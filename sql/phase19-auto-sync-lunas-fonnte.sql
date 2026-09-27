-- ═══════════════════════════════════════════════════════════════
-- Phase 19 — Auto-Sync Invoice Lunas ↔ Payment + Fonnte Reminder
--
-- GOAL: 1 aksi Nadya = semua sync
--   1. Klik ✅Lunas di invoice → auto-insert payment record → Rekap Kas balance
--   2. Order Termin baru → auto-WA customer dgn no_invoice (biar bisa dicantumin
--      saat konfirmasi bayar nanti)
--   3. Invoice overdue → auto-reminder H+1 / H+7 / H+14 via Fonnte (anti-spam)
--
-- CATATAN: sebelum run file ini, pastikan pg_cron extension enabled di
--          Supabase Dashboard → Database → Extensions → cari "pg_cron" → Enable.
--          Kalo ga di-enable, seluruh file tetap jalan tapi bagian pg_cron di
--          skip (reminder harus di-trigger manual pake SELECT).
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1) Tambah kolom tracking di invoices (idempotent)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS last_reminder_sent DATE,
  ADD COLUMN IF NOT EXISTS last_reminder_tier INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS notified_customer BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.invoices.last_reminder_sent IS 'Tanggal reminder Fonnte terakhir dikirim';
COMMENT ON COLUMN public.invoices.last_reminder_tier IS 'Tier terakhir: 0=belum, 1=H+1, 2=H+7, 3=H+14';
COMMENT ON COLUMN public.invoices.notified_customer IS 'Apakah customer udah dinotify pas invoice dibuat';

-- Tambah kolom audit di payments (biar tau payment auto atau manual)
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS auto_from_invoice BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.payments.auto_from_invoice IS 'true kalo payment ini auto-create dari trigger invoice Lunas';

-- ─────────────────────────────────────────────────────────────
-- 2) Trigger: Invoice status → 'Lunas', auto-insert Payment
--    (biar Rekap Kas Masuk sync tanpa Nadya perlu double-input)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.invoice_lunas_auto_payment()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  payment_exists BOOLEAN;
BEGIN
  -- Hanya proses saat status berubah JADI 'Lunas' (dari yg bukan Lunas)
  IF NEW.status <> 'Lunas' THEN RETURN NEW; END IF;
  IF OLD.status = 'Lunas' THEN RETURN NEW; END IF;

  -- Cek udah ada payment untuk invoice ini blm (anti-dup)
  SELECT EXISTS(
    SELECT 1 FROM public.payments WHERE invoice_id = NEW.id
  ) INTO payment_exists;

  IF payment_exists THEN RETURN NEW; END IF;

  -- Auto-insert payment record
  BEGIN
    INSERT INTO public.payments(
      tanggal_bayar, customer_nama, jumlah, metode, keterangan,
      invoice_id, auto_from_invoice
    ) VALUES (
      COALESCE(NEW.tgl_lunas, CURRENT_DATE),
      NEW.customer_nama,
      NEW.total,
      'Transfer',
      'Auto dari invoice ' || NEW.no_invoice || ' (klik ✅Lunas)',
      NEW.id,
      true
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Auto-payment failed for invoice %: %', NEW.no_invoice, SQLERRM;
  END;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_invoice_lunas_auto_payment ON public.invoices;
CREATE TRIGGER trg_invoice_lunas_auto_payment
  AFTER UPDATE OF status ON public.invoices
  FOR EACH ROW
  WHEN (NEW.status = 'Lunas' AND (OLD.status IS NULL OR OLD.status <> 'Lunas'))
  EXECUTE FUNCTION public.invoice_lunas_auto_payment();

-- ─────────────────────────────────────────────────────────────
-- 3) Trigger: Invoice baru dibuat → Fonnte WA ke Customer
--    Kirim NO_INVOICE ke customer biar bisa dicantumin saat konfirmasi bayar
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_customer_new_invoice()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  fonnte_token TEXT;
  fonnte_enabled TEXT;
  cust_wa TEXT;
  order_row RECORD;
  msg TEXT;
  nl TEXT := chr(10);
