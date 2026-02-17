# Kuro — Current State of the Application (Authoritative, Technical)

**Last updated:** 2026-02-17

This document is the **authoritative, technical snapshot** of the Kuro app (iOS client + Supabase backend) and the current codebase. It is written for engineers and LLMs that need a complete and precise understanding of how the system works today.

For a non‑technical version, see: `CURRENT_APP_STATE_PLAIN.md`.

---

## 0) RULES: This file must always be updated

This file is a **contract**. It must be updated **after every single change** to the app or backend.

**Update protocol (required):**
1. Update the relevant sections in this file immediately after any change (UI, backend, schema, edge functions, scripts, cron jobs, ops, performance, etc.).
2. Add a new entry to the **Change Log** section with:
   - Date
   - Brief summary of changes
   - Commit hash(es)
3. If you are unsure where a change belongs, add a note under **Open Questions / Unknowns**.
4. If you are making changes for a new chat/LLM, this file must be the **first reference** and must reflect the current state.
5. After changes, refresh the auto-generated sections:
   ```bash
   node scripts/generate_app_state_inventory.js
   node scripts/generate_app_state_maps.js
   node scripts/generate_app_state_sources.js
   node scripts/generate_app_state_codebase_bundle.js
   # Optional (requires SUPABASE_SERVICE_ROLE_KEY + deployed admin_schema_snapshot RPC):
   node scripts/generate_app_state_live_snapshot.js
   ```

**Failure to update this file = incorrect system state.**

---

## 1) High-level architecture

**Client:** iOS SwiftUI app (`/Kuro`)
- Local caching and UI-only state.
- Uses Supabase as system of record.
- Concierge: deterministic-first parsing + LLM fallback.
- Apple Foundation Models: on-device LLM for mode classification, disambiguation, synopsis condensation, and NL collection search (iOS 26+ only; graceful fallback via `StubFMProvider`).
- Network monitoring: `NetworkMonitor` tracks connectivity, shows offline banner.

**Backend:** Supabase (Postgres + Edge Functions + Storage + RPC + RLS)
- Postgres stores anime/manga catalog, user lists, recommendations, concierge sessions, clubs, and ops metrics.
- Edge Functions handle bulk imports, concierge operations (parse/resolve/recommend/apply/undo), and image mirroring.
- Storage provides CDN for mirrored images (public bucket).

**Primary data source:** AniList (imported via scripts + edge functions).

---

## 1.1) Configuration + secrets (where keys live)

### iOS app config
- `Kuro/Services/AppConfig.swift` reads:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
  from **Info.plist** or process env.
- If missing, `SupabaseService` uses **hardcoded fallback** URL + anon key (see `SupabaseService.init()`).
- **xcconfig files** (for future env-based builds):
  - `Config/Shared.xcconfig` — shared settings
  - `Config/Debug.xcconfig` — debug overrides
  - `Config/Release.xcconfig` — release overrides

### Supabase Edge Functions env vars
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GROQ_API_KEY` (LLM)
- `GROQ_MODEL`, `GROQ_MODEL_RESOLVE` (LLM models)
- `IMPORT_SECRET` — shared secret for bulk-import auth (pg_cron/pg_net can't send JWTs; verified via `x-import-secret` header)

### LLM flags
- `public.system_flags` controls `llm_enabled` (on/off)
- Budgets + rate limits in `public.concierge_config` (JSON)

---

## 2) Repository map (where things live)

### Root
- `Kuro/` — iOS app source (SwiftUI views, services, models)
- `supabase/` — Supabase migrations, edge functions, ops docs
- `scripts/` — import scripts, audits, load tests, ops tools
- `mockups/` — UI references
- `BROWSE_REFINED_SUMMARY.md`, `MASTER_PLAN.md`, `COMPLETE_APP_DOCUMENTATION.md` — historical docs

<!-- BEGIN AUTO-INVENTORY -->

## 2.1) Auto-generated inventory (exhaustive file lists)

Generated: **2026-02-05T17:59:23.062Z**  (git: `ca671d5` on `main`)

This section is auto-generated. Rebuild it after any repo change:
```bash
node scripts/generate_app_state_inventory.js
```

### iOS (Swift) files (count: 63)
- `Kuro/ContentView.swift`
- `Kuro/Design/Color+Hex.swift` *(hex color utility)*
- `Kuro/Design/KuroDesignSystem.swift`
- `Kuro/KuroApp.swift`
- `Kuro/Models/DiscoverBundle.swift`
- `Kuro/Models/SupabaseModels.swift`
- `Kuro/Services/AppleFMService.swift` *(Apple Foundation Models — on-device classification, disambiguation, synopsis condensation, collection search intent)*
- `Kuro/Services/AppConfig.swift`
- `Kuro/Services/ConciergeAnalytics.swift` *(concierge telemetry + interaction tracking)*
- `Kuro/Services/DeepLinkRouter.swift` *(deep link parsing for kuro:// scheme — anime, manga, club, collection, discover, concierge routes)*
- `Kuro/Services/FeatureFlags.swift` *(feature flag definitions for staged rollout — clubs, concierge, realtime)*
- `Kuro/Services/ImagePipeline.swift`
- `Kuro/Services/KuroDiskDetailCache.swift`
- `Kuro/Services/KuroPerf.swift`
- `Kuro/Services/NetworkMonitor.swift` *(NWPathMonitor-based connectivity tracking, @Environment injection, offline banner)*
- `Kuro/Services/SupabaseRPCParams.swift`
- `Kuro/Services/SupabaseService.swift`
- `Kuro/Services/TextNormalization.swift` *(text normalization utilities for search/parsing)*
- `Kuro/Views/AuthView.swift`
- `Kuro/Views/BrowseView.swift`
- `Kuro/Views/Cards.swift`
- `Kuro/Views/ClubCreateSheets.swift` *(create/join club sheet UI)*
- `Kuro/Views/ClubDetailView.swift`
- `Kuro/Views/ClubsView.swift`
- `Kuro/Views/Collection/CollectionManagementView.swift`
- `Kuro/Views/ConciergeActionFooter.swift` *(concierge action footer bar)*
- `Kuro/Views/ConciergeComponents.swift` *(shared concierge UI components, curated copy layer)*
- `Kuro/Views/ConciergeComposerDock.swift` *(concierge input composer dock)*
- `Kuro/Views/ConciergeEditorialShell.swift` *(editorial shell wrapper for concierge page)*
- `Kuro/Views/ConciergeImportCards.swift` *(import preview/confirm card components)*
- `Kuro/Views/ConciergeInputField.swift` *(concierge text input field)*
- `Kuro/Views/ConciergeIntentDeck.swift` *(quick-action intent deck for concierge)*
- `Kuro/Views/ConciergeRecommendationRails.swift` *(recommendation rail rendering)*
- `Kuro/Views/ConciergeResponseStage.swift` *(concierge response stage rendering)*
- `Kuro/Views/ConciergeView.swift`
- `Kuro/Views/CountdownTimer.swift`
- `Kuro/Views/DetailPages/AnimeDetailView.swift`
- `Kuro/Views/DetailPages/ClubActivitySection.swift`
- `Kuro/Views/DetailPages/ExternalLinksSection.swift` *(streaming/source link section on detail pages)*
- `Kuro/Views/DetailPages/MangaDetailView.swift`
- `Kuro/Views/DetailPages/MediaDetailSheet.swift`
- `Kuro/Views/DiscoverView.swift`
- `Kuro/Views/DiscoverViewModel.swift`
- `Kuro/Views/EditorialCards.swift`
- `Kuro/Views/EditorialCollectionView.swift`
- `Kuro/Views/EditorialDiscoverView.swift`
- `Kuro/Views/EditorialSearchView.swift`
- `Kuro/Views/GenreHubView.swift`
- `Kuro/Views/KuroCachedAsyncImage.swift`
- `Kuro/Views/KuroCardText.swift`
- `Kuro/Views/KuroConciergeMark.swift`
- `Kuro/Views/KuroGlass.swift`
- `Kuro/Views/KuroInteractionEnvironment.swift`
- `Kuro/Views/KuroLoadMoreSentinel.swift`
- `Kuro/Views/KuroPagingGesture.swift`
- `Kuro/Views/KuroRefinedCard.swift`
- `Kuro/Views/KuroToast.swift`
- `Kuro/Views/KuroTransientBanner.swift`
- `Kuro/Views/OnboardingView.swift` *(first-launch onboarding flow)*
- `Kuro/Views/ProfileView.swift`
- `Kuro/Views/SearchView.swift`
- `Kuro/Views/SearchViewModel.swift`
- `Kuro/Views/UIComponents.swift`

### Supabase migrations (count: 88)
- `supabase/migrations/20250109_remote_applied_placeholder.sql` *(baseline schema SQL; already applied in production migration history; used for fresh project bootstrap)*
- `supabase/migrations/20250909_remote_applied_placeholder.sql`
- `supabase/migrations/20250917_remote_applied_placeholder.sql`
- `supabase/migrations/20260203171100_concierge_core.sql`
- `supabase/migrations/20260203171110_concierge_title_search_rebuild.sql`
- `supabase/migrations/20260203181000_profiles_insert_policy.sql`
- `supabase/migrations/20260203183000_concierge_recommend_rpc.sql`
- `supabase/migrations/20260203190000_editorial_recommend_engine.sql`
- `supabase/migrations/20260203191500_recommend_focus_tags.sql`
- `supabase/migrations/20260203194500_recommend_focus_filter.sql`
- `supabase/migrations/20260203201000_editorial_story_boosts.sql`
- `supabase/migrations/20260203203000_recommend_seed_similarity.sql`
- `supabase/migrations/20260203223000_scale_perf_bundle_and_indexes.sql`
- `supabase/migrations/20260203224500_browse_rpc_add_created_at.sql`
- `supabase/migrations/20260203233500_mirror_runs.sql`
- `supabase/migrations/20260203235500_search_rpc_keyset.sql`
- `supabase/migrations/20260204010500_collection_paging_rpc.sql`
- `supabase/migrations/20260204124500_title_aliases.sql`
- `supabase/migrations/20260204133000_collection_feed_paging_rpc.sql`
- `supabase/migrations/20260204221500_concierge_rate_limits_and_llm_budgets.sql`
- `supabase/migrations/20260204233000_recommend_seed_similarity_allow_anon.sql`
- `supabase/migrations/20260204233010_concierge_ops_observability_and_retention.sql`
- `supabase/migrations/20260204234500_recommend_seed_similarity_ranked_tags.sql`
- `supabase/migrations/20260204235500_recommend_seed_similarity_genre_gate.sql`
- `supabase/migrations/20260204240500_backfill_anime_episodes_from_next_airing.sql`
- `supabase/migrations/20260205000500_concierge_global_llm_budget_and_default_tuning.sql`
- `supabase/migrations/20260205002000_concierge_budget_raise.sql`
- `supabase/migrations/20260205160000_admin_schema_snapshot.sql`
- `supabase/migrations/20260205190000_concierge_modes_config.sql`
- `supabase/migrations/20260205231000_curated_rails.sql`
- `supabase/migrations/20260205232000_concierge_mode_cache.sql`
- `supabase/migrations/20260205232500_concierge_router_flag_and_retention.sql`
- `supabase/migrations/20260205233000_concierge_modes_v2_config.sql`
- `supabase/migrations/20260205234000_curated_rails_seed.sql`
- `supabase/migrations/20260205235000_discover_bundle_use_curated_rails.sql`               
- `supabase/migrations/20260206100000_concierge_modes_v3_expanded.sql` *(14 modes; +6 new: short, movie, romance, romcom, fantasy, isekai)*                                           
- `supabase/migrations/20260206120000_curated_rails_expansion.sql` *(+366 editorial picks across 4 rails; ecchi/low-score excluded)*
- `supabase/migrations/20260206143000_fix_legacy_tags_and_comments.sql` *(prod schema drift fix: tags.kitsu_id, comments.user_id type)*
- `supabase/migrations/20260206150000_security_hardening_rls_and_views.sql` *(RLS on 5 tables + SECURITY INVOKER on 5 views)*
- `supabase/migrations/20260207000000_search_titles_enrich_year_format.sql` *(search_titles() returns year+format for better disambiguation)*
- `supabase/migrations/20260207011000_curated_rails_vibes_seed.sql` *(seed pinned vibe rails for Action/Comedy/Cozy/Dark/Hidden Gems)*
- `supabase/migrations/20260207012000_concierge_modes_v4_add_vibe_rail_ids.sql` *(attach rail_id to additional vibe modes so Concierge serves pinned rails when available)*
- `supabase/migrations/20260207020000_curated_rails_more_vibes_seed.sql` *(seed pinned rails for additional modes: romcom, romance_serious, short, movie, isekai, fantasy_no_isekai)*
- `supabase/migrations/20260207021000_concierge_modes_v5_add_more_vibe_rail_ids.sql` *(attach rail_id to the additional modes seeded by 20260207020000)*
- `supabase/migrations/20260208090000_refine_short_and_fantasy_rails.sql` *(refine pinned rails: short_one_season now <=13 eps + finished; fantasy_no_isekai caps length + requires finished)*
- `supabase/migrations/20260208091500_curated_rails_premium_picks_seed.sql` *(seed pinned Premium Picks rails used as the default fallback mode)*
- `supabase/migrations/20260208092000_concierge_modes_v6_add_premium_picks_rail_id.sql` *(attach rail_id to premium_picks so vague prompts use pinned rails first)*
- `supabase/migrations/20260206162329_curated_rails_expansion.sql` *(idempotent re-run of curated expansion; safe no-op)*
- `supabase/migrations/20260206164200_security_hardening_rls_and_views.sql` *(idempotent re-run of RLS hardening; safe no-op)*
- `supabase/migrations/20260208022035_phase0_remove_sequels.sql` *(Phase 0: remove sequel entries from all anime rails — one entry per franchise)*
- `supabase/migrations/20260208022043_concierge_mode_analytics.sql` *(Phase 3: analytics table for mode routing telemetry)*
- `supabase/migrations/20260208022110_add_sports_mode.sql` *(Phase 1: sports_anime + sports_manga rails, 35 items each)*
- `supabase/migrations/20260208022136_phase0_remove_misclassified.sql` *(Phase 0: remove non-isekai from isekai, IDOLiSH7 from dark_serious, etc.)*
- `supabase/migrations/20260208022153_add_scifi_mode.sql` *(Phase 1: scifi_anime + scifi_manga rails, 45+32 items)*
- `supabase/migrations/20260208022239_add_horror_supernatural_mode.sql` *(Phase 1: horror_supernatural rails, 38+36 items)*
- `supabase/migrations/20260208022250_phase0_dedup_rails.sql` *(Phase 0: remove cross-rail duplicates to below 40% overlap)*
- `supabase/migrations/20260208022326_phase0_slim_and_rerank.sql` *(Phase 0: trim all rails to 30-80 target sizes, re-rank)*
- `supabase/migrations/20260208022342_add_demographic_rails.sql` *(Phase 1: seinen/shoujo/josei rails for anime + manga)*
- `supabase/migrations/20260208022356_update_concierge_config_new_modes.sql` *(Phase 1: add sports/scifi/horror_supernatural to concierge_config modes)*
- `supabase/migrations/20260208022404_phase0_fix_classics.sql` *(Phase 0: add missing cornerstone classics — Akira, Galaxy Express 999, Macross DYRL, Rurouni Kenshin)*
- `supabase/migrations/20260208023052_phase0_backfill_underpopulated_rails.sql` *(backfill premium_picks/action/short after dedup thinned them)*
- `supabase/migrations/20260208023221_phase0_dedup_backfilled_rails.sql` *(dedup newly backfilled items against existing rails)*
- `supabase/migrations/20260208023331_phase0_final_backfill.sql` *(final fill to target sizes for picks/short/manga)*
- `supabase/migrations/20260209000000_search_titles_add_cover_image.sql` *(add cover_image_medium to search_titles() RPC for concierge UI)*
- `supabase/migrations/20260209100000_concierge_modes_v7_german_synonyms.sql` *(v7: add German synonyms across all 17 modes + umlaut normalization)*
- `supabase/migrations/20260209110000_concierge_modes_v8_expanded.sql` *(v8: add 6 new modes — mecha, mystery_detective, music_performance, historical, school_coming_of_age, shoujo_josei — total 23 modes)*
- `supabase/migrations/20260209120000_new_vibe_rails.sql` *(seed 12 new curated rails for v8 modes — total 50 rails)*
- `supabase/migrations/20260209135229_import_reconciliation.sql` *(add import_action + previous_values columns to import_session_items for reconciliation)*
- `supabase/migrations/20260209200000_clubs_foundation.sql` *(7 club tables, generate_invite_code helper, indexes, triggers, RLS enabled)*
- `supabase/migrations/20260209201000_clubs_rls_policies.sql` *(25 RLS policies + 3 SECURITY DEFINER helper functions for clubs)*
- `supabase/migrations/20260209202000_clubs_rpcs.sql` *(6 RPCs + 3 helper functions for clubs)*
- `supabase/migrations/20260209220000_club_analytics.sql` *(club_analytics table, log_club_event RPC, extended housekeeping)*
- `supabase/migrations/20260209222528_fix_p0_p1_database_issues.sql` *(production-readiness: FK NOT NULL, RLS initplan optimization, anonymous write policies fixed, missing indexes, duplicate indexes removed)*
- `supabase/migrations/20260209222542_move_pg_trgm_to_extensions_schema.sql` *(move pg_trgm extension to extensions schema)*
- `supabase/migrations/20260209222659_fix_search_path_include_extensions.sql` *(add extensions schema to search_path for RPCs using pg_trgm)*
- `supabase/migrations/20260209222728_fix_remaining_functions_search_path.sql` *(fix search_path on remaining functions)*
- `supabase/migrations/20260209224945_fix_mirror_cron_contention.sql` *(per-batch lock keys, 120s TTL, 200 batch size, 15-min spacing for mirror cron jobs)*
- `supabase/migrations/20260209225348_add_import_secret_to_cron_jobs.sql` *(add x-import-secret header to 4 pg_cron bulk import jobs)*
- `supabase/migrations/20260216000000_catalog_created_at_not_null.sql` *(backfill NULLs + NOT NULL on created_at for 8 catalog tables: anime, manga, episodes, chapters, volumes, characters, studios, staff)*
- `supabase/migrations/20260216000001_drop_unused_indexes_merge_policies_health_check.sql` *(drop 12 unused indexes, merge duplicate club_members DELETE policies, create check_mirror_health() function)*
- `supabase/migrations/20260211030140_feature_flags.sql` *(feature flags table for staged rollout)*
- `supabase/migrations/20260211100000_rag_tables.sql` *(RAG/embedding tables for future semantic search)*
- `supabase/migrations/20260211110000_privacy_retention_and_gdpr.sql` *(privacy retention policies + GDPR compliance helpers)*
- `supabase/migrations/20260211113000_rag_retrieve_candidates.sql` *(RAG candidate retrieval RPC)*
- `supabase/migrations/20260211154000_fetch_club_bundle_member_identity.sql` *(stable member identity in club bundle via UUID hex prefix)*
- `supabase/migrations/20260211162000_reduce_school_shoujo_overlap.sql` *(reduce overlap between school_coming_of_age and shoujo_josei rails)*
- `supabase/migrations/20260211170000_enable_concierge_intelligence_de_canary.sql` *(enable concierge intelligence German canary flag)*
- `supabase/migrations/20260213130000_clubs_concierge_swipe_flags.sql` *(clubs + concierge swipe feature flags)*
- `supabase/migrations/20260213143000_concierge_editorial_v1_flag.sql` *(concierge editorial shell v1 flag)*
- `supabase/migrations/20260215124919_add_create_rail_and_poll_rpcs.sql` *(add create_club_rail + create_club_poll RPCs)*
- `supabase/migrations/20260215124946_create_club_rail_and_poll_rpcs.sql` *(club rail + poll RPC creation)*
- `supabase/migrations/20260215125056_fix_invite_code_crypto_and_club_members_insert.sql` *(fix invite code cryptographic generation + club_members insert policy)*
- `supabase/migrations/20260215125312_club_reactions_and_invite_share.sql` *(club reactions table + invite sharing improvements)*
- `supabase/migrations/20260215130000_fix_club_fk_housekeeping_gdpr.sql` *(fix club FK constraints, housekeeping, GDPR cleanup)*
- `supabase/migrations/20260216193000_add_club_rail_item_structured_errors.sql` *(structured error codes for add_club_rail_item RPC)*

### Supabase Edge Functions (index.ts) (count: 12)
- `supabase/functions/bulk-import-anime/index.ts`
- `supabase/functions/bulk-import-manga/index.ts`
- `supabase/functions/concierge-apply/index.ts`
- `supabase/functions/concierge-import-anilist/index.ts` *(AniList import helper)*
- `supabase/functions/concierge-parse/index.ts`
- `supabase/functions/concierge-recommend/index.ts`
- `supabase/functions/concierge-resolve/index.ts`
- `supabase/functions/concierge-retrieve-assist/index.ts` *(RAG retrieval assist)*
- `supabase/functions/concierge-retrieve-feedback/index.ts` *(RAG feedback collection)*
- `supabase/functions/concierge-undo/index.ts`
- `supabase/functions/delete-account/index.ts` *(GDPR account deletion)*
- `supabase/functions/mirror-images/index.ts`

### Quality gate scripts (count: 8)
- `scripts/quality-gates/check_secrets.sh`
- `scripts/quality-gates/check_migrations.sh`
- `scripts/quality-gates/test_router_offline.sh`
- `scripts/quality-gates/router_test_cases.js`
- `scripts/quality-gates/test_concierge_corpora.sh`
- `scripts/quality-gates/audit_rails.sh`
- `scripts/quality-gates/build_ios.sh`
- `scripts/quality-gates/run_all.sh`

### Git hooks
- `.githooks/pre-commit`

### Repo scripts (count: 19)
- `scripts/apply_remote_sql.js`
- `scripts/check_cron_health.js`
- `scripts/collect_db_metrics.js`
- `scripts/concierge_corpus_generate.js`
- `scripts/concierge_eval_parse.js`
- `scripts/db_state.sql`
- `scripts/generate_app_state_codebase_bundle.js`
- `scripts/generate_app_state_inventory.js`
- `scripts/generate_app_state_live_snapshot.js`
- `scripts/generate_app_state_maps.js`
- `scripts/generate_app_state_sources.js`
- `scripts/genre_audit.js`
- `scripts/import_anilist_fast.js`
- `scripts/import_anilist_local.js`
- `scripts/load_test_concierge.js`
- `scripts/report_airing_window.js`
- `scripts/run_full_import.js`
- `scripts/smoke_concierge_recommend.js`
- `scripts/smoke_magic_parse_apply.js`


<!-- END AUTO-INVENTORY -->

### iOS app structure (`/Kuro`)
- `Kuro/ContentView.swift` — app entry point + navigation/swipe pager + top header
- `Kuro/KuroApp.swift` — `@main` entry, `scenePhase` lifecycle handling, `NetworkMonitor` + `SupabaseService` environment injection, `.onOpenURL` deep link handler
- `Kuro/Services/DeepLinkRouter.swift` — `enum DeepLink` with cases for anime(id:), manga(id:), club(id:), collection, discover, concierge(prompt:); parses `kuro://` scheme URLs
- `Kuro/Services/AppleFMService.swift` — Apple Foundation Models integration (on-device LLM: mode classification, disambiguation, synopsis condensation, collection search intent)
- `Kuro/Services/NetworkMonitor.swift` — `NWPathMonitor` connectivity tracking, `@Environment` injection, offline banner
- `Kuro/Services/SupabaseService.swift` — core data layer, RPC usage, caching, `fmService` (AppleFMService), `withRetry` helper
- `Kuro/Views/` — SwiftUI UI components
- `Kuro/Models/` — data models (Anime, Manga, UserList, etc.)
- `Config/` — xcconfig files (Shared, Debug, Release) for env-based builds

### Feature-to-file map (frontend)
- **Concierge UI**: `Kuro/Views/ConciergeView.swift` (inline chat, import, recommend UI, toasts), `ConciergeEditorialShell.swift` (editorial shell wrapper), `ConciergeComponents.swift` (shared components + curated copy), `ConciergeInputField.swift` (text input), `ConciergeComposerDock.swift` (input composer dock), `ConciergeActionFooter.swift` (action footer bar), `ConciergeIntentDeck.swift` (quick-action intent deck), `ConciergeImportCards.swift` (import preview/confirm cards), `ConciergeRecommendationRails.swift` (recommendation rail rendering), `ConciergeResponseStage.swift` (response stage rendering)
- **Discover**: `Kuro/Views/EditorialDiscoverView.swift` (sections, rails, filters)
- **Collection**: `Kuro/Views/EditorialCollectionView.swift` + list helpers in `SupabaseService`
- **Browse**: `Kuro/Views/BrowseView.swift` (full-page browse with filters)
- **Search**: `Kuro/Views/EditorialSearchView.swift`
- **Clubs**: `Kuro/Views/ClubsView.swift` (club list, enriched cards, unread dots), `Kuro/Views/ClubDetailView.swift` (4-tab: Rails/This Week/Polls/Chat), `Kuro/Views/ClubCreateSheets.swift` (create/join sheets), `Kuro/Views/DetailPages/ClubActivitySection.swift` (media detail club context)
- **Cards / badges**: `Kuro/Views/KuroRefinedCard.swift`, `Kuro/Views/KuroCardText.swift`
- **Glass UI**: `Kuro/Views/KuroGlass.swift`
- **Toasts**: `Kuro/Views/KuroToast.swift`
- **Image caching**: `Kuro/Views/KuroCachedAsyncImage.swift`, `Kuro/Services/ImagePipeline.swift`
- **Profile**: `Kuro/Views/ProfileView.swift` (includes Clubs tab)
- **Onboarding**: `Kuro/Views/OnboardingView.swift` (first-launch onboarding flow)
- **Apple Foundation Models**: `Kuro/Services/AppleFMService.swift` (on-device: mode classification, disambiguation, synopsis condensation, NL collection search intent)
- **Network monitoring**: `Kuro/Services/NetworkMonitor.swift` (connectivity state, offline banner in `KuroApp.swift`)
- **Feature flags**: `Kuro/Services/FeatureFlags.swift` (staged rollout definitions for clubs, concierge, realtime features)
- **Analytics**: `Kuro/Services/ConciergeAnalytics.swift` (concierge + club interaction telemetry)
- **Text normalization**: `Kuro/Services/TextNormalization.swift` (search/parsing text utilities)
- **Synopsis condenser**: `AnimeDetailView.swift`, `MangaDetailView.swift` call `fmService.condenseSynopsis()` for descriptions > 200 chars
- **Next Up picks**: `NextUpSection` (in `AnimeDetailView.swift`), `MangaNextUpSection` (in `MangaDetailView.swift`) — personalized next episode/chapter recommendations
- **Deep linking**: `Kuro/Services/DeepLinkRouter.swift` (URL parsing), `KuroApp.swift` (`.onOpenURL` handler), `ContentView.swift` (navigation + sheet presentation for deep link targets)
- **External links**: `Kuro/Views/DetailPages/ExternalLinksSection.swift` (streaming/source links on detail pages)
- **Design utilities**: `Kuro/Design/Color+Hex.swift` (hex color conversion)

### Supabase
- `supabase/migrations/` — schema, indexes, views, RPCs, cron jobs
- `supabase/functions/` — Edge Functions
- `supabase/CONCIERGE_OPS.md` — concierge budgets, rate limits, retention

### Edge function map
- `bulk-import-anime/` — imports anime catalog from AniList (server-side ingest)
- `bulk-import-manga/` — imports manga catalog from AniList (server-side ingest)
- `concierge-parse/` — deterministic parser; search title candidates
- `concierge-resolve/` — LLM disambiguation for ambiguous titles
- `concierge-recommend/` — deterministic recommendations + optional LLM narration
- `concierge-apply/` — apply parsed items to user lists
- `concierge-undo/` — rollback last import session
- `mirror-images/` — mirror external images to Storage CDN

### Scripts
- `scripts/import_anilist_fast.js`, `scripts/import_anilist_local.js`, `scripts/run_full_import.js` — AniList ingestion
- `scripts/genre_audit.js`, `scripts/report_airing_window.js` — data QA
- `scripts/concierge_eval_parse.js`, `scripts/concierge_corpus_generate.js`, `scripts/load_test_concierge.js` — concierge QA/ops
- `scripts/check_cron_health.js`, `scripts/collect_db_metrics.js` — ops
- `scripts/db_state.sql` — DB snapshot queries (row counts, coverage, etc.)
- `scripts/quality-gates/` — CI quality gate scripts (secrets, migrations, router tests, rails audit, iOS build); see section 13.1

---

## 3) Frontend (iOS) — current UX + navigation

### Main navigation
- File: `Kuro/ContentView.swift`
- Root: `ContentView -> KuroRootView -> KuroMainView`
- Swipe order (left to right):
  1. **Concierge**
  2. **Discover**
  3. **Browse**
  4. **Collection**
  5. **Clubs**
- **Search** is not a page — it opens as a sheet from the magnifying glass icon in the header, available from any page.
- **Offline banner**: Monochrome "OFFLINE" text banner (9pt, tracked) appears at top of `RootView` when `networkMonitor.isConnected == false`. Injected as `@Environment` from `KuroApp`.
- **App lifecycle**: `scenePhase` tracked in `KuroApp.swift` for background/foreground transitions.
- **Deep linking**: `KuroApp.swift` handles `.onOpenURL` events, passes `pendingDeepLink` binding to `ContentView`. `DeepLinkRouter.swift` defines `enum DeepLink` with cases: `.anime(id:)`, `.manga(id:)`, `.club(id:)`, `.collection`, `.discover`, `.concierge(prompt:)`. Parses `kuro://` scheme URLs. `ContentView` navigates to the target page for page-level links, or presents a detail sheet for anime/manga/club links.

### Header (top bar)
- Left: **KURO** wordmark only (no concierge icon next to it).
- Center: animated section title window (shows section name).
- On Concierge page only: a small **chat icon** appears next to the section title.
- Right: **Profile menu** (circle with initial). Dropdown contains:
  - Profile (sheet)
  - Sign Out

### Concierge
- Full left page (no floating launcher in header).
- **Inline chat architecture** (no full-screen takeovers, no state machine):
  - Typing indicator for loading states
- Inline confirm bubble for import preview (grouped: NEW / UPDATE / UNCHANGED)
  - Inline editorial rails for recommendations
  - Toast + undo for completion
- Empty state:
  - Concierge glass intro card
  - Curated entry actions:
    - Import list
    - See curated example prompts
    - Ask for a mood-based recommendation
- Main features:
  - Deterministic parsing of pasted list with import reconciliation (Add/Update/Skip actions)
  - Auto-apply for high-confidence imports (all items score >= 0.85, no ambiguous adaptations)
  - Candidate disambiguation
  - LLM fallback for ambiguous lines
  - Apply/undo sessions (undo restores previous_values for updates)
  - Recommendations with LLM narration (optional), 23 vibe mode IDs
  - Editorial mode-to-copy mapping in `ConciergeComponents.swift` (`ConciergeCuratedCopy`) that surfaces polished section names (e.g., “The Cut”, “Dark, Not Empty”, etc.) in EN/DE while keeping backend IDs stable
  - Edge function warmup on view appear (`concierge-parse?warmup=true`)
  - **Task lifecycle**: tracked `@State` task references (`warmupTask`, `prefetchTask`, `prefetchTask2`, `backgroundRefreshTask`, `backgroundRefreshTask2`) with consolidated `.onDisappear` cancellation — prevents leaked `Task.detached` work
- All UI components use `KuroDesignSystem` tokens (fonts, spacing, radii, animations).
- German NLP: `GERMAN_VIBE_FORMS` allowlist (15 adjective stems x 5 inflections), German intent keywords in `scoreMode()`, umlaut normalization (u->ue, o->oe, a->ae, ss->ss).
- **Accessibility** (P2): Message bubbles ("You said: ..." / "Concierge: ..."), recommendation rail headers `.isHeader`, clarification cards with combined labels. `ConciergeRecommendationRails`: `.accessibilityAddTraits(.isHeader)` on rail title. `ConciergeComponents`: combined accessibility labels on clarification cards.

### Discover
- Editorial layout with sections (Essentials, Classics, New to You, Trending, etc.)
- Cards are two-column + compact horizontal rails
- Cards show rating pill + metadata line (YEAR · EPS/CH)
- **Per-rail error state** (P2): `@State loadError` with inline retry view when `fetchDiscoverBundle()` fails on first load. Accessibility label on error state.
- **Accessibility**: `.accessibilityAddTraits(.isHeader)` on CompactHorizontalSection and Dense2ColumnSectionFixed titles.

### Collection
- Uses collection feed + paging RPCs
- **Accessibility**: `.accessibilityAddTraits(.isHeader)` on section headers in `EditorialCollectionView`.

### Browse + Search
- RPC-backed paging

### Clubs
- 5th page in the swipe pager (rightmost).
- `ClubsView`: joined club list, empty state with create/join prompts, pull-to-refresh. No `NavigationStack` wrapper (bare view inside pager); club detail opens as a sheet. **Accessibility**: `.accessibilityLabel` on empty state ("No clubs yet...") and club cards (name + member count).
- `ClubDetailView`: 4-tab layout (Rails / This Week / Polls / Chat — chat gated by `clubs_chat_v1` flag), settings sheet for owner/admin. Each rail has a "+" button (for unlocked rails or owner/admin on locked rails) that opens `AddItemToRailSheet` — server-side search via `search_anime_page`/`search_manga_page` RPCs with debounced input, compact result rows, typed `PostgrestError` handling for duplicates/lock/membership errors.
- `ClubActivitySection`: embedded on `AnimeDetailView` and `MangaDetailView` — shows which clubs have this title in a rail, aggregate member status counts, and (if sharing level allows) per-member details. Member identity uses stable 6-char UUID hex prefix (not positional "Member N").
- `ClubActivitySection`: now renders explicit member watch/read progress language (tracking, completed, planning, paused, dropped, not-started) and does not use placeholder status labels when per-member detail is unavailable.
- Clubs tab also accessible from `ProfileView` (secondary access path via sheet).
- Monochrome status pills (no colored dots).

---

## 3.1) Client data layer (SupabaseService)

Key responsibilities (file: `Kuro/Services/SupabaseService.swift`):
- **Auth bootstrap**: restores session, ensures `profiles` row, loads user lists + feed.
- **Discover**: `fetchDiscoverBundle()` uses RPC `discover_bundle`, cached with in-flight de-dupe.
- **Search**: RPCs `search_anime_page`, `search_manga_page`.
- **Browse**: RPCs `browse_anime_page`, `browse_manga_page` with sort selection.
- **Collection**: keyset paging RPCs `collection_*_page` + in-memory caches.
- **Upcoming**: `airing_next(days)` RPC + caching/backoff for rate-safe refresh.
- **Concierge**: calls Edge Functions for parse/recommend/apply/undo; caches parse + recommend.
- **Realtime**: subscribes to user-scoped channel to refresh list/collection data on changes. Club-specific channel subscription for live updates (rail items, polls, votes, reactions, messages) with 500ms debounce.
- **Local caches**: `discoverBundleCache`, `conciergeParseCache`, `conciergeRecommendCache` (in-memory, TTL-based).
- **Apple FM integration**: `fmService` property (`AppleFMService` instance) provides on-device classification, disambiguation, synopsis condensation, and NL collection search intent parsing.
- **Retry logic**: `withRetry` static helper (exponential backoff, max 2 retries, URLError-only) wrapping 5 key call sites: `fetchMoreAnime`, `fetchMoreManga`, `fetchDiscoverBundle`, `conciergeParse`, `conciergeRecommend`.
- **Debug logging**: all 64+ `print()` statements wrapped in `#if DEBUG`.

<!-- BEGIN AUTO-IOS-MAP -->

## 3.2) Auto iOS backend usage index

Generated: **2026-02-05T17:59:23.173Z** (git: `ca671d5`)

- Swift files scanned: **45** (all `Kuro/**/*.swift`)

### RPCs used by iOS (count: 15)
- `browse_anime_page`
- `browse_manga_page`
- `collection_anime_page`
- `collection_feed_page`
- `collection_manga_page`
- `create_club`
- `join_club`
- `leave_club`
- `fetch_club_bundle`
- `add_club_rail_item`
- `cast_club_vote`
- `discover_bundle`
- `recommend_ids_similar_to_seeds`
- `search_anime_page`
- `search_manga_page`

### Edge Functions invoked by iOS (count: 5)
- `concierge-apply`
- `concierge-parse`
- `concierge-recommend`
- `concierge-resolve`
- `concierge-undo`


<!-- END AUTO-IOS-MAP -->

## 3.3) Apple Foundation Models (on-device LLM)

**File:** `Kuro/Services/AppleFMService.swift`

`AppleFMService` is a `@MainActor @Observable` class implementing the `FMProvider` protocol. It provides 4 on-device LLM capabilities via Apple Foundation Models (iOS 26+):

1. **Mode classification** (`classifyMode`): Classifies a user's vibe request into one of the available concierge modes. Prompt lists all mode IDs + synonyms; output validated against allowed set. Timeout: 5s.
2. **Disambiguation** (`disambiguate`): Picks the best candidate from an ambiguous title search. Considers year mentions, format, and context clues. Timeout: 8s.
3. **Synopsis condensation** (`condenseSynopsis`): Generates a spoiler-free 2-sentence hook from a long description. Called by `AnimeDetailView` and `MangaDetailView` for descriptions > 200 chars. Cached per `mediaId` in `[Int: String]` dictionary. Timeout: 10s.
4. **NL collection search** (`parseSearchIntent`): Extracts genre, status, year range, and keywords from natural language collection queries. Timeout: 5s.

**Architecture details:**
- 4 `@Generable` structs with `@Guide` annotations: `FMDisambiguationOutput`, `FMModeOutput`, `FMSynopsisOutput`, `FMSearchIntentOutput` (all reasoning-before-selection pattern)
- `withFMTimeout` helper: uses `ThrowingTaskGroup` to race the FM call against a sleep timer; cancels loser
- `StubFMProvider`: no-op implementation for devices/OS versions without Foundation Models support
- Compile guards: `#if canImport(FoundationModels)` + `#available(iOS 26, *)`
- **No entitlement needed**: Foundation Models framework works via simple `import FoundationModels` — no capability toggle or entitlement required in the Developer Portal. Only the Adapter entitlement (for custom LoRA fine-tunes) requires a separate request.
- Integrated into `SupabaseService.fmService` (property on both production and mock service)

## 3.4) Network monitoring

**File:** `Kuro/Services/NetworkMonitor.swift`

`NetworkMonitor` is a `@MainActor @Observable` class using `NWPathMonitor` from the Network framework.

- **Published state**: `isConnected` (Bool), `connectionType` (`.wifi`, `.cellular`, `.wired`, `.unknown`)
- **Injection**: created in `KuroApp.swift`, injected as `@Environment` throughout the app
- **Offline banner**: `RootView` in `KuroApp.swift` shows a monochrome "OFFLINE" text banner (9pt, tracked 1.2, black 45% opacity) when `isConnected == false`
- **Lifecycle**: starts monitoring on init, cancels on deinit

---

## 4) Design system (current)

**Design philosophy:** Editorial minimalism + premium glass surfaces

**Key design primitives**
- `KuroGlassCard` in `Kuro/Views/KuroGlass.swift`
- `KuroGlassPill` in `Kuro/Views/KuroGlass.swift`
- `KuroScoreBadge`, `KuroPortraitCard`, `KuroCompactCard` in `Kuro/Views/KuroRefinedCard.swift`. Card widths are adaptive: `floor((screenWidth - 56) / 2.8)` clamped to [112, 144]. `CompactHorizontalSection` / `CompactHorizontalMangaSection` require explicit `containerWidth` (no default). All surfaces pass screen width or GeometryReader width.
- Concierge iconography: `KuroConciergeMark` (butler glyph) in `Kuro/Views/KuroConciergeMark.swift`

**Typography**
- Serif for titles and editorial feel
- Light weights for subtitles
- Uppercase tracking for section titles

**Card details (current)**
- Rating pill in top-right of poster
- Metadata line shows `YEAR · EPS/CH` under title
- Poster corners rounded (8–12pt depending on card type)

---

## 5) Image + CDN pipeline

### Client-side caching
- `Kuro/Views/KuroCachedAsyncImage.swift` uses `ImagePipeline`
- `Kuro/Services/ImagePipeline.swift`:
  - In-memory cache (NSCache, ~80MB)
  - URLCache-backed disk cache
  - Downsampling to max pixel size
  - Request de-dupe for in-flight images

### Server-side image mirroring
- Edge Function: `supabase/functions/mirror-images`
- Mirrors AniList image URLs into Supabase Storage public bucket
- Uses public URLs: `https://<ref>.supabase.co/storage/v1/object/public/<bucket>/<path>`
- Supports ANIME, MANGA, CHARACTER, STAFF images
- Payload supports:
  - `bucket` (default `media`)
  - `mediaTypes` (array)
  - `limit`, `offset`, `overwrite`
  - `skipIfMirrored` (default true)
  - `cacheControl` (default 604800)
  - `timeBudgetMs` (default 90000)

### Storage bucket
- Public bucket name used by default: `media`
- Public URL pattern: `https://<ref>.supabase.co/storage/v1/object/public/media/<path>`

---

## 6) Backend data model (Supabase)

### Core catalog tables
- `anime`
- `manga`
- `episodes`
- `chapters`
- `volumes`
- `characters`
- `staff`
- `studios`
- All 8 catalog tables have `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` (NULLs backfilled via migration `catalog_created_at_not_null`)
- `studios`
- `authors`
- `tags`, `anime_tags`, `manga_tags`
- `genres`
- `external_links` (for source/streaming links)
- Join tables: `anime_characters`, `manga_characters`, `anime_staff`, `manga_staff`, `anime_studios`, `manga_authors`
- Comments: `anime_comments`, `manga_comments`

### User data
- `profiles` (1:1 with auth.users)
- `anime_user_lists`
- `manga_user_lists`
- `user_lists` (user-specific list metadata)
- `collection_feed` views (via RPC)
- `user_airing_next` view + RPCs (airing countdown/next-episode data)

### Search + discover
- `title_aliases` (for canonical search)
- `search_*` RPCs
- `discover_bundle` RPC
- `recommend_*` RPCs

### Concierge
- `import_sessions`
- `import_session_items`
- `concierge_runs`
- `concierge_parse_feedback`
- `concierge_config` (rate limits + budgets JSON)
- `rate_limit_buckets`
- `llm_daily_usage`
- `system_flags` (e.g., `llm_enabled`)
- `mirror_runs` (logs mirror-image jobs)

### Clubs
- `clubs` (id uuid, name, description, created_by, invite_code, invite_expires_at, invite_max_uses, invite_use_count, sharing_level, max_members, is_archived)
- `club_members` (id uuid, club_id, user_id uuid, role [owner/admin/member], sharing_level, joined_at)
- `club_rails` (id uuid, club_id, title, description, created_by, is_locked, sort_order)
- `club_rail_items` (id uuid, rail_id, media_type [ANIME/MANGA], media_id int, added_by uuid, sort_order, note)
- `club_rail_item_reactions` (id uuid, item_id FK, user_id FK, emoji CHECK(fire/heart/eyes/100), created_at; UNIQUE(item_id, user_id, emoji))
- `club_polls` (id uuid, club_id, question, created_by, closes_at, is_closed)
- `club_poll_options` (id uuid, poll_id, label, media_type, media_id, sort_order)
- `club_votes` (id uuid, poll_id, option_id, user_id uuid; UNIQUE(poll_id, user_id))
- `club_messages` (id uuid, club_id FK, user_id FK CASCADE, text 1-280 chars, created_at; auto-pruned after 30 days)
- `club_analytics` (id uuid, event_type, club_id, user_id, metadata jsonb, created_at; events: club_created/joined/left/rail_opened/vote_cast/import_applied/import_undone)

### Ops / metrics
- `concierge_metrics_hourly`
- `llm_usage_daily_totals`
- `rate_limit_recent_top`
- `import_state` (cursor table for scheduled AniList imports)
- `import_runs` (optional; bulk-import functions write run history if present)
- `club_analytics` (club telemetry events; 90-day retention via housekeeping cron)

**Schema definitions are in** `supabase/migrations/`.

### Auth + RLS
- Supabase Auth is used (email/password; OAuth can be added later).
- `profiles` row is ensured on sign-in (`SupabaseService.ensureProfileRow()`).
- RLS is enabled; user tables are scoped to `auth.uid()` in migrations.
- Concierge endpoints always derive user id from JWT (never accept raw user_id from client).
- **Clubs RLS**: 30+ policies across 9 tables. All access gated by membership via `is_club_member()` / `is_club_admin_or_owner()` / `is_club_owner()` (SECURITY DEFINER helpers to avoid infinite recursion on club_members self-query). club_members INSERT is managed via SECURITY DEFINER RPCs only (no direct policy). Rail lock enforced in `club_rail_items` INSERT policy (`cr.is_locked = false`). `club_rail_item_reactions`: member-gated SELECT/INSERT, self-only DELETE. `club_messages`: member-gated SELECT/INSERT, self-only DELETE. **Merged policy** (P2): duplicate `club_members` DELETE policies consolidated into single `club_members_delete_self_or_admin`.
- **Club analytics RLS**: authenticated insert own (`user_id = auth.uid()`), service_role select only.
- **Storage RLS** (P0-7): `media` bucket policies — read public (anon + authenticated), write/delete authenticated only, service_role full access. MIME types restricted to `image/jpeg`, `image/png`, `image/webp`, `image/avif`, `image/gif` (P0-6). File size limit: 5MB (P1-15).
- **Security fixes**: `generate_invite_code()`, `sharing_level_rank()`, and all club helper functions use `SET search_path = public` to prevent search_path injection.

---

## 6.1) Unified views (important)

### `public.user_lists` view
- Defined in `08_create_user_lists_view.sql` (root).
- Unifies `anime_user_lists` + `manga_user_lists` into a single shape used by:
  - recommendation RPCs
  - concierge logic
- **This view must exist** or many recommend RPCs break.

### `public.user_airing_next` view + `public.airing_next(days)` RPC
- Defined in `10_create_user_airing_next_view.sql` and `11_airing_next_rpc.sql` (root).
- Pulls upcoming airings for titles in the user’s list.
- `user_id` is stored as `text` in those views for compatibility.

---

## 6.2) Clubs system (detailed)

### Overview
Clubs are private groups (2-20 members) for sharing anime/manga watch activity. Privacy-by-design: three sharing levels control what members see.

### Tables (9)
| Table | Primary key | Key constraints |
|-------|------------|----------------|
| `clubs` | uuid | `name` <= 80 chars, `invite_code` UNIQUE, `sharing_level` IN (private/status/progress), `max_members` default 20 |
| `club_members` | uuid | UNIQUE(club_id, user_id), `role` IN (owner/admin/member), user_id is UUID (not TEXT like legacy tables) |
| `club_rails` | uuid | `title` <= 120 chars, `is_locked` boolean, `sort_order` int |
| `club_rail_items` | uuid | UNIQUE(rail_id, media_type, media_id), `media_type` IN (ANIME/MANGA), `note` <= 280 chars |
| `club_rail_item_reactions` | uuid | UNIQUE(item_id, user_id, emoji), `emoji` CHECK IN (fire/heart/eyes/100), member-gated RLS |
| `club_polls` | uuid | `question` <= 200 chars, `is_closed` boolean + `closes_at` (no `is_active`) |
| `club_poll_options` | uuid | `label` <= 120 chars, optional media_type/media_id link. Append-only (no updated_at) |
| `club_votes` | uuid | UNIQUE(poll_id, user_id). Append-only. Single-choice: delete+reinsert to change vote |
| `club_messages` | uuid | `text` 1-280 chars, FK CASCADE on user delete, 30-day auto-prune via cron, member-gated RLS, rate-limited (20/min) |

### Privacy model
- **Sharing levels** (club-wide default + per-member override):
  - `private` (rank 0): aggregates only, no per-member data
  - `status` (rank 1): names + list statuses, no progress numbers
  - `progress` (rank 2): full detail including episode/chapter progress
- **Minimum 3 members** for aggregate breakdown (H1 rule): with <3 members, only own data is visible
- Per-member `sharing_level` can only be more restrictive than the club default (enforced by `sharing_level_rank()`)
- Effective level = `min(member_override ?? club_default, club_default)`

### RLS design (30+ policies + 4 helper functions)
- 3 SECURITY DEFINER helpers (`is_club_member`, `is_club_admin_or_owner`, `is_club_owner`) avoid infinite recursion on club_members self-query
- `club_members` has NO INSERT policy for `authenticated` role -- membership managed exclusively via SECURITY DEFINER RPCs (`create_club`, `join_club`)
- `club_rail_items` INSERT policy enforces rail lock: `AND cr.is_locked = false`
- `club_poll_options` and `club_votes` have no UPDATE policy (append-only; delete+reinsert pattern)
- `club_rail_item_reactions`: member-gated SELECT/INSERT, self-only DELETE
- `club_messages`: member-gated SELECT/INSERT, self-only DELETE
- All helper functions use `SET search_path = public`

### RPCs (12)
1. `create_club` -- SECURITY DEFINER; creates club + owner row; invite code with collision retry (max 5)
2. `join_club` -- SECURITY DEFINER; rate-limited (10/min via rate_limit_hit); validates code/expiry/cap/membership/member count
3. `leave_club` -- SECURITY DEFINER; ownership transfer: oldest admin first, then oldest member; deletes club if last member
4. `fetch_club_bundle` -- SECURITY INVOKER (relies on RLS); returns club + members (with display_name) + rails (with LEFT JOIN media enrichment + per-member `member_statuses` jsonb array + per-item `reactions` aggregates + `my_reactions` + `episode_count`/`chapter_count`) + polls (anonymous vote counts only, never voter IDs)
5. `add_club_rail_item` -- SECURITY DEFINER; validates membership + lock + media existence + note length; auto-increments sort_order
6. `cast_club_vote` -- SECURITY DEFINER; validates membership + open poll + option belongs to poll; delete+reinsert for re-vote
7. `create_club_rail` -- SECURITY DEFINER; membership check, title 1-120 chars, auto sort_order; returns {rail_id, title}
8. `create_club_poll` -- SECURITY DEFINER; membership check, question 1-200 chars, 2-10 options; returns {poll_id, question}
9. `toggle_club_reaction` -- SECURITY DEFINER; membership check, toggle insert/delete; returns {action, emoji}
10. `fetch_my_clubs_enriched` -- SECURITY DEFINER; returns caller's clubs with member_count, last_activity_at, activity_preview, ordered by activity
11. `send_club_message` -- SECURITY DEFINER; membership check, 280 char max, rate-limited (20/min); returns {message_id, created_at}
12. `fetch_club_messages` -- SECURITY DEFINER; membership check, paginated newest-first (max 100/page); returns messages

### fetch_club_bundle implementation notes
- Uses LEFT JOINs to anime/manga tables (one join per media type, not N scalar subqueries per item)
- Caller's own list status via LEFT JOIN to anime_user_lists/manga_user_lists
- `member_statuses`: per-member status jsonb array (only when sharing >= 'status' and >= 3 members)
- `member_status_counts`: aggregate {WATCHING: 3, COMPLETED: 2} counts per item (respects sharing levels)
- user_id::text cast for joins to legacy user-list tables

### Analytics
- `club_analytics` table: event_type, club_id, user_id, metadata jsonb
- Events: club_created, club_joined, club_left, rail_opened, vote_cast, import_applied, import_undone
- `log_club_event` RPC (SECURITY DEFINER, always uses auth.uid())
- 90-day retention via extended `concierge_housekeeping()` cron
- RLS: authenticated insert own, service_role select only

### iOS views
- `ClubsView.swift`: 5th page in swipe pager (rightmost). No `NavigationStack` wrapper; club detail opens as sheet. Lists joined clubs with enriched cards (member count, activity preview, unread dot). Empty state with create/join prompts. Foreground notification check on `willEnterForeground`.
- `ClubDetailView.swift`: 4-tab segmented picker (RAILS / THIS WEEK / POLLS / CHAT — chat gated by `clubs_chat_v1` flag). Settings sheet for owner/admin. Reactions row (fire/heart/eyes/100 capsules) on each rail item (gated by `clubs_reactions_v1`). Pace text on This Week items ("3 ep behind the group" / "In sync", gated by `clubs_pace_sync_v1`, requires sharing_level=progress and ≥3 members). Milestone celebration cards when all members complete a title. Realtime subscription (on appear/disappear, gated by `clubs_realtime_v1`). Add-to-rail: "+" button per rail header (gated by lock status + role), opens `AddItemToRailSheet` with media type toggle, debounced server-side search, typed `PostgrestError` handling (DUPLICATE_ITEM, NOT_A_MEMBER, RAIL_LOCKED, MEDIA_NOT_FOUND). Task lifecycle managed via `.onDisappear` cancellation. **Vote error handling**: `castVote` wrapped in do/catch with `.error` toast + `errorHaptic()`. **Accessibility**: `.accessibilityAddTraits(.isHeader)` on section headers.
- `ClubActivitySection.swift`: Embedded on `AnimeDetailView` and `MangaDetailView`. Shows club context: which clubs have this title, aggregate member statuses.
- `ProfileView.swift`: "Clubs" row opens ClubsView sheet (secondary access path).
- Monochrome status pills (no colored dots).

### Realtime
- `club_rail_items`, `club_polls`, `club_votes`, `club_rail_item_reactions`, `club_messages` added to `supabase_realtime` publication.
- iOS subscribes to club-specific channel on `ClubDetailView` appear; 500ms debounce triggers `refreshClubBundle`.
- Unsubscribes on disappear; switches subscription when opening a different club.

### Chat (ephemeral)
- Text-only messages, 280 char max, rate-limited (20/min per user).
- 30-day auto-prune via `prune_club_messages` cron job (daily 3 AM UTC).
- Reversed ScrollView (newest at bottom, like iMessage), paginated load-earlier.
- GDPR: CASCADE on user delete, explicit cleanup in `delete_user_concierge_data()`.

### Notifications (in-app)
- `check_club_activity_since` RPC returns boolean for new activity since last-seen.
- Last-seen stored in local UserDefaults per club (`com.kuro.clubLastSeen.*`).
- Badge dot on Clubs page indicator in header when unseen activity exists.
- Badge cleared when navigating to Clubs page.

---

## 7) RPCs (current usage)

Client + edge functions rely on these RPCs:
- `discover_bundle`
- `search_anime_page`, `search_manga_page`
- `browse_anime_page`, `browse_manga_page`
- `collection_feed_page`
- `collection_anime_page`, `collection_manga_page`
- `recommend_ids_similar_to_seeds`
- `recommend_ids_premium`
- `search_titles` (now returns `cover_image_medium` via coalesce on anime/manga)
- `check_concierge_rate_limit`
- `get_concierge_config`
- `log_concierge_run`
- `log_concierge_parse_feedback`
- `llm_budget_reserve`, `llm_budget_finalize`
- `llm_global_budget_reserve`, `llm_global_budget_finalize`
- `is_flag_enabled`
- `acquire_import_lock`, `release_import_lock`
- **Club RPCs** (SECURITY DEFINER except fetch_club_bundle which is INVOKER):
  - `create_club(p_name, p_description, p_sharing_level)` — creates club + owner membership, generates invite code with collision retry
  - `join_club(p_invite_code)` — validates code/expiry/cap, rate-limited (10/min), inserts member
  - `leave_club(p_club_id)` — removes member, transfers ownership (oldest admin first, then oldest member) or deletes club if last member
  - `fetch_club_bundle(p_club_id)` — SECURITY INVOKER, returns club info + members (with display_name) + rails (with media joins via LEFT JOIN, per-member watch statuses as `member_statuses` jsonb array, per-item `reactions` aggregate counts + `my_reactions` + `episode_count`/`chapter_count`) + polls (anonymous vote counts). Privacy: <3 members returns only own data; `private` sharing returns aggregates only; `status` returns names+statuses; `progress` returns full detail
  - `add_club_rail_item(p_rail_id, p_media_type, p_media_id, p_note)` — validates membership + lock + media existence
  - `cast_club_vote(p_poll_id, p_option_id)` — validates membership + open poll, delete+reinsert for re-vote
  - `create_club_rail(p_club_id, p_title, p_description)` — validates membership, title 1-120 chars, auto sort_order
  - `create_club_poll(p_club_id, p_question, p_options[])` — validates membership, 2-10 options, returns {poll_id, question}
  - `toggle_club_reaction(p_rail_item_id, p_emoji)` — validates membership, toggle insert/delete, returns {action, emoji}
  - `fetch_my_clubs_enriched()` — returns caller's clubs with member_count, last_activity_at, activity_preview
  - `send_club_message(p_club_id, p_text)` — validates membership, 280 char max, rate-limited (20/min)
  - `fetch_club_messages(p_club_id, p_limit, p_before)` — validates membership, paginated newest-first, max 100/page
- **Club helper functions**:
  - `is_club_member(uuid)`, `is_club_admin_or_owner(uuid)`, `is_club_owner(uuid)` — SECURITY DEFINER, STABLE
  - `sharing_level_rank(text)` — IMMUTABLE, returns 0/1/2 for private/status/progress
  - `generate_invite_code(int)` — 8-char alphanumeric (62^8 combinations)
  - `log_club_event(p_event_type, p_club_id, p_metadata)` — SECURITY DEFINER, inserts analytics row
- **Ops functions**:
  - `check_mirror_health()` — returns JSONB with mirror run stats (total runs, successes, failures, consecutive failures, alert boolean). Used for operational health monitoring.

<!-- BEGIN AUTO-MIGRATION-MAP -->

## 7.1) Auto migration map (objects by migration)

Generated: **2026-02-05T17:59:23.173Z** (git: `ca671d5`)

Each migration is summarized by the objects it defines. For full SQL, open the file.

### supabase/migrations/20250109_remote_applied_placeholder.sql
- Tables (24): `public.anime`, `public.manga`, `public.episodes`, `public.chapters`, `public.volumes`, `public.characters`, `public.studios`, `public.authors`, `public.staff`, `public.tags`, `public.anime_characters`, `public.manga_characters`, `public.anime_studios`, `public.manga_authors`, `public.anime_staff`, `public.manga_staff`, `public.anime_tags`, `public.manga_tags`, `public.anime_user_lists`, `public.manga_user_lists`, `public.anime_comments`, `public.manga_comments`, `public.external_links`, `public.import_state`, `public.import_runs`, `public.import_locks`
- Functions (5): `public.update_updated_at_column`, `public.normalize_description`, `public.airing_next`, `public.acquire_import_lock`, `public.release_import_lock`
- Views (2): `public.user_lists`, `public.user_airing_next`
- Materialized views (7): `public.mv_anime_trending`, `public.mv_anime_top_rated`, `public.mv_anime_current_season`, `public.mv_anime_newly_added`, `public.mv_manga_trending`, `public.mv_manga_top_rated`, `public.mv_manga_newly_added`
- Cron (1): `kuro-refresh-matviews @ 30 1 * * *` (refreshes all discover matviews; conditional on pg_cron)
- Indexes (50+): external ID lookups, content search (GIN), relationship FKs, user list indexes, FTS, MV unique indexes
- Triggers (12): `update_*_updated_at` (10 tables), `set_anime_description_normalized`, `set_manga_description_normalized`
- RLS + Policies (25 tables enabled; public read on catalog, user-scoped on lists/comments)
- Defensive fixes: `tags.kitsu_id` ADD COLUMN, `comments.user_id` INTEGER→TEXT migration
- *Mostly idempotent* — `CREATE TABLE/INDEX IF NOT EXISTS` and policy guards are true no-ops; `CREATE OR REPLACE FUNCTION/VIEW` and `DROP+CREATE TRIGGER` overwrite definitions (safe if identical to existing)

### supabase/migrations/20250909_remote_applied_placeholder.sql

### supabase/migrations/20250917_remote_applied_placeholder.sql

### supabase/migrations/20260203171100_concierge_core.sql
- Extensions (1): `pg_trgm`
- Tables (6): `public.concierge_runs`, `public.import_session_items`, `public.import_sessions`, `public.profiles`, `public.title_search`, `public.user_taste_profiles`
- Functions (4): `public.log_concierge_run`, `public.normalize_title`, `public.search_titles`, `public.set_updated_at`
- Policies (6): `public.import_session_items:import_session_items_own_all`, `public.import_sessions:import_sessions_own_all`, `public.profiles:profiles_select_own`, `public.profiles:profiles_update_own`, `public.title_search:title_search_select_all`, `public.user_taste_profiles:taste_profiles_own_all`
- Indexes (5): `idx_concierge_runs_user_created`, `idx_import_session_items_session`, `idx_import_sessions_user_created`, `idx_title_search_media`, `idx_title_search_title_norm_trgm`
- Triggers (3): `import_session_items_set_updated_at`, `import_sessions_set_updated_at`, `profiles_set_updated_at`

### supabase/migrations/20260203171110_concierge_title_search_rebuild.sql
- Functions (1): `public.rebuild_title_search`

### supabase/migrations/20260203181000_profiles_insert_policy.sql
- Policies (1): `public.profiles:profiles_insert_own`

### supabase/migrations/20260203183000_concierge_recommend_rpc.sql
- Functions (1): `public.recommend_ids_by_tag_categories`

### supabase/migrations/20260203190000_editorial_recommend_engine.sql
- Tables (2): `public.editorial_boosts`, `public.editorial_penalty_tags`
- Functions (1): `public.recommend_ids_premium`

### supabase/migrations/20260203191500_recommend_focus_tags.sql
- Functions (1): `public.recommend_ids_premium`

### supabase/migrations/20260203194500_recommend_focus_filter.sql
- Functions (1): `public.recommend_ids_premium`

### supabase/migrations/20260203201000_editorial_story_boosts.sql
- Tables (1): `public.editorial_tag_boosts`
- Functions (1): `public.recommend_ids_premium`

### supabase/migrations/20260203203000_recommend_seed_similarity.sql
- Functions (1): `public.recommend_ids_similar_to_seeds`

### supabase/migrations/20260203223000_scale_perf_bundle_and_indexes.sql
- Functions (4): `public.browse_anime_page`, `public.browse_manga_page`, `public.current_season_name`, `public.discover_bundle`
- Indexes (15): `idx_anime_created_id`, `idx_anime_genres_gin`, `idx_anime_next_airing_at`, `idx_anime_popularity_id`, `idx_anime_score_id`, `idx_anime_search_tsv`, `idx_anime_season_year_popularity_id`, `idx_anime_status_popularity_id`, `idx_anime_trending_id`, `idx_manga_created_id`, `idx_manga_genres_gin`, `idx_manga_popularity_id`, `idx_manga_score_id`, `idx_manga_search_tsv`, `idx_manga_trending_id`

### supabase/migrations/20260203224500_browse_rpc_add_created_at.sql
- Functions (2): `public.browse_anime_page`, `public.browse_manga_page`

### supabase/migrations/20260203233500_mirror_runs.sql
- Tables (1): `public.mirror_runs`
- Indexes (1): `idx_mirror_runs_started_at`

### supabase/migrations/20260203235500_search_rpc_keyset.sql
- Extensions (1): `pg_trgm`
- Functions (2): `public.search_anime_page`, `public.search_manga_page`
- Indexes (2): `idx_anime_title_trgm`, `idx_manga_title_trgm`

### supabase/migrations/20260204010500_collection_paging_rpc.sql
- Functions (2): `public.collection_anime_page`, `public.collection_manga_page`
- Indexes (2): `idx_anime_user_lists_user_updated_id`, `idx_manga_user_lists_user_updated_id`

### supabase/migrations/20260204124500_title_aliases.sql
- Tables (1): `public.title_aliases`
- Policies (1): `public.title_aliases:title_aliases_own_all`
- Indexes (2): `idx_title_aliases_user_alias`, `idx_title_aliases_user_updated`
- Triggers (1): `title_aliases_set_updated_at`

### supabase/migrations/20260204133000_collection_feed_paging_rpc.sql
- Functions (1): `public.collection_feed_page`

### supabase/migrations/20260204221500_concierge_rate_limits_and_llm_budgets.sql
- Tables (3): `public.llm_daily_usage`, `public.rate_limit_buckets`, `public.system_flags`
- Functions (5): `public.check_concierge_rate_limit`, `public.is_flag_enabled`, `public.llm_budget_finalize`, `public.llm_budget_reserve`, `public.rate_limit_hit`
- Indexes (1): `idx_rate_limit_buckets_window_start`
- Triggers (3): `llm_daily_usage_set_updated_at`, `rate_limit_buckets_set_updated_at`, `system_flags_set_updated_at`

### supabase/migrations/20260204233000_recommend_seed_similarity_allow_anon.sql
- Functions (1): `public.recommend_ids_similar_to_seeds`

### supabase/migrations/20260204233010_concierge_ops_observability_and_retention.sql
- Extensions (1): `pg_cron`
- Tables (2): `public.concierge_config`, `public.concierge_parse_feedback`
- Views (3): `public.concierge_metrics_hourly`, `public.llm_usage_daily_totals`, `public.rate_limit_recent_top`
- Functions (5): `public.check_concierge_rate_limit`, `public.concierge_housekeeping`, `public.get_concierge_config`, `public.llm_budget_reserve`, `public.log_concierge_parse_feedback`
- Indexes (2): `idx_concierge_parse_feedback_created`, `idx_concierge_parse_feedback_user_created`
- Triggers (1): `concierge_config_set_updated_at`
- Cron (1): `concierge_housekeeping_daily @ 0 4 * * *`

### supabase/migrations/20260204234500_recommend_seed_similarity_ranked_tags.sql
- Functions (1): `public.recommend_ids_similar_to_seeds`

### supabase/migrations/20260204235500_recommend_seed_similarity_genre_gate.sql
- Functions (1): `public.recommend_ids_similar_to_seeds`

### supabase/migrations/20260204240500_backfill_anime_episodes_from_next_airing.sql

### supabase/migrations/20260205000500_concierge_global_llm_budget_and_default_tuning.sql
- Tables (1): `public.llm_global_daily_usage`
- Functions (2): `public.llm_global_budget_finalize`, `public.llm_global_budget_reserve`
- Triggers (1): `llm_global_daily_usage_set_updated_at`

### supabase/migrations/20260205002000_concierge_budget_raise.sql

### supabase/migrations/20260205160000_admin_schema_snapshot.sql
- Functions (1): `public.admin_schema_snapshot`

### supabase/migrations/20260205190000_concierge_modes_config.sql

### supabase/migrations/20260209000000_search_titles_add_cover_image.sql
- Functions (1): `public.search_titles` *(adds cover_image_medium to return set via LEFT JOIN on anime/manga)*

### supabase/migrations/20260209100000_concierge_modes_v7_german_synonyms.sql
- *(config update: adds German synonyms across all 17 modes + umlaut normalization)*

### supabase/migrations/20260209110000_concierge_modes_v8_expanded.sql
- *(config update: adds 6 new modes — mecha, mystery_detective, music_performance, historical, school_coming_of_age, shoujo_josei — total 23 modes)*

### supabase/migrations/20260209120000_new_vibe_rails.sql
- *(seeds 12 new curated rails for v8 modes — total 50 rails)*

### supabase/migrations/20260209135229_import_reconciliation.sql
- Columns (2): `public.import_session_items.import_action` (text, default 'add', CHECK add/update/skip), `public.import_session_items.previous_values` (jsonb)

### supabase/migrations/20260209200000_clubs_foundation.sql
- Tables (7): `public.clubs`, `public.club_members`, `public.club_rails`, `public.club_rail_items`, `public.club_polls`, `public.club_poll_options`, `public.club_votes`
- Functions (1): `public.generate_invite_code`
- Indexes (10): `idx_clubs_invite_code`, `idx_clubs_created_by`, `idx_club_members_user`, `idx_club_members_club`, `idx_club_rails_club_sort`, `idx_club_rail_items_rail_sort`, `idx_club_polls_club_created`, `idx_club_poll_options_poll`, `idx_club_votes_option`, `idx_club_votes_poll`, `idx_club_votes_user`
- Triggers (5): `clubs_set_updated_at`, `club_members_set_updated_at`, `club_rails_set_updated_at`, `club_rail_items_set_updated_at`, `club_polls_set_updated_at`
- RLS enabled on all 7 tables

### supabase/migrations/20260209201000_clubs_rls_policies.sql
- Functions (3): `public.is_club_member`, `public.is_club_admin_or_owner`, `public.is_club_owner` *(all SECURITY DEFINER, SET search_path = public)*
- Policies (25): 4 on clubs, 4 on club_members, 4 on club_rails, 3 on club_rail_items, 4 on club_polls, 3 on club_poll_options, 3 on club_votes

### supabase/migrations/20260209202000_clubs_rpcs.sql
- Functions (9): `public.is_club_member`, `public.is_club_admin_or_owner`, `public.sharing_level_rank`, `public.create_club`, `public.join_club`, `public.leave_club`, `public.fetch_club_bundle`, `public.add_club_rail_item`, `public.cast_club_vote`

### supabase/migrations/20260209220000_club_analytics.sql
- Tables (1): `public.club_analytics`
- Functions (2): `public.log_club_event` (SECURITY DEFINER), `public.concierge_housekeeping` *(extended to prune club_analytics > 90 days)*
- Policies (2): `club_analytics_insert_own`, `club_analytics_select_service`
- Indexes (2): `idx_club_analytics_created_at`, `idx_club_analytics_club_id`

### supabase/migrations/20260209222528_fix_p0_p1_database_issues.sql
- FK NOT NULL constraints added, RLS initplan optimization, anonymous write policies fixed, missing indexes added, duplicate indexes removed *(production-readiness P1-1 through P1-6)*

### supabase/migrations/20260209222542_move_pg_trgm_to_extensions_schema.sql
- Moves `pg_trgm` extension to extensions schema *(P1-10)*

### supabase/migrations/20260209222659_fix_search_path_include_extensions.sql
- Adds extensions schema to `search_path` for RPCs that use `pg_trgm` operators

### supabase/migrations/20260209222728_fix_remaining_functions_search_path.sql
- Fixes `search_path` on remaining functions that reference extensions

### supabase/migrations/20260209224945_fix_mirror_cron_contention.sql
- Alters 5 mirror cron jobs: 15-min spacing, batch size 200, `lockTtlSeconds:120` in payload *(P1-16)*

### supabase/migrations/20260209225348_add_import_secret_to_cron_jobs.sql
- Adds `x-import-secret` header to 4 pg_cron bulk import jobs *(P0-4)*

*(Migrations 20260211–20260215 omitted — feature flags, RAG tables, privacy/GDPR, club identity, rails overlap, concierge flags, club stubs)*

### supabase/migrations/20260216015514_clubs_list_enrichment.sql
- Functions (1): `fetch_my_clubs_enriched()` — SECURITY DEFINER, returns caller's clubs with member_count, last_activity_at, activity_preview

### supabase/migrations/20260216015733_club_reactions_in_bundle.sql
- Updates `fetch_club_bundle()`: adds per-item `reactions` (aggregate counts), `my_reactions` (caller's own), `episode_count`/`chapter_count`, `display_name` from profiles JOIN

### supabase/migrations/20260216015921_clubs_realtime_publication.sql
- Adds `club_rail_items`, `club_polls`, `club_votes`, `club_rail_item_reactions` to `supabase_realtime` publication

### supabase/migrations/20260216020023_club_messages.sql
- Tables (1): `club_messages` (text 1-280 chars, FK CASCADE on user delete)
- Functions (2): `send_club_message()` (SECURITY DEFINER, rate-limited 20/min), `fetch_club_messages()` (SECURITY DEFINER, paginated)
- Policies (3): member-gated SELECT/INSERT, self-only DELETE
- Cron (1): `prune_club_messages` — daily 3 AM UTC, deletes messages > 30 days
- Added `club_messages` to `supabase_realtime` publication


<!-- END AUTO-MIGRATION-MAP -->

---

## 8) Concierge system (detailed)

### Deterministic-first
- `concierge-parse` Edge Function
  - Parses user text (list or vibe)
  - **Input limit**: max 5000 chars (P1-11); returns 400 if exceeded
  - Calls `search_titles` RPC to get candidates (now returns `cover_image_medium`)
  - Logs parse feedback when low-confidence
  - Supports: abbreviations (30+, e.g., AoT/JJK/HxH), seasons (`S2`, `Season 2`), episode markers (`ep 12`, `S2E5`), roman numerals, "completed/caught up" flags, year mentions (e.g., "HxH 2011")
  - Warmup endpoint: `concierge-parse?warmup=true` returns 204 immediately (used by iOS on view appear)
  - Import reconciliation: returns `existing_entry` per item after candidate resolution; proposes Add/Update/Skip actions
  - Items processed in parallel via `Promise.all`

### Disambiguation
- `concierge-resolve` Edge Function
  - LLM fallback (Groq OpenAI-compatible)
  - Uses budgets + rate limits
  - Includes year/format tags in Groq prompts (`[2011] TV`)
  - iOS `conciergeResolve()` client code removed (dead code cleanup)

### Recommendations
- `concierge-recommend` Edge Function
  - Uses deterministic recommendation pipeline first (RPCs)
  - Optional LLM narration (Groq)
  - Supports "seeded" requests (e.g., "like Vagabond") via `recommend_ids_similar_to_seeds`
  - Uses editorial scoring + tag/category inference when no seed is provided
  - **23 vibe modes** (was 17): original 17 + mecha, mystery_detective, music_performance, historical, school_coming_of_age, shoujo_josei
  - 50 curated rails total (12 new for the 6 new modes)
  - German NLP: `GERMAN_VIBE_FORMS` allowlist (15 adjective stems x 5 inflections), `normalizeGermanVibeWords()`, German intent keywords in all `scoreMode()` patterns, umlaut normalization
  - Negative genre suppression: `mapStrongGenreToModeId()` respects excluded genres
  - Auth + rate-limit parallelized via `Promise.all`
  - Primary + secondary rail building parallelized; `fetchMediaContext` (3 DB queries) parallelized; config+tag+boost loading parallelized
  - **groqRouteMode removed** (production-readiness): LLM router stripped; all mode routing is deterministic via `scoreMode()`
  - **Prompt injection sanitization** (P1-13): `sanitizeForLLM()` strips injection patterns (ignore/disregard instructions, system: prefixes, role-play commands, markdown/HTML code blocks) from user text before LLM interpolation in `groqNarrate` and `groqResolve`

### Apply + Undo
- `concierge-apply` writes user list items
  - **Input limit**: max 100 items per request (P1-12); returns 400 if exceeded
  - Supports `action` field: `add` (new entry), `update` (modify existing), `skip` (no-op)
  - TOCTOU protection via `expectedExisting` field
  - Stores `previous_values` for updates (enables undo restoration)
  - Items processed in parallel via `Promise.all`; auth/rate-limit/body-parse parallelized
- `concierge-undo` rolls back last session
  - For `add` actions: deletes the entry
  - For `update` actions: restores `previous_values` snapshot
  - For `skip` actions: no-op
  - Detects manual edits since import (warns instead of reverting if list_type/progress changed)
  - Only allows undo of the most recent applied session

### Budgets + rate limits
- Configured in `public.concierge_config`
- Default as of now (from `supabase/CONCIERGE_OPS.md`):
  - Rate limits (per 60s):
    - parse: user 120/min, ip 300/min
    - recommend: user 20/min, ip 80/min
    - resolve: user 10/min, ip 40/min
    - apply: user 12/min, ip 50/min
    - undo: user 6/min, ip 20/min
  - LLM budgets:
    - per user per day: 50,000 tokens, 40 calls
    - global per day: 1,000,000 tokens, 600 calls
- Rate limits are enforced by RPC `check_concierge_rate_limit`, stored in `rate_limit_buckets`.

### LLM provider
- Groq (OpenAI-compatible endpoint)
- Env vars:
  - `GROQ_API_KEY`
  - `GROQ_MODEL` (default `openai/gpt-oss-20b`)
  - `GROQ_MODEL_RESOLVE` (optional override)

---

### Edge Function contracts (concierge)
**concierge-parse** (deterministic parser)
Request JSON:
- `text` (string, **max 5000 chars** — P1-11)
- `scope` (`anime` | `manga` | `both`, default `both`)
- `limitPerItem` (int, default 10)
- Warmup: `?warmup=true` query param returns 204 immediately

Response JSON:
- `items[]` (parsed lines with candidate lists; each candidate includes `cover_image_medium`)
- `items[].existing_entry` (if user has this title in their list: `{list_type, progress, rating}`)
- `items[].import_action` (`add` | `update` | `skip`)
- `userId` (null if unauthenticated)

**concierge-resolve** (LLM disambiguation)
Request JSON:
- `items[]` (parsed items w/ `raw`, `parsed`, `candidates`)
- `maxCandidates` (int, 2–10)

Response JSON:
- `choices[]` (indexes into candidates)
- `budget_exceeded` / `global_budget_exceeded` flags

**concierge-recommend** (recommendations)
Request JSON:
- `text` (string)
- `scope` (`anime` | `manga` | `both`)
- `limit` (3–20)
- `narrate` (bool)

Response JSON:
- list of recommended items (ids + titles + optional narration)

**concierge-apply** (write to list)
Request JSON:
- `items[]` each with `mediaType`, `mediaId`, `status`, optional progress fields, `action` (`add`/`update`/`skip`), `expectedExisting` (TOCTOU guard) — **max 100 items** (P1-12)

Response JSON:
- `sessionId`
- `applied` count + errors
- Each item stored with `import_action` and `previous_values` (for undo)

**concierge-undo** (rollback)
Request JSON:
- `sessionId` (required; must be the most recent applied session)

Response JSON:
- `success`, `sessionId`, `reverted[]` (with `undoType`: "deleted" or "restored"), `warnings[]`, `errors[]`

<!-- BEGIN AUTO-EDGE-MAP -->

## 8.2) Auto edge-function map (contracts + dependencies)

Generated: **2026-02-05T17:59:23.173Z** (git: `ca671d5`)

### bulk-import-anime
- Source: `supabase/functions/bulk-import-anime/index.ts`
- Env vars: `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, `IMPORT_SECRET`
- **Auth** (P0-4): verifies `x-import-secret` header against `IMPORT_SECRET` env var (pg_cron/pg_net can't send JWTs)
- RPCs: `acquire_import_lock`, `release_import_lock`
- Tables touched: `anime`, `anime_characters`, `anime_staff`, `anime_studios`, `anime_tags`, `characters`, `episodes`, `external_links`, `import_runs`, `import_state`, `staff`, `studios`, `tags`

### bulk-import-manga
- Source: `supabase/functions/bulk-import-manga/index.ts`
- Env vars: `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, `IMPORT_SECRET`
- **Auth** (P0-4): verifies `x-import-secret` header against `IMPORT_SECRET` env var (pg_cron/pg_net can't send JWTs)
- RPCs: `acquire_import_lock`, `release_import_lock`
- Tables touched: `authors`, `chapters`, `characters`, `external_links`, `import_runs`, `import_state`, `manga`, `manga_authors`, `manga_characters`, `manga_staff`, `manga_tags`, `staff`, `tags`, `volumes`

### concierge-apply
- Source: `supabase/functions/concierge-apply/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `log_concierge_run`
- Tables touched: `anime`, `anime_user_lists`, `episodes`, `import_session_items`, `import_sessions`, `manga`, `manga_user_lists`, `title_aliases`

### concierge-parse
- Source: `supabase/functions/concierge-parse/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `get_concierge_config`, `log_concierge_parse_feedback`, `log_concierge_run`, `search_titles`
- Tables touched: `title_aliases`

### concierge-recommend
- Source: `supabase/functions/concierge-recommend/index.ts`
- Env vars: `GROQ_API_KEY`, `GROQ_MODEL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `get_concierge_config`, `is_flag_enabled`, `llm_budget_finalize`, `llm_budget_reserve`, `llm_global_budget_finalize`, `llm_global_budget_reserve`, `log_concierge_run`, `recommend_ids_premium`, `recommend_ids_similar_to_seeds`, `search_titles`
- Tables touched: `editorial_boosts`, `editorial_tag_boosts`, `tags`

### concierge-resolve
- Source: `supabase/functions/concierge-resolve/index.ts`
- Env vars: `GROQ_API_KEY`, `GROQ_MODEL`, `GROQ_MODEL_RESOLVE`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `get_concierge_config`, `is_flag_enabled`, `llm_budget_finalize`, `llm_budget_reserve`, `llm_global_budget_finalize`, `llm_global_budget_reserve`

### concierge-undo
- Source: `supabase/functions/concierge-undo/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `log_concierge_run`
- Tables touched: `anime_user_lists`, `import_session_items`, `import_sessions`, `manga_user_lists`
- Reads `import_action` + `previous_values` columns for reconciliation-aware undo (add=delete, update=restore, skip=no-op)

### mirror-images
- Source: `supabase/functions/mirror-images/index.ts`
- Env vars: `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `acquire_import_lock`, `release_import_lock`
- Tables touched: `anime`, `characters`, `manga`, `mirror_runs`, `staff`
- **Lock fix** (P1-14/P1-16): lock release in `finally` block (was missing on error paths). Per-batch lock keys derived from `mediaTypes:offset` (e.g. `mirror-images:ANIME,MANGA:0`). Lock TTL reduced from 1800s to 120s. Batch size 200 (was 500). Cron jobs spaced 15 min apart (was 10 min).
- **AVIF support** (P2): `getExtFromContentType()` now handles `image/avif` → `.avif` extension.
- **Cache-control** (P2): default changed to `max-age=31536000, immutable` (1 year, immutable) for mirrored images.


<!-- END AUTO-EDGE-MAP -->

---

### Adult content filters
- Default behavior excludes adult content:
  - `is_adult` false
  - tag categories exclude `Sexual Content`
  - filters out `Hentai` and `Ecchi` genres

---

## 8.1) Recommendation engine (editorial)

- `editorial_boosts` and `editorial_penalty_tags` tables bias "premium/classic" picks.
- RPC `recommend_ids_premium` combines:
  - tag match score
  - quality signals (favourites/popularity/score)
  - classic bias (older high-value titles)
  - editorial boosts and penalties
- Results exclude already-listed user titles via `user_lists` view.
- **23 vibe modes** (v8): action, comedy, cozy_slice_of_life, dark_serious, hidden_gems, short_one_season, movie_night, romance_serious, romcom, fantasy_non_isekai, isekai, premium_picks, sports_anime, scifi, horror_supernatural, seinen, shoujo, josei, mecha, mystery_detective, music_performance, historical, school_coming_of_age, shoujo_josei.
- **50 curated rails** total (2 per mode: anime + manga). Pinned via `rail_id` in `concierge_config` modes JSON.
- Mode routing: `scoreMode()` intent boosts + `mapStrongGenreToModeId()` hard-routes. Genre-less modes (school, shoujo_josei) route via synonym matching + `rail_id` pinning. Negative genre suppression respects exclusions.
- German synonyms on all 23 modes from day one.

---

## 9) Scheduled jobs / cron

**Current pg_cron job** (from `supabase/migrations/20260204233010_concierge_ops_observability_and_retention.sql`, extended by `20260209220000_club_analytics.sql`):
- `concierge_housekeeping_daily`
  - Schedule: `0 4 * * *`
  - Function: `public.concierge_housekeeping()`
  - Cleans: rate limit buckets, LLM usage, old import sessions, concierge runs, feedback, mode cache, **club_analytics** (90-day retention)

**Mirror cron jobs** (P1-16: fixed contention — was 58% skip rate):
- 5 `pg_cron` mirror jobs, spaced 15 min apart (02:00, 02:15, 02:30, 02:45, 03:00)
- Batch size: 200 (was 500), per-batch lock keys, 120s TTL (was 1800s)

**Bulk import cron jobs** (P0-4: auth added):
- 4 `pg_cron` bulk import jobs send `x-import-secret` header for auth
- `IMPORT_SECRET` set as Supabase secret; pg_cron jobs updated via migration `20260209225348_add_import_secret_to_cron_jobs.sql`

**Other periodic operations**
- Mirror images can also be run manually via `mirror-images` edge function
- Bulk AniList imports can also be run via scripts or edge functions manually

---

## 9.1) Ops & observability

- Concierge logging: `concierge_runs` + `concierge_parse_feedback`
- Metrics views:
  - `concierge_metrics_hourly`
  - `llm_usage_daily_totals`
  - `rate_limit_recent_top`
- Mirror health: `check_mirror_health()` function returns JSONB with run stats, consecutive failures, and alert boolean
- Ops doc: `supabase/CONCIERGE_OPS.md`
- Scripts:
  - `scripts/check_cron_health.js`
  - `scripts/collect_db_metrics.js`
  - `scripts/load_test_concierge.js`

---

## 10) Data ingestion (sources)

### AniList ingestion
- `scripts/import_anilist_fast.js` / `scripts/run_full_import.js`
- Edge functions: `bulk-import-anime`, `bulk-import-manga`
- Imports include:
  - core anime/manga records
  - episodes/chapters
  - tags/genres
  - staff/character links
  - external links / streaming links (stored in `external_links`)

### Import locking / concurrency
- Edge functions use `acquire_import_lock` + `release_import_lock` to prevent overlapping runs.
- `mirror-images` also uses the same lock mechanism.

### Post-processing
- `mirror-images` edge function for CDN storage
- `title_aliases` for search
- Discover + recommendation engines use dedicated RPCs

---

## 11) Performance + caching

### Client caching
- `ImagePipeline` with memory + disk caching
- SupabaseService uses in-flight task de-duplication for:
  - discover bundle
  - concierge recommend/parse
  - collection feeds
  - upcoming airing windows

### Retry logic (P1-18)
- `SupabaseService.withRetry` — static helper with exponential backoff (max 2 retries, URLError-only; non-network errors thrown immediately)
- Wrapped call sites: `fetchMoreAnime`, `fetchMoreManga`, `fetchDiscoverBundle`, `conciergeParse`, `conciergeRecommend`

### Apple FM synopsis cache
- `AppleFMService.synopsisCache` — `[Int: String]` dictionary keyed on `mediaId` (or `description.hashValue` fallback)
- Populated lazily on first detail view visit; survives navigation but not app restart

### Server performance
- Keyset pagination RPCs for collection + search
- Indexes added in migrations (see `20260203223000_scale_perf_bundle_and_indexes.sql`)

### Pagination defaults
- `SupabaseService` default page size: **50**
- Collection feed uses keyset pagination on `(updated_at, id)` for anime/manga lists
- Browse + Search use RPC paging (`browse_*`, `search_*`)

### Realtime
- `SupabaseService` subscribes to user-scoped realtime channels to keep lists/collection fresh.
- Subscriptions are stopped on sign out.

### Perf instrumentation
- `KuroPerf` is used around heavy RPCs + image fetches for perf logging.

---

## 12) Current UI state (Concierge + Header + Clubs)

- Concierge is a **full page** (left swipe). Uses **inline chat architecture** — no state machine, no full-screen takeovers.
  - `ConciergeDisplayState` enum deleted. Everything renders inline in the chat scroll: typing indicator for loading, inline confirm bubble for imports, editorial rails for recommendations, toast+undo for completion.
  - All UI components use `KuroDesignSystem` tokens (`Font.kuroBody()`, `.kuroCaption()`, `KuroRadius.sm/md/lg`, `KuroAnimation.editorial/fast`, `KuroDesignSpacing.*`).
  - `ConciergeRecCard`: `KuroCachedAsyncImage` + `KuroScoreBadge` overlay, `contextMenu` for save/hide, press state `scaleEffect(0.98)`, KURO watermark on failure. Cards: 130x195pt.
  - `ConciergeConfirmBubble`: inline import review with curated section labels (`NEW`, `UPDATE`, `UNCHANGED`) and concise action summary.
  - Auto-apply: high-confidence imports (all items score >= 0.85, no ambiguous adaptations) auto-apply with undo toast.
- Header left is **only KURO text**.
- A small **chat icon** appears next to the section title **only on Concierge page**.
- Profile is a **top-right menu** (not a dedicated page).
- **Swipe pager**: 5 pages in order: Concierge (0) ← **Discover** (1, default) → Browse (2) → Collection (3) → Clubs (4). Natural discovery funnel: find → collect → share.
- **Clubs** is the 5th page (rightmost). Profile sheet also has a "Clubs" shortcut. Club list cards show member count, activity preview, and unread dot. Club detail has 4 tabs (Rails/This Week/Polls/Chat). Reactions (fire/heart/eyes/100) on rail items. Pace tracking on This Week. Milestone celebrations. Realtime updates. Badge dot on Clubs page indicator for unseen activity.
- **Browse** is a first-class page (3rd position), no longer a sheet modal.
- **Search** remains a global sheet accessible from the header magnifying-glass icon on any page.
- **Performance**: distance-based page mounting (current ± 1 neighbors mounted, distant pages use placeholder). `.snappy(duration: 0.22)` pager animation. 120fps ProMotion enabled via `CADisableMinimumFrameDurationOnPhone`. Exclusion zone filtering limited to viewport.
- **Detail views** (AnimeDetailView, MangaDetailView):
  - **Synopsis condenser**: descriptions > 200 chars are condensed to 2-sentence hooks via `fmService.condenseSynopsis()` on supported devices; falls back to full description on non-FM devices.
  - **Next Up picks**: `NextUpSection` (anime) and `MangaNextUpSection` (manga) show personalized next episode/chapter recommendations based on user progress.
- **Offline banner**: monochrome "OFFLINE" text at top of `RootView` when `networkMonitor.isConnected == false`.

---

## 13) Build + run

- Xcode project: `Kuro.xcodeproj`
- Scheme: `Kuro`
- Default simulator: iPhone 17 Pro (iOS 26.0)

---

## 13.1) Quality gates

Quality gate scripts live in `scripts/quality-gates/` with a pre-commit hook in `.githooks/pre-commit`.

### Gate scripts (5 gates + runner + test data)
1. **`check_secrets.sh`** — Scans Swift/TypeScript/JavaScript for hardcoded secrets (service_role JWTs, sbp_/sk-/gsk_ keys). No false-positive on publishable anon key (by design: only flags service_role patterns). Whitelists test fixtures and env var references.
2. **`check_migrations.sh`** — Checks for untracked/modified SQL files in `supabase/migrations/`, generates/verifies SHA-256 checksums (`.checksums` file). Read-only by default; pass `--update` to write checksums. Warning-only (no hard fail on modified migrations).
3. **`test_router_offline.sh`** — Runs `router_test_cases.js` which tests `scoreMode()` / `mapStrongGenreToModeId()` logic offline (no network). Hard fail on test failure.
4. **`audit_rails.sh`** — Wraps `scripts/audit_curated_rails_quality.js` (prefers env vars for Supabase credentials). Hard fail on: adult content, overlap > 40%, rail size > 100 or < 5, score below floor, franchise duplicates. Warning on: overlap > 15%, rail size near limits. Runs in both JSON and human-readable mode.
5. **`build_ios.sh`** — Runs `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`. Hard fail on build error.
6. **`run_all.sh`** — Orchestrator: runs all 5 gates, prints summary table, exits 1 if any blocking gate fails. Supports `SKIP_IOS_BUILD=1` and `SKIP_RAILS_AUDIT=1` env vars for faster runs.

### Pre-commit hook
- File: `.githooks/pre-commit` (install: `git config core.hooksPath .githooks`)
- Fast checks on staged files only:
  1. Secrets scan: checks `git diff --cached` for JWT/sbp_/sk-/gsk_ patterns in .swift/.ts/.js files. Blocks commit if found.
  2. Migration hygiene: warns on non-standard migration name prefix for staged SQL files.
- Compatible with bash 3.2 (macOS default).

---

## 13.2) TestFlight / Fastlane deployment

### How to push a new TestFlight build

```bash
fastlane beta
```

This single command:
1. Auto-increments the build number (reads latest from App Store Connect, adds 1)
2. Archives `Kuro.xcodeproj` (scheme `Kuro`, automatic signing, `generic/platform=iOS`)
3. Uploads to TestFlight via App Store Connect API

### Configuration files

| File | Purpose |
|------|---------|
| `fastlane/Appfile` | Team ID (`YLG68JL5Y7`), Bundle ID (`com.Kuro.app`), App ID (`6759221230`) |
| `fastlane/Fastfile` | `beta` lane definition (build + upload) |
| `~/.appstoreconnect/private_keys/AuthKey_7L84A7P9X7.p8` | API key for App Store Connect auth (NOT in repo) |

### Auth (API Key — no password/2FA needed)

- **Key ID**: `7L84A7P9X7`
- **Issuer ID**: `bca97a4b-8a3a-4051-9c89-510f10db0b06`
- **Key file**: `~/.appstoreconnect/private_keys/AuthKey_7L84A7P9X7.p8`
- Fastlane reads these automatically from the `api_key` block in the Fastfile.

### Signing

- `CODE_SIGN_STYLE = Automatic`
- `-allowProvisioningUpdates` in Fastlane xcargs
- Apple Distribution certificate (YLG68JL5Y7), expires 2027-01-27

### Entitlements

- `Kuro.entitlements` contains:
  - `com.apple.developer.applesignin`
  - `com.apple.developer.associated-domains` — placeholder `applinks:kuro.app` for deep linking (Universal Links)
- Foundation Models does **NOT** need an entitlement (just `import FoundationModels` + `#available(iOS 26, *)`)

### Current build

- **Version**: 1.0
- **Latest build**: 2 (uploaded 2026-02-15)
- **Bundle ID**: `com.Kuro.app` (capital K)

---

## 14) Change Log (append-only)

- 2026-02-17: **Detail page error feedback + accessibility fix** — `EpisodesSection`/`EpisodeListSheet` (AnimeDetailView) and `ChaptersSection`/`ChapterListSheet` (MangaDetailView) now show error toast to user when `markWatched`/`markRead` fails (was only `#if DEBUG` print). Thread `onError` callback from parent detail views; list sheets have own toast state + overlay. `ChapterItemRow` accessibility hint changed from hardcoded "Opens on AniList" to generic "Opens external link". Commit: `504716c`.
- 2026-02-16: **P2 production blockers completed — backend hardening, iOS bug fixes, accessibility, deep linking** —
  - **Backend**: Migration `catalog_created_at_not_null` backfilled NULLs + set NOT NULL on `created_at` for 8 catalog tables. Migration `drop_unused_indexes_merge_policies_health_check` dropped 12 unused indexes (FTS/trigram superseded by title_search MV, duplicate genre GIN, unused sort indexes), merged duplicate club_members DELETE policies into single `club_members_delete_self_or_admin`, created `check_mirror_health()` JSONB function. Mirror-images edge function: AVIF support in `getExtFromContentType()`, cache-control changed to `max-age=31536000, immutable`.
  - **iOS bug fixes**: Vote error handling in ClubDetailView (do/catch with `.error` toast + `errorHaptic()`). Task.detached cancellation in ConciergeView (tracked `@State` task refs: warmupTask, prefetchTask, prefetchTask2, backgroundRefreshTask, backgroundRefreshTask2; consolidated `.onDisappear` cancellation). Per-rail error state in EditorialDiscoverView (`@State loadError` with inline retry view on first-load failure).
  - **Accessibility pass**: ClubDetailView (`.isHeader` on section headers), ClubsView (`.accessibilityLabel` on empty state + club cards), EditorialCollectionView (`.isHeader` on section headers), EditorialDiscoverView (`.isHeader` on section titles + error state label), ConciergeView/Components (message bubbles "You said:"/"Concierge:", rail headers `.isHeader`, clarification cards combined labels), ConciergeRecommendationRails (`.isHeader` on rail title).
  - **Deep linking**: `DeepLinkRouter.swift` (new) with `enum DeepLink` — cases for anime(id:), manga(id:), club(id:), collection, discover, concierge(prompt:); parses `kuro://` scheme URLs. `KuroApp.swift` `.onOpenURL` handler passes `pendingDeepLink` binding to ContentView. ContentView navigates to page for page-level links, presents detail sheet for anime/manga/club links. `Kuro.entitlements` updated with Associated Domains placeholder (`applinks:kuro.app`).
  - Files changed: `ContentView.swift`, `Kuro.entitlements`, `KuroApp.swift`, `ClubDetailView.swift`, `ClubsView.swift`, `ConciergeComponents.swift`, `ConciergeInputField.swift`, `ConciergeRecommendationRails.swift`, `ConciergeView.swift`, `EditorialCollectionView.swift`, `EditorialDiscoverView.swift`, `mirror-images/index.ts`. New file: `DeepLinkRouter.swift`.
- 2026-02-16: **Add-to-rail from ClubDetailView + adaptive card sizing** — "+" button per club rail opens `AddItemToRailSheet` (server-side search via `search_anime_page`/`search_manga_page` RPCs, debounced, typed `PostgrestError` handling for DUPLICATE_ITEM/NOT_A_MEMBER/RAIL_LOCKED/MEDIA_NOT_FOUND). Gated by lock status + role. Member identity labels use stable 6-char UUID hex prefix instead of positional "Member N". Search task lifecycle managed via `.onDisappear` cancellation. `fetchSearchAnimePage`/`fetchSearchMangaPage` exposed as internal. Adaptive card sizing: removed misleading `containerWidth` default (393pt), all surfaces now pass explicit screen/geometry width. `KuroCompactCard` width adaptive via `floor((screenWidth - 56) / 2.8)` clamped [112, 144] in SimilarSection, MangaSimilarSection, KuroHorizontalSection. GenreHubView passes `screenWidth` to all 10 section call sites. Commit: `5273f21`.
- 2026-02-16: **Clubs Enhancement — 6-phase feature expansion** —
  - **Phase 0**: Verified existing stub RPCs (`create_club_rail`, `create_club_poll`, `toggle_club_reaction`) were already complete on remote DB.
  - **Phase 1 (List Enrichment)**: New `fetch_my_clubs_enriched()` RPC returns member_count, last_activity_at, activity_preview per club. `ClubsView` cards now show member count icon, 1-line activity preview, and unread dot (UserDefaults-backed last-seen timestamps). Replaced two-query `fetchMyClubs()` with single enriched RPC.
  - **Phase 2 (Reactions)**: Updated `fetch_club_bundle()` to include per-item `reactions` (anonymous aggregate counts) and `my_reactions` (caller's own). New `ClubReactionRow` with 4 emoji capsules (fire/heart/eyes/100), optimistic toggle, monochrome palette.
  - **Phase 3 (Progress Sync)**: Client-only pace tracking using median of member progress. Shows "3 ep behind the group" / "In sync" / "2 ep ahead" on This Week items (only when sharing_level=progress and ≥3 members). Milestone celebration cards when all members complete a title.
  - **Phase 4 (Realtime)**: Added 5 tables to `supabase_realtime` publication. iOS subscribes to per-club Realtime channel on detail view appear, 500ms debounce triggers bundle refresh. Unsubscribes on disappear.
  - **Phase 5 (Chat)**: `club_messages` table (280 char max, FK CASCADE, 30-day auto-prune cron). `send_club_message` RPC (rate-limited 20/min) + `fetch_club_messages` RPC (paginated). New CHAT tab in `ClubDetailView` with reversed ScrollView, `ClubChatBubble` (member initial + name + relative time), text input with send button. Real-time message delivery via Supabase Realtime.
  - **Phase 6 (Notifications)**: In-app badge dot on Clubs page indicator when unseen club activity exists. `checkClubNotifications()` calls `check_club_activity_since` RPC. Badge cleared on navigate to Clubs. Foreground check on `willEnterForeground`.
  - **Feature flags** (6 new): `clubs_list_enriched_v1` (100%), `clubs_reactions_v1` (50%), `clubs_pace_sync_v1` (100%), `clubs_realtime_v1` (50%), `clubs_chat_v1` (0% staged), `clubs_notifications_v1` (100%).
  - **Migrations** (4): `clubs_list_enrichment`, `club_reactions_in_bundle`, `clubs_realtime_publication`, `club_messages`.
  - Files changed: `SupabaseService.swift`, `SupabaseRPCParams.swift`, `FeatureFlags.swift`, `ClubsView.swift`, `ClubDetailView.swift`, `ContentView.swift`.
- 2026-02-15: **5-page swipe pager restored + performance polish** —
  - Swipe pager expanded from 3 pages to 5: Concierge ← [Discover] → Browse → Collection → Clubs. Natural discovery funnel order.
  - Browse promoted from sheet modal to first-class page (position 2). Search remains a global sheet from header icon.
  - Clubs elevated from ProfileView sub-sheet to its own page (position 4, rightmost). ProfileView still has Clubs as secondary access path.
  - `ClubsView` `NavigationStack` removed; club detail now opens as sheet (pager pages are bare views).
  - Distance-based page mounting: current page + immediate neighbors mounted; distant pages use `Color(.systemBackground)` placeholder. `mountedSections` set retained as fallback for visited/launch-argument pages.
  - Pager animation changed from `.interactiveSpring(response: 0.28)` to `.snappy(duration: 0.22, extraBounce: 0.02)` for crisper transitions.
  - 120fps ProMotion enabled via `INFOPLIST_KEY_CADisableMinimumFrameDurationOnPhone = YES` in both Debug and Release build settings.
  - Exclusion zone filtering: viewport intersection check + equality guard prevents unnecessary `swipeExclusions` state mutations during animation.
  - BrowseView image prefetch increased from 32 to 48 items.
  - Header dot indicators automatically show 5 dots. "Browse" removed from profile menu. `showBrowseSheet` state eliminated.
  - Files changed: `ContentView.swift`, `ClubsView.swift`, `BrowseView.swift`, `project.pbxproj`. Commit: `172b3f7`.
- 2026-02-15: **43 UX improvements + TestFlight deployment** —
  - **16-agent team** shipped 43 UX audit improvements across discover, collection, browse, search, detail pages, concierge, and settings. +4142/-1908 lines across 46 files.
  - **Senior code audit fixes**: German umlaut typo fixed (`OnboardingView.swift:73` "Uberspringen" → "Überspringen"), Apple Sign In nonce cleanup (`AuthView.swift` defer block), monochrome palette violation fixed (`ProfileView.swift` deletion spinner red → black.opacity(0.55)).
  - **Bundle ID**: Changed from `com.kuro.app` to `com.Kuro.app` to match App Store Connect registration.
  - **App icon**: Generated 1024x1024 placeholder icon (white K on dark background) in `Assets.xcassets/AppIcon.appiconset/`.
  - **Fastlane configured**: `fastlane/Appfile` (team + bundle ID), `fastlane/Fastfile` (beta lane: auto-increment build number, archive, upload to TestFlight). API Key auth via `.p8` file. Run `fastlane beta` to push new builds.
  - **TestFlight build live**: Build 2, version 1.0 uploaded to App Store Connect (App ID: 6759221230). Foundation Models code compiled in but no entitlement needed — FM framework works without a special entitlement (confirmed via App Store Connect API: capability type does not exist in provisioning system). FM features activate on iOS 26 devices with Apple Intelligence enabled.
  - **Entitlements**: `Kuro.entitlements` contains only `com.apple.developer.applesignin`. Foundation Models does NOT require an entitlement — just `import FoundationModels` + availability guards. The "Foundation Models Framework Adapter Entitlement" in the Developer Portal is only for custom-trained LoRA adapters, not basic `@Generable` usage.
  - **Distribution certificate**: Apple Distribution (YLG68JL5Y7), expires 2027/01/27.
  - **Signing**: Automatic (`CODE_SIGN_STYLE = Automatic`), `-allowProvisioningUpdates` flag in Fastlane build step.
  - `.gitignore` updated: added Fastlane artifacts + `*.p8` exclusion.
- 2026-02-14: **Concierge + Clubs activity copy polish** —
  - `Kuro/Views/DetailPages/ClubActivitySection.swift`: fixed member status rendering so per-member rows now use real watch/read progress and explicit “not started” state; removed placeholder “Member” text path and generic sharing-level misuse.
  - `Kuro/Services/SupabaseService.swift`: added concierge/club interaction telemetry points (`clubs_add_to_rail_*`) and helper state for remember-last-club UX in add-to-rail sheet.
  - `Kuro/Views/ConciergeComponents.swift`: introduced curated copy layer for concierge presentation:
    - internal mode IDs map to editorial titles/subtitles in EN/DE (`ConciergeCuratedCopy`);
    - concise curator notes are always rendered above recommendation sets when available;
    - entry/clarify copy avoids raw mode naming in the UI.
  - Commit references: `e874b34`, `d73da13`.
- 2026-02-09: **Production Readiness + Apple FM + Network Monitor** —
  - **Apple Foundation Models service** (new): `Kuro/Services/AppleFMService.swift` — `@MainActor @Observable` class implementing `FMProvider` protocol. 4 capabilities: mode classification (5s timeout), disambiguation (8s timeout), synopsis condensation (10s timeout), NL collection search intent parsing (5s timeout). 4 `@Generable` structs with `@Guide` annotations (`FMDisambiguationOutput`, `FMModeOutput`, `FMSynopsisOutput`, `FMSearchIntentOutput`). `StubFMProvider` for non-FM devices. `withFMTimeout` helper using `ThrowingTaskGroup`. Synopsis cache `[Int: String]`. Guards: `#if canImport(FoundationModels)` + `#available(iOS 26, *)`. Integrated into `SupabaseService.fmService`.
  - **Synopsis condenser**: `AnimeDetailView` + `MangaDetailView` call `fmService.condenseSynopsis()` for descriptions > 200 chars. Shows spoiler-free 2-sentence hook on supported devices.
  - **NL collection search**: `parseSearchIntent()` extracts genre/status/year/keywords from natural language queries for collection filtering.
  - **Next Up picks**: `NextUpSection` (anime) and `MangaNextUpSection` (manga) structs in detail views showing personalized next episode/chapter recommendations.
  - **NetworkMonitor** (new): `Kuro/Services/NetworkMonitor.swift` — `@MainActor @Observable` class using `NWPathMonitor`. Tracks `isConnected` + `connectionType` (wifi/cellular/wired/unknown). Injected as `@Environment` throughout app. Monochrome "OFFLINE" banner in `RootView`.
  - **App lifecycle**: `scenePhase` handling added to `KuroApp.swift` (P0-3).
  - **P0 production blockers fixed**:
    - P0-2: Network handling (NetworkMonitor)
    - P0-3: App lifecycle (scenePhase in KuroApp.swift)
    - P0-4: Bulk import auth (`IMPORT_SECRET` env var + `x-import-secret` header in bulk-import-anime/manga)
    - P0-6: Storage MIME types restricted to jpeg/png/webp/avif/gif
    - P0-7: Storage RLS policies (read public, write/delete authenticated, service_role full)
  - **P1 production blockers fixed**:
    - P1-1 through P1-6: DB FK NOT NULL constraints, RLS initplan optimization, anonymous write policies fixed, missing indexes added, duplicate indexes removed (migration: `fix_p0_p1_database_issues`)
    - P1-10: pg_trgm moved to extensions schema (migration: `move_pg_trgm_to_extensions_schema`)
    - P1-11: concierge-parse 5000 char text limit
    - P1-12: concierge-apply 100 item array cap
    - P1-13: LLM prompt injection sanitization (`sanitizeForLLM()` in concierge-recommend: strips injection patterns, markdown/HTML, role-play commands)
    - P1-14: mirror-images lock release in finally block (was missing on error paths)
    - P1-15: Storage 5MB file size limit
    - P1-16: Mirror cron contention fixed — per-batch lock keys (`mirror-images:ANIME,MANGA:0`), 120s TTL (was 1800s), 200 batch size (was 500), 15-min spacing (was 10)
    - P1-17: All 64 `print()` statements wrapped in `#if DEBUG`
    - P1-18: Retry logic (`SupabaseService.withRetry` — exponential backoff, URLError-only, 5 key call sites: fetchMoreAnime, fetchMoreManga, fetchDiscoverBundle, conciergeParse, conciergeRecommend)
    - P1-19: `UIScreen.main` deprecation fixed (removed all references)
  - **Edge function changes**: concierge-recommend: removed `groqRouteMode` + LLM router (all routing deterministic); `sanitizeForLLM()` added. concierge-parse: 5000 char limit. concierge-apply: 100 item cap. bulk-import-anime/manga: `IMPORT_SECRET` header auth. mirror-images: lock release fix + per-batch keys + 120s TTL.
  - **DB migrations applied**: `fix_p0_p1_database_issues`, `move_pg_trgm_to_extensions_schema`, `fix_search_path_include_extensions`, `fix_remaining_functions_search_path`, `fix_mirror_cron_contention`, `add_import_secret_to_cron_jobs`.
  - **Infrastructure**: xcconfig files created (`Config/Shared.xcconfig`, `Config/Debug.xcconfig`, `Config/Release.xcconfig`). `AppConfig.swift` reads from Info.plist/env with hardcoded anon key fallback. `IMPORT_SECRET` set as Supabase secret. 4 pg_cron bulk import jobs updated with `x-import-secret` header.
  - **Mock SupabaseService**: cleaned up, removed dead type references, added `fmService` property.
- 2026-02-09: **Clubs + Import Reconciliation + Quality Gates + Phase 5 Polish** —
  - **Clubs feature (new)**: Private groups (2-20 members) with curated rails, polls, and privacy-by-design sharing levels. 7 new tables (`clubs`, `club_members`, `club_rails`, `club_rail_items`, `club_polls`, `club_poll_options`, `club_votes`) with full RLS (25 policies + 4 helper functions). 6 RPCs (`create_club`, `join_club`, `leave_club`, `fetch_club_bundle`, `add_club_rail_item`, `cast_club_vote`) + 3 helper functions (`is_club_member`, `is_club_admin_or_owner`, `sharing_level_rank`) + `generate_invite_code`. iOS: `ClubsView` (6th page in swipe pager) + `ClubDetailView` (3-tab: Rails/This Week/Polls) + `ClubActivitySection` on media detail views + Create/Join sheets + Settings sheet. Migrations: `20260209200000_clubs_foundation.sql`, `20260209201000_clubs_rls_policies.sql`, `20260209202000_clubs_rpcs.sql`.
- **Import reconciliation**: Detects existing entries during concierge parse and proposes Add/Update/Skip actions. `concierge-parse` returns `existing_entry` per item after candidate resolution. `concierge-apply` respects `action` field (add/update/skip) with TOCTOU protection via `expectedExisting`. Undo for updates restores `previous_values` snapshot. `concierge-undo` handles add (delete), update (restore previous_values), skip (no-op). iOS `ConciergeConfirmBubble` shows grouped sections (`NEW`, `UPDATE`, `UNCHANGED`). Migration: `20260209135229_import_reconciliation.sql` (adds `import_action` + `previous_values` columns to `import_session_items`). Files: `ConciergeView.swift`, `concierge-parse/index.ts`, `concierge-apply/index.ts`, `concierge-undo/index.ts`.
  - **Quality gates (new)**: 5 gate scripts in `scripts/quality-gates/`: `check_secrets.sh` (secret detection, no false-positive on anon key), `check_migrations.sh` (migration hygiene, read-only by default), `test_router_offline.sh` + `router_test_cases.js` (offline mode router tests), `audit_rails.sh` (curated rails quality audit via `audit_curated_rails_quality.js`, prefers env vars), `build_ios.sh` (xcodebuild check). `run_all.sh` orchestrator. `.githooks/pre-commit` hook for staged-file secrets + migration name checks.
  - **Club telemetry**: `public.club_analytics` table (RLS: authenticated insert own, service_role select). `log_club_event` RPC (SECURITY DEFINER). 90-day retention via extended `concierge_housekeeping()` cron. Migration: `20260209220000_club_analytics.sql`.
  - **Haptics polished**: Club create/join use `.medium` impact (was `.success` notification). Import confirm uses `.medium` (was `.light`). Vote cast `.light`. Empty states improved: rails tab shows add prompt for admins, This Week text updated.
  - **Owner transfer UX**: Leave club confirmation dialog now context-aware: owners see "Ownership will transfer to [member]..." or "This club will be deleted" based on member/admin roster. Regular members see "Leave [club name]?".
  - **Build verified**: `xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` passes with zero errors.
- 2026-02-09: **Concierge redesign — inline chat architecture, visual token alignment, German NLP, curation expansion** —
  - **State machine removed**: Deleted `ConciergeDisplayState` enum and all 5 full-screen subviews (`ConciergeThinkingView`, `ConciergeConfirmingView`, `ConciergePresentingView`, `ConciergeDoneView`, `PresentCard`/`ConfirmRow`). ConciergeView.swift rewritten from 1313→707 lines. Everything now renders inline in chat: typing indicator for loading, inline confirm bubble for imports, editorial rails for recommendations, toast+undo for completion.
- **Visual token alignment**: All concierge UI components now use `KuroDesignSystem` tokens (`Font.kuroBody()`, `.kuroCaption()`, `KuroRadius.sm/md/lg`, `KuroAnimation.editorial/fast`, `KuroDesignSpacing.*`). Removed all hardcoded font sizes, corner radii, and spring animations. User bubble double-background eliminated (removed glassBubble wrapping solid black). Typing indicator kept lightweight and intentionally calm.
- **Editorial recommendation cards**: `ConciergeRecCard` redesigned with `KuroCachedAsyncImage`, `KuroScoreBadge` overlay, `contextMenu` for save/hide (replaces visible buttons), press state `scaleEffect(0.98)`, KURO watermark on failure. Cards: 130x195pt. Rail headers now use curator-facing titles/subtitles in EN/DE and softer typography.
- **Inline confirm bubble**: `ConciergeConfirmBubble` renders import review inline in chat with concise section labels (`NEW`, `UPDATE`, `UNCHANGED`) and a compact confirm action. No full-screen takeover.
  - **Auto-apply**: High-confidence imports (all items score >= 0.85, no ambiguous adaptations) auto-apply immediately with undo toast. Mixed confidence shows inline confirm bubble.
  - **Performance**: Edge function warmup on concierge view appear (`conciergeWarmup()` fires `concierge-parse?warmup=true`). Auth+rate-limit parallelized in `concierge-recommend` via `Promise.all`. Dead code removed: `conciergeResolve()` + `ConciergeResolveResponse` (~70 lines).
  - **German NLP hardening**: Added `GERMAN_VIBE_FORMS` allowlist (15 adjective stems × 5 inflections) + `normalizeGermanVibeWords()` in concierge-recommend. German intent keywords added to all `scoreMode()` patterns (wantsClassic/Hidden/Short/Movie/Mature/Sports/SciFi/Horror/Cozy + 6 new modes). Umlaut normalization (ü→ue, ö→oe, ä→ae, ß→ss) applied to both user text and synonyms. iOS `looksLikeImport()` updated with German vibe exclusion markers.
  - **Curation expansion**: 6 new vibe modes (23 total): `mecha`, `mystery_detective`, `music_performance`, `historical`, `school_coming_of_age`, `shoujo_josei`. 12 new curated rails (50 total). All modes have German synonyms from day one. Routing via `scoreMode()` intent boosts + `mapStrongGenreToModeId()` hard-routes. Genre-less modes (`school`, `shoujo_josei`) route via synonym matching + `rail_id` pinning.
  - Migrations: `20260209100000_concierge_modes_v7_german_synonyms.sql`, `20260209110000_concierge_modes_v8_expanded.sql`, `20260209120000_new_vibe_rails.sql`.
  - Files modified: `ConciergeView.swift` (major rewrite), `ConciergeComponents.swift` (shared concierge UI components), `SupabaseService.swift` (added warmup, deleted resolve), `concierge-recommend/index.ts` (German NLP + new intents + auth parallel).
- 2026-02-09: **Concierge images wired** — `search_titles()` RPC now returns `cover_image_medium` via `coalesce(a.cover_image_medium, m.cover_image_medium)` (migration `20260209000000_search_titles_add_cover_image.sql`). `ConciergeCandidate` Swift struct gains `cover_image_medium: String?`. Import preview (`ConfirmRow`) and recommendation carousel (`PresentCard`) now use `KuroCachedAsyncImage` with gradient fallback instead of static `LinearGradient` placeholders.
- 2026-02-09: **P0 fix — progress data forwarding** — `confirmImport()` in ConciergeView.swift now forwards all parsed progress fields (`progressEpisodes`, `progressChapters`, `progressVolumes`, `seasonNumber`, `episodeInSeason`, `caughtUp`, `lastEpisode`, `completed`) to the `concierge-apply` edge function. Previously all imports landed with progress=0.
- 2026-02-09: **Performance parallelization** — All 3 concierge edge functions parallelized: `concierge-parse` processes items via `Promise.all` (was serial for-loop) + parallelizes search queries within each item; `concierge-apply` processes items via `Promise.all` + parallelizes auth/rate-limit/body-parse; `concierge-recommend` parallelizes primary+secondary rail building, `fetchMediaContext` (3 DB queries), curated rail anime/manga fetches, seed similarity fetches, config+tag+boost loading, and LLM flag checks. iOS post-apply fetches (`fetchUserLists`, `fetchCollectionItems`, `fetchCollectionFeed`) parallelized with `async let`. Expected 2-5x latency reduction.
- 2026-02-08: **Adaptation disambiguation** — `concierge-parse` extracts year mentions from input (e.g. "HxH 2011"), boosts candidates matching that year (+0.25), and strips year mentions from trigram search queries. `concierge-resolve` includes year/format tags in Groq prompts (`[2011] TV`) and passes them through in the response. iOS auto-apply guard blocks auto-selection when top 2 candidates share a base title but differ in `media_id` (e.g. HxH 1999 vs 2011), unless the user's year mention resolves ambiguity. Deployed to Supabase Edge Functions (verify with `supabase functions list --project-ref bkdifromsqxkndnllmdj`).
- 2026-02-08: **Negative genre mode suppression** — `mapStrongGenreToModeId()` respects excluded genres (e.g. "action but no romance" no longer routes to romcom). `scoreMode()` penalizes modes whose required_genres overlap with excluded genres. Router eval hardened: exponential backoff for 429/5xx and infra errors separated from routing failures. Deployed to Supabase Edge Functions (verify with `supabase functions list --project-ref bkdifromsqxkndnllmdj`).
- 2026-02-08: **Curated content overhaul** — Phase 0: removed ~200 sequel entries (one-entry-per-franchise), purged misclassified items (Sailor Moon/Precure from isekai, IDOLiSH7 from dark_serious), deduped cross-rail overlap (94% → 36%), slimmed all rails to 30-80 targets, fixed classics (removed post-2014, added Akira/Galaxy Express 999/Macross DYRL/Rurouni Kenshin). Phase 1: added 3 new vibe modes (Sports, Sci-Fi, Horror/Supernatural) + 11 new rails + 5 demographic rails (seinen/shoujo/josei). Phase 2: expanded parser abbreviations (10→30), added negative genre filtering ("no romance"/"without harem"), updated mode router for new modes, deployed concierge-parse v30 + concierge-recommend v29. Phase 3: enhanced audit script (overlap/franchise/year/size/score checks), created `concierge_mode_analytics` table. Total: 23 modes, 50 curated rails, 63 migrations.
- 2026-02-08: **UI cleanup** — removed genre text (Action, Adventure) from all card types across the app (EditorialDiscoverView, EditorialCollectionView, EditorialSearchView, EditorialCards, Cards). Tightened title-to-meta spacing on compact and grid cards.
- 2026-02-08: Pinned the default fallback mode (`premium_picks`, surfaced as **The Cut**) to curated rails so vague prompts ("recommend something") return consistent results. Migrations: `20260208091500_curated_rails_premium_picks_seed.sql`, `20260208092000_concierge_modes_v6_add_premium_picks_rail_id.sql`. Config expanded through v8 with German synonyms and 6 additional modes.
- 2026-02-08: Refined pinned curated rails that were producing off-vibe picks: `short_one_season_*` is now truly short (<=13 eps, FINISHED) and `fantasy_non_isekai_*` now excludes ongoing and caps length (FINISHED, <=60 eps / <=220 chapters). Migration: `20260208090000_refine_short_and_fantasy_rails.sql`.
- 2026-02-07: Added pinned curated vibe rails for core internal modes (`premium_action`, `premium_comedy_grownup`, `cozy_comfort`, `dark_serious`, `hidden_gems`) and wired them into Concierge via `rail_id` config. Migrations: `20260207011000_curated_rails_vibes_seed.sql`, `20260207012000_concierge_modes_v4_add_vibe_rail_ids.sql`.
- 2026-02-07: Improved disambiguation by enriching `search_titles()` with `year` + `format` (used by Concierge parse/resolve + iOS auto-apply safety). Migration: `20260207000000_search_titles_enrich_year_format.sql`.
- 2026-02-06: Security hardening: enabled RLS on 5 unprotected tables (`editorial_boosts`, `editorial_penalty_tags`, `editorial_tag_boosts`, `import_state`, `mirror_runs`) + switched 5 views to SECURITY INVOKER. Migration: `20260206150000_security_hardening_rls_and_views.sql`.
- 2026-02-06: Deleted legacy edge functions `Bulk-import-anime` (capital B, v7) and `manga-bulk-import-` (trailing dash, v5). Active functions now: 8.
- 2026-02-06: Concierge UI polish: signal badges (MASTERPIECE/CLASSIC/MATCH) now visible on recommendation cards, serif title fonts, editorial divider on rail headers, larger import candidate hit targets (10→12px), serif CONCIERGE header + editorial divider on intro card.
- 2026-02-06: Curated rail expansion: +366 editorial picks (90 classics_anime, 97 classics_manga, 75 gateway_anime, 104 gateway_manga). All picks verified: no Ecchi/Hentai genres, score >= 76 (classics) / >= 78 (gateway). Removed problematic picks from initial draft (ecchi-tagged, low-score). Fixed candidate generation script criteria. Migration: `20260206120000_curated_rails_expansion.sql`.
- 2026-02-06: Baseline schema SQL captured in `supabase/migrations/20250109_remote_applied_placeholder.sql`: consolidates legacy root SQL (02-14) **plus** remote-only objects (`import_runs`, `import_locks`, lock RPCs, 7 materialized views incl. `mv_anime_current_season`, and the `kuro-refresh-matviews` pg_cron job). Defensive fixes for `tags.kitsu_id` and `comments.user_id` type drift. Original SQL files moved to `legacy_sql/`.
- 2026-02-06: Removed iOS dead code: `ConciergeOverlay.swift`, `KuroChanMascot.swift`, `getByMood()`, `#if false SearchViewNew` block (~500 lines total).
- 2026-02-06: Concierge modes expanded to 14 (v3) and deployed: added `short_one_season`, `movie_night`, `romance_serious`, `romcom`, `fantasy_non_isekai`, `isekai`. Enriched synonyms (incl. German) across all modes. Migration: `20260206100000_concierge_modes_v3_expanded.sql`. Edge function deployed: `supabase/functions/concierge-recommend/index.ts`.
- 2026-02-05: Concierge recommend perf: reuse shared candidate pools + media context across rails to reduce DB queries/latency. Commit: `ca671d5`
- 2026-02-05: Concierge recommendations: added configurable **vibe modes** (2 curated rails per prompt) + expanded Classics rail; response now includes `modes` + `sets` (backwards compatible `items`). Commits: `3bcc32f`, `a23e5b8`, `d1efdb0`
- 2026-02-05: Added full "include everything" documentation pipeline (source excerpts + codebase bundle) and optional live DB snapshot tooling (`admin_schema_snapshot`). Commits: `889b9c8`, `7a87228`, `7d07be7`, `c2d0414`, `5eb4168`, `9c734db`
- 2026-02-05: Redacted Supabase secrets from docs and from generated bundles/excerpts (docs remain reflective, but credentials are never inlined). Commits: `590e8a0`, `8da8b68`, `68f9a11`, `bce062f`, `16d3826`, `c8b9c3a`
- 2026-02-05: Added auto-generated inventory + maps (migrations, edge functions, iOS RPC usage) via scripts.
- 2026-02-05: Added deep appendices (data dictionary, RPC catalog, edge function examples, operator runbook).
- 2026-02-05: Expanded CURRENT_APP_STATE with appendices (full DDL + concierge guardrails).
- 2026-02-05: Added/expanded CURRENT_APP_STATE docs with full technical + plain-English snapshots.
- 2026-02-05: Concierge left page + profile menu. Header simplified. Cards show `YEAR · EPS`. Concierge intro + quick-start glass pills added. Commits: `e8430fe`, `2451b46`

---

## 15) Open Questions / Unknowns

- **User ID type mismatch**: Club tables use `user_id UUID REFERENCES auth.users(id)`, but legacy tables (`anime_user_lists`, `manga_user_lists`) use `user_id TEXT`. All joins between club_members and user-list tables must cast: `cm.user_id::text = aul.user_id`. A future migration may unify them.
- Materialized view definitions in the foundation migration are inferred from usage (discover_bundle RPC + Swift client). If the remote MV definitions differ (e.g., different LIMIT, extra WHERE clauses), update the foundation to match.
- v8 modes (23 total) are deployed; if you add new modes later, deploy with `supabase db push --linked` + `supabase functions deploy concierge-recommend --linked`.
- **Hardcoded Supabase secret key** in `Kuro/Services/SupabaseService.swift:27` — allowed through GitHub push protection temporarily. Must rotate the key and move to env/Info.plist/xcconfig before shipping.
- **Apple FM availability**: `AppleFMService` gracefully degrades on non-FM devices via `StubFMProvider`. The `condenseSynopsis` cache is in-memory only (lost on app restart); consider persisting to disk if cache hit rates are low.
- **xcconfig files** (`Config/`) are created but not yet wired into Xcode build configurations. Wiring them is a prerequisite for removing hardcoded keys.

---

## 16) Appendix A — Core Schema DDL (now in `supabase/migrations/20250109_remote_applied_placeholder.sql`; original files archived in `legacy_sql/`)

```sql
-- ============================================
-- COMPREHENSIVE TABLE CREATION SCRIPT
-- Optimal structure with internal IDs + external references
-- ============================================

-- ============================================
-- 1. ANIME TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE anime (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Basic Info
    title_english TEXT,
    title_romaji TEXT,
    title_native TEXT,
    title_synonyms TEXT[],
    
    -- Visual
    cover_image_large TEXT,
    cover_image_medium TEXT,
    cover_image_color TEXT,
    banner_image TEXT,
    
    -- Anime-specific
    format TEXT, -- 'TV', 'MOVIE', 'OVA', 'ONA', 'SPECIAL'
    status TEXT, -- 'FINISHED', 'RELEASING', 'NOT_YET_RELEASED'
    description TEXT,
    description_normalized TEXT,
    
    -- Episodes
    episodes INTEGER,
    duration INTEGER, -- minutes per episode
    total_duration INTEGER, -- total runtime in minutes
    season TEXT, -- 'SPRING', 'SUMMER', 'FALL', 'WINTER'
    season_year INTEGER,
    
    -- Airing schedule
    next_episode_number INTEGER,
    next_airing_at TIMESTAMP WITH TIME ZONE,
    
    -- Dates
    start_date_year INTEGER,
    start_date_month INTEGER,
    start_date_day INTEGER,
    end_date_year INTEGER,
    end_date_month INTEGER,
    end_date_day INTEGER,
    
    -- Ratings
    average_score INTEGER,
    mean_score INTEGER,
    popularity INTEGER,
    trending INTEGER,
    favourites INTEGER,
    
    -- Content
    genres TEXT[],
    source TEXT,
    country_of_origin TEXT,
    is_adult BOOLEAN DEFAULT false,
    age_rating TEXT,
    
    -- External links
    site_url TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at_anilist TIMESTAMP WITH TIME ZONE
);

-- ============================================
-- 2. MANGA TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE manga (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Basic Info
    title_english TEXT,
    title_romaji TEXT,
    title_native TEXT,
    title_synonyms TEXT[],
    
    -- Visual
    cover_image_large TEXT,
    cover_image_medium TEXT,
    cover_image_color TEXT,
    banner_image TEXT,
    
    -- Manga-specific
    format TEXT, -- 'MANGA', 'NOVEL', 'ONE_SHOT', 'DOUJINSHI', 'MANHWA', 'MANHUA'
    status TEXT, -- 'FINISHED', 'RELEASING', 'NOT_YET_RELEASED', 'HIATUS'
    description TEXT,
    description_normalized TEXT,
    
    -- Chapters/Volumes
    chapters INTEGER,
    volumes INTEGER,
    
    -- Chapter schedule
    next_chapter_number INTEGER,
    next_chapter_at TIMESTAMP WITH TIME ZONE,
    
    -- Dates
    start_date_year INTEGER,
    start_date_month INTEGER,
    start_date_day INTEGER,
    end_date_year INTEGER,
    end_date_month INTEGER,
    end_date_day INTEGER,
    
    -- Ratings
    average_score INTEGER,
    mean_score INTEGER,
    popularity INTEGER,
    trending INTEGER,
    favourites INTEGER,
    
    -- Content
    genres TEXT[],
    source TEXT,
    country_of_origin TEXT,
    is_adult BOOLEAN DEFAULT false,
    age_rating TEXT,
    
    -- External links
    site_url TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at_anilist TIMESTAMP WITH TIME ZONE
);

-- ============================================
-- 3. EPISODES TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE episodes (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Episode info
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    
    -- Airing info
    air_date DATE,
    air_at TIMESTAMP WITH TIME ZONE,
    thumbnail TEXT,
    duration INTEGER, -- minutes
    
    -- Episode metadata
    is_filler BOOLEAN DEFAULT false,
    is_recap BOOLEAN DEFAULT false,
    is_mixed BOOLEAN DEFAULT false,
    filler_source TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 4. CHAPTERS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE chapters (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Chapter info
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    
    -- Release info
    release_date DATE,
    release_at TIMESTAMP WITH TIME ZONE,
    thumbnail TEXT,
    pages INTEGER,
    
    -- Chapter metadata
    is_side_story BOOLEAN DEFAULT false,
    is_extra BOOLEAN DEFAULT false,
    is_omake BOOLEAN DEFAULT false,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 5. VOLUMES TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE volumes (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Volume info
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    
    -- Visual
    cover_image_large TEXT,
    cover_image_medium TEXT,
    
    -- Release info
    release_date DATE,
    release_at TIMESTAMP WITH TIME ZONE,
    pages INTEGER,
    
    -- Volume metadata
    isbn TEXT,
    price_jpy INTEGER,
    price_usd DECIMAL(10,2),
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 6. CHARACTERS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE characters (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Character info
    name_full TEXT,
    name_native TEXT,
    name_alternative TEXT[],
    
    -- Visual
    image_large TEXT,
    image_medium TEXT,
    
    -- Character details
    description TEXT,
    gender TEXT, -- 'Male', 'Female', 'Non-binary', 'Unknown'
    age INTEGER,
    birthday DATE,
    blood_type TEXT, -- 'A', 'B', 'AB', 'O', 'Unknown'
    
    -- Physical attributes
    height INTEGER, -- cm
    weight INTEGER, -- kg
    hair_color TEXT,
    eye_color TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 7. STUDIOS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE studios (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Studio info
    name TEXT NOT NULL,
    name_romaji TEXT,
    name_native TEXT,
    
    -- Studio details
    description TEXT,
    is_animation_studio BOOLEAN DEFAULT false,
    is_producer BOOLEAN DEFAULT false,
    is_licensor BOOLEAN DEFAULT false,
    
    -- External
    site_url TEXT,
    favourites INTEGER DEFAULT 0,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 8. AUTHORS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE authors (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Author info
    name_full TEXT,
    name_native TEXT,
    name_romaji TEXT,
    
    -- Visual
    image_large TEXT,
    image_medium TEXT,
    
    -- Author details
    description TEXT,
    birth_date DATE,
    death_date DATE,
    hometown TEXT,
    blood_type TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 9. STAFF TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE staff (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Staff info
    name_full TEXT,
    name_native TEXT,
    name_romaji TEXT,
    
    -- Visual
    image_large TEXT,
    image_medium TEXT,
    
    -- Staff details
    description TEXT,
    primary_occupations TEXT[], -- ['Director', 'Writer', 'Music', 'Character Design']
    birth_date DATE,
    death_date DATE,
    hometown TEXT,
    blood_type TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 10. TAGS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE tags (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Tag info
    name TEXT NOT NULL,
    name_romaji TEXT,
    name_native TEXT,
    description TEXT,
    
    -- Tag metadata
    category TEXT, -- 'Genre', 'Theme', 'Demographic', 'Content'
    is_general_spoiler BOOLEAN DEFAULT false,
    is_media_spoiler BOOLEAN DEFAULT false,
    is_adult BOOLEAN DEFAULT false,
    rank INTEGER DEFAULT 0,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 11. RELATIONSHIP TABLES (All use INTERNAL IDs)
-- ============================================

-- Anime-Character relationship
CREATE TABLE anime_characters (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Main', 'Supporting', 'Background'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, character_id)
);

-- Manga-Character relationship
CREATE TABLE manga_characters (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Main', 'Supporting', 'Background'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, character_id)
);

-- Anime-Studio relationship
CREATE TABLE anime_studios (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    studio_id INTEGER REFERENCES studios(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Animation', 'Production', 'Licensor'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, studio_id)
);

-- Manga-Author relationship
CREATE TABLE manga_authors (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    author_id INTEGER REFERENCES authors(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Story', 'Art', 'Story & Art', 'Supervision'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, author_id)
);

-- Anime-Staff relationship
CREATE TABLE anime_staff (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    staff_id INTEGER REFERENCES staff(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Director', 'Writer', 'Music', 'Character Design'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, staff_id)
);

-- Manga-Staff relationship
CREATE TABLE manga_staff (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    staff_id INTEGER REFERENCES staff(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Editor', 'Publisher', 'Translator'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, staff_id)
);

-- Anime-Tag relationship
CREATE TABLE anime_tags (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    tag_id INTEGER REFERENCES tags(id) ON DELETE CASCADE, -- INTERNAL reference
    rank INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, tag_id)
);

-- Manga-Tag relationship
CREATE TABLE manga_tags (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    tag_id INTEGER REFERENCES tags(id) ON DELETE CASCADE, -- INTERNAL reference
    rank INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, tag_id)
);

-- ============================================
-- 12. USER INTERACTION TABLES (All use INTERNAL IDs)
-- ============================================

-- Anime user lists
CREATE TABLE anime_user_lists (
    id SERIAL PRIMARY KEY, -- Auto-increment for user list entry ID
    user_id INTEGER NOT NULL, -- Your user system ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    list_type TEXT NOT NULL, -- 'WATCHING', 'COMPLETED', 'PLANNING', 'DROPPED', 'PAUSED'
    progress INTEGER DEFAULT 0, -- episodes watched
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, anime_id)
);

-- Manga user lists
CREATE TABLE manga_user_lists (
    id SERIAL PRIMARY KEY, -- Auto-increment for user list entry ID
    user_id INTEGER NOT NULL, -- Your user system ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    list_type TEXT NOT NULL, -- 'READING', 'COMPLETED', 'PLANNING', 'DROPPED', 'PAUSED'
    progress INTEGER DEFAULT 0, -- chapters read
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, manga_id)
);

-- Anime comments
CREATE TABLE anime_comments (
    id SERIAL PRIMARY KEY, -- Auto-increment for comment ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    user_id INTEGER NOT NULL, -- Your user system ID
    comment TEXT NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    is_spoiler BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Manga comments
CREATE TABLE manga_comments (
    id SERIAL PRIMARY KEY, -- Auto-increment for comment ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    user_id INTEGER NOT NULL, -- Your user system ID
    comment TEXT NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    is_spoiler BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 13. PERFORMANCE INDEXES
-- ============================================

-- Primary entity indexes (INTERNAL IDs)
CREATE INDEX idx_anime_id ON anime(id);
CREATE INDEX idx_manga_id ON manga(id);
CREATE INDEX idx_episodes_id ON episodes(id);
CREATE INDEX idx_chapters_id ON chapters(id);
CREATE INDEX idx_volumes_id ON volumes(id);
CREATE INDEX idx_characters_id ON characters(id);
CREATE INDEX idx_studios_id ON studios(id);
CREATE INDEX idx_authors_id ON authors(id);
CREATE INDEX idx_staff_id ON staff(id);
CREATE INDEX idx_tags_id ON tags(id);

-- External ID indexes (for sync)
CREATE INDEX idx_anime_anilist_id ON anime(anilist_id);
CREATE INDEX idx_anime_mal_id ON anime(mal_id);
CREATE INDEX idx_manga_anilist_id ON manga(anilist_id);
CREATE INDEX idx_manga_mal_id ON manga(mal_id);
CREATE INDEX idx_characters_anilist_id ON characters(anilist_id);
CREATE INDEX idx_characters_mal_id ON characters(mal_id);
CREATE INDEX idx_studios_anilist_id ON studios(anilist_id);
CREATE INDEX idx_studios_mal_id ON studios(mal_id);
CREATE INDEX idx_authors_anilist_id ON authors(anilist_id);
CREATE INDEX idx_authors_mal_id ON authors(mal_id);
CREATE INDEX idx_staff_anilist_id ON staff(anilist_id);
CREATE INDEX idx_staff_mal_id ON staff(mal_id);
CREATE INDEX idx_tags_anilist_id ON tags(anilist_id);
CREATE INDEX idx_tags_mal_id ON tags(mal_id);

-- Content indexes
CREATE INDEX idx_anime_title_english ON anime(title_english);
CREATE INDEX idx_anime_title_romaji ON anime(title_romaji);
CREATE INDEX idx_anime_status ON anime(status);
CREATE INDEX idx_anime_popularity ON anime(popularity DESC);
CREATE INDEX idx_anime_average_score ON anime(average_score DESC);
CREATE INDEX idx_anime_genres ON anime USING GIN(genres);
CREATE INDEX idx_anime_season_year ON anime(season_year);
CREATE INDEX idx_anime_next_airing ON anime(next_airing_at);

CREATE INDEX idx_manga_title_english ON manga(title_english);
CREATE INDEX idx_manga_title_romaji ON manga(title_romaji);
CREATE INDEX idx_manga_status ON manga(status);
CREATE INDEX idx_manga_popularity ON manga(popularity DESC);
CREATE INDEX idx_manga_average_score ON manga(average_score DESC);
CREATE INDEX idx_manga_genres ON manga USING GIN(genres);
CREATE INDEX idx_manga_next_chapter ON manga(next_chapter_at);

-- Relationship indexes (INTERNAL IDs)
CREATE INDEX idx_anime_characters_anime_id ON anime_characters(anime_id);
CREATE INDEX idx_anime_characters_character_id ON anime_characters(character_id);
CREATE INDEX idx_manga_characters_manga_id ON manga_characters(manga_id);
CREATE INDEX idx_manga_characters_character_id ON manga_characters(character_id);
CREATE INDEX idx_anime_studios_anime_id ON anime_studios(anime_id);
CREATE INDEX idx_anime_studios_studio_id ON anime_studios(studio_id);
CREATE INDEX idx_manga_authors_manga_id ON manga_authors(manga_id);
CREATE INDEX idx_manga_authors_author_id ON manga_authors(author_id);
CREATE INDEX idx_anime_staff_anime_id ON anime_staff(anime_id);
CREATE INDEX idx_anime_staff_staff_id ON anime_staff(staff_id);
CREATE INDEX idx_manga_staff_manga_id ON manga_staff(manga_id);
CREATE INDEX idx_manga_staff_staff_id ON manga_staff(staff_id);
CREATE INDEX idx_anime_tags_anime_id ON anime_tags(anime_id);
CREATE INDEX idx_anime_tags_tag_id ON anime_tags(tag_id);
CREATE INDEX idx_manga_tags_manga_id ON manga_tags(manga_id);
CREATE INDEX idx_manga_tags_tag_id ON manga_tags(tag_id);

-- User interaction indexes
CREATE INDEX idx_anime_user_lists_user_id ON anime_user_lists(user_id);
CREATE INDEX idx_anime_user_lists_anime_id ON anime_user_lists(anime_id);
CREATE INDEX idx_anime_user_lists_list_type ON anime_user_lists(list_type);
CREATE INDEX idx_manga_user_lists_user_id ON manga_user_lists(user_id);
CREATE INDEX idx_manga_user_lists_manga_id ON manga_user_lists(manga_id);
CREATE INDEX idx_manga_user_lists_list_type ON manga_user_lists(list_type);
CREATE INDEX idx_anime_comments_anime_id ON anime_comments(anime_id);
CREATE INDEX idx_anime_comments_user_id ON anime_comments(user_id);
CREATE INDEX idx_manga_comments_manga_id ON manga_comments(manga_id);
CREATE INDEX idx_manga_comments_user_id ON manga_comments(user_id);

-- ============================================
-- 14. AUTO-UPDATE TRIGGERS
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for all tables
CREATE TRIGGER update_anime_updated_at BEFORE UPDATE ON anime FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_manga_updated_at BEFORE UPDATE ON manga FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_episodes_updated_at BEFORE UPDATE ON episodes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_chapters_updated_at BEFORE UPDATE ON chapters FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_volumes_updated_at BEFORE UPDATE ON volumes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_characters_updated_at BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_studios_updated_at BEFORE UPDATE ON studios FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_authors_updated_at BEFORE UPDATE ON authors FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_staff_updated_at BEFORE UPDATE ON staff FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_tags_updated_at BEFORE UPDATE ON tags FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 15. ROW LEVEL SECURITY (RLS)
-- ============================================

-- Enable RLS on all tables
ALTER TABLE anime ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga ENABLE ROW LEVEL SECURITY;
ALTER TABLE episodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE chapters ENABLE ROW LEVEL SECURITY;
ALTER TABLE volumes ENABLE ROW LEVEL SECURITY;
ALTER TABLE characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE studios ENABLE ROW LEVEL SECURITY;
ALTER TABLE authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_studios ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_user_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_user_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_comments ENABLE ROW LEVEL SECURITY;

-- Create policies for public read access
CREATE POLICY "Public read access" ON anime FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga FOR SELECT USING (true);
CREATE POLICY "Public read access" ON episodes FOR SELECT USING (true);
CREATE POLICY "Public read access" ON chapters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON volumes FOR SELECT USING (true);
CREATE POLICY "Public read access" ON characters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON studios FOR SELECT USING (true);
CREATE POLICY "Public read access" ON authors FOR SELECT USING (true);
CREATE POLICY "Public read access" ON staff FOR SELECT USING (true);
CREATE POLICY "Public read access" ON tags FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_characters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_characters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_studios FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_authors FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_staff FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_staff FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_tags FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_tags FOR SELECT USING (true);

-- User-specific policies for user lists and comments
CREATE POLICY "Users can manage their own lists" ON anime_user_lists USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can manage their own lists" ON manga_user_lists USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can manage their own comments" ON anime_comments USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can manage their own comments" ON manga_comments USING (auth.uid()::text = user_id::text);

-- ============================================
-- 16. VERIFICATION
-- ============================================

-- Verify all tables were created
SELECT 
    schemaname,
    tablename,
    tableowner
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;

-- Verify all indexes were created
SELECT 
    schemaname,
    tablename,
    indexname
FROM pg_indexes 
WHERE schemaname = 'public' 
ORDER BY tablename, indexname;

-- Verify all triggers were created
SELECT 
    trigger_name,
    event_object_table,
    action_timing,
    event_manipulation
FROM information_schema.triggers 
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

```

---

## 17) Appendix B — Core Views + Aux Tables

### 08_create_user_lists_view.sql
```sql
-- ============================================
-- CREATE UNIFIED VIEW: user_lists
-- Bridges anime_user_lists and manga_user_lists into a single shape expected by the app
-- ============================================

CREATE OR REPLACE VIEW public.user_lists AS
SELECT
  aul.id AS id,
  aul.user_id::text AS user_id,
  aul.anime_id AS media_id,
  'anime'::text AS media_type,
  aul.list_type AS status,
  aul.progress AS progress,
  NULL::integer AS progress_volumes,
  CASE WHEN aul.rating IS NULL THEN NULL ELSE aul.rating * 10 END AS score,
  aul.notes AS notes,
  NULL::timestamp with time zone AS started_at,
  NULL::timestamp with time zone AS completed_at,
  FALSE AS private,
  aul.created_at AS created_at,
  aul.updated_at AS updated_at
FROM public.anime_user_lists aul
UNION ALL
SELECT
  mul.id AS id,
  mul.user_id::text AS user_id,
  mul.manga_id AS media_id,
  'manga'::text AS media_type,
  mul.list_type AS status,
  mul.progress AS progress,
  NULL::integer AS progress_volumes,
  CASE WHEN mul.rating IS NULL THEN NULL ELSE mul.rating * 10 END AS score,
  mul.notes AS notes,
  NULL::timestamp with time zone AS started_at,
  NULL::timestamp with time zone AS completed_at,
  FALSE AS private,
  mul.created_at AS created_at,
  mul.updated_at AS updated_at
FROM public.manga_user_lists mul;

-- Optional helper indexes on the view via materialized pattern could be added if needed.

```

### 09_import_state.sql
```sql
-- Cursor table for scheduled imports
CREATE TABLE IF NOT EXISTS public.import_state (
  media_type text PRIMARY KEY, -- 'ANIME' | 'MANGA'
  last_page integer NOT NULL DEFAULT 0,
  updated_at timestamp with time zone DEFAULT now()
);

-- Seed rows if not present
INSERT INTO public.import_state (media_type, last_page)
VALUES ('ANIME', 0)
ON CONFLICT (media_type) DO NOTHING;

INSERT INTO public.import_state (media_type, last_page)
VALUES ('MANGA', 0)
ON CONFLICT (media_type) DO NOTHING;

```

### 10_create_user_airing_next_view.sql
```sql
-- ============================================
-- CREATE USER-SCOPED UPCOMING AIRINGS VIEW (ANIME)
-- Only includes titles saved by a user, with a future next_airing_at
-- Requires: 12_fix_user_id_type.sql must be run FIRST
-- ============================================

CREATE OR REPLACE VIEW public.user_airing_next AS
SELECT
  aul.user_id        AS user_id,           -- TEXT (after migration)
  a.id               AS anime_id,          -- anime PK
  a.title_english    AS title_english,
  a.title_romaji     AS title_romaji,
  a.next_episode_number AS next_episode_number,
  a.next_airing_at   AS next_airing_at,
  aul.list_type      AS list_type,         -- WATCHING, COMPLETED, etc.
  aul.progress       AS progress,          -- Episodes watched
  aul.updated_at     AS list_updated_at
FROM public.anime_user_lists aul
JOIN public.anime a ON a.id = aul.anime_id
WHERE a.next_airing_at IS NOT NULL
  AND a.next_airing_at > now()
ORDER BY a.next_airing_at ASC;

-- Notes:
-- - RLS applies on underlying tables
-- - Client should filter: WHERE user_id = auth.uid()::text
-- - Can add additional filters for date windows (e.g., next 7 days)
-- - Ordered by airing date (soonest first)

-- Verification query (optional):
-- SELECT * FROM user_airing_next WHERE user_id = auth.uid()::text LIMIT 5;
```

### 11_airing_next_rpc.sql
```sql
-- ============================================
-- OPTIONAL: RPC to fetch the caller's upcoming airings within N days
-- Uses auth.uid() for scoping; SECURITY INVOKER respects RLS
-- Requires: 12_fix_user_id_type.sql must be run FIRST
-- ============================================

CREATE OR REPLACE FUNCTION public.airing_next(days integer DEFAULT 7)
RETURNS TABLE(
  anime_id int,
  title_english text,
  title_romaji text,
  next_episode_number int,
  next_airing_at timestamptz,
  list_type text,
  progress int
) AS $$
  SELECT
    a.id,
    a.title_english,
    a.title_romaji,
    a.next_episode_number,
    a.next_airing_at,
    aul.list_type,
    aul.progress
  FROM public.anime a
  JOIN public.anime_user_lists aul ON aul.anime_id = a.id
  WHERE aul.user_id = auth.uid()::text  -- Matches TEXT user_id
    AND a.next_airing_at IS NOT NULL
    AND a.next_airing_at BETWEEN now() AND (now() + (days || ' days')::interval)
  ORDER BY a.next_airing_at ASC
  LIMIT 500;
$$ LANGUAGE sql SECURITY INVOKER STABLE;

-- Notes:
-- - SECURITY INVOKER: Executes with caller's permissions (respects RLS)
-- - STABLE: Query result doesn't change within transaction (optimization)
-- - Returns up to 500 upcoming episodes within specified days window
-- - Ordered by airing date (soonest first)

-- Usage example:
-- SELECT * FROM airing_next(7);  -- Next 7 days
-- SELECT * FROM airing_next(1);  -- Next 24 hours
```

### 13_alter_episodes_add_stream_fields.sql
```sql
-- Adds streaming link fields to episodes for Watch CTA support
ALTER TABLE public.episodes
  ADD COLUMN IF NOT EXISTS stream_url TEXT;

ALTER TABLE public.episodes
  ADD COLUMN IF NOT EXISTS stream_site TEXT;
```

### 14_create_external_links.sql
```sql
-- Stores curated external streaming links for anime/manga detail CTAs
CREATE TABLE IF NOT EXISTS public.external_links (
  id SERIAL PRIMARY KEY,
  media_type TEXT CHECK (media_type IN ('ANIME','MANGA')) NOT NULL,
  media_id INT NOT NULL,
  site TEXT,
  url TEXT NOT NULL,
  language TEXT,
  color TEXT,
  priority INT DEFAULT 999,
  is_disabled BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(media_type, media_id, url)
);

CREATE INDEX IF NOT EXISTS idx_external_links_media ON public.external_links(media_type, media_id);

ALTER TABLE public.external_links ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  BEGIN
    CREATE POLICY "Public read access" ON public.external_links FOR SELECT USING (true);
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END;
$$;
```

### 20260204124500_title_aliases.sql
```sql
-- User-specific title aliases for "magic" parsing.
-- Stores previously-confirmed mappings from noisy user input -> canonical media id.

begin;

create table if not exists public.title_aliases (
  user_id uuid not null references auth.users(id) on delete cascade,
  alias_norm text not null,
  media_type text not null check (media_type in ('ANIME','MANGA')),
  media_id integer not null,
  title_raw text,
  hits integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, alias_norm, media_type)
);

create index if not exists idx_title_aliases_user_updated on public.title_aliases (user_id, updated_at desc);
create index if not exists idx_title_aliases_user_alias on public.title_aliases (user_id, alias_norm);

alter table public.title_aliases enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='title_aliases' and policyname='title_aliases_own_all'
  ) then
    create policy title_aliases_own_all on public.title_aliases
      for all
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'title_aliases_set_updated_at') then
    create trigger title_aliases_set_updated_at
      before update on public.title_aliases
      for each row execute function public.set_updated_at();
  end if;
end $$;

commit;

```

### 20260203233500_mirror_runs.sql
```sql
begin;

-- Track mirror-images runs so schedules can be verified and failures diagnosed.
create table if not exists public.mirror_runs (
  id bigserial primary key,
  status text not null default 'running', -- running | success | error | skipped
  payload jsonb,
  results jsonb,
  message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  duration_ms integer
);

create index if not exists idx_mirror_runs_started_at on public.mirror_runs (started_at desc);

commit;

```

---

## 18) Appendix C — Concierge Guardrails + Budgets DDL

### 20260204221500_concierge_rate_limits_and_llm_budgets.sql
```sql
-- Server-side guardrails for Concierge:
-- - Rate limits (per-user and per-IP) for Edge Functions
-- - LLM daily budget + global kill-switch flag

begin;

-- 1) Kill switch / flags (readable via SECURITY DEFINER function).
create table if not exists public.system_flags (
  key text primary key,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.system_flags enable row level security;

-- No policies: clients cannot read flags directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'system_flags_set_updated_at') then
    create trigger system_flags_set_updated_at
      before update on public.system_flags
      for each row execute function public.set_updated_at();
  end if;
end $$;

insert into public.system_flags(key, enabled)
values ('llm_enabled', true)
on conflict (key) do nothing;

create or replace function public.is_flag_enabled(p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v boolean;
begin
  select enabled into v from public.system_flags where key = p_key;
  return coalesce(v, true);
end $$;

grant execute on function public.is_flag_enabled(text) to anon, authenticated;

-- 2) Rate limit buckets (atomic upsert increments).
create table if not exists public.rate_limit_buckets (
  bucket_key text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (bucket_key, window_start)
);

create index if not exists idx_rate_limit_buckets_window_start on public.rate_limit_buckets (window_start desc);

alter table public.rate_limit_buckets enable row level security;
-- No policies: users cannot read/write buckets directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'rate_limit_buckets_set_updated_at') then
    create trigger rate_limit_buckets_set_updated_at
      before update on public.rate_limit_buckets
      for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.rate_limit_hit(
  p_bucket_key text,
  p_window_seconds integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare wstart timestamptz;
declare v integer;
begin
  if p_bucket_key is null or length(p_bucket_key) = 0 then
    raise exception 'rate_limit_hit: missing bucket_key';
  end if;
  if p_window_seconds is null or p_window_seconds < 1 or p_window_seconds > 86400 then
    raise exception 'rate_limit_hit: invalid window_seconds';
  end if;

  -- Fixed window bucket aligned to epoch.
  wstart := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);

  insert into public.rate_limit_buckets(bucket_key, window_start, hits)
  values (p_bucket_key, wstart, 1)
  on conflict (bucket_key, window_start)
  do update set hits = public.rate_limit_buckets.hits + 1, updated_at = now()
  returning hits into v;

  return v;
end $$;

grant execute on function public.rate_limit_hit(text, integer) to anon, authenticated;

create or replace function public.check_concierge_rate_limit(
  p_kind text,
  p_ip text,
  p_window_seconds integer default 60,
  p_max_user integer default 40,
  p_max_ip integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare u_hits integer;
declare ip_hits integer;
declare allow boolean := true;
declare retry_after integer;
declare kind text;
begin
  uid := auth.uid();
  kind := coalesce(nullif(p_kind, ''), 'any');

  if uid is null and (p_ip is null or length(p_ip) = 0) then
    return jsonb_build_object('allowed', true, 'note', 'no uid/ip');
  end if;

  if uid is not null then
    u_hits := public.rate_limit_hit('user:' || uid::text || ':' || kind || ':' || p_window_seconds::text, p_window_seconds);
    if u_hits > coalesce(p_max_user, 0) then allow := false; end if;
  end if;

  if p_ip is not null and length(p_ip) > 0 then
    ip_hits := public.rate_limit_hit('ip:' || p_ip || ':' || kind || ':' || p_window_seconds::text, p_window_seconds);
    if ip_hits > coalesce(p_max_ip, 0) then allow := false; end if;
  end if;

  retry_after := p_window_seconds - (extract(epoch from now())::integer % p_window_seconds);
  return jsonb_build_object(
    'allowed', allow,
    'user_hits', u_hits,
    'ip_hits', ip_hits,
    'retry_after_s', retry_after
  );
end $$;

grant execute on function public.check_concierge_rate_limit(text, text, integer, integer, integer) to anon, authenticated;

-- 3) LLM daily budget (reserve + finalize to keep budgets accurate and concurrency-safe).
create table if not exists public.llm_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  reserved_tokens integer not null default 0,
  actual_tokens integer not null default 0,
  calls integer not null default 0,
  last_model text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.llm_daily_usage enable row level security;
-- No policies: users cannot read/write usage directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'llm_daily_usage_set_updated_at') then
    create trigger llm_daily_usage_set_updated_at
      before update on public.llm_daily_usage
      for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.llm_budget_reserve(
  p_reserved_tokens integer,
  p_max_daily_tokens integer default 20000,
  p_max_daily_calls integer default 80,
  p_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare d date;
declare used_tokens integer;
declare used_calls integer;
declare next_tokens integer;
declare next_calls integer;
declare allow boolean;
declare lock_key bigint;
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;

  lock_key := hashtext(uid::text || ':' || d::text || ':llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  select
    coalesce(actual_tokens, 0) + coalesce(reserved_tokens, 0),
    coalesce(calls, 0)
  into used_tokens, used_calls
  from public.llm_daily_usage
  where user_id = uid and day = d;

  next_tokens := coalesce(used_tokens, 0) + p_reserved_tokens;
  next_calls := coalesce(used_calls, 0) + 1;

  allow :=
    next_tokens <= coalesce(p_max_daily_tokens, 0)
    and next_calls <= coalesce(p_max_daily_calls, 0);

  if allow then
    insert into public.llm_daily_usage(user_id, day, reserved_tokens, actual_tokens, calls, last_model)
    values (uid, d, p_reserved_tokens, 0, 1, p_model)
    on conflict (user_id, day)
    do update set
      reserved_tokens = public.llm_daily_usage.reserved_tokens + excluded.reserved_tokens,
      calls = public.llm_daily_usage.calls + 1,
      last_model = coalesce(excluded.last_model, public.llm_daily_usage.last_model),
      updated_at = now();
  end if;

  return jsonb_build_object(
    'allowed', allow,
    'day', d::text,
    'used_tokens', coalesce(used_tokens, 0),
    'used_calls', coalesce(used_calls, 0),
    'next_tokens', next_tokens,
    'next_calls', next_calls,
    'max_daily_tokens', p_max_daily_tokens,
    'max_daily_calls', p_max_daily_calls
  );
end $$;

create or replace function public.llm_budget_finalize(
  p_reserved_tokens integer,
  p_actual_tokens integer,
  p_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare d date;
declare lock_key bigint;
declare r integer;
declare a integer;
declare tokens_total integer;
declare reserved_total integer;
declare actual_total integer;
declare calls_total integer;
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('success', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  r := greatest(0, least(coalesce(p_reserved_tokens, 0), 500000));
  a := greatest(0, least(coalesce(p_actual_tokens, 0), 500000));

  lock_key := hashtext(uid::text || ':' || d::text || ':llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  -- Ensure row exists even if finalize is called after a failed reserve (best-effort).
  insert into public.llm_daily_usage(user_id, day, reserved_tokens, actual_tokens, calls, last_model)
  values (uid, d, 0, 0, 0, p_model)
  on conflict (user_id, day) do nothing;

  update public.llm_daily_usage
  set
    reserved_tokens = greatest(0, reserved_tokens - r),
    actual_tokens = actual_tokens + a,
    last_model = coalesce(p_model, last_model),
    updated_at = now()
  where user_id = uid and day = d;

  select reserved_tokens, actual_tokens, calls
  into reserved_total, actual_total, calls_total
  from public.llm_daily_usage
  where user_id = uid and day = d;

  tokens_total := coalesce(reserved_total, 0) + coalesce(actual_total, 0);
  return jsonb_build_object(
    'success', true,
    'day', d::text,
    'reserved_tokens', coalesce(reserved_total, 0),
    'actual_tokens', coalesce(actual_total, 0),
    'tokens_total', coalesce(tokens_total, 0),
    'calls', coalesce(calls_total, 0)
  );
end $$;

grant execute on function public.llm_budget_reserve(integer, integer, integer, text) to authenticated;
grant execute on function public.llm_budget_finalize(integer, integer, text) to authenticated;

commit;
```

### 20260204233010_concierge_ops_observability_and_retention.sql
```sql
-- Concierge ops hardening:
-- - Config table for tunable guardrails without redeploy
-- - Parse feedback logging (low-confidence/no-match)
-- - Retention + housekeeping (pg_cron)
-- - Admin-only metrics views (no grants)

begin;

-- 1) Config (single-row JSON, simple to edit in the dashboard).
create table if not exists public.concierge_config (
  id boolean primary key default true, -- single row: id=true
  config jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.concierge_config enable row level security;
-- No policies: clients cannot read/write config directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'concierge_config_set_updated_at') then
    create trigger concierge_config_set_updated_at
      before update on public.concierge_config
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- Default config (safe launch defaults).
insert into public.concierge_config(id, config)
values (
  true,
  jsonb_build_object(
    'rate_limits', jsonb_build_object(
      'parse', jsonb_build_object('window_seconds', 60, 'max_user', 140, 'max_ip', 240),
      'apply', jsonb_build_object('window_seconds', 60, 'max_user', 18, 'max_ip', 80),
      'undo', jsonb_build_object('window_seconds', 60, 'max_user', 12, 'max_ip', 50),
      'resolve', jsonb_build_object('window_seconds', 60, 'max_user', 18, 'max_ip', 80),
      'recommend', jsonb_build_object('window_seconds', 60, 'max_user', 30, 'max_ip', 100)
    ),
    'llm_budget', jsonb_build_object(
      'daily_tokens', 20000,
      'daily_calls', 80
    ),
    'parse_feedback', jsonb_build_object(
      'enabled', true,
      'low_confidence_score', 0.55,
      'max_log_chars', 140
    ),
    'retention_days', jsonb_build_object(
      'rate_limit_buckets', 2,
      'llm_daily_usage', 90,
      'import_sessions', 30,
      'concierge_runs', 60,
      'parse_feedback', 14
    )
  )
)
on conflict (id) do nothing;

create or replace function public.get_concierge_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare cfg jsonb;
begin
  select config into cfg from public.concierge_config where id = true;
  return coalesce(cfg, '{}'::jsonb);
end $$;

grant execute on function public.get_concierge_config() to anon, authenticated;

-- 2) Parse feedback table (for iterative improvement).
create table if not exists public.concierge_parse_feedback (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete cascade,
  raw_snippet text,
  normalized text,
  alias_norm text,
  best_score real,
  candidates_count integer,
  top_media_type text,
  top_media_id integer,
  created_at timestamptz not null default now()
);

create index if not exists idx_concierge_parse_feedback_created on public.concierge_parse_feedback (created_at desc);
create index if not exists idx_concierge_parse_feedback_user_created on public.concierge_parse_feedback (user_id, created_at desc);

alter table public.concierge_parse_feedback enable row level security;
-- No policies: do not expose raw user text to other clients.

create or replace function public.log_concierge_parse_feedback(
  p_raw text,
  p_normalized text,
  p_alias_norm text,
  p_best_score real,
  p_candidates_count integer,
  p_top_media_type text,
  p_top_media_id integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare cfg jsonb;
declare enabled boolean;
declare low_score real;
declare max_chars integer;
begin
  uid := auth.uid();
  if uid is null then
    return;
  end if;

  cfg := public.get_concierge_config();
  enabled := coalesce((cfg->'parse_feedback'->>'enabled')::boolean, true);
  if not enabled then
    return;
  end if;

  low_score := coalesce((cfg->'parse_feedback'->>'low_confidence_score')::real, 0.55);
  if p_best_score is not null and p_best_score >= low_score then
    return;
  end if;

  max_chars := greatest(20, least(coalesce((cfg->'parse_feedback'->>'max_log_chars')::int, 140), 400));

  insert into public.concierge_parse_feedback(
    user_id, raw_snippet, normalized, alias_norm, best_score, candidates_count, top_media_type, top_media_id
  )
  values(
    uid,
    left(coalesce(p_raw, ''), max_chars),
    left(coalesce(p_normalized, ''), max_chars),
    left(coalesce(p_alias_norm, ''), max_chars),
    p_best_score,
    p_candidates_count,
    left(coalesce(p_top_media_type, ''), 16),
    p_top_media_id
  );
end $$;

grant execute on function public.log_concierge_parse_feedback(text, text, text, real, integer, text, integer) to authenticated;

-- 3) Make guardrail functions read defaults from config when caller passes null.
create or replace function public.check_concierge_rate_limit(
  p_kind text,
  p_ip text,
  p_window_seconds integer default 60,
  p_max_user integer default 40,
  p_max_ip integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare u_hits integer;
declare ip_hits integer;
declare allow boolean := true;
declare retry_after integer;
declare kind text;
declare cfg jsonb;
declare rl jsonb;
declare win_s integer;
declare max_u integer;
declare max_i integer;
begin
  uid := auth.uid();
  kind := coalesce(nullif(p_kind, ''), 'any');

  cfg := public.get_concierge_config();
  rl := cfg->'rate_limits'->kind;

  win_s := coalesce(p_window_seconds, (rl->>'window_seconds')::int, 60);
  max_u := coalesce(p_max_user, (rl->>'max_user')::int, 40);
  max_i := coalesce(p_max_ip, (rl->>'max_ip')::int, 120);

  if uid is null and (p_ip is null or length(p_ip) = 0) then
    return jsonb_build_object('allowed', true, 'note', 'no uid/ip');
  end if;

  if uid is not null then
    u_hits := public.rate_limit_hit('user:' || uid::text || ':' || kind || ':' || win_s::text, win_s);
    if u_hits > coalesce(max_u, 0) then allow := false; end if;
  end if;

  if p_ip is not null and length(p_ip) > 0 then
    ip_hits := public.rate_limit_hit('ip:' || p_ip || ':' || kind || ':' || win_s::text, win_s);
    if ip_hits > coalesce(max_i, 0) then allow := false; end if;
  end if;

  retry_after := win_s - (extract(epoch from now())::integer % win_s);
  return jsonb_build_object(
    'allowed', allow,
    'user_hits', u_hits,
    'ip_hits', ip_hits,
    'retry_after_s', retry_after,
    'window_seconds', win_s,
    'max_user', max_u,
    'max_ip', max_i
  );
end $$;

-- LLM budget defaults from config when caller passes null.
create or replace function public.llm_budget_reserve(
  p_reserved_tokens integer,
  p_max_daily_tokens integer default 20000,
  p_max_daily_calls integer default 80,
  p_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare d date;
declare used_tokens integer;
declare used_calls integer;
declare next_tokens integer;
declare next_calls integer;
declare allow boolean;
declare lock_key bigint;
declare cfg jsonb;
declare budget jsonb;
declare max_tokens integer;
declare max_calls integer;
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;

  cfg := public.get_concierge_config();
  budget := cfg->'llm_budget';
  max_tokens := coalesce(p_max_daily_tokens, (budget->>'daily_tokens')::int, 20000);
  max_calls := coalesce(p_max_daily_calls, (budget->>'daily_calls')::int, 80);

  lock_key := hashtext(uid::text || ':' || d::text || ':llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  select
    coalesce(actual_tokens, 0) + coalesce(reserved_tokens, 0),
    coalesce(calls, 0)
  into used_tokens, used_calls
  from public.llm_daily_usage
  where user_id = uid and day = d;

  next_tokens := coalesce(used_tokens, 0) + p_reserved_tokens;
  next_calls := coalesce(used_calls, 0) + 1;

  allow :=
    next_tokens <= coalesce(max_tokens, 0)
    and next_calls <= coalesce(max_calls, 0);

  if allow then
    insert into public.llm_daily_usage(user_id, day, reserved_tokens, actual_tokens, calls, last_model)
    values (uid, d, p_reserved_tokens, 0, 1, p_model)
    on conflict (user_id, day)
    do update set
      reserved_tokens = public.llm_daily_usage.reserved_tokens + excluded.reserved_tokens,
      calls = public.llm_daily_usage.calls + 1,
      last_model = coalesce(excluded.last_model, public.llm_daily_usage.last_model),
      updated_at = now();
  end if;

  return jsonb_build_object(
    'allowed', allow,
    'day', d::text,
    'used_tokens', coalesce(used_tokens, 0),
    'used_calls', coalesce(used_calls, 0),
    'next_tokens', next_tokens,
    'next_calls', next_calls,
    'max_daily_tokens', max_tokens,
    'max_daily_calls', max_calls
  );
end $$;

-- 4) Housekeeping + retention.
create or replace function public.concierge_housekeeping()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare cfg jsonb;
declare r jsonb;
declare days_rate integer;
declare days_llm integer;
declare days_import integer;
declare days_runs integer;
declare days_feedback integer;
begin
  cfg := public.get_concierge_config();
  r := cfg->'retention_days';
  days_rate := coalesce((r->>'rate_limit_buckets')::int, 2);
  days_llm := coalesce((r->>'llm_daily_usage')::int, 90);
  days_import := coalesce((r->>'import_sessions')::int, 30);
  days_runs := coalesce((r->>'concierge_runs')::int, 60);
  days_feedback := coalesce((r->>'parse_feedback')::int, 14);

  delete from public.rate_limit_buckets
  where window_start < now() - make_interval(days => greatest(1, days_rate));

  delete from public.llm_daily_usage
  where day < (timezone('utc', now())::date - greatest(7, days_llm));

  -- Import sessions/items (only completed/cancelled/failed; keep drafts).
  delete from public.import_session_items i
  using public.import_sessions s
  where i.session_id = s.id
    and s.status in ('applied','cancelled','failed')
    and s.updated_at < now() - make_interval(days => greatest(7, days_import));

  delete from public.import_sessions
  where status in ('applied','cancelled','failed')
    and updated_at < now() - make_interval(days => greatest(7, days_import));

  delete from public.concierge_runs
  where created_at < now() - make_interval(days => greatest(14, days_runs));

  delete from public.concierge_parse_feedback
  where created_at < now() - make_interval(days => greatest(7, days_feedback));
end $$;

-- Schedule housekeeping daily (best-effort). If pg_cron isn't available, the function still exists.
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    -- ignore if extension not available in this environment
    return;
  end;

  -- Ensure we don't double-schedule.
  if not exists (select 1 from cron.job where jobname = 'concierge_housekeeping_daily') then
    perform cron.schedule('concierge_housekeeping_daily', '0 4 * * *', 'select public.concierge_housekeeping();');
  end if;
end $$;

-- 5) Admin views (no grants; use dashboard/service role).
create or replace view public.concierge_metrics_hourly as
select
  date_trunc('hour', created_at) as hour,
  kind,
  status,
  count(*)::int as runs,
  coalesce(sum(items_count), 0)::int as items_total,
  coalesce(avg(latency_ms), 0)::real as avg_latency_ms,
  coalesce(sum(case when error is null then 0 else 1 end), 0)::int as errors
from public.concierge_runs
group by 1, 2, 3;

create or replace view public.llm_usage_daily_totals as
select
  day,
  count(*)::int as users,
  sum(actual_tokens)::bigint as actual_tokens,
  sum(reserved_tokens)::bigint as reserved_tokens,
  sum(calls)::bigint as calls
from public.llm_daily_usage
group by 1
order by day desc;

create or replace view public.rate_limit_recent_top as
select
  window_start,
  bucket_key,
  hits
from public.rate_limit_buckets
where window_start > now() - interval '6 hours'
order by hits desc, window_start desc
limit 200;

commit;
```

### 20260205000500_concierge_global_llm_budget_and_default_tuning.sql
```sql
-- Add global LLM daily budget + tune default "natural usage" limits.
-- Goal: prevent LLM spend abuse even with many users.

begin;

-- 1) Global daily usage table.
create table if not exists public.llm_global_daily_usage (
  day date primary key,
  reserved_tokens integer not null default 0,
  actual_tokens integer not null default 0,
  calls integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.llm_global_daily_usage enable row level security;
-- No policies: clients cannot read/write global usage directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'llm_global_daily_usage_set_updated_at') then
    create trigger llm_global_daily_usage_set_updated_at
      before update on public.llm_global_daily_usage
      for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.llm_global_budget_reserve(
  p_reserved_tokens integer,
  p_max_daily_tokens integer,
  p_max_daily_calls integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare d date;
declare used_tokens integer;
declare used_calls integer;
declare next_tokens integer;
declare next_calls integer;
declare allow boolean;
declare lock_key bigint;
begin
  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;
  if p_max_daily_tokens is null or p_max_daily_tokens < 0 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_max_daily_tokens');
  end if;
  if p_max_daily_calls is null or p_max_daily_calls < 0 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_max_daily_calls');
  end if;

  lock_key := hashtext(d::text || ':global_llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  select coalesce(actual_tokens, 0) + coalesce(reserved_tokens, 0), coalesce(calls, 0)
  into used_tokens, used_calls
  from public.llm_global_daily_usage
  where day = d;

  next_tokens := coalesce(used_tokens, 0) + p_reserved_tokens;
  next_calls := coalesce(used_calls, 0) + 1;

  allow := next_tokens <= p_max_daily_tokens and next_calls <= p_max_daily_calls;

  if allow then
    insert into public.llm_global_daily_usage(day, reserved_tokens, actual_tokens, calls)
    values (d, p_reserved_tokens, 0, 1)
    on conflict (day) do update set
      reserved_tokens = public.llm_global_daily_usage.reserved_tokens + excluded.reserved_tokens,
      calls = public.llm_global_daily_usage.calls + 1,
      updated_at = now();
  end if;

  return jsonb_build_object(
    'allowed', allow,
    'day', d::text,
    'used_tokens', coalesce(used_tokens, 0),
    'used_calls', coalesce(used_calls, 0),
    'next_tokens', next_tokens,
    'next_calls', next_calls,
    'max_daily_tokens', p_max_daily_tokens,
    'max_daily_calls', p_max_daily_calls
  );
end $$;

create or replace function public.llm_global_budget_finalize(
  p_reserved_tokens integer,
  p_actual_tokens integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare d date;
declare lock_key bigint;
declare r integer;
declare a integer;
declare reserved_total integer;
declare actual_total integer;
declare calls_total integer;
begin
  d := (timezone('utc', now()))::date;
  r := greatest(0, least(coalesce(p_reserved_tokens, 0), 500000));
  a := greatest(0, least(coalesce(p_actual_tokens, 0), 500000));

  lock_key := hashtext(d::text || ':global_llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  insert into public.llm_global_daily_usage(day, reserved_tokens, actual_tokens, calls)
  values (d, 0, 0, 0)
  on conflict (day) do nothing;

  update public.llm_global_daily_usage
  set
    reserved_tokens = greatest(0, reserved_tokens - r),
    actual_tokens = actual_tokens + a,
    updated_at = now()
  where day = d;

  select reserved_tokens, actual_tokens, calls
  into reserved_total, actual_total, calls_total
  from public.llm_global_daily_usage
  where day = d;

  return jsonb_build_object(
    'success', true,
    'day', d::text,
    'reserved_tokens', coalesce(reserved_total, 0),
    'actual_tokens', coalesce(actual_total, 0),
    'calls', coalesce(calls_total, 0)
  );
end $$;

grant execute on function public.llm_global_budget_reserve(integer, integer, integer) to authenticated;
grant execute on function public.llm_global_budget_finalize(integer, integer) to authenticated;

-- 2) Patch default config with "natural usage" limits + global budget.
update public.concierge_config
set config =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        config,
        '{llm_budget}',
        jsonb_build_object('daily_tokens', 12000, 'daily_calls', 40),
        true
      ),
      '{global_llm_budget}',
      jsonb_build_object('daily_tokens', 250000, 'daily_calls', 600),
      true
    ),
    '{rate_limits}',
    jsonb_build_object(
      'parse', jsonb_build_object('window_seconds', 60, 'max_user', 120, 'max_ip', 300),
      'apply', jsonb_build_object('window_seconds', 60, 'max_user', 12, 'max_ip', 50),
      'undo', jsonb_build_object('window_seconds', 60, 'max_user', 6, 'max_ip', 20),
      'resolve', jsonb_build_object('window_seconds', 60, 'max_user', 10, 'max_ip', 40),
      'recommend', jsonb_build_object('window_seconds', 60, 'max_user', 20, 'max_ip', 80)
    ),
    true
  )
where id = true;

commit;

```

### 20260205002000_concierge_budget_raise.sql
```sql
-- Raise LLM token budgets (requested):
-- - global daily tokens: 1,000,000
-- - per-user daily tokens: 50,000

begin;

update public.concierge_config
set config =
  jsonb_set(
    jsonb_set(
      config,
      '{llm_budget,daily_tokens}',
      to_jsonb(50000),
      true
    ),
    '{global_llm_budget,daily_tokens}',
    to_jsonb(1000000),
    true
  )
where id = true;

commit;

```

---

## 19) Appendix D — Recommendation & Search RPC DDL (selected)

### 20260203183000_concierge_recommend_rpc.sql
```sql
-- Deterministic recommendation primitives (no LLM).
-- Uses tags + join tables to produce "new to you" premium-ish candidates.

begin;

create or replace function public.recommend_ids_by_tag_categories(
  p_media_type text,
  p_categories text[],
  p_limit integer default 10
)
returns table (
  media_type text,
  media_id integer,
  match_count integer
)
language sql stable as $$
  select media_type, media_id, match_count from (
    select
      'ANIME'::text as media_type,
      at.anime_id as media_id,
      count(*)::int as match_count,
      max(a.average_score) as avg_score,
      max(a.popularity) as pop
    from public.anime_tags at
    join public.tags t on t.id = at.tag_id
    join public.anime a on a.id = at.anime_id
    where p_media_type = 'ANIME'
      and auth.uid() is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and not exists (
        select 1
        from public.user_lists ul
        where ul.user_id = auth.uid()::text
          and ul.media_type = 'anime'
          and ul.media_id = at.anime_id
      )
    group by at.anime_id

    union all

    select
      'MANGA'::text as media_type,
      mt.manga_id as media_id,
      count(*)::int as match_count,
      max(m.average_score) as avg_score,
      max(m.popularity) as pop
    from public.manga_tags mt
    join public.tags t on t.id = mt.tag_id
    join public.manga m on m.id = mt.manga_id
    where p_media_type = 'MANGA'
      and auth.uid() is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and not exists (
        select 1
        from public.user_lists ul
        where ul.user_id = auth.uid()::text
          and ul.media_type = 'manga'
          and ul.media_id = mt.manga_id
      )
    group by mt.manga_id
  ) ranked
  order by match_count desc, avg_score desc nulls last, pop desc nulls last
  limit greatest(1, least(p_limit, 50));
$$;

grant execute on function public.recommend_ids_by_tag_categories(text, text[], integer) to authenticated;

commit;
```

### 20260203190000_editorial_recommend_engine.sql
```sql
-- Editorial weighting for premium recommendations.
-- Goal: push classics/masterpieces up front; softly de-emphasize gimmick isekai/reincarnation/harem,
-- while still keeping everything searchable and accessible.

begin;

create table if not exists public.editorial_boosts (
  media_type text not null check (media_type in ('ANIME','MANGA')),
  media_id integer not null,
  weight integer not null default 0,
  label text not null default '',
  created_at timestamptz not null default now(),
  primary key (media_type, media_id)
);

create table if not exists public.editorial_penalty_tags (
  tag_id integer primary key references public.tags(id) on delete cascade,
  penalty integer not null default 0,
  reason text,
  created_at timestamptz not null default now()
);

-- Seed: core classics/masterpieces (internal ids, not AniList ids).
insert into public.editorial_boosts (media_type, media_id, weight, label) values
  ('MANGA', 14, 25, 'classic'),   -- Vagabond
  ('MANGA', 97, 22, 'classic'),   -- Kingdom
  ('MANGA', 30, 25, 'classic'),   -- 20th Century Boys
  ('MANGA', 29, 22, 'classic'),   -- Monster
  ('MANGA', 5, 25, 'classic'),    -- Berserk
  ('MANGA', 16, 18, 'classic'),   -- Vinland Saga
  ('MANGA', 11, 18, 'classic'),   -- Oyasumi Punpun
  ('MANGA', 98, 18, 'classic'),   -- Slam Dunk
  ('MANGA', 162, 16, 'classic'),  -- Real
  ('MANGA', 116, 14, 'classic'),  -- The Climber
  ('MANGA', 169, 18, 'classic'),  -- Akira
  ('ANIME', 12, 16, 'classic'),   -- Fullmetal Alchemist: Brotherhood
  ('ANIME', 29, 14, 'classic'),   -- Steins;Gate
  ('ANIME', 117, 12, 'classic'),  -- Cowboy Bebop
  ('ANIME', 1072, 14, 'classic')  -- Legend of the Galactic Heroes
on conflict (media_type, media_id) do update
  set weight = excluded.weight, label = excluded.label;

-- Seed: de-emphasize gimmick clusters by default (not a ban).
insert into public.editorial_penalty_tags (tag_id, penalty, reason) values
  (350, -12, 'Isekai'),
  (1023, -10, 'Reincarnation'),
  (358, -6, 'Female Harem'),
  (9154, -6, 'Male Harem'),
  (18064, -6, 'Mixed Gender Harem')
on conflict (tag_id) do update
  set penalty = excluded.penalty, reason = excluded.reason;

create or replace function public.recommend_ids_premium(
  p_media_type text,
  p_categories text[] default null,
  p_limit integer default 10,
  p_allow_gimmicks boolean default false
)
returns table (
  media_id integer,
  match_count integer,
  score real
)
language sql stable security definer
set search_path = public
as $$
  with req as (
    select
      greatest(1, least(coalesce(p_limit, 10), 50))::int as lim,
      p_categories as cats,
      p_allow_gimmicks as allow_gimmicks
  ),
  me as (
    select auth.uid()::text as user_id
  ),
  anime_pen as (
    select at.anime_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.anime_tags at
    join public.editorial_penalty_tags p on p.tag_id = at.tag_id
    group by at.anime_id
  ),
  manga_pen as (
    select mt.manga_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.manga_tags mt
    join public.editorial_penalty_tags p on p.tag_id = mt.tag_id
    group by mt.manga_id
  ),
  anime_match as (
    select
      at.anime_id as media_id,
      count(*)::int as match_count
    from public.anime_tags at
    join public.tags t on t.id = at.tag_id
    where p_categories is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(t.category, '') <> 'Sexual Content'
    group by at.anime_id
  ),
  manga_match as (
    select
      mt.manga_id as media_id,
      count(*)::int as match_count
    from public.manga_tags mt
    join public.tags t on t.id = mt.tag_id
    where p_categories is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(t.category, '') <> 'Sexual Content'
    group by mt.manga_id
  )
  select *
  from (
    select
      a.id as media_id,
      coalesce(am.match_count, 0) as match_count,
      (
        -- Tag fit (dominant when the user gives a vibe)
        coalesce(am.match_count, 0) * 8
        -- Quality (multi-signal, not rating-only)
        + ln(1 + coalesce(a.favourites, 0)) * 2.0
        + ln(1 + coalesce(a.popularity, 0)) * 1.0
        + (coalesce(a.average_score, 0) / 10.0)
        -- Classic bias
        + case
            when a.start_date_year is not null and a.start_date_year <= 2005 then 7
            when a.start_date_year is not null and a.start_date_year <= 2015 then 4
            else 0
          end
        -- Editorial boost
        + coalesce(eb.weight, 0)
        -- Soft penalties (unless user asks for gimmicks)
        + case
            when (select allow_gimmicks from req) then 0
            else coalesce(ap.penalty, 0)
          end
      )::real as score
    from public.anime a
    left join anime_match am on am.media_id = a.id
    left join public.editorial_boosts eb on eb.media_type = 'ANIME' and eb.media_id = a.id
    left join anime_pen ap on ap.media_id = a.id
    where p_media_type = 'ANIME'
      and (select user_id from me) is not null
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = (select user_id from me)
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )

    union all

    select
      m.id as media_id,
      coalesce(mm.match_count, 0) as match_count,
      (
        coalesce(mm.match_count, 0) * 8
        + ln(1 + coalesce(m.favourites, 0)) * 2.0
        + ln(1 + coalesce(m.popularity, 0)) * 1.0
        + (coalesce(m.average_score, 0) / 10.0)
        + case
            when m.start_date_year is not null and m.start_date_year <= 2000 then 6
            when m.start_date_year is not null and m.start_date_year <= 2015 then 4
            else 0
          end
        + coalesce(eb.weight, 0)
        + case
            when (select allow_gimmicks from req) then 0
            else coalesce(mp.penalty, 0)
          end
      )::real as score
    from public.manga m
    left join manga_match mm on mm.media_id = m.id
    left join public.editorial_boosts eb on eb.media_type = 'MANGA' and eb.media_id = m.id
    left join manga_pen mp on mp.media_id = m.id
    where p_media_type = 'MANGA'
      and (select user_id from me) is not null
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = (select user_id from me)
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ) ranked
  order by score desc
  limit (select lim from req);
$$;

grant execute on function public.recommend_ids_premium(text, text[], integer, boolean) to authenticated;

commit;
```

---

## 20) Appendix E — Data Dictionary (human-readable)

Notes:
- Column types and constraints are defined in the DDL appendices above.
- This section provides **semantic meaning** for each column.
- If a column is not listed in a downstream migration, assume it still exists from the base DDL unless dropped later.

### anime
- id: internal primary key (may or may not match AniList id; see schema note below).
- anilist_id, mal_id, kitsu_id: external IDs for sync/dedup.
- title_english, title_romaji, title_native: localized titles.
- title_synonyms: extra title aliases from source.
- cover_image_large, cover_image_medium, cover_image_color, banner_image: artwork URLs.
- format: TV/MOVIE/OVA/etc.
- status: FINISHED/RELEASING/NOT_YET_RELEASED.
- description: raw synopsis text.
- description_normalized: sanitized/plain text for search.
- episodes: total episodes (if known).
- duration: minutes per episode.
- total_duration: episodes * duration.
- season, season_year: seasonal metadata.
- next_episode_number, next_airing_at: next airing info.
- start_date_year/month/day, end_date_year/month/day: date components.
- average_score, mean_score: ratings.
- popularity, trending, favourites: ranking stats.
- genres: text array.
- source: original source type (manga, original, etc).
- country_of_origin: two-letter origin.
- is_adult: adult flag.
- age_rating: content rating string.
- site_url: AniList page.
- created_at, updated_at, last_synced_at, updated_at_anilist: system timestamps.

### manga
- id: internal primary key.
- anilist_id, mal_id, kitsu_id: external IDs.
- title_english, title_romaji, title_native, title_synonyms: titles.
- cover_image_large/medium/color, banner_image: artwork.
- format: MANGA/NOVEL/ONE_SHOT/etc.
- status: FINISHED/RELEASING/HIATUS/etc.
- description, description_normalized: synopsis.
- chapters, volumes: totals.
- next_chapter_number, next_chapter_at: next release info.
- start/end date components.
- average_score, mean_score, popularity, trending, favourites.
- genres, source, country_of_origin.
- is_adult, age_rating.
- site_url.
- created_at, updated_at, last_synced_at, updated_at_anilist.

### episodes
- id: internal PK.
- anime_id: FK to anime.
- anilist_id, mal_id: external episode IDs.
- number: episode number.
- title, title_romaji: names.
- description: episode synopsis.
- air_date, air_at: date/time.
- thumbnail: image URL.
- duration: minutes.
- is_filler, is_recap, is_mixed, filler_source: content classification.
- stream_url, stream_site: streaming CTA info (migration 13).
- created_at, updated_at.

### chapters
- id: internal PK.
- manga_id: FK to manga.
- anilist_id, mal_id: external chapter IDs.
- number: chapter number.
- title, title_romaji, description.
- release_date, release_at.
- created_at, updated_at.

### volumes
- id: internal PK.
- manga_id: FK to manga.
- number, title, description.
- release_date.
- created_at, updated_at.

### characters
- id: internal PK.
- anilist_id, mal_id, kitsu_id: external IDs.
- name_full, name_native.
- image_large, image_medium.
- description, gender, age, blood_type.
- site_url.
- favourites.
- created_at, updated_at, last_synced_at.

### studios
- id: internal PK.
- anilist_id, mal_id, kitsu_id.
- name.
- site_url.
- favourites.
- created_at, updated_at, last_synced_at.

### authors
- id: internal PK.
- anilist_id, mal_id, kitsu_id.
- name_full, name_native.
- image_large, image_medium.
- description.
- site_url.
- favourites.
- created_at, updated_at, last_synced_at.

### staff
- id: internal PK.
- anilist_id, mal_id, kitsu_id.
- name_full, name_native.
- image_large, image_medium.
- description.
- primary_occupations.
- site_url.
- favourites.
- created_at, updated_at, last_synced_at.

### tags
- id: internal PK (AniList tag id).
- name, description.
- category.
- rank.
- is_spoiler, is_adult.
- created_at, updated_at.

### anime_characters / manga_characters
- anime_id or manga_id.
- character_id.
- role (main, supporting, etc).
- created_at, updated_at.

### anime_studios / manga_authors
- anime_id or manga_id.
- studio_id or author_id.
- is_main (for studios).
- created_at, updated_at.

### anime_staff / manga_staff
- anime_id or manga_id.
- staff_id.
- role (string).
- created_at, updated_at.

### anime_tags / manga_tags
- anime_id or manga_id.
- tag_id.
- rank.
- is_spoiler, is_adult.
- created_at, updated_at.

### anime_user_lists / manga_user_lists
- id: list row PK.
- user_id: auth user id.
- anime_id or manga_id.
- list_type: WATCHING/PLANNING/COMPLETED/etc.
- progress: episodes/chapters count.
- rating: integer (0-10, converted to 0-100 in view).
- notes.
- created_at, updated_at.

### anime_comments / manga_comments
- id: PK.
- user_id.
- anime_id or manga_id.
- comment text.
- created_at, updated_at.

### external_links
- id: PK.
- media_type: ANIME/MANGA.
- media_id.
- site: source site name.
- url: link.
- language, color.
- priority: rank for display.
- is_disabled.
- created_at, updated_at.

### profiles
- id: auth user id.
- display_name.
- adult_opt_in.
- created_at, updated_at.

### title_search
- id: PK.
- media_type, media_id.
- variant_type: english/romaji/native/synonym/alias/user_alias.
- title_raw, title_norm.
- lang.
- popularity.
- created_at.

### title_aliases
- user_id.
- alias_norm.
- media_type, media_id.
- title_raw.
- hits.
- created_at, updated_at.

### import_state
- media_type: ANIME/MANGA.
- last_page: cursor for imports.
- updated_at.

### import_sessions
- id: UUID.
- user_id.
- status: draft/applied/failed/cancelled.
- source: chat (default).
- created_at, updated_at.

### import_session_items
- id: UUID.
- session_id.
- raw: raw input line.
- parsed: json payload of parsed info.
- candidates: json candidate list.
- chosen: selected candidate.
- action: final action payload.
- confidence: float score.
- state: needs_choice/ready/applied/error/skipped.
- error: error text.
- created_at, updated_at.

### concierge_runs
- id: PK.
- user_id (nullable).
- kind: parse/recommend/apply/llm_router/llm_resolve.
- status: success/error/skipped.
- input_chars, items_count.
- latency_ms.
- token_in, token_out.
- error.
- created_at.

### concierge_parse_feedback
- id: PK.
- user_id.
- raw_snippet, normalized, alias_norm.
- best_score, candidates_count.
- top_media_type, top_media_id.
- created_at.

### concierge_config
- id: single row (true).
- config: jsonb.
- created_at, updated_at.

### system_flags
- key (e.g., llm_enabled).
- enabled.
- created_at, updated_at.

### rate_limit_buckets
- bucket_key.
- window_start.
- hits.
- created_at, updated_at.

### llm_daily_usage
- user_id.
- day (date).
- reserved_tokens, actual_tokens.
- calls.
- last_model.
- created_at, updated_at.

### llm_global_daily_usage
- day.
- reserved_tokens, actual_tokens.
- calls.
- created_at, updated_at.

### mirror_runs
- id: PK.
- status: running/success/error/skipped.
- payload, results.
- message.
- started_at, finished_at, duration_ms.

### user_taste_profiles
- user_id.
- vector (jsonb).
- updated_at.

### user_lists (view)
- Unified view over anime_user_lists + manga_user_lists.
- Fields: media_type, media_id, status, progress, score, notes, timestamps.

### user_airing_next (view)
- User-scoped upcoming airings for anime in list.

Schema note:
- Some edge functions comment that `anime.id` and `manga.id` are AniList ids. The base DDL defines internal ids + `anilist_id` columns. If a migration or import strategy makes `id` = AniList id, update this section and the import scripts accordingly.

---

## 21) Appendix F — RPC Catalog (with examples)

These RPCs are used by the app and Edge Functions. For full SQL definitions, see migrations.

### discover_bundle(p_limit int, p_hours int) -> jsonb
- Returns: JSON with multiple rails (essentials, classics, trending, etc).
- Example:
```sql
select public.discover_bundle(30, 24);
```

### search_titles(p_query text, p_media_type text, p_limit int) -> setof (media_type, media_id, variant_type, title_raw, score)
- Example:
```sql
select * from public.search_titles('attack on titan', 'ANIME', 10);
```

### search_anime_page / search_manga_page
- Used by Search UI. Returns paged rows.
- Example:
```sql
select * from public.search_anime_page('naruto', 0, 30, null);
```

### browse_anime_page / browse_manga_page
- Used by Browse UI with sort keys.
- Example:
```sql
select * from public.browse_anime_page('popular', 0, 30, null);
```

### collection_feed_page
- Unified feed (anime + manga) sorted by updated_at.
- Example:
```sql
select * from public.collection_feed_page(null, null, null, 40);
```

### collection_anime_page / collection_manga_page
- Keyset paging for anime_user_lists / manga_user_lists.
- Example:
```sql
select * from public.collection_anime_page(null, null, 40);
```

### airing_next(days int)
- User upcoming airing episodes.
- Example:
```sql
select * from public.airing_next(7);
```

### recommend_ids_premium / recommend_ids_similar_to_seeds
- Deterministic recommendation primitives.
- Example:
```sql
select * from public.recommend_ids_premium('ANIME', array['Action'], 10, false);
```

### check_concierge_rate_limit(p_kind, p_ip, p_window_seconds, p_max_user, p_max_ip) -> jsonb
- Example:
```sql
select public.check_concierge_rate_limit('parse', '1.2.3.4', 60, null, null);
```

### get_concierge_config() -> jsonb
- Example:
```sql
select public.get_concierge_config();
```

### log_concierge_run(...)
- Used by Edge Functions to log runs (SECURITY DEFINER).

### log_concierge_parse_feedback(...)
- Stores low-confidence parse events.

### llm_budget_reserve / llm_budget_finalize
- Reserve + finalize per-user budget.

### llm_global_budget_reserve / llm_global_budget_finalize
- Reserve + finalize global daily budget.

### is_flag_enabled(p_key)
- Example:
```sql
select public.is_flag_enabled('llm_enabled');
```

### acquire_import_lock / release_import_lock
- Used by bulk imports + mirror-images to prevent overlap.

---

## 22) Appendix G — Edge Function HTTP API (examples)

All functions are invoked via:
```
POST https://<project-ref>.supabase.co/functions/v1/<function-name>
Authorization: Bearer <user-access-token>
Content-Type: application/json
```

### concierge-parse
Request:
```json
{ "text": "AoT completed, JJK ep 12", "scope": "both", "limitPerItem": 10 }
```
Response (shape):
```json
{ "success": true, "items": [ { "id": "...", "raw": "...", "candidates": [ ... ] } ], "userId": "..." }
```

### concierge-resolve
Request:
```json
{ "items": [ { "raw": "JJK", "parsed": {"status":"COMPLETED"}, "candidates": [ ... ] } ], "maxCandidates": 6 }
```
Response:
```json
{ "success": true, "choices": [ { "i": 0, "pick": 1 } ] }
```

### concierge-recommend
Request:
```json
{ "text": "something funny, not childish", "scope": "anime", "limit": 8, "narrate": true }
```
Response:
```json
{ "success": true, "items": [ { "mediaId": 12, "title": "...", "blurb": "..." } ] }
```

### concierge-apply
Request:
```json
{ "items": [ { "mediaType": "ANIME", "mediaId": 16498, "status": "COMPLETED", "progressEpisodes": 25 } ] }
```
Response:
```json
{ "success": true, "applied": 1, "sessionId": "...", "errors": [] }
```

### concierge-undo
Request:
```json
{ "sessionId": "<optional>" }
```
Response:
```json
{ "success": true, "reverted": 3 }
```

### bulk-import-anime / bulk-import-manga
Request:
```json
{ "startPage": 1, "pageCount": 10, "concurrency": 2 }
```
Response:
```json
{ "success": true, "pages": 10, "updated": 500 }
```

### mirror-images
Request:
```json
{ "bucket": "media", "mediaTypes": ["ANIME","MANGA"], "limit": 200, "offset": 0, "overwrite": false }
```
Response:
```json
{ "success": true, "results": { "anime": 180, "manga": 170 } }
```

---

## 23) Appendix H — Operator Runbook (step-by-step)

### Imports (AniList)
1. Set `SUPABASE_SERVICE_ROLE_KEY` in environment.
2. Run `scripts/run_full_import.js` or call `bulk-import-anime`/`bulk-import-manga` functions.
3. Verify `import_state` updates.
4. Run `scripts/db_state.sql` for counts.

### Image mirroring (CDN)
1. Call `mirror-images` edge function with mediaTypes.
2. Check `mirror_runs` table for status.
3. Verify storage URLs in `anime`/`manga`/`characters`/`staff`.

### Concierge budgets / rate limits
1. Update `public.concierge_config` JSON in SQL editor.
2. To disable LLM globally: `update public.system_flags set enabled=false where key='llm_enabled';`.
3. Check `llm_usage_daily_totals` and `rate_limit_recent_top` views.

### Housekeeping
- Manual run: `select public.concierge_housekeeping();`
- Scheduled job: `concierge_housekeeping_daily` (04:00 UTC).

### Troubleshooting
- If parse/recommend fails: check `concierge_runs` + edge function logs.
- If recommendations are empty: verify `user_lists` view and `recommend_*` RPCs.
- If images slow: ensure mirror-images has run and Storage URLs are used.
- If swipe/paging is broken: check `ContentView.swift` for swipe order + exclusions.

---

## 24) Appendix I — Live Supabase DB Snapshot (auto-generated, service-role only)

This appendix is **optional** and exists to detect **drift** between:
- the repo's declared schema (migrations), and
- the **live** Supabase database (production/dev).

It requires:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- the RPC `public.admin_schema_snapshot()` to be deployed (see migration `supabase/migrations/20260205160000_admin_schema_snapshot.sql`).

Rebuild:
```bash
node scripts/generate_app_state_live_snapshot.js
```

<!-- BEGIN AUTO-LIVE-DB-SNAPSHOT -->

Generated: **2026-02-05T17:49:36.205Z** (git: `d1efdb0`)

Status: **SKIPPED** (missing `SUPABASE_URL` and/or `SUPABASE_SERVICE_ROLE_KEY` in environment).

To enable live snapshot generation, set env vars locally (do not commit secrets) and ensure the RPC is deployed:
```bash
SUPABASE_URL="https://<project>.supabase.co" \
SUPABASE_SERVICE_ROLE_KEY="<service_role_key>" \
node scripts/generate_app_state_live_snapshot.js
```


<!-- END AUTO-LIVE-DB-SNAPSHOT -->

---

## 25) Appendix J — Source of truth excerpts (auto-generated)

This appendix inlines the **exact current source** for the most important runtime components so another LLM can reason from ground truth without opening the repo.

For a complete (very large) source bundle, see: `CURRENT_APP_STATE_CODEBASE.md` (auto-generated).

Rebuild:
```bash
node scripts/generate_app_state_sources.js
node scripts/generate_app_state_codebase_bundle.js
```

<!-- BEGIN AUTO-SOURCE-EXCERPTS -->

Generated: **2026-02-05T17:59:23.130Z** (git: `ca671d5`)

This section is auto-generated. Rebuild after any change to the referenced files:
```bash
node scripts/generate_app_state_sources.js
```

### iOS pager + swipe navigation (authoritative)

- Path: `Kuro/ContentView.swift`


```swift
// uses PosterView.swift
import SwiftUI
import UIKit

#if DEBUG
// Debug mode: Set this to true to see spacing visualization
let SHOW_SPACING_DEBUG = false
#endif

// MARK: - Type Aliases
// (Removed)

// MARK: - Utility Functions
fileprivate func pixelAlign(_ value: CGFloat, scale: CGFloat = 3.0) -> CGFloat {
    return floor(value * scale) / scale
}

// MARK: - KURO APP - Single Source of Truth
// "Elevated Minimalism" / "Editorial Minimalism" Design System

// MARK: - Content View
struct ContentView: View {
    @Environment(SupabaseService.self) private var supabaseService
    
    var body: some View {
        KuroRootView()
            .environment(supabaseService)
    }
}

// MARK: - Root View with Launch
struct KuroRootView: View {
    @State private var showLaunch = true
    
    var body: some View {
        if showLaunch {
            KuroLaunchView()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            showLaunch = false
                        }
                    }
                }
        } else {
            KuroMainView()
        }
    }
}

// MARK: - Launch View
struct KuroLaunchView: View {
    @State private var logoOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 8) {
                Text("KURO")
                    .font(.system(size: 24, weight: .ultraLight, design: .serif))
                    .tracking(8)
                    .foregroundColor(.black)
                    .opacity(logoOpacity)
                
                Text("CURATED ANIME")
                    .font(.system(size: 10, weight: .light))
                    .tracking(3)
                    .foregroundColor(.black.opacity(0.5))
                    .opacity(subtitleOpacity)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.2)) {
                    logoOpacity = 1.0
                }
                withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                    subtitleOpacity = 1.0
                }
            }
        }
    }
}

// MARK: - Main View
struct KuroMainView: View {
    @Environment(SupabaseService.self) private var supabaseService
    // Removed: @State private var currentSection = 0
    // Removed: @State private var selectedMood: String? = nil
    // Removed: @State private var dragOffset: CGFloat = 0
    // Removed: let sections = ["DISCOVER", "COLLECTION", "SEARCH"]

    enum Section: Int, CaseIterable {
        case concierge, discover, browse, collection, clubs

        var title: String {
            switch self {
            case .concierge:
                return "CONCIERGE"
            case .discover:
                return "DISCOVER"
            case .collection:
                return "COLLECTION"
            case .browse:
                return "BROWSE"
            case .search:
                return "SEARCH"
            }
        }
    }

	@State private var selection: Section = .discover
	@State private var showProfileSheet = false
	@State private var mountedSections: Set<Section> = [.discover]
	@State private var swipeExclusions: [CGRect] = []
	// Concierge is a first-class page to the LEFT of Discover.
	private let swipeOrder: [Section] = [.concierge, .discover, .browse, .collection, .clubs]
	private let swipeThreshold: CGFloat = 40
	private let swipeEdgeMargin: CGFloat = 24
    
    var body: some View {
	        ZStack {
	            Color.white.ignoresSafeArea()

	            VStack(spacing: 0) {
                // Fixed Header - Three-part layout
                KuroHeaderNew(selection: $selection, showProfileSheet: $showProfileSheet)

                // Header-driven pager: keeps sections mounted once visited.
	                KuroSectionPager(
	                    selection: $selection,
	                    mountedSections: $mountedSections,
	                    order: swipeOrder
	                )
	                .background(Color.clear)
	            }
	        }
	        .coordinateSpace(name: "kuro_root")
	        .onPreferenceChange(KuroSwipeExclusionPreferenceKey.self) { v in
	            swipeExclusions = v
	        }
	        .simultaneousGesture(
	            DragGesture(minimumDistance: 10, coordinateSpace: .named("kuro_root"))
	                .onEnded { value in
	                    let start = value.startLocation
	                    #if os(iOS)
	                    let rootWidth = UIScreen.main.bounds.width
	                    #else
	                    let rootWidth: CGFloat = 1024
	                    #endif
	                    let edgeAllowed = (start.x <= swipeEdgeMargin) || (start.x >= max(0, rootWidth - swipeEdgeMargin))

	                    let expanded = swipeExclusions.map { $0.insetBy(dx: -14, dy: -14) }
	                    if expanded.contains(where: { $0.contains(start) }) && !edgeAllowed { return }

	                    let dx = value.translation.width
	                    let dy = value.translation.height
	                    // Be forgiving: people swipe slightly diagonally.
	                    guard abs(dx) > abs(dy) * 0.85 else { return }

	                    let predictedDx = value.predictedEndTranslation.width
	                    let effectiveDx = abs(predictedDx) > abs(dx) ? predictedDx : dx
	                    guard abs(effectiveDx) >= swipeThreshold else { return }

	                    guard let currentIndex = swipeOrder.firstIndex(of: selection) else { return }
	                    let nextIndex = currentIndex + (effectiveDx < 0 ? 1 : -1)
	                    guard swipeOrder.indices.contains(nextIndex) else { return }
	                    selection = swipeOrder[nextIndex]
	                    KuroAccessibility.impactHaptic(.light)
	                }
	        )
	            .onChange(of: selection) { _, newValue in
	                mountedSections.insert(newValue)
	            }
	            .task {
	                // Warm the Discover bundle so the first Discover render feels instant.
                _ = await supabaseService.fetchDiscoverBundle(limit: 30, hours: 24)
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView()
                    .environment(supabaseService)
            }
    }
}

// MARK: - Interactive section pager (keeps tabs mounted once visited)
private struct KuroSectionPager: View {
    typealias Section = KuroMainView.Section

    @Binding var selection: Section
    @Binding var mountedSections: Set<Section>
    let order: [Section]

    private var selectionIndex: Int {
        order.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let height = max(1, geo.size.height)

            HStack(spacing: 0) {
                ForEach(order, id: \.self) { section in
                    page(for: section)
                        .frame(width: width, height: height)
                }
            }
            .environment(\.kuroSuppressCardTaps, false)
            .offset(x: (-CGFloat(selectionIndex) * width))
            .clipped()
            // Animate only when the selection changes (header-driven paging).
            // This avoids gesture conflicts with in-page horizontal carousels.
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.92), value: selectionIndex)
        }
    }

    @ViewBuilder
    private func page(for section: Section) -> some View {
        let shouldMount = mountedSections.contains(section) || section == selection

        if shouldMount {
            switch section {
            case .concierge:
                ConciergeView(assistantEnabled: false)
            case .discover:
                EditorialDiscoverView()
            case .collection:
                EditorialCollectionView()
            case .browse:
                BrowseView()
            case .search:
                EditorialSearchView()
            }
        } else {
            // Placeholder keeps layout stable without triggering `.task` in heavy pages.
            Color.white
        }
    }
}

// MARK: - New Responsive Header Component (Fixed)
struct KuroHeaderNew: View {
    @Binding var selection: KuroMainView.Section
    @Binding var showProfileSheet: Bool
    @Environment(SupabaseService.self) private var supabaseService
    
    private let swipeOrder: [KuroMainView.Section] = [.concierge, .discover, .browse, .collection, .clubs]

    private static let windowTextPaddingX: CGFloat = 14
    private static let windowTextPaddingY: CGFloat = 7
    private static let windowTextSlack: CGFloat = 10

    @State private var displayedSection: KuroMainView.Section = .discover
    @State private var previousSection: KuroMainView.Section? = nil
    @State private var isForwardTransition = true
    @State private var titleProgress: CGFloat = 1.0
    @State private var titleTextWidth: CGFloat = 92

    private var currentTitle: String { selection.title }
    private var canSwipeLeft: Bool {
        guard let i = swipeOrder.firstIndex(of: selection) else { return false }
        return i > 0
    }
    private var canSwipeRight: Bool {
        guard let i = swipeOrder.firstIndex(of: selection) else { return false }
        return i < (swipeOrder.count - 1)
    }

    private static let titleFont = UIFont.systemFont(ofSize: 11, weight: .regular)
    private static let titleTracking: CGFloat = 1.5

    private static func measureTitleWidth(_ title: String) -> CGFloat {
        let base = (title as NSString).size(withAttributes: [.font: titleFont]).width
        let tracking = titleTracking * CGFloat(max(0, title.count - 1))
        return ceil(base + tracking)
    }

    private var titleWindow: some View {
        let hint = (canSwipeLeft || canSwipeRight)
        // Rounded "window" with edge shading (no heavy fill) for a physical mask feel.
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let innerMask = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let titleHeight: CGFloat = 16
        let travel = (titleTextWidth + (Self.windowTextPaddingX * 2) + 28)

        return ZStack {
            shape
                .fill(Color.clear)
                // Tiny fill keeps the shape "present" so the shadow reads, without tinting the interior.
                .background(shape.fill(Color.white.opacity(0.001)))
                .overlay(
                    shape
                        .stroke(Color.black.opacity(hint ? 0.12 : 0.06), lineWidth: 0.6)
                )
                // Subtle highlight to sell the "window" edge without changing the interior color.
                .overlay(
                    shape
                        .stroke(Color.white.opacity(0.75), lineWidth: 0.6)
                        .blendMode(.overlay)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)

            TitleWindowAnimator(
                current: displayedSection.title,
                previous: previousSection?.title,
                progress: titleProgress,
                forward: isForwardTransition,
                travel: travel
            )
            // Keep the window tight to the current word, but during the transition ensure
            // we have enough width for BOTH titles so nothing gets clipped mid-slide.
            .frame(width: max(54, titleTextWidth), height: titleHeight, alignment: .center)
            .padding(.horizontal, Self.windowTextPaddingX)
            .padding(.vertical, Self.windowTextPaddingY)
            // Clip only the moving text layer (cheaper than masking the whole window).
            .clipShape(innerMask)
        }
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityHidden(true)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Three-part layout with proper spacing
            HStack(alignment: .center) {
                // Left: Brand (30% opacity)
                HStack(spacing: 10) {
                    Text("KURO")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.black.opacity(0.3))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Center: Section (full opacity)
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        if selection == .concierge {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.7)
                                )
                                .overlay(
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.70))
                                )
                                .accessibilityHidden(true)
                        }

                        titleWindow
                    }
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Section")
                .accessibilityValue(currentTitle)
                .accessibilityHint("Swipe left or right to change sections.")
                .frame(maxWidth: .infinity, alignment: .center)

                // Right: Action (minimal interaction)
                HStack {
                    Spacer()
                    Menu {
                        Button("Profile") {
                            showProfileSheet = true
                        }
                        Button("Sign Out", role: .destructive) {
                            Task { await supabaseService.signOut() }
                        }
                    } label: {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(supabaseService.currentUserInitial)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.black.opacity(0.80))
                            )
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.7)
                            )
                    }
                    .buttonStyle(KuroHeaderIconButtonStyle())
                    .accessibilityLabel("Profile")
                    .accessibilityHint("Opens account menu")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Section navigation")
            .accessibilityValue(currentTitle)
            .accessibilityHint("Swipe left or right to change sections.")
            .onAppear {
                displayedSection = selection
                previousSection = nil
                titleProgress = 1.0
                titleTextWidth = Self.measureTitleWidth(selection.title) + Self.windowTextSlack
            }
            .onChange(of: selection) { _, newValue in
                let oldIndex = swipeOrder.firstIndex(of: displayedSection) ?? 0
                let newIndex = swipeOrder.firstIndex(of: newValue) ?? 0
                isForwardTransition = newIndex > oldIndex
                let from = displayedSection
                let fromWidth = Self.measureTitleWidth(from.title) + Self.windowTextSlack
                let toWidth = Self.measureTitleWidth(newValue.title) + Self.windowTextSlack

                previousSection = from
                displayedSection = newValue
                titleTextWidth = max(fromWidth, toWidth)

                titleProgress = 0.0
                withAnimation(.easeOut(duration: 0.18)) {
                    titleProgress = 1.0
                }

                // Clear previous after animation; avoids unnecessary layout work.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    if displayedSection == newValue {
                        previousSection = nil
                        withAnimation(.easeOut(duration: 0.12)) {
                            titleTextWidth = toWidth
                        }
                    }
                }
            }

            // Subtle divider
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
        .frame(height: 48)
        .background(Color.white)
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
    }
}

private struct TitleWindowAnimator: View {
    let current: String
    let previous: String?
    let progress: CGFloat
    let forward: Bool
    let travel: CGFloat

    var body: some View {
        let dir: CGFloat = forward ? 1 : -1

        return ZStack {
            if let previous {
                Text(previous)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .offset(x: (-progress) * dir * travel)
            }

            Text(current)
                .font(.system(size: 11, weight: .regular))
                .tracking(1.5)
                .foregroundColor(.black)
                .lineLimit(1)
                .offset(x: (1 - progress) * dir * travel)
        }
    }
}

private struct KuroHeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .rotationEffect(.degrees(configuration.isPressed ? -4 : 0))
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

// MARK: - New Discover View (Single Column Sophistication)
struct DiscoverViewNew: View {
    @Environment(SupabaseService.self) private var supabaseService
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if supabaseService.isLoading {
                LoadingStateViewNew()
            } else if supabaseService.animeItems.isEmpty {
                DiscoverEmptyStateView()
            } else {
                VStack(spacing: 48) {
                    // CURRENT SEASON Section
                    DiscoverSectionNew(
                        title: "CURRENT SEASON",
                        subtitle: "Airing now",
                        items: currentSeasonItems
                    )

                    // TRENDING NOW Section
                    DiscoverSectionNew(
                        title: "TRENDING NOW",
                        subtitle: "Most popular this week",
                        items: trendingItems
                    )

                    // NEWLY ADDED Section
                    DiscoverSectionNew(
                        title: "NEWLY ADDED",
                        subtitle: "Fresh to the collection",
                        items: newlyAddedItems
                    )

                    // TOP RATED Section
                    DiscoverSectionNew(
                        title: "TOP RATED",
                        subtitle: "Highest scores",
                        items: topRatedItems
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            Task {
                supabaseService.setPageSize(50)
                let total = KuroScreen.isLargeScreen ? 500 : 300
                await supabaseService.prefetchAnime(total: total)
            }
        }
    }

    // MARK: - Content Filters

    private var currentSeasonItems: [Anime] {
        // Filter for current season (2024-2025) - Show 3 items for elegance
        supabaseService.animeItems.filter { anime in
            (anime.seasonYear ?? 0) >= 2024 && anime.status == "RELEASING"
        }.prefix(3).map { $0 }
    }

    private var trendingItems: [Anime] {
        // Sort by popularity/trending - Show 3 items
        supabaseService.animeItems.sorted { ($0.trending ?? 0) > ($1.trending ?? 0) }
            .prefix(3).map { $0 }
    }

    private var newlyAddedItems: [Anime] {
        // Sort by created_at (newest first) - Show 3 items
        supabaseService.animeItems.sorted { $0.createdAt > $1.createdAt }
            .prefix(3).map { $0 }
    }

    private var topRatedItems: [Anime] {
        // Sort by average score - Show 3 items
        supabaseService.animeItems.filter { ($0.averageScore ?? 0) > 75 }
            .sorted { ($0.averageScore ?? 0) > ($1.averageScore ?? 0) }
            .prefix(3).map { $0 }
    }
}

// MARK: - New Discover Section (Single Column)
struct DiscoverSectionNew: View {
    let title: String
    let subtitle: String
    let items: [Anime]

    var body: some View {
        VStack(spacing: 0) {
            // Refined Section Header - More Editorial
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text(title)
                        .font(.system(size: 18, weight: .light, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.black)

                    Text(subtitle)
                        .font(.system(size: 10, weight: .light))
                        .tracking(0.8)
                        .foregroundColor(.black.opacity(0.35))
                        .padding(.bottom, 2)
                }

                Rectangle()
                    .fill(Color.black)
                    .frame(height: 0.5)
                    .frame(maxWidth: 60)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)

            // Section Content - Single column for sophistication
            VStack(spacing: 32) {
                ForEach(items, id: \.id) { anime in
                    SophisticatedAnimeCard(media: anime)
                }
            }
        }
    }
}

// MARK: - New Loading State View (Single Column)
struct LoadingStateViewNew: View {
    var body: some View {
        VStack(spacing: 48) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 0) {
                    // Section header skeleton
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 120, height: 11)

                        Rectangle()
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 80, height: 9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)

                    // Single column skeleton
                    VStack(spacing: 32) {
                        ForEach(0..<3, id: \.self) { _ in
                            SophisticatedCardLoading()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 48)
    }
}

// MARK: - Sophisticated Card Loading
struct SophisticatedCardLoading: View {
    var body: some View {
        HStack(spacing: 16) {
            // Left: Image placeholder
            Rectangle()
                .fill(Color.black.opacity(0.04))
                .frame(width: 100, height: 150)  // Fixed consistent size
                .overlay(
                    ProgressView()
                        .scaleEffect(0.5)
                        .foregroundColor(.black.opacity(0.2))
                )

            // Right: Text placeholders
            VStack(alignment: .leading, spacing: 8) {
                // Title placeholder
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)

                // Metadata placeholder
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 10)
                    .frame(width: 80)

                // Description placeholders
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(height: 11)
                        .frame(maxWidth: .infinity)
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(height: 11)
                        .frame(maxWidth: .infinity)
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(height: 11)
                        .frame(width: 120)
                }

                Spacer()

                // Genre placeholders
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(width: 50, height: 16)
                        .cornerRadius(8)
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(width: 40, height: 16)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150)
    }
}

// MARK: - Comprehensive Discover View with Sections
// MARK: - Sophisticated Discover Section Component
struct DiscoverSection: View {
    let title: String
    let subtitle: String
    let items: [Anime]
    let geometry: GeometryProxy
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let horizontalPadding: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Refined Section Header - More Editorial
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text(title)
                        .font(.system(size: 18, weight: .light, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.black)

                    Text(subtitle)
                        .font(.system(size: 10, weight: .light))
                        .tracking(0.8)
                        .foregroundColor(.black.opacity(0.35))
                        .padding(.bottom, 2)
                }

                Rectangle()
                    .fill(Color.black)
                    .frame(height: 0.5)
                    .frame(maxWidth: 60)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, max(geometry.size.width * 0.06, 24))

            // Section Content - Single column for sophistication
            VStack(spacing: max(geometry.size.width * 0.08, 32)) {
                ForEach(items, id: \.id) { anime in
                    SophisticatedAnimeCard(media: anime)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }
}

// MARK: - Loading State View
struct LoadingStateView: View {
    let geometry: GeometryProxy
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let horizontalPadding: CGFloat

    var body: some View {
        VStack(spacing: max(geometry.size.width * 0.12, 48)) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 0) {
                    // Section header skeleton
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 120, height: 11)

                        Rectangle()
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 80, height: 9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, max(geometry.size.width * 0.04, 16))

                    // Local sizing constants for grid and cards
                    let padding: CGFloat = 20
                    let perfectSpacing: CGFloat = 16
                    let columnsCount: Int = 2
                    let totalSpacing = CGFloat(columnsCount - 1) * perfectSpacing
                    let availableWidth = geometry.size.width - (2 * padding) - totalSpacing
                    let cardWidth = floor(availableWidth / CGFloat(columnsCount))
                    let textHeight: CGFloat = 72
                    let imageHeight: CGFloat = cardWidth / 0.7
                    let cardHeight: CGFloat = floor(imageHeight + 8 + textHeight)

                    LazyVGrid(
                        columns: [
                            GridItem(.fixed(cardWidth), spacing: perfectSpacing, alignment: .top),
                            GridItem(.fixed(cardWidth), spacing: perfectSpacing, alignment: .top)
                        ],
                        alignment: .center,
                        spacing: rowSpacing
                    ) {
                        ForEach(0..<6, id: \.self) { _ in
                            DiscoverCardLoading()
                                .frame(width: cardWidth, height: cardHeight, alignment: .top)
                        }
                    }
                    .padding(.horizontal, padding)
                }
            }
        }
        .padding(.top, max(geometry.size.width * 0.06, 24))
        .padding(.bottom, max(geometry.size.width * 0.12, 48))
    }
}

// MARK: - Discover Empty State View
struct DiscoverEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("LOADING YOUR COLLECTION...")
                .font(.system(size: 14, weight: .light))
                .tracking(1.0)
                .foregroundColor(.black.opacity(0.6))

            Text("Connecting to Supabase...")
                .font(.system(size: 12, weight: .light))
                .tracking(0.5)
                .foregroundColor(.black.opacity(0.3))

            ProgressView()
                .scaleEffect(0.8)
                .padding(.top, 20)
        }
        .padding(.top, 80)
    }
}

struct CollectionViewSimple: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var filter = "ALL"
    let filters = ["ALL", "WATCHING", "COMPLETED", "PLANNED"]
    @State private var mediaIsManga = false
    @State private var displayCount = 60
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Media toggle + Filter tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 32) {
                        FilterTabSimple(
                            title: mediaIsManga ? "MANGA" : "ANIME",
                            isSelected: true,
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) { mediaIsManga.toggle() }
                                if mediaIsManga && supabaseService.mangaItems.isEmpty {
                                    Task { await supabaseService.prefetchManga(total: 300) }
                                }
                            }
                        )
                        ForEach(filters, id: \.self) { filterOption in
                            FilterTabSimple(
                                title: filterOption,
                                isSelected: filter == filterOption,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        filter = filterOption
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 20)
                
                // Collection grid with PERFECT spacing to match reference
                ScrollView(.vertical, showsIndicators: false) {
                    // Collection grid with DESIGN-SYSTEM spacing & fixed card size
                    let metrics = KuroCardMetrics.grid(for: geometry.size.width, columns: 2)
                    let columns = metrics.columns
                    let cardWidth = metrics.cardWidth
                    let cardHeight = metrics.cardHeight
                    
                    // Create grid with PERFECT spacing to match reference
                    LazyVGrid(
                        columns: columns,
                        alignment: .center,
                        spacing: 16
                    ) {
                        if supabaseService.isLoading {
                            ForEach(0..<9, id: \.self) { _ in
                                CollectionCardLoading()
                                    .frame(width: cardWidth, height: cardHeight, alignment: .top)
                            }
                        } else if mediaIsManga, !collectionManga.isEmpty {
                            let items = Array(collectionManga.prefix(displayCount))
                            ForEach(items, id: \.id) { manga in
                                CollectionCardReal(media: manga)
                                    .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                    .onAppear {
                                        if manga.id == items.last?.id {
                                            displayCount = min(displayCount + 60, collectionManga.count)
                                        }
                                    }
                            }
                        } else if !mediaIsManga, !collectionAnime.isEmpty {
                            let items = Array(collectionAnime.prefix(displayCount))
                            ForEach(items, id: \.id) { anime in
                                CollectionCardReal(media: anime)
                                    .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                    .onAppear {
                                        if anime.id == items.last?.id {
                                            displayCount = min(displayCount + 60, collectionAnime.count)
                                        }
                                    }
                            }
                        } else {
                            // Fallback to general list if user collection is empty
                            if mediaIsManga {
                                let items = Array(supabaseService.mangaItems.prefix(displayCount))
                                ForEach(items, id: \.id) { manga in
                                    CollectionCardReal(media: manga)
                                        .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                        .onAppear {
                                            if manga.id == items.last?.id {
                                                displayCount = min(displayCount + 60, supabaseService.mangaItems.count)
                                                if supabaseService.hasMoreManga {
                                                    Task { await supabaseService.fetchNextMangaPage() }
                                                }
                                            }
                                        }
                                }
                            } else {
                                let items = Array(supabaseService.animeItems.prefix(displayCount))
                                ForEach(items, id: \.id) { anime in
                                    CollectionCardReal(media: anime)
                                        .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                        .onAppear {
                                            if anime.id == items.last?.id {
                                                displayCount = min(displayCount + 60, supabaseService.animeItems.count)
                                                if supabaseService.hasMoreAnime {
                                                    Task { await supabaseService.fetchNextAnimePage() }
                                                }
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            Task {
                await supabaseService.fetchUserLists()
                supabaseService.setPageSize(50)
                if supabaseService.animeItems.isEmpty { await supabaseService.prefetchAnime(total: 300) }
                if supabaseService.mangaItems.isEmpty { await supabaseService.prefetchManga(total: 300) }
            }
        }
    }

    // Map filter string to DB list type
    private var selectedStatus: ListStatus? {
        switch filter {
        case "WATCHING": return .current
        case "COMPLETED": return .completed
        case "PLANNED": return .planning
        default: return nil
        }
    }

    // Build collection items from user lists and available anime cache
    private var collectionAnime: [Anime] {
        let ids: Set<Int> = Set(
            supabaseService.userLists
                .filter { $0.mediaType.lowercased() == "anime" }
                .filter { entry in
                    guard let s = selectedStatus else { return true }
                    return entry.status == s
                }
                .map { $0.mediaId }
        )
        if ids.isEmpty { return [] }
        let lookup: [Int: Anime] = Dictionary(uniqueKeysWithValues: supabaseService.animeItems.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var collectionManga: [Manga] {
        let ids: Set<Int> = Set(
            supabaseService.userLists
                .filter { $0.mediaType.lowercased() == "manga" }
                .filter { entry in
                    guard let s = selectedStatus else { return true }
                    return entry.status == s
                }
                .map { $0.mediaId }
        )
        if ids.isEmpty { return [] }
        let lookup: [Int: Manga] = Dictionary(uniqueKeysWithValues: supabaseService.mangaItems.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

// MARK: - New Search View (Single Column)
#if false
struct SearchViewNew: View {
    @Environment(SupabaseService.self) private var supabaseService
    @State private var searchText: String = ""
    @State private var selectedCategories: Set<String> = []
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var sheetAnime: Anime? = nil
    @State private var mediaIsManga: Bool = false
    // Season filter (explicit control)
    @State private var selectedSeasonNameSearch: String = {
        let m = Calendar.current.component(.month, from: Date())
        switch m { case 12,1,2: return "WINTER"; case 3,4,5: return "SPRING"; case 6,7,8: return "SUMMER"; default: return "FALL" }
    }()
    @State private var selectedSeasonYearSearch: Int = Calendar.current.component(.year, from: Date())

    // Filter results based on search and categories
    private var filteredAnimeResults: [Anime] {
        let base = searchText.isEmpty ? supabaseService.animeItems : supabaseService.searchAnimeItems
        var results = base
        
        // Apply text search
        if !searchText.isEmpty {
            results = results.filter { media in
                media.title.localizedCaseInsensitiveContains(searchText) ||
                media.displayDescription.localizedCaseInsensitiveContains(searchText) ||
                media.genres?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false
            }
        }
        
        // Apply category filters
        if !selectedCategories.isEmpty {
            results = results.filter { media in
                selectedCategories.contains { category in
                    switch category {
                    case "TRENDING":
                        return (media.averageScore ?? 0) > 80
                    case "NEW SEASON":
                        return Int(media.year) ?? 0 >= 2020
                    case "CLASSICS":
                        return Int(media.year) ?? 0 < 2010
                    case "HIDDEN GEMS":
                        return (media.averageScore ?? 0) > 85 && Int(media.year) ?? 0 < 2015
                    default:
                        return false
                    }
                }
            }
        }
        
        return results
    }
    
    private var filteredMangaResults: [Manga] {
        let base = searchText.isEmpty ? supabaseService.mangaItems : supabaseService.searchMangaItems
        var results = base
        if !searchText.isEmpty {
            results = results.filter { media in
                media.title.localizedCaseInsensitiveContains(searchText) ||
                media.displayDescription.localizedCaseInsensitiveContains(searchText) ||
                media.genres?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false
            }
        }
        if !selectedCategories.isEmpty {
            results = results.filter { media in
                selectedCategories.contains { category in
                    switch category {
                    case "TRENDING":
                        return (media.averageScore ?? 0) > 80
                    case "NEW SEASON":
                        return (media.startDateYear ?? 0) >= 2020
                    case "CLASSICS":
                        return (media.startDateYear ?? 0) < 2010
                    case "HIDDEN GEMS":
                        return (media.averageScore ?? 0) > 85 && (media.startDateYear ?? 0) < 2015
                    default:
                        return false
                    }
                }
            }
        }
        return results
    }
    
    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = max(geometry.size.width * 0.05, 20)
            
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.black.opacity(0.3))
                        .font(.system(size: 16, weight: .light))
                    
                    TextField("SEARCH ANIME", text: $searchText)
                        .font(.system(size: 14, weight: .light))
                        .tracking(0.5)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.05))
                .cornerRadius(0)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)
                
                // Category pills with selection
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Media toggle
                        CategoryPillSelectable(
                            title: mediaIsManga ? "MANGA" : "ANIME",
                            isSelected: true,
                            action: {
                                mediaIsManga.toggle()
                                if mediaIsManga && supabaseService.mangaItems.isEmpty {
                                    Task { await supabaseService.prefetchManga(total: 300) }
                                }
                            }
                        )
                        ForEach(["TRENDING", "TRENDING AIRING", "AIRING", "THIS SEASON", "SEASON", "NEW SEASON", "CLASSICS", "HIDDEN GEMS"], id: \.self) { category in
                            CategoryPillSelectable(
                                title: category,
                                isSelected: selectedCategories.contains(category)
                            ) {
                                if selectedCategories.contains(category) {
                                    selectedCategories.remove(category)
                                } else {
                                    selectedCategories.insert(category)
                                }
                                // Trigger debounced search with new filters
                                debounceSearch()
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
                .padding(.vertical, 20)

                // Reset filters
                HStack {
                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        selectedCategories.removeAll()
                        // Reset season selector to current
                        let m = Calendar.current.component(.month, from: Date())
                        selectedSeasonNameSearch = (m == 12 || m == 1 || m == 2) ? "WINTER" : (m <= 5 ? "SPRING" : (m <= 8 ? "SUMMER" : "FALL"))
                        selectedSeasonYearSearch = Calendar.current.component(.year, from: Date())
                        debounceSearch()
                    }) {
                        Text("RESET FILTERS")
                            .font(.system(size: 10, weight: .regular))
                            .tracking(1.2)
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    Spacer()
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 8)
                
                // Season picker controls (visible when SEASON facet is active)
                if selectedCategories.contains("SEASON") {
                    HStack(spacing: 8) {
                        Button(action: {
                            KuroAccessibility.impactHaptic(.light)
                            previousSeasonSearch()
                            debounceSearch()
                        }) {
                            Image(systemName: "chevron.left").foregroundColor(.black.opacity(0.6))
                        }
                        Text("\(selectedSeasonNameSearch) \(selectedSeasonYearSearch)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.black)
                        Button(action: {
                            KuroAccessibility.impactHaptic(.light)
                            nextSeasonSearch()
                            debounceSearch()
                        }) {
                            Image(systemName: "chevron.right").foregroundColor(.black.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, horizontalPadding)
                }
                
                // Search Results with single column layout
                if !searchText.isEmpty || !selectedCategories.isEmpty {
                    if supabaseService.isLoading {
                        ProgressView("Searching...")
                            .padding(.top, 40)
                    } else if filteredAnimeResults.isEmpty {
                        VStack(spacing: 8) {
                            Text("NO RESULTS FOUND")
                                .font(.system(size: 11, weight: .regular))
                                .tracking(1.5)
                                .foregroundColor(.black.opacity(0.3))
                            
                            Text("Try adjusting your search or filters")
                                .font(.system(size: 10, weight: .light))
                                .tracking(1.0)
                                .foregroundColor(.black.opacity(0.2))
                        }
                        .padding(.top, 60)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            // Collection grid with DESIGN-SYSTEM spacing & fixed card size
                            let metrics = KuroCardMetrics.grid(for: geometry.size.width, columns: 2)
                            let columns = metrics.columns
                            let cardWidth = metrics.cardWidth
                            let cardHeight = metrics.cardHeight
                            
                            LazyVGrid(
                                columns: columns,
                                alignment: .center,
                                spacing: 16
                            ) {
                                if mediaIsManga {
                                    ForEach(filteredMangaResults) { manga in
                                        CollectionCardReal(media: manga)
                                            .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                    }
                                } else {
                                    ForEach(filteredAnimeResults) { anime in
                                        CollectionCardReal(media: anime)
                                            .frame(width: cardWidth, height: cardHeight, alignment: .top)
                                    }
                                }
                            }
                            .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                            .padding(.bottom, 40)
                            
                            // Show More for search base set (API-backed)
                            if mediaIsManga ? supabaseService.hasMoreManga : supabaseService.hasMoreAnime {
                                Button(action: {
                                    KuroAccessibility.impactHaptic(.light)
                                    Task {
                                        if !searchText.isEmpty {
                                            await supabaseService.fetchNextSearchPage()
                                        } else {
                                            if mediaIsManga { await supabaseService.fetchNextMangaPage() }
                                            else { await supabaseService.fetchNextAnimePage() }
                                        }
                                    }
                                }) {
                                    Text("SHOW MORE")
                                        .font(.system(size: 11, weight: .regular))
                                        .tracking(1.5)
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                        )
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, KuroCardMetrics.horizontalPadding)
                                .padding(.top, 8)
                                .padding(.bottom, 20)
                            }
                        }
                        .sheet(item: $sheetAnime) { anime in
                            AnimeDetailView(anime: anime)
                        }
                    }
                } else {
                    Spacer()
                    
                    VStack(spacing: 8) {
                        Text("BEGIN TYPING TO SEARCH")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(1.5)
                            .foregroundColor(.black.opacity(0.3))
                        
                        Text("DISCOVER YOUR NEXT OBSESSION")
                            .font(.system(size: 10, weight: .light))
                            .tracking(1.0)
                            .foregroundColor(.black.opacity(0.2))
                    }
                    .padding(.top, 80)
                    
                    Spacer()
                }
            }
        }
        .onChange(of: searchText) { _, _ in
            debounceSearch()
        }
        .onAppear {
            // Load data if not already loaded
            Task {
                supabaseService.setPageSize(50)
                if supabaseService.animeItems.isEmpty { await supabaseService.prefetchAnime(total: 300) }
                if supabaseService.mangaItems.isEmpty { await supabaseService.prefetchManga(total: 300) }
            }
        }
    }
    
    private func performSearch() {
        Task {
            supabaseService.resetSearch(query: searchText, isManga: mediaIsManga)
            var filters = SupabaseService.SearchFilters(
                trending: selectedCategories.contains("TRENDING") || selectedCategories.contains("TRENDING AIRING"),
                newSeason: selectedCategories.contains("NEW SEASON"),
                classics: selectedCategories.contains("CLASSICS"),
                hiddenGems: selectedCategories.contains("HIDDEN GEMS"),
                airingOnly: selectedCategories.contains("AIRING") || selectedCategories.contains("TRENDING AIRING")
            )
            if selectedCategories.contains("THIS SEASON") {
                let m = Calendar.current.component(.month, from: Date())
                let season: String = (m == 12 || m == 1 || m == 2) ? "WINTER" : (m <= 5 ? "SPRING" : (m <= 8 ? "SUMMER" : "FALL"))
                filters.seasonName = season
                filters.seasonYear = Calendar.current.component(.year, from: Date())
            }
            if selectedCategories.contains("SEASON") {
                filters.seasonName = selectedSeasonNameSearch
                filters.seasonYear = selectedSeasonYearSearch
            }
            supabaseService.setSearchFilters(filters)
            await supabaseService.fetchNextSearchPage()
        }
    }

    private func previousSeasonSearch() {
        let order = ["WINTER","SPRING","SUMMER","FALL"]
        guard let idx = order.firstIndex(of: selectedSeasonNameSearch) else { return }
        let newIdx = (idx + 3) % 4
        if newIdx == 3 && idx == 0 { selectedSeasonYearSearch -= 1 }
        selectedSeasonNameSearch = order[newIdx]
    }

    private func nextSeasonSearch() {
        let order = ["WINTER","SPRING","SUMMER","FALL"]
        guard let idx = order.firstIndex(of: selectedSeasonNameSearch) else { return }
        let newIdx = (idx + 1) % 4
        if newIdx == 0 && idx == 3 { selectedSeasonYearSearch += 1 }
        selectedSeasonNameSearch = order[newIdx]
    }
    
    private func debounceSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                performSearch()
            }
        }
    }
}
#endif

// Legacy search UI is kept for reference; the app uses the RPC-backed `EditorialSearchView`.
struct SearchViewNew: View {
    var body: some View { EditorialSearchView() }
}

// MARK: - Search View with debounce
// MARK: - Enhanced Components

struct CategoryPillSelectable: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .tracking(1.0)
                .foregroundColor(.black.opacity(isSelected ? 1.0 : 0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .stroke(Color.black.opacity(isSelected ? 0.8 : 0.15), lineWidth: 0.5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(isSelected ? 0.05 : 0.0))
                        )
                )
        }
    }
}

struct SearchResultRowReal: View {
    let media: any MediaDisplayable
    @State private var showDetail = false
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            HStack(alignment: .top, spacing: 16) { // Top alignment for consistent rows
                // Fixed-size image container
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.5)
                                .foregroundColor(.black.opacity(0.3))
                        )
                }
                .frame(width: 50, height: 70, alignment: .center) // Fixed dimensions
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                
                // Text content with consistent spacing
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title.uppercased())
                        .font(.system(size: 12, weight: .regular))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("\(media.year) · \(media.genres?.first ?? "Unknown")")
                        .font(.system(size: 10, weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.5))
                    
                    if let episodes = media.episodes {
                        Text("\(episodes) EPS")
                            .font(.system(size: 9, weight: .light))
                            .tracking(0.5)
                            .foregroundColor(.black.opacity(0.3))
                    } else if let chapters = media.chapters {
                        Text("\(chapters) CH")
                            .font(.system(size: 9, weight: .light))
                            .tracking(0.5)
                            .foregroundColor(.black.opacity(0.3))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading) // Fill available space
                
                // Rating and chevron section
                VStack(alignment: .trailing, spacing: 8) {
                    if let rating = media.rating {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.black.opacity(0.8))
                            
                            Text("★")
                                .font(.system(size: 8))
                                .foregroundColor(.black.opacity(0.3))
                        }
                    }
                    
                    Spacer() // Push chevron to bottom
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(.black.opacity(0.2))
                }
                .frame(height: 70) // Match image height for consistent alignment
            }
            .frame(minHeight: 70) // Ensure consistent row height
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            } else if let manga = media as? Manga {
                MangaDetailView(manga: manga)
            }
        }
    }
}

struct CollectionCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .aspectRatio(0.7, contentMode: .fill)
                .frame(maxWidth: .infinity, alignment: .center) // Center alignment for loading
                .overlay(
                    ProgressView()
                        .scaleEffect(0.6)
                        .foregroundColor(.black.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 9)
                    .frame(width: 40)
            }
            .frame(height: 72)
            .frame(maxWidth: .infinity, alignment: .leading) // Consistent text width
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 10)
                .shadow(color: .black.opacity(0.02), radius: 5, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

struct CollectionCardReal: View {
    let media: any MediaDisplayable
    @State private var showDetail = false
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                                .foregroundColor(.black.opacity(0.3))
                        )
                }
                .aspectRatio(0.7, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                // Text content with fixed height container
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title.uppercased())
                        .font(.system(size: 10, weight: .regular))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("\(media.year) · \(episodeText)")
                        .font(.system(size: 9, weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.5))
                    
                    if let rating = media.rating {
                        HStack(spacing: 2) {
                            Text("★")
                                .font(.system(size: 8))
                                .foregroundColor(.black.opacity(0.4))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 8, weight: .light))
                                .foregroundColor(.black.opacity(0.4))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading) // Consistent text width
                .frame(height: 72) // Fixed text area height to enforce uniform card height
                .padding(.top, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 10)
                    .shadow(color: .black.opacity(0.02), radius: 5, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            } else if let manga = media as? Manga {
                MangaDetailView(manga: manga)
            }
        }
    }
    
    private var episodeText: String {
        if let episodes = media.episodes {
            return "\(episodes) EPS"
        } else if let chapters = media.chapters {
            return "\(chapters) CH"
        } else {
            return "Movie"
        }
    }
}

// MARK: - Simple Components
struct MoodPillSimple: View {
    let mood: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(mood.uppercased())
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(isSelected ? 1.0 : 0.3))
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 0.5)
                    .scaleEffect(x: isSelected ? 1.0 : 0.0, anchor: .center)
                    .opacity(isSelected ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.3), value: isSelected)
            }
        }
    }
}

struct FeaturedCardSimple: View {
    let title: String
    let year: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Placeholder image
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .overlay(
                    Text("IMAGE")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundColor(.black.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 12) {
                Text(title.uppercased())
                    .font(.system(size: 20, weight: .ultraLight, design: .serif))
                    .tracking(0.5)
                    .foregroundColor(.black)
                
                Text(year)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(0.5))
                
                Text(description)
                    .font(.system(size: 11, weight: .light))
                    .tracking(1.0)
                    .foregroundColor(.black.opacity(0.6))
                    .lineSpacing(4)
            }
            .padding(.vertical, 24)
        }
    }
}

struct CollectionCardSimple: View {
    let title: String
    let year: String
    let episodeText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .aspectRatio(0.7, contentMode: .fill)
                .overlay(
                    Text("IMG")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.black.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.8))
                    .lineLimit(2)
                
                Text("\(year) · \(episodeText)")
                    .font(.system(size: 9, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.5))
            }
            .frame(height: 72)
            .padding(.top, 8)
        }
    }
}

struct FilterTabSimple: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black.opacity(isSelected ? 1.0 : 0.3))
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 0.5)
                    .scaleEffect(x: isSelected ? 1.0 : 0.0, anchor: .center)
                    .opacity(isSelected ? 1.0 : 0.0)
            }
        }
    }
}

struct CategoryPillSimple: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .regular))
            .tracking(1.0)
            .foregroundColor(.black.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
            )
    }
}

struct SearchResultRowSimple: View {
    let title: String
    let year: String
    let genre: String
    
    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(width: 50, height: 70)
                .overlay(
                    Text("IMG")
                        .font(.system(size: 8, weight: .light))
                        .foregroundColor(.black.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .regular))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.8))
                    .lineLimit(1)
                
                Text("\(year) · \(genre)")
                    .font(.system(size: 10, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.5))
                
                Text("12 EPS")
                    .font(.system(size: 9, weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.3))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .light))
                .foregroundColor(.black.opacity(0.2))
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Sophisticated Single-Column Card (Grown-Up Design)
struct SophisticatedAnimeCard: View {
    let media: any MediaDisplayable
    @State private var showDetail = false

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.medium)
            showDetail = true
        }) {
            HStack(spacing: 16) {
                // Left: Portrait Cover Image
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.04))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.5)
                                .foregroundColor(.black.opacity(0.2))
                        )
                }
                .frame(width: 100, height: 150)  // Fixed consistent size
                .clipped()
                .cornerRadius(0)

                // Right: Elegant Info Section
                VStack(alignment: .leading, spacing: 8) {
                    // Title - Large Serif
                    Text(media.title.uppercased())
                        .font(.system(size: 16, weight: .light, design: .serif))
                        .tracking(0.3)
                        .foregroundColor(.black)
                        .lineLimit(3)
                        .lineSpacing(2)

                    // Metadata Line
                    HStack(spacing: 6) {
                        Text(media.year)
                            .font(.system(size: 10, weight: .light))
                            .tracking(1.0)
                            .foregroundColor(.black.opacity(0.4))

                        if let rating = media.rating {
                            Text("·")
                                .foregroundColor(.black.opacity(0.2))
                            HStack(spacing: 2) {
                                Text("★")
                                    .font(.system(size: 9))
                                    .foregroundColor(.black.opacity(0.4))
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 10, weight: .medium))
                                    .tracking(0.5)
                                    .foregroundColor(.black.opacity(0.6))
                            }
                        }

                        if let episodes = media.episodes {
                            Text("·")
                                .foregroundColor(.black.opacity(0.2))
                            Text("\(episodes) EP")
                                .font(.system(size: 10, weight: .light))
                                .tracking(0.8)
                                .foregroundColor(.black.opacity(0.4))
                        }
                    }

                    // Description - Sophisticated
                    if !media.displayDescription.isEmpty {
                        Text(media.displayDescription)
                            .font(.system(size: 11, weight: .light))
                            .tracking(0.2)
                            .foregroundColor(.black.opacity(0.5))
                            .lineLimit(3)
                            .lineSpacing(3)
                    }

                    Spacer()

                    // Genres - Minimal Pills
                    if let genres = media.genres?.prefix(3) {
                        HStack(spacing: 6) {
                            ForEach(Array(genres), id: \.self) { genre in
                                Text(genre.uppercased())
                                    .font(.system(size: 8, weight: .medium))
                                    .tracking(0.8)
                                    .foregroundColor(.black.opacity(0.6))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                                    )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 150)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            } else if let manga = media as? Manga {
                MangaDetailView(manga: manga)
            }
        }
    }
}

// MARK: - Elegant 2-Column Discover Card (Legacy - Kept for Collection/Search)
struct DiscoverCardElegant: View {
    let media: any MediaDisplayable
    @State private var showDetail = false

    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Cover image with elegant portrait aspect ratio
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                                .foregroundColor(.black.opacity(0.3))
                        )
                }
                .aspectRatio(0.7, contentMode: .fill) // Elegant portrait ratio
                .clipped()
                .cornerRadius(0) // Sharp corners for minimalism

                // Minimal info section
                VStack(alignment: .leading, spacing: 6) {
                    // Title - elegant serif
                    Text(media.title.uppercased())
                        .font(.system(size: 13, weight: .light, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Year and type - minimal metadata
                    HStack(spacing: 4) {
                        Text(media.year)
                            .font(.system(size: 9, weight: .light))
                            .tracking(0.8)
                            .foregroundColor(.black.opacity(0.5))

                        if let rating = media.rating {
                            Text("·")
                                .foregroundColor(.black.opacity(0.3))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 9, weight: .light))
                                .tracking(0.8)
                                .foregroundColor(.black.opacity(0.5))
                        }
                    }
                }
                .frame(height: 72)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            } else if let manga = media as? Manga {
                MangaDetailView(manga: manga)
            }
        }
    }
}

// MARK: - Elegant Loading Card for 2-Column Grid
struct DiscoverCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image placeholder
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .aspectRatio(0.7, contentMode: .fill)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.6)
                        .foregroundColor(.black.opacity(0.3))
                )

            // Info placeholder
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 13)
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 9)
                    .frame(width: 60)
            }
            .frame(height: 72)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Real Firebase Data Components (Original Featured Card - kept for reference)
struct FeaturedCardReal: View {
    let media: any MediaDisplayable
    @State private var showDetail = false
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Real image or placeholder
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            Text("IMAGE")
                                .font(.system(size: 24, weight: .ultraLight))
                                .foregroundColor(.black.opacity(0.3))
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .clipped()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text(media.title.uppercased())
                        .font(.system(size: 20, weight: .ultraLight, design: .serif))
                        .tracking(0.5)
                        .foregroundColor(.black)
                    
                    Text("\(media.year)")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.black.opacity(0.5))
                    
                    Text(media.displayDescription)
                        .font(.system(size: 11, weight: .light))
                        .tracking(1.0)
                        .foregroundColor(.black.opacity(0.6))
                        .lineSpacing(4)
                        .lineLimit(3)
                }
                .padding(.vertical, 24)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            if let anime = media as? Anime {
                AnimeDetailView(anime: anime)
            } else if let manga = media as? Manga {
                MangaDetailView(manga: manga)
            }
        }
    }
}

struct FeaturedCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(.black.opacity(0.3))
                )
            
            VStack(alignment: .leading, spacing: 12) {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 20)
                    .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 12)
                    .frame(width: 60)
                
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 24)
        }
    }
}



// MARK: - Preview
#Preview {
    ContentView()
        .environment(SupabaseService.shared)
}

```

### iOS Supabase client + RPC/Edge wiring (authoritative)

- Path: `Kuro/Services/SupabaseService.swift`


```swift
import Foundation
import Observation
import UserNotifications

#if canImport(Supabase)
import Supabase

// MARK: - Supabase Service
// Connects to your existing comprehensive database schema

@MainActor
@Observable
class SupabaseService {
    static let shared = SupabaseService()
    
    // Supabase client
    private let client: SupabaseClient
    // Realtime (user-scoped) subscriptions
    private var realtimeChannel: RealtimeChannelV2? = nil
    private var realtimeListenTasks: [Task<Void, Never>] = []
    private var realtimeDebounceTask: Task<Void, Never>? = nil
    private var realtimeSubscribedUserId: String? = nil

    // Auth state
    var isAuthBootstrapping: Bool = true
    var isAuthenticated: Bool = false
    var authErrorMessage: String? = nil
    // Lightweight identity for UI (header menus, etc.)
    var currentUserEmail: String? = nil

    var currentUserInitial: String {
        let c = currentUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).first
        return c.map { String($0).uppercased() } ?? "M"
    }
    
    // Observable properties (no @Published needed with @Observable)
    var animeItems: [Anime] = []
    var mangaItems: [Manga] = []
    // User's personal collection (server-driven; doesn't rely on global prefetch)
    // Lightweight cards for collection grids; details are loaded on demand.
    var collectionAnimeItems: [AnimeCard] = []
    var collectionMangaItems: [MangaCard] = []
    // Unified feed used by the main Collection screen (anime + manga interleaved by last updated).
    var collectionFeedItems: [Media] = []
    var isCollectionLoading: Bool = false
    var collectionErrorMessage: String? = nil
    var userLists: [UserList] = []
    var episodes: [Episode] = []
    // Detail caches: cards/grids only carry minimal fields; we fetch full details by id on demand.
    private var animeDetailCache: [Int: Anime] = [:]
    private var mangaDetailCache: [Int: Manga] = [:]
    // De-dupe frequently called network fetches so multiple screens mounting doesn't fan-out.
    private var userListsFetchInFlight: Task<Void, Never>? = nil
    private var collectionFetchInFlight: Task<Void, Never>? = nil
    private var collectionFetchGeneration: Int = 0
    private var collectionFetchInFlightGeneration: Int = 0
    private var collectionFeedFetchInFlight: Task<Void, Never>? = nil
    private var collectionFeedFetchGeneration: Int = 0
    private var collectionFeedFetchInFlightGeneration: Int = 0
    private var upcomingFetchInFlight: Task<Void, Never>? = nil

    // Lightweight response caches (avoid refetching the same rails/recs when a view reappears).
    private struct TimedCache<T>: Sendable {
        let value: T
        let storedAt: Date
    }

    private var discoverBundleCache: [String: TimedCache<DiscoverBundle>] = [:]
    private var discoverBundleInFlight: [String: Task<DiscoverBundle?, Never>] = [:]

    private var conciergeRecommendCache: [String: TimedCache<ConciergeRecommendResponse>] = [:]
    private var conciergeRecommendInFlight: [String: Task<ConciergeRecommendResponse, Error>] = [:]

    private var conciergeParseCache: [String: TimedCache<ConciergeParseResponse>] = [:]
    private var conciergeParseInFlight: [String: Task<ConciergeParseResponse, Error>] = [:]

    private func trimCache<T>(_ cache: inout [String: TimedCache<T>], maxEntries: Int) {
        guard cache.count > maxEntries else { return }
        let sorted = cache.sorted { $0.value.storedAt < $1.value.storedAt }
        let removeCount = max(0, sorted.count - maxEntries)
        for (k, _) in sorted.prefix(removeCount) { cache.removeValue(forKey: k) }
    }

    private struct BackoffState: Sendable {
        var failures: Int = 0
        var until: Date? = nil

        mutating func canAttempt(now: Date = Date()) -> Bool {
            guard let until else { return true }
            return now >= until
        }

        mutating func recordSuccess() {
            failures = 0
            until = nil
        }

        mutating func recordFailure(now: Date = Date()) {
            failures = min(failures + 1, 6)
            let base: Double = 2.0
            let delay = min(60.0, base * pow(2.0, Double(failures - 1)))
            until = now.addingTimeInterval(delay)
        }
    }

    private var upcomingBackoff = BackoffState()
    private var lastUpcomingFetchAt: Date? = nil
    private var lastUpcomingDays: Int = 7

    // Collection pagination state (keyset by list updated_at + list row id).
    var hasMoreCollectionAnime: Bool = true
    var hasMoreCollectionManga: Bool = true
    var isLoadingMoreCollectionAnime: Bool = false
    var isLoadingMoreCollectionManga: Bool = false
    private var collectionAnimeCursorUpdatedAt: Date? = nil
    private var collectionAnimeCursorRowId: Int? = nil
    private var collectionMangaCursorUpdatedAt: Date? = nil
    private var collectionMangaCursorRowId: Int? = nil

    // Collection feed pagination state (keyset by updated_at + source_rank + list row id).
    var hasMoreCollectionFeed: Bool = true
    var isLoadingMoreCollectionFeed: Bool = false
    private var collectionFeedCursorUpdatedAt: Date? = nil
    private var collectionFeedCursorSourceRank: Int? = nil
    private var collectionFeedCursorRowId: Int? = nil

    private var currentCollectionStatusFilter: ListStatus? = nil
    // Upcoming airings for user's saved anime (next X days)
    struct UpcomingAiring: Decodable, Sendable {
        let anime_id: Int
        let title_english: String?
        let title_romaji: String?
        let next_episode_number: Int?
        let next_airing_at: Date
    }
    var upcomingAirings: [UpcomingAiring] = []
    // Formatted countdowns keyed by anime_id
    var countdownByAnimeId: [Int: String] = [:]
    private var countdownTimer: Timer?
    var isLoading = false
    var errorMessage: String?

    private let animeProviderRanking: [String] = [
        "crunchyroll",
        "netflix",
        "hidive",
        "disney",
        "amazon",
        "prime",
        "hulu",
        "youtube",
        "apple",
        "max"
    ]

    private let mangaProviderRanking: [String] = [
        "manga plus",
        "viz",
        "bookwalker",
        "comixology",
        "kindle",
        "kodansha",
        "yen press",
        "azuki"
    ]

    // MARK: - Discovery policy
    struct DiscoveryPolicy: Sendable {
        var includeAdult: Bool = false
        var excludeEcchi: Bool = true
    }

    static let canonicalGenres: [String] = [
        "Action",
        "Adventure",
        "Comedy",
        "Drama",
        "Ecchi",
        "Fantasy",
        "Hentai",
        "Horror",
        "Mahou Shoujo",
        "Mecha",
        "Music",
        "Mystery",
        "Psychological",
        "Romance",
        "Sci-Fi",
        "Slice of Life",
        "Sports",
        "Supernatural",
        "Thriller"
    ]

    private func sanitizeAnimeForDiscovery(_ items: [Anime], policy: DiscoveryPolicy = .init()) -> [Anime] {
        items.filter { anime in
            if !policy.includeAdult {
                if anime.isAdult { return false }
                if anime.genres?.contains("Hentai") == true { return false }
            }
            if policy.excludeEcchi {
                if anime.genres?.contains("Ecchi") == true { return false }
            }
            return true
        }
    }

    private func sanitizeMangaForDiscovery(_ items: [Manga], policy: DiscoveryPolicy = .init()) -> [Manga] {
        items.filter { manga in
            if !policy.includeAdult {
                if manga.isAdult { return false }
                if manga.genres?.contains("Hentai") == true { return false }
            }
            if policy.excludeEcchi {
                if manga.genres?.contains("Ecchi") == true { return false }
            }
            return true
        }
    }

    // Search state (paged server-side text search)
    // NOTE: These are lightweight cards (rank included for keyset pagination).
    var searchAnimeItems: [AnimeCard] = []
    var searchMangaItems: [MangaCard] = []
    private var currentSearchQuery: String = ""
    private enum SearchMode { case anime, manga, combined }
    private var searchMode: SearchMode = .anime
    private var searchPageSize = 20
    var hasMoreSearch = true
    var isSearching = false
    private var hasMoreSearchAnime = true
    private var hasMoreSearchManga = true
    private var searchCursorAnimeRank: Double? = nil
    private var searchCursorAnimePopularity: Int? = nil
    private var searchCursorAnimeId: Int? = nil
    private var searchCursorMangaRank: Double? = nil
    private var searchCursorMangaPopularity: Int? = nil
    private var searchCursorMangaId: Int? = nil

    struct SearchFilters {
        var trending: Bool = false
        var newSeason: Bool = false
        var classics: Bool = false
        var hiddenGems: Bool = false
        // New: airing-only and precise season window
        var airingOnly: Bool = false
        var seasonName: String? = nil  // "WINTER", "SPRING", "SUMMER", "FALL"
        var seasonYear: Int? = nil
    }
    private var currentSearchFilters: SearchFilters? = nil

    enum BrowseSort: String, CaseIterable {
        case popular = "POPULAR"
        case trending = "TRENDING"
        case topRated = "TOP RATED"
        case newlyAdded = "NEW"

        var orderColumn: String {
            switch self {
            case .popular: return "popularity"
            case .trending: return "trending"
            case .topRated: return "average_score"
            case .newlyAdded: return "created_at"
            }
        }

        var rpcKey: String {
            switch self {
            case .popular: return "popular"
            case .trending: return "trending"
            case .topRated: return "topRated"
            case .newlyAdded: return "newlyAdded"
            }
        }
    }

    // Pagination state
    private var currentAnimePage = 0
    private var currentMangaPage = 0
    private var pageSize = 50  // Increased for better performance with large datasets
    var hasMoreAnime = true
    var hasMoreManga = true
    
    init() {
        // Initialize Supabase client from configuration; fallback to embedded defaults to avoid breaking the app
        let fallbackURL = URL(string: "https://bkdifromsqxkndnllmdj.supabase.co")!
        // NOTE: keeping this hardcoded per current preference; move to Info.plist/env before shipping.
        let fallbackKey = "[REDACTED_JWT]"
        let url = AppConfig.supabaseURL ?? fallbackURL
        let key = AppConfig.supabaseAnonKey ?? fallbackKey

        if AppConfig.supabaseURL == nil || AppConfig.supabaseAnonKey == nil {
            print("⚠️ Using fallback Supabase config from code. Add SUPABASE_URL and SUPABASE_ANON_KEY to Info.plist or env.")
        }

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key
        )
        print("🔥 Supabase client initialized: \(url.host ?? url.absoluteString)")

        Task { await restoreSession() }
    }
    
    // MARK: - Authentication
    func restoreSession() async {
        defer { isAuthBootstrapping = false }

        do {
            let session = try await client.auth.session
            isAuthenticated = true
            authErrorMessage = nil
            currentUserEmail = session.user.email
            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            isAuthenticated = false
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        authErrorMessage = nil
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            let session = try await client.auth.session
            isAuthenticated = true
            currentUserEmail = session.user.email
            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            authErrorMessage = error.localizedDescription
            isAuthenticated = false
            throw error
        }
    }

    func signUpWithEmail(email: String, password: String) async throws {
        authErrorMessage = nil
        do {
            _ = try await client.auth.signUp(email: email, password: password)
            // Depending on Supabase settings, user may need email confirmation. We still attempt bootstrap if a session exists.
            if let session = (try? await client.auth.session) {
                isAuthenticated = true
                currentUserEmail = session.user.email
                await ensureProfileRow()
                await bootstrapAfterAuth()
            } else {
                isAuthenticated = false
            }
        } catch {
            authErrorMessage = error.localizedDescription
            throw error
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            print("❌ signOut error: \(error)")
        }
        await stopRealtimeSubscriptions()
        isAuthenticated = false
        currentUserEmail = nil
        authErrorMessage = nil
        stopCountdownUpdates()
        resetUserState()
    }

    private func resetUserState() {
        userLists = []
        collectionAnimeItems = []
        collectionMangaItems = []
        collectionFeedItems = []
        upcomingAirings = []
        countdownByAnimeId = [:]
    }

    private func ensureProfileRow() async {
        guard let user = try? await client.auth.session.user else { return }
        struct ProfilePayload: Encodable {
            let id: UUID
            let adult_opt_in: Bool
        }
        do {
            try await client
                .from("profiles")
                .upsert(ProfilePayload(id: user.id, adult_opt_in: false), onConflict: "id")
                .execute()
        } catch {
            print("⚠️ ensureProfileRow failed: \(error)")
        }
    }

    private func bootstrapAfterAuth() async {
        // Load user state early so collection indicators + progress are correct across the UI.
        await fetchUserLists()
        await fetchCollectionItems()
        await fetchCollectionFeed()
        await fetchUpcomingForUser(days: 7)
        startCountdownUpdates()
        subscribeToUpdates()
    }

    private func currentUserIdString() async -> String? {
        (try? await client.auth.session.user.id.uuidString)
    }
    
    // MARK: - Fetch Anime (API-backed pagination)
    func setPageSize(_ size: Int) {
        pageSize = max(1, size)
    }

    func resetAnimePaging() {
        currentAnimePage = 0
        hasMoreAnime = true
        animeItems = []
    }

    func fetchNextAnimePage() async {
        guard hasMoreAnime, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let offset = currentAnimePage * pageSize
            let response: [Anime] = try await client
                .from("anime")
                .select()
                .order("popularity", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value

            animeItems.append(contentsOf: response)
            hasMoreAnime = response.count == pageSize
            if hasMoreAnime { currentAnimePage += 1 }
            print("✅ Fetched page \(currentAnimePage) (\(response.count) items), total: \(animeItems.count)")
        } catch {
            errorMessage = "Failed to fetch anime: \(error.localizedDescription)"
            print("❌ Supabase error: \(error)")
        }

        isLoading = false
    }

    func prefetchAnime(total: Int) async {
        resetAnimePaging()
        let pages = Int(ceil(Double(max(0, total)) / Double(pageSize)))
        for _ in 0..<pages {
            await fetchNextAnimePage()
            if !hasMoreAnime { break }
        }
    }

    // Backwards-compat shim (deprecated)
    func fetchAnime(limit: Int = 20, reset: Bool = false) async {
        if reset {
            resetAnimePaging()
        }
        // Use pageSize for pagination regardless of provided limit
        await fetchNextAnimePage()
    }
    
    // MARK: - Fetch Manga (API-backed pagination)
    func resetMangaPaging() {
        currentMangaPage = 0
        hasMoreManga = true
        mangaItems = []
    }

    func fetchNextMangaPage() async {
        guard hasMoreManga, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let offset = currentMangaPage * pageSize
            let response: [Manga] = try await client
                .from("manga")
                .select()
                .order("popularity", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value

            mangaItems.append(contentsOf: response)
            hasMoreManga = response.count == pageSize
            if hasMoreManga { currentMangaPage += 1 }
            print("✅ Fetched manga page \(currentMangaPage) (\(response.count) items), total: \(mangaItems.count)")
        } catch {
            errorMessage = "Failed to fetch manga: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }

        isLoading = false
    }

    func prefetchManga(total: Int) async {
        resetMangaPaging()
        let pages = Int(ceil(Double(max(0, total)) / Double(pageSize)))
        for _ in 0..<pages {
            await fetchNextMangaPage()
            if !hasMoreManga { break }
        }
    }
    
    // MARK: - Search (using your full-text search index)
    func searchContent(query: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Search anime using your full-text search index
            let animeResponse: [Anime] = try await client
                .from("anime")
                .select()
                .textSearch("title_english,title_romaji,description_normalized", query: query)
                .execute()
                .value
            
            // Search manga
            let mangaResponse: [Manga] = try await client
                .from("manga")
                .select()
                .textSearch("title_english,title_romaji,description_normalized", query: query)
                .execute()
                .value
            
            animeItems = animeResponse
            mangaItems = mangaResponse
            print("✅ Found \(animeResponse.count) anime, \(mangaResponse.count) manga")
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("❌ Search error: \(error)")
        }
        
        isLoading = false
    }

    // MARK: - Server-side paged text search
    func setSearchPageSize(_ size: Int) { searchPageSize = max(1, size) }

    func resetSearch(query: String, isManga: Bool) {
        currentSearchQuery = query
        searchMode = isManga ? .manga : .anime
        hasMoreSearch = true
        hasMoreSearchAnime = true
        hasMoreSearchManga = true
        searchAnimeItems = []
        searchMangaItems = []
        searchCursorAnimeRank = nil
        searchCursorAnimePopularity = nil
        searchCursorAnimeId = nil
        searchCursorMangaRank = nil
        searchCursorMangaPopularity = nil
        searchCursorMangaId = nil
    }

    func setSearchFilters(_ filters: SearchFilters?) {
        currentSearchFilters = filters
    }

    private func newSeasonThresholdYear() -> Int {
        // "New season" is meant to feel current; keep it dynamic so the UI stays fresh year over year.
        max(1900, Calendar.current.component(.year, from: Date()) - 1)
    }

    func fetchNextSearchPage() async {
        if searchMode == .combined {
            await fetchNextCombinedSearchPage()
            return
        }

        let trimmedQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow "filters-only" searches (no text) for category browsing; but don't fetch anything if both are empty.
        if trimmedQuery.isEmpty && currentSearchFilters == nil { return }
        // Avoid hammering the DB for 1-character incremental typing.
        if trimmedQuery.count < 2 && currentSearchFilters == nil { return }
        guard hasMoreSearch, !isSearching else { return }
        isSearching = true
        defer { isSearching = false }

        do {
            if searchMode == .manga {
                let page = try await fetchSearchMangaPage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: searchCursorMangaRank,
                    cursorPopularity: searchCursorMangaPopularity,
                    cursorId: searchCursorMangaId,
                    limit: searchPageSize
                )
                searchMangaItems.append(contentsOf: page)
                hasMoreSearch = page.count == searchPageSize
                if let last = page.last {
                    searchCursorMangaRank = last.rank ?? 0
                    searchCursorMangaPopularity = last.popularity ?? 0
                    searchCursorMangaId = last.id
                }
            } else {
                let page = try await fetchSearchAnimePage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: searchCursorAnimeRank,
                    cursorPopularity: searchCursorAnimePopularity,
                    cursorId: searchCursorAnimeId,
                    limit: searchPageSize
                )
                searchAnimeItems.append(contentsOf: page)
                hasMoreSearch = page.count == searchPageSize
                if let last = page.last {
                    searchCursorAnimeRank = last.rank ?? 0
                    searchCursorAnimePopularity = last.popularity ?? 0
                    searchCursorAnimeId = last.id
                }
            }
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            hasMoreSearch = false
            print("❌ Search page error: \(error)")
        }
    }

    func resetCombinedSearch(query: String) {
        currentSearchQuery = query
        searchMode = .combined
        hasMoreSearchAnime = true
        hasMoreSearchManga = true
        hasMoreSearch = true
        searchAnimeItems = []
        searchMangaItems = []
        searchCursorAnimeRank = nil
        searchCursorAnimePopularity = nil
        searchCursorAnimeId = nil
        searchCursorMangaRank = nil
        searchCursorMangaPopularity = nil
        searchCursorMangaId = nil
    }

    func fetchNextCombinedSearchPage() async {
        let trimmedQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty && currentSearchFilters == nil { return }
        if trimmedQuery.count < 2 && currentSearchFilters == nil { return }
        guard hasMoreSearch, !isSearching else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            let filters = currentSearchFilters

            if hasMoreSearchAnime {
                let page = try await fetchSearchAnimePage(
                    query: trimmedQuery,
                    filters: filters,
                    cursorRank: searchCursorAnimeRank,
                    cursorPopularity: searchCursorAnimePopularity,
                    cursorId: searchCursorAnimeId,
                    limit: searchPageSize
                )
                searchAnimeItems.append(contentsOf: page)
                hasMoreSearchAnime = page.count == searchPageSize
                if let last = page.last {
                    searchCursorAnimeRank = last.rank ?? 0
                    searchCursorAnimePopularity = last.popularity ?? 0
                    searchCursorAnimeId = last.id
                }
            }

            if hasMoreSearchManga {
                let page = try await fetchSearchMangaPage(
                    query: trimmedQuery,
                    filters: filters,
                    cursorRank: searchCursorMangaRank,
                    cursorPopularity: searchCursorMangaPopularity,
                    cursorId: searchCursorMangaId,
                    limit: searchPageSize
                )
                searchMangaItems.append(contentsOf: page)
                hasMoreSearchManga = page.count == searchPageSize
                if let last = page.last {
                    searchCursorMangaRank = last.rank ?? 0
                    searchCursorMangaPopularity = last.popularity ?? 0
                    searchCursorMangaId = last.id
                }
            }

            hasMoreSearch = hasMoreSearchAnime || hasMoreSearchManga
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            hasMoreSearch = false
            hasMoreSearchAnime = false
            hasMoreSearchManga = false
            print("❌ Combined search error: \(error)")
        }
    }

    // MARK: - Search refresh (keeps old results on transient failures)
    func refreshSearch() async {
        let trimmedQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty && currentSearchFilters == nil { return }
        if trimmedQuery.count < 2 && currentSearchFilters == nil { return }
        guard !isSearching else { return }

        let oldAnime = searchAnimeItems
        let oldManga = searchMangaItems
        let oldHasMore = hasMoreSearch
        let oldHasMoreAnime = hasMoreSearchAnime
        let oldHasMoreManga = hasMoreSearchManga

        isSearching = true
        defer { isSearching = false }

        do {
            switch searchMode {
            case .anime:
                searchCursorAnimeRank = nil
                searchCursorAnimePopularity = nil
                searchCursorAnimeId = nil
                let page = try await fetchSearchAnimePage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: searchPageSize
                )
                searchAnimeItems = page
                hasMoreSearch = page.count == searchPageSize
                if let last = page.last {
                    searchCursorAnimeRank = last.rank ?? 0
                    searchCursorAnimePopularity = last.popularity ?? 0
                    searchCursorAnimeId = last.id
                }
            case .manga:
                searchCursorMangaRank = nil
                searchCursorMangaPopularity = nil
                searchCursorMangaId = nil
                let page = try await fetchSearchMangaPage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: searchPageSize
                )
                searchMangaItems = page
                hasMoreSearch = page.count == searchPageSize
                if let last = page.last {
                    searchCursorMangaRank = last.rank ?? 0
                    searchCursorMangaPopularity = last.popularity ?? 0
                    searchCursorMangaId = last.id
                }
            case .combined:
                // Reset both cursors.
                searchCursorAnimeRank = nil
                searchCursorAnimePopularity = nil
                searchCursorAnimeId = nil
                searchCursorMangaRank = nil
                searchCursorMangaPopularity = nil
                searchCursorMangaId = nil

                let animePage = try await fetchSearchAnimePage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: searchPageSize
                )
                let mangaPage = try await fetchSearchMangaPage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: searchPageSize
                )
                searchAnimeItems = animePage
                searchMangaItems = mangaPage
                hasMoreSearchAnime = animePage.count == searchPageSize
                hasMoreSearchManga = mangaPage.count == searchPageSize
                hasMoreSearch = hasMoreSearchAnime || hasMoreSearchManga

                if let last = animePage.last {
                    searchCursorAnimeRank = last.rank ?? 0
                    searchCursorAnimePopularity = last.popularity ?? 0
                    searchCursorAnimeId = last.id
                }
                if let last = mangaPage.last {
                    searchCursorMangaRank = last.rank ?? 0
                    searchCursorMangaPopularity = last.popularity ?? 0
                    searchCursorMangaId = last.id
                }
            }
        } catch {
            // Restore old state and surface a message.
            searchAnimeItems = oldAnime
            searchMangaItems = oldManga
            hasMoreSearch = oldHasMore
            hasMoreSearchAnime = oldHasMoreAnime
            hasMoreSearchManga = oldHasMoreManga
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("❌ search refresh: \(error)")
        }
    }

    private func fetchSearchAnimePage(
        query: String,
        filters: SearchFilters?,
        cursorRank: Double?,
        cursorPopularity: Int?,
        cursorId: Int?,
        limit: Int
    ) async throws -> [AnimeCard] {
        let perf = KuroPerf.begin("rpc.search_anime_page")
        do {
            let params = RPCSearchAnimePageParams(
                p_query: query,
                p_limit: max(1, min(50, limit)),
                p_cursor_rank: cursorRank,
                p_cursor_popularity: cursorPopularity,
                p_cursor_id: cursorId,
                p_trending: filters?.trending ?? false,
                p_new_season: filters?.newSeason ?? false,
                p_classics: filters?.classics ?? false,
                p_hidden_gems: filters?.hiddenGems ?? false,
                p_airing_only: filters?.airingOnly ?? false,
                p_season: filters?.seasonName,
                p_season_year: filters?.seasonYear
            )
            let page: [AnimeCard] = try await client
                .rpc("search_anime_page", params: params)
                .execute()
                .value
            KuroPerf.end(perf, message: "ok \(page.count)")
            return page
        } catch {
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    private func fetchSearchMangaPage(
        query: String,
        filters: SearchFilters?,
        cursorRank: Double?,
        cursorPopularity: Int?,
        cursorId: Int?,
        limit: Int
    ) async throws -> [MangaCard] {
        let perf = KuroPerf.begin("rpc.search_manga_page")
        do {
            let params = RPCSearchMangaPageParams(
                p_query: query,
                p_limit: max(1, min(50, limit)),
                p_cursor_rank: cursorRank,
                p_cursor_popularity: cursorPopularity,
                p_cursor_id: cursorId,
                p_trending: filters?.trending ?? false,
                p_new_season: filters?.newSeason ?? false,
                p_classics: filters?.classics ?? false,
                p_hidden_gems: filters?.hiddenGems ?? false
            )
            let page: [MangaCard] = try await client
                .rpc("search_manga_page", params: params)
                .execute()
                .value
            KuroPerf.end(perf, message: "ok \(page.count)")
            return page
        } catch {
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    // MARK: - Discover bundle (single call)
    func fetchDiscoverBundle(limit: Int = 30, hours: Int = 24, force: Bool = false) async -> DiscoverBundle? {
        let key = "discover_bundle|\(max(1, min(60, limit)))|\(max(1, min(168, hours)))"
        let now = Date()
        if !force, let cached = discoverBundleCache[key], now.timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }
        if let task = discoverBundleInFlight[key] {
            return await task.value
        }

        let task = Task<DiscoverBundle?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            let perf = KuroPerf.begin("rpc.discover_bundle")
            do {
                let params = RPCDiscoverBundleParams(
                    p_limit: max(1, min(60, limit)),
                    p_hours: max(1, min(168, hours))
                )
                let bundle: DiscoverBundle = try await self.client
                    .rpc("discover_bundle", params: params)
                    .execute()
                    .value
                KuroPerf.end(perf, message: "ok")
                self.discoverBundleCache[key] = TimedCache(value: bundle, storedAt: now)
                self.trimCache(&self.discoverBundleCache, maxEntries: 6)
                return bundle
            } catch {
                print("❌ discover_bundle rpc: \(error)")
                KuroPerf.end(perf, message: "error")
                return nil
            }
        }

        discoverBundleInFlight[key] = task
        let value = await task.value
        discoverBundleInFlight[key] = nil
        return value
    }

    // MARK: - Detail fetch by id (full models)
    func fetchAnimeById(_ animeId: Int) async throws -> Anime? {
        if let cached = animeDetailCache[animeId] { return cached }
        if let disk: Anime = await KuroDiskDetailCache.read(kind: .anime, id: animeId, as: Anime.self) {
            animeDetailCache[animeId] = disk
            return disk
        }
        let perf = KuroPerf.begin("db.anime_by_id")
        do {
            let rows: [Anime] = try await client
                .from("anime")
                .select()
                .eq("id", value: animeId)
                .limit(1)
                .execute()
                .value
            let item = rows.first
            if let item {
                animeDetailCache[animeId] = item
                // Keep cache bounded.
                if animeDetailCache.count > 200, let k = animeDetailCache.keys.first {
                    animeDetailCache.removeValue(forKey: k)
                }
                Task { await KuroDiskDetailCache.write(kind: .anime, id: animeId, value: item) }
            }
            KuroPerf.end(perf, message: item == nil ? "missing" : "ok")
            return item
        } catch {
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    func fetchMangaById(_ mangaId: Int) async throws -> Manga? {
        if let cached = mangaDetailCache[mangaId] { return cached }
        if let disk: Manga = await KuroDiskDetailCache.read(kind: .manga, id: mangaId, as: Manga.self) {
            mangaDetailCache[mangaId] = disk
            return disk
        }
        let perf = KuroPerf.begin("db.manga_by_id")
        do {
            let rows: [Manga] = try await client
                .from("manga")
                .select()
                .eq("id", value: mangaId)
                .limit(1)
                .execute()
                .value
            let item = rows.first
            if let item {
                mangaDetailCache[mangaId] = item
                if mangaDetailCache.count > 200, let k = mangaDetailCache.keys.first {
                    mangaDetailCache.removeValue(forKey: k)
                }
                Task { await KuroDiskDetailCache.write(kind: .manga, id: mangaId, value: item) }
            }
            KuroPerf.end(perf, message: item == nil ? "missing" : "ok")
            return item
        } catch {
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    // MARK: - Server-driven Discover sections (Anime)
    func fetchTrendingAnime(limit: Int = 20, onlyAiring: Bool = false, genre: String? = nil) async -> [Anime] {
        do {
            // Uses materialized view for fast, stable results (refreshed nightly by cron).
            var q = client.from("mv_anime_trending").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let statusQuery = onlyAiring ? q.eq("status", value: "RELEASING") : q
            let orderedQuery = statusQuery.order("trending", ascending: false)
            let rows: [Anime] = try await orderedQuery.range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ trending fetch: \(error)"); return [] }
    }

    func fetchCurrentSeasonAnime(limit: Int = 20, year: Int? = nil, onlyAiring: Bool = true, genre: String? = nil) async -> [Anime] {
        do {
            let yr = year ?? Calendar.current.component(.year, from: Date())
            var q = client.from("anime").select().eq("season_year", value: yr)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let statusQuery = onlyAiring ? q.eq("status", value: "RELEASING") : q
            let orderedQuery = statusQuery.order("popularity", ascending: false)
            let rows: [Anime] = try await orderedQuery.range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ current season fetch: \(error)"); return [] }
    }

    func fetchSeasonAnime(season: String, year: Int, limit: Int = 20, onlyAiring: Bool = true, genre: String? = nil) async -> [Anime] {
        do {
            var q = client.from("anime").select().eq("season", value: season).eq("season_year", value: year)
            if onlyAiring { q = q.eq("status", value: "RELEASING") }
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("popularity", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ season fetch: \(error)"); return [] }
    }

    func fetchNewlyAddedAnime(limit: Int = 20, genre: String? = nil) async -> [Anime] {
        do {
            // Uses materialized view for fast, stable results (refreshed nightly by cron).
            var q = client.from("mv_anime_newly_added").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("created_at", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ newly added fetch: \(error)"); return [] }
    }

    func fetchTopRatedAnime(limit: Int = 20, minScore: Int = 80, genre: String? = nil) async -> [Anime] {
        do {
            // Uses materialized view for fast, stable results (refreshed nightly by cron).
            // Still supports minScore by filtering the view.
            var q = client.from("mv_anime_top_rated").select().gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("average_score", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ top rated fetch: \(error)"); return [] }
    }

    // MARK: - Server-driven Discover sections (Manga)
    func fetchTrendingManga(limit: Int = 20, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_trending").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("trending", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch { print("❌ manga trending fetch: \(error)"); return [] }
    }

    func fetchNewlyAddedManga(limit: Int = 20, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_newly_added").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("created_at", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch { print("❌ manga newly added fetch: \(error)"); return [] }
    }

    func fetchTopRatedManga(limit: Int = 20, minScore: Int = 80, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_top_rated").select().gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("average_score", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch { print("❌ manga top rated fetch: \(error)"); return [] }
    }

    // MARK: - Premium discovery rails (Essentials / Classics / New-to-you)
    func fetchEssentialsAnime(limit: Int = 20, minScore: Int = 85, genre: String? = nil) async -> [Anime] {
        do {
            var q = client.from("anime").select()
                .eq("is_adult", value: false)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q
                .order("favourites", ascending: false)
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ essentials anime fetch: \(error)"); return [] }
    }

    func fetchClassicsAnime(limit: Int = 20, yearBefore: Int = 2015, minScore: Int = 80, genre: String? = nil) async -> [Anime] {
        do {
            var q = client.from("anime").select()
                .eq("is_adult", value: false)
                .lt("season_year", value: yearBefore)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ classics anime fetch: \(error)"); return [] }
    }

    func fetchNewToYouAnime(limit: Int = 20, candidateLimit: Int = 250, minScore: Int = 80, genre: String? = nil) async -> [Anime] {
        let saved: Set<Int> = Set(userLists.filter { $0.mediaType.lowercased() == "anime" }.map(\.mediaId))
        do {
            var q = client.from("anime").select()
                .eq("is_adult", value: false)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let candidates: [Anime] = try await q
                .order("popularity", ascending: false)
                .order("average_score", ascending: false)
                .range(from: 0, to: max(0, candidateLimit - 1))
                .execute()
                .value

            let filtered = sanitizeAnimeForDiscovery(candidates)
                .filter { !saved.contains($0.id) }

            // Deterministic daily reshuffle to avoid showing the same top items forever.
            let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
            let shuffled = filtered.sorted { lhs, rhs in
                let a = (lhs.id &* 1103515245 &+ day) & 0x7fffffff
                let b = (rhs.id &* 1103515245 &+ day) & 0x7fffffff
                return a < b
            }
            return Array(shuffled.prefix(limit))
        } catch { print("❌ new-to-you anime fetch: \(error)"); return [] }
    }

    func fetchEssentialsManga(limit: Int = 20, minScore: Int = 85, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("manga").select()
                .eq("is_adult", value: false)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q
                .order("favourites", ascending: false)
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeMangaForDiscovery(rows)
        } catch { print("❌ essentials manga fetch: \(error)"); return [] }
    }

    func fetchClassicsManga(limit: Int = 20, yearBefore: Int = 2015, minScore: Int = 80, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("manga").select()
                .eq("is_adult", value: false)
                .lt("start_date_year", value: yearBefore)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeMangaForDiscovery(rows)
        } catch { print("❌ classics manga fetch: \(error)"); return [] }
    }

    func fetchNewToYouManga(limit: Int = 20, candidateLimit: Int = 300, minScore: Int = 80, genre: String? = nil) async -> [Manga] {
        let saved: Set<Int> = Set(userLists.filter { $0.mediaType.lowercased() == "manga" }.map(\.mediaId))
        do {
            var q = client.from("manga").select()
                .eq("is_adult", value: false)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let candidates: [Manga] = try await q
                .order("popularity", ascending: false)
                .order("average_score", ascending: false)
                .range(from: 0, to: max(0, candidateLimit - 1))
                .execute()
                .value

            let filtered = sanitizeMangaForDiscovery(candidates)
                .filter { !saved.contains($0.id) }

            let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
            let shuffled = filtered.sorted { lhs, rhs in
                let a = (lhs.id &* 1103515245 &+ day) & 0x7fffffff
                let b = (rhs.id &* 1103515245 &+ day) & 0x7fffffff
                return a < b
            }
            return Array(shuffled.prefix(limit))
        } catch { print("❌ new-to-you manga fetch: \(error)"); return [] }
    }

    // Imminent airing within next N hours
    func fetchAiringSoonAnime(hours: Int = 24, limit: Int = 20, genre: String? = nil) async -> [Anime] {
        do {
            let now = Date()
            let end = now.addingTimeInterval(TimeInterval(hours * 3600))
            let iso = ISO8601DateFormatter()
            let nowStr = iso.string(from: now)
            let endStr = iso.string(from: end)
            var q = client.from("anime").select()
                .eq("is_adult", value: false)
                .gt("next_airing_at", value: nowStr)
                .lte("next_airing_at", value: endStr)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("next_airing_at", ascending: true)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ airing soon fetch: \(error)"); return [] }
    }

    // MARK: - Sub-genre (tag) insights for a genre
    private struct _TagNode: Decodable {
        let id: Int
        let name: String
        let category: String?
        let isAdult: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, category
            case isAdult = "is_adult"
        }
    }

    private struct _TagEdge: Decodable {
        let rank: Int?
        let tagId: Int?
        let tags: _TagNode?

        enum CodingKeys: String, CodingKey {
            case rank
            case tagId = "tag_id"
            case tags
        }
    }

    private struct _AnimeTagSampleRow: Decodable {
        let id: Int
        let animeTags: [_TagEdge]

        enum CodingKeys: String, CodingKey {
            case id
            case animeTags = "anime_tags"
        }
    }

    /// Returns top non-adult tags for a specific anime (used for "sub-genres" on detail pages).
    func fetchTopTagsForAnime(animeId: Int, limit: Int = 12) async -> [TagFacet] {
        do {
            let rows: [_AnimeTagSampleRow] = try await client
                .from("anime")
                .select("id,anime_tags(rank,tags(id,name,category,is_adult))")
                .eq("id", value: animeId)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return [] }
            let tags = row.animeTags
                .compactMap { edge -> (id: Int, name: String, category: String?, isAdult: Bool, rank: Int)? in
                    guard let node = edge.tags else { return nil }
                    let r = edge.rank ?? 0
                    return (node.id, node.name, node.category, node.isAdult, r)
                }
                .filter { !$0.isAdult }
                .sorted { $0.rank > $1.rank }
                .prefix(limit)
                .map { TagFacet(id: $0.id, name: $0.name, category: $0.category, count: 0) }
            return Array(tags)
        } catch {
            print("❌ anime tag fetch: \(error)")
            return []
        }
    }

    /// Returns top non-adult tags for a specific manga (used for "sub-genres" on detail pages).
    func fetchTopTagsForManga(mangaId: Int, limit: Int = 12) async -> [TagFacet] {
        do {
            let rows: [_MangaTagSampleRow] = try await client
                .from("manga")
                .select("id,manga_tags(rank,tags(id,name,category,is_adult))")
                .eq("id", value: mangaId)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return [] }
            let tags = row.mangaTags
                .compactMap { edge -> (id: Int, name: String, category: String?, isAdult: Bool, rank: Int)? in
                    guard let node = edge.tags else { return nil }
                    let r = edge.rank ?? 0
                    return (node.id, node.name, node.category, node.isAdult, r)
                }
                .filter { !$0.isAdult }
                .sorted { $0.rank > $1.rank }
                .prefix(limit)
                .map { TagFacet(id: $0.id, name: $0.name, category: $0.category, count: 0) }
            return Array(tags)
        } catch {
            print("❌ manga tag fetch: \(error)")
            return []
        }
    }

    /// Minimal "More like this" fetcher for detail pages (Swiss minimal: deterministic, no LLM).
    /// Primary path uses the DB similarity RPC (tag overlap + editorial boosts/penalties).
    /// Falls back to a lightweight genre anchor if the RPC isn't available.
    func fetchSimilarAnime(seed: Anime, limit: Int = 14) async -> [Anime] {
        let rpc = await fetchSimilarIdsViaRPC(mediaType: "ANIME", seedIds: [seed.id], limit: limit, allowGimmicks: false)
        if !rpc.isEmpty, let items = await fetchAnimeByIdsPreservingOrder(rpc.map(\.mediaId)) {
            return sanitizeAnimeForDiscovery(items)
        }
        return await fetchSimilarAnimeFallbackByGenre(seed: seed, limit: limit)
    }

    func fetchSimilarManga(seed: Manga, limit: Int = 14) async -> [Manga] {
        let rpc = await fetchSimilarIdsViaRPC(mediaType: "MANGA", seedIds: [seed.id], limit: limit, allowGimmicks: false)
        if !rpc.isEmpty, let items = await fetchMangaByIdsPreservingOrder(rpc.map(\.mediaId)) {
            return sanitizeMangaForDiscovery(items)
        }
        return await fetchSimilarMangaFallbackByGenre(seed: seed, limit: limit)
    }

    private struct _RecommendSimilarRow: Decodable {
        let mediaId: Int
        let overlapCount: Int
        let score: Double

        enum CodingKeys: String, CodingKey {
            case mediaId = "media_id"
            case overlapCount = "overlap_count"
            case score
        }
    }

    private func fetchSimilarIdsViaRPC(
        mediaType: String,
        seedIds: [Int],
        limit: Int,
        allowGimmicks: Bool
    ) async -> [_RecommendSimilarRow] {
        // This RPC is a production-grade deterministic similarity engine (tag overlap + editorial weights).
        // It may be missing in some DBs (or require auth, depending on migration state), so treat failure as "no results".
        let perf = KuroPerf.begin("rpc.recommend_ids_similar_to_seeds")
        do {
            let params = RPCRecommendSimilarParams(
                p_media_type: mediaType,
                p_seed_ids: seedIds,
                p_limit: max(1, min(50, limit)),
                p_allow_gimmicks: allowGimmicks
            )
            let rows: [_RecommendSimilarRow] = try await client
                .rpc("recommend_ids_similar_to_seeds", params: params)
                .execute()
                .value
            KuroPerf.end(perf, message: "ok \(rows.count)")
            return rows
        } catch {
            KuroPerf.end(perf, message: "error")
            return []
        }
    }

    private func fetchAnimeByIdsPreservingOrder(_ ids: [Int]) async -> [Anime]? {
        if ids.isEmpty { return [] }
        // Avoid hammering the API: fetch via cache first, then fill in missing ones concurrently.
        // Keep ordering identical to the RPC output.
        var resultsById: [Int: Anime] = [:]
        resultsById.reserveCapacity(ids.count)

        for id in ids {
            if let cached = animeDetailCache[id] {
                resultsById[id] = cached
            }
        }

        let missing = ids.filter { resultsById[$0] == nil }
        if !missing.isEmpty {
            await withTaskGroup(of: Anime?.self) { group in
                for id in missing {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return try? await self.fetchAnimeById(id)
                    }
                }
                for await item in group {
                    if let item { resultsById[item.id] = item }
                }
            }
        }

        let ordered = ids.compactMap { resultsById[$0] }
        return ordered.isEmpty ? nil : ordered
    }

    private func fetchMangaByIdsPreservingOrder(_ ids: [Int]) async -> [Manga]? {
        if ids.isEmpty { return [] }
        var resultsById: [Int: Manga] = [:]
        resultsById.reserveCapacity(ids.count)

        for id in ids {
            if let cached = mangaDetailCache[id] {
                resultsById[id] = cached
            }
        }

        let missing = ids.filter { resultsById[$0] == nil }
        if !missing.isEmpty {
            await withTaskGroup(of: Manga?.self) { group in
                for id in missing {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return try? await self.fetchMangaById(id)
                    }
                }
                for await item in group {
                    if let item { resultsById[item.id] = item }
                }
            }
        }

        let ordered = ids.compactMap { resultsById[$0] }
        return ordered.isEmpty ? nil : ordered
    }

    private func fetchSimilarAnimeFallbackByGenre(seed: Anime, limit: Int) async -> [Anime] {
        guard let primaryGenre = seed.genreList?.first, !primaryGenre.isEmpty else { return [] }
        do {
            let rows: [Anime] = try await client
                .from("anime")
                .select()
                .eq("is_adult", value: false)
                .contains("genres", value: [primaryGenre])
                .neq("id", value: seed.id)
                .order("favourites", ascending: false)
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeAnimeForDiscovery(rows)
        } catch {
            return []
        }
    }

    private func fetchSimilarMangaFallbackByGenre(seed: Manga, limit: Int) async -> [Manga] {
        guard let primaryGenre = seed.genreList?.first, !primaryGenre.isEmpty else { return [] }
        do {
            let rows: [Manga] = try await client
                .from("manga")
                .select()
                .eq("is_adult", value: false)
                .contains("genres", value: [primaryGenre])
                .neq("id", value: seed.id)
                .order("favourites", ascending: false)
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeMangaForDiscovery(rows)
        } catch {
            return []
        }
    }

    private struct _MangaTagSampleRow: Decodable {
        let id: Int
        let mangaTags: [_TagEdge]

        enum CodingKeys: String, CodingKey {
            case id
            case mangaTags = "manga_tags"
        }
    }

    private func isBlockedTag(_ t: _TagNode) -> Bool {
        if t.isAdult { return true }
        // Keep it simple: AniList already flags adult tags; category filters can be layered later.
        return false
    }

    func fetchTopTagsForAnimeGenre(genre: String, sampleLimit: Int = 180, limit: Int = 18) async -> (facets: [TagFacet], mediaToTagIds: [Int: Set<Int>]) {
        do {
            let rows: [_AnimeTagSampleRow] = try await client
                .from("anime")
                .select("id, anime_tags(rank, tag_id, tags(id, name, category, is_adult))")
                .eq("is_adult", value: false)
                .contains("genres", value: [genre])
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, sampleLimit - 1))
                .execute()
                .value

            var mediaToTagIds: [Int: Set<Int>] = [:]
            var tally: [Int: (name: String, category: String?, count: Int, rankSum: Int)] = [:]

            for row in rows {
                var tagIds: Set<Int> = []
                for edge in row.animeTags {
                    guard let t = edge.tags, !isBlockedTag(t) else { continue }
                    tagIds.insert(t.id)
                    var cur = tally[t.id] ?? (t.name, t.category, 0, 0)
                    cur.count += 1
                    cur.rankSum += (edge.rank ?? 0)
                    tally[t.id] = cur
                }
                mediaToTagIds[row.id] = tagIds
            }

            let sorted = tally
                .map { (id, v) in (id: id, name: v.name, category: v.category, count: v.count, rankSum: v.rankSum) }
                .sorted { a, b in
                    if a.count != b.count { return a.count > b.count }
                    return a.rankSum > b.rankSum
                }
                .prefix(max(0, limit))
                .map { TagFacet(id: $0.id, name: $0.name, category: $0.category, count: $0.count) }

            return (Array(sorted), mediaToTagIds)
        } catch {
            print("❌ anime tag facets fetch: \(error)")
            return ([], [:])
        }
    }

    func fetchTopTagsForMangaGenre(genre: String, sampleLimit: Int = 180, limit: Int = 18) async -> (facets: [TagFacet], mediaToTagIds: [Int: Set<Int>]) {
        do {
            let rows: [_MangaTagSampleRow] = try await client
                .from("manga")
                .select("id, manga_tags(rank, tag_id, tags(id, name, category, is_adult))")
                .eq("is_adult", value: false)
                .contains("genres", value: [genre])
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, sampleLimit - 1))
                .execute()
                .value

            var mediaToTagIds: [Int: Set<Int>] = [:]
            var tally: [Int: (name: String, category: String?, count: Int, rankSum: Int)] = [:]

            for row in rows {
                var tagIds: Set<Int> = []
                for edge in row.mangaTags {
                    guard let t = edge.tags, !isBlockedTag(t) else { continue }
                    tagIds.insert(t.id)
                    var cur = tally[t.id] ?? (t.name, t.category, 0, 0)
                    cur.count += 1
                    cur.rankSum += (edge.rank ?? 0)
                    tally[t.id] = cur
                }
                mediaToTagIds[row.id] = tagIds
            }

            let sorted = tally
                .map { (id, v) in (id: id, name: v.name, category: v.category, count: v.count, rankSum: v.rankSum) }
                .sorted { a, b in
                    if a.count != b.count { return a.count > b.count }
                    return a.rankSum > b.rankSum
                }
                .prefix(max(0, limit))
                .map { TagFacet(id: $0.id, name: $0.name, category: $0.category, count: $0.count) }

            return (Array(sorted), mediaToTagIds)
        } catch {
            print("❌ manga tag facets fetch: \(error)")
            return ([], [:])
        }
    }
    
    // MARK: - User Lists (normalized tables)
    private func statusFromDB(_ listType: String) -> ListStatus {
        switch listType.uppercased() {
        case "READING": return .current
        case "WATCHING": return .current
        case "PLANNING": return .planning
        case "COMPLETED": return .completed
        case "DROPPED": return .dropped
        case "PAUSED": return .paused
        default: return .planning
        }
    }

    private func dbListType(for status: ListStatus, mediaType: String) -> String {
        let isManga = mediaType.lowercased() == "manga"
        switch status {
        case .current: return isManga ? "READING" : "WATCHING"
        case .planning: return "PLANNING"
        case .completed: return "COMPLETED"
        case .dropped: return "DROPPED"
        case .paused: return "PAUSED"
        case .repeating: return isManga ? "READING" : "WATCHING"
        }
    }

    // MARK: - Collection (server-driven)
    func fetchCollectionItems(status: ListStatus? = nil) async {
        currentCollectionStatusFilter = status
        collectionFetchGeneration += 1
        let gen = collectionFetchGeneration

        collectionFetchInFlight?.cancel()
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchCollectionItemsImpl(status: status, generation: gen)
        }
        collectionFetchInFlight = t
        collectionFetchInFlightGeneration = gen
        await t.value
        if collectionFetchInFlightGeneration == gen { collectionFetchInFlight = nil }
    }

    func fetchCollectionItems() async {
        await fetchCollectionItems(status: nil)
    }

    // MARK: - Collection feed (anime + manga interleaved)
    func fetchCollectionFeed(status: ListStatus? = nil) async {
        currentCollectionStatusFilter = status
        collectionFeedFetchGeneration += 1
        let gen = collectionFeedFetchGeneration

        collectionFeedFetchInFlight?.cancel()
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchCollectionFeedImpl(status: status, generation: gen)
        }
        collectionFeedFetchInFlight = t
        collectionFeedFetchInFlightGeneration = gen
        await t.value
        if collectionFeedFetchInFlightGeneration == gen { collectionFeedFetchInFlight = nil }
    }

    private struct CollectionPagingSnapshot: Sendable {
        let anime: [AnimeCard]
        let manga: [MangaCard]
        let feed: [Media]
        let animeHasMore: Bool
        let mangaHasMore: Bool
        let feedHasMore: Bool
        let animeCursorUpdatedAt: Date?
        let animeCursorRowId: Int?
        let mangaCursorUpdatedAt: Date?
        let mangaCursorRowId: Int?
        let feedCursorUpdatedAt: Date?
        let feedCursorSourceRank: Int?
        let feedCursorRowId: Int?
    }

    private func _fetchCollectionItemsImpl(status: ListStatus?, generation: Int) async {
        guard let userId = await currentUserIdString() else { return }
        _ = userId // user_id is derived via JWT in the RPCs.
        isCollectionLoading = true
        collectionErrorMessage = nil
        defer { isCollectionLoading = false }

        let snapshot = CollectionPagingSnapshot(
            anime: collectionAnimeItems,
            manga: collectionMangaItems,
            feed: collectionFeedItems,
            animeHasMore: hasMoreCollectionAnime,
            mangaHasMore: hasMoreCollectionManga,
            feedHasMore: hasMoreCollectionFeed,
            animeCursorUpdatedAt: collectionAnimeCursorUpdatedAt,
            animeCursorRowId: collectionAnimeCursorRowId,
            mangaCursorUpdatedAt: collectionMangaCursorUpdatedAt,
            mangaCursorRowId: collectionMangaCursorRowId,
            feedCursorUpdatedAt: collectionFeedCursorUpdatedAt,
            feedCursorSourceRank: collectionFeedCursorSourceRank,
            feedCursorRowId: collectionFeedCursorRowId
        )

        do {
            resetCollectionPaging()

            let listTypeAnime = status.map { dbListType(for: $0, mediaType: "anime") }
            let listTypeManga = status.map { dbListType(for: $0, mediaType: "manga") }

            _ = try await fetchNextCollectionAnimePage(
                limit: 80,
                listType: listTypeAnime,
                generation: generation
            )
            _ = try await fetchNextCollectionMangaPage(
                limit: 80,
                listType: listTypeManga,
                generation: generation
            )
        } catch {
            // Avoid blanking the UI on transient failures (e.g. pull-to-refresh).
            // Keep the previous content and surface an error message.
            collectionErrorMessage = "Failed to load collection: \(error.localizedDescription)"
            print("❌ collection fetch: \(error)")
            restoreCollectionSnapshot(snapshot)
        }
    }

    private func _fetchCollectionFeedImpl(status: ListStatus?, generation: Int) async {
        guard (await currentUserIdString()) != nil else { return }
        isCollectionLoading = true
        collectionErrorMessage = nil
        defer { isCollectionLoading = false }

        let snapshot = CollectionPagingSnapshot(
            anime: collectionAnimeItems,
            manga: collectionMangaItems,
            feed: collectionFeedItems,
            animeHasMore: hasMoreCollectionAnime,
            mangaHasMore: hasMoreCollectionManga,
            feedHasMore: hasMoreCollectionFeed,
            animeCursorUpdatedAt: collectionAnimeCursorUpdatedAt,
            animeCursorRowId: collectionAnimeCursorRowId,
            mangaCursorUpdatedAt: collectionMangaCursorUpdatedAt,
            mangaCursorRowId: collectionMangaCursorRowId,
            feedCursorUpdatedAt: collectionFeedCursorUpdatedAt,
            feedCursorSourceRank: collectionFeedCursorSourceRank,
            feedCursorRowId: collectionFeedCursorRowId
        )

        do {
            resetCollectionFeedPaging()

            let listTypeAnime = status.map { dbListType(for: $0, mediaType: "anime") }
            let listTypeManga = status.map { dbListType(for: $0, mediaType: "manga") }

            _ = try await fetchNextCollectionFeedPage(
                limit: 90,
                listTypeAnime: listTypeAnime,
                listTypeManga: listTypeManga,
                generation: generation
            )
        } catch {
            collectionErrorMessage = "Failed to load collection: \(error.localizedDescription)"
            print("❌ collection feed fetch: \(error)")
            restoreCollectionSnapshot(snapshot)
        }
    }

    private func restoreCollectionSnapshot(_ snapshot: CollectionPagingSnapshot) {
        collectionAnimeItems = snapshot.anime
        collectionMangaItems = snapshot.manga
        collectionFeedItems = snapshot.feed
        hasMoreCollectionAnime = snapshot.animeHasMore
        hasMoreCollectionManga = snapshot.mangaHasMore
        hasMoreCollectionFeed = snapshot.feedHasMore
        collectionAnimeCursorUpdatedAt = snapshot.animeCursorUpdatedAt
        collectionAnimeCursorRowId = snapshot.animeCursorRowId
        collectionMangaCursorUpdatedAt = snapshot.mangaCursorUpdatedAt
        collectionMangaCursorRowId = snapshot.mangaCursorRowId
        collectionFeedCursorUpdatedAt = snapshot.feedCursorUpdatedAt
        collectionFeedCursorSourceRank = snapshot.feedCursorSourceRank
        collectionFeedCursorRowId = snapshot.feedCursorRowId
    }

    private func resetCollectionPaging() {
        collectionAnimeItems = []
        collectionMangaItems = []
        hasMoreCollectionAnime = true
        hasMoreCollectionManga = true
        isLoadingMoreCollectionAnime = false
        isLoadingMoreCollectionManga = false
        collectionAnimeCursorUpdatedAt = nil
        collectionAnimeCursorRowId = nil
        collectionMangaCursorUpdatedAt = nil
        collectionMangaCursorRowId = nil
    }

    private func resetCollectionFeedPaging() {
        collectionFeedItems = []
        hasMoreCollectionFeed = true
        isLoadingMoreCollectionFeed = false
        collectionFeedCursorUpdatedAt = nil
        collectionFeedCursorSourceRank = nil
        collectionFeedCursorRowId = nil
    }

    struct CollectionAnimeRow: Decodable, Sendable {
        let list_updated_at: Date
        let list_row_id: Int
        let id: Int
        let title_english: String?
        let title_romaji: String?
        let title_native: String?
        let cover_image_large: String?
        let cover_image_medium: String?
        let banner_image: String?
        let format: String?
        let status: String?
        let episode_count: Int?
        let season_year: Int?
        let start_date_year: Int?
        let average_score: Int?
        let popularity: Int?
        let trending: Int?
        let favourites: Int?
        let genres: [String]?
        let created_at: Date?

        var card: AnimeCard {
            AnimeCard(
                id: id,
                titleEnglish: title_english,
                titleRomaji: title_romaji,
                titleNative: title_native,
                coverImageLarge: cover_image_large,
                coverImageMedium: cover_image_medium,
                bannerImage: banner_image,
                format: format,
                status: status,
                episodeCount: episode_count,
                seasonYear: season_year,
                startDateYear: start_date_year,
                averageScore: average_score,
                popularity: popularity,
                trending: trending,
                favourites: favourites,
                genreList: genres,
                createdAt: created_at,
                rank: nil
            )
        }
    }

    struct CollectionMangaRow: Decodable, Sendable {
        let list_updated_at: Date
        let list_row_id: Int
        let id: Int
        let title_english: String?
        let title_romaji: String?
        let title_native: String?
        let cover_image_large: String?
        let cover_image_medium: String?
        let format: String?
        let status: String?
        let chapter_count: Int?
        let start_date_year: Int?
        let average_score: Int?
        let popularity: Int?
        let trending: Int?
        let favourites: Int?
        let genres: [String]?
        let created_at: Date?

        var card: MangaCard {
            MangaCard(
                id: id,
                titleEnglish: title_english,
                titleRomaji: title_romaji,
                titleNative: title_native,
                coverImageLarge: cover_image_large,
                coverImageMedium: cover_image_medium,
                format: format,
                status: status,
                chapterCount: chapter_count,
                startDateYear: start_date_year,
                averageScore: average_score,
                popularity: popularity,
                trending: trending,
                favourites: favourites,
                genreList: genres,
                createdAt: created_at,
                rank: nil
            )
        }
    }

    struct CollectionFeedRow: Decodable, Sendable {
        let list_updated_at: Date
        let source_rank: Int
        let list_row_id: Int
        let media_type: String
        let id: Int
        let title_english: String?
        let title_romaji: String?
        let title_native: String?
        let cover_image_large: String?
        let cover_image_medium: String?
        let banner_image: String?
        let format: String?
        let status: String?
        let episode_count: Int?
        let chapter_count: Int?
        let season_year: Int?
        let start_date_year: Int?
        let average_score: Int?
        let popularity: Int?
        let trending: Int?
        let favourites: Int?
        let genres: [String]?
        let created_at: Date?

        var media: Media {
            let kind: MediaKind = media_type.uppercased() == "MANGA" ? .manga : .anime
            let yearInt: Int? = kind == .anime ? (season_year ?? start_date_year) : start_date_year
            let rating: Double? = average_score.map { Double($0) / 10.0 }
            let image = cover_image_large ?? cover_image_medium
            let title = (title_english?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title_english : nil)
                ?? title_romaji
                ?? title_native
                ?? "Untitled"

            return Media(
                id: id,
                kind: kind,
                title: title,
                imageURL: image,
                year: yearInt.map(String.init) ?? "TBA",
                displayDescription: "",
                episodes: episode_count,
                chapters: chapter_count,
                rating: rating,
                genres: genres,
                statusRaw: status,
                formatRaw: format,
                popularityValue: popularity,
                trendingValue: trending,
                createdAtValue: created_at
            )
        }
    }

    @discardableResult
    func fetchNextCollectionFeedPage(limit: Int = 90) async -> Bool {
        do {
            let listTypeAnime = currentCollectionStatusFilter.map { dbListType(for: $0, mediaType: "anime") }
            let listTypeManga = currentCollectionStatusFilter.map { dbListType(for: $0, mediaType: "manga") }
            return try await fetchNextCollectionFeedPage(
                limit: limit,
                listTypeAnime: listTypeAnime,
                listTypeManga: listTypeManga,
                generation: collectionFeedFetchGeneration
            )
        } catch {
            collectionErrorMessage = "Failed to load more: \(error.localizedDescription)"
            print("❌ collection feed page: \(error)")
            return false
        }
    }

    @discardableResult
    func fetchNextCollectionAnimePage(limit: Int = 80) async -> Bool {
        do {
            let listType = currentCollectionStatusFilter.map { dbListType(for: $0, mediaType: "anime") }
            return try await fetchNextCollectionAnimePage(limit: limit, listType: listType, generation: collectionFetchGeneration)
        } catch {
            collectionErrorMessage = "Failed to load more: \(error.localizedDescription)"
            print("❌ collection anime page: \(error)")
            return false
        }
    }

    @discardableResult
    func fetchNextCollectionMangaPage(limit: Int = 80) async -> Bool {
        do {
            let listType = currentCollectionStatusFilter.map { dbListType(for: $0, mediaType: "manga") }
            return try await fetchNextCollectionMangaPage(limit: limit, listType: listType, generation: collectionFetchGeneration)
        } catch {
            collectionErrorMessage = "Failed to load more: \(error.localizedDescription)"
            print("❌ collection manga page: \(error)")
            return false
        }
    }

    private func fetchNextCollectionFeedPage(
        limit: Int,
        listTypeAnime: String?,
        listTypeManga: String?,
        generation: Int
    ) async throws -> Bool {
        guard hasMoreCollectionFeed, !isLoadingMoreCollectionFeed else { return false }
        isLoadingMoreCollectionFeed = true
        defer { isLoadingMoreCollectionFeed = false }
        if Task.isCancelled { return false }

        let perf = KuroPerf.begin("rpc.collection_feed_page")
        let params = RPCCollectionFeedPageParams(
            p_limit: max(1, min(120, limit)),
            p_cursor_updated_at: collectionFeedCursorUpdatedAt,
            p_cursor_source_rank: collectionFeedCursorSourceRank,
            p_cursor_row_id: collectionFeedCursorRowId,
            p_list_type_anime: listTypeAnime,
            p_list_type_manga: listTypeManga
        )
        let rows: [CollectionFeedRow] = try await client
            .rpc("collection_feed_page", params: params)
            .execute()
            .value
        if Task.isCancelled || generation != collectionFeedFetchGeneration {
            KuroPerf.end(perf, message: "cancelled")
            return false
        }

        let items = rows.map(\.media)
        collectionFeedItems.append(contentsOf: items)
        hasMoreCollectionFeed = rows.count == params.p_limit
        if let last = rows.last {
            collectionFeedCursorUpdatedAt = last.list_updated_at
            collectionFeedCursorSourceRank = last.source_rank
            collectionFeedCursorRowId = last.list_row_id
        }
        KuroPerf.end(perf, message: "ok \(rows.count)")
        return true
    }

    private func fetchNextCollectionAnimePage(limit: Int, listType: String?, generation: Int) async throws -> Bool {
        guard hasMoreCollectionAnime, !isLoadingMoreCollectionAnime else { return false }
        isLoadingMoreCollectionAnime = true
        defer { isLoadingMoreCollectionAnime = false }
        if Task.isCancelled { return false }

        let perf = KuroPerf.begin("rpc.collection_anime_page")
        let params = RPCCollectionAnimePageParams(
            p_limit: max(1, min(120, limit)),
            p_cursor_updated_at: collectionAnimeCursorUpdatedAt,
            p_cursor_row_id: collectionAnimeCursorRowId,
            p_list_type: listType
        )
        let rows: [CollectionAnimeRow] = try await client
            .rpc("collection_anime_page", params: params)
            .execute()
            .value
        if Task.isCancelled || generation != collectionFetchGeneration {
            KuroPerf.end(perf, message: "cancelled")
            return false
        }

        let cards = rows.map(\.card)
        collectionAnimeItems.append(contentsOf: cards)
        hasMoreCollectionAnime = rows.count == params.p_limit
        if let last = rows.last {
            collectionAnimeCursorUpdatedAt = last.list_updated_at
            collectionAnimeCursorRowId = last.list_row_id
        }
        KuroPerf.end(perf, message: "ok \(rows.count)")
        return true
    }

    private func fetchNextCollectionMangaPage(limit: Int, listType: String?, generation: Int) async throws -> Bool {
        guard hasMoreCollectionManga, !isLoadingMoreCollectionManga else { return false }
        isLoadingMoreCollectionManga = true
        defer { isLoadingMoreCollectionManga = false }
        if Task.isCancelled { return false }

        let perf = KuroPerf.begin("rpc.collection_manga_page")
        let params = RPCCollectionMangaPageParams(
            p_limit: max(1, min(120, limit)),
            p_cursor_updated_at: collectionMangaCursorUpdatedAt,
            p_cursor_row_id: collectionMangaCursorRowId,
            p_list_type: listType
        )
        let rows: [CollectionMangaRow] = try await client
            .rpc("collection_manga_page", params: params)
            .execute()
            .value
        if Task.isCancelled || generation != collectionFetchGeneration {
            KuroPerf.end(perf, message: "cancelled")
            return false
        }

        let cards = rows.map(\.card)
        collectionMangaItems.append(contentsOf: cards)
        hasMoreCollectionManga = rows.count == params.p_limit
        if let last = rows.last {
            collectionMangaCursorUpdatedAt = last.list_updated_at
            collectionMangaCursorRowId = last.list_row_id
        }
        KuroPerf.end(perf, message: "ok \(rows.count)")
        return true
    }

    // MARK: - Upsert user list entry (status/progress/rating/notes)
    func upsertUserListEntry(
        mediaId: Int,
        mediaType: String,
        status: ListStatus,
        progress: Int,
        rating: Int?,
        notes: String?
    ) async {
        guard let userId = await currentUserIdString() else { return }
        errorMessage = nil
        do {
            let table: String
            let onConflict: String
            let payload: Encodable

            struct AnimePayload: Encodable {
                let user_id: String
                let anime_id: Int
                let list_type: String
                let progress: Int
                let rating: Int?
                let notes: String?
            }

            struct MangaPayload: Encodable {
                let user_id: String
                let manga_id: Int
                let list_type: String
                let progress: Int
                let rating: Int?
                let notes: String?
            }

            if mediaType.lowercased() == "anime" {
                table = "anime_user_lists"
                onConflict = "user_id,anime_id"
                payload = AnimePayload(
                    user_id: userId,
                    anime_id: mediaId,
                    list_type: dbListType(for: status, mediaType: mediaType),
                    progress: max(0, progress),
                    rating: rating,
                    notes: notes
                )
            } else if mediaType.lowercased() == "manga" {
                table = "manga_user_lists"
                onConflict = "user_id,manga_id"
                payload = MangaPayload(
                    user_id: userId,
                    manga_id: mediaId,
                    list_type: dbListType(for: status, mediaType: mediaType),
                    progress: max(0, progress),
                    rating: rating,
                    notes: notes
                )
            } else {
                print("⚠️ Unknown mediaType: \(mediaType)")
                return
            }

            try await client
                .from(table)
                .upsert(payload, onConflict: onConflict)
                .execute()

            errorMessage = nil
            await fetchUserLists()
            await fetchCollectionItems(status: currentCollectionStatusFilter)
            await fetchCollectionFeed(status: currentCollectionStatusFilter)

            if mediaType.lowercased() == "anime" {
                await scheduleAiringNotifications(animeId: mediaId)
                await fetchUpcomingForUser(days: 7)
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            print("❌ upsert list entry error: \(error)")
        }
    }

    func updateUserListProgress(mediaId: Int, mediaType: String, progress: Int) async {
        guard let userId = await currentUserIdString() else { return }
        do {
            let table = mediaType.lowercased() == "anime" ? "anime_user_lists" : "manga_user_lists"
            let idColumn = mediaType.lowercased() == "anime" ? "anime_id" : "manga_id"

            struct UpdateData: Encodable { let progress: Int }

            try await client
                .from(table)
                .update(UpdateData(progress: max(0, progress)))
                .eq("user_id", value: userId)
                .eq(idColumn, value: mediaId)
                .execute()

            await fetchUserLists()
        } catch {
            print("❌ Failed to update progress: \(error)")
        }
    }

    func fetchUserLists() async {
        if let t = userListsFetchInFlight {
            await t.value
            return
        }
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchUserListsImpl()
        }
        userListsFetchInFlight = t
        await t.value
        userListsFetchInFlight = nil
    }

    private func _fetchUserListsImpl() async {
        guard let userId = await currentUserIdString() else { return }

        struct AnimeListRow: Decodable {
            let id: Int
            let user_id: String
            let anime_id: Int
            let list_type: String
            let progress: Int
            let rating: Int?
            let notes: String?
            let created_at: Date
            let updated_at: Date
        }

        struct MangaListRow: Decodable {
            let id: Int
            let user_id: String
            let manga_id: Int
            let list_type: String
            let progress: Int
            let rating: Int?
            let notes: String?
            let created_at: Date
            let updated_at: Date
        }

        do {
            // Avoid `async let`: some SDK builders are not Sendable under Swift 6 strict concurrency.
            let animeRows: [AnimeListRow] = try await client
                .from("anime_user_lists")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value
            let mangaRows: [MangaListRow] = try await client
                .from("manga_user_lists")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let mappedAnime = animeRows.map { row in
                UserList(
                    id: row.id,
                    userId: row.user_id,
                    mediaId: row.anime_id,
                    mediaType: "anime",
                    status: statusFromDB(row.list_type),
                    progress: row.progress,
                    progressVolumes: nil,
                    score: row.rating.map { $0 * 10 },
                    notes: row.notes,
                    startedAt: nil,
                    completedAt: nil,
                    isPrivate: false,
                    createdAt: row.created_at,
                    updatedAt: row.updated_at
                )
            }

            let mappedManga = mangaRows.map { row in
                UserList(
                    id: row.id,
                    userId: row.user_id,
                    mediaId: row.manga_id,
                    mediaType: "manga",
                    status: statusFromDB(row.list_type),
                    progress: row.progress,
                    progressVolumes: nil,
                    score: row.rating.map { $0 * 10 },
                    notes: row.notes,
                    startedAt: nil,
                    completedAt: nil,
                    isPrivate: false,
                    createdAt: row.created_at,
                    updatedAt: row.updated_at
                )
            }

            let combined = (mappedAnime + mappedManga).sorted { $0.updatedAt > $1.updatedAt }
            userLists = combined
            rebuildUserListCaches()
            print("✅ Fetched user lists: anime=\(mappedAnime.count), manga=\(mappedManga.count)")
        } catch {
            errorMessage = "Failed to fetch lists: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
    }
    
    // MARK: - Add/Remove in normalized user lists
    func addToList(mediaId: Int, mediaType: String, status: ListStatus) async {
        await upsertUserListEntry(
            mediaId: mediaId,
            mediaType: mediaType,
            status: status,
            progress: 0,
            rating: nil,
            notes: nil
        )
    }

    func removeFromList(mediaId: Int, mediaType: String) async {
        guard let userId = await currentUserIdString() else { return }
        errorMessage = nil
        do {
            let table: String
            let idColumn: String
            switch mediaType.lowercased() {
            case "anime": table = "anime_user_lists"; idColumn = "anime_id"
            case "manga": table = "manga_user_lists"; idColumn = "manga_id"
            default: return
            }

            try await client
                .from(table)
                .delete()
                .eq("user_id", value: userId)
                .eq(idColumn, value: mediaId)
                .execute()

            errorMessage = nil
            await fetchUserLists()
            await fetchCollectionItems(status: currentCollectionStatusFilter)
            await fetchCollectionFeed(status: currentCollectionStatusFilter)
            print("✅ Removed from user list")
            if mediaType.lowercased() == "anime" {
                cancelAiringNotifications(animeId: mediaId)
                // Remove countdown entry
                countdownByAnimeId[mediaId] = nil
                upcomingAirings.removeAll { $0.anime_id == mediaId }
            }
        } catch {
            errorMessage = "Failed to remove from list: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
    }

    // MARK: - Upcoming Airings (user-scoped)
    func fetchUpcomingForUser(days: Int = 7) async {
        if let t = upcomingFetchInFlight {
            await t.value
            return
        }

        // Don't hammer the API when multiple screens mount or when realtime emits bursts.
        let now = Date()
        if days == lastUpcomingDays, let last = lastUpcomingFetchAt, now.timeIntervalSince(last) < 20 {
            return
        }
        guard upcomingBackoff.canAttempt(now: now) else { return }

        lastUpcomingDays = days
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchUpcomingForUserImpl(days: days)
        }
        upcomingFetchInFlight = t
        await t.value
        upcomingFetchInFlight = nil
    }

    private func _fetchUpcomingForUserImpl(days: Int) async {
        guard let userId = await currentUserIdString() else { return }
        do {
            let nowISO = ISO8601DateFormatter().string(from: Date())
            let untilISO = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(days) * 24 * 60 * 60))
            let rows: [UpcomingAiring] = try await client
                .from("user_airing_next")
                .select()
                .eq("user_id", value: userId)
                .gte("next_airing_at", value: nowISO)
                .lt("next_airing_at", value: untilISO)
                .order("next_airing_at", ascending: true)
                .limit(500)
                .execute()
                .value
            self.upcomingAirings = rows
            updateCountdowns()
            lastUpcomingFetchAt = Date()
            upcomingBackoff.recordSuccess()
        } catch {
            upcomingBackoff.recordFailure()
            print("❌ Failed to fetch upcoming airings: \(error)")
        }
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        if interval <= 0 { return "Now" }
        let minutes = Int(interval / 60)
        let days = minutes / (60 * 24)
        let hours = (minutes % (60 * 24)) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private func updateCountdowns() {
        let now = Date()
        var map: [Int: String] = [:]
        for u in upcomingAirings {
            let interval = u.next_airing_at.timeIntervalSince(now)
            map[u.anime_id] = formatInterval(interval)
        }
        countdownByAnimeId = map
    }

    private func startCountdownUpdates() {
        countdownTimer?.invalidate()
        // Avoid passing an actor-isolated closure to Timer (Swift 6 strict concurrency warning).
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdowns()
            }
        }
    }

    private func stopCountdownUpdates() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Local Notifications for Airings (Anime only)
    private func ensureNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("⚠️ Notification permission request failed: \(error)")
            }
        }
    }

    private func scheduleNotification(id: String, title: String, body: String, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do { try await UNUserNotificationCenter.current().add(request) } catch { print("❌ Schedule notif failed: \(error)") }
    }

    func scheduleAiringNotifications(animeId: Int) async {
        do {
            struct Row: Decodable { let id: Int; let title_english: String?; let title_romaji: String?; let next_episode_number: Int?; let next_airing_at: Date? }
            let row: Row = try await client
                .from("anime")
                .select("id,title_english,title_romaji,next_episode_number,next_airing_at")
                .eq("id", value: animeId)
                .single()
                .execute()
                .value
            guard let airAt = row.next_airing_at, airAt > Date() else { return }
            await ensureNotificationPermission()
            let title = row.title_english ?? row.title_romaji ?? "Upcoming Episode"
            let ep = row.next_episode_number.map { "E\($0)" } ?? "Next"
            // Schedule "now airing"
            await scheduleNotification(id: "airing-\(animeId)-start", title: "\(title) airs now", body: "\(ep) is starting.", at: airAt)
            // Schedule 1 hour before if applicable
            let oneHourBefore = airAt.addingTimeInterval(-3600)
            if oneHourBefore > Date() {
                await scheduleNotification(id: "airing-\(animeId)-1h", title: "In 1 hour: \(title)", body: "\(ep) airs soon.", at: oneHourBefore)
            }
        } catch {
            print("⚠️ Could not schedule notifications: \(error)")
        }
    }

    func cancelAiringNotifications(animeId: Int) {
        let ids = ["airing-\(animeId)-start", "airing-\(animeId)-1h"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - External Links & Streaming Helpers
    func fetchExternalLinks(mediaType: String, mediaId: Int) async -> [ExternalLink] {
        do {
            return try await client
                .from("external_links")
                .select()
                .eq("media_type", value: mediaType.uppercased())
                .eq("media_id", value: mediaId)
                .eq("is_disabled", value: false)
                .order("priority", ascending: true)
                .execute()
                .value
        } catch {
            print("❌ Error fetching external links: \(error)")
            return []
        }
    }

    // MARK: - Episodes / Chapters (paged)
    func fetchEpisodesNext(animeId: Int, fromNumber: Int, limit: Int = 20) async -> [Episode] {
        do {
            var q = client.from("episodes").select()
                .eq("anime_id", value: animeId)

            if fromNumber > 1 {
                q = q.gte("number", value: fromNumber)
            }

            let ordered = q.order("number", ascending: true)
            return try await ordered.range(from: 0, to: max(0, limit - 1)).execute().value
        } catch {
            print("❌ fetch episodes next: \(error)")
            return []
        }
    }

    func fetchEpisodesPage(animeId: Int, offset: Int, limit: Int = 50) async -> [Episode] {
        do {
            let from = max(0, offset)
            let to = from + max(1, limit) - 1
            return try await client.from("episodes").select()
                .eq("anime_id", value: animeId)
                .order("number", ascending: true)
                .range(from: from, to: to)
                .execute()
                .value
        } catch {
            print("❌ fetch episodes page: \(error)")
            return []
        }
    }

    func fetchChaptersNext(mangaId: Int, fromNumber: Int, limit: Int = 20) async -> [MangaChapter] {
        do {
            var q = client.from("chapters").select()
                .eq("manga_id", value: mangaId)

            if fromNumber > 1 {
                q = q.gte("number", value: fromNumber)
            }

            let ordered = q.order("number", ascending: true)
            return try await ordered.range(from: 0, to: max(0, limit - 1)).execute().value
        } catch {
            print("❌ fetch chapters next: \(error)")
            return []
        }
    }

    func fetchChaptersPage(mangaId: Int, offset: Int, limit: Int = 50) async -> [MangaChapter] {
        do {
            let from = max(0, offset)
            let to = from + max(1, limit) - 1
            return try await client.from("chapters").select()
                .eq("manga_id", value: mangaId)
                .order("number", ascending: true)
                .range(from: from, to: to)
                .execute()
                .value
        } catch {
            print("❌ fetch chapters page: \(error)")
            return []
        }
    }

    func setUserProgress(mediaId: Int, mediaType: String, progress: Int) async {
        if let existing = userLists.first(where: { $0.mediaId == mediaId && $0.mediaType.lowercased() == mediaType.lowercased() }) {
            let rating = existing.score.map { $0 / 10 }
            await upsertUserListEntry(
                mediaId: mediaId,
                mediaType: mediaType,
                status: existing.status,
                progress: progress,
                rating: (rating ?? 0) > 0 ? rating : nil,
                notes: existing.notes
            )
        } else {
            await upsertUserListEntry(
                mediaId: mediaId,
                mediaType: mediaType,
                status: .current,
                progress: progress,
                rating: nil,
                notes: nil
            )
        }
    }

    func getStreamLinkForEpisode(animeId: Int, episodeNumber: Int) async -> (url: String, site: String)? {
        do {
            let rows: [Episode] = try await client
                .from("episodes")
                .select()
                .eq("anime_id", value: animeId)
                .eq("number", value: episodeNumber)
                .limit(1)
                .execute()
                .value
            if let ep = rows.first, let url = ep.streamUrl, let site = ep.streamSite {
                return (url, site)
            }
        } catch {
            print("❌ Error fetching episode stream: \(error)")
        }
        return nil
    }

    private func bestLink(from links: [ExternalLink], ranking: [String]) -> ExternalLink? {
        guard !links.isEmpty else { return nil }
        func weight(for link: ExternalLink) -> (Int, Int) {
            let priority = link.priority ?? 999
            let site = (link.site ?? "").lowercased()
            let rankIndex = ranking.firstIndex(where: { site.contains($0) }) ?? 999
            return (priority, rankIndex)
        }
        return links
            .filter { !$0.isDisabled && $0.url.lowercased().hasPrefix("http") }
            .min(by: { lhs, rhs in weight(for: lhs) < weight(for: rhs) })
    }

    func getProgress(for mediaId: Int) -> Int? {
        userLists.first { $0.mediaId == mediaId && $0.mediaType.lowercased() == "anime" }?.progress
    }

    func getBestWatchLink(anime: Anime, userProgress: Int?) async -> (url: String, site: String, label: String)? {
        let nextEpisode = max(1, (userProgress ?? 0) + 1)
        if let episodeLink = await getStreamLinkForEpisode(animeId: anime.id, episodeNumber: nextEpisode) {
            let label = "WATCH EP \(nextEpisode) ON \(episodeLink.site.uppercased())"
            return (episodeLink.url, episodeLink.site, label)
        }

        let links = await fetchExternalLinks(mediaType: "ANIME", mediaId: anime.id)
        guard let best = bestLink(from: links, ranking: animeProviderRanking) else {
            return nil
        }
        let siteLabel = (best.site ?? "PROVIDER").uppercased()
        let verb = (userProgress ?? 0) > 0 ? "CONTINUE" : "WATCH"
        return (best.url, best.site ?? "Provider", "\(verb) ON \(siteLabel)")
    }

    func getBestReadLink(manga: Manga) async -> (url: String, site: String, label: String)? {
        let links = await fetchExternalLinks(mediaType: "MANGA", mediaId: manga.id)
        guard let best = bestLink(from: links, ranking: mangaProviderRanking) else { return nil }
        let siteLabel = (best.site ?? "Reader").uppercased()
        return (best.url, best.site ?? "Reader", "READ ON \(siteLabel)")
    }

    // MARK: - Browse (server-driven paging + filters)
    func fetchBrowseAnimePageKeyset(
        genre: String?,
        status: String?,
        minEpisodes: Int?,
        maxEpisodes: Int?,
        sort: BrowseSort = .popular,
        cursorInt: Int?,
        cursorDate: Date?,
        cursorId: Int?,
        limit: Int
    ) async -> [AnimeCard] {
        do {
            let perf = KuroPerf.begin("rpc.browse_anime_page")
            let params = RPCBrowseAnimePageParams(
                p_genre: genre,
                p_status: status,
                p_min_episodes: minEpisodes,
                p_max_episodes: maxEpisodes,
                p_sort: sort.rpcKey,
                p_cursor_int: cursorInt,
                p_cursor_ts: cursorDate,
                p_cursor_id: cursorId,
                p_limit: max(1, min(120, limit))
            )
            let rows: [AnimeCard] = try await client.rpc("browse_anime_page", params: params).execute().value
            KuroPerf.end(perf, message: "ok")
            return rows
        } catch {
            print("❌ browse_anime_page rpc: \(error)")
            return []
        }
    }

    func fetchBrowseMangaPageKeyset(
        genre: String?,
        status: String?,
        minChapters: Int?,
        maxChapters: Int?,
        sort: BrowseSort = .popular,
        cursorInt: Int?,
        cursorDate: Date?,
        cursorId: Int?,
        limit: Int
    ) async -> [MangaCard] {
        do {
            let perf = KuroPerf.begin("rpc.browse_manga_page")
            let params = RPCBrowseMangaPageParams(
                p_genre: genre,
                p_status: status,
                p_min_chapters: minChapters,
                p_max_chapters: maxChapters,
                p_sort: sort.rpcKey,
                p_cursor_int: cursorInt,
                p_cursor_ts: cursorDate,
                p_cursor_id: cursorId,
                p_limit: max(1, min(120, limit))
            )
            let rows: [MangaCard] = try await client.rpc("browse_manga_page", params: params).execute().value
            KuroPerf.end(perf, message: "ok")
            return rows
        } catch {
            print("❌ browse_manga_page rpc: \(error)")
            return []
        }
    }

    func fetchBrowseAnimePage(
        genre: String?,
        status: String?,
        minEpisodes: Int?,
        maxEpisodes: Int?,
        sort: BrowseSort = .popular,
        page: Int,
        pageSize: Int
    ) async -> [Anime] {
        do {
            let size = max(1, pageSize)
            let offset = max(0, page) * size
            var q = client.from("anime").select()

            if let genre, !genre.isEmpty {
                q = q.contains("genres", value: [genre])
            }
            if let status, !status.isEmpty {
                q = q.eq("status", value: status)
            }
            if let minEpisodes {
                q = q.gte("episodes", value: minEpisodes)
            }
            if let maxEpisodes {
                q = q.lte("episodes", value: maxEpisodes)
            }

            let ordered = q.order(sort.orderColumn, ascending: false).order("id", ascending: false)
            return try await ordered.range(from: offset, to: offset + size - 1).execute().value
        } catch {
            print("❌ browse anime fetch: \(error)")
            return []
        }
    }

    func fetchBrowseMangaPage(
        genre: String?,
        status: String?,
        minChapters: Int?,
        maxChapters: Int?,
        sort: BrowseSort = .popular,
        page: Int,
        pageSize: Int
    ) async -> [Manga] {
        do {
            let size = max(1, pageSize)
            let offset = max(0, page) * size
            var q = client.from("manga").select()

            if let genre, !genre.isEmpty {
                q = q.contains("genres", value: [genre])
            }
            if let status, !status.isEmpty {
                q = q.eq("status", value: status)
            }
            if let minChapters {
                q = q.gte("chapters", value: minChapters)
            }
            if let maxChapters {
                q = q.lte("chapters", value: maxChapters)
            }

            let ordered = q.order(sort.orderColumn, ascending: false).order("id", ascending: false)
            return try await ordered.range(from: offset, to: offset + size - 1).execute().value
        } catch {
            print("❌ browse manga fetch: \(error)")
            return []
        }
    }
    
    // MARK: - Filter by Genre (using your genres array)
    func filterByGenre(_ genre: String) async {
        isLoading = true
        
        do {
            let response: [Anime] = try await client
                .from("anime")
                .select()
                .contains("genres", value: [genre])
                .order("average_score", ascending: false)
                .limit(50)
                .execute()
                .value
            
            animeItems = response
            print("✅ Filtered by genre: \(genre)")
        } catch {
            errorMessage = "Filter failed: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Get by Mood (using your genre system)
    func getByMood(_ mood: String) -> [Anime] {
        switch mood {
        case "Contemplative":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Drama", "Psychological", "Mystery"].contains(genre)
                }) ?? false
            }
        case "Energetic":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Action", "Sports", "Adventure"].contains(genre)
                }) ?? false
            }
        case "Melancholic":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Drama", "Romance", "Slice of Life"].contains(genre)
                }) ?? false
            }
        case "Uplifting":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Comedy", "Adventure", "Music"].contains(genre)
                }) ?? false
            }
        case "Mysterious":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Thriller", "Horror", "Supernatural", "Mystery"].contains(genre)
                }) ?? false
            }
        default:
            return Array(animeItems.prefix(10))
        }
    }

    // MARK: - Concierge (Edge Functions)
    enum ConciergeScope: String, Sendable {
        case anime
        case manga
        case both
    }

    enum ConciergeGuardrailsError: LocalizedError, Sendable, Equatable {
        case rateLimited(retryAfterSeconds: Int?)

        var errorDescription: String? {
            switch self {
            case .rateLimited(let s):
                if let s, s > 0 { return "Too many requests. Try again in \(s)s." }
                return "Too many requests. Try again in a moment."
            }
        }
    }

    private func decodeRetryAfterSeconds(from data: Data) -> Int? {
        // Edge functions return: { "error": "Rate limited", "retry_after_s": 30 }
        guard !data.isEmpty else { return nil }
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let n = obj["retry_after_s"] as? Int { return n }
            if let d = obj["retry_after_s"] as? Double { return Int(d.rounded()) }
            if let s = obj["retry_after_s"] as? String, let n = Int(s) { return n }
        }
        return nil
    }

    private func translateConciergeFunctionError(_ error: Error) -> Error {
        if case let FunctionsError.httpError(code, data) = error, code == 429 {
            return ConciergeGuardrailsError.rateLimited(retryAfterSeconds: decodeRetryAfterSeconds(from: data))
        }
        return error
    }

    struct ConciergeCandidate: Decodable, Sendable, Hashable {
        let media_type: String
        let media_id: Int
        let variant_type: String
        let title_raw: String
        let score: Double
    }

    struct ConciergeParseItemParsed: Decodable, Sendable {
        let mediaTypeHint: String?
        let status: String?
        let progressEpisodes: Int?
        let progressChapters: Int?
        let progressVolumes: Int?
        let seasonNumber: Int?
        let episodeInSeason: Int?
        let caughtUp: Bool?
        let lastEpisode: Bool?
        let completed: Bool?
    }

    struct ConciergeParseItem: Decodable, Sendable, Identifiable {
        let raw: String
        let normalized: String
        let parsed: ConciergeParseItemParsed
        let candidates: [ConciergeCandidate]
        let candidateError: String?

        var id: String { raw + "|" + normalized }
    }

    struct ConciergeParseResponse: Decodable, Sendable {
        let success: Bool
        let userId: String?
        let items: [ConciergeParseItem]
    }

    func conciergeParse(text: String, scope: ConciergeScope = .both, limitPerItem: Int = 10) async throws -> ConciergeParseResponse {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lim = max(3, min(15, limitPerItem))
        let user = await currentUserIdString() ?? "anon"
        let key = "concierge_parse|\(user)|\(scope.rawValue)|\(lim)|\(normalized)"

        let now = Date()
        // Very short TTL: just enough to make back-to-back retries feel instant.
        if let cached = conciergeParseCache[key], now.timeIntervalSince(cached.storedAt) < 600 {
            return cached.value
        }
        if let task = conciergeParseInFlight[key] {
            return try await task.value
        }

        // Run decoding off the main actor to avoid UI jank (keyboard/input stutter).
        let client = self.client
        let task = Task<ConciergeParseResponse, Error>.detached(priority: .userInitiated) {
            let payload = [
                "text": text,
                "scope": scope.rawValue,
                "limitPerItem": lim,
            ] as [String : Any]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let options = FunctionInvokeOptions(method: .post, body: data)
            let resp: ConciergeParseResponse = try await client.functions.invoke("concierge-parse", options: options)
            return resp
        }
        conciergeParseInFlight[key] = task
        defer { conciergeParseInFlight[key] = nil }
        do {
            let resp = try await task.value
            conciergeParseCache[key] = TimedCache(value: resp, storedAt: now)
            trimCache(&conciergeParseCache, maxEntries: 50)
            return resp
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }

    struct ConciergeApplyResponse: Decodable, Sendable {
        let success: Bool
        let sessionId: String?
        struct Applied: Decodable, Sendable {
            let mediaType: String
            let mediaId: Int
            let status: String
        }
        struct ApplyError: Decodable, Sendable {
            let mediaType: String?
            let mediaId: Int?
            let error: String
        }
        let applied: [Applied]?
        let errors: [ApplyError]?
    }

    func conciergeApply(items: [[String: Any]]) async throws -> ConciergeApplyResponse {
        do {
            let payload: [String: Any] = [
                "items": items,
            ]
            let client = self.client
            let task = Task<ConciergeApplyResponse, Error>.detached(priority: .userInitiated) {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                let options = FunctionInvokeOptions(method: .post, body: data)
                return try await client.functions.invoke("concierge-apply", options: options)
            }
            return try await task.value
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }

    struct ConciergeUndoResponse: Decodable, Sendable {
        let success: Bool
        let sessionId: String?
        struct Reverted: Decodable, Sendable {
            let mediaType: String
            let mediaId: Int
        }
        struct UndoError: Decodable, Sendable {
            let id: String?
            let error: String
        }
        let reverted: [Reverted]?
        let errors: [UndoError]?
    }

    func conciergeUndo(sessionId: String) async throws -> ConciergeUndoResponse {
        do {
            let payload: [String: Any] = [
                "sessionId": sessionId,
            ]
            let client = self.client
            let task = Task<ConciergeUndoResponse, Error>.detached(priority: .userInitiated) {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                let options = FunctionInvokeOptions(method: .post, body: data)
                return try await client.functions.invoke("concierge-undo", options: options)
            }
            return try await task.value
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }

    struct ConciergeResolveResponse: Decodable, Sendable {
        let success: Bool
        struct Choice: Decodable, Sendable {
            let i: Int
            let pick: Int
            let confidence: Double
            let reason: String?
            struct Chosen: Decodable, Sendable {
                let id: String
                let title: String
            }
            let chosen: Chosen?
        }
        let choices: [Choice]?
        let error: String?
    }

    func conciergeResolve(items: [ConciergeParseItem], maxCandidates: Int = 6) async throws -> ConciergeResolveResponse {
        let payloadItems: [[String: Any]] = items.prefix(20).map { item in
            let parsed: [String: Any] = [
                "mediaTypeHint": item.parsed.mediaTypeHint as Any,
                "status": item.parsed.status as Any,
                "progressEpisodes": item.parsed.progressEpisodes as Any,
                "progressChapters": item.parsed.progressChapters as Any,
                "progressVolumes": item.parsed.progressVolumes as Any,
                "seasonNumber": item.parsed.seasonNumber as Any,
                "episodeInSeason": item.parsed.episodeInSeason as Any,
                "caughtUp": item.parsed.caughtUp as Any,
                "lastEpisode": item.parsed.lastEpisode as Any,
                "completed": item.parsed.completed as Any,
            ]
            let cands: [[String: Any]] = item.candidates.prefix(max(2, min(10, maxCandidates))).map { c in
                [
                    "media_type": c.media_type,
                    "media_id": c.media_id,
                    "variant_type": c.variant_type,
                    "title_raw": c.title_raw,
                    "score": c.score,
                ]
            }
            return [
                "raw": item.raw,
                "normalized": item.normalized,
                "parsed": parsed,
                "candidates": cands,
            ]
        }

        let payload: [String: Any] = [
            "items": payloadItems,
            "maxCandidates": max(2, min(10, maxCandidates)),
        ]
        do {
            let client = self.client
            let task = Task<ConciergeResolveResponse, Error>.detached(priority: .userInitiated) {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                let options = FunctionInvokeOptions(method: .post, body: data)
                return try await client.functions.invoke("concierge-resolve", options: options)
            }
            return try await task.value
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }

    struct ConciergeRecommendResponse: Decodable, Sendable {
        let success: Bool
        let categories: [String]?
        struct Mode: Decodable, Sendable, Identifiable {
            let id: String
            let title: String
            let confidence: Double?
            let reason: String?
        }
        struct Item: Decodable, Sendable, Identifiable {
            let mediaType: String
            let mediaId: Int
            let matchCount: Int?
            let title: String
            let coverImageMedium: String?
            let averageScore: Int?
            let year: Int?
            let format: String?
            let status: String?
            let siteUrl: String?
            let signals: [String]?
            let blurb: String?

            var id: String { "\(mediaType)|\(mediaId)" }
        }
        struct Set: Decodable, Sendable, Identifiable {
            let id: String
            let title: String
            let modeId: String?
            let confidence: Double?
            let reason: String?
            let items: [Item]?
        }
        let modes: [Mode]?
        let sets: [Set]?
        let items: [Item]?
        let message: String?
        let narrated: Bool?
        let error: String?
    }

    func conciergeRecommend(text: String, scope: ConciergeScope = .both, limit: Int = 8, narrate: Bool = true) async throws -> ConciergeRecommendResponse {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lim = max(3, min(20, limit))
        let user = await currentUserIdString() ?? "anon"
        let key = "concierge_recommend|\(user)|\(scope.rawValue)|\(lim)|\(narrate ? 1 : 0)|\(normalized)"

        let now = Date()
        if let cached = conciergeRecommendCache[key], now.timeIntervalSince(cached.storedAt) < 3600 {
            return cached.value
        }
        if let task = conciergeRecommendInFlight[key] {
            return try await task.value
        }

        // Run decoding off the main actor to keep the chat input responsive.
        let client = self.client
        let task = Task<ConciergeRecommendResponse, Error>.detached(priority: .userInitiated) {
            let payload: [String: Any] = [
                "text": text,
                "scope": scope.rawValue,
                "limit": lim,
                "narrate": narrate,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let options = FunctionInvokeOptions(method: .post, body: data)
            let resp: ConciergeRecommendResponse = try await client.functions.invoke("concierge-recommend", options: options)
            return resp
        }
        conciergeRecommendInFlight[key] = task
        defer { conciergeRecommendInFlight[key] = nil }
        do {
            let resp = try await task.value
            conciergeRecommendCache[key] = TimedCache(value: resp, storedAt: now)
            trimCache(&conciergeRecommendCache, maxEntries: 60)
            return resp
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }
    
    // MARK: - Real-time Subscriptions  
    func subscribeToUpdates() {
        Task { [weak self] in
            guard let self else { return }
            await self.startRealtimeSubscriptionsIfNeeded()
        }
    }

    private func startRealtimeSubscriptionsIfNeeded() async {
        guard let userId = await currentUserIdString() else { return }
        if realtimeSubscribedUserId == userId, realtimeChannel != nil { return }

        await stopRealtimeSubscriptions()
        realtimeSubscribedUserId = userId

        await client.realtimeV2.connect()

        let channel = client.channel("kuro.user.\(userId)")
        realtimeChannel = channel

        let animeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "anime_user_lists",
            filter: .eq("user_id", value: userId)
        )
        let mangaStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "manga_user_lists",
            filter: .eq("user_id", value: userId)
        )

        realtimeListenTasks = [
            Task { [weak self] in
                guard let self else { return }
                for await _ in animeStream {
                    await MainActor.run { self.scheduleRealtimeRefresh() }
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in mangaStream {
                    await MainActor.run { self.scheduleRealtimeRefresh() }
                }
            },
        ]

        await channel.subscribe()
    }

    @MainActor
    private func scheduleRealtimeRefresh() {
        // Coalesce bursts of changes (imports, batch edits) into a single refresh.
        realtimeDebounceTask?.cancel()
        realtimeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.refreshAfterRealtimeEvent()
        }
    }

    private func refreshAfterRealtimeEvent() async {
        // These are all user-scoped; in-flight de-dupe + cancellation keep this cheap.
        await fetchUserLists()
        await fetchCollectionFeed(status: currentCollectionStatusFilter)
        await fetchCollectionItems(status: currentCollectionStatusFilter)
        await fetchUpcomingForUser(days: 7)
    }

    private func stopRealtimeSubscriptions() async {
        realtimeDebounceTask?.cancel()
        realtimeDebounceTask = nil
        for t in realtimeListenTasks { t.cancel() }
        realtimeListenTasks = []

        if let channel = realtimeChannel {
            await client.removeChannel(channel)
        }
        realtimeChannel = nil
        realtimeSubscribedUserId = nil
    }
    
    // MARK: - Collection Management Helpers
    // Fast lookup caches to keep scrolling snappy (avoid O(n) list scans per card render).
    private var collectionAnimeIds: Set<Int> = []
    private var collectionMangaIds: Set<Int> = []
    private var userListByTypeAndId: [String: [Int: UserList]] = [:]
    private var userIdsByTypeAndStatus: [String: [ListStatus: Set<Int>]] = [:]

    private func rebuildUserListCaches() {
        var anime: Set<Int> = []
        var manga: Set<Int> = []
        var byType: [String: [Int: UserList]] = ["anime": [:], "manga": [:]]
        var byTypeStatus: [String: [ListStatus: Set<Int>]] = ["anime": [:], "manga": [:]]

        for item in userLists {
            let t = item.mediaType.lowercased()
            if t == "anime" { anime.insert(item.mediaId) }
            if t == "manga" { manga.insert(item.mediaId) }
            byType[t, default: [:]][item.mediaId] = item
            byTypeStatus[t, default: [:]][item.status, default: []].insert(item.mediaId)
        }

        collectionAnimeIds = anime
        collectionMangaIds = manga
        userListByTypeAndId = byType
        userIdsByTypeAndStatus = byTypeStatus
    }

    func userMediaIds(mediaType: String, status: ListStatus? = nil) -> Set<Int> {
        let t = mediaType.lowercased()
        if let status {
            return userIdsByTypeAndStatus[t]?[status] ?? []
        }
        switch t {
        case "anime": return collectionAnimeIds
        case "manga": return collectionMangaIds
        default: return []
        }
    }

    func isInCollection(mediaId: Int, mediaType: String) -> Bool {
        switch mediaType.lowercased() {
        case "anime": return collectionAnimeIds.contains(mediaId)
        case "manga": return collectionMangaIds.contains(mediaId)
        default: return false
        }
    }

    func isInCollection(_ animeId: Int) -> Bool {
        isInCollection(mediaId: animeId, mediaType: "anime")
    }

    func isInCollectionManga(_ mangaId: Int) -> Bool {
        isInCollection(mediaId: mangaId, mediaType: "manga")
    }

    func userListProgress(mediaType: String, mediaId: Int) -> Int? {
        userListByTypeAndId[mediaType.lowercased()]?[mediaId]?.progress
    }

    func isFavorited(_ animeId: Int) -> Bool {
        // Check if anime has high score (favorited)
        return userListByTypeAndId["anime"]?[animeId]?.score ?? 0 >= 90
    }

    func toggleInCollection(mediaId: Int, mediaType: String) {
        let type = mediaType.lowercased()
        if isInCollection(mediaId: mediaId, mediaType: type) {
            Task { await removeFromList(mediaId: mediaId, mediaType: type) }
        } else {
            Task { await addToList(mediaId: mediaId, mediaType: type, status: .planning) }
        }
    }

    func toggleInCollection(_ animeId: Int) {
        toggleInCollection(mediaId: animeId, mediaType: "anime")
    }

    func toggleFavorite(for animeId: Int) {
        // Toggle by setting/removing high score
        Task {
            guard let entry = userLists.first(where: { $0.mediaId == animeId && $0.mediaType.lowercased() == "anime" }) else { return }
            let shouldUnfavorite = (entry.score ?? 0) >= 90
            let newRating: Int? = shouldUnfavorite ? nil : 10
            await updateListRating(mediaId: animeId, mediaType: "anime", rating: newRating)
        }
    }

    private func updateListRating(mediaId: Int, mediaType: String, rating: Int?) async {
        guard let userId = await currentUserIdString() else { return }
        do {
            let table = mediaType.lowercased() == "anime" ? "anime_user_lists" : "manga_user_lists"
            let idColumn = mediaType.lowercased() == "anime" ? "anime_id" : "manga_id"

            struct UpdateData: Encodable {
                let rating: Int?
            }

            try await client
                .from(table)
                .update(UpdateData(rating: rating))
                .eq("user_id", value: userId)
                .eq(idColumn, value: mediaId)
                .execute()

            await fetchUserLists()
        } catch {
            print("❌ Failed to update rating: \(error)")
        }
    }
}

#else
// Fallback mock service when the Supabase SDK isn't available
@MainActor
@Observable
class SupabaseService {
    static let shared = SupabaseService()

    // Data stores
    var animeItems: [Anime] = []
    var mangaItems: [Manga] = []
    var userLists: [UserList] = []
    var episodes: [Episode] = []
    var isLoading = false
    var errorMessage: String?

    init() {
        // No-op: mock environment
        print("⚠️ Supabase SDK not found. Running with mock SupabaseService.")
    }

    // Auth no-op
    func signInAnonymously() async throws {}

    // Data loading no-ops that simulate empty results
    func fetchAnime(limit: Int = 50) async {
        isLoading = true
        defer { isLoading = false }
        animeItems = []
    }

    func fetchManga(limit: Int = 50) async {
        isLoading = true
        defer { isLoading = false }
        mangaItems = []
    }

    func searchContent(query: String) async {
        isLoading = true
        defer { isLoading = false }
        // Keep whatever is already loaded (mock does nothing)
    }

    func fetchUserLists() async {
        userLists = []
    }

    func addToList(mediaId: Int, mediaType: String, status: ListStatus) async {
        // No persistence in mock
    }

    func filterByGenre(_ genre: String) async {
        isLoading = true
        defer { isLoading = false }
        // No-op
    }

    func getByMood(_ mood: String) -> [Anime] {
        return []
    }

    func subscribeToUpdates() {
        // No realtime in mock
    }

    func isInCollection(_ animeId: Int) -> Bool { false }
    func isFavorited(_ animeId: Int) -> Bool { false }
    func toggleInCollection(_ animeId: Int) {}
    func toggleFavorite(for animeId: Int) {}
}
#endif

```

### Concierge UI (authoritative)

- Path: `Kuro/Views/ConciergeView.swift`


```swift
import SwiftUI

struct ConciergeView: View {
    @Environment(SupabaseService.self) private var supabaseService

    let assistantEnabled: Bool

    @State private var input: String = ""
    @FocusState private var inputFocused: Bool
    @State private var messages: [ConciergeMessage] = []
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var selectedByItemId: [String: SupabaseService.ConciergeCandidate] = [:]
    @State private var lastApplySessionId: String? = nil
    @State private var selectedAnime: Anime? = nil
    @State private var selectedManga: Manga? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var assistantExpanded: Bool = false
    @State private var assistantOffset: CGSize = .zero
    @State private var assistantDragStart: CGSize = .zero

    private var hasActionBar: Bool {
        (activeItems?.isEmpty == false) || lastApplySessionId != nil
    }

    init(assistantEnabled: Bool = true) {
        self.assistantEnabled = assistantEnabled
    }

    var body: some View {
        ZStack {
            // Ambient background so glass has something to refract (kept very subtle).
            // Use a clear base so the sheet's material background stays visible.
            Color.clear.ignoresSafeArea()
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.06), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: -140, y: -220)
                .blur(radius: 0.5)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.05), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .frame(width: 420, height: 420)
                .offset(x: 160, y: -80)
                .blur(radius: 0.5)

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty {
                                ConciergeIntroCard()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 14)
                                    .padding(.bottom, 8)

                                ConciergeStarterActions(
                                    onPaste: { pasteFromClipboard() },
                                    onExampleImport: { seedExampleImport() },
                                    onExampleVibe: { seedExampleVibe() }
                                )
                                .frame(maxWidth: .infinity)
                            }

                            ForEach(messages) { msg in
                                ConciergeBubble(
                                    message: msg,
                                    selected: { item in selectedByItemId[item.id] },
                                    onSelect: { item, candidate in
                                        KuroAccessibility.impactHaptic(.light)
                                        selectedByItemId[item.id] = candidate
                                    },
                                    onOpenRecommendation: { rec in
                                        Task { await openRecommendation(rec) }
                                    },
                                    onQuickSave: { rec in
                                        Task { await quickSaveRecommendation(rec) }
                                    }
                                )
                                .id(msg.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            if isWorking {
                                ConciergeTypingIndicator()
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }

            if let activeItems, !activeItems.isEmpty {
                ConciergeActionBar(
                    selectedCount: activeSelectedCount,
                    hasAnySelection: activeSelectedCount > 0,
                    canUndo: lastApplySessionId != nil,
                    onApply: { Task { await applyActiveItems() } },
                    onUndo: { Task { await undoLastApply() } }
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    KuroGlassCard(cornerRadius: 22) { Color.clear }
                )
            } else if lastApplySessionId != nil {
                ConciergeActionBar(
                    selectedCount: 0,
                    hasAnySelection: false,
                    canUndo: true,
                    onApply: {},
                    onUndo: { Task { await undoLastApply() } }
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    KuroGlassCard(cornerRadius: 22) { Color.clear }
                )
            }

            Divider()
                .opacity(0.12)

                HStack(spacing: 10) {
                    TextField("Paste titles, or ask for a vibe…", text: $input, axis: .vertical)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.black.opacity(0.86))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .lineLimit(1...4)
                        .padding(.vertical, 10)
                        .focused($inputFocused)
                        .submitLabel(.send)
                        .onSubmit { Task { await send() } }

                    Button(action: { Task { await send() } }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking ? .black.opacity(0.2) : .black)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    KuroGlassCard(cornerRadius: 22) {
                        Color.clear
                    }
                )
                // Prevent the global pager swipe gesture from stealing drags/taps while typing.
                // This fixes "faulty" keyboard interactions and accidental page switches.
                .kuroSwipeExclusionZone()
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, hasActionBar ? 152 : 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if assistantEnabled {
                GeometryReader { geo in
                    KuroConciergeAssistant(
                        expanded: $assistantExpanded,
                        offset: $assistantOffset,
                        dragStart: $assistantDragStart,
                        baseBottomPadding: hasActionBar ? 168 : 104,
                        containerSize: geo.size
                    ) {
                        inputFocused = true
                    }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $selectedAnime) { anime in
            AnimeDetailView(anime: anime)
        }
        .sheet(item: $selectedManga) { manga in
            MangaDetailView(manga: manga)
        }
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorText = nil
        input = ""
        withAnimation(.easeInOut(duration: 0.18)) { isWorking = true }
        lastApplySessionId = nil

        let userMsg = ConciergeMessage(role: .user, text: text, items: nil)
        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
            messages.append(userMsg)
        }

        do {
            if looksLikeImport(text) {
                let response = try await supabaseService.conciergeParse(text: text, scope: .both)
                let auto = autoResolveForApply(items: response.items)

                var remaining = auto.remaining
                var llmItemsToApply: [[String: Any]] = []
                var appliedSummaryLines = auto.appliedSummaryLines

                if response.userId != nil, !remaining.isEmpty {
                    // Use the tiny LLM resolver to reduce taps for messy/typo inputs.
                    if let resolve = try? await supabaseService.conciergeResolve(items: remaining, maxCandidates: 6),
                       resolve.success,
                       let choices = resolve.choices,
                       !choices.isEmpty {
                        var appliedIds = Set<String>()

                        for choice in choices {
                            guard choice.pick >= 0 else { continue }
                            guard remaining.indices.contains(choice.i) else { continue }
                            let item = remaining[choice.i]
                            guard item.candidates.indices.contains(choice.pick) else { continue }
                            let picked = item.candidates[choice.pick]

                            selectedByItemId[item.id] = picked

                            // Only auto-apply LLM picks when confidence is high.
                            let titleSafe = isTitleAutoApplySafe(normalized: item.normalized, parsed: item.parsed, candidateTitle: picked.title_raw)
                            let canAutoApply = choice.confidence >= 0.88 && picked.score >= 0.70 && titleSafe
                            if !canAutoApply { continue }

                            let status = normalizedStatus(for: item.parsed.status, mediaType: picked.media_type)
                            var payload: [String: Any] = [
                                "raw": item.raw,
                                "mediaType": picked.media_type.uppercased(),
                                "mediaId": picked.media_id,
                                "status": status,
                                "confidence": picked.score,
                                "candidates": item.candidates.map { cand in
                                    [
                                        "media_type": cand.media_type,
                                        "media_id": cand.media_id,
                                        "variant_type": cand.variant_type,
                                        "title_raw": cand.title_raw,
                                        "score": cand.score,
                                    ]
                                },
                            ]

                            if let p = item.parsed.progressEpisodes { payload["progressEpisodes"] = p }
                            if let p = item.parsed.progressChapters { payload["progressChapters"] = p }
                            if let p = item.parsed.progressVolumes { payload["progressVolumes"] = p }
                            if let s = item.parsed.seasonNumber { payload["seasonNumber"] = s }
                            if let e = item.parsed.episodeInSeason { payload["episodeInSeason"] = e }
                            if let b = item.parsed.caughtUp { payload["caughtUp"] = b }
                            if let b = item.parsed.lastEpisode { payload["lastEpisode"] = b }
                            if let b = item.parsed.completed { payload["completed"] = b }

                            llmItemsToApply.append(payload)
                            appliedIds.insert(item.id)
                            appliedSummaryLines.append(
                                summaryLineForAppliedItem(title: picked.title_raw, mediaType: picked.media_type, status: status, parsed: item.parsed)
                            )
                        }

                        remaining = remaining.filter { !appliedIds.contains($0.id) }
                    }
                }

                let combinedToApply = auto.itemsToApply + llmItemsToApply

                if response.userId != nil, !combinedToApply.isEmpty {
                    let res = try await supabaseService.conciergeApply(items: combinedToApply)
                    if let sessionId = res.sessionId { lastApplySessionId = sessionId }
                    await supabaseService.fetchUserLists()
                    await supabaseService.fetchCollectionItems()

                    if remaining.isEmpty {
                        let details = appliedSummaryLines.isEmpty ? "" : ("\n" + appliedSummaryLines.prefix(6).map { "• \($0)" }.joined(separator: "\n"))
                        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                            messages.append(
                                ConciergeMessage(
                                    role: .assistant,
                                    text: res.success
                                        ? "Saved.\(details)"
                                        : "Applied with errors. You can undo and try again.",
                                    items: nil
                                )
                            )
                        }
                    } else {
                        // Preselect the top candidate for the rest so it feels fast.
                        for item in remaining {
                            guard let top = item.candidates.first else { continue }
                            if top.score >= 0.60 {
                                selectedByItemId[item.id] = top
                            }
                        }
                        let details = appliedSummaryLines.isEmpty ? "" : ("\n" + appliedSummaryLines.prefix(6).map { "• \($0)" }.joined(separator: "\n"))
                        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                            messages.append(
                                ConciergeMessage(
                                    role: .assistant,
                                    text: "Saved what I’m confident about.\(details)\n\nA few are still ambiguous — tap the right match, then APPLY.",
                                    items: remaining
                                )
                            )
                        }
                    }
                } else {
                    // Preselect obvious matches to reduce taps for common cases.
                    for item in response.items {
                        guard let top = item.candidates.first else { continue }
                        if top.score >= 0.60 {
                            selectedByItemId[item.id] = top
                        }
                    }
                    let missing = response.items.filter { !$0.candidateError.isNilOrEmpty }.count
                    let summaryText =
                        response.userId == nil
                        ? "Sign in to apply changes. I can still help you match titles:"
                        : (missing > 0
                            ? "Parsed \(response.items.count) item(s). Some titles didn’t match — tap candidates, then APPLY."
                            : "Parsed \(response.items.count) item(s). Tap candidates, then APPLY.")
                    withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                        messages.append(
                            ConciergeMessage(
                                role: .assistant,
                                text: summaryText,
                                items: response.items
                            )
                        )
                    }
                }
            } else {
                let rec = try await supabaseService.conciergeRecommend(text: text, scope: .both, limit: 8)
                let sets = (rec.sets ?? []).filter { ($0.items ?? []).isEmpty == false }
                let flattened = sets.flatMap { $0.items ?? [] }
                let displayItems = !flattened.isEmpty ? flattened : (rec.items ?? [])

                if rec.success, !displayItems.isEmpty {
                    // Prefetch covers so the recommendation rail renders instantly.
                    let urls = displayItems
                        .compactMap { URL(string: $0.coverImageMedium ?? "") }
                        .prefix(16)
                    if !urls.isEmpty {
                        Task { await ImagePipeline.shared.prefetch(urls: Array(urls), maxPixelSize: 520) }
                    }
                    withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                        messages.append(
                            ConciergeMessage(
                                role: .assistant,
                                text: rec.message ?? "Here are a few picks:",
                                items: nil,
                                recommendations: displayItems,
                                recommendationSets: sets.isEmpty ? nil : sets,
                                recommendationCategories: rec.categories
                            )
                        )
                    }
                } else {
                    withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                        messages.append(
                            ConciergeMessage(
                                role: .assistant,
                                text: rec.message ?? "Tell me a vibe (funny, sad, cozy, action) and I’ll recommend something new-to-you.",
                                items: nil,
                                recommendations: nil
                            )
                        )
                    }
                }
            }
        } catch {
            if let guardrail = error as? SupabaseService.ConciergeGuardrailsError {
                errorText = guardrail.localizedDescription
                showToast(.init(kind: .error, title: "Slow down", subtitle: guardrail.localizedDescription, actionTitle: nil, onAction: nil), autoDismissSeconds: 3.0)
            } else {
                errorText = "Concierge error: \(error.localizedDescription)"
                showToast(.init(kind: .error, title: "Concierge error", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil), autoDismissSeconds: 3.0)
            }
        }

        withAnimation(.easeInOut(duration: 0.18)) { isWorking = false }
    }

    private func looksLikeImport(_ text: String) -> Bool {
        // High precision: false positives feel like "wrong responses" because we route to import parsing
        // instead of recommendations. We prefer a few false negatives over misrouting vibes.
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = t.lowercased()

        if t.contains("\n") { return true }

        // Explicit import language (EN + DE)
        if l.contains("watching") || l.contains("reading") || l.contains("completed") || l.contains("finished") || l.contains("dropped") { return true }
        if l.contains("i watched") || l.contains("i'm watching") || l.contains("im watching") { return true }
        if l.contains("caught up") || l.contains("up to date") { return true }
        if l.contains("ich habe") || l.contains("ich schaue") || l.contains("ich gucke") || l.contains("ich sehe") || l.contains("ich lese") { return true }
        if l.contains("staffel") || l.contains("folge") || l.contains("kapitel") || l.contains("band") { return true }

        // Progress patterns
        if l.contains(" ep ") || l.contains("episode") || l.contains("chapter") || l.contains(" vol") { return true }
        if l.range(of: #"s\d{1,2}\s*e\d{1,4}"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"\b\d{1,2}\s*x\s*\d{1,4}\b"#, options: .regularExpression) != nil { return true }

        // Comma-separated lists are common for vibes ("funny, not childish") so only treat commas
        // as import if we have multiple title-like segments.
        if t.contains(",") {
            let parts = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count >= 2 {
                let titleLikeCount = parts.filter { segmentLooksTitleLike($0) }.count
                if titleLikeCount >= 2 { return true }
            }
        }

        // Short prompts like "funny anime" shouldn't be treated as import.
        if t.count <= 28 { return false }
        return false
    }

    private func segmentLooksTitleLike(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return false }
        let l = t.lowercased()

        // Natural language / vibe words are not titles.
        let vibeMarkers = ["something", "funny", "sad", "cozy", "vibe", "recommend", "suggest", "like", "but", "not", "please", "anime", "manga"]
        if vibeMarkers.contains(where: { l.contains($0) }) && t.split(separator: " ").count <= 6 {
            return false
        }

        // Strong title hints.
        if t.contains("(") || t.contains(")") { return true }
        if t.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"\b(ep|episode|ch|chapter|vol|volume|s\d+e\d+|\d+x\d+)\b"#, options: .regularExpression) != nil { return true }

        // Heuristic: multiple words + some uppercase characters.
        let words = t.split(separator: " ")
        if words.count >= 2 && t.range(of: #"[A-Z]"#, options: .regularExpression) != nil {
            return true
        }

        // If user pasted lowercased titles, allow "two+ words" as a weak signal.
        if words.count >= 3 { return true }

        return false
    }

    private struct AutoResolveResult {
        let itemsToApply: [[String: Any]]
        let remaining: [SupabaseService.ConciergeParseItem]
        let appliedSummaryLines: [String]
    }

    private func autoResolveForApply(items: [SupabaseService.ConciergeParseItem]) -> AutoResolveResult {
        var toApply: [[String: Any]] = []
        var remaining: [SupabaseService.ConciergeParseItem] = []
        var appliedSummaryLines: [String] = []

        for item in items {
            if !(item.candidateError?.isEmpty ?? true) { remaining.append(item); continue }
            guard let top = item.candidates.first else { remaining.append(item); continue }
            let secondScore = item.candidates.dropFirst().first?.score ?? 0

            // Confidence rules: high similarity and not too ambiguous.
            let margin = top.score - secondScore
            // Auto-apply must be extremely safe. We trade friction for avoiding wrong saves.
            // Score-only thresholds are not enough for ambiguous short titles; add a title plausibility gate.
            let confident =
                (top.score >= 1.10 && margin >= 0.10) ||
                (top.score >= 1.00 && margin >= 0.22)
            let titleSafe = isTitleAutoApplySafe(normalized: item.normalized, parsed: item.parsed, candidateTitle: top.title_raw)
            if !confident || !titleSafe { remaining.append(item); continue }

            let status = normalizedStatus(for: item.parsed.status, mediaType: top.media_type)
            var payload: [String: Any] = [
                "raw": item.raw,
                "mediaType": top.media_type.uppercased(),
                "mediaId": top.media_id,
                "status": status,
                "confidence": top.score,
                "candidates": item.candidates.map { cand in
                    [
                        "media_type": cand.media_type,
                        "media_id": cand.media_id,
                        "variant_type": cand.variant_type,
                        "title_raw": cand.title_raw,
                        "score": cand.score,
                    ]
                },
            ]

            if let p = item.parsed.progressEpisodes { payload["progressEpisodes"] = p }
            if let p = item.parsed.progressChapters { payload["progressChapters"] = p }
            if let p = item.parsed.progressVolumes { payload["progressVolumes"] = p }
            if let s = item.parsed.seasonNumber { payload["seasonNumber"] = s }
            if let e = item.parsed.episodeInSeason { payload["episodeInSeason"] = e }
            if let b = item.parsed.caughtUp { payload["caughtUp"] = b }
            if let b = item.parsed.lastEpisode { payload["lastEpisode"] = b }
            if let b = item.parsed.completed { payload["completed"] = b }

            toApply.append(payload)

            appliedSummaryLines.append(summaryLineForAppliedItem(title: top.title_raw, mediaType: top.media_type, status: status, parsed: item.parsed))
        }

        return AutoResolveResult(itemsToApply: toApply, remaining: remaining, appliedSummaryLines: appliedSummaryLines)
    }

    private func isTitleAutoApplySafe(
        normalized: String,
        parsed: SupabaseService.ConciergeParseItemParsed,
        candidateTitle: String
    ) -> Bool {
        func tokens(_ s: String) -> [String] {
            let stop: Set<String> = [
                // EN
                "the", "a", "an", "of", "and", "or", "to", "in", "on", "for", "with",
                // DE
                "der", "die", "das", "ein", "eine", "einer", "eines", "und", "oder", "zu", "im", "in", "am", "auf", "mit",
            ]
            let cleaned = s
                .lowercased()
                .replacingOccurrences(of: #"[^\\p{L}\\p{N}\\s]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cleaned.split(separator: " ").map(String.init)
            return parts.filter { !$0.isEmpty && !stop.contains($0) }
        }

        let q = tokens(normalized)
        let c = tokens(candidateTitle)
        guard !q.isEmpty, !c.isEmpty else { return false }

        // Single-token titles are the most ambiguous (e.g. Naruto vs Naruto Shippuden).
        // Only auto-apply if the candidate is also single-token and exact.
        // If the user also mentioned a season number, force disambiguation instead of guessing.
        if q.count == 1 {
            if let season = parsed.seasonNumber, season >= 2 { return false }
            return c.count == 1 && c[0] == q[0]
        }

        let qSet = Set(q)
        let cSet = Set(c)
        let overlap = Double(qSet.intersection(cSet).count) / Double(qSet.count)

        // Require that most query tokens appear in the chosen title.
        if overlap < 0.75 { return false }

        // Avoid auto-apply to long variants when the user gave a short base title.
        if c.count - q.count >= 4 { return false }

        return true
    }

    private func summaryLineForAppliedItem(
        title: String,
        mediaType: String,
        status: String,
        parsed: SupabaseService.ConciergeParseItemParsed
    ) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = status.uppercased()

        let verb: String
        switch s {
        case "COMPLETED": verb = "Completed"
        case "WATCHING": verb = "Watching"
        case "READING": verb = "Reading"
        case "PLANNING": verb = "Planned"
        case "DROPPED": verb = "Dropped"
        case "PAUSED": verb = "Paused"
        default: verb = s.capitalized
        }

        if mediaType.uppercased() == "ANIME" {
            if let season = parsed.seasonNumber, let ep = parsed.episodeInSeason {
                return "\(cleanTitle) — \(verb) (S\(season)E\(ep))"
            }
            if let ep = parsed.progressEpisodes {
                return "\(cleanTitle) — \(verb) (Ep \(ep))"
            }
            return "\(cleanTitle) — \(verb)"
        } else {
            if let ch = parsed.progressChapters {
                return "\(cleanTitle) — \(verb) (Ch \(ch))"
            }
            if let vol = parsed.progressVolumes {
                return "\(cleanTitle) — \(verb) (Vol \(vol))"
            }
            return "\(cleanTitle) — \(verb)"
        }
    }

    private var activeItems: [SupabaseService.ConciergeParseItem]? {
        messages.last(where: { $0.role == .assistant && ($0.items?.isEmpty == false) })?.items
    }

    private var activeSelectedCount: Int {
        guard let items = activeItems else { return 0 }
        return items.reduce(0) { acc, item in
            acc + (selectedByItemId[item.id] != nil ? 1 : 0)
        }
    }

    private func normalizedStatus(for raw: String?, mediaType: String) -> String {
        let s = (raw ?? "").uppercased()
        if mediaType == "MANGA", s == "WATCHING" { return "READING" }
        if mediaType == "ANIME", s == "READING" { return "WATCHING" }
        if s.isEmpty { return "PLANNING" }
        return s
    }

    private func applyActiveItems() async {
        guard let items = activeItems else { return }
        let chosen = items.compactMap { item -> [String: Any]? in
            guard let c = selectedByItemId[item.id] else { return nil }
            let status = normalizedStatus(for: item.parsed.status, mediaType: c.media_type)
            var payload: [String: Any] = [
                "raw": item.raw,
                "mediaType": c.media_type,
                "mediaId": c.media_id,
                "status": status,
                "confidence": c.score,
                "candidates": item.candidates.map { cand in
                    [
                        "media_type": cand.media_type,
                        "media_id": cand.media_id,
                        "variant_type": cand.variant_type,
                        "title_raw": cand.title_raw,
                        "score": cand.score,
                    ]
                },
            ]
            if let p = item.parsed.progressEpisodes { payload["progressEpisodes"] = p }
            if let p = item.parsed.progressChapters { payload["progressChapters"] = p }
            if let p = item.parsed.progressVolumes { payload["progressVolumes"] = p }
            if let s = item.parsed.seasonNumber { payload["seasonNumber"] = s }
            if let e = item.parsed.episodeInSeason { payload["episodeInSeason"] = e }
            if let b = item.parsed.caughtUp { payload["caughtUp"] = b }
            if let b = item.parsed.lastEpisode { payload["lastEpisode"] = b }
            if let b = item.parsed.completed { payload["completed"] = b }
            return payload
        }

        guard !chosen.isEmpty else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            let summaryLines: [String] = items.compactMap { item in
                guard let c = selectedByItemId[item.id] else { return nil }
                let status = normalizedStatus(for: item.parsed.status, mediaType: c.media_type)
                return summaryLineForAppliedItem(title: c.title_raw, mediaType: c.media_type, status: status, parsed: item.parsed)
            }

            let res = try await supabaseService.conciergeApply(items: chosen)
            if let sessionId = res.sessionId { lastApplySessionId = sessionId }
            await supabaseService.fetchUserLists()
            await supabaseService.fetchCollectionItems()
            await supabaseService.fetchCollectionFeed(status: nil)
            let details = summaryLines.isEmpty ? "" : ("\n" + summaryLines.prefix(8).map { "• \($0)" }.joined(separator: "\n"))
            messages.append(
                ConciergeMessage(
                    role: .assistant,
                    text: res.success
                        ? "Saved.\(details)"
                        : "Applied with errors. You can try again or undo the last batch.",
                    items: nil
                )
            )
            if res.success {
                let n = chosen.count
                showToast(
                    .init(
                        kind: .success,
                        title: "Saved \(n) item\(n == 1 ? "" : "s")",
                        subtitle: lastApplySessionId == nil ? nil : "You can undo the batch.",
                        actionTitle: lastApplySessionId == nil ? nil : "Undo",
                        onAction: lastApplySessionId == nil ? nil : { Task { await undoLastApply() } }
                    ),
                    autoDismissSeconds: lastApplySessionId == nil ? 2.0 : 4.5
                )
            } else {
                showToast(.init(kind: .error, title: "Applied with issues", subtitle: "Try again or undo.", actionTitle: nil, onAction: nil))
            }
        } catch {
            errorText = "Apply failed: \(error.localizedDescription)"
            showToast(.init(kind: .error, title: "Apply failed", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil))
        }
    }

    private func undoLastApply() async {
        guard let sessionId = lastApplySessionId else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            let res = try await supabaseService.conciergeUndo(sessionId: sessionId)
            await supabaseService.fetchUserLists()
            await supabaseService.fetchCollectionItems()
            await supabaseService.fetchCollectionFeed(status: nil)
            lastApplySessionId = nil
            messages.append(
                ConciergeMessage(
                    role: .assistant,
                    text: res.success ? "Undid last batch." : "Undo failed. Try again.",
                    items: nil
                )
            )
            showToast(.init(kind: res.success ? .success : .error, title: res.success ? "Undid last batch" : "Undo failed", subtitle: nil, actionTitle: nil, onAction: nil))
        } catch {
            errorText = "Undo failed: \(error.localizedDescription)"
            showToast(.init(kind: .error, title: "Undo failed", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil))
        }
    }

    private func openRecommendation(_ item: SupabaseService.ConciergeRecommendResponse.Item) async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            if item.mediaType.uppercased() == "ANIME" {
                let anime = try await supabaseService.fetchAnimeById(item.mediaId)
                guard let anime else {
                    errorText = "Couldn’t find that anime in the database."
                    return
                }
                selectedAnime = anime
            } else {
                let manga = try await supabaseService.fetchMangaById(item.mediaId)
                guard let manga else {
                    errorText = "Couldn’t find that manga in the database."
                    return
                }
                selectedManga = manga
            }
        } catch {
            errorText = "Couldn’t open: \(error.localizedDescription)"
        }
    }

    private func quickSaveRecommendation(_ item: SupabaseService.ConciergeRecommendResponse.Item) async {
        let mediaType = item.mediaType.uppercased() == "ANIME" ? "anime" : "manga"
        await supabaseService.upsertUserListEntry(
            mediaId: item.mediaId,
            mediaType: mediaType,
            status: .planning,
            progress: 0,
            rating: nil,
            notes: nil
        )
        showToast(.init(kind: .success, title: "Added to Planning", subtitle: item.title, actionTitle: nil, onAction: nil))
    }

    @MainActor
    private func showToast(_ next: KuroToastState, autoDismissSeconds: Double = 2.5) {
        toastDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            toast = next
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0.8, autoDismissSeconds) * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toast = nil
                }
            }
        }
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        guard let t = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty
        else {
            showToast(.init(kind: .info, title: "Clipboard is empty", subtitle: "Copy a list of titles, then tap Paste.", actionTitle: nil, onAction: nil))
            return
        }
        input = t
        inputFocused = true
        KuroAccessibility.impactHaptic(.light)
        #endif
    }

    private func seedExampleImport() {
        input = """
        Attack on Titan (completed)
        Jujutsu Kaisen up to ep 12
        Hunter x Hunter (2011)
        """
        inputFocused = true
        KuroAccessibility.impactHaptic(.light)
    }

    private func seedExampleVibe() {
        input = "Something funny, premium, not childish."
        inputFocused = true
        KuroAccessibility.impactHaptic(.light)
    }
}

private struct ConciergeBubble: View {
    let message: ConciergeMessage
    let selected: (SupabaseService.ConciergeParseItem) -> SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeParseItem, SupabaseService.ConciergeCandidate) -> Void
    let onOpenRecommendation: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onQuickSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    @State private var hiddenRecommendationIds: Set<String> = []
    @State private var stepIndex: Int = 0

    private func glassBubble<Content: View>(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.72), Color.white.opacity(0.18), Color.black.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 10)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if message.role == .user {
                Text(message.text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.92))
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                glassBubble(cornerRadius: 18) {
                    Text(message.text)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.black.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let items = message.items, !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.raw)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black)
                                Spacer()
                                if let hint = item.parsed.mediaTypeHint {
                                    Text(hint)
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(1.0)
                                        .foregroundColor(.black.opacity(0.45))
                                }
                            }

                            if !item.candidates.isEmpty {
                                let top = item.candidates.prefix(5)
                                let picked = selected(item)
                                ForEach(Array(top.enumerated()), id: \.offset) { _, c in
                                    Button(action: { onSelect(item, c) }) {
                                        HStack(spacing: 10) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(c.title_raw)
                                                    .font(.system(size: 13, weight: .regular))
                                                    .foregroundColor(.black.opacity(0.85))
                                                    .lineLimit(1)
                                                Text("\(c.media_type) • \(String(format: "%.2f", c.score))")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .tracking(1.0)
                                                    .foregroundColor(.black.opacity(0.35))
                                            }
                                            Spacer()
                                            Image(systemName: picked == c ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 16, weight: .regular))
                                                .foregroundColor(picked == c ? .black : .black.opacity(0.2))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(picked == c ? Color.black.opacity(0.06) : Color.black.opacity(0.03))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else if let err = item.candidateError, !err.isEmpty {
                                Text("No candidates (missing title_search/search_titles?)")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.black.opacity(0.5))
                            } else {
                                Text("No candidates")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.black.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.03))
                        )
                    }
                }
            }

            if let cats = message.recommendationCategories, !cats.isEmpty,
               ((message.recommendationSets ?? []).isEmpty == false || (message.recommendations ?? []).isEmpty == false) {
                ConciergeCategoryPills(categories: cats)
            }

            if let sets = message.recommendationSets, !sets.isEmpty {
                ConciergeRecommendationSetsDeck(
                    sets: sets,
                    hiddenIds: $hiddenRecommendationIds,
                    onOpen: onOpenRecommendation,
                    onSave: onQuickSave
                )
            } else if let recs = message.recommendations, !recs.isEmpty {
                ConciergeRecommendationDeck(
                    items: recs,
                    hiddenIds: $hiddenRecommendationIds,
                    onOpen: onOpenRecommendation,
                    onSave: onQuickSave
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct ConciergeCategoryPills: View {
    let categories: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { c in
                    Text(c.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.3)
                        .foregroundColor(.black.opacity(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.05))
                        )
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 26)
        .kuroSwipeExclusionZone()
    }
}

private struct ConciergeRecommendationDeck: View {
    let items: [SupabaseService.ConciergeRecommendResponse.Item]
    @Binding var hiddenIds: Set<String>
    let onOpen: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void

    private var visible: [SupabaseService.ConciergeRecommendResponse.Item] {
        items.filter { !hiddenIds.contains($0.id) }
    }

    private var classics: [SupabaseService.ConciergeRecommendResponse.Item] {
        visible.filter { ($0.signals ?? []).map { $0.uppercased() }.contains("CLASSIC") }
    }
    private var picks: [SupabaseService.ConciergeRecommendResponse.Item] {
        let classicIds = Set(classics.map { $0.id })
        return visible.filter { !classicIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if picks.isEmpty && classics.isEmpty {
                Text("Nothing else in this set — try a different vibe.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.black.opacity(0.5))
            } else {
                if !picks.isEmpty {
                    ConciergeRecommendationRail(
                        title: "PICKS",
                        items: picks,
                        hiddenIds: $hiddenIds,
                        onOpen: onOpen,
                        onSave: onSave
                    )
                }
                if !classics.isEmpty {
                    ConciergeRecommendationRail(
                        title: "CLASSICS",
                        items: classics,
                        hiddenIds: $hiddenIds,
                        onOpen: onOpen,
                        onSave: onSave
                    )
                }
            }
        }
    }
}

private struct ConciergeRecommendationSetsDeck: View {
    let sets: [SupabaseService.ConciergeRecommendResponse.Set]
    @Binding var hiddenIds: Set<String>
    let onOpen: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sets) { set in
                let items = set.items ?? []
                if !items.isEmpty {
                    ConciergeRecommendationRail(
                        title: set.title.uppercased(),
                        items: items,
                        hiddenIds: $hiddenIds,
                        onOpen: onOpen,
                        onSave: onSave
                    )
                }
            }
        }
    }
}

private struct ConciergeRecommendationRail: View {
    let title: String
    let items: [SupabaseService.ConciergeRecommendResponse.Item]
    @Binding var hiddenIds: Set<String>
    let onOpen: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void

    private var visible: [SupabaseService.ConciergeRecommendResponse.Item] {
        items.filter { !hiddenIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.black.opacity(0.55))
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(visible) { item in
                        ConciergeRecommendationCompactCard(
                            item: item,
                            onOpen: { onOpen(item) },
                            onSave: {
                                onSave(item)
                                hiddenIds.insert(item.id)
                            },
                            onSkip: {
                                KuroAccessibility.impactHaptic(.light)
                                hiddenIds.insert(item.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
            .kuroSwipeExclusionZone()
        }
    }
}

private struct ConciergeRecommendationCompactCard: View {
    let item: SupabaseService.ConciergeRecommendResponse.Item
    let onOpen: () -> Void
    let onSave: () -> Void
    let onSkip: () -> Void

    private let width: CGFloat = 176
    private var height: CGFloat { width / 0.72 }

    private var displayScore: Double? {
        guard let s = item.averageScore else { return nil }
        return Double(s) / 10.0
    }

    private var badges: [String] {
        var out: [String] = []
        if let s = item.averageScore, s >= 88 { out.append("MASTERPIECE") }
        else if let y = item.year, y > 0 && y <= 2010, (item.averageScore ?? 0) >= 80 { out.append("CLASSIC") }
        if (item.matchCount ?? 0) >= 2 { out.append("MATCH") }
        return out
    }

    private var signals: [String] {
        let raw = (item.signals ?? []).map { $0.uppercased() }
        // De-dup and keep tight.
        var seen: Set<String> = []
        var out: [String] = []
        for s in (badges + raw) {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty { continue }
            if seen.contains(v) { continue }
            seen.insert(v)
            out.append(v)
            if out.count >= 4 { break }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                onOpen()
            }) {
                ZStack(alignment: .topTrailing) {
                    KuroCachedAsyncImage(url: URL(string: item.coverImageMedium ?? ""), maxPixelSize: 220) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: width, height: height)
                                .clipped()
                        case .failure, .empty:
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                                .frame(width: width, height: height)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let s = displayScore, s > 0 {
                        KuroScoreBadge(score: s)
                            .padding(8)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.92))
                    .lineLimit(2)
                    .frame(height: 34, alignment: .top)

                HStack(spacing: 6) {
                    if let y = item.year { Text(String(y)) }
                    if let f = item.format, !f.isEmpty {
                        if item.year != nil { Text("·") }
                        Text(f)
                    }
                }
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.black.opacity(0.55))
                .frame(height: 14, alignment: .topLeading)

                if let blurb = item.blurb, !blurb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(blurb)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.black.opacity(0.62))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button(action: onSkip) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black.opacity(0.55))
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.03))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onSave) {
                        HStack(spacing: 8) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("SAVE")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.4)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.90))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint("Recommendation. Save or open details.")
    }
}

private struct ConciergeActionBar: View {
    let selectedCount: Int
    let hasAnySelection: Bool
    let canUndo: Bool
    let onApply: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onUndo) {
                Text("UNDO")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(canUndo ? .black : .black.opacity(0.25))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(canUndo ? 0.04 : 0.02))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)

            Spacer()

            Button(action: onApply) {
                HStack(spacing: 8) {
                    Text("APPLY")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                    Text("\(selectedCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.0)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hasAnySelection ? Color.black : Color.black.opacity(0.2))
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasAnySelection)
        }
    }
}

private struct ConciergeTypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Circle().fill(Color.black.opacity(0.25)).frame(width: 6, height: 6).opacity(phase == 0 ? 1 : 0.35)
                    .scaleEffect(phase == 0 ? 1.15 : 0.95)
                Circle().fill(Color.black.opacity(0.25)).frame(width: 6, height: 6).opacity(phase == 1 ? 1 : 0.35)
                    .scaleEffect(phase == 1 ? 1.15 : 0.95)
                Circle().fill(Color.black.opacity(0.25)).frame(width: 6, height: 6).opacity(phase == 2 ? 1 : 0.35)
                    .scaleEffect(phase == 2 ? 1.15 : 0.95)
            }
            Text("Thinking")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.black.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.72), Color.white.opacity(0.18), Color.black.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 10)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 220_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

private struct ConciergeIntroCard: View {
    var body: some View {
        KuroGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    KuroConciergeMark(size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONCIERGE")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(2.0)
                            .foregroundColor(.black.opacity(0.80))
                        Text("Imports + recommendations")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.black.opacity(0.55))
                    }

                    Spacer(minLength: 0)
                }

                Text("Paste titles to import, or describe the mood.\nDefaults are clean — no adult content.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black.opacity(0.62))
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Concierge. Paste titles to import, or ask for a vibe.")
    }
}

private struct ConciergeStarterActions: View {
    let onPaste: () -> Void
    let onExampleImport: () -> Void
    let onExampleVibe: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KuroGlassPill(
                title: "Paste from clipboard",
                subtitle: "Fast import",
                systemImage: "doc.on.clipboard",
                action: onPaste
            )
            .offset(y: appeared ? 0 : 6)
            .opacity(appeared ? 1 : 0)

            KuroGlassPill(
                title: "Try an import example",
                subtitle: "Shows the format",
                systemImage: "text.append",
                action: onExampleImport
            )
            .offset(y: appeared ? 0 : 10)
            .opacity(appeared ? 1 : 0)

            KuroGlassPill(
                title: "Give me a vibe",
                subtitle: "Recommendations",
                systemImage: "sparkles",
                action: onExampleVibe
            )
            .offset(y: appeared ? 0 : 14)
            .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) {
                appeared = true
            }
        }
    }
}

private struct KuroConciergeAssistant: View {
    @Binding var expanded: Bool
    @Binding var offset: CGSize
    @Binding var dragStart: CGSize
    let baseBottomPadding: CGFloat
    let containerSize: CGSize
    let onTapMascot: () -> Void

    @Namespace private var mascotNS
    @State private var pulse: Bool = false

    private let panelWidth: CGFloat = 316
    private let panelHeight: CGFloat = 148

    var body: some View {
        let clamped = clamp(offset: offset)

        VStack(spacing: 0) {
            if expanded {
                KuroGlassCard(cornerRadius: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            KuroConciergeMark(size: 34)
                                .matchedGeometryEffect(id: "kurochan", in: mascotNS)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("CONCIERGE")
                                    .font(.system(size: 12, weight: .semibold))
                                    .tracking(2.0)
                                    .foregroundColor(.black.opacity(0.78))
                                Text("Imports + recommendations")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.black.opacity(0.55))
                            }
                            Spacer(minLength: 0)

                            Button(action: { withAnimation(.easeInOut(duration: 0.18)) { expanded = false } }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.55))
                                    .frame(width: 34, height: 34)
                                    .background(
                                        Circle().fill(Color.white.opacity(0.35))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Paste a list to import, or ask for a vibe.\nClean results by default — no adult content.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.black.opacity(0.62))

                        Button(action: {
                            KuroAccessibility.impactHaptic(.light)
                            onTapMascot()
                        }) {
                            HStack(spacing: 10) {
                                Text("START CHAT")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1.8)
                                    .foregroundColor(.black.opacity(0.82))
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.42))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.32))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 0.8))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
                }
                .overlay(alignment: .topTrailing) {
                    // Subtle sheen that makes the glass feel premium.
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 180, height: 140)
                    .rotationEffect(.degrees(-20))
                    .offset(x: 40, y: -30)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                }
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            offset = CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            let next = clamp(offset: offset)
                            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.86)) {
                                offset = next
                            }
                            dragStart = next
                        }
                )
            } else {
                Button(action: {
                    withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.86)) { expanded = true }
                }) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.9)
                            )
                            .frame(width: 56, height: 56)

                        Circle()
                            .strokeBorder(Color.white.opacity(pulse ? 0.65 : 0.25), lineWidth: 1.1)
                            .frame(width: 56, height: 56)
                            .scaleEffect(pulse ? 1.08 : 0.96)
                            .opacity(pulse ? 1.0 : 0.0)
                            .allowsHitTesting(false)

                        KuroConciergeMark(size: 24)
                            .matchedGeometryEffect(id: "kurochan", in: mascotNS)
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            offset = CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            let next = clamp(offset: offset)
                            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.86)) {
                                offset = next
                            }
                            dragStart = next
                        }
                )
            }
        }
        .padding(.leading, 16)
        .padding(.bottom, baseBottomPadding)
        .offset(clamped)
        .onAppear {
            // Ensure a sensible initial position.
            if dragStart == .zero, offset == .zero {
                dragStart = .zero
                offset = .zero
            }

            // Soft pulse so the orb feels "alive".
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func clamp(offset: CGSize) -> CGSize {
        // Relative to bottom-leading with padding already applied.
        // Allow dragging right/up, but not off-screen.
        let maxRight = max(0, containerSize.width - (panelWidth + 32))
        let minX: CGFloat = 0
        let maxX: CGFloat = maxRight

        // Allow moving up roughly 70% of the screen; don't allow dragging below the base anchor.
        let minY: CGFloat = -max(120, containerSize.height * 0.70)
        let maxY: CGFloat = 0

        return CGSize(
            width: min(maxX, max(minX, offset.width)),
            height: min(maxY, max(minY, offset.height))
        )
	    }
	}

	struct ConciergeMessage: Identifiable {
	    enum Role { case user, assistant }
	    let id = UUID()
    let role: Role
    let text: String
    let items: [SupabaseService.ConciergeParseItem]?
    let recommendations: [SupabaseService.ConciergeRecommendResponse.Item]?
    let recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]?
    let recommendationCategories: [String]?

    init(
        role: Role,
        text: String,
        items: [SupabaseService.ConciergeParseItem]? = nil,
        recommendations: [SupabaseService.ConciergeRecommendResponse.Item]? = nil,
        recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]? = nil,
        recommendationCategories: [String]? = nil
    ) {
        self.role = role
        self.text = text
        self.items = items
        self.recommendations = recommendations
        self.recommendationSets = recommendationSets
        self.recommendationCategories = recommendationCategories
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isEmpty
        }
    }
}

```

### Edge Function: concierge-parse (deterministic parsing)

- Path: `supabase/functions/concierge-parse/index.ts`


```ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MediaType = "ANIME" | "MANGA";
type ListStatus = "WATCHING" | "READING" | "PLANNING" | "COMPLETED" | "DROPPED" | "PAUSED";

type ParsedItem = {
  raw: string;
  normalized: string;
  mediaTypeHint?: MediaType;
  status?: ListStatus;
  progressEpisodes?: number;
  progressChapters?: number;
  progressVolumes?: number;
  seasonNumber?: number;
  episodeInSeason?: number;
  caughtUp?: boolean;
  lastEpisode?: boolean;
  completed?: boolean;
};

function romanToInt(input: string): number | null {
  const s = String(input ?? "").trim().toUpperCase();
  if (!s) return null;
  // Keep this conservative: only accept typical roman numerals up to 40-ish.
  if (!/^[IVXLCDM]{1,6}$/.test(s)) return null;

  const map: Record<string, number> = { I: 1, V: 5, X: 10, L: 50, C: 100, D: 500, M: 1000 };
  let total = 0;
  let prev = 0;
  for (let i = s.length - 1; i >= 0; i--) {
    const v = map[s[i]];
    if (!v) return null;
    if (v < prev) total -= v;
    else total += v;
    prev = v;
  }
  if (total < 1 || total > 40) return null;
  return total;
}

function expandCommonAbbreviations(title: string): string | null {
  const raw = String(title ?? "").trim();
  if (!raw) return null;

  // Normalize to a compact key for exact-match abbreviations (e.g. "FMA:B" -> "fmab").
  const compact = raw.toLowerCase().replace(/[^a-z0-9]+/g, "");
  const map: Record<string, string> = {
    aot: "Attack on Titan",
    snk: "Attack on Titan", // Shingeki no Kyojin (common abbreviation)
    jjk: "Jujutsu Kaisen",
    mha: "My Hero Academia",
    hxh: "Hunter x Hunter",
    fmab: "Fullmetal Alchemist: Brotherhood",
    fma: "Fullmetal Alchemist",
    opm: "One Punch Man",
    csm: "Chainsaw Man",
    jjba: "JoJo's Bizarre Adventure",
    kny: "Demon Slayer: Kimetsu no Yaiba",
  };

  // Only expand when we have a known mapping. Avoid risky short acronyms like "DS".
  if (map[compact] && map[compact] !== raw) return map[compact];

  // If the abbreviation is the first token in a longer query, expand it too.
  const parts = raw.split(/\s+/g);
  if (parts.length >= 2) {
    const head = parts[0].toLowerCase().replace(/[^a-z0-9]+/g, "");
    const expanded = map[head];
    if (expanded) return [expanded, ...parts.slice(1)].join(" ");
  }

  return null;
}

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function normalizeLine(s: string) {
  return s
    .trim()
    .replace(/\u00A0/g, " ")
    .replace(/\s+/g, " ");
}

function normalizeAliasKey(raw: string): string {
  let s = String(raw ?? "").toLowerCase();
  s = s.replace(/\u00a0/g, " ");
  // strip filler + verbs/status
  s = s.replace(/\b(um+|uh+|erm+|eh+|like|also|äh+|ae+h+|so|halt)\b/giu, " ");
  s = s.replace(/\b(i\s+have|i'?m|im|i\s+am|i)\b/giu, " ");
  s = s.replace(/\b(ich\s+habe|ich\s+hab|ich|bin)\b/giu, " ");
  s = s.replace(
    /\b(watched|watching|finished|completed|dropped|paused|planning|read|reading|caught up|up to date|seen|saw)\b/giu,
    " ",
  );
  s = s.replace(
    /\b(geschaut|gesehen|gelesen|fertig|abgeschlossen|beendet|abgebrochen|pausiert|geplant|aktuell|komplett|vollständig|vollstaendig)\b/giu,
    " ",
  );
  // strip progress markers
  s = s.replace(/\b(?:season|staffel|episode|ep|folge|chapter|ch|kapitel|volume|vol|band)\b/giu, " ");
  s = s.replace(/\b\d{1,2}\s*x\s*\d{1,4}\b/giu, " ");
  s = s.replace(/\bs\d{1,2}\s*e\d{1,4}\b/giu, " ");
  // keep only letters/numbers/spaces (unicode)
  s = s.replace(/[^\p{L}\p{N}\s]+/gu, " ");
  s = s.replace(/\s+/g, " ").trim();
  return s.slice(0, 160);
}

function splitItems(text: string): string[] {
  const normalized = text.replace(/\r\n/g, "\n").trim();
  if (!normalized) return [];

  const splitOnClauseBoundaries = (s: string) =>
    s
      .split(/[\n]+|(?<=[.!?;])\s+/g)
      .flatMap((part) => part.split(/,\s*(?=(?:i\s+|i'?m\s+|i\s+am\s+|ich\s+))/i))
      .map((x) => x.trim())
      .filter(Boolean);

  const splitTitleList = (tail: string) =>
    tail
      .split(/\s*(?:,|;|\bund\b|\band\b|&|\u2022)\s*/i)
      .map((x) => x.trim())
      .filter(Boolean);

  const englishVerbRe =
    /^(?<verb>(?:i\s+(?:(?:just|recently|only)\s+)?(?:watched|finished|completed|dropped|paused|started|read)|i\s+have\s+(?:watched|seen|read)|i\s+am\s+(?:watching|reading)|i'?m\s+(?:watching|reading)|im\s+(?:watching|reading)|watching|reading))\s+(?<tail>.+)$/i;
  const germanPresentVerbRe =
    /^(?<verb>ich\s+(?:schaue|gucke|sehe|lese|bin)\b)\s+(?<tail>.+)$/i;
  const germanPerfectVerbRe =
    /^(?<head>ich\s+(?:habe|hab))\s+(?<tail>.+?)\s+(?<past>gesehen|geschaut|gelesen)\b/i;

  const clauses = splitOnClauseBoundaries(normalized);
  const out: string[] = [];

  for (const clause of clauses) {
    const parts = clause
      .split(/\b(?:and|und)\b\s+(?=(?:i\b|ich\b))/i)
      .map((x) => x.trim())
      .filter(Boolean);

    for (const part of parts) {
      const c = part.trim();
      if (!c) continue;

      const germanPerfect = c.match(germanPerfectVerbRe);
      if (germanPerfect?.groups?.tail && germanPerfect.groups?.head && germanPerfect.groups?.past) {
        const titles = splitTitleList(germanPerfect.groups.tail);
        for (const t of titles) {
          if (!t) continue;
          out.push(`${germanPerfect.groups.head} ${t} ${germanPerfect.groups.past}`.trim());
        }
        continue;
      }

      const english = c.match(englishVerbRe);
      if (english?.groups?.verb && english.groups?.tail) {
        // If the tail includes another clause ("... and I ..."), split that part out first.
        const tailParts = english.groups.tail
          .split(/\b(?:and|und)\b\s+(?=(?:i\b|ich\b))/i)
          .map((x) => x.trim())
          .filter(Boolean);

        const firstTail = tailParts[0] ?? "";
        const titles = splitTitleList(firstTail);
        for (const t of titles) {
          if (!t) continue;
          // If the chunk already begins with another verb clause, keep it as-is.
          if (englishVerbRe.test(t) || germanPresentVerbRe.test(t) || germanPerfectVerbRe.test(t)) out.push(t);
          else out.push(`${english.groups.verb} ${t}`.trim());
        }
        // Push remaining verb-clauses back into the pipeline.
        for (const extra of tailParts.slice(1)) out.push(extra);
        continue;
      }

      const germanPresent = c.match(germanPresentVerbRe);
      if (germanPresent?.groups?.verb && germanPresent.groups?.tail) {
        const tailParts = germanPresent.groups.tail
          .split(/\b(?:and|und)\b\s+(?=(?:i\b|ich\b))/i)
          .map((x) => x.trim())
          .filter(Boolean);
        const firstTail = tailParts[0] ?? "";

        const titles = splitTitleList(firstTail);
        for (const t of titles) {
          if (!t) continue;
          if (englishVerbRe.test(t) || germanPresentVerbRe.test(t) || germanPerfectVerbRe.test(t)) out.push(t);
          else out.push(`${germanPresent.groups.verb} ${t}`.trim());
        }
        for (const extra of tailParts.slice(1)) out.push(extra);
        continue;
      }

      // Fallback: treat as a plain title line (or a comma-separated list).
      if (c.includes(",") && c.length < 200) out.push(...c.split(",").map((x) => x.trim()).filter(Boolean));
      else out.push(c);
    }
  }

  return out.map((l) => l.replace(/^[\-\*\u2022]+\s*/, "").trim()).filter(Boolean);
}

function parseStatus(raw: string): { status?: ListStatus; completed?: boolean } {
  const s = raw.toLowerCase();
  const explicitCompletion =
    /\b(last episode|to the end|all of it|every season|fully|entirely|whole thing)\b/.test(s) ||
    /\b(bis zur letzten folge|bis zum ende|alles gesehen|komplett gesehen|vollständig|vollstaendig)\b/.test(s);
  const hasPartialProgress =
    /\b(?:until|till|up to|upto|to|bis)\b/.test(s) &&
    /\b(?:season|staffel|episode|ep|folge|chapter|ch|kapitel|band|vol|volume|\d{1,2}\s*x\s*\d{1,4}|s\d{1,2}\s*e\d{1,4})\b/.test(s);

  // English + slang
  if (/\b(caught up|up to date|up-to-date|latest|current)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(i\s+(?:just\s+)?watched|i\s+(?:just\s+)?finished|i\s+(?:just\s+)?completed|i\s+(?:just\s+)?saw|i\s+have\s+watched|i\s+have\s+seen)\b/.test(s)) {
    if (hasPartialProgress && !explicitCompletion) return { status: "WATCHING" };
    return { status: "COMPLETED", completed: true };
  }
  if (/\b(i\s+(?:just\s+)?read|i\s+have\s+read)\b/.test(s)) {
    if (hasPartialProgress && !explicitCompletion) return { status: "READING" };
    return { status: "COMPLETED", completed: true };
  }
  if (/\b(i'?m\s+watching|i\s+am\s+watching)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(i'?m\s+reading|i\s+am\s+reading)\b/.test(s)) return { status: "READING" };
  if (/\b(completed|finished|done)\b/.test(s)) return { status: "COMPLETED", completed: true };
  if (/\b(dropped)\b/.test(s)) return { status: "DROPPED" };
  if (/\b(paused|on hold|on-hold|hiatus)\b/.test(s)) return { status: "PAUSED" };
  if (/\b(planning|plan to watch|plan to read|ptw|ptr)\b/.test(s)) return { status: "PLANNING" };
  if (/\b(reading)\b/.test(s)) return { status: "READING" };
  if (/\b(watching)\b/.test(s)) return { status: "WATCHING" };

  // German
  if (/\b(aktuell|auf dem neuesten stand|up to date|auf dem aktuellen stand)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(ich\s+habe|ich\s+hab)\b/.test(s) && /\b(geschaut|gesehen|gelesen)\b/.test(s)) {
    if (hasPartialProgress) {
      if (/\b(gelesen)\b/.test(s)) return { status: "READING" };
      return { status: "WATCHING" };
    }
    return { status: "COMPLETED", completed: true };
  }
  if (/\b(ich\s+(?:schaue|gucke|sehe)|gerade\s+am\s+schauen|am\s+schauen)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(ich\s+lese|gerade\s+am\s+lesen|am\s+lesen)\b/.test(s)) return { status: "READING" };
  if (/\b(fertig|abgeschlossen|beendet|zu ende|komplett)\b/.test(s)) return { status: "COMPLETED", completed: true };
  if (/\b(abgebrochen|gedroppt|droppe|droppen)\b/.test(s)) return { status: "DROPPED" };
  if (/\b(pausiert|pause|auf eis)\b/.test(s)) return { status: "PAUSED" };
  if (/\b(plane|geplant|will schauen|will sehen|möchte schauen|möchte sehen)\b/.test(s)) return { status: "PLANNING" };
  if (/\b(lese|am lesen|gerade am lesen)\b/.test(s)) return { status: "READING" };
  if (/\b(schaue|gucke|sehe|am schauen|gerade am schauen)\b/.test(s)) return { status: "WATCHING" };
  return {};
}

function parseMagicFlags(raw: string): Pick<ParsedItem, "caughtUp" | "lastEpisode" | "completed"> {
  const s = raw.toLowerCase();
  const caughtUp =
    /\b(caught up|up to date|up-to-date|latest)\b/.test(s) ||
    /\b(auf dem neuesten stand|aktuell|up to date)\b/.test(s);

  const lastEpisode =
    /\b(last episode|to the end|all of it|every season|fully|entirely|whole thing)\b/.test(s) ||
    /\b(bis zur letzten folge|bis zum ende|alles gesehen|komplett gesehen|vollständig|ganz gesehen|komplett|vollstaendig)\b/.test(s);

  return {
    caughtUp: caughtUp || undefined,
    lastEpisode: lastEpisode || undefined,
    completed: lastEpisode || undefined,
  };
}

function parseProgress(
  raw: string,
): Pick<
  ParsedItem,
  "progressEpisodes" | "progressChapters" | "progressVolumes" | "seasonNumber" | "episodeInSeason"
> {
  let s = raw.toLowerCase();
  const out: any = {};

  // Normalize small number-words (EN/DE) so "season two episode five" works.
  const wordMap: Record<string, string> = {
    one: "1",
    two: "2",
    three: "3",
    four: "4",
    five: "5",
    six: "6",
    seven: "7",
    eight: "8",
    nine: "9",
    ten: "10",
    first: "1",
    second: "2",
    third: "3",
    fourth: "4",
    fifth: "5",
    sixth: "6",
    seventh: "7",
    eighth: "8",
    ninth: "9",
    tenth: "10",
    eins: "1",
    eine: "1",
    zwei: "2",
    drei: "3",
    vier: "4",
    fünf: "5",
    funf: "5",
    sechs: "6",
    sieben: "7",
    acht: "8",
    neun: "9",
    zehn: "10",
    erste: "1",
    zweite: "2",
    dritte: "3",
    vierte: "4",
    fünfte: "5",
    funfte: "5",
    sechste: "6",
    siebte: "7",
    achte: "8",
    neunte: "9",
    zehnte: "10",
  };
  s = s.replace(
    /\b(one|two|three|four|five|six|seven|eight|nine|ten|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eins|eine|zwei|drei|vier|fünf|funf|sechs|sieben|acht|neun|zehn|erste|zweite|dritte|vierte|fünfte|funfte|sechste|siebte|achte|neunte|zehnte)\b/g,
    (m) => wordMap[m] ?? m,
  );

  // Season/Episode formats:
  //  - S2E5, s02e05, 2x05
  //  - Season 2 Episode 5
  //  - Staffel 2 Folge 5
  //  - Season II Episode 5 / Staffel IV Folge 3
  const romanSeasonEp = s.match(
    /\b(?:season|staffel|part|cour)\s*([ivxlcdm]{1,6})\b(?:\s*[,.\- ]\s*)?(?:episode|ep|folge)\s*(\d{1,4})\b/,
  );
  if (romanSeasonEp) {
    const sn = romanToInt(romanSeasonEp[1]);
    if (sn != null) {
      out.seasonNumber = sn;
      out.episodeInSeason = parseInt(romanSeasonEp[2], 10);
      out.progressEpisodes = out.episodeInSeason;
    }
  }

  const sxe = s.match(/\bs(?:eason)?\s*(\d{1,2})\s*(?:e|ep|episode)?\s*(\d{1,4})\b/);
  const x = s.match(/\b(\d{1,2})\s*x\s*(\d{1,4})\b/);
  const seasonEp =
    s.match(/\b(?:season|staffel)\s*(\d{1,2})\b(?:\s*[,.\- ]\s*)?(?:episode|ep|folge)\s*(\d{1,4})\b/);
  const se = seasonEp ?? sxe ?? x;
  if (se && !out.seasonNumber) {
    out.seasonNumber = parseInt(se[1], 10);
    out.episodeInSeason = parseInt(se[2], 10);
    out.progressEpisodes = out.episodeInSeason;
  }

  const seasonOnly = s.match(/\b(?:season|staffel)\s*(\d{1,2})\b/);
  if (seasonOnly && !out.seasonNumber) out.seasonNumber = parseInt(seasonOnly[1], 10);

  const romanSeasonOnly = s.match(/\b(?:season|staffel|part|cour)\s*([ivxlcdm]{1,6})\b/);
  if (romanSeasonOnly && !out.seasonNumber) {
    const sn = romanToInt(romanSeasonOnly[1]);
    if (sn != null) out.seasonNumber = sn;
  }

  const ep = s.match(/\b(?:ep|episode)\s*(\d{1,4})\b/);
  if (ep) out.progressEpisodes = parseInt(ep[1], 10);
  const folge = s.match(/\b(?:folge)\s*(\d{1,4})\b/);
  if (folge) out.progressEpisodes = parseInt(folge[1], 10);

  const ch = s.match(/\b(?:ch|chapter)\s*(\d{1,5})\b/);
  if (ch) out.progressChapters = parseInt(ch[1], 10);
  const kap = s.match(/\b(?:kapitel)\s*(\d{1,5})\b/);
  if (kap) out.progressChapters = parseInt(kap[1], 10);

  const vol = s.match(/\b(?:vol|volume)\s*(\d{1,4})\b/);
  if (vol) out.progressVolumes = parseInt(vol[1], 10);
  const band = s.match(/\b(?:band)\s*(\d{1,4})\b/);
  if (band) out.progressVolumes = parseInt(band[1], 10);

  return out;
}

function mediaTypeHint(raw: string): MediaType | undefined {
  const s = raw.toLowerCase();
  // Explicit media words
  if (/\b(manga|manhwa|manhua)\b/.test(s)) return "MANGA";
  if (/\b(anime)\b/.test(s)) return "ANIME";

  // Verb hints (magic: "watched" => anime, "read" => manga)
  if (/\b(read|reading|i\s+read|i'?m\s+reading|im\s+reading|lese|gelesen|am\s+lesen)\b/.test(s)) return "MANGA";
  if (/\b(watched|watching|i\s+watched|i'?m\s+watching|im\s+watching|schaue|gucke|sehe|geschaut|gesehen|am\s+schauen)\b/.test(s)) return "ANIME";

  // Progress-unit hints
  if (/\b(volume|vol\.|band|chapter|ch\.|kapitel)\b/.test(s)) return "MANGA";
  if (/\b(episode|ep\.|folge|staffel)\b/.test(s)) return "ANIME";
  return undefined;
}

function stripMeta(raw: string): string {
  // remove parenthetical notes and common suffixes without nuking the title
  let s = raw;
  s = s.replace(/\((?:[^()]+)\)/g, " ");
  // Speech fillers (EN/DE)
  s = s.replace(/\b(um+|uh+|erm+|eh+|like|also|äh+|ae+h+|so|halt)\b/gi, " ");
  // Explicit completion phrases (keep as flags, remove from title query)
  s = s.replace(/\b(?:the\s+)?last\s+episode\b/gi, " ");
  s = s.replace(/\b(?:to\s+the\s+end|all\s+of\s+it|every\s+season)\b/gi, " ");
  s = s.replace(/\b(?:bis\s+(?:zur|zum)\s+letzten\s+folge|bis\s+zum\s+ende|zu\s+ende)\b/gi, " ");
  s = s.replace(/\b(until|till|bis)\b/gi, " ");
  s = s.replace(/\b(completed|finished|done|dropped|paused|planning|watching|reading|caught up|up to date)\b/gi, " ");
  s = s.replace(/\b(fully|entirely|whole\s+thing|whole|complete|completely)\b/gi, " ");
  s = s.replace(/\b(fertig|abgeschlossen|beendet|abgebrochen|pausiert|geplant|aktuell|auf dem neuesten stand|komplett)\b/gi, " ");
  s = s.replace(/\b(vollständig|vollstaendig|ganz)\b/gi, " ");
  s = s.replace(/\b(just|recently|only)\b/gi, " ");
  s = s.replace(/\b(watched|seen|saw|read)\b/gi, " ");
  s = s.replace(/\b(geschaut|gesehen|gelesen)\b/gi, " ");
  s = s.replace(/\b(all of|everything)\b/gi, " ");
  s = s.replace(/\b(alles)\b/gi, " ");
  // Remove leading chatty pronouns/aux verbs once we've stripped the meaningful verbs.
  s = s.replace(/^\s*i'?m\b\s*/i, " ");
  s = s.replace(/^\s*im\b\s*/i, " ");
  s = s.replace(/^\s*i\s+am\b\s*/i, " ");
  s = s.replace(/^\s*i\b\s*/i, " ");
  s = s.replace(/^\s*ich\b\s*(?:habe|hab)?\b\s*/i, " ");
  // Remove trailing progress phrases like "until the last episode" / "bis zur letzten Folge".
  s = s.replace(/\b(until|till|to)\b\s+(?:the\s+)?(?:last\s+episode|end)\b/gi, " ");
  s = s.replace(/\b(bis)\b\s+(?:zur|zum)\s+(?:letzten\s+folge|ende)\b/gi, " ");
  s = s.replace(/\b(?:season|staffel)\s*\d{1,2}\b/gi, " ");
  // Word-number season/episode (EN/DE): "season three", "staffel zwei", etc.
  s = s.replace(
    /\b(?:season|staffel)\s*(?:one|two|three|four|five|six|seven|eight|nine|ten|eins|eine|zwei|drei|vier|fünf|funf|sechs|sieben|acht|neun|zehn)\b/gi,
    " ",
  );
  s = s.replace(/\b(?:ep|episode|folge|ch|chapter|kapitel|vol|volume|band)\s*\d{1,5}\b/gi, " ");
  s = s.replace(
    /\b(?:ep|episode|folge|ch|chapter|kapitel|vol|volume|band)\s*(?:one|two|three|four|five|six|seven|eight|nine|ten|eins|eine|zwei|drei|vier|fünf|funf|sechs|sieben|acht|neun|zehn)\b/gi,
    " ",
  );
  s = s.replace(/\b\d{1,2}\s*x\s*\d{1,4}\b/gi, " ");
  s = s.replace(/\bs\d{1,2}\s*e\d{1,4}\b/gi, " ");
  s = s.replace(/\s+/g, " ").trim();
  return s;
}

function tokenOverlapBoost(query: string, title: string): number {
  const stop = new Set(["the", "a", "an", "of", "and", "or", "to", "in", "on", "at", "for"]);
  const q = query
    .toLowerCase()
    .replace(/[^a-z0-9äöüß\s]/gi, " ")
    .split(/\s+/g)
    .filter(Boolean);
  const t = title
    .toLowerCase()
    .replace(/[^a-z0-9äöüß\s]/gi, " ")
    .split(/\s+/g)
    .filter(Boolean);
  if (q.length === 0 || t.length === 0) return 0;

  const qSet = new Set(q.filter((w) => w.length >= 3 && !stop.has(w)));
  const tSet = new Set(t.filter((w) => w.length >= 3 && !stop.has(w)));

  let overlap = 0;
  for (const w of qSet) if (tSet.has(w)) overlap++;

  // Special case: titles like "My Hero Academia" often get dictated with "my ... academia".
  if (overlap >= 1 && q.includes("my") && t.includes("my")) overlap++;

  if (overlap >= 3) return 0.42;
  if (overlap === 2) return 0.34;
  if (overlap === 1) return 0.14;
  return 0;
}

function variantPenalty(query: string, candidate: { title_raw?: string; variant_type?: string }): number {
  const q = query.toLowerCase();
  const t = String(candidate?.title_raw ?? "").toLowerCase();
  const v = String(candidate?.variant_type ?? "").toLowerCase();

  // Penalize spin-offs/variants unless the user asked for them.
  const wantsOva = /\b(ova|special|movie|film|recap)\b/.test(q);
  if (!wantsOva && (/\b(ova|special|movie|film|recap)\b/.test(t) || /\b(ova|special|movie|film|recap)\b/.test(v))) {
    return 0.12;
  }

  // Collab/collection titles (often include ×) should never beat the main title.
  if (t.includes("×") || t.includes(" x ")) return 0.18;

  // Many movies/spinoffs have ":" subtitles. Penalize unless user explicitly typed a subtitle.
  if (!q.includes(":") && t.includes(":")) return 0.10;

  // Season-labeled variants should not beat the base title unless the user mentioned a season.
  const userMentionsSeason = /\b(season|staffel|s\d{1,2})\b/.test(q);
  if (!userMentionsSeason && /\bseason\b/.test(t) && (/\bfinal\b/.test(t) || /\b\d{1,2}\b/.test(t))) {
    return 0.10;
  }

  return 0;
}

function seasonMatchBoost(titleRaw: string, seasonNumber: number): number {
  const t = titleRaw.toLowerCase();
  const n = String(seasonNumber);
  const patterns = [
    new RegExp(`\\bseason\\s*${n}\\b`, "i"),
    new RegExp(`\\bstaffel\\s*${n}\\b`, "i"),
    new RegExp(`\\bpart\\s*${n}\\b`, "i"),
    new RegExp(`\\b${n}(?:st|nd|rd|th)\\s+season\\b`, "i"),
    new RegExp(`第\\s*${n}\\s*期`, "i"),
    new RegExp(`${n}期`, "i"),
  ];
  return patterns.some((p) => p.test(t)) ? 0.18 : 0;
}

function buildSeasonQueries(baseTitle: string, seasonNumber: number): string[] {
  const n = seasonNumber;
  const ordinal = (x: number) => {
    const mod100 = x % 100;
    if (mod100 >= 11 && mod100 <= 13) return "th";
    const mod10 = x % 10;
    if (mod10 === 1) return "st";
    if (mod10 === 2) return "nd";
    if (mod10 === 3) return "rd";
    return "th";
  };
  const suffixes = [
    `season ${n}`,
    `s${n}`,
    `staffel ${n}`,
    `${n}${ordinal(n)} season`,
    `part ${n}`,
    `cour ${n}`,
  ];
  return suffixes.map((s) => `${baseTitle} ${s}`.trim());
}

function buildDenoisedQueries(title: string): string[] {
  const stop = new Set([
    "the",
    "a",
    "an",
    "of",
    "and",
    "or",
    "to",
    "until",
    "till",
    "up",
    "upto",
    "bis",
    "zur",
    "zum",
    "ich",
    "habe",
    "hab",
    "bin",
    "i",
    "im",
    "i'm",
    "am",
    "my",
    "just",
    "recently",
    "only",
    "watched",
    "watching",
    "read",
    "reading",
    "gesehen",
    "geschaut",
    "gelesen",
    "schaue",
    "gucke",
    "sehe",
    "lese",
    "season",
    "staffel",
    "episode",
    "ep",
    "folge",
    "chapter",
    "ch",
    "kapitel",
    "volume",
    "vol",
    "band",
  ]);

  const rawTokens = title
    .toLowerCase()
    .split(/\s+/g)
    .map((t) => t.replace(/[^a-z0-9äöüß]/gi, ""))
    .filter((t) => t.length >= 3)
    .filter((t) => !stop.has(t))
    .filter((t) => !/^\d+$/.test(t));

  const tokens = Array.from(new Set(rawTokens));
  if (tokens.length === 0) return [];

  const queries: string[] = [];

  // Strongest anchor tokens (longer words tend to be distinctive).
  const long = tokens.filter((t) => t.length >= 6).slice(0, 2);
  queries.push(...long);

  // Last 1–3 tokens often contain the core noun (e.g. "... academia").
  for (let len = Math.min(3, tokens.length); len >= 1; len--) {
    queries.push(tokens.slice(-len).join(" "));
  }

  // First 2 tokens can help for two-word titles.
  if (tokens.length >= 2) queries.push(tokens.slice(0, 2).join(" "));

  return Array.from(new Set(queries)).filter(Boolean).slice(0, 5);
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
  const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const supabaseKey = supabaseAnon ?? supabaseService;
  if (!supabaseUrl || !supabaseKey) {
    return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const client = createClient(supabaseUrl, supabaseKey, {
    global: { headers: authHeader ? { Authorization: authHeader } : {} },
  });

  // Rate limit parsing even for unauthenticated users (falls back to per-IP).
  const ip = clientIp(req);
  const { data: rl } = await client.rpc("check_concierge_rate_limit", {
    p_kind: "parse",
    p_ip: ip,
    // Nulls => load tunables from public.concierge_config.
    p_window_seconds: null,
    p_max_user: null,
    p_max_ip: null,
  });
  if (rl && rl.allowed === false) {
    return json(
      { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
      { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
    );
  }

  const body = await req.json().catch(() => ({}));
  const text: string = String(body?.text ?? "");
  const scope: "anime" | "manga" | "both" = body?.scope ?? "both";
  const limitPerItem = Math.max(3, Math.min(15, Number(body?.limitPerItem ?? 10)));

  const itemsRaw = splitItems(text);
  if (itemsRaw.length === 0) {
    return json({ success: true, items: [] });
  }

  // Verify user (required for launch). If missing, we still return candidates but mark unauthenticated.
  const { data: userData } = await client.auth.getUser();
  const userId = userData?.user?.id ?? null;

  // Optional: configure feedback logging threshold (single DB roundtrip per request).
  let feedbackEnabled = Boolean(userId);
  let feedbackLowScore = 0.55;
  if (userId) {
    try {
      const { data: cfg } = await client.rpc("get_concierge_config");
      const pf = cfg?.parse_feedback ?? cfg?.parseFeedback ?? null;
      if (pf && typeof pf === "object") {
        if (typeof pf.enabled === "boolean") feedbackEnabled = pf.enabled;
        const v = Number(pf.low_confidence_score ?? pf.lowConfidenceScore ?? feedbackLowScore);
        if (Number.isFinite(v) && v >= 0 && v <= 1.5) feedbackLowScore = v;
      }
    } catch {
      // best-effort
    }
  }

  const parsed: ParsedItem[] = itemsRaw.map((raw) => {
    const cleaned = normalizeLine(raw);
    const status = parseStatus(cleaned);
    const progress = parseProgress(cleaned);
    const hint = mediaTypeHint(cleaned);
    const flags = parseMagicFlags(cleaned);
    return {
      raw: cleaned,
      normalized: stripMeta(cleaned),
      mediaTypeHint: hint,
      status: status.status,
      completed: status.completed,
      ...flags,
      ...progress,
    };
  });

  const outItems: any[] = [];

  for (const item of parsed) {
    const mediaType =
      scope === "anime" ? "ANIME" : scope === "manga" ? "MANGA" : item.mediaTypeHint ?? null;

    let aliasTarget: { media_type: string; media_id: number; title_raw?: string | null } | null = null;
    if (userId && item.normalized) {
      const aliasNorm = normalizeAliasKey(item.raw);
      if (aliasNorm) {
        const mediaTypeFilter = mediaType ?? null;
        const q = client
          .from("title_aliases")
          .select("media_type,media_id,title_raw,hits")
          .eq("user_id", userId)
          .eq("alias_norm", aliasNorm);
        const res = mediaTypeFilter ? await q.eq("media_type", mediaTypeFilter).maybeSingle() : await q.order("hits", { ascending: false }).limit(1).maybeSingle();
        if (!res.error && res.data?.media_id && res.data?.media_type) {
          aliasTarget = res.data;
        }
      }
    }

    const queries: { q: string; seasonBoost: boolean }[] = [{ q: item.normalized, seasonBoost: false }];
    const expanded = expandCommonAbbreviations(item.normalized);
    if (expanded && expanded !== item.normalized) {
      // Treat the expanded form as an alternate query; it tends to help new users on acronyms (AoT/JJK/etc).
      queries.push({ q: expanded, seasonBoost: false });
    }
    if (item.seasonNumber && item.normalized && (mediaType === "ANIME" || item.mediaTypeHint === "ANIME")) {
      for (const q of buildSeasonQueries(item.normalized, item.seasonNumber)) {
        queries.push({ q, seasonBoost: true });
      }
    }

    const merged = new Map<string, any>();
    let candidateError: string | null = null;

    for (const q of queries) {
      const { data: candidates, error } = await client.rpc("search_titles", {
        p_query: q.q,
        p_media_type: mediaType,
        p_limit: Math.max(5, Math.min(limitPerItem, 12)),
      });
      if (error) {
        candidateError = candidateError ?? error.message ?? "search error";
        continue;
      }
      for (const c of (candidates ?? [])) {
        const key = `${c.media_type}:${c.media_id}`;
        const baseScore = typeof c.score === "number" ? c.score : 0;
        const seasonBoost = q.seasonBoost && item.seasonNumber ? seasonMatchBoost(String(c.title_raw ?? ""), item.seasonNumber) : 0;
        const overlapBoost = tokenOverlapBoost(item.normalized, String(c.title_raw ?? ""));
        const penalty = variantPenalty(item.raw, { title_raw: c.title_raw, variant_type: c.variant_type });
        const aliasBoost =
          aliasTarget && aliasTarget.media_type === c.media_type && Number(aliasTarget.media_id) === Number(c.media_id) ? 0.80 : 0;
        // Allow a tiny score > 1 so "Season 2" variants can beat the base title when both match at 1.0.
        const adjusted = Math.max(0, Math.min(1.25, baseScore + seasonBoost + overlapBoost + aliasBoost - penalty));
        const existing = merged.get(key);
        if (!existing || (existing.score ?? 0) < adjusted) {
          merged.set(key, { ...c, score: adjusted });
        }
      }
    }

    const mergedCandidates = Array.from(merged.values())
      .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
      .slice(0, limitPerItem);

    // Second pass: if confidence is low, try denoised keyword queries.
    const bestScore = typeof mergedCandidates[0]?.score === "number" ? mergedCandidates[0].score : 0;
    if (bestScore < 0.55 && item.normalized.length >= 8) {
      for (const q of buildDenoisedQueries(item.normalized)) {
        const { data: extra, error } = await client.rpc("search_titles", {
          p_query: q,
          p_media_type: mediaType,
          p_limit: Math.max(5, Math.min(limitPerItem, 12)),
        });
        if (error) continue;
        for (const c of (extra ?? [])) {
          const key = `${c.media_type}:${c.media_id}`;
          const baseScore = typeof c.score === "number" ? c.score : 0;
          const penalty = variantPenalty(item.raw, { title_raw: c.title_raw, variant_type: c.variant_type });
          const adjusted = Math.max(0, Math.min(1.25, baseScore + tokenOverlapBoost(item.normalized, String(c.title_raw ?? "")) - penalty));
          const existing = merged.get(key);
          if (!existing || (existing.score ?? 0) < adjusted) {
            merged.set(key, { ...c, score: adjusted });
          }
        }
      }
    }

    const finalCandidates = Array.from(merged.values())
      .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
      .slice(0, limitPerItem);

    if (feedbackEnabled) {
      try {
        const top = finalCandidates[0] ?? null;
        const bestScore = typeof top?.score === "number" ? top.score : null;
        // Only log low-confidence/no-match items to avoid added latency.
        if (bestScore == null || bestScore < feedbackLowScore || finalCandidates.length === 0) {
          await client.rpc("log_concierge_parse_feedback", {
            p_raw: item.raw,
            p_normalized: item.normalized,
            p_alias_norm: normalizeAliasKey(item.raw),
            p_best_score: bestScore,
            p_candidates_count: finalCandidates.length,
            p_top_media_type: top?.media_type ?? null,
            p_top_media_id: top?.media_id ?? null,
          });
        }
      } catch {
        // best-effort
      }
    }

    outItems.push({
      raw: item.raw,
      normalized: item.normalized,
      parsed: {
        mediaTypeHint: item.mediaTypeHint ?? null,
        status: item.status ?? null,
        progressEpisodes: item.progressEpisodes ?? null,
        progressChapters: item.progressChapters ?? null,
        progressVolumes: item.progressVolumes ?? null,
        seasonNumber: item.seasonNumber ?? null,
        episodeInSeason: item.episodeInSeason ?? null,
        caughtUp: item.caughtUp ?? null,
        lastEpisode: item.lastEpisode ?? null,
        completed: item.completed ?? null,
      },
      candidates: finalCandidates,
      candidateError,
      aliasNorm: userId ? normalizeAliasKey(item.raw) : null,
    });
  }

  // Lightweight run logging (best-effort; table is RLS-deny by default for users).
  if (userId) {
    try {
      await client.rpc("log_concierge_run", {
        p_kind: "parse",
        p_status: "success",
        p_input_chars: text.length,
        p_items_count: outItems.length,
      });
    } catch {
      // Best-effort metrics only.
    }
  }

  return json({ success: true, userId, items: outItems });
});

```

### Edge Function: concierge-resolve (LLM disambiguation)

- Path: `supabase/functions/concierge-resolve/index.ts`


```ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Candidate = {
  media_type: "ANIME" | "MANGA";
  media_id: number;
  title_raw: string;
  variant_type?: string;
  score?: number;
};

type Parsed = {
  mediaTypeHint?: string | null;
  status?: string | null;
  progressEpisodes?: number | null;
  progressChapters?: number | null;
  progressVolumes?: number | null;
  seasonNumber?: number | null;
  episodeInSeason?: number | null;
  caughtUp?: boolean | null;
  lastEpisode?: boolean | null;
  completed?: boolean | null;
};

type ResolveItem = {
  raw: string;
  normalized?: string;
  parsed?: Parsed;
  candidates: Candidate[];
};

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function clampInt(v: unknown, min: number, max: number) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return null;
  return Math.max(min, Math.min(max, n));
}

function extractJsonObject(text: string): any | null {
  const s = String(text || "");
  const start = s.indexOf("{");
  const end = s.lastIndexOf("}");
  if (start < 0 || end < 0 || end <= start) return null;
  const candidate = s.slice(start, end + 1);
  try {
    return JSON.parse(candidate);
  } catch {
    return null;
  }
}

async function groqResolve(opts: {
  apiKey: string;
  model: string;
  items: Array<{ raw: string; parsed: Parsed; options: Array<{ id: string; title: string; variant?: string; score?: number }> }>;
}): Promise<{ resolved: any | null; usageTotal: number | null }> {
  const url = "https://api.groq.com/openai/v1/chat/completions";

  const system = `Return JSON only: {"choices":[{"i":0,"pick":0,"confidence":0.0,"reason":""}]}`;

  const user = `You are resolving user-entered anime/manga titles to one of the provided options.

Rules:
- You MUST pick from the options for each item: pick is an integer index into that item's options array (0-based).
- If none match, set pick to -1.
- If the user explicitly says watched/saw/schaue/geschaut => prefer ANIME; read/lese/gelesen => prefer MANGA.
- If seasonNumber is present, prefer an option whose title includes that season (e.g., "Season 2", "2nd Season") IF the base title also matches.
- DO NOT hallucinate. Only choose from options.
- Output must be valid JSON ONLY, matching:
  {"choices":[{"i":number,"pick":number,"confidence":number,"reason":string}...]}

Items:
${opts.items
  .map((it, idx) =>
    `#${idx} raw="${it.raw}" parsed=${JSON.stringify(it.parsed ?? {})}\noptions:\n${it.options
      .map((o, j) => `  [${j}] ${o.id} ${o.title}${o.variant ? ` (${o.variant})` : ""}${typeof o.score === "number" ? ` score=${o.score.toFixed(3)}` : ""}`)
      .join("\n")}`,
  )
  .join("\n\n")}`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${opts.apiKey}`,
    },
    body: JSON.stringify({
      model: opts.model,
      temperature: 0.0,
      // Keep this tiny; output is a small JSON object.
      max_tokens: 220,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });

  const jsonRes = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(`Groq error: ${res.status} ${JSON.stringify(jsonRes)?.slice(0, 300)}`);
  }

  const usageTotal = Number(
    jsonRes?.usage?.total_tokens ??
      ((Number(jsonRes?.usage?.prompt_tokens ?? 0) || 0) + (Number(jsonRes?.usage?.completion_tokens ?? 0) || 0)),
  );
  const usage = Number.isFinite(usageTotal) && usageTotal > 0 ? usageTotal : null;

  const content = jsonRes?.choices?.[0]?.message?.content ?? "";
  const parsed = extractJsonObject(content);
  return { resolved: parsed ?? null, usageTotal: usage };
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseKey = supabaseAnon ?? supabaseService;
    if (!supabaseUrl || !supabaseKey) {
      return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const client = createClient(supabaseUrl, supabaseKey, {
      global: { headers: authHeader ? { Authorization: authHeader } : {} },
    });

    const { data: userData, error: userErr } = await client.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });

    // Server-side rate limiting (per-user + per-IP).
    const ip = clientIp(req);
    const { data: rl } = await client.rpc("check_concierge_rate_limit", {
      p_kind: "resolve",
      p_ip: ip,
      p_window_seconds: null,
      p_max_user: null,
      p_max_ip: null,
    });
    if (rl && rl.allowed === false) {
      return json(
        { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
        { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
      );
    }

    // Global kill-switch: if disabled, just don't resolve (user can pick manually).
    const { data: llmEnabled } = await client.rpc("is_flag_enabled", { p_key: "llm_enabled" });
    if (llmEnabled === false) return json({ success: true, choices: [], disabled: true });

    const groqKey = Deno.env.get("GROQ_API_KEY");
    const model = Deno.env.get("GROQ_MODEL_RESOLVE") ?? Deno.env.get("GROQ_MODEL") ?? "openai/gpt-oss-20b";
    if (!groqKey) return json({ error: "Missing GROQ_API_KEY secret" }, { status: 500 });

    const body = await req.json().catch(() => ({}));
    const items: ResolveItem[] = Array.isArray(body?.items) ? body.items : [];
    const maxCandidates = clampInt(body?.maxCandidates, 2, 10) ?? 6;

    if (items.length === 0) return json({ success: true, choices: [] });

    const packed = items.slice(0, 20).map((it) => {
      const raw = String(it?.raw ?? "").slice(0, 300);
      const parsed: Parsed = it?.parsed ?? {};
      const options = (Array.isArray(it?.candidates) ? it.candidates : [])
        .slice(0, maxCandidates)
        .map((c) => ({
          id: `${String(c.media_type).toUpperCase()}|${Number(c.media_id)}`,
          title: String(c.title_raw ?? "").slice(0, 120),
          variant: String(c.variant_type ?? ""),
          score: typeof c.score === "number" ? c.score : undefined,
        }));
      return { raw, parsed, options };
    });

    // Budget guardrails. We reserve before the LLM call, then finalize with actual usage if available.
    const maxCompletion = 220;
    const promptChars =
      1400 + // small constant for prompt framing
      packed.reduce((sum, it) => sum + it.raw.length + JSON.stringify(it.options).length + JSON.stringify(it.parsed ?? {}).length, 0);
    const reserveTokens = Math.min(8000, Math.max(120, Math.ceil(promptChars / 4) + maxCompletion));

    const { data: budget } = await client.rpc("llm_budget_reserve", {
      p_reserved_tokens: reserveTokens,
      // Nulls => defaults from public.concierge_config.
      p_max_daily_tokens: null,
      p_max_daily_calls: null,
      p_model: model,
    });
    if (budget && budget.allowed === false) {
      return json({ success: true, choices: [], budget_exceeded: true });
    }

    // Global budget (prevents "many users" abuse).
    const { data: cfg } = await client.rpc("get_concierge_config");
    const globalBudget = cfg?.global_llm_budget ?? null;
    const globalDailyTokens = Number(globalBudget?.daily_tokens ?? 250000);
    const globalDailyCalls = Number(globalBudget?.daily_calls ?? 600);
    const { data: gBudget } = await client.rpc("llm_global_budget_reserve", {
      p_reserved_tokens: reserveTokens,
      p_max_daily_tokens: Number.isFinite(globalDailyTokens) ? globalDailyTokens : 250000,
      p_max_daily_calls: Number.isFinite(globalDailyCalls) ? globalDailyCalls : 600,
    });
    if (gBudget && gBudget.allowed === false) {
      // Release per-user reservation (best-effort).
      try {
        await client.rpc("llm_budget_finalize", { p_reserved_tokens: reserveTokens, p_actual_tokens: 0, p_model: model });
      } catch {
        // ignore
      }
      return json({ success: true, choices: [], budget_exceeded: true, global_budget_exceeded: true });
    }

    const { resolved, usageTotal } = await groqResolve({ apiKey: groqKey, model, items: packed });
    const choices = Array.isArray(resolved?.choices) ? resolved.choices : [];

    // Validate and map.
    const out: any[] = [];
    for (const c of choices) {
      const i = clampInt(c?.i, 0, packed.length - 1);
      if (i == null) continue;
      const pick = clampInt(c?.pick, -1, packed[i].options.length - 1);
      if (pick == null) continue;
      const confidence = Math.max(0, Math.min(1, Number(c?.confidence ?? 0)));
      const reason = String(c?.reason ?? "").slice(0, 240);
      const opt = pick >= 0 ? packed[i].options[pick] : null;
      out.push({
        i,
        pick,
        confidence,
        reason,
        chosen: opt ? { id: opt.id, title: opt.title } : null,
      });
    }

    try {
      const actual = usageTotal ?? reserveTokens;
      await client.rpc("llm_budget_finalize", {
        p_reserved_tokens: reserveTokens,
        p_actual_tokens: actual,
        p_model: model,
      });
      await client.rpc("llm_global_budget_finalize", {
        p_reserved_tokens: reserveTokens,
        p_actual_tokens: actual,
      });
    } catch {
      // best-effort
    }

    return json({ success: true, choices: out });
  } catch (e) {
    return json({ success: false, error: e?.message ?? String(e) }, { status: 500 });
  }
});

```

### Edge Function: concierge-recommend (recommend + narration)

- Path: `supabase/functions/concierge-recommend/index.ts`


```ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MediaType = "ANIME" | "MANGA";

type ConciergeMode = {
  id: string;
  title: string;
  synonyms?: string[];
  required_genres?: string[];
  exclude_genres?: string[];
  min_score?: number;
  min_popularity?: number;
  max_popularity?: number;
  exclude_formats?: string[];
  classic_year_max?: number;
};

type ModePick = { id: string; title: string; confidence: number; reason: string };

type CandidateRow = { media_id: number; match_count?: number | null; score?: number | null };

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function uniq<T>(arr: T[]) {
  return Array.from(new Set(arr));
}

function safeStringArray(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return uniq(
    v
      .map((x) => (typeof x === "string" ? x.trim() : ""))
      .filter((x) => x.length > 0),
  );
}

function safeNumber(v: unknown): number | null {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

function normalizeText(s: string): string {
  return s
    .toLowerCase()
    .replace(/[_/\\-]+/g, " ")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function parseModesFromConfig(cfg: any): ConciergeMode[] {
  const raw = cfg?.modes;
  if (!Array.isArray(raw)) return [];
  const out: ConciergeMode[] = [];
  for (const r of raw) {
    if (!r || typeof r !== "object") continue;
    const id = typeof r.id === "string" ? r.id.trim() : "";
    const title = typeof r.title === "string" ? r.title.trim() : "";
    if (!id || !title) continue;
    out.push({
      id,
      title,
      synonyms: safeStringArray((r as any).synonyms),
      required_genres: safeStringArray((r as any).required_genres),
      exclude_genres: safeStringArray((r as any).exclude_genres),
      min_score: safeNumber((r as any).min_score) ?? undefined,
      min_popularity: safeNumber((r as any).min_popularity) ?? undefined,
      max_popularity: safeNumber((r as any).max_popularity) ?? undefined,
      exclude_formats: safeStringArray((r as any).exclude_formats),
      classic_year_max: safeNumber((r as any).classic_year_max) ?? undefined,
    });
  }
  return out;
}

function defaultModes(): ConciergeMode[] {
  // Safe fallback if config/migration hasn't been applied yet.
  return [
    {
      id: "premium_action",
      title: "Premium Action",
      synonyms: ["premium action", "best action", "action premium", "hype action", "fight scenes"],
      required_genres: ["Action"],
      min_score: 75,
      min_popularity: 3500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "cozy_comfort",
      title: "Cozy / Comfort",
      synonyms: ["cozy", "comfort", "chill", "relax", "healing", "iyashikei", "gemütlich"],
      required_genres: ["Slice of Life"],
      min_score: 70,
      min_popularity: 1200,
      exclude_formats: ["MUSIC"],
    },
    {
      id: "premium_comedy_grownup",
      title: "Premium Comedy (grown-up)",
      synonyms: ["funny but not childish", "grown up comedy", "smart comedy", "adult humor", "witzig aber nicht kindisch"],
      required_genres: ["Comedy"],
      min_score: 75,
      min_popularity: 3500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "dark_serious",
      title: "Dark / Serious",
      synonyms: ["dark", "serious", "mature", "grown up", "not childish", "psychological", "thriller", "mind game"],
      required_genres: ["Drama", "Thriller", "Psychological", "Mystery"],
      min_score: 78,
      min_popularity: 2500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "hidden_gems",
      title: "Hidden Gems",
      synonyms: ["hidden gems", "underrated", "less known", "something new", "new to me", "surprise me"],
      min_score: 78,
      max_popularity: 45000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "classics_expanded",
      title: "Classics (expanded)",
      synonyms: ["classic", "classics", "must watch", "essentials", "goat", "greatest of all time"],
      classic_year_max: 2012,
      min_score: 80,
      min_popularity: 1500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
  ];
}

function scoreMode(text: string, mode: ConciergeMode, inferredGenres: string[]): { score: number; reason: string } {
  const t = normalizeText(text);
  let score = 0;
  let reason = "";

  const synonyms = mode.synonyms ?? [];
  for (const syn of synonyms) {
    const s = normalizeText(syn);
    if (!s) continue;
    if (t.includes(s)) {
      score += Math.max(2, Math.min(5, Math.ceil(s.split(" ").length / 2) + 2));
      if (!reason) reason = `matches "${syn}"`;
    }
  }

  // Genre overlap is a strong signal (even if the user doesn't use the mode's exact synonyms).
  const req = mode.required_genres ?? [];
  const overlap = req.filter((g) => inferredGenres.includes(g));
  if (overlap.length > 0) {
    score += 2 + Math.min(3, overlap.length);
    if (!reason) reason = `genre: ${overlap.slice(0, 2).join(", ")}`;
  }

  // Classic intent boosts the classics mode and slightly downweights gimmick modes.
  const wantsClassic = /\b(classic|classics|must watch|essentials|goat|greatest)\b/i.test(text);
  if (wantsClassic && mode.id.includes("classic")) {
    score += 3;
    if (!reason) reason = "classic intent";
  }
  const wantsHidden = /\b(hidden gem|underrated|less known|new to me|surprise)\b/i.test(text);
  if (wantsHidden && mode.id.includes("hidden")) {
    score += 3;
    if (!reason) reason = "hidden gems intent";
  }

  // Cheap maturity heuristic.
  const mature = /\b(not childish|grown[- ]?up|mature|serious|dark)\b/i.test(text);
  if (mature && (mode.id.includes("grown") || mode.id.includes("dark"))) {
    score += 2;
    if (!reason) reason = "mature tone";
  }

  return { score, reason: reason || "default" };
}

function pickTwoModes(text: string, modes: ConciergeMode[], inferredGenres: string[]): ModePick[] {
  const scored = modes.map((m) => {
    const { score, reason } = scoreMode(text, m, inferredGenres);
    return { mode: m, score, reason };
  });

  // Always keep a classics rail as a stable anchor, unless we don't have such a mode.
  const classics = scored.find((x) => x.mode.id.includes("classic"))?.mode ?? null;

  scored.sort((a, b) => b.score - a.score);

  const primary = scored.find((x) => !x.mode.id.includes("classic"))?.mode ?? scored[0]?.mode ?? null;
  const primaryReason = scored.find((x) => x.mode.id === primary?.id)?.reason ?? "default";
  const primaryScore = scored.find((x) => x.mode.id === primary?.id)?.score ?? 0;

  let secondary: ConciergeMode | null = null;
  let secondaryReason = "default";
  let secondaryScore = 0;

  if (classics && classics.id !== primary?.id) {
    secondary = classics;
    const hit = scored.find((x) => x.mode.id === classics.id);
    secondaryReason = hit?.reason ?? "classic rail";
    secondaryScore = hit?.score ?? 0;
  } else {
    const next = scored.find((x) => x.mode.id !== primary?.id);
    secondary = next?.mode ?? null;
    secondaryReason = next?.reason ?? "default";
    secondaryScore = next?.score ?? 0;
  }

  const mk = (m: ConciergeMode | null, score: number, reason: string): ModePick | null => {
    if (!m) return null;
    // Convert a small integer-ish score to a [0..1] confidence for UI/debugging.
    const confidence = Math.max(0, Math.min(1, score / 10));
    return { id: m.id, title: m.title, confidence, reason };
  };

  const out: ModePick[] = [];
  const p = mk(primary, primaryScore, primaryReason);
  if (p) out.push(p);
  const s = mk(secondary, secondaryScore, secondaryReason);
  if (s) out.push(s);
  return out.slice(0, 2);
}

function inferLanguage(text: string): "de" | "en" {
  const t = text.toLowerCase();
  // Minimal heuristic: just enough for DE narration.
  if (/\b(ich|habe|hab|schaue|gucke|sehe|lese|staffel|folge|kapitel|band|bitte|empfehl)\b/.test(t)) return "de";
  if (/[äöüß]/i.test(t)) return "de";
  return "en";
}

function inferMediaType(text: string, scope: string): MediaType | "BOTH" {
  const s = (scope || "").toLowerCase();
  if (s === "anime") return "ANIME";
  if (s === "manga") return "MANGA";
  const t = text.toLowerCase();
  if (/\b(manga|manhwa|manhua)\b/.test(t)) return "MANGA";
  if (/\b(anime)\b/.test(t)) return "ANIME";
  return "BOTH";
}

function inferSeedQuery(text: string): string | null {
  const t = text.trim();
  const m1 = t.match(/\b(?:like|similar to)\s+(.+?)(?:[.?!]|$)/i);
  if (m1?.[1]) return m1[1].trim().replace(/^["']|["']$/g, "");
  return null;
}

function inferCategories(text: string): string[] {
  const t = text.toLowerCase();
  const out: string[] = [];

  // NOTE:
  // `recommend_ids_premium` uses `tags.category` (as imported from AniList tag.category) to compute matches.
  // AniList category strings are usually "Comedy", "Drama", "Slice of Life", etc. (not "Theme-...").
  //
  // We also do a genre gate later using `anime.genres` / `manga.genres` for higher precision.

  // EN
  if (/\b(fun|funny|comedy|laugh)\b/.test(t)) out.push("Comedy");
  if (/\b(sad|cry|tears?|heartbreak)\b/.test(t)) out.push("Drama");
  if (/\b(cozy|comfort|chill|relax)\b/.test(t)) out.push("Slice of Life");
  if (/\b(romance|love|romcom)\b/.test(t)) out.push("Romance");
  if (/\b(action)\b/.test(t)) out.push("Action");
  if (/\b(adventure)\b/.test(t)) out.push("Adventure");
  if (/\b(fantasy)\b/.test(t)) out.push("Fantasy");
  if (/\b(sci[- ]?fi|scifi|science fiction)\b/.test(t)) out.push("Sci-Fi");
  if (/\b(mystery|detective)\b/.test(t)) out.push("Mystery");
  if (/\b(thriller)\b/.test(t)) out.push("Thriller");
  if (/\b(horror|scary)\b/.test(t)) out.push("Horror");
  if (/\b(psychological|mind[- ]?game)\b/.test(t)) out.push("Psychological");
  if (/\b(supernatural)\b/.test(t)) out.push("Supernatural");
  if (/\b(sports?)\b/.test(t)) out.push("Sports");
  if (/\b(music)\b/.test(t)) out.push("Music");

  // DE (keep lightweight; only high-signal words)
  if (/\b(lustig|witzig|kom(ö|oe)die|zum lachen)\b/.test(t)) out.push("Comedy");
  if (/\b(traurig|heul|weinen|herzschmerz)\b/.test(t)) out.push("Drama");
  if (/\b(gem(ü|ue)tlich|comfort|chillen|entspann)\b/.test(t)) out.push("Slice of Life");
  if (/\b(liebe|romantik|romance|romcom)\b/.test(t)) out.push("Romance");
  if (/\b(action)\b/.test(t)) out.push("Action");
  if (/\b(abenteuer)\b/.test(t)) out.push("Adventure");
  if (/\b(fantasy|fantasie)\b/.test(t)) out.push("Fantasy");
  if (/\b(sci[- ]?fi|science fiction)\b/.test(t)) out.push("Sci-Fi");
  if (/\b(krimi|mystery|detektiv)\b/.test(t)) out.push("Mystery");
  if (/\b(thriller)\b/.test(t)) out.push("Thriller");
  if (/\b(horror|gruselig)\b/.test(t)) out.push("Horror");
  if (/\b(psychologisch)\b/.test(t)) out.push("Psychological");
  if (/\b(übernatürlich)\b/.test(t)) out.push("Supernatural");
  if (/\b(sport)\b/.test(t)) out.push("Sports");
  if (/\b(musik)\b/.test(t)) out.push("Music");

  // “First anime/manga” intent nudges toward accessible, broadly-liked picks.
  // This is not hardcoded curation; it just biases toward general-audience categories.
  if (/\b(first anime|first manga|getting into anime|getting into manga)\b/.test(t)) {
    out.push("Slice of Life", "Drama", "Adventure");
  }
  if (/\b(erstes anime|erstes manga|anime anfangen|manga anfangen|neu bei anime|neu bei manga)\b/.test(t)) {
    out.push("Slice of Life", "Drama", "Adventure");
  }
  // Explicit modes that should be discoverable.
  if (/\b(isekai)\b/.test(t)) out.push("Fantasy");

  return uniq(out);
}

function inferGimmickTagIds(text: string): number[] {
  const t = text.toLowerCase();
  const ids: number[] = [];
  if (/\b(isekai)\b/.test(t)) ids.push(350);
  if (/\b(reincarnat|reborn|tensei|wiedergeboren|reinkarnat)\b/.test(t)) ids.push(1023);
  if (/\b(another world|in another world|isekai)\b/.test(t)) ids.push(350);
  if (/\b(slime)\b/.test(t)) ids.push(350, 1023);
  if (/\b(harem)\b/.test(t)) ids.push(358, 9154, 18064);
  return uniq(ids);
}

function inferRequiredGenres(text: string): string[] {
  const t = text.toLowerCase();
  const out: string[] = [];
  if (/\b(fun|funny|comedy|laugh|lustig|witzig|kom(ö|oe)die)\b/.test(t)) out.push("Comedy");
  if (/\b(romance|love|romcom|liebe|romantik)\b/.test(t)) out.push("Romance");
  if (/\b(action)\b/.test(t)) out.push("Action");
  if (/\b(adventure|abenteuer)\b/.test(t)) out.push("Adventure");
  if (/\b(fantasy|fantasie|isekai)\b/.test(t)) out.push("Fantasy");
  if (/\b(sci[- ]?fi|scifi|science fiction)\b/.test(t)) out.push("Sci-Fi");
  if (/\b(slice of life|sol|comfort|cozy|gem(ü|ue)tlich)\b/.test(t)) out.push("Slice of Life");
  if (/\b(drama|sad|cry|traurig|herzschmerz)\b/.test(t)) out.push("Drama");
  if (/\b(mystery|detective|krimi|detektiv)\b/.test(t)) out.push("Mystery");
  if (/\b(thriller)\b/.test(t)) out.push("Thriller");
  if (/\b(horror|scary|gruselig)\b/.test(t)) out.push("Horror");
  if (/\b(psychological|psychologisch)\b/.test(t)) out.push("Psychological");
  if (/\b(supernatural|übernatürlich)\b/.test(t)) out.push("Supernatural");
  if (/\b(sports?|sport)\b/.test(t)) out.push("Sports");
  return uniq(out);
}

function inferQualityFloor(text: string): { minScore: number; minPopularity: number; excludeFormats: Set<string> } {
  const t = text.toLowerCase();
  const wantsPremium = /\b(premium|masterpiece|must[- ]?watch|classic|classics|top tier|best)\b/.test(t);
  const noChildish = /\b(not childish|grown[- ]?up|mature|serious|not for kids)\b/.test(t);

  // Defaults: avoid over-filtering; the DB may be small in early imports.
  let minScore = 0;
  let minPopularity = 0;

  if (wantsPremium) {
    minScore = 75;
    minPopularity = 5000;
  }
  if (noChildish) {
    minScore = Math.max(minScore, 75);
    minPopularity = Math.max(minPopularity, 3500);
  }

  // Exclude shortform/noise formats unless explicitly requested.
  const excludeFormats = new Set<string>(["TV_SHORT", "SPECIAL", "MUSIC"]);
  if (/\b(short|mini|shortform)\b/.test(t)) {
    excludeFormats.delete("TV_SHORT");
  }
  return { minScore, minPopularity, excludeFormats };
}

async function mapTagAnilistIdsToInternal(client: any, anilistIds: number[]): Promise<number[]> {
  const ids = uniq(anilistIds).filter((x) => Number.isFinite(x) && x > 0);
  if (!ids.length) return [];
  const { data, error } = await client.from("tags").select("id,anilist_id").in("anilist_id", ids);
  if (error || !Array.isArray(data)) return [];
  return uniq(data.map((r: any) => Number(r.id)).filter((x: any) => Number.isFinite(x) && x > 0));
}

async function groqNarrate(opts: {
  apiKey: string;
  model: string;
  lang: "de" | "en";
  userText: string;
  debug?: boolean;
  items: Array<{ id: string; title: string; year?: number | null; format?: string | null; signals: string[] }>;
}): Promise<{ blurbs: Record<string, string>; usageTotal: number | null }> {
  const url = "https://api.groq.com/openai/v1/chat/completions";
  // NOTE: Groq's GPT-OSS models sometimes return empty `content` if the system prompt is too "policy-like".
  // Keep the system prompt extremely short and drive style via a single user instruction.
  const system =
    opts.lang === "de"
      ? `Gib nur JSON zurück: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`
      : `Return JSON only: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`;

  const user =
    opts.lang === "de"
      ? `User prompt: ${opts.userText}\n\nItems:\n${opts.items
          .map((it) => `- ${it.id}: ${it.title} (${it.year ?? "?"}) ${it.format ?? ""} [${it.signals.join(", ")}]`)
          .join("\n")}\n\nSchreibe pro Item genau einen kurzen, spoilerfreien Satz. Gib nur JSON zurück: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`
      : `User prompt: ${opts.userText}\n\nItems:\n${opts.items
          .map((it) => `- ${it.id}: ${it.title} (${it.year ?? "?"}) ${it.format ?? ""} [${it.signals.join(", ")}]`)
          .join("\n")}\n\nWrite one short, spoiler-free sentence per item. Return JSON only: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${opts.apiKey}`,
    },
    body: JSON.stringify({
      model: opts.model,
      // Keep this deterministic and tiny. We're only writing 5–10 single-sentence blurbs.
      temperature: 0.2,
      // We only need short JSON blurbs; keeping this low improves latency/cost.
      max_tokens: 260,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });

  const jsonRes = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(`Groq error: ${res.status} ${JSON.stringify(jsonRes)?.slice(0, 300)}`);
  }

  const usageTotal = Number(
    jsonRes?.usage?.total_tokens ??
      ((Number(jsonRes?.usage?.prompt_tokens ?? 0) || 0) + (Number(jsonRes?.usage?.completion_tokens ?? 0) || 0)),
  );
  const usage = Number.isFinite(usageTotal) && usageTotal > 0 ? usageTotal : null;

  const content = jsonRes?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || !content.trim()) {
    if (opts.debug) {
      throw new Error(
        `Groq narration missing content. status=${res.status} body_snippet=${JSON.stringify(jsonRes)?.slice(0, 600)}`,
      );
    }
    return { blurbs: {}, usageTotal: usage };
  }
  try {
    // Be forgiving: some models wrap JSON in text/code fences.
    const start = content.indexOf("{");
    const end = content.lastIndexOf("}");
    const candidate = start >= 0 && end > start ? content.slice(start, end + 1) : content;
    const parsed = JSON.parse(candidate);
    const blurbs = parsed?.blurbs;
    if (blurbs && typeof blurbs === "object") return { blurbs, usageTotal: usage };
  } catch {
    // ignore
  }
  if (opts.debug) {
    throw new Error(`Groq narration JSON parse failed. content_snippet=${content.slice(0, 400)}`);
  }
  return { blurbs: {}, usageTotal: usage };
}

function clampBlurb(s: string, maxWords: number, maxChars: number) {
  const trimmed = s.replace(/\s+/g, " ").trim();
  if (!trimmed) return "";
  const words = trimmed.split(" ");
  const clippedWords = words.slice(0, maxWords).join(" ");
  const clippedChars = clippedWords.slice(0, maxChars).trim();
  return clippedChars.replace(/[,\s]+$/g, "").trim();
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseKey = supabaseAnon ?? supabaseService;
    if (!supabaseUrl || !supabaseKey) {
      return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const client = createClient(supabaseUrl, supabaseKey, {
      global: { headers: authHeader ? { Authorization: authHeader } : {} },
    });

    const { data: userData, error: userErr } = await client.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });

    // Server-side rate limiting (per-user + per-IP).
    const ip = clientIp(req);
    const { data: rl } = await client.rpc("check_concierge_rate_limit", {
      p_kind: "recommend",
      p_ip: ip,
      p_window_seconds: null,
      p_max_user: null,
      p_max_ip: null,
    });
    if (rl && rl.allowed === false) {
      return json(
        { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
        { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
      );
    }

    const body = await req.json().catch(() => ({}));
    const text: string = String(body?.text ?? "");
    const scope: string = String(body?.scope ?? "both");
    const limit = Math.max(3, Math.min(20, Number(body?.limit ?? 8)));
    let narrate: boolean = Boolean(body?.narrate ?? false);
    const debugNarration: boolean = Boolean(body?.debugNarration ?? false);

    const categories = inferCategories(text);
    const gimmickTagIds = inferGimmickTagIds(text);
    const requiredGenres = inferRequiredGenres(text);
    const quality = inferQualityFloor(text);

    // Concierge config (tunable without redeploy): used for modes + global LLM budgets.
    const { data: conciergeCfg } = await client.rpc("get_concierge_config");
    const configuredModes = parseModesFromConfig(conciergeCfg);
    const modes = configuredModes.length ? configuredModes : defaultModes();

    // Focus tags are only used for explicit "gimmicks" (isekai, reincarnation, etc.)
    // because `recommend_ids_premium` *requires* focus tags to match when provided.
    const focusTagIds = await mapTagAnilistIdsToInternal(client, gimmickTagIds);
    const allowGimmicks =
      gimmickTagIds.length > 0 || /\b(slime)\b/.test(text.toLowerCase());
    const lang = inferLanguage(text);

    const mediaType = inferMediaType(text, scope);
    const seedQuery = inferSeedQuery(text);

    // Load editorial tag boosts once; used to add deterministic "premium" signals.
    const { data: tagBoosts } = await client
      .from("editorial_tag_boosts")
      .select("tag_id,boost,reason");
    const tagBoostByTag = new Map<number, any>((tagBoosts ?? []).map((t: any) => [t.tag_id, t]));
    const boostTagIds = Array.from(tagBoostByTag.keys());

    const mergeAlternating = <T>(a: T[], b: T[], max: number): T[] => {
      const out: T[] = [];
      let i = 0;
      while (out.length < max && (i < a.length || i < b.length)) {
        if (i < a.length) out.push(a[i]);
        if (out.length >= max) break;
        if (i < b.length) out.push(b[i]);
        i++;
      }
      return out;
    };

    const compileQuality = (mode: ConciergeMode | null) => {
      const minScore = Math.max(quality.minScore, Number(mode?.min_score ?? 0) || 0);
      const minPopularity = Math.max(quality.minPopularity, Number(mode?.min_popularity ?? 0) || 0);
      const maxPopularityRaw = mode?.max_popularity;
      const maxPopularity = Number.isFinite(Number(maxPopularityRaw)) ? Number(maxPopularityRaw) : null;
      const excludeFormats = new Set<string>(Array.from(quality.excludeFormats));
      for (const f of safeStringArray(mode?.exclude_formats)) {
        excludeFormats.add(String(f).toUpperCase());
      }
      return { minScore, minPopularity, maxPopularity, excludeFormats };
    };

    const getPremiumCandidates = async (mt: MediaType, pCategories: string[] | null): Promise<CandidateRow[]> => {
      const { data: ids, error } = await client.rpc("recommend_ids_premium", {
        p_media_type: mt,
        p_categories: pCategories && pCategories.length ? pCategories : null,
        p_limit: 50,
        p_allow_gimmicks: allowGimmicks,
        p_focus_tag_ids: focusTagIds.length ? focusTagIds : null,
      });
      if (error) throw error;
      const rows = Array.isArray(ids) ? ids : [];
      return rows.map((r: any) => ({
        media_id: Number(r.media_id),
        match_count: r.match_count ?? r.overlap_count ?? 0,
        score: r.score ?? null,
      }));
    };

    type MediaContext = {
      byId: Map<number, any>;
      boostById: Map<number, any>;
      boostedReasonsById: Map<number, string[]>;
    };

    const fetchMediaContext = async (mt: MediaType, idList: number[]): Promise<MediaContext> => {
      const ids = uniq(idList).filter((x) => Number.isFinite(x) && x > 0);
      if (ids.length === 0) return { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() };

      const table = mt === "ANIME" ? "anime" : "manga";
      const { data: mediaRows, error: mediaErr } = await client
        .from(table)
        .select("id,title_english,title_romaji,title_native,cover_image_medium,average_score,popularity,start_date_year,format,status,site_url,is_adult,genres")
        .in("id", ids);
      if (mediaErr) throw mediaErr;
      const byId = new Map<number, any>((mediaRows ?? []).map((r: any) => [r.id, r]));

      const { data: boosts } = await client
        .from("editorial_boosts")
        .select("media_id,label,weight")
        .eq("media_type", mt)
        .in("media_id", ids);
      const boostById = new Map<number, any>((boosts ?? []).map((b: any) => [b.media_id, b]));

      // Get which boosted tags apply to each media id (signals only; not used for ranking).
      let tagLinks: any[] = [];
      if (boostTagIds.length > 0) {
        const linkTable = mt === "ANIME" ? "anime_tags" : "manga_tags";
        const idCol = mt === "ANIME" ? "anime_id" : "manga_id";
        const resLinks = await client
          .from(linkTable)
          .select(`${idCol},tag_id`)
          .in(idCol, ids)
          .in("tag_id", boostTagIds);
        if (!resLinks.error) tagLinks = resLinks.data ?? [];
      }

      const boostedReasonsById = new Map<number, string[]>();
      for (const row of tagLinks) {
        const mediaId = Number(row[mt === "ANIME" ? "anime_id" : "manga_id"]);
        const tagId = Number(row.tag_id);
        const tb = tagBoostByTag.get(tagId);
        const reason = String(tb?.reason ?? "").trim();
        if (!reason) continue;
        const arr = boostedReasonsById.get(mediaId) ?? [];
        if (!arr.includes(reason)) arr.push(reason);
        boostedReasonsById.set(mediaId, arr);
      }

      return { byId, boostById, boostedReasonsById };
    };

    const buildItemsFromRows = (mt: MediaType, rows: CandidateRow[], ctx: MediaContext, opts: {
      limit: number;
      requiredGenres: string[];
      excludeGenres: string[];
      classicYearMax?: number;
      quality: { minScore: number; minPopularity: number; maxPopularity: number | null; excludeFormats: Set<string> };
      prioritizeClassicBoost?: boolean;
    }) => {
      const hasGenres = (m: any, required: string[]) => {
        if (!required.length) return true;
        const gs = Array.isArray(m?.genres) ? m.genres.map((x: any) => String(x)) : [];
        if (!gs.length) return false;
        // Require at least one requested genre to match.
        return required.some((g) => gs.includes(g));
      };

      const hasExcludedGenres = (m: any, excluded: string[]) => {
        if (!excluded.length) return false;
        const gs = Array.isArray(m?.genres) ? m.genres.map((x: any) => String(x)) : [];
        if (!gs.length) return false;
        return excluded.some((g) => gs.includes(g));
      };

      const passes = (m: any) => {
        if (!m) return false;
        if (m.is_adult === true) return false;
        if (opts.quality.excludeFormats.has(String(m.format ?? "").toUpperCase())) return false;
        if (hasExcludedGenres(m, opts.excludeGenres)) return false;

        const year = Number(m.start_date_year ?? 0);
        if (opts.classicYearMax && year > 0 && year > opts.classicYearMax) return false;

        const score = Number(m.average_score ?? 0);
        const pop = Number(m.popularity ?? 0);
        if (opts.quality.minScore > 0 && score > 0 && score < opts.quality.minScore) return false;
        if (opts.quality.minPopularity > 0 && pop > 0 && pop < opts.quality.minPopularity) return false;
        if (opts.quality.maxPopularity != null && pop > 0 && pop > opts.quality.maxPopularity) return false;
        return true;
      };

      // Prefer: genre match + quality; then quality; then anything (no hard failures).
      const primary: CandidateRow[] = [];
      const secondary: CandidateRow[] = [];
      const tertiary: CandidateRow[] = [];

      for (const r of rows) {
        const m = ctx.byId.get(r.media_id);
        if (!m) continue;
        if (passes(m) && hasGenres(m, opts.requiredGenres)) primary.push(r);
        else if (passes(m)) secondary.push(r);
        else tertiary.push(r);
      }

      let ordered = [...primary, ...secondary, ...tertiary];
      if (opts.prioritizeClassicBoost) {
        const boosted: CandidateRow[] = [];
        const rest: CandidateRow[] = [];
        for (const r of ordered) {
          const b = ctx.boostById.get(r.media_id);
          if (b?.label === "classic") boosted.push(r);
          else rest.push(r);
        }
        ordered = [...boosted, ...rest];
      }
      ordered = ordered.slice(0, opts.limit);

      const out: any[] = [];
      for (const r of ordered) {
        const m = ctx.byId.get(r.media_id);
        if (!m) continue;
        const signals: string[] = [];
        const b = ctx.boostById.get(r.media_id);
        if (b?.label === "classic") signals.push("CLASSIC");
        const reasons = ctx.boostedReasonsById.get(r.media_id) ?? [];
        for (const x of reasons.slice(0, 3)) signals.push(String(x).toUpperCase());
        if ((r.match_count ?? 0) >= 2) signals.push("MATCH");

        out.push({
          mediaType: mt,
          mediaId: r.media_id,
          matchCount: r.match_count ?? 0,
          score: r.score ?? null,
          title: m.title_english ?? m.title_romaji ?? m.title_native ?? "Unknown",
          coverImageMedium: m.cover_image_medium ?? null,
          averageScore: m.average_score ?? null,
          year: m.start_date_year ?? null,
          format: m.format ?? null,
          status: m.status ?? null,
          siteUrl: m.site_url ?? null,
          signals,
          genres: Array.isArray(m.genres) ? m.genres : null,
        });
      }
      return out;
    };

    const modePicks = pickTwoModes(text, modes, requiredGenres);
    const modeById = new Map<string, ConciergeMode>(modes.map((m) => [m.id, m]));

    const resolvedModes = modePicks
      .map((mp) => modeById.get(mp.id))
      .filter((m): m is ConciergeMode => Boolean(m));

    const hasClassicMode = resolvedModes.some((m) => m.id.includes("classic"));
    const nonClassicModes = resolvedModes.filter((m) => !m.id.includes("classic"));

    // Pull candidate pools once (per media type), then slice/filter into rails in-memory.
    const unionCats = uniq([
      ...categories,
      ...nonClassicModes.flatMap((m) => m.required_genres ?? []),
    ]);
    const premiumCats = unionCats.length ? unionCats : (categories.length ? categories : null);
    const classicCats = hasClassicMode ? (categories.length ? categories : null) : null;

    const premiumRowsByType: Record<MediaType, CandidateRow[]> = { ANIME: [], MANGA: [] };
    const classicRowsByType: Record<MediaType, CandidateRow[]> = { ANIME: [], MANGA: [] };

    if (mediaType === "ANIME" || mediaType === "BOTH") {
      premiumRowsByType.ANIME = await getPremiumCandidates("ANIME", premiumCats);
      if (hasClassicMode) classicRowsByType.ANIME = await getPremiumCandidates("ANIME", classicCats);
    }
    if (mediaType === "MANGA" || mediaType === "BOTH") {
      premiumRowsByType.MANGA = await getPremiumCandidates("MANGA", premiumCats);
      if (hasClassicMode) classicRowsByType.MANGA = await getPremiumCandidates("MANGA", classicCats);
    }

    const ctxByType: Record<MediaType, MediaContext> = {
      ANIME: { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() },
      MANGA: { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() },
    };
    if (mediaType === "ANIME" || mediaType === "BOTH") {
      const ids = uniq([
        ...premiumRowsByType.ANIME.map((r) => r.media_id),
        ...classicRowsByType.ANIME.map((r) => r.media_id),
      ]);
      ctxByType.ANIME = await fetchMediaContext("ANIME", ids);
    }
    if (mediaType === "MANGA" || mediaType === "BOTH") {
      const ids = uniq([
        ...premiumRowsByType.MANGA.map((r) => r.media_id),
        ...classicRowsByType.MANGA.map((r) => r.media_id),
      ]);
      ctxByType.MANGA = await fetchMediaContext("MANGA", ids);
    }

    // Build up to 2 rails (modes). Always keep a classics rail as the second choice where possible.
    const sets: any[] = [];

    for (const mp of modePicks) {
      const mode = modeById.get(mp.id) ?? null;
      const isClassicMode = (mode?.id ?? mp.id).includes("classic");
      const perSetTotal = isClassicMode ? Math.min(20, Math.max(limit, 14)) : limit;
      const perType = mediaType === "BOTH" ? Math.max(3, Math.ceil(perSetTotal / 2)) : perSetTotal;

      const modeRequired = uniq([...(mode?.required_genres ?? []), ...requiredGenres]);
      const modeExcluded = mode?.exclude_genres ?? [];

      const q = compileQuality(mode);

      const animeRows =
        (mediaType === "ANIME" || mediaType === "BOTH")
          ? (isClassicMode ? classicRowsByType.ANIME : premiumRowsByType.ANIME)
          : [];
      const mangaRows =
        (mediaType === "MANGA" || mediaType === "BOTH")
          ? (isClassicMode ? classicRowsByType.MANGA : premiumRowsByType.MANGA)
          : [];

      const animeItems = (mediaType === "ANIME" || mediaType === "BOTH")
        ? buildItemsFromRows("ANIME", animeRows, ctxByType.ANIME, {
          limit: perType,
          requiredGenres: modeRequired,
          excludeGenres: modeExcluded,
          classicYearMax: mode?.classic_year_max,
          quality: q,
          prioritizeClassicBoost: isClassicMode,
        })
        : [];
      const mangaItems = (mediaType === "MANGA" || mediaType === "BOTH")
        ? buildItemsFromRows("MANGA", mangaRows, ctxByType.MANGA, {
          limit: perType,
          requiredGenres: modeRequired,
          excludeGenres: modeExcluded,
          classicYearMax: mode?.classic_year_max,
          quality: q,
          prioritizeClassicBoost: isClassicMode,
        })
        : [];

      const merged = mediaType === "BOTH" ? mergeAlternating(animeItems, mangaItems, perSetTotal) : [...animeItems, ...mangaItems].slice(0, perSetTotal);

      sets.push({
        id: mp.id,
        title: mp.title,
        modeId: mp.id,
        confidence: mp.confidence,
        reason: mp.reason,
        items: merged,
      });
    }

    // If the user is explicit ("like Vagabond"), offer a similarity rail as the first mode.
    // This keeps the UX feeling "smart" without spending LLM tokens.
    if (seedQuery) {
      // Only override when we can find a decent seed title.
      const pickSeed = async (mt: MediaType) => {
        const { data: seeds, error: seedErr } = await client.rpc("search_titles", {
          p_query: seedQuery,
          p_media_type: mt,
          p_limit: 6,
        });
        if (seedErr || !Array.isArray(seeds) || seeds.length === 0) return null;
        const top = seeds[0];
        if ((top?.score ?? 0) < 0.35) return null;
        return { mt, mediaId: Number(top.media_id), title: String(top.title ?? "").trim() };
      };

      const seed = mediaType === "MANGA" ? await pickSeed("MANGA")
        : mediaType === "ANIME" ? await pickSeed("ANIME")
        : (await pickSeed("ANIME")) ?? (await pickSeed("MANGA"));

      if (seed && Number.isFinite(seed.mediaId) && seed.mediaId > 0) {
        const perSetTotal = limit;
        const perType = mediaType === "BOTH" ? Math.max(3, Math.ceil(perSetTotal / 2)) : perSetTotal;
        const q = compileQuality(null);

        const getSim = async (mt: MediaType) => {
          const { data: sim, error: simErr } = await client.rpc("recommend_ids_similar_to_seeds", {
            p_media_type: mt,
            p_seed_ids: [seed.mediaId],
            p_limit: 50,
            p_allow_gimmicks: allowGimmicks,
          });
          if (simErr || !Array.isArray(sim)) return [] as CandidateRow[];
          return sim.map((r: any) => ({
            media_id: Number(r.media_id),
            match_count: r.overlap_count ?? r.match_count ?? 0,
            score: r.score ?? null,
          }));
        };

        const animeRows = (mediaType === "ANIME" || mediaType === "BOTH") ? await getSim("ANIME") : [];
        const mangaRows = (mediaType === "MANGA" || mediaType === "BOTH") ? await getSim("MANGA") : [];
        const simCtxAnime = (mediaType === "ANIME" || mediaType === "BOTH")
          ? await fetchMediaContext("ANIME", animeRows.map((r) => r.media_id))
          : { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() };
        const simCtxManga = (mediaType === "MANGA" || mediaType === "BOTH")
          ? await fetchMediaContext("MANGA", mangaRows.map((r) => r.media_id))
          : { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() };

        const animeItems = (mediaType === "ANIME" || mediaType === "BOTH")
          ? buildItemsFromRows("ANIME", animeRows, simCtxAnime, { limit: perType, requiredGenres, excludeGenres: [], quality: q })
          : [];
        const mangaItems = (mediaType === "MANGA" || mediaType === "BOTH")
          ? buildItemsFromRows("MANGA", mangaRows, simCtxManga, { limit: perType, requiredGenres, excludeGenres: [], quality: q })
          : [];

        const merged = mediaType === "BOTH" ? mergeAlternating(animeItems, mangaItems, perSetTotal) : [...animeItems, ...mangaItems].slice(0, perSetTotal);
        const title = seed.title || seedQuery;

        // Keep the classics rail as the secondary mode, but replace the primary.
        if (sets.length >= 1) {
          sets[0] = {
            id: "similar_to_seed",
            title: `Similar to “${title}”`,
            modeId: "similar_to_seed",
            confidence: 1,
            reason: "seed similarity",
            items: merged,
          };
        } else {
          sets.unshift({
            id: "similar_to_seed",
            title: `Similar to “${title}”`,
            modeId: "similar_to_seed",
            confidence: 1,
            reason: "seed similarity",
            items: merged,
          });
        }
      }
    }

    // Flatten for backwards compatibility + LLM narration.
    const allItems: any[] = [];
    const seen = new Set<string>();
    for (const s of sets) {
      for (const it of (s?.items ?? [])) {
        const key = `${it.mediaType}|${it.mediaId}`;
        if (seen.has(key)) continue;
        seen.add(key);
        allItems.push(it);
      }
    }

    try {
      await client.rpc("log_concierge_run", {
        p_kind: "recommend",
        p_status: "success",
        p_input_chars: text.length,
        p_items_count: allItems.length,
      });
    } catch {
      // best-effort
    }

    const message = (() => {
      if (sets.length === 0) {
        return categories.length === 0
          ? "Premium picks (new to you). Tell me a vibe like “funny”, “sad”, “cozy”, or a genre to sharpen it."
          : null;
      }
      const titles = sets.slice(0, 2).map((s: any) => String(s.title ?? "")).filter(Boolean);
      if (titles.length >= 2) return `Two rails for you: ${titles[0]} + ${titles[1]}.`;
      if (titles.length === 1) return `Here’s a rail for you: ${titles[0]}.`;
      return null;
    })();

    // Optional narration (pure presentation layer).
    let narrationError: string | null = null;
    if (narrate) {
      // Global kill-switch: keep core recommendations deterministic if disabled.
      const { data: llmEnabled } = await client.rpc("is_flag_enabled", { p_key: "llm_enabled" });
      if (llmEnabled === false) narrate = false;
    }

    if (narrate) {
      const groqKey = Deno.env.get("GROQ_API_KEY");
      const groqModel = Deno.env.get("GROQ_MODEL") ?? "openai/gpt-oss-20b";
      if (groqKey) {
        const maxCompletion = 260;
        const packed = allItems.slice(0, 8).map((it) => ({
          id: `${it.mediaType}|${it.mediaId}`,
          title: it.title,
          year: it.year,
          format: it.format,
          signals: Array.isArray(it.signals) ? it.signals : [],
        }));

        const promptChars = 1200 + text.length + JSON.stringify(packed).length;
        const reserveTokens = Math.min(9000, Math.max(160, Math.ceil(promptChars / 4) + maxCompletion));

        // Reserve budget. If exceeded, just return without blurbs.
        const { data: budget } = await client.rpc("llm_budget_reserve", {
          p_reserved_tokens: reserveTokens,
          p_max_daily_tokens: null,
          p_max_daily_calls: null,
          p_model: groqModel,
        });
        if (budget && budget.allowed === false) {
          narrate = false;
        }

        // Global budget (prevents "many users" abuse).
        let gReserveOk = true;
        if (narrate) {
          try {
            const globalBudget = conciergeCfg?.global_llm_budget ?? null;
            const globalDailyTokens = Number(globalBudget?.daily_tokens ?? 250000);
            const globalDailyCalls = Number(globalBudget?.daily_calls ?? 600);
            const { data: gBudget } = await client.rpc("llm_global_budget_reserve", {
              p_reserved_tokens: reserveTokens,
              p_max_daily_tokens: Number.isFinite(globalDailyTokens) ? globalDailyTokens : 250000,
              p_max_daily_calls: Number.isFinite(globalDailyCalls) ? globalDailyCalls : 600,
            });
            if (gBudget && gBudget.allowed === false) gReserveOk = false;
          } catch {
            // If config/global budget fails for some reason, fail closed (no narration).
            gReserveOk = false;
          }
          if (!gReserveOk) {
            narrate = false;
            try {
              await client.rpc("llm_budget_finalize", { p_reserved_tokens: reserveTokens, p_actual_tokens: 0, p_model: groqModel });
            } catch {
              // ignore
            }
          }
        }

        try {
          if (!narrate) throw new Error("LLM budget exceeded");

          const { blurbs, usageTotal } = await groqNarrate({
            apiKey: groqKey,
            model: groqModel,
            lang,
            userText: text,
            debug: debugNarration,
            items: packed,
          });
          for (const it of allItems) {
            const key = `${it.mediaType}|${it.mediaId}`;
            const b = blurbs[key];
            if (typeof b === "string" && b.trim()) it.blurb = clampBlurb(b, 18, 180);
          }

          // Finalize with actual usage if available; else treat reserve as actual.
          try {
            const actual = usageTotal ?? reserveTokens;
            await client.rpc("llm_budget_finalize", {
              p_reserved_tokens: reserveTokens,
              p_actual_tokens: actual,
              p_model: groqModel,
            });
            await client.rpc("llm_global_budget_finalize", {
              p_reserved_tokens: reserveTokens,
              p_actual_tokens: actual,
            });
          } catch {
            // best-effort
          }
        } catch (e) {
          // Release reservation on failure (best-effort).
          try {
            await client.rpc("llm_budget_finalize", {
              p_reserved_tokens: reserveTokens,
              p_actual_tokens: 0,
              p_model: groqModel,
            });
            await client.rpc("llm_global_budget_finalize", {
              p_reserved_tokens: reserveTokens,
              p_actual_tokens: 0,
            });
          } catch {
            // best-effort
          }
          narrationError = (e as Error)?.message ?? String(e);
        }
      } else {
        narrate = false;
      }
    }

    return json({
      success: true,
      categories,
      modes: modePicks,
      sets,
      // Backwards compat: clients that only understand `items` still get a useful response.
      items: allItems,
      message,
      narrated: narrate,
      ...(debugNarration ? { narrationError } : {}),
    });
  } catch (e) {
    const err = e as Error;
    return json({ error: "Internal error", message: err?.message ?? String(e) }, { status: 500 });
  }
});

```

### Edge Function: concierge-apply (idempotent upserts)

- Path: `supabase/functions/concierge-apply/index.ts`


```ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MediaType = "ANIME" | "MANGA";
type ListStatus = "WATCHING" | "READING" | "PLANNING" | "COMPLETED" | "DROPPED" | "PAUSED";

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function clampInt(v: unknown, min: number, max: number) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return null;
  return Math.max(min, Math.min(max, n));
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

function normalizeAliasKey(raw: string): string {
  let s = String(raw ?? "").toLowerCase();
  s = s.replace(/\u00a0/g, " ");
  // strip filler + verbs/status
  s = s.replace(/\b(um+|uh+|erm+|eh+|like|also|äh+|ae+h+|so|halt)\b/giu, " ");
  s = s.replace(/\b(i\s+have|i'?m|im|i\s+am|i)\b/giu, " ");
  s = s.replace(/\b(ich\s+habe|ich\s+hab|ich|bin)\b/giu, " ");
  s = s.replace(
    /\b(watched|watching|finished|completed|dropped|paused|planning|read|reading|caught up|up to date|seen|saw)\b/giu,
    " ",
  );
  s = s.replace(
    /\b(geschaut|gesehen|gelesen|fertig|abgeschlossen|beendet|abgebrochen|pausiert|geplant|aktuell|komplett|vollständig|vollstaendig)\b/giu,
    " ",
  );
  // strip progress markers
  s = s.replace(/\b(?:season|staffel|episode|ep|folge|chapter|ch|kapitel|volume|vol|band)\b/giu, " ");
  s = s.replace(/\b\d{1,2}\s*x\s*\d{1,4}\b/giu, " ");
  s = s.replace(/\bs\d{1,2}\s*e\d{1,4}\b/giu, " ");
  // keep only letters/numbers/spaces (unicode)
  s = s.replace(/[^\p{L}\p{N}\s]+/gu, " ");
  s = s.replace(/\s+/g, " ").trim();
  return s.slice(0, 160);
}

async function bumpTitleAlias(client: any, args: {
  userId: string;
  aliasNorm: string;
  mediaType: MediaType;
  mediaId: number;
  titleRaw?: string | null;
}) {
  const aliasNorm = args.aliasNorm;
  if (!aliasNorm) return;

  const existing = await client
    .from("title_aliases")
    .select("hits")
    .eq("user_id", args.userId)
    .eq("alias_norm", aliasNorm)
    .eq("media_type", args.mediaType)
    .maybeSingle();

  const nextHits = clampInt((existing.data?.hits ?? 0) + 1, 1, 1_000_000) ?? 1;

  await client
    .from("title_aliases")
    .upsert({
      user_id: args.userId,
      alias_norm: aliasNorm,
      media_type: args.mediaType,
      media_id: args.mediaId,
      title_raw: args.titleRaw ?? null,
      hits: nextHits,
    }, { onConflict: "user_id,alias_norm,media_type" });
}

async function fetchLatestEpisodeNumber(client: any, animeId: number): Promise<number | null> {
  const res = await client
    .from("episodes")
    .select("number")
    .eq("anime_id", animeId)
    .not("number", "is", null)
    .order("number", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (res.error) return null;
  const n = clampInt(res.data?.number, 0, 100_000);
  return n ?? null;
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseKey = supabaseAnon ?? supabaseService;
    if (!supabaseUrl || !supabaseKey) {
      return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const client = createClient(supabaseUrl, supabaseKey, {
      global: { headers: authHeader ? { Authorization: authHeader } : {} },
    });

    const { data: userData, error: userErr } = await client.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });
    const userId = userData.user.id;

    const ip = clientIp(req);
    const { data: rl } = await client.rpc("check_concierge_rate_limit", {
      p_kind: "apply",
      p_ip: ip,
      p_window_seconds: null,
      p_max_user: null,
      p_max_ip: null,
    });
    if (rl && rl.allowed === false) {
      return json(
        { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
        { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
      );
    }

    const body = await req.json().catch(() => ({}));
    const items: any[] = Array.isArray(body?.items) ? body.items : [];
    if (items.length === 0) return json({ success: true, applied: 0, sessionId: null, errors: [] });

    // Create an import session so we can support undo.
    const { data: sessionRow, error: sessionErr } = await client
      .from("import_sessions")
      .insert({ user_id: userId, status: "draft", source: "chat" })
      .select("id")
      .single();
    if (sessionErr || !sessionRow?.id) {
      return json({ error: `Failed to create import session: ${sessionErr?.message ?? "unknown"}` }, { status: 500 });
    }
    const sessionId: string = sessionRow.id;

    const applied: any[] = [];
    const errors: any[] = [];

    for (const it of items) {
      const mediaType: MediaType | null = it?.mediaType === "ANIME" || it?.mediaType === "MANGA" ? it.mediaType : null;
      const mediaId: number | null = clampInt(it?.mediaId, 1, 2_000_000_000);
      let status: ListStatus | null =
        typeof it?.status === "string" ? (it.status.toUpperCase() as ListStatus) : null;

      if (!mediaType || !mediaId || !status) {
        errors.push({ item: it, error: "Invalid mediaType/mediaId/status" });
        continue;
      }

      try {
        if (mediaType === "ANIME") {
          const explicitComplete = it?.lastEpisode === true || it?.completed === true;
          const caughtUp = it?.caughtUp === true;
          if (explicitComplete && status !== "COMPLETED") status = "COMPLETED";

          let progress = clampInt(it?.progressEpisodes, 0, 100_000) ?? clampInt(it?.progress, 0, 100_000);

          // If the user says "caught up" or "last episode" without a number, compute best-effort progress.
          if (progress == null && (caughtUp || status === "COMPLETED")) {
            const { data: animeRow } = await client
              .from("anime")
              .select("episodes,next_episode_number,status")
              .eq("id", mediaId)
              .maybeSingle();

            const nextEp = clampInt(animeRow?.next_episode_number, 0, 100_000);
            const totalKnown = clampInt(animeRow?.episodes, 0, 100_000);

            if (status === "COMPLETED") {
              progress = totalKnown ?? await fetchLatestEpisodeNumber(client, mediaId);
            } else if (caughtUp) {
              progress = nextEp != null && nextEp > 0 ? Math.max(0, nextEp - 1) : (await fetchLatestEpisodeNumber(client, mediaId));
            }
          }

          const before = await client
            .from("anime_user_lists")
            .select("list_type,progress,rating,notes")
            .eq("user_id", userId)
            .eq("anime_id", mediaId)
            .maybeSingle();
          if (before.error) throw before.error;

          const seasonNumber = clampInt(it?.seasonNumber, 1, 100);
          const episodeInSeason = clampInt(it?.episodeInSeason, 0, 100_000);
          const seasonNote = seasonNumber && episodeInSeason ? `S${seasonNumber}E${episodeInSeason}` : null;
          const rawNotes = typeof it?.notes === "string" ? it.notes.slice(0, 2000) : null;
          const notes = seasonNote && !rawNotes ? seasonNote : rawNotes;

          const payload = {
            user_id: userId,
            anime_id: mediaId,
            list_type: status,
            progress: progress ?? null,
            rating: clampInt(it?.rating, 0, 10),
            notes,
          };
          const { error } = await client.from("anime_user_lists").upsert(payload as any, {
            onConflict: "user_id,anime_id",
          });
          if (error) throw error;

          try {
            const aliasNorm = normalizeAliasKey(it?.raw ?? it?.normalized ?? "");
            await bumpTitleAlias(client, {
              userId,
              aliasNorm,
              mediaType: "ANIME",
              mediaId,
              titleRaw: typeof it?.titleRaw === "string" ? it.titleRaw : null,
            });
          } catch {
            // best-effort
          }

          await client.from("import_session_items").insert({
            session_id: sessionId,
            raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
            parsed: {
              status,
              progressEpisodes: progress ?? null,
              seasonNumber: seasonNumber ?? null,
              episodeInSeason: episodeInSeason ?? null,
              caughtUp: caughtUp || null,
              lastEpisode: explicitComplete || null,
            },
            candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
            chosen: { mediaType, mediaId },
            action: {
              table: "anime_user_lists",
              key: { user_id: userId, anime_id: mediaId },
              before: before.data ?? null,
              after: payload,
            },
            confidence: typeof it?.confidence === "number" ? it.confidence : 0,
            state: "applied",
          });
        } else {
          const explicitComplete = it?.completed === true;
          const caughtUp = it?.caughtUp === true;
          if (explicitComplete && status !== "COMPLETED") status = "COMPLETED";

          let progress = clampInt(it?.progressChapters, 0, 500_000) ?? clampInt(it?.progress, 0, 500_000);
          if (progress == null && (caughtUp || status === "COMPLETED")) {
            const { data: mangaRow } = await client
              .from("manga")
              .select("chapters,status")
              .eq("id", mediaId)
              .maybeSingle();
            const totalKnown = clampInt(mangaRow?.chapters, 0, 500_000);
            if (totalKnown != null) progress = totalKnown;
          }

          const before = await client
            .from("manga_user_lists")
            .select("list_type,progress,rating,notes")
            .eq("user_id", userId)
            .eq("manga_id", mediaId)
            .maybeSingle();
          if (before.error) throw before.error;
          const payload = {
            user_id: userId,
            manga_id: mediaId,
            list_type: status,
            progress: progress ?? null,
            rating: clampInt(it?.rating, 0, 10),
            notes: typeof it?.notes === "string" ? it.notes.slice(0, 2000) : null,
          };
          const { error } = await client.from("manga_user_lists").upsert(payload as any, {
            onConflict: "user_id,manga_id",
          });
          if (error) throw error;

          try {
            const aliasNorm = normalizeAliasKey(it?.raw ?? it?.normalized ?? "");
            await bumpTitleAlias(client, {
              userId,
              aliasNorm,
              mediaType: "MANGA",
              mediaId,
              titleRaw: typeof it?.titleRaw === "string" ? it.titleRaw : null,
            });
          } catch {
            // best-effort
          }

          await client.from("import_session_items").insert({
            session_id: sessionId,
            raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
            parsed: {
              status,
              progressChapters: progress ?? null,
              caughtUp: caughtUp || null,
            },
            candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
            chosen: { mediaType, mediaId },
            action: {
              table: "manga_user_lists",
              key: { user_id: userId, manga_id: mediaId },
              before: before.data ?? null,
              after: payload,
            },
            confidence: typeof it?.confidence === "number" ? it.confidence : 0,
            state: "applied",
          });
        }

        applied.push({ mediaType, mediaId, status });
      } catch (e) {
        errors.push({ mediaType, mediaId, error: (e as Error).message ?? String(e) });
        await client.from("import_session_items").insert({
          session_id: sessionId,
          raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType ?? "UNKNOWN"}:${mediaId ?? "?"}`,
          parsed: it?.parsed ?? {},
          candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
          chosen: mediaType && mediaId ? { mediaType, mediaId } : null,
          action: null,
          confidence: typeof it?.confidence === "number" ? it.confidence : 0,
          state: "error",
          error: ((e as Error).message ?? String(e)).slice(0, 500),
        });
      }
    }

    await client.from("import_sessions").update({
      status: errors.length ? "failed" : "applied",
    }).eq("id", sessionId);

    try {
      await client.rpc("log_concierge_run", {
        p_kind: "apply",
        p_status: errors.length ? "error" : "success",
        p_items_count: items.length,
        p_error: errors.length ? JSON.stringify(errors).slice(0, 1000) : null,
      });
    } catch {
      // Best-effort metrics only.
    }

    return json({ success: errors.length === 0, sessionId, applied, errors });
  } catch (e) {
    const err = e as Error;
    return json(
      {
        error: "Internal error",
        message: err?.message ?? String(e),
      },
      { status: 500 },
    );
  }
});

```

### Edge Function: concierge-undo (session rollback)

- Path: `supabase/functions/concierge-undo/index.ts`


```ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MediaType = "ANIME" | "MANGA";
type ListStatus = "WATCHING" | "READING" | "PLANNING" | "COMPLETED" | "DROPPED" | "PAUSED";

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function clampInt(v: unknown, min: number, max: number) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return null;
  return Math.max(min, Math.min(max, n));
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseKey = supabaseAnon ?? supabaseService;
    if (!supabaseUrl || !supabaseKey) {
      return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const client = createClient(supabaseUrl, supabaseKey, {
      global: { headers: authHeader ? { Authorization: authHeader } : {} },
    });

    const { data: userData, error: userErr } = await client.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });
    const userId = userData.user.id;

    const ip = clientIp(req);
    const { data: rl } = await client.rpc("check_concierge_rate_limit", {
      p_kind: "undo",
      p_ip: ip,
      p_window_seconds: null,
      p_max_user: null,
      p_max_ip: null,
    });
    if (rl && rl.allowed === false) {
      return json(
        { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
        { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
      );
    }

    const body = await req.json().catch(() => ({}));
    const sessionId = typeof body?.sessionId === "string" ? body.sessionId : null;
    if (!sessionId) return json({ error: "Missing sessionId" }, { status: 400 });

  const session = await client
    .from("import_sessions")
    .select("id,user_id,status")
    .eq("id", sessionId)
    .maybeSingle();

  if (session.error) return json({ error: session.error.message }, { status: 500 });
  if (!session.data) return json({ error: "Not found" }, { status: 404 });
  if (session.data.user_id !== userId) return json({ error: "Forbidden" }, { status: 403 });

  const itemsRes = await client
    .from("import_session_items")
    .select("id,chosen,action,state")
    .eq("session_id", sessionId);
  if (itemsRes.error) return json({ error: itemsRes.error.message }, { status: 500 });

  const reverted: any[] = [];
  const errors: any[] = [];

  for (const row of itemsRes.data ?? []) {
    try {
      const chosen = row?.chosen ?? {};
      const mediaType: MediaType | null = chosen?.mediaType === "ANIME" || chosen?.mediaType === "MANGA" ? chosen.mediaType : null;
      const mediaId: number | null = clampInt(chosen?.mediaId, 1, 2_000_000_000);
      if (!mediaType || !mediaId) continue;

      const action = row?.action ?? {};
      const before = action?.before ?? null;

      if (mediaType === "ANIME") {
        if (!before) {
          const del = await client
            .from("anime_user_lists")
            .delete()
            .eq("user_id", userId)
            .eq("anime_id", mediaId);
          if (del.error) throw del.error;
        } else {
          const payload = {
            user_id: userId,
            anime_id: mediaId,
            list_type: (before?.list_type as ListStatus) ?? "PLANNING",
            progress: before?.progress ?? null,
            rating: before?.rating ?? null,
            notes: before?.notes ?? null,
          };
          const up = await client
            .from("anime_user_lists")
            .upsert(payload as any, { onConflict: "user_id,anime_id" });
          if (up.error) throw up.error;
        }
      } else {
        if (!before) {
          const del = await client
            .from("manga_user_lists")
            .delete()
            .eq("user_id", userId)
            .eq("manga_id", mediaId);
          if (del.error) throw del.error;
        } else {
          const payload = {
            user_id: userId,
            manga_id: mediaId,
            list_type: (before?.list_type as ListStatus) ?? "PLANNING",
            progress: before?.progress ?? null,
            rating: before?.rating ?? null,
            notes: before?.notes ?? null,
          };
          const up = await client
            .from("manga_user_lists")
            .upsert(payload as any, { onConflict: "user_id,manga_id" });
          if (up.error) throw up.error;
        }
      }

      reverted.push({ mediaType, mediaId });
    } catch (e) {
      errors.push({ id: row?.id, error: (e as Error).message ?? String(e) });
    }
  }

  await client.from("import_sessions").update({ status: "cancelled" }).eq("id", sessionId);

  try {
    await client.rpc("log_concierge_run", {
      p_kind: "undo",
      p_status: errors.length ? "error" : "success",
      p_items_count: (itemsRes.data ?? []).length,
      p_error: errors.length ? JSON.stringify(errors).slice(0, 1000) : null,
    });
  } catch {
    // Best-effort metrics only.
  }

    return json({ success: errors.length === 0, sessionId, reverted, errors });
  } catch (e) {
    const err = e as Error;
    return json(
      {
        error: "Internal error",
        message: err?.message ?? String(e),
      },
      { status: 500 },
    );
  }
});

```

### DB: Concierge rate limits + LLM budgets (source)

- Path: `supabase/migrations/20260204221500_concierge_rate_limits_and_llm_budgets.sql`


```sql
-- Server-side guardrails for Concierge:
-- - Rate limits (per-user and per-IP) for Edge Functions
-- - LLM daily budget + global kill-switch flag

begin;

-- 1) Kill switch / flags (readable via SECURITY DEFINER function).
create table if not exists public.system_flags (
  key text primary key,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.system_flags enable row level security;

-- No policies: clients cannot read flags directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'system_flags_set_updated_at') then
    create trigger system_flags_set_updated_at
      before update on public.system_flags
      for each row execute function public.set_updated_at();
  end if;
end $$;

insert into public.system_flags(key, enabled)
values ('llm_enabled', true)
on conflict (key) do nothing;

create or replace function public.is_flag_enabled(p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v boolean;
begin
  select enabled into v from public.system_flags where key = p_key;
  return coalesce(v, true);
end $$;

grant execute on function public.is_flag_enabled(text) to anon, authenticated;

-- 2) Rate limit buckets (atomic upsert increments).
create table if not exists public.rate_limit_buckets (
  bucket_key text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (bucket_key, window_start)
);

create index if not exists idx_rate_limit_buckets_window_start on public.rate_limit_buckets (window_start desc);

alter table public.rate_limit_buckets enable row level security;
-- No policies: users cannot read/write buckets directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'rate_limit_buckets_set_updated_at') then
    create trigger rate_limit_buckets_set_updated_at
      before update on public.rate_limit_buckets
      for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.rate_limit_hit(
  p_bucket_key text,
  p_window_seconds integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare wstart timestamptz;
declare v integer;
begin
  if p_bucket_key is null or length(p_bucket_key) = 0 then
    raise exception 'rate_limit_hit: missing bucket_key';
  end if;
  if p_window_seconds is null or p_window_seconds < 1 or p_window_seconds > 86400 then
    raise exception 'rate_limit_hit: invalid window_seconds';
  end if;

  -- Fixed window bucket aligned to epoch.
  wstart := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);

  insert into public.rate_limit_buckets(bucket_key, window_start, hits)
  values (p_bucket_key, wstart, 1)
  on conflict (bucket_key, window_start)
  do update set hits = public.rate_limit_buckets.hits + 1, updated_at = now()
  returning hits into v;

  return v;
end $$;

grant execute on function public.rate_limit_hit(text, integer) to anon, authenticated;

create or replace function public.check_concierge_rate_limit(
  p_kind text,
  p_ip text,
  p_window_seconds integer default 60,
  p_max_user integer default 40,
  p_max_ip integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare u_hits integer;
declare ip_hits integer;
declare allow boolean := true;
declare retry_after integer;
declare kind text;
begin
  uid := auth.uid();
  kind := coalesce(nullif(p_kind, ''), 'any');

  if uid is null and (p_ip is null or length(p_ip) = 0) then
    return jsonb_build_object('allowed', true, 'note', 'no uid/ip');
  end if;

  if uid is not null then
    u_hits := public.rate_limit_hit('user:' || uid::text || ':' || kind || ':' || p_window_seconds::text, p_window_seconds);
    if u_hits > coalesce(p_max_user, 0) then allow := false; end if;
  end if;

  if p_ip is not null and length(p_ip) > 0 then
    ip_hits := public.rate_limit_hit('ip:' || p_ip || ':' || kind || ':' || p_window_seconds::text, p_window_seconds);
    if ip_hits > coalesce(p_max_ip, 0) then allow := false; end if;
  end if;

  retry_after := p_window_seconds - (extract(epoch from now())::integer % p_window_seconds);
  return jsonb_build_object(
    'allowed', allow,
    'user_hits', u_hits,
    'ip_hits', ip_hits,
    'retry_after_s', retry_after
  );
end $$;

grant execute on function public.check_concierge_rate_limit(text, text, integer, integer, integer) to anon, authenticated;

-- 3) LLM daily budget (reserve + finalize to keep budgets accurate and concurrency-safe).
create table if not exists public.llm_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  reserved_tokens integer not null default 0,
  actual_tokens integer not null default 0,
  calls integer not null default 0,
  last_model text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.llm_daily_usage enable row level security;
-- No policies: users cannot read/write usage directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'llm_daily_usage_set_updated_at') then
    create trigger llm_daily_usage_set_updated_at
      before update on public.llm_daily_usage
      for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.llm_budget_reserve(
  p_reserved_tokens integer,
  p_max_daily_tokens integer default 20000,
  p_max_daily_calls integer default 80,
  p_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare d date;
declare used_tokens integer;
declare used_calls integer;
declare next_tokens integer;
declare next_calls integer;
declare allow boolean;
declare lock_key bigint;
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;

  lock_key := hashtext(uid::text || ':' || d::text || ':llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  select
    coalesce(actual_tokens, 0) + coalesce(reserved_tokens, 0),
    coalesce(calls, 0)
  into used_tokens, used_calls
  from public.llm_daily_usage
  where user_id = uid and day = d;

  next_tokens := coalesce(used_tokens, 0) + p_reserved_tokens;
  next_calls := coalesce(used_calls, 0) + 1;

  allow :=
    next_tokens <= coalesce(p_max_daily_tokens, 0)
    and next_calls <= coalesce(p_max_daily_calls, 0);

  if allow then
    insert into public.llm_daily_usage(user_id, day, reserved_tokens, actual_tokens, calls, last_model)
    values (uid, d, p_reserved_tokens, 0, 1, p_model)
    on conflict (user_id, day)
    do update set
      reserved_tokens = public.llm_daily_usage.reserved_tokens + excluded.reserved_tokens,
      calls = public.llm_daily_usage.calls + 1,
      last_model = coalesce(excluded.last_model, public.llm_daily_usage.last_model),
      updated_at = now();
  end if;

  return jsonb_build_object(
    'allowed', allow,
    'day', d::text,
    'used_tokens', coalesce(used_tokens, 0),
    'used_calls', coalesce(used_calls, 0),
    'next_tokens', next_tokens,
    'next_calls', next_calls,
    'max_daily_tokens', p_max_daily_tokens,
    'max_daily_calls', p_max_daily_calls
  );
end $$;

create or replace function public.llm_budget_finalize(
  p_reserved_tokens integer,
  p_actual_tokens integer,
  p_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare d date;
declare lock_key bigint;
declare r integer;
declare a integer;
declare tokens_total integer;
declare reserved_total integer;
declare actual_total integer;
declare calls_total integer;
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('success', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  r := greatest(0, least(coalesce(p_reserved_tokens, 0), 500000));
  a := greatest(0, least(coalesce(p_actual_tokens, 0), 500000));

  lock_key := hashtext(uid::text || ':' || d::text || ':llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  -- Ensure row exists even if finalize is called after a failed reserve (best-effort).
  insert into public.llm_daily_usage(user_id, day, reserved_tokens, actual_tokens, calls, last_model)
  values (uid, d, 0, 0, 0, p_model)
  on conflict (user_id, day) do nothing;

  update public.llm_daily_usage
  set
    reserved_tokens = greatest(0, reserved_tokens - r),
    actual_tokens = actual_tokens + a,
    last_model = coalesce(p_model, last_model),
    updated_at = now()
  where user_id = uid and day = d;

  select reserved_tokens, actual_tokens, calls
  into reserved_total, actual_total, calls_total
  from public.llm_daily_usage
  where user_id = uid and day = d;

  tokens_total := coalesce(reserved_total, 0) + coalesce(actual_total, 0);
  return jsonb_build_object(
    'success', true,
    'day', d::text,
    'reserved_tokens', coalesce(reserved_total, 0),
    'actual_tokens', coalesce(actual_total, 0),
    'tokens_total', coalesce(tokens_total, 0),
    'calls', coalesce(calls_total, 0)
  );
end $$;

grant execute on function public.llm_budget_reserve(integer, integer, integer, text) to authenticated;
grant execute on function public.llm_budget_finalize(integer, integer, text) to authenticated;

commit;

```

### DB: Global LLM budget + defaults (source)

- Path: `supabase/migrations/20260205000500_concierge_global_llm_budget_and_default_tuning.sql`


```sql
-- Add global LLM daily budget + tune default "natural usage" limits.
-- Goal: prevent LLM spend abuse even with many users.

begin;

-- 1) Global daily usage table.
create table if not exists public.llm_global_daily_usage (
  day date primary key,
  reserved_tokens integer not null default 0,
  actual_tokens integer not null default 0,
  calls integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.llm_global_daily_usage enable row level security;
-- No policies: clients cannot read/write global usage directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'llm_global_daily_usage_set_updated_at') then
    create trigger llm_global_daily_usage_set_updated_at
      before update on public.llm_global_daily_usage
      for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.llm_global_budget_reserve(
  p_reserved_tokens integer,
  p_max_daily_tokens integer,
  p_max_daily_calls integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare d date;
declare used_tokens integer;
declare used_calls integer;
declare next_tokens integer;
declare next_calls integer;
declare allow boolean;
declare lock_key bigint;
begin
  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;
  if p_max_daily_tokens is null or p_max_daily_tokens < 0 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_max_daily_tokens');
  end if;
  if p_max_daily_calls is null or p_max_daily_calls < 0 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_max_daily_calls');
  end if;

  lock_key := hashtext(d::text || ':global_llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  select coalesce(actual_tokens, 0) + coalesce(reserved_tokens, 0), coalesce(calls, 0)
  into used_tokens, used_calls
  from public.llm_global_daily_usage
  where day = d;

  next_tokens := coalesce(used_tokens, 0) + p_reserved_tokens;
  next_calls := coalesce(used_calls, 0) + 1;

  allow := next_tokens <= p_max_daily_tokens and next_calls <= p_max_daily_calls;

  if allow then
    insert into public.llm_global_daily_usage(day, reserved_tokens, actual_tokens, calls)
    values (d, p_reserved_tokens, 0, 1)
    on conflict (day) do update set
      reserved_tokens = public.llm_global_daily_usage.reserved_tokens + excluded.reserved_tokens,
      calls = public.llm_global_daily_usage.calls + 1,
      updated_at = now();
  end if;

  return jsonb_build_object(
    'allowed', allow,
    'day', d::text,
    'used_tokens', coalesce(used_tokens, 0),
    'used_calls', coalesce(used_calls, 0),
    'next_tokens', next_tokens,
    'next_calls', next_calls,
    'max_daily_tokens', p_max_daily_tokens,
    'max_daily_calls', p_max_daily_calls
  );
end $$;

create or replace function public.llm_global_budget_finalize(
  p_reserved_tokens integer,
  p_actual_tokens integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare d date;
declare lock_key bigint;
declare r integer;
declare a integer;
declare reserved_total integer;
declare actual_total integer;
declare calls_total integer;
begin
  d := (timezone('utc', now()))::date;
  r := greatest(0, least(coalesce(p_reserved_tokens, 0), 500000));
  a := greatest(0, least(coalesce(p_actual_tokens, 0), 500000));

  lock_key := hashtext(d::text || ':global_llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  insert into public.llm_global_daily_usage(day, reserved_tokens, actual_tokens, calls)
  values (d, 0, 0, 0)
  on conflict (day) do nothing;

  update public.llm_global_daily_usage
  set
    reserved_tokens = greatest(0, reserved_tokens - r),
    actual_tokens = actual_tokens + a,
    updated_at = now()
  where day = d;

  select reserved_tokens, actual_tokens, calls
  into reserved_total, actual_total, calls_total
  from public.llm_global_daily_usage
  where day = d;

  return jsonb_build_object(
    'success', true,
    'day', d::text,
    'reserved_tokens', coalesce(reserved_total, 0),
    'actual_tokens', coalesce(actual_total, 0),
    'calls', coalesce(calls_total, 0)
  );
end $$;

grant execute on function public.llm_global_budget_reserve(integer, integer, integer) to authenticated;
grant execute on function public.llm_global_budget_finalize(integer, integer) to authenticated;

-- 2) Patch default config with "natural usage" limits + global budget.
update public.concierge_config
set config =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        config,
        '{llm_budget}',
        jsonb_build_object('daily_tokens', 12000, 'daily_calls', 40),
        true
      ),
      '{global_llm_budget}',
      jsonb_build_object('daily_tokens', 250000, 'daily_calls', 600),
      true
    ),
    '{rate_limits}',
    jsonb_build_object(
      'parse', jsonb_build_object('window_seconds', 60, 'max_user', 120, 'max_ip', 300),
      'apply', jsonb_build_object('window_seconds', 60, 'max_user', 12, 'max_ip', 50),
      'undo', jsonb_build_object('window_seconds', 60, 'max_user', 6, 'max_ip', 20),
      'resolve', jsonb_build_object('window_seconds', 60, 'max_user', 10, 'max_ip', 40),
      'recommend', jsonb_build_object('window_seconds', 60, 'max_user', 20, 'max_ip', 80)
    ),
    true
  )
where id = true;

commit;


```

### DB: Admin schema snapshot RPC (source)

- Path: `supabase/migrations/20260205160000_admin_schema_snapshot.sql`


```sql
-- Admin-only schema snapshot RPC for documentation and drift detection.
-- This is intended to be callable only with the Supabase service role key.
--
-- Why:
-- - The repo schema (migrations) is the primary source of truth, but production/dev DB can drift.
-- - This RPC provides a safe way to fetch *metadata* (not data) for auditing and docs generation.
--
-- Safety:
-- - SECURITY DEFINER so it can read catalogs (and cron schema if present).
-- - EXECUTE is granted ONLY to service_role; revoked from PUBLIC.

create or replace function public.admin_schema_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog, information_schema
as $$
declare
  cron_exists boolean := (to_regclass('cron.job') is not null);
  out jsonb;
begin
  out := jsonb_build_object(
    'generated_at', now(),
    'schemas', jsonb_build_object(
      'included', jsonb_build_array('public', 'auth', 'storage', 'cron')
    ),
    'extensions', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'name', extname,
        'schema', nspname,
        'version', extversion
      ) order by extname), '[]'::jsonb)
      from pg_extension e
      join pg_namespace n on n.oid = e.extnamespace
    ),
    'tables', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'schema', table_schema,
        'name', table_name,
        'type', table_type
      ) order by table_schema, table_name), '[]'::jsonb)
      from information_schema.tables
      where table_schema in ('public', 'auth', 'storage', 'cron')
        and table_type in ('BASE TABLE', 'VIEW')
    ),
    'columns', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'schema', table_schema,
        'table', table_name,
        'column', column_name,
        'ordinal', ordinal_position,
        'data_type', data_type,
        'udt_name', udt_name,
        'is_nullable', is_nullable,
        'column_default', column_default
      ) order by table_schema, table_name, ordinal_position), '[]'::jsonb)
      from information_schema.columns
      where table_schema in ('public', 'auth', 'storage', 'cron')
    ),
    'functions', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'schema', n.nspname,
        'name', p.proname,
        'args', pg_get_function_identity_arguments(p.oid),
        'returns', pg_get_function_result(p.oid),
        'security_definer', p.prosecdef,
        'language', l.lanname
      ) order by n.nspname, p.proname), '[]'::jsonb)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
      where n.nspname in ('public')
        and p.proname not like 'pg_%'
    ),
    'policies', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'schema', schemaname,
        'table', tablename,
        'name', policyname,
        'roles', roles,
        'cmd', cmd,
        'permissive', permissive,
        'qual', qual,
        'with_check', with_check
      ) order by schemaname, tablename, policyname), '[]'::jsonb)
      from pg_policies
      where schemaname in ('public')
    ),
    'cron_jobs', (
      case
        when cron_exists then (
          select coalesce(jsonb_agg(jsonb_build_object(
            'jobid', jobid,
            'schedule', schedule,
            'command', command,
            'nodename', nodename,
            'nodeport', nodeport,
            'database', database,
            'username', username,
            'active', active
          ) order by jobid), '[]'::jsonb)
          from cron.job
        )
        else jsonb_build_object('note', 'cron.job not present (pg_cron not installed or schema not exposed)')
      end
    )
  );

  return out;
end;
$$;

revoke all on function public.admin_schema_snapshot() from public;
grant execute on function public.admin_schema_snapshot() to service_role;


```


<!-- END AUTO-SOURCE-EXCERPTS -->
