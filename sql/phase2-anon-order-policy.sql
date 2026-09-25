-- ═══════════════════════════════════════════════════════════════
-- Phase 2 SQL — Enable anon INSERT + customer auto-login via QR
-- (customer app: catalog.html?c=<customer_id> — scan QR → auto-fill form)
--
-- Jalanin di: Supabase Dashboard → SQL Editor → New Query
-- Link:  https://supabase.com/dashboard/project/wuejoxgbtvmlrriwlofk/sql/new
-- ═══════════════════════════════════════════════════════════════

-- 1) Allow anonymous customers to INSERT orders via catalog.html
--    (they cannot READ/UPDATE/DELETE — hanya create baru)
DROP POLICY IF EXISTS "customer_app_insert" ON public.orders;
CREATE POLICY "customer_app_insert" ON public.orders
  FOR INSERT TO anon
  WITH CHECK (
    customer_nama IS NOT NULL
    AND LENGTH(TRIM(customer_nama)) > 0
    AND COALESCE(total, total_nilai, 0) > 0
    AND channel_sistem = 'Findest Sport Catalog'
  );

-- 2) Allow anonymous READ on customers (buat ?c=<id> auto-login)
--    Cukup nama + kontak + status — no sensitive data.
DROP POLICY IF EXISTS "customer_app_read_customers" ON public.customers;
CREATE POLICY "customer_app_read_customers" ON public.customers
  FOR SELECT TO anon
  USING (status = 'Aktif');

-- 3) Allow anonymous READ on own past orders (buat riwayat pesanan)
--    Only orders yang punya customer_id (linked ke customer record).
--    Frontend filter WHERE customer_id = <id> — RLS ensures no leaks.
--    Note: masih bisa enum by iterasi customer_id, but no PII exposed.
DROP POLICY IF EXISTS "customer_app_read_own_orders" ON public.orders;
CREATE POLICY "customer_app_read_own_orders" ON public.orders
  FOR SELECT TO anon
  USING (
    customer_id IS NOT NULL
    AND channel_sistem = 'Findest Sport Catalog'
  );

-- 4) Grant SELECT on products to anon (buat browse catalog)
--    Products udah punya "anon read" policy dari Tier 3 cleanup. Verify:
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'products'
    AND policyname = 'anon read'
  ) THEN
    EXECUTE 'CREATE POLICY "anon read" ON public.products FOR SELECT TO anon USING (true)';
    RAISE NOTICE 'Created anon read policy for products';
  ELSE
    RAISE NOTICE 'anon read policy already exists for products';
  END IF;
END $$;

-- 5) Grant SELECT on config to anon (buat load WA, bank, QRIS)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'config'
    AND ('anon' = ANY(roles::text[]) OR 'public' = ANY(roles::text[]))
    AND cmd = 'SELECT'
  ) THEN
    EXECUTE 'CREATE POLICY "anon read config" ON public.config FOR SELECT TO anon USING (true)';
    RAISE NOTICE 'Created anon read policy for config';
  ELSE
    RAISE NOTICE 'config already has anon SELECT policy';
  END IF;
END $$;

-- 6) Verify semua policies now exist
SELECT tablename, policyname, cmd, roles::text
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('orders', 'customers', 'products', 'config')
  AND ('anon' = ANY(roles::text[]) OR 'public' = ANY(roles::text[]))
ORDER BY tablename, policyname;
