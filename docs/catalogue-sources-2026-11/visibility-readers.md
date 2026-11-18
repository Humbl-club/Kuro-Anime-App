# list_only visibility: reader inventory (catalogue Task 15b)

Scope of the task. Source of the list: every `.rpc("...")` the app calls (`rg '\.rpc\("' Kuro`), every direct
`.from("anime"|"manga")` read in `Kuro/`, and the latest definition of each function from
`python3 scripts/agents/policy.py --rpc <name>` cross-checked against both migration folders
(`supabase/migrations`, `supabase/prepared-migrations`). "Latest" is the last definition in filename order across
both folders; it does not prove which one is live. Prepared SQL: `20261112100400_catalogue_visibility_v1.sql`
and `20261112100401_catalogue_visibility_discover_v1.sql`. DB test: `supabase/tests/rls/125_catalogue_visibility_v1.sql`.

## Filtered (browse, search, Discover, rails, recommendations)

The filter is `<alias>.catalogue_visibility = 'visible'`, parenthesised next to the reader's existing adult predicate on
that alias. Matview-backed rails (`mv_*_trending`, `mv_*_top_rated`) check the base row (`catalogue_anime_visible(id)` /
`catalogue_manga_visible(id)`), because a matview is a copy taken at refresh time.

| Reader | Latest definition | Refs | Predicates | Migration | Behaviour tested in the fixture |
|---|---|---|---|---|---|
| `browse_anime_page`, `browse_manga_page` | 20261109001251_load_hotpaths_v1 | 1 each | 1 each | 100400 | run, list_only title absent |
| `search_anime_page`, `search_manga_page` | 20261109200000_search_staged_v1 | 3 each | 3 each | 100400 | run, list_only title absent |
| `curated_rail_cards` | 20260205231000_curated_rails | 2 | 2 | 100400 | source check only (fixture lacks `curated_rail_items`) |
| `fetch_tonight_shelf` | 20260806010000_serving_fixes_v1 | 2 | 2 | 100400 | source check |
| `fetch_daily_feature` | 20260805100000_daily_feature_display_synopsis | 2 | 2 | 100400 | source check |
| `fetch_personalized_new_to_you` | 20260731070000_taste_math_v2_hotfix | 2 | 2 | 100400 | source check |
| `fetch_realm_hidden_gem` | 20260806020000_serving_hardening_v1 | 2 | 2 | 100400 | source check |
| `fetch_because_you_rail` | 20260731150000_realm_graph_v1 | 4 | 2 (the card hydration; the other two refs read the seed title) | 100400 | source check |
| `fetch_taste_deck_batch` | 20260731150000_realm_graph_v1 | 2 | 2 | 100400 | source check |
| `recommend_ids_similar_to_seeds` | 20260806020000_serving_hardening_v1 | 2 | 1 (candidate stage; hand patch) | 100400 | source check |
| `_recommend_ids_similar_to_seeds_live` | 20260804130000_media_similar_titles_precompute | 8 | 2 (final candidate stages; the other refs are seed look-ups and curated-rail bonus pools) | 100400 | source check |
| `media_similar_v1` | 20261103100100_media_similar_v1 | 2 | 2 | 100400 | source check |
| `discover_bundle` | 20261109200200_discover_newly_added_base_v1 (parked 1c) | 18 | 18 (4 on matviews) | 100401 | source check |
| `discover_section_page_v1` | 20261104100000_discover_usability_v1 | 4 | 4 | 100401 | source check |
| `discover_mood_v1` | 20261104100100_discover_mood_perf_v1 | 8 | 4 (the rest hydrate already filtered ids) | 100401 | source check |
| `_discover_page_v1` | 20261104100000_discover_usability_v1 | 4 | 2 (the rest hydrate already filtered ids) | 100401 | source check |

"Source check" means test 125 asserts the function exists once and its stored source holds at least the predicate count
the generator added; it does not execute the reader. Executing them needs tables the DB fixture does not have
(curated rails, realm membership, similarity edges). A production-shaped run is not done.

## Not filtered, on purpose (list, export, detail, import resolution)

`collection_feed_page`, `home_bundle_v1` (+ `home_events_page_v1`, `home_pending_page_v1`), `series_detail_bundle_v1`,
`series_units_page_v1`, `series_editions_page_v1`, `collection_series_*`, `fetch_club_bundle` (club content), `get_media_ladder`,
the export identity lookup (`CatalogStore+ExportIdentities`: a public table read of 6 columns), and the by-id table reads
`CatalogStore.loadAnimeById`, `fetchAnimeCards`, `fetchTopTagsForAnime`, `DiscoveryStore` airing slots and
`DiscoveryStore+Usability.hydrateCards` (these hydrate ids a filtered RPC already chose, or a title the user opened).
Test 125 checks the user-list join, the detail/by-id read and the export lookup shape still return a `list_only` title.

## Open: not covered by this task

- **`rag_retrieve_candidates`** reads `rag_entity_index` only (no `anime`/`manga` reference). A `list_only` title can still be
  retrieved for Concierge recommendations. Needs a decision: filter inside the index refresh, or join the catalogue table.
- **`Kuro/Discovery/RecommendationsReader.swift` (`fetchSimilarAnimeFallbackByGenre`, and the manga twin at ~line 287)** is a
  PostgREST table read used as a recommendation fallback; it needs `.eq("catalogue_visibility", value: "visible")`. That is an
  app change and the column must exist first, so it ships after the migration is applied. Not done here.
- **Materialised views** `mv_{anime,manga}_{trending,top_rated}` still contain `list_only` rows until refreshed; the readers
  above filter them. (`mv_*_newly_added` are dropped by Task 15d.)
- **Parked 1c / Discover usability:** see the header of 100401. `discover_bundle` here is built on the parked 1c body.
- **Task 15d** later revokes `anime.anilist_id` from clients. The visibility predicate does not select that column.
