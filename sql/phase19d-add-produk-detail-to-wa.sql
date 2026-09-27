-- ═══════════════════════════════════════════════════════════════
-- Phase 19D — Tambah Detail Produk di WA Reminder ke Customer
--
-- User feedback: customer bisa lupa isi order-nya apa kalo cuma dikirim
-- no faktur. Tambahin `orders.produk` di 3 function customer-facing:
--   1. notify_customer_new_invoice (invoice baru)
--   2. send_overdue_reminders (cron reminder)
--   3. send_reminder_for_invoice (manual button)
--
-- Format pesan: Detail order muncul di bawah info invoice, sebelum
-- instruksi transfer.
-- ═══════════════════════════════════════════════════════════════

-- ─── 1) notify_customer_new_invoice ────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_customer_new_invoice()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  fonnte_token TEXT; fonnte_enabled TEXT; cust_wa TEXT;
  order_row RECORD; msg TEXT; produk_section TEXT; nl TEXT := chr(10);
BEGIN
  BEGIN
    SELECT value INTO fonnte_enabled FROM public.config WHERE key='fonnte_enabled';
    IF fonnte_enabled IS NULL OR fonnte_enabled <> 'true' THEN RETURN NEW; END IF;
    SELECT value INTO fonnte_token FROM public.config WHERE key='fonnte_token';
    IF fonnte_token IS NULL OR fonnte_token = '' THEN RETURN NEW; END IF;
    IF NEW.order_id IS NULL THEN RETURN NEW; END IF;
    SELECT * INTO order_row FROM public.orders WHERE id = NEW.order_id;
    IF NOT FOUND THEN RETURN NEW; END IF;
    IF order_row.pembayaran <> 'Termin 30 Hari' THEN RETURN NEW; END IF;
    SELECT wa INTO cust_wa FROM public.customers WHERE id = order_row.customer_id;
    IF cust_wa IS NULL OR cust_wa = '' THEN RETURN NEW; END IF;

    -- Build produk section
    IF order_row.produk IS NOT NULL AND order_row.produk <> '' THEN
      produk_section := nl || '*Detail Order:*' || nl || order_row.produk || nl;
    ELSE
      produk_section := '';
    END IF;

    msg := '*Findest Sport - Invoice Baru*' || nl || nl ||
           'Halo ' || COALESCE(NEW.customer_nama,'Pelanggan') || ',' || nl || nl ||
           'Order kamu sudah masuk sistem:' || nl ||
           '*No Faktur: ' || NEW.no_invoice || '*' || nl ||
           'Total: Rp ' || to_char(NEW.total, 'FM999G999G999G990') || nl ||
           'Jatuh Tempo: ' || to_char(NEW.jatuh_tempo, 'DD Mon YYYY') || nl ||
           produk_section || nl ||
           'Mohon *simpan No Faktur ini* — dipakai saat kirim bukti transfer nanti.' || nl || nl ||
           'Terima kasih!';

    PERFORM net.http_post(
      url := 'https://api.fonnte.com/send',
      headers := jsonb_build_object('Authorization', fonnte_token, 'Content-Type', 'application/json'),
      body := jsonb_build_object('target', cust_wa, 'message', msg, 'countryCode', '62')
    );
    UPDATE public.invoices SET notified_customer = true WHERE id = NEW.id;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Notify customer failed: %', SQLERRM; END;
  RETURN NEW;
END $$;

