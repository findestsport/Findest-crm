-- ═══════════════════════════════════════════════════════════════
-- Phase 4B — WhatsApp push notif ke sales via Fonnte
--
-- Setup Fonnte dulu sebelum jalanin:
-- 1. Daftar di https://fonnte.com (free trial 5 hari, terus Rp 50rb/bulan)
-- 2. Scan QR pake HP → connect device
-- 3. Copy Token di menu Device → https://md.fonnte.com/device
-- 4. Simpan token + admin WA di config table (lihat step SETUP di bawah)
--
-- Jalanin di: Supabase Dashboard → SQL Editor → New Query
-- ═══════════════════════════════════════════════════════════════

-- ─── 0) ENABLE pg_net EXTENSION ─────────────────────────────
-- Buat HTTP call dari database trigger
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ─── 1) SETUP: SIMPAN FONNTE TOKEN + ADMIN WA DI CONFIG ─────
-- GANTI 'YOUR_FONNTE_TOKEN_HERE' dgn token dari fonnte.com/device
-- GANTI '628xxxxxxxxxx' dgn nomor WA admin (format international, tanpa +)
-- Kalo mau kirim ke multiple admins → pisahin pake koma, misal:
--   '6281234567890,6289876543210'
INSERT INTO public.config(key, value)
VALUES
  ('fonnte_token', 'YOUR_FONNTE_TOKEN_HERE'),
  ('fonnte_admin_wa', '628xxxxxxxxxx'),
  ('fonnte_enabled', 'false')  -- ubah ke 'true' setelah token diset
ON CONFLICT(key) DO NOTHING;

-- ─── 2) FUNCTION: BUILD MESSAGE + SEND KE FONNTE ─────────────
CREATE OR REPLACE FUNCTION public.notify_new_order_wa()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  fonnte_token TEXT;
  admin_wa TEXT;
  fonnte_enabled TEXT;
  msg TEXT;
  order_time TEXT;
  produk_detail TEXT;
  termin_info TEXT;
BEGIN
  -- Skip kalo bukan status Pending (order baru)
  IF NEW.status <> 'Pending' AND NEW.status <> 'Baru' THEN
    RETURN NEW;
  END IF;

  -- Load config
  SELECT value INTO fonnte_token FROM public.config WHERE key='fonnte_token';
  SELECT value INTO admin_wa FROM public.config WHERE key='fonnte_admin_wa';
  SELECT value INTO fonnte_enabled FROM public.config WHERE key='fonnte_enabled';

  -- Skip kalo config incomplete atau enabled=false
  IF fonnte_enabled IS NULL OR fonnte_enabled <> 'true'
     OR fonnte_token IS NULL OR fonnte_token='YOUR_FONNTE_TOKEN_HERE' OR fonnte_token=''
     OR admin_wa IS NULL OR admin_wa='' THEN
    RETURN NEW;
  END IF;

  -- Format
  order_time := to_char(NOW() AT TIME ZONE 'Asia/Makassar', 'DD Mon YYYY HH24:MI');
  produk_detail := COALESCE(NEW.produk, '(detail via CRM)');

  -- Termin note
  IF NEW.pembayaran = 'Termin 30 Hari' AND NEW.due_date IS NOT NULL THEN
    termin_info := E'\n📆 Jatuh Tempo: ' || to_char(NEW.due_date, 'DD Mon YYYY');
  ELSE
    termin_info := '';
  END IF;

  -- Build WA message
  msg := E'🆕 *ORDER BARU — FINDEST SPORT*\n\n' ||
    E'📋 *' || COALESCE(NEW.no_order, 'ORDER #' || NEW.id::text) || E'*\n' ||
    E'👤 ' || COALESCE(NEW.customer_nama, '—') || E'\n' ||
    E'🏷 ' || COALESCE(NEW.channel_tipe, 'Public') || E'\n\n' ||
    E'📦 *Produk:*\n' || produk_detail || E'\n\n' ||
    E'💰 *Total:* Rp ' || to_char(NEW.total_nilai, 'FM999,999,999') || E'\n' ||
    E'💳 *Bayar:* ' || COALESCE(NEW.pembayaran, '—') || termin_info || E'\n\n' ||
    E'🕒 ' || order_time || E'\n\n' ||
    E'👉 Konfirmasi di:\nhttps://findestsport.github.io/Findest-crm/admin-orders.html';

  -- Fire HTTP POST ke Fonnte API (async — ga blocking insert)
  PERFORM net.http_post(
    url := 'https://api.fonnte.com/send',
    headers := jsonb_build_object(
      'Authorization', fonnte_token,
      'Content-Type', 'application/x-www-form-urlencoded'
    ),
    body := jsonb_build_object(
      'target', admin_wa,
      'message', msg,
      'countryCode', '62'
    )
  );

  RETURN NEW;
END $$;

-- ─── 3) TRIGGER: ON INSERT ORDERS → SEND WA ──────────────────
DROP TRIGGER IF EXISTS trg_orders_notify_wa ON public.orders;
CREATE TRIGGER trg_orders_notify_wa
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_order_wa();

-- ─── 4) HELPER: CEK FONNTE STATUS ───────────────────────────
-- Panggil kapan aja buat cek: SELECT public.check_fonnte_status();
CREATE OR REPLACE FUNCTION public.check_fonnte_status()
RETURNS TABLE(setting TEXT, value TEXT, status TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    'fonnte_enabled'::TEXT,
    COALESCE((SELECT value FROM public.config WHERE key='fonnte_enabled'), 'NOT SET')::TEXT,
    CASE
      WHEN (SELECT value FROM public.config WHERE key='fonnte_enabled') = 'true' THEN '✓ Enabled'
      ELSE '✗ Disabled — ubah value ke ''true'' di config table'
    END::TEXT
  UNION ALL
  SELECT
    'fonnte_token',
    CASE
      WHEN (SELECT value FROM public.config WHERE key='fonnte_token') IN ('YOUR_FONNTE_TOKEN_HERE','') THEN 'NOT SET'
      ELSE '****' || RIGHT((SELECT value FROM public.config WHERE key='fonnte_token'), 4)
    END,
    CASE
      WHEN (SELECT value FROM public.config WHERE key='fonnte_token') NOT IN ('YOUR_FONNTE_TOKEN_HERE','','') THEN '✓ Token set'
      ELSE '✗ Token not set — copy dari https://md.fonnte.com/device'
    END
  UNION ALL
  SELECT
    'fonnte_admin_wa',
    COALESCE((SELECT value FROM public.config WHERE key='fonnte_admin_wa'), 'NOT SET'),
    CASE
      WHEN (SELECT value FROM public.config WHERE key='fonnte_admin_wa') NOT IN ('628xxxxxxxxxx','') THEN '✓ WA set'
      ELSE '✗ WA not set — format 628xxx (tanpa +)'
    END;
$$;

-- ─── VERIFY ────────────────────────────────────────────────
SELECT * FROM public.check_fonnte_status();

-- Trigger check
SELECT tgname FROM pg_trigger
WHERE tgrelid = 'public.orders'::regclass
  AND tgname = 'trg_orders_notify_wa';
