# Kuro legal site: placeholders and open review points

Status: **DRAFT for legal review** (2026-11-02). The pages in this folder are not legal advice. A lawyer or data-protection advisor must review them before publication. The German text is the binding version; the English text is a convenience translation.

Every placeholder is shown on the pages as a yellow `[BRACKETED]` mark. None of these values were found in the repository, and none were invented.

## 1. Company details (Impressum, privacy policy, terms)

| Placeholder | Where | What to insert |
| --- | --- | --- |
| `[FIRMENNAME]` | all pages | Registered company name |
| `[RECHTSFORM]` | all pages | Legal form (e.g. GmbH, UG (haftungsbeschränkt), Einzelunternehmen) |
| `[STRASSE HAUSNUMMER]` | impressum, datenschutz, nutzungsbedingungen | Street address that can receive service of process (no P.O. box) |
| `[PLZ ORT]` | impressum, datenschutz, nutzungsbedingungen | Postcode and city |
| `[VERTRETEN DURCH]` | impressum, datenschutz | Managing director(s) / authorised representative(s) |
| `[E-MAIL]` | all pages | Contact email. It also serves as the DSA single point of contact and the privacy contact. |
| `[TELEFON]` | impressum, datenschutz | Phone number, or another fast direct contact channel (§ 5 Abs. 1 Nr. 2 DDG) |
| `[REGISTERGERICHT]` | impressum | Register court (e.g. Amtsgericht …); remove if not registered |
| `[REGISTERNUMMER]` | impressum | Commercial register number (HRB/HRA …); remove if not registered |
| `[USt-IdNr.]` | impressum | VAT ID (§ 27a UStG); remove if none exists (a Wirtschafts-ID can be added instead, if one exists) |
| `[ZUSTÄNDIGE AUFSICHTSBEHÖRDE]` | datenschutz | Data-protection authority of the federal state of the company seat (name, address, website) |

## 2. Additional placeholders introduced by the draft

| Placeholder | Where | What to decide or insert |
| --- | --- | --- |
| `[DATENSCHUTZBEAUFTRAGTER …]` | datenschutz §1 | DPO contact, or a statement that no DPO is required (Art. 37 DSGVO, § 38 BDSG) |
| `[VERANTWORTLICH § 18 ABS. 2 MSTV – Name]` | impressum | Person responsible for editorial content (curated rails and copy), with address |
| `[VSBG-ERKLÄRUNG …]` | impressum, nutzungsbedingungen §15 | Statement under § 36 VSBG (participation in consumer arbitration: yes or no). Required if the company has more than 10 employees or has terms of use; including it is harmless either way. |
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
| `[rechtlich prüfen: Einordnung unter § 25 Abs. 2 Nr. 2 TDDDG …]` | datenschutz §5 | The offline analytics-event queue on the device: decide whether it is "strictly necessary" or needs consent |
| `[KÜNDIGUNGSFRIST …]` | nutzungsbedingungen §12 | Ordinary notice period for termination by the provider |
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

## 4. App wiring (not changed by this commit)

- `Kuro/Views/About/KuroLegalLinks.swift`: `privacy` points to `https://kuro.app/privacy`, and `terms` is `nil`. Once the site is live on the final domain, set both URLs (`/privacy` redirects to `/datenschutz#en`, and `/terms` redirects to `/nutzungsbedingungen#en`). Optionally add an Impressum link in Profile → About.
