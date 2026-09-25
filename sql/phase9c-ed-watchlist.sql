-- ═══════════════════════════════════════════════════════════════
-- Phase 9C — Urgent ED Watchlist (actionable, contact info attached)
--
-- Enhance ed_alert_all: join dgn customers (buat konsi) & outlets (buat FP)
-- biar dapet PIC + WA contact. Dashboard bisa nampilin "call to action" list
-- terurut by urgency + tombol WA langsung ke PIC.
-- ═══════════════════════════════════════════════════════════════

-- Drop old view + recreate dgn kontak info
DROP VIEW IF EXISTS public.ed_alert_summary;
DROP VIEW IF EXISTS public.ed_alert_all;

CREATE OR REPLACE VIEW public.ed_alert_all AS
-- FP outlets
SELECT
  'FP' AS location_type,
  o.nama AS location_name,
  o.id AS location_id,
  NULL::BIGINT AS customer_id,
  o.pic AS contact_pic,
  o.no_hp AS contact_wa,
  p.nama AS produk,
  p.brand,
  oi.batch_no,
  oi.qty,
  oi.ed_date,
  (oi.ed_date - CURRENT_DATE)::int AS days_to_ed,
  oi.qty * COALESCE(p.harga, oi.harga_beli, 0) AS nilai,
  oi.id AS ref_id
FROM public.outlet_inventory oi
JOIN public.outlets o ON o.id = oi.outlet_id
LEFT JOIN public.products p ON p.id = oi.product_id
WHERE oi.qty > 0 AND oi.ed_date IS NOT NULL

UNION ALL

-- Konsinyasi partners (join with customers untuk dapet WA + PIC)
SELECT
  'Konsinyasi' AS location_type,
  k.outlet AS location_name,
  NULL::BIGINT AS location_id,
  c.id AS customer_id,
  COALESCE(c.pic, c.nama) AS contact_pic,
  c.wa AS contact_wa,
  k.produk AS produk,
  NULL AS brand,
  k.batch_no,
  (k.qty_titip - k.qty_terjual - k.qty_retur) AS qty,
  k.ed_date,
  (k.ed_date - CURRENT_DATE)::int AS days_to_ed,
  (k.qty_titip - k.qty_terjual - k.qty_retur) * k.harga AS nilai,
  k.id AS ref_id
FROM public.konsinyasi k
LEFT JOIN public.customers c ON c.nama = k.outlet
WHERE k.status = 'Aktif' AND k.ed_date IS NOT NULL
  AND (k.qty_titip - k.qty_terjual - k.qty_retur) > 0;

GRANT SELECT ON public.ed_alert_all TO authenticated, anon;

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
SELECT * FROM public.ed_alert_all ORDER BY days_to_ed LIMIT 10;
SELECT * FROM public.ed_alert_summary;
