# AniList id readers (catalogue Task 15d inventory)

Written 2026-11-18 from the repository (`rg anilist Kuro Packages`, `rg anilist_id supabase scripts`, the latest SQL definition of every function that names the column). The plan's 2026-11-10 live inventory is the scope; this file checks it against the source. **No production query was run.** Items that only a live read-only query can settle are listed at the end.

Rule: `anilist_id` stays in the tables (crosswalk key, importer conflict key). No anon / authenticated read, matview, view or RPC returns it.

## Tables (12): column-level grants

`anime`, `manga`, `authors`, `chapters`, `characters`, `curated_rail_items`, `episodes`, `rag_entity_index`, `staff`, `studios`, `tags`, `volumes`. Migration `20261112100500` revokes table SELECT from `public`, `anon`, `authenticated` and grants every other column. Test `126` asserts the granted list equals the columns minus `anilist_id`.

## Matviews

| Matview | Action |
| --- | --- |
| `mv_anime_trending`, `mv_anime_top_rated`, `mv_manga_trending`, `mv_manga_top_rated` | rebuilt without the column (baseline definitions, unique `id` index, the baseline score/trending indexes, the `*_cold_v1` partial indexes, SELECT for anon/authenticated/service_role) |
| `mv_anime_newly_added`, `mv_manga_newly_added` | dropped (step 1c, superseded by this migration) |

Readers of the matviews: `discover_bundle` (trending and top-rated rails; the newly-added rails already read the base tables in `20261112100401`), `Kuro/Discovery/DiscoveryStore.swift:230` (`mv_anime_trending`, `.select()`: expands to the rebuilt column list). The pre-capture iOS builds that read `mv_*_newly_added` through PostgREST lose that read.

## RPCs and functions

| Function | Latest definition | Mode | Finding | Action |
| --- | --- | --- | --- | --- |
| `anime_cast_v1`, `character_voice_actors_v1`, `staff_voice_roles_v1` | `20261103100000` | invoker | return and read `anilist_id` | DROP + CREATE, same names and argument lists, no anilist columns |
| `rag_retrieve_candidates` | `20260211113000` | definer | returns `rag_entity_index.anilist_id`; sole caller is `concierge-retrieve-assist` through the **service-role** client | EXECUTE revoked from public, anon, authenticated; service_role keeps it |
| `_is_blessed_canon` | `20260802141000` | invoker | false positive: only the parameter is named `p_anilist_id`; it reads `canon_seed.media_id` | none (test 126 calls it as a client when the fixture has it) |
| `curated_rail_cards` | `20261112100400` | definer | joins `anime.anilist_id = curated_rail_items.anilist_id` inside the definer; result table has no anilist column | none (asserted) |
| `discover_bundle` | `20261112100401` | definer | same join; payload built from explicit columns | none (runtime payload asserted to contain no "anilist") |
| `discover_section_page_v1`, `discover_mood_v1`, `_discover_page_v1` | `20261112100401` | definer | joins only | none (source asserted) |
| `_release_schedule_units_v1`, `catalogue_*`, import and enrichment functions | various | definer / service | read the column inside definer or service-only code | none |
| `home_events_page_v1` | `20261101000000` | invoker | no anilist reference (the scan hit text only) | none |

`refresh_discover_matviews_v1()` is redefined for the four remaining matviews (service-only).

Views: no non-security-invoker view is affected by a column revoke (owner-run). `anime_home_resume_v1` / `manga_home_resume_v1` (security_invoker) do not name the column. A view or matview that exposes the column to a client would be a leak, not a break: test 126 asserts none exists in the fixture; the live check is query 3 below.

## App (Swift)

| File | Change |
| --- | --- |
| `Kuro/Catalog/CatalogColumns.swift` | character, staff, author embeds lose `anilist_id`; new `studioEmbed` constant |
| `Kuro/Catalog/CatalogStore.swift` | studios read uses `CatalogColumns.studioEmbed` |
| `Kuro/Catalog/CatalogCreditsModels.swift` | `Character`, `Staff`, `Studio`, `Author` lose `anilistId` |
| `Kuro/Catalog/CatalogVoiceModels.swift` | the three RPC row types lose the AniList fields; fixtures follow |
| `Kuro/Catalog/CatalogStore+ExportIdentities.swift` | identity select is `id,mal_id,title_english,title_romaji,title_native` |
| `Kuro/Views/DetailPages/ExternalLinksSection.swift` | MyAnimeList only; takes the Kuro id for telemetry (the view has no caller today) |
| `Kuro/Views/Home/SeriesDetailViews.swift`, `Kuro/Views/Routing/NavigationFixture.swift` | initialiser arguments |
| `Packages/KuroModules/.../LibraryExportInput.swift`, `LibraryExportTabular.swift` | `ExportCatalogueRow` loses `anilistId`; the Kuro CSV has 19 columns; the Kuro JSON entry has no `anilist_id` key. The MAL XML export is unaffected |

