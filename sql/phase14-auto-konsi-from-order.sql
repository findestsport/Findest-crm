-- ═══════════════════════════════════════════════════════════════
-- Phase 14 — Auto Konsinyasi dari Order (Single Entry via QR Scan)
--
-- User idea: konsi partner scan QR mereka juga (bukan cuma FnB).
-- Kalo customer scan-nya sistem='Konsinyasi' → order otomatis
-- dianggap TITIPAN, auto-insert row-row konsinyasi per produk.
--
-- Benefit: 1 entry point (catalog scan), no manual form konsi lagi.
-- Rekonsiliasi tetep via edit konsi row (update qty_terjual, qty_retur).
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────
-- 1. FUNCTION auto_konsi_from_order — trigger body
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auto_konsi_from_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sistem TEXT;
  item     JSONB;
  v_ed     DATE;
  v_batch  TEXT;
  v_qty    INTEGER;
  v_harga  NUMERIC;
BEGIN
  -- Only for orders WITH customer_id (skip anonymous/public orders)
  IF NEW.customer_id IS NULL OR NEW.produk_json IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT sistem INTO v_sistem FROM public.customers WHERE id = NEW.customer_id;
  IF v_sistem IS DISTINCT FROM 'Konsinyasi' THEN
    RETURN NEW;
  END IF;

  -- Loop produk_json, insert 1 row konsi per item
  FOR item IN SELECT * FROM jsonb_array_elements(NEW.produk_json)
  LOOP
    v_qty   := COALESCE((item->>'qty')::int, 1);
    v_harga := COALESCE((item->>'harga')::numeric, 0);

    -- Get ED from item (kalo catalog kirim), else from batches FIFO
    v_ed := NULLIF(item->>'ed_date','')::date;
    IF v_ed IS NULL THEN
      SELECT expired_date INTO v_ed
      FROM public.batches
      WHERE produk_nama = item->>'nama'
        AND status = 'Aktif' AND jumlah_sisa > 0
      ORDER BY expired_date ASC LIMIT 1;
    END IF;

    v_batch := NULLIF(item->>'batch_no','');

    INSERT INTO public.konsinyasi (
      outlet, produk, tgl_titip, qty_titip, qty_terjual, qty_retur,
      harga, nilai, status, ed_date, batch_no, catatan
    ) VALUES (
      NEW.customer_nama,
      item->>'nama',
      COALESCE(NEW.created_at::date, CURRENT_DATE),
      v_qty,
      0,
      0,
      v_harga,
      v_qty * v_harga,
      'Aktif',
      v_ed,
      v_batch,
      format('Auto dari order #%s (scan QR)', COALESCE(NEW.no_order, NEW.id::text))
    );
  END LOOP;

  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────
-- 2. TRIGGER — after insert on orders
-- ─────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_auto_konsi_from_order ON public.orders;
CREATE TRIGGER trg_auto_konsi_from_order
AFTER INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.auto_konsi_from_order();

-- ─────────────────────────────────────────────────────────
-- 3. VERIFY
-- ─────────────────────────────────────────────────────────
SELECT
  trigger_name, event_manipulation, action_timing, action_orientation
FROM information_schema.triggers
WHERE trigger_name = 'trg_auto_konsi_from_order';
