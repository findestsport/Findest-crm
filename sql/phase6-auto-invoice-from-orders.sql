-- ═══════════════════════════════════════════════════════════════
-- Phase 6 — Auto-generate Invoice from Order 'Selesai'
--
-- Flow: order status → 'Selesai' → trigger auto-create invoice row.
-- Invoice muncul di CRM dashboard (Omzet Bulanan, P&L, Aging Piutang)
-- tanpa manual data entry. Termin orders → jatuh_tempo pake due_date
-- order. Non-termin → jatuh_tempo = tgl_invoice (langsung due).
--
-- Jalanin di: Supabase Dashboard → SQL Editor → New Query
-- ═══════════════════════════════════════════════════════════════

-- 1) Add order_id link column ke invoices (buat idempotency + audit)
ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS order_id BIGINT;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_invoices_order_id
  ON public.invoices(order_id)
  WHERE order_id IS NOT NULL;

-- 2) Trigger function: create invoice on order → Selesai
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
  -- Only fire when transitioning INTO 'Selesai'
  IF NEW.status <> 'Selesai' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'Selesai' THEN
    RETURN NEW;  -- already selesai, skip
  END IF;

  -- Skip kalo total zero (order kosong)
  IF COALESCE(NEW.total_nilai, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- Idempotent: skip kalo sudah ada invoice untuk order ini
  SELECT id INTO existing_inv_id FROM public.invoices WHERE order_id = NEW.id LIMIT 1;
  IF existing_inv_id IS NOT NULL THEN
    -- Kalo invoice-nya di-Batal (status='Batal'), reactivate
    UPDATE public.invoices
      SET status = 'Pending'
      WHERE id = existing_inv_id AND status IN ('Batal','Dibatalkan');
    RETURN NEW;
  END IF;

  -- Determine jatuh_tempo:
  --   Termin  → pakai due_date order (30 hari dari order date)
  --   Non-termin → jatuh_tempo = tgl_invoice (langsung due, alias tunai)
  IF NEW.pembayaran = 'Termin 30 Hari' AND NEW.due_date IS NOT NULL THEN
    invoice_due := NEW.due_date;
  ELSE
    invoice_due := today;  -- cash/QRIS/transfer: due immediately
  END IF;

  -- Generate no_invoice: INV-<yy><mm>-<orderid> biar traceable
  new_no_invoice := 'INV-' || to_char(today, 'YYMM') || '-' || NEW.id::text;

  -- Insert
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
      WHEN NEW.pembayaran IN ('QRIS','Transfer Bank') THEN 'Lunas'  -- prepaid → langsung Lunas
      ELSE 'Pending'
    END,
    NEW.id
  );

  RETURN NEW;
END $$;

-- 3) Trigger AFTER UPDATE (main path — order status berubah jadi Selesai)
DROP TRIGGER IF EXISTS trg_orders_auto_invoice_update ON public.orders;
CREATE TRIGGER trg_orders_auto_invoice_update
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'Selesai' AND (OLD.status IS NULL OR OLD.status <> 'Selesai'))
  EXECUTE FUNCTION public.orders_auto_invoice();

-- 4) Trigger AFTER INSERT (rare — order dibuat langsung dgn status Selesai)
DROP TRIGGER IF EXISTS trg_orders_auto_invoice_insert ON public.orders;
CREATE TRIGGER trg_orders_auto_invoice_insert
  AFTER INSERT ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'Selesai')
  EXECUTE FUNCTION public.orders_auto_invoice();

-- 5) BONUS: handler kalo order Selesai di-CANCEL (Batal/Dibatalkan)
--    Invoice-nya juga di-mark Batal biar ga ke-count di P&L
CREATE OR REPLACE FUNCTION public.orders_cancel_invoice()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('Dibatalkan','Batal') AND OLD.status = 'Selesai' THEN
    UPDATE public.invoices
      SET status = 'Batal'
      WHERE order_id = NEW.id
        AND status NOT IN ('Batal','Dibatalkan');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_orders_cancel_invoice ON public.orders;
CREATE TRIGGER trg_orders_cancel_invoice
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status IN ('Dibatalkan','Batal') AND OLD.status = 'Selesai')
  EXECUTE FUNCTION public.orders_cancel_invoice();

-- 6) BACKFILL: existing catalog orders yg udah 'Selesai' tapi belum punya invoice
-- Uncomment kalo mau backfill. Buat data yg udah masuk sebelum trigger aktif.
-- INSERT INTO public.invoices(no_invoice, customer_nama, customer_tipe, customer_sistem, tgl_invoice, jatuh_tempo, total, status, order_id)
-- SELECT
--   'INV-' || to_char(COALESCE(o.created_at, NOW())::date, 'YYMM') || '-' || o.id::text,
--   COALESCE(o.customer_nama, 'Guest'),
--   o.channel_tipe,
--   o.channel_sistem,
--   COALESCE(o.created_at::date, CURRENT_DATE),
--   CASE WHEN o.pembayaran = 'Termin 30 Hari' AND o.due_date IS NOT NULL THEN o.due_date
--        ELSE COALESCE(o.created_at::date, CURRENT_DATE) END,
--   o.total_nilai,
--   CASE WHEN o.pembayaran IN ('QRIS','Transfer Bank') THEN 'Lunas' ELSE 'Pending' END,
--   o.id
-- FROM public.orders o
-- WHERE o.status = 'Selesai'
--   AND o.total_nilai > 0
--   AND o.channel_sistem = 'Findest Sport Catalog'
--   AND NOT EXISTS (SELECT 1 FROM public.invoices WHERE order_id = o.id)
-- ORDER BY o.id;

-- ─── VERIFY ────────────────────────────────────────────────
-- Cek triggers
SELECT tgname, tgrelid::regclass AS on_table
FROM pg_trigger
WHERE tgrelid = 'public.orders'::regclass
  AND tgname LIKE 'trg_orders_%invoice%'
ORDER BY tgname;

-- Cek order_id column ada di invoices
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema='public' AND table_name='invoices' AND column_name='order_id';
