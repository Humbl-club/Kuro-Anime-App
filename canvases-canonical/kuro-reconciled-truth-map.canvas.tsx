import {
  Callout,
  Card,
  CardBody,
  CardHeader,
  CollapsibleSection,
  Divider,
  Grid,
  H1,
  H2,
  H3,
  Pill,
  Row,
  Stack,
  Stat,
  Table,
  Text,
  useHostTheme,
} from "cursor/canvas";

/**
 * KURO CANONICAL MAP 1/3 — System Truth & Sources
 * Sister maps:
 *   2) kuro-functionality-map.canvas.tsx — Capability Inventory
 *   3) kuro-user-journeys.canvas.tsx — User Journeys (+ non-happy)
 * Last verified against live Supabase + Swift: 2026-08-09
 */

type Take = "take" | "partial" | "discard" | "skip" | "option";

function TakePill({ t }: { t: Take }) {
  const m: Record<Take, { tone: "success" | "warning" | "neutral" | "deleted" | "info"; label: string }> = {
    take: { tone: "success", label: "Taking" },
    partial: { tone: "warning", label: "Partial" },
    discard: { tone: "neutral", label: "Fetched · not stored" },
    skip: { tone: "deleted", label: "Not taking" },
    option: { tone: "info", label: "Could take" },
  };
  return (
    <Pill tone={m[t].tone} size="sm" active>
      {m[t].label}
    </Pill>
  );
}

function Field(field: string, t: Take, notes: string) {
  return [field, <TakePill t={t} />, notes];
}

function Verdict({ v }: { v: "true" | "false" | "partial" }) {
  const m = {
    true: { tone: "success" as const, label: "TRUE" },
    false: { tone: "deleted" as const, label: "FALSE" },
    partial: { tone: "warning" as const, label: "PARTIAL" },
  };
  return (
    <Pill tone={m[v].tone} size="sm" active>
      {m[v].label}
    </Pill>
  );
}

function TrilogyNav() {
  return (
    <Card>
      <CardBody>
        <Stack gap={8}>
          <Text size="small" weight="medium">
            Canonical trilogy — read in order for a new LLM session
          </Text>
          <Row gap={8} wrap>
            <Pill tone="info" size="sm" active>
              1/3 System Truth ← you are here
            </Pill>
            <Pill tone="neutral" size="sm">
              2/3 Capability Inventory
            </Pill>
            <Pill tone="neutral" size="sm">
              3/3 User Journeys
            </Pill>
          </Row>
          <Text size="small" tone="secondary">
            Files: kuro-reconciled-truth-map · kuro-functionality-map · kuro-user-journeys (same
            canvases/ folder)
          </Text>
        </Stack>
      </CardBody>
    </Card>
  );
}

