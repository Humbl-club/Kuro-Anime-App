# Kuro legal site: placeholders and open review points

**Filled on 2026-11-02 from the owner:** provider "Lazy", Martinstraße 10–12, 52062 Aachen (Nordrhein-Westfalen); email contact@lazy.space; not entered in the commercial register; supervisory authority LDI NRW. Owner does not want a phone number: a second fast contact channel (e.g. a contact form) is still needed under § 5 Abs. 1 Nr. 2 DDG. Lead defaults (review): VSBG non-participation, termination notice four weeks, no DPO (Art. 37 GDPR / § 38 BDSG). **Filled on 2026-11-02 (second pass):** legal form *Einzelunternehmen* (sole trader), owner and § 18 Abs. 2 MStV responsible person **Max Hufschlag**; the second fast contact channel is the **contact form** (`kontakt.html`, alias `/contact`, also in the app under Profile → Contact us), backed by the Edge Function `contact-submit` and the table `contact_messages` (both prepared, **not deployed** yet — see section 4). **Still open:** VAT ID if one exists; Resend e-mail notification (required for go-live, see section 4); lawyer review of the response-time wording (the "within a few working days" promise was removed from the form and the app on 2026-11-02; decide whether to state a time at all); the review items below.

Status: **DRAFT for legal review** (2026-11-02). The pages in this folder are not legal advice. A lawyer or data-protection advisor must review them before publication. The German text is the binding version; the English text is a convenience translation.

Every placeholder is shown on the pages as a yellow `[BRACKETED]` mark. None of these values were found in the repository, and none were invented.

## 1. Company details (Impressum, privacy policy, terms)

| Placeholder | Where | What to insert |
| --- | --- | --- |
| ~~`[FIRMENNAME]`~~ | all pages | **Filled:** Max Hufschlag, trading as „Lazy“ (sole trader; the person leads, the business name has no legal personality) |
| ~~`[RECHTSFORM]`~~ | all pages | **Filled:** Einzelunternehmen |
| ~~`[STRASSE HAUSNUMMER]`~~ | impressum, datenschutz, nutzungsbedingungen | **Filled:** Martinstraße 10–12 |
| ~~`[PLZ ORT]`~~ | impressum, datenschutz, nutzungsbedingungen | **Filled:** 52062 Aachen |
| ~~`[VERTRETEN DURCH]`~~ | impressum, datenschutz | **Filled:** Inhaber / Owner: Max Hufschlag (row relabelled "Inhaber"; a sole trader has no representative) |
| ~~`[E-MAIL]`~~ | all pages | **Filled:** contact@lazy.space (also DSA single point of contact and privacy contact) |
| ~~`[TELEFON]` / `[ZWEITER SCHNELLER KONTAKTWEG]`~~ | impressum, datenschutz | **Filled:** no phone; contact form `/kontakt` (§ 5 Abs. 1 Nr. 2 DDG). It only works once `contact-submit` and its migration are deployed. |
| ~~`[REGISTERGERICHT]`~~ | impressum | **Removed:** not entered in the commercial register |
| ~~`[REGISTERNUMMER]`~~ | impressum | **Removed:** not entered in the commercial register |
| `[USt-IdNr.]` | impressum | VAT ID (§ 27a UStG); remove if none exists (a Wirtschafts-ID can be added instead, if one exists) |
| ~~`[ZUSTÄNDIGE AUFSICHTSBEHÖRDE]`~~ | datenschutz | **Filled:** LDI NRW |

## 2. Additional placeholders introduced by the draft