BEGIN
  -- Wrap semua logic Fonnte biar kalo error ga block INSERT invoice
  BEGIN
    -- Cek config
    SELECT value INTO fonnte_enabled FROM public.config WHERE key='fonnte_enabled';
    IF fonnte_enabled IS NULL OR fonnte_enabled <> 'true' THEN RETURN NEW; END IF;

    SELECT value INTO fonnte_token FROM public.config WHERE key='fonnte_token';
    IF fonnte_token IS NULL OR fonnte_token = '' THEN RETURN NEW; END IF;

    -- Ambil order utk cek Termin & customer_id
    IF NEW.order_id IS NULL THEN RETURN NEW; END IF;
    SELECT * INTO order_row FROM public.orders WHERE id = NEW.order_id;
    IF NOT FOUND THEN RETURN NEW; END IF;

    -- Hanya notify utk order Termin (yg Tunai ga perlu diingetin)
    IF order_row.pembayaran <> 'Termin 30 Hari' THEN RETURN NEW; END IF;

    -- Ambil WA customer
    SELECT wa INTO cust_wa FROM public.customers WHERE id = order_row.customer_id;
    IF cust_wa IS NULL OR cust_wa = '' THEN RETURN NEW; END IF;

    -- Build message
    msg := '*Findest Sport - Invoice Baru*' || nl || nl ||
           'Halo ' || COALESCE(NEW.customer_nama,'Pelanggan') || ',' || nl || nl ||
           'Order kamu sudah masuk sistem kami:' || nl ||
           '*No Faktur: ' || NEW.no_invoice || '*' || nl ||
           'Total: Rp ' || to_char(NEW.total, 'FM999G999G999G990') || nl ||
           'Jatuh Tempo: ' || to_char(NEW.jatuh_tempo, 'DD Mon YYYY') || nl || nl ||
           'Mohon *simpan No Faktur ini* — dipakai saat kirim bukti transfer nanti.' || nl || nl ||
           'Terima kasih!';

    PERFORM net.http_post(
      url := 'https://api.fonnte.com/send',
      headers := jsonb_build_object(
        'Authorization', fonnte_token,
        'Content-Type', 'application/x-www-form-urlencoded'
      ),
      body := jsonb_build_object(
        'target', cust_wa,
        'message', msg,
        'countryCode', '62'
      )
    );

    -- Tandai notified
    UPDATE public.invoices SET notified_customer = true WHERE id = NEW.id;

  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Notify customer new invoice failed: %', SQLERRM;
  END;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_invoices_notify_customer ON public.invoices;
CREATE TRIGGER trg_invoices_notify_customer
  AFTER INSERT ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.notify_customer_new_invoice();