export default function KuroMap1SystemTruth() {
  const theme = useHostTheme();

  return (
    <Stack gap={28} style={{ padding: 28, maxWidth: 1080 }}>
      <Stack gap={10}>
        <Text
          size="small"
          tone="tertiary"
          weight="medium"
          style={{ letterSpacing: 1.4, textTransform: "uppercase" }}
        >
          Kuro canonical · Map 1 of 3 · Verified 2026-08-09
        </Text>
        <H1>System Truth & Sources</H1>
        <Text tone="secondary" style={{ maxWidth: 720, lineHeight: 1.55 }}>
          What is actually true in production right now: live flags, deployed edges, external
          dependencies, AniList take/skip map, and corrections to overstated audits. Use this before
          trusting any “Production ✅” claim in older docs.
        </Text>
        <Row gap={8} wrap>
          <Pill tone="success" size="sm" active>
            LIVE
          </Pill>
          <Pill tone="warning" size="sm" active>
            STAGED 0%
          </Pill>
          <Pill tone="info" size="sm" active>
            CANARY
          </Pill>
          <Pill tone="deleted" size="sm" active>
            FALSE / DEAD
          </Pill>
        </Row>
      </Stack>

      <TrilogyNav />

      <Callout tone="info" title="For the next LLM">
        Project: Kuro — curated anime + manga iOS app (SwiftUI @Observable, Supabase). Repo:
        /Users/max/Kuro-Anime-App. Project ref: bkdifromsqxkndnllmdj. Light mode only. Do not invent
        flags or pager pages — re-query feature_flags if rollout matters. After this map, read Map
        2 (capabilities) then Map 3 (journeys).
      </Callout>

      <Grid columns={5} gap={12}>
        <Stat value="5" label="Live pager pages" tone="success" />
        <Stat value="20" label="DB feature flags" />
        <Stat value="16" label="Edge functions ACTIVE" />
        <Stat value="234" label="Migration files" />
        <Stat value="93" label="Swift app files" />
      </Grid>

      {/* ── PRODUCT SHAPE ── */}
      <H2>1. Live product shape</H2>
      <Row gap={6} wrap align="center">
        {["Taste", "Discover", "Browse", "Collection", "Clubs"].map((p, i) => (
          <>
            {i > 0 ? (
              <Text tone="tertiary" size="small">
                →
              </Text>
            ) : null}
            <Pill size="sm" active tone={p === "Discover" ? "success" : "neutral"}>
              {p}
            </Pill>
          </>
        ))}
        <Text tone="tertiary" size="small">
          +
        </Text>
        <Pill size="sm" tone="warning" active>
          Concierge sheet
        </Pill>
        <Pill size="sm" tone="warning" active>
          Search sheet
        </Pill>
      </Row>
      <Text size="small" tone="secondary">
        Default launch page = Discover. taste_deck_v1 = 100% → Concierge is NOT a pager page. Flag
        off restores legacy Concierge at index 0 (rollback path in ContentView.swipeOrder).
      </Text>

      <Grid columns={2} gap={12}>
        <Card>
          <CardHeader>Stack (exact)</CardHeader>
          <CardBody>
            <Stack gap={4}>
              <Text size="small">iOS SwiftUI · @Observable (no Combine)</Text>
              <Text size="small">Supabase: Postgres + Edge (Deno) + Auth + Storage + Realtime + RPC/RLS</Text>
              <Text size="small">On-device AI: Apple Foundation Models (iOS 26+)</Text>
              <Text size="small">Cloud LLM: Groq (narration / resolve / realm-describe)</Text>
              <Text size="small">Catalog: AniList · Chapters: MangaDex · Providers ops: Watchmode</Text>
            </Stack>
          </CardBody>
        </Card>
        <Card>
          <CardHeader>Verification method (do this again)</CardHeader>
          <CardBody>
            <Stack gap={4}>
              <Text size="small">GET /rest/v1/feature_flags (anon key)</Text>
              <Text size="small">supabase functions list --project-ref bkdifromsqxkndnllmdj</Text>
              <Text size="small">supabase migration list --linked</Text>
              <Text size="small">Read ContentView.swipeOrder + FeatureFlags.swift</Text>
              <Text size="small">Read bulk-import-* GraphQL for AniList truth</Text>
            </Stack>
          </CardBody>
        </Card>
      </Grid>

      {/* ── FLAGS ── */}
      <H2>2. Live feature flags (authoritative)</H2>
      <Text size="small" tone="secondary">
        Queried live 2026-08-09. Swift exposes 18 accessors; DB has 20 rows (affiliate_links_v1 +
        clubs_chat_v1 have no Swift accessors). Missing flag → false.
      </Text>
      <Table
        headers={["Flag", "En", "%", "Markets", "User impact today"]}
        rows={[
          ["taste_deck_v1", "T", "100", "—", "LIVE — Taste @0; Concierge sheet"],
          ["swipe_tap_guard_v1", "T", "100", "—", "LIVE"],
          ["social_activity_v1", "T", "100", "*", "LIVE — friends/comments"],
          ["credits_cast_v1", "T", "100", "—", "LIVE"],
          ["clubs_reactions_v1", "T", "100", "*", "LIVE"],
          ["clubs_list_enriched_v1", "T", "100", "*", "LIVE path always attempted"],
          ["clubs_realtime_v1", "T", "100", "*", "LIVE — claimed live DB 100%"],
          ["clubs_pace_sync_v1", "T", "100", "*", "LIVE — claimed live DB 100%"],
          ["clubs_notifications_v1", "T", "100", "*", "LIVE — claimed live DB 100%"],
          ["streaming_availability_v1", "T", "0", "—", "STAGED — UI off"],
          ["personalized_new_to_you_v1", "T", "0", "—", "STAGED"],
          ["discover_realm_rails_v1", "T", "0", "—", "STAGED Shelf/Gem"],
          ["fm_assist_v1", "T", "5", "DE/AT/CH", "Canary"],
          ["clarify_v2", "T", "5", "DE/AT/CH", "Canary"],
          ["rag_assist_v1", "T", "5", "DE/AT/CH", "Canary flag; iOS never invokes assist"],
          ["clubs_interaction_v2", "F", "0", "—", "OFF"],
          ["concierge_editorial_v1", "F", "0", "—", "OFF (client hardcodes editorial)"],
          ["concierge_perf_v2", "F", "0", "—", "OFF"],
          ["affiliate_links_v1", "F", "0", "*", "OFF — no Swift accessor"],
          ["clubs_chat_v1", "F", "100*", "*", "OFF — chat dead; % irrelevant"],
        ]}
      />

      <Callout tone="warning" title="Migration vs live DB discrepancy — verify before trusting">
        Migration <code>20260731040000_clubs_trust_pack_v1.sql</code> inserts clubs_realtime_v1,
        clubs_pace_sync_v1, and clubs_notifications_v1 at <strong>0%</strong> with ON CONFLICT DO
        NOTHING. No subsequent migration UPDATEs them to 100%. The 100% claim above is from a
        manual live DB query (2026-08-09) and is <strong>not reproducible from migrations alone</strong>.
        On a fresh replay these flags stay at 0%. If you need canonical ground truth, query the
        live feature_flags table — do not trust migrations for these three flags.
      </Callout>

      {/* ── EDGES ── */}
      <H2>3. Deployed edge functions (16 ACTIVE)</H2>
      <Table
        headers={["Function", "Auth", "External", "iOS?", "Role"]}
        rows={[
          ["concierge-parse", "JWT", "—", "Yes", "List NLP parse"],
          ["concierge-apply", "JWT", "—", "Yes", "Write lists"],
          ["concierge-undo", "JWT", "—", "Yes", "Rollback session"],
          ["concierge-recommend", "JWT", "Groq narrate optional", "Yes", "Deterministic rails"],
          ["concierge-import-anilist", "JWT", "AniList", "Yes", "Public list → parse text"],
          ["concierge-retrieve-feedback", "JWT", "—", "Best-effort", "RAG feedback"],
          ["concierge-resolve", "JWT", "Groq", "No", "Deployed; unused by iOS"],
          ["concierge-retrieve-assist", "JWT", "—", "No", "RAG; unused by iOS"],
          ["delete-account", "JWT", "Apple revoke", "Yes", "GDPR"],
          ["auth-callback", "Public", "Google Fonts", "Browser", "Email HTML fallback"],
          ["bulk-import-anime", "IMPORT_SECRET", "AniList", "Cron", "Catalog"],
          ["bulk-import-manga", "IMPORT_SECRET", "AniList", "Cron", "Catalog"],
          ["mirror-images", "IMPORT_SECRET", "AniList URLs", "Cron", "CDN media bucket"],
          ["manga-chapter-enrich", "IMPORT_SECRET", "MangaDex", "Cron", "Chapters"],
          ["manga-source-review-action", "IMPORT_SECRET", "—", "Ops", "Mapping review"],
          ["realm-describe", "IMPORT_SECRET", "Groq", "Cron/ops", "Realm descriptors"],
        ]}
      />

      {/* ── ANILIST ── */}
      <Divider />
      <H2>4. AniList source import map</H2>
      <Text tone="secondary" style={{ maxWidth: 720, lineHeight: 1.5 }}>
        Canonical upstream: GraphQL https://graphql.anilist.co. Three Kuro entry points. Field
        surface checked against AniList Media reference + live query strings in
        supabase/functions/bulk-import-* and concierge-import-anilist.
      </Text>

      <Grid columns={3} gap={12}>
        <Card>
          <CardHeader trailing={<Pill tone="success" size="sm" active>Ops</Pill>}>
            bulk-import-anime
          </CardHeader>
          <CardBody>
            <Text size="small">
              Page(POPULARITY_DESC, ANIME) → anime upsert + optional relations/episodes +
              externalLinks. Images CDN-mirrored later.
            </Text>
          </CardBody>
        </Card>
        <Card>
          <CardHeader trailing={<Pill tone="success" size="sm" active>Ops</Pill>}>
            bulk-import-manga
          </CardHeader>
          <CardBody>
            <Text size="small">
              Same for MANGA. Chapter/volume rows mostly placeholders from counts; real chapters
              from MangaDex enrich.
            </Text>
          </CardBody>
        </Card>
        <Card>
          <CardHeader trailing={<Pill tone="info" size="sm" active>User</Pill>}>
            concierge-import-anilist
          </CardHeader>
          <CardBody>
            <Text size="small">
              Public MediaList by username → status/progress/score + thin media stub → text for
              parse. Not a catalog refresh.
            </Text>
          </CardBody>
        </Card>
      </Grid>

      <H3>Taking (catalog)</H3>
      <Table
        headers={["AniList field", "Status", "Kuro use"]}
        rows={[
          Field("id → anilist_id", "take", "Upsert key"),
          Field("idMal → mal_id", "take", "External identity"),
          Field("title.romaji/english/native", "take", "UI titles"),
          Field("synonyms", "take", "Search/match"),
          Field("coverImage.large/medium/color", "take", "Posters → CDN mirror"),
          Field("bannerImage", "take", "Detail heroes"),
          Field("format/status/type", "take", "Filters/badges"),
          Field("description(asHtml:false)", "take", "Raw synopsis (+ enhance pipeline)"),
          Field("source/countryOfOrigin/isAdult", "take", "Origin + adult filter"),
          Field("startDate/endDate", "take", "Y/M/D columns"),
          Field("episodes/duration (+ derived)", "take", "Length; airing derive"),
          Field("season/seasonYear", "take", "Seasonal rails"),
          Field("nextAiringEpisode.episode/airingAt", "take", "Airing Today / Next Up"),
          Field("chapters/volumes counts", "take", "Manga totals + placeholders"),
          Field("averageScore/meanScore/popularity/trending/favourites", "take", "Sort/rails"),
          Field("genres[]", "take", "Browse/cards"),
          Field("siteUrl/updatedAt", "take", "Link + stale sync"),
          Field("externalLinks{site,url,language,color}", "take", "Watch/read outbound"),
          Field("streamingEpisodes{...}", "partial", "Anime when includeEpisodes; numbers parsed from titles"),
          Field("relations v2 + node stub", "take", "media_relations → Adaptation Path"),
          Field("studios (anime)", "take", "studios + join"),
          Field("tags + rank", "take", "tags + joins"),
          Field("characters(ROLE, perPage:10)", "partial", "Top ~10 mains"),
          Field("staff(RELEVANCE, perPage:10)", "partial", "Top ~10; manga→authors too"),
        ]}
      />

      <H3>User-list import (thin)</H3>
      <Table
        headers={["Field", "Status", "Notes"]}
        rows={[
          Field("MediaList.status/progress/score(POINT_10)/updatedAt", "take", "→ Concierge parse text"),
          Field("media.id/titles/format/year", "partial", "Identity stub only"),
          Field("notes/startedAt/completedAt/repeat/custom lists", "skip", "Not requested"),
        ]}
      />

      <H3>Fetched but not stored</H3>
      <Table
        headers={["Field", "Status", "Notes"]}
        rows={[
          Field("title.userPreferred", "discard", "Queried; never written"),
          Field("hashtag", "discard", "Queried; no write"),
          Field("coverImage.extraLarge", "discard", "Queried; only large/medium/color stored"),
          Field("nextAiringEpisode.timeUntilAiring", "discard", "We store absolute airingAt"),
        ]}
      />

      <H3>Not taking (on AniList Media)</H3>
      <Table
        headers={["Field", "Status", "What it is"]}
        rows={[
          Field("trailer", "skip", "YT/Dailymotion trailer ids"),
          Field("isLicensed", "skip", "License vs doujin"),
          Field("airingSchedule (full)", "skip", "Full schedule graph"),
          Field("rankings[]", "skip", "Seasonal/all-time ranks"),
          Field("trends / stats histograms", "skip", "Community distributions"),
          Field("recommendations / reviews", "skip", "AniList social editorial"),
          Field("voiceActors + characters beyond p1", "skip", "10-cap; no VA edges"),
          Field("Character bloodType/birthday/…", "skip", "Not in query"),
          Field("mediaListEntry / isFavourite", "skip", "Needs AniList OAuth"),
          Field("modNotes / lock flags", "skip", "Edge cases"),
        ]}
      />

      <H3>Could take (options, not commitments)</H3>
      <Table
        headers={["Option", "Effort", "Why nice"]}
        rows={[
          ["trailer", "Low", "In-app Watch trailer"],
          ["rankings", "Low", "“#3 Seasonal” badges"],
          ["stats distributions", "Med", "Detail/Taste social proof"],
          ["airingSchedule", "Med", "Richer calendars"],
          ["voiceActors + more cast pages", "Med", "Cast depth / VA rails"],
          ["isLicensed", "Low", "Filter doujin noise"],
          ["AniList recommendations", "Med", "Extra similar signal"],
          ["Store extraLarge + userPreferred", "Low", "Already fetched"],
          ["Richer MediaList import fields", "Med", "Import fidelity"],
          ["AniList OAuth private lists", "High", "Private sync — privacy cost"],
        ]}
      />

      <Callout tone="warning" title="Chapter / episode nuance">
        Manga chapter substance ≈ MangaDex, not AniList. AniList streamingEpisodes are legal-link
        oriented and often incomplete as an episode bible.
      </Callout>

      {/* ── EXTERNALS ── */}
      <H2>5. External integrations</H2>
      <Table
        headers={["Service", "Role", "Risk"]}
        rows={[
          ["Supabase", "DB/Auth/Storage/Edge/Realtime", "Core dependency"],
          ["AniList", "Catalog + user list import + images", "Schema drift medium"],
          ["MangaDex", "Chapter enrich", "RPS capped"],
          ["Groq", "Narrate / resolve / realm-describe", "429; fallback still Groq"],
          ["Apple Sign-In", "Identity + revoke on delete", "Standard"],
          ["Watchmode", "Local provider worker only", "Not in iOS; needs API key"],
          ["IAP / Ads / Firebase / PostHog", "Absent", "Zero revenue; ConciergeAnalytics→concierge_events only"],
        ]}
      />
      <Callout tone="danger" title="Highest ops risk">
        IMPORT_SECRET compromise allows arbitrary catalog writes via cron-callable edges. Env-only;
        rotate if logs leak.
      </Callout>

      {/* ── AUDIT FIXES ── */}
      <CollapsibleSection title="6. Audit claim corrections (do not re-introduce)" defaultOpen>
        <Table
          headers={["Claim", "Verdict", "Truth"]}
          rows={[
            ["6 pager pages / Concierge page", <Verdict v="false" />, "5 pages; Concierge sheet"],
            ["Taste Like/Dislike/Superlike / 10 cards", <Verdict v="false" />, "3 judgments · batch 12"],
            ["Streaming/BecauseYou/Shelf/GenreHub Production", <Verdict v="false" />, "0% or unwired"],
            ["Club chat Production", <Verdict v="false" />, "clubs_chat_v1 off"],
            ["Clubs realtime/pace/notif still 0%", <Verdict v="partial" />, "Migration inserts 0%; live DB shows 100% but no UPDATE migration — verify with live query"],
            ["Social = anime_comments", <Verdict v="partial" />, "Product uses title_comments"],
            ["No analytics at all", <Verdict v="partial" />, "concierge_events exists"],
            ["16 edges · 93 Swift · no IAP", <Verdict v="true" />, "Confirmed"],
          ]}
        />
      </CollapsibleSection>

      <Divider />
      <H2>Sources</H2>
      <Table
        headers={["Source", "Used for"]}
        rows={[
          ["Live feature_flags + functions list + table-stats", "Production truth"],
          ["bulk-import-* / concierge-import-anilist", "AniList take/skip"],
          ["docs.anilist.co Media reference", "Could-take field surface"],
          ["Kuro Swift (ContentView, FeatureFlags, …)", "Client truth"],
          ["Downloads audits (4 MD)", "Schema hints — corrected in §6"],
        ]}
      />
      <Text size="small" tone="tertiary" style={{ color: theme.text.tertiary }}>
        Next: Map 2/3 Capability Inventory (kuro-functionality-map.canvas.tsx) → Map 3/3 User
        Journeys (kuro-user-journeys.canvas.tsx)
      </Text>
    </Stack>
  );
}
