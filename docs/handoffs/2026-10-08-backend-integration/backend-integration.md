# Kuro backend integration — 8 October 2026

**Current status: SOURCE REPAIRED / LOCAL SQL QUALIFIED / NOT DEPLOYED. Delivery target: installed simulator.**

The [27-finding register](import-user-journey-review.md) now records the implementation dispositions. The two-wave plan is saved at [the canonical specification](../../plans/2026-10-08-import-library-home-completion.md). Imports v2 adds reviewed preparation, explicit field decisions, stop, paged results and guarded Undo while Library remains the only tracking authority.

The current production candidate is **four pinned SQL inputs and six named Edge closures**: see [deployment approval](deployment-approval.md), [manifest](backend-deployment-DRAFT.json), [exact atomic SQL](backend-atomic-DRAFT.sql) and [265-assertion rehearsal](import-v2-atomic-rehearsal-summary.json). All four execute in one guarded transaction; historical migration inputs remain intact. No deployment has happened. Fresh read-only migration/function inventories are saved as live-migrations-v2-preflight.txt and live-functions-v2-preflight.txt.

Current frontend flow: typed source selection → protected canonical pages → prepare_import_chunk_v2 review → frozen approvals → Library affected-key sequencing → apply_import_chunk_v2 receipts → finish/status → one typed Library/Home/visible Collection/Releases publication. Home/Profile discover manifests after restore. Another device can inspect/stop but cannot continue application without the original local pages.

The nine v2 contracts and shared models are documented in [import-v2-contract.md](import-v2-contract.md). Default Keep and missing-field semantics are enforced server-side, not just in views. Legacy Concierge signatures remain available and cannot write v2 jobs.

**The earlier three-input/118-assertion audit below is retained as historical context. Its deployment set and readiness recommendations are superseded by the current four-input packet.** Actual controlled MAL OAuth, real imported-title navigation, interruption/restart and changed hosted authorization/deletion remain pending. Global Home flags remain disabled; existing live RAG rollout is unchanged; no TestFlight, backfill or scheduler activation.

## Current identity and evidence

- Project: `bkdifromsqxkndnllmdj`, AniThing is Possible, main Production, eu-central-1.
- Checkout: `codex/integrated-testflight`, HEAD `a7f39b66237bc5a9558b5ab2a6758cd1b085e466`; the dirty checkout is the implementation baseline, not HEAD alone. Unrelated experiments are preserved.
- Existing authenticated Supabase CLI management access works. Named function deployment supports `--use-api`, without Docker. Two read-only administrative checks passed (absent GoTrue-user lookup and empty media-prefix listing); cleanup verification is available. Existing key was held only in the child environment, never printed or retained. No new credentials, permissions or keys were created.
- Live audit: 2026-10-07T22:37:30.898677+00:00. Runtime dependency audit: 2026-10-07T22:51:43.888002+00:00. Saved SQL is explicitly read-only.
- Literal frontend inventory: 61 RPC names, 19 direct relation names and 7 Edge slugs. Dynamic repository targets are reviewed separately; this static scan is not a proof of every runtime path.
- Six candidate Edge closures exactly match the accepted prior source checkpoint. Reuse their meaningful existing tests; do not rerun unchanged suites merely to increase counts.
- Existing customer library totals: 37 Anime and 11 Manga rows. The persistent simulator development account remains intact.

## Interaction and ownership map