-- ─────────────────────────────────────────────────────────────
-- 4) Function: Daily scan overdue invoices → send Fonnte reminder
--    Tier 1 (H+1): reminder halus ke customer
--    Tier 2 (H+7): follow-up ke customer + CC ke Fazar
--    Tier 3 (H+14): warning ke customer + CC ke Fazar
--    Anti-spam: tiap invoice max 1 kali per tier
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_overdue_reminders()
RETURNS TABLE(invoice_id BIGINT, no_invoice TEXT, tier INT, sent_to_customer BOOLEAN, sent_to_admin BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  inv RECORD;
  fonnte_token TEXT;
  fonnte_enabled TEXT;
  admin_wa TEXT;
  msg TEXT;
  admin_msg TEXT;
  days_overdue INT;
  target_tier INT;
  sent_cust BOOLEAN;
  sent_adm BOOLEAN;
  nl TEXT := chr(10);
BEGIN
  -- Cek config Fonnte
  SELECT value INTO fonnte_enabled FROM public.config WHERE key='fonnte_enabled';
  IF fonnte_enabled IS NULL OR fonnte_enabled <> 'true' THEN
    RAISE NOTICE 'Fonnte disabled, skipping reminders';
    RETURN;
  END IF;

  SELECT value INTO fonnte_token FROM public.config WHERE key='fonnte_token';
  SELECT value INTO admin_wa FROM public.config WHERE key='fonnte_admin_wa';
  IF fonnte_token IS NULL OR fonnte_token = '' THEN
    RAISE NOTICE 'Fonnte token not set, skipping reminders';
    RETURN;
  END IF;

  -- Loop invoice overdue
  FOR inv IN
    SELECT i.id, i.no_invoice, i.customer_nama, i.total, i.jatuh_tempo,
           i.last_reminder_tier, i.last_reminder_sent,
           o.customer_id, c.wa AS cust_wa
    FROM public.invoices i
    LEFT JOIN public.orders o ON o.id = i.order_id
    LEFT JOIN public.customers c ON c.id = o.customer_id
    WHERE i.status NOT IN ('Lunas','Batal','Dibatalkan')
      AND i.jatuh_tempo IS NOT NULL
      AND i.jatuh_tempo < CURRENT_DATE
  LOOP
    days_overdue := (CURRENT_DATE - inv.jatuh_tempo)::INT;

    -- Determine tier
    IF days_overdue >= 14 THEN target_tier := 3;
    ELSIF days_overdue >= 7 THEN target_tier := 2;
    ELSIF days_overdue >= 1 THEN target_tier := 1;
    ELSE CONTINUE;
    END IF;

    -- Anti-spam: skip kalo tier ini udah pernah dikirim
    IF COALESCE(inv.last_reminder_tier, 0) >= target_tier THEN CONTINUE; END IF;

    -- Anti-spam extra: skip kalo hari ini udah kirim reminder untuk invoice ini
    IF inv.last_reminder_sent = CURRENT_DATE THEN CONTINUE; END IF;

    sent_cust := false;
    sent_adm := false;

    -- Build message per tier
    IF target_tier = 1 THEN
      msg := '*Findest Sport - Reminder Pembayaran*' || nl || nl ||
             'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
             'Invoice berikut lewat jatuh tempo *' || days_overdue || ' hari*:' || nl ||
             '*No Faktur: ' || inv.no_invoice || '*' || nl ||
             'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
             'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl || nl ||
             'Mohon konfirmasi pembayaran ya. *Cantumkan No Faktur ' || inv.no_invoice ||
             '* saat kirim bukti transfer.' || nl || nl || 'Terima kasih.';
    ELSIF target_tier = 2 THEN
      msg := '*Findest Sport - Follow Up Pembayaran*' || nl || nl ||
             'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
             'Invoice ini sudah lewat *' || days_overdue || ' hari* dari jatuh tempo:' || nl ||
             '*No Faktur: ' || inv.no_invoice || '*' || nl ||
             'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
             'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl || nl ||
             'Mohon segera diselesaikan. Kalau ada kendala, silakan hubungi kami.' || nl || nl ||
             '*Cantumkan No Faktur ' || inv.no_invoice || '* saat kirim bukti transfer.';
    ELSE
      msg := '*Findest Sport - WARNING Pembayaran*' || nl || nl ||
             'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
             'Invoice ini sudah lewat *' || days_overdue || ' hari* dari jatuh tempo:' || nl ||
             '*No Faktur: ' || inv.no_invoice || '*' || nl ||
             'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
             'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl || nl ||
             'Mohon segera diselesaikan. Team kami akan follow-up langsung untuk kelanjutannya.' || nl || nl ||
             '*Cantumkan No Faktur ' || inv.no_invoice || '* saat kirim bukti transfer.';
    END IF;

    -- Send ke customer
    IF inv.cust_wa IS NOT NULL AND inv.cust_wa <> '' THEN
      BEGIN
        PERFORM net.http_post(
          url := 'https://api.fonnte.com/send',
          headers := jsonb_build_object(
            'Authorization', fonnte_token,
            'Content-Type', 'application/x-www-form-urlencoded'
          ),
          body := jsonb_build_object(
            'target', inv.cust_wa, 'message', msg, 'countryCode', '62'
          )
        );
        sent_cust := true;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Send customer failed INV %: %', inv.no_invoice, SQLERRM;
      END;
    END IF;

    -- CC ke admin (Fazar) mulai tier 2 (biar ga spam Fazar tiap hari)
    IF target_tier >= 2 AND admin_wa IS NOT NULL AND admin_wa <> '' THEN
      admin_msg := '[CC Reminder T' || target_tier || '] ' || inv.no_invoice || nl ||
                   'Customer: ' || COALESCE(inv.customer_nama,'-') || nl ||
                   'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
                   'Overdue: ' || days_overdue || ' hari';
      BEGIN
        PERFORM net.http_post(
          url := 'https://api.fonnte.com/send',
          headers := jsonb_build_object(
            'Authorization', fonnte_token,
            'Content-Type', 'application/x-www-form-urlencoded'
          ),
          body := jsonb_build_object(
            'target', admin_wa, 'message', admin_msg, 'countryCode', '62'
          )
        );
        sent_adm := true;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Send admin CC failed INV %: %', inv.no_invoice, SQLERRM;
      END;
    END IF;

    -- Update tracking (hanya kalo minimal 1 pesan kekirim)
    IF sent_cust OR sent_adm THEN
      UPDATE public.invoices
      SET last_reminder_sent = CURRENT_DATE,
          last_reminder_tier = target_tier
      WHERE id = inv.id;

      RETURN QUERY SELECT inv.id, inv.no_invoice, target_tier, sent_cust, sent_adm;
    END IF;
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 5) Schedule pg_cron: run daily jam 09:00 WIB (02:00 UTC)
--    Skip kalo pg_cron ga di-enable
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Unschedule dulu kalo udah ada (idempotent)
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'findest-daily-overdue-reminders') THEN
      PERFORM cron.unschedule('findest-daily-overdue-reminders');
    END IF;

    PERFORM cron.schedule(
      'findest-daily-overdue-reminders',
      '0 2 * * *',
      'SELECT public.send_overdue_reminders();'
    );

    RAISE NOTICE 'pg_cron scheduled: findest-daily-overdue-reminders @ 02:00 UTC (09:00 WIB)';
  ELSE
    RAISE NOTICE 'pg_cron TIDAK ter-install. Enable di Supabase Dashboard > Database > Extensions > pg_cron, terus re-run file ini. Sementara, panggil manual: SELECT public.send_overdue_reminders();';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 6) VERIFY — Cek semua object udah kebuat
