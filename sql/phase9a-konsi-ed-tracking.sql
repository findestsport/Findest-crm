-- ═══════════════════════════════════════════════════════════════
-- Phase 9A — Konsinyasi ED Tracking + Outlet PIC info
--
-- Enables control barang titipan di rekanan konsinyasi:
--   • ed_date per titipan (ED alert per produk per outlet)
--   • batch_no biar bisa traceable (kalo recall)
--   • Outlets tab dapet PIC + no_hp yg proper
-- ═══════════════════════════════════════════════════════════════

-- 1) Add ED tracking columns ke konsinyasi
ALTER TABLE public.konsinyasi
  ADD COLUMN IF NOT EXISTS ed_date DATE,
  ADD COLUMN IF NOT EXISTS batch_no TEXT,
  ADD COLUMN IF NOT EXISTS ed_alerted BOOLEAN DEFAULT FALSE;

-- Index buat filter by ED
CREATE INDEX IF NOT EXISTS idx_konsi_ed_date
  ON public.konsinyasi(ed_date)
  WHERE ed_date IS NOT NULL AND status = 'Aktif';

-- 2) Ensure outlets table has all display columns (buat data lengkap)
ALTER TABLE public.outlets
  ADD COLUMN IF NOT EXISTS pic TEXT,
  ADD COLUMN IF NOT EXISTS no_hp TEXT,
  ADD COLUMN IF NOT EXISTS catatan TEXT,
  ADD COLUMN IF NOT EXISTS nilai_aset BIGINT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_unit INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ed_alert INTEGER DEFAULT 0;

-- 3) VIEW: konsinyasi ED summary per outlet (buat dashboard alert)
CREATE OR REPLACE VIEW public.konsi_ed_summary AS
SELECT
  outlet,
  COUNT(*) FILTER (WHERE ed_date IS NOT NULL AND ed_date < CURRENT_DATE + INTERVAL '30 days') AS ed_30d,
  COUNT(*) FILTER (WHERE ed_date IS NOT NULL AND ed_date < CURRENT_DATE + INTERVAL '60 days') AS ed_60d,
  COUNT(*) FILTER (WHERE ed_date IS NOT NULL AND ed_date < CURRENT_DATE + INTERVAL '90 days') AS ed_90d,
  COUNT(*) FILTER (WHERE ed_date IS NOT NULL AND ed_date < CURRENT_DATE) AS ed_expired,
  SUM((qty_titip - qty_terjual - qty_retur) * harga) AS nilai_sisa,
  SUM(qty_titip - qty_terjual - qty_retur) AS unit_sisa
FROM public.konsinyasi
WHERE status = 'Aktif'
GROUP BY outlet;

GRANT SELECT ON public.konsi_ed_summary TO authenticated, anon;

-- ─── VERIFY ────────────────────────────────────────────────
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema='public' AND table_name='konsinyasi'
  AND column_name IN ('ed_date','batch_no','ed_alerted');

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema='public' AND table_name='outlets'
  AND column_name IN ('pic','no_hp','catatan');

SELECT * FROM public.konsi_ed_summary LIMIT 5;
