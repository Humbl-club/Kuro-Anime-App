# Contact form: hard release prerequisite (2026-11-02)

The Impressum (`web/legal/impressum.html`) names the contact form as the second fast contact channel under § 5 Abs. 1 Nr. 2 DDG, and the app has had **Profile → Contact us** since TestFlight build 20. Both post to the Edge Function `contact-submit`, which is **prepared, not deployed**. Until every step below is done, an in-app send returns 404 (or 500 when the function is live and the table is not), and the website form shows "Senden fehlgeschlagen".

**Rule:** do not publish the legal site and do not submit an app build for review until steps 1–6 are done and recorded here. TestFlight builds that already contain the sheet show the e-mail address (contact@lazy.space) in the form and in every failure notice, so no user is left without a working channel.

| # | Step | Command / where | Done (date, by) |
| --- | --- | --- | --- |
| 1 | Apply the table migration | `supabase/prepared-migrations/20261102100000_contact_messages.sql` (table, 12-month purge, daily cron). Local proof: `scripts/db/run_local_db_tests.sh --only 93_contact_messages` | |
| 2 | Deploy the function without gateway JWT check | `supabase functions deploy contact-submit --no-verify-jwt --project-ref bkdifromsqxkndnllmdj` | |
| 3 | Set the IP-hash secret | `CONTACT_IP_HASH_SECRET` (random, at least 32 bytes) | |
| 4 | Set the e-mail alert (**required**) | `RESEND_API_KEY`, `CONTACT_NOTIFY_TO` (owner inbox), `CONTACT_NOTIFY_FROM` (sender on a domain verified in Resend). Sign the Resend DPA; then resolve the `[prüfen: Resend aktiv?]` / `[ANSCHRIFT RESEND …]` marks in `datenschutz.html`. Without it, messages land in a table nobody watches and the function logs an error on every request. | |
| 5 | CORS matches the live hostname | `ALLOWED_ORIGINS` in `supabase/functions/contact-submit/handler.ts` includes the hostname the legal site is served from (today `https://kuro-legal.vercel.app`); `KuroLegalLinks.legalSiteBase` in the app points to the same host. | |
| 6 | Live smoke, both channels | (a) Submit on `<legal site>/kontakt` → 200, row in `contact_messages` with `source = 'web'`, e-mail arrives in `CONTACT_NOTIFY_TO`. (b) Submit from the app (signed in) → "Message sent", row with `source = 'app'` and the account's `user_id`, e-mail arrives. (c) Delete both test rows. | |

## Limits the function enforces (for the smoke and for support questions)

All per hour, IP keys are a keyed hash, IPv6 grouped by /64:

- website: 5 per IP (kind `contact`), 200 in total (kind `contact_global`, then 429);
- app: 30 per IP, checked before the token is verified (kind `contact_app_ip`), and 5 per account (kind `contact_user`);
- notification e-mails: 50 in total (kind `contact_notify`); beyond that the message is stored without an e-mail.

## Handling

- Reports of illegal content (topic `report_content`, Art. 16 DSA): the reporter gets a confirmation of receipt **by hand**, by e-mail (Terms section 7 promises it). The function sends no automatic acknowledgement on purpose: mailing an address the sender typed in would make the form a spam relay.
- Response time: the form and the app no longer promise "within a few working days". Whether to state a time at all is a lawyer-review item (`web/legal/PLACEHOLDERS.md`).