Not touched (AniList as a *source*, not a catalogue id read): the AniList list import (`Kuro/Imports`, Concierge import views, `ProfileView`), `ImagePipeline` host check, release-source copy, comments.

## Other readers found outside the app

| Reader | Client | Finding | Status |
| --- | --- | --- | --- |
| `supabase/functions/concierge-recommend/catalog_repository.ts:91` `tagIdsForAnilistIds` | **caller's anon + JWT client** | `from("tags").select("id,anilist_id").in("anilist_id", ids)`. After the revoke this errors and the function silently returns no tag ids (degraded recommendations) | **NOT fixed here; must be fixed before apply** (use the service-role client the handler already builds for `globalBudgetClient`, or a definer RPC). Needs the owner/lead decision: it is an edge-function deploy |
| `supabase/functions/concierge-recommend/catalog_repository.ts:350` | edge response of `concierge-retrieve-assist` | consumes `entity_candidates[].anilist_id` from the service-only retrieve-assist function | unchanged (service path) |
| `scripts/load/profiles/export-mal-id-lookup.js` | anon load profile mirroring the app's export read | select updated in this commit | fixed |
| `scripts/live/probe_import_workflow_v2.js:131` | owner token | selects and filters `anilist_id` | not edited (live probe, approved-probe file); would fail after apply |
| Importers, `release-intake`, `mirror-images`, `manga-chapter-enrich`, `catalogue-intake`, workers in `scripts/` | service role | keep the column | no change |
| Tests | local | `110_export_identity_lookup_plan` (identity select), `125` (identity shape), `84` (voice RPC shape) | updated |

## Live read-only queries needed (lead)

1. Effective column privileges on the 12 tables and which roles hold them:
   `select c.relname, a.attname, has_column_privilege('anon', c.oid, a.attname, 'select') anon, has_column_privilege('authenticated', c.oid, a.attname, 'select') auth from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid where n.nspname='public' and a.attname='anilist_id' and not a.attisdropped and c.relkind in ('r','m','v','p') order by 1;`
2. Matview definitions, indexes and ACLs (to confirm the rebuild matches live): `select matviewname, definition from pg_matviews where schemaname='public' and matviewname in ('mv_anime_trending','mv_anime_top_rated','mv_manga_trending','mv_manga_top_rated');` then `select tablename, indexname, indexdef from pg_indexes where schemaname='public' and tablename like 'mv\_%' order by 1,2;` and `select relname, relacl from pg_class where relname like 'mv\_%' and relkind='m';`
3. Every client-visible function whose result names an anilist column (includes functions the repository scan cannot see): `select p.oid::regprocedure, pg_get_function_result(p.oid), p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and pg_get_function_result(p.oid) ~* 'anilist' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'));`
4. Invoker functions and views whose live body reads the column: `select p.oid::regprocedure, p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and not p.prosecdef and p.prosrc ~ 'anilist_id';` and `select schemaname, viewname, definition from pg_views where schemaname='public' and definition ~ 'anilist_id';`
5. Live definitions of the three voice RPCs and `discover_bundle` (they are in `prepared-migrations`, and `pending_migrations.txt` does not list the voice file): `select pg_get_functiondef('public.anime_cast_v1(integer,text,integer)'::regprocedure);` (and the other two), and `select prosrc ~ 'mv_(anime|manga)_newly_added' from pg_proc where proname='discover_bundle';` (must be false before apply).
6. Cron commands naming the matviews: `select jobid, jobname, command from cron.job where command ~ 'mv_(anime|manga)_newly_added|refresh_discover_matviews_v1';`
7. Is the `tags` read in `concierge-recommend` still on the hot path (`pg_stat_statements` or Edge logs for `select id,anilist_id from tags`)?
8. Does any policy name the column: `select tablename, policyname, qual, with_check from pg_policies where schemaname='public' and (qual ~ 'anilist_id' or with_check ~ 'anilist_id');`
