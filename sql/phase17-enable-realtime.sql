-- ═══════════════════════════════════════════════════════════════
-- Phase 17 — Enable Realtime Subscription (Investor Dashboard)
--
-- Investor Dashboard subscribe ke perubahan tabel via Supabase Realtime.
-- Setiap ada INSERT/UPDATE/DELETE di tabel yg disubscribe → dashboard
-- auto-update tanpa refresh.
--
-- Cara enable: tambahin tabel ke publication `supabase_realtime` yang
-- default sudah ada di Supabase project.
-- ═══════════════════════════════════════════════════════════════

-- Add tables to realtime publication (idempotent — safe re-run)
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.orders; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.invoices; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.payments; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.expenses; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.customers; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.konsinyasi; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.products; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- Verify
SELECT tablename FROM pg_publication_tables
WHERE pubname='supabase_realtime' AND schemaname='public'
ORDER BY tablename;
