import {
  Callout,
  Card,
  CardBody,
  CardHeader,
  Divider,
  Grid,
  H1,
  H2,
  Pill,
  Row,
  Stack,
  Stat,
  Table,
  Text,
} from "cursor/canvas";

/**
 * Combinatorial / ecosystem map — how Kuro capabilities compose
 */

export default function KuroEcosystemFlows() {
  return (
    <Stack gap={28} style={{ padding: 28, maxWidth: 1080 }}>
      <Stack gap={10}>
        <Text
          size="small"
          tone="tertiary"
          weight="medium"
          style={{ letterSpacing: 1.4, textTransform: "uppercase" }}
        >
          Kuro follow-up · Combinatorial map · 2026-08-10
        </Text>
        <H1>How capabilities combine</H1>
        <Text tone="secondary" style={{ maxWidth: 720, lineHeight: 1.55 }}>
          Not a feature list — composition paths. Solid = live wires. Dashed labels = staged /
          dark / dead.
        </Text>
      </Stack>

      <Grid columns={3} gap={12}>
        <Stat value="5" label="Pager pages (taste on)" tone="info" />
        <Stat value="2" label="Sheets (Concierge / Search)" />
        <Stat value="3" label="Dark personalization paths" tone="warning" />
      </Grid>

      <H2>1. Primary taste → discovery → ownership → social loop</H2>
      <Card>
        <CardHeader trailing={<Pill tone="success" size="sm" active>Live</Pill>}>
          Core loop
        </CardHeader>
        <CardBody>
          <Stack gap={10}>
            <Text weight="medium" style={{ lineHeight: 1.5 }}>
              Taste Deck signals → taste profile / tag stats → Discover editorial rails (default) +
              Collection ownership → Club rails / polls → Social title comments (friends who share a
              club)
            </Text>
            <Table
              headers={["Hop", "Surface", "Wire"]}
              rows={[
                ["1", "Taste (pager 0)", "fetch_taste_deck_batch / record_taste_deck_signal"],
                ["2", "Profile math", "taste_tag_stats + fetch_my_taste_profile"],
                ["3", "Discover", "discover_bundle (+ NTY rotation server-side)"],
                ["4", "Collection", "anime/manga_user_lists + collection_*_page"],
                ["5", "Clubs", "club_rails + reactions + pace + realtime"],
                ["6", "Social", "title_comments via shares_club_with()"],
              ]}
            />
            <Callout tone="warning" title="Not wired yet (flags 0%)">
              Taste → Because You / Personalized NTY / Tonight Shelf / Realm Hidden Gem stay dark
              (`personalized_new_to_you_v1`, `discover_realm_rails_v1`). Signals accumulate; UI paths
              do not consume them for those rails until rollout.
            </Callout>
          </Stack>
        </CardBody>
      </Card>

      <H2>2. Combinatorial matrix (capability × capability)</H2>
      <Table
        headers={["From \\ To", "Discover", "Collection", "Clubs", "Social", "Concierge"]}
        rows={[
          [
            "Taste",
            "Dark: Because You / NTY personalization",
            "Indirect (list later)",
            "No direct",
            "No direct",
            "No direct",
          ],
          [
            "Discover",
            "—",
            "Add to list from cards",
            "Add to Club… context menu",
            "Friend count badges",
            "Open sheet / deep link",
          ],
          [
            "Browse / Search",
            "Editorial vs catalog",
            "Add / filter ownership",
            "Add to Club…",
            "Friend counts",
            "Import / vibe prompts",
          ],
          [
            "Collection",
            "Seen-set for NTY",
            "—",
            "Pace sync source",
            "Tracking counts",
            "Import apply target",
          ],
          [
            "Clubs",
            "No",
            "Pace reads lists",
            "Realtime / polls / rails",
            "Friend graph via membership",
            "No",
          ],
          [
            "Streaming (0%)",
            "Where-to-watch filters dark",
            "No",
            "club_shared_providers dark",
            "No",
            "No",
          ],
        ]}
      />

      <H2>3. Data-flow diagram (textual)</H2>
      <Card>
        <CardBody>
          <Stack gap={6}>
            <Text size="small" style={{ fontFamily: "monospace", lineHeight: 1.7 }}>
              AniList ──bulk-import──▶ anime/manga catalog ──matviews──▶ Discover rails
            </Text>
            <Text size="small" style={{ fontFamily: "monospace", lineHeight: 1.7 }}>
              User ──Taste signals──▶ taste_tag_stats ─┬─▶ (dark) personalized rails
            </Text>
            <Text size="small" style={{ fontFamily: "monospace", lineHeight: 1.7 }}>
              {"                              └─▶ profile cards / future recs"}
            </Text>
            <Text size="small" style={{ fontFamily: "monospace", lineHeight: 1.7 }}>
              User lists ◀──Concierge apply── import_sessions / AniList import
            </Text>
            <Text size="small" style={{ fontFamily: "monospace", lineHeight: 1.7 }}>
              User lists ──pace──▶ club pace banners · milestones
            </Text>
            <Text size="small" style={{ fontFamily: "monospace", lineHeight: 1.7 }}>
              club_members ──shares_club_with──▶ title_comments + reactions
            </Text>
            <Text size="small" style={{ fontFamily: "monospace", lineHeight: 1.7 }}>
              Media ladder ◀──get_media_ladder── adaptation path on detail
            </Text>
            <Text size="small" style={{ fontFamily: "monospace", lineHeight: 1.7 }}>
              MangaDex ──manga-chapter-enrich──▶ chapters (not AniList chapters)
            </Text>
          </Stack>
        </CardBody>
      </Card>

      <H2>4. Flag-gated composition edges</H2>
      <Table
        headers={["Edge", "Flag", "Live %", "Effect when off"]}
        rows={[
          ["Pager includes Taste", "taste_deck_v1", "100", "4-page pager, Concierge as page 0"],
          ["Club live refresh", "clubs_realtime_v1", "100", "Manual refresh only"],
          ["Pace banners", "clubs_pace_sync_v1", "100", "No behind/milestone UI"],
          ["Club badges", "clubs_notifications_v1", "100", "No unread dots"],
          ["Social activity", "social_activity_v1", "100", "No comments/friend counts"],
          ["Credits/cast", "credits_cast_v1", "100", "Sections hidden"],
          ["Streaming UI", "streaming_availability_v1", "0", "Provider filters/notes hidden"],
          ["Realm Shelf/Gem", "discover_realm_rails_v1", "0", "Rails not mounted"],
          ["Personalized NTY", "personalized_new_to_you_v1", "0", "Server NTY rotation only"],
          ["Club chat", "clubs_chat_v1", "off", "Messages schema retained, UI gone"],
          ["RAG assist", "rag_assist_v1", "5% DE/AT/CH", "iOS never calls retrieve-assist"],
        ]}
      />

      <H2>5. Highest-leverage closed loops (product)</H2>
      <Grid columns={2} gap={12}>
        <Card>
          <CardHeader>Working today</CardHeader>
          <CardBody>
            <Stack gap={4}>
              <Text size="small">Browse/Search → Collection → Club rail → reactions</Text>
              <Text size="small">Collection progress → Club pace sync</Text>
              <Text size="small">Shared club → Social comments on title</Text>
              <Text size="small">Concierge import → Collection → Discover seen-set</Text>
              <Text size="small">Detail ladder → related titles → list/club add</Text>
            </Stack>
          </CardBody>
        </Card>
        <Card>
          <CardHeader>Designed but dark</CardHeader>
          <CardBody>
            <Stack gap={4}>
              <Text size="small">Taste → Because You / personalized NTY</Text>
              <Text size="small">Realm affinity → Shelf + Hidden Gem</Text>
              <Text size="small">Provider availability → Browse/club filters</Text>
              <Text size="small">RAG entities → Concierge retrieve assist</Text>
            </Stack>
          </CardBody>
        </Card>
      </Grid>

      <Divider />
      <Text size="small" tone="secondary">
        Sister canvases: kuro-reconciled-truth-map · kuro-functionality-map · kuro-user-journeys ·
        kuro-schema-crossref
      </Text>
    </Stack>
  );
}
