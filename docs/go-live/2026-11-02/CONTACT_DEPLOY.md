# Contact system: production deploy record (2026-11-02)

Project `bkdifromsqxkndnllmdj`. This record covers release checklist steps 1, 2 and 5 plus the web half of step 6 in `CONTACT_FORM_RELEASE.md`. Steps 3, 4 and 6b are **still open**; see "Open before go-live" below.

## 1. Pre-check (read-only, before any write)

- `to_regclass('public.contact_messages')` → null. `purge_contact_messages_v1()` → absent. `cron.job` 'contact-messages-retention' → 0 rows.
- Limiter RPC present: `check_concierge_rate_limit(p_kind text, p_ip text, p_window_seconds integer, p_max_user integer, p_max_ip integer)`, anon EXECUTE = true (the handler calls it through the anon client).
- History convention, from the `20261101*` rows: `version`, `name` (no version prefix), `statements` = a single element holding the whole file text (md5 of `20261101020000` = md5 of the local file `115ff4bb…`), `created_by` / `idempotency_key` / `rollback` null.
- Offline: `deno test --no-prompt supabase/functions/contact-submit/` → 39 passed, 0 failed.

## 2. Migration `20261102100000_contact_messages`

- Applied through the Management API `database/query` as the file's own `begin … commit` transaction. The history `INSERT` ran inside that same transaction, just before `commit;`, so the schema and the history row landed together. The file stays in `supabase/prepared-migrations/`, as the `20261101*` files do.
- History row: `version = 20261102100000`, `name = contact_messages`, one statement, `md5(statements[1]) = baaa7b9f7b539170ebb4aff1e1e40219` = `md5` of the local file.
- Verified after the apply:

| Check | Result |
| --- | --- |
| `relrowsecurity` | true |
| policies on `contact_messages` | 0 (on purpose: service role only) |
| anon select / insert / update / delete | false / false / false / false |
| authenticated select / insert / update / delete | false / false / false / false |
| service_role insert | true |
| table grants (`information_schema.role_table_grants`) | only `postgres` and `service_role` |
| `purge_contact_messages_v1()` EXECUTE for anon / authenticated / service_role | false / false / true |
| cron job | jobid 119, `contact-messages-retention`, `50 4 * * *`, `select public.purge_contact_messages_v1();`, active |
| rows | 0 |

## 3. Edge Function `contact-submit`

- `supabase functions deploy contact-submit --no-verify-jwt --project-ref bkdifromsqxkndnllmdj --use-api` (CLI 2.78.1). The repo has no `supabase/config.toml`, so the flag is the only place this is set.
- Live: version 1, ACTIVE, `verify_jwt: false` (Management API `GET /functions/contact-submit`), id `1df050a5-1584-413a-9a9a-6a68e9d07f1b`, deployed 2026-11-02 12:19:09 UTC. Bundle: `index.ts`, `handler.ts`, `_shared/rate_limit_gate.ts`.

## 4. Live smoke (2026-11-02 ≈12:19 UTC, `https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/contact-submit`)

| Request | Expected | Got |
| --- | --- | --- |
| POST, no Origin, no Authorization, topic `other`, email `deploy-check@lazy.space`, message "Deployment smoke test – please ignore", consent true | 200 + one row | 200 `{"ok":true}`; one row: `source = web`, `topic = other`, `user_id` null, `locale = de`, `status = new` |
| POST, honeypot `website` filled, email `deploy-check-honeypot@lazy.space` | 200, no row | 200 `{"ok":true}`; 0 rows for that address |
| POST, invalid topic / email / empty message / consent false | 400 | 400 `{"error":"invalid","fields":["topic","email","message","consent"]}` |
| OPTIONS, Origin `https://kuro.app` | allowed | 204, `Access-Control-Allow-Origin: https://kuro.app` |
| OPTIONS, Origin `https://evil.example` | not allowed | 403, no `Access-Control-Allow-*` headers |
| OPTIONS, Origin `https://kuro-legal.vercel.app` | allowed | 204, ACAO echoes the origin |
| OPTIONS, Origin = the new preview (below) | allowed (preview pattern) | 204, ACAO echoes the origin |
| POST shaped like the website (preview Origin, `apikey` + `Bearer <public anon key>`) | 200 + row, `source = web` | 200 `{"ok":true}`; row `source = web`, `user_id` null; ACAO echoes the preview origin |