| Interaction | Frontend owner and authoritative state | Backend dependencies and behavior | Current gap |
|---|---|---|---|
| Launch, sign-in, SDK restore, account switch | Identity and SessionController; one account-generation funnel | GoTrue, own profile under RLS; credential leases invalidate late work | Actual simulator password/callback/restore/sign-out passed; no new auth rewrite |
| Home initial load and paging | HomeStore consumes Library confirmed revision and pending projection | home_bundle_v1, home_events_page_v1, home_pending_page_v1; bounded independent ordered pages | All three absent live; foundation defines them |
| Episode/chapter progress, status and Undo | Library alone owns tracking, account queue, durable SQLite body and receipt | apply_progress_mutations_v1, apply_remove_mutations_v1; revisions, lifecycle, tombstones and exact unit identity | RPCs absent; forward repair fixes legacy precision and Undo lifetime compatibility |
| Collection and series children | Collection reads Library state; selection never changes tracking | Existing collection_feed_page plus collection_series_page_v1 / children_v1 | Legacy feed exists; two series RPCs absent |
| Selected season, detail, chapters/episodes | Detail consumes selected child metadata, shared Library state | series_detail_bundle_v1, series_units_page_v1, series_editions_page_v1; opaque cursors and exact labels | Three absent; populated mapping/enrichment still needs reader qualification |
| AniList import | ImportsService account-scoped durable page/action journal | concierge-import-anilist structured pages -> start/apply/finish/status RPCs -> Library refresh -> committed Home revision | Deployed AniList v5 lacks structured paging; four import RPCs absent |
| MAL account import | Account-bound native PKCE connector and Keychain; same import-job owner | Provider list API and both-media paging -> same typed provider reference/merge contract | Published simulator registration configured; OAuth consent and actual provider import not yet exercised |
| MAL file import | Bounded parser and structured drafts; same import-job contract | Same start/apply/finish/status RPCs, no source omission deletion | Local proof present; real simulator merge/recovery requires deployment |
| Concierge Apply/Undo | Immutable retry action, typed disposition, one Library refresh hook | Existing slugs -> service-only apply_import_session / undo_import_session | Live handlers treat deletion refusals as retryable500; local403 contract ready |
| Recommendations and retrieval | ConciergeStore credential lease, Catalog reader | recommend -> retrieve-assist -> rag_retrieve_candidates; public catalogue candidate hydration and budgets | Live medium-free cache and unchecked retrieved identities; candidate fixes required for existing 5% RAG cohort |
| Club activity, private discussion and reactions | Clubs/Social permission generation clears Home/detail/peer caches | Current memberships and scoped comments; club_activity_signals / club_membership_signals invalidations | Signals exist; scoped/paged APIs absent and current disclosure SQL must integrate |
| Provider availability and outbound links | Providers owner; private preference calls under credential lease | Existing public provider catalogue/RPCs plus account preferences/shared-club reads | Existing contracts present; optional availability remains staged |
| Account deletion and upload races | Identity deletion only reports success after handler acknowledgment | JWT-derived user, write barrier, Storage origin cleanup, club memberships, GoTrue deletion | Live v9 lacks stricter concierge acknowledgment and bounded Apple revoke path; refreshed race proof required |
| Catalogue ingestion and operational workers | Distinct catalog/synopsis/provider/relation/enrichment runs | Existing slugs/RPCs, catalog bridge triggers, queue/lease/finish contracts | This deployment installs future bridge/queue triggers; no historical backfill or new scheduler activation |

## Confirmed findings and concrete repairs

1. **Sixteen frontend RPCs are absent live.** Apply the pinned foundation and account-lifecycle forward input in one guarded transaction. All 16 definitions are present in that candidate.
2. **Status-only legacy Apply erases precise chapter/unit metadata.** The new forward repair omits position when progress was omitted; explicit zero still writes zero.
3. **Undo loses exact metadata and can reverse a later precise edit.** Capture unit/label in journals, compare and restore progress/unit/label as one value and use the authoritative writer once.
4. **Undo can reverse a removed-and-readded entry.** Journal lifecycle identity and skip a mismatching lifetime before any mutation.
5. **Historical Undo has no lifecycle proof.** Whole-item skip with `legacy_lifecycle_unavailable` is the deliberately conservative compatibility decision. This changes older Undo behavior; it preserves title data and avoids invented identity or old-session backfill.
6. **AniList v5 cannot serve the frontend structured stream.** Deploy the full seven-file candidate closure, retaining old response fields for existing clients.
7. **Apply/Undo deletion failures are misclassified.** Deploy both current complete closures so the exact deletion refusal is terminal403 rather than retryable500.
8. **Deletion can accept an ambiguous concierge cleanup response.** Deploy the complete deletion closure, which requires success=true and bounds Apple token revocation without skipping Storage cleanup.
9. **Live retrieval mixes independent Anime/Manga identities.** Deploy recommend and retrieve-assist together: medium-specific rag-v2 keys, finite valid identifiers/scores and medium checks before candidate/seed use.
10. **Staging documentation disagrees with live RAG.** rag_assist_v1 is enabled at5% for DE/AT/CH, updated11February. Fix its existing chain; do not activate another feature or change this percentage.
11. **Prepared tables are not populated serving proof.** Foundation adds series/unit/art/theme infrastructure and honest singleton/empty responses. Existing catalog backfill and enrichment need an explicit bounded data step and reader proof before claiming populated season/unit journeys complete.
12. **Simulator Debug overrides differ from release cohorts.** feature_flag_overrides is intentionally omitted for current Debug-only delivery. No claim is made about signed Release cohort overrides, TestFlight, physical-device behavior or App Store readiness.

