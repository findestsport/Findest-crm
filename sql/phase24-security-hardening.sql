-- ═══════════════════════════════════════════════════════════════
-- Phase 24 — Security hardening (dari audit pra-investor, 2026-10-25)
-- Semua SUDAH di-apply ke DB production. File ini buat dokumentasi +
-- version control (idempotent, aman re-run).
--
-- Sumber: Supabase security advisor + audit manual.
-- ═══════════════════════════════════════════════════════════════

-- ─── #2: Kunci fungsi SECURITY DEFINER dari role publik (anon) ───
-- Advisor nemu 22 fungsi bisa dipanggil `anon` via /rest/v1/rpc.
-- PENTING: EXECUTE default di-grant ke PUBLIC, dan anon INHERIT dari PUBLIC —
-- jadi REVOKE ... FROM anon doang GA NGEFEK. Harus REVOKE ... FROM PUBLIC,
-- baru GRANT balik ke authenticated buat fungsi yg dipanggil CRM saat login.
--
-- Hasil akhir (diverifikasi via has_function_privilege):
--   anon bisa EXECUTE cuma: get_konsi_turnover_historical (investor),
--   is_gm & get_user_role (RLS). Sisanya anon = FALSE.

-- 1) Cabut default PUBLIC execute
REVOKE EXECUTE ON FUNCTION public.archive_transactions_before_reset(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.auto_konsi_from_order() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_fonnte_status() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.invoice_lunas_auto_payment() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.konsi_rekap_after_delete() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.konsi_rekap_after_insert() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_customer_new_invoice() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_new_order_wa() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.orders_auto_invoice() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.orders_cancel_invoice() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.orders_stok_on_insert() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.orders_stok_sync() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.refresh_outlet_aggregates(bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.retur_from_konsi(bigint,integer,text,text,text,bigint,text,date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.send_overdue_reminders() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.send_reminder_for_invoice(bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trigger_outlet_aggregates() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_konsi_turnover_historical(integer) FROM PUBLIC;

-- 2) Grant balik ke authenticated (dipanggil CRM saat login + utility aman).
--    13 fungsi trigger murni TIDAK di-grant — trigger tetap jalan tanpa EXECUTE grant.
GRANT EXECUTE ON FUNCTION public.retur_from_konsi(bigint,integer,text,text,text,bigint,text,date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_reminder_for_invoice(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_overdue_reminders() TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_transactions_before_reset(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_fonnte_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_outlet_aggregates(bigint) TO authenticated;

-- 3) get_konsi_turnover_historical: investor (anon) + CRM (authenticated)
GRANT EXECUTE ON FUNCTION public.get_konsi_turnover_historical(integer) TO anon, authenticated;

-- ─── #5: View ED alert jangan SECURITY DEFINER ───
-- Advisor level ERROR. View ini cuma dibaca CRM (authenticated) yg udah
-- punya akses RLS ke batches/konsinyasi → aman jadi security_invoker.
ALTER VIEW public.ed_alert_all     SET (security_invoker = true);
ALTER VIEW public.ed_alert_summary SET (security_invoker = true);

-- ─── #8: Lock search_path di fungsi SECURITY DEFINER ───
-- Cegah search_path injection (advisor WARN).
ALTER FUNCTION public.retur_from_konsi(bigint,integer,text,text,text,bigint,text,date) SET search_path = public, pg_temp;
ALTER FUNCTION public.auto_konsi_from_order() SET search_path = public, pg_temp;
ALTER FUNCTION public.archive_transactions_before_reset(text) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_konsi_turnover_historical(integer) SET search_path = public, pg_temp;

-- ─── CATATAN: yg SENGAJA TIDAK diubah ───
-- • Advisor lint 0029 (authenticated bisa execute SECURITY DEFINER) dibiarkan:
--   authenticated = karyawan login, risiko rendah, revoke bisa mecahin RLS/CRM.
--   Yg kritis (anon/publik) udah ditutup.
-- • is_gm & get_user_role tetap bisa anon/authenticated — dipakai evaluasi RLS.
-- • Leaked password protection (HaveIBeenPwned) → toggle manual di
--   Supabase Dashboard → Authentication → Policies (ga bisa via SQL).

-- ─── VERIFY ───
-- SELECT p.proname, has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.prosecdef
-- ORDER BY anon_can DESC, p.proname;
