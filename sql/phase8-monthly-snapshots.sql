-- ═══════════════════════════════════════════════════════════════
-- Phase 8 — Monthly Snapshots (auto-archive history per bulan)
--
-- Nyimpen snapshot metrics per bulan: omzet, top produk, top customer,
-- kas, piutang. History ini tetep ada walaupun data mentah (orders,
-- invoices) di-reset. Snapshot bisa di-save:
--   • Otomatis: dipanggil di frontend tiap awal bulan
--   • Sebelum Reset: doResetTrial panggil dulu snapshotAllMonths()
--   • Manual: tombol "Snapshot Sekarang" di dashboard
-- ═══════════════════════════════════════════════════════════════

-- 1) TABLE: monthly_snapshots
CREATE TABLE IF NOT EXISTS public.monthly_snapshots (
  id BIGSERIAL PRIMARY KEY,
  period TEXT NOT NULL,                        -- YYYY-MM
  total_omzet NUMERIC DEFAULT 0,
  total_order INTEGER DEFAULT 0,
  total_invoice INTEGER DEFAULT 0,
  kas_masuk NUMERIC DEFAULT 0,
  kas_keluar NUMERIC DEFAULT 0,
  saldo_awal NUMERIC DEFAULT 0,
  saldo_akhir NUMERIC DEFAULT 0,
  piutang_outstanding NUMERIC DEFAULT 0,
  top_products JSONB DEFAULT '[]',             -- [{product_id, nama, brand, qty, revenue}]
  top_customers JSONB DEFAULT '[]',            -- [{customer_id, nama, revenue, order_count}]
  channel_breakdown JSONB DEFAULT '{}',        -- {catalog: 402000, manual: 0, ...}
  expenses_breakdown JSONB DEFAULT '{}',       -- {bensin: 1500000, biaya_fp: 18900000, ...}
  snapshot_type TEXT DEFAULT 'manual',         -- 'auto' | 'manual' | 'pre_reset'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_snapshots_period_type
  ON public.monthly_snapshots(period, snapshot_type);
CREATE INDEX IF NOT EXISTS idx_snapshots_period
  ON public.monthly_snapshots(period DESC);

-- 2) RLS: hanya authenticated bisa read/write
ALTER TABLE public.monthly_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "snapshots_read" ON public.monthly_snapshots;
CREATE POLICY "snapshots_read" ON public.monthly_snapshots
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "snapshots_write" ON public.monthly_snapshots;
CREATE POLICY "snapshots_write" ON public.monthly_snapshots
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 3) RPC: take_monthly_snapshot(period, snapshot_type)
--    Panggil dari frontend: sb.rpc('take_monthly_snapshot', {p_period: '2026-09', p_type: 'auto'})
CREATE OR REPLACE FUNCTION public.take_monthly_snapshot(
  p_period TEXT,
  p_type TEXT DEFAULT 'manual'
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id BIGINT;
  v_omzet NUMERIC := 0;
  v_orders INTEGER := 0;
  v_invoices INTEGER := 0;
  v_masuk NUMERIC := 0;
  v_keluar NUMERIC := 0;
  v_piutang NUMERIC := 0;
  v_saldo_awal NUMERIC := 0;
  v_saldo_akhir NUMERIC := 0;
  v_top_prod JSONB;
  v_top_cust JSONB;
  v_channel JSONB;
  v_expenses JSONB;
BEGIN
  -- Omzet dari invoices bulan itu
  SELECT COALESCE(SUM(total), 0), COUNT(*)
    INTO v_omzet, v_invoices
    FROM public.invoices
    WHERE to_char(created_at, 'YYYY-MM') = p_period AND status <> 'Batal';

  -- Order count dari orders bulan itu
  SELECT COUNT(*) INTO v_orders
    FROM public.orders
    WHERE to_char(created_at, 'YYYY-MM') = p_period;

  -- Kas Masuk dari payments (tanggal_bayar starts with period)
  SELECT COALESCE(SUM(jumlah), 0) INTO v_masuk
    FROM public.payments
    WHERE tanggal_bayar LIKE p_period || '%';

  -- Kas Keluar dari expenses (tgl starts with period)
  SELECT COALESCE(SUM(nominal), 0) INTO v_keluar
    FROM public.expenses
    WHERE tgl LIKE p_period || '%';

  -- Piutang: invoice belum lunas per akhir period (cumulative)
  SELECT COALESCE(SUM(total), 0) INTO v_piutang
    FROM public.invoices
    WHERE status <> 'Lunas' AND status <> 'Batal'
      AND to_char(created_at, 'YYYY-MM') <= p_period;

  -- Saldo awal dari config
  SELECT COALESCE((value)::numeric, 0) INTO v_saldo_awal
    FROM public.config WHERE key = 'cash_start_' || p_period;
  v_saldo_awal := COALESCE(v_saldo_awal, 0);
  v_saldo_akhir := v_saldo_awal + v_masuk - v_keluar;

  -- Top products: aggregate produk_json dari orders bulan itu (yg Selesai)
  WITH item AS (
    SELECT
      (elem->>'product_id')::int AS pid,
      elem->>'nama' AS nama,
      elem->>'brand' AS brand,
      (elem->>'qty')::int AS qty,
      COALESCE((elem->>'subtotal')::numeric, (elem->>'qty')::numeric * (elem->>'harga')::numeric) AS revenue
    FROM public.orders o, jsonb_array_elements(o.produk_json) elem
    WHERE to_char(o.created_at, 'YYYY-MM') = p_period
      AND o.status = 'Selesai'
      AND o.produk_json IS NOT NULL
  )
  SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.revenue DESC), '[]'::jsonb) INTO v_top_prod
  FROM (
    SELECT pid AS product_id, nama, brand, SUM(qty) AS qty, SUM(revenue) AS revenue
    FROM item
    WHERE pid IS NOT NULL
    GROUP BY pid, nama, brand
    ORDER BY SUM(revenue) DESC
    LIMIT 10
  ) t;

  -- Top customers: aggregate dari orders bulan itu
  SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.revenue DESC), '[]'::jsonb) INTO v_top_cust
  FROM (
    SELECT
      customer_id,
      customer_nama AS nama,
      SUM(total_nilai) AS revenue,
      COUNT(*)::int AS order_count
    FROM public.orders
    WHERE to_char(created_at, 'YYYY-MM') = p_period
      AND status <> 'Dibatalkan' AND status <> 'Batal'
    GROUP BY customer_id, customer_nama
    ORDER BY SUM(total_nilai) DESC
    LIMIT 10
  ) t;

  -- Channel breakdown (by channel_sistem)
  SELECT COALESCE(jsonb_object_agg(channel_sistem, total_omzet), '{}'::jsonb) INTO v_channel
  FROM (
    SELECT COALESCE(channel_sistem, 'Manual') AS channel_sistem, SUM(total_nilai) AS total_omzet
    FROM public.orders
    WHERE to_char(created_at, 'YYYY-MM') = p_period AND status <> 'Batal' AND status <> 'Dibatalkan'
    GROUP BY channel_sistem
  ) t;

  -- Expenses breakdown (by kategori)
  SELECT COALESCE(jsonb_object_agg(kategori, total), '{}'::jsonb) INTO v_expenses
  FROM (
    SELECT COALESCE(kategori, 'Lain-lain') AS kategori, SUM(nominal) AS total
    FROM public.expenses
    WHERE tgl LIKE p_period || '%'
    GROUP BY kategori
  ) t;

  -- Upsert
  INSERT INTO public.monthly_snapshots(
    period, total_omzet, total_order, total_invoice,
    kas_masuk, kas_keluar, saldo_awal, saldo_akhir,
    piutang_outstanding, top_products, top_customers,
    channel_breakdown, expenses_breakdown, snapshot_type
  ) VALUES (
    p_period, v_omzet, v_orders, v_invoices,
    v_masuk, v_keluar, v_saldo_awal, v_saldo_akhir,
    v_piutang, v_top_prod, v_top_cust,
    v_channel, v_expenses, p_type
  )
  ON CONFLICT (period, snapshot_type) DO UPDATE SET
    total_omzet = EXCLUDED.total_omzet,
    total_order = EXCLUDED.total_order,
    total_invoice = EXCLUDED.total_invoice,
    kas_masuk = EXCLUDED.kas_masuk,
    kas_keluar = EXCLUDED.kas_keluar,
    saldo_awal = EXCLUDED.saldo_awal,
    saldo_akhir = EXCLUDED.saldo_akhir,
    piutang_outstanding = EXCLUDED.piutang_outstanding,
    top_products = EXCLUDED.top_products,
    top_customers = EXCLUDED.top_customers,
    channel_breakdown = EXCLUDED.channel_breakdown,
    expenses_breakdown = EXCLUDED.expenses_breakdown,
    created_at = NOW()
  RETURNING id INTO new_id;

  RETURN new_id;
END $$;

-- 4) RPC: snapshot_all_months() — buat pre-reset backup semua bulan yg ada data
CREATE OR REPLACE FUNCTION public.snapshot_all_months(p_type TEXT DEFAULT 'pre_reset')
RETURNS TABLE(period TEXT, snapshot_id BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m TEXT;
BEGIN
  FOR m IN
    SELECT DISTINCT to_char(created_at, 'YYYY-MM')
    FROM (
      SELECT created_at FROM public.orders
      UNION ALL
      SELECT created_at FROM public.invoices
      UNION ALL
      SELECT created_at FROM public.payments
      UNION ALL
      SELECT created_at FROM public.expenses
    ) x
    WHERE created_at IS NOT NULL
    ORDER BY 1
  LOOP
    period := m;
    snapshot_id := public.take_monthly_snapshot(m, p_type);
    RETURN NEXT;
  END LOOP;
  RETURN;
END $$;

-- ─── VERIFY ────────────────────────────────────────────────
SELECT table_name FROM information_schema.tables
WHERE table_schema='public' AND table_name='monthly_snapshots';

SELECT routine_name FROM information_schema.routines
WHERE routine_schema='public' AND routine_name IN ('take_monthly_snapshot','snapshot_all_months');
