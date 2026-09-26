-- ═══════════════════════════════════════════════════════════════
-- Phase 12 — Retur Konsi (Consignment Return Tracking)
--
-- Real problem: Customer FnB pesan produk. FP habis, tapi produk itu
-- ada di konsi partner (misal Healthy Plus Sanur). Findest tarik retur
-- dari konsi → transfer ke customer. Selama ini ga ada log rapih, SO
-- akhir bulan sering selisih.
--
-- Solusi:
-- 1. Table konsi_returns — audit trail per retur
-- 2. RPC retur_from_konsi() — atomic: konsi qty_retur ↑ + FP stok ↑
--    + batches (biar ED-nya keikut) + log
-- 3. View konsi_returns_summary — rekap per bulan/partner buat rekonsiliasi
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────
-- 1. TABLE konsi_returns
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.konsi_returns (
  id             BIGSERIAL PRIMARY KEY,
  konsi_id       BIGINT REFERENCES public.konsinyasi(id) ON DELETE SET NULL,
  outlet         TEXT NOT NULL,     -- konsi partner name (snapshot)
  produk         TEXT NOT NULL,     -- produk_nama
  qty            INTEGER NOT NULL CHECK (qty > 0),
  batch_no       TEXT,              -- kalo ada
  ed_date        DATE,              -- ED batch yg diretur
  alasan         TEXT,              -- kenapa retur (transfer ke customer X, dll)
  tujuan         TEXT,              -- 'gudang_fp' (default) atau 'customer' atau 'buang' (rusak)
  transfer_ke_customer TEXT,        -- nama customer tujuan kalo langsung transfer
  order_id       BIGINT,            -- link ke order kalo retur buat penuhin order tsb
  tgl_retur      DATE DEFAULT CURRENT_DATE,
  created_by     TEXT,              -- user email/nama
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  catatan        TEXT
);
CREATE INDEX IF NOT EXISTS idx_kr_tgl     ON public.konsi_returns(tgl_retur DESC);
CREATE INDEX IF NOT EXISTS idx_kr_outlet  ON public.konsi_returns(outlet);
CREATE INDEX IF NOT EXISTS idx_kr_produk  ON public.konsi_returns(produk);
CREATE INDEX IF NOT EXISTS idx_kr_konsi   ON public.konsi_returns(konsi_id);

