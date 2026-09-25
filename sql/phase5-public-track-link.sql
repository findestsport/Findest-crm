-- ═══════════════════════════════════════════════════════════════
-- Phase 5 — Public Order Tracking Link
--
-- Relax RLS supaya anon bisa SELECT any catalog order lewat URL
-- ?o=<order_id> — buat customer publik (tanpa QR) tetap bisa lacak.
--
-- Data yg ke-expose: nama, produk, total, status, pembayaran.
-- Order IDs sequential jadi bisa di-enumerate — kalo mau tighter
-- security nanti tambah kolom tracking_code (random) + policy match.
-- Buat MVP, trade-off ini acceptable.
--
-- Jalanin di: Supabase Dashboard → SQL Editor → New Query
-- ═══════════════════════════════════════════════════════════════

-- Replace policy: dulu cuma customer_id-linked, sekarang semua catalog order
DROP POLICY IF EXISTS "customer_app_read_own_orders" ON public.orders;

CREATE POLICY "customer_app_read_catalog_orders" ON public.orders
  FOR SELECT TO anon
  USING (channel_sistem = 'Findest Sport Catalog');

-- Verify
SELECT tablename, policyname, cmd, roles::text
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'orders'
  AND ('anon' = ANY(roles::text[]))
ORDER BY policyname;
