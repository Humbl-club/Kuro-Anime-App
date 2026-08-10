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
  Pill,
  Row,
  Stack,
  Stat,
  Table,
  Text,
} from "cursor/canvas";

/**
 * Follow-up to canonical trilogy: deep schema cross-reference
 * Verified 2026-08-10 against live table-stats + migration CREATE inventory + iOS .rpc() call sites
 */

export default function KuroSchemaCrossref() {
  return (
    <Stack gap={28} style={{ padding: 28, maxWidth: 1080 }}>
      <Stack gap={10}>
        <Text
          size="small"
          tone="tertiary"
          weight="medium"
          style={{ letterSpacing: 1.4, textTransform: "uppercase" }}
        >
          Kuro follow-up · Schema cross-reference · 2026-08-10
        </Text>
        <H1>Schema ↔ maps audit</H1>
        <Text tone="secondary" style={{ maxWidth: 720, lineHeight: 1.55 }}>
          Every client RPC, map-claimed table, and RLS enablement checked against live DB
          table-stats and migration CREATE inventory. Flags mismatches the trilogy under- or
          over-claimed.
        </Text>
        <Row gap={8} wrap>
          <Pill tone="success" size="sm" active>
            Present
          </Pill>
          <Pill tone="warning" size="sm" active>
            Type nuance
          </Pill>
          <Pill tone="deleted" size="sm" active>
            Gap
          </Pill>
          <Pill tone="info" size="sm" active>
            Unmentioned live
          </Pill>
        </Row>
      </Stack>

      <Grid columns={4} gap={12}>
        <Stat value="108" label="Live tables (stats)" tone="info" />
        <Stat value="49/49" label="Client RPCs in migrations" tone="success" />
        <Stat value="3" label="Map type nuances" tone="warning" />
        <Stat value="33" label="Live tables maps omitted" />
      </Grid>

      <Callout tone="success" title="Client RPC surface is clean">
        All 49 SupabaseService `.rpc(...)` names resolve to `CREATE FUNCTION` in migrations
        (including `shares_club_with`). No phantom client RPCs.
      </Callout>

      <H2>1. Map-claimed relations — type corrections</H2>
      <Table
        headers={["Name", "Maps said", "Live truth", "Action"]}
        rows={[
          [
            "media_realm_membership",
            "Table",
            "MATERIALIZED VIEW (migrations)",
            "Maps should say matview; not in table-stats as heap table",
          ],
          [
            "media_realm_llm_pending",
            "Table",
            "VIEW (ops queue)",
            "Not a table; security_invoker view for descriptor workers",
          ],
          [
            "media_realm_tier",
            "Often implied as matview",
            "MATERIALIZED VIEW (migrations)",
            "Maps should say matview; listed in table-stats after refresh",
          ],
          [
            "anime_comments / manga_comments",
            "Legacy / non-product",
            "LIVE tables exist",
            "Correct: product path is title_comments",
          ],
          [
            "club_messages",
            "Schema retained / chat dead",
            "LIVE table",
            "Correct",
          ],
        ]}
      />

      <H2>2. Live tables the trilogy under-mentioned (ops / realm / critique)</H2>
      <Text size="small" tone="secondary">
        Present in live DB; not first-class in Maps 1–3. Mostly ops, realm graph, critique, RAG
        index, taste math internals.
      </Text>
      <CollapsibleSection title="33 unmentioned live tables" defaultOpen>
        <Table
          headers={["Table", "Likely domain", "Should maps care?"]}
          rows={[
            ["media_franchise_components / entry_points / franchise_component_cut", "Ladder / franchise", "Yes — Adaptation Path internals"],
            ["media_relation_refresh_queue", "Ladder ops", "Yes — enqueue_media_relation_refresh"],
            ["media_similar_titles / media_similar_seed_state / media_rec_edges", "Recs precompute", "Yes — More Like This / recommend"],
            ["media_realm_membership_delta / media_realm_tier / realm_*", "Realm graph", "Yes — Shelf/Gem prerequisites"],
            ["canon_seed / curation_seasonal_signal", "Curation", "Ops/editorial"],
            ["critic_reviews / critic_sources / media_critic_claims / media_craft_scores", "Critique ingestion", "Ops — realm quality"],
            ["taste_tag_stats / taste_import_context", "Taste math", "Yes — profile recompute"],
            ["title_search", "Search index", "Yes — search RPCs"],
            ["provider_source_map / provider_availability_refresh_state", "Streaming ops", "Staged product"],
            ["rag_entity_index / aliases / tags", "RAG", "Dead wire from iOS"],
            ["concierge_config / parse_feedback / mode_analytics / runs", "Concierge ops", "Yes — rate limits/budgets"],
            ["llm_global_daily_usage", "LLM budgets", "Ops"],
            ["club_analytics", "Clubs ops", "Retention/analytics"],
            ["editorial_penalty_tags / media_content_notes / verdict_voice", "Editorial", "Optional"],
            ["catalog_safety_* (mentioned partially)", "Safety pipeline", "Ops maps"],
          ]}
        />
      </CollapsibleSection>

      <H2>3. Materialized views (migrations) — Discover/rails fuel</H2>
      <Table
        headers={["Matview", "Role"]}
        rows={[
          ["mv_anime_trending / mv_manga_trending", "Trending rails"],
          ["mv_anime_top_rated / mv_manga_top_rated", "Top rated"],
          ["mv_anime_newly_added / mv_manga_newly_added", "Just added"],
          ["mv_anime_current_season", "Seasonal"],
          ["media_tag_vectors", "Taste / similarity math"],
          ["media_realm_membership / realm_affinity", "Realm graph"],
          ["media_realm_tier", "Realm tiering"],
        ]}
      />

      <H2>4. RLS snapshot (migration inventory)</H2>
      <Grid columns={2} gap={12}>
        <Card>
          <CardHeader>Coverage</CardHeader>
          <CardBody>
            <Stack gap={4}>
              <Text size="small">~108 tables with ENABLE ROW LEVEL SECURITY in migrations</Text>
              <Text size="small">~121 create policy bindings parsed from migration history</Text>
              <Text size="small">False positives in parse: IF / hands / media_realm_tier_next</Text>
            </Stack>
          </CardBody>
        </Card>
        <Card>
          <CardHeader>Policy note</CardHeader>
          <CardBody>
            <Text size="small">
              Full live policy dump needs service-role SQL (`pg_policies`). Migration inventory
              shows RLS is the norm; ops views (e.g. media_realm_llm_pending) use revoke/grant
              instead of anon-open RLS.
            </Text>
          </CardBody>
        </Card>
      </Grid>

      <H2>5. Client RPC checklist (all present)</H2>
      <CollapsibleSection title="49 iOS .rpc names — all found in migrations">
        <Text size="small">
          Auth: check_email_exists · Discover: discover_bundle, fetch_daily_feature,
          fetch_because_you_rail, fetch_tonight_shelf, fetch_realm_hidden_gem · Search/Browse:
          search_*_page, browse_*_page · Collection: collection_*_page · Taste:
          fetch_taste_deck_batch, record_taste_deck_signal, fetch_my_taste_profile,
          fetch_personalized_new_to_you · Clubs: fetch_my_clubs_*, create/join/leave_club,
          fetch_club_bundle*, add_club_rail_item, create_club_rail/poll, cast_club_vote,
          toggle_club_reaction, check_club_activity_since, send/fetch_club_messages · Ladder:
          get_media_ladder, enqueue_media_relation_refresh · Social: friend activity + comments +
          reactions + counts · Streaming: batch_provider_*, enqueue/get availability,
          save_user_streaming_services, club_shared_providers · Misc:
          recommend_ids_similar_to_seeds, get_manga_chapter_status, record_outbound_link
        </Text>
      </CollapsibleSection>

      <Callout tone="warning" title="Migration follow-up shipped in repo">
        `20260810120000_clubs_trust_flags_promote_100.sql` UPDATEs clubs_realtime_v1,
        clubs_pace_sync_v1, clubs_notifications_v1 to enabled=true, rollout 100%, markets * — so
        history matches live DB (previously only raised out-of-band).
      </Callout>

      <Divider />
      <Text size="small" tone="secondary">
        Sources: supabase inspect db table-stats --linked · migration CREATE FUNCTION/TABLE/POLICY
        parse · Kuro Services *.rpc() · Maps 1–3 claims. Sister: kuro-ecosystem-flows.canvas.tsx
      </Text>
    </Stack>
  );
}
