-- ═══════════════════════════════════════════════════════════════
-- Phase 19B — Manual Reminder Button RPC
--
-- GOAL: Nadya bisa langsung klik tombol 🔔 di invoice overdue,
--       ga perlu nunggu cron jam 9 pagi.
--
-- USAGE: SELECT * FROM public.send_reminder_for_invoice(123);
--        atau dari frontend via sb.rpc('send_reminder_for_invoice', {p_invoice_id: 123})
--
-- Bypass anti-spam: manual button selalu kirim, ga peduli last_reminder_tier
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.send_reminder_for_invoice(
  p_invoice_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  inv RECORD;
  fonnte_token TEXT;
  fonnte_enabled TEXT;
  admin_wa TEXT;
  cust_wa TEXT;
  msg TEXT;
  admin_msg TEXT;
  days_overdue INT;
  target_tier INT;
  sent_cust BOOLEAN := false;
  sent_adm BOOLEAN := false;
  err_text TEXT := NULL;
  nl TEXT := chr(10);
BEGIN
  -- Ambil invoice + customer WA
  SELECT i.id, i.no_invoice, i.customer_nama, i.total, i.jatuh_tempo,
         i.status, o.customer_id, c.wa AS cust_wa
  INTO inv
  FROM public.invoices i
  LEFT JOIN public.orders o ON o.id = i.order_id
  LEFT JOIN public.customers c ON c.id = o.customer_id
  WHERE i.id = p_invoice_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Invoice tidak ditemukan');
  END IF;

  IF inv.status = 'Lunas' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Invoice sudah Lunas, ga perlu reminder');
  END IF;

  -- Cek Fonnte config
  SELECT value INTO fonnte_enabled FROM public.config WHERE key='fonnte_enabled';
  IF fonnte_enabled IS NULL OR fonnte_enabled <> 'true' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Fonnte belum di-enable di config');
  END IF;

  SELECT value INTO fonnte_token FROM public.config WHERE key='fonnte_token';
  SELECT value INTO admin_wa FROM public.config WHERE key='fonnte_admin_wa';

  IF fonnte_token IS NULL OR fonnte_token = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Fonnte token belum di-set');
  END IF;

  IF inv.cust_wa IS NULL OR inv.cust_wa = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'Customer "' || inv.customer_nama || '" belum punya nomor WA. Isi dulu di Sales > Customer.');
  END IF;

  -- Hitung days_overdue (bisa negatif kalo belum jatuh tempo — treat as tier 1)
  days_overdue := GREATEST((CURRENT_DATE - inv.jatuh_tempo)::INT, 1);

  -- Determine tier
  IF days_overdue >= 14 THEN target_tier := 3;
  ELSIF days_overdue >= 7 THEN target_tier := 2;
  ELSE target_tier := 1;
  END IF;

  -- Build message per tier
  IF target_tier = 1 THEN
    msg := '*Findest Sport - Reminder Pembayaran*' || nl || nl ||
           'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
           'Invoice berikut lewat jatuh tempo *' || days_overdue || ' hari*:' || nl ||
           '*No Faktur: ' || inv.no_invoice || '*' || nl ||
           'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
           'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl || nl ||
           'Mohon konfirmasi pembayaran ya. *Cantumkan No Faktur ' || inv.no_invoice ||
           '* saat kirim bukti transfer.' || nl || nl || 'Terima kasih.';
  ELSIF target_tier = 2 THEN
    msg := '*Findest Sport - Follow Up Pembayaran*' || nl || nl ||
           'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
           'Invoice ini sudah lewat *' || days_overdue || ' hari* dari jatuh tempo:' || nl ||
           '*No Faktur: ' || inv.no_invoice || '*' || nl ||
           'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
           'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl || nl ||
           'Mohon segera diselesaikan. Kalau ada kendala, silakan hubungi kami.' || nl || nl ||
           '*Cantumkan No Faktur ' || inv.no_invoice || '* saat kirim bukti transfer.';
  ELSE
    msg := '*Findest Sport - WARNING Pembayaran*' || nl || nl ||
           'Halo ' || COALESCE(inv.customer_nama,'Pelanggan') || ',' || nl || nl ||
           'Invoice ini sudah lewat *' || days_overdue || ' hari* dari jatuh tempo:' || nl ||
           '*No Faktur: ' || inv.no_invoice || '*' || nl ||
           'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
           'Jatuh Tempo: ' || to_char(inv.jatuh_tempo,'DD Mon YYYY') || nl || nl ||
           'Mohon segera diselesaikan. Team kami akan follow-up langsung untuk kelanjutannya.' || nl || nl ||
           '*Cantumkan No Faktur ' || inv.no_invoice || '* saat kirim bukti transfer.';
  END IF;

  -- Kirim ke customer
  BEGIN
    PERFORM net.http_post(
      url := 'https://api.fonnte.com/send',
      headers := jsonb_build_object(
        'Authorization', fonnte_token,
        'Content-Type', 'application/x-www-form-urlencoded'
      ),
      body := jsonb_build_object(
        'target', inv.cust_wa,
        'message', msg,
        'countryCode', '62'
      )
    );
    sent_cust := true;
  EXCEPTION WHEN OTHERS THEN
    err_text := SQLERRM;
  END;

  -- Kirim CC admin kalo tier >= 2 (dan tombol manual = mungkin urgent)
  IF sent_cust AND target_tier >= 2 AND admin_wa IS NOT NULL AND admin_wa <> '' THEN
    admin_msg := '[Manual Reminder T' || target_tier || '] ' || inv.no_invoice || nl ||
                 'Customer: ' || COALESCE(inv.customer_nama,'-') || nl ||
                 'Total: Rp ' || to_char(inv.total,'FM999G999G999G990') || nl ||
                 'Overdue: ' || days_overdue || ' hari' || nl ||
                 '(dikirim manual dari CRM)';
    BEGIN
      PERFORM net.http_post(
        url := 'https://api.fonnte.com/send',
        headers := jsonb_build_object(
          'Authorization', fonnte_token,
          'Content-Type', 'application/x-www-form-urlencoded'
        ),
        body := jsonb_build_object(
          'target', admin_wa,
          'message', admin_msg,
          'countryCode', '62'
        )
      );
      sent_adm := true;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  -- Update tracking kalo berhasil kirim
  IF sent_cust THEN
    UPDATE public.invoices
    SET last_reminder_sent = CURRENT_DATE,
        last_reminder_tier = GREATEST(COALESCE(last_reminder_tier,0), target_tier)
    WHERE id = inv.id;
  END IF;

  RETURN jsonb_build_object(
    'ok', sent_cust,
    'invoice_id', inv.id,
    'no_invoice', inv.no_invoice,
    'customer', inv.customer_nama,
    'wa_target', inv.cust_wa,
    'tier', target_tier,
    'days_overdue', days_overdue,
    'sent_to_customer', sent_cust,
    'sent_to_admin', sent_adm,
    'error', err_text
  );
END $$;

-- Kasih izin execute dari frontend (authenticated user)
GRANT EXECUTE ON FUNCTION public.send_reminder_for_invoice(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_reminder_for_invoice(BIGINT) TO anon;

-- Verify
SELECT 'send_reminder_for_invoice' AS item,
  CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='send_reminder_for_invoice')
       THEN '✅ RPC siap dipakai' ELSE '❌' END AS status;
