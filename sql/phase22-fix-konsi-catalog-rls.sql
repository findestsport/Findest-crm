-- ═══════════════════════════════════════════════════════════════
-- Phase 22 — FIX: Order KONSI dari catalog diblok RLS (silent fail)
--
-- BUG (ditemuin 2026-10-01):
--   Customer anon yang scan catalog CUMA boleh insert order dengan
--   channel_sistem = 'Findest Sport Catalog' (policy customer_app_insert).
--   Tapi order KONSI (titipan) dari catalog pakai channel
--   'Konsinyasi (Titipan)' → DITOLAK RLS → order GAK ke-save.
--   Akibatnya: order konsi partner ilang, gak ada popup tracking, gak
--   masuk tab Konsinyasi. Order F&B/biasa lolos (channel-nya match).
--
--   Policy SELECT anon (customer_app_read_catalog_orders) juga cuma izinin
--   'Findest Sport Catalog' → RETURNING sesudah insert gak kebaca →
--   popup tracking gak dapet data walau insert lolos.
--
-- FIX:
--   Izinkan channel 'Konsinyasi (Titipan)' juga di 2 policy anon
--   (INSERT with_check + SELECT using), biar konsi partner bisa order
--   via catalog — sesuai fitur phase 14 (auto_konsi_from_order).
--
-- STATUS: SUDAH di-apply langsung ke DB production (live, 2026-10-01).
--   File ini untuk dokumentasi + version control (idempotent, aman re-run).
-- ═══════════════════════════════════════════════════════════════

ALTER POLICY customer_app_insert ON public.orders
  WITH CHECK (
    (customer_nama IS NOT NULL)
    AND (length(trim(both from customer_nama)) > 0)
    AND (total_nilai > 0)
    AND (channel_sistem IN ('Findest Sport Catalog', 'Konsinyasi (Titipan)'))
  );

ALTER POLICY customer_app_read_catalog_orders ON public.orders
  USING (channel_sistem IN ('Findest Sport Catalog', 'Konsinyasi (Titipan)'));

-- ─────────────────────────────────────────────────────────
-- VERIFY — cek policy sudah update
-- ─────────────────────────────────────────────────────────
SELECT policyname, cmd,
       pg_get_expr(polwithcheck, polrelid) AS with_check,
       pg_get_expr(polqual, polrelid)      AS using_expr
FROM pg_policies pp
JOIN pg_policy po ON po.polname = pp.policyname
WHERE pp.tablename = 'orders'
  AND pp.policyname IN ('customer_app_insert', 'customer_app_read_catalog_orders');