## Exact deployment set and compatibility

See [backend-deployment-DRAFT.json](backend-deployment-DRAFT.json) for all source and closure hashes and [backend-atomic-DRAFT.sql](backend-atomic-DRAFT.sql) for the exact guarded transaction.

| SQL identity | Exact SHA256 | Role |
|---|---|---|
| 20261007040000 | `9803ed3ec24a10d5e80a4388835c09f5a0eda8f2a2ca2095f77b91cb7cf1d651` | 20261007040000_series_home_foundation_v1.sql |
| 20261007130000 | `8cfb01f295f013dc2562b8a8f74ce865ffe7fe9c5bae071b7f15617d5f73b777` | 20261007130000_series_account_lifecycle.sql |
| 20261008100000 | `af22886f86a23d7e5314f49de59b63185a28b3c5b47c98a4f84f2a00b7f4eccd` | 20261008100000_import_status_fence_preserves_units.sql |

| Edge slug | Live version before deployment | Candidate closure |
|---|---:|---:|
| concierge-import-anilist | 5 | 7 files; JWT verification remains enabled |
| concierge-apply | 26 | 6 files; JWT verification remains enabled |
| concierge-undo | 17 | 4 files; JWT verification remains enabled |
| delete-account | 9 | 4 files; JWT verification remains enabled |
| concierge-recommend | 49 | 8 files; JWT verification remains enabled |
| concierge-retrieve-assist | 8 | 4 files; JWT verification remains enabled |

- Apply additive SQL before its consumers. No blanket migration push, applied-history rewrites, function prune, global feature rollout, scheduler activation or TestFlight.
- One atomic transaction encloses all three SQL execution bodies, original-source migration-history records, postflight checks and PostgREST schema reload. Only original standalone wrappers are omitted from execution.
- Lock timeout3s and statement timeout30s bound work. List-table locks protect legacy-field digests; existing progress, statuses, notes, ratings and retained history must remain unchanged. On error the complete SQL delta rolls back.
- New default/revision/lifecycle fields are added to the existing48 list rows. Catalog bridge and future-ingestion queue/delete triggers and club/social behavior affect existing production clients even while global Home flags stay off.
- All20 new tables require RLS. Public callable functions derive account identity from auth.uid(); service-only mutation helpers retain restricted grants and search_path. Flags are presentation rollout, never authorization.
- Existing counterpart/source contracts, auth settings and deployment IDs are pinned; recheck them immediately before replacement. Stop if the live baseline changed.
- Legacy client Apply/Undo fields and dispositions remain readable. Older lifecycle-unknown Undo is the disclosed exception above. No customer backfill or deletion is implied by code retirement.

## Risk-matched acceptance and next execution

| Step | Required evidence | Status now |
|---|---|---|
| Contract audit | Live function signatures/grants, relation columns/policies, trigger/publication identity, frontend and Edge dependency mapping | PASS at read-only metadata/source layer |
| Forward import repair | Regression for status-only precision, coupled restoration, newer edit and lifetime replacement | SQL81 PASS40 assertions; independently source accepted |
| Exact SQL deployment assembly | Pinned originals/history bytes, one transaction, guards and actual disposable fixture execution | Independent source acceptance PASS; expanded rehearsal PASS118 assertions |
| Direct tracking writer | Affected SQL94 confirms exact fractional writer behavior and immutable replay | PASS69 assertions on the exact bundle; unchanged broader suites reused |
| Named Edge replacements | Closure hashes match accepted checkpoint; effective versions/JWT after named deployment | Source evidence reused; NOT DEPLOYED |
| Installed simulator integration | Home/detail/Collection use shared revisions; both-media import/recovery and account transition execute real owners | Sign-in passes; new foundation workflows pending deployment |
| Live authorization and services | Owner/member/outsider outcomes; API error shape; current Realtime revocation; deletion overlap/old-token refusal and origin cleanup | Prior evidence retained historically; fresh changed-backend proof pending |
| Delivery | Current installed simulator source/backend identities, clean disposable resources and disable/recovery record | NOT COMPLETE |

After reviewed deployment, enable foundation then Home only through the installed Debug qualification simulator launch arguments. Keep global flags0%. Exercise populated Anime and Manga through existing catalog data; use one deliberate page request at a time. Do not count a fixture response as a real provider, Realtime or Storage result.