-- ─────────────────────────────────────────────────────────
-- 2. RPC retur_from_konsi — atomic transfer konsi → FP
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.retur_from_konsi(
  p_konsi_id     BIGINT,
  p_qty          INTEGER,
  p_alasan       TEXT DEFAULT NULL,
  p_tujuan       TEXT DEFAULT 'gudang_fp',
  p_transfer_ke_customer TEXT DEFAULT NULL,
  p_order_id     BIGINT DEFAULT NULL,
  p_created_by   TEXT DEFAULT NULL,
  p_tgl_retur    DATE DEFAULT NULL
)
RETURNS TABLE(
  return_id       BIGINT,
  konsi_sisa      INTEGER,
  new_fp_stok     INTEGER,
  batch_id        BIGINT,
  message         TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_konsi        RECORD;
  v_prod         RECORD;
  v_new_qty_ret  INTEGER;
  v_new_stok     INTEGER;
  v_sisa         INTEGER;
  v_return_id    BIGINT;
  v_batch_id     BIGINT;
  v_tgl          DATE;
BEGIN
  IF p_qty IS NULL OR p_qty <= 0 THEN
    RAISE EXCEPTION 'qty harus > 0';
  END IF;

  v_tgl := COALESCE(p_tgl_retur, CURRENT_DATE);

  -- Lock konsi row
  SELECT * INTO v_konsi FROM public.konsinyasi WHERE id = p_konsi_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Konsinyasi id % not found', p_konsi_id;
  END IF;

  -- Sisa konsi = qty_titip - qty_terjual - qty_retur
  v_sisa := COALESCE(v_konsi.qty_titip,0) - COALESCE(v_konsi.qty_terjual,0) - COALESCE(v_konsi.qty_retur,0);
  IF p_qty > v_sisa THEN
    RAISE EXCEPTION 'Qty retur (%) > sisa titip di konsi (%)', p_qty, v_sisa;
  END IF;

  v_new_qty_ret := COALESCE(v_konsi.qty_retur,0) + p_qty;
  UPDATE public.konsinyasi
     SET qty_retur = v_new_qty_ret
   WHERE id = p_konsi_id;

  -- Update FP stok kalo tujuan gudang_fp atau customer (barang keluar dari konsi anyway)
  IF p_tujuan = 'gudang_fp' THEN
    SELECT * INTO v_prod FROM public.products WHERE nama = v_konsi.produk ORDER BY id LIMIT 1 FOR UPDATE;
    IF FOUND THEN
      v_new_stok := COALESCE(v_prod.stok,0) + p_qty;
      UPDATE public.products SET stok = v_new_stok WHERE id = v_prod.id;

      -- Add ke batches biar ED-nya keikut, kalo ada info batch di konsi
      IF v_konsi.batch_no IS NOT NULL OR v_konsi.ed_date IS NOT NULL THEN
        INSERT INTO public.batches (
          produk_nama, brand, jumlah_masuk, jumlah_sisa, harga_beli,
          tanggal_masuk, expired_date, status
        ) VALUES (
          v_konsi.produk,
          COALESCE(v_prod.brand,''),
          p_qty, p_qty, COALESCE(v_konsi.harga, v_prod.harga_beli, 0),
          v_tgl, v_konsi.ed_date, 'Aktif'
        ) RETURNING id INTO v_batch_id;
      END IF;
    END IF;
  ELSIF p_tujuan = 'customer' THEN
    -- Barang langsung ke customer, ga masuk FP. Ga update products.stok.
    v_new_stok := NULL;
  ELSIF p_tujuan = 'buang' THEN
    -- Rusak / expired, ga masuk FP
    v_new_stok := NULL;
  END IF;

  -- Insert log ke konsi_returns
  INSERT INTO public.konsi_returns (
    konsi_id, outlet, produk, qty, batch_no, ed_date,
    alasan, tujuan, transfer_ke_customer, order_id,
    tgl_retur, created_by
  ) VALUES (
    p_konsi_id, v_konsi.outlet, v_konsi.produk, p_qty,
    v_konsi.batch_no, v_konsi.ed_date,
    p_alasan, COALESCE(p_tujuan,'gudang_fp'), p_transfer_ke_customer, p_order_id,
    v_tgl, p_created_by
  ) RETURNING id INTO v_return_id;

  return_id    := v_return_id;
  konsi_sisa   := v_sisa - p_qty;
  new_fp_stok  := v_new_stok;
  batch_id     := v_batch_id;
  message      := format('✅ Retur %s unit "%s" dari %s (sisa titip %s)', p_qty, v_konsi.produk, v_konsi.outlet, konsi_sisa);
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.retur_from_konsi(BIGINT,INTEGER,TEXT,TEXT,TEXT,BIGINT,TEXT,DATE)
  TO anon, authenticated;

-- ─────────────────────────────────────────────────────────
-- 3. VIEW konsi_returns_summary — rekap per bulan/partner
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.konsi_returns_summary AS
SELECT
  TO_CHAR(tgl_retur, 'YYYY-MM')   AS period,
  outlet,
  produk,
  SUM(qty)                        AS total_qty,
  COUNT(*)                        AS n_returns,
  MIN(tgl_retur)                  AS first_retur,
  MAX(tgl_retur)                  AS last_retur
FROM public.konsi_returns
GROUP BY 1,2,3
ORDER BY 1 DESC, 2, 3;

-- ─────────────────────────────────────────────────────────
-- 4. RLS
-- ─────────────────────────────────────────────────────────
ALTER TABLE public.konsi_returns ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='konsi_returns' AND policyname='anon_all_kr') THEN
    CREATE POLICY anon_all_kr ON public.konsi_returns FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Grant read to view
GRANT SELECT ON public.konsi_returns_summary TO anon, authenticated;

-- Verify
SELECT 'konsi_returns'         AS obj, COUNT(*) AS rows FROM public.konsi_returns UNION ALL
SELECT 'konsi_returns_summary' , COUNT(*)              FROM public.konsi_returns_summary;
