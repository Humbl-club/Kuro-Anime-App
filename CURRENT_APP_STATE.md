# Kuro — Current State of the Application (Authoritative, Technical)

**Last updated:** 2026-03-26

This document is the **authoritative, technical snapshot** of the Kuro app (iOS client + Supabase backend) and the current codebase. It is written for engineers and LLMs that need a complete and precise understanding of how the system works today.

**Current repo inventory:** 88 app Swift files in `/Kuro`; 169 SQL migrations in `/supabase/migrations`.
**Current staged/live note:** provider availability remains staged behind `streaming_availability_v1` at 0%; live watch/read links still come from `external_links`.
Historical change-log entries below may include point-in-time counts. Treat them as historical context, not current inventory.

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
   python3 scripts/quality-gates/check_docs_current_state.py
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
- Local synopsis enrichment runtime: launchd-managed Mac worker (`scripts/synopsis_enrichment_worker.swift`) continuously generates editorial synopsis variants and writes them to Supabase via RPC (non-destructive, enhanced fields only).
- Local catalog safety runtime: separate launchd-managed Mac worker (`scripts/catalog_safety_worker.swift`) scans anime/manga records for pornographic signals, writes safety state via dedicated RPCs, and emits uncertain/open-gap reports to a separate dashboard/report path.

**Backend:** Supabase (Postgres + Edge Functions + Storage + RPC + RLS)
- Postgres stores anime/manga catalog, user lists, recommendations, concierge sessions, clubs, and ops metrics.
- Edge Functions handle bulk imports, concierge operations (parse/resolve/recommend/apply/undo), and image mirroring.
- Storage provides CDN for mirrored images (public bucket).

**Primary data source:** AniList (imported via scripts + edge functions).

## 1.0) Current discovery/search policy (2026-03-26)

- `discover_bundle` now rotates `new_to_you` server-side per user via `public.discover_rail_impressions`.
- `new_to_you` ordering is: unseen-for-that-user first, then `popularity desc`, `average_score desc`, `favourites desc`, `id desc`.
- Default anime `Discover`, `Search`, and `Browse` now hide ancillary formats `SPECIAL`, `MUSIC`, and `TV_SHORT`.
- Browse keeps an explicit override: if the user deliberately chooses one of those formats in the format filter, results for that format still appear.
- Collection/detail navigation are unchanged; saved items are not hidden by this policy.

---

## 1.1) Configuration + secrets (where keys live)

### iOS app config
- `Kuro/Services/AppConfig.swift` reads:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
  from **Info.plist** or process env.
- If missing, `SupabaseService` sets `configError` and shows an error screen (no hardcoded fallback).
- **Info.plist** (project root, NOT `Kuro/Info.plist`): registers `kuro://` URL scheme via `CFBundleURLTypes`, references `$(SUPABASE_URL)` and `$(SUPABASE_ANON_KEY)` build variables (resolved from xcconfig). `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Info.plist` — Xcode merges generated keys with custom ones.
- **xcconfig files** (wired into Xcode project as `baseConfigurationReference`):
  - `Config/Shared.xcconfig` — shared settings including `SUPABASE_URL` and `SUPABASE_ANON_KEY`
  - `Config/Debug.xcconfig` — debug overrides
  - `Config/Release.xcconfig` — release overrides

### MCP servers (`.mcp.json` at project root)
- `supabase` — Supabase MCP (database, functions, docs, storage, branching)
- `resend` — Resend email API (for custom SMTP setup + email management)

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
- `emails/` — 5 branded HTML email templates (confirm, reset-password, magic-link, change-email, invite). Cormorant serif wordmark, warm gray `#f5f5f0` background, black CTA buttons, MSO-compatible table layout. Use `{{ .ConfirmationURL }}` Supabase template variables. Must be pasted into Supabase Dashboard → Auth → Email Templates.
- `mockups/` — UI references
- `Info.plist` — custom URL scheme registration (`kuro://`). Lives at project root (NOT `Kuro/Info.plist` — that causes duplicate resource errors). `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Info.plist` in both Debug+Release build configs.
- `.mcp.json` — MCP server config: Supabase (HTTP) + Resend (`@resend/mcp` via npx, API key in env)
- `CLAUDE.md` — mandatory project rules + full context for new sessions
- `MASTER_PLAN.md` — architectural north star (historical docs moved to `archive/`)

<!-- BEGIN AUTO-INVENTORY -->

## 2.1) Auto-generated inventory (exhaustive file lists)

Generated: **2026-03-26T16:16:10.625Z**  (git: `a8b9f78` on `main`)

This section is auto-generated. Rebuild it after any repo change:
```bash
node scripts/generate_app_state_inventory.js
```

### iOS (Swift) files (count: 88)
- `Kuro/ContentView.swift`
- `Kuro/Design/Color+Hex.swift`
- `Kuro/Design/KuroDesignSystem.swift`
- `Kuro/KuroApp.swift`
- `Kuro/Models/DiscoverBundle.swift`
- `Kuro/Models/SupabaseModels.swift`
- `Kuro/Services/AppConfig.swift`
- `Kuro/Services/AppleFMService.swift`
- `Kuro/Services/ConciergeAnalytics.swift`
- `Kuro/Services/DeepLinkRouter.swift`
- `Kuro/Services/FeatureFlags.swift`
- `Kuro/Services/ImagePipeline.swift`
- `Kuro/Services/KuroDiskDetailCache.swift`
- `Kuro/Services/KuroPerf.swift`
- `Kuro/Services/NetworkMonitor.swift`
- `Kuro/Services/SupabaseRPCParams.swift`
- `Kuro/Services/SupabaseService+Browse.swift`
- `Kuro/Services/SupabaseService+ClubRealtime.swift`
- `Kuro/Services/SupabaseService+Clubs.swift`
- `Kuro/Services/SupabaseService+Collection.swift`
- `Kuro/Services/SupabaseService+Concierge.swift`
- `Kuro/Services/SupabaseService+Recommendations.swift`
- `Kuro/Services/SupabaseService+Social.swift`
- `Kuro/Services/SupabaseService+Streaming.swift`
- `Kuro/Services/SupabaseService+UserLists.swift`
- `Kuro/Services/SupabaseService.swift`
- `Kuro/Services/TextNormalization.swift`
- `Kuro/Views/AddToListSheet.swift`
- `Kuro/Views/AuthView.swift`
- `Kuro/Views/BrowseComponents.swift`
- `Kuro/Views/BrowseView.swift`
- `Kuro/Views/Cards.swift`
- `Kuro/Views/ClubCreateSheets.swift`
- `Kuro/Views/ClubDetailSheets.swift`
- `Kuro/Views/ClubDetailShellComponents.swift`
- `Kuro/Views/ClubDetailTabComponents.swift`
- `Kuro/Views/ClubDetailView.swift`
- `Kuro/Views/ClubsView.swift`
- `Kuro/Views/ConciergeActionFooter.swift`
- `Kuro/Views/ConciergeAniListImportCoordinator.swift`
- `Kuro/Views/ConciergeComponents.swift`
- `Kuro/Views/ConciergeComposerDock.swift`
- `Kuro/Views/ConciergeEditorialShell.swift`
- `Kuro/Views/ConciergeImportCards.swift`
- `Kuro/Views/ConciergeInputField.swift`
- `Kuro/Views/ConciergeIntentDeck.swift`
- `Kuro/Views/ConciergeRecommendationRails.swift`
- `Kuro/Views/ConciergeResponseStage.swift`
- `Kuro/Views/ConciergeView+AniListImport.swift`
- `Kuro/Views/ConciergeView.swift`
- `Kuro/Views/CountdownTimer.swift`
- `Kuro/Views/DetailPages/AdaptationPathSection.swift`
- `Kuro/Views/DetailPages/AnimeDetailView.swift`
- `Kuro/Views/DetailPages/CastSection.swift`
- `Kuro/Views/DetailPages/ClubActivitySection.swift`
- `Kuro/Views/DetailPages/CreditsSection.swift`
- `Kuro/Views/DetailPages/EntityDetailSheets.swift`
- `Kuro/Views/DetailPages/ExternalLinksSection.swift`
- `Kuro/Views/DetailPages/FriendsActivitySection.swift`
- `Kuro/Views/DetailPages/MangaDetailView.swift`
- `Kuro/Views/DetailPages/MediaDetailSheet.swift`
- `Kuro/Views/DiscoverViewModel.swift`
- `Kuro/Views/EditorialCards.swift`
- `Kuro/Views/EditorialCollectionComponents.swift`
- `Kuro/Views/EditorialCollectionView.swift`
- `Kuro/Views/EditorialDiscoverRouting.swift`
- `Kuro/Views/EditorialDiscoverView.swift`
- `Kuro/Views/EditorialSearchView.swift`
- `Kuro/Views/GenreHubView.swift`
- `Kuro/Views/KuroCachedAsyncImage.swift`
- `Kuro/Views/KuroCardText.swift`
- `Kuro/Views/KuroConciergeMark.swift`
- `Kuro/Views/KuroDeliberateTap.swift`
- `Kuro/Views/KuroGestureCoordinator.swift`
- `Kuro/Views/KuroGesturePolicy.swift`
- `Kuro/Views/KuroGlass.swift`
- `Kuro/Views/KuroInteractionEnvironment.swift`
- `Kuro/Views/KuroLoadMoreSentinel.swift`
- `Kuro/Views/KuroPagingGesture.swift`
- `Kuro/Views/KuroRefinedCard.swift`
- `Kuro/Views/KuroToast.swift`
- `Kuro/Views/KuroTransientBanner.swift`
- `Kuro/Views/OnboardingView.swift`
- `Kuro/Views/PosterView.swift`
- `Kuro/Views/ProfileFreshnessCard.swift`
- `Kuro/Views/ProfileView.swift`
- `Kuro/Views/QuickVerdictActionCard.swift`
- `Kuro/Views/UIComponents.swift`

### Supabase migrations (count: 169)
- `supabase/migrations/20250109_remote_applied_placeholder.sql`
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
- `supabase/migrations/20260206100000_concierge_modes_v3_expanded.sql`
- `supabase/migrations/20260206120000_curated_rails_expansion.sql`
- `supabase/migrations/20260206143000_fix_legacy_tags_and_comments.sql`
- `supabase/migrations/20260206150000_security_hardening_rls_and_views.sql`
- `supabase/migrations/20260206162329_curated_rails_expansion.sql`
- `supabase/migrations/20260206164200_security_hardening_rls_and_views.sql`
- `supabase/migrations/20260207000000_search_titles_enrich_year_format.sql`
- `supabase/migrations/20260207011000_curated_rails_vibes_seed.sql`
- `supabase/migrations/20260207012000_concierge_modes_v4_add_vibe_rail_ids.sql`
- `supabase/migrations/20260207020000_curated_rails_more_vibes_seed.sql`
- `supabase/migrations/20260207021000_concierge_modes_v5_add_more_vibe_rail_ids.sql`
- `supabase/migrations/20260208022035_phase0_remove_sequels.sql`
- `supabase/migrations/20260208022043_concierge_mode_analytics.sql`
- `supabase/migrations/20260208022110_add_sports_mode.sql`
- `supabase/migrations/20260208022136_phase0_remove_misclassified.sql`
- `supabase/migrations/20260208022153_add_scifi_mode.sql`
- `supabase/migrations/20260208022239_add_horror_supernatural_mode.sql`
- `supabase/migrations/20260208022250_phase0_dedup_rails.sql`
- `supabase/migrations/20260208022326_phase0_slim_and_rerank.sql`
- `supabase/migrations/20260208022342_add_demographic_rails.sql`
- `supabase/migrations/20260208022356_update_concierge_config_new_modes.sql`
- `supabase/migrations/20260208022404_phase0_fix_classics.sql`
- `supabase/migrations/20260208023052_phase0_backfill_underpopulated_rails.sql`
- `supabase/migrations/20260208023221_phase0_dedup_backfilled_rails.sql`
- `supabase/migrations/20260208023331_phase0_final_backfill.sql`
- `supabase/migrations/20260208090000_refine_short_and_fantasy_rails.sql`
- `supabase/migrations/20260208091500_curated_rails_premium_picks_seed.sql`
- `supabase/migrations/20260208092000_concierge_modes_v6_add_premium_picks_rail_id.sql`
- `supabase/migrations/20260209000000_search_titles_add_cover_image.sql`
- `supabase/migrations/20260209100000_concierge_modes_v7_german_synonyms.sql`
- `supabase/migrations/20260209110000_concierge_modes_v8_expanded.sql`
- `supabase/migrations/20260209120000_new_vibe_rails.sql`
- `supabase/migrations/20260209135229_import_reconciliation.sql`
- `supabase/migrations/20260209200000_clubs_foundation.sql`
- `supabase/migrations/20260209201000_clubs_rls_policies.sql`
- `supabase/migrations/20260209202000_clubs_rpcs.sql`
- `supabase/migrations/20260209220000_club_analytics.sql`
- `supabase/migrations/20260209224945_fix_mirror_cron_contention.sql`
- `supabase/migrations/20260211030140_feature_flags.sql`
- `supabase/migrations/20260211100000_rag_tables.sql`
- `supabase/migrations/20260211110000_privacy_retention_and_gdpr.sql`
- `supabase/migrations/20260211113000_rag_retrieve_candidates.sql`
- `supabase/migrations/20260211154000_fetch_club_bundle_member_identity.sql`
- `supabase/migrations/20260211162000_reduce_school_shoujo_overlap.sql`
- `supabase/migrations/20260211170000_enable_concierge_intelligence_de_canary.sql`
- `supabase/migrations/20260213130000_clubs_concierge_swipe_flags.sql`
- `supabase/migrations/20260213143000_concierge_editorial_v1_flag.sql`
- `supabase/migrations/20260215124919_add_create_rail_and_poll_rpcs.sql`
- `supabase/migrations/20260215124946_create_club_rail_and_poll_rpcs.sql`
- `supabase/migrations/20260215125056_fix_invite_code_crypto_and_club_members_insert.sql`
- `supabase/migrations/20260215125312_club_reactions_and_invite_share.sql`
- `supabase/migrations/20260215130000_fix_club_fk_housekeeping_gdpr.sql`
- `supabase/migrations/20260216015514_clubs_list_enrichment.sql`
- `supabase/migrations/20260216015733_club_reactions_in_bundle.sql`
- `supabase/migrations/20260216015921_clubs_realtime_publication.sql`
- `supabase/migrations/20260216020023_club_messages.sql`
- `supabase/migrations/20260216193000_add_club_rail_item_structured_errors.sql`
- `supabase/migrations/20260216200204_catalog_created_at_not_null.sql`
- `supabase/migrations/20260216200227_drop_unused_indexes_merge_policies_health_check.sql`
- `supabase/migrations/20260216214047_fix_initplan_rls_club_messages_reactions.sql`
- `supabase/migrations/20260216214050_authors_tags_created_at_not_null.sql`
- `supabase/migrations/20260218131735_fix_join_club_archived_check.sql`
- `supabase/migrations/20260218141739_capture_club_message_functions.sql`
- `supabase/migrations/20260218141754_update_join_create_club_functions.sql`
- `supabase/migrations/20260218141757_fix_storage_insert_policy.sql`
- `supabase/migrations/20260218173617_drop_duplicate_indexes.sql`
- `supabase/migrations/20260218173619_drop_dead_rag_cache_cleanup.sql`
- `supabase/migrations/20260219002612_critical_security_drop_and_revoke.sql`
- `supabase/migrations/20260219002639_drop_start_bulk_import_with_args.sql`
- `supabase/migrations/20260219002706_revoke_public_from_admin_functions.sql`
- `supabase/migrations/20260219003105_add_user_lists_to_realtime_publication.sql`
- `supabase/migrations/20260219003111_anime_is_adult_not_null.sql`
- `supabase/migrations/20260219003305_drop_ambiguous_overloads.sql`
- `supabase/migrations/20260219003323_harden_toggle_reaction.sql`
- `supabase/migrations/20260219003339_harden_create_club.sql`
- `supabase/migrations/20260219003351_tighten_club_write_policies.sql`
- `supabase/migrations/20260219003357_tighten_storage_update_policy.sql`
- `supabase/migrations/20260219003402_add_missing_fk_indexes.sql`
- `supabase/migrations/20260219003703_cron_cleanup_and_mirror_auth.sql`
- `supabase/migrations/20260219100000_critical_security_drop_and_revoke.sql`
- `supabase/migrations/20260219100001_drop_start_bulk_import_with_args.sql`
- `supabase/migrations/20260219100002_revoke_public_from_admin_functions.sql`
- `supabase/migrations/20260219100003_add_user_lists_to_realtime_publication.sql`
- `supabase/migrations/20260219100004_anime_manga_is_adult_not_null.sql`
- `supabase/migrations/20260219100005_drop_ambiguous_overloads.sql`
- `supabase/migrations/20260219100006_harden_toggle_reaction.sql`
- `supabase/migrations/20260219100007_harden_create_club.sql`
- `supabase/migrations/20260219100008_tighten_club_write_policies.sql`
- `supabase/migrations/20260219100009_tighten_storage_update_policy.sql`
- `supabase/migrations/20260219100010_add_missing_fk_indexes.sql`
- `supabase/migrations/20260219100011_cron_cleanup_and_mirror_auth.sql`
- `supabase/migrations/20260219114953_set_not_null_on_nullable_required_columns.sql`
- `supabase/migrations/20260219120000_set_not_null_on_nullable_required_columns.sql`
- `supabase/migrations/20260219153000_manga_chapter_enrichment_v1.sql`
- `supabase/migrations/20260219234000_fix_manga_chapter_enrich_cron_secret.sql`
- `supabase/migrations/20260219235500_manga_review_approved_mapping_method.sql`
- `supabase/migrations/20260220103000_manga_fuzzy_matcher_v2.sql`
- `supabase/migrations/20260221120000_browse_filters_year_format.sql`
- `supabase/migrations/20260221150000_manga_fuzzy_matcher_method_allow_title_fuzzy.sql`
- `supabase/migrations/20260221162000_manga_zero_touch_canonical_mapping.sql`
- `supabase/migrations/20260221173000_manga_chapter_crunch_mode.sql`
- `supabase/migrations/20260221190000_enable_swipe_tap_guard_v1.sql`
- `supabase/migrations/20260221191000_synopsis_enhancement_fields.sql`
- `supabase/migrations/20260221192000_synopsis_enrichment_rpcs.sql`
- `supabase/migrations/20260223002000_synopsis_retry_backoff_and_resume.sql`
- `supabase/migrations/20260224101000_catalog_safety_runner_v1.sql`
- `supabase/migrations/20260224150000_social_activity_layer.sql`
- `supabase/migrations/20260225100000_check_email_exists_rpc.sql`
- `supabase/migrations/20260301100000_streaming_availability_v1.sql`
- `supabase/migrations/20260301153000_streaming_availability_country_lang_v1.sql`
- `supabase/migrations/20260304100000_credits_cast_v1_flag.sql`
- `supabase/migrations/20260305151500_fix_delete_user_concierge_data_uuid_compare.sql`
- `supabase/migrations/20260305153000_fix_delete_user_concierge_data_import_sessions_and_coverage.sql`
- `supabase/migrations/20260305162000_cleanup_db_lint_warnings.sql`
- `supabase/migrations/20260306113000_provider_availability_note_contract.sql`
- `supabase/migrations/20260307120000_media_relations_ladder_v1.sql`
- `supabase/migrations/20260307150000_adaptation_ladder_v2_editorial_context.sql`
- `supabase/migrations/20260307163000_fix_adaptation_ladder_entry_point.sql`
- `supabase/migrations/20260311100000_ladder_source_author.sql`
- `supabase/migrations/20260313100000_slim_club_bundle_limits.sql`
- `supabase/migrations/20260313120000_social_activity_v1_rollout_100.sql`
- `supabase/migrations/20260316100000_fix_club_bundle_columns_and_reactions.sql`
- `supabase/migrations/20260316220000_clubs_list_cover_images_members.sql`
- `supabase/migrations/20260317063000_clubs_list_cover_image_large.sql`
- `supabase/migrations/20260317110000_fetch_club_bundle_ordering_and_poll_counts.sql`
- `supabase/migrations/20260318103000_import_track_and_worker_state.sql`
- `supabase/migrations/20260318104000_club_loading_rpcs.sql`
- `supabase/migrations/20260319123000_provider_availability_request_priority.sql`
- `supabase/migrations/20260322110000_add_list_verdicts.sql`
- `supabase/migrations/20260324173000_search_title_priority.sql`
- `supabase/migrations/20260324180000_search_title_popularity_tiebreak.sql`
- `supabase/migrations/20260324213000_discover_airing_today_berlin_day.sql`
- `supabase/migrations/20260326221000_discover_new_to_you_rotation.sql`
- `supabase/migrations/20260326234000_exclude_ancillary_anime_from_default_surfaces.sql`

### Supabase Edge Functions (index.ts) (count: 15)
- `supabase/functions/auth-callback/index.ts`
- `supabase/functions/bulk-import-anime/index.ts`
- `supabase/functions/bulk-import-manga/index.ts`
- `supabase/functions/concierge-apply/index.ts`
- `supabase/functions/concierge-import-anilist/index.ts`
- `supabase/functions/concierge-parse/index.ts`
- `supabase/functions/concierge-recommend/index.ts`
- `supabase/functions/concierge-resolve/index.ts`
- `supabase/functions/concierge-retrieve-assist/index.ts`
- `supabase/functions/concierge-retrieve-feedback/index.ts`
- `supabase/functions/concierge-undo/index.ts`
- `supabase/functions/delete-account/index.ts`
- `supabase/functions/manga-chapter-enrich/index.ts`
- `supabase/functions/manga-source-review-action/index.ts`
- `supabase/functions/mirror-images/index.ts`

### Repo scripts (count: 45)
- `scripts/apply_remote_sql.js`
- `scripts/audit_curated_rails_quality.js`
- `scripts/catalog_safety_dashboard_server.js`
- `scripts/check_cron_health.js`
- `scripts/collect_db_metrics.js`
- `scripts/concierge_corpus_generate.js`
- `scripts/concierge_eval_parse.js`
- `scripts/db_state.sql`
- `scripts/eval_concierge_modes.js`
- `scripts/eval_router.js`
- `scripts/generate_app_state_codebase_bundle.js`
- `scripts/generate_app_state_inventory.js`
- `scripts/generate_app_state_live_snapshot.js`
- `scripts/generate_app_state_maps.js`
- `scripts/generate_app_state_sources.js`
- `scripts/generate_curated_rail_candidates.js`
- `scripts/generate_curated_rails_migration.js`
- `scripts/generate_more_vibe_rails_migration.js`
- `scripts/generate_premium_picks_rails_migration.js`
- `scripts/generate_rail_migration.js`
- `scripts/generate_refined_short_and_fantasy_rails_migration.js`
- `scripts/generate_vibe_rails_migration.js`
- `scripts/genre_audit.js`
- `scripts/import_anilist_fast.js`
- `scripts/import_anilist_local.js`
- `scripts/legacy/03_updated_edge_function.js`
- `scripts/legacy/04_manga_edge_function.js`
- `scripts/legacy/06_anime_edge_function_with_episodes.js`
- `scripts/legacy/07_manga_edge_function_with_chapters.js`
- `scripts/lib/project_config.js`
- `scripts/load_test_concierge.js`
- `scripts/manual/test_bulk_import_anime.js`
- `scripts/manual/test_bulk_import_manga.js`
- `scripts/manual/test_bulk_import_manga_with_chapters.js`
- `scripts/manual/verify_supabase_connection.js`
- `scripts/media_relations_worker.js`
- `scripts/provider_availability_dashboard_server.js`
- `scripts/quality-gates/router_test_cases.js`
- `scripts/report_airing_window.js`
- `scripts/run_full_import.js`
- `scripts/run_manga_chapter_crunch.js`
- `scripts/smoke_concierge_recommend.js`
- `scripts/smoke_magic_parse_apply.js`
- `scripts/synopsis_dashboard_server.js`
- `scripts/unified_local_dashboard_server.js`


<!-- END AUTO-INVENTORY -->

### iOS app structure (`/Kuro`)
- `Kuro/ContentView.swift` — app entry point + navigation/swipe pager + top header
- `Kuro/KuroApp.swift` — `@main` entry (63 lines), `scenePhase` lifecycle handling, `NetworkMonitor` + `SupabaseService` environment injection, `.onOpenURL` deep link handler (line 33). Auth callbacks intercepted at app level (line 37, before auth gate) — calls `handleAuthCallback()` directly instead of passing to ContentView. URL cache: 64MB memory + 256MB disk.
- `Kuro/Services/DeepLinkRouter.swift` — `enum DeepLink` with cases for anime(id:), manga(id:), club(id:), collection, discover, concierge(prompt:), authCallback(accessToken:, refreshToken:); parses `kuro://` scheme URLs
- `Kuro/Services/AppleFMService.swift` — Apple Foundation Models integration (on-device LLM: mode classification, disambiguation, synopsis condensation, collection search intent)
- `Kuro/Services/NetworkMonitor.swift` — `NWPathMonitor` connectivity tracking, `@Environment` injection, offline banner
- `Kuro/Services/SupabaseService.swift` — core data layer, RPC usage, caching, `fmService` (AppleFMService), `withRetry` helper, `configError` property (graceful config gate), `trimCachesForMemoryPressure()`, `authCallbackURL`, `handleAuthCallback()`, `signUpWithEmail`/`resetPassword`, `checkEmailExists(email:)` (debounced uniqueness check via `check_email_exists` RPC)
- `Kuro/Views/` — SwiftUI UI components
- `Kuro/Models/` — data models (Anime, Manga, UserList, etc.)
- `Config/` — xcconfig files (Shared, Debug, Release) wired as `baseConfigurationReference` in Xcode project

### Feature-to-file map (frontend)
- **Concierge UI**: `Kuro/Views/ConciergeView.swift` (inline chat, import, recommend UI, toasts), `ConciergeEditorialShell.swift` (editorial shell wrapper), `ConciergeComponents.swift` (shared components + curated copy), `ConciergeInputField.swift` (text input), `ConciergeComposerDock.swift` (input composer dock), `ConciergeActionFooter.swift` (action footer bar), `ConciergeIntentDeck.swift` (quick-action intent deck), `ConciergeImportCards.swift` (import preview/confirm cards), `ConciergeRecommendationRails.swift` (recommendation rail rendering), `ConciergeResponseStage.swift` (response stage rendering)
- **Discover**: `Kuro/Views/EditorialDiscoverView.swift` (sections, rails, filters)
- **Collection**: `Kuro/Views/EditorialCollectionView.swift` + list helpers in `SupabaseService`
- **Browse**: `Kuro/Views/BrowseView.swift` (full-page browse with filters)
- **Search**: `Kuro/Views/EditorialSearchView.swift`
- **Clubs**: `Kuro/Views/ClubsView.swift` (club list, enriched cards, unread dots), `Kuro/Views/ClubDetailView.swift` (3-tab: Rails/This Week/Polls), `Kuro/Views/ClubCreateSheets.swift` (create/join sheets), `Kuro/Views/DetailPages/ClubActivitySection.swift` (media detail club context + Add to Club sheet)
- **Social activity**: `Kuro/Views/DetailPages/FriendsActivitySection.swift` (friend tracking pills, title comments, thumbs up/down reactions)
- **Cards / badges**: `Kuro/Views/KuroRefinedCard.swift`, `Kuro/Views/KuroCardText.swift`
- **Glass UI**: `Kuro/Views/KuroGlass.swift`
- **Toasts**: `Kuro/Views/KuroToast.swift`
- **Image caching**: `Kuro/Views/KuroCachedAsyncImage.swift`, `Kuro/Services/ImagePipeline.swift`
- **Profile**: `Kuro/Views/ProfileView.swift` (includes Clubs tab)
- **Onboarding**: `Kuro/Views/OnboardingView.swift` (first-launch onboarding flow)
- **Apple Foundation Models**: `Kuro/Services/AppleFMService.swift` (on-device: mode classification, disambiguation, synopsis condensation, NL collection search intent)
- **Network monitoring**: `Kuro/Services/NetworkMonitor.swift` (connectivity state, offline banner in `KuroApp.swift`)
- **Feature flags**: `Kuro/Services/FeatureFlags.swift` (staged rollout definitions for clubs, concierge, realtime, social activity, FM assist, streaming availability features)
- **Analytics**: `Kuro/Services/ConciergeAnalytics.swift` (concierge + club interaction telemetry)
- **Text normalization**: `Kuro/Services/TextNormalization.swift` (search/parsing text utilities)
- **Synopsis condenser**: `AnimeDetailView.swift`, `MangaDetailView.swift` call `fmService.condenseSynopsis()` for descriptions > 200 chars
- **Next Up picks**: `NextUpSection` (in `AnimeDetailView.swift`), `MangaNextUpSection` (in `MangaDetailView.swift`) — personalized next episode/chapter recommendations
- **Gesture system**: `Kuro/Views/KuroDeliberateTap.swift` (`.kuroDeliberateTap {}` modifier — simple `.onTapGesture` + `suppressCardTaps` environment check), `Kuro/Views/KuroGestureCoordinator.swift` (pager gesture coordination), `Kuro/Views/KuroGesturePolicy.swift` (pager timing constants: `postSwipeTapCooldownMs`, `fastFlingPredictedDxPt`, `fastFlingDirectionRatio`), `Kuro/Views/KuroPagingGesture.swift` (root pager DragGesture + exclusion zones)
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
- `auth-callback/` — email verification fallback redirect; serves dark-themed HTML page with animated K logo. Primary flow uses direct `kuro://auth/callback` redirect (no intermediate page). verify_jwt: false.

### Scripts
- `scripts/import_anilist_fast.js`, `scripts/import_anilist_local.js`, `scripts/run_full_import.js` — AniList ingestion
- `scripts/genre_audit.js`, `scripts/report_airing_window.js` — data QA
- `scripts/concierge_eval_parse.js`, `scripts/concierge_corpus_generate.js`, `scripts/load_test_concierge.js` — concierge QA/ops
- `scripts/check_cron_health.js`, `scripts/collect_db_metrics.js` — ops
- `scripts/db_state.sql` — DB snapshot queries (row counts, coverage, etc.)
- `scripts/quality-gates/` — CI quality gate scripts (8 gates: secrets, migrations, concierge-corpora, router tests, rails audit, docs-current-state, iOS build, iOS test); see section 13.1

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
- **Offline handling**: Monochrome "OFFLINE" text banner (9pt, tracked) at top of `RootView` when disconnected. Plus: cache-fallback in detail fetches (`fetchAnimeById`/`fetchMangaById` return disk cache on network failure), "SHOWING CACHED DATA" stale indicators (Discover, Collection), offline error states with retry (Browse, Collection, detail sheets), write-action guards (Concierge send, Add to List save/remove, club create rail/poll disabled when offline), auto-refresh on reconnect (Discover/Collection/Clubs via `reconnectionGeneration` observer in `ContentView`).
- **App lifecycle**: `scenePhase` tracked in `KuroApp.swift` for background/foreground transitions.
- **Deep linking**: `KuroApp.swift` handles `.onOpenURL` events, passes `pendingDeepLink` binding to `ContentView`. `DeepLinkRouter.swift` defines `enum DeepLink` with cases: `.anime(id:)`, `.manga(id:)`, `.club(id:)`, `.collection`, `.discover`, `.concierge(prompt:)`, `.authCallback(accessToken:, refreshToken:)`. Parses `kuro://` scheme URLs. `ContentView` navigates to the target page for page-level links, or presents a detail sheet for anime/manga/club links. Auth callbacks are intercepted at `KuroApp` level (before auth gate) and call `handleAuthCallback()` to set session immediately.
- **Auth flow (signup + sign-in)**:
  1. User enters email and password in `AuthView.swift`.
  2. **Inline validation (sign-up mode)**: Real-time email format check (regex on keystroke), debounced 500ms uniqueness check via `check_email_exists` RPC, password minimum length check. Two enums drive state: `EmailStatus` (.empty, .invalidFormat, .checking, .taken, .available) and `PasswordStatus` (.empty, .tooShort, .valid). Inline hint text + checkmarks displayed inside fields. `canSubmit` gates on validation state.
  3. `signUpWithEmail` creates the account — email confirmation is disabled (no `redirectTo`). User is signed in immediately after signup.
  4. `SupabaseService.handleAuthCallback()` (line 483) still exists for deep link auth flows (password reset, magic link) → `client.auth.setSession()` → `ensureProfileRow()` → `bootstrapAfterAuth()`.
  - **Key code**: `AuthView.swift` (inline validation enums + debounced RPC check), `SupabaseService.checkEmailExists(email:)` (calls `check_email_exists` RPC), `authCallbackURL` (SupabaseService.swift:420), `handleAuthCallback` (line 483).
  - **Fallback**: `auth-callback` edge function (315 lines) — dark-themed HTML page with Cormorant serif, grain SVG overlay, animated K logo, type-specific status messages (signup/recovery/magiclink/email_change/invite), loading dots, "Open Kuro" CTA button after 4s timeout, "Continue in browser" secondary link. Security headers: `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Cache-Control: no-store`.
  - **Pending Supabase Dashboard manual step**:
    1. Auth → Settings → disable "Enable email confirmations" (so signup signs in immediately without verification email)

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
  - Concierge glass intro card with **first-time contextual hint**: expanded two-row layout (import + recommendations with concrete examples) for new users, collapses to slim text after first interaction. One-way UserDefaults flag (`kuro_concierge_used`), set in `send()` after first message.
  - Curated entry actions:
    - Import list
    - See curated example prompts
    - Ask for a mood-based recommendation
- **Intent routing**: Hybrid FM-primary with keyword fallback.
  - When Apple FM is available + `fm_assist_v1` flag enabled: `assistIntent()` classifies user text into 6 intents (`import`, `recommend_vibe`, `recommend_seed`, `library_query`, `club_action`, `unknown`) with confidence score. Confidence threshold: 0.65. On FM failure/timeout/low-confidence: falls back to `looksLikeImport()` keywords.
  - When FM unavailable (non-iOS 26, flag off): `looksLikeImport()` keyword routing (same as before).
  - `routeByKeywords()` helper shared by fallback and non-FM paths.
  - Analytics: `intent_detected` event with `"source": "fm"` or `"source": "keywords"` to compare routing accuracy.
  - **`fm_assist_v1` flag rollout**: 0% (staged). Intentionally dormant until on-device testing validates FM accuracy. Planned rollout: 0% → 10% canary → 50% → 100%.
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
- Editorial layout with **progressive disclosure**: 6 primary sections always visible, 7 secondary sections behind a "Show More" button.
- **Primary sections** (reordered by user value): New to You → Airing Today → Essential Anime → New to You (Manga) → Trending → Essential Manga.
- **Secondary sections** (behind "Show More"): Classics → Current Season → Top Rated → Just Added → Manga Classics → Trending Manga → Top Rated Manga.
- "Show More" button: monochrome editorial style (stroked rounded rect, chevron down, "N MORE SECTIONS" label). One-way UserDefaults flag (`kuro_discover_show_more`) — once expanded, stays expanded across launches.
- Data fetching unchanged — all 14 arrays still load via `fetchDiscoverBundle()`. This is UI-only progressive disclosure.
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
- `ClubDetailView`: **Journal editorial design** — blurred 2x2 poster mosaic hero (220pt) with grain texture overlay, gradient fades, serif italic club name, member avatar row, and sharing-level pill. Custom underline tab bar (RAILS / ACTIVE / POLLS) with `matchedGeometryEffect` animation replaces segmented Picker. Scroll-based status bar transitions from transparent (over hero) to white with club name. **Rails tab**: curator's notes in serif italic above each rail, 120x170pt poster cards with progress text and member-watching labels, editorial dividers between rails. **Activity tab**: journal-style prose entries synthesized from `member_statuses` across all rail items, grouped by date with serif italic day headers, pace banners, pull-quote milestone cards. **Polls tab**: conversational framing ("S ASKED:"), serif italic questions, percentage fill bars with voted-dot indicators. **Glass bottom bar**: `.ultraThinMaterial` capsule pill (48pt) with ADD/INVITE/POLL buttons, role-gated (non-admins see only INVITE). Settings sheet for owner/admin. Each rail has a "+" button (for unlocked rails or owner/admin on locked rails) that opens `AddItemToRailSheet` — server-side search via `search_anime_page`/`search_manga_page` RPCs with debounced input, compact result rows, typed `PostgrestError` handling for duplicates/lock/membership errors. **Reaction rows**: items with existing reactions show full `ClubReactionRow` (4 emoji capsules, width 120); items with no reactions show `ClubReactionRowCompact` (single smiley icon that expands to full row on tap). All business logic (data fetching, voting, reactions, Realtime subscriptions, sheets) preserved from pre-Journal implementation.
- `ClubActivitySection`: embedded on `AnimeDetailView` and `MangaDetailView` — shows which clubs have this title in a rail, aggregate member status counts, and (if sharing level allows) per-member details. Member identity uses stable 6-char UUID hex prefix (not positional "Member N"). `AddToClubRailSheet` is public (used by card context menus for "Add to Club..." action).
- `ClubActivitySection`: now renders explicit member watch/read progress language (tracking, completed, planning, paused, dropped, not-started) and does not use placeholder status labels when per-member detail is unavailable.
- `FriendsActivitySection`: embedded on `AnimeDetailView` and `MangaDetailView` (after ClubActivitySection). Shows friend tracking count pills, title comments with thumbs up/down reactions, and a comment input field. Gated by `social_activity_v1` feature flag. "Friends" are users who share at least one club with the viewer.
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
- **Realtime**: subscribes to user-scoped channel to refresh list/collection data on changes. Club-specific channel subscription for live updates on 5 tables (rail items, polls, votes, reactions, messages) with 500ms debounce.
- **Local caches**: `discoverBundleCache`, `conciergeParseCache`, `conciergeRecommendCache` (in-memory, TTL-based).
- **Apple FM integration**: `fmService` property (`AppleFMService` instance) provides on-device classification, disambiguation, synopsis condensation, and NL collection search intent parsing.
- **Retry logic**: `withRetry` static helper (exponential backoff, max 2 retries, URLError-only) wrapping 5 key call sites: `fetchMoreAnime`, `fetchMoreManga`, `fetchDiscoverBundle`, `conciergeParse`, `conciergeRecommend`.
- **Debug logging**: all 127+ `print()` statements wrapped in `#if DEBUG`.
- **Config error handling**: `init()` sets `configError` instead of `fatalError` when credentials are missing; UI gate in `KuroApp.RootView` prevents any code path from reaching uninitialized `client`.
- **Memory pressure**: `trimCachesForMemoryPressure()` sheds all entity, detail, discover, and concierge caches plus `ImagePipeline` memory cache without touching user-facing state.

<!-- BEGIN AUTO-IOS-MAP -->

## 3.2) Auto iOS backend usage index

Generated: **2026-03-26T16:16:10.704Z** (git: `a8b9f78`)

- Swift files scanned: **88** (all `Kuro/**/*.swift`)

### RPCs used by iOS (count: 40)
- `add_club_rail_item`
- `batch_provider_availability_for_media_v2`
- `batch_providers_for_media`
- `browse_anime_page`
- `browse_manga_page`
- `cast_club_vote`
- `check_club_activity_since`
- `check_email_exists`
- `club_shared_providers`
- `collection_anime_page`
- `collection_feed_page`
- `collection_manga_page`
- `count_friends_tracking`
- `create_club`
- `create_club_poll`
- `create_club_rail`
- `delete_title_comment`
- `discover_bundle`
- `enqueue_media_availability_refresh`
- `enqueue_media_relation_refresh`
- `fetch_club_bundle`
- `fetch_club_bundle_loading`
- `fetch_club_messages`
- `fetch_friend_activity_for_title`
- `fetch_my_clubs_enriched`
- `fetch_my_clubs_loading`
- `get_manga_chapter_status`
- `get_media_availability_status`
- `get_media_ladder`
- `get_provider_availability_refresh_queue_summary`
- `join_club`
- `leave_club`
- `recommend_ids_similar_to_seeds`
- `save_user_streaming_services`
- `search_anime_page`
- `search_manga_page`
- `send_club_message`
- `toggle_club_reaction`
- `toggle_comment_reaction`
- `upsert_title_comment`

### Edge Functions invoked by iOS (count: 7)
- `concierge-apply`
- `concierge-import-anilist`
- `concierge-parse`
- `concierge-recommend`
- `concierge-retrieve-feedback`
- `concierge-undo`
- `delete-account`


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

- **Published state**: `isConnected` (Bool), `connectionType` (`.wifi`, `.cellular`, `.wired`, `.unknown`), `reconnectionGeneration` (Int, increments on each network reconnection)
- **Injection**: created in `KuroApp.swift`, injected as `@Environment` throughout the app. Referenced in 10 view files for offline-aware UI.
- **Offline banner**: `RootView` in `KuroApp.swift` shows a monochrome "OFFLINE" text banner (9pt, tracked 1.2, black 45% opacity) when `isConnected == false`
- **Reconnection signal**: `reconnectionGeneration` increments in `pathUpdateHandler` when `connected == true`. `ContentView.KuroMainView` observes `.onChange(of: reconnectionGeneration)` to auto-refresh the active page (Discover → force bundle, Collection → user lists + feed, Clubs → notifications).
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

### Streaming availability
- `streaming_services` (id serial, canonical registry of streaming/reading platforms; 19 seed rows; columns: name, slug, logo_url, media_types, region_codes, is_active)
- `user_streaming_services` (user_id FK, service_id FK, language preference; UNIQUE(user_id, service_id); RLS scoped to auth.uid())
- RPCs (3): `batch_providers_for_media`, `club_shared_providers`, `save_user_streaming_services`
- GDPR: `user_streaming_services` added to `delete_user_concierge_data` cascade
- Feature flag: `streaming_availability_v1` (0% rollout)

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

### Social activity
- `title_comments` (id uuid, user_id FK, media_type [ANIME/MANGA], media_id int, body text 1-500 chars, created_at, updated_at; UNIQUE(user_id, media_type, media_id) — one comment per user per title)
- `title_comment_reactions` (id uuid, comment_id FK CASCADE, user_id FK, reaction_type CHECK(thumbs_up/thumbs_down), created_at; UNIQUE(comment_id, user_id))
- Helper: `shares_club_with(a_user uuid, b_user uuid)` SECURITY DEFINER — returns true if both users share at least one club
- RLS: comments visible only to users sharing a club with the author; reactions gated the same way
- RPCs (5): `upsert_title_comment`, `delete_title_comment`, `toggle_comment_reaction`, `fetch_friend_activity_for_title`, `count_friends_tracking`
- Rate limits: 10 comments per 5 minutes, 30 reactions per minute
- Feature flag: `social_activity_v1` (100% rollout)

### Ops / metrics
- `concierge_metrics_hourly`
- `llm_usage_daily_totals`
- `rate_limit_recent_top`
- `import_state` (cursor table for scheduled AniList imports)
- `import_runs` (optional; bulk-import functions write run history if present)
- `club_analytics` (club telemetry events; 90-day retention via housekeeping cron)

**Schema definitions are in** `supabase/migrations/`.

### Auth + RLS
- Supabase Auth is used (email/password, email confirmation disabled; OAuth can be added later).
- Inline sign-up validation: `AuthView.swift` checks email format (regex) and uniqueness (debounced `check_email_exists` RPC) in real time. `check_email_exists` is a SECURITY DEFINER function querying `auth.users`, granted to anon+authenticated.
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
- `ClubDetailView.swift`: 3-tab segmented picker (RAILS / THIS WEEK / POLLS). Chat tab removed in favor of title-level social activity layer. Settings sheet for owner/admin. Reactions row (fire/heart/eyes/100 capsules) on each rail item (gated by `clubs_reactions_v1`). Pace text on This Week items ("3 ep behind the group" / "In sync", gated by `clubs_pace_sync_v1`, requires sharing_level=progress and ≥3 members). Milestone celebration cards when all members complete a title. Realtime subscription (on appear/disappear, gated by `clubs_realtime_v1`). Add-to-rail: "+" button per rail header (gated by lock status + role), opens `AddItemToRailSheet` with media type toggle, debounced server-side search, typed `PostgrestError` handling (DUPLICATE_ITEM, NOT_A_MEMBER, RAIL_LOCKED, MEDIA_NOT_FOUND). Task lifecycle managed via `.onDisappear` cancellation. **Vote error handling**: `castVote` wrapped in do/catch with `.error` toast + `errorHaptic()`. **Accessibility**: `.accessibilityAddTraits(.isHeader)` on section headers.
- `ClubActivitySection.swift`: Embedded on `AnimeDetailView` and `MangaDetailView`. Shows club context: which clubs have this title, aggregate member statuses.
- `ProfileView.swift`: "Clubs" row opens ClubsView sheet (secondary access path).
- Monochrome status pills (no colored dots).

### Realtime
- `club_rail_items`, `club_polls`, `club_votes`, `club_rail_item_reactions`, `club_messages` added to `supabase_realtime` publication.
- iOS `subscribeToClubUpdates()` subscribes to club-specific channel on `ClubDetailView` appear, listening on 5 tables: `club_rail_items`, `club_polls`, `club_votes`, `club_rail_item_reactions`, `club_messages`. 500ms debounce triggers `refreshClubBundle`.
- Unsubscribes on disappear; switches subscription when opening a different club.

### Chat (deprecated — replaced by social activity layer)
- Club chat tab removed from iOS UI. `clubs_chat_v1` feature flag disabled (0%).
- `prune_club_messages` cron job unscheduled. `club_messages` table retained for data migration/cleanup.
- Replaced by title-level social activity: friend comments + reactions visible on anime/manga detail pages and card indicators.
- GDPR: CASCADE on user delete still in place for existing `club_messages` rows.

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
- **Streaming availability RPCs**:
  - `batch_providers_for_media(p_media_type, p_media_ids)` — returns streaming/reading providers for a batch of media IDs, joined against user's selected services
  - `club_shared_providers(p_club_id)` — returns providers shared by all members of a club (intersection)
  - `save_user_streaming_services(p_service_ids, p_language)` — upserts user's selected streaming services + language preference
- **Ops functions**:
  - `check_mirror_health()` — returns JSONB with mirror run stats (total runs, successes, failures, consecutive failures, alert boolean). Used for operational health monitoring.

<!-- BEGIN AUTO-MIGRATION-MAP -->

## 7.1) Auto migration map (objects by migration)

Generated: **2026-03-26T16:16:10.704Z** (git: `a8b9f78`)

Each migration is summarized by the objects it defines. For full SQL, open the file.

### supabase/migrations/20250109_remote_applied_placeholder.sql

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

### supabase/migrations/20260205231000_curated_rails.sql
- Tables (2): `public.curated_rail_items`, `public.curated_rails`
- Functions (1): `public.curated_rail_cards`
- Policies (2): `public.curated_rail_items:curated_rail_items_select_all`, `public.curated_rails:curated_rails_select_all`
- Indexes (1): `idx_curated_rail_items_rail_rank`
- Triggers (2): `curated_rail_items_set_updated_at`, `curated_rails_set_updated_at`

### supabase/migrations/20260205232000_concierge_mode_cache.sql
- Tables (1): `public.concierge_mode_cache`
- Policies (1): `public.concierge_mode_cache:concierge_mode_cache_own_all`
- Indexes (1): `idx_concierge_mode_cache_user_updated`
- Triggers (1): `concierge_mode_cache_set_updated_at`

### supabase/migrations/20260205232500_concierge_router_flag_and_retention.sql
- Functions (1): `public.concierge_housekeeping`

### supabase/migrations/20260205233000_concierge_modes_v2_config.sql

### supabase/migrations/20260205234000_curated_rails_seed.sql

### supabase/migrations/20260205235000_discover_bundle_use_curated_rails.sql
- Functions (1): `public.discover_bundle`

### supabase/migrations/20260206100000_concierge_modes_v3_expanded.sql

### supabase/migrations/20260206120000_curated_rails_expansion.sql

### supabase/migrations/20260206143000_fix_legacy_tags_and_comments.sql

### supabase/migrations/20260206150000_security_hardening_rls_and_views.sql
- Policies (5): `public.editorial_boosts:service_role_read`, `public.editorial_penalty_tags:service_role_read`, `public.editorial_tag_boosts:service_role_read`, `public.import_state:service_role_all`, `public.mirror_runs:service_role_all`

### supabase/migrations/20260206162329_curated_rails_expansion.sql

### supabase/migrations/20260206164200_security_hardening_rls_and_views.sql

### supabase/migrations/20260207000000_search_titles_enrich_year_format.sql
- Functions (1): `public.search_titles`

### supabase/migrations/20260207011000_curated_rails_vibes_seed.sql

### supabase/migrations/20260207012000_concierge_modes_v4_add_vibe_rail_ids.sql

### supabase/migrations/20260207020000_curated_rails_more_vibes_seed.sql

### supabase/migrations/20260207021000_concierge_modes_v5_add_more_vibe_rail_ids.sql

### supabase/migrations/20260208022035_phase0_remove_sequels.sql

### supabase/migrations/20260208022043_concierge_mode_analytics.sql
- Tables (1): `public.concierge_mode_analytics`
- Policies (1): `public.concierge_mode_analytics:mode_analytics_insert`
- Indexes (2): `idx_mode_analytics_created`, `idx_mode_analytics_mode_id`

### supabase/migrations/20260208022110_add_sports_mode.sql

### supabase/migrations/20260208022136_phase0_remove_misclassified.sql

### supabase/migrations/20260208022153_add_scifi_mode.sql

### supabase/migrations/20260208022239_add_horror_supernatural_mode.sql

### supabase/migrations/20260208022250_phase0_dedup_rails.sql

### supabase/migrations/20260208022326_phase0_slim_and_rerank.sql

### supabase/migrations/20260208022342_add_demographic_rails.sql

### supabase/migrations/20260208022356_update_concierge_config_new_modes.sql

### supabase/migrations/20260208022404_phase0_fix_classics.sql

### supabase/migrations/20260208023052_phase0_backfill_underpopulated_rails.sql

### supabase/migrations/20260208023221_phase0_dedup_backfilled_rails.sql

### supabase/migrations/20260208023331_phase0_final_backfill.sql

### supabase/migrations/20260208090000_refine_short_and_fantasy_rails.sql

### supabase/migrations/20260208091500_curated_rails_premium_picks_seed.sql

### supabase/migrations/20260208092000_concierge_modes_v6_add_premium_picks_rail_id.sql

### supabase/migrations/20260209000000_search_titles_add_cover_image.sql
- Functions (1): `public.search_titles`

### supabase/migrations/20260209100000_concierge_modes_v7_german_synonyms.sql

### supabase/migrations/20260209110000_concierge_modes_v8_expanded.sql

### supabase/migrations/20260209120000_new_vibe_rails.sql

### supabase/migrations/20260209135229_import_reconciliation.sql

### supabase/migrations/20260209200000_clubs_foundation.sql
- Tables (7): `public.club_members`, `public.club_poll_options`, `public.club_polls`, `public.club_rail_items`, `public.club_rails`, `public.club_votes`, `public.clubs`
- Functions (1): `public.generate_invite_code`
- Indexes (11): `idx_club_members_club`, `idx_club_members_user`, `idx_club_poll_options_poll`, `idx_club_polls_club_created`, `idx_club_rail_items_rail_sort`, `idx_club_rails_club_sort`, `idx_club_votes_option`, `idx_club_votes_poll`, `idx_club_votes_user`, `idx_clubs_created_by`, `idx_clubs_invite_code`
- Triggers (5): `club_members_set_updated_at`, `club_polls_set_updated_at`, `club_rail_items_set_updated_at`, `club_rails_set_updated_at`, `clubs_set_updated_at`

### supabase/migrations/20260209201000_clubs_rls_policies.sql
- Functions (3): `public.is_club_admin_or_owner`, `public.is_club_member`, `public.is_club_owner`

### supabase/migrations/20260209202000_clubs_rpcs.sql
- Functions (9): `public.add_club_rail_item`, `public.cast_club_vote`, `public.create_club`, `public.fetch_club_bundle`, `public.is_club_admin_or_owner`, `public.is_club_member`, `public.join_club`, `public.leave_club`, `public.sharing_level_rank`

### supabase/migrations/20260209220000_club_analytics.sql
- Tables (1): `public.club_analytics`
- Functions (2): `public.concierge_housekeeping`, `public.log_club_event`
- Indexes (2): `idx_club_analytics_club_id`, `idx_club_analytics_created_at`

### supabase/migrations/20260209224945_fix_mirror_cron_contention.sql

### supabase/migrations/20260211030140_feature_flags.sql
- Tables (1): `feature_flags`
- Functions (1): `update_feature_flags_timestamp`
- Triggers (1): `trg_feature_flags_updated_at`

### supabase/migrations/20260211100000_rag_tables.sql
- Extensions (1): `pg_trgm`
- Tables (6): `public.concierge_events`, `public.rag_entity_aliases`, `public.rag_entity_index`, `public.rag_entity_tags`, `public.rag_retrieval_cache`, `public.rag_retrieval_feedback`
- Functions (1): `public.rag_cache_cleanup`
- Policies (6): `public.concierge_events:concierge_events_insert_own`, `public.rag_entity_aliases:rag_entity_aliases_select_anon`, `public.rag_entity_index:rag_entity_index_select_anon`, `public.rag_entity_tags:rag_entity_tags_select_anon`, `public.rag_retrieval_feedback:rag_feedback_insert_own`, `public.rag_retrieval_feedback:rag_feedback_select_own`
- Indexes (5): `idx_concierge_events_name_market_created`, `idx_rag_cache_expires`, `idx_rag_entity_aliases_entity_id`, `idx_rag_entity_locale_year_format`, `idx_rag_entity_tags_entity_id`
- Triggers (1): `rag_entity_index_set_updated_at`

### supabase/migrations/20260211110000_privacy_retention_and_gdpr.sql
- Functions (2): `public.concierge_housekeeping`, `public.delete_user_concierge_data`
- Policies (3): `public.concierge_events:concierge_events_insert_own`, `public.rag_retrieval_feedback:rag_feedback_insert_own`, `public.rag_retrieval_feedback:rag_feedback_select_own`

### supabase/migrations/20260211113000_rag_retrieve_candidates.sql
- Functions (1): `public.rag_retrieve_candidates`

### supabase/migrations/20260211154000_fetch_club_bundle_member_identity.sql
- Functions (1): `public.fetch_club_bundle`

### supabase/migrations/20260211162000_reduce_school_shoujo_overlap.sql

### supabase/migrations/20260211170000_enable_concierge_intelligence_de_canary.sql

### supabase/migrations/20260213130000_clubs_concierge_swipe_flags.sql

### supabase/migrations/20260213143000_concierge_editorial_v1_flag.sql

### supabase/migrations/20260215124919_add_create_rail_and_poll_rpcs.sql

### supabase/migrations/20260215124946_create_club_rail_and_poll_rpcs.sql

### supabase/migrations/20260215125056_fix_invite_code_crypto_and_club_members_insert.sql

### supabase/migrations/20260215125312_club_reactions_and_invite_share.sql

### supabase/migrations/20260215130000_fix_club_fk_housekeeping_gdpr.sql
- Functions (3): `public.check_club_activity_since`, `public.concierge_housekeeping`, `public.delete_user_concierge_data`

### supabase/migrations/20260216015514_clubs_list_enrichment.sql
- Functions (1): `public.fetch_my_clubs_enriched`

### supabase/migrations/20260216015733_club_reactions_in_bundle.sql
- Functions (1): `public.fetch_club_bundle`

### supabase/migrations/20260216015921_clubs_realtime_publication.sql

### supabase/migrations/20260216020023_club_messages.sql
- Tables (1): `public.club_messages`
- Functions (2): `public.fetch_club_messages`, `public.send_club_message`
- Policies (3): `public.club_messages:club_messages_delete_own`, `public.club_messages:club_messages_insert_member`, `public.club_messages:club_messages_select_member`
- Indexes (1): `idx_club_messages_club_created`

### supabase/migrations/20260216193000_add_club_rail_item_structured_errors.sql
- Functions (1): `public.add_club_rail_item`

### supabase/migrations/20260216200204_catalog_created_at_not_null.sql

### supabase/migrations/20260216200227_drop_unused_indexes_merge_policies_health_check.sql
- Functions (1): `check_mirror_health`
- Policies (1): `club_members:club_members_delete_self_or_admin`

### supabase/migrations/20260216214047_fix_initplan_rls_club_messages_reactions.sql
- Policies (5): `public.club_messages:club_messages_delete_own`, `public.club_messages:club_messages_insert_member`, `public.club_messages:club_messages_select_member`, `public.club_rail_item_reactions:club_reactions_delete_own`, `public.club_rail_item_reactions:club_reactions_insert_member`

### supabase/migrations/20260216214050_authors_tags_created_at_not_null.sql

### supabase/migrations/20260218131735_fix_join_club_archived_check.sql
- Functions (1): `public.join_club`

### supabase/migrations/20260218141739_capture_club_message_functions.sql
- Functions (2): `public.fetch_club_messages`, `public.send_club_message`

### supabase/migrations/20260218141754_update_join_create_club_functions.sql
- Functions (2): `public.create_club`, `public.join_club`

### supabase/migrations/20260218141757_fix_storage_insert_policy.sql
- Policies (1): `storage.objects:Authenticated users can upload media`

### supabase/migrations/20260218173617_drop_duplicate_indexes.sql

### supabase/migrations/20260218173619_drop_dead_rag_cache_cleanup.sql

### supabase/migrations/20260219002612_critical_security_drop_and_revoke.sql
- Policies (1): `public.concierge_mode_analytics:mode_analytics_insert`

### supabase/migrations/20260219002639_drop_start_bulk_import_with_args.sql

### supabase/migrations/20260219002706_revoke_public_from_admin_functions.sql

### supabase/migrations/20260219003105_add_user_lists_to_realtime_publication.sql

### supabase/migrations/20260219003111_anime_is_adult_not_null.sql

### supabase/migrations/20260219003305_drop_ambiguous_overloads.sql

### supabase/migrations/20260219003323_harden_toggle_reaction.sql
- Functions (1): `public.toggle_club_reaction`

### supabase/migrations/20260219003339_harden_create_club.sql
- Functions (1): `public.create_club`

### supabase/migrations/20260219003351_tighten_club_write_policies.sql
- Policies (5): `public.club_members:club_members_delete_self_or_admin`, `public.club_messages:club_messages_delete_own`, `public.club_messages:club_messages_insert_member`, `public.club_rail_item_reactions:club_reactions_delete_own`, `public.club_rail_item_reactions:club_reactions_insert_member`

### supabase/migrations/20260219003357_tighten_storage_update_policy.sql
- Policies (1): `storage.objects:Authenticated users can update own media`

### supabase/migrations/20260219003402_add_missing_fk_indexes.sql
- Indexes (2): `idx_club_messages_user_id`, `idx_rag_retrieval_feedback_selected_entity_id`

### supabase/migrations/20260219003703_cron_cleanup_and_mirror_auth.sql
- Cron (6): `mirror-images-anime-manga-0 @ 0 2 * * *`, `mirror-images-anime-manga-200 @ 15 2 * * *`, `mirror-images-anime-manga-400 @ 30 2 * * *`, `mirror-images-character @ 45 2 * * *`, `mirror-images-staff @ 0 3 * * *`, `prune_club_messages @ 15 3 * * *`

### supabase/migrations/20260219100000_critical_security_drop_and_revoke.sql
- Policies (1): `public.concierge_mode_analytics:mode_analytics_insert`

### supabase/migrations/20260219100001_drop_start_bulk_import_with_args.sql

### supabase/migrations/20260219100002_revoke_public_from_admin_functions.sql

### supabase/migrations/20260219100003_add_user_lists_to_realtime_publication.sql

### supabase/migrations/20260219100004_anime_manga_is_adult_not_null.sql

### supabase/migrations/20260219100005_drop_ambiguous_overloads.sql

### supabase/migrations/20260219100006_harden_toggle_reaction.sql
- Functions (1): `public.toggle_club_reaction`

### supabase/migrations/20260219100007_harden_create_club.sql
- Functions (1): `public.create_club`

### supabase/migrations/20260219100008_tighten_club_write_policies.sql
- Policies (5): `public.club_members:club_members_delete_self_or_admin`, `public.club_messages:club_messages_delete_own`, `public.club_messages:club_messages_insert_member`, `public.club_rail_item_reactions:club_reactions_delete_own`, `public.club_rail_item_reactions:club_reactions_insert_member`

### supabase/migrations/20260219100009_tighten_storage_update_policy.sql
- Policies (1): `storage.objects:Authenticated users can update own media`

### supabase/migrations/20260219100010_add_missing_fk_indexes.sql
- Indexes (2): `idx_club_messages_user_id`, `idx_rag_retrieval_feedback_selected_entity_id`

### supabase/migrations/20260219100011_cron_cleanup_and_mirror_auth.sql
- Cron (1): `prune_club_messages @ 15 3 * * *`

### supabase/migrations/20260219114953_set_not_null_on_nullable_required_columns.sql

### supabase/migrations/20260219120000_set_not_null_on_nullable_required_columns.sql

### supabase/migrations/20260219153000_manga_chapter_enrichment_v1.sql
- Tables (2): `public.manga_source_link_review`, `public.manga_source_links`
- Functions (2): `public.get_manga_chapter_enrich_candidates`, `public.get_manga_chapter_enrich_metrics`
- Indexes (4): `idx_manga_source_link_review_manga_pending`, `idx_manga_source_link_review_provider_status`, `idx_manga_source_link_review_status_created_at`, `idx_manga_source_links_manga_provider_status`
- Triggers (2): `manga_source_link_review_set_updated_at`, `manga_source_links_set_updated_at`

### supabase/migrations/20260219234000_fix_manga_chapter_enrich_cron_secret.sql

### supabase/migrations/20260219235500_manga_review_approved_mapping_method.sql

### supabase/migrations/20260220103000_manga_fuzzy_matcher_v2.sql
- Functions (2): `public.get_manga_chapter_enrich_candidates`, `public.get_manga_match_quality_metrics`
- Indexes (2): `idx_manga_source_links_manga_provider_status_next_verify`, `idx_manga_source_links_status_next_verify_at`

### supabase/migrations/20260221120000_browse_filters_year_format.sql
- Functions (2): `public.browse_anime_page`, `public.browse_manga_page`

### supabase/migrations/20260221150000_manga_fuzzy_matcher_method_allow_title_fuzzy.sql

### supabase/migrations/20260221162000_manga_zero_touch_canonical_mapping.sql
- Tables (1): `public.manga_mapping_alias_memory`
- Functions (2): `public.get_manga_chapter_enrich_candidates`, `public.get_manga_chapter_status`
- Indexes (2): `idx_manga_mapping_alias_memory_lookup`, `idx_manga_source_link_review_status_next_retry`

### supabase/migrations/20260221173000_manga_chapter_crunch_mode.sql
- Functions (1): `public.get_manga_chapter_enrich_candidates`

### supabase/migrations/20260221190000_enable_swipe_tap_guard_v1.sql

### supabase/migrations/20260221191000_synopsis_enhancement_fields.sql
- Indexes (2): `idx_anime_synopsis_enhanced_queue`, `idx_manga_synopsis_enhanced_queue`

### supabase/migrations/20260221192000_synopsis_enrichment_rpcs.sql
- Functions (3): `public.get_synopsis_enrichment_candidates`, `public.mark_synopsis_enhanced_failed`, `public.upsert_synopsis_enhanced`

### supabase/migrations/20260223002000_synopsis_retry_backoff_and_resume.sql
- Functions (4): `public.get_synopsis_enrichment_backlog_count`, `public.get_synopsis_enrichment_candidates`, `public.mark_synopsis_enhanced_failed`, `public.upsert_synopsis_enhanced`
- Indexes (2): `idx_anime_synopsis_retry_queue`, `idx_manga_synopsis_retry_queue`

### supabase/migrations/20260224101000_catalog_safety_runner_v1.sql
- Tables (2): `public.catalog_safety_audit`, `public.catalog_safety_terms`
- Functions (5): `public.get_catalog_safety_backlog_count`, `public.get_catalog_safety_candidates`, `public.get_catalog_safety_open_gaps`, `public.mark_catalog_safety_failed`, `public.upsert_catalog_safety_result`
- Indexes (6): `idx_anime_safety_blocked`, `idx_anime_safety_queue`, `idx_catalog_safety_audit_lookup`, `idx_catalog_safety_audit_state`, `idx_manga_safety_blocked`, `idx_manga_safety_queue`

### supabase/migrations/20260224150000_social_activity_layer.sql
- Tables (2): `public.title_comment_reactions`, `public.title_comments`
- Functions (6): `public.count_friends_tracking`, `public.delete_title_comment`, `public.fetch_friend_activity_for_title`, `public.shares_club_with`, `public.toggle_comment_reaction`, `public.upsert_title_comment`
- Policies (7): `title_comment_reactions:comment_reactions_delete`, `title_comment_reactions:comment_reactions_insert`, `title_comment_reactions:comment_reactions_select`, `title_comments:title_comments_delete`, `title_comments:title_comments_insert`, `title_comments:title_comments_select`, `title_comments:title_comments_update`
- Triggers (1): `title_comments_updated_at`

### supabase/migrations/20260225100000_check_email_exists_rpc.sql
- Functions (1): `public.check_email_exists`

### supabase/migrations/20260301100000_streaming_availability_v1.sql
- Tables (2): `public.streaming_services`, `public.user_streaming_services`
- Functions (4): `public.batch_providers_for_media`, `public.club_shared_providers`, `public.delete_user_concierge_data`, `public.save_user_streaming_services`
- Policies (4): `public.streaming_services:streaming_services_public_read`, `public.user_streaming_services:uss_delete_own`, `public.user_streaming_services:uss_insert_own`, `public.user_streaming_services:uss_select_own`
- Indexes (1): `idx_external_links_media`

### supabase/migrations/20260301153000_streaming_availability_country_lang_v1.sql
- Tables (3): `public.provider_availability`, `public.provider_availability_refresh_state`, `public.provider_source_map`
- Functions (5): `public.batch_provider_availability_for_media_v2`, `public.enqueue_media_availability_refresh`, `public.get_media_availability_status`, `public.get_media_provider_availability_detail`, `public.get_provider_availability_refresh_candidates`
- Indexes (7): `idx_provider_availability_audio_gin`, `idx_provider_availability_last_seen`, `idx_provider_availability_media`, `idx_provider_availability_provider_country`, `idx_provider_availability_refresh_due`, `idx_provider_availability_subtitle_gin`, `idx_provider_source_map_status`

### supabase/migrations/20260304100000_credits_cast_v1_flag.sql

### supabase/migrations/20260305151500_fix_delete_user_concierge_data_uuid_compare.sql
- Functions (1): `public.delete_user_concierge_data`

### supabase/migrations/20260305153000_fix_delete_user_concierge_data_import_sessions_and_coverage.sql
- Functions (1): `public.delete_user_concierge_data`

### supabase/migrations/20260305162000_cleanup_db_lint_warnings.sql
- Functions (2): `public.batch_providers_for_media`, `public.generate_invite_code`

### supabase/migrations/20260306113000_provider_availability_note_contract.sql
- Functions (1): `public.batch_provider_availability_for_media_v2`

### supabase/migrations/20260307120000_media_relations_ladder_v1.sql
- Tables (1): `public.media_relations`
- Functions (1): `public.get_media_ladder`
- Indexes (2): `idx_media_relations_from`, `idx_media_relations_to`
- Triggers (1): `media_relations_set_updated_at`

### supabase/migrations/20260307150000_adaptation_ladder_v2_editorial_context.sql
- Tables (1): `public.media_relation_refresh_queue`
- Functions (2): `public.enqueue_media_relation_refresh`, `public.get_media_ladder`
- Indexes (1): `idx_media_relation_refresh_queue_status_requested`
- Triggers (1): `media_relation_refresh_queue_set_updated_at`

### supabase/migrations/20260307163000_fix_adaptation_ladder_entry_point.sql
- Functions (1): `public.get_media_ladder`

### supabase/migrations/20260311100000_ladder_source_author.sql
- Functions (1): `public.get_media_ladder`

### supabase/migrations/20260313100000_slim_club_bundle_limits.sql
- Functions (1): `public.fetch_club_bundle`

### supabase/migrations/20260313120000_social_activity_v1_rollout_100.sql

### supabase/migrations/20260316100000_fix_club_bundle_columns_and_reactions.sql
- Functions (1): `public.fetch_club_bundle`

### supabase/migrations/20260316220000_clubs_list_cover_images_members.sql
- Functions (1): `public.fetch_my_clubs_enriched`

### supabase/migrations/20260317063000_clubs_list_cover_image_large.sql
- Functions (1): `public.fetch_my_clubs_enriched`

### supabase/migrations/20260317110000_fetch_club_bundle_ordering_and_poll_counts.sql
- Functions (1): `public.fetch_club_bundle`

### supabase/migrations/20260318103000_import_track_and_worker_state.sql
- Tables (3): `public.image_mirror_state`, `public.import_track_state`, `public.manga_chapter_enrich_state`
- Views (3): `public.image_mirror_state_metrics`, `public.import_track_state_metrics`, `public.manga_chapter_enrich_state_metrics`
- Policies (3): `public.image_mirror_state:service_role_all`, `public.import_track_state:service_role_all`, `public.manga_chapter_enrich_state:service_role_all`
- Indexes (6): `idx_image_mirror_state_last_run_at`, `idx_image_mirror_state_state_visibility`, `idx_import_track_state_media_type_updated_at`, `idx_import_track_state_preset_state`, `idx_manga_chapter_enrich_state_last_run_at`, `idx_manga_chapter_enrich_state_state_visibility`

### supabase/migrations/20260318104000_club_loading_rpcs.sql
- Functions (2): `public.fetch_club_bundle_loading`, `public.fetch_my_clubs_loading`

### supabase/migrations/20260319123000_provider_availability_request_priority.sql
- Functions (3): `public.enqueue_media_availability_refresh`, `public.get_provider_availability_refresh_candidates`, `public.get_provider_availability_refresh_queue_summary`
- Indexes (1): `idx_provider_availability_refresh_request_priority`

### supabase/migrations/20260322110000_add_list_verdicts.sql

### supabase/migrations/20260324173000_search_title_priority.sql
- Extensions (1): `pg_trgm`
- Functions (2): `public.search_anime_page`, `public.search_manga_page`

### supabase/migrations/20260324180000_search_title_popularity_tiebreak.sql
- Extensions (1): `pg_trgm`
- Functions (2): `public.search_anime_page`, `public.search_manga_page`

### supabase/migrations/20260324213000_discover_airing_today_berlin_day.sql
- Functions (1): `public.discover_bundle`

### supabase/migrations/20260326221000_discover_new_to_you_rotation.sql
- Tables (1): `public.discover_rail_impressions`
- Functions (1): `public.discover_bundle`
- Indexes (1): `discover_rail_impressions_lookup_idx`

### supabase/migrations/20260326234000_exclude_ancillary_anime_from_default_surfaces.sql
- Extensions (1): `pg_trgm`
- Tables (1): `public.discover_rail_impressions`
- Functions (5): `public.browse_anime_page`, `public.browse_manga_page`, `public.discover_bundle`, `public.search_anime_page`, `public.search_manga_page`
- Indexes (1): `discover_rail_impressions_lookup_idx`


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

Generated: **2026-03-26T16:16:10.704Z** (git: `a8b9f78`)

### auth-callback
- Source: `supabase/functions/auth-callback/index.ts`

### bulk-import-anime
- Source: `supabase/functions/bulk-import-anime/index.ts`
- Env vars: `IMPORT_HEAVY_ENABLED`, `IMPORT_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `acquire_import_lock`, `release_import_lock`
- Tables touched: `anime`, `anime_characters`, `anime_staff`, `anime_studios`, `anime_tags`, `characters`, `episodes`, `external_links`, `import_runs`, `import_state`, `import_track_state`, `media_relations`, `staff`, `studios`, `tags`

### bulk-import-manga
- Source: `supabase/functions/bulk-import-manga/index.ts`
- Env vars: `IMPORT_HEAVY_ENABLED`, `IMPORT_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `acquire_import_lock`, `release_import_lock`
- Tables touched: `authors`, `chapters`, `characters`, `external_links`, `import_runs`, `import_state`, `import_track_state`, `manga`, `manga_authors`, `manga_characters`, `manga_staff`, `manga_tags`, `media_relations`, `staff`, `tags`, `volumes`

### concierge-apply
- Source: `supabase/functions/concierge-apply/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `log_concierge_run`
- Tables touched: `anime`, `anime_user_lists`, `episodes`, `import_session_items`, `import_sessions`, `manga`, `manga_user_lists`, `title_aliases`

### concierge-import-anilist
- Source: `supabase/functions/concierge-import-anilist/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`

### concierge-parse
- Source: `supabase/functions/concierge-parse/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `get_concierge_config`, `log_concierge_parse_feedback`, `log_concierge_run`, `search_titles`
- Tables touched: `anime_user_lists`, `manga_user_lists`, `title_aliases`

### concierge-recommend
- Source: `supabase/functions/concierge-recommend/index.ts`
- Env vars: `GROQ_API_KEY`, `GROQ_MODEL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `curated_rail_cards`, `get_concierge_config`, `is_flag_enabled`, `llm_budget_finalize`, `llm_budget_reserve`, `llm_global_budget_finalize`, `llm_global_budget_reserve`, `log_concierge_run`, `recommend_ids_premium`, `recommend_ids_similar_to_seeds`, `search_titles`
- Tables touched: `anime`, `concierge_mode_cache`, `editorial_boosts`, `editorial_tag_boosts`, `feature_flags`, `manga`, `tags`, `user_lists`

### concierge-resolve
- Source: `supabase/functions/concierge-resolve/index.ts`
- Env vars: `GROQ_API_KEY`, `GROQ_MODEL`, `GROQ_MODEL_RESOLVE`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `get_concierge_config`, `is_flag_enabled`, `llm_budget_finalize`, `llm_budget_reserve`, `llm_global_budget_finalize`, `llm_global_budget_reserve`

### concierge-retrieve-assist
- Source: `supabase/functions/concierge-retrieve-assist/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `rag_retrieve_candidates`
- Tables touched: `rag_retrieval_cache`

### concierge-retrieve-feedback
- Source: `supabase/functions/concierge-retrieve-feedback/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`
- Tables touched: `rag_retrieval_feedback`

### concierge-undo
- Source: `supabase/functions/concierge-undo/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `log_concierge_run`
- Tables touched: `anime_user_lists`, `import_session_items`, `import_sessions`, `manga_user_lists`

### delete-account
- Source: `supabase/functions/delete-account/index.ts`
- Env vars: `APPLE_CLIENT_ID`, `APPLE_CLIENT_SECRET`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `delete_user_concierge_data`
- Tables touched: `anime_user_lists`, `club_members`, `clubs`, `manga_user_lists`, `media`, `profiles`

### manga-chapter-enrich
- Source: `supabase/functions/manga-chapter-enrich/index.ts`
- Env vars: `IMPORT_SECRET`, `MANGA_MATCHER_MODE`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `acquire_import_lock`, `get_manga_chapter_enrich_candidates`, `get_manga_match_quality_metrics`, `release_import_lock`
- Tables touched: `chapters`, `import_runs`, `manga`, `manga_chapter_enrich_state`, `manga_mapping_alias_memory`, `manga_source_link_review`, `manga_source_links`

### manga-source-review-action
- Source: `supabase/functions/manga-source-review-action/index.ts`
- Env vars: `IMPORT_SECRET`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- Tables touched: `manga_source_link_review`, `manga_source_links`

### mirror-images
- Source: `supabase/functions/mirror-images/index.ts`
- Env vars: `IMPORT_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `acquire_import_lock`, `release_import_lock`
- Tables touched: `anime`, `characters`, `image_mirror_state`, `manga`, `mirror_runs`, `staff`


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
- **Clubs** is the 5th page (rightmost). Profile sheet also has a "Clubs" shortcut. Club list cards show member count, activity preview, and unread dot. Club detail has 3 tabs (Rails/This Week/Polls — chat tab removed). Reactions (fire/heart/eyes/100) on rail items. Pace tracking on This Week. Milestone celebrations. Realtime updates. Badge dot on Clubs page indicator for unseen activity. Cards have "Add to Club..." context menu. Friend activity indicators on cards show how many friends are tracking each title.
- **Browse** is a first-class page (3rd position), no longer a sheet modal.
- **Search** remains a global sheet accessible from the header magnifying-glass icon on any page.
- **Performance**: distance-based page mounting (current ± 1 neighbors mounted, distant pages use placeholder). `.snappy(duration: 0.22)` pager animation. 120fps ProMotion enabled via `CADisableMinimumFrameDurationOnPhone`. Exclusion zone filtering limited to viewport.
- **Gesture system**: Card taps use `.kuroDeliberateTap {}` modifier (simple `.onTapGesture` + `suppressCardTaps` environment check). The pager sets `suppressCardTaps = true` during swipes to prevent accidental taps; the `.kuroDeliberateTap` modifier reads this flag and ignores taps when suppressed. No custom `DragGesture` on card taps — avoids competing with ScrollView vertical/horizontal drags. Pager constants in `KuroGesturePolicy.swift` (`postSwipeTapCooldownMs`, `fastFlingPredictedDxPt`, `fastFlingDirectionRatio`). The `swipe_tap_guard_v1` feature flag (100%) gates the pager's `suppressCardTaps` logic, not the tap recognizer itself.
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

### Gate scripts (8 gates + runner + test data)
1. **`check_secrets.sh`** — Scans Swift/TypeScript/JavaScript for hardcoded secrets (service_role JWTs, sbp_/sk-/gsk_ keys). No false-positive on publishable anon key (by design: only flags service_role patterns). Whitelists test fixtures and env var references.
2. **`check_migrations.sh`** — Checks for untracked/modified SQL files in `supabase/migrations/`, generates/verifies SHA-256 checksums (`.checksums` file). Read-only by default; pass `--update` to write checksums. Warning-only (no hard fail on modified migrations).
3. **`test_router_offline.sh`** — Runs `router_test_cases.js` which tests `scoreMode()` / `mapStrongGenreToModeId()` logic offline (no network). Hard fail on test failure.
4. **`audit_rails.sh`** — Wraps `scripts/audit_curated_rails_quality.js` (prefers env vars for Supabase credentials). Hard fail on: adult content, overlap > 40%, rail size > 100 or < 5, score below floor, franchise duplicates. Warning on: overlap > 15%, rail size near limits. Runs in both JSON and human-readable mode.
5. **`check_docs_current_state.sh`** — Wrapper around `check_docs_current_state.py`; verifies the top-level repo counts in `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, and `CLAUDE.md` match the real repo inventory and that required documentation surfaces exist. Hard fail on drift.
6. **`build_ios.sh`** — Runs `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`. Hard fail on build error.
7. **`test_ios_unit.sh`** — Runs `xcodebuild test` on the Kuro scheme. Primary destination is `iPhone 17 Pro (iOS 26.2)`; fallback picks another available `iPhone 17 Pro` simulator first, then an `iPhone 17` simulator if needed. Hard fail on test failure.
8. **`run_all.sh`** — Orchestrator: runs all gates, prints summary table, exits 1 if any blocking gate fails. Supports `SKIP_IOS_BUILD=1`, `SKIP_RAILS_AUDIT=1`, and `SKIP_IOS_TEST=1` env vars for faster runs.

### Supporting files (not gates)
- **`router_test_cases.js`** — Offline router test fixtures/runner used by `test_router_offline.sh`.
- **`check_docs_current_state.py`** — Python implementation used by `check_docs_current_state.sh`.

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

### 2026-03-06 — Detail CTA copy fallback cleanup

Updated detail-page link copy so the CTA note reflects actual data availability instead of pretending we know more than we do.

Files changed:
- `Kuro/Views/DetailPages/AnimeDetailView.swift`
- `Kuro/Views/DetailPages/MangaDetailView.swift`

Behavior change:
- If a legal watch/read link exists but no verified provider-availability metadata is present, anime now shows `Availability, audio, and subtitle options may vary by region.` and manga shows `Reading availability may vary by region and publisher.`
- If no legal link exists, both detail pages now show `Link coming soon.` in the CTA note slot.
- Matching no-link toast copy and manga chapter/list empty-state link copy were updated to the same `Link coming soon.` language for consistency.

Validation:
- `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` → `BUILD SUCCEEDED`

### 2026-03-06 — Free streaming availability research spike (non-production)

Added a research-only benchmark harness to test whether free GitHub sources are strong enough for `platform + country + EN/DE audio/subtitle note` before touching the deferred provider-availability rollout.

New files:
- `research/streaming_availability/free_streaming_availability_spike.py`
- `research/streaming_availability/benchmark_manifest.json`
- `research/streaming_availability/provider_mappings.json`
- `research/streaming_availability/README.md`

Report outputs (local only):
- `reports/streaming-availability-research/title_by_title.json`
- `reports/streaming-availability-research/provider_country_aggregate.csv`
- `reports/streaming-availability-research/precision_review.md`
- `reports/streaming-availability-research/unresolved_mismatches.md`

Spike rules:
- No Supabase writes, no migrations, no UI wiring.
- `simple-justwatch-python-api` is used as the only title-level source (via a local Python 3.9-compatible adapter against the same GraphQL contract because the upstream package requires newer typing syntax than the local interpreter).
- `justwatch-selenium-api` remains adapter-scoped but unavailable in this environment (missing Selenium stack), and is treated as optional.
- `anime-streaming` is parsed only as `service_region_hint`, never as title-level truth.

Benchmark result:
- 50 titles total (`25 anime`, `25 manga`) from Kuro's own catalog.

### 2026-03-06 — Streaming note contract hardening

Tightened streaming/provider note rendering so the app only claims what the backend actually knows.

Files changed:
- `Kuro/Models/SupabaseModels.swift`
- `Kuro/Services/SupabaseService.swift`
- `Kuro/Views/DetailPages/AnimeDetailView.swift`
- `Kuro/Views/DetailPages/MangaDetailView.swift`
- `Kuro/Views/DetailPages/EntityDetailSheets.swift`
- `KuroTests/KuroTests.swift`
- `supabase/migrations/20260306113000_provider_availability_note_contract.sql`

Behavior change:
- Provider availability notes now use a typed contract: `dub`, `audio`, `subtitles`, or generic `availability`.
- `dub` is emitted only when the offered audio language differs from the inferred original language. Unknown originals now fall back to `audio`, never forced `dub`.
- Subtitle-only evidence now renders as `EN subtitles: ...` / `DE subtitles: ...` instead of being dropped.
- Manga detail pages intentionally stay on the generic legal-link copy path; Kuro does not currently have trustworthy per-title manga locale metadata.
- Character works rails now use composite mixed-media identity keys (`anime-123` vs `manga-123`) so anime/manga with the same numeric ID cannot collide in SwiftUI.

Backend/runtime:
- Added follow-up migration `20260306113000_provider_availability_note_contract.sql` to extend `batch_provider_availability_for_media_v2` with `audio_languages`, `subtitle_languages`, and `countries_by_sub_lang`.
- Applied remotely via `supabase db push --linked --include-all`.
- `supabase db lint --linked` remains clean after the migration.

Validation:
- `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` → `BUILD SUCCEEDED`
- `xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test -only-testing:KuroTests` → `TEST SUCCEEDED`
- Added targeted tests for EN/DE dub/audio/subtitle note derivation and mixed anime/manga rail identity.
- Deterministic JustWatch matches: `13/50`.
- Titles with title-level locale evidence: `12/50`.
- Anime split: `13/25` matches, `12/25` locale-evidence titles.
- Manga split: `0/25` matches, `0/25` locale-evidence titles.

Decision:
- Useful as research for anime provider/country plus locale hints.
- Not strong enough to productionize as Kuro's source of truth, especially for manga.
- The deferred paid-source/provider-availability scaffold remains the intended production path; this spike is evidence gathering only.

### 2026-03-02 — Streaming availability parked behind feature flag (deferred rollout)

Decision: pause rollout of the new provider country/language metadata path and keep all related UI/backend behavior behind `streaming_availability_v1` at 0%.

What is implemented and retained (not enabled by default):
- Pre-production migration scaffold: `20260301153000_streaming_availability_country_lang_v1.sql`
  - Tables: `provider_source_map`, `provider_availability`, `provider_availability_refresh_state`
  - RPCs: `batch_provider_availability_for_media_v2`, `get_media_provider_availability_detail`, `enqueue_media_availability_refresh`, `get_media_availability_status`, `get_provider_availability_refresh_candidates`
- Local operational tooling:
  - `scripts/provider_availability_worker.swift`
  - `scripts/run_provider_availability.sh`
  - `scripts/install_provider_availability_launchd.sh`
  - `scripts/provider_availability_dashboard_server.js` (`localhost:8789`)

Release posture:
- Keep current production behavior on existing legal-link paths.
- Do not enable streaming availability features broadly until provider API source/cost strategy is finalized.

### 2026-03-01 — Streaming Availability v1 ("Where to Watch/Read")

New feature: streaming/reading provider availability on cards, collection filters, profile settings, and club shared-provider views. Gated behind `streaming_availability_v1` feature flag at 0% rollout.

Backend (migration `20260301100000_streaming_availability_v1.sql`):
- 2 new tables: `streaming_services` (canonical registry, 19 seed rows), `user_streaming_services` (per-user selections + language, RLS scoped to `auth.uid()`)
- 3 new RPCs: `batch_providers_for_media`, `club_shared_providers`, `save_user_streaming_services`
- GDPR: `user_streaming_services` added to `delete_user_concierge_data` cascade

iOS:
- `SupabaseService.swift`: provider cache, batch prefetch, CRUD, club shared providers, registry fetch, bootstrap (~120 lines)
- `SupabaseRPCParams.swift`: 2 new param structs (`RPCBatchProvidersParams`, `RPCSaveStreamingServicesParams`)
- `FeatureFlags.swift`: `isStreamingAvailabilityV1Enabled` accessor
- `EditorialCollectionView.swift`: service + language filter pills (tri-state), provider prefetch alongside friend count prefetch
- `KuroRefinedCard.swift`: provider badge on KuroPortraitCard + KuroCompactCard
- `ProfileView.swift`: services preview card + `StreamingServicePickerSheet` + `ServiceToggleRow`
- `ClubDetailView.swift`: shared availability toggle, coverage text, dimmed cards, rail prefetch

Other:
- `normalizedExternalLanguage` visibility changed from `private` to `internal`
- Hardcoded allowlist arrays annotated with `TODO` for removal when flag reaches 100%

Totals: 0 new Swift files, 7 modified Swift files, 1 new migration. 64 Swift files, 144 migrations.

### 2026-02-28 — Concierge Import UX Improvements

Major UX improvements to the concierge import flow across 3 files:

**ConciergeImportCards.swift — Improved import cards:**
- Poster enlarged: 70x100pt → 80x114pt with sharp edges (matches editorial style)
- Title typography: `.kuroTitle()` 19pt serif → `.kuroBody(weight: .medium)` 15pt sans-serif
- New: Media type badge (ANIME/MANGA capsule) on each card
- New: Parsed intent row showing status + progress (e.g., "WATCHING · Ep 12 of 24")
- New: Tap poster or title opens `MediaDetailSheet` for preview
- Removed: Redundant "N% match" text line (ring indicator sufficient)
- `episodeText` now renders actual progress data from parsed item
- Auto-expand "Other possibilities" when top match score < 0.80
- Press feedback: `scaleEffect(0.98)` animation on interaction

**ConciergeComponents.swift — Enhanced confirm bubble:**
- New: Loading state on CONFIRM button (spinner + "APPLYING" text, button disabled)
- New: Applied state shows summary text + UNDO button + VIEW COLLECTION button (persistent in bubble, no longer toast-only)
- New properties: `onUndo`, `onViewCollection`, `isApplying`, `appliedSummary`
- Confirm button disabled state now more visually distinct

**ConciergeView.swift — Flow improvements:**
- New state: `applyingImportMessageId` tracks which message is actively applying
- New state: `appliedImportSummary` stores human-readable summary (e.g., "2 added, 1 updated")
- `confirmImport()` now sets applying state during network call, builds summary from server response
- `autoApplyImport()` chat message now includes title list (bulleted)
- "View Collection" navigation via `kuro://collection` deep link

**ContentView.swift:**
- No structural changes, ConciergeView init unchanged

Files changed: 4 (ConciergeImportCards.swift, ConciergeComponents.swift, ConciergeView.swift, ContentView.swift)
New files: 0. New migrations: 0.

### 2026-02-28 — Fix Concierge Import False Success Toast
- **Bug**: `autoApplyImport()` and `confirmImport()` in ConciergeView.swift showed success toast unconditionally, even when `concierge-apply` returned `success: false`. Items appeared "added" but weren't.
- **Fix**: Added `guard res.success` check in both functions. On failure: shows error toast with server error detail. On success: uses `res.applied?.count` for accurate counts.
- **Investigation**: Confirmed production `anime_user_lists.user_id` / `manga_user_lists.user_id` are TEXT (not INTEGER). Type mismatch hypothesis ruled out.
- Files changed: `ConciergeView.swift` (2 functions modified).

### 2026-02-26 — Simplify KuroDeliberateTap Gesture (Fix Scroll + Tap Reliability)

Replaced the over-aggressive `DragGesture(minimumDistance: 0)` tap recognizer in `KuroDeliberateTap.swift` with a simple `.onTapGesture` + single `suppressCardTaps` environment check. The old gesture had 5 sequential guards (6pt movement, 80ms dwell, 220ms post-rail cooldown, suppressCardTaps, didCancelTap) that: (a) competed with ScrollView for vertical drags, (b) rejected ~30% of legitimate taps, (c) interfered with horizontal rail scrolling via a competing drag recognizer.

Files changed:
- `KuroDeliberateTap.swift`: `DragGesture(minimumDistance: 0)` + 5 guards replaced with `.onTapGesture` + `suppressCardTaps` check. API unchanged (`.kuroDeliberateTap {}`).
- `KuroGesturePolicy.swift`: removed 3 unused constants (`deliberateTapMinDwellMs`, `deliberateTapMaxMovementPt`, `dragCancelMovementPt`). Kept pager constants.
- No changes to `KuroGestureCoordinator.swift`, `KuroPagingGesture.swift`, `ContentView.swift`, or card call sites.
- `swipe_tap_guard_v1` stays at 100% — gates the pager's `suppressCardTaps` logic (correct), not the tap recognizer.

Totals: 0 new files, 2 modified Swift files, 0 new migrations. 64 Swift files, 143 migrations.

### 2026-02-24 — Social Activity Layer + Add to Club Context Menu

Major feature: replaced club-level ephemeral chat with title-level social activity.

Backend (migration `20260224150000_social_activity_layer.sql`):
- New tables: `title_comments` (one comment per user per title, 500 char max), `title_comment_reactions` (thumbs_up/thumbs_down per comment, one per user)
- New SECURITY DEFINER helper: `shares_club_with(a_user, b_user)` — returns true if both users share at least one club
- RLS: comments and reactions visible only to users who share a club with the author
- 5 new RPCs: `upsert_title_comment`, `delete_title_comment`, `toggle_comment_reaction`, `fetch_friend_activity_for_title`, `count_friends_tracking`
- Rate limits: 10 comments/5min, 30 reactions/min (via `rate_limit_buckets`)
- Feature flag: `social_activity_v1` at 100% rollout
- Chat deprecation: `prune_club_messages` cron unscheduled, `clubs_chat_v1` flag disabled

iOS models + service layer:
- `SupabaseService.swift`: 6 new models (`TitleComment`, `FriendTitleActivity`, `FriendActivityResponse`, `FriendCountItem`, `UpsertCommentResponse`, `ToggleCommentReactionResponse`), 4 service functions (`fetchFriendActivityForTitle`, `upsertTitleComment`, `deleteTitleComment`, `toggleCommentReaction`), friend count cache with batch prefetch (`prefetchFriendCounts`)
- `SupabaseRPCParams.swift`: 5 new RPC param structs

iOS UI — detail page friends activity section:
- New file: `Kuro/Views/DetailPages/FriendsActivitySection.swift` — friend tracking pills, comments with thumbs up/down reactions, comment input
- `AnimeDetailView.swift` and `MangaDetailView.swift`: added `FriendsActivitySection` after `ClubActivitySection`

iOS UI — card friend indicators + batch prefetch:
- `KuroRefinedCard.swift`: friend count indicator on Portrait, Compact, and Hero card types + "Add to Club..." context menu on all 3 types
- `Cards.swift`: friend count indicator on SharedVertical + SharedHorizontal cards
- `EditorialDiscoverView.swift`, `BrowseView.swift`, `EditorialCollectionView.swift`: prefetch triggers for friend counts after page data loads

iOS UI — Add to Club context menu:
- `ClubActivitySection.swift`: `AddToClubRailSheet` made public (was private) so card context menus can present it

iOS UI — club chat tab removed:
- `ClubDetailView.swift`: `.chat` removed from Tab enum, `ClubChatTab` (~240 lines) and `ClubChatBubble` (~75 lines) structs deleted, tabs simplified to 3 (Rails/This Week/Polls)
- `FeatureFlags.swift`: removed `isClubsChatV1Enabled`, added `isSocialActivityV1Enabled`

Totals: 2 new files, 12 modified files. ~316 lines removed (chat), ~600 lines added. 64 Swift files, 142 migrations. Build: SUCCEEDED.

### 2026-02-24 — Catalog safety uncertain-rate remediation

Investigated high uncertain rates in catalog safety runs (e.g. ~340/400 uncertain).

Root cause confirmed from live reports:
- `uncertain-latest.md` reason distribution showed almost all open gaps as:
  - `model_uncertain`
  - `no_strong_signal`
- This meant the model was returning conservative `uncertain` for many records with no porn signal, and worker logic had no safe fallback in that branch.

Worker logic hardening:
- Updated `/Applications/Kuro/scripts/catalog_safety_worker.swift`:
  - Prompt now explicitly instructs: choose `safe` when there are no explicit porn indicators.
  - Added deterministic safe fallback when:
    - model is uncertain/unavailable, and
    - rules have no meaningful signal (`hits.isEmpty`, low score threshold via `CATALOG_SAFETY_SAFE_FALLBACK_MAX_RULE_SCORE`, default `40`).
  - Added run metric: `safe_fallback_no_signal`.
  - Added `safe_fallback_no_signal` to per-run summary log output.

Dashboard update:
- Updated `/Applications/Kuro/scripts/catalog_safety_dashboard_server.js` to show:
  - `safe_fallback_no_signal` (run-level card)

Validation:
- `xcrun swiftc -parse-as-library scripts/catalog_safety_worker.swift -o /tmp/catalog_safety_worker_check`
- `node --check scripts/catalog_safety_dashboard_server.js`
- Forced run validation (latest run):
  - `processed=240 blocked=5 safe=235 uncertain=0`
  - `safe_fallback_no_signal=137`

### 2026-02-24 — Audit remediation: safety open-gaps reliability + doc snapshot correction

Implemented follow-up fixes from the senior audit findings:

Safety pipeline reliability:
- Updated `/Applications/Kuro/scripts/catalog_safety_worker.swift` to remove silent fallback on open-gaps fetch.
- `get_catalog_safety_open_gaps` fetch now uses explicit `do/catch` instead of `try?`.
- Added run metric: `open_gaps_fetch_failed`.
- Added `open_gaps_fetch_failed` to per-run summary log output for quicker CLI troubleshooting.
- On fetch failure, worker appends a warning to `worker.log` and preserves `uncertain-latest.md` (writes only run-specific fallback output), preventing false “zero gaps” states.

Documentation snapshot correctness:
- Refreshed auto-inventory section in `/Applications/Kuro/CURRENT_APP_STATE.md` using:
  - `node scripts/generate_app_state_inventory.js`
- Corrected stale runtime version claims in `/Applications/Kuro/CLAUDE.md`:
  - `manga-chapter-enrich:v10`
  - `bulk-import-anime:v20`
  - `bulk-import-manga:v19`
- Enhanced `/Applications/Kuro/scripts/catalog_safety_dashboard_server.js` with progress visualization:
  - session baseline/remaining/reduced counters
  - completion percentage
  - last-run backlog delta
  - progress rail UI on `http://127.0.0.1:8788`

Validation in this pass:
- `xcrun swiftc -parse-as-library scripts/catalog_safety_worker.swift -o /tmp/catalog_safety_worker_check`
- `node scripts/generate_app_state_inventory.js`

### 2026-02-24 — Separate catalog-safety runner + open-gaps visibility flow

Implemented a fully separate catalog-safety pipeline without changing the synopsis runner lifecycle.

Backend support (migration scaffolded):
- Added migration: `/Applications/Kuro/supabase/migrations/20260224101000_catalog_safety_runner_v1.sql`
- Adds catalog safety state columns to `anime` and `manga` (`safety_state`, `safety_blocked`, model/rule metadata, scan/retry timestamps).
- Adds lexicon + audit tables:
  - `public.catalog_safety_terms`
  - `public.catalog_safety_audit`
- Seeds baseline EN/DE/JP-romaji safety terms and system flag key `catalog_safety_enforce_v1` (default disabled).
- Adds service-role RPCs:
  - `get_catalog_safety_candidates(...)`
  - `upsert_catalog_safety_result(...)`
  - `mark_catalog_safety_failed(...)`
  - `get_catalog_safety_open_gaps(p_limit int)`
  - `get_catalog_safety_backlog_count(...)`

Local runtime + isolation:
- New worker: `/Applications/Kuro/scripts/catalog_safety_worker.swift`
  - Uses separate report root: `/Applications/Kuro/reports/catalog-safety/`
  - Pulls candidates via RPC, applies rule matching + optional Apple FM classification, writes decisions via RPC.
  - Generates:
    - `latest-status.json`
    - `run-*.log`
    - `uncertain-latest.md`
    - `uncertain-<run>.md`
- New runner: `/Applications/Kuro/scripts/run_catalog_safety.sh`
  - Uses independent lock: `/Applications/Kuro/reports/catalog-safety/.worker.lock`
  - Uses stale-lock self-heal pattern (PID + TTL), isolated from synopsis lock files.
- New launchd installer: `/Applications/Kuro/scripts/install_catalog_safety_launchd.sh`
  - Label: `com.kuro.catalog-safety`
  - Default interval: 600s (10 minutes)
  - Default batch size: 200

Separate dashboard:
- Added `/Applications/Kuro/scripts/catalog_safety_dashboard_server.js`
- Local URL: `http://127.0.0.1:8788`
- Panels include scanned/blocked/safe/uncertain counts, blocked-by-rules vs blocked-by-model, open source gaps (`uncertain-latest.md`), run history, and launchd worker state.

Validation in this pass:
- `xcrun swiftc -parse-as-library scripts/catalog_safety_worker.swift -o /tmp/catalog_safety_worker_check`
- `bash -n scripts/run_catalog_safety.sh`
- `bash -n scripts/install_catalog_safety_launchd.sh`
- `node --check scripts/catalog_safety_dashboard_server.js`

### 2026-02-23 — Synopsis enrichment runtime hardening + dashboard observability sync

Verified and documented the current synopsis enrichment state:
- Remote migration parity includes `20260223002000_synopsis_retry_backoff_and_resume.sql` (`supabase migration list --linked`).
- Deployed function snapshot includes:
  - `manga-chapter-enrich` version `9`
  - `bulk-import-anime` version `19`
  - `bulk-import-manga` version `18`
  (from `supabase functions list --project-ref bkdifromsqxkndnllmdj`).

Synopsis pipeline updates captured in this state refresh:
- Worker: `scripts/synopsis_enrichment_worker.swift`
  - now tracks due-backlog before/after (`backlog_due_before`, `backlog_due_after`)
  - emits quality counters (`tone_polish_used`, `fallback_used`, `autodeduped_sentences`)
  - writes generated outputs to `reports/synopsis-enrichment/generated-samples-latest.md` + per-run sample files.
- Runner/install scripts:
  - `scripts/run_synopsis_enrichment.sh` now enforces single-run lock (`.worker.lock`) and compile-on-change behavior
  - lock handling now self-heals stale locks using PID metadata + TTL (`SYNOPSIS_LOCK_TTL_SECONDS`, default 1800s), then reacquires automatically
  - default synopsis profile tuned for concise editorial copy (`140..420` chars, `3..4` sentences)
  - `scripts/install_synopsis_enrichment_launchd.sh` preserves existing env values and fails fast when required Supabase secrets are missing.
- Dashboard: `scripts/synopsis_dashboard_server.js`
  - added cumulative totals and 24h rollups
  - added generated-samples panel/API and run-history columns for tone/fallback/dedup metrics.
  - fixed `/api/status` timestamp fallback so `updated_at` is always populated from latest run/file metadata when `latest-status.json` lacks it.

Operational result:
- Synopsis worker + dashboard now provide resumable backlog processing visibility and explicit quality telemetry without requiring manual per-run log inspection.

### 2026-02-20 — Import cursor reset bug fixed in run_full_import.js

Patched `/Applications/Kuro/scripts/run_full_import.js` `ensureImportState()` so it no longer resets `import_state.last_page` to `0` on every run.
- Previous behavior used `upsert({ media_type, last_page: 0 })`, which rewound cursors.
- New behavior seeds both media rows with conflict-safe insert semantics:
  - `upsert([...], { onConflict: "media_type", ignoreDuplicates: true })`
  - Existing cursor positions are preserved.

Run verification after patch:
- script syntax check: `node --check scripts/run_full_import.js` passed.

### 2026-02-20 — Full import script auto-fallback on timeout

Updated `/Applications/Kuro/scripts/run_full_import.js` to auto-recover when edge imports hit gateway timeouts (`504/524` or timeout text):
- Added `shouldFallback(...)` detection for timeout-class failures.
- Added schedule-safe fallback payload builder (`buildFallbackPayload(...)`) per media type.
- `runImporter(...)` now:
  - logs the failure,
  - runs one schedule-safe lightweight batch automatically,
  - continues loop on successful fallback instead of aborting the full run.

Smoke verification:
- fallback path triggered in live run after anime `504` and advanced cursor (`last_page: 0 -> 1`) with successful fallback results.

### 2026-02-20 — Collision tie-break loosened + English preference + chapter insert fix

`manga-chapter-enrich` was updated and deployed to reduce unresolved mappings in AL/MAL collision cases and to prefer English-titled candidates when confidence is close:
- Collision tie-break thresholds relaxed:
  - min score `0.82` (was `0.92`)
  - min margin `0.03` (was `0.07`)
- Added English-title preference in collision scoring:
  - explicit English title similarity signal + boost
  - preference helper that selects strong/medium English-title candidates while avoiding edition-marker variants (`webtoon version`, `oneshot`, `promo`, `pilot`) where possible.
- Increased chapter-coverage weight in collision score to favor candidates with actual usable chapter depth.

Critical ingest fix:
- Replaced chapter `upsert(... onConflict: "manga_id,number")` with read-then-insert dedupe logic because the remote schema/index shape did not accept that conflict target via PostgREST.
- Added race-safe duplicate handling on insert (`23505` tolerated per-row fallback).

Validation:
- `manga-chapter-enrich` deployed as version `v6`.
- Forced enrich on AniList `86707` (`Yao Shen Ji` / `Tales of Demons and Gods`) now succeeds:
  - mapping set to MangaDex `812f9696-048f-496d-9ed4-84c99345d1fb`
  - chapter rows inserted: `321`
  - `manga.chapters` updated to `468`
  - `get_manga_chapter_status(263)` now reports `mapping_status = ready`.

### 2026-02-20 — Backend parity closed (migrations + functions deployed)

Executed sequential release actions:
1. `supabase db push --linked --include-all --yes`
2. `supabase functions deploy manga-chapter-enrich --project-ref bkdifromsqxkndnllmdj`
3. `supabase functions deploy manga-source-review-action --project-ref bkdifromsqxkndnllmdj`

Verification:
- `supabase migration list --linked` now shows both `20260221150000` and `20260221162000` applied remotely.
- `supabase functions list --project-ref bkdifromsqxkndnllmdj` now shows:
  - `manga-chapter-enrich` version `4`
  - `manga-source-review-action` version `2`
- `supabase db lint --linked` remains warnings-only (`generate_invite_code` `_i` variable warning).
- `supabase inspect db db-stats --linked` remains healthy.
- `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` remains `BUILD SUCCEEDED`.

### 2026-02-20 — Supabase CLI parity check + docs sync

Validation run completed from `/Applications/Kuro`:
- `supabase functions list --project-ref bkdifromsqxkndnllmdj`
- `supabase migration list --linked`
- `supabase db lint --linked`
- `supabase inspect db db-stats --linked`
- `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build`

Result snapshot:
- iOS build passes: `BUILD SUCCEEDED`.
- DB lint has warnings only (`public.generate_invite_code` shadowed/unused loop variable `_i`), no hard lint failures.
- Runtime DB health is stable (cache hit rates: index `0.99`, table `0.98`; no long-running or blocking queries).
- Deployed function inventory is healthy but behind local changes for chapter enrichment stack:
  - `manga-chapter-enrich` deployed version `3`
  - `manga-source-review-action` deployed version `1`
- Migration parity is not fully converged yet: local migrations `20260221150000` and `20260221162000` are present locally but not applied remotely.

Documentation updated in this pass:
- `CURRENT_APP_STATE.md` (this entry)
- `CURRENT_APP_STATE_PLAIN.md`
- `CLAUDE.md`

### 2026-02-20 — Manga Fuzzy Mapping v2 (No-manual-review ops)

**Edge function**: `supabase/functions/manga-chapter-enrich/index.ts` upgraded with runtime-selectable matcher modes (`strict` / `fuzzy_v2`) and kill-switch behavior.
- Added fuzzy scoring path after AL/MAL exact matches:
  - Jaro-Winkler title similarity, token Jaccard overlap, alias exact signal
  - weighted score `0.55/0.30/0.15`
  - gating by confidence threshold + top-2 margin + hard conflict checks
- Added verification-memory flow for pinned mappings:
  - periodic verify on `next_verify_at`
  - verify status + fail counters
  - deactivate mapping after repeated mismatches and rematch safely
- Added run metrics fields:
  - `fuzzy_attempted`, `fuzzy_auto_mapped`, `skipped_low_confidence`, `skipped_ambiguous`
  - `verify_checked`, `verify_mismatch`, `verify_deactivated`, `wrong_map_proxy_count`
  - `mode_used`, `mode_degraded`
- Added safety degrade:
  - if rolling `wrong_map_proxy_rate_pct` exceeds configured limit, run degrades to `strict` for that execution.

**DB migration**: `supabase/migrations/20260220103000_manga_fuzzy_matcher_v2.sql`
- Extended `manga_source_links` with verification lifecycle columns:
  - `last_verified_at`, `next_verify_at`, `verify_status`, `verify_fail_count`, `last_verify_reason`
- Updated `get_manga_chapter_enrich_candidates(...)` priority policy:
  - added class `4` for active mappings due verification
- Added quality RPC:
  - `get_manga_match_quality_metrics(p_hours int default 24)`
- Added daily review housekeeping cron:
  - pending `manga_source_link_review` rows older than 30 days auto-mark `rejected` with `reason='auto_expired'`

**Ops script**: `scripts/check_cron_health.js`
- Added matcher quality scorecard output:
  - auto-resolve rate, wrong-map proxy rate, unresolved trend (24h vs previous 24h),
    verify checked/deactivated, fuzzy auto-share, pending review count, latest matcher mode/degraded status.

### 2026-02-20 — Senior Full-Stack Stability Audit Artifacts

- Added evidence-backed audit deliverables:
  - `/Applications/Kuro/docs/audit-2026-02-20-manifest.md`
  - `/Applications/Kuro/docs/audit-2026-02-20-findings.md`
  - `/Applications/Kuro/docs/audit-2026-02-20-remediation-plan.md`
  - `/Applications/Kuro/docs/audit-2026-02-20-release-gate.md`
- Gate decision captured as **NO-GO** until P0/P1 blockers are remediated.
- Verified prior P3 concern about add-to-rail string matching is resolved via structured `PostgrestError` mapping.

### 2026-02-18: Database Health Audit Fixes
- Dropped 2 duplicate indexes (`idx_chapters_id`, `idx_episodes_id`) saving ~19 MB
- Dropped dead `rag_cache_cleanup()` function (active job uses `rag_cleanup_expired_cache()`)
- Populated 3 previously remote-only migration files locally (club message, join/create club, storage policy)
- Migration count: 94 total (92 local + 2 remote-applied)
- Public functions: 67 (was 68)
- Postgres confirmed at 17.6
- Pending Dashboard items reduced from 6 to 3

### 2026-02-19 — Pre-ship Audit P0 Remediation

**DB Migration**: `20260219120000_set_not_null_on_nullable_required_columns.sql` — SET NOT NULL on 17 columns across 7 tables (`anime`, `manga`, `episodes`, `chapters`, `external_links`, `anime_user_lists`, `manga_user_lists`, `feature_flags`) to match non-optional Swift model properties. Prevents runtime decode crashes from unexpected NULL values.

**SupabaseService.swift — ConciergeParseItemParsed**:
- Added `rating: Double?`, `progressTotal: Int?`, `progressUnit: String?` to `ConciergeParseItemParsed` struct. Ratings from edge function parse responses were previously silently dropped due to missing Decodable properties.

**SupabaseService.swift — Realtime subscriptions**:
- `subscribeToClubUpdates()` now listens on 5 tables: `club_rail_items`, `club_polls`, `club_votes`, `club_rail_item_reactions`, `club_messages`. Previously only subscribed to `club_rail_items`, `club_votes`, and `club_rail_item_reactions` — new polls and chat messages did not trigger live refresh.

**SupabaseService.swift — Error surfacing**:
- `updateUserListProgress()` and `updateListRating()` now surface errors to `errorMessage` instead of silently printing. Users see feedback when progress/rating updates fail.

**ConciergeView.swift**:
- `buildApplyPayload()` now includes `rating` field from parsed items (was omitted, losing user-specified ratings on import apply).
- Added `initialPrompt` parameter for deep link prompt injection (`kuro://concierge?prompt=X`).

**ContentView.swift**:
- Deep link `kuro://concierge?prompt=X` now extracts prompt and passes to ConciergeView via `pendingConciergePrompt` state. Consumed once and cleared after 0.5s to prevent re-triggering.

**ClubDetailView.swift**:
- Chat tab now shows error/retry view on message load failure (was silent).
- `toggleReaction` surfaces errors via toast callback chain (was silent).

**ConciergeImportCards.swift**:
- Fixed mock initializer to include 3 new `ConciergeParseItemParsed` properties (`rating`, `progressTotal`, `progressUnit`), resolving a pre-existing build break.

**Totals**: 1 new migration (94 total: 92 local + 2 remote-applied), 4 Swift files modified. Migration also applied to production via MCP `apply_migration`.

### 2026-02-19 — Backend Quality Remediation (5 Phases)

**Phase 1: Critical Security**
- Dropped 5 dangerous functions: `check_and_trigger_sync()`, `start_bulk_import()` (both contained hardcoded service_role JWT), `heartbeat()`, `on_heartbeat()`, plus `start_bulk_import(text, integer)` overload
- Revoked anon/authenticated EXECUTE from 4 admin functions: `admin_schema_snapshot`, `rebuild_title_search`, `concierge_housekeeping`, `check_mirror_health`
- Fixed `concierge_mode_analytics` INSERT policy (was `WITH CHECK (false)` — silently blocked all inserts)

**Phase 2: Edge Function Auth**
- Added IMPORT_SECRET auth gate to `mirror-images` edge function (was completely unauthenticated)
- Deployed `concierge-import-anilist` edge function (14 total now)
- Updated all 5 mirror-images cron jobs to include `x-import-secret` header

**Phase 3: Swift Model + Realtime**
- Fixed Anime CodingKeys: `id_mal` → `mal_id`, `id_kitsu` → `kitsu_id` (matching actual DB columns)
- Changed `idKitsu` type from `String?` to `Int?` (DB column is integer)
- Removed dead properties from Anime: `tags` (no column), `trailerUrl` (no column), `tagsAsDictionary` computed property
- Removed dead `tags` property from Manga model (no column exists)
- Fixed Manga CodingKey: `id_mal` → `mal_id`
- Made `is_adult` NOT NULL on both `anime` and `manga` tables (was nullable)
- Added `anime_user_lists` and `manga_user_lists` to Realtime publication (fixes silent subscription failure)

**Phase 4: RPC Security + Policy Tightening**
- Dropped 2 ambiguous function overloads: `create_club_poll(jsonb)`, `recommend_ids_premium` (4-param)
- Added rate limit (30/min) + emoji allowlist (fire/heart/eyes/100) to `toggle_club_reaction`
- Added rate limit (5/hour) + club cap (20 max) to `create_club`
- Tightened 5 club write policies from `{public}` to `{authenticated}`
- Fixed storage UPDATE policy: added `owner_id` check to `WITH CHECK` clause
- Added 2 missing FK indexes: `club_messages.user_id`, `rag_retrieval_feedback.selected_entity_id`

**Phase 5: Cron Cleanup**
- Added `cleanup-cron-history` job (daily, retains 14 days)
- Removed duplicate `concierge_events_retention` weekly cleanup (covered by daily housekeeping)
- Moved `prune_club_messages` from 03:00 to 03:15 (resolved scheduling overlap)
- Updated all 5 mirror-images cron commands with `x-import-secret` header

**Totals**: 12 new migrations, 58 public functions (was 67), 14 edge functions (was 13), 7 RLS policies fixed, 2 FK indexes added

- 2026-02-19: **Manga Chapter Enrichment v1 (safe additive rollout)** —
  - Added migration `20260219153000_manga_chapter_enrichment_v1.sql`:
    - new tables `manga_source_links` (strict provider mapping) + `manga_source_link_review` (manual triage queue),
    - RPC `get_manga_chapter_enrich_candidates(p_limit, p_force_manga_id)` (missing/dirty-first selection),
    - RPC `get_manga_chapter_enrich_metrics(p_hours)` (coverage + run health + unresolved queue),
    - pg_cron job `manga-chapter-enrich-15m` (`*/15 * * * *`) calling new edge function with schedule-safe payload.
  - Added edge function `supabase/functions/manga-chapter-enrich/index.ts`:
    - secret-gated (`x-import-secret`), import lock key `manga-chapter-enrich`, `import_runs` logging (`run_type='chapter_enrich'`),
    - strict MangaDex mapping policy (`links.al` -> `links.mal` -> strict title match; otherwise review queue),
    - chapter aggregate ingestion with EN/DE-first language strategy + all-language fallback,
    - fractional chapter keys skipped and counted, idempotent upsert on `(manga_id, number)`, `last_synced_at` updates.
  - Added edge function `supabase/functions/manga-source-review-action/index.ts`:
    - secret-gated admin action endpoint for review queue rows (`approve`/`reject`),
    - approval writes explicit mapping with `mapping_method='review_approved'`,
    - approval triggers immediate one-title `manga-chapter-enrich` run (`forceMangaId`) for fast validation.
  - Added migration `20260219235500_manga_review_approved_mapping_method.sql`:
    - extends `manga_source_links.mapping_method` check to include `review_approved`.
  - iOS legal-link policy wired for manga:
    - `SupabaseService` now exposes `fetchLegalReadLinks(...)` + `getBestLegalReadLink(...)` using strict allowlist + locale ordering (EN/DE),
    - `MangaDetailView` chapter taps now use legal provider resolver (no `manga.siteUrl` fallback),
    - chapter/CTA UI now shows explicit "no legal read provider yet" messaging when no allowlisted link exists.
  - Ops:
    - `scripts/check_cron_health.js` now checks chapter enrichment metrics, recent `chapter_enrich` runs, and includes `manga-chapter-enrich` smoke invocation.
  - Validation:
    - `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` succeeded.
    - `node --check scripts/check_cron_health.js` succeeded.
    - Follow-up migration `20260219234000_fix_manga_chapter_enrich_cron_secret.sql` rescheduled `manga-chapter-enrich-15m` with a guaranteed `x-import-secret` header (DB setting first, safe fallback).

- 2026-02-18: **Audit follow-up — error handling, dead code cleanup, backend hardening** — 4-agent team fixed 21 findings from the 5-agent audit. **Swift error handling (8 fixes)**: AuthView `.onChange(of: authErrorMessage)` now surfaces auth errors to UI; `randomNonceString()` returns `String?` (was force-empty on failure); ClubDetailView added error toasts for leaveClub, POLL_CLOSED, CLUB_NOT_FOUND, RATE_LIMITED/MESSAGE_TOO_LONG on chat, haptic on reaction error; ClubsView added RATE_LIMITED on join. **Dead code cleanup (5 fixes)**: Deleted 4 unused files (DiscoverView.swift, SearchView.swift, SearchViewModel.swift, CollectionManagementView.swift — ~1,572 lines), extracted live `AddToListSheet` to new `AddToListSheet.swift`; removed `DiscoverViewNew`/`SearchViewNew` dead structs from ContentView (~523 lines); fixed 2 force-unwraps in MangaDetailView (`siteUrl!` → optional chaining); fixed 1 force-unwrap in ConciergeImportCards (`studioText!` → if-let); added `#if DEBUG` logging to 4 bare catch blocks in AppleFMService. **Backend (5 fixes)**: 3 migrations — `capture_club_message_functions` (send/fetch RPCs), `update_join_create_club_functions` (description validation max 500 chars + control char sanitization, dropped unused `validate_club_invite`), `fix_storage_insert_policy` (path restricted to `auth.uid()::text` folder); concierge-recommend input length limit (5000 chars); edge function redeployed. **Feature flags corrected**: `clubs_chat_v1`, `clubs_reactions_v1`, `clubs_realtime_v1` all at 100% (docs updated from 0%/50%). **Docs**: Added 3 manual Dashboard items (OTP expiry, leaked password protection, Postgres upgrade). 60 Swift files (was 64), 91 migrations (88 local + 3 remote-applied).
- 2026-02-18: **Pre-ship quality audit fixes** — 7-agent audit identified and fixed: (1) `withRetry` force-unwrap safety (`SupabaseService.swift:141` — `lastError!` → `lastError ?? URLError(.unknown)`); (2) Auth callback silent failure (`SupabaseService.swift:547` — now sets `authErrorMessage` in catch block so users see "Verification failed"); (3) `precondition` crash in AuthView nonce generation (`AuthView.swift:214` — replaced with `guard/return`); (4) BrowseGrid ForEach identity bug (`BrowseView.swift:1096` — `\.offset` → `\.id` to prevent O(n) re-render on pagination); (5) Unicode URL encoding for CJK/Korean external links (`AnimeDetailView.swift:1237`, `MangaDetailView.swift:1111` — added `addingPercentEncoding` fallback, fixes 1,417 broken links); (6) Privacy Manifest created (`Kuro/PrivacyInfo.xcprivacy` — UserDefaults `CA92.1` declaration, required for App Store submission); (7) `join_club` RPC archived check (migration `fix_join_club_archived_check` — blocks joining archived clubs via direct API). 89 migrations total.
- 2026-02-18: **Direct kuro:// redirect + Resend SMTP setup** — Changed `SupabaseService.authCallbackURL` from edge function URL to `kuro://auth/callback` directly, so Supabase redirects straight into the app after email verification (no intermediate webpage). `DeepLinkRouter.parseAuthParams()` now handles tokens from both URL fragment (`#access_token=...`) and query params. `Info.plist` created at project root with `CFBundleURLTypes` registering `kuro://` URL scheme. `INFOPLIST_FILE = Info.plist` added to project.pbxproj. Resend MCP server configured in `.mcp.json` for production email delivery. Commit: `13fa6f4`.
- 2026-02-17: **Branded email templates + auth callback deep linking** — 5 editorial email templates in `emails/` (confirm, reset-password, magic-link, change-email, invite) with monochrome Kuro branding (Cormorant serif wordmark, warm gray background, black CTA buttons). `auth-callback` edge function deployed (verify_jwt: false) — serves dark-themed HTML redirect page with animated K logo that extracts tokens from Supabase hash fragment and redirects to `kuro://auth/callback`. `DeepLinkRouter` extended with `.authCallback(accessToken:, refreshToken:)` case. `KuroApp.swift` intercepts auth callbacks at app level (before auth gate) and calls `handleAuthCallback()`. `SupabaseService` extended with `authCallbackURL`, `redirectTo` in `signUpWithEmail`/`resetPassword`, and `handleAuthCallback()` method using `setSession()`. Commit: `740a2b4`.
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
- **Apple FM availability**: `AppleFMService` gracefully degrades on non-FM devices via `StubFMProvider`. The `condenseSynopsis` cache is in-memory only (lost on app restart); consider persisting to disk if cache hit rates are low.

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

For a complete (very large) source bundle, see: `archive/CURRENT_APP_STATE_CODEBASE.md` (auto-generated).

Rebuild:
```bash
node scripts/generate_app_state_sources.js
node scripts/generate_app_state_codebase_bundle.js
```

<!-- BEGIN AUTO-SOURCE-EXCERPTS -->

Generated: **2026-03-26T16:16:10.828Z** (git: `a8b9f78`)

This section is auto-generated. Rebuild after any change to the referenced files:
```bash
node scripts/generate_app_state_sources.js
```

### iOS pager + swipe navigation (authoritative)

- Path: `Kuro/ContentView.swift`


```swift
// uses Kuro/Views/PosterView.swift
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
    @Binding var pendingDeepLink: DeepLink?
    @Environment(SupabaseService.self) private var supabaseService

    var body: some View {
        KuroRootView(pendingDeepLink: $pendingDeepLink)
            .environment(supabaseService)
    }
}

// MARK: - Root View with Launch
struct KuroRootView: View {
    @Binding var pendingDeepLink: DeepLink?
    @State private var showLaunchOverlay = true
    @State private var launchOpacity: Double = 1
    @State private var launchDismissTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            KuroMainView(pendingDeepLink: $pendingDeepLink)

            if showLaunchOverlay {
                KuroLaunchView()
                    .opacity(launchOpacity)
                    .transition(.opacity)
                    .onAppear {
                        launchDismissTask?.cancel()
                        launchOpacity = 1
                        launchDismissTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 160_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.25)) {
                                launchOpacity = 0
                            }
                            try? await Task.sleep(nanoseconds: 260_000_000)
                            guard !Task.isCancelled else { return }
                            showLaunchOverlay = false
                        }
                    }
                    .onDisappear {
                        launchDismissTask?.cancel()
                        launchDismissTask = nil
                    }
            }
        }
    }
}

// MARK: - Launch View
struct KuroLaunchView: View {
    @State private var logoOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()

            VStack(spacing: 8) {
                Text("KURO")
                    .font(.kuroHeadline(weight: .ultraLight))
                    .tracking(8)
                    .foregroundColor(.kuroBlack)
                    .opacity(logoOpacity)

                Text("CURATED ANIME")
                    .font(.kuroMicro(weight: .light))
                    .tracking(3)
                    .foregroundColor(.kuroTextTertiary)
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
    @Binding var pendingDeepLink: DeepLink?
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(NetworkMonitor.self) private var networkMonitor

    enum Section: Int, CaseIterable {
        case concierge, discover, browse, collection, clubs

        var title: String {
            switch self {
            case .concierge:
                return "CONCIERGE"
            case .discover:
                return "DISCOVER"
            case .browse:
                return "BROWSE"
            case .collection:
                return "COLLECTION"
            case .clubs:
                return "CLUBS"
            }
        }
    }

	@State private var selection: Section = .discover
	@State private var showProfileSheet = false
	@State private var showSearchSheet = false
	@State private var mountedSections: Set<Section> = [.discover]
	@State private var swipeExclusions: [CGRect] = []
    @State private var suppressCardTaps = false
    @State private var tapSuppressionResetTask: Task<Void, Never>? = nil
    @State private var didTrackSuppressionThisGesture = false
    @State private var didApplyStartArgument = false
    @State private var showOnboarding = !OnboardingView.hasCompletedOnboarding
    @State private var edgeBounceOffset: CGFloat = 0
    @State private var deepLinkAnimeId: Int? = nil
    @State private var deepLinkMangaId: Int? = nil
    @State private var deepLinkClubId: String? = nil
    @State private var pendingConciergePrompt: String? = nil
    @State private var pendingPromptClearTask: Task<Void, Never>? = nil
	// Five-page discovery funnel: Concierge ← [Discover] → Browse → Collection → Clubs
    private let swipeOrder: [Section] = [.concierge, .discover, .browse, .collection, .clubs]
    private let swipeThreshold: CGFloat = 40
    private let swipeEdgeMargin: CGFloat = 24

    private var conciergeEditorialV1Enabled: Bool {
        // Concierge has fully migrated to the editorial shell.
        true
    }

    private var hidesHeaderForConcierge: Bool {
        selection == .concierge && conciergeEditorialV1Enabled
    }

    private func sectionFromLaunchArgument(_ raw: String) -> Section? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "concierge": return .concierge
        case "discover": return .discover
        case "browse": return .browse
        case "collection": return .collection
        case "clubs": return .clubs
        default: return nil
        }
    }

    // MARK: - Swipe conflict helpers (deduplicated from onChanged/onEnded)

    private var rootWidth: CGFloat {
        #if os(iOS)
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width) ?? 393
        #else
        1024
        #endif
    }

    /// Returns true when the drag starts inside an exclusion zone and is NOT on a screen edge.
    private func isSwipeExcluded(start: CGPoint) -> Bool {
        let edgeAllowed = (start.x <= swipeEdgeMargin) || (start.x >= max(0, rootWidth - swipeEdgeMargin))
        let expanded = swipeExclusions.map { $0.insetBy(dx: -14, dy: -14) }
        return expanded.contains(where: { $0.contains(start) }) && !edgeAllowed
    }

    private func scheduleTapSuppressionReset(delayNs: UInt64 = 120_000_000) {
        tapSuppressionResetTask?.cancel()
        tapSuppressionResetTask = Task {
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            suppressCardTaps = false
        }
    }

    private func isFastFlingOverride(_ value: DragGesture.Value) -> Bool {
        let dx = abs(value.translation.width)
        let dy = abs(value.translation.height)
        let predictedDx = abs(value.predictedEndTranslation.width)
        guard dx > dy * KuroGesturePolicy.fastFlingDirectionRatio else { return false }
        return predictedDx >= KuroGesturePolicy.fastFlingPredictedDxPt
    }

    var body: some View {
	        ZStack {
	            Color.kuroBackground.ignoresSafeArea()

	            VStack(spacing: 0) {
                if !hidesHeaderForConcierge {
                    KuroHeaderNew(selection: $selection, showProfileSheet: $showProfileSheet, showSearchSheet: $showSearchSheet)
                }

                // Header-driven pager: keeps sections mounted once visited.
	                KuroSectionPager(
	                    selection: $selection,
	                    mountedSections: $mountedSections,
	                    order: swipeOrder,
                        suppressCardTaps: suppressCardTaps,
                        pendingConciergePrompt: pendingConciergePrompt
	                )
	                .offset(x: edgeBounceOffset)
	                .background(Color.clear)
	            }
	        }
	        .coordinateSpace(name: "kuro_root")
	        .onPreferenceChange(KuroSwipeExclusionPreferenceKey.self) { v in
	            let viewport = CGRect(x: 0, y: 0, width: rootWidth, height: 2000)
	            let visible = v.filter { $0.intersects(viewport) }
	            if visible != swipeExclusions {
	                swipeExclusions = visible
	            }
	        }
            .onAppear {
                // Debug support: launch directly into Concierge for screenshots or manual QA.
                // Example: `xcrun simctl launch booted com.kuro.app --args --kuro-start=concierge`
                guard !didApplyStartArgument else { return }
                didApplyStartArgument = true
                let args = ProcessInfo.processInfo.arguments
                if let kv = args.first(where: { $0.hasPrefix("--kuro-start=") }),
                   let value = kv.split(separator: "=", maxSplits: 1).last,
                   let target = sectionFromLaunchArgument(String(value))
                {
                    selection = target
                    mountedSections.insert(target)
                } else if args.contains("--kuro-start-concierge") {
                    selection = .concierge
                    mountedSections.insert(.concierge)
                }
            }
	        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named("kuro_root"))
                    .onChanged { value in
                        guard FeatureFlags.shared.isSwipeTapGuardEnabled else { return }
                        guard !KuroGestureCoordinator.shared.isHorizontalRailDragging else { return }
                        let excluded = isSwipeExcluded(start: value.startLocation)
                        if excluded && !isFastFlingOverride(value) { return }

                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        let predictedDx = abs(value.predictedEndTranslation.width)
                        let velocityHint = abs(value.predictedEndTranslation.width - value.translation.width)
                        guard dx > 12, dx > dy * 1.1 else { return }
                        guard predictedDx > 18 || velocityHint > 20 || dx > 24 else { return }
                        if !suppressCardTaps {
                            suppressCardTaps = true
                        }
                        if !didTrackSuppressionThisGesture {
                            didTrackSuppressionThisGesture = true
                            supabaseService.trackInteractionEvent(
                                "card_tap_suppressed_during_swipe",
                                surface: "root_pager",
                                result: "active"
                            )
                        }
                    }
	                .onEnded { value in
                        let shouldManageSuppression = FeatureFlags.shared.isSwipeTapGuardEnabled
                        defer { didTrackSuppressionThisGesture = false }
                        if shouldManageSuppression && suppressCardTaps {
                            scheduleTapSuppressionReset()
                        }
                        guard !KuroGestureCoordinator.shared.isHorizontalRailDragging else { return }
                        guard !KuroGestureCoordinator.shared.recentlyDraggedRail(withinMs: KuroGesturePolicy.postSwipeTapCooldownMs) else { return }

                        let excluded = isSwipeExcluded(start: value.startLocation)
                        if excluded && !isFastFlingOverride(value) { return }

	                    let dx = value.translation.width
	                    let dy = value.translation.height
	                    guard abs(dx) > abs(dy) * 0.85 else { return }

	                    let predictedDx = value.predictedEndTranslation.width
	                    let effectiveDx = abs(predictedDx) > abs(dx) ? predictedDx : dx
	                    guard abs(effectiveDx) >= swipeThreshold else { return }

	                    guard let currentIndex = swipeOrder.firstIndex(of: selection) else { return }
	                    let nextIndex = currentIndex + (effectiveDx < 0 ? 1 : -1)
	                    guard swipeOrder.indices.contains(nextIndex) else {
	                        KuroAccessibility.impactHaptic(.rigid)
	                        let bounceDirection: CGFloat = effectiveDx < 0 ? -1 : 1
	                        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
	                            edgeBounceOffset = bounceDirection * 12
	                        }
	                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
	                            edgeBounceOffset = 0
	                        }
	                        return
	                    }
	                    selection = swipeOrder[nextIndex]
	                    KuroAccessibility.impactHaptic(.light)

                        guard shouldManageSuppression else {
                            suppressCardTaps = false
                            return
                        }
                        let delayNs: UInt64 = abs(predictedDx) > 220 ? 280_000_000 : 120_000_000
                        scheduleTapSuppressionReset(delayNs: delayNs)
	                }
	        )
	            .onChange(of: selection) { _, newValue in
	                mountedSections.insert(newValue)
                    if newValue == .clubs {
                        supabaseService.clearClubNotificationBadge()
                    }
	            }
	            .task {
	                // Warm the Discover bundle so the first Discover render feels instant.
                _ = await supabaseService.fetchDiscoverBundle(limit: 30, hours: 24)
                // Check club notifications
                await supabaseService.checkClubNotifications()
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView(
                    onOpenConciergeImportReview: { prompt in
                        showProfileSheet = false
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            handleDeepLink(.concierge(prompt: prompt))
                        }
                    }
                )
                    .environment(supabaseService)
            }
            .sheet(isPresented: $showSearchSheet) {
                NavigationStack {
                    EditorialSearchView()
                        .environment(supabaseService)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { showSearchSheet = false }) {
                                    Image(systemName: "xmark")
                                        .font(.kuroBody(weight: .light))
                                        .foregroundColor(.kuroBlack60)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                }
            }
            .onDisappear {
                tapSuppressionResetTask?.cancel()
            }
            .onChange(of: networkMonitor.reconnectionGeneration) { _, _ in
                guard networkMonitor.isConnected else { return }
                Task {
                    switch selection {
                    case .discover:
                        _ = await supabaseService.fetchDiscoverBundle(limit: 30, hours: 24, force: true)
                    case .collection:
                        await supabaseService.fetchUserLists()
                        await supabaseService.fetchCollectionFeed(status: nil)
                    case .clubs:
                        await supabaseService.checkClubNotifications()
                    case .concierge, .browse:
                        break
                    }
                }
            }
            .onChange(of: pendingDeepLink) { _, link in
                guard let link else { return }
                pendingDeepLink = nil
                handleDeepLink(link)
            }
            .sheet(isPresented: Binding(
                get: { deepLinkAnimeId != nil },
                set: { if !$0 { deepLinkAnimeId = nil } }
            )) {
                if let animeId = deepLinkAnimeId {
                    MediaDetailSheet(kind: .anime, id: animeId)
                        .environment(supabaseService)
                }
            }
            .sheet(isPresented: Binding(
                get: { deepLinkMangaId != nil },
                set: { if !$0 { deepLinkMangaId = nil } }
            )) {
                if let mangaId = deepLinkMangaId {
                    MediaDetailSheet(kind: .manga, id: mangaId)
                        .environment(supabaseService)
                }
            }
            .sheet(isPresented: Binding(
                get: { deepLinkClubId != nil },
                set: { if !$0 { deepLinkClubId = nil } }
            )) {
                if let clubId = deepLinkClubId {
                    NavigationStack {
                        ClubDetailView(clubId: clubId)
                            .environment(supabaseService)
                    }
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    showOnboarding = false
                }
            }
            if let transientBannerMessage = supabaseService.transientBannerMessage {
                VStack {
                    KuroTransientBanner(message: transientBannerMessage)
                        .padding(.top, hidesHeaderForConcierge ? 20 : 10)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
    }

    private func handleDeepLink(_ link: DeepLink) {
        switch link {
        case .anime(let id):
            deepLinkAnimeId = id
        case .manga(let id):
            deepLinkMangaId = id
        case .club(let id):
            deepLinkClubId = id
        case .collection:
            selection = .collection
            mountedSections.insert(.collection)
        case .discover:
            selection = .discover
        case .concierge(let prompt):
            selection = .concierge
            mountedSections.insert(.concierge)
            pendingConciergePrompt = prompt
            // Clear after next runloop so ConciergeView can consume it once
            pendingPromptClearTask?.cancel()
            pendingPromptClearTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                pendingConciergePrompt = nil
            }
        case .authCallback:
            break // Handled at app level in KuroApp.swift, never reaches here
        }
    }
}

// MARK: - Interactive section pager (keeps tabs mounted once visited)
private struct KuroSectionPager: View {
    typealias Section = KuroMainView.Section

    @Binding var selection: Section
    @Binding var mountedSections: Set<Section>
    let order: [Section]
    let suppressCardTaps: Bool
    var pendingConciergePrompt: String?

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
            .environment(\.kuroSuppressCardTaps, suppressCardTaps)
            .offset(x: (-CGFloat(selectionIndex) * width))
            .clipped()
            // Animate only when the selection changes (header-driven paging).
            // This avoids gesture conflicts with in-page horizontal carousels.
            .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: selectionIndex)
        }
    }

    @ViewBuilder
    private func page(for section: Section) -> some View {
        let sectionIdx = order.firstIndex(of: section) ?? 0
        let distance = abs(selectionIndex - sectionIdx)
        // Mount current page + immediate neighbors; unmount distant pages to save memory.
        let shouldMount = distance <= 1 || mountedSections.contains(section)

        if shouldMount {
            switch section {
            case .concierge:
                ConciergeView(assistantEnabled: true, initialPrompt: pendingConciergePrompt)
            case .discover:
                EditorialDiscoverView()
            case .browse:
                BrowseView()
            case .collection:
                EditorialCollectionView()
            case .clubs:
                ClubsView()
            }
        } else {
            // Placeholder keeps layout stable without triggering `.task` in heavy pages.
            Color.kuroBackground
        }
    }
}

// MARK: - New Responsive Header Component (Fixed)
struct KuroHeaderNew: View {
    @Binding var selection: KuroMainView.Section
    @Binding var showProfileSheet: Bool
    @Binding var showSearchSheet: Bool
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
    @State private var previousSectionCleanupTask: Task<Void, Never>? = nil

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
                .background(shape.fill(Color.kuroWhite.opacity(0.001)))
                .overlay(
                    shape
                        .stroke(hint ? Color.kuroBlack12 : Color.kuroBlack06, lineWidth: 0.6)
                )
                // Subtle highlight to sell the "window" edge without changing the interior color.
                .overlay(
                    shape
                        .stroke(Color.kuroWhite80, lineWidth: 0.6)
                        .blendMode(.overlay)
                )
                .shadow(color: Color.kuroBlack06, radius: 10, x: 0, y: 6)

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

    @ViewBuilder
    private func headerIconCircle<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Circle()
            .fill(Color.kuroBlack06)
            .frame(width: 32, height: 32)
            .overlay { content() }
            .overlay(
                Circle().stroke(Color.kuroBlack10, lineWidth: 0.7)
            )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Three-part layout with proper spacing
            HStack(alignment: .center) {
                // Left: Brand (30% opacity)
                HStack(spacing: 10) {
                    Text("KURO")
                        .font(.kuroNavigation(weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.kuroTextTertiary)
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
                                    Circle().stroke(Color.kuroBlack10, lineWidth: 0.7)
                                )
                                .overlay(
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.kuroCustom(13, weight: .semibold, relativeTo: .caption1))
                                        .foregroundColor(.kuroBlack70)
                                )
                                .accessibilityHidden(true)
                        }

                        titleWindow
                    }

                    // Dot indicators for positional context
                    HStack(spacing: 5) {
                        ForEach(swipeOrder, id: \.self) { section in
                            ZStack {
                                Circle()
                                    .fill(section == selection ? Color.kuroTextSecondary : Color.kuroBlack15)
                                    .frame(width: 4, height: 4)

                                // Badge dot for Clubs when unseen activity exists
                                if section == .clubs && supabaseService.hasUnseenClubActivity && selection != .clubs {
                                    Circle()
                                        .fill(Color.kuroBlack70)
                                        .frame(width: 6, height: 6)
                                        .offset(x: 5, y: -3)
                                }
                            }
                        }
                    }
                    .animation(.easeOut(duration: 0.18), value: selection)
                    .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Section")
                .accessibilityValue(currentTitle)
                .accessibilityHint("Swipe left or right to change sections.")
                .frame(maxWidth: .infinity, alignment: .center)

                // Right: Actions
                HStack(spacing: 10) {
                    Spacer()

                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        showSearchSheet = true
                    }) {
                        headerIconCircle {
                            Image(systemName: "magnifyingglass")
                                .font(.kuroCustom(13, weight: .regular, relativeTo: .caption1))
                                .foregroundColor(.kuroBlack60)
                        }
                    }
                    .buttonStyle(KuroHeaderIconButtonStyle())
                    .accessibilityLabel("Search")
                    .accessibilityHint("Opens search")

                    Menu {
                        Button("Profile") {
                            showProfileSheet = true
                        }
                        Button("Sign Out", role: .destructive) {
                            Task { await supabaseService.signOut() }
                        }
                    } label: {
                        headerIconCircle {
                            Text(supabaseService.currentUserInitial)
                                .font(.kuroCustom(12, weight: .medium, relativeTo: .caption1))
                                .foregroundColor(.kuroBlack80)
                        }
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
                previousSectionCleanupTask?.cancel()
                previousSectionCleanupTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    if displayedSection == newValue {
                        previousSection = nil
                        withAnimation(.easeOut(duration: 0.12)) {
                            titleTextWidth = toWidth
                        }
                    }
                }
            }
            .onDisappear {
                previousSectionCleanupTask?.cancel()
                previousSectionCleanupTask = nil
            }

            // Subtle divider
            Rectangle()
                .fill(Color.kuroBlack08)
                .frame(height: 0.5)
        }
        .frame(height: 54)
        .background(Color.kuroBackground)
        .shadow(color: Color.kuroBlack08, radius: 10, x: 0, y: 6)
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
                    .font(.kuroNavigation(weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack)
                    .lineLimit(1)
                    .offset(x: (-progress) * dir * travel)
            }

            Text(current)
                .font(.kuroNavigation(weight: .regular))
                .tracking(1.5)
                .foregroundColor(.kuroBlack)
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


// MARK: - Preview
#Preview {
    ContentView(pendingDeepLink: .constant(nil))
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

    // Apple Foundation Models service (on-device classification/condensation)
    let fmService = AppleFMService()

    // Concierge telemetry (fire-and-forget, privacy-safe)
    let analytics = ConciergeAnalytics.shared

    // Supabase client (nil only when config is missing)
    let client: SupabaseClient!
    // Surface configuration errors to UI instead of crashing
    var configError: String? = nil
    // Realtime (user-scoped) subscriptions
    private var realtimeChannel: RealtimeChannelV2? = nil
    private var realtimeListenTasks: [Task<Void, Never>] = []
    private var realtimeDebounceTask: Task<Void, Never>? = nil
    private var realtimeSubscribedUserId: String? = nil

    // Auth state
    var isAuthBootstrapping: Bool = true
    var isAuthenticated: Bool = false
    var authErrorMessage: String? = nil
    private var authStateTask: Task<Void, Never>?
    // Lightweight identity for UI (header menus, etc.)
    var currentUserEmail: String? = nil
    // Used for local-only UI labeling (e.g. Clubs member list "You").
    var currentUserId: String? = nil

    var currentUserInitial: String {
        let c = currentUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).first
        return c.map { String($0).uppercased() } ?? "M"
    }

    nonisolated static func userFacingAuthErrorMessage(from error: Error) -> String {
        #if DEBUG
        let chain = authErrorChain(from: error)
            .map { "\($0.domain)(\($0.code)): \($0.localizedDescription)" }
            .joined(separator: " -> ")
        print("[Auth] error chain: \(chain)")
        #endif

        if let transportMessage = transportAuthErrorMessage(from: error) {
            return transportMessage
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("invalid login credentials") {
            return "Incorrect email or password. Please try again."
        } else if lower.contains("user already registered") {
            return "An account with this email already exists. Try signing in instead."
        } else if lower.contains("email not confirmed") {
            return "Please check your email to verify your account."
        } else if lower.contains("password should be at least") {
            return "Password must be at least 6 characters."
        }
        return "Something went wrong. Please try again."
    }

    nonisolated private static func transportAuthErrorMessage(from error: Error) -> String? {
        for candidate in authErrorChain(from: error) {
            guard candidate.domain == NSURLErrorDomain else { continue }
            let code = URLError.Code(rawValue: candidate.code)
            switch code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return "No internet connection. Check your connection and try again."
            case .networkConnectionLost:
                return "The network connection was lost. Please try again."
            case .timedOut:
                return "The request timed out. Please try again."
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .secureConnectionFailed, .cannotLoadFromNetwork,
                 .appTransportSecurityRequiresSecureConnection, .badServerResponse:
                return "Can't reach the server right now. Please try again."
            default:
                continue
            }
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("internet connection appears to be offline") ||
            lower.contains("not connected to the internet") {
            return "No internet connection. Check your connection and try again."
        } else if lower.contains("network connection was lost") {
            return "The network connection was lost. Please try again."
        } else if lower.contains("timed out") {
            return "The request timed out. Please try again."
        } else if lower.contains("cannot connect to the server") ||
                    lower.contains("could not connect to the server") ||
                    lower.contains("cannot connect to host") {
            return "Can't reach the server right now. Please try again."
        }
        return nil
    }

    nonisolated private static func authErrorChain(from error: Error) -> [NSError] {
        var queue: [NSError] = [error as NSError]
        var seen = Set<String>()
        var chain: [NSError] = []

        while let current = queue.first {
            queue.removeFirst()
            let key = "\(current.domain)#\(current.code)#\(current.localizedDescription)"
            if !seen.insert(key).inserted {
                continue
            }
            chain.append(current)
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                queue.append(underlying)
            } else if let underlying = current.userInfo[NSUnderlyingErrorKey] as? Error {
                queue.append(underlying as NSError)
            }
        }

        return chain
    }

    // MARK: - Shared interaction telemetry helpers

    typealias InteractionStartedAt = CFAbsoluteTime

    func beginInteractionTiming() -> InteractionStartedAt {
        CFAbsoluteTimeGetCurrent()
    }

    func trackInteractionEvent(
        _ event: String,
        surface: String,
        result: String,
        startedAt: InteractionStartedAt? = nil,
        extra: [String: Any] = [:]
    ) {
        var payload = extra
        payload["surface"] = surface
        payload["result"] = result
        payload["market"] = Locale.current.region?.identifier.uppercased() ?? "US"
        if let startedAt {
            payload["latency_ms"] = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0)
        }
        analytics.track(event, payload: payload)
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
    var transientBannerMessage: String? = nil
    var userLists: [UserList] = []
    var episodes: [Episode] = []
    // Detail caches: cards/grids only carry minimal fields; we fetch full details by id on demand.
    var animeDetailCache: [Int: Anime] = [:]
    var mangaDetailCache: [Int: Manga] = [:]

    // Entity inline caches (keyed by media ID, cap 100 each)
    var animeCharactersCache: [Int: [(character: Character, role: String)]] = [:]
    var animeStaffCache: [Int: [(staff: Staff, role: String)]] = [:]
    var animeStudiosCache: [Int: [Studio]] = [:]
    var mangaCharactersCache: [Int: [(character: Character, role: String)]] = [:]
    var mangaAuthorsCache: [Int: [(author: Author, role: String)]] = [:]

    // Entity sheet caches (keyed by entity ID, TTL 120s)
    var studioWorksCache: [String: TimedCache<[Media]>] = [:]
    var staffWorksCache: [String: TimedCache<[(media: Media, role: String)]>] = [:]
    var authorWorksCache: [String: TimedCache<[(media: Media, role: String)]>] = [:]
    var characterWorksCache: [String: TimedCache<[Media]>] = [:]
    var mediaLadderCache: [String: TimedCache<MediaLadderResponse>] = [:]
    var mediaLadderRefreshEnqueueCooldown: [String: Date] = [:]
    // De-dupe frequently called network fetches so multiple screens mounting doesn't fan-out.
    var userListsFetchInFlight: Task<Void, Never>? = nil
    var collectionFetchInFlight: Task<Void, Never>? = nil
    var collectionFetchGeneration: Int = 0
    var collectionFetchInFlightGeneration: Int = 0
    var collectionFeedFetchInFlight: Task<Void, Never>? = nil
    var collectionFeedFetchGeneration: Int = 0
    var collectionFeedFetchInFlightGeneration: Int = 0
    var upcomingFetchInFlight: Task<Void, Never>? = nil

    // Lightweight response caches (avoid refetching the same rails/recs when a view reappears).
    struct TimedCache<T>: Sendable {
        let value: T
        let storedAt: Date
    }

    private var discoverBundleCache: [String: TimedCache<DiscoverBundle>] = [:]
    private var discoverBundleInFlight: [String: Task<DiscoverBundle?, Never>] = [:]

    private var conciergeRecommendCache: [String: TimedCache<ConciergeRecommendResponse>] = [:]
    private var conciergeRecommendInFlight: [String: Task<ConciergeRecommendResponse, Error>] = [:]

    private var conciergeParseCache: [String: TimedCache<ConciergeParseResponse>] = [:]
    private var conciergeParseInFlight: [String: Task<ConciergeParseResponse, Error>] = [:]

    func trimCache<T>(_ cache: inout [String: TimedCache<T>], maxEntries: Int) {
        guard cache.count > maxEntries else { return }
        let sorted = cache.sorted { $0.value.storedAt < $1.value.storedAt }
        let removeCount = max(0, sorted.count - maxEntries)
        for (k, _) in sorted.prefix(removeCount) { cache.removeValue(forKey: k) }
    }

    /// Retry helper for transient network failures (URLError only).
    /// Non-network errors (e.g. HTTP 4xx, decoding) are thrown immediately.
    /// Static so it's callable from any isolation context (including Task.detached).
    private static func withRetry<T>(
        maxRetries: Int = 2,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch let error as URLError {
                lastError = error
                if attempt < maxRetries {
                    #if DEBUG
                    print("⟳ retry \(attempt + 1)/\(maxRetries) after URLError \(error.code.rawValue)")
                    #endif
                    try await Task.sleep(for: .milliseconds(Int(500 * pow(2.0, Double(attempt)))))
                }
            } catch {
                throw error // Non-network errors are not retried
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    struct BackoffState: Sendable {
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

    var upcomingBackoff = BackoffState()
    var lastUpcomingFetchAt: Date? = nil
    var lastUpcomingDays: Int = 7

    // Collection pagination state (keyset by list updated_at + list row id).
    var hasMoreCollectionAnime: Bool = true
    var hasMoreCollectionManga: Bool = true
    var isLoadingMoreCollectionAnime: Bool = false
    var isLoadingMoreCollectionManga: Bool = false
    var collectionAnimeCursorUpdatedAt: Date? = nil
    var collectionAnimeCursorRowId: Int? = nil
    var collectionMangaCursorUpdatedAt: Date? = nil
    var collectionMangaCursorRowId: Int? = nil

    // Collection feed pagination state (keyset by updated_at + source_rank + list row id).
    var hasMoreCollectionFeed: Bool = true
    var isLoadingMoreCollectionFeed: Bool = false
    var collectionFeedCursorUpdatedAt: Date? = nil
    var collectionFeedCursorSourceRank: Int? = nil
    var collectionFeedCursorRowId: Int? = nil

    var currentCollectionStatusFilter: ListStatus? = nil

    // User list derived caches
    var collectionAnimeIds: Set<Int> = []
    var collectionMangaIds: Set<Int> = []
    var userListByTypeAndId: [String: [Int: UserList]] = [:]
    var userIdsByTypeAndStatus: [String: [ListStatus: Set<Int>]] = [:]
    var togglingMediaKeys: Set<String> = []

    // Clubs and social state
    var clubBundleCache: [String: TimedCache<ClubBundle>] = [:]
    var clubBundleInFlight: [String: Task<ClubBundle, Error>] = [:]
    let rememberedClubIdKey = "com.kuro.rememberedAddToClubId"
    var myClubs: [ClubListRow] = []
    var hasUnseenClubActivity: Bool = false
    var friendTrackingCounts: [String: Int] = [:]
    var friendCountPrefetchTask: Task<Void, Never>?

    // Club realtime state
    var clubRealtimeChannel: RealtimeChannelV2?
    var clubRealtimeListenTasks: [Task<Void, Never>] = []
    var clubRealtimeDebounceTask: Task<Void, Never>?
    var clubRealtimeSubscribedId: String?
    var clubOnlineMemberCount: Int = 0
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
    var countdownTimer: Timer?
    var isLoading = false
    var errorMessage: String?
    private var transientBannerDismissTask: Task<Void, Never>? = nil

    func showTransientBanner(_ message: String, duration: Double = 2.4) {
        transientBannerDismissTask?.cancel()
        transientBannerMessage = message
        transientBannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if transientBannerMessage == message {
                transientBannerMessage = nil
            }
        }
    }

    // TODO: remove when streaming_availability_v1 reaches 100% — replaced by streaming_services registry
    let animeProviderRanking: [String] = [
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

    // Strict legal provider allowlist for watch links.
    let animeLegalProviderAllowlist: [String] = [
        "crunchyroll",
        "netflix",
        "hidive",
        "disney",
        "amazon",
        "prime video",
        "hulu",
        "youtube",
        "apple tv",
        "apple",
        "max"
    ]

    let mangaProviderRanking: [String] = [
        "manga plus",
        "mangaplus",
        "viz",
        "viz media",
        "bookwalker",
        "global bookwalker",
        "comixology",
        "kindle",
        "kobo",
        "j-novel club",
        "manga up",
        "kodansha",
        "yen press",
        "azuki"
    ]

    // Strict legal provider allowlist for read/buy links.
    let mangaLegalProviderAllowlist: [String] = [
        "manga plus",
        "mangaplus",
        "viz",
        "viz media",
        "bookwalker",
        "global bookwalker",
        "comixology",
        "kindle",
        "kobo",
        "kodansha",
        "yen press",
        "azuki",
        "j-novel club",
        "manga up",
        "google play books",
        "apple books"
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

    func sanitizeAnimeForDiscovery(_ items: [Anime]) -> [Anime] {
        sanitizeAnimeForDiscovery(items, policy: DiscoveryPolicy(includeAdult: false, excludeEcchi: true))
    }

    func sanitizeAnimeForDiscovery(_ items: [Anime], policy: DiscoveryPolicy) -> [Anime] {
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

    func sanitizeMangaForDiscovery(_ items: [Manga]) -> [Manga] {
        sanitizeMangaForDiscovery(items, policy: DiscoveryPolicy(includeAdult: false, excludeEcchi: true))
    }

    func sanitizeMangaForDiscovery(_ items: [Manga], policy: DiscoveryPolicy) -> [Manga] {
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
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else {
            client = nil
            configError = "Missing SUPABASE_URL or SUPABASE_ANON_KEY in configuration"
            isAuthBootstrapping = false
            return
        }

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key
        )
        analytics.configure(client: client)
        #if DEBUG
        print("🔥 Supabase client initialized: \(url.host ?? url.absoluteString)")
        #endif

        Task { await restoreSession() }
    }

    private func missingConfigError() -> NSError {
        NSError(
            domain: "KuroConfig",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: configError ?? "Missing Supabase configuration."]
        )
    }

    // MARK: - Authentication
    func restoreSession() async {
        defer { isAuthBootstrapping = false }
        guard let client else {
            isAuthenticated = false
            authErrorMessage = configError
            currentUserId = nil
            currentUserEmail = nil
            analytics.setUserId(nil)
            return
        }

        do {
            let session = try await client.auth.session
            isAuthenticated = true
            authErrorMessage = nil
            currentUserEmail = session.user.email
            currentUserId = session.user.id.uuidString
            analytics.setUserId(currentUserId)
            await ensureProfileRow()
            // Fire bootstrap without blocking — the UI can show immediately
            // with shimmer/skeleton placeholders while data loads in parallel.
            Task { await bootstrapAfterAuth() }
        } catch {
            isAuthenticated = false
            currentUserId = nil
            analytics.setUserId(nil)
        }

        // Listen for auth state changes (token refresh failure, server-side revocation, etc.)
        startAuthStateListener()
    }

    private func startAuthStateListener() {
        guard let client else { return }
        authStateTask?.cancel()
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                switch event {
                case .signedIn:
                    if !isAuthenticated, let session {
                        isAuthenticated = true
                        currentUserEmail = session.user.email
                        currentUserId = session.user.id.uuidString
                        analytics.setUserId(currentUserId)
                    }
                case .signedOut:
                    if isAuthenticated {
                        await stopRealtimeSubscriptions()
                        isAuthenticated = false
                        currentUserEmail = nil
                        currentUserId = nil
                        authErrorMessage = nil
                        stopCountdownUpdates()
                        resetUserState()
                        analytics.setUserId(nil)
                        FeatureFlags.shared.setUserId(nil)
                    }
                case .tokenRefreshed:
                    if let session {
                        currentUserEmail = session.user.email
                    }
                default:
                    break
                }
            }
        }
    }

    /// Lightweight session check on foreground — if the token expired while backgrounded,
    /// catch it early rather than waiting for the next API call to fail.
    func refreshSessionIfNeeded() async {
        guard let client else {
            authErrorMessage = configError
            return
        }
        do {
            _ = try await client.auth.session
        } catch {
            #if DEBUG
            print("⚠️ Session refresh failed on foreground: \(error.localizedDescription)")
            #endif
            // The authStateChanges listener will handle .signedOut if the session is truly gone.
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        authErrorMessage = nil
        guard let client else {
            authErrorMessage = configError
            throw missingConfigError()
        }
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            let session = try await client.auth.session
            isAuthenticated = true
            currentUserEmail = session.user.email
            currentUserId = session.user.id.uuidString
            analytics.setUserId(currentUserId)
            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            authErrorMessage = Self.userFacingAuthErrorMessage(from: error)
            isAuthenticated = false
            currentUserId = nil
            analytics.setUserId(nil)
            throw error
        }
    }

    /// Auth callback redirect URL — custom scheme so Supabase redirects straight into the app (no intermediate webpage).
    static let authCallbackURL = URL(string: "kuro://auth/callback")!

    func signUpWithEmail(email: String, password: String) async throws {
        authErrorMessage = nil
        guard let client else {
            authErrorMessage = configError
            throw missingConfigError()
        }
        do {
            _ = try await client.auth.signUp(email: email, password: password)
            // With email confirmation disabled, the session is immediately available.
            if let session = (try? await client.auth.session) {
                isAuthenticated = true
                currentUserEmail = session.user.email
                currentUserId = session.user.id.uuidString
                analytics.setUserId(currentUserId)
                await ensureProfileRow()
                await bootstrapAfterAuth()
            } else {
                isAuthenticated = false
                currentUserId = nil
                analytics.setUserId(nil)
            }
        } catch {
            authErrorMessage = Self.userFacingAuthErrorMessage(from: error)
            throw error
        }
    }

    /// Lightweight email existence check for inline sign-up validation.
    func checkEmailExists(email: String) async -> Bool {
        guard let client else {
            authErrorMessage = configError
            return false
        }
        do {
            let result: Bool = try await client
                .rpc("check_email_exists", params: ["p_email": email])
                .execute()
                .value
            return result
        } catch {
            #if DEBUG
            print("[Auth] checkEmailExists error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws {
        authErrorMessage = nil
        guard let client else {
            authErrorMessage = configError
            throw missingConfigError()
        }
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: rawNonce
                )
            )
            isAuthenticated = true
            currentUserEmail = session.user.email
            currentUserId = session.user.id.uuidString
            analytics.setUserId(currentUserId)

            // Apple only provides full name on first sign-in; persist it.
            if let fullName, !fullName.isEmpty {
                _ = try? await client.auth.update(
                    user: .init(data: ["full_name": .string(fullName)])
                )
            }

            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            authErrorMessage = Self.userFacingAuthErrorMessage(from: error)
            isAuthenticated = false
            currentUserId = nil
            analytics.setUserId(nil)
            throw error
        }
    }

    func resetPassword(email: String) async throws {
        guard let client else {
            authErrorMessage = configError
            throw missingConfigError()
        }
        try await client.auth.resetPasswordForEmail(email, redirectTo: Self.authCallbackURL)
    }

    /// Handle auth callback deep link — set session from tokens received via email verification redirect.
    func handleAuthCallback(accessToken: String, refreshToken: String) async {
        guard let client else {
            authErrorMessage = configError
            return
        }
        do {
            try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
            let session = try await client.auth.session
            isAuthenticated = true
            currentUserEmail = session.user.email
            currentUserId = session.user.id.uuidString
            analytics.setUserId(currentUserId)
            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            authErrorMessage = "Verification failed. Please request a new link."
            #if DEBUG
            print("handleAuthCallback failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// GDPR-compliant account deletion. Calls the `delete-account` Edge Function
    /// which cascades through all user data tables, removes storage objects,
    /// then deletes the auth.users row.
    var isAppleUser: Bool {
        get async {
            guard let client else { return false }
            guard let user = try? await client.auth.user() else { return false }
            return user.identities?.contains(where: { $0.provider == "apple" }) ?? false
        }
    }

    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        guard let client else {
            authErrorMessage = configError
            throw missingConfigError()
        }
        struct DeleteResponse: Decodable {
            let success: Bool?
            let error: String?
            let message: String?
        }
        var body: [String: String] = ["confirm": "true"]
        if let appleAuthorizationCode {
            body["apple_authorization_code"] = appleAuthorizationCode
        }
        let response: DeleteResponse = try await client.functions.invoke(
            "delete-account",
            options: .init(body: body)
        )
        if response.success != true {
            throw NSError(
                domain: "KuroAccountDeletion",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: response.error ?? response.message ?? "Account deletion failed"]
            )
        }
        // Clear local state (same as sign out).
        await stopRealtimeSubscriptions()
        isAuthenticated = false
        currentUserEmail = nil
        currentUserId = nil
        authErrorMessage = nil
        stopCountdownUpdates()
        resetUserState()
        analytics.setUserId(nil)
        FeatureFlags.shared.setUserId(nil)
    }

    func signOut() async {
        guard let client else {
            authErrorMessage = configError
            return
        }
        do {
            try await client.auth.signOut()
        } catch {
            #if DEBUG
            print("❌ signOut error: \(error)")
            #endif
            // Error logged in debug only
        }
        await stopRealtimeSubscriptions()
        isAuthenticated = false
        currentUserEmail = nil
        currentUserId = nil
        authErrorMessage = nil
        stopCountdownUpdates()
        resetUserState()
        analytics.setUserId(nil)
        FeatureFlags.shared.setUserId(nil)
    }

    private func resetUserState() {
        userLists = []
        collectionAnimeItems = []
        collectionMangaItems = []
        collectionFeedItems = []
        upcomingAirings = []
        countdownByAnimeId = [:]
        togglingMediaKeys.removeAll()
        // Entity caches
        animeCharactersCache.removeAll()
        animeStaffCache.removeAll()
        animeStudiosCache.removeAll()
        mangaCharactersCache.removeAll()
        mangaAuthorsCache.removeAll()
        studioWorksCache.removeAll()
        staffWorksCache.removeAll()
        authorWorksCache.removeAll()
        characterWorksCache.removeAll()
        mediaLadderCache.removeAll()
        mediaLadderRefreshEnqueueCooldown.removeAll()
    }

    /// Shed non-essential entity caches under memory pressure without
    /// touching user-facing state (lists, collection, auth).
    func trimCachesForMemoryPressure() {
        animeCharactersCache.removeAll()
        animeStaffCache.removeAll()
        animeStudiosCache.removeAll()
        mangaCharactersCache.removeAll()
        mangaAuthorsCache.removeAll()
        studioWorksCache.removeAll()
        staffWorksCache.removeAll()
        authorWorksCache.removeAll()
        characterWorksCache.removeAll()
        mediaLadderCache.removeAll()
        mediaLadderRefreshEnqueueCooldown.removeAll()
        discoverBundleCache.removeAll()
        conciergeRecommendCache.removeAll()
        conciergeParseCache.removeAll()
        animeDetailCache.removeAll()
        mangaDetailCache.removeAll()
        Task { await ImagePipeline.shared.clearMemoryCache() }
        #if DEBUG
        print("[MemoryPressure] Trimmed entity + image caches")
        #endif
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
            #if DEBUG
            print("⚠️ ensureProfileRow failed: \(error)")
            #endif
            // Error logged in debug only
        }
    }

    private func bootstrapAfterAuth() async {
        // Fetch all independent user data in parallel to cut startup latency.
        // Each fetch updates @Observable properties, so the UI fills progressively.
        async let lists: () = fetchUserLists()
        async let collection: () = fetchCollectionItems()
        async let feed: () = fetchCollectionFeed()
        async let upcoming: () = fetchUpcomingForUser(days: 7)
        _ = await (lists, collection, feed, upcoming)

        startCountdownUpdates()
        subscribeToUpdates()

        // Feature flags are non-critical; fire without blocking.
        if let client {
            Task { await FeatureFlags.shared.refresh(client: client, userId: currentUserId) }
        }

        // Streaming availability: load registry + user services (non-blocking)
        if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
            Task {
                await fetchStreamingServiceRegistry()
                await fetchUserStreamingServices()
            }
        }
    }

    func currentUserIdString() async -> String? {
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
            let response: [Anime] = try await Self.withRetry {
                try await self.client
                    .from("anime")
                    .select()
                    .order("popularity", ascending: false)
                    .range(from: offset, to: offset + self.pageSize - 1)
                    .execute()
                    .value
            }

            animeItems.append(contentsOf: response)
            hasMoreAnime = response.count == pageSize
            if hasMoreAnime { currentAnimePage += 1 }
            #if DEBUG
            print("✅ Fetched page \(currentAnimePage) (\(response.count) items), total: \(animeItems.count)")
            #endif
        } catch {
            errorMessage = "Failed to fetch anime: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Supabase error: \(error)")
            #endif
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
            let response: [Manga] = try await Self.withRetry {
                try await self.client
                    .from("manga")
                    .select()
                    .order("popularity", ascending: false)
                    .range(from: offset, to: offset + self.pageSize - 1)
                    .execute()
                    .value
            }

            mangaItems.append(contentsOf: response)
            hasMoreManga = response.count == pageSize
            if hasMoreManga { currentMangaPage += 1 }
            #if DEBUG
            print("✅ Fetched manga page \(currentMangaPage) (\(response.count) items), total: \(mangaItems.count)")
            #endif
        } catch {
            errorMessage = "Failed to fetch manga: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Error: \(error)")
            #endif
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
            #if DEBUG
            print("✅ Found \(animeResponse.count) anime, \(mangaResponse.count) manga")
            #endif
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Search error: \(error)")
            #endif
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
            #if DEBUG
            print("❌ Search page error: \(error)")
            #endif
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
            #if DEBUG
            print("❌ Combined search error: \(error)")
            #endif
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
            #if DEBUG
            print("❌ search refresh: \(error)")
            #endif
        }
    }

    func fetchSearchAnimePage(
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

    func fetchSearchMangaPage(
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
                let bundle: DiscoverBundle = try await Self.withRetry {
                    try await self.client
                        .rpc("discover_bundle", params: params)
                        .execute()
                        .value
                }
                KuroPerf.end(perf, message: "ok")
                self.discoverBundleCache[key] = TimedCache(value: bundle, storedAt: now)
                self.trimCache(&self.discoverBundleCache, maxEntries: 6)
                return bundle
            } catch {
                #if DEBUG
                print("❌ discover_bundle rpc: \(error)")
                #endif
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
        let diskFallback: Anime? = await KuroDiskDetailCache.read(kind: .anime, id: animeId, as: Anime.self)
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
            if let diskFallback {
                #if DEBUG
                print("⚠️ anime_by_id network error, using disk fallback: \(error)")
                #endif
                animeDetailCache[animeId] = diskFallback
                KuroPerf.end(perf, message: "disk_fallback")
                return diskFallback
            }
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    func fetchMangaById(_ mangaId: Int) async throws -> Manga? {
        if let cached = mangaDetailCache[mangaId] { return cached }
        let diskFallback: Manga? = await KuroDiskDetailCache.read(kind: .manga, id: mangaId, as: Manga.self)
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
            if let diskFallback {
                #if DEBUG
                print("⚠️ manga_by_id network error, using disk fallback: \(error)")
                #endif
                mangaDetailCache[mangaId] = diskFallback
                KuroPerf.end(perf, message: "disk_fallback")
                return diskFallback
            }
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
        } catch {
            #if DEBUG
            print("❌ trending fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ current season fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    func fetchSeasonAnime(season: String, year: Int, limit: Int = 20, onlyAiring: Bool = true, genre: String? = nil) async -> [Anime] {
        do {
            var q = client.from("anime").select().eq("season", value: season).eq("season_year", value: year)
            if onlyAiring { q = q.eq("status", value: "RELEASING") }
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("popularity", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ season fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    func fetchNewlyAddedAnime(limit: Int = 20, genre: String? = nil) async -> [Anime] {
        do {
            // Uses materialized view for fast, stable results (refreshed nightly by cron).
            var q = client.from("mv_anime_newly_added").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("created_at", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ newly added fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ top rated fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    // MARK: - Server-driven Discover sections (Manga)
    func fetchTrendingManga(limit: Int = 20, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_trending").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("trending", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ manga trending fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    func fetchNewlyAddedManga(limit: Int = 20, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_newly_added").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("created_at", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ manga newly added fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    func fetchTopRatedManga(limit: Int = 20, minScore: Int = 80, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_top_rated").select().gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("average_score", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ manga top rated fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ essentials anime fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ classics anime fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ new-to-you anime fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ essentials manga fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ classics manga fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ new-to-you manga fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ airing soon fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
            #if DEBUG
            print("❌ anime tag fetch: \(error)")
            #endif
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
            #if DEBUG
            print("❌ manga tag fetch: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Similar title recommendations

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
            #if DEBUG
            print("❌ anime tag facets fetch: \(error)")
            #endif
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
            #if DEBUG
            print("❌ manga tag facets fetch: \(error)")
            #endif
            return ([], [:])
        }
    }

        // MARK: - User Lists (normalized tables)
    // Extracted to SupabaseService+UserLists.swift

    // MARK: - Collection (server-driven)
    // Extracted to SupabaseService+Collection.swift

    // MARK: - User List mutation + sync helpers
    // Extracted to SupabaseService+UserLists.swift

// MARK: - Browse (server-driven paging + filters)
    // Extracted to SupabaseService+Browse.swift


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

    func decodeRetryAfterSeconds(from data: Data) -> Int? {
        // Edge functions return: { "error": "Rate limited", "retry_after_s": 30 }
        guard !data.isEmpty else { return nil }
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let n = obj["retry_after_s"] as? Int { return n }
            if let d = obj["retry_after_s"] as? Double { return Int(d.rounded()) }
            if let s = obj["retry_after_s"] as? String, let n = Int(s) { return n }
        }
        return nil
    }

    func translateConciergeFunctionError(_ error: Error) -> Error {
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
        let year: Int?
        let format: String?
        let cover_image_medium: String?
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
        let yearMention: Int?
        let rating: Double?
        let progressTotal: Int?
        let progressUnit: String?
    }

    struct ConciergeExistingEntry: Decodable, Sendable {
        let media_type: String
        let media_id: Int
        let status: String
        let progress_episodes: Int?
        let progress_chapters: Int?
        let progress_volumes: Int?
        let rating: Int?
        let updated_at: String
    }

    struct ConciergeAmbiguity: Decodable, Sendable {
        let kind: String             // "status_unclear", "unit_unclear", "intent_unclear"
        let options: [String]?       // e.g. ["COMPLETED", "CURRENT"] or ["episode", "season", "chapter", "volume"]
        let suggested_question: String?
        let title_context: String?   // title the ambiguity relates to
        let number_context: String?  // the ambiguous number (for unit_unclear)
    }

    struct ConciergeParseItem: Decodable, Sendable, Identifiable {
        let raw: String
        let normalized: String
        let parsed: ConciergeParseItemParsed
        let candidates: [ConciergeCandidate]
        let candidateError: String?
        let existing_entry: ConciergeExistingEntry?
        let ambiguity: ConciergeAmbiguity?

        var id: String { raw + "|" + normalized }
    }

    struct ConciergeParseResponse: Decodable, Sendable {
        let success: Bool
        let userId: String?
        let items: [ConciergeParseItem]
    }

    /// Fire-and-forget edge function warmup — warms the Deno isolate without auth/rate-limit.
    func conciergeWarmup() async {
        do {
            let client = self.client
            _ = try await Task.detached(priority: .background) {
                let data = try JSONSerialization.data(withJSONObject: ["text": ""], options: [])
                let options = FunctionInvokeOptions(
                    method: .post,
                    query: [URLQueryItem(name: "warmup", value: "true")],
                    body: data
                )
                let _: [String: Bool] = try await client!.functions.invoke("concierge-parse", options: options)
            }.value
        } catch {
            // Best-effort warmup — silently ignore failures
        }
    }

    func conciergeParse(text: String, scope: ConciergeScope = .both, limitPerItem: Int = 10, clarification: [String: String]? = nil) async throws -> ConciergeParseResponse {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lim = max(3, min(15, limitPerItem))
        let user = await currentUserIdString() ?? "anon"
        let clarifyKey = clarification.map { $0.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "&") } ?? ""
        let key = "concierge_parse|\(user)|\(scope.rawValue)|\(lim)|\(normalized)|\(clarifyKey)"

        let now = Date()
        // Very short TTL: just enough to make back-to-back retries feel instant.
        if let cached = conciergeParseCache[key], now.timeIntervalSince(cached.storedAt) < 600 {
            return cached.value
        }
        if let task = conciergeParseInFlight[key] {
            return try await task.value
        }

        // Keep the request in a Task so callers can share in-flight work.
        // This runs on the main actor; the network call is async and should not block the UI thread.
        let client = self.client
        let clarify = clarification
        let task = Task<ConciergeParseResponse, Error>(priority: .userInitiated) {
            var payload: [String: Any] = [
                "text": text,
                "scope": scope.rawValue,
                "limitPerItem": lim,
            ]
            if let clarify {
                payload["clarification"] = clarify
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let options = FunctionInvokeOptions(method: .post, body: data)
            return try await SupabaseService.withRetry { [client] in
                try await client!.functions.invoke("concierge-parse", options: options)
            }
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
            let action: String?
        }
        struct Skipped: Decodable, Sendable {
            let mediaType: String
            let mediaId: Int
        }
        struct Conflict: Decodable, Sendable {
            let mediaType: String?
            let mediaId: Int?
            let error: String
        }
        struct ApplyError: Decodable, Sendable {
            let mediaType: String?
            let mediaId: Int?
            let error: String
        }
        let applied: [Applied]?
        let skipped: [Skipped]?
        let conflicts: [Conflict]?
        let errors: [ApplyError]?
    }

    func conciergeApply(items: [[String: Any]]) async throws -> ConciergeApplyResponse {
        do {
            let payload: [String: Any] = [
                "items": items,
            ]
            let client = self.client
            let task = Task<ConciergeApplyResponse, Error>(priority: .userInitiated) {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                let options = FunctionInvokeOptions(method: .post, body: data)
                return try await client!.functions.invoke("concierge-apply", options: options)
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
            let task = Task<ConciergeUndoResponse, Error>(priority: .userInitiated) {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                let options = FunctionInvokeOptions(method: .post, body: data)
                return try await client!.functions.invoke("concierge-undo", options: options)
            }
            return try await task.value
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }

    // MARK: - Concierge: AniList import
    // Extracted to SupabaseService+Concierge.swift


	    struct ConciergeRecommendResponse: Decodable, Sendable {
	        let success: Bool
	        let locale: String?
	        let curatorNote: String?
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
	            let internalTitle: String?
	            let displayTitle: String?
	            let displaySubtitle: String?
	            let curatorNote: String?
	            let locale: String?
	            let modeId: String?
	            let confidence: Double?
	            let reason: String?
	            let items: [Item]?
	        }
        struct Assist: Decodable, Sendable {
            let ragUsed: Bool?
            let seedEntityId: String?

            enum CodingKeys: String, CodingKey {
                case ragUsed
                case seedEntityId
            }
        }
        let modes: [Mode]?
        let sets: [Set]?
        let items: [Item]?
        let assist: Assist?
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

        // Keep the request in a Task so callers can share in-flight work.
        // This runs on the main actor; the network call is async and should not block the UI thread.
        let client = self.client
        let task = Task<ConciergeRecommendResponse, Error>(priority: .userInitiated) {
            let payload: [String: Any] = [
                "text": text,
                "scope": scope.rawValue,
                "limit": lim,
                "narrate": narrate,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let options = FunctionInvokeOptions(method: .post, body: data)
            let resp: ConciergeRecommendResponse = try await SupabaseService.withRetry { [client] in
                try await client!.functions.invoke("concierge-recommend", options: options)
            }
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

    /// Best-effort feedback for server-side RAG retrieval.
    /// Never throws to callers by design; failures are debug-logged only.
    func conciergeRetrieveFeedback(
        query: String,
        locale: String,
        selectedEntityId: String?,
        accepted: Bool,
        rejectedReason: String? = nil
    ) async {
        do {
            var payload: [String: Any] = [
                "query": query,
                "locale": locale,
                "accepted": accepted,
            ]
            if let selectedEntityId, !selectedEntityId.isEmpty {
                payload["selected_entity_id"] = selectedEntityId
            }
            if let rejectedReason, !rejectedReason.isEmpty {
                payload["rejected_reason"] = rejectedReason
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let options = FunctionInvokeOptions(method: .post, body: data)
            let _: [String: Bool] = try await client.functions.invoke(
                "concierge-retrieve-feedback",
                options: options
            )
        } catch {
            #if DEBUG
            print("[SupabaseService] conciergeRetrieveFeedback failed: \(error.localizedDescription)")
            #endif
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

        do {
            _ = try await channel.subscribeWithError()
        } catch {
            #if DEBUG
            print("⚠️ realtime subscribe failed: \(error)")
            #endif
        }
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
    // Extracted to SupabaseService+UserLists.swift

// MARK: - Concierge: Library export helper

    struct ConciergeLibraryExportResult: Sendable {
        let text: String
        let exportedItemCount: Int
        let truncated: Bool
    }

    /// Build plain-text concierge payload from the user's current library list.
    /// Useful for one-tap import from within the app.
    func conciergeLibraryExportText(
        includeStatus: Set<ListStatus>? = nil,
        includeMediaTypes: Set<String> = ["anime", "manga"],
        maxItems: Int = 400
    ) async -> ConciergeLibraryExportResult? {
        if userLists.isEmpty {
            await fetchUserLists()
        }

        guard !userLists.isEmpty else { return nil }

        let allowedStatuses = includeStatus.map(Set.init) ?? Set(ListStatus.allCases)
        let allowedTypes = Set(includeMediaTypes.map { $0.lowercased() })

        let filtered = userLists.filter {
            allowedTypes.contains($0.mediaType.lowercased()) && allowedStatuses.contains($0.status)
        }

        guard !filtered.isEmpty else { return nil }

        let capped = Array(filtered.prefix(max(0, maxItems)))
        guard !capped.isEmpty else { return nil }

        // 1) Resolve titles for this snapshot.
        let lookup = await resolveLibraryTitles(for: capped)

        // 2) Keep list in server order (updatedAt desc from fetchUserLists).
        let lines: [String] = capped.compactMap { entry in
            guard let title = lookup[entry.mediaId] else { return nil }
            let suffix = conciergeLibrarySuffix(for: entry)
            return suffix.isEmpty ? title : "\(title) \(suffix)"
        }

        guard !lines.isEmpty else { return nil }
        return ConciergeLibraryExportResult(
            text: lines.joined(separator: "\n"),
            exportedItemCount: lines.count,
            truncated: filtered.count > capped.count
        )
    }

    private func conciergeLibrarySuffix(for entry: UserList) -> String {
        let isAnime = entry.mediaType.lowercased() == "anime"
        let progress = max(0, entry.progress)
        switch entry.status {
        case .completed:
            return "(completed)"
        case .dropped:
            return "(dropped)"
        case .paused:
            return "(paused)"
        case .planning:
            return "(planning)"
        case .repeating:
            return isAnime ? "(rewatching)" : "(re-reading)"
        case .current:
            if progress > 0 {
                return isAnime ? "(watching ep \(progress))" : "(reading ch \(progress))"
            }
            return isAnime ? "(watching)" : "(reading)"
        }
    }

    private func resolveLibraryTitles(for items: [UserList]) async -> [Int: String] {
        let animeIds = Set(items.filter { $0.mediaType.lowercased() == "anime" }.map(\.mediaId))
        let mangaIds = Set(items.filter { $0.mediaType.lowercased() == "manga" }.map(\.mediaId))

        var titlesById: [Int: String] = [:]

        for (table, ids) in [("anime", animeIds), ("manga", mangaIds)] as [(String, Set<Int>)] {
            let idList = Array(ids).sorted()
            guard !idList.isEmpty else { continue }

            struct MediaTitleRow: Decodable {
                let id: Int
                let titleEnglish: String?
                let titleRomaji: String?
                let titleNative: String?

                enum CodingKeys: String, CodingKey {
                    case id
                    case titleEnglish = "title_english"
                    case titleRomaji = "title_romaji"
                    case titleNative = "title_native"
                }
            }

            for start in stride(from: 0, through: max(0, idList.count), by: 200) {
                let end = min(start + 200, idList.count)
                guard start < end else { continue }
                let chunk = Array(idList[start..<end])

                do {
                    let rows: [MediaTitleRow] = try await client
                        .from(table)
                        .select("id,title_english,title_romaji,title_native")
                        .in("id", values: chunk)
                        .execute()
                        .value

                    for row in rows {
                        let title = row.titleEnglish?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? row.titleRomaji?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? row.titleNative?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? ""
                        if !title.isEmpty {
                            titlesById[row.id] = title
                        }
                    }
                } catch {
                    #if DEBUG
                    print("[SupabaseService] Failed to resolve titles for \(table): \(error)")
                    #endif
                }

            }
        }

        // Use local detail cache as a fallback if table lookups failed.
        var localAnimeLookup: [Int: String] = [:]
        for item in animeItems {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && title.lowercased() != "unknown" {
                localAnimeLookup[item.id] = title
            }
        }

        var localMangaLookup: [Int: String] = [:]
        for item in mangaItems {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && title.lowercased() != "unknown" {
                localMangaLookup[item.id] = title
            }
        }

        for item in items {
            if titlesById[item.mediaId] == nil {
                let fallback = item.mediaType.lowercased() == "anime"
                    ? localAnimeLookup[item.mediaId]
                    : localMangaLookup[item.mediaId]
                if let fallback, !fallback.isEmpty {
                    titlesById[item.mediaId] = fallback
                }
            }
        }

        return titlesById
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

    func userListEntry(mediaType: String, mediaId: Int) -> UserList? {
        userListByTypeAndId[mediaType.lowercased()]?[mediaId]
    }

    func incrementProgress(mediaId: Int, mediaType: String) async {
        guard let entry = userListByTypeAndId[mediaType.lowercased()]?[mediaId] else { return }
        let newProgress = entry.progress + 1
        await upsertUserListEntry(
            mediaId: mediaId,
            mediaType: mediaType,
            status: entry.status,
            progress: newProgress,
            rating: entry.score,
            notes: entry.notes,
            verdict: entry.verdict
        )
    }

    func isFavorited(_ animeId: Int) -> Bool {
        // Check if anime has high score (favorited)
        return userListByTypeAndId["anime"]?[animeId]?.score ?? 0 >= 90
    }

    func toggleInCollection(mediaId: Int, mediaType: String) {
        let type = mediaType.lowercased()
        let key = "\(type)-\(mediaId)"
        guard !togglingMediaKeys.contains(key) else { return }
        togglingMediaKeys.insert(key)

        let wasInCollection = isInCollection(mediaId: mediaId, mediaType: type)

        // Optimistic: flip local set immediately so UI reflects the change
        if type == "anime" {
            if wasInCollection { collectionAnimeIds.remove(mediaId) } else { collectionAnimeIds.insert(mediaId) }
        } else {
            if wasInCollection { collectionMangaIds.remove(mediaId) } else { collectionMangaIds.insert(mediaId) }
        }

        Task {
            if wasInCollection {
                let success = await removeFromList(mediaId: mediaId, mediaType: type)
                if !success {
                    // Rollback: re-insert the ID
                    if type == "anime" { collectionAnimeIds.insert(mediaId) } else { collectionMangaIds.insert(mediaId) }
                    showTransientBanner("Couldn't update list. Try again.")
                } else {
                    showTransientBanner("Removed from collection")
                }
            } else {
                let success = await addToList(mediaId: mediaId, mediaType: type, status: .planning)
                if !success {
                    // Rollback: remove the optimistically inserted ID
                    if type == "anime" { collectionAnimeIds.remove(mediaId) } else { collectionMangaIds.remove(mediaId) }
                    showTransientBanner("Couldn't update list. Try again.")
                } else {
                    showTransientBanner("Added to collection")
                }
            }
            togglingMediaKeys.remove(key)
        }
    }

    func toggleInCollection(_ animeId: Int) {
        toggleInCollection(mediaId: animeId, mediaType: "anime")
    }

    func toggleFavorite(for animeId: Int) {
        let key = "fav-\(animeId)"
        guard !togglingMediaKeys.contains(key) else { return }
        togglingMediaKeys.insert(key)
        Task {
            defer { togglingMediaKeys.remove(key) }
            guard let entry = userLists.first(where: { $0.mediaId == animeId && $0.mediaType.lowercased() == "anime" }) else { return }
            let shouldUnfavorite = (entry.score ?? 0) >= 90
            let newRating: Int? = shouldUnfavorite ? nil : 100
            await updateListRating(mediaId: animeId, mediaType: "anime", rating: newRating)
        }
    }

    private func updateListRating(mediaId: Int, mediaType: String, rating: Int?) async {
        guard let userId = await currentUserIdString() else { return }
        errorMessage = nil
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

            errorMessage = nil
            await fetchUserLists()
        } catch {
            errorMessage = "Couldn't update rating: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Failed to update rating: \(error)")
            #endif
        }
    }

        // MARK: - Clubs
    // Extracted to SupabaseService+Clubs.swift

    // MARK: - Social Activity (Friend Comments & Indicators)
    // Extracted to SupabaseService+Social.swift

// MARK: - Streaming Availability state

    // Stored on the main service; behavior lives in SupabaseService+Streaming.swift.
    var providerCache: [String: [ProviderInfo]] = [:]
    var providerPrefetchTask: Task<Void, Never>?
    var providerAvailabilityCache: [String: [ProviderAvailabilityProvider]] = [:]
    var providerAvailabilityPrefetchTask: Task<Void, Never>?
    var availabilityRefreshEnqueueCooldown: [String: Date] = [:]
    var userStreamingServices: [String] = []
    var clubSharedProvidersCache: [String: ClubSharedProvidersResponse] = [:]
    var streamingServiceRegistry: [StreamingServiceRecord] = []

        // MARK: - Club Realtime
    // Extracted to SupabaseService+ClubRealtime.swift


}

#else
// Fallback mock service when the Supabase SDK isn't available.
// Kept minimal: no model-type references (Anime, Manga, UserList,
// Episode, ListStatus) so this block compiles standalone.
@MainActor
@Observable
class SupabaseService {
    static let shared = SupabaseService()

    let fmService = AppleFMService()

    // Observable state used by views
    var isLoading = false
    var errorMessage: String?
    var configError: String? = nil
    var isAuthBootstrapping: Bool = false
    var isAuthenticated: Bool = false
    var authErrorMessage: String? = nil
    var currentUserEmail: String? = nil
    var currentUserId: String? = nil

    init() {
        #if DEBUG
        print("[Mock] Supabase SDK not found. Running with mock SupabaseService.")
        #endif
    }

    // Auth
    func signInAnonymously() async throws {}
    func handleAuthCallback(accessToken: String, refreshToken: String) async {}
    func refreshSessionIfNeeded() async {}

    // Memory pressure
    func trimCachesForMemoryPressure() {}

    // Data loading no-ops
    func fetchAnime(limit: Int = 50) async {
        isLoading = true
        isLoading = false
    }

    func fetchManga(limit: Int = 50) async {
        isLoading = true
        isLoading = false
    }

    func searchContent(query: String) async {
        isLoading = true
        isLoading = false
    }

    func fetchUserLists() async {}

    func filterByGenre(_ genre: String) async {
        isLoading = true
        isLoading = false
    }

    func subscribeToUpdates() {}

    func isInCollection(_ animeId: Int) -> Bool { false }
    func isInCollection(mediaId: Int, mediaType: String) -> Bool { false }
    func isFavorited(_ animeId: Int) -> Bool { false }
    func toggleInCollection(_ animeId: Int) {}
    func toggleInCollection(mediaId: Int, mediaType: String) {}
    func toggleFavorite(for animeId: Int) {}
}
#endif

```

### Concierge UI (authoritative)

- Path: `Kuro/Views/ConciergeView.swift`


```swift
// MARK: - CONCIERGE VIEW (INLINE CHAT ARCHITECTURE)
// No full-screen state machine. Everything renders inline in the chat scroll.
// High-confidence imports auto-apply with undo toast. Recommendations appear as editorial rails.

import SwiftUI

// MARK: - Import Reconciliation Types

enum ImportItemAction: String, Sendable {
    case add
    case update
    case skip
}

struct ImportDiff: Sendable {
    struct FieldDiff<T: Sendable>: Sendable {
        let from: T
        let to: T
    }
    var status: FieldDiff<String>?
    var progressEpisodes: FieldDiff<Int>?
    var progressChapters: FieldDiff<Int>?
    var progressVolumes: FieldDiff<Int>?
    var rating: FieldDiff<Int?>?

    var isEmpty: Bool {
        status == nil && progressEpisodes == nil && progressChapters == nil && progressVolumes == nil && rating == nil
    }
}

// MARK: - Main View
struct ConciergeView: View {
    @Environment(SupabaseService.self) private var supabaseService

    let assistantEnabled: Bool
    var initialPrompt: String? = nil

    // MARK: Input & Core State
    @State private var input: String = ""
    @State private var didConsumeInitialPrompt = false
    @State private var focusRequest: Bool = false
    @State private var messages: [ConciergeMessage] = []
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var selectedByItemId: [String: SupabaseService.ConciergeCandidate] = [:]
    @State private var itemActions: [String: ImportItemAction] = [:]
    @State private var excludedItemIds: Set<String> = []
    @State private var autoReasonByItemId: [String: String] = [:]
    @State private var lastApplySessionId: String? = nil
    @State private var lastApplySessionResetTask: Task<Void, Never>? = nil
    @State private var selectedAnime: Anime? = nil
    @State private var selectedManga: Manga? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var assistantExpanded: Bool = false
    @State private var assistantOffset: CGSize = .zero
    @State private var assistantDragStart: CGSize = .zero
    @State private var containerSize: CGSize = CGSize(width: 393, height: 852)
    @State private var appliedImportMessageIds: Set<UUID> = []
    @State private var lastAppliedImportMessageId: UUID? = nil
    @State private var applyingImportMessageId: UUID? = nil
    @State private var appliedImportSummary: String? = nil
    @State private var lastRecommendQuery: String? = nil
    @State private var lastRecommendWasRagAssist: Bool = false
    @State private var warmupTask: Task<Void, Never>? = nil
    @State private var prefetchTask: Task<Void, Never>? = nil
    @State private var prefetchTask2: Task<Void, Never>? = nil
    @State private var backgroundRefreshTask: Task<Void, Never>? = nil
    @State private var backgroundRefreshTask2: Task<Void, Never>? = nil
    @State private var undoRefreshTask: Task<Void, Never>? = nil
    @State private var disambiguationTask: Task<Void, Never>? = nil
    @State private var lastRagSeedEntityId: String? = nil
    @State private var ragFeedbackSentForQuery: Set<String> = []
    @State private var showAniListImportSheet: Bool = false
    private var mascotState: ConciergeMascotState {
        if isWorking { return .thinking }
        if errorText != nil { return .concerned }
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .idle }
        return .listening
    }

    private var clarifyV2Enabled: Bool {
        FeatureFlags.shared.isClarifyV2Enabled
    }

    private var fmAssistEnabled: Bool {
        FeatureFlags.shared.isFmAssistEnabled && supabaseService.fmService.isAvailable
    }

    private var conciergePerfV2Enabled: Bool {
        FeatureFlags.shared.isConciergePerfV2Enabled
    }

    private var isGermanLocale: Bool {
        let language = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        return language.hasPrefix("de")
    }

    private var editorialSubtitle: String {
        "Import from Kuro instantly — or tell me what you're in the mood for."
    }

    private var editorialFooterText: String {
        if isWorking {
            return isGermanLocale ? "Einen Moment." : "One moment."
        }
        return isGermanLocale ? "Importiere direkt aus deiner Bibliothek — oder lass mich zwei Rails kuratieren." : "Import from your list — or let me curate two rails."
    }

    init(assistantEnabled: Bool = true, initialPrompt: String? = nil) {
        self.assistantEnabled = assistantEnabled
        self.initialPrompt = initialPrompt
    }

    // MARK: Body
    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()

            editorialChatView

            // Toast overlay
            if let toast {
                VStack {
                    Spacer()
                    KuroToast(toast: toast)
                        .padding(.horizontal, KuroDesignSpacing.md)
                        .padding(.bottom, 92)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .sheet(item: $selectedAnime) { anime in
            AnimeDetailView(anime: anime)
        }
        .sheet(item: $selectedManga) { manga in
            MangaDetailView(manga: manga)
        }
        .sheet(isPresented: $showAniListImportSheet) {
            ConciergeAniListImportSheet(
                supabaseService: supabaseService,
                isGermanLocale: isGermanLocale
            ) { response in
                let count = response.itemCount ?? 0
                await sendExternalImport(
                    sourceLabel: "AniList",
                    displayText: isGermanLocale
                        ? "AniList-Import — \(count) Titel"
                        : "AniList import — \(count) items",
                    sourceText: response.text ?? "",
                    truncated: response.truncated ?? false
                )
            }
        }
        .task {
            // Warm up the edge function isolate on view appear (fire-and-forget)
            warmupTask = Task.detached(priority: .background) {
                await supabaseService.conciergeWarmup()
            }

            // Pre-fill input from deep link prompt (consumed once)
            if !didConsumeInitialPrompt, let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
                didConsumeInitialPrompt = true
                input = prompt
                focusRequest = true
            }
        }
        .onDisappear {
            lastApplySessionResetTask?.cancel()
            warmupTask?.cancel()
            prefetchTask?.cancel()
            prefetchTask2?.cancel()
            backgroundRefreshTask?.cancel()
            backgroundRefreshTask2?.cancel()
            undoRefreshTask?.cancel()
            toastDismissTask?.cancel()
            disambiguationTask?.cancel()
        }
        .preferredColorScheme(.light)
    }

    private var editorialChatView: some View {
        ConciergeEditorialShell(
            title: "Concierge",
            subtitle: editorialSubtitle,
            errorText: errorText,
            showsIntentDeck: false
        ) {
            EmptyView()
        } responseStage: {
            ConciergeResponseStage {
                messageTimeline(
                    horizontalPadding: 24,
                    topPadding: 20,
                    bottomPadding: 20,
                    messageSpacing: 20,
                    includeStarter: true
                )
            }
        } composer: {
            ConciergeInputField(
                text: $input,
                isSending: isWorking,
                focusRequest: $focusRequest,
                onSend: { text in
                    Task { await send(text: text) }
                }
                ,onAutoSend: { text in
                    // Auto-send only when the input field detects a real paste import list.
                    Task { await send(text: text) }
                }
            )
            .kuroSwipeExclusionZone()
        } footer: {
            EmptyView()
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { containerSize = geo.size }
            }
        }
    }

    private func sendExternalImport(sourceLabel: String, displayText: String, sourceText: String, truncated: Bool) async {
        let t = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard !isWorking else { return }

        errorText = nil
        let sendStartedAt = supabaseService.beginInteractionTiming()

        // Compact user bubble (avoid dumping 200 lines into chat).
        let userMsg = ConciergeMessage(role: .user, text: displayText, sourceUserText: t, items: nil)
        withAnimation(KuroAnimation.editorial) {
            messages.append(userMsg)
        }

        isWorking = true
        defer { isWorking = false }

        await handleImportFlow(text: t, interactionStartedAt: sendStartedAt)

        if truncated {
            showToast(.init(
                kind: .info,
                title: isGermanLocale ? "Teilimport" : "Partial import",
                subtitle: isGermanLocale ? "Ich habe zuerst 200 Titel importiert. Du kannst später mehr importieren." : "Imported the first 200 items. You can import more later.",
                actionTitle: nil,
                onAction: nil
            ), autoDismissSeconds: 4.0)
        }
    }

    // MARK: Chat View (Always Visible)
    private var chatView: some View {
        VStack(spacing: 0) {
            messageTimeline(
                horizontalPadding: KuroDesignSpacing.padding,
                topPadding: KuroDesignSpacing.md,
                bottomPadding: KuroDesignSpacing.md,
                includeStarter: true
            )

            if let errorText {
                Text(errorText)
                    .font(.kuroCaption())
                    .foregroundColor(.kuroError)
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.vertical, 10)
            }

            Rectangle()
                .fill(Color.kuroBlack06)
                .frame(height: 0.5)

            ConciergeInputField(
                text: $input,
                isSending: isWorking,
                focusRequest: $focusRequest,
                onSend: { text in
                    Task { await send(text: text) }
                }
            )
            .kuroSwipeExclusionZone()
            .padding(.horizontal, KuroDesignSpacing.md)
            .padding(.bottom, 14)
            .padding(.top, KuroDesignSpacing.sm)
        }
        .overlay(alignment: .bottomLeading) {
            if assistantEnabled {
                KuroConciergeMascot(
                    expanded: $assistantExpanded,
                    offset: $assistantOffset,
                    dragStart: $assistantDragStart,
                    baseBottomPadding: 104,
                    containerSize: containerSize,
                    state: mascotState
                ) {
                    focusRequest = true
                }
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { containerSize = geo.size }
            }
        }
    }

    private func messageTimeline(
        horizontalPadding: CGFloat,
        topPadding: CGFloat,
        bottomPadding: CGFloat,
        messageSpacing: CGFloat = KuroDesignSpacing.md,
        includeStarter: Bool
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: messageSpacing) {
                    if includeStarter && messages.isEmpty {
                        ConciergeIntroCard()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                            .padding(.bottom, KuroDesignSpacing.sm)

                        ConciergeStarterActions(
                            onPaste: { pasteFromClipboard() },
                            onImportLibrary: {
                                Task { await importFromLibrary() }
                            },
                            onExampleImport: { seedExampleImport() },
                            onExampleVibe: { seedExampleVibe() }
                        )
                        .frame(maxWidth: .infinity)
                    }

                    if !messages.isEmpty {
                        HStack {
                            Spacer()
                            Button {
                                startNewChat()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.message")
                                        .font(.kuroCustom(10, weight: .medium, relativeTo: .caption1))
                                    Text("NEW CHAT")
                                        .font(.kuroMicro(weight: .semibold))
                                        .tracking(1.2)
                                }
                                .foregroundColor(.kuroTextTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.kuroBlack06)
                                )
                            }
                        }
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
                            },
                            onClarifyPaste: { pasteFromClipboard() },
                            onClarifyImportLibrary: {
                                Task { await importFromLibrary() }
                            },
                            onClarifyExampleImport: { seedExampleImport() },
                            onClarifyExampleVibe: { seedExampleVibe() },
                            onClarifyAmbiguity: clarifyV2Enabled ? { kind, value, sourceText in
                                Task { await handleClarification(kind: kind, value: value, sourceText: sourceText) }
                            } : nil,
                            onConfirmItems: { response in
                                Task { await confirmImport(response: response, sourceMessageId: msg.id) }
                            },
                            onReparse: {
                                reparse(message: msg)
                            },
                            onUndoImport: lastApplySessionId != nil ? {
                                guard let sid = lastApplySessionId else { return }
                                Task { await undoApply(sessionId: sid) }
                            } : nil,
                            onViewCollection: appliedImportMessageIds.contains(msg.id) ? {
                                navigateToCollection()
                            } : nil,
                            isImportApplied: appliedImportMessageIds.contains(msg.id),
                            isImportApplying: applyingImportMessageId == msg.id,
                            importAppliedSummary: appliedImportMessageIds.contains(msg.id) ? appliedImportSummary : nil,
                            autoReasonByItemId: autoReasonByItemId,
                            itemActions: itemActions,
                            excludedItemIds: $excludedItemIds
                        )
                        .id(msg.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if isWorking && !messages.isEmpty {
                        ConciergeTypingIndicator()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation(KuroAnimation.fast) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: Send (Main Entry Point)
    private func send(text: String) async {
        guard !text.isEmpty else { return }
        guard !isWorking else { return }
        errorText = nil
        let sendStartedAt = supabaseService.beginInteractionTiming()

        #if DEBUG
        let sendStart = CFAbsoluteTimeGetCurrent()
        #endif

        // Add user message immediately (optimistic)
        let userMsg = ConciergeMessage(role: .user, text: text, items: nil)
        withAnimation(KuroAnimation.editorial) {
            messages.append(userMsg)
        }

        // Mark first use (collapses intro hint on next visit)
        if !UserDefaults.standard.bool(forKey: "kuro_concierge_used") {
            UserDefaults.standard.set(true, forKey: "kuro_concierge_used")
        }

        #if DEBUG
        let optimisticEnd = CFAbsoluteTimeGetCurrent()
        print("[Concierge Timing] send() called -> optimistic append: \(String(format: "%.1f", (optimisticEnd - sendStart) * 1000))ms")
        #endif

        // Low-signal prompts ("ADD", random letters, etc.) should not guess.
        // Ask a clarifying question with examples instead of hitting the network.
        if shouldAskClarifyingQuestion(text) {
            let assistantMsg = ConciergeMessage(
                role: .assistant,
                text: "What would you like to do?",
                showClarifyActions: true,
                items: nil
            )
            withAnimation(KuroAnimation.editorial) {
                messages.append(assistantMsg)
            }
            supabaseService.analytics.track("clarify_shown", payload: [
                "reason": "low_signal",
                "input_length": Double(text.count),
                "surface": "concierge_chat",
                "result": "clarify",
            ])
            supabaseService.trackInteractionEvent(
                "concierge_first_response_ms",
                surface: "concierge_chat",
                result: "clarify",
                startedAt: sendStartedAt
            )
            return
        }

        isWorking = true

        if fmAssistEnabled {
            // FM-primary: use on-device model for intent classification
            let locale = isGermanLocale ? "de" : "en"
            let fmResult = await supabaseService.fmService.assistIntent(text: text, locale: locale)

            if let result = fmResult, result.confidence >= 0.65 {
                let intent = result.selectedIntent

                supabaseService.analytics.track("intent_detected", payload: [
                    "intent": intent,
                    "source": "fm",
                    "confidence": result.confidence,
                    "input_length": Double(text.count),
                ])

                #if DEBUG
                print("[Concierge] FM intent: \(intent) (confidence: \(String(format: "%.2f", result.confidence)), reasoning: \(result.reasoning))")
                #endif

                switch intent {
                case "import":
                    await handleImportFlow(text: text, interactionStartedAt: sendStartedAt)
                case "unknown":
                    let clarifyMsg = ConciergeMessage(
                        role: .assistant,
                        text: "What would you like to do?",
                        showClarifyActions: true,
                        items: nil
                    )
                    withAnimation(KuroAnimation.editorial) {
                        messages.append(clarifyMsg)
                    }
                default:
                    // recommend_vibe, recommend_seed, library_query, club_action
                    await handleRecommendationFlow(text: text, interactionStartedAt: sendStartedAt)
                }
            } else {
                // FM failed, timed out, or low confidence — fall back to keywords
                #if DEBUG
                if let result = fmResult {
                    print("[Concierge] FM low confidence (\(String(format: "%.2f", result.confidence))), falling back to keywords")
                } else {
                    print("[Concierge] FM unavailable, falling back to keywords")
                }
                #endif
                await routeByKeywords(text: text, sendStartedAt: sendStartedAt)
            }
        } else {
            // FM not available — keyword routing (current behavior)
            await routeByKeywords(text: text, sendStartedAt: sendStartedAt)
        }

        isWorking = false
    }

    private func routeByKeywords(text: String, sendStartedAt: CFAbsoluteTime) async {
        if looksLikeImport(text) {
            supabaseService.analytics.track("intent_detected", payload: [
                "intent": "import",
                "source": "keywords",
                "input_length": Double(text.count),
            ])
            await handleImportFlow(text: text, interactionStartedAt: sendStartedAt)
        } else {
            supabaseService.analytics.track("intent_detected", payload: [
                "intent": "recommend",
                "source": "keywords",
                "input_length": Double(text.count),
            ])
            await handleRecommendationFlow(text: text, interactionStartedAt: sendStartedAt)
        }
    }

    private func reparse(message: ConciergeMessage) {
        // Only assistant messages that were generated from a specific user input can re-parse.
        guard message.role == .assistant, let source = message.sourceUserText, !source.isEmpty else { return }
        input = source
        focusRequest = true
    }

    // MARK: Clarification Re-Parse (Disambiguated)
    private func handleClarification(kind: String, value: String, sourceText: String) async {
        guard clarifyV2Enabled else { return }
        errorText = nil
        isWorking = true

        // Dismiss keyboard
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif

        // Intent-level clarify can switch flows directly.
        if kind == "intent_unclear" {
            if value.lowercased() == "recommend_seed" {
                supabaseService.analytics.track("clarify_selected", payload: [
                    "kind": kind,
                    "value": value,
                    "routed_to": "recommend",
                    "surface": "concierge_chat",
                    "result": "recommend",
                ])
                await handleRecommendationFlow(text: sourceText)
                isWorking = false
                return
            }
        }

        let clarification = [kind: value]
        supabaseService.analytics.track("clarify_selected", payload: [
            "kind": kind,
            "value": value,
            "routed_to": "import_reparse",
            "surface": "concierge_chat",
            "result": "import_reparse",
        ])

        do {
            let response = try await supabaseService.conciergeParse(
                text: sourceText,
                scope: .both,
                clarification: clarification
            )

            // Pre-select top candidates
            for item in response.items {
                autoReasonByItemId[item.id] = nil
                if let top = item.candidates.first, top.score >= 0.60 {
                    if !hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention) {
                        selectedByItemId[item.id] = top
                    }
                }
                let action = computeItemAction(item: item)
                itemActions[item.id] = action
            }

            // Check if there are still ambiguities in the re-parsed response
            let remainingAmbiguity = response.items.compactMap(\.ambiguity).first

            if remainingAmbiguity != nil, clarifyV2Enabled {
                // Still ambiguous -- show another clarify card
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: "",
                    sourceUserText: sourceText,
                    items: response.items,
                    parseResponse: response,
                    ambiguity: remainingAmbiguity
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
            } else {
                // Resolved -- show the confirm bubble
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: "",
                    sourceUserText: sourceText,
                    items: response.items,
                    parseResponse: response
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
            }
        } catch {
            handleError(error)
        }

        isWorking = false
    }

    // NOTE: This runs BEFORE FM intent classification (by design).
    // Catches garbage/low-signal input without burning FM inference.
    private func shouldAskClarifyingQuestion(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }

        // If it already looks like an import (multi-line, progress/status cues), don't block.
        if looksLikeImport(t) { return false }

        // Single-token short inputs are most likely noise unless they are known abbreviations.
        let tokens = t.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
        if tokens.count == 1 {
            let s = String(tokens[0])
            let upper = s.uppercased()

            // Known short anime abbreviations we should treat as a seed instead of asking.
            // Keep this set small and high-signal; the server still handles the rich parsing.
            let knownAbbrev: Set<String> = [
                "AOT", "HXH", "NGE", "EVA", "DB", "DBZ", "DBS", "SAO",
                "TPN", "BNHA", "OP"
            ]
            if knownAbbrev.contains(upper) { return false }

            // Obvious low-signal (very short or command-like).
            if s.count <= 3 { return true }
            if upper == "ADD" || upper == "IMPORT" { return true }

            // Random letters (no vowels) tends to be noise: "AGBTT".
            if s.count <= 6,
               s.range(of: #"^[A-Za-z]{3,6}$"#, options: .regularExpression) != nil
            {
                let lower = s.lowercased()
                let hasVowel = lower.contains(where: { "aeiouy".contains($0) })
                if !hasVowel { return true }
            }
        }

        // If it's extremely short and has no structure, ask.
        if t.count < 5, t.range(of: #"[0-9\(\)]"#, options: .regularExpression) == nil {
            return true
        }

        return false
    }

    // MARK: Import Flow (Inline)
    private func handleImportFlow(text: String, interactionStartedAt: SupabaseService.InteractionStartedAt? = nil) async {
        let parseStartedAt = supabaseService.beginInteractionTiming()
        do {
            var firstResponseTracked = false

            func trackFirstResponseIfNeeded(_ result: String) {
                guard let interactionStartedAt, !firstResponseTracked else { return }
                firstResponseTracked = true
                supabaseService.trackInteractionEvent(
                    "concierge_first_response_ms",
                    surface: "concierge_chat",
                    result: result,
                    startedAt: interactionStartedAt
                )
            }

            #if DEBUG
            let parseStart = CFAbsoluteTimeGetCurrent()
            #endif

            let response = try await supabaseService.conciergeParse(text: text, scope: .both)

            supabaseService.analytics.track("parse_completed", payload: [
                "item_count": Double(response.items.count),
                "has_ambiguity": response.items.contains { $0.ambiguity != nil },
            ])
            supabaseService.trackInteractionEvent(
                "concierge_parse_ms",
                surface: "concierge_parse",
                result: "ok",
                startedAt: parseStartedAt,
                extra: ["item_count": response.items.count]
            )

            #if DEBUG
            let parseEnd = CFAbsoluteTimeGetCurrent()
            print("[Concierge Timing] parse response returned: \(String(format: "%.0f", (parseEnd - parseStart) * 1000))ms")
            #endif

            // Prefetch top candidate covers so the confirm bubble feels instant.
            #if canImport(UIKit)
            let maxPrefetchItems = conciergePerfV2Enabled ? 12 : 8
            let coverUrls: [URL] = Array(response.items.flatMap { item in
                item.candidates.prefix(1).compactMap { c in
                    guard let s = c.cover_image_medium, let url = URL(string: s) else { return nil }
                    return url
                }
            }.prefix(maxPrefetchItems))
            #if DEBUG
            let prefetchStart = CFAbsoluteTimeGetCurrent()
            print("[Concierge Timing] image prefetch started: \(String(format: "%.1f", (prefetchStart - parseEnd) * 1000))ms after parse")
            #endif
            prefetchTask = Task.detached(priority: .background) {
                await ImagePipeline.shared.prefetch(urls: coverUrls, maxPixelSize: 520)
            }
            #endif

            // Pre-select top candidates (skip when adaptations are ambiguous)
            var hasAnyExistingEntry = false
            var ambiguousItemsNeedingHelp: [SupabaseService.ConciergeParseItem] = []
            for item in response.items {
                autoReasonByItemId[item.id] = nil
                if let top = item.candidates.first, top.score >= 0.60 {
                    if hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention) {
                        ambiguousItemsNeedingHelp.append(item)
                        continue
                    }
                    selectedByItemId[item.id] = top
                }

                // Compute reconciliation action per item
                let action = computeItemAction(item: item)
                itemActions[item.id] = action
                if item.existing_entry != nil {
                    hasAnyExistingEntry = true
                }
            }

            // Check for parser-level ambiguities that need user clarification
            let parserAmbiguity = response.items.compactMap(\.ambiguity).first

            if let ambiguity = parserAmbiguity, clarifyV2Enabled {
                // Dismiss keyboard when clarify card appears
                #if os(iOS)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif

                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: ambiguity.suggested_question ?? "",
                    sourceUserText: text,
                    items: response.items,
                    parseResponse: response,
                    ambiguity: ambiguity
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
                trackFirstResponseIfNeeded("clarify")
                #if DEBUG
                print("[Concierge Timing] clarify card rendered: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - parseStart) * 1000))ms total from parse start")
                #endif
            } else {
                // Auto-apply safety: disabled when ANY item has an existing_entry
                let allHighConfidence = !hasAnyExistingEntry && response.items.allSatisfy { item in
                    guard let top = item.candidates.first else { return false }
                    return top.score >= 0.85 && !hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention)
                }

                if allHighConfidence && !response.items.isEmpty {
                    // Auto-apply: skip confirm UI entirely
                    await autoApplyImport(response: response, interactionStartedAt: interactionStartedAt)
                } else {
                    // Show inline confirm bubble in chat
                    let assistantMsg = ConciergeMessage(
                        role: .assistant,
                        text: "",
                        sourceUserText: text,
                        items: response.items,
                        parseResponse: response
                    )
                    withAnimation(KuroAnimation.editorial) {
                        messages.append(assistantMsg)
                    }
                    trackFirstResponseIfNeeded("confirm")
                    #if DEBUG
                    print("[Concierge Timing] confirm bubble rendered: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - parseStart) * 1000))ms total from parse start")
                    #endif
                }
            }

            // On-device Apple FM can help pick the correct adaptation when candidates share a base title
            // (e.g. "Hunter x Hunter" 1999 vs 2011). This runs after the confirm bubble is visible
            // so the UI stays snappy, and it never overrides a user-made selection.
            if !ambiguousItemsNeedingHelp.isEmpty {
                disambiguationTask = Task {
                    await autoDisambiguateAmbiguousAdaptations(items: ambiguousItemsNeedingHelp, userText: text)
                }
            }
        } catch {
            supabaseService.trackInteractionEvent(
                "concierge_parse_ms",
                surface: "concierge_parse",
                result: "error",
                startedAt: parseStartedAt
            )
            handleError(error)
        }
    }

    private func autoDisambiguateAmbiguousAdaptations(
        items: [SupabaseService.ConciergeParseItem],
        userText: String
    ) async {
        // FM assist is optional and flag-gated.
        guard fmAssistEnabled else { return }

        for item in items {
            if Task.isCancelled { return }

            // Respect manual selections and "excluded" toggles.
            if excludedItemIds.contains(item.id) { continue }
            if selectedByItemId[item.id] != nil { continue }

            // Keep the candidate set small to reduce latency.
            let topCandidates = Array(item.candidates.prefix(4))
            guard topCandidates.count >= 2 else { continue }

            let fmCandidates: [DisambiguationCandidate] = topCandidates.enumerated().map { i, c in
                DisambiguationCandidate(
                    index: i,
                    title: c.title_raw,
                    year: c.year,
                    format: c.format,
                    score: c.score,
                    variantType: c.media_type
                )
            }

            guard let picked = await supabaseService.fmService.disambiguate(
                candidates: fmCandidates,
                userText: userText,
                rawTitle: item.raw
            ) else {
                continue
            }

            let idx = picked.selectedIndex
            guard topCandidates.indices.contains(idx) else { continue }

            // Apply only if the user still hasn't chosen something else.
            if selectedByItemId[item.id] == nil && !excludedItemIds.contains(item.id) {
                selectedByItemId[item.id] = topCandidates[idx]
                autoReasonByItemId[item.id] = picked.reasoning
            }
        }
    }

    // MARK: Reconciliation Helpers

    private func computeItemAction(item: SupabaseService.ConciergeParseItem) -> ImportItemAction {
        guard let existing = item.existing_entry else { return .add }
        let diff = computeDiff(existing: existing, parsed: item.parsed)
        if let diff, !diff.isEmpty { return .update }
        return .skip
    }

    private func computeDiff(existing: SupabaseService.ConciergeExistingEntry, parsed: SupabaseService.ConciergeParseItemParsed) -> ImportDiff? {
        var diff = ImportDiff()

        if let parsedStatus = parsed.status,
           parsedStatus.uppercased() != existing.status.uppercased() {
            diff.status = ImportDiff.FieldDiff(from: existing.status, to: parsedStatus.uppercased())
        }
        if let ep = parsed.progressEpisodes,
           ep != (existing.progress_episodes ?? 0) {
            diff.progressEpisodes = ImportDiff.FieldDiff(from: existing.progress_episodes ?? 0, to: ep)
        }
        if let ch = parsed.progressChapters,
           ch != (existing.progress_chapters ?? 0) {
            diff.progressChapters = ImportDiff.FieldDiff(from: existing.progress_chapters ?? 0, to: ch)
        }
        if let vol = parsed.progressVolumes,
           vol != (existing.progress_volumes ?? 0) {
            diff.progressVolumes = ImportDiff.FieldDiff(from: existing.progress_volumes ?? 0, to: vol)
        }

        return diff.isEmpty ? nil : diff
    }

    // MARK: Auto-Apply (High Confidence, Pure Adds Only)
    private func autoApplyImport(
        response: SupabaseService.ConciergeParseResponse,
        interactionStartedAt: SupabaseService.InteractionStartedAt? = nil
    ) async {
        do {
            let chosen = buildApplyPayload(from: response)
            guard !chosen.isEmpty else { return }

            let res = try await supabaseService.conciergeApply(items: chosen)
            if let sessionId = res.sessionId {
                setLastApplySession(sessionId)
            }

            // Check if the apply actually succeeded
            guard res.success else {
                let errorDetail = res.errors?.first?.error ?? "Unknown error"
                showToast(.init(kind: .error, title: "Failed to add items", subtitle: errorDetail, actionTitle: nil, onAction: nil))
                return
            }

            // Refresh collection in background (don't block toast)
            backgroundRefreshTask = Task.detached {
                async let _lists: () = supabaseService.fetchUserLists()
                async let _items: () = supabaseService.fetchCollectionItems()
                async let _feed: () = supabaseService.fetchCollectionFeed(status: nil)
                _ = await (_lists, _items, _feed)
            }

            // Show success toast with undo
            let appliedCount = res.applied?.count ?? chosen.count
            let summaryText = "\(appliedCount) item\(appliedCount == 1 ? "" : "s") added to collection"
            let sid = lastApplySessionId
            showToast(.init(
                kind: .success,
                title: summaryText,
                subtitle: nil,
                actionTitle: "UNDO",
                onAction: {
                    guard let sid else { return }
                    Task {
                        await undoApply(sessionId: sid)
                    }
                }
            ), autoDismissSeconds: 4.0)

            // Build title list for confirmation message
            let titleNames = response.items.compactMap { item -> String? in
                guard let c = selectedByItemId[item.id] else { return nil }
                if excludedItemIds.contains(item.id) { return nil }
                return c.title_raw
            }
            let titleList = titleNames.isEmpty ? "" : "\n" + titleNames.map { "· \($0)" }.joined(separator: "\n")

            // Add confirmation message to chat
            let confirmMsg = ConciergeMessage(
                role: .assistant,
                text: "\(summaryText).\(titleList)",
                items: nil
            )
            withAnimation(KuroAnimation.editorial) {
                appliedImportSummary = summaryText
                messages.append(confirmMsg)
            }
            if let interactionStartedAt {
                supabaseService.trackInteractionEvent(
                    "concierge_first_response_ms",
                    surface: "concierge_chat",
                    result: "auto_apply",
                    startedAt: interactionStartedAt
                )
            }

        } catch {
            handleError(error)
        }
    }

    // MARK: Recommendation Flow (Inline Rails)
    private func handleRecommendationFlow(
        text: String,
        interactionStartedAt: SupabaseService.InteractionStartedAt? = nil
    ) async {
        let recommendStartedAt = supabaseService.beginInteractionTiming()
        do {
            var firstResponseTracked = false

            func trackFirstResponseIfNeeded(_ result: String) {
                guard let interactionStartedAt, !firstResponseTracked else { return }
                firstResponseTracked = true
                supabaseService.trackInteractionEvent(
                    "concierge_first_response_ms",
                    surface: "concierge_chat",
                    result: result,
                    startedAt: interactionStartedAt
                )
            }

            #if DEBUG
            let recStart = CFAbsoluteTimeGetCurrent()
            #endif

            let rec = try await supabaseService.conciergeRecommend(text: text, scope: .both, limit: 8)
            supabaseService.trackInteractionEvent(
                "concierge_recommend_ms",
                surface: "concierge_recommend",
                result: "ok",
                startedAt: recommendStartedAt,
                extra: ["item_count": (rec.items ?? []).count]
            )
            lastRecommendQuery = text
            lastRecommendWasRagAssist = rec.assist?.ragUsed == true
            lastRagSeedEntityId = rec.assist?.seedEntityId
            let sets = (rec.sets ?? []).filter { ($0.items ?? []).isEmpty == false }
            let flattened = sets.flatMap { $0.items ?? [] }
            let displayItems = !flattened.isEmpty ? flattened : (rec.items ?? [])
            let note = (rec.curatorNote ?? sets.first?.curatorNote ?? rec.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            #if DEBUG
            let recEnd = CFAbsoluteTimeGetCurrent()
            print("[Concierge Timing] recommend response returned: \(String(format: "%.0f", (recEnd - recStart) * 1000))ms")
            #endif

            // Prefetch recommendation posters for a snappy first render.
            #if canImport(UIKit)
            let maxPrefetchItems = conciergePerfV2Enabled ? 12 : 8
            let recUrls: [URL] = Array(displayItems.compactMap { item in
                guard let s = item.coverImageMedium, let url = URL(string: s) else { return nil }
                return url
            }.prefix(maxPrefetchItems))
            #if DEBUG
            print("[Concierge Timing] rec image prefetch started: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - recEnd) * 1000))ms after response")
            #endif
            prefetchTask2 = Task.detached(priority: .background) {
                await ImagePipeline.shared.prefetch(urls: recUrls, maxPixelSize: 560)
            }
            #endif

            if rec.success, !displayItems.isEmpty {
                // Append inline recommendation message with editorial rails
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: note,
                    items: nil,
                    recommendations: !sets.isEmpty ? nil : displayItems,
                    recommendationSets: !sets.isEmpty ? sets : nil
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
                let ladderCandidates: [(mediaType: String, mediaId: Int)] = displayItems
                    .prefix(8)
                    .map { item in
                        (mediaType: item.mediaType.uppercased(), mediaId: item.mediaId)
                    }
                supabaseService.prefetchMediaRelationRefreshRequests(
                    items: ladderCandidates,
                    reason: "concierge_recommend"
                )
                trackFirstResponseIfNeeded("recommend")
                #if DEBUG
                print("[Concierge Timing] rec bubble rendered: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - recStart) * 1000))ms total from rec start")
                #endif
            } else {
                lastRecommendWasRagAssist = false
                lastRagSeedEntityId = nil
                // No results — show text message
                let locale = (rec.locale ?? "en").lowercased()
                let fallback = locale.hasPrefix("de")
                    ? "Sag mir eine Stimmung oder eine klare Kante (kurz, ohne Romance, ein Jahr) — ich kuratiere es neu fuer dich."
                    : "Give me a mood or one constraint (short, no romance, a year) and I’ll curate it — new to you."
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: rec.message ?? fallback,
                    items: nil
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
                trackFirstResponseIfNeeded("recommend_empty")
            }

        } catch {
            supabaseService.trackInteractionEvent(
                "concierge_recommend_ms",
                surface: "concierge_recommend",
                result: "error",
                startedAt: recommendStartedAt
            )
            handleError(error)
        }
    }

    // MARK: Confirm Import (From Inline Bubble)
    private func confirmImport(response: SupabaseService.ConciergeParseResponse, sourceMessageId: UUID? = nil) async {
        isWorking = true
        if let sourceMessageId {
            applyingImportMessageId = sourceMessageId
        }

        do {
            let chosen = buildApplyPayload(from: response)

            guard !chosen.isEmpty else {
                showToast(.init(kind: .error, title: "No items selected", subtitle: nil, actionTitle: nil, onAction: nil))
                isWorking = false
                applyingImportMessageId = nil
                return
            }

            let res = try await supabaseService.conciergeApply(items: chosen)
            if let sessionId = res.sessionId {
                setLastApplySession(sessionId)
            }

            // Check if the apply actually succeeded
            guard res.success else {
                let errorDetail = res.errors?.first?.error ?? "Unknown error"
                showToast(.init(kind: .error, title: "Failed to apply items", subtitle: errorDetail, actionTitle: nil, onAction: nil))
                isWorking = false
                applyingImportMessageId = nil
                return
            }

            // Refresh collection in background
            backgroundRefreshTask2 = Task.detached {
                async let _lists: () = supabaseService.fetchUserLists()
                async let _items: () = supabaseService.fetchCollectionItems()
                async let _feed: () = supabaseService.fetchCollectionFeed(status: nil)
                _ = await (_lists, _items, _feed)
            }

            // Compute summary text based on actual server response
            let appliedItems = res.applied ?? []
            let serverAddCount = appliedItems.filter { $0.action == "add" }.count
            let serverUpdateCount = appliedItems.filter { $0.action == "update" }.count
            let conflictCount = res.conflicts?.count ?? 0

            var summaryParts: [String] = []
            if serverAddCount > 0 { summaryParts.append("\(serverAddCount) added") }
            if serverUpdateCount > 0 { summaryParts.append("\(serverUpdateCount) updated") }
            let summaryText = summaryParts.isEmpty ? "\(appliedItems.count) items applied" : summaryParts.joined(separator: ", ")

            let sid = lastApplySessionId
            showToast(.init(
                kind: conflictCount > 0 ? .info : .success,
                title: summaryText,
                subtitle: conflictCount > 0 ? "\(conflictCount) conflict\(conflictCount == 1 ? "" : "s") -- review needed" : nil,
                actionTitle: "UNDO",
                onAction: {
                    guard let sid else { return }
                    Task {
                        await undoApply(sessionId: sid)
                    }
                }
            ), autoDismissSeconds: 4.0)

            withAnimation(KuroAnimation.editorial) {
                appliedImportSummary = summaryText
                applyingImportMessageId = nil
                if let sourceMessageId {
                    appliedImportMessageIds.insert(sourceMessageId)
                    lastAppliedImportMessageId = sourceMessageId
                }
            }

        } catch {
            handleError(error)
        }

        isWorking = false
    }

    // MARK: Build Apply Payload
    private func buildApplyPayload(from response: SupabaseService.ConciergeParseResponse) -> [[String: Any]] {
        response.items.compactMap { item -> [String: Any]? in
            guard let c = selectedByItemId[item.id] else { return nil }

            // Respect per-item exclusion toggles
            if excludedItemIds.contains(item.id) { return nil }

            let action = itemActions[item.id] ?? .add
            // Skip items produce no apply payload
            if action == .skip { return nil }

            let mediaType = c.media_type
            let status = normalizedStatus(for: item.parsed.status, mediaType: mediaType)

            var payload: [String: Any] = [
                "raw": item.raw,
                "mediaType": mediaType.uppercased(),
                "mediaId": c.media_id,
                "status": status,
                "confidence": c.score,
                "action": action.rawValue,
            ]

            let p = item.parsed
            if let v = p.progressEpisodes  { payload["progressEpisodes"] = v }
            if let v = p.progressChapters   { payload["progressChapters"] = v }
            if let v = p.progressVolumes    { payload["progressVolumes"] = v }
            if let v = p.seasonNumber       { payload["seasonNumber"] = v }
            if let v = p.episodeInSeason    { payload["episodeInSeason"] = v }
            if let v = p.caughtUp           { payload["caughtUp"] = v }
            if let v = p.lastEpisode        { payload["lastEpisode"] = v }
            if let v = p.completed          { payload["completed"] = v }
            if let v = p.rating             { payload["rating"] = v }

            // TOCTOU protection: send expected existing state for updates
            if action == .update, let existing = item.existing_entry {
                var expected: [String: Any] = ["status": existing.status]
                if let ep = existing.progress_episodes { expected["progress_episodes"] = ep }
                if let ch = existing.progress_chapters { expected["progress_chapters"] = ch }
                if let vol = existing.progress_volumes { expected["progress_volumes"] = vol }
                payload["expectedExisting"] = expected
            }

            return payload
        }
    }

    // MARK: Actions
    private func openRecommendation(_ item: SupabaseService.ConciergeRecommendResponse.Item) async {
        errorText = nil

        do {
            if item.mediaType.uppercased() == "ANIME" {
                let anime = try await supabaseService.fetchAnimeById(item.mediaId)
                guard let anime else {
                    errorText = "Couldn't find that anime in the database."
                    return
                }
                selectedAnime = anime
                recordRagFeedbackIfNeeded(accepted: true)
            } else {
                let manga = try await supabaseService.fetchMangaById(item.mediaId)
                guard let manga else {
                    errorText = "Couldn't find that manga in the database."
                    return
                }
                selectedManga = manga
                recordRagFeedbackIfNeeded(accepted: true)
            }
        } catch {
            errorText = "Couldn't open: \(error.localizedDescription)"
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
            notes: nil,
            verdict: supabaseService.userListEntry(mediaType: mediaType, mediaId: item.mediaId)?.verdict
        )
        recordRagFeedbackIfNeeded(accepted: true)
        showToast(.init(kind: .success, title: "Added to Planning", subtitle: item.title, actionTitle: nil, onAction: nil))
    }

    // MARK: Undo
    private func undoApply(sessionId: String) async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            let res = try await supabaseService.conciergeUndo(sessionId: sessionId)

            // Refresh in background
            undoRefreshTask = Task.detached {
                async let _lists: () = supabaseService.fetchUserLists()
                async let _items: () = supabaseService.fetchCollectionItems()
                async let _feed: () = supabaseService.fetchCollectionFeed(status: nil)
                _ = await (_lists, _items, _feed)
            }

            setLastApplySession(nil)

            if res.success {
                if let lastAppliedImportMessageId {
                    appliedImportMessageIds.remove(lastAppliedImportMessageId)
                    self.lastAppliedImportMessageId = nil
                }
                showToast(.init(kind: .success, title: "Import undone", subtitle: nil, actionTitle: nil, onAction: nil))
            } else {
                showToast(.init(kind: .error, title: "Undo failed", subtitle: "Try again.", actionTitle: nil, onAction: nil))
            }
        } catch {
            errorText = "Undo failed: \(error.localizedDescription)"
            showToast(.init(kind: .error, title: "Undo failed", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil))
        }
    }

    // MARK: Helpers
    private func handleError(_ error: Error) {
        if let guardrail = error as? SupabaseService.ConciergeGuardrailsError {
            // Persistent: rate limit / guardrail errors stay inline until next action
            errorText = guardrail.localizedDescription
        } else {
            // Transient: network / server errors as auto-dismissing toast only
            errorText = nil
            showToast(.init(kind: .error, title: "Error", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil), autoDismissSeconds: 3.0)
        }
    }

    private func navigateToCollection() {
        #if os(iOS)
        if let url = URL(string: "kuro://collection") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func startNewChat() {
        withAnimation(KuroAnimation.fast) {
            messages = []
        }
        input = ""
        focusRequest = true
        errorText = nil
        selectedByItemId = [:]
        itemActions = [:]
        excludedItemIds = []
        autoReasonByItemId = [:]
        appliedImportMessageIds = []
        lastAppliedImportMessageId = nil
        applyingImportMessageId = nil
        appliedImportSummary = nil
        lastRecommendQuery = nil
        lastRecommendWasRagAssist = false
        lastRagSeedEntityId = nil
        ragFeedbackSentForQuery = []
    }

    private func normalizedStatus(for raw: String?, mediaType: String?) -> String {
        let s = (raw ?? "").uppercased()
        if mediaType == "manga", s == "WATCHING" { return "READING" }
        if mediaType == "anime", s == "READING" { return "WATCHING" }
        if s.isEmpty { return "PLANNING" }
        return s
    }

    private func setLastApplySession(_ sessionId: String?) {
        lastApplySessionResetTask?.cancel()
        lastApplySessionId = sessionId
        guard let sessionId else { return }
        // Avoid stale sticky undo controls if the user moves on.
        lastApplySessionResetTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            guard !Task.isCancelled else { return }
            if lastApplySessionId == sessionId {
                lastApplySessionId = nil
            }
        }
    }

    // MARK: Adaptation Ambiguity Guard
    private func strippedBaseTitle(_ raw: String) -> String {
        var t = raw
        if let range = t.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            t.removeSubrange(range)
        }
        if let range = t.range(of: ": ") {
            t = String(t[t.startIndex..<range.lowerBound])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func hasAmbiguousAdaptations(
        candidates: [SupabaseService.ConciergeCandidate],
        yearMention: Int?
    ) -> Bool {
        guard candidates.count >= 2 else { return false }

        let top = candidates[0]
        let second = candidates[1]

        guard top.media_id != second.media_id else { return false }

        let baseTop = strippedBaseTitle(top.title_raw)
        let baseSecond = strippedBaseTitle(second.title_raw)
        guard baseTop == baseSecond else { return false }

        if let mentioned = yearMention, let topYear = top.year, topYear == mentioned {
            return false
        }

        return true
    }

    private func recordRagFeedbackIfNeeded(accepted: Bool, rejectedReason: String? = nil) {
        guard lastRecommendWasRagAssist, let query = lastRecommendQuery else { return }
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        guard !ragFeedbackSentForQuery.contains(key) else { return }
        ragFeedbackSentForQuery.insert(key)

        let locale = Locale.current.identifier
        let entityId = lastRagSeedEntityId

        Task(priority: .utility) {
            await supabaseService.conciergeRetrieveFeedback(
                query: query,
                locale: locale,
                selectedEntityId: entityId,
                accepted: accepted,
                rejectedReason: rejectedReason
            )
        }
    }


    @MainActor
    private func showToast(_ next: KuroToastState, autoDismissSeconds: Double = 2.5) {
        toastDismissTask?.cancel()
        withAnimation(KuroAnimation.fast) {
            toast = next
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0.8, autoDismissSeconds) * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(KuroAnimation.fast) {
                    toast = nil
                }
            }
        }
    }

    private func importFromLibrary() async {
        guard !isWorking else { return }
        errorText = nil

        let result = await supabaseService.conciergeLibraryExportText(
            includeStatus: Set(ListStatus.allCases),
            includeMediaTypes: ["anime", "manga"],
            maxItems: 400
        )

        guard let result else {
            showToast(.init(
                kind: .info,
                title: isGermanLocale ? "Bibliothek leer" : "Library is empty",
                subtitle: isGermanLocale ? "Bitte füge zuerst Titel zu deiner Bibliothek hinzu." : "Add titles to your library first.",
                actionTitle: nil,
                onAction: nil
            ))
            return
        }

        await sendExternalImport(
            sourceLabel: isGermanLocale ? "Kuro-Liste" : "Kuro library",
            displayText: isGermanLocale
                ? "Kuro-Liste importieren (\(result.exportedItemCount) Titel)"
                : "Importing from Kuro library (\(result.exportedItemCount) items)",
            sourceText: result.text,
            truncated: result.truncated
        )
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        guard let t = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty
        else {
            showToast(.init(
                kind: .info,
                title: isGermanLocale ? "Zwischenablage ist leer" : "Clipboard is empty",
                subtitle: isGermanLocale ? "Kopiere eine Liste von Titeln und tippe dann auf Einfügen." : "Copy a list of titles, then tap Paste.",
                actionTitle: nil,
                onAction: nil
            ))
            return
        }
        input = t
        focusRequest = true
        KuroAccessibility.impactHaptic(.light)
        #endif
    }

    private func seedExampleImport() {
        input = """
        Attack on Titan (completed)
        Jujutsu Kaisen up to ep 12
        Hunter x Hunter (2011)
        """
        focusRequest = true
        KuroAccessibility.impactHaptic(.light)
    }

    private func seedExampleVibe() {
        input = isGermanLocale
            ? "Etwas lustig, trocken, figurengetrieben — nicht kindisch."
            : "Something funny, dry, character-led — not childish."
        focusRequest = true
        KuroAccessibility.impactHaptic(.light)
    }

    // MARK: Import vs Vibe Detection
    private func looksLikeImport(_ text: String) -> Bool {
        TextNormalization.looksLikeImport(text)
    }
}

// MARK: - Guided Tutorial Overlay

private struct ConciergeTutorialOverlay: View {
    @Binding var step: Int
    let isGerman: Bool
    let onDismiss: () -> Void

    private let steps: [(iconEN: String, titleEN: String, bodyEN: String, iconDE: String, titleDE: String, bodyDE: String)] = [
        (
            iconEN: "text.bubble",
            titleEN: "Describe a mood",
            bodyEN: "Type something like \"dark, not gory, short\" and the Concierge curates two rails for you.",
            iconDE: "text.bubble",
            titleDE: "Beschreibe eine Stimmung",
            bodyDE: "Schreibe z.B. \"dunkel, kein Gore, kurz\" und der Concierge kuratiert zwei Rails fur dich."
        ),
        (
            iconEN: "doc.on.clipboard",
            titleEN: "Or paste your list",
            bodyEN: "Paste your anime list from any source. The Concierge matches, reconciles, and imports it.",
            iconDE: "doc.on.clipboard",
            titleDE: "Oder fuge deine Liste ein",
            bodyDE: "Fuge deine Anime-Liste ein. Der Concierge gleicht ab, erkennt Konflikte und importiert."
        ),
        (
            iconEN: "sparkles",
            titleEN: "Curated for you",
            bodyEN: "Recommendations come filtered against your library. No duplicates, no noise.",
            iconDE: "sparkles",
            titleDE: "Kuratiert fur dich",
            bodyDE: "Empfehlungen werden gegen deine Bibliothek gefiltert. Keine Duplikate, kein Rauschen."
        ),
    ]

    private var activeStep: (iconEN: String, titleEN: String, bodyEN: String, iconDE: String, titleDE: String, bodyDE: String) {
        steps[step]
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.kuroBlack.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { advance() }

            VStack(spacing: 20) {
                Spacer()

                tutorialCard
                .padding(.vertical, 28)
                .padding(.horizontal, 20)

                Spacer()

                // Skip
                if step < steps.count - 1 {
                    skipButton
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isGerman ? "Concierge-Anleitung" : "Concierge tutorial")
    }

    private var tutorialCard: some View {
        VStack(spacing: 18) {
            Circle()
                .fill(Color.kuroWhite.opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: isGerman ? activeStep.iconDE : activeStep.iconEN)
                        .font(.kuroCustom(22, weight: .light, relativeTo: .title3))
                        .foregroundColor(Color.kuroWhite.opacity(0.88))
                )

            Text(isGerman ? activeStep.titleDE : activeStep.titleEN)
                .font(.kuroCustom(22, weight: .ultraLight, design: .serif, relativeTo: .title3))
                .foregroundColor(Color.kuroWhite92)

            Text(isGerman ? activeStep.bodyDE : activeStep.bodyEN)
                .font(.kuroBody(weight: .light))
                .foregroundColor(Color.kuroWhite.opacity(0.68))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)

            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle()
                        .fill(Color.kuroWhite.opacity(step == i ? 0.80 : 0.25))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.top, 4)

            Button(action: { advance() }) {
                Text(step < steps.count - 1
                     ? (isGerman ? "WEITER" : "NEXT")
                     : (isGerman ? "VERSTANDEN" : "GOT IT"))
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.8)
                    .foregroundColor(Color.kuroBlack.opacity(0.88))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.kuroWhite92)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var skipButton: some View {
        Button(action: { onDismiss() }) {
            Text(isGerman ? "Uberspringen" : "Skip")
                .font(.kuroCaption(weight: .medium))
                .foregroundColor(Color.kuroWhite.opacity(0.42))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 48)
    }

    private func advance() {
        KuroAccessibility.impactHaptic(.light)
        if step < steps.count - 1 {
            withAnimation(KuroAnimation.fast) {
                step += 1
            }
        } else {
            onDismiss()
        }
    }
}

// MARK: - Preview
#Preview {
    ConciergeView()
}

```

### Edge Function: concierge-parse (deterministic parsing)

- Path: `supabase/functions/concierge-parse/index.ts`


```ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { umlautFold } from "../_shared/normalization.ts";

type MediaType = "ANIME" | "MANGA";
type ListStatus = "WATCHING" | "READING" | "PLANNING" | "COMPLETED" | "DROPPED" | "PAUSED";

type Ambiguity = {
  kind: "status_unclear" | "unit_unclear" | "intent_unclear";
  options: string[];
  suggested_question: string;
  suggested_question_de: string;
  title_context?: string;
  number_context?: string;
} | null;

type ParsedItem = {
  raw: string;
  normalized: string;
  mediaTypeHint?: MediaType;
  status?: ListStatus;
  progressEpisodes?: number;
  progressChapters?: number;
  progressVolumes?: number;
  progressTotal?: number;
  progressUnit?: string;
  seasonNumber?: number;
  episodeInSeason?: number;
  caughtUp?: boolean;
  lastEpisode?: boolean;
  completed?: boolean;
  yearMention?: number;
  rating?: number;
  ambiguity?: Ambiguity;
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
    snk: "Attack on Titan", // Shingeki no Kyojin
    jjk: "Jujutsu Kaisen",
    mha: "My Hero Academia",
    bnha: "My Hero Academia", // Boku no Hero Academia
    hxh: "Hunter x Hunter",
    fmab: "Fullmetal Alchemist: Brotherhood",
    fma: "Fullmetal Alchemist",
    opm: "One Punch Man",
    csm: "Chainsaw Man",
    jjba: "JoJo's Bizarre Adventure",
    kny: "Demon Slayer: Kimetsu no Yaiba",
    op: "One Piece",
    db: "Dragon Ball",
    dbz: "Dragon Ball Z",
    dbs: "Dragon Ball Super",
    sao: "Sword Art Online",
    bc: "Black Clover",
    tog: "Tower of God",
    mia: "Made in Abyss",
    rezero: "Re:ZERO -Starting Life in Another World-",
    konosuba: "Kono Subarashii Sekai ni Shukufuku wo!",
    mp100: "Mob Psycho 100",
    nge: "Neon Genesis Evangelion",
    eva: "Neon Genesis Evangelion",
    lotgh: "Legend of the Galactic Heroes",
    logh: "Legend of the Galactic Heroes",
    tpn: "The Promised Neverland",
    dm: "Dungeon Meshi",
    cote: "Classroom of the Elite",
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
    /\b(watched|watching|finished|completed|dropped|paused|planning|read|reading|caught up|up to date|seen|saw|started|begun)\b/giu,
    " ",
  );
  s = s.replace(
    /\b(geschaut|gesehen|gelesen|fertig|abgeschlossen|beendet|abgebrochen|pausiert|geplant|aktuell|komplett|vollständig|vollstaendig|angefangen|noch dabei)\b/giu,
    " ",
  );
  // strip rating patterns
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s*\/\s*\d{1,2}\b/giu, " ");
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s+(?:von|out of)\s+\d{1,2}\b/giu, " ");
  s = s.replace(/\beine?\s+\d{1,2}\b/giu, " ");
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s+(?:punkte|points?|stars?|sterne?)\b/giu, " ");
  s = s.replace(/⭐/g, " ");
  // strip progress markers
  s = s.replace(/\b(?:season|staffel|episode|ep|folge|chapter|ch|kapitel|volume|vol|band)\b/giu, " ");
  s = s.replace(/\b\d{1,2}\s*x\s*\d{1,4}\b/giu, " ");
  s = s.replace(/\bs\d{1,2}\s*e\d{1,4}\b/giu, " ");
  // keep only letters/numbers/spaces (unicode)
  s = s.replace(/[^\p{L}\p{N}\s]+/gu, " ");
  // Fold umlauts for consistent alias matching
  s = umlautFold(s);
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
  const hasSoftPartial =
    /\b(halfway|half way|midway|partway|some of it|a bit|a few (?:eps|episodes|chapters))\b/.test(s) ||
    /\b(halb|hälfte|haelfte|zur hälfte|zur haelfte|teilweise|ein bisschen)\b/.test(s);

  // English + slang
  if (/\b(caught up|up to date|up-to-date|latest|current)\b/.test(s)) return { status: "WATCHING" };
  const iFinished =
    /\b(i\s+(?:just\s+)?finished|i\s+(?:just\s+)?completed)\b/.test(s);
  const iWatched =
    /\b(i\s+(?:just\s+)?watched|i\s+(?:just\s+)?saw|i\s+have\s+watched|i\s+have\s+seen)\b/.test(s);
  const iRead =
    /\b(i\s+(?:just\s+)?read|i\s+have\s+read)\b/.test(s);
  const iStarted =
    /\b(i\s+(?:just\s+)?started|i\s+(?:just\s+)?begun|i\s+have\s+started)\b/.test(s);

  if (iFinished) {
    if ((hasPartialProgress || hasSoftPartial) && !explicitCompletion) return { status: "WATCHING" };
    return { status: "COMPLETED", completed: true };
  }
  if (iWatched) {
    // "I watched X" is ambiguous; default to WATCHING unless explicitly completed.
    if ((hasPartialProgress || hasSoftPartial) && !explicitCompletion) return { status: "WATCHING" };
    if (explicitCompletion) return { status: "COMPLETED", completed: true };
    return { status: "WATCHING" };
  }
  if (iRead) {
    if ((hasPartialProgress || hasSoftPartial) && !explicitCompletion) return { status: "READING" };
    if (explicitCompletion) return { status: "COMPLETED", completed: true };
    return { status: "READING" };
  }
  if (iStarted) {
    // "I started X" → WATCHING unless manga context
    if (/\b(read|reading|manga|manhwa|manhua|chapter|ch|volume|vol|band|kapitel)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
  if (/\b(i'?m\s+watching|i\s+am\s+watching)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(i'?m\s+reading|i\s+am\s+reading)\b/.test(s)) return { status: "READING" };
  if (/\b(completed|finished|done)\b/.test(s)) return { status: "COMPLETED", completed: true };
  if (/\b(started|begun)\b/.test(s)) {
    if (/\b(read|reading|manga|manhwa|manhua|chapter|ch|volume|vol|band|kapitel)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
  if (/\b(dropped)\b/.test(s)) return { status: "DROPPED" };
  if (/\b(paused|on hold|on-hold|hiatus)\b/.test(s)) return { status: "PAUSED" };
  if (/\b(planning|plan to watch|plan to read|ptw|ptr)\b/.test(s)) return { status: "PLANNING" };
  if (/\b(reading)\b/.test(s)) return { status: "READING" };
  if (/\b(watching)\b/.test(s)) return { status: "WATCHING" };

  // German
  if (/\b(aktuell|auf dem neuesten stand|up to date|auf dem aktuellen stand)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(ich\s+habe|ich\s+hab)\b/.test(s) && /\b(geschaut|gesehen|gelesen)\b/.test(s)) {
    if (hasPartialProgress || hasSoftPartial) {
      if (/\b(gelesen)\b/.test(s)) return { status: "READING" };
      return { status: "WATCHING" };
    }
    if (explicitCompletion) return { status: "COMPLETED", completed: true };
    // "Ich habe X geschaut" is ambiguous; default to WATCHING unless explicit completion.
    if (/\b(gelesen)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
  if (/\b(ich\s+(?:schaue|gucke|sehe)|gerade\s+am\s+schauen|am\s+schauen|schaue\s+gerade)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(ich\s+lese|gerade\s+am\s+lesen|am\s+lesen|lese\s+gerade)\b/.test(s)) return { status: "READING" };
  if (/\b(noch\s+dabei)\b/.test(s)) {
    if (/\b(lese|lesen|gelesen|manga|manhwa|manhua|kapitel|band)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
  if (/\b(fertig|abgeschlossen|beendet|zu ende|komplett)\b/.test(s)) return { status: "COMPLETED", completed: true };
  if (/\b(abgebrochen|gedroppt|droppe|droppen)\b/.test(s)) return { status: "DROPPED" };
  if (/\b(pausiert|pause|auf eis)\b/.test(s)) return { status: "PAUSED" };
  if (/\b(plane|geplant|will schauen|will sehen|möchte schauen|möchte sehen|will lesen|möchte lesen)\b/.test(s)) return { status: "PLANNING" };
  if (/\b(angefangen)\b/.test(s)) {
    if (/\b(lese|lesen|gelesen|manga|manhwa|manhua|kapitel|band)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
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

function parseRating(raw: string): number | undefined {
  const s = raw.toLowerCase();

  // Star emoji counting: ⭐⭐⭐ = 3
  const starEmojis = (raw.match(/⭐/g) ?? []).length;
  if (starEmojis >= 1 && starEmojis <= 10) return starEmojis;

  // "X/10" or "X/Y" rating format (e.g. 9/10, 8.5/10)
  const slashRating = s.match(/\b(\d{1,2}(?:\.\d)?)\s*\/\s*(\d{1,2})\b/);
  if (slashRating) {
    const num = parseFloat(slashRating[1]);
    const denom = parseInt(slashRating[2], 10);
    if (denom > 0 && num >= 0 && num <= denom) {
      return Math.round((num / denom) * 10 * 10) / 10; // Normalize to 0-10 scale
    }
  }

  // "X von 10" / "X out of 10"
  const outOfRating = s.match(/\b(\d{1,2}(?:\.\d)?)\s+(?:von|out of)\s+(\d{1,2})\b/);
  if (outOfRating) {
    const num = parseFloat(outOfRating[1]);
    const denom = parseInt(outOfRating[2], 10);
    if (denom > 0 && num >= 0 && num <= denom) {
      return Math.round((num / denom) * 10 * 10) / 10;
    }
  }

  // "eine 8" / "eine 9" (DE casual rating)
  const eineRating = s.match(/\beine?\s+(\d{1,2}(?:\.\d)?)\b/);
  if (eineRating) {
    const val = parseFloat(eineRating[1]);
    if (val >= 0 && val <= 10) return val;
  }

  // "8 Punkte" / "8 points"
  const punkteRating = s.match(/\b(\d{1,2}(?:\.\d)?)\s+(?:punkte|points?)\b/);
  if (punkteRating) {
    const val = parseFloat(punkteRating[1]);
    if (val >= 0 && val <= 10) return val;
  }

  // "8 stars" / "8 Sterne"
  const starsRating = s.match(/\b(\d{1,2}(?:\.\d)?)\s+(?:stars?|sterne?)\b/);
  if (starsRating) {
    const val = parseFloat(starsRating[1]);
    if (val >= 0 && val <= 10) return val;
  }

  return undefined;
}

function parseProgress(
  raw: string,
): Pick<
  ParsedItem,
  "progressEpisodes" | "progressChapters" | "progressVolumes" | "progressTotal" | "progressUnit" | "seasonNumber" | "episodeInSeason"
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

  // "bis Folge X" / "bei Episode X" / "bei Folge X" (DE preposition + unit)
  const bisEp = s.match(/\b(?:bis|bei)\s+(?:folge|episode|ep)\s*(\d{1,4})\b/);
  if (bisEp && !out.progressEpisodes) out.progressEpisodes = parseInt(bisEp[1], 10);
  const bisKap = s.match(/\b(?:bis|bei)\s+(?:kapitel|chapter|ch)\s*(\d{1,5})\b/);
  if (bisKap && !out.progressChapters) out.progressChapters = parseInt(bisKap[1], 10);
  const bisBand = s.match(/\b(?:bis|bei)\s+(?:band|volume|vol)\s*(\d{1,4})\b/);
  if (bisBand && !out.progressVolumes) out.progressVolumes = parseInt(bisBand[1], 10);

  // "X of Y episodes/chapters/volumes" / "X von Y Folgen/Kapitel/Bände"
  const xOfYEp = s.match(/\b(\d{1,4})\s+(?:of|von)\s+(\d{1,4})\s*(?:episodes?|folgen?|eps?)\b/);
  if (xOfYEp) {
    out.progressEpisodes = out.progressEpisodes ?? parseInt(xOfYEp[1], 10);
    out.progressTotal = parseInt(xOfYEp[2], 10);
    out.progressUnit = "episode";
  }
  const xOfYCh = s.match(/\b(\d{1,5})\s+(?:of|von)\s+(\d{1,5})\s*(?:chapters?|kapitel)\b/);
  if (xOfYCh) {
    out.progressChapters = out.progressChapters ?? parseInt(xOfYCh[1], 10);
    out.progressTotal = parseInt(xOfYCh[2], 10);
    out.progressUnit = "chapter";
  }
  const xOfYVol = s.match(/\b(\d{1,4})\s+(?:of|von)\s+(\d{1,4})\s*(?:volumes?|bände|baende|band)\b/);
  if (xOfYVol) {
    out.progressVolumes = out.progressVolumes ?? parseInt(xOfYVol[1], 10);
    out.progressTotal = parseInt(xOfYVol[2], 10);
    out.progressUnit = "volume";
  }

  // "Folge X von Y" / "Episode X of Y" (unit before numbers)
  const folgeXvonY = s.match(/\b(?:folge|episode|ep)\s*(\d{1,4})\s+(?:von|of)\s+(\d{1,4})\b/);
  if (folgeXvonY) {
    out.progressEpisodes = out.progressEpisodes ?? parseInt(folgeXvonY[1], 10);
    out.progressTotal = out.progressTotal ?? parseInt(folgeXvonY[2], 10);
    out.progressUnit = out.progressUnit ?? "episode";
  }
  const kapXvonY = s.match(/\b(?:kapitel|chapter|ch)\s*(\d{1,5})\s+(?:von|of)\s+(\d{1,5})\b/);
  if (kapXvonY) {
    out.progressChapters = out.progressChapters ?? parseInt(kapXvonY[1], 10);
    out.progressTotal = out.progressTotal ?? parseInt(kapXvonY[2], 10);
    out.progressUnit = out.progressUnit ?? "chapter";
  }

  // Infer progressUnit from what was detected
  if (!out.progressUnit) {
    if (out.progressEpisodes != null) out.progressUnit = "episode";
    else if (out.progressChapters != null) out.progressUnit = "chapter";
    else if (out.progressVolumes != null) out.progressUnit = "volume";
  }

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

// Year mention policy (product): used to disambiguate adaptations (e.g. "HxH 2011").
// Keep this small to reduce false positives on random numbers in prompts.
const YEAR_MENTION_MIN = 1960;
const YEAR_MENTION_MAX = 2030;

function isPlausibleYearMention(y: number): boolean {
  return Number.isFinite(y) && y >= YEAR_MENTION_MIN && y <= YEAR_MENTION_MAX;
}

function extractYearMention(raw: string): number | undefined {
  // Must run BEFORE stripMeta() removes parenthesized content.
  // Collect all 4-digit numbers that look like plausible anime/manga years.
  const matches: number[] = [];

  // Parenthesized years: "Hunter x Hunter (2011)"
  for (const m of raw.matchAll(/\((\d{4})\)/g)) {
    const y = Number(m[1]);
    if (isPlausibleYearMention(y)) matches.push(y);
  }

  // Standalone 4-digit years (not part of larger number)
  for (const m of raw.matchAll(/(?<!\d)(\d{4})(?!\d)/g)) {
    const y = Number(m[1]);
    if (isPlausibleYearMention(y) && !matches.includes(y)) matches.push(y);
  }

  // If multiple distinct years found (e.g. "FMA 2003 vs 2009"), ambiguous: return nothing.
  const unique = Array.from(new Set(matches));
  if (unique.length !== 1) return undefined;
  return unique[0];
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
  // Strip rating patterns so they don't pollute title search.
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s*\/\s*\d{1,2}\b/gi, " ");
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s+(?:von|out of)\s+\d{1,2}\b/gi, " ");
  s = s.replace(/\beine?\s+\d{1,2}(?:\.\d)?\b/gi, " ");
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s+(?:punkte|points?|stars?|sterne?)\b/gi, " ");
  s = s.replace(/⭐/g, " ");
  // Strip new status keywords from title.
  s = s.replace(/\b(started|begun|angefangen|noch dabei)\b/gi, " ");
  // Strip "bis/bei" progress phrases from title.
  s = s.replace(/\b(?:bis|bei)\s+(?:folge|episode|ep|kapitel|chapter|ch|band|volume|vol)\s*\d{1,5}\b/gi, " ");
  // Strip "X of/von Y" progress phrases.
  s = s.replace(/\b\d{1,5}\s+(?:of|von)\s+\d{1,5}\s*(?:episodes?|folgen?|eps?|chapters?|kapitel|volumes?|bände|baende|band)\b/gi, " ");
  // Strip standalone year mentions so they don't pollute trigram search.
  // Parenthesized years are already removed above. Keep year-only queries (e.g. manga "1984").
  s = s.replace(/\s+/g, " ").trim();
  if (!/^\d{4}$/.test(s)) {
    s = s.replace(/(?<!\d)(\d{4})(?!\d)/g, (m, yy) => {
      const y = Number(yy);
      return isPlausibleYearMention(y) ? " " : m;
    });
  }
  s = s.replace(/\s+/g, " ").trim();
  return s;
}

function detectAmbiguity(item: ParsedItem): Ambiguity {
  const s = item.raw.toLowerCase();
  const hasStatus = item.status != null;
  const hasProgress = (item.progressEpisodes != null || item.progressChapters != null || item.progressVolumes != null);
  const hasRating = item.rating != null;
  const titleContext = item.normalized || item.raw;
  const numberContext = firstNumber(item.raw);

  // "watched" / "geschaut" / "gesehen" without explicit completion signal
  // The parser defaults these to WATCHING, but the user may mean COMPLETED.
  const ambiguousWatched =
    (/\b(watched|saw|geschaut|gesehen)\b/.test(s) && !(/\b(i'?m\s+watching|i\s+am\s+watching|schaue\s+gerade|gerade\s+am\s+schauen|noch\s+dabei)\b/.test(s))) &&
    item.status === "WATCHING" &&
    !item.completed && !item.caughtUp && !item.lastEpisode &&
    !hasProgress;

  // "gelesen" / "read" without explicit completion signal
  const ambiguousRead =
    (/\b(read|gelesen)\b/.test(s) && !(/\b(i'?m\s+reading|i\s+am\s+reading|lese\s+gerade|gerade\s+am\s+lesen|noch\s+dabei)\b/.test(s))) &&
    item.status === "READING" &&
    !item.completed &&
    !hasProgress;

  if (ambiguousWatched || ambiguousRead) {
    return {
      kind: "status_unclear",
      options: ["COMPLETED", ambiguousRead ? "READING" : "WATCHING"],
      suggested_question: ambiguousRead ? "Finished or still reading?" : "Finished or still watching?",
      suggested_question_de: ambiguousRead ? "Fertig gelesen oder noch dabei?" : "Fertig geschaut oder noch dabei?",
      title_context: titleContext,
    };
  }

  // Progress number without clear unit context
  // A bare number attached to progress without a recognized unit keyword
  if (hasProgress && !item.progressUnit && !item.seasonNumber) {
    return {
      kind: "unit_unclear",
      options: ["episode", "season", "chapter", "volume"],
      suggested_question: "Which unit? Episode, season, chapter, or volume?",
      suggested_question_de: "Welche Einheit? Folge, Staffel, Kapitel oder Band?",
      title_context: titleContext,
      number_context: numberContext != null ? String(numberContext) : undefined,
    };
  }

  // Status + bare number without unit (e.g. "watched 203", "ich habe 12 gesehen").
  // Ask the user what the number refers to.
  const hasUnitKeyword = /\b(ep|episode|folge|season|staffel|chapter|ch|kapitel|volume|vol|band)\b/i.test(s);
  const numericHint =
    numberContext != null &&
    (item.yearMention == null || numberContext !== item.yearMention);
  if (hasStatus && !hasProgress && !hasRating && numericHint && !hasUnitKeyword) {
    return {
      kind: "unit_unclear",
      options: ["episode", "season", "chapter", "volume"],
      suggested_question: "Does that number mean episode, season, chapter, or volume?",
      suggested_question_de: "Meint diese Zahl Folge, Staffel, Kapitel oder Band?",
      title_context: titleContext,
      number_context: String(numberContext),
    };
  }

  // Title-only without status, progress, or rating → unclear intent
  if (!hasStatus && !hasProgress && !hasRating && item.normalized.length > 0) {
    return {
      kind: "intent_unclear",
      options: ["import", "recommend_seed"],
      suggested_question: "Add to your list, or use as a recommendation seed?",
      suggested_question_de: "Zur Liste hinzufügen oder als Empfehlungsgrundlage nutzen?",
      title_context: titleContext,
    };
  }

  return null;
}

function parseClarificationMap(input: unknown): Record<string, string> {
  if (!input || typeof input !== "object" || Array.isArray(input)) return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(input as Record<string, unknown>)) {
    if (typeof v !== "string") continue;
    const key = String(k).trim();
    const val = v.trim();
    if (!key || !val) continue;
    out[key] = val;
  }
  return out;
}

function firstNumber(raw: string): number | undefined {
  const m = raw.match(/\b(\d{1,5})\b/);
  if (!m) return undefined;
  const n = parseInt(m[1], 10);
  return Number.isFinite(n) && n > 0 ? n : undefined;
}

function applyClarification(item: ParsedItem, clarification: Record<string, string>): ParsedItem {
  if (!item.ambiguity) return item;

  const kind = item.ambiguity.kind;
  const pick = clarification[kind]?.toLowerCase();
  if (!pick) return item;

  if (kind === "status_unclear") {
    // Accept parser UI values plus common aliases.
    if (pick === "completed" || pick === "fertig") {
      item.status = "COMPLETED";
      item.completed = true;
      item.ambiguity = null;
    } else if (pick === "watching" || pick === "current" || pick === "noch dabei") {
      const lower = item.raw.toLowerCase();
      const looksLikeReading =
        item.mediaTypeHint === "MANGA" ||
        /\b(read|reading|gelesen|lese|kapitel|chapter|band|volume|manga|manhwa|manhua)\b/.test(lower);
      item.status = looksLikeReading ? "READING" : "WATCHING";
      item.completed = false;
      item.ambiguity = null;
    } else if (pick === "reading" || pick === "lesend") {
      item.status = "READING";
      item.completed = false;
      item.ambiguity = null;
    }
    return item;
  }

  if (kind === "unit_unclear") {
    const unit = pick;
    const n = firstNumber(item.raw);
    if (!n) return item;

    if (unit === "episode" || unit === "ep" || unit === "folge") {
      item.progressEpisodes = n;
      item.progressUnit = "episode";
      item.ambiguity = null;
    } else if (unit === "chapter" || unit === "ch" || unit === "kapitel") {
      item.progressChapters = n;
      item.progressUnit = "chapter";
      item.ambiguity = null;
    } else if (unit === "volume" || unit === "vol" || unit === "band") {
      item.progressVolumes = n;
      item.progressUnit = "volume";
      item.ambiguity = null;
    } else if (unit === "season" || unit === "staffel") {
      item.seasonNumber = n;
      item.progressUnit = "season";
      item.ambiguity = null;
    }
    return item;
  }

  if (kind === "intent_unclear") {
    // Parse endpoint can only return import-ready rows.
    // If user clarifies import, pin a safe default status.
    if (pick === "import") {
      item.status = item.status ?? "PLANNING";
      item.ambiguity = null;
    }
    return item;
  }

  return item;
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

  // Warmup: short-circuit before auth/rate-limit to warm the Deno isolate
  const url = new URL(req.url);
  if (url.searchParams.get("warmup") === "true") {
    return json({ ok: true });
  }

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

  const body = await req.json().catch(() => ({}));
  const text: string = String(body?.text ?? "");
  if (typeof text !== "string" || text.length > 5000) {
    return json({ error: "Text too long (max 5000 chars)" }, { status: 400 });
  }
  const scope: "anime" | "manga" | "both" = body?.scope ?? "both";
  const limitPerItem = Math.max(3, Math.min(15, Number(body?.limitPerItem ?? 10)));
  const clarification = parseClarificationMap(body?.clarification);

  const itemsRaw = splitItems(text);
  if (itemsRaw.length === 0) {
    return json({ success: true, items: [] });
  }

  // Run rate-limit check and auth verification in parallel (they are independent).
  const ip = clientIp(req);
  const [rlResult, userResult] = await Promise.all([
    client.rpc("check_concierge_rate_limit", {
      p_kind: "parse",
      p_ip: ip,
      p_window_seconds: null,
      p_max_user: null,
      p_max_ip: null,
    }),
    client.auth.getUser(),
  ]);

  const rl = rlResult.data;
  if (rl && rl.allowed === false) {
    return json(
      { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
      { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
    );
  }

  const userId = userResult.data?.user?.id ?? null;

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
    const yearMention = extractYearMention(cleaned);
    const rating = parseRating(cleaned);
    const item: ParsedItem = {
      raw: cleaned,
      normalized: stripMeta(cleaned),
      mediaTypeHint: hint,
      status: status.status,
      completed: status.completed,
      yearMention,
      rating,
      ...flags,
      ...progress,
    };
    item.ambiguity = detectAmbiguity(item);
    return applyClarification(item, clarification);
  });

  // Process all parsed items in parallel — each item searches for a different title
  // so they are fully independent of each other.
  const outItems = await Promise.all(parsed.map(async (item) => {
    try {
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

      // Run all initial search queries for this item in parallel.
      const searchLimit = Math.max(5, Math.min(limitPerItem, 12));
      const searchResults = await Promise.all(
        queries.map((q) =>
          client.rpc("search_titles", {
            p_query: q.q,
            p_media_type: mediaType,
            p_limit: searchLimit,
          }).then((res) => ({ ...res, seasonBoost: q.seasonBoost }))
        )
      );

      for (const result of searchResults) {
        if (result.error) {
          candidateError = candidateError ?? result.error.message ?? "search error";
          continue;
        }
        for (const c of (result.data ?? [])) {
          const key = `${c.media_type}:${c.media_id}`;
          const baseScore = typeof c.score === "number" ? c.score : 0;
          const seasonBoost = result.seasonBoost && item.seasonNumber ? seasonMatchBoost(String(c.title_raw ?? ""), item.seasonNumber) : 0;
          const overlapBoost = tokenOverlapBoost(item.normalized, String(c.title_raw ?? ""));
          const penalty = variantPenalty(item.raw, { title_raw: c.title_raw, variant_type: c.variant_type });
          const aliasBoost =
            aliasTarget && aliasTarget.media_type === c.media_type && Number(aliasTarget.media_id) === Number(c.media_id) ? 0.80 : 0;
          const yearBoost = item.yearMention && typeof c.year === "number" && c.year === item.yearMention ? 0.25 : 0;
          // Allow a tiny score > 1 so "Season 2" variants can beat the base title when both match at 1.0.
          const adjusted = Math.max(0, Math.min(1.25, baseScore + seasonBoost + overlapBoost + aliasBoost + yearBoost - penalty));
          const existing = merged.get(key);
          if (!existing || (existing.score ?? 0) < adjusted) {
            merged.set(key, { ...c, score: adjusted });
          }
        }
      }

      const mergedCandidates = Array.from(merged.values())
        .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
        .slice(0, limitPerItem);

      // Second pass: if confidence is low, try denoised keyword queries in parallel.
      const bestScore = typeof mergedCandidates[0]?.score === "number" ? mergedCandidates[0].score : 0;
      if (bestScore < 0.55 && item.normalized.length >= 8) {
        const denoisedQueries = buildDenoisedQueries(item.normalized);
        const denoisedResults = await Promise.all(
          denoisedQueries.map((q) =>
            client.rpc("search_titles", {
              p_query: q,
              p_media_type: mediaType,
              p_limit: searchLimit,
            })
          )
        );

        for (const { data: extra, error } of denoisedResults) {
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

      // --- Import reconciliation: look up existing user list entry ---
      let existingEntry: {
        media_type: string;
        media_id: number;
        status: string;
        progress_episodes: number | null;
        progress_chapters: number | null;
        progress_volumes: number | null;
        rating: number | null;
        updated_at: string;
      } | null = null;

      const topCandidate = finalCandidates[0] ?? null;
      const topScore = typeof topCandidate?.score === "number" ? topCandidate.score : 0;

      if (userId && topCandidate && topScore >= 0.60) {
        try {
          const cMediaType: string = topCandidate.media_type;
          const cMediaId: number = Number(topCandidate.media_id);
          // user_id in anime_user_lists/manga_user_lists is TEXT, auth.uid() is UUID — cast to text
          const userIdText = String(userId);

          if (cMediaType === "ANIME") {
            const { data: row } = await client
              .from("anime_user_lists")
              .select("list_type,progress,rating,updated_at")
              .eq("user_id", userIdText)
              .eq("anime_id", cMediaId)
              .maybeSingle();
            if (row) {
              existingEntry = {
                media_type: "ANIME",
                media_id: cMediaId,
                status: row.list_type ?? "PLANNING",
                progress_episodes: row.progress ?? null,
                progress_chapters: null,
                progress_volumes: null,
                rating: row.rating ?? null,
                updated_at: row.updated_at ?? new Date().toISOString(),
              };
            }
          } else if (cMediaType === "MANGA") {
            const { data: row } = await client
              .from("manga_user_lists")
              .select("list_type,progress,rating,updated_at")
              .eq("user_id", userIdText)
              .eq("manga_id", cMediaId)
              .maybeSingle();
            if (row) {
              existingEntry = {
                media_type: "MANGA",
                media_id: cMediaId,
                status: row.list_type ?? "PLANNING",
                progress_episodes: null,
                progress_chapters: row.progress ?? null,
                progress_volumes: null,
                rating: row.rating ?? null,
                updated_at: row.updated_at ?? new Date().toISOString(),
              };
            }
          }
        } catch {
          // best-effort: if lookup fails, treat as no existing entry
        }
      }

      return {
        raw: item.raw,
        normalized: item.normalized,
        parsed: {
          mediaTypeHint: item.mediaTypeHint ?? null,
          status: item.status ?? null,
          progressEpisodes: item.progressEpisodes ?? null,
          progressChapters: item.progressChapters ?? null,
          progressVolumes: item.progressVolumes ?? null,
          progressTotal: item.progressTotal ?? null,
          progressUnit: item.progressUnit ?? null,
          seasonNumber: item.seasonNumber ?? null,
          episodeInSeason: item.episodeInSeason ?? null,
          caughtUp: item.caughtUp ?? null,
          lastEpisode: item.lastEpisode ?? null,
          completed: item.completed ?? null,
          yearMention: item.yearMention ?? null,
          rating: item.rating ?? null,
        },
        ambiguity: item.ambiguity ?? null,
        candidates: finalCandidates,
        candidateError,
        aliasNorm: userId ? normalizeAliasKey(item.raw) : null,
        existing_entry: existingEntry,
      };
    } catch (err) {
      // Per-item error handling: don't let one item's failure abort others.
      return {
        raw: item.raw,
        normalized: item.normalized,
        parsed: {
          mediaTypeHint: item.mediaTypeHint ?? null,
          status: item.status ?? null,
          progressEpisodes: item.progressEpisodes ?? null,
          progressChapters: item.progressChapters ?? null,
          progressVolumes: item.progressVolumes ?? null,
          progressTotal: item.progressTotal ?? null,
          progressUnit: item.progressUnit ?? null,
          seasonNumber: item.seasonNumber ?? null,
          episodeInSeason: item.episodeInSeason ?? null,
          caughtUp: item.caughtUp ?? null,
          lastEpisode: item.lastEpisode ?? null,
          completed: item.completed ?? null,
          yearMention: item.yearMention ?? null,
          rating: item.rating ?? null,
        },
        ambiguity: item.ambiguity ?? null,
        candidates: [],
        candidateError: err instanceof Error ? err.message : "unknown error",
        aliasNorm: userId ? normalizeAliasKey(item.raw) : null,
        existing_entry: null,
      };
    }
  }));

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
  year?: number;
  format?: string;
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
  yearMention?: number | null;
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

/** Strip common LLM prompt-injection patterns from user-supplied text before interpolation. */
function sanitizeForLLM(text: string): string {
  return text
    // Strip common injection patterns
    .replace(/\b(ignore|disregard|forget)\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?|context)/gi, '[filtered]')
    .replace(/\b(you\s+are\s+now|new\s+instructions?|system\s*:)/gi, '[filtered]')
    .replace(/\b(act\s+as|pretend\s+(to\s+be|you\s+are)|role\s*play)/gi, '[filtered]')
    // Strip markdown/HTML injection attempts
    .replace(/```[\s\S]*?```/g, '')
    .replace(/<[^>]+>/g, '')
    // Limit length
    .slice(0, 2000)
    // Trim whitespace
    .trim();
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
  items: Array<{ raw: string; parsed: Parsed; options: Array<{ id: string; title: string; variant?: string; score?: number; year?: number; format?: string }> }>;
}): Promise<{ resolved: any | null; usageTotal: number | null }> {
  const url = "https://api.groq.com/openai/v1/chat/completions";

  const system = `Return JSON only: {"choices":[{"i":0,"pick":0,"confidence":0.0,"reason":""}]}`;

  const user = `You are resolving user-entered anime/manga titles to one of the provided options.

Rules:
- You MUST pick from the options for each item: pick is an integer index into that item's options array (0-based).
- If none match, set pick to -1.
- If the user explicitly says watched/saw/schaue/geschaut => prefer ANIME; read/lese/gelesen => prefer MANGA.
- If seasonNumber is present, prefer an option whose title includes that season (e.g., "Season 2", "2nd Season") IF the base title also matches.
- If the user mentions a year (yearMention in parsed), prefer the option whose year matches that year.
- DO NOT hallucinate. Only choose from options.
- Output must be valid JSON ONLY, matching:
  {"choices":[{"i":number,"pick":number,"confidence":number,"reason":string}...]}

Items:
${opts.items
  .map((it, idx) =>
    `#${idx} raw="${sanitizeForLLM(it.raw)}" parsed=${JSON.stringify(it.parsed ?? {})}\noptions:\n${it.options
      .map((o, j) => `  [${j}] ${o.id} ${o.title}${o.year ? ` [${o.year}]` : ""}${o.format ? ` ${o.format}` : ""}${o.variant ? ` (${o.variant})` : ""}${typeof o.score === "number" ? ` score=${o.score.toFixed(3)}` : ""}`)
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
          year: typeof c.year === "number" ? c.year : undefined,
          format: typeof c.format === "string" && c.format ? c.format : undefined,
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
        chosen: opt ? { id: opt.id, title: opt.title, year: opt.year ?? null, format: opt.format ?? null } : null,
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
  // Optional linkage to a pinned curated rail (per media type).
  // Example config:
  //   "rail_id": {"anime":"classics_anime","manga":"classics_manga"}
  rail_id?: string | { anime?: string; manga?: string; both?: string };
  required_genres?: string[];
  exclude_genres?: string[];
  min_score?: number;
  min_popularity?: number;
  max_popularity?: number;
  exclude_formats?: string[];
  classic_year_max?: number;
};

type ModePick = { id: string; title: string; confidence: number; reason: string };

type UserConstraints = {
  excluded_genres: string[];
  format: string | null;       // "MOVIE" | "SHORT_FORM" | "ONA" | "OVA" | null
  max_episodes: number | null;
  min_episodes: number | null;
  year_min: number | null;
  year_max: number | null;
  why: string[];
};

type CandidateRow = { media_id: number; match_count?: number | null; score?: number | null };

// Penalties for known weak/sparse mode inventories.
// Keeps routing deterministic while reducing accidental selection of weaker rails
// unless user intent is explicit.
const MODE_HEALTH_PENALTIES: Record<string, number> = {
  historical: 2.8,
  mecha: 2.6,
  school_coming_of_age: 2.4,
  shoujo_josei: 2.2,
  mystery_detective: 1.4,
  music_performance: 1.2,
};

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

function stableBucket(input: string): number {
  // djb2-style deterministic hash, then map into [0, 99].
  let hash = 5381;
  for (let i = 0; i < input.length; i++) {
    hash = ((hash << 5) + hash) + input.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash) % 100;
}

function inferRequestMarket(req: Request): string {
  const cfCountry = req.headers.get("cf-ipcountry")?.trim().toUpperCase();
  if (cfCountry && /^[A-Z]{2}$/.test(cfCountry)) return cfCountry;

  const acceptLanguage = req.headers.get("accept-language") ?? "";
  const first = acceptLanguage.split(",")[0]?.trim() ?? "";
  const region = first.match(/-[A-Za-z]{2}\b/)?.[0]?.slice(1).toUpperCase();
  if (region && /^[A-Z]{2}$/.test(region)) return region;
  return "US";
}

type Locale = "en" | "de";

function inferLocale(req: Request, market: string): Locale {
  const m = (market || "").trim().toUpperCase();
  if (["DE", "AT", "CH"].includes(m)) return "de";
  const acceptLanguage = (req.headers.get("accept-language") ?? "").trim().toLowerCase();
  if (acceptLanguage.startsWith("de")) return "de";
  return "en";
}

type CuratedCopy = {
  displayTitle: string;
  displaySubtitle?: string;
  // A short axis used for deterministic curator notes.
  tasteAxis: { en: string; de: string };
};

const CURATED_MODE_COPY: Record<string, CuratedCopy> = {
  premium_picks: {
    displayTitle: "The Cut",
    displaySubtitle: "High-confidence picks, new to you",
    tasteAxis: { en: "craft-forward picks", de: "Handwerk und Qualität" },
  },
  gateway_start_here: {
    displayTitle: "Start Here",
    displaySubtitle: "A clean entry point",
    tasteAxis: { en: "approachable, high-signal stories", de: "zugänglich und treffsicher" },
  },
  premium_action: {
    displayTitle: "Action With Craft",
    displaySubtitle: "Clean choreography, real momentum",
    tasteAxis: { en: "momentum and clarity", de: "Tempo und Klarheit" },
  },
  premium_comedy_grownup: {
    displayTitle: "Comedy With Bite",
    displaySubtitle: "Smart, dry, character-led",
    tasteAxis: { en: "dry wit and precision", de: "trockener Witz und Präzision" },
  },
  cozy_comfort: {
    displayTitle: "Soft Evenings",
    displaySubtitle: "Gentle, restorative stories",
    tasteAxis: { en: "gentle pacing", de: "sanft und wohltuend" },
  },
  dark_serious: {
    displayTitle: "Dark, Not Empty",
    displaySubtitle: "Serious tone, strong craft",
    tasteAxis: { en: "serious tone", de: "ernst, aber mit Substanz" },
  },
  hidden_gems: {
    displayTitle: "Underseen",
    displaySubtitle: "Quiet classics, overlooked hits",
    tasteAxis: { en: "under-discussed brilliance", de: "unter dem Radar" },
  },
  classics_expanded: {
    displayTitle: "The Canon",
    displaySubtitle: "Anchors worth knowing",
    tasteAxis: { en: "foundational works", de: "Grundpfeiler" },
  },
  short_one_season: {
    displayTitle: "Short, Complete",
    displaySubtitle: "One season, clean finish",
    tasteAxis: { en: "tight structure", de: "straff und abgeschlossen" },
  },
  movie_night: {
    displayTitle: "One Perfect Film",
    displaySubtitle: "Stand-alone nights",
    tasteAxis: { en: "one-shot impact", de: "ein Abend, ein Treffer" },
  },
  romance_serious: {
    displayTitle: "Romance That Lands",
    displaySubtitle: "Earned, not fluffy",
    tasteAxis: { en: "emotional weight", de: "emotionale Wucht" },
  },
  romcom: {
    displayTitle: "Light, Sharp Romance",
    displaySubtitle: "Warmth with timing",
    tasteAxis: { en: "warm timing", de: "warm und pointiert" },
  },
  fantasy_non_isekai: {
    displayTitle: "Fantasy With Texture",
    displaySubtitle: "Myth, wonder, discipline",
    tasteAxis: { en: "mythic texture", de: "Mythos und Textur" },
  },
  isekai: {
    displayTitle: "Other Worlds, Cleanly",
    displaySubtitle: "Escapism with craft",
    tasteAxis: { en: "clear escapism", de: "klare Eskapismus-Linie" },
  },
  sports: {
    displayTitle: "Competition, Pure",
    displaySubtitle: "Training arcs that work",
    tasteAxis: { en: "earned momentum", de: "verdientes Momentum" },
  },
  scifi: {
    displayTitle: "Ideas With Heat",
    displaySubtitle: "Speculation, not noise",
    tasteAxis: { en: "clean sci-fi ideas", de: "klare Sci-Fi-Ideen" },
  },
  horror_supernatural: {
    displayTitle: "Unease, Done Right",
    displaySubtitle: "Atmosphere over gore",
    tasteAxis: { en: "atmosphere and tension", de: "Atmosphäre und Spannung" },
  },
  mecha: {
    displayTitle: "Steel and Stakes",
    displaySubtitle: "Big machines, real themes",
    tasteAxis: { en: "scale and conviction", de: "Groesse und Haltung" },
  },
  mystery_detective: {
    displayTitle: "Cases With Discipline",
    displaySubtitle: "Puzzles that hold",
    tasteAxis: { en: "sharp mystery logic", de: "scharfe Logik" },
  },
  music_performance: {
    displayTitle: "Sound and Feeling",
    displaySubtitle: "Performance that moves",
    tasteAxis: { en: "rhythm and emotion", de: "Rhythmus und Gefühl" },
  },
  historical: {
    displayTitle: "Period Weight",
    displaySubtitle: "History with texture",
    tasteAxis: { en: "weight and texture", de: "Gewicht und Textur" },
  },
  school_coming_of_age: {
    displayTitle: "Coming-of-Age, Quietly",
    displaySubtitle: "Youth, rendered cleanly",
    tasteAxis: { en: "intimate growth", de: "intimes Wachsen" },
  },
  shoujo_josei: {
    displayTitle: "Emotion, With Clarity",
    displaySubtitle: "Character-first, precise",
    tasteAxis: { en: "emotional clarity", de: "emotionale Klarheit" },
  },
  similar_to_seed: {
    displayTitle: "In the Same Orbit",
    displaySubtitle: "Close to your anchor",
    tasteAxis: { en: "adjacent craft", de: "nahe am Anker" },
  },
};

function softenFallbackTitle(raw: string): string {
  const t = String(raw ?? "").trim();
  if (!t) return "Selections";
  return t
    .replace(/\bpremium\b/gi, "")
    .replace(/\(.*?\)/g, "")
    .replace(/\s*\/\s*/g, " · ")
    .replace(/\s+/g, " ")
    .trim();
}

function curatedCopyForMode(locale: Locale, modeId: string, modeTitleFallback: string): { displayTitle: string; displaySubtitle?: string; tasteAxis: string } {
  const c = CURATED_MODE_COPY[modeId];
  if (!c) {
    const softened = softenFallbackTitle(modeTitleFallback);
    return {
      displayTitle: softened,
      displaySubtitle: locale === "de" ? "Kuratiert, neu für dich" : "Curated, new to you",
      tasteAxis: locale === "de" ? "Ton und Handwerk" : "tone and craft",
    };
  }
  const deTitles: Record<string, string> = {
    // Hand-authored DE titles (do not auto-translate).
    premium_picks: "Die Auswahl",
    premium_comedy_grownup: "Komödie mit Biss",
    cozy_comfort: "Sanfte Abende",
    dark_serious: "Dunkel, nicht leer",
    hidden_gems: "Unterschätzt",
    classics_expanded: "Der Kanon",
    short_one_season: "Kurz, abgeschlossen",
    movie_night: "Ein perfekter Film",
    romance_serious: "Romantik, die trifft",
    romcom: "Leicht, aber scharf",
    fantasy_non_isekai: "Fantasy mit Textur",
    isekai: "Andere Welten, sauber",
    sports: "Wettkampf, pur",
    scifi: "Ideen mit Hitze",
    horror_supernatural: "Unbehagen, richtig",
    mecha: "Stahl und Einsatz",
    mystery_detective: "Fälle mit Disziplin",
    music_performance: "Klang und Gefühl",
    historical: "Zeitgewicht",
    school_coming_of_age: "Coming-of-Age, leise",
    shoujo_josei: "Gefühl, mit Klarheit",
    gateway_start_here: "Hier anfangen",
    premium_action: "Action mit Handwerk",
    similar_to_seed: "In derselben Umlaufbahn",
  };
  const deSubtitles: Record<string, string> = {
    premium_picks: "Sichere Picks, neu für dich",
    premium_comedy_grownup: "Trocken, klug, figurengetrieben",
    cozy_comfort: "Ruhig, warm, erholsam",
    dark_serious: "Ernst, aber mit Substanz",
    hidden_gems: "Übersehenes, das sitzt",
    classics_expanded: "Anker, die man kennt",
    short_one_season: "Eine Staffel, sauberer Abschluss",
    movie_night: "Standalone-Abende",
    romance_serious: "Verdient, nicht fluffig",
    romcom: "Wärme mit Timing",
    fantasy_non_isekai: "Mythos, Staunen, Disziplin",
    isekai: "Eskapismus mit Handwerk",
    sports: "Training, das funktioniert",
    scifi: "Spekulation, nicht Lärm",
    horror_supernatural: "Atmosphäre statt Gore",
    mecha: "Große Maschinen, echte Themen",
    mystery_detective: "Rätsel, die halten",
    music_performance: "Performance, die bewegt",
    historical: "Geschichte mit Textur",
    school_coming_of_age: "Jugend, klar gezeichnet",
    shoujo_josei: "Figuren zuerst, präzise",
    gateway_start_here: "Ein sauberer Einstieg",
    premium_action: "Choreo, Tempo, Klarheit",
    similar_to_seed: "Nahe an deinem Anker",
  };
  return {
    displayTitle: locale === "de" ? (deTitles[modeId] ?? c.displayTitle) : c.displayTitle,
    displaySubtitle: locale === "de" ? (deSubtitles[modeId] ?? c.displaySubtitle) : c.displaySubtitle,
    tasteAxis: locale === "de" ? c.tasteAxis.de : c.tasteAxis.en,
  };
}

function clampWords(s: string, maxWords: number): string {
  const parts = String(s ?? "").trim().split(/\s+/).filter(Boolean);
  if (parts.length <= maxWords) return parts.join(" ");
  return parts.slice(0, maxWords).join(" ");
}

function buildCuratorNote(args: {
  locale: Locale;
  primaryModeId: string;
  primaryModeTitle: string;
  constraints: UserConstraints;
  ragUsed: boolean;
  seedTitle?: string | null;
  avoidedGenres?: string[];
}): string {
  const { locale, constraints, primaryModeId, primaryModeTitle } = args;
  const copy = curatedCopyForMode(locale, primaryModeId, primaryModeTitle);

  const constraintBits: string[] = [];
  if (constraints.format === "MOVIE") constraintBits.push(locale === "de" ? "nur Filme" : "movie-only");
  if (constraints.max_episodes != null) constraintBits.push(locale === "de" ? "kurz gehalten" : "kept it short");
  if (constraints.year_min != null || constraints.year_max != null) {
    const a = constraints.year_min != null ? String(constraints.year_min) : "";
    const b = constraints.year_max != null ? String(constraints.year_max) : "";
    const span = a && b ? `${a}-${b}` : (a ? `ab ${a}` : (b ? `bis ${b}` : ""));
    if (span) constraintBits.push(locale === "de" ? `im Zeitraum ${span}` : `within ${span}`);
  }
  if (constraints.excluded_genres.length > 0) {
    const g = constraints.excluded_genres.slice(0, 2).join(locale === "de" ? " und " : " and ");
    constraintBits.push(locale === "de" ? `ohne ${g}` : `avoiding ${g}`);
  }

  const constraintPhrase = constraintBits.length
    ? constraintBits[0]
    : (locale === "de" ? "sauber gefiltert" : "cleanly filtered");

  const personalPhrase = (() => {
    if (args.ragUsed && args.seedTitle) {
      const t = clampWords(String(args.seedTitle), 6);
      return locale === "de" ? `in der Nähe von ${t}` : `near ${t}`;
    }
    return locale === "de" ? "neu für dich" : "new to you";
  })();

  return locale === "de"
    ? `Ich habe ${constraintPhrase} beachtet, in Richtung ${copy.tasteAxis} geneigt und ${personalPhrase} priorisiert.`
    : `I kept it ${constraintPhrase}, leaned toward ${copy.tasteAxis}, and prioritized ${personalPhrase}.`;
}

/** Strip common LLM prompt-injection patterns from user-supplied text before interpolation. */
function sanitizeForLLM(text: string): string {
  return text
    // Strip common injection patterns
    .replace(/\b(ignore|disregard|forget)\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?|context)/gi, '[filtered]')
    .replace(/\b(you\s+are\s+now|new\s+instructions?|system\s*:)/gi, '[filtered]')
    .replace(/\b(act\s+as|pretend\s+(to\s+be|you\s+are)|role\s*play)/gi, '[filtered]')
    // Strip markdown/HTML injection attempts
    .replace(/```[\s\S]*?```/g, '')
    .replace(/<[^>]+>/g, '')
    // Limit length
    .slice(0, 2000)
    // Trim whitespace
    .trim();
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
    let rail_id: ConciergeMode["rail_id"] | undefined = undefined;
    const rid = (r as any).rail_id;
    if (typeof rid === "string" && rid.trim()) {
      rail_id = rid.trim();
    } else if (rid && typeof rid === "object") {
      const anime = typeof (rid as any).anime === "string" ? (rid as any).anime.trim() : "";
      const manga = typeof (rid as any).manga === "string" ? (rid as any).manga.trim() : "";
      const both = typeof (rid as any).both === "string" ? (rid as any).both.trim() : "";
      rail_id = {
        ...(anime ? { anime } : {}),
        ...(manga ? { manga } : {}),
        ...(both ? { both } : {}),
      };
    }
    out.push({
      id,
      title,
      synonyms: safeStringArray((r as any).synonyms),
      rail_id,
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
  // Matches the v3 migration (20260206100000_concierge_modes_v3_expanded).
  return [
    // ── Existing 8 modes (enriched synonyms) ──
    {
      id: "premium_picks",
      title: "Premium Picks",
      synonyms: ["something good", "recommend something", "surprise me", "premium", "best", "top tier", "what should i watch", "anything good", "just pick something", "quality"],
      min_score: 75,
      min_popularity: 2500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "gateway_start_here",
      title: "Start Here",
      synonyms: ["first anime", "first manga", "where do i start", "getting into anime", "getting into manga", "beginner", "new to anime", "new to manga", "gateway", "never watched anime"],
      rail_id: { anime: "gateway_anime", manga: "gateway_manga" },
    },
    {
      id: "premium_action",
      title: "Premium Action",
      synonyms: ["action", "hype action", "action premium", "best action", "sakuga", "fight scenes", "battle", "tournament", "shounen", "epic fights", "adrenaline"],
      required_genres: ["Action"],
      min_score: 75,
      min_popularity: 3500,
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "premium_comedy_grownup",
      title: "Premium Comedy (grown-up)",
      synonyms: ["funny but not childish", "grown up comedy", "adult humor", "smart comedy", "witzig aber nicht kindisch", "sitcom", "parody", "satire", "clever humor", "comedy for adults"],
      required_genres: ["Comedy"],
      min_score: 75,
      min_popularity: 3500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "cozy_comfort",
      title: "Cozy / Comfort",
      synonyms: ["cozy", "comfort", "chill", "relax", "healing", "iyashikei", "gemütlich", "wholesome", "feel good", "heartwarming", "warm", "gentle", "peaceful"],
      required_genres: ["Slice of Life"],
      min_score: 70,
      min_popularity: 1200,
      exclude_formats: ["MUSIC"],
    },
    {
      id: "dark_serious",
      title: "Dark / Serious",
      synonyms: ["dark", "serious", "mature", "grown up", "not childish", "psychological", "thriller", "mind game", "seinen", "gore", "violent", "gritty", "brutal", "mind bending"],
      required_genres: ["Drama", "Thriller", "Psychological", "Mystery"],
      min_score: 78,
      min_popularity: 2500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "hidden_gems",
      title: "Hidden Gems",
      synonyms: ["hidden gems", "underrated", "less known", "something new", "new to me", "overlooked", "sleeper", "cult", "niche", "off the beaten path"],
      min_score: 78,
      max_popularity: 45000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "classics_expanded",
      title: "Classics (expanded)",
      synonyms: ["classic", "classics", "must watch", "essentials", "goat", "greatest of all time", "old school", "retro", "90s anime", "80s anime", "iconic", "all time best"],
      rail_id: { anime: "classics_anime", manga: "classics_manga" },
      classic_year_max: 2012,
      min_score: 80,
      min_popularity: 1500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    // ── 6 new modes ──
    {
      id: "short_one_season",
      title: "Short & Complete",
      synonyms: ["short", "one season", "12 episodes", "13 episodes", "quick watch", "binge", "one cour", "single season", "short anime"],
      min_score: 74,
      min_popularity: 2000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC", "MOVIE", "ONA"],
    },
    {
      id: "movie_night",
      title: "Movie Night",
      synonyms: ["movie", "movies", "film", "anime movie", "movie night", "feature film", "standalone movie"],
      min_score: 76,
      min_popularity: 2000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV", "TV_SHORT", "SPECIAL", "MUSIC", "ONA", "OVA"],
    },
    {
      id: "romance_serious",
      title: "Romance (serious)",
      synonyms: ["serious romance", "love story", "romantic drama", "romance drama", "emotional romance", "bittersweet", "heartbreak", "romance not comedy", "deep romance"],
      required_genres: ["Romance", "Drama"],
      min_score: 74,
      min_popularity: 2000,
      exclude_genres: ["Kids", "Comedy"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "romcom",
      title: "Romcom",
      synonyms: ["romcom", "romantic comedy", "rom com", "funny romance", "lighthearted romance", "love comedy", "cute romance", "fluffy", "sweet romance"],
      required_genres: ["Romance", "Comedy"],
      min_score: 72,
      min_popularity: 2000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "fantasy_non_isekai",
      title: "Fantasy (no isekai)",
      synonyms: ["fantasy", "high fantasy", "swords and sorcery", "magic", "epic fantasy", "fantasy no isekai", "traditional fantasy", "pure fantasy"],
      required_genres: ["Fantasy"],
      min_score: 74,
      min_popularity: 2000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    {
      id: "isekai",
      title: "Isekai",
      synonyms: ["isekai", "transported to another world", "reincarnated", "another world", "reborn", "other world", "parallel world", "summoned to another world", "truck-kun"],
      required_genres: ["Fantasy", "Adventure"],
      min_score: 72,
      min_popularity: 2500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
    },
    // ── 3 additional modes (Phase 1 expansion) ──
    {
      id: "sports",
      title: "Sports",
      synonyms: ["sports", "sport", "basketball", "soccer", "football", "volleyball", "boxing", "tennis", "baseball", "cycling", "running", "swimming", "haikyuu", "blue lock", "kuroko"],
      required_genres: ["Sports"],
      min_score: 72,
      min_popularity: 1500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
      rail_id: { anime: "sports_anime", manga: "sports_manga" },
    },
    {
      id: "scifi",
      title: "Sci-Fi",
      synonyms: ["sci-fi", "science fiction", "scifi", "cyberpunk", "space", "futuristic", "dystopian", "robots", "space opera", "mecha"],
      required_genres: ["Sci-Fi"],
      min_score: 74,
      min_popularity: 2000,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
      rail_id: { anime: "scifi_anime", manga: "scifi_manga" },
    },
    {
      id: "horror_supernatural",
      title: "Horror & Supernatural",
      synonyms: ["horror", "scary", "creepy", "supernatural", "ghost", "demon", "occult", "vampire", "zombie", "curse", "haunted", "junji ito"],
      required_genres: ["Horror", "Supernatural"],
      min_score: 70,
      min_popularity: 1500,
      exclude_genres: ["Kids"],
      exclude_formats: ["TV_SHORT", "SPECIAL", "MUSIC"],
      rail_id: { anime: "horror_supernatural_anime", manga: "horror_supernatural_manga" },
    },
  ];
}

const GERMAN_VIBE_FORMS: Record<string, string> = {
  "düsteres": "düster", "düstere": "düster", "düsterem": "düster", "düsterer": "düster", "düsteren": "düster",
  "lustiges": "lustig", "lustige": "lustig", "lustigem": "lustig", "lustiger": "lustig", "lustigen": "lustig",
  "gemütliches": "gemütlich", "gemütliche": "gemütlich", "gemütlichem": "gemütlich",
  "ernstes": "ernst", "ernste": "ernst", "ernstem": "ernst", "ernster": "ernst",
  "gruseliges": "gruselig", "gruselige": "gruselig", "gruseligem": "gruselig",
  "romantisches": "romantisch", "romantische": "romantisch", "romantischem": "romantisch",
  "historisches": "historisch", "historische": "historisch", "historischem": "historisch",
  "witziges": "witzig", "witzige": "witzig", "witzigem": "witzig",
  "entspannendes": "entspannend", "entspannende": "entspannend",
  "unheimliches": "unheimlich", "unheimliche": "unheimlich",
  "legendäres": "legendär", "legendäre": "legendär",
  "übernatürliches": "übernatürlich", "übernatürliche": "übernatürlich",
};

function normalizeUmlauts(s: string): string {
  return s.replace(/ü/g, "ue").replace(/ö/g, "oe").replace(/ä/g, "ae").replace(/ß/g, "ss")
          .replace(/Ü/g, "Ue").replace(/Ö/g, "Oe").replace(/Ä/g, "Ae");
}

function normalizeGermanVibeWords(text: string): string {
  let result = text.toLowerCase();
  for (const [inflected, base] of Object.entries(GERMAN_VIBE_FORMS)) {
    result = result.replace(new RegExp(`\\b${inflected}\\b`, "g"), base);
  }
  return result;
}

function scoreMode(text: string, mode: ConciergeMode, inferredGenres: string[], excludedGenres: string[] = [], userConstraints?: UserConstraints): { score: number; reason: string } {
  const t = normalizeText(text);
  const tNorm = normalizeUmlauts(normalizeGermanVibeWords(text));
  let score = 0;
  let reason = "";

  const synonyms = mode.synonyms ?? [];
  for (const syn of synonyms) {
    const s = normalizeText(syn);
    if (!s) continue;
    if (t.includes(s) || normalizeUmlauts(normalizeGermanVibeWords(t)).includes(normalizeUmlauts(normalizeGermanVibeWords(s)))) {
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

  // Penalize modes whose core genres are excluded by user (e.g. "no romance" suppresses romcom).
  const exclLower = new Set(excludedGenres.map((g) => g.toLowerCase()));
  const exclOverlap = req.filter((g) => exclLower.has(g.toLowerCase()));
  if (exclOverlap.length > 0) {
    score -= 5 * exclOverlap.length;
  }

  // Classic intent boosts the classics mode and slightly downweights gimmick modes.
  const wantsClassic = /\b(classic|classics|must watch|essentials|goat|greatest|retro|old school|oldschool|vintage|80s|90s|klassiker|klassisch|legendaer|meisterwerk|muss man gesehen haben)\b/i.test(tNorm);
  if (wantsClassic && mode.id.includes("classic")) {
    score += 3;
    if (!reason) reason = "classic intent";
  }
  const wantsHidden = /\b(hidden gem|underrated|less known|new to me|surprise|geheimtipp|unterschaetzt|unbekannt|wenig bekannt)\b/i.test(tNorm);
  if (wantsHidden && mode.id.includes("hidden")) {
    score += 3;
    if (!reason) reason = "hidden gems intent";
  }

  // Cheap maturity heuristic.
  const mature = /\b(not childish|grown[- ]?up|mature|serious|dark)\b/i.test(tNorm);
  if (mature && (mode.id.includes("grown") || mode.id.includes("dark"))) {
    score += 2;
    if (!reason) reason = "mature tone";
  }

  // Movie intent.
  const wantsMovie = /\b(movie|film|filme|movie night|filmabend|kinofilm)\b/i.test(tNorm);
  if (wantsMovie && mode.id === "movie_night") {
    score += 3;
    if (!reason) reason = "movie intent";
  }

  // Short/binge intent.
  const wantsShort = /\b(short|one season|quick watch|binge|one cour|12 ep|13 ep|kurz|eine staffel|1 staffel|schnell|durchschauen|kurze serie|kurz und gut)\b/i.test(tNorm);
  if (wantsShort && mode.id === "short_one_season") {
    score += 3;
    if (!reason) reason = "short series intent";
  }

  // Isekai intent (boost isekai, penalize fantasy_non_isekai).
  const wantsIsekai = /\b(isekai|reincarnated|another world|reborn|truck[- ]?kun)\b/i.test(tNorm);
  if (wantsIsekai && mode.id === "isekai") {
    score += 3;
    if (!reason) reason = "isekai intent";
  }
  if (wantsIsekai && mode.id === "fantasy_non_isekai") {
    score -= 4; // suppress non-isekai fantasy when user explicitly wants isekai
  }

  // "No isekai" intent (boost fantasy_non_isekai, penalize isekai).
  const noIsekai = /\b(no isekai|not isekai|ohne isekai|nicht isekai|kein isekai|fantasy no isekai|non[- ]?isekai)\b/i.test(tNorm);
  if (noIsekai && mode.id === "fantasy_non_isekai") {
    score += 4;
    if (!reason) reason = "non-isekai intent";
  }
  if (noIsekai && mode.id === "isekai") {
    score -= 4;
  }

  // Romance sub-type disambiguation.
  const wantsRomcom = /\b(romcom|rom com|romantic comedy|funny romance|cute romance|fluffy|romantische komoedie|lustige romanze)\b/i.test(tNorm);
  if (wantsRomcom && mode.id === "romcom") {
    score += 3;
    if (!reason) reason = "romcom intent";
  }
  if (wantsRomcom && mode.id === "romance_serious") {
    score -= 2;
  }
  const wantsSeriousRomance = /\b(serious romance|romance drama|heartbreak|bittersweet|deep romance|ernste romanze|liebesgeschichte|herzschmerz)\b/i.test(tNorm);
  if (wantsSeriousRomance && mode.id === "romance_serious") {
    score += 3;
    if (!reason) reason = "serious romance intent";
  }
  if (wantsSeriousRomance && mode.id === "romcom") {
    score -= 2;
  }

  // Sports intent.
  const wantsSports = /\b(sports?|soccer|basketball|volleyball|boxing|tennis|baseball|haikyuu|blue lock|kuroko|fussball)\b/i.test(tNorm);
  if (wantsSports && mode.id === "sports") {
    score += 3;
    if (!reason) reason = "sports intent";
  }

  // Sci-fi intent.
  const wantsScifi = /\b(sci[- ]?fi|scifi|science fiction|cyberpunk|space|futuristic|dystopian|space opera|mecha|weltraum|zukunft|roboter)\b/i.test(tNorm);
  if (wantsScifi && mode.id === "scifi") {
    score += 3;
    if (!reason) reason = "sci-fi intent";
  }

  // Horror/supernatural intent (disambiguate from dark_serious).
  const wantsHorror = /\b(horror|scary|creepy|ghost|demon|occult|vampire|zombie|curse|haunted|junji ito|gruselig|geist|daemon|unheimlich|schaurig)\b/i.test(tNorm);
  if (wantsHorror && mode.id === "horror_supernatural") {
    score += 3;
    if (!reason) reason = "horror intent";
  }
  if (wantsHorror && mode.id === "dark_serious") {
    score -= 2; // prefer horror_supernatural over dark_serious for explicit horror queries
  }

  // Cozy/comfort intent.
  const wantsCozy = /\b(cozy|chill|healing|wholesome|comfort|gemuetlich|entspannend|wohlfuehl|beruhigend)\b/i.test(tNorm);
  if (wantsCozy && mode.id === "cozy_comfort") {
    score += 3;
    if (!reason) reason = "cozy intent";
  }

  // Mecha intent.
  const wantsMecha = /\b(mecha|giant robot|gundam|eva(ngelion)?|code geass|roboter|riesenroboter)\b/i.test(tNorm);
  if (wantsMecha && mode.id === "mecha") {
    score += 3;
    if (!reason) reason = "mecha intent";
  }

  // Mystery/detective intent.
  const wantsMystery = /\b(mystery|detective|whodunit|krimi|detektiv|who done it|case solved|raetsel)\b/i.test(tNorm);
  if (wantsMystery && mode.id === "mystery_detective") {
    score += 3;
    if (!reason) reason = "mystery intent";
  }

  // Music/performance intent.
  const wantsMusic = /\b(music anime|band|idol|concert|musik|instrument|k[- ]?on)\b/i.test(tNorm);
  if (wantsMusic && mode.id === "music_performance") {
    score += 3;
    if (!reason) reason = "music intent";
  }

  // Historical intent.
  const wantsHistorical = /\b(historical|samurai|period|war drama|medieval|historisch|mittelalter|vinland)\b/i.test(tNorm);
  if (wantsHistorical && mode.id === "historical") {
    score += 3;
    if (!reason) reason = "historical intent";
  }

  // School/coming-of-age intent.
  const wantsSchool = /\b(school|campus|high school|coming.of.age|youth|schule|jugend|gymnasium)\b/i.test(tNorm);
  if (wantsSchool && mode.id === "school_coming_of_age") {
    score += 3;
    if (!reason) reason = "school intent";
  }

  // Shoujo/Josei intent.
  const wantsShoujoJosei = /\b(shoujo|josei|for women|girls manga|fuer frauen|maedchen|woman protagonist)\b/i.test(tNorm);
  if (wantsShoujoJosei && mode.id === "shoujo_josei") {
    score += 3;
    if (!reason) reason = "shoujo/josei intent";
  }

  // ── Constraint-based mode penalties ──
  if (userConstraints) {
    // Movie constraint: penalize TV-focused modes, boost movie_night.
    if (userConstraints.format === "MOVIE") {
      if (mode.id === "movie_night") {
        score += 4;
        if (!reason) reason = "movie constraint";
      } else if (mode.exclude_formats?.includes("MOVIE")) {
        score -= 6; // mode explicitly excludes movies
      }
    }
    // Short-form constraint: penalize long-series modes.
    if (userConstraints.format === "SHORT_FORM" || userConstraints.format === "OVA" || userConstraints.format === "ONA") {
      if (mode.id === "short_one_season") {
        score += 3;
        if (!reason) reason = "short-form constraint";
      }
    }
    // Max-episodes constraint: boost short_one_season mode when user wants <=26 episodes.
    if (userConstraints.max_episodes != null && userConstraints.max_episodes <= 26) {
      if (mode.id === "short_one_season") {
        score += 2;
        if (!reason) reason = "episode limit constraint";
      }
    }
    // Min-episodes constraint: penalize short modes when user wants long.
    if (userConstraints.min_episodes != null && userConstraints.min_episodes >= 50) {
      if (mode.id === "short_one_season" || mode.id === "movie_night") {
        score -= 5;
      }
    }
    // Year max constraint: boost classics mode if user wants older titles.
    if (userConstraints.year_max != null && userConstraints.year_max <= 2012) {
      if (mode.id.includes("classic")) {
        score += 2;
        if (!reason) reason = "year constraint (classic era)";
      }
    }
  }

  // Quality guardrail: down-weight known weak/sparse mode inventories when
  // the prompt signal is weak. Explicit intent still wins.
  const healthPenalty = MODE_HEALTH_PENALTIES[mode.id] ?? 0;
  if (healthPenalty > 0) {
    if (score < 3) {
      score -= healthPenalty;
      if (!reason) reason = "quality safeguard";
    } else if (score < 5) {
      score -= Math.min(1.5, healthPenalty * 0.35);
    }
  }

  return { score, reason: reason || "default" };
}

function sigmoid(x: number) {
  const v = 1 / (1 + Math.exp(-x));
  return Math.max(0, Math.min(1, v));
}

function isClassicIntent(text: string) {
  const t = normalizeUmlauts(text.toLowerCase());
  return /\b(classic|classics|must watch|essentials|goat|greatest|retro|old school|oldschool|vintage|80s|90s|klassiker|klassisch|meisterwerk|muss man gesehen haben|legendaer|legendaere)\b/i.test(t);
}

function isGatewayIntent(text: string) {
  const t = normalizeUmlauts(text.toLowerCase());
  return /\b(first anime|first manga|where do i start|getting into anime|getting into manga|neu bei anime|neu bei manga|anime anfangen|manga anfangen|erstes anime|erstes manga|womit anfangen|wo fange ich an)\b/i.test(t);
}

function isHiddenGemsIntent(text: string) {
  const t = normalizeUmlauts(text.toLowerCase());
  return /\b(hidden gem|hidden gems|underrated|less known|new to me|geheimtipp|unterschaetzt|unbekannt|wenig bekannt|insider)\b/i.test(t);
}

function mapStrongGenreToModeId(text: string, excludedGenres: string[] = []): string | null {
  const t = normalizeUmlauts(normalizeGermanVibeWords(text.toLowerCase()));
  const excl = new Set(excludedGenres.map((g) => g.toLowerCase()));
  // High-signal intent should win over generic genre words.
  // Structural intents (movie, short, no-isekai) are never blocked by genre exclusions.
  if (/\b(classic|classics|must watch|essentials|goat|greatest|retro|old school|oldschool|vintage|80s|90s|klassiker|klassisch|legendaer|meisterwerk)\b/.test(t)) return "classics_expanded";
  if (/\b(movie|movies|film|filme|movie night|feature film|standalone movie|filmabend|kinofilm)\b/.test(t)) return "movie_night";
  if (/\b(short|one season|quick watch|binge|one cour|12 ep|13 ep|eine staffel|1 staffel|kurze serie|kurz und gut)\b/.test(t)) return "short_one_season";
  if (/\b(no isekai|not isekai|ohne isekai|nicht isekai|non[- ]?isekai|kein isekai)\b/.test(t)) return "fantasy_non_isekai";
  // Special romance sub-genres (no dedicated mode, but we prefer serious romance over romcom).
  if (!excl.has("romance") && /\b(shounen ai|shonen ai)\b/.test(t)) return "romance_serious";
  // "Magical girl" / mahou shoujo shouldn't be treated as generic fantasy.
  if (/\b(mahou shoujo|magical girl)\b/.test(t)) return "premium_picks";
  if (!excl.has("isekai") && /\b(isekai|reincarnat|reborn|another world|truck[- ]?kun)\b/.test(t)) return "isekai";
  if (!excl.has("romance") && /\b(romcom|rom com|romantic comedy)\b/.test(t)) return "romcom";
  if (!excl.has("romance") && /\b(serious romance|romance drama|bittersweet|heartbreak|deep romance)\b/.test(t)) return "romance_serious";
  if (!excl.has("romance") && /\b(romance|love story|romantic)\b/.test(t)) return "romcom";
  // School/coming-of-age and shoujo/josei (after romance to avoid false positives).
  if (/\b(school anime|high school|coming of age|schule|jugend)\b/.test(t)) return "school_coming_of_age";
  if (/\b(shoujo|josei|for women|fuer frauen|maedchen)\b/.test(t)) return "shoujo_josei";
  // Specific genre modes (before generic action/comedy/fantasy).
  if (/\b(mecha|giant robot|gundam|evangelion)\b/.test(t)) return "mecha";
  if (/\b(mystery|detective|whodunit|krimi|detektiv)\b/.test(t)) return "mystery_detective";
  if (/\b(music anime|band anime|idol anime|musik anime)\b/.test(t)) return "music_performance";
  if (/\b(historical|samurai|period drama|medieval|historisch|mittelalter)\b/.test(t)) return "historical";
  if (!excl.has("action") && /\b(action)\b/.test(t)) return "premium_action";
  if (!excl.has("comedy") && /\b(comedy|funny|laugh)\b/.test(t)) return "premium_comedy_grownup";
  if (!excl.has("slice of life") && /\b(slice of life|cozy|comfort|chill|relax|gemuetlich|entspannend|wohlfuehl)\b/.test(t)) return "cozy_comfort";
  if (!excl.has("horror") && !excl.has("supernatural") && /\b(horror|scary|creepy|supernatural|ghost|demon|occult|vampire|zombie|gruselig|unheimlich|schaurig)\b/.test(t)) return "horror_supernatural";
  if (!excl.has("thriller") && !excl.has("psychological") && !excl.has("mystery") && /\b(thriller|psychological|mind[- ]?game|mystery|dark|serious)\b/.test(t)) return "dark_serious";
  if (!excl.has("sci-fi") && /\b(sci[- ]?fi|scifi|science fiction|cyberpunk|space opera|dystopian|futuristic|weltraum|zukunft)\b/.test(t)) return "scifi";
  if (!excl.has("sports") && /\b(sports?|soccer|basketball|volleyball|boxing|tennis|baseball|fussball)\b/.test(t)) return "sports";
  if (!excl.has("fantasy") && /\b(fantasy|magic)\b/.test(t)) return "fantasy_non_isekai";
  return null;
}

function normalizePromptForCache(text: string) {
  return normalizeText(text).slice(0, 220);
}

type RouterDecision = {
  primaryId: string;
  secondaryId: string;
  secondaryCandidates: string[];
  primaryConfidence: number;
  primaryReason: string;
  usedLLM: boolean;
  topScore: number;
};


function inferLanguage(text: string): "de" | "en" {
  const t = text.toLowerCase();
  // Minimal heuristic: just enough for DE narration.
  if (/\b(ich|habe|hab|schaue|gucke|sehe|lese|staffel|folge|kapitel|band|bitte|empfehl|vorschlagen|suchen|finden|zeig|such|importieren|eintragen|hinzuf(ü|ue)gen|aktualisieren)\b/.test(t)) return "de";
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

type SeedOverride = { mt: MediaType; mediaId: number; title: string };

function expandKnownAbbrevSeed(raw: string): string | null {
  const t = raw.trim();
  // Keep this small and high-signal; it only runs for bare/short prompts.
  const map: Record<string, string> = {
    aot: "Attack on Titan",
    hxh: "Hunter x Hunter",
    fmab: "Fullmetal Alchemist: Brotherhood",
    nge: "Neon Genesis Evangelion",
    eva: "Neon Genesis Evangelion",
    lotgh: "Legend of the Galactic Heroes",
    op: "One Piece",
  };
  const key = t.toLowerCase();
  return map[key] ?? null;
}

function inferBareSeedCandidate(text: string): string | null {
  const t = text.trim();
  if (!t) return null;
  // Avoid treating normal recommendation prompts as seeds.
  if (/\b(recommend|something|give me|suggest|looking for|i want|show me|find me)\b/i.test(t)) return null;
  // Limit to short queries: bare titles or abbreviations.
  const words = t.split(/\s+/).filter(Boolean);
  if (words.length === 0 || words.length > 5) return null;
  if (t.length > 40) return null;

  // Abbrev + optional year (e.g. "HxH 2011").
  const yearMatch = t.match(/\b(19|20)\d{2}\b/);
  const year = yearMatch ? yearMatch[0] : null;
  const tokenNoYear = year ? t.replace(year, "").trim() : t;
  const expanded = expandKnownAbbrevSeed(tokenNoYear);
  if (expanded) return year ? `${expanded} ${year}` : expanded;

  // Single/bare title candidate; verified against DB before use.
  return t;
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

function inferExcludedGenres(text: string): string[] {
  const excluded: string[] = [];
  const lower = text.toLowerCase();

  // Patterns: "no romance", "without harem", "not isekai", "minus comedy"
  // German: "kein romance", "keine comedy", "ohne harem"
  const negPatterns = [
    /\b(?:no|without|not|minus|keine?|ohne)\s+(\w+)/gi,
  ];

  const genreMap: Record<string, string> = {
    romance: "Romance",
    comedy: "Comedy",
    action: "Action",
    horror: "Horror",
    harem: "Harem",
    ecchi: "Ecchi",
    isekai: "Isekai",
    mecha: "Mecha",
    sports: "Sports",
    music: "Music",
    kids: "Kids",
    fantasy: "Fantasy",
    scifi: "Sci-Fi",
    "sci-fi": "Sci-Fi",
    drama: "Drama",
    thriller: "Thriller",
    mystery: "Mystery",
    supernatural: "Supernatural",
  };

  for (const pat of negPatterns) {
    pat.lastIndex = 0;
    let m;
    while ((m = pat.exec(lower)) !== null) {
      const mapped = genreMap[m[1].toLowerCase()];
      if (mapped && !excluded.includes(mapped)) excluded.push(mapped);
    }
  }

  return excluded;
}

/**
 * Unified constraint extraction from user text (EN + DE).
 * Produces structured constraints used by mode selection, rail filtering, and post-filtering.
 * Each detected constraint appends an explainable reason to `why`.
 */
function extractConstraints(text: string): UserConstraints {
  const t = text.toLowerCase();
  const tNorm = normalizeUmlauts(t);
  const why: string[] = [];

  // ── Genre/tag exclusions (extends inferExcludedGenres) ──
  const excluded_genres = inferExcludedGenres(text);
  for (const g of excluded_genres) {
    why.push(`Excluded genre: user excluded '${g}'`);
  }
  // Additional DE patterns: "nicht Isekai", "non-isekai"
  if (/\b(?:nicht|non)\s*[- ]?\s*isekai\b/i.test(tNorm) && !excluded_genres.includes("Isekai")) {
    excluded_genres.push("Isekai");
    why.push("Excluded genre: user excluded 'Isekai' (nicht/non pattern)");
  }

  // ── Format constraints ──
  let format: string | null = null;

  // Movie intent (EN + DE)
  if (/\b(movie|movies|film|filme|filmabend|kinofilm|feature film|standalone movie)\b/i.test(tNorm)) {
    format = "MOVIE";
    why.push("Format: user wants movies");
  }
  // One season / short series intent (EN + DE)
  else if (/\b(one season|eine staffel|1 staffel|single season|one cour|ein cour)\b/i.test(tNorm)) {
    format = "TV_SHORT_SERIES";  // sentinel: handled as max_episodes <= 13 below
    why.push("Format: user wants single-season / short series");
  }
  // Short / OVA / ONA intent (EN + DE)
  else if (/\b(short|kurz|ova|ona|special|kurzfilm)\b/i.test(tNorm) &&
           !/\b(short series|kurze serie)\b/i.test(tNorm)) {
    // Only match standalone "short" / "kurz", not "short series"
    if (/\b(ova)\b/i.test(tNorm)) {
      format = "OVA";
      why.push("Format: user wants OVA");
    } else if (/\b(ona)\b/i.test(tNorm)) {
      format = "ONA";
      why.push("Format: user wants ONA");
    } else {
      format = "SHORT_FORM"; // sentinel for ONA|OVA|SPECIAL
      why.push("Format: user wants short-form content");
    }
  }

  // ── Length constraints ──
  let max_episodes: number | null = null;
  let min_episodes: number | null = null;

  // "under X episodes" / "unter X Folgen" / "weniger als X Folgen" / "less than X episodes"
  const maxEpMatch = tNorm.match(/\b(?:under|unter|weniger als|less than|max|maximal|hoechstens|höchstens|bis zu)\s+(\d{1,4})\s*(?:episodes?|folgen?|eps?)\b/i);
  if (maxEpMatch) {
    max_episodes = parseInt(maxEpMatch[1], 10);
    why.push(`Length: max ${max_episodes} episodes`);
  }
  // "over X episodes" / "über X Folgen" / "mehr als X Folgen" / "more than X episodes"
  const minEpMatch = tNorm.match(/\b(?:over|ueber|über|mehr als|more than|min|mindestens|ab)\s+(\d{1,4})\s*(?:episodes?|folgen?|eps?)\b/i);
  if (minEpMatch) {
    min_episodes = parseInt(minEpMatch[1], 10);
    why.push(`Length: min ${min_episodes} episodes`);
  }
  // "long" / "lang" implies 50+ episodes
  if (!min_episodes && /\b(long anime|long series|langes anime|lange serie|lang|marathon)\b/i.test(tNorm)) {
    min_episodes = 50;
    why.push("Length: user wants long series (50+ episodes)");
  }

  // One-season sentinel: apply max_episodes if not already set
  if (format === "TV_SHORT_SERIES" && !max_episodes) {
    max_episodes = 13;
    format = null; // don't lock to a specific format, just limit episodes
  } else if (format === "TV_SHORT_SERIES") {
    format = null; // max_episodes already captures intent
  }

  // ── Year constraints ──
  let year_min: number | null = null;
  let year_max: number | null = null;
  const currentYear = new Date().getFullYear();

  // "from YYYY" / "ab YYYY" / "seit YYYY" / "after YYYY" / "nach YYYY"
  const yearMinMatch = tNorm.match(/\b(?:from|ab|seit|after|nach|starting|beginning)\s+((?:19|20)\d{2})\b/i);
  if (yearMinMatch) {
    year_min = parseInt(yearMinMatch[1], 10);
    why.push(`Year: from ${year_min} onward`);
  }
  // "before YYYY" / "vor YYYY" / "until YYYY" / "bis YYYY" (year context only)
  const yearMaxMatch = tNorm.match(/\b(?:before|vor|until|bis)\s+((?:19|20)\d{2})\b/i);
  if (yearMaxMatch) {
    year_max = parseInt(yearMaxMatch[1], 10);
    why.push(`Year: before ${year_max}`);
  }
  // "classic" / "Klassiker" → year_max: 2005
  if (!year_max && /\b(classic|klassiker|klassisch|retro|old school|oldschool|vintage)\b/i.test(tNorm)) {
    year_max = 2005;
    why.push("Year: classic era (pre-2005)");
  }
  // "new" / "neu" / "recent" / "aktuell" → year_min: current_year - 2
  if (!year_min && /\b(new|neu|recent|aktuell|neue|neues|neueste|latest|this season|diese saison)\b/i.test(tNorm)) {
    // Avoid false positives: "new to me" / "new to anime" is not a year filter
    if (!/\b(new to me|new to anime|new to manga|neu bei)\b/i.test(tNorm)) {
      year_min = currentYear - 2;
      why.push(`Year: recent (${year_min}+)`);
    }
  }
  // Decade mentions: "90s anime" / "80er" / "2000er"
  const decadeMatch = tNorm.match(/\b((?:19|20)?\d0)s?\s*(?:anime|manga)?\b/i) ??
                       tNorm.match(/\b((?:19|20)?\d0)er\b/i);
  if (decadeMatch && !year_min && !year_max) {
    let decade = parseInt(decadeMatch[1], 10);
    if (decade < 100) decade += decade >= 50 ? 1900 : 2000; // "90s" → 1990, "00s" → 2000
    if (decade >= 1960 && decade <= 2020) {
      year_min = decade;
      year_max = decade + 9;
      why.push(`Year: ${decade}s decade`);
    }
  }

  return { excluded_genres, format, max_episodes, min_episodes, year_min, year_max, why };
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

  const safeUserText = sanitizeForLLM(opts.userText);
  const user =
    opts.lang === "de"
      ? `User prompt: ${safeUserText}\n\nItems:\n${opts.items
          .map((it) => `- ${it.id}: ${it.title} (${it.year ?? "?"}) ${it.format ?? ""} [${it.signals.join(", ")}]`)
          .join("\n")}\n\nSchreibe pro Item genau einen kurzen, spoilerfreien Satz. Gib nur JSON zurück: {"blurbs":{"ANIME|123":"...", "MANGA|456":"..."}}`
      : `User prompt: ${safeUserText}\n\nItems:\n${opts.items
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

async function isFeatureFlagEnabledForUser(
  client: any,
  flagName: string,
  userId: string,
  market: string,
): Promise<boolean> {
  try {
    const { data, error } = await client
      .from("feature_flags")
      .select("enabled,rollout_percentage,target_markets")
      .eq("flag_name", flagName)
      .maybeSingle();
    if (error || !data) return false;

    const enabled = Boolean((data as any).enabled);
    if (!enabled) return false;

    const targetMarkets = Array.isArray((data as any).target_markets)
      ? (data as any).target_markets.map((x: any) => String(x).toUpperCase())
      : [];
    if (targetMarkets.length > 0 && !targetMarkets.includes("*") && !targetMarkets.includes(market.toUpperCase())) {
      return false;
    }

    const rollout = Number((data as any).rollout_percentage ?? 0);
    if (!Number.isFinite(rollout) || rollout <= 0) return false;
    if (rollout >= 100) return true;

    const bucket = stableBucket(`${userId}:${flagName}`);
    return bucket < rollout;
  } catch {
    return false;
  }
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

    // Auth + rate-limit in parallel (both use the same client).
    const ip = clientIp(req);
    const [rlResult, userResult] = await Promise.all([
      client.rpc("check_concierge_rate_limit", {
        p_kind: "recommend",
        p_ip: ip,
        p_window_seconds: null,
        p_max_user: null,
        p_max_ip: null,
      }),
      client.auth.getUser(),
    ]);

    const rl = rlResult.data;
    if (rl && rl.allowed === false) {
      return json(
        { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
        { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
      );
    }

    const userData = userResult.data;
    const userErr = userResult.error;
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });

    const body = await req.json().catch(() => ({}));
    const text: string = String(body?.text ?? "");
    if (text.length > 5000) {
      return json({ error: "Text too long (max 5000 chars)" }, { status: 400 });
    }
    const scope: string = String(body?.scope ?? "both");
    const limit = Math.max(3, Math.min(20, Number(body?.limit ?? 8)));
    let narrate: boolean = Boolean(body?.narrate ?? false);
    const debugNarration: boolean = Boolean(body?.debugNarration ?? false);

    const categories = inferCategories(text);
    const gimmickTagIds = inferGimmickTagIds(text);
    const requiredGenres = inferRequiredGenres(text);
    const constraints = extractConstraints(text);
    const userExcludedGenres = constraints.excluded_genres;
    const quality = inferQualityFloor(text);

    // Parallel fetch: config, tag mapping, and editorial boosts are independent.
    const allowGimmicks =
      gimmickTagIds.length > 0 || /\b(slime)\b/.test(text.toLowerCase());
    const lang = inferLanguage(text);
    const mediaType = inferMediaType(text, scope);
    let seedQuery = inferSeedQuery(text);
    let seedOverride: SeedOverride | null = null;

    const [
      { data: conciergeCfg },
      focusTagIds,
      { data: tagBoosts },
    ] = await Promise.all([
      client.rpc("get_concierge_config"),
      mapTagAnilistIdsToInternal(client, gimmickTagIds),
      client.from("editorial_tag_boosts").select("tag_id,boost,reason"),
    ]);

    const configuredModes = parseModesFromConfig(conciergeCfg);
    const modes = configuredModes.length ? configuredModes : defaultModes();
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
      const linkTable = mt === "ANIME" ? "anime_tags" : "manga_tags";
      const idCol = mt === "ANIME" ? "anime_id" : "manga_id";
      const mediaSelect =
        mt === "ANIME"
          ? "id,title_english,title_romaji,title_native,cover_image_medium,average_score,popularity,start_date_year,format,status,site_url,is_adult,genres,episodes"
          : "id,title_english,title_romaji,title_native,cover_image_medium,average_score,popularity,start_date_year,format,status,site_url,is_adult,genres,chapters";

      // All three queries depend only on `ids` — run in parallel.
      const [mediaRes, boostsRes, tagLinksRes] = await Promise.all([
        client
          .from(table)
          .select(mediaSelect)
          .in("id", ids),
        client
          .from("editorial_boosts")
          .select("media_id,label,weight")
          .eq("media_type", mt)
          .in("media_id", ids),
        boostTagIds.length > 0
          ? client
              .from(linkTable)
              .select(`${idCol},tag_id`)
              .in(idCol, ids)
              .in("tag_id", boostTagIds)
          : Promise.resolve({ data: [] as any[], error: null }),
      ]);

      if (mediaRes.error) throw mediaRes.error;
      const rows = Array.isArray(mediaRes.data) ? mediaRes.data : [];
      const normalizedRows = rows.map((r: any) => {
        if (mt === "MANGA" && r?.episodes == null && r?.chapters != null) {
          r.episodes = r.chapters;
        }
        return r;
      });
      const byId = new Map<number, any>(normalizedRows.map((r: any) => [r.id, r]));
      const boostById = new Map<number, any>((boostsRes.data ?? []).map((b: any) => [b.media_id, b]));
      const tagLinks = !tagLinksRes.error ? (tagLinksRes.data ?? []) : [];

      const boostedReasonsById = new Map<number, string[]>();
      for (const row of tagLinks) {
        const mediaId = Number(row[idCol]);
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
      avoidGenres?: string[];
      classicYearMax?: number;
      quality: { minScore: number; minPopularity: number; maxPopularity: number | null; excludeFormats: Set<string> };
      prioritizeClassicBoost?: boolean;
      constraints?: UserConstraints;
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

      const uc = opts.constraints;

      const passes = (m: any) => {
        if (!m) return false;
        if (m.is_adult === true) return false;
        const fmt = String(m.format ?? "").toUpperCase();

        // Format constraint: if user wants MOVIE, only allow MOVIE format.
        if (uc?.format === "MOVIE" && fmt !== "MOVIE") return false;
        // Short-form: allow ONA, OVA, SPECIAL only.
        if (uc?.format === "SHORT_FORM" && !["ONA", "OVA", "SPECIAL"].includes(fmt)) return false;
        if (uc?.format === "OVA" && fmt !== "OVA") return false;
        if (uc?.format === "ONA" && fmt !== "ONA") return false;

        // Default format exclusions (unless overridden by constraint).
        if (!uc?.format && opts.quality.excludeFormats.has(fmt)) return false;
        if (hasExcludedGenres(m, opts.excludeGenres)) return false;

        const year = Number(m.start_date_year ?? 0);
        if (opts.classicYearMax && year > 0 && year > opts.classicYearMax) return false;
        // Year constraints from user.
        if (uc?.year_min != null && year > 0 && year < uc.year_min) return false;
        if (uc?.year_max != null && year > 0 && year > uc.year_max) return false;

        const score = Number(m.average_score ?? 0);
        const pop = Number(m.popularity ?? 0);
        if (opts.quality.minScore > 0 && score > 0 && score < opts.quality.minScore) return false;
        if (opts.quality.minPopularity > 0 && pop > 0 && pop < opts.quality.minPopularity) return false;
        if (opts.quality.maxPopularity != null && pop > 0 && pop > opts.quality.maxPopularity) return false;

        // Episode count constraints (anime only; manga uses chapters).
        if (mt === "ANIME") {
          const eps = Number(m.episodes ?? 0);
          if (uc?.max_episodes != null && eps > 0 && eps > uc.max_episodes) return false;
          if (uc?.min_episodes != null && eps > 0 && eps < uc.min_episodes) return false;
        }

        return true;
      };

      const avoid = Array.isArray(opts.avoidGenres) ? opts.avoidGenres.map((g) => String(g)).filter(Boolean) : [];
      const shouldDiversify = avoid.length > 0 && opts.requiredGenres.length === 0;

      const overlapCount = (m: any): number => {
        if (!shouldDiversify) return 0;
        const gs = Array.isArray(m?.genres) ? m.genres.map((x: any) => String(x)) : [];
        if (!gs.length) return 0;
        let n = 0;
        for (const g of avoid) {
          if (gs.includes(g)) n++;
        }
        return n;
      };

      const stableDiversify = (arr: CandidateRow[]): CandidateRow[] => {
        if (!shouldDiversify || arr.length <= 1) return arr;
        return arr
          .map((r, idx) => ({ r, idx }))
          .sort((a, b) => {
            const ma = ctx.byId.get(a.r.media_id);
            const mb = ctx.byId.get(b.r.media_id);
            const oa = overlapCount(ma);
            const ob = overlapCount(mb);
            if (oa !== ob) return oa - ob; // prefer less overlap with top genres
            return a.idx - b.idx; // stable tie-break
          })
          .map((x) => x.r);
      };

      // Prefer: genre match + quality; then quality; then anything (no hard failures).
      let primary: CandidateRow[] = [];
      let secondary: CandidateRow[] = [];
      let tertiary: CandidateRow[] = [];

      for (const r of rows) {
        const m = ctx.byId.get(r.media_id);
        if (!m) continue;
        if (passes(m) && hasGenres(m, opts.requiredGenres)) primary.push(r);
        else if (passes(m)) secondary.push(r);
        else tertiary.push(r);
      }

      primary = stableDiversify(primary);
      secondary = stableDiversify(secondary);
      tertiary = stableDiversify(tertiary);

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

    const modeById = new Map<string, ConciergeMode>(modes.map((m) => [m.id, m]));
    const classicsMode = modeById.get("classics_expanded") ?? Array.from(modeById.values()).find((m) => m.id.includes("classic")) ?? null;
    const premiumMode = modeById.get("premium_picks") ?? Array.from(modeById.values()).find((m) => m.id.includes("premium")) ?? null;

    const routerCfg = conciergeCfg?.router_llm ?? {};
    const cacheTtlDays = Number(routerCfg?.cache_ttl_days ?? 30);

    const userId = userData.user.id;
    const market = inferRequestMarket(req);
    const locale = inferLocale(req, market);
    const ragAssistEnabled = await isFeatureFlagEnabledForUser(client, "rag_assist_v1", userId, market);
    const promptNorm = normalizePromptForCache(text);

    const userTopGenresPromise: Promise<string[]> = (async () => {
      try {
        const { data: ul, error: ulErr } = await client
          .from("user_lists")
          .select("media_type,media_id")
          .eq("user_id", userId)
          .limit(120);
        if (ulErr || !Array.isArray(ul) || ul.length === 0) return [];

        const animeIds = ul.filter((r: any) => String(r.media_type ?? "").toLowerCase() === "anime").map((r: any) => Number(r.media_id)).filter((x: number) => Number.isFinite(x) && x > 0).slice(0, 80);
        const mangaIds = ul.filter((r: any) => String(r.media_type ?? "").toLowerCase() === "manga").map((r: any) => Number(r.media_id)).filter((x: number) => Number.isFinite(x) && x > 0).slice(0, 80);

        const [aRes, mRes] = await Promise.all([
          animeIds.length ? client.from("anime").select("id,genres").in("id", animeIds) : Promise.resolve({ data: [] as any[], error: null as any }),
          mangaIds.length ? client.from("manga").select("id,genres").in("id", mangaIds) : Promise.resolve({ data: [] as any[], error: null as any }),
        ]);

        const counts = new Map<string, number>();
        const bump = (g: string) => counts.set(g, (counts.get(g) ?? 0) + 1);
        const ingest = (rows: any[]) => {
          for (const r of rows) {
            const gs = Array.isArray(r?.genres) ? r.genres.map((x: any) => String(x)) : [];
            for (const g of gs) {
              if (!g) continue;
              if (g === "Hentai" || g === "Ecchi" || g === "Kids") continue;
              bump(g);
            }
          }
        };

        if (Array.isArray(aRes.data)) ingest(aRes.data);
        if (Array.isArray(mRes.data)) ingest(mRes.data);

        const top = Array.from(counts.entries())
          .sort((a, b) => b[1] - a[1])
          .map(([g]) => g)
          .slice(0, 5);
        return top;
      } catch {
        return [];
      }
    })();

    const modeFamily = (modeId: string) => {
      if (modeId.startsWith("premium_")) return "premium";
      if (modeId.startsWith("classics")) return "classics";
      if (modeId === "romcom" || modeId.startsWith("romance_")) return "romance";
      if (modeId === "similar_to_seed") return "seed";
      return modeId.split("_")[0] ?? modeId;
    };

    const arrayOverlapCount = (a: string[], b: string[]) => {
      if (!a.length || !b.length) return 0;
      const right = new Set(b.map((x) => x.toLowerCase()));
      let n = 0;
      for (const item of a) if (right.has(item.toLowerCase())) n++;
      return n;
    };

    const rankSecondaryCandidates = async (primaryId: string): Promise<Array<{ id: string; score: number; reason: string }>> => {
      const classicsId = classicsMode?.id ?? "classics_expanded";
      const primary = modeById.get(primaryId) ?? null;
      const primaryReq = safeStringArray(primary?.required_genres);
      const topGenres = await userTopGenresPromise;
      const wantsClassic = isClassicIntent(text);

      const all = Array.from(modeById.values())
        .filter((m) => m.id !== primaryId && m.id !== "similar_to_seed")
        .map((m) => {
          const s = scoreMode(text, m, requiredGenres, userExcludedGenres, constraints);
          let score = s.score;
          const reasons: string[] = [];

          const req = safeStringArray(m.required_genres);
          const genreOverlap = arrayOverlapCount(primaryReq, req);
          if (genreOverlap > 0) {
            score -= Math.min(4, genreOverlap * 1.6);
            reasons.push("genre-overlap");
          }

          if (modeFamily(primaryId) === modeFamily(m.id)) {
            score -= 2.2;
            reasons.push("same-family");
          }

          // Keep classics available, but no longer hardwire it as the default second rail.
          if (m.id === classicsId) {
            if (wantsClassic) {
              score += 2.5;
              reasons.push("explicit-classic");
            } else {
              score -= 3.2;
              reasons.push("avoid-default-classic");
            }
          }

          // Prefer less saturated taste pockets for secondary rails.
          const topGenreOverlap = arrayOverlapCount(req, topGenres);
          if (topGenreOverlap > 0) {
            score -= Math.min(3, topGenreOverlap * 1.1);
            reasons.push("top-genre-overlap");
          }

          // Slightly prefer curated rails (when quality is present) to keep selection deterministic.
          if (m.rail_id) {
            score += 0.4;
          }

          return {
            id: m.id,
            score,
            reason: reasons.length > 0 ? reasons.join(",") : (s.reason || "scored"),
          };
        })
        .sort((a, b) => b.score - a.score);

      return all;
    };

    const mkPick = (id: string, title: string, confidence: number, reason: string): ModePick => ({
      id,
      title,
      confidence: Math.max(0, Math.min(1, confidence)),
      reason,
    });

    const loadCache = async (): Promise<RouterDecision | null> => {
      if (!cacheTtlDays || cacheTtlDays <= 0) return null;
      const { data, error } = await client
        .from("concierge_mode_cache")
        .select("primary_mode_id,secondary_mode_id,used_llm,updated_at")
        .eq("user_id", userId)
        .eq("prompt_norm", promptNorm)
        .maybeSingle();
      if (error || !data) return null;
      const updatedAt = Date.parse(String((data as any).updated_at ?? ""));
      if (!Number.isFinite(updatedAt)) return null;
      const ageDays = (Date.now() - updatedAt) / (1000 * 60 * 60 * 24);
      if (ageDays > cacheTtlDays) return null;
      const primaryId = String((data as any).primary_mode_id ?? "").trim();
      const secondaryId = String((data as any).secondary_mode_id ?? "").trim();
      if (!primaryId || !secondaryId) return null;
      return {
        primaryId,
        secondaryId,
        secondaryCandidates: [secondaryId],
        primaryConfidence: 0.75,
        primaryReason: "cache",
        usedLLM: Boolean((data as any).used_llm ?? false),
        topScore: 999,
      };
    };

    const saveCache = async (dec: RouterDecision) => {
      if (!cacheTtlDays || cacheTtlDays <= 0) return;
      try {
        await client
          .from("concierge_mode_cache")
          .upsert(
            {
              user_id: userId,
              prompt_norm: promptNorm,
              primary_mode_id: dec.primaryId,
              secondary_mode_id: dec.secondaryId,
              used_llm: dec.usedLLM,
            },
            { onConflict: "user_id,prompt_norm" },
          );
      } catch {
        // best-effort
      }
    };

    const decideModes = async (): Promise<RouterDecision> => {
      const classicsId = classicsMode?.id ?? "classics_expanded";

      const buildDecision = async (
        primaryId: string,
        primaryConfidence: number,
        primaryReason: string,
        usedLLM: boolean,
        topScore: number,
      ): Promise<RouterDecision> => {
        const ranked = await rankSecondaryCandidates(primaryId);
        const fallbackSecondary = primaryId === classicsId
          ? (premiumMode?.id ?? "premium_picks")
          : (premiumMode?.id ?? classicsId);
        const secondaryId = ranked[0]?.id ?? fallbackSecondary;
        return {
          primaryId,
          secondaryId,
          secondaryCandidates: uniq([secondaryId, ...ranked.map((r) => r.id)]).slice(0, 8),
          primaryConfidence,
          primaryReason,
          usedLLM,
          topScore,
        };
      };

      // Cache (prevents repeated LLM spend and stabilizes routing).
      const cached = await loadCache();
      if (cached) {
        // Rehydrate ranked alternatives on cache hits so we do not lock users
        // into a stale single secondary rail for the full cache TTL window.
        const ranked = await rankSecondaryCandidates(cached.primaryId);
        cached.secondaryCandidates = uniq([cached.secondaryId, ...ranked.map((r) => r.id)]).slice(0, 8);
        return cached;
      }

      // Hard overrides (one-shot magic).
      if (seedQuery) {
        const dec = await buildDecision("similar_to_seed", 1, "seed similarity", false, 999);
        await saveCache(dec);
        return dec;
      }

      // Bare-title seed: verify against DB first (prevents gibberish => empty Similar rail).
      const bareCandidate = inferBareSeedCandidate(text);
      if (bareCandidate) {
        const pickSeedVerified = async (mt: MediaType) => {
          const { data: seeds, error: seedErr } = await client.rpc("search_titles", {
            p_query: bareCandidate,
            p_media_type: mt,
            p_limit: 6,
          });
          if (seedErr || !Array.isArray(seeds) || seeds.length === 0) return null;
          const top = seeds[0];
          if ((top?.score ?? 0) < 0.45) return null;
          return { mt, mediaId: Number(top.media_id), title: String(top.title_raw ?? top.title ?? "").trim() };
        };

        const verified =
          mediaType === "MANGA" ? await pickSeedVerified("MANGA")
            : mediaType === "ANIME" ? await pickSeedVerified("ANIME")
            : (await pickSeedVerified("ANIME")) ?? (await pickSeedVerified("MANGA"));

        if (verified && Number.isFinite(verified.mediaId) && verified.mediaId > 0) {
          seedQuery = bareCandidate;
          seedOverride = verified;
          const dec = await buildDecision("similar_to_seed", 1, "bare title seed similarity", false, 999);
          await saveCache(dec);
          return dec;
        }
      }

      if (isClassicIntent(text)) {
        const dec = await buildDecision(classicsId, 1, "classic intent", false, 999);
        await saveCache(dec);
        return dec;
      }
      if (isGatewayIntent(text)) {
        const primaryId = modeById.has("gateway_start_here") ? "gateway_start_here" : (premiumMode?.id ?? "premium_picks");
        const dec = await buildDecision(primaryId, 1, "start here intent", false, 999);
        await saveCache(dec);
        return dec;
      }
      if (isHiddenGemsIntent(text)) {
        const primaryId = modeById.has("hidden_gems") ? "hidden_gems" : (premiumMode?.id ?? "premium_picks");
        const dec = await buildDecision(primaryId, 1, "hidden gems intent", false, 999);
        await saveCache(dec);
        return dec;
      }
      const genreMapped = mapStrongGenreToModeId(text, userExcludedGenres);
      if (genreMapped && modeById.has(genreMapped)) {
        const dec = await buildDecision(genreMapped, 0.9, "strong genre signal", false, 999);
        await saveCache(dec);
        return dec;
      }

      // Deterministic scoring (fallback).
      const candidates = Array.from(modeById.values()).filter((m) => m.id !== classicsId);
      const scored = candidates.map((m) => {
        const s = scoreMode(text, m, requiredGenres, userExcludedGenres, constraints);
        let score = s.score;
        // Tie-breaker so vague prompts don't pick random modes.
        if (m.id === "premium_picks") score += 1;
        return { mode: m, score, reason: s.reason };
      }).sort((a, b) => b.score - a.score);

      const top = scored[0] ?? null;
      const runner = scored[1] ?? null;
      const topId = top?.mode?.id ?? (premiumMode?.id ?? "premium_picks");
      const topScore = Number(top?.score ?? 0);
      const delta = Number(top?.score ?? 0) - Number(runner?.score ?? 0);
      const primaryConfidence = sigmoid(delta - 1);
      const primaryReason = top?.reason ?? "scored";

      const dec = await buildDecision(topId, primaryConfidence, primaryReason, false, topScore);
      await saveCache(dec);
      return dec;
    };

	    const decision = await decideModes();

	    const modePicks: ModePick[] = [];
	    const primaryMode = modeById.get(decision.primaryId) ?? null;
	    const primaryCopy = curatedCopyForMode(locale, decision.primaryId, primaryMode?.title ?? decision.primaryId);
	    modePicks.push(mkPick(decision.primaryId, primaryCopy.displayTitle, decision.primaryConfidence, decision.primaryReason));

    const perTypeLimit = (total: number) => mediaType === "BOTH" ? Math.max(3, Math.ceil(total / 2)) : total;

    const mapCuratedRowToItem = (row: any) => {
      const mt = String(row?.media_type ?? row?.mediaType ?? "").toUpperCase();
      const mediaTypeOut = mt === "MANGA" ? "MANGA" : "ANIME";
      const mediaId = Number(row?.media_id ?? row?.mediaId ?? 0);
      const title = row?.title_english ?? row?.title_romaji ?? row?.title_native ?? "Unknown";
      return {
        mediaType: mediaTypeOut,
        mediaId,
        matchCount: null,
        score: null,
        title,
        coverImageMedium: row?.cover_image_medium ?? row?.coverImageMedium ?? null,
        averageScore: row?.average_score ?? row?.averageScore ?? null,
        year: row?.year ?? null,
        format: row?.format ?? null,
        status: row?.status ?? null,
        siteUrl: row?.site_url ?? row?.siteUrl ?? null,
        signals: Array.isArray(row?.signals) ? row.signals : [],
        genres: Array.isArray(row?.genres) ? row.genres : null,
      };
    };

    const railIdFor = (mode: ConciergeMode | null, mt: MediaType): string | null => {
      if (!mode?.rail_id) return null;
      if (typeof mode.rail_id === "string") return mode.rail_id;
      const both = mode.rail_id.both;
      if (both) return both;
      return mt === "ANIME" ? (mode.rail_id.anime ?? null) : (mode.rail_id.manga ?? null);
    };

    const filterByConstraints = (items: any[]) => {
      return items.filter((it) => {
        // Genre exclusion.
        if (userExcludedGenres.length) {
          const gs = Array.isArray(it.genres) ? it.genres.map((g: any) => String(g)) : [];
          if (userExcludedGenres.some((eg) => gs.includes(eg))) return false;
        }
        // Format constraint.
        const fmt = String(it.format ?? "").toUpperCase();
        if (constraints.format === "MOVIE" && fmt !== "MOVIE") return false;
        if (constraints.format === "SHORT_FORM" && !["ONA", "OVA", "SPECIAL"].includes(fmt)) return false;
        if (constraints.format === "OVA" && fmt !== "OVA") return false;
        if (constraints.format === "ONA" && fmt !== "ONA") return false;
        // Year constraints.
        const year = Number(it.year ?? 0);
        if (constraints.year_min != null && year > 0 && year < constraints.year_min) return false;
        if (constraints.year_max != null && year > 0 && year > constraints.year_max) return false;
        return true;
      });
    };

	    const fetchCurated = async (mode: ConciergeMode, total: number) => {
	      const avoidGenres = await userTopGenresPromise;
	      const stableDiversifyItems = (arr: any[]): any[] => {
	        if (!Array.isArray(arr) || arr.length <= 1) return arr;
	        if (!avoidGenres.length) return arr;
	        const overlap = (it: any) => {
	          const gs = Array.isArray(it?.genres) ? it.genres.map((g: any) => String(g)) : [];
	          if (!gs.length) return 0;
	          let n = 0;
	          for (const g of avoidGenres) if (gs.includes(g)) n++;
	          return n;
	        };
	        return arr
	          .map((it, idx) => ({ it, idx }))
	          .sort((a, b) => {
	            const oa = overlap(a.it);
	            const ob = overlap(b.it);
	            if (oa !== ob) return oa - ob;
	            return a.idx - b.idx;
	          })
	          .map((x) => x.it);
	      };

	      // Fetch extra to compensate for post-filtering by user constraints.
	      const hasActiveConstraints = userExcludedGenres.length > 0 || constraints.format != null || constraints.year_min != null || constraints.year_max != null;
	      const fetchLimit = hasActiveConstraints ? total + 20 : total;
      const perType = perTypeLimit(fetchLimit);
      const animeRid = railIdFor(mode, "ANIME");
      const mangaRid = railIdFor(mode, "MANGA");
      const [animeRows, mangaRows] = await Promise.all([
        (mediaType === "ANIME" || mediaType === "BOTH") && animeRid
          ? client.rpc("curated_rail_cards", { p_rail_id: animeRid, p_limit: perType, p_exclude_seen: true }).then((r) => r.data)
          : [],
        (mediaType === "MANGA" || mediaType === "BOTH") && mangaRid
          ? client.rpc("curated_rail_cards", { p_rail_id: mangaRid, p_limit: perType, p_exclude_seen: true }).then((r) => r.data)
          : [],
      ]);
	      const a = stableDiversifyItems(filterByConstraints(Array.isArray(animeRows) ? animeRows.map(mapCuratedRowToItem) : []));
	      const m = stableDiversifyItems(filterByConstraints(Array.isArray(mangaRows) ? mangaRows.map(mapCuratedRowToItem) : []));
	      const merged = mediaType === "BOTH" ? mergeAlternating(a, m, total) : [...a, ...m].slice(0, total);
	      return merged;
	    };

    let ragAssistUsed = false;
    let ragSeedEntityId: string | null = null;

    const fetchSeedFromRag = async (): Promise<{ mt: MediaType; mediaId: number; title: string; entityId: string | null } | null> => {
      if (!ragAssistEnabled || !seedQuery) return null;

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);
      const ragFormat =
        constraints.format === "MOVIE" || constraints.format === "ONA" || constraints.format === "OVA"
          ? constraints.format
          : null;

      try {
        const ragUrl = `${supabaseUrl}/functions/v1/concierge-retrieve-assist`;
        const res = await fetch(ragUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            ...(authHeader ? { Authorization: authHeader } : {}),
          },
          body: JSON.stringify({
            query: seedQuery,
            locale: lang,
            media_type: mediaType === "BOTH" ? null : mediaType,
            excluded_genres: userExcludedGenres,
            format: ragFormat,
            year_min: constraints.year_min,
            year_max: constraints.year_max,
          }),
          signal: controller.signal,
        });
        if (!res.ok) return null;
        const payload = await res.json().catch(() => null);
        const candidates = Array.isArray(payload?.entity_candidates) ? payload.entity_candidates : [];
        const top = candidates[0];
        if (!top) return null;

        const mt = String(top.media_type ?? "").toUpperCase();
        const mediaId = Number(top.anilist_id ?? 0);
        const score = Number(top.score ?? 0);
        const title = String(top.title ?? "").trim();
        const entityId = typeof top.entity_id === "string" ? top.entity_id : null;
        if (!Number.isFinite(mediaId) || mediaId <= 0) return null;
        if (score < 0.45) return null;
        if (mt !== "ANIME" && mt !== "MANGA") return null;

        ragAssistUsed = true;
        ragSeedEntityId = entityId;
        return { mt, mediaId, title: title || seedQuery, entityId };
      } catch {
        return null;
      } finally {
        clearTimeout(timeout);
      }
    };

	    const buildSimilarToSeedRail = async (total: number) => {
      // Only build when we have a decent seed title.
      const pickSeed = async (mt: MediaType) => {
        const { data: seeds, error: seedErr } = await client.rpc("search_titles", {
          p_query: seedQuery,
          p_media_type: mt,
          p_limit: 6,
        });
        if (seedErr || !Array.isArray(seeds) || seeds.length === 0) return null;
        const top = seeds[0];
        if ((top?.score ?? 0) < 0.35) return null;
        return { mt, mediaId: Number(top.media_id), title: String(top.title_raw ?? top.title ?? "").trim() };
      };

      const seed = seedOverride
        ? seedOverride
        : mediaType === "MANGA" ? await pickSeed("MANGA")
        : mediaType === "ANIME" ? await pickSeed("ANIME")
        : (await pickSeed("ANIME")) ?? (await pickSeed("MANGA"));
      const ragSeed = (!seed || !Number.isFinite(seed.mediaId) || seed.mediaId <= 0)
        ? await fetchSeedFromRag()
        : null;
      if (ragSeed) {
        seedOverride = { mt: ragSeed.mt, mediaId: ragSeed.mediaId, title: ragSeed.title };
      }
	      const effectiveSeed = seedOverride ?? seed;
	      if (!effectiveSeed || !Number.isFinite(effectiveSeed.mediaId) || effectiveSeed.mediaId <= 0) {
	        return { title: "Similar", items: [] as any[] };
	      }

	      const avoidGenres = await userTopGenresPromise;
	      const perType = perTypeLimit(total);
	      const q = compileQuality(null);
	      const getSim = async (mt: MediaType) => {
        const { data: sim, error: simErr } = await client.rpc("recommend_ids_similar_to_seeds", {
          p_media_type: mt,
          p_seed_ids: [effectiveSeed.mediaId],
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

      const [animeRows, mangaRows] = await Promise.all([
        (mediaType === "ANIME" || mediaType === "BOTH") ? getSim("ANIME") : [],
        (mediaType === "MANGA" || mediaType === "BOTH") ? getSim("MANGA") : [],
      ]);
      const emptyCtx: MediaContext = { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() };
      const [simCtxAnime, simCtxManga] = await Promise.all([
        (mediaType === "ANIME" || mediaType === "BOTH")
          ? fetchMediaContext("ANIME", animeRows.map((r) => r.media_id))
          : emptyCtx,
        (mediaType === "MANGA" || mediaType === "BOTH")
          ? fetchMediaContext("MANGA", mangaRows.map((r) => r.media_id))
          : emptyCtx,
      ]);

	      const a = (mediaType === "ANIME" || mediaType === "BOTH")
	        ? buildItemsFromRows("ANIME", animeRows, simCtxAnime, { limit: perType, requiredGenres, excludeGenres: userExcludedGenres, avoidGenres, quality: q, constraints })
	        : [];
	      const m = (mediaType === "MANGA" || mediaType === "BOTH")
	        ? buildItemsFromRows("MANGA", mangaRows, simCtxManga, { limit: perType, requiredGenres, excludeGenres: userExcludedGenres, avoidGenres, quality: q, constraints })
	        : [];

      const merged = mediaType === "BOTH" ? mergeAlternating(a, m, total) : [...a, ...m].slice(0, total);
      const title = effectiveSeed.title || seedQuery || "seed";
      return { title: `Similar to "${title}"`, items: merged };
    };

	    const buildAlgorithmicRail = async (mode: ConciergeMode | null, total: number) => {
	      const avoidGenres = await userTopGenresPromise;
	      const perType = perTypeLimit(total);
	      const modeRequired = uniq([...(mode?.required_genres ?? []), ...requiredGenres]);
	      const modeExcluded = uniq([...(mode?.exclude_genres ?? []), ...userExcludedGenres]);
      const q = compileQuality(mode);
      const pCats = uniq([...categories, ...(mode?.required_genres ?? [])]);
      const cats = pCats.length ? pCats : (categories.length ? categories : null);

      const [animeRows, mangaRows] = await Promise.all([
        (mediaType === "ANIME" || mediaType === "BOTH") ? getPremiumCandidates("ANIME", cats) : [],
        (mediaType === "MANGA" || mediaType === "BOTH") ? getPremiumCandidates("MANGA", cats) : [],
      ]);
      const emptyCtx: MediaContext = { byId: new Map(), boostById: new Map(), boostedReasonsById: new Map() };
      const [ctxAnime, ctxManga] = await Promise.all([
        (mediaType === "ANIME" || mediaType === "BOTH")
          ? fetchMediaContext("ANIME", animeRows.map((r) => r.media_id))
          : emptyCtx,
        (mediaType === "MANGA" || mediaType === "BOTH")
          ? fetchMediaContext("MANGA", mangaRows.map((r) => r.media_id))
          : emptyCtx,
      ]);

	      const a = (mediaType === "ANIME" || mediaType === "BOTH")
	        ? buildItemsFromRows("ANIME", animeRows, ctxAnime, {
	          limit: perType,
	          requiredGenres: modeRequired,
	          excludeGenres: modeExcluded,
	          avoidGenres,
	          classicYearMax: mode?.classic_year_max,
	          quality: q,
	          prioritizeClassicBoost: (mode?.id ?? "").includes("classic"),
	          constraints,
	        })
	        : [];
	      const m = (mediaType === "MANGA" || mediaType === "BOTH")
	        ? buildItemsFromRows("MANGA", mangaRows, ctxManga, {
	          limit: perType,
	          requiredGenres: modeRequired,
	          excludeGenres: modeExcluded,
	          avoidGenres,
	          classicYearMax: mode?.classic_year_max,
	          quality: q,
	          prioritizeClassicBoost: (mode?.id ?? "").includes("classic"),
	          constraints,
	        })
	        : [];
      return mediaType === "BOTH" ? mergeAlternating(a, m, total) : [...a, ...m].slice(0, total);
    };

    const buildRailItems = async (modeId: string, total: number) => {
      if (modeId === "similar_to_seed") {
        return await buildSimilarToSeedRail(total);
      }
      const mode = modeById.get(modeId) ?? null;
      // Curated rail if configured; fall back to algorithmic if empty/unavailable.
      // If curated returns fewer than requested, fill the remainder algorithmically (still one-shot).
      if (mode?.rail_id) {
        try {
          const curated = await fetchCurated(mode, total);
          if (curated.length > 0) {
            if (curated.length >= total) return { title: mode.title, items: curated.slice(0, total) };

            const algo = await buildAlgorithmicRail(mode, total);
            const seen = new Set(curated.map((it: any) => `${it.mediaType}|${it.mediaId}`));
            const filled = [...curated];
            for (const it of algo) {
              if (filled.length >= total) break;
              const k = `${it.mediaType}|${it.mediaId}`;
              if (seen.has(k)) continue;
              seen.add(k);
              filled.push(it);
            }
            return { title: mode.title, items: filled };
          }
        } catch {
          // ignore
        }
      }
      const items = await buildAlgorithmicRail(mode, total);
      return { title: mode?.title ?? modeId, items };
    };

    // Exactly 2 rails: primary + diversified secondary (no hard classics anchor).
    const primaryTotal = limit;
    const secondaryTotal = Math.max(10, Math.min(16, limit + 2));
    const minSecondaryItems = Math.max(8, Math.min(secondaryTotal, 12));

    const classicsId = classicsMode?.id ?? "classics_expanded";
    const explicitClassicIntent = isClassicIntent(text);
    const preferredSecondaryIds = uniq([
      decision.secondaryId,
      ...decision.secondaryCandidates,
      premiumMode?.id ?? "premium_picks",
      ...(explicitClassicIntent ? [classicsId] : []),
    ])
      .filter((id) => !!id && id !== decision.primaryId)
      .slice(0, 5);

    const primaryBuilt = await buildRailItems(decision.primaryId, primaryTotal);
    const primaryItemKeys = new Set(primaryBuilt.items.map((it: any) => `${it.mediaType}|${it.mediaId}`));
    const secondaryPriority = new Map<string, number>();
    preferredSecondaryIds.forEach((id, idx) => secondaryPriority.set(id, preferredSecondaryIds.length - idx));

    const evaluateSecondary = (modeId: string, built: { title: string; items: any[] }) => {
      const itemKeys = built.items.map((it: any) => `${it.mediaType}|${it.mediaId}`);
      const overlapCount = itemKeys.filter((k) => primaryItemKeys.has(k)).length;
      const overlapRatio = built.items.length > 0 ? overlapCount / built.items.length : 1;
      const itemCoverage = Math.min(1, built.items.length / Math.max(1, secondaryTotal));
      let score = 0;
      score += (secondaryPriority.get(modeId) ?? 0) * 1.1;
      score += itemCoverage * 2.0;
      score -= overlapRatio * 5.0;
      if (built.items.length < minSecondaryItems) score -= 2.8;
      if (modeId === classicsId && !explicitClassicIntent) score -= 3.2;
      if (modeFamily(modeId) === modeFamily(decision.primaryId)) score -= 1.2;
      const acceptable = built.items.length >= minSecondaryItems && overlapRatio <= 0.45;
      return {
        score,
        acceptable,
        overlapRatio,
        overlapCount,
      };
    };

    const fallbackSecondaryId = preferredSecondaryIds[0] ?? (premiumMode?.id ?? classicsId);
    const fallbackSecondaryBuilt = await buildRailItems(fallbackSecondaryId, secondaryTotal);

    type SecondaryCandidateEvaluation = {
      modeId: string;
      built: { title: string; items: any[] };
      eval: {
        score: number;
        acceptable: boolean;
        overlapRatio: number;
        overlapCount: number;
      };
    };

    const secondaryCandidateResults: SecondaryCandidateEvaluation[] = await Promise.all(
      preferredSecondaryIds.map(async (modeId): Promise<SecondaryCandidateEvaluation> => {
        try {
          const built = await buildRailItems(modeId, secondaryTotal);
          return { modeId, built, eval: evaluateSecondary(modeId, built) };
        } catch {
          const emptyBuilt = { title: modeId, items: [] as any[] };
          return {
            modeId,
            built: emptyBuilt,
            eval: {
              score: Number.NEGATIVE_INFINITY,
              acceptable: false,
              overlapRatio: 1,
              overlapCount: 0,
            },
          };
        }
      }),
    );

    const chooseBetterSecondary = (a: SecondaryCandidateEvaluation, b: SecondaryCandidateEvaluation) => {
      if (a.eval.acceptable !== b.eval.acceptable) {
        return a.eval.acceptable ? -1 : 1;
      }
      if (a.eval.score !== b.eval.score) {
        return b.eval.score - a.eval.score;
      }
      if (a.eval.overlapRatio !== b.eval.overlapRatio) {
        return a.eval.overlapRatio - b.eval.overlapRatio;
      }
      if (a.built.items.length !== b.built.items.length) {
        return b.built.items.length - a.built.items.length;
      }
      const ap = secondaryPriority.get(a.modeId) ?? 0;
      const bp = secondaryPriority.get(b.modeId) ?? 0;
      return bp - ap;
    };

    const sortedSecondaryCandidates = secondaryCandidateResults
      .slice()
      .sort(chooseBetterSecondary);

    let chosenSecondary = sortedSecondaryCandidates[0] ?? {
      modeId: fallbackSecondaryId,
      built: fallbackSecondaryBuilt,
      eval: evaluateSecondary(fallbackSecondaryId, fallbackSecondaryBuilt),
    };

    // Guardrail: if classics wins by default, prefer a close non-classics candidate
    // unless the user explicitly asked for classics.
    if (!explicitClassicIntent && chosenSecondary.modeId === classicsId) {
      const bestNonClassic = sortedSecondaryCandidates.find((c) =>
        c.modeId !== classicsId && c.eval.acceptable
      );
      if (bestNonClassic && bestNonClassic.eval.score >= (chosenSecondary.eval.score - 0.9)) {
        chosenSecondary = bestNonClassic;
      }
    }

    // Diversity stabilizer: rotate within the top close alternatives so the second rail
    // does not collapse into the same mode for broad prompts.
    if (!explicitClassicIntent) {
      const nonClassicAcceptable = sortedSecondaryCandidates.filter((c) =>
        c.modeId !== classicsId && c.eval.acceptable
      );
      if (nonClassicAcceptable.length >= 2) {
        const topScore = nonClassicAcceptable[0].eval.score;
        const closeBand = nonClassicAcceptable
          .filter((c) => (topScore - c.eval.score) <= 0.8)
          .slice(0, 3);
        if (closeBand.length >= 2) {
          const pickIndex = stableBucket(`${promptNorm}|${decision.primaryId}|secondary`) % closeBand.length;
          chosenSecondary = closeBand[pickIndex];
        }
      }
    }

    const chosenSecondaryId = chosenSecondary.modeId;
    const chosenSecondaryBuilt = chosenSecondary.built;
    const chosenEval = chosenSecondary.eval;

    const secondaryMode = modeById.get(chosenSecondaryId) ?? null;
    const secondaryCopy = curatedCopyForMode(locale, chosenSecondaryId, secondaryMode?.title ?? chosenSecondaryBuilt.title);
    const secondaryConfidence = chosenEval.acceptable ? 0.82 : 0.64;
    const secondaryReason = chosenEval.acceptable
      ? "diversified-secondary"
      : "fallback-secondary";

    if (chosenSecondaryId !== decision.secondaryId) {
      await saveCache({
        ...decision,
        secondaryId: chosenSecondaryId,
        secondaryCandidates: uniq([chosenSecondaryId, ...decision.secondaryCandidates]),
      });
    }

    modePicks.push(mkPick(chosenSecondaryId, secondaryCopy.displayTitle, secondaryConfidence, secondaryReason));

	    const curatorNote = buildCuratorNote({
	      locale,
	      primaryModeId: decision.primaryId,
	      primaryModeTitle: primaryMode?.title ?? primaryBuilt.title,
	      constraints,
	      ragUsed: ragAssistUsed,
	      seedTitle: seedOverride?.title ?? null,
	      avoidedGenres: await userTopGenresPromise,
	    });

	    const sets: any[] = [
	      {
	        id: decision.primaryId,
	        title: primaryCopy.displayTitle,
	        internalTitle: primaryBuilt.title,
	        displayTitle: primaryCopy.displayTitle,
	        displaySubtitle: primaryCopy.displaySubtitle,
	        curatorNote,
	        locale,
	        modeId: decision.primaryId,
	        confidence: modePicks[0].confidence,
	        reason: modePicks[0].reason,
	        items: primaryBuilt.items,
	      },
	      {
	        id: chosenSecondaryId,
	        title: secondaryCopy.displayTitle,
	        internalTitle: chosenSecondaryBuilt.title,
	        displayTitle: secondaryCopy.displayTitle,
	        displaySubtitle: secondaryCopy.displaySubtitle,
	        curatorNote,
	        locale,
	        modeId: chosenSecondaryId,
	        confidence: modePicks[1].confidence,
	        reason: modePicks[1].reason,
	        items: chosenSecondaryBuilt.items,
	      },
	    ];

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

      // Router quality telemetry for secondary-rail diversity and overlap monitoring.
      await client.rpc("log_concierge_run", {
        p_kind: "recommend_router_v2",
        p_status: "success",
        p_input_chars: text.length,
        p_items_count: chosenSecondaryBuilt.items.length,
        p_error: JSON.stringify({
          primary_mode_id: decision.primaryId,
          secondary_mode_id: chosenSecondaryId,
          secondary_candidates_count: preferredSecondaryIds.length,
          secondary_overlap_ratio: Number(chosenEval.overlapRatio.toFixed(4)),
          secondary_overlap_count: chosenEval.overlapCount,
          secondary_item_count: chosenSecondaryBuilt.items.length,
          secondary_acceptable: chosenEval.acceptable,
        }),
      });
    } catch {
      // best-effort
    }

	    const message = (() => {
	      if (sets.length === 0) {
	        return locale === "de"
	          ? "Sag mir eine Stimmung oder eine klare Kante (kurz, ohne Romance, ein Jahr) — ich kuratiere es neu für dich."
	          : "Give me a mood or one constraint (short, no romance, a year) and I’ll curate it — new to you.";
	      }
	      // Backwards-compat: older clients can show the curator note in plain text.
	      return curatorNote;
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
	      locale,
	      curatorNote,
	      categories,
	      modes: modePicks,
	      sets,
	      // Backwards compat: clients that only understand `items` still get a useful response.
      items: allItems,
      message,
      narrated: narrate,
      // Constraint info for WhyThisSheet and debugging.
      constraints: constraints.why.length > 0 ? {
        excluded_genres: constraints.excluded_genres.length > 0 ? constraints.excluded_genres : undefined,
        format: constraints.format ?? undefined,
        max_episodes: constraints.max_episodes ?? undefined,
        min_episodes: constraints.min_episodes ?? undefined,
        year_min: constraints.year_min ?? undefined,
        year_max: constraints.year_max ?? undefined,
        why: constraints.why,
      } : undefined,
      assist: ragAssistEnabled
        ? {
          ragUsed: ragAssistUsed,
          seedEntityId: ragSeedEntityId ?? undefined,
        }
        : undefined,
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

    const ip = clientIp(req);

    // Parallelize auth, rate-limit check, and body parsing — they are independent.
    const [authResult, rlResult, body] = await Promise.all([
      client.auth.getUser(),
      client.rpc("check_concierge_rate_limit", {
        p_kind: "apply",
        p_ip: ip,
        p_window_seconds: null,
        p_max_user: null,
        p_max_ip: null,
      }),
      req.json().catch(() => ({})),
    ]);

    const { data: userData, error: userErr } = authResult;
    if (userErr || !userData?.user) return json({ error: "Unauthorized" }, { status: 401 });
    const userId = userData.user.id;

    const rl = rlResult.data;
    if (rl && rl.allowed === false) {
      return json(
        { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
        { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
      );
    }
    const items: any[] = Array.isArray(body?.items) ? body.items : [];
    if (!Array.isArray(body?.items) || items.length > 100) {
      return json({ error: "Too many items (max 100)" }, { status: 400 });
    }
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
    const skipped: any[] = [];
    const conflicts: any[] = [];
    const errors: any[] = [];

    // Process all items in parallel — each targets a different media_id so they're independent.
    const results = await Promise.all(items.map(async (it) => {
      const mediaType: MediaType | null = it?.mediaType === "ANIME" || it?.mediaType === "MANGA" ? it.mediaType : null;
      const mediaId: number | null = clampInt(it?.mediaId, 1, 2_000_000_000);
      let status: ListStatus | null =
        typeof it?.status === "string" ? (it.status.toUpperCase() as ListStatus) : null;

      if (!mediaType || !mediaId || !status) {
        return { ok: false as const, kind: "error" as const, item: it, error: "Invalid mediaType/mediaId/status" };
      }

      // Reconciliation action: 'add' (default for backwards compat), 'update', or 'skip'
      const importAction: "add" | "update" | "skip" =
        it?.action === "update" ? "update" : it?.action === "skip" ? "skip" : "add";

      try {
        // --- Handle skip action ---
        if (importAction === "skip") {
          await client.from("import_session_items").insert({
            session_id: sessionId,
            raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
            parsed: it?.parsed ?? {},
            candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
            chosen: { mediaType, mediaId },
            action: null,
            confidence: typeof it?.confidence === "number" ? it.confidence : 0,
            state: "skipped",
            import_action: "skip",
          });
          return { ok: true as const, kind: "skip" as const, mediaType, mediaId, status };
        }

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

          // Re-check current state (TOCTOU protection for updates)
          const before = await client
            .from("anime_user_lists")
            .select("list_type,progress,rating,notes")
            .eq("user_id", userId)
            .eq("anime_id", mediaId)
            .maybeSingle();
          if (before.error) throw before.error;

          // TOCTOU check for updates: verify current state matches what client expected
          if (importAction === "update" && it?.expectedExisting) {
            const exp = it.expectedExisting;
            const cur = before.data;
            if (!cur) {
              // Entry was deleted between parse and apply — conflict
              return { ok: false as const, kind: "conflict" as const, mediaType, mediaId, error: "Entry no longer exists (deleted since parse)" };
            }
            if (
              (exp.status && cur.list_type !== exp.status) ||
              (exp.progress_episodes != null && cur.progress !== exp.progress_episodes)
            ) {
              await client.from("import_session_items").insert({
                session_id: sessionId,
                raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
                parsed: it?.parsed ?? {},
                candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
                chosen: { mediaType, mediaId },
                action: { table: "anime_user_lists", key: { user_id: userId, anime_id: mediaId }, before: cur, after: null },
                confidence: typeof it?.confidence === "number" ? it.confidence : 0,
                state: "error",
                import_action: "update",
                error: "TOCTOU conflict: current state changed since parse",
              });
              return { ok: false as const, kind: "conflict" as const, mediaType, mediaId, error: "State changed since parse — review and retry" };
            }
          }

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

          // Store previous_values for undo support on updates
          const previousValues = importAction === "update" && before.data ? before.data : null;

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
            import_action: importAction,
            previous_values: previousValues,
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

          // Re-check current state (TOCTOU protection for updates)
          const before = await client
            .from("manga_user_lists")
            .select("list_type,progress,rating,notes")
            .eq("user_id", userId)
            .eq("manga_id", mediaId)
            .maybeSingle();
          if (before.error) throw before.error;

          // TOCTOU check for updates: verify current state matches what client expected
          if (importAction === "update" && it?.expectedExisting) {
            const exp = it.expectedExisting;
            const cur = before.data;
            if (!cur) {
              return { ok: false as const, kind: "conflict" as const, mediaType, mediaId, error: "Entry no longer exists (deleted since parse)" };
            }
            if (
              (exp.status && cur.list_type !== exp.status) ||
              (exp.progress_chapters != null && cur.progress !== exp.progress_chapters)
            ) {
              await client.from("import_session_items").insert({
                session_id: sessionId,
                raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType}:${mediaId}`,
                parsed: it?.parsed ?? {},
                candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
                chosen: { mediaType, mediaId },
                action: { table: "manga_user_lists", key: { user_id: userId, manga_id: mediaId }, before: cur, after: null },
                confidence: typeof it?.confidence === "number" ? it.confidence : 0,
                state: "error",
                import_action: "update",
                error: "TOCTOU conflict: current state changed since parse",
              });
              return { ok: false as const, kind: "conflict" as const, mediaType, mediaId, error: "State changed since parse — review and retry" };
            }
          }

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

          const previousValues = importAction === "update" && before.data ? before.data : null;

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
            import_action: importAction,
            previous_values: previousValues,
          });
        }

        return { ok: true as const, kind: importAction as "add" | "update", mediaType, mediaId, status };
      } catch (e) {
        await client.from("import_session_items").insert({
          session_id: sessionId,
          raw: typeof it?.raw === "string" ? it.raw.slice(0, 500) : `${mediaType ?? "UNKNOWN"}:${mediaId ?? "?"}`,
          parsed: it?.parsed ?? {},
          candidates: Array.isArray(it?.candidates) ? it.candidates.slice(0, 12) : [],
          chosen: mediaType && mediaId ? { mediaType, mediaId } : null,
          action: null,
          confidence: typeof it?.confidence === "number" ? it.confidence : 0,
          state: "error",
          import_action: importAction,
          error: ((e as Error).message ?? String(e)).slice(0, 500),
        });
        return { ok: false as const, kind: "error" as const, mediaType, mediaId, error: (e as Error).message ?? String(e) };
      }
    }));

    // Collect results preserving original order.
    for (const r of results) {
      if (r.ok && r.kind === "skip") {
        skipped.push({ mediaType: r.mediaType, mediaId: r.mediaId });
      } else if (r.ok) {
        applied.push({ mediaType: r.mediaType, mediaId: r.mediaId, status: r.status, action: r.kind });
      } else if (r.kind === "conflict") {
        conflicts.push({ mediaType: r.mediaType, mediaId: r.mediaId, error: r.error });
      } else if ("item" in r) {
        errors.push({ item: r.item, error: r.error });
      } else {
        errors.push({ mediaType: r.mediaType, mediaId: r.mediaId, error: r.error });
      }
    }

    await client.from("import_sessions").update({
      status: errors.length || conflicts.length ? "failed" : "applied",
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

    return json({ success: errors.length === 0 && conflicts.length === 0, sessionId, applied, skipped, conflicts, errors });
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

  // H4: Only allow undo of the most recent session for this user
  const latestSession = await client
    .from("import_sessions")
    .select("id")
    .eq("user_id", userId)
    .eq("status", "applied")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (latestSession.error) return json({ error: latestSession.error.message }, { status: 500 });
  if (!latestSession.data) return json({ error: "No applied session to undo" }, { status: 404 });
  if (latestSession.data.id !== sessionId) {
    return json({ error: "Can only undo the most recent import session" }, { status: 409 });
  }

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
    .select("id,chosen,action,state,import_action,previous_values")
    .eq("session_id", sessionId);
  if (itemsRes.error) return json({ error: itemsRes.error.message }, { status: 500 });

  const reverted: any[] = [];
  const warnings: any[] = [];
  const errors: any[] = [];

  for (const row of itemsRes.data ?? []) {
    try {
      const chosen = row?.chosen ?? {};
      const mediaType: MediaType | null = chosen?.mediaType === "ANIME" || chosen?.mediaType === "MANGA" ? chosen.mediaType : null;
      const mediaId: number | null = clampInt(chosen?.mediaId, 1, 2_000_000_000);
      if (!mediaType || !mediaId) continue;

      const itemAction = row?.import_action ?? "add";
      const actionData = row?.action ?? {};
      const afterData = actionData?.after ?? null;
      const previousValues = row?.previous_values ?? null;

      // Skip items that were skipped during import — nothing to undo
      if (itemAction === "skip") continue;

      if (mediaType === "ANIME") {
        // Verify current state matches what we set (detect manual edits / overlapping imports)
        const current = await client
          .from("anime_user_lists")
          .select("list_type,progress,rating,notes")
          .eq("user_id", userId)
          .eq("anime_id", mediaId)
          .maybeSingle();

        if (current.error) throw current.error;

        // If the entry no longer exists or was modified since our import, warn instead of blindly reverting
        if (afterData && current.data) {
          const cur = current.data;
          if (cur.list_type !== afterData.list_type || cur.progress !== afterData.progress) {
            warnings.push({ mediaType, mediaId, reason: "Entry was modified since import — skipping undo to avoid data loss" });
            continue;
          }
        }

        if (itemAction === "update" && previousValues) {
          // Restore previous values for updates
          const payload = {
            user_id: userId,
            anime_id: mediaId,
            list_type: (previousValues.list_type as ListStatus) ?? "PLANNING",
            progress: previousValues.progress ?? null,
            rating: previousValues.rating ?? null,
            notes: previousValues.notes ?? null,
          };
          const up = await client
            .from("anime_user_lists")
            .upsert(payload as any, { onConflict: "user_id,anime_id" });
          if (up.error) throw up.error;
          reverted.push({ mediaType, mediaId, undoType: "restored" });
        } else {
          // For adds (or legacy items without import_action): delete the entry
          const before = actionData?.before ?? null;
          if (!before) {
            const del = await client
              .from("anime_user_lists")
              .delete()
              .eq("user_id", userId)
              .eq("anime_id", mediaId);
            if (del.error) throw del.error;
            reverted.push({ mediaType, mediaId, undoType: "deleted" });
          } else {
            const payload = {
              user_id: userId,
              anime_id: mediaId,
              list_type: (before.list_type as ListStatus) ?? "PLANNING",
              progress: before.progress ?? null,
              rating: before.rating ?? null,
              notes: before.notes ?? null,
            };
            const up = await client
              .from("anime_user_lists")
              .upsert(payload as any, { onConflict: "user_id,anime_id" });
            if (up.error) throw up.error;
            reverted.push({ mediaType, mediaId, undoType: "restored" });
          }
        }
      } else {
        // MANGA
        const current = await client
          .from("manga_user_lists")
          .select("list_type,progress,rating,notes")
          .eq("user_id", userId)
          .eq("manga_id", mediaId)
          .maybeSingle();

        if (current.error) throw current.error;

        if (afterData && current.data) {
          const cur = current.data;
          if (cur.list_type !== afterData.list_type || cur.progress !== afterData.progress) {
            warnings.push({ mediaType, mediaId, reason: "Entry was modified since import — skipping undo to avoid data loss" });
            continue;
          }
        }

        if (itemAction === "update" && previousValues) {
          const payload = {
            user_id: userId,
            manga_id: mediaId,
            list_type: (previousValues.list_type as ListStatus) ?? "PLANNING",
            progress: previousValues.progress ?? null,
            rating: previousValues.rating ?? null,
            notes: previousValues.notes ?? null,
          };
          const up = await client
            .from("manga_user_lists")
            .upsert(payload as any, { onConflict: "user_id,manga_id" });
          if (up.error) throw up.error;
          reverted.push({ mediaType, mediaId, undoType: "restored" });
        } else {
          const before = actionData?.before ?? null;
          if (!before) {
            const del = await client
              .from("manga_user_lists")
              .delete()
              .eq("user_id", userId)
              .eq("manga_id", mediaId);
            if (del.error) throw del.error;
            reverted.push({ mediaType, mediaId, undoType: "deleted" });
          } else {
            const payload = {
              user_id: userId,
              manga_id: mediaId,
              list_type: (before.list_type as ListStatus) ?? "PLANNING",
              progress: before.progress ?? null,
              rating: before.rating ?? null,
              notes: before.notes ?? null,
            };
            const up = await client
              .from("manga_user_lists")
              .upsert(payload as any, { onConflict: "user_id,manga_id" });
            if (up.error) throw up.error;
            reverted.push({ mediaType, mediaId, undoType: "restored" });
          }
        }
      }
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

    return json({ success: errors.length === 0, sessionId, reverted, warnings, errors });
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

## Change Log

### 2026-02-24 — Fix Detail Page Scrolling Issues
- **Vertical dead zone fix**: Added `.padding(.bottom, -safeTop)` after `.offset(y: -safeTop)` on hero sections in both `AnimeDetailView.swift` and `MangaDetailView.swift`. The offset is visual-only and didn't shrink the layout frame, creating a phantom gap at the bottom of the scroll content equal to `safeTop` (~59pt). The negative bottom padding compensates.
- **Horizontal scroll fix**: Removed `.kuroSwipeExclusionZone()` from `SimilarSection` (AnimeDetailView:332) and `MangaSimilarSection` (MangaDetailView:289). These sections only appear inside `.sheet()` presentations where the root pager's gesture doesn't apply. The exclusion zone added a competing `DragGesture(minimumDistance: 4)` that fought with the native horizontal ScrollView gesture and the `.kuroDeliberateTap` gesture on each card, preventing horizontal scrolling.

### 2026-02-25 — Inline Auth Validation + Email Confirmation Disabled

Added inline email/password validation to `AuthView.swift` and disabled email confirmation flow.

Backend (migration `20260225100000_check_email_exists_rpc.sql`):
- New SECURITY DEFINER function `check_email_exists(email_input)` querying `auth.users` to check if an email is already registered.
- Granted to `anon` + `authenticated` roles.

iOS — AuthView inline validation:
- `AuthView.swift`: Two new enums — `EmailStatus` (.empty, .invalidFormat, .checking, .taken, .available) and `PasswordStatus` (.empty, .tooShort, .valid).
- Real-time email format validation via regex on keystroke.
- Debounced 500ms uniqueness check via `check_email_exists` RPC (sign-up mode only).
- Inline status indicators: hint text + checkmarks inside text fields.
- Removed "Check your email to confirm your account" post-signup message.
- `canSubmit` now gates on validation state (both fields must pass).

iOS — SupabaseService auth changes:
- `SupabaseService.swift`: Added `checkEmailExists(email:)` method calling the new RPC.
- Removed `redirectTo: Self.authCallbackURL` from `signUpWithEmail` (email confirmation being disabled).

Dashboard steps reduced:
- Previous: 3 manual Supabase Dashboard steps (redirect URLs, email templates, SMTP config).
- Now: 1 step — disable email confirmations in Auth settings. Redirect URLs, email templates, and SMTP config are no longer launch blockers.

### 2026-02-28 — Fix Concierge Import False Success Toast

**Bug**: Both `autoApplyImport()` and `confirmImport()` in `ConciergeView.swift` showed a success toast ("N items added to collection") unconditionally after calling the `concierge-apply` edge function, even when the server returned `success: false`. Users saw "added to collection" but items weren't actually added.

**Root cause**: The `ConciergeApplyResponse.success` field was properly decoded but never checked. The toast fired based on the API call completing without throwing, not on the actual result.

**Fix (ConciergeView.swift)**:
- `autoApplyImport()`: Added `guard res.success` check before showing success toast. On failure: shows error toast with server's error detail (`res.errors?.first?.error`).
- `confirmImport()`: Same fix. On success: uses `res.applied?.count` for accurate count and `res.applied` action fields for add/update breakdown, instead of client-side `chosen.count`.
- Both paths: success toast only shown when `res.success == true`.

**Investigation notes**: Confirmed production `anime_user_lists.user_id` and `manga_user_lists.user_id` are TEXT type (verified via Supabase OpenAPI endpoint), not INTEGER as in the legacy SQL file. The type mismatch hypothesis was ruled out — the schema was already corrected during initial remote setup. The iOS-side fix correctly surfaces whatever server error caused the failure.

Totals: 0 new files, 1 modified Swift file, 0 new migrations. 64 Swift files, 143 migrations.

### 2026-02-27 — UX Density + Clarity Improvements

4 changes across 4 files to reduce cognitive overload and improve first-time clarity.

**EditorialDiscoverView.swift — Section reduction + "Show More" expansion:**
- Reordered and split 13 sections into 6 primary (always visible) + 7 secondary (behind "Show More" button).
- Primary sections (by user value): New to You → Airing Today → Essential Anime → New to You (Manga) → Trending → Essential Manga.
- Secondary sections: Classics → Current Season → Top Rated → Just Added → Manga Classics → Trending Manga → Top Rated Manga.
- "Show More" button: monochrome editorial style, shows "N MORE SECTIONS" with chevron, expands with `KuroAnimation.editorial`, persists to UserDefaults (`kuro_discover_show_more`) as one-way flag.
- Data loading unchanged — all arrays still fetched. This is UI-only progressive disclosure.

**ConciergeComponents.swift — First-time contextual hint:**
- `ConciergeIntroCard` now reads `UserDefaults.standard.bool(forKey: "kuro_concierge_used")`.
- First-time users see expanded two-row hint: "Import a list" (with concrete description) + "Get recommendations" (with example "dark, short, no gore").
- Returning users see slim text: "Import your list, or describe a mood."
- Subtitle updated to "Imports + recommendations" / "Imports + Empfehlungen".
- New `hintRow(icon:title:detail:)` private helper.

**ConciergeView.swift — First-use flag + error dedup:**
- Added 3 lines in `send()` to set `kuro_concierge_used` UserDefaults flag after first message.
- Fixed `handleError()` double error display: guardrail errors → inline text only (persistent); network/server errors → toast only (transient, auto-dismiss 3s). Never both simultaneously.

**ClubDetailView.swift — Compact reaction row:**
- Items with zero reactions now show `ClubReactionRowCompact` (single smiley icon) instead of full 4-emoji `ClubReactionRow`.
- Tapping the compact icon expands to full reaction row with `KuroAnimation.fast`.
- Items with existing reactions show full row immediately.
- New `ClubReactionRowCompact` private struct.

Totals: 0 new Swift files, 2 modified Swift files, 1 new migration. 64 Swift files, 143 migrations.

### 2026-02-26 — Simplify KuroDeliberateTap Gesture (Fix Scroll + Tap Reliability)

Replaced the over-aggressive `DragGesture(minimumDistance: 0)` tap recognizer in `KuroDeliberateTap.swift` with a simple `.onTapGesture` + single `suppressCardTaps` environment check.

**Root cause**: The `swipe_tap_guard_v1` feature flag at 100% rollout enabled a custom gesture system where card taps used a `DragGesture(minimumDistance: 0)` with 5 sequential guards (6pt movement threshold, 80ms minimum dwell, 220ms post-rail cooldown, `suppressCardTaps` check, `didCancelTap` check). This caused three problems: (a) the DragGesture competed with ScrollView for vertical drags, breaking vertical scrolling; (b) the over-strict thresholds rejected ~30% of legitimate taps; (c) the competing drag recognizer interfered with horizontal rail scrolling.

**KuroDeliberateTap.swift**: Replaced `DragGesture(minimumDistance: 0)` + 5 guards with `.onTapGesture` + single `suppressCardTaps` environment check. The `.kuroDeliberateTap {}` API is unchanged — no call-site changes needed.

**KuroGesturePolicy.swift**: Removed 3 unused tap-related constants (`deliberateTapMinDwellMs`, `deliberateTapMaxMovementPt`, `dragCancelMovementPt`). Kept pager constants (`postSwipeTapCooldownMs`, `fastFlingPredictedDxPt`, `fastFlingDirectionRatio`) which are still used by the swipe pager.

**No changes** to `KuroGestureCoordinator.swift`, `KuroPagingGesture.swift`, `ContentView.swift`, or any card call sites.

**Feature flag**: `swipe_tap_guard_v1` stays at 100% — it gates the pager's `suppressCardTaps` logic (correct and still needed), not the tap recognizer itself.

Totals: 0 new files, 2 modified Swift files, 0 new migrations. 64 Swift files, 143 migrations.

### 2026-02-28 — Fix: Concierge import intent detection gaps
- **ConciergeView.swift** `looksLikeImport()`: Added missing import detection patterns — standalone "watched"/"paused"/"saw"/"seen", soft-partial markers ("halfway"/"midway"/"partway"), "i'm reading"/"im reading", German past tense ("geschaut"/"gesehen"/"gelesen"/"zur hälfte"). Previously "Watched jujutsu kaisen halfway through" was misrouted to recommendations because the client gatekeeper only checked "i watched" (not standalone "watched") and had no soft-partial marker detection. The server-side parser (`concierge-parse`) already handled these correctly — this fix aligns the iOS gatekeeper with the server.

### 2026-02-28 — FM-powered intent classification for Concierge
- **ConciergeView.swift**: Replaced keyword-only intent routing with hybrid FM-primary + keyword-fallback architecture. When Apple Foundation Models are available and `fm_assist_v1` flag is enabled, `assistIntent()` (already implemented in `AppleFMService.swift`) is now called as the primary intent classifier. It classifies user text into 6 intents (`import`, `recommend_vibe`, `recommend_seed`, `library_query`, `club_action`, `unknown`) with confidence scoring. Confidence threshold: 0.65 — below that, falls back to `looksLikeImport()` keywords. FM failure/timeout also falls back to keywords. Non-FM devices (pre-iOS 26) use keyword routing unchanged.
- **New helper**: `routeByKeywords(text:sendStartedAt:)` — extracted existing keyword logic into a named function shared by both the FM fallback path and the non-FM path.
- **Analytics**: `intent_detected` event now includes `"source": "fm"` or `"source": "keywords"` field to compare routing accuracy in production. FM path also logs `confidence` value.
- **`looksLikeImport()` extracted** to `TextNormalization.looksLikeImport()` (+ `segmentLooksTitleLike()`) for testability. ConciergeView's private `looksLikeImport()` now delegates to it. Logic unchanged.
- **Unit tests added**: 14 tests in `ImportIntentTests` suite covering keyword detection (status keywords, past tense, I-prefix, soft-partial markers, progress patterns, multi-line, comma-separated, German import/vibe, short input, segment heuristics).
- **UI test added**: `testConciergeImportRouting` — types "Watched Jujutsu Kaisen halfway through" in Concierge with `--ff-off=fm_assist_v1` (keyword fallback forced), verifies CONFIRM button appears (import flow, not recommendations).
- **Scheme updated**: KuroTests target added to Kuro.xcscheme test action (was missing — only KuroUITests was wired).
- **No new Swift files, no backend changes.** 64 Swift files, 143 migrations.

### 2026-03-01 — FM intent classification post-review remediation
- **P1-a: Stale code snapshot fixed** in `CURRENT_APP_STATE.md` — replaced 260-line embedded `send()` + `looksLikeImport()` + `segmentLooksTitleLike()` code dump (still showing pre-FM keyword routing) with a concise 6-line summary pointing to the actual source. The change log already documents the FM wiring; embedding full code created a maintenance burden and was already stale.
- **P1-b: `fm_assist_v1` rollout documented** — added `fm_assist_v1 (0%, staged)` to the Concierge intent routing section with planned rollout: 0% → 10% canary → 50% → 100%. The flag was already in `FeatureFlags.swift` and the change log but wasn't called out in the feature description.
- **8 edge case tests added** to `KuroTests/KuroTests.swift` (`ImportIntentTests` suite, now 22 tests total):
  - `testEmptyAndWhitespace` — empty string and whitespace-only input
  - `testGermanVibeWithStaffel` — German vibe marker present but staffel/folge overrides to import
  - `testCaseInsensitive` — WATCHED/COMPLETED uppercase matching
  - `testRegexBoundaries` — s1e1, s12e1234, 1x50 regex edge cases
- **P2 clarity comments added**:
  - `ConciergeView.swift`: ordering comment above `shouldAskClarifyingQuestion()` explaining it runs before FM classification
  - `ConciergeInputField.swift`: distinction comment above `looksLikeImportListText()` explaining separation from `TextNormalization.looksLikeImport()`
- **No logic changes, no new files, no backend changes.** 64 Swift files, 143 migrations. All 22 unit tests pass.

### 2026-03-01 — Offline Mode Hardening (6 gaps fixed)

Backend connectivity audit found 6 offline handling gaps. All fixed across 10 files, no new files, no backend changes.

**SupabaseService.swift — Cache fallback on network failure:**
- `fetchAnimeById` and `fetchMangaById` now stash disk cache as `diskFallback` before attempting network. On catch: if disk fallback exists, return it (+ populate memory cache); else rethrow. Success path unchanged.
- KuroPerf records `"disk_fallback"` message when fallback path taken.

**NetworkMonitor.swift — Reconnection signal:**
- Added `reconnectionGeneration: Int` property, incremented in `pathUpdateHandler` when `connected == true`.

**ContentView.swift — Auto-refresh on reconnect:**
- `KuroMainView` observes `.onChange(of: networkMonitor.reconnectionGeneration)` to refresh the active page: Discover (force bundle), Collection (user lists + feed), Clubs (notifications). Concierge/Browse skip (user-driven).

**BrowseView.swift — Offline error state:**
- Added `loadError` state. When search returns empty AND offline, shows `wifi.slash` icon + "COULDN'T LOAD" + retry button. Clears on successful load.

**ConciergeInputField.swift — Send guard:**
- `canSend` now requires `networkMonitor.isConnected`. Placeholder shows "Offline" when disconnected. Accessibility hint says "You're offline".

**AddToListSheet.swift — Save guard:**
- Save button `.disabled` when offline. "OFFLINE — SAVE DISABLED" hint text shown.

**ClubDetailView.swift — Create guards:**
- All 4 create rail/poll buttons `.disabled(!networkMonitor.isConnected)`. Existing vote/reaction error toasts unchanged.

**MediaDetailSheet.swift — Retry button:**
- Both `AnimeDetailLoaderView` and `MangaDetailLoaderView` get `retryCount` state + RETRY button. `.task(id:)` keyed on `"\(id)-\(retryCount)"` to re-trigger fetch.

**EditorialCollectionView.swift — Network-aware error + stale indicator:**
- Error block shows `wifi.slash`/"YOU'RE OFFLINE" when disconnected, `exclamationmark.triangle`/"COULDN'T LOAD COLLECTION" when connected. RETRY button calls `fetchUserLists` + `fetchCollectionFeed`.
- "SHOWING CACHED DATA" label when offline but content is displayed.

**EditorialDiscoverView.swift — Stale indicator:**
- "SHOWING CACHED DATA" label at top of content when offline and `hasAnyContent`.

Totals: 0 new files, 10 modified files (3 services, 7 views), 0 new migrations. 64 Swift files, 143 migrations.

### 2026-03-01 — Streaming Availability v1 ("Where to Watch/Read")

New feature: streaming/reading provider availability on cards, detail pages, collection filters, and club shared-provider views. Gated behind `streaming_availability_v1` feature flag at 0% rollout.

**Backend (migration `20260301100000_streaming_availability_v1.sql`):**
- New table `streaming_services`: canonical registry of streaming/reading platforms (19 seed rows covering Crunchyroll, Funimation, Netflix, etc.)
- New table `user_streaming_services`: per-user service selection + language preference, RLS scoped to `auth.uid()`
- 3 new RPCs: `batch_providers_for_media` (batch lookup for media IDs against user's services), `club_shared_providers` (intersection of all club members' providers), `save_user_streaming_services` (upsert user selections + language)
- GDPR: `user_streaming_services` added to `delete_user_concierge_data` cascade

**SupabaseService.swift (~120 lines added):**
- Provider cache + batch prefetch method for provider data alongside existing friend count prefetch
- CRUD for user streaming services (save, fetch registry, fetch user selections)
- Club shared providers fetch
- Bootstrap: streaming services loaded during auth bootstrap when flag enabled

**SupabaseRPCParams.swift:**
- 2 new param structs: `RPCBatchProvidersParams`, `RPCSaveStreamingServicesParams`

**FeatureFlags.swift:**
- New accessor: `isStreamingAvailabilityV1Enabled`

**EditorialCollectionView.swift:**
- Service + language filter pills (tri-state toggle) in collection filter bar
- Provider prefetch alongside friend count prefetch on page load

**KuroRefinedCard.swift:**
- Provider badge overlay on `KuroPortraitCard` + `KuroCompactCard` (shows service icons when available)

**ProfileView.swift:**
- Services preview card in profile settings
- New `StreamingServicePickerSheet` for selecting streaming services + language
- New `ServiceToggleRow` component

**ClubDetailView.swift:**
- Shared availability toggle on club rails
- Coverage text showing how many members can access each title
- Dimmed cards for titles not available on shared providers
- Rail prefetch for provider data

**Other changes:**
- `normalizedExternalLanguage` visibility changed from `private` to `internal` (needed by streaming filter logic)
- Hardcoded allowlist arrays annotated with `TODO` for removal when flag reaches 100%

Totals: 0 new Swift files, 7 modified Swift files, 1 new migration. 64 Swift files, 144 migrations.

### 2026-03-03 — UX Wave 1: P0 Quick Wins (6 fixes across 5 files)

**EditorialDiscoverView.swift — Featured hero card:**
- `KuroHeroCard` now renders at the top of the Discover page (before "AIRING TODAY") when `vm.featured != nil`
- Uses `currentWidth - 40` for width (matching 20pt horizontal padding)

**BrowseView.swift — Empty state with filter guidance:**
- `BrowseEmptyState` now receives `activeFilterCount`, `activeFilterSummary`, and `onClearFilters` closure
- When filters are active: shows "NO MATCHES FOR N FILTER(S)" + summary of active filters + "CLEAR FILTERS" black capsule button
- When no filters active: shows original "NO MATCHES / Try different filters" text
- Added `activeFilterCount` computed property and `activeFiltersLabel` for human-readable filter summary
- Clear button resets all 6 filter states with `.easeInOut(duration: 0.2)` animation + haptic
- Added `loadError` state with offline error screen (wifi.slash + retry)

**EditorialCollectionView.swift — Dropped filter:**
- Added `case dropped = "DROPPED"` to `CollectionFilter` enum, mapped to `ListStatus.dropped`
- Auto-renders in filter bar via `CaseIterable`

**EditorialCollectionView.swift — Anime/Manga type filter:**
- New `MediaTypeFilter` enum (`.all` / `.anime` / `.manga`)
- `@State private var selectedMediaType` with Menu pill in sort bar
- `displayItems` filters by `selectedMediaType` before streaming/language filters

**ConciergeComponents.swift — CONFIRM 0 explanation:**
- New `confirmZeroExplanation` computed property on `ConciergeConfirmBubble`
- Three contextual messages: "All items already in your library" (all `.skip`), "All items excluded — tap to re-include" (all excluded), "Select matches above to continue" (fallback)
- Shows below disabled CONFIRM 0 button in `.kuroCaption(weight: .light)` + `.kuroTextTertiary`
- Added `isApplying` state with spinner + "APPLYING" text on confirm button
- Added applied state: summary text + UNDO / VIEW COLLECTION buttons

**AnimeDetailView.swift + MangaDetailView.swift — UIScreen.main removal:**
- `SimilarSection` and `MangaSimilarSection` now accept `containerWidth: CGFloat` parameter
- Replaced deprecated `UIScreen.main.bounds.width` with `containerWidth` from parent GeometryReader
- Zero `UIScreen.main` references remaining in detail pages

Totals: 0 new files, 5 modified Swift files, 0 new migrations. 64 Swift files, 144 migrations.

### 2026-03-03 — UX Wave 1 fix: Gate streaming availability calls behind feature flag

**AnimeDetailView.swift + MangaDetailView.swift:**
- `fetchProviderAvailabilityV2` and `enqueueAvailabilityRefreshIfStale` in `refreshLinks()` now gated behind `FeatureFlags.shared.isStreamingAvailabilityV1Enabled`
- `bestProviderAvailabilityNote` returns `nil` when flag is off
- Matches gating pattern used in EditorialCollectionView and SupabaseService bootstrap

Totals: 0 new files, 2 modified Swift files. 64 Swift files, 144 migrations.

### 2026-03-03 — UX Wave 2: Medium-Effort P0s (3 changes across 3 files)

**ConciergeView.swift — Wire empty-state starter actions:**
- Line 194: `includeStarter: false` → `includeStarter: true` — enables `ConciergeStarterActions` (4 pills: From Library, From Clipboard, Curate, Show Examples) when `messages.isEmpty`
- Line 184: `showsIntentDeck: messages.isEmpty` → `showsIntentDeck: false` — disables redundant `WhisperEmptyState` moon overlay that would overlap the starter pills
- All callbacks were already bound to real methods (pasteFromClipboard, importFromLibrary, seedExampleImport, seedExampleVibe)

**EditorialDiscoverView.swift — Anime/manga segmentation toggle:**
- New `DiscoverMediaTypeFilter` enum (`.all` / `.anime` / `.manga`)
- `@State private var selectedMediaType` with Menu pill (matching Collection pattern: `rectangle.stack` icon, 9pt medium, 0.8 tracking)
- All 14 sections wrapped with type guards:
  - ANIME (9): featured, airingToday, newToYou, essentials, trending, classics, currentSeason, topRated, newlyAdded
  - MANGA (5): newToYouManga, essentialsManga, classicsManga, trendingManga, topRatedManga
- "Show More" button and secondary sections also respect the media type filter

**ConciergeComponents.swift + ConciergeView.swift — Conversation persistence:**
- `ConciergeMessage.Role` now conforms to `String, Codable`
- New `ConciergeMessagePersisted: Codable` struct — slim text-only wrapper (id, role, text, sourceUserText, timestamp)
- New `ConciergeConversationCache` enum following `KuroDiskDetailCache` pattern:
  - Folder: `kuro.concierge.v1`, single file `session.json`, 7-day max age
  - `save()` / `load()` / `clear()` — all async, best-effort, atomic writes
- ConciergeView lifecycle wiring:
  - `.task`: restores last session on first appear (guarded by `hasRestoredSession`)
  - `.onDisappear`: saves snapshot
  - `.onChange(of: scenePhase)`: saves on background/inactive
- "NEW CHAT" capsule button (right-aligned, `plus.message` icon) at top of message list when messages exist
- `startNewChat()` clears messages with animation, resets all import/recommendation state, calls cache clear
- Restored messages appear as text-only bubbles (no interactive import cards — expected for v1)

Totals: 0 new files, 3 modified Swift files, 0 new migrations. 64 Swift files, 144 migrations.

### 2026-03-03 — Post-review fixes: cache user-scoping + browse error state

**ConciergeComponents.swift — P1 fix: scope conversation cache by user ID:**
- `ConciergeConversationCache` now requires `userId: String` on `save()`, `load()`, and `clear()`
- Cache path changed from `kuro.concierge.v1/session.json` to `kuro.concierge.v1/{userId}/session.json`
- New `clearAll()` method removes entire cache folder (all users)

**SupabaseService.swift — Clear cache on sign-out:**
- `signOut()` now calls `ConciergeConversationCache.clearAll()` before resetting user state
- Prevents cross-account message leaks on shared devices

**ConciergeView.swift — Pass userId to all cache calls:**
- Load, save (onDisappear + scenePhase), and clear (startNewChat) all pass `supabaseService.currentUserId`
- Gracefully no-ops when userId is nil (signed-out state)

**BrowseView.swift — P2 fix: explicit error state assignment:**
- Both anime and manga reload branches changed from conditional set/reset to single assignment: `loadError = page0.isEmpty && !networkMonitor.isConnected`
- Prevents error state latching when network returns but results are legitimately empty

Totals: 0 new files, 4 modified Swift files. 64 Swift files, 144 migrations.

### 2026-03-03 — UX Wave 3: P1 Quick Wins (13 fixes across 8 files)

**EditorialCollectionView.swift — 5 items (Agent A):**
- **Live search (Item 10)**: `.onChange(of: searchText)` with 300ms debounced `Task` filters `items` by `localizedCaseInsensitiveContains`. Cancels previous debounce task on each keystroke. Empty text clears filter (shows all). Existing `.onSubmit` FM search path preserved.
- **MY RATING sort (Item 11)**: New `case myRating = "MY RATING"` in `CollectionSort`. Sorts by `userListEntry().score` descending. Appears in sort menu automatically via `CaseIterable`.
- **Empty state CTAs (Item 12)**: Wired `onExploreDiscover` closure (was declared but never connected) to `kuro://discover` deep link. Added `onExploreConcierge` parameter opening `kuro://concierge`. Both use `UIApplication.shared.open(url)`.
- **Status summary row (Item 13)**: `statusCounts` computed property aggregates user list statuses. Rendered as horizontal `HStack` with interpunct separators above the filter bar. Uses `.kuroMicro(weight: .medium)` + `.kuroTextSecondary`.
- **Batch remove confirmation (Item 14)**: `batchRemove()` now sets `showBatchRemoveConfirm = true` instead of deleting immediately. `.confirmationDialog` shows "Remove N item(s) from collection?" with destructive "Remove" button calling `confirmBatchRemove()`. Follows existing `.confirmationDialog` pattern at line 414.

**AddToListSheet.swift — 2 items (Agent B):**
- **Score clear toggle + scale fix (Item 15)**: Tapping the already-selected star now clears score to 0 (toggle behavior). **Bug fix**: save now writes `score * 10` instead of raw `score` — DB stores 10-100 scale but UI was saving 1-10, causing scores to appear reset after round-trip (`50 / 10 = 5` on load, save wrote `5`, next load `5 / 10 = 0`).
- **Progress text field (Item 16)**: New `isEditingProgress` state. Tap the progress label to switch from Stepper to NumberPad TextField + Done button. Clamps to `0...maxProgress` on submit. Reverts to Stepper on Done.

**EditorialDiscoverView.swift — 1 item (Agent C):**
- **Dense2ColumnSection context menus (Item 19)**: `Dense2ColumnSection`, `Dense2ColumnSectionFixed`, `Dense2ColumnMangaSectionFixed`, and `FullSectionView` card renders now have `.contextMenu` matching `GridAnimeCard` pattern: Quick Add/Remove, Edit List/Add to List, Add to Club (gated by `!supabaseService.myClubs.isEmpty`).

**BrowseView.swift — 1 item (Agent C):**
- **Result count indicator (Item 20)**: `"N RESULT(S)"` text above browse grid when results loaded. `.kuroMicro(weight: .medium)`, tracking 1.5, `.kuroTextTertiary`. Scrolls with content.

**ClubDetailView.swift — 1 item (Agent D):**
- **Tab rename (Item 24)**: `case thisWeek = "THIS WEEK"` → `case active = "ACTIVE"`. All `.thisWeek` references updated to `.active`. Function name `thisWeekTab()` preserved (internal only).

**FriendsActivitySection.swift — 1 item (Agent D):**
- **Delete own comment (Item 25)**: Trash icon button next to edit pencil (gated by `comment.is_own`). Red icon (`.red.opacity(0.65)`) — correct per CLAUDE.md for destructive actions. `.alert("Delete your comment?")` with destructive "Delete" calling `supabaseService.deleteTitleComment()` + `loadActivity()` refresh.

**AnimeDetailView.swift + MangaDetailView.swift — 2 items (Agent D):**
- **Empty synopsis guard (Item 30)**: `DescriptionSection` now wrapped in `if anime.description != nil || anime.synopsisEnhanced != nil` (and manga equivalent). Prevents empty SYNOPSIS header when no description data exists.
- **Share deep link (Item 31)**: `ShareLink` added below club/friends activity section. Shares `kuro://anime/{id}` / `kuro://manga/{id}` with title as subject. Editorial capsule style: `square.and.arrow.up` icon + "SHARE" text, `.kuroMicro(weight: .medium)`, tracking 1.2, `.kuroTextSecondary`, rounded rect background.

Totals: 0 new files, 8 modified Swift files, 0 new migrations. 64 Swift files, 144 migrations.

### 2026-03-03 — Post-Wave 3 review fixes (3 bugs across 3 files)

**EditorialCollectionView.swift — P1: Batch remove awaits all removals:**
- `confirmBatchRemove()` now calls `supabaseService.removeFromList()` directly (awaitable) instead of fire-and-forget `toggleInCollection()`. Checks `isInCollection` before/after each removal to detect per-item failures. Three outcome paths: all succeeded (success haptic + count), partial failure (impact haptic + "N of M, K failed"), total failure (error haptic + connection hint).

**SupabaseService.swift — P1: Favorite toggle writes correct scale:**
- `toggleFavorite(for:)` line 4206: `newRating` changed from `10` to `100`. DB uses 10-100 scale; `isFavorited()` checks `>= 90`, so setting `10` was never recognized as favorited on next read.

**FriendsActivitySection.swift — P2: Delete comment surfaces errors:**
- Delete confirmation handler changed from `try?` (silent failure) to `do/catch` with `errorText = "Could not delete comment."` on failure. Uses existing `errorText` state and red error label already rendered in the view.

Totals: 0 new files, 3 modified Swift files. 64 Swift files, 144 migrations.

### 2026-03-03 — Pre-release hardening (2 fixes across 4 files)

**SupabaseService.swift + EditorialCollectionView.swift — Batch remove performance:**
- `removeFromList()` now accepts `skipRefresh: Bool` parameter. Default `false` preserves existing behavior for single-item removes.
- `confirmBatchRemove()` passes `skipRefresh: true` for each item, then does a single `fetchUserLists()` + `fetchCollectionFeed()` at the end. Reduces network round-trips from 3N to N+2 for a batch of N items.

**AnimeDetailView.swift + MangaDetailView.swift — Synopsis guard tightened:**
- Guard changed from `description != nil || synopsisEnhanced != nil` to `!displayDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayDescription != "No description available"`. Catches empty-string descriptions (`""`) and the fallback placeholder that the `!= nil` check missed.

Totals: 0 new files, 4 modified Swift files. 64 Swift files, 144 migrations.

### 2026-03-04 — Production audit fixes (2 items across 2 files)

**BrowseView.swift — Task leak on view disappear:**
- Added `.onDisappear { reloadTask?.cancel() }`. Previously the reload task could complete after sign-out, writing stale catalog data to empty-state arrays.

**SupabaseService.swift — Double-tap guard on toggle operations:**
- New `togglingMediaKeys: Set<String>` guard set. `toggleInCollection()` inserts key before launching Task, removes on completion — second tap while in-flight is silently ignored. Same guard on `toggleFavorite()` (key prefix `fav-`). Cleared in `resetUserState()` on sign-out.

Totals: 0 new files, 2 modified Swift files. 64 Swift files, 144 migrations.

### 2026-03-04 — Characters, Staff, Studios & Authors on Detail Pages

**New files (3 Swift + 1 migration):**
- `Kuro/Views/DetailPages/CastSection.swift` — CastSection horizontal portrait rail + CastCircleItem (64pt circles, MAIN badge, sorted MAIN > SUPPORTING, BACKGROUND excluded)
- `Kuro/Views/DetailPages/CreditsSection.swift` — ProductionSection (anime: inline tappable studios + editorial credit bylines), MangaProductionSection (manga: editorial author bylines), AllCreditsSheet
- `Kuro/Views/DetailPages/EntityDetailSheets.swift` — CharacterDetailSheet, StaffDetailSheet, AuthorDetailSheet, StudioDetailSheet, EntitySortMode, EntityWorksRail, EntityHeroSection, EntityWorkCard
- `supabase/migrations/20260304100000_credits_cast_v1_flag.sql` — `credits_cast_v1` feature flag at 100%

**SupabaseModels.swift — 4 entity models + join wrappers + DTOs + CreditRole:**
- `Character`, `Staff`, `Studio`, `Author` structs with explicit CodingKeys
- 5 forward join wrappers, 2 lightweight DTOs (`AnimeWorkRow`, `MangaWorkRow`), 5 reverse join wrappers
- `CreditRole` enum (10 cases, `from(raw:)` normalization, priority by rawValue, `editorialPrefix` computed property for byline rendering)

**SupabaseService.swift — 5 inline caches + 4 entity-sheet caches + 9 fetch methods:**
- All sheet fetches filter `isAdult` + genre-based exclusion
- All caches cleared in `resetUserState()`

**AnimeDetailView.swift / MangaDetailView.swift:**
- Parallel entity fetches gated by `isCreditsCastV1Enabled`
- Anime: CastSection → ProductionSection (studios as inline tappable interpunct text + editorial credit bylines, top 2 + ALL CREDITS capsule) after Tags
- Manga: CastSection → MangaProductionSection (editorial author bylines) after Tags

**FeatureFlags.swift:** `isCreditsCastV1Enabled` accessor
**AuthView.swift / TextNormalization.swift:** `Swift.Character` qualification to avoid name collision
**KuroTests.swift:** 12 new CreditRole + cast sorting unit tests

Totals: 3 new Swift files, 7 modified Swift files, 1 new migration. 67 Swift files, 145 migrations.

### 2026-03-04 — Credits/Cast audit fixes (4 items)

**[P1] Migration pushed to remote:**
- `20260304100000_credits_cast_v1_flag.sql` applied via `supabase db push --linked --include-all`.

**[P2] Flag refresh race in detail pages:**
- Entity fetches split into separate `.task(id: "\(id)-\(flag)")` keyed on both media ID and `isCreditsCastV1Enabled`. When flag transitions false→true after async refresh, the task re-fires and loads entity data.

**[P2] Server-side adult filtering in entity-sheet queries:**
- Added `.eq("anime.is_adult", value: false)` / `.eq("manga.is_adult", value: false)` to all 4 entity-sheet fetch methods (`fetchAnimeByStudio`, `fetchAnimeByStaff`, `fetchMangaByAuthor`, `fetchMediaByCharacter`). Client-side filter retained as defense-in-depth.

**[P3] Migration conflict strategy:**
- `credits_cast_v1_flag.sql` changed from `ON CONFLICT DO NOTHING` to `ON CONFLICT DO UPDATE SET enabled, rollout_percentage, description` to enforce intended state even if row pre-exists.

### 2026-03-06 — Concierge + Add-to-List stabilization

**ConciergeView.swift + ConciergeComponents.swift + SupabaseService.swift — Concierge is session-local:**
- Removed the disk-backed `ConciergeConversationCache` path and its persisted DTOs. Concierge no longer restores or saves prior sessions on appear, disappear, or app lifecycle changes.
- `signOut()` no longer clears concierge session files because cross-session concierge persistence no longer exists.
- `NEW CHAT` still resets the current in-memory conversation and related import/recommendation UI state.

**AddToListSheet.swift — list mutations are consistently online-only:**
- Save and remove now share one inline mutation-status slot. When offline, the sheet shows `You're offline. Reconnect to update your list.`
- `REMOVE FROM LIST` is now disabled offline, matching the existing save-button policy.
- `saveToList()` and `removeFromList()` now guard against offline execution before calling Supabase, instead of relying only on button disabled state.

Totals: 0 new files, 4 modified Swift files. 67 Swift files, 145 migrations.

### 2026-03-06 — Credits/cast differentiation + filter wiring audit

**EntityDetailSheets.swift — creator/studio sheets are now editorial discovery surfaces:**
- `EntitySortMode` adds `ERA` alongside `RATING` and `YEAR`, grouping titles into 2020s / 2010s / 2000s / earlier buckets.
- `CharacterDetailSheet` adds `ALL / ANIME / MANGA` filtering over the mixed appearance list.
- `StaffDetailSheet` adds role filters (`ALL ROLES / DIRECTOR / WRITER / MUSIC / DESIGN`) derived from existing free-text credit roles.
- `AuthorDetailSheet` adds role filters (`ALL / STORY / ART / STORY & ART`) derived from `manga_authors.role`.
- `EntityWorksRail` gains a short editorial subtitle; sheets now frame the lists as discovery pages rather than raw filmographies.

**EditorialSearchView.swift — latent backend search flags are now exposed:**
- Search remains a sheet, but now exposes a server-backed refinement strip.
- New chips map directly to `SupabaseService.SearchFilters` and existing RPC params:
  - anime: `TRENDING`, `NEW SEASON`, `CLASSICS`, `HIDDEN GEMS`, `AIRING`
  - manga: `TRENDING`, `NEW`, `CLASSICS`, `HIDDEN GEMS`
  - combined: shared flags only
- Search now supports filter-driven results even with an empty text query, using the existing `search_*_page` RPC filter-only mode.

**EditorialDiscoverView.swift — local rail refinements are now explicit:**
- Rail-level chips inside Discover sections are labeled `REFINE THIS RAIL` to distinguish them from global backend discovery filters.
- Full-sheet rail views are labeled `EDITORIAL RAIL`, clarifying that `See All` opens the current curated rail, not the full catalog.

**Audit artifact:**
- Added `docs/filter-wiring-audit.md` with a code-first matrix classifying each visible sort/filter/drilldown surface as `backend_wired`, `client_only_intentional`, `latent_backend_not_exposed`, or `broken_or_misleading`.

**KuroTests.swift:**
- Added entity discovery tests for era grouping and staff/author role categorization.

### 2026-03-07 — Adaptation ladder v1 (live)

**New schema contract:**
- Added `supabase/migrations/20260307120000_media_relations_ladder_v1.sql`.
- New table: `public.media_relations` with directional anime↔manga relation edges (`SOURCE`, `ADAPTATION`, `PREQUEL`, `SEQUEL`, `SIDE_STORY`, `SPIN_OFF`).
- New read RPC: `public.get_media_ladder(p_media_type text, p_media_id int)` returning grouped ladder buckets (`source_material`, `adaptations`, `prequels`, `sequels`, `side_stories`, `spin_offs`).
- Safety contract is enforced in SQL: adult rows and `Hentai` / `Ecchi` genre rows are omitted before the ladder payload reaches iOS.

**AniList import pipeline:**
- `supabase/functions/bulk-import-anime/index.ts` now requests AniList `relations`, resolves target AniList IDs to local anime/manga rows, and rewrites source-owned `media_relations` edges on each relation-heavy refresh.
- `supabase/functions/bulk-import-manga/index.ts` does the same for manga imports.
- Import remains directional and non-heuristic: only supported AniList relation types are stored, and only targets already present in Kuro as anime/manga are materialized.

**iOS models/service/UI:**
- New typed ladder models in `Kuro/Models/SupabaseModels.swift`: `MediaLadderItem` and `MediaLadderResponse`.
- New RPC params in `Kuro/Services/SupabaseRPCParams.swift`: `RPCGetMediaLadderParams`.
- New service path in `Kuro/Services/SupabaseService.swift`: `fetchMediaLadder(mediaType:mediaId:)` with a short-lived response cache.
- New shared UI section in `Kuro/Views/DetailPages/AdaptationPathSection.swift`.
- `AnimeDetailView.swift` and `MangaDetailView.swift` now fetch ladder data and render `ADAPTATION PATH` below the creator/studio block when qualifying relations exist.
- The ladder is intentionally editorial, not exhaustive: it prioritizes `READ THE SOURCE`, `WATCH THE ADAPTATION`, `START WITH`, `CONTINUE TO`, then side-story/spin-off fallback rows.

**Validation:**
- `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` → `BUILD SUCCEEDED`
- `xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test -only-testing:KuroTests` → `TEST SUCCEEDED`
- `supabase db lint --linked` → `No schema errors found`
- `supabase migration list --linked` shows `20260307120000` present both locally and remotely.
- `supabase functions list --project-ref bkdifromsqxkndnllmdj` shows deployed versions `bulk-import-anime:v33` and `bulk-import-manga:v32`.
- Controlled post-deploy relation backfill seeded the first live ladder coverage pass; `public.media_relations` now contains live rows and `get_media_ladder(...)` returns grouped payloads for known titles such as Attack on Titan, Chainsaw Man, and Kaguya-sama.
- Deno type-check could not be run on this machine because `deno` is not installed in PATH.

Totals: 1 new Swift file, 8 modified code files, 1 new migration. 68 Swift files, 146 migrations.

### 2026-03-07 — Adaptation ladder v2 (editorial context + targeted coverage)

**New backend contract:**
- Added `supabase/migrations/20260307150000_adaptation_ladder_v2_editorial_context.sql`.
- `public.get_media_ladder(text, int)` now returns additive editorial fields on top of the v1 buckets:
  - `entry_point`
  - `next_step`
  - `primary_source`
  - `primary_adaptation`
  - `franchise_note`
  - `coverage_status` (`strong` / `partial` / `minimal`)
- Added `public.media_relation_refresh_queue` plus `public.enqueue_media_relation_refresh(...)` so iOS can request strict AniList-only refreshes when ladder coverage is weak.

**Editorial selection rules (server-side):**
- Chronology (`PREQUEL` / `SEQUEL`) stays year-ascending.
- `SOURCE` and `ADAPTATION` primary picks are deterministic: rating → popularity → year, with anime adaptation picks also preferring stronger formats (`TV`, `MOVIE`) over weaker companions (`SPECIAL`, `MUSIC`).
- The RPC never guesses from title similarity and never infers reverse edges in SQL.
- Safety rules remain enforced before editorial selection: adult titles plus `Hentai` / `Ecchi` branches are filtered out in SQL.

**iOS presentation and opportunistic refresh:**
- `MediaLadderItem` gained `reasonLabel`; `MediaLadderResponse` gained the editorial fields and `coverageStatus`.
- `AdaptationPathSection.swift` now renders an editorial path:
  - featured `entry_point`
  - featured `next_step`
  - up to 3 compact follow-up rows from `READ THE SOURCE`, `WATCH THE ADAPTATION`, `SIDE STORY`, `SPIN OFF`
- `AnimeDetailView.swift` and `MangaDetailView.swift` enqueue a ladder refresh on detail open when coverage is not `strong`.
- `EditorialDiscoverView.swift` enqueues refreshes for hero/current-season/trending/editorial-primary titles.
- `ConciergeView.swift` enqueues refreshes for the first recommendation set items so ladders improve on recommendation-heavy surfaces too.

**Operational coverage expansion:**
- Added a dedicated worker path:
  - `scripts/media_relations_worker.js`
  - `scripts/run_media_relations_refresh.sh`
  - `scripts/install_media_relations_launchd.sh`
- Worker modes:
  - `queue` — processes `media_relation_refresh_queue`
  - `top-catalog` — backfills top anime + manga by popularity (default 500 each)
  - `report` — writes `reports/media-relations/latest-status.json`, `latest-run.json`, and `missing-top-catalog.md`
- Installed local launchd agent `com.kuro.media-relations` at a 900-second interval so opportunistic ladder refresh requests are consumed continuously.
- The worker now uses AniList request batching (`ANILIST_BATCH_SIZE`, default `10`) and request timeouts (`ANILIST_TIMEOUT_MS`, default `20000`) to keep the top-catalog backfill and queue processing bounded.

**Validation:**
- `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` → `BUILD SUCCEEDED`
- `xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test -only-testing:KuroTests` → `TEST SUCCEEDED`
- `supabase db push --linked --include-all --yes` applied `20260307150000_adaptation_ladder_v2_editorial_context.sql` to project `bkdifromsqxkndnllmdj`
- `supabase migration list --linked` shows `20260307150000` present locally and remotely
- `supabase db lint --linked` → `No schema errors found`
- Live RPC verification on the correct project confirms editorial fields:
  - `get_media_ladder('ANIME', 2)` (`Attack on Titan`) now returns `coverage_status = strong`, `entry_point`, `next_step`, `primary_source`, and a franchise note

Totals: 0 new Swift files, 8 modified Swift files, 3 new scripts, 1 new migration. 68 Swift files, 147 migrations.

### 2026-03-07 — Unified local operations dashboard

**New local dashboard server:**
- Added `scripts/unified_local_dashboard_server.js`.
- Serves a single localhost dashboard at `http://127.0.0.1:8791`.
- Aggregates the existing local worker/report surfaces instead of inventing a new status system:
  - catalog safety
  - synopsis enrichment
  - provider availability
  - media relations
  - local CI
  - local CD

**What it reads:**
- Each service's existing `latest-status.json` or CI/CD status file
- Existing `worker.log` / local CI/CD log tails
- launchd state via `launchctl print`
- active local process state via `ps`

**Presentation contract:**
- One Swiss-minimal page with:
  - overview counts (`Running now`, `Healthy recent`, `Stale`, `Quiet`)
  - a dedicated Adaptation Ladder coverage panel (relation rows, distinct titles, strong/partial mix, current backfill progress, top missing high-popularity titles)
  - per-service cards (metrics + launchd + process state + direct actions)
  - integrated log tails
  - links to dedicated sub-dashboards where they already exist (`8787`, `8788`, `8789`)
- Each service card now exposes read-only drilldowns directly from the unified page:
  - `Status JSON`
  - `Run JSON` (where available)
  - `Log tail`
  - ladder-specific `Coverage report`
- Statuses are classified from the current machine state:
  - `Running now`
  - `Healthy recent run`
  - `Stale status`
  - `No status yet`

**Launchd install path:**
- Added `scripts/install_unified_dashboard_launchd.sh`
- Installs `com.kuro.unified-dashboard`
- Keeps the dashboard alive on the machine using `/usr/local/bin/node`
- Logs to `reports/local-dashboard/dashboard.out.log` and `dashboard.err.log`

**Verification:**
- `node --check scripts/unified_local_dashboard_server.js` → pass
- `bash -n scripts/install_unified_dashboard_launchd.sh` → pass
- `launchctl print gui/$(id -u)/com.kuro.unified-dashboard` shows the agent registered
- `curl http://127.0.0.1:8791/api/status` returns the unified aggregated payload

### 2026-03-07 — Search refinements + public script config + docs truth cleanup

**Search behavior correction:**
- `EditorialSearchView.swift` now treats active refinement chips as a valid server-backed search mode even when the text field is empty.
- Empty-query search is still blocked only when both the query and refinement chips are empty.
- Added `EditorialSearchTests` coverage so filter-only anime/manga/combined search stays intentional.

**Script/tooling config decoupling:**
- Added committed non-secret public config at `scripts/project_public.env` (`SUPABASE_URL` + `SUPABASE_ANON_KEY` only).
- Added shared loaders:
  - `scripts/lib/project_config.js`
  - `scripts/lib/load_project_public_env.sh`
- Public-read scripts now prefer env vars first, then `project_public.env`, and no longer scrape `Kuro/Services/SupabaseService.swift` for project config.
- Sensitive credentials remain env-only (`SUPABASE_SERVICE_ROLE_KEY`, `IMPORT_SECRET`, provider/API keys).

**Docs truth + guardrail:**
- Refreshed current-state markers in `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, and `CLAUDE.md` to match actual repo inventory (`68` app Swift files, `153` SQL migrations).
- Marked `SQL_COMPATIBILITY_REPORT.md` as a historical point-in-time report instead of a whole-repo authority surface.
- Added `scripts/quality-gates/check_docs_current_state.py` (+ shell wrapper) and wired it into `scripts/quality-gates/run_all.sh` so stale file-count/current-state drift fails the quality gate.
- Current-state docs now explicitly state that provider availability remains staged behind `streaming_availability_v1` and that live watch/read links still come from `external_links`.

### 2026-03-09 — Archive warning cleanup

**Code-level archive warnings removed:**
- `SupabaseService.swift`: Apple Sign In profile update now explicitly discards the optional auth update result, eliminating the unused `try?` warning.
- `SupabaseService.swift`: club realtime subscriptions now use typed `RealtimePostgresFilter.eq(...)` instead of deprecated string filters.
- `GenreHubView.swift`: width now comes from `GeometryReader` instead of `UIScreen.main`, and the media-kind refresh uses the modern two-parameter `onChange` closure.
- `KuroRefinedCard.swift`: `KuroHorizontalSection` now computes card width from a passed container width instead of `UIScreen.main`.
- `KuroTests.swift`: provider-availability and ladder decoding suites are `@MainActor`, removing the Swift 6 isolation warnings triggered by the macro-generated equality checks.

**Validation:**
- `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` now emits no Kuro code warnings; the only remaining warning is Xcode's `appintentsmetadataprocessor` note that no AppIntents framework dependency exists.
- `xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test -only-testing:KuroTests` still passes with the same tool-only AppIntents warning.
- `fastlane beta` successfully archived and uploaded build `12` to TestFlight; the archive log no longer includes the earlier Kuro code warnings.

### 2026-03-10 — Runtime cleanup outside the release path

**Task-based UI timing cleanup:**
- `ContentView.swift` now replaces remaining `DispatchQueue.main.asyncAfter` usage with cancellable `Task.sleep(...)` flows for launch dismissal, pending Concierge deep-link prompt clearing, and header title-window cleanup.
- `Cards.swift` now uses cancellable task-based resets for quick-action animations and long-press action dismissal, avoiding delayed state mutations after the card has already disappeared.
- `ConciergeInputField.swift` now uses task-based intent-indicator resets and a main-actor task for UITextView height measurement instead of queue hopping.

**Validation:**
- `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` still succeeds with only the Xcode AppIntents metadata tool warning.
- `xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test -only-testing:KuroTests` still succeeds with the same tool-only warning.

### 2026-03-10 — Documentation cleanup: archive stale docs, fix inventory counts

**Archived 17 stale root-level docs:**
- Moved to `archive/`: DESIGN_UPDATE_OCT_8_2025.md, DISCOVER_SECTIONS_UPDATE.md, SLEEK_REDESIGN_COMPLETE.md, SMART_LAYOUT_REFACTOR.md, SOPHISTICATED_DISCOVER_DESIGN.md, NAVIGATION_DESIGN_LOCKED.md, KURO_CLOUD_KNOWLEDGE.md, KURO_CLOUD_KNOWLEDGE_ADDENDUM.md, COMPLETE_APP_DOCUMENTATION.md, CURRENT_APP_STATE_CODEBASE.md, DOCUMENTATION_INDEX.md, DEPLOY_COUNTDOWN_NOW.md, SESSION_SUMMARY.md, SQL_COMPATIBILITY_REPORT.md, SQL_DEPLOYMENT_GUIDE.md, BROWSE_REFINED_SUMMARY.md, higgs_field_animation_brief.md
- Root now has exactly 7 MD files: CLAUDE.md, CURRENT_APP_STATE.md, CURRENT_APP_STATE_PLAIN.md, IMPLEMENTATION_PLAN_Variation1.md, MASTER_PLAN.md, REPRODUCE.md, SCHEDULES.md

**Fixed conflicting inventory numbers:**
- CLAUDE.md line 294: 145 → 153 migrations (as of 2026-03-10)
- CURRENT_APP_STATE.md auto-inventory block: regenerated via `node scripts/generate_app_state_inventory.js` — now shows 68 Swift files, 153 migrations
- KNOWLEDGE/PART-00_FILE_MAP.md: fully rewritten with current 68 Swift files (was missing CastSection, CreditsSection, EntityDetailSheets, AdaptationPathSection) and all 15 edge functions (was listing only 3)

**Cross-reference updates:**
- CURRENT_APP_STATE.md line 105: updated to reference `archive/` for historical docs
- CURRENT_APP_STATE.md source bundle reference → `archive/CURRENT_APP_STATE_CODEBASE.md`
- CURRENT_APP_STATE_PLAIN.md: both `CURRENT_APP_STATE_CODEBASE.md` references → `archive/` path
- `scripts/quality-gates/check_docs_current_state.py` line 13: SQL report path → `archive/`
- KNOWLEDGE/INDEX.md: added design-note blockquote about intentional overlap with CURRENT_APP_STATE.md
- Added `/docs/documentation-surface-map.md` to define the keep/trim/archive policy for Markdown surfaces
- Added `archive/README.md` so archived docs are explicitly marked historical instead of just moved out of the root

### 2026-03-10 — Detail page redesign HTML mockup

**New file:** `mockups/detail-page-redesign.html` — self-contained browser mockup (839 lines) for proposed detail page layout changes.

**Mockup contents:**
- **Page 1 — Anime Detail Page** in a 393×852 iPhone frame: hero, meta line, genre/sub-genre pills, cast circles (64px), **merged PRODUCTION section** (studios as inline tappable interpunct-separated text + credits as editorial bylines e.g. "Directed by HIROSHI KOUJINA", top 2 + ALL CREDITS capsule), **episode breakdown bar** (canon/filler/mixed ratio with legend), synopsis with READ MORE, more-like-this poster rail.
- **Page 2 — AddToList Sheet** *(superseded by Concept A "The Editorial Spread" — see 2026-03-11 entry)*: originally showed media preview card + 2×3 status grid + star rating. Now redesigned as full-bleed poster hero with gradient overlay, horizontal capsule status pills, 44pt serif score with dot indicators, centered progress with ± buttons, pull-quote notes field, and pinned save dock.

**Design tokens used:** All CSS custom properties match `KuroDesignSystem` exactly (monochrome palette, serif/sans font stack, 8px spacing grid, radius scale, type scale from micro 9px to hero 64px).

Totals: 1 new file (`mockups/detail-page-redesign.html`), 0 modified Swift files, 0 new migrations. 68 Swift files, 153 migrations.

### 2026-03-10 — Detail Page Declutter (PRODUCTION merge + score labels)
- Merged Studios + Credits into single PRODUCTION section on detail pages (~250px saved)
- Section order: Cast → PRODUCTION (was: Studios → Credits → Cast)
- Studios render as inline tappable interpunct-separated text
- Credits render as editorial bylines (top 2 + ALL CREDITS drill-down)
- Added `CreditRole.editorialPrefix` computed property
- Manga: AuthorsSection → MangaProductionSection with same editorial byline format
- AddToListSheet: curator's shorthand score labels (1=SKIP...10=CANON) below stars
- Removed score guide table from AddToListSheet
- Extracted ScoreSection subview to resolve SwiftUI type-checker timeout
- Updated mockup: `mockups/detail-page-redesign.html` with new PRODUCTION layout + score labels

### 2026-03-10 — Club detail page redesign mockup v2
- Rewrote `mockups/club-page-redesign.html` with elevated editorial treatment for the club detail page
- Clubs list page kept unchanged (mosaic cards already good)
- Club detail page improvements:
  - Cinematic hero header: blurred darkened poster mosaic (200px), bottom gradient, overlaid serif club name, member avatars, sharing-level pill
  - Status bar goes transparent/white-text over hero, reverts on scroll past hero
  - Watchlist tab: larger poster cards (120x170), serif italic titles, episode progress labels, "who's watching" text, reaction bounce animation, "+" add-reaction pill, magazine section dividers with thin rule lines
  - Activity tab: poster thumbnails (36x52) on each activity entry, editorial group headers with thin rule, glass-morphism pace banner with catch-up CTA, full editorial milestone card with confetti dots, completion badge, serif italic quote, avatar row
  - Polls tab: pull-quote treatment (40px rule above question), full-width tappable option cards with background fill, voter avatar stacks per option, pulsing active-poll dot
  - Bottom bar: fixed glass-morphism bar with ADD/INVITE/SETTINGS replacing separate FAB + invite pill, inline search slides up from bar
  - Tab content fade-in animation on switch
- No Swift changes, no backend changes. Mockup only.

### 2026-03-11 — AddToList Sheet — Editorial Redesign (Concept A: "The Editorial Spread")

**Files modified**: `Kuro/Views/AddToListSheet.swift` (full body rewrite)
**Files created**: `mockups/addtolist-concepts.html` (interactive browser mockup with 3 concepts)

**What changed:**
- Full-bleed poster hero with dark gradient overlay, title + metadata overlaid in white serif
- Floating circular X dismiss button (replaces NavigationView Cancel toolbar)
- Status selection: horizontal capsule pills via FlowLayout (replaces 2x3 icon grid, saves ~100px)
- Score: 44pt serif number + curator label (SKIP->CANON) + 10 dot indicators (replaces 10 star rating)
- Progress: 34pt serif centered number (tap to type-edit) + 2pt bar + +/- circle buttons (replaces Stepper)
- Notes: pull-quote style with 2px left bar accent + serif placeholder "What would you tell a friend?" (replaces plain TextEditor with grey background)
- Pinned save dock via `.safeAreaInset` with semi-transparent background (replaces inline button)
- Numeric content transition animation on score number

**What did NOT change (all business logic preserved):**
- `saveToList()`, `removeFromList()` — exact same
- Score scale: UI 1-10 -> DB 0-100 (`score * 10`)
- `scoreLabel` computed property (SKIP->CANON)
- Offline guard + error messaging
- Pre-fill from existing entry via `.task(id:)`
- Manga-specific labels (Reading/Rereading)
- Progress auto-complete on COMPLETED

**Subviews extracted (type-checker safety):**
- `SpreadHeroSection`, `SpreadStatusRow`, `SpreadProgressSection`, `SpreadScoreSection`, `SpreadNotesSection`, `SpreadSaveDock` (all private)
- Removed: `MediaPreview`, `StatusCard`, `ScoreSection` (old subviews)

Totals: 1 new file (`mockups/addtolist-concepts.html`), 1 modified Swift file. 68 Swift files, 153 migrations.

### 2026-03-11 — Club detail page stylistic variations (3 mockups)
- Created 3 self-contained HTML mockups exploring different layout philosophies for the club detail page, all within Kuro's editorial design language:
  - `mockups/club-redesign-gallery.html` — **Option A: The Gallery** — Maximum white space, full-bleed landscape posters in a vertical lookbook flow, single dramatic hero image, floating FAB, barely-there activity, pull-quote polls
  - `mockups/club-redesign-broadsheet.html` — **Option B: The Broadsheet** — Dense 2-column portrait grid, typographic-only masthead (no hero image), newspaper-like activity feed with 2px dividers, ballot-style polls with radio circles, text-only toolbar
  - `mockups/club-redesign-journal.html` — **Option C: The Journal** — Blurred mosaic hero with grain overlay and italic serif name, horizontal rails with curator's notes ("What we're watching right now"), prose-style journal activity entries with date headers, conversational polls ("S asked:"), glass pill bottom bar with WRITE action, invite overlay
- All 3 share the same clubs list page (3 cards: Shonen Sundays, Studio Ghibli Marathon, Seinen Deep Cuts)
- All interactive: tab switching with animated underline, screen navigation, toast notifications, press effects
- Zero emoji, monochrome palette, Cormorant Garamond + system sans, all Kuro design tokens
- No Swift changes, no backend changes. Mockups only.
- Totals: 3 new files. 68 Swift files, 153 migrations (unchanged).

### 2026-03-11 — Club detail page: Journal editorial redesign (Swift implementation)
- Full visual rewrite of `ClubDetailView.swift` implementing Option C ("The Journal") from the HTML mockups.
- **Hero section**: `JournalHeroSection` — blurred 2x2 poster mosaic from first 4 rail items, `.blur(radius: 20)` + `.scaleEffect(1.15)`, grain texture overlay, dual gradient fades, serif italic club name, member avatar row, sharing-level pill, parallax on scroll.
- **Status bar**: `JournalStatusBar` — transparent over hero, transitions to white with club name on scroll past hero via `ClubScrollOffsetPreferenceKey` + `.coordinateSpace`.
- **Tab bar**: `JournalTabBar` — custom HStack with `@Namespace` + `matchedGeometryEffect` underline animation, replaces segmented `Picker`.
- **Rails tab**: `JournalRailsContent` / `JournalRailSection` / `JournalRailItemCard` — curator's notes in serif italic above each rail, 120x170pt poster cards (was 110x157), progress text ("EP 8 OF 24"), member-watching labels, editorial dividers between rails, dashed add-card.
- **Activity tab**: `JournalActivityContent` / `JournalActivityEntry` — synthesizes entries from `member_statuses` across all rail items, groups by date with serif italic headers, prose-style text (bold name + action + italic title), `JournalPaceBanner` (behind pace banner), `JournalMilestoneCard` (pull-quote with decorative rules).
- **Polls tab**: `JournalPollsContent` / `JournalPollCard` / `JournalPollOptionRow` — conversational framing ("S ASKED:"), serif italic questions, percentage fill bars (3pt), voted-dot indicator, dashed create-poll card ("ASK A QUESTION").
- **Bottom bar**: `JournalBottomBar` — `.ultraThinMaterial` capsule pill (48pt), shadow from `KuroGlassCard` pattern, ADD/INVITE/POLL buttons with dividers, role-gated (non-admin sees only INVITE).
- **Navigation**: Hidden system nav bar (`.toolbar(.hidden, for: .navigationBar)`), custom back/settings overlay buttons matching `AnimeDetailView` pattern.
- **Preserved verbatim**: All business logic (`loadBundle`, `voteOnPoll`, `showToast`, `canAddToRail`, `handleMembershipLoss`, Realtime `.task`, `.refreshable`, all `.sheet` modifiers), `ClubReactionRow`/`Compact` (width 110->120), `AddItemToRailSheet`, `RailSearchResultRow`, `ClubSettingsSheet`.
- **Removed**: `clubHeader()`, `clubContent()`, `railsTab()`, `thisWeekTab()`, `pollsTab()`, `ClubRailSection`, `ClubRailItemCard`, `ClubMilestoneCard`, `ClubPollCard`, `ClubPollOptionRow`, `ThisWeekRow`.
- All feature flag gates preserved (`clubs_reactions_v1`, `clubs_pace_sync_v1`, `streaming_availability_v1`).
- 0 new files, 0 backend changes, 0 new migrations. 68 Swift files, 153 migrations (unchanged).

### 2026-03-11 — Adaptation Path: Editorial Footnote redesign
- Full rewrite of `Kuro/Views/DetailPages/AdaptationPathSection.swift` — replaced card-based ladder UI with an editorial footnote design.
- **New migration**: `supabase/migrations/20260311100000_ladder_source_author.sql` — modified `get_media_ladder` RPC to include `source_author_name` inside `primary_source` JSON (resolved via `manga_authors` -> `authors` join, prioritizing story roles), added `total_franchise_count` (integer) and `alternate_adaptation_summary` (text) at top level.
- **Collapsed state (on detail page)**: "ADAPTATION PATH" section header, 26pt serif statement ("Based on the manga by {Author}" or "Adapted as {Title} ({year})"), 9pt micro metadata line (title, year, format, rating separated by interpuncts), thin 1px rule, editorial footnote prose in 14pt serif with tappable underlined inline links.
- **Template logic**: Anime from manga/novel shows "Based on the {format} by {Author}" (falls back to "Based on {Title}" if no author). Manga with anime adaptation shows "Adapted as {Title} ({year})". Original anime with no source: section hidden entirely.
- **Footnote prose**: Mentions alternate adaptations ("Also adapted as a 2003 television series") and franchise breadth ("The franchise includes 8 titles — see the full path"). Both are tappable — alternate opens that title's detail sheet, "see the full path" opens the franchise sheet.
- **Expanded sheet (FranchisePathSheet)**: Full franchise tree grouped by category (Source, Adaptations, Prequels, Sequels, Side Stories, Spin-Offs) with tappable rows showing title, year, format, rating.
- **Model changes in `SupabaseModels.swift`**: Added `sourceAuthorName: String?` to `MediaLadderItem` (CodingKey `source_author_name`). Added `totalFranchiseCount: Int?` and `alternateAdaptationSummary: String?` to `MediaLadderResponse` (CodingKeys `total_franchise_count`, `alternate_adaptation_summary`). Updated `static let empty` to include new fields as nil.
- **Call site changes**: `AnimeDetailView.swift` and `MangaDetailView.swift` now pass `mediaType: .anime` / `mediaType: .manga` to `AdaptationPathSection`. The outer `if mediaLadder.hasContent` guard was removed — the section's internal `shouldShow` handles visibility.
- **Subview extraction**: 8 private subviews (`FootnoteStatement`, `FootnoteMetadataLine`, `FootnoteProse`, `FootnoteProseContent`, `FranchisePathSheet`, `FranchisePathGroup`, `FranchisePathRow`, `WrappedTextFlow`) to avoid SwiftUI type-checker timeouts.
- **MediaLadderItem**: Added `Hashable` conformance (in `AdaptationPathSection.swift` extension) for `sheet(item:)` presentation.
- **Old structs removed**: `AdaptationPathRowModel`, `EditorialLadderCard`, `AdaptationPathRow`, `KuroCompactCard` posters.
- **Mockup**: `mockups/adaptation-path-concepts.html` created during design phase (3 options; user picked Option 3: Editorial Footnote).
- Build: `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` -> `BUILD SUCCEEDED`.
- 0 new Swift files, 1 new migration. 68 Swift files, 154 migrations.

### 2026-03-12 — Bulk import parallel item processing

Replaced sequential per-item processing in both bulk import edge functions with batched parallel processing (chunks of 5 via `Promise.all`).

Files changed:
- `supabase/functions/bulk-import-anime/index.ts`
- `supabase/functions/bulk-import-manga/index.ts`

Behavior change:
- Previously, each AniList media item within a fetched page was processed sequentially (upsert + relations + episodes/chapters/tags/etc.), leading to 100+ sequential Supabase round-trips per page.
- Now items are processed in chunks of 5 concurrently using `Promise.all()`. Each item still has its own try/catch so one failure does not affect the batch.
- Added `ITEM_BATCH_SIZE = 5` constant to both functions.
- All existing error handling, result counting, auth, response format, and page-level logic unchanged.
- With `DEFAULT_PER_PAGE = 25`, each page now processes in 5 parallel rounds of 5 items instead of 25 sequential rounds.

### 2026-03-13 — Feature flags refresh retry logic

Added network-aware retry logic to `FeatureFlags.refresh()` so transient network failures don't leave the app running with stale or empty flags.

Files changed:
- `Kuro/Services/FeatureFlags.swift`

Behavior change:
- Previously, a single network failure during flag refresh silently fell through to cached values with no retry.
- Now the refresh loop retries up to 3 times on `URLError` (network issues) with delays of 10s, 30s, 60s.
- Non-network errors (decode failures, HTTP 4xx) are not retried — they exit immediately using cached values.
- If all retries exhaust and a cache exists (from `loadFromCache()`), the app continues with cached flags and logs a warning.
- If all retries exhaust and the cache is empty, a separate warning is logged.
- All new `print()` statements are wrapped in `#if DEBUG`.
- No new files. 68 Swift files, 154 migrations.

### 2026-03-13 — Local CI/CD pipeline improvements

Added iOS unit test quality gate and wired quality gates into Fastlane and local CI.

Files changed:
- `scripts/quality-gates/test_ios_unit.sh` (new) — runs `xcodebuild test` with iPhone 17 Pro simulator primary, generic fallback
- `scripts/quality-gates/run_all.sh` — added `ios-test` gate entry + `SKIP_IOS_TEST` env var skip logic
- `fastlane/Fastfile` — added `scripts/quality-gates/run_all.sh` before `build_app` in both `beta` and `release` lanes
- `scripts/local_ci.sh` — replaced ad-hoc xcodebuild call with quality gates orchestrator (with xcodebuild fallback)

Behavior change:
- `run_all.sh` now runs 8 gates (was 7): secrets, migrations, concierge-corpora, router-tests, rails-audit, docs-current-state, ios-build, ios-test.
- `fastlane beta` and `fastlane release` now run all quality gates before building. If any gate fails, the lane stops before `build_app`.
- `scripts/local_ci.sh` now delegates to `run_all.sh` when available instead of running a standalone xcodebuild build.
- No new Swift files. 68 Swift files, 154 migrations.

### 2026-03-13 — Safety pagination limits on fetch_club_bundle RPC
Added safety LIMIT clauses to `fetch_club_bundle` to prevent runaway result sets on corrupted or abused data. No functional changes — all logic, columns, and joins are identical.
- Members: `LIMIT 50` on all 3 member SELECT branches (private / H1 / full). Club max is 20; 50 is a generous safety cap.
- Rail items: `LIMIT 50` per rail on the inner `club_rail_items` subquery.
- Polls: `LIMIT 20` on the outer polls query (open-first, newest-first ordering preserved).
- Rails and poll options: kept unbounded (clubs rarely exceed 10 rails; polls typically have 2-6 options).
- Migration: `20260313100000_slim_club_bundle_limits.sql`
- No new Swift files. 68 Swift files, 155 migrations.

### 2026-03-13 — Production hardening: graceful config error + memory pressure handler
Replaced `fatalError` in `SupabaseService.init` with a `configError` property and UI gate so the app shows a configuration error screen instead of crashing if Supabase credentials are missing. Added `trimCachesForMemoryPressure()` to SupabaseService that sheds all entity, detail, discover, and concierge caches plus the ImagePipeline memory cache without touching user-facing state (lists, collection, auth). RootView listens for `UIApplication.didReceiveMemoryWarningNotification` and calls the trim method. ImagePipeline gained a public `clearMemoryCache()` method.
- `Kuro/Services/SupabaseService.swift` — `client` is now `SupabaseClient!` (IUO), new `configError` property, new `trimCachesForMemoryPressure()` method, 7 closure sites use explicit `client!` for IUO type-inference in generic contexts.
- `Kuro/KuroApp.swift` — RootView body checks `configError` before auth bootstrapping, `.task` listens for memory warnings.
- `Kuro/Services/ImagePipeline.swift` — new `clearMemoryCache()` method.
- All print statements across the codebase were verified to be inside `#if DEBUG` guards already — no changes needed.
- No new Swift files. 68 Swift files, 155 migrations.

### 2026-03-13 — Production hardening fix pass (audit corrections)

Audit review identified 5 issues in the initial implementation. All corrected:

**[P1] Member LIMIT in club bundle migration**: LIMIT 50 was applied after `jsonb_agg` (ineffective). Fixed by restructuring all 3 member branches to use a subquery pattern: `SELECT jsonb_agg(...) FROM (SELECT ... ORDER BY cm.joined_at, cm.user_id LIMIT 50) member_rows`. LIMIT now applies before aggregation.

**[P1] Rail-item cap nondeterministic**: `LIMIT 50` on rail items had no `ORDER BY`, yielding arbitrary rows. Fixed by adding `ORDER BY cri.sort_order, cri.id` before `LIMIT 50` in the enriched items subquery.

**[P2] fatalError replacement only partial**: `client` as IUO could still crash through auth callback or foreground refresh paths. Fixed by adding `guard let client else { return }` to `restoreSession()`, `startAuthStateListener()`, and other entry points. `KuroApp.swift` now gates `.onOpenURL` and `.onChange(of: scenePhase)` with `configError == nil`.

**[P3] Image pipeline in-flight cap partial**: `maxInFlightCap` (40) only applied in `prefetch()`. Fixed by adding `waitForInFlightSlot(for:)` call in `image(url:)` before creating new load tasks, so normal requests also respect the cap.

**Test fixes**: `KuroTests.swift` ladder test fixtures updated to include `sourceAuthorName` field (added in adaptation footnote redesign). `test_ios_unit.sh` updated to use concrete simulator destination with `-only-testing:KuroTests`.

Files changed:
- `supabase/migrations/20260313100000_slim_club_bundle_limits.sql` — member subquery restructure + rail-item ORDER BY
- `Kuro/Services/SupabaseService.swift` — guard-let-client in auth entry points
- `Kuro/KuroApp.swift` — configError gate on onOpenURL + scenePhase
- `Kuro/Services/ImagePipeline.swift` — in-flight cap on image(url:)
- `scripts/quality-gates/test_ios_unit.sh` — concrete simulator + -only-testing
- `KuroTests/KuroTests.swift` — ladder fixture sourceAuthorName
- No new Swift files. 68 Swift files, 155 migrations.

### 2026-03-13 — social_activity_v1 rollout to 100%

Rolled `social_activity_v1` from 0% to 100% via `UPDATE feature_flags SET rollout_percentage = 100 WHERE flag_name = 'social_activity_v1'`.

Code fix: Added `prefetchFriendCounts` calls to `BrowseView.fetchNextPage()` for both anime and manga pagination paths. Previously only the initial page load prefetched friend counts; page 2+ showed 0 until navigating away and back.

Files changed:
- `Kuro/Views/BrowseView.swift` — friend count prefetch on pagination
- `CLAUDE.md` — flag 0% → 100%
- `CURRENT_APP_STATE.md` — flag 0% → 100% (3 locations)
- `CURRENT_APP_STATE_PLAIN.md` — flag 0% → 100%
- No new files. 68 Swift files, 155 migrations.

### 2026-03-14 — Production readiness rollup (Build 16)

Consolidated summary of all production readiness work completed 2026-03-13, verified and shipped as Build 16 to TestFlight with 8/8 quality gates passing.

**Team A — iOS Hardening:**
- Replaced `fatalError` in `SupabaseService.init` with graceful `configError` property + error UI in `KuroApp.RootView`.
- `client` changed to `SupabaseClient!` (IUO); 7 closure sites use explicit `client!`; `guard let client` added to `restoreSession()`, `startAuthStateListener()`, and other auth entry points.
- `KuroApp` gates `.onOpenURL` and `.onChange(of: scenePhase)` with `configError == nil`.
- Added `trimCachesForMemoryPressure()` to SupabaseService (sheds entity/detail/discover/concierge caches + ImagePipeline memory cache). RootView listens for `UIApplication.didReceiveMemoryWarningNotification`.
- `ImagePipeline`: new `clearMemoryCache()` method; `maxInFlightCap = 40` now enforced in both `image(url:)` and `prefetch()`.
- Wrapped 127+ `print()` statements in `#if DEBUG` across all Swift files (verified complete audit).

**Team B — Feature Flags Retry:**
- `FeatureFlags.refresh()` retries up to 3 times on `URLError` with delays of 10s/30s/60s. Non-network errors exit immediately. Falls back to cache if all retries exhaust.

**Team C — Local CI/CD:**
- New `scripts/quality-gates/test_ios_unit.sh` — iOS unit test gate (iPhone 17 Pro primary, generic fallback).
- `run_all.sh` now runs 8 gates (was 7): secrets, migrations, concierge-corpora, router-tests, rails-audit, docs-current-state, ios-build, ios-test.
- Fastlane `beta` and `release` lanes run all quality gates before `build_app`.
- `scripts/local_ci.sh` delegates to `run_all.sh` instead of standalone xcodebuild.

**Team D — Backend:**
- Migration `20260313100000_slim_club_bundle_limits.sql`: LIMIT clauses on `fetch_club_bundle` (members 50, rail items 50, polls 20). Member and rail-item limits use subquery pattern so LIMIT applies before `jsonb_agg`.

**Social Activity v1 Rollout:**
- `social_activity_v1` rolled from 0% to 100% (migration `20260313120000_social_activity_v1_rollout_100.sql`).
- Fixed Browse pagination friend count prefetch gap in `BrowseView.fetchNextPage()`.

**Config Fix:**
- Wired `Config/*.xcconfig` files into Xcode project as `baseConfigurationReference`.
- `Info.plist` now uses `$(SUPABASE_URL)` and `$(SUPABASE_ANON_KEY)` variable references instead of hardcoded values.
- Removed hardcoded Supabase key fallback from SupabaseService; missing credentials now surface as `configError`.

**Build:** Build 16 uploaded to TestFlight. 8/8 quality gates passing.
68 Swift files, 156 migrations.

### 2026-03-16: UX Smoothness + Club Bundle Fix

**UX Smoothness (4 improvements):**
- Detail page section skeletons: shimmer placeholders for Cast/Production/AdaptationPath during loading (AnimeDetailView, MangaDetailView).
- Optimistic collection toggles: `toggleInCollection` now flips local `collectionAnimeIds`/`collectionMangaIds` Sets immediately, with rollback on server failure.
- Browse pagination skeleton: replaced `ProgressView()` spinner with 4 ghost cards matching `BrowseGridSkeleton`.
- Collection load-more prefetch: `fetchNextCollectionFeedPage` now prefetches images + friend counts + streaming availability for newly loaded items.

**Bug Fix: fetch_club_bundle regression (migration 20260316100000):**
- Fixed wrong column names: `a.episode_count` → `a.episodes`, `m.chapter_count` → `m.chapters`.
- Restored missing `reactions` and `my_reactions` fields in item JSON output (dropped in 20260313100000).
- Added `#if DEBUG` diagnostic logging to `ClubDetailView.loadBundle()` catch block.

**Build:** Build 17 uploaded to TestFlight. 8/8 quality gates passing.
68 Swift files, 157 migrations.

### 2026-03-16: Clubs list page editorial redesign ("Journal Foyer")

Replaced KuroGlassCard-based club rows with clean editorial entries (serif typography, rule-line dividers, no card wrappers, no chevrons). New private structs: `JournalEmptyState` (magazine-page opener with decorative rules + serif tagline + full-width CTA buttons), `JournalLoadingSkeleton` (3 ghost cards with shimmer + dividers), `JournalActionRow` (extracted create/join capsule buttons), `JournalClubCard` (19pt serif title, sharing-level capsule, member count, relative time, activity preview). LazyVStack spacing changed from `KuroDesignSpacing.md` to 0 with explicit editorial dividers. No new files — all changes in `ClubsView.swift`.

### 2026-03-16: Foundation refactor wave — extracted view/service slices

- Extracted Browse paging/query code into `Kuro/Services/SupabaseService+Browse.swift`, reducing `SupabaseService.swift` from ~5.8k lines to 5,494 lines and isolating browse RPC/query logic from auth, collection, club, and detail paths.
- Split the largest SwiftUI surfaces into navigable component files without changing runtime ownership: `Kuro/Views/ClubDetailSections.swift`, `Kuro/Views/EditorialCollectionComponents.swift`, and `Kuro/Views/BrowseComponents.swift`.
- Refactored `EditorialCollectionView.swift` into smaller view builders (`statusSummarySection`, `collectionHeaderSection`, `collectionContent`) and centralized collection metadata prefetch so the main body is type-checkable and easier to maintain.
- Build/test validation after the split: iOS build succeeded, `KuroTests` passed, Supabase linked schema lint passed.
- Current repo inventory after the refactor wave: 74 Swift files, 157 migrations.

### 2026-03-16: Foundation pass — topology cleanup + similar-title batching

- Moved runtime `PosterView.swift` into `Kuro/Views/PosterView.swift` and removed the last compiled Swift source from the repo root.
- Moved historical/debug source-like files into `scripts/legacy/` and renamed manual importer utilities under `scripts/manual/` for readability.
- Added `Kuro/Services/SupabaseService+Recommendations.swift` and extracted the similar-title recommendation path out of the `SupabaseService.swift` monolith.
- Reworked similar-title hydration to use cache-first batched `IN (...)` queries before any per-ID fallback, removing the avoidable detail-fetch fanout on detail pages.
- Added audit deliverables: `docs/foundation-audit-2026-03-16.md` and `docs/foundation-remediation-plan-2026-03-16.md`.
- Updated repo inventories after the topology move and service split. 70 Swift files, 157 migrations.

### 2026-03-16: Foundation refactor wave — design-token cleanup on extracted surfaces

- Replaced the remaining raw `.black` / `.white` surface styling in `Kuro/Views/EditorialCollectionComponents.swift` and `Kuro/Views/BrowseComponents.swift`; both extracted files now render through `KuroDesignSystem` color tokens and typography helpers only.
- Added `Font.kuroCustom(...)` plus a small set of missing black/white opacity tokens in `Kuro/Design/KuroDesignSystem.swift` so the extracted component files can keep exact sizing without falling back to ad hoc `.font(.system(...))` and raw opacity chains.
- Reduced `Kuro/Views/ClubDetailSections.swift` from a broad mix of raw color/font values to tokenized styling on its high-traffic sections (rails, polls, reactions, add-item sheet, settings/member badges), keeping only deliberate dynamic opacity cases where the value depends on runtime state.
- No new runtime files or schema changes. Repo inventory remains 74 Swift files, 157 migrations.

### 2026-03-16: Foundation refactor wave — concierge/shell cleanup + warning removal

- Removed the remaining static raw design drift from `Kuro/Views/ConciergeComponents.swift`: raw `.black` / `.white` usage and ad hoc `.font(.system(...))` calls now route through `KuroDesignSystem` tokens plus `Font.kuroCustom(...)`, keeping the existing concierge look while centralizing the styling surface.
- Cleaned `Kuro/ContentView.swift` so the app shell/header no longer falls back to raw system colors/fonts for the launch wordmark, header icons, title window, or pager placeholder. Added a small in-file `headerIconCircle` helper to reduce repeated glass/icon styling without changing ownership.
- Removed the iOS 26 `Text + Text` deprecation warnings in `Kuro/Views/DetailPages/AdaptationPathSection.swift` by switching the editorial footnote prose to interpolated `Text(...)` composition while keeping the same copy and tap behavior.
- Removed the dead `lastError` retry state from `Kuro/Services/FeatureFlags.swift`; retry behavior is unchanged.
- Validation after this pass: iOS build succeeded (`-derivedDataPath /tmp/KuroNextWaveDD`) and all 8 quality gates passed again. No new runtime files or schema changes. Repo inventory remains 74 Swift files, 157 migrations.

### 2026-03-16: Clubs list page mosaic card redesign (matches HTML mockup)

- New migration `20260316220000_clubs_list_cover_images_members.sql` — enriches `fetch_my_clubs_enriched` RPC with `cover_images` (up to 4 cover URLs from rail items) and `member_names` (up to 4 display names from profiles).
- `ClubListRow` in `SupabaseService.swift` gained 2 optional fields: `cover_images: [String]?`, `member_names: [String]?`.
- `JournalClubCard` in `ClubsView.swift` rewritten: 2x2 image mosaic grid (140pt, 1px gaps), card body with serif name + overlapping avatar stack + relative time + chevron, white card wrapper with 12pt corners + border + shadow, 8pt unread dot overlay.
- `JournalLoadingSkeleton` updated to match card shape (140pt mosaic placeholder + text bars inside bordered card).
- `LazyVStack(spacing: 16)` replaces divider-based spacing.
- 68 Swift files (unchanged), 158 migrations (+1).

### 2026-03-17: Lean hot-path wave — club bundle tightening + concierge shell cleanup

- Added migration `20260317110000_fetch_club_bundle_ordering_and_poll_counts.sql` to tighten `fetch_club_bundle` without changing the RPC contract: deterministic tie-break ordering for rails, rail items, member statuses, and polls; poll option vote counts now aggregate once per poll instead of doing per-option scalar `count(*)` subqueries; `my_vote_option_id` lookup now uses a defensive `LIMIT 1`.
- `supabase db lint --linked` passes after the new club-bundle migration. Existing club-table index coverage remains sufficient; no new index migration was needed for this pass.
- Cleaned `Kuro/Views/ConciergeView.swift` so the AniList import shell, timeline shell, tutorial overlay, and CTA chrome now route through `KuroDesignSystem` tokens and `Font.kuroCustom(...)` instead of raw `.black` / `.white` or ad hoc `.font(.system(...))` styling.
- This wave intentionally skipped the conditional ClubDetail consumer follow-up because the backend worker kept the `fetch_club_bundle` contract stable and did not require any Swift-side adaptation.
- Validation after integration: iOS build succeeded (`-derivedDataPath /tmp/KuroLeanWaveDD`), `supabase db lint --linked` passed, and the repo inventory is now 74 Swift files / 160 migrations.

### 2026-03-17: Follow-up hardening — streaming split + clean migration gate

- Added `Kuro/Services/SupabaseService+Streaming.swift` and moved the streaming-availability domain behavior out of `SupabaseService.swift`: provider registry/user-service fetches, provider-availability RPC calls, club shared-provider fetches, and the provider note/cache helpers now live in the companion file while the shared state remains on `SupabaseService`.
- Finished the last remaining static error-color drift in `Kuro/Views/ConciergeView.swift` by routing the inline error text through the new `Color.kuroError` token in `Kuro/Design/KuroDesignSystem.swift`.
- Tracked the previously untracked migrations `20260316220000_clubs_list_cover_images_members.sql`, `20260317063000_clubs_list_cover_image_large.sql`, and `20260317110000_fetch_club_bundle_ordering_and_poll_counts.sql` so the default migration hygiene gate can pass without `MIGRATIONS_ALLOW_UNTRACKED=1`.
- Validation after this follow-up: iOS build succeeded (`-derivedDataPath /tmp/KuroDo123DD4`), `supabase db lint --linked` passed, and the current repo inventory is now 75 Swift files / 160 migrations.

### 2026-03-18: Remediation wave — service + view decomposition

- Major `SupabaseService.swift` decomposition: extracted 6 new companion files — `+Clubs.swift` (club CRUD, bundle, reactions, polls, notifications, entity/ladder fetches), `+ClubRealtime.swift` (Realtime subscriptions), `+Collection.swift` (collection queries, prefetch), `+Concierge.swift` (concierge RPCs), `+Social.swift` (title comments/reactions), `+UserLists.swift` (anime/manga list mutations). State and caches remain on the main class; companion files extend it.
- `ClubDetailView.swift` decomposed into 3 companion files: `ClubDetailShellComponents.swift` (hero, status bar, tab bar, bottom bar), `ClubDetailTabComponents.swift` (rails/activity/polls tab content), `ClubDetailSheets.swift` (settings, add-item, rail search).
- `ConciergeView.swift` AniList import flow extracted into `ConciergeView+AniListImport.swift` + `ConciergeAniListImportCoordinator.swift`.
- `EditorialDiscoverView.swift` routing extracted into `EditorialDiscoverRouting.swift`.
- `OnboardingView.swift` cleaned.
- 2 new migrations: `20260318103000_import_track_and_worker_state.sql` (import tracking + worker state), `20260318104000_club_loading_rpcs.sql` (`fetch_my_clubs_loading` + `fetch_club_bundle_loading` lightweight loading RPCs).
- Commit `4dec33d`. 20 files changed, +5930 / -4346 lines.

### 2026-03-18: Wire club loading RPCs

- `fetchMyClubs()` in `SupabaseService+Clubs.swift` now prefers `fetch_my_clubs_loading` and falls back to `fetch_my_clubs_enriched()`.
- Added `ClubBundleLoading` model and `fetchClubBundleLoading(clubId:)` for lightweight club-detail loading snapshots.
- `ClubDetailView.swift` requests the lightweight loading snapshot in parallel with the full bundle, enriching the initial loading state immediately.
- Commit `926c848`. 2 files changed, +110 / -17 lines.
- Validation: iOS build passed, unit tests passed. `supabase db lint --linked` not re-verified in this session (requires DB auth). Current repo inventory: 86 Swift files / 162 migrations.

### 2026-03-25: Auth transport errors clarified (Build 19)

- `SupabaseService.userFacingAuthErrorMessage(from:)` now maps transport-layer auth failures into explicit user copy:
  - offline -> `No internet connection. Check your connection and try again.`
  - timeout -> `The request timed out. Please try again.`
  - cannot-connect / DNS / TLS / bad-server-response -> `Can't reach the server right now. Please try again.`
- `AuthView` now uses the shared mapping instead of local string matching, so sign-in, sign-up, and Apple sign-in all surface the same clearer messaging.
- Added focused `KuroTests` coverage for offline, timeout, wrapped cannot-connect, and invalid-credentials cases.
- Commit `6836fcb`. TestFlight build `19` uploaded successfully after all 8 quality gates passed.

### 2026-03-26: Discover rotation + ancillary anime exclusions

- Added migration `20260326221000_discover_new_to_you_rotation.sql`: `discover_bundle` is now `plpgsql`/`volatile`, `new_to_you` uses per-user `discover_rail_impressions`, and rotation prefers unseen titles first before recycling oldest impressions.
- Added migration `20260326234000_exclude_ancillary_anime_from_default_surfaces.sql`: default anime `Discover`, `Search`, and `Browse` now exclude `SPECIAL`, `MUSIC`, and `TV_SHORT`.
- Browse keeps an explicit override: if `p_format` is one of those values, the browse RPC still returns that format intentionally.
- Live verification:
  - `search_anime_page('Darwin')` now returns mainline Darwin results first.
  - `search_anime_page('One Piece Fan Letter')` no longer returns the ancillary `SPECIAL` item in default anime search.
  - default `browse_anime_page` excludes ancillary formats, while explicit `p_format = 'SPECIAL'` still returns them.
  - `discover_bundle` no longer surfaces `ONE PIECE FAN LETTER`.
- Commits `8c4e1ff` and `a8b9f78`.