Cleanup: both test rows (`a57b0453-554c-4b67-800a-f4822f89521b`, `cf2216df-3304-4ce5-a501-f16746103097`) were deleted by id/address. `select count(*) from public.contact_messages` → 0.

## 5. Legal site preview

- `cd web/legal && vercel deploy --yes`. The directory is linked to `kuro-legal` (`prj_NuioiGY23eEmnq6VIVmeO3svmrCF`) in team `lazy-53aeee76`. This was a preview only; nothing was promoted to production.
- Preview: **https://kuro-legal-rdn6zbgeb-lazy-53aeee76.vercel.app** (Ready, Preview).
- An anonymous curl gets 302 on `/kontakt` and `/impressum` because of Vercel Authentication on previews. Fetched through the Vercel MCP (`web_fetch_vercel_url`), both return **200**. `/kontakt` serves the form with `ENDPOINT = …/functions/v1/contact-submit`. `/impressum` names Max Hufschlag (Einzelunternehmen) and links `/kontakt` as the further contact channel.
- The CSP `script-src` hash in `vercel.json` (`sha256-8f5OLLXK…`) matches the sha256 of the inline script in `kontakt.html`, and `connect-src` allows exactly the function URL.

## Open before go-live (not done here, no values available to this deploy)

1. **E-mail alert (checklist step 4, required):** `RESEND_API_KEY`, `CONTACT_NOTIFY_TO`, `CONTACT_NOTIFY_FROM` are **not set** (`supabase secrets list` shows no CONTACT_* or RESEND_* names). Messages are stored, but nobody is notified, and every POST logs "e-mail notification NOT configured". After setting them, sign the Resend DPA and resolve the Resend marks in `datenschutz.html`.
2. **IP-hash secret (checklist step 3):** `CONTACT_IP_HASH_SECRET` is not set. The function falls back to the service-role key as the HMAC key, which works, but a dedicated random secret (≥ 32 bytes) is the intended state.
3. **App smoke (checklist step 6b):** send from a signed-in app build → row with `source = app` and the account's `user_id`, e-mail arrives, then delete the row.
4. **E-mail arrival for the web smoke (step 6a):** re-run once the step 4 secrets are set.
5. Record steps 1, 2, 5 and 6a as done in `CONTACT_FORM_RELEASE.md`, and update `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md` and MEMORY. Those files were intentionally left untouched by this commit.
6. Production legal-site deploy (`vercel deploy --prod`) is the owner's call once 1–4 are closed.

Rollback (from the migration header): `select cron.unschedule('contact-messages-retention'); drop function if exists public.purge_contact_messages_v1(); drop table if exists public.contact_messages;`, then `delete from supabase_migrations.schema_migrations where version = '20261102100000';` and `supabase functions delete contact-submit --project-ref bkdifromsqxkndnllmdj`.

## Follow-up hardening (2026-11-02 12:22 UTC)
- Security review: `check_concierge_rate_limit` and `rate_limit_hit` are EXECUTE-able by `anon`, so the
  guessable bucket names `contact:global`, `contact:global:notify` and `contact:user:<uuid>` could be
  filled by anyone to block the form. `b3d307f`: every bucket name is now `contact:` +
  HMAC(`CONTACT_IP_HASH_SECRET`, label), like the IP buckets. Offline tests 39/39, lint/check clean.
- `CONTACT_IP_HASH_SECRET` set (random, 48 bytes, never printed); the service-role fallback is no longer used.
- `contact-submit` redeployed with `--no-verify-jwt`. Smoke: valid web POST 200 (row deleted, table
  count 0), invalid 400 with fields. The new global bucket row is hashed; the one literal
  `contact:global` row is from the 12:20 smoke and expires with its window.
- The "leftmost x-forwarded-for is spoofable" finding does not apply on Supabase hosting (live probe,
  see STAGE4_DATA_ON.md "Client IP in Edge Functions"); the body-size finding was fixed in `c4bfb13`.
- Still open: Resend secrets (`RESEND_API_KEY`, `CONTACT_NOTIFY_TO`, `CONTACT_NOTIFY_FROM`) — messages
  are stored but nobody is e-mailed until they are set.
