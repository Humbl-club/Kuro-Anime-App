# Anime music and related metadata — source feasibility

Checked 26 September 2026, Europe/Berlin. Primary provider documentation/source only. Read-only research: no catalogue import, music download, playback, account change or project edit. Root agent separately audits Kuro's already-ingested fields; this memo does **not** label any field unused in Kuro without that comparison.

## Recommendation

If “songs for seasons/episodes” means opening and ending credits, **AnimeThemes is the best structural match among the sources checked**. Start with a compact Music section containing OP/ED label, song, credited performers, episode coverage where known, and verified outbound music links. Full soundtracks, episode background cues and in-app/background playback are separate scopes. They cannot be inferred from an opening/ending catalogue.

The current documentation supports this proposal, but a live AnimeThemes metadata request returned HTTP 403 from this environment; Jikan returned 504. No working integration or complete coverage is claimed. AnimeThemes' indexed homepage also currently reports a host-datacenter outage; that message may be stale and does not establish the cause of the 403. [Provider homepage](https://animethemes.moe/)

## Verified source capabilities

### 1. AniList: catalogue and relationships, not a structured theme-song catalogue

Current official Media reference exposes IDs including `idMal`, multilingual titles, season/year, dates, format, episode/duration totals, relations, staff, studios, tags, airing schedules, external links, trailers and legal streaming-episode links. It does **not document song, opening-theme or ending-theme fields on Media**. Theme-music credits may be represented by staff roles, but that is not a reliable normalized song/version/episode model. `isLicensed` describes the media's licensing/self-published classification; it is not permission for Kuro to play music. [Media schema](https://docs.anilist.co/reference/object/media), [Media edge roles](https://docs.anilist.co/reference/object/mediaedge)

