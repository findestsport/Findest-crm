-- ═══════════════════════════════════════════════════════════════
-- Phase 21 — Konsi Rekap Bulanan (Monthly Reconciliation Workflow)
--
-- Reality: konsi outlet direkap TIAP BULAN (tanggal 25), bukan real-time.
-- Sales visit outlet ambil data terjual + retur, input batch, auto invoice.
-- Sisa titipan CARRY OVER ke bulan depan (row tetep Aktif).
--
-- Flow:
--  Tgl 22 (H-3) → 📱 Fonnte remind sales: "Waktunya visit outlet konsi"
--  Tgl 23 (H-2) → 📱 Fonnte remind outlet: "Siapkan rekap penjualan"
--  Tgl 25       → Sales input Batch Rekon Form (1 modal, all outlet)
--                 → Auto-generate invoice ke outlet (termin 30 hari)
--                 → Update konsinyasi.qty_terjual += rekap.qty_terjual_bulan
--                 → Konsi row TETEP Aktif (carry over)
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────
-- 1. TABLE konsi_rekap_bulanan
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.konsi_rekap_bulanan (
  id BIGSERIAL PRIMARY KEY,
  konsi_id BIGINT REFERENCES public.konsinyasi(id) ON DELETE SET NULL,
  outlet TEXT NOT NULL,
  produk TEXT NOT NULL,
  bulan DATE NOT NULL, -- '2026-09-01' represent month
  qty_terjual_bulan INTEGER DEFAULT 0,
  qty_retur_bulan INTEGER DEFAULT 0,
  harga NUMERIC DEFAULT 0,
  nilai_terjual NUMERIC DEFAULT 0,
  invoice_id BIGINT REFERENCES public.invoices(id) ON DELETE SET NULL,
  tgl_rekon DATE DEFAULT CURRENT_DATE,
  catatan TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by TEXT
);

-- 1 rekap per konsi row per bulan
CREATE UNIQUE INDEX IF NOT EXISTS uniq_rekap_konsi_bulan
  ON public.konsi_rekap_bulanan(konsi_id, bulan);
CREATE INDEX IF NOT EXISTS idx_rekap_outlet_bulan
  ON public.konsi_rekap_bulanan(outlet, bulan);
CREATE INDEX IF NOT EXISTS idx_rekap_bulan
  ON public.konsi_rekap_bulanan(bulan);

-- Enable RLS
ALTER TABLE public.konsi_rekap_bulanan ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "konsi_rekap_all_authenticated" ON public.konsi_rekap_bulanan;
CREATE POLICY "konsi_rekap_all_authenticated" ON public.konsi_rekap_bulanan
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- ─────────────────────────────────────────────────────────
-- 2. TRIGGER: setelah insert rekap → update konsinyasi + auto invoice
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.konsi_rekap_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_no_invoice TEXT;
  new_inv_id BIGINT;
  today DATE := CURRENT_DATE;
BEGIN
  -- 1) Update konsinyasi row: tambah qty_terjual + qty_retur cumulative
  IF NEW.konsi_id IS NOT NULL THEN
    UPDATE public.konsinyasi
    SET qty_terjual = COALESCE(qty_terjual,0) + COALESCE(NEW.qty_terjual_bulan,0),
        qty_retur   = COALESCE(qty_retur,0)   + COALESCE(NEW.qty_retur_bulan,0),
        tgl_rekon   = NEW.tgl_rekon
    WHERE id = NEW.konsi_id;
  END IF;

  -- 2) Auto-create invoice ke outlet konsi (kalo ada nilai_terjual)
  IF COALESCE(NEW.nilai_terjual,0) > 0 AND NEW.invoice_id IS NULL THEN
    new_no_invoice := 'INV-KONSI-' || to_char(NEW.bulan,'YYMM') || '-' || NEW.id::text;

    INSERT INTO public.invoices(
      no_invoice, customer_nama, customer_tipe, customer_sistem,
      tgl_invoice, jatuh_tempo, total, status
    ) VALUES (
      new_no_invoice,
      NEW.outlet,
      'Konsinyasi Rekap',
      'Konsinyasi Rekap Bulanan', -- BEDA dari 'Konsinyasi (Titipan)' — ini invoice real
      today,
      today + INTERVAL '30 days',
      NEW.nilai_terjual,
      'Pending'
    )
    RETURNING id INTO new_inv_id;

    -- Link invoice_id back ke rekap row
    UPDATE public.konsi_rekap_bulanan SET invoice_id = new_inv_id WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_konsi_rekap_after_insert ON public.konsi_rekap_bulanan;
CREATE TRIGGER trg_konsi_rekap_after_insert
  AFTER INSERT ON public.konsi_rekap_bulanan
  FOR EACH ROW
  EXECUTE FUNCTION public.konsi_rekap_after_insert();