-- ─── 2) send_overdue_reminders ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_overdue_reminders()
RETURNS TABLE(invoice_id BIGINT, no_invoice TEXT, tier INT, sent_to_customer BOOLEAN, sent_to_admin BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  inv RECORD; fonnte_token TEXT; fonnte_enabled TEXT; admin_wa TEXT;
  msg TEXT; admin_msg TEXT; produk_section TEXT;
  days_overdue INT; target_tier INT;
  sent_cust BOOLEAN; sent_adm BOOLEAN; nl TEXT := chr(10);
BEGIN
  SELECT value INTO fonnte_enabled FROM public.config WHERE key='fonnte_enabled';
  IF fonnte_enabled IS NULL OR fonnte_enabled <> 'true' THEN RETURN; END IF;
  SELECT value INTO fonnte_token FROM public.config WHERE key='fonnte_token';
  SELECT value INTO admin_wa FROM public.config WHERE key='fonnte_admin_wa';
  IF fonnte_token IS NULL OR fonnte_token = '' THEN RETURN; END IF;

  FOR inv IN
    SELECT i.id, i.no_invoice, i.customer_nama, i.total, i.jatuh_tempo,
           i.last_reminder_tier, i.last_reminder_sent,
           o.customer_id, o.produk AS order_produk, c.wa AS cust_wa
    FROM public.invoices i
    LEFT JOIN public.orders o ON o.id = i.order_id
    LEFT JOIN public.customers c ON c.id = o.customer_id
    WHERE i.status NOT IN ('Lunas','Batal','Dibatalkan')
      AND i.jatuh_tempo IS NOT NULL AND i.jatuh_tempo < CURRENT_DATE
  LOOP
    days_overdue := (CURRENT_DATE - inv.jatuh_tempo)::INT;
    IF days_overdue >= 14 THEN target_tier := 3;
    ELSIF days_overdue >= 7 THEN target_tier := 2;
    ELSIF days_overdue >= 1 THEN target_tier := 1;
    ELSE CONTINUE; END IF;

    IF COALESCE(inv.last_reminder_tier, 0) >= target_tier THEN CONTINUE; END IF;
    IF inv.last_reminder_sent = CURRENT_DATE THEN CONTINUE; END IF;

    sent_cust := false; sent_adm := false;

    -- Build produk section
    IF inv.order_produk IS NOT NULL AND inv.order_produk <> '' THEN
      produk_section := nl || '*Detail Order:*' || nl || inv.order_produk || nl;
    ELSE
      produk_section := '';
    END IF;

    IF target_tier = 1 THEN
      msg := '*Findest Sport - Reminder Pembayaran*' || nl || nl ||
             'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
             'Invoice berikut lewat jatuh tempo *' || days_overdue || ' hari*:' || nl ||
             '*No Faktur: ' || inv.no_invoice || '*' || nl ||
             'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
             'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl ||
             produk_section || nl ||
             'Mohon konfirmasi ya. *Cantumkan No Faktur ' || inv.no_invoice || '* saat kirim bukti transfer.';
    ELSIF target_tier = 2 THEN
      msg := '*Findest Sport - Follow Up Pembayaran*' || nl || nl ||
             'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
             'Invoice sudah lewat *' || days_overdue || ' hari*:' || nl ||
             '*No Faktur: ' || inv.no_invoice || '*' || nl ||
             'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
             'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl ||
             produk_section || nl ||
             'Mohon segera diselesaikan. *Cantumkan No Faktur ' || inv.no_invoice || '* saat kirim bukti transfer.';
    ELSE
      msg := '*Findest Sport - WARNING Pembayaran*' || nl || nl ||
             'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
             'Invoice sudah lewat *' || days_overdue || ' hari*:' || nl ||
             '*No Faktur: ' || inv.no_invoice || '*' || nl ||
             'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
             'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl ||
             produk_section || nl ||
             'Team kami akan follow-up langsung. *Cantumkan No Faktur ' || inv.no_invoice || '* saat kirim bukti transfer.';
    END IF;

    IF inv.cust_wa IS NOT NULL AND inv.cust_wa <> '' THEN
      BEGIN
        PERFORM net.http_post(url := 'https://api.fonnte.com/send',
          headers := jsonb_build_object('Authorization', fonnte_token, 'Content-Type', 'application/json'),
          body := jsonb_build_object('target', inv.cust_wa, 'message', msg, 'countryCode', '62'));
        sent_cust := true;
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Send customer failed %: %', inv.no_invoice, SQLERRM; END;
    END IF;

    IF target_tier >= 2 AND admin_wa IS NOT NULL AND admin_wa <> '' THEN
      admin_msg := '[CC Reminder T' || target_tier || '] ' || inv.no_invoice || nl ||
                   'Customer: ' || COALESCE(inv.customer_nama,'-') || nl ||
                   'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
                   'Overdue: ' || days_overdue || ' hari';
      BEGIN
        PERFORM net.http_post(url := 'https://api.fonnte.com/send',
          headers := jsonb_build_object('Authorization', fonnte_token, 'Content-Type', 'application/json'),
          body := jsonb_build_object('target', admin_wa, 'message', admin_msg, 'countryCode', '62'));
        sent_adm := true;
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Send admin CC failed: %', SQLERRM; END;
    END IF;

    IF sent_cust OR sent_adm THEN
      UPDATE public.invoices SET last_reminder_sent = CURRENT_DATE, last_reminder_tier = target_tier WHERE id = inv.id;
      RETURN QUERY SELECT inv.id, inv.no_invoice, target_tier, sent_cust, sent_adm;
    END IF;
  END LOOP;
END $$;

-- ─── 3) send_reminder_for_invoice ──────────────────────────────
CREATE OR REPLACE FUNCTION public.send_reminder_for_invoice(p_invoice_id BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  inv RECORD; fonnte_token TEXT; fonnte_enabled TEXT; admin_wa TEXT;
  msg TEXT; admin_msg TEXT; produk_section TEXT;
  days_overdue INT; target_tier INT;
  sent_cust BOOLEAN := false; sent_adm BOOLEAN := false; err_text TEXT := NULL;
  nl TEXT := chr(10);
BEGIN
  SELECT i.id, i.no_invoice, i.customer_nama, i.total, i.jatuh_tempo, i.status,
         o.customer_id, o.produk AS order_produk, c.wa AS cust_wa
  INTO inv
  FROM public.invoices i
  LEFT JOIN public.orders o ON o.id = i.order_id
  LEFT JOIN public.customers c ON c.id = o.customer_id
  WHERE i.id = p_invoice_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'Invoice tidak ditemukan'); END IF;
  IF inv.status = 'Lunas' THEN RETURN jsonb_build_object('ok', false, 'error', 'Invoice sudah Lunas'); END IF;

  SELECT value INTO fonnte_enabled FROM public.config WHERE key='fonnte_enabled';
  IF fonnte_enabled IS NULL OR fonnte_enabled <> 'true' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Fonnte belum di-enable'); END IF;
  SELECT value INTO fonnte_token FROM public.config WHERE key='fonnte_token';
  SELECT value INTO admin_wa FROM public.config WHERE key='fonnte_admin_wa';
  IF fonnte_token IS NULL OR fonnte_token = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Fonnte token belum di-set'); END IF;
  IF inv.cust_wa IS NULL OR inv.cust_wa = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Customer "' || inv.customer_nama || '" belum punya nomor WA'); END IF;

  days_overdue := GREATEST((CURRENT_DATE - inv.jatuh_tempo)::INT, 1);
  IF days_overdue >= 14 THEN target_tier := 3;
  ELSIF days_overdue >= 7 THEN target_tier := 2;
  ELSE target_tier := 1; END IF;

  -- Build produk section
  IF inv.order_produk IS NOT NULL AND inv.order_produk <> '' THEN
    produk_section := nl || '*Detail Order:*' || nl || inv.order_produk || nl;
  ELSE
    produk_section := '';
  END IF;

  IF target_tier = 1 THEN
    msg := '*Findest Sport - Reminder Pembayaran*' || nl || nl ||
           'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
           'Invoice berikut lewat jatuh tempo *' || days_overdue || ' hari*:' || nl ||
           '*No Faktur: ' || inv.no_invoice || '*' || nl ||
           'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
           'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl ||
           produk_section || nl ||
           'Mohon konfirmasi ya. *Cantumkan No Faktur ' || inv.no_invoice || '* saat kirim bukti transfer.';
  ELSIF target_tier = 2 THEN
    msg := '*Findest Sport - Follow Up Pembayaran*' || nl || nl ||
           'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
           'Invoice sudah lewat *' || days_overdue || ' hari*:' || nl ||
           '*No Faktur: ' || inv.no_invoice || '*' || nl ||
           'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
           'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl ||
           produk_section || nl ||
           'Mohon segera diselesaikan. *Cantumkan No Faktur ' || inv.no_invoice || '* saat kirim bukti transfer.';
  ELSE
    msg := '*Findest Sport - WARNING Pembayaran*' || nl || nl ||
           'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
           'Invoice sudah lewat *' || days_overdue || ' hari*:' || nl ||
           '*No Faktur: ' || inv.no_invoice || '*' || nl ||
           'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
           'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl ||
           produk_section || nl ||
           'Team kami akan follow-up langsung. *Cantumkan No Faktur ' || inv.no_invoice || '* saat kirim bukti transfer.';
  END IF;

  BEGIN
    PERFORM net.http_post(url := 'https://api.fonnte.com/send',
      headers := jsonb_build_object('Authorization', fonnte_token, 'Content-Type', 'application/json'),
      body := jsonb_build_object('target', inv.cust_wa, 'message', msg, 'countryCode', '62'));
    sent_cust := true;
  EXCEPTION WHEN OTHERS THEN err_text := SQLERRM; END;

  IF sent_cust AND target_tier >= 2 AND admin_wa IS NOT NULL AND admin_wa <> '' THEN
    admin_msg := '[Manual Reminder T' || target_tier || '] ' || inv.no_invoice || nl ||
                 'Customer: ' || COALESCE(inv.customer_nama,'-') || nl ||
                 'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
                 'Overdue: ' || days_overdue || ' hari (manual)';
    BEGIN
      PERFORM net.http_post(url := 'https://api.fonnte.com/send',
        headers := jsonb_build_object('Authorization', fonnte_token, 'Content-Type', 'application/json'),
        body := jsonb_build_object('target', admin_wa, 'message', admin_msg, 'countryCode', '62'));
      sent_adm := true;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  IF sent_cust THEN
    UPDATE public.invoices
    SET last_reminder_sent = CURRENT_DATE,
        last_reminder_tier = GREATEST(COALESCE(last_reminder_tier,0), target_tier)
    WHERE id = inv.id;
  END IF;

  RETURN jsonb_build_object(
    'ok', sent_cust, 'invoice_id', inv.id, 'no_invoice', inv.no_invoice,
    'customer', inv.customer_nama, 'wa_target', inv.cust_wa,
    'tier', target_tier, 'days_overdue', days_overdue,
    'sent_to_customer', sent_cust, 'sent_to_admin', sent_adm, 'error', err_text
  );
END $$;

-- ─── Verify: cek 3 function udah punya *Detail Order:* di body ────
SELECT 'notify_customer_new_invoice' AS fn,
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%Detail Order:%' THEN '✅' ELSE '❌' END AS has_produk
FROM pg_proc p WHERE proname = 'notify_customer_new_invoice'
UNION ALL
SELECT 'send_overdue_reminders',
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%Detail Order:%' THEN '✅' ELSE '❌' END
FROM pg_proc p WHERE proname = 'send_overdue_reminders'
UNION ALL
SELECT 'send_reminder_for_invoice',
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%Detail Order:%' THEN '✅' ELSE '❌' END
FROM pg_proc p WHERE proname = 'send_reminder_for_invoice';
