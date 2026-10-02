-- ═══════════════════════════════════════════════════════════════
-- Phase 23 — FIX CRITICAL: cegah self-signup jadi GM/Admin
--
-- BUG (ditemuin 2026-10-02, audit pra-investor):
--   Form daftar punya dropdown role dgn opsi "GM (Akses Semua)" + "Admin".
--   Trigger handle_new_user (on_auth_user_created) INSERT user_profiles
--   pakai COALESCE(raw_user_meta_data->>'role','staff') — percaya role
--   dari metadata (yg di-set client-side pas signUp) MENTAH-MENTAH.
--   Akibat: SIAPA AJA yg punya link CRM → Daftar → pilih "GM" → langsung
--   akses semua (keuangan, payroll, data investor, hapus data).
--   Fix client-side (initApp default 'staff') GAK ngaruh: trigger jalan
--   duluan bikin profilnya, jadi cabang staff-default gak pernah kena.
--
-- FIX (authoritative di server, gak bisa dibypass dari UI/API):
--   • user PERTAMA (user_profiles kosong)      → gm (bootstrap owner, sekali)
--   • via_invite + role karyawan aman           → role sesuai undangan
--       (safe = supervisor/sales/finance/gudang/hr/staff)
--   • selain itu (gm/admin/role palsu/walk-in)  → staff (akses minimal)
--   gm & admin TIDAK PERNAH bisa dari metadata → mentok staff.
--
-- Layer 2 (di index.html, bukan file ini):
--   • opsi GM/Admin dihapus dari dropdown daftar
--   • fallback `role || 'gm'` → `role || 'staff'` (fail-safe, bukan fail-open)
--
-- STATUS: SUDAH di-apply ke DB production (live, 2026-10-02).
--   File ini buat dokumentasi + version control (idempotent, aman re-run).
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count  bigint;
  v_meta   text    := NEW.raw_user_meta_data->>'role';
  v_invite boolean := COALESCE((NEW.raw_user_meta_data->>'via_invite')::boolean, false);
  v_role   text;
  v_divisi text;
BEGIN
  SELECT count(*) INTO v_count FROM public.user_profiles;

  IF v_count = 0 THEN
    v_role := 'gm';                         -- owner pertama (bootstrap, sekali aja)
  ELSIF v_invite AND v_meta IN ('supervisor','sales','finance','gudang','hr','staff') THEN
    v_role := v_meta;                       -- undangan sah + role karyawan aman
  ELSE
    v_role := 'staff';                      -- gm/admin/palsu/walk-in → minimal
  END IF;

  v_divisi := COALESCE(NEW.raw_user_meta_data->>'divisi',
                       CASE WHEN v_role = 'gm' THEN 'GM' ELSE initcap(v_role) END);

  INSERT INTO public.user_profiles (id, email, nama, role, divisi)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'nama', split_part(NEW.email, '@', 1)),
    v_role,
    v_divisi
  );
  RETURN NEW;
END;
$function$;

-- ─────────────────────────────────────────────────────────
-- VERIFY — simulasi keputusan role (tabel sudah berisi → non-bootstrap)
-- gm/admin harus SELALU jadi 'staff'.
-- ─────────────────────────────────────────────────────────
-- WITH s(skenario, meta_role, via_invite) AS (VALUES
--   ('walk-in pilih GM','gm',false), ('craft gm+invite','gm',true),
--   ('craft admin','admin',true),    ('walk-in finance','finance',false),
--   ('invite sales','sales',true),   ('invite supervisor','supervisor',true))
-- SELECT skenario, meta_role, via_invite,
--   CASE WHEN via_invite AND meta_role IN
--        ('supervisor','sales','finance','gudang','hr','staff')
--        THEN meta_role ELSE 'staff' END AS role_hasil
-- FROM s;