-- Reverse trigger: kalo rekap di-delete (edit ulang), revert konsinyasi cumulative
CREATE OR REPLACE FUNCTION public.konsi_rekap_after_delete()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF OLD.konsi_id IS NOT NULL THEN
    UPDATE public.konsinyasi
    SET qty_terjual = GREATEST(0, COALESCE(qty_terjual,0) - COALESCE(OLD.qty_terjual_bulan,0)),
        qty_retur   = GREATEST(0, COALESCE(qty_retur,0)   - COALESCE(OLD.qty_retur_bulan,0))
    WHERE id = OLD.konsi_id;
  END IF;
  -- Cancel linked invoice
  IF OLD.invoice_id IS NOT NULL THEN
    UPDATE public.invoices SET status='Batal' WHERE id = OLD.invoice_id AND status NOT IN ('Batal','Dibatalkan');
  END IF;
  RETURN OLD;
END $$;

DROP TRIGGER IF EXISTS trg_konsi_rekap_after_delete ON public.konsi_rekap_bulanan;
CREATE TRIGGER trg_konsi_rekap_after_delete
  AFTER DELETE ON public.konsi_rekap_bulanan
  FOR EACH ROW
  EXECUTE FUNCTION public.konsi_rekap_after_delete();

-- ─────────────────────────────────────────────────────────
-- 3. UPDATE orders_auto_invoice — Rekap invoice bukan titipan, JANGAN skip
-- ─────────────────────────────────────────────────────────
-- (already handled: Phase 20 skip ILIKE '%konsinyasi%'. Rekap invoice pake
--  customer_sistem 'Konsinyasi Rekap Bulanan' — dashboard perlu filter khusus:
--  invoice 'Konsinyasi Rekap Bulanan' = OMZET REAL, 'Konsinyasi (Titipan)' = inventory)

-- ─────────────────────────────────────────────────────────
-- 4. FONNTE REMINDER: send_konsi_rekap_reminder()
-- ─────────────────────────────────────────────────────────
-- Kirim ke sales (H-3) + outlet konsi (H-2)
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_konsi_rekap_reminder(p_target TEXT DEFAULT 'sales')
RETURNS TABLE(target_type TEXT, target_nama TEXT, wa TEXT, sent BOOLEAN, err TEXT)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  fonnte_token TEXT;
  fonnte_enabled TEXT;
  admin_wa TEXT;
  msg TEXT;
  nl TEXT := chr(10);
  rec RECORD;
  sent_ok BOOLEAN;
  err_msg TEXT;
BEGIN
  SELECT value INTO fonnte_enabled FROM public.config WHERE key='fonnte_enabled';
  IF fonnte_enabled IS NULL OR fonnte_enabled <> 'true' THEN
    RAISE NOTICE 'Fonnte disabled'; RETURN;
  END IF;

  SELECT value INTO fonnte_token FROM public.config WHERE key='fonnte_token';
  IF fonnte_token IS NULL OR fonnte_token = '' THEN RETURN; END IF;

  IF p_target = 'sales' THEN
    -- H-3 REMINDER ke SALES tim
    msg := '📅 *Reminder Rekap Konsi Bulan Ini*' || nl || nl ||
           'Halo tim Sales!' || nl || nl ||
           'H-3 sebelum akhir bulan. Waktunya visit outlet konsi buat ambil rekap penjualan:' || nl ||
           '• Cek qty terjual per produk' || nl ||
           '• Foto stok fisik yg tersisa' || nl ||
           '• Konfirmasi retur (kalo ada)' || nl || nl ||
           'Input hasil rekap di CRM → Konsinyasi tab → "🧾 Rekap Bulanan"' || nl || nl ||
           'Deadline: tanggal 25' || nl ||
           '_Auto-invoice ke outlet akan generate setelah lu save._';

    -- Loop semua karyawan divisi Sales yg punya WA
    FOR rec IN
      SELECT nama, no_wa FROM public.employees
      WHERE status='Aktif' AND (divisi ILIKE '%sales%' OR jabatan ILIKE '%sales%')
        AND no_wa IS NOT NULL AND no_wa <> ''
    LOOP
      sent_ok := FALSE; err_msg := NULL;
      BEGIN
        PERFORM net.http_post(
          url := 'https://api.fonnte.com/send',
          headers := jsonb_build_object('Authorization', fonnte_token, 'Content-Type', 'application/json'),
          body := jsonb_build_object('target', rec.no_wa, 'message', msg)
        );
        sent_ok := TRUE;
      EXCEPTION WHEN OTHERS THEN err_msg := SQLERRM;
      END;
      target_type := 'sales'; target_nama := rec.nama; wa := rec.no_wa; sent := sent_ok; err := err_msg;
      RETURN NEXT;
    END LOOP;

  ELSIF p_target = 'outlet' THEN
    -- H-2 REMINDER ke OUTLET konsi
    -- Loop semua customer Konsi yg punya konsi_row Aktif
    FOR rec IN
      SELECT DISTINCT c.nama, c.wa
      FROM public.customers c
      JOIN public.konsinyasi k ON k.outlet = c.nama
      WHERE c.status='Aktif' AND c.sistem='Konsinyasi' AND c.wa IS NOT NULL AND c.wa <> ''
        AND k.status='Aktif'
    LOOP
      msg := '📊 *Rekap Bulanan Titipan Findest Sport*' || nl || nl ||
             'Halo ' || rec.nama || '!' || nl || nl ||
             'Bulan ini kami akan datang tgl 25 buat ambil rekap penjualan produk titipan.' || nl || nl ||
             '📝 Mohon disiapkan:' || nl ||
             '• Data qty terjual per produk' || nl ||
             '• Sisa stok fisik' || nl ||
             '• Barang retur (kalo ada — ED dekat, rusak, dll)' || nl || nl ||
             'Kalau bisa kirim rekap via WA sebelumnya biar lebih cepet. Terima kasih! 🙏';

      sent_ok := FALSE; err_msg := NULL;
      BEGIN
        PERFORM net.http_post(
          url := 'https://api.fonnte.com/send',
          headers := jsonb_build_object('Authorization', fonnte_token, 'Content-Type', 'application/json'),
          body := jsonb_build_object('target', rec.wa, 'message', msg)
        );
        sent_ok := TRUE;
      EXCEPTION WHEN OTHERS THEN err_msg := SQLERRM;
      END;
      target_type := 'outlet'; target_nama := rec.nama; wa := rec.wa; sent := sent_ok; err := err_msg;
      RETURN NEXT;
    END LOOP;
  END IF;

  RETURN;