-- ─────────────────────────────────────────────────────────────
SELECT 'invoices.last_reminder_sent' AS check_item,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='invoices'
                AND column_name='last_reminder_sent') THEN '✅' ELSE '❌' END AS status
UNION ALL
SELECT 'invoices.last_reminder_tier',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='invoices'
                AND column_name='last_reminder_tier') THEN '✅' ELSE '❌' END
UNION ALL
SELECT 'payments.auto_from_invoice',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='payments'
                AND column_name='auto_from_invoice') THEN '✅' ELSE '❌' END
UNION ALL
SELECT 'trg_invoice_lunas_auto_payment',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.triggers
              WHERE trigger_name='trg_invoice_lunas_auto_payment') THEN '✅' ELSE '❌' END
UNION ALL
SELECT 'trg_invoices_notify_customer',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.triggers
              WHERE trigger_name='trg_invoices_notify_customer') THEN '✅' ELSE '❌' END
UNION ALL
SELECT 'fn.send_overdue_reminders()',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc
              WHERE proname='send_overdue_reminders') THEN '✅' ELSE '❌' END
UNION ALL
SELECT 'pg_cron schedule',
       CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
            AND EXISTS (SELECT 1 FROM cron.job WHERE jobname='findest-daily-overdue-reminders')
            THEN '✅ scheduled 09:00 WIB'
            WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
            THEN '⚠️ pg_cron ada tapi job blm ter-schedule'
            ELSE '⚠️ pg_cron blm enabled — reminder harus manual' END;

-- ─────────────────────────────────────────────────────────────
-- 7) TEST MANUAL (opsional, biar tau function jalan)
-- Uncomment untuk test:
-- SELECT * FROM public.send_overdue_reminders();
-- ─────────────────────────────────────────────────────────────
