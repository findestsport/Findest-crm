-- ═══════════════════════════════════════════════════════════════
-- Phase 10 — Faktur Print Config
--
-- Seed default company info + bank details ke config table.
-- Frontend printFaktur() bakal read dari sini. Ubah value kapan aja.
-- ═══════════════════════════════════════════════════════════════

INSERT INTO public.config(key, value) VALUES
  ('company_name', 'FINDEST SPORT CEPAT SEMBUH'),
  ('company_alamat', 'Jl. Sunset Road, Basangkasa 1a., Kab. Badung, Bali'),
  ('company_telp', ''),
  ('faktur_ppn', 'on'),                    -- 'on' = tampil breakdown DPP + PPN 11%, 'off' = tanpa PPN
  ('faktur_diskon_per_item', '15000')      -- Diskon default per unit (Rp). Ubah nominal atau set '0' buat disable
ON CONFLICT(key) DO NOTHING;

-- Note: bank_nama, bank_rekening, bank_atas_nama sudah ada dari config catalog.
-- Kalo belum, insert juga:
INSERT INTO public.config(key, value) VALUES
  ('bank_nama', 'BCA'),
  ('bank_rekening', 'XXX-XXXX-XX'),
  ('bank_atas_nama', 'Nama Rekening')
ON CONFLICT(key) DO NOTHING;

-- Verify
SELECT key, value FROM public.config
WHERE key IN ('company_name','company_alamat','company_telp','bank_nama','bank_rekening','bank_atas_nama','faktur_ppn')
ORDER BY key;
