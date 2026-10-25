-- ═══════════════════════════════════════════════════════════════
-- Phase 24 — Security hardening (dari audit pra-investor, 2026-10-25)
-- Semua SUDAH di-apply ke DB production. File ini buat dokumentasi +
-- version control (idempotent, aman re-run).
--
-- Sumber: Supabase security advisor + audit manual.
-- ═══════════════════════════════════════════════════════════════

-- ─── #2: Kunci fungsi SECURITY DEFINER dari role anon (publik) ───
-- Advisor nemu 22 fungsi bisa dipanggil `anon` via /rest/v1/rpc.
-- Yg bahaya: retur_from_konsi, archive_transactions_before_reset,
-- send_overdue_reminders, send_reminder_for_invoice (spam WA/biaya).
-- Cabut EXECUTE dari anon buat semua, KECUALI yg dipakai halaman publik:
--   KEEP anon → get_konsi_turnover_historical (investor dashboard),
--               is_gm & get_user_role (dipakai evaluasi RLS).
-- Trigger tetap jalan normal (trigger ga butuh grant EXECUTE ke role).
REVOKE EXECUTE ON FUNCTION public.archive_transactions_before_reset(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.auto_konsi_from_order() FROM anon;
REVOKE EXECUTE ON FUNCTION public.check_fonnte_status() FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon;
REVOKE EXECUTE ON FUNCTION public.invoice_lunas_auto_payment() FROM anon;
REVOKE EXECUTE ON FUNCTION public.konsi_rekap_after_delete() FROM anon;
REVOKE EXECUTE ON FUNCTION public.konsi_rekap_after_insert() FROM anon;
REVOKE EXECUTE ON FUNCTION public.notify_customer_new_invoice() FROM anon;
REVOKE EXECUTE ON FUNCTION public.notify_new_order_wa() FROM anon;
REVOKE EXECUTE ON FUNCTION public.orders_auto_invoice() FROM anon;
REVOKE EXECUTE ON FUNCTION public.orders_cancel_invoice() FROM anon;
REVOKE EXECUTE ON FUNCTION public.orders_stok_on_insert() FROM anon;
REVOKE EXECUTE ON FUNCTION public.orders_stok_sync() FROM anon;
REVOKE EXECUTE ON FUNCTION public.refresh_outlet_aggregates(bigint) FROM anon;
REVOKE EXECUTE ON FUNCTION public.retur_from_konsi(bigint,integer,text,text,text,bigint,text,date) FROM anon;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon;
REVOKE EXECUTE ON FUNCTION public.send_overdue_reminders() FROM anon;
REVOKE EXECUTE ON FUNCTION public.send_reminder_for_invoice(bigint) FROM anon;
REVOKE EXECUTE ON FUNCTION public.trigger_outlet_aggregates() FROM anon;

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

-- ─── CATATAN: yg TIDAK diubah di sini ───
-- • Advisor lint 0029 (authenticated bisa execute SECURITY DEFINER) SENGAJA
--   dibiarkan: authenticated = karyawan login, risiko rendah, dan revoke
--   bisa mecahin RLS/fitur CRM. Yg kritis (anon/publik) udah ditutup.
-- • Leaked password protection (HaveIBeenPwned) → toggle manual di
--   Supabase Dashboard → Auth → Policies (ga bisa via SQL).