END $$;

-- ─────────────────────────────────────────────────────────
-- 5. PG_CRON SCHEDULE: reminder otomatis
-- ─────────────────────────────────────────────────────────
-- Tgl 22 jam 09:00 WIB (02:00 UTC) → reminder sales
-- Tgl 23 jam 10:00 WIB (03:00 UTC) → reminder outlet
-- ─────────────────────────────────────────────────────────
DO $$
BEGIN
  -- Unschedule kalo udah ada (idempotent)
  PERFORM cron.unschedule('konsi_rekap_reminder_sales') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname='konsi_rekap_reminder_sales'
  );
  PERFORM cron.unschedule('konsi_rekap_reminder_outlet') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname='konsi_rekap_reminder_outlet'
  );
EXCEPTION WHEN OTHERS THEN NULL; -- cron ga tersedia = skip
END $$;

-- Schedule sales reminder — tanggal 22 tiap bulan
SELECT cron.schedule(
  'konsi_rekap_reminder_sales',
  '0 2 22 * *',
  $$SELECT public.send_konsi_rekap_reminder('sales');$$
);

-- Schedule outlet reminder — tanggal 23 tiap bulan
SELECT cron.schedule(
  'konsi_rekap_reminder_outlet',
  '0 3 23 * *',
  $$SELECT public.send_konsi_rekap_reminder('outlet');$$
);

-- ─────────────────────────────────────────────────────────
-- 6. HELPER RPC: historical turnover per outlet (buat dashboard investor)
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_konsi_turnover_historical(p_months INT DEFAULT 3)
RETURNS TABLE(
  outlet TEXT,
  months_data INT,
  avg_nilai_terjual_bulan NUMERIC,
  total_nilai_terjual NUMERIC,
  last_bulan DATE
)
LANGUAGE sql SECURITY DEFINER
AS $$
  SELECT outlet,
         COUNT(DISTINCT bulan)::INT AS months_data,
         COALESCE(AVG(nilai_terjual),0)::NUMERIC AS avg_nilai_terjual_bulan,
         COALESCE(SUM(nilai_terjual),0)::NUMERIC AS total_nilai_terjual,
         MAX(bulan)::DATE AS last_bulan
  FROM public.konsi_rekap_bulanan
  WHERE bulan >= (date_trunc('month', CURRENT_DATE) - (p_months || ' months')::INTERVAL)::DATE
    AND bulan < date_trunc('month', CURRENT_DATE)::DATE
  GROUP BY outlet;
$$;

-- ─────────────────────────────────────────────────────────
-- 7. VERIFY
-- ─────────────────────────────────────────────────────────
SELECT 'konsi_rekap_bulanan' as check, EXISTS (
  SELECT 1 FROM information_schema.tables WHERE table_name='konsi_rekap_bulanan'
) as ok;

SELECT 'trigger_after_insert' as check, EXISTS (
  SELECT 1 FROM pg_trigger WHERE tgname='trg_konsi_rekap_after_insert'
) as ok;

SELECT 'cron_sales' as check, EXISTS (
  SELECT 1 FROM cron.job WHERE jobname='konsi_rekap_reminder_sales'
) as ok;

SELECT 'cron_outlet' as check, EXISTS (
  SELECT 1 FROM cron.job WHERE jobname='konsi_rekap_reminder_outlet'
) as ok;

SELECT 'rpc_turnover' as check, EXISTS (
  SELECT 1 FROM pg_proc WHERE proname='get_konsi_turnover_historical'
) as ok;