Reuse existing failures/retry tests. Run the affected direct-writer/import SQL tests and exact transaction once, then changed live and simulator interactions. Repeat only for changed source or unresolved failures. Do not add coverage quotas, extreme load runs, a screenshot matrix or redundant broad suites.

Bound live work to newly recorded disposable resources: at most5 test accounts,5 concurrent requests,5requests/s and1000API calls per qualification run. Keep the retained development account; delete disposable accounts via the app handler and verify GoTrue rows and Storage origin paths administratively. Do not launch probes that lack a cleanup-verification path.

Provider consent remains explicit at the normal MAL authorization page. Public native client registration is already configured; do not create secrets or bypass the blocked registration administration page.

## Disable, recovery and partial deployment

Before SQL commit, any failed preflight/DDL/history/postflight aborts the transaction. After commit, recover with a reviewed forward correction; do not drop customer columns, receipts, jobs, journals or queued device actions.

Disable the new native surface by relaunching Debug without its two local Home overrides; global defaults stay off. That does not disable deployed grants/triggers. Preserve immutable attempted mutations and receipts for retries. If an Edge replacement fails, stop, record the successfully deployed versions and leave native consumers disabled until the set is consistent. Restore only a separately reviewed compatible closure; do not blindly restore an old handler that omits a safety repair.

## Complete literal frontend contract inventory

Each row identifies actual owners/call sites. “Present” is metadata/source evidence; it is not execution acceptance.

