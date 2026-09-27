-- ═══════════════════════════════════════════════════════════════
-- Phase 18 — Seed 8 Konsi Partner (Migration from Farmacare)
--
-- Bulk insert 8 apotek partner yang sebelumnya di-track via Farmacare.
-- Setelah run ini + set markup, tim bisa langsung generate QR + track
-- konsi via CRM Findest tanpa Farmacare.
--
-- Post-migration checklist:
-- 1. Verify: SELECT nama, sistem, markup_pct FROM customers WHERE sistem='Konsinyasi';
-- 2. Update PIC + no_hp per partner via CRM edit
-- 3. Generate QR per partner via qr-generator.html
-- 4. Kasih QR fisik ke tiap apotek
-- ═══════════════════════════════════════════════════════════════

-- Insert 8 apotek partner (idempotent via NOT EXISTS check)
DO $$
DECLARE
  partners TEXT[] := ARRAY[
    'APOTEK Adam','APOTEK Alvin','APOTEK Canggu','APOTEK Kawan',
    'APOTEK Sunset Farma','APOTEK Medicare','APOTEK GWS','APOTEK Linjong'
  ];
  p TEXT;
BEGIN
  FOREACH p IN ARRAY partners LOOP
    IF NOT EXISTS (SELECT 1 FROM public.customers WHERE nama = p) THEN
      INSERT INTO public.customers (nama, tipe, sistem, status, markup_pct, catatan)
      VALUES (p, 'Apotek', 'Konsinyasi', 'Aktif', 24, 'Migrated from Farmacare');
    END IF;
  END LOOP;
END $$;

-- Verify — pastiin 8 partner udah masuk
SELECT id, nama, tipe, sistem, status, markup_pct, catatan
FROM public.customers
WHERE sistem='Konsinyasi' AND catatan LIKE '%Farmacare%'
ORDER BY id;