External links have provider identity, type, language, notes and disabled state. Preserve those distinctions rather than flattening all URLs into a generic “watch” link. Staff/voice roles include language, role notes and dub-group distinctions, useful for correctly labeled credits. [External-link schema](https://docs.anilist.co/reference/object/mediaexternallink), [Staff-role schema](https://docs.anilist.co/reference/object/staffroletype)

For root's comparison, candidate field groups are relation type and source IDs; full paginated staff/character relationships; external-link disabled/language/type metadata; season/duration/source/format; airing freshness; tag spoiler flags; staff-role/dub distinctions. Availability in a schema does not prove population coverage or absence from Kuro.

**Terms:** AniList prohibits mass collection and competing non-complementary tracker services; its under-$150/month commercial allowance is not an override of those restrictions. Existing authorization, if any, must cover the actual product and data use before enlarging an ingestion strategy. Current rate documentation states 90/min nominally but includes a degraded-state warning of 30/min and says rate-limit increases are not currently accepted. Implement adaptive headers/backoff, not a hard assumption of 90. [Terms](https://docs.anilist.co/guide/terms-of-use), [rate limits](https://github.com/AniList/docs/blob/master/docs/guide/rate-limiting.md)

Access: current indexed official schema; official GitHub docs fetched directly. GraphQL introspection returned403, so no live schema-response claim. Docs repository HEAD `03281c0a4bbf0c7f2097e0c935cddaed1096aa65`, dated 18 Aug 2026 (repository commit, not each page's publication date).

### 2. AnimeThemes: structured OP/ED, versions and coverage

The official documentation distinguishes:

| Entity | Useful available data | Important interpretation |
|---|---|---|
| Anime | Provider ID, name/slug, premiere season/year, format, timestamps, external resources | A production, not an arbitrary franchise umbrella |
| AnimeTheme | OP/ED type, sequence number, song association | OP2 is a sequence label, not “season 2” |
| AnimeThemeEntry | Version, nullable `episodes` string, spoiler/NSFW, notes, timestamps | Coverage is text, not guaranteed normalized integers; version can represent visual changes |
| Song / performance | Song ID/title; artist associations, credited alias/character/member information | Do not merge recording, composition, performer and character identities solely by title |
| External resource | Site, link, nullable external integer ID | AniList/MAL joins and music-provider links; preserve URL because many music IDs are not integers |
| Video / Audio | Separate resource IDs, storage URLs and technical metadata | Technical access is not playback/redistribution licensing |

Sources: [Anime](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/anime/index.md), [Theme](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/animetheme/index.md), [Entry](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/animethemeentry/index.md), [Song](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/song/index.md), [performance credits](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/artistsong/index.md), [external resources](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/resource/index.md).

External-resource enum includes Spotify, YouTube Music, YouTube, Apple Music, Amazon Music and Official Website. This means the model can represent these links, **not** that every song has them or every linked upload is rights-holder verified. The song endpoint supports its resources; the anime endpoint's allowed nested includes do not explicitly list `animethemes.song.resources`, so use a supported song hydration request or verified GraphQL selection rather than assuming unlimited nested REST includes.

The GraphQL `findAnimeByExternalSite(site: ANILIST, id: [Int!])` accepts multiple external IDs without authentication; documentation explicitly allows **multiple anime per external resource**. Do not enforce a one-to-one crosswalk prematurely. REST has sparse fields, includes, pagination and updated/deleted filters. [Batch join example](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/graphql/examples/filter-by-external-site/index.md), [REST index](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/anime/index/index.md)

Both API styles document90 requests/min with remaining/reset/retry headers. GraphQL also documents depth13 and complexity10000, with complexity explicitly experimental. [REST quota](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/intro/ratelimiting/index.md), [GraphQL limits](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/graphql/intro/ratelimiting/index.md)

Video fields include creditless/subtitled/lyrics/uncensored distinctions, source format and whether visuals overlap episode content. Audio is described as the audio track of the theme video, not necessarily a full commercial recording. Neither the supplied URLs nor the repository's MIT software/documentation license establishes audiovisual rights, a commercial data-reuse grant or complete attribution requirements. Public API support contact is documented; exact intended cache/republication and playback terms remain unverified. Attribute factual metadata sources and preserve per-row provenance, but do not pretend attribution resolves missing rights. [Video](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/video/index.md), [Audio](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/docs/jsonapi/reference/content/audio/index.md), [license](https://github.com/AnimeThemes/animethemes-api-docs/blob/main/LICENSE)

Access: official repository docs fetched directly after documentation-host timeout. HEAD `f4ac78c1e0046a63bb4b3336e504e8bcafd56224`, dated10 Sep2026. One public metadata GET with includes returned403; no audio/video bytes requested. Confirm access, data terms and sample coverage before implementation.

### 3. MAL official API versus Jikan

The [MAL official v2 reference](https://myanimelist.net/apiconfig/references/api/v2) could not be opened in this environment. **Official theme-song availability was not independently verified here.** Do not conflate Jikan's fields with MAL's official API, and do not present an official-API absence as a fresh verified fact from this lane.

Jikan's own OpenAPI specifies `GET /anime/{id}/themes`: `data.openings` and `data.endings` are arrays of strings. This is useful fallback display text, not normalized artists, playable URLs, version IDs or validated episode ranges. Preserve source text; any parsing needs confidence and a raw fallback. [Official Jikan OpenAPI](https://github.com/jikan-me/jikan-rest/blob/master/storage/api-docs/api-docs.json), [theme response implementation](https://github.com/jikan-me/jikan-rest/blob/master/app/Http/Resources/V4/AnimeThemesResource.php)

Jikan states that it scrapes MAL, is unofficial/unaffiliated, and provides read-only GET data without authenticated list updates. Its documentation gives60/min and3/sec, upstream MAL may throttle too; requests are documented as cached24h, with ETag/If-None-Match/304 and cache headers. Respect these freshness limits rather than polling rapidly. Software is open source; the README explicitly directs users to respect MAL's terms. This is not a new grant to republish underlying MAL data commercially. [Jikan README](https://github.com/jikan-me/jikan-rest), [API documentation](https://docs.api.jikan.moe/)

Access: documentation HTML pointed to the directly fetched provider OpenAPI JSON; source HEAD `1e33a79bcc9161f1831e4428004e110c67a48676`, dated14 Jun2026. One sample `anime/1/themes` request returned504; no success or freshness claim. Dedicated Jikan terms page was inaccessible in the web tool; exact reuse terms remain to be checked before adoption.

### 4. MusicBrainz: identity and discography enrichment, optional

MusicBrainz can resolve artist, recording, work, release and release-group identities, ISRC/ISWC and URL relationships. This helps disambiguate a TV edit from a full recording or an artist from a similarly named performer. It is not a reliable general source for which song plays in which anime episode, and does not supply music streams. [API](https://musicbrainz.org/doc/MusicBrainz_API), [scope statement](https://musicbrainz.org/doc/Copyright_and_DMCA_Compliance)

Core metadata is CC0; supplementary data and live feed have different noncommercial/share-alike licensing. **Public API commercial access is a separate question:** documentation says free for noncommercial use and points commercial users to plans/contact. API requires a meaningful User-Agent and at most one call/second. Do not promise commercial MusicBrainz API use is free because core data is CC0. [Data license](https://musicbrainz.org/doc/About/Data_License), [rate limits](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting)

Access: direct docs initially429; official indexed full pages read. No music/API enrichment requests made. Do not introduce this dependency for the first OP/ED release unless unresolved identity needs justify it.

## Proposed minimal data model

This is a design proposal, not a migration request.

- `anime_music_source_map`: Kuro anime ID, provider, source anime ID/URL, external AniList/MAL ID, match method/confidence and review state. Allow multiple source rows per production and explicit ambiguity; use existing source IDs first, titles only as a fallback candidate search.
- `music_song`: Kuro song ID, source song IDs, original/display title, optional recording/work identifiers. Do not treat an AnimeThemes song ID as proof of one specific commercial recording.
- `music_credit`: song, artist source ID/display name, credited alias/character, role when explicitly supplied and credit order. Leave unknown composer/lyricist roles unknown; theme performance is not authorship.
- `anime_theme`: Kuro anime ID, song ID, OP/ED/other-known-role, sequence, source theme ID. Insert/OST roles need a different verified source; do not invent them from OP/ED data.
- `theme_version`: theme, source entry ID, version, `episodes_raw`, nullable normalized ranges/exceptions, parse confidence, spoiler/NSFW/notes. Preserve odd cases such as episode0, specials, decimals, comma sets and unknown coverage without forcing integers.
- `music_link`: song/version, provider, canonical destination URL, link kind (official song, artist, source reference, video, audio), verification method/date, availability/disabled state, rights status. Keep source-reference links separate from approved playback URLs.
- Shared provenance: source URL, fetched_at, source_updated_at when available, payload hash, parser version, last_success/error and deletion marker. Optional raw metadata snapshot only to the extent allowed by the source's terms; never copy media as part of this ingest.

## Efficient ingestion and serving

1. Build an authorized bounded pilot around active/current-season and frequently opened detail titles, not an indiscriminate whole-catalogue crawl. Prefer existing source IDs and batch matching. Review collisions between split cours, sequel seasons and film compilations.
2. Fetch only metadata required by the feature. Keep song/artist/entry hydration batched and deduplicated; cache negative matches with a shorter expiry for currently airing titles. A missing result means unknown/unmapped, not “this anime has no music.”
3. After initial permitted hydration, schedule current-season refreshes more often and finished titles less often. Use provider timestamps and supported updated/deleted filters with a small overlap and stable cursor. Do **not assume child-song or entry edits update the parent anime timestamp**; track child changes or periodically reconcile bounded hydrated titles. Retry transient failures with jitter, honor429/Retry-After, and pause on403 rather than switching endpoints to evade it.
4. For Jikan, use conditional ETags and documented cache freshness; one shared server scheduler enforces both second and minute quotas. For AnimeThemes, follow response quotas and GraphQL complexity limits. Neither provider's per-minute allowance is an endorsement of bulk collection.
5. Serve a compact music summary from Kuro's own permitted cache alongside the detail payload. Never issue live third-party requests per card or block title rendering on enrichment. Detail expansion can enqueue refresh and continue showing the last valid snapshot with an honest missing-state.
6. Deduplicate writes by provider ID and payload hash; keep old valid data through transient outages, track removals, and expose administrative mapping/provenance checks. Measure match coverage, ambiguous matches, usable music-link coverage and age, not just successful HTTP calls.

## Link-out versus playback decision

The narrowest useful version requires no in-app audio: users see credits and choose “Open in Spotify/Apple Music/official video” for an individually verified destination. This avoids treating a song catalogue as a playback service. It does not guarantee users can listen free or in their region; destination service/account rules apply. Do not invent links from title-only searches or label community-hosted media “official.”

If playback is requested, evaluate the chosen provider's authorized player/SDK separately. Spotify documents embeds for controlled websites under its developer terms; it is not blanket permission for a native custom player, background soundtrack, caching or full-track access. YouTube explicitly prohibits separating audio and hidden/background players. Do not use a YouTube video URL as an audio-only background music source. [Spotify embeds](https://developer.spotify.com/documentation/embeds), [Spotify widget terms](https://developer.spotify.com/documentation/embeds/terms), [YouTube developer policies](https://developers.google.com/youtube/terms/developer-policies)

Until the pending scope clarification is answered, recommend **OP/ED factual metadata plus official link-outs**, with episode coverage shown only when source-backed. Present OST/insert-song cataloguing and background playback as separate follow-ups with independent sourcing and rights work. Do not hide useful title details behind music loading or autoplay music on detail entry.