| RPC | Frontend call site(s) | Live audit |
|---|---|---|
| `add_club_rail_item` | `Kuro/Clubs/ClubsStore.swift:612` | Present |
| `apply_import_chunk_v1` | `Kuro/Imports/ImportsService.swift:292` | Absent; foundation candidate |
| `apply_progress_mutations_v1` | `Kuro/Composition/PostgrestLibraryTransport.swift:78`; `Kuro/Home/HomeStore.swift:645` | Absent; foundation candidate |
| `apply_remove_mutations_v1` | `Kuro/Composition/PostgrestLibraryTransport.swift:87` | Absent; foundation candidate |
| `batch_provider_availability_for_media_v2` | `Kuro/Providers/ProviderAvailabilityStore.swift:324` | Present |
| `batch_providers_for_media` | `Kuro/Providers/ProviderAvailabilityStore.swift:370` | Present |
| `browse_anime_page` | `Kuro/Discovery/DiscoveryStore.swift:190` | Present |
| `browse_manga_page` | `Kuro/Discovery/DiscoveryStore.swift:232` | Present |
| `cast_club_vote` | `Kuro/Clubs/ClubsStore.swift:625` | Present |
| `check_club_activity_since` | `Kuro/Clubs/ClubsStore.swift:758` | Present |
| `check_email_exists` | `Kuro/Identity/AuthService.swift:165` | Present |
| `club_shared_providers` | `Kuro/Providers/ProviderAvailabilityStore.swift:573` | Present |
| `collection_feed_page` | `Kuro/Collection/CollectionStore.swift:316` | Present |
| `collection_series_children_v1` | `Kuro/Collection/CollectionStore.swift:514` | Absent; foundation candidate |
| `collection_series_page_v1` | `Kuro/Collection/CollectionStore.swift:484` | Absent; foundation candidate |
| `count_friends_tracking` | `Kuro/Social/SocialActivityStore.swift:259` | Present |
| `create_club` | `Kuro/Clubs/ClubsStore.swift:461` | Present |
| `create_club_poll` | `Kuro/Clubs/ClubsStore.swift:650` | Present |
| `create_club_rail` | `Kuro/Clubs/ClubsStore.swift:637` | Present |
| `delete_title_comment` | `Kuro/Social/SocialActivityStore.swift:197` | Present |
| `discover_bundle` | `Kuro/Discovery/DiscoveryStore.swift:114` | Present |
| `enqueue_media_availability_refresh` | `Kuro/Providers/ProviderAvailabilityStore.swift:415` | Present |
| `enqueue_media_relation_refresh` | `Kuro/Catalog/CatalogStore.swift:753` | Present |
| `fetch_because_you_rail` | `Kuro/Discovery/DiscoveryStore.swift:271` | Present |
| `fetch_club_bundle` | `Kuro/Clubs/ClubsStore.swift:528` | Present |
| `fetch_club_bundle_loading` | `Kuro/Clubs/ClubsStore.swift:561` | Present |
| `fetch_daily_feature` | `Kuro/Discovery/DiscoveryStore.swift:251` | Present |
| `fetch_friend_activity_for_title` | `Kuro/Social/SocialActivityStore.swift:163` | Present |
| `fetch_my_clubs_enriched` | `Kuro/Clubs/ClubsStore.swift:402` | Present |
| `fetch_my_clubs_loading` | `Kuro/Clubs/ClubsStore.swift:400` | Present |
| `fetch_my_taste_profile` | `Kuro/Taste/TasteStore.swift:152` | Present |
| `fetch_personalized_new_to_you` | `Kuro/Taste/TasteStore.swift:175` | Present |
| `fetch_realm_hidden_gem` | `Kuro/Discovery/DiscoveryStore.swift:311` | Present |
| `fetch_taste_deck_batch` | `Kuro/Taste/TasteStore.swift:132` | Present |
| `fetch_tonight_shelf` | `Kuro/Discovery/DiscoveryStore.swift:291` | Present |
| `finish_library_import_v1` | `Kuro/Imports/ImportsService.swift:302` | Absent; foundation candidate |
| `friend_activity_page_v1` | `Kuro/Social/SocialActivityStore.swift:160` | Absent; foundation candidate |
| `get_manga_chapter_status` | `Kuro/Catalog/CatalogStore.swift:904` | Present |
| `get_media_availability_status` | `Kuro/Providers/ProviderAvailabilityStore.swift:484` | Present |
| `get_media_ladder` | `Kuro/Catalog/CatalogStore.swift:720` | Present |
| `get_provider_availability_refresh_queue_summary` | `Kuro/Providers/ProviderAvailabilityStore.swift:449` | Present |
| `home_bundle_v1` | `Kuro/Home/HomeStore.swift:302`; `Kuro/Home/HomeStore.swift:354`; `Kuro/Home/HomeStore.swift:444` | Absent; foundation candidate |
| `home_events_page_v1` | `Kuro/Home/HomeStore.swift:388` | Absent; foundation candidate |
| `home_pending_page_v1` | `Kuro/Home/HomeStore.swift:413` | Absent; foundation candidate |
| `import_job_status_v1` | `Kuro/Imports/ImportsService.swift:287` | Absent; foundation candidate |
| `join_club` | `Kuro/Clubs/ClubsStore.swift:475` | Present |
| `leave_club` | `Kuro/Clubs/ClubsStore.swift:490` | Present |
| `recommend_ids_similar_to_seeds` | `Kuro/Discovery/RecommendationsReader.swift:80` | Present |
| `record_outbound_link` | `Kuro/Telemetry/OutboundLinkTelemetry.swift:46` | Present |
| `record_taste_deck_signal` | `Kuro/Taste/TasteStore.swift:227` | Present |
| `save_user_streaming_services` | `Kuro/Providers/ProviderAvailabilityStore.swift:540` | Present |
| `search_anime_page` | `Kuro/Search/SearchStore.swift:413` | Present |
| `search_manga_page` | `Kuro/Search/SearchStore.swift:447` | Present |
| `series_detail_bundle_v1` | `Kuro/Home/HomeStore.swift:96` | Absent; foundation candidate |
| `series_editions_page_v1` | `Kuro/Home/HomeStore.swift:118` | Absent; foundation candidate |
| `series_units_page_v1` | `Kuro/Home/HomeStore.swift:108` | Absent; foundation candidate |
| `start_library_import_v1` | `Kuro/Imports/ImportsService.swift:277` | Absent; foundation candidate |
| `toggle_club_reaction` | `Kuro/Clubs/ClubsStore.swift:665` | Present |
| `toggle_comment_reaction` | `Kuro/Social/SocialActivityStore.swift:210` | Present |
| `upsert_title_comment` | `Kuro/Social/SocialActivityStore.swift:186` | Present |
| `upsert_title_comment_scoped_v1` | `Kuro/Social/SocialActivityStore.swift:183` | Absent; foundation candidate |

