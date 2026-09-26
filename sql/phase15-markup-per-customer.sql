-- ═══════════════════════════════════════════════════════════════
-- Phase 15 — Markup per Customer
--
-- Beda customer beda markup. FnB acuan catalog price (markup 12-15%
-- baseline). Konsi partner minta markup extra (biasanya 8-15% extra
-- di atas catalog price).
--
-- Formula: harga_final = products.harga × (1 + markup_pct/100)
--
-- Kalo customer.markup_pct NULL atau 0 → harga catalog as-is.
-- ═══════════════════════════════════════════════════════════════

-- 1. Add column
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS markup_pct NUMERIC(5,2);

COMMENT ON COLUMN public.customers.markup_pct IS
  'Markup persen extra di atas products.harga. NULL/0 = pake harga catalog as-is. Contoh: konsi Adam 12% → harga × 1.12';

-- 2. Update auto_konsi_from_order trigger biar respect markup dari order (produk_json udah adjusted di frontend)
-- Trigger existing udah baca (item->>'harga')::numeric, jadi kalau frontend sudah adjust harga sebelum insert,
-- otomatis harga adjusted yang masuk konsinyasi.

-- Verify
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema='public' AND table_name='customers' AND column_name='markup_pct';
