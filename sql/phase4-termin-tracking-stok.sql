-- ═══════════════════════════════════════════════════════════════
-- Phase 4 SQL — Termin 30 hari + Order Tracking + Auto-Stok
--
-- Jalanin di: Supabase Dashboard → SQL Editor → New Query
-- Link:  https://supabase.com/dashboard/project/wuejoxgbtvmlrriwlofk/sql/new
-- ═══════════════════════════════════════════════════════════════

-- ─── FEATURE 1: TERMIN 30 HARI ────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS credit_days INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS due_date DATE;

-- Backfill due_date buat existing termin orders (kalo ada credit_days > 0)
UPDATE public.orders
SET due_date = (COALESCE(tanggal, created_at::date) + credit_days)
WHERE credit_days > 0 AND due_date IS NULL;

-- ─── FEATURE 3: STRUCTURED PRODUK JSON ────────────────────────
-- Kolom baru buat store detail item per order (buat auto-stok trigger)
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS produk_json JSONB;

-- Index buat query cepet
CREATE INDEX IF NOT EXISTS idx_orders_produk_json_gin
  ON public.orders USING GIN (produk_json)
  WHERE produk_json IS NOT NULL;

-- ─── FEATURE 3: AUTO-DECREMENT STOK ON STATUS = 'Selesai' ─────
CREATE OR REPLACE FUNCTION public.orders_stok_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item JSONB;
  pid INTEGER;
  qty INTEGER;
BEGIN
  -- Trigger only kalau produk_json ada
  IF NEW.produk_json IS NULL THEN
    RETURN NEW;
  END IF;

  -- Case 1: transisi ke 'Selesai' → decrement stok
  IF NEW.status = 'Selesai' AND (OLD.status IS NULL OR OLD.status <> 'Selesai') THEN
    FOR item IN SELECT * FROM jsonb_array_elements(NEW.produk_json)
    LOOP
      pid := NULLIF(item->>'product_id','')::int;
      qty := COALESCE(NULLIF(item->>'qty','')::int, 0);
      IF pid IS NOT NULL AND qty > 0 THEN
        UPDATE public.products
        SET stok = GREATEST(0, COALESCE(stok, 0) - qty)
        WHERE id = pid;
      END IF;
    END LOOP;
  END IF;

  -- Case 2: undo dari 'Selesai' → 'Dibatalkan' → restore stok
  IF NEW.status IN ('Dibatalkan','Batal') AND OLD.status = 'Selesai' THEN
    FOR item IN SELECT * FROM jsonb_array_elements(NEW.produk_json)
    LOOP
      pid := NULLIF(item->>'product_id','')::int;
      qty := COALESCE(NULLIF(item->>'qty','')::int, 0);
      IF pid IS NOT NULL AND qty > 0 THEN
        UPDATE public.products
        SET stok = COALESCE(stok, 0) + qty
        WHERE id = pid;
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_orders_stok_sync ON public.orders;
CREATE TRIGGER trg_orders_stok_sync
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.orders_stok_sync();

-- Juga trigger AFTER INSERT — kalo ada order langsung create dgn status='Selesai'
CREATE OR REPLACE FUNCTION public.orders_stok_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item JSONB;
  pid INTEGER;
  qty INTEGER;
BEGIN
  IF NEW.produk_json IS NULL OR NEW.status <> 'Selesai' THEN
    RETURN NEW;
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(NEW.produk_json)
  LOOP
    pid := NULLIF(item->>'product_id','')::int;
    qty := COALESCE(NULLIF(item->>'qty','')::int, 0);
    IF pid IS NOT NULL AND qty > 0 THEN
      UPDATE public.products
      SET stok = GREATEST(0, COALESCE(stok, 0) - qty)
      WHERE id = pid;
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_orders_stok_insert ON public.orders;
CREATE TRIGGER trg_orders_stok_insert
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.orders_stok_on_insert();

-- ─── FEATURE 2: ENABLE REALTIME ON ORDERS ─────────────────────
-- Biar customer app bisa subscribe order status updates lewat WebSocket
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'orders'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.orders';
    RAISE NOTICE 'Enabled realtime on orders table';
  ELSE
    RAISE NOTICE 'orders already in supabase_realtime publication';
  END IF;
END $$;

-- ─── UPDATE RLS: Customer app SELECT own orders juga expose kolom baru ──
-- (Existing policy sudah cover — no change needed karena SELECT * respect RLS)

-- ─── VERIFY ───────────────────────────────────────────────────
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'orders'
  AND column_name IN ('credit_days','due_date','produk_json','customer_id','channel_sistem','total_nilai')
ORDER BY column_name;

-- Check triggers
SELECT tgname, tgrelid::regclass AS table_name
FROM pg_trigger
WHERE tgrelid = 'public.orders'::regclass
  AND tgname LIKE 'trg_orders_stok%';

-- Check realtime publication
SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime' AND tablename = 'orders';