| Direct relation | Frontend call site(s) | Live audit |
|---|---|---|
| `anime` | `Kuro/Catalog/CatalogStore.swift:96`; `Kuro/Catalog/CatalogStore.swift:193`; `Kuro/Catalog/CatalogStore.swift:342`; `Kuro/Discovery/RecommendationsReader.swift:96`; `Kuro/Releases/ReminderScheduler.swift:182` | Present |
| `anime_characters` | `Kuro/Catalog/CatalogStore.swift:415`; `Kuro/Catalog/CatalogStore.swift:665` | Present |
| `anime_staff` | `Kuro/Catalog/CatalogStore.swift:446`; `Kuro/Catalog/CatalogStore.swift:597` | Present |
| `anime_studios` | `Kuro/Catalog/CatalogStore.swift:477`; `Kuro/Catalog/CatalogStore.swift:568` | Present |
| `chapters` | `Kuro/Catalog/CatalogStore.swift:864`; `Kuro/Catalog/CatalogStore.swift:886` | Present |
| `concierge_events` | `Kuro/Services/ConciergeAnalytics.swift:115` | Present |
| `episodes` | `Kuro/Catalog/CatalogStore.swift:825`; `Kuro/Catalog/CatalogStore.swift:847`; `Kuro/Catalog/CatalogStore.swift:920` | Present |
| `external_links` | `Kuro/Catalog/CatalogStore.swift:804` | Present |
| `feature_flag_overrides` | `Kuro/Services/FeatureFlags.swift:126` | Absent; deliberately excluded Debug cohort table |
| `feature_flags` | `Kuro/Services/FeatureFlags.swift:110` | Present |
| `manga` | `Kuro/Catalog/CatalogStore.swift:141`; `Kuro/Catalog/CatalogStore.swift:249`; `Kuro/Catalog/CatalogStore.swift:373`; `Kuro/Discovery/RecommendationsReader.swift:118` | Present |
| `manga_authors` | `Kuro/Catalog/CatalogStore.swift:539`; `Kuro/Catalog/CatalogStore.swift:631` | Present |
| `manga_characters` | `Kuro/Catalog/CatalogStore.swift:508`; `Kuro/Catalog/CatalogStore.swift:672` | Present |
| `mv_anime_trending` | `Kuro/Discovery/DiscoveryStore.swift:140` | Present |
| `profiles` | `Kuro/Identity/AuthService.swift:107` | Present |
| `realm_meta` | `Kuro/Taste/TasteStore.swift:195` | Present |
| `streaming_services` | `Kuro/Providers/ProviderAvailabilityStore.swift:493` | Present |
| `user_airing_next` | `Kuro/Releases/ReleasesStore.swift:136` | Present |
| `user_streaming_services` | `Kuro/Providers/ProviderAvailabilityStore.swift:516` | Present |

| Edge slug | Frontend call site(s) | Deployment decision |
|---|---|---|
| `concierge-apply` | `Kuro/Imports/ImportsService.swift:234` | Named candidate replacement |
| `concierge-import-anilist` | `Kuro/Imports/ImportsService.swift:355`; `Kuro/Imports/ImportsService.swift:425`; `Kuro/Imports/ImportsService.swift:444` | Named candidate replacement |
| `concierge-parse` | `Kuro/Concierge/ConciergeStore.swift:75`; `Kuro/Imports/ImportsService.swift:193` | Retain existing deployment |
| `concierge-recommend` | `Kuro/Concierge/ConciergeStore.swift:113` | Named candidate replacement |
| `concierge-retrieve-feedback` | `Kuro/Concierge/ConciergeStore.swift:160` | Retain existing deployment; staged feedback remains gated |
| `concierge-undo` | `Kuro/Imports/ImportsService.swift:395` | Named candidate replacement |
| `delete-account` | `Kuro/Identity/AuthService.swift:146` | Named candidate replacement |

## Saved evidence

- [Frontend contract inventory](frontend-contract-inventory.json)
- [Live schema/policy/grant/trigger/publication inventory](live-inventory.json)
- [Live legacy mutation/privacy/deletion definitions](live-function-source.json)
- [Live handler SQL/table dependency signatures](live-runtime-dependencies.json)
- [Administrative cleanup-access preflight](admin-cleanup-preflight.json)
- [Prepared read-only deployment postflight](deployment-postflight-readonly.sql)
- [Deployed Edge identities](deployed-edge-identities.json)
- [Candidate runtime closure hashes](candidate-edge-closures.json)
- [Unchanged Edge evidence reuse](edge-evidence-reuse.json)
- [Latest simulator sign-in and MAL configuration evidence](../2026-10-08-simulator-qualification/qualification.md)

Nothing was deployed by this audit/repair initiative. Final qualification cannot pass until the reviewed set is installed and the changed workflows are exercised.