| Placeholder | Where | What to decide or insert |
| --- | --- | --- |
| ~~`[DATENSCHUTZBEAUFTRAGTER …]`~~ | datenschutz §1 | **Filled:** statement that no DPO is required (Art. 37 DSGVO, § 38 BDSG) |
| ~~`[VERANTWORTLICH § 18 ABS. 2 MSTV – Name]`~~ | impressum | **Filled:** Max Hufschlag, Martinstraße 10–12, 52062 Aachen |
| ~~`[VSBG-ERKLÄRUNG …]`~~ | impressum, nutzungsbedingungen §15 | **Filled:** non-participation statement (§ 36 VSBG; lead default, review) |
| `[ANSCHRIFT SUPABASE laut Auftragsverarbeitungsvertrag]` | datenschutz §3 | Contracting Supabase entity and address from the signed DPA |
| `[ANSCHRIFT GROQ laut Auftragsverarbeitungsvertrag]` | datenschutz §4.4 | Groq entity and address from the DPA |
| `[Groq-DPA, Aufbewahrung und Nutzung zu Trainingszwecken …]` | datenschutz §4.4 | Groq's retention period and whether inputs are used for training (from the DPA or settings) |
| `[ggf. E-MAIL-VERSANDDIENSTLEISTER …]` | datenschutz §4.1 | Only if a custom SMTP provider (e.g. Resend) is configured in Supabase Auth. If so, give its name, location and transfer basis. If not, delete the bracket. |
| `[SUPABASE-LOG-AUFBEWAHRUNG]` | datenschutz §4.9, §8 | Retention of Supabase API, auth and edge logs on the current plan |
| `[BACKUP-AUFBEWAHRUNG]` | datenschutz §8 | Retention of database backups / PITR on the current plan |
| `[VERCEL-LOG-AUFBEWAHRUNG]` | datenschutz §4.13 | Vercel request-log retention on the current plan |
| `[prüfen und je Empfänger festlegen: DPF-Zertifizierung …]` | datenschutz §7 | For each of Groq, Supabase Inc. and Vercel: DPF certification (check dataprivacyframework.gov) and/or signed SCCs |
| `[prüfen: Anteil direkt geladener Bilder …]` | datenschutz §4.10 | Whether all cover images are mirrored to Supabase Storage. If they are, the AniList-CDN sentence can be removed. |
| `[vor Veröffentlichung gegen die produktive Konfiguration prüfen]` | datenschutz §8 | Retention periods are migration defaults (`concierge_housekeeping`, `purge_outbound_link_events`). Confirm them against the live `concierge_config`. |
| `[prüfen: Ausführungsregion der Edge Functions …]` | datenschutz §3 | Supabase Edge Functions run near the caller by default; no `x-region` pinning was found in the app. Either pin them to eu-central-1 or keep the wording. |
| `[prüfen: kürzere Frist festlegen]` | datenschutz §8 | `discover_rail_impressions` (titles shown in Discover) has no time-based purge, only deletion with the account. Decide on a retention period. |
| `[rechtlich prüfen: Einordnung unter § 25 Abs. 2 Nr. 2 TDDDG …]` | datenschutz §5 | The offline analytics-event queue on the device: decide whether it is "strictly necessary" or needs consent |
| `[ANSCHRIFT RESEND laut Auftragsverarbeitungsvertrag]` | datenschutz §4.15 | Resend entity and address from its DPA (only if e-mail notification is used) |
| `[prüfen: Resend aktiv? …]` | datenschutz §4.15, §6 | Keep the Resend paragraph/rows only if `RESEND_API_KEY`, `CONTACT_NOTIFY_TO` and `CONTACT_NOTIFY_FROM` are set for `contact-submit`; otherwise delete them |
| `[prüfen: DPF-Zertifizierung von Resend bzw. abgeschlossene SCC]` | datenschutz §7 | Transfer basis for Resend (USA) |
| ~~`[KÜNDIGUNGSFRIST …]`~~ | nutzungsbedingungen §12 | **Filled:** four weeks (lead default, review) |
| `[rechtlich prüfen: Haftungsmaßstab …]` | nutzungsbedingungen §11 | Liability clause for a free service (§§ 521, 599 BGB analog; § 307, § 309 Nr. 7 BGB) |
| `[rechtlich prüfen: §§ 327 ff. BGB …]` | nutzungsbedingungen §10 | Update obligations and permitted changes for digital products |
| `[rechtlich prüfen: Apple-Standard-EULA …]` | nutzungsbedingungen §14 | Use Apple's standard EULA, or a custom EULA containing Apple's required minimum terms |
| `[WIDERRUFSBELEHRUNG …]` | nutzungsbedingungen §16 | Whether § 312 Abs. 1a BGB applies, because personal data is used beyond contract performance (first-party analytics). If it does, add the model withdrawal notice and form. |

## 3. Facts to verify before publishing

These statements are based on the source code (as of 2026-11-02) but were not confirmed against live systems:

- **Supabase region eu-central-1 (Frankfurt).** Taken from `docs/handoffs/2026-10-05-live-service-evidence.md`. A Supabase MCP `get_project` call was refused (no permission), so the region was not re-checked live.
- **Vercel Inc. address** (440 N Barranca Ave #4133, Covina, CA 91723, USA). Check it against Vercel's DPA.
- **Groq usage.** Narration in `concierge-recommend` is optional and gated by the `llm_enabled` flag and budgets. `concierge-resolve` (Groq) is disabled per `docs/app-store-metadata.md`, so the text says "falls aktiviert". `realm-describe` sends only catalogue data to Groq. If Groq is turned off for good, remove the section.
- **MyAnimeList account connection.** Described as available "sofern in Ihrer App-Version verfügbar", because the MAL connector still requires qualification (`docs/app-store-metadata.md`).
- **Account deletion scope** follows `supabase/functions/delete-account` and `delete_user_concierge_data`. Apple token revocation is best effort and needs the authorization code from the client.
- **Release reminders** are local notifications only (`Kuro/Releases/ReminderScheduler.swift`); no push tokens are used. If remote push is added, update §4.7.
- **"Keine Werbung / kein Tracking / keine Drittanbieter-Analyse"** holds as of today (`NSPrivacyTracking = false`, no ad or analytics SDK). Re-check before every release.
- **Minimum age 16.** Germany has not used the Art. 8(1) DSGVO opening clause, so 16 applies and no BDSG paragraph is cited. Check that the App Store age rating matches.
- **No EU ODR-platform link.** The EU online dispute resolution platform (Regulation (EU) 524/2013) was discontinued in July 2025. Confirm this, and do not add the old link back.

## 4. App wiring and the contact form

- `Kuro/Views/About/KuroLegalLinks.swift`: `privacy` points to `https://kuro.app/privacy`, and `terms` is still `nil`: on 2026-11-02 `kuro.app` did not resolve (DNS), so the final domain is not confirmed. Once the site is live on the final domain, set `terms` (`/terms` redirects to `/nutzungsbedingungen#en`).
- Contact form: `kontakt.html` posts to `https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/contact-submit` with the **public** anon key (the same one the app ships). The app's Contact sheet (Profile → About → Contact us) posts to the same function with the signed-in user's session.
- **Hard release prerequisite** (owner approval; full checklist `docs/go-live/2026-11-02/CONTACT_FORM_RELEASE.md`). Do not publish these pages (the Impressum names the form as the § 5 Abs. 1 Nr. 2 DDG channel) and do not ship an app build with Profile → Contact us until, in this order: (1) `supabase/prepared-migrations/20261102100000_contact_messages.sql` (table, 12-month purge, daily cron) is applied; (2) the function is deployed with `supabase functions deploy contact-submit --no-verify-jwt --project-ref bkdifromsqxkndnllmdj`; (3) `CONTACT_IP_HASH_SECRET` (random, ≥ 32 bytes) **and** the e-mail alert `RESEND_API_KEY`, `CONTACT_NOTIFY_TO`, `CONTACT_NOTIFY_FROM` (a sender on a domain verified in Resend, Resend DPA signed) are set — the alert is **required**: nobody watches the table, and the form only counts as a fast channel if messages reach the owner promptly; then resolve the `[prüfen: Resend aktiv?]` marks; (4) the CORS list matches the live hostname (below); (5) a live smoke from the website origin and from the app is stored **and** arrives by e-mail.
- Rate limits (all per hour, keyed hash, IPv6 grouped by /64): website 5 per IP, app 30 per IP (checked before the token is verified) and 5 per account, website 200 in total (then 429), notification e-mails 50 in total (beyond that, stored without e-mail).
- Illegal-content reports (Art. 16 DSA) through the form: receipt is confirmed **by hand** by e-mail (the function sends no automatic acknowledgement, so it cannot be abused as a mail relay).
- **CSP hash:** the inline script in `kontakt.html` is allowed by `script-src 'sha256-…'` in `vercel.json`. After ANY change to that script, recompute and replace the hash, or browsers block the form:
  `python3 -c "import re,hashlib,base64;s=open('web/legal/kontakt.html').read();b=re.search(r'<script>(.*?)</script>',s,re.S).group(1);print('sha256-'+base64.b64encode(hashlib.sha256(b.encode()).digest()).decode())"`
- `connect-src` allows exactly the function URL; `form-action 'none'` stays (the form is sent by `fetch`, never natively).
