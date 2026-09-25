-- ═══════════════════════════════════════════════════════════════
-- Phase 9B — FP Outlet Inventory + Consolidated ED Alert
--
-- Track stok per FP outlet dgn batch + ED. Auto-compute total_unit,
-- nilai_aset, ed_alert per outlet. View konsolidasi ED (FP + konsi).
-- ═══════════════════════════════════════════════════════════════

-- 1) TABLE: outlet_inventory (stok per outlet per batch)
CREATE TABLE IF NOT EXISTS public.outlet_inventory (
  id BIGSERIAL PRIMARY KEY,
  outlet_id BIGINT NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  product_id BIGINT NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  qty INTEGER DEFAULT 0,
  ed_date DATE,
  batch_no TEXT,
  harga_beli NUMERIC DEFAULT 0,     -- snapshot HPP (biar audit historical)
  last_updated DATE DEFAULT CURRENT_DATE,
  catatan TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_oi_outlet ON public.outlet_inventory(outlet_id);
CREATE INDEX IF NOT EXISTS idx_oi_product ON public.outlet_inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_oi_ed
  ON public.outlet_inventory(ed_date)
  WHERE ed_date IS NOT NULL AND qty > 0;

-- 2) RLS
ALTER TABLE public.outlet_inventory ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "oi_read" ON public.outlet_inventory;
CREATE POLICY "oi_read" ON public.outlet_inventory FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "oi_write" ON public.outlet_inventory;
CREATE POLICY "oi_write" ON public.outlet_inventory FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 3) TRIGGER: auto-update outlets aggregate on inventory changes
CREATE OR REPLACE FUNCTION public.refresh_outlet_aggregates(target_outlet_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_unit INTEGER;
  v_nilai_aset NUMERIC;
  v_ed_alert INTEGER;
BEGIN
  SELECT
    COALESCE(SUM(oi.qty), 0),
    COALESCE(SUM(oi.qty * COALESCE(p.harga, oi.harga_beli, 0)), 0),
    COUNT(*) FILTER (WHERE oi.ed_date IS NOT NULL AND oi.ed_date < CURRENT_DATE + INTERVAL '60 days' AND oi.qty > 0)
  INTO v_total_unit, v_nilai_aset, v_ed_alert
  FROM public.outlet_inventory oi
  LEFT JOIN public.products p ON p.id = oi.product_id
  WHERE oi.outlet_id = target_outlet_id;

  UPDATE public.outlets
    SET total_unit = v_total_unit,
        nilai_aset = v_nilai_aset,
        ed_alert = v_ed_alert
    WHERE id = target_outlet_id;
END $$;

CREATE OR REPLACE FUNCTION public.trigger_outlet_aggregates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.refresh_outlet_aggregates(OLD.outlet_id);
    RETURN OLD;
  ELSE
    PERFORM public.refresh_outlet_aggregates(NEW.outlet_id);
    IF TG_OP = 'UPDATE' AND OLD.outlet_id <> NEW.outlet_id THEN
      PERFORM public.refresh_outlet_aggregates(OLD.outlet_id);
    END IF;
    RETURN NEW;
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_oi_aggregate ON public.outlet_inventory;
CREATE TRIGGER trg_oi_aggregate
  AFTER INSERT OR UPDATE OR DELETE ON public.outlet_inventory
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_outlet_aggregates();

-- 4) VIEW: konsolidasi ED alert (FP outlet + konsinyasi)
CREATE OR REPLACE VIEW public.ed_alert_all AS
SELECT
  'FP' AS location_type,
  o.nama AS location_name,
  o.id AS location_id,
  p.nama AS produk,
  p.brand,
  oi.batch_no,
  oi.qty,
  oi.ed_date,
  (oi.ed_date - CURRENT_DATE)::int AS days_to_ed,
  oi.qty * COALESCE(p.harga, oi.harga_beli, 0) AS nilai
FROM public.outlet_inventory oi
JOIN public.outlets o ON o.id = oi.outlet_id
LEFT JOIN public.products p ON p.id = oi.product_id
WHERE oi.qty > 0 AND oi.ed_date IS NOT NULL
UNION ALL
SELECT
  'Konsinyasi' AS location_type,
  k.outlet AS location_name,
  NULL::BIGINT AS location_id,
  k.produk AS produk,
  NULL AS brand,
  k.batch_no,
  (k.qty_titip - k.qty_terjual - k.qty_retur) AS qty,
  k.ed_date,
  (k.ed_date - CURRENT_DATE)::int AS days_to_ed,
  (k.qty_titip - k.qty_terjual - k.qty_retur) * k.harga AS nilai
FROM public.konsinyasi k
WHERE k.status = 'Aktif' AND k.ed_date IS NOT NULL
  AND (k.qty_titip - k.qty_terjual - k.qty_retur) > 0;

GRANT SELECT ON public.ed_alert_all TO authenticated, anon;

-- 5) VIEW: consolidated ED summary (buat dashboard KPI card)
CREATE OR REPLACE VIEW public.ed_alert_summary AS
SELECT
  location_type,
  COUNT(*) FILTER (WHERE days_to_ed < 0) AS ed_expired_count,
  COUNT(*) FILTER (WHERE days_to_ed >= 0 AND days_to_ed <= 30) AS ed_30d_count,
  COUNT(*) FILTER (WHERE days_to_ed > 30 AND days_to_ed <= 60) AS ed_60d_count,
  COUNT(*) FILTER (WHERE days_to_ed > 60 AND days_to_ed <= 90) AS ed_90d_count,
  SUM(nilai) FILTER (WHERE days_to_ed < 0) AS ed_expired_nilai,
  SUM(nilai) FILTER (WHERE days_to_ed >= 0 AND days_to_ed <= 30) AS ed_30d_nilai,
  SUM(nilai) FILTER (WHERE days_to_ed > 30 AND days_to_ed <= 60) AS ed_60d_nilai,
  SUM(nilai) FILTER (WHERE days_to_ed > 60 AND days_to_ed <= 90) AS ed_90d_nilai
FROM public.ed_alert_all
GROUP BY location_type;

GRANT SELECT ON public.ed_alert_summary TO authenticated, anon;

-- ─── VERIFY ────────────────────────────────────────────────
SELECT table_name FROM information_schema.tables
WHERE table_schema='public' AND table_name IN ('outlet_inventory');

SELECT * FROM public.ed_alert_summary;
