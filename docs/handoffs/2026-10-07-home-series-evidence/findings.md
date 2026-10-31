# Findings — Home / series audit, 7 October 2026

Inspection was of the working tree on HEAD `a7f39b6`, not a live `EXPLAIN` against production. Query plans below are the shapes the new RPCs use. Measured plans on a large hosted dataset were not run.

## Call inventory (integrated paths)

| Caller | Endpoint | Risk found | What this change does |
| --- | --- | --- | --- |
| `SupabaseLibraryBackend.fetchAll` | PostgREST pages of `anime_user_lists` / `manga_user_lists`, offset, up to 100 pages | Full-library read. Offset pages. No revision column, so a lost response can be applied twice by a client that increments | Home no longer uses this for the page. `home_bundle_v1` reads the caller's partial index (`user_id`, `updated_at`, id) with a keyset cursor, limit 12–50. Collection still uses the old feed until it is switched. That remaining full read is recorded, not claimed fixed. |
| `SupabaseLibraryBackend.edit` | PATCH of edited columns only | Field ownership is already narrow. No receipt, so replay is a second write. `mutationId` / `baseRevision` were accepted and dropped | `apply_progress_mutations_v1` updates progress (or a fractional label) only, writes one receipt, and conflicts on a stale base revision. The trigger advances `server_revision` for this RPC and for a direct PATCH. |
| Detail screens | Separate tasks for tags, similar, ladder, credits, episodes | Franchise-wide and unbounded credit reads on the old detail | With `series_home_native_v1` the detail asks for `series_detail_bundle_v1` (3 units, 12 cast). The old detail remains when the flag is off. |
| `ClubRealtimeCoordinator` | Per-open-club channels. Legacy content tables are off (`listensToLegacyContentTables = false`) | Earlier unfiltered `club_rail_items` / `club_votes` / reactions subscriptions are not the live path | Left as already revised. Home club text is a fresh rank-checked read, not a channel payload. No offline club body is stored. |
| `concierge-import-anilist` | Public AniList list, previously capped at 400 and turned into text | Score was POINT_10 only; notes, repeats, volumes and raw score were not a structured import | The query now also asks for raw score, volumes, repeat, notes, privacy and dates. `libraryItems` is returned beside the text. Durable apply is `apply_import_chunk_v1` (merge, mal id or anilist id, never title). |
| MAL account API | None | Advertising XML success as account connect would be false | `start_library_import_v1` raises `MAL_ACCOUNT_API_UNAVAILABLE` for `source_kind = account`. XML export parse and chunk apply are the working path. |
| `publish_mapping_revision` | Service/maintenance | A failed refresh that deletes then rebuilds can drop the last good spans | Validation runs before replacement. `UNRESOLVED_TARGET` raises and leaves the previous spans. Authenticated `auth.role()` is rejected. |

## Schema

New tables are additive: series, sections, spans (one anime or manga target), provider refs, mapping revisions, units, artwork materials, detail copy, theme links, adaptation coverage, release events, import jobs/items, receipts, tombstones, home publication counter. List rows gain `server_revision`, `lifecycle_id`, `unit_id`, `progress_label`, raw score and repeat fields. Catalogue ids are unchanged. RLS is on. Catalogue tables are public read. Jobs and intent are owner read. Receipts and tombstones have no authenticated policies; the definer functions write them.

`shares_club_at_least` is the rank check for the Home club slice. Private rank does not return a name. Comment text with `spoiler_scope` other than `none` is omitted.

## Not measured

- Production `EXPLAIN ANALYZE`
- 1000/5000 session capacity, burst and soak
- Physical device VoiceOver, haptics and scroll-versus-tap
- Live AniList or MAL HTTP
- Deployed migration identity

Those gates stay **NOT RUN**. They block a release claim.
