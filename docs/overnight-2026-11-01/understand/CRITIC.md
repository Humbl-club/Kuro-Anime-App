# Completeness critique of the overnight understand reports (lane: critic)

Date: 2026-11-01. Branch `kuro/overnight-2026-11-01`. Persona: Senior QA Engineer. Read-only: no source, git, simulator or remote state changed. I made no live database queries. The only network call was a local `curl` to 127.0.0.1 ports 8803, 8799 and 8791.

Reports reviewed: `api-surface.md`, `intake.md`, `schema.md`, `sources.md`, `screens.md`, `DESIGN_RULEBOOK.md`, `auth-onboarding.md`, `product-surfaces.md`.

What I checked myself, against source:
- `Kuro/Services/FeatureFlags.swift:100-160,225-245`
- `Kuro/Views/ClubDetailView.swift:20-40`
- `Kuro/Views/TastePicksView.swift:101-102`
- a grep for `TasteDeckView(` construction
- a grep of `manga-chapter-enrich/*.ts` for `release_at`, `release_date` and `publishAt`
- the `supabase/migrations` vs `supabase/prepared-migrations` listings
- a grep for callers of `publish_mapping_revision`
- the `tools/design-directions/*.html` list
- `Kuro/Assets.xcassets`
- that `Kuro/PrivacyInfo.xcprivacy` exists
- `docs/production-blockers.md`
- localhost: **8803 = 200; 8799 and 8791 = no listener**

Labels used below:
- **BLOCKING**: the owner's goal can't be met until this is resolved.
- **FIX-IN-SPEC**: the design/spec lane must settle it before implementation.
- **[checked]**: I verified it in source.
- **[settle with]**: the one check that would decide it.

---

## 1. Gaps: asked for (or needed for "production ready") and owned by no report

### G1. BLOCKING: nothing produces series grouping, so the target "flag-on" Home world has no data path
- Product-surfaces §0 and §1.1, and rulebook §14, treat the series world as the target: Home, series detail and series Collection.
- That world reads `series`, `series_sections`, `series_entry_spans`, `mapping_revisions` and `adaptation_coverage`. All five are about 8 kB live (schema §4, product-surfaces §1.1).
- Schema's Appendix A gives their only writer as `publish_mapping_revision`. **[checked]** Nothing outside SQL calls it: there are no hits in `scripts/`, `supabase/functions/`, `tools/` or `Kuro/`.
- Intake covers `catalogue_units` (the bridge), `release_events`, `theme_links`, `detail_copy` and `artwork_materials`. It never names a producer for season or series grouping, or for `adaptation_coverage`.
- Result: even after every intake fix, series detail keeps showing "This entry is not in an approved season group." (`SeriesDetailViews.swift:157`). No lane owns this.
- The spec must choose one:
  - build a grouping producer from `media_relations` (sequel/prequel chains are already imported), or
  - ship the flag-on world with legacy fallbacks, as product-surfaces §12.2 suggests.

### G2. BLOCKING: licensing gates conflict with "take in more from our sources", and only sources.md raises them
- Sources §0 records three gates:
  - **Gate 1:** AniList terms forbid mass collection and use in "list or tracker services".
  - **Gate 2:** if Kuro is commercial at all, AnimeThemes, MangaDex and AnimeSchedule are prohibited or need permission.
  - **Gate 3:** there is no attribution surface anywhere.
- At the same time, other lanes recommend expanding exactly these sources:
  - intake §8 rec. 1, 6, 7: an AniList airing window, a MangaDex `/feed` read, and AnimeThemes;
  - schema §3.4: `theme_link_urls` from AnimeThemes;
  - product-surfaces §13: "MangaDex chapter cadence".
- Nobody reconciles the two. Kuro already calls MangaDex in production (`manga-chapter-enrich`).
- Default for tonight, reversible:
  - Build the intake behind per-source kill switches (`system_flags`).
  - Add a "Data sources" credit screen under Profile → About (Gate 3 costs nothing, so do it).
  - Prefer MangaUpdates (the permissive terms in sources §3.3) over a new MangaDex `/feed` dependency.
  - Escalate Gate 1 and Gate 2 to the owner in the morning report, verbatim.

### G3. BLOCKING: deploy authority is unresolved, and the owner's main data asks can't be met client-only
- Every lane defers backend deploys and worker scheduling to "explicit owner approval": intake §8, schema §9, api-surface §5, auth §6.5, and CLAUDE.md "prepared, NOT deployed".
- The owner's request says to work through the night "without needing any of my approval".
- Songs, next chapter, next volume and accurate next-episode freshness all need new migrations, edge or cron changes, or a scheduled worker:
  - intake §1 and §7;
  - `theme_links` is empty and its worker has "never been scheduled" (intake §2.7);
  - manga `release_events` is "structurally empty" (intake §5.3).
