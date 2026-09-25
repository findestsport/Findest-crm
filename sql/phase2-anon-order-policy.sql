-- ═══════════════════════════════════════════════════════════════
-- Phase 2 SQL — Enable anon INSERT ke orders table
-- (buat customer app bisa submit order tanpa authentication)
--
-- Jalanin di: Supabase Dashboard → SQL Editor → New Query
-- Link:  https://supabase.com/dashboard/project/wuejoxgbtvmlrriwlofk/sql/new
-- ═══════════════════════════════════════════════════════════════

-- 1) Allow anonymous customers to INSERT new orders via customer app
--    (they cannot READ/UPDATE/DELETE — hanya create baru)
CREATE POLICY "customer_app_insert" ON public.orders
  FOR INSERT TO anon
  WITH CHECK (
    -- Basic validation: nama required, total positive
    customer_nama IS NOT NULL
    AND LENGTH(TRIM(customer_nama)) > 0
    AND total_nilai > 0
    AND channel_sistem = 'Findest Order App'  -- must be from our app
  );

-- 2) Optional: rate limit to prevent spam
--    (advanced — skip untuk MVP, tambah kalo perlu)

-- 3) Grant SELECT on customers to anon (buat auto-login by ?c=<id>)
--    Current customer_read policy sudah authenticated-only. Perlu tambahin anon.
CREATE POLICY "customer_app_read_customers" ON public.customers
  FOR SELECT TO anon
  USING (status = 'Aktif');

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

-- Verify semua policies now exist
SELECT tablename, policyname, cmd, roles::text
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('orders', 'customers', 'products')
  AND ('anon' = ANY(roles::text[]) OR 'public' = ANY(roles::text[]))
ORDER BY tablename, policyname;
