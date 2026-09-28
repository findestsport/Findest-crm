-- ═══════════════════════════════════════════════════════════════
-- Phase 20 — REVENUE RECOGNITION FIX (Critical)
--
-- Problem: Konsi customer titipan order → phase6 trigger buat invoice
-- pas order Selesai. Invoice ini kecatet di CRM sebagai OMZET, padahal
-- barangnya belum kejual (masih titipan). Boss liat dashboard omzet
-- tinggi palsu.
--
-- Real case: FP Uluwatu titipan 18jt + Miyo Dessert sale 8.4jt
--            = Dashboard show 26.4jt (WRONG, should be 8.4jt)
--
-- Fix: phase6 trigger skip create invoice kalo channel_sistem = Konsinyasi.
-- Omzet konsi diakui saat qty_terjual di-update (phase20 bonus trigger).
--
-- Optional: cancel invoices existing yg terlanjur dibuat dari titipan
-- (jalanin manual di bawah kalo mau clean up).
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────
-- 1. UPDATE orders_auto_invoice — skip Konsi titipan
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.orders_auto_invoice()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  existing_inv_id BIGINT;
  new_no_invoice TEXT;
  invoice_due DATE;
  today DATE := CURRENT_DATE;
BEGIN
  IF NEW.status <> 'Selesai' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'Selesai' THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.total_nilai, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- NEW: skip Konsi titipan — bukan omzet, cuma inventory move.
  -- Omzet konsi diakui via update qty_terjual di konsinyasi table.
  IF COALESCE(NEW.channel_sistem,'') ILIKE '%konsinyasi%' THEN
    RETURN NEW;
  END IF;

  SELECT id INTO existing_inv_id FROM public.invoices WHERE order_id = NEW.id LIMIT 1;
  IF existing_inv_id IS NOT NULL THEN
    UPDATE public.invoices
      SET status = 'Pending'
      WHERE id = existing_inv_id AND status IN ('Batal','Dibatalkan');
    RETURN NEW;
  END IF;

  IF NEW.pembayaran = 'Termin 30 Hari' AND NEW.due_date IS NOT NULL THEN
    invoice_due := NEW.due_date;
  ELSE
    invoice_due := today;
  END IF;

  new_no_invoice := 'INV-' || to_char(today, 'YYMM') || '-' || NEW.id::text;

  INSERT INTO public.invoices(
    no_invoice, customer_nama, customer_tipe, customer_sistem,
    tgl_invoice, jatuh_tempo, total, status, order_id
  ) VALUES (
    new_no_invoice,
    COALESCE(NEW.customer_nama, 'Guest'),
    NEW.channel_tipe,
    NEW.channel_sistem,
    today,
    invoice_due,
    NEW.total_nilai,
    CASE
      WHEN NEW.pembayaran IN ('QRIS','Transfer Bank') THEN 'Lunas'
      ELSE 'Pending'
    END,
    NEW.id
  );

  RETURN NEW;
END $$;

-- ─────────────────────────────────────────────────────────
-- 2. CLEAN UP existing Konsi titipan invoices (OPTIONAL)
--    Jalanin manual kalo mau clean up data yg terlanjur salah.
--    Ini nge-cancel invoice-invoice yg dibuat dari titipan konsi.
-- ─────────────────────────────────────────────────────────
-- Preview dulu berapa yang bakal ke-cancel:
-- SELECT id, no_invoice, customer_nama, customer_sistem, total, tgl_invoice
-- FROM public.invoices
-- WHERE customer_sistem ILIKE '%konsinyasi%'
--   AND status NOT IN ('Batal','Dibatalkan');

-- Kalo yakin, uncomment ini:
-- UPDATE public.invoices
-- SET status = 'Batal'
-- WHERE customer_sistem ILIKE '%konsinyasi%'
--   AND status NOT IN ('Batal','Dibatalkan');

-- ─────────────────────────────────────────────────────────
-- 3. VERIFY
-- ─────────────────────────────────────────────────────────
-- Cek trigger masih ada
SELECT tgname, tgrelid::regclass AS on_table
FROM pg_trigger
WHERE tgrelid = 'public.orders'::regclass
  AND tgname LIKE 'trg_orders_%invoice%'
ORDER BY tgname;

-- Cek function definition updated
SELECT proname, pg_get_functiondef(oid) LIKE '%konsinyasi%' AS has_konsi_guard
FROM pg_proc WHERE proname = 'orders_auto_invoice';