- No report says which changes tonight's run will **deploy** and which it will only **prepare**.
- The spec must make that call explicitly and record it. It should weigh it against the CLAUDE.md rule and against the destructive items:
  - bridge identity repair (schema P0-6);
  - placeholder deletes (schema P2-3), which write `withdrawn` events unless P0-6 lands first.

### G4. Production readiness has no lane
The owner says "ready for production". None of these was audited:
- **Privacy:** `Kuro/PrivacyInfo.xcprivacy` exists **[checked]**, but nobody compared it with the telemetry that actually runs. `InteractionTelemetry.setUserId` and `concierge_events` both exist (auth §3.2 G3). App Store privacy labels were not audited either.
- **`docs/production-blockers.md`** (2026-02-09, 72 lines) is cited by no report **[checked]**. None of its P0 and P1 items were rechecked:
  - storage bucket MIME and size limits and `storage.objects` write RLS (P0 #6–7);
  - Groq prompt injection in `concierge-resolve` / `concierge-recommend` (P1 #13);
  - `concierge-parse` / `concierge-apply` input caps (P1 #11–12);
  - pg_trgm / pg_net in the public schema;
  - leaked-password protection.
- **Supabase advisors** (`get_advisors` security and performance) were never run (no report mentions them). Nobody compared edge function `verify_jwt` settings or deployed versions with the repo.
- **Undeployed edge code:** the execution ledger says `concierge-apply`, `concierge-undo` and `delete-account` changes are "VERIFIED locally; NOT deployed" (`docs/plans/2026-10-05-modular-architecture-execution-ledger.md:78`). No report reconciles that with what the app now calls.
- **Shipped binary:** no report checks what TestFlight or the App Store actually ships compared with HEAD. Every "what users see today" claim (screens §1.1, product-surfaces §0) describes source, and product-surfaces §5 admits the installed binary may still show the Taste Deck.
- **Notification permission:** no report decides when to ask. `ReminderScheduler.requestAuthorizationIfNeeded` exists (`ReminderScheduler.swift:43-53`); auth §6.3 mentions it only as an optional "contextual primer". Reminders are anime-only (product-surfaces §1.2).
- **QA baseline:** no current unit, gate or simulator results were recorded as a baseline. Commit `3962ad1` says the gates pass; no report re-ran them.

### G5. Edge-side API calls were not inventoried ("check every single API call")
- Api-surface covers iOS → backend calls only.
- Intake covers the import and enrichment egress.
- Not covered:
  - the edge → Groq calls (cost, `sanitizeForLLM` use, retries) in `concierge-recommend`, `concierge-resolve` and `realm-describe`;
  - the edge → DB calls inside the concierge functions;
  - `concierge-retrieve-assist`, which CLAUDE.md lists as a client feature but no Swift calls (api-surface §2.3);
  - the SQL functions that only cron calls, beyond the cost table in schema §2.1.
- Realtime publication membership was not checked. LibraryRealtime and the club signals depend on `anime_user_lists`, `manga_user_lists`, `club_activity_signals` and `club_membership_signals` being in the `supabase_realtime` publication.
- **[settle with]** `select tablename from pg_publication_tables where pubname='supabase_realtime';`

### G6. Several screens have no audit or direction
- **Concierge:** 9 view files plus 3 owners. It is reachable as a sheet from Profile, `kuro://concierge` and the launch argument. Screens lists it (P7, S3) but gives it no per-screen issue list, and the rulebook gives it no direction.
- **No rulebook direction:** Browse, AddToListSheet beyond controls, the Import chooser and workflow, entity sheets, the provider sheet, and launch/bootstrap (beyond auth §6.4).
- **Button interactions** (an explicit owner ask): the rulebook §7 has a spec, but no lane audited press states or haptics per screen against it.
- **Pathways not walked end to end:**
  - club invite (`kuro://join/<code>`) → join → detail;
  - notification tap → detail;
  - sign out → sign in as a different account (onboarding is keyed per device, auth O3);
  - delete account → welcome;
  - import → Home publication.
  Product-surfaces §2 walks only Discover → detail → track → Home.

### G7. Assets: generation is allowed, but nothing is inventoried
- The owner said "if you need to generate any assets, generate them yourself".
- `Kuro/Assets.xcassets` holds `AppIcon` (one `AppIcon.png`), `AccentColor` (unset, so system blue), `KuroMark`, `KuroZenMountains`, and four unapproved imagesets plus the forbidden `KuroZenTV` **[checked]**.
- No report lists which assets the redesign needs:
  - a launch mark (`UILaunchScreen` is empty, auth §6.4);
  - onboarding stills (rulebook §14.8);
  - empty, offline and club-empty art;
  - a missing-art treatment;
  - a review of the AppIcon itself;
  - App Store screenshots, which an iPad build needs (screens H-4).
- The rulebook §11 forbids the existing unapproved assets but defines no rules for making new ones beyond "atmosphere only".

### G8. No native rendering exists, so every adaptivity claim is inferred
- Screens is "static source review only" (screens §0).
- The screen canvas is stale (2026-09-30, screens §6). The live preview at 8799 is down **[checked]**.
- The owner asked to "fix up any screen that is not adaptive". Implementation needs **before** captures from the Simulator for every pager page and major sheet, at:
  - 320, 390 and 430 pt;
  - AX5;
  - DE.
- The rulebook rendered the 8803 prototypes headlessly and then deleted the output (rulebook §2). No reference captures of the selected prototypes were kept for lanes to compare against.

### G9. The verification queries overlap and none were run
- Intake §9 (Q1–Q10) and schema §10 (Q1–Q11) duplicate each other:
  - placeholder share: intake Q7 = schema Q2;
  - bridge and queue state: intake Q3/Q5 ≈ schema Q5;
  - triggers: intake Q8 vs schema Q9;
  - airing staleness: intake Q2 ≈ schema Q8.
- Several headline claims rest on them: live flag values, row counts, cron payloads, trigger presence and airing staleness.
- Gating step: run one deduplicated, read-only query set. It should include `select flag_name, enabled, rollout_percentage from feature_flags` and `supabase migration list --linked`.

### G10. Open owner questions need reversible defaults tonight
- With the owner away, these stall implementation unless the spec picks a labelled default for each:
  - rulebook §15 (six items);
  - product-surfaces §13;
  - auth §8;
  - screens H-4 (iPad or landscape);
  - sources §6.
- Examples:
  - lock iPhone to portrait and keep iPad in max-width containers;
  - keep the One Thing hero;
  - keep the 2-column manga layout;
  - neutral `#222222` club room.

### G11. No single "next event" contract
Each report proposes a different delivery shape:
- api-surface P2: `user_release_schedule_v1`;
- schema P1-1: a `next_release` object in `series_detail_bundle_v1`;
- sources §5.5: a per-detail RPC with `{last_unit, next_unit{at, precision, certainty, source}}`;
- product-surfaces §11: a `next_event` on `collection_series_page_v1` / `collection_feed_page` plus the Discover airing rows.

The spec needs one projection and one contract that Home, detail, list rows, Discover "airing today", Clubs and reminders all read.

---

## 2. Contradictions and unverified claims across reports

### C1. Does the missing `feature_flag_overrides` table matter? schema §0 vs api-surface headline 2
**Verdict: api-surface is right about the mechanism [checked].**
- Schema says the impact "is just one wasted request".
- In code, a PostgREST error (not a `URLError`) falls into the generic `catch` at `FeatureFlags.swift:~146`. That calls `removeHomeCohort`, which sets `foundationHydrated = false` (`:238-242`), and `seriesHomeNativeV1Enabled` requires that flag.
- Visible impact only appears when the series flags are on. If live is 0% (screens §1.1, product-surfaces §0), there is no tab flip today.
- But this table is also the only per-account path to turn on the target Home. Without it, Home can only be rolled out globally.
- The fixes conflict too:
  - schema P2-7 wraps the read in `#if DEBUG`, which kills per-account cohorts;
  - api-surface P0 treats `PGRST205` / 404 as "no overrides" without touching the cohort.
- Use api-surface's fix.

### C2. Do chapter and volume release dates exist? api-surface §6 / P2 and product-surfaces §1.2, §13 vs intake §2.2–2.3, §5.3–5.4 and schema §3.1
**Verdict: they don't exist. Intake and schema are right [checked].**
- Api-surface proposes a release RPC over `chapters.release_at` and `volumes.release_at` "because the tables already exist". Product-surfaces says "MangaDex chapter cadence is already ingested into `chapters`".
- In fact:
  - `manga-chapter-enrich` never writes `release_at`, `release_date` or `publishAt` (grep found 0 hits);
  - chapters hold numbers or placeholders only;
  - volumes hold placeholders only;
  - `manga.next_chapter_*` is forced to null.
- Any release RPC returns nothing for manga until the intake changes (MangaUpdates or MangaDex feed dates).

### C3. Three incompatible ways to model "estimated" dates
| Report | Proposal |
|---|---|
| sources §2 | Compute estimates at read time and never store them; or add a `certainty` column |
| schema §3.4 | Store `basis='projected_cadence'` plus `confidence`, with no new status |
| intake §5.3 | A new status value or a convention |

The design side disagrees as well:
- rulebook §9: "never invent a cadence", show "Dates to come";
- sources §3.3: allows "Usually weekly · next expected around Sun 9 Nov" when the cadence is regular;
- product-surfaces §6.2 and §11: shows date-stamps like "Ch 141 · Nov 14" with no certainty label.

Fractional chapters have two proposals too: schema P1-6 adds `number_decimal`, while sources §2 changes the column to `numeric` or adds `number_text`. Volume territory and edition (sources §2, §3.4) are missing from schema's additive migration.

Pick one model and apply it everywhere.

### C4. Can songs carry verified music links? schema §3.4 (`theme_link_urls`) and intake §2.7 / §8.7 vs sources §3.1
- Schema and intake recommend fetching AnimeThemes song resources to get verified Spotify and Apple Music links.
- Sources' live test shows `animethemes.song.resources` returned `[]`, and Spotify's terms forbid storing Spotify content.
- Sources says to use search URLs, built on device, for both Apple Music and Spotify.
- The UI only links to Spotify today (screens S7). The rulebook §14.2 mentions only "Find on Spotify".
- Intake also reports AnimeThemes returning 403 (September). Sources got 200 tonight at 90 requests/min, and found that the JSON:API the worker uses is **deprecated**. Intake doesn't mention the deprecation.

### C5. What is actually deployed? schema §0 / api-surface §2.1 vs sources §1 / §6 vs the ledger and CLAUDE.md
- `supabase/migrations/` holds **246** files. Schema says 245; CLAUDE.md says 235 plus 3 prepared.
- `supabase/prepared-migrations/` holds **14** files. **[checked]** Nine of them (`20261005*`) are byte-identical copies of files in `migrations/`.
- Schema and api-surface infer that the `20261005*` set is live because its signal tables appear in `table-stats`. The execution ledger says "prepared club RLS migrations … NOT deployed".
- Sources §1 and §6 Q3 call the `20261007040000` status an unexplained discrepancy. Intake and schema resolve it from the approved deployment receipt.
- **[settle with]** `supabase migration list --linked`, run once.

### C6. Club detail tab names: screens S16 and rulebook §14.7 vs product-surfaces §8
**Verdict: product-surfaces is right [checked].**
- Code: `ClubDetailView.swift`, `case rails = "RAILS"`, `active = "ACTIVE"`, `polls = "POLLS"`.
- Screens and the rulebook say "Rails / This Week / Polls", which is stale (it was copied from CLAUDE.md).

### C7. Taste calls and dead code: api-surface §3.10 T1–T3 vs screens §2.4 and product-surfaces §5
**Verdict: api-surface lists dead calls and misses live ones [checked].**
- `TasteDeckView` is never constructed.
- Api-surface lists `fetch_taste_deck_batch`, `fetch_my_taste_profile` + `realm_meta`, and `record_taste_deck_signal` as live, all triggered from that view.
- It leaves out the live `TastePicksView:101-102` calls:
  - `fetch_because_you_rail(limit 8)`, unconditional, even though api-surface D3 calls it "0%-gated";
  - a third `discover_bundle(limit 12)`, which also writes impressions and so adds to headline 3.
- The bootstrap estimate "about 10–13 requests" (api-surface §3.2) undercounts by this amount.

### C8. Proposals that touch frozen or restricted surfaces: auth-onboarding §6.2–6.3 vs rulebook §8, §13 #16, §14.8
- **Welcome screen:** auth adds an "I already have an account" button, makes "Get started" go to Create account, and changes the welcome copy. The rulebook freezes the welcome composition and says not to change it (the headline is OPEN).
- **Onboarding motion:** auth's onboarding "Arrival" step uses the animated `KuroSceneryLoop`. The rulebook allows ambient drift only on welcome and the empty-Home invitation, and asks for scenery **stills** in onboarding.
- **Onboarding content:** auth's step 4 "opens the Taste Deck (existing flag `tasteDeckV1Enabled`)". That view is dead (C7). The rulebook proposes either at most 3 frames (Home, Find/Import, Clubs) or dropping onboarding.
- Auth's flow change ("Get started" → sign-up) is a behaviour fix, so it can probably be made without altering the composition. The spec must say so explicitly.

### C9. Live pager and flag state are asserted inconsistently, and nobody queried them
- Rulebook §14.8 calls `[.taste, .home, .discover, .collection, .clubs]` "the live series-home pager".
- Screens §1.1 and product-surfaces §0 say that order is debug-only, and that production gets `Taste ← Discover → Browse → Collection → Clubs`, based on a value recorded on 2026-10-08.
- Api-surface §1 says the live value is unknown.
- `table-stats` shows a stale estimate of 2 rows for `feature_flags`.
- **[settle with]** the `feature_flags` select in G9.

### C10. Localization strategy
- Screens H-6: move to a String Catalog.
- Rulebook §10: use the existing inline `isGerman ? … : …` pattern.
- Auth §6.2: add a shared `KuroLocale.isGerman` helper, because two different locale checks exist (auth U16).

Choose one for tonight (the rulebook pattern plus the shared helper is the least risky) and note the String Catalog as follow-up.

### C11. iPad and landscape
- Screens H-4: a decision is needed; dropping iPad is the fastest path.
- Auth §6.2: lock iPhone to portrait; iPad keeps every orientation.
- Rulebook §5 and §16: requires iPad verification for every screen.

### C12. Which lists concept to build
- Product-surfaces §11: build "Folio Ledger" in both Profile and Collection, with Contact Sheet as a density toggle and Almanac later. It also leaves open whether Collection stays a pager page.
- Rulebook §14.3–14.4: a Profile shelf preview (a row of covers per status) and a Shelf/Index toggle in Collection.

These are compatible, but not the same. Both need cover, total and next event on the series rows, which is a backend change (product-surfaces §11) and depends on G3.

### C13. Smaller discrepancies (all unverified estimates)
- `manga_source_links`:
  - intake §2.3 says "a few thousand rows at most";
  - schema §2.3 says "45 rows / ~45 mapped titles";
  - `table-stats` shows a reltuples of 45 against 200 kB.
  - Both readings rest on a stale estimate; settle with `count(*)`.
- Airing-window sync:
  - intake §8.1: a +14 d window at 2–6 pages per run;
  - sources §5.1: +8 d at 10–20 pages.
- Whether AniList `updatedAt` changes on every episode:
  - intake §2.1 says roughly every episode (impact inferred);
  - schema §3.5 says UNVERIFIED.
  - The fast path refreshes `next_airing_at` anyway, so this matters only for the synopsis-reset churn.
- `fetch_my_clubs_*`:
  - product-surfaces §8 names `fetch_my_clubs_enriched` as the data call;
  - api-surface K1 shows `fetch_my_clubs_loading` as primary, with enriched only as a catch-all fallback.
  - Api-surface matches the code it cites.
- Volumes:
  - product-surfaces §1.1: "probably populated";
  - schema and intake: placeholders only.
  - Q2 in schema §10 settles it.

---

## 3. Coverage verdict per owner ask

| Owner ask | Covered by | Verdict |
|---|---|---|
| Every API call | api-surface (iOS) and intake (import egress) | Partial: edge → Groq / DB calls, realtime publication and Taste calls are wrong or missing (G5, C7) |
| Every intake path | intake, sources | Good. Licensing not reconciled (G2) |
| All tables | schema (132 tables) | Good for tables. Storage buckets, advisors and views beyond two were not checked (G4) |
| Songs, next episode / chapter / book | intake, sources, schema, product-surfaces | Diagnosed, but no agreed model (C3, C4, G11), no deploy authority (G3), and no series producer (G1) |
| Optimize tables / intake / delivery | schema §9, intake §8, api-surface §5 | Good backlog. Ordering depends on G3, and P0-6 must land before any backfill |
| Every screen on localhost | rulebook §2 (8803 fetched, all 21 pages classified) | Done for 8803. 8799 and 8791 are down. No reference captures kept (G8) |
| Adaptive, on-brand Home, Discover, Clubs, Profile + lists | screens, rulebook, product-surfaces | Static only (G8). Discover, Clubs and lists are extrapolation. Defaults needed (G10) |
| Onboarding and sign-in perfect, branded | auth-onboarding, rulebook | Good diagnosis. Conflicts in C8. Assets missing (G7) |
| Button interactions | rulebook §7 (spec only) | Not audited (G6) |
| Every pathway makes sense | product-surfaces §2 | One pathway only (G6) |
| Production ready | none | No lane (G4) |
