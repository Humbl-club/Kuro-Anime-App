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
 * KURO CANONICAL MAP 2/3 — Capability Inventory
 * Sister maps:
 *   1) kuro-reconciled-truth-map.canvas.tsx — System Truth & Sources
 *   3) kuro-user-journeys.canvas.tsx — User Journeys (+ non-happy)
 * Code-backed from Kuro/*.swift + SupabaseService+* · 2026-08-09
 */

type Status = "live" | "staged" | "gated" | "dead" | "ops" | "canary";

function S({ status, label }: { status: Status; label?: string }) {
  const map: Record<Status, { tone: "success" | "warning" | "deleted" | "info" | "neutral"; text: string }> = {
    live: { tone: "success", text: "Live" },
    staged: { tone: "warning", text: "Staged 0%" },
    gated: { tone: "warning", text: "Flag-gated" },
    dead: { tone: "deleted", text: "Dead / unwired" },
    ops: { tone: "info", text: "Ops" },
    canary: { tone: "info", text: "Canary" },
  };
  return (
    <Pill tone={map[status].tone} size="sm" active>
      {label ?? map[status].text}
    </Pill>
  );
}

function R(cap: string, status: Status, backend: string, notes = "—") {
  return [cap, <S status={status} />, backend, notes];
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
            <Pill tone="neutral" size="sm">
              1/3 System Truth
            </Pill>
            <Pill tone="info" size="sm" active>
              2/3 Capability Inventory ← you are here
            </Pill>
            <Pill tone="neutral" size="sm">
              3/3 User Journeys
            </Pill>
          </Row>
        </Stack>
      </CardBody>
    </Card>
  );
}

export default function KuroMap2Capabilities() {
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
          Kuro canonical · Map 2 of 3 · Code-backed 2026-08-09
        </Text>
        <H1>Capability Inventory</H1>
        <Text tone="secondary" style={{ maxWidth: 720, lineHeight: 1.55 }}>
          Exhaustive what-the-system-can-do map from Swift views/services and RPCs/edges. Pair with
          Map 1 for live flag % and AniList sources. Pair with Map 3 for how users walk these
          capabilities (including failures).
        </Text>
        <Row gap={8} wrap>
          <Pill tone="success" size="sm" active>
            Live
          </Pill>
          <Pill tone="warning" size="sm" active>
            Staged / gated
          </Pill>
          <Pill tone="info" size="sm" active>
            Ops / canary
          </Pill>
          <Pill tone="deleted" size="sm" active>
            Dead
          </Pill>
        </Row>
      </Stack>

      <TrilogyNav />

      <Callout tone="info" title="For the next LLM">
        Prefer this map when answering “does Kuro have X?” or “which RPC?”. Do not assume staged
        surfaces are user-visible — check Map 1 flags. File paths under /Users/max/Kuro-Anime-App/Kuro/.
      </Callout>

      <Grid columns={4} gap={12}>
        <Stat value="5+2" label="Pages + sheets" tone="info" />
        <Stat value="50+" label="Client RPCs" />
        <Stat value="7" label="FM capabilities" />
        <Stat value="12+" label="Service extensions" />
      </Grid>

      {/* SHELL */}
      <H2>0. App shell</H2>
      <Text size="small" tone="secondary">
        KuroApp.swift · ContentView.swift · NetworkMonitor · DeepLinkRouter
      </Text>
      <Table
        headers={["Capability", "Status", "Backend / code", "Notes"]}
        rows={[
          R("Root: config error / auth spinner / AuthView / ContentView", "live", "KuroApp.RootView", "Light mode forced"),
          R("OFFLINE banner", "live", "NetworkMonitor", "—"),
          R("Pager Taste→Discover→Browse→Collection→Clubs", "live", "swipeOrder + taste_deck_v1", "Default Discover"),
          R("Legacy pager Concierge@0", "gated", "taste_deck_v1 OFF", "Rollback path"),
          R("Header wordmark / title+dots / search / profile", "live", "KuroHeaderNew", "Clubs unread on dots"),
          R("Search sheet", "live", "EditorialSearchView", "Not a page"),
          R("Concierge sheet", "live", "Profile / deep link / launch arg", "When Taste owns index 0"),
          R("Swipe/tap guard", "live", "swipe_tap_guard_v1 100%", "—"),
          R("Reconnect refresh Discover/Collection/Clubs", "live", "reconnectionGeneration", "—"),
          R("Memory pressure trim", "live", "Image + detail caches", "—"),
          R("Onboarding cover", "live", "OnboardingView", "kuro_onboarding_completed"),
          R("Launch overlay KURO / CURATED ANIME", "live", "ContentView", "~160ms"),
        ]}
      />

      <CollapsibleSection title="Deep links" defaultOpen>
        <Table
          headers={["URL", "Action", "Notes"]}
          rows={[
            ["kuro://anime/{id}", "Anime detail sheet", "Int"],
            ["kuro://manga/{id}", "Manga detail sheet", "Int"],
            ["kuro://club/{uuid}", "Club detail", "UUID"],
            ["kuro://join/{CODE}", "Join sheet prefilled", "6–12 alnum; UI join sheet caps 8"],
            ["kuro://discover / collection", "Select page", "—"],
            ["kuro://concierge(?prompt=)", "Concierge sheet/page", "Sheet when Taste on"],
            ["kuro://auth/callback", "setSession", "Fragment then query"],
            ["Invalid URL", "Silent drop", "parse nil — no toast"],
          ]}
        />
      </CollapsibleSection>

      {/* AUTH */}
      <CollapsibleSection title="1. Auth & account" defaultOpen>
        <Table
          headers={["Capability", "Status", "Backend / code", "Notes"]}
          rows={[
            R("Email sign-in / sign-up", "live", "signIn/signUp + redirectTo callback", "Immediate session path"),
            R("Email uniqueness check", "live", "RPC check_email_exists", "Client ≥8 chars"),
            R("Sign in with Apple", "live", "signInWithApple", "—"),
            R("Password reset", "live", "resetPassword", "Email → callback"),
            R("Auth callback HTML fallback", "ops", "edge auth-callback", "verify_jwt false"),
            R("Delete account GDPR", "live", "edge delete-account", "Apple revoke + cascade"),
            R("Typed transport auth errors", "live", "userFacingAuthErrorMessage", "Offline/timeout/server"),
            R("Sign out", "live", "signOut", "No confirm"),
          ]}
        />
      </CollapsibleSection>

      {/* TASTE */}
      <CollapsibleSection title="2. Taste Deck" defaultOpen>
        <Table
          headers={["Capability", "Status", "Backend / code", "Notes"]}
          rows={[
            R("12-card batches (endless)", "live", "RPC fetch_taste_deck_batch", "TasteDeckView batchSize=12"),
            R("NOT FOR ME / I KNOW THIS / CALLS TO ME", "live", "record_taste_deck_signal", "love/known/skip + retract"),
            R("Flick L/U/R", "live", "TasteDeckView", "Same judgments"),
            R("Long-press synopsis / Undo / Leanings", "live", "fetch_my_taste_profile + realm_meta", "—"),
            R("300 signals/day", "live", "DB enforce", "—"),
            R("Never re-deal listed/judged/passed", "live", "batch logic", "—"),
            R("Profile recompute queue", "ops", "drain_taste_recompute_queue */15", "List mutations also signal"),
            R("Stall / offline / empty / exhausted UI", "live", "TasteDeckView", "See Map 3"),
          ]}
        />
      </CollapsibleSection>

      {/* DISCOVER */}
      <CollapsibleSection title="3. Discover" defaultOpen>
        <Stack gap={12}>
          <Table
            headers={["Capability", "Status", "Backend / code", "Notes"]}
            rows={[
              R("Pull refresh + ALL/ANIME/MANGA", "live", "discover_bundle", "—"),
              R("Show More (persists)", "live", "kuro_discover_show_more", "7 secondary rails"),
              R("Cached-data banner", "live", "SHOWING CACHED DATA", "—"),
              R("Friend-count prefetch", "gated", "social_activity_v1 → count_friends_tracking", "—"),
            ]}
          />
          <H3>Primary rails (code order)</H3>
          <Table
            headers={["Section", "Status", "Data", "Notes"]}
            rows={[
              ["The One Thing / Featured", <S status="live" />, "fetch_daily_feature", "FEATURED fallback"],
              ["AIRING TODAY", <S status="live" />, "discover_bundle", "See All"],
              ["BECAUSE YOU LOVED", <S status="staged" />, "fetch_because_you_rail", "Needs ≥4; replaces NTY"],
              ["NEW TO YOU", <S status="live" />, "bundle rotation (+ personalized RPC staged)", "—"],
              ["THE SHELF", <S status="staged" />, "fetch_tonight_shelf", "realm rails flag"],
              ["ESSENTIAL ANIME", <S status="live" />, "discover_bundle", "—"],
              ["HIDDEN GEM", <S status="staged" />, "fetch_realm_hidden_gem", "One Thing grammar"],
              ["NEW TO YOU (MANGA)", <S status="live" />, "discover_bundle", "—"],
              ["TRENDING (+ refine chips)", <S status="live" />, "discover_bundle", "Local refine only"],
              ["ESSENTIAL MANGA", <S status="live" />, "discover_bundle", "—"],
            ]}
          />
          <Text size="small">
            Secondary: CLASSICS · CURRENT SEASON · TOP RATED · JUST ADDED · MANGA CLASSICS ·
            TRENDING MANGA · TOP RATED MANGA. Card menu: Quick Add / Edit List / Add to Club…
          </Text>
        </Stack>
      </CollapsibleSection>

      {/* BROWSE SEARCH */}
      <CollapsibleSection title="4. Browse & Search" defaultOpen>
        <Stack gap={12}>
          <H3>Browse</H3>
          <Table
            headers={["Capability", "Status", "Backend / code", "Notes"]}
            rows={[
              R("ANIME/MANGA toggle", "live", "BrowseModeToggle", "—"),
              R("Keyset pageSize 60", "live", "browse_anime_page / browse_manga_page", "Hero + grid"),
              R("Sort POPULAR/TRENDING/TOP RATED/NEW", "live", "BrowseSort", "—"),
              R("Status FINISHED/AIRING", "live", "—", "AIRING=RELEASING"),
              R("Length / Genre(19) / Decade / Format", "live", "BrowseComponents", "Format can surface SPECIAL"),
              R("GenreHubView", "dead", "GenreHubView.swift", "Never instantiated"),
            ]}
          />
          <H3>Search sheet</H3>
          <Table
            headers={["Capability", "Status", "Backend / code", "Notes"]}
            rows={[
              R("Scopes ALL/ANIME/MANGA", "live", "EditorialSearchView", "—"),
              R("Chips TRENDING/NEW/CLASSICS/HIDDEN GEMS/AIRING", "live", "search_*_page", "Chips work empty query"),
              R("Structured search (not NL)", "live", "query ≥2 or chips", "NL = Collection only"),
            ]}
          />
        </Stack>
      </CollapsibleSection>

      {/* COLLECTION */}
      <CollapsibleSection title="5. Collection" defaultOpen>
        <Table
          headers={["Capability", "Status", "Backend / code", "Notes"]}
          rows={[
            R("Personal anime+manga lists", "live", "collection_*_page + user_lists tables", "—"),
            R("Status / verdict / sort / type / grid↔list", "live", "EditorialCollectionView", "—"),
            R("Substring search while typing", "live", "debounce", "—"),
            R("NL search on submit", "live", "FM parseSearchIntent", "Fallback substring"),
            R("EDIT batch status/remove", "live", "ConfirmationDialog", "Partial fail messaging"),
            R("SERVICE/LANG filters", "staged", "streaming_availability_v1", "—"),
            R("Card: Quick Classify / +1 / Edit / Remove", "live", "components", "—"),
          ]}
        />
      </CollapsibleSection>

      {/* CONCIERGE */}
      <CollapsibleSection title="6. Concierge" defaultOpen>
        <Table
          headers={["Capability", "Status", "Backend / code", "Notes"]}
          rows={[
            R("Starters: library/clipboard/curate/examples", "live", "ConciergeStarterActions", "Wired"),
            R("ConciergeIntentDeck", "dead", "showsIntentDeck:false", "Never presented"),
            R("Parse → reconcile → apply", "live", "edges parse/apply", "EN/DE NLP"),
            R("Auto-apply ≥0.85 no existing/ambiguous", "live", "ConciergeView", "Toast Undo"),
            R("Clarify cards v2", "canary", "clarify_v2 5% DE/AT/CH", "—"),
            R("Recommend vibe/seed rails", "live", "edge recommend", "Groq narrate optional"),
            R("AniList import", "live", "edge import-anilist", "Profile + Concierge"),
            R("Undo session", "live", "edge undo", "—"),
            R("FM assistIntent", "canary", "fm_assist_v1 + FM available", "Else keywords"),
            R("RAG retrieve-assist", "dead", "edge exists + flag canary", "iOS never invokes"),
            R("Groq resolve", "dead", "edge exists", "iOS never invokes; FM disambiguate used"),
            R("Analytics", "live", "ConciergeAnalytics → concierge_events", "Offline queue ≤200"),
            R("Session-local chat", "live", "—", "No honest cross-session restore"),
          ]}
        />
      </CollapsibleSection>

      {/* CLUBS */}
      <CollapsibleSection title="7. Clubs" defaultOpen>
        <Table
          headers={["Capability", "Status", "Backend / code", "Notes"]}
          rows={[
            R("Create/join/leave 2–20", "live", "create/join/leave_club", "Typed ERROR_ codes"),
            R("List enriched cards", "live", "fetch_my_clubs_*", "Flag accessor unused"),
            R("Tabs Rails / Active / Polls", "live", "ClubDetailView", "No chat tab"),
            R("Rails add/lock/notes/search", "live", "add_club_rail_item / create_club_rail", "DETAIL codes"),
            R("Reactions 🔥❤️👀💯", "live", "clubs_reactions_v1 100%", "—"),
            R("Pace + milestones", "live", "clubs_pace_sync_v1 100%", "≥3 + progress sharing"),
            R("Realtime", "live", "clubs_realtime_v1 100%", "Service early-return if off"),
            R("Unread badges", "live", "clubs_notifications_v1 100%", "—"),
            R("Polls vote/create", "live", "create_club_poll / cast_club_vote", "Optimistic if interaction v2"),
            R("Settings invite/leave", "live", "leave_club", "Sole member deletes club"),
            R("SHARED provider strip", "staged", "streaming + club_shared_providers", "—"),
            R("Chat RPCs/UI", "dead", "send/fetch_club_messages; clubs_chat_v1 off", "Schema retained"),
          ]}
        />
      </CollapsibleSection>

      {/* SOCIAL */}
      <CollapsibleSection title="8. Social activity" defaultOpen>
        <Table
          headers={["Capability", "Status", "Backend / code", "Notes"]}
          rows={[
            R("Friends = share club", "live", "shares_club_with()", "social 100%"),
            R("Friend counts on cards", "gated", "count_friends_tracking", "UI gated"),
            R("One comment/user/title ≤500", "live", "upsert/delete_title_comment", "10/5min"),
            R("Thumbs on comments", "live", "toggle_comment_reaction", "30/min"),
            R("FriendsActivitySection", "gated", "fetch_friend_activity_for_title", "Sharing-level visibility"),
          ]}
        />
        <Text size="small" tone="secondary">
          Note: anime_comments / manga_comments tables exist in baseline schema but are not the
          product path — title_comments is.
        </Text>
      </CollapsibleSection>

      {/* DETAIL */}
      <CollapsibleSection title="9. Detail pages" defaultOpen>
        <Table
          headers={["Capability", "Status", "Backend / code", "Notes"]}
          rows={[
            R("MediaDetailSheet loader + disk cache", "live", "KuroDiskDetailCache ≤300", "—"),
            R("Hero/genres/synopsis expand", "live", "—", "—"),
            R("FM synopsis condense", "live", "AppleFMService.condenseSynopsis", "iOS 26+"),
            R("NEXT UP", "live", "progress + catalog", "—"),
            R("Episodes mark + legal links", "live", "episodes + external_links", "Allowlists"),
            R("Chapters mark + legal links", "live", "chapters + get_manga_chapter_status", "MangaDex enrich"),
            R("Adaptation Path", "live", "get_media_ladder", "enqueue_media_relation_refresh"),
            R("Cast / Production", "live", "credits_cast_v1 100%", "Entity sheets"),
            R("More Like This", "live", "recommend_ids_similar_to_seeds", "Genre fallback"),
            R("Club + Friends sections", "live", "ClubActivity / FriendsActivity", "—"),
            R("External AniList/MAL", "live", "ExternalLinksSection", "—"),
            R("Sticky Save / Verdict / Watch", "live", "AddToList + QuickVerdict", "Providers staged"),
            R("Outbound click ledger", "live", "record_outbound_link", "affiliates OFF"),
            R("Provider availability UI", "staged", "batch_provider_availability_for_media_v2", "—"),
          ]}
        />
      </CollapsibleSection>

      {/* LISTS / PROFILE */}
      <CollapsibleSection title="10. Lists, Profile, Onboarding">
        <Table
          headers={["Capability", "Status", "Backend / code", "Notes"]}
          rows={[
            R("AddToListSheet status/progress/score/notes", "live", "upsertUserListEntry", "Offline blocks"),
            R("Quick verdict MASTERPIECE/OKAY/BAD", "live", "QuickVerdictActionCard", "—"),
            R("User-list Realtime", "live", "subscribeToUpdates", "Bootstrap"),
            R("Local countdown notifications", "live", "UNUserNotificationCenter", "Not APNs push"),
            R("Onboarding 5 cards EN/DE → Taste CTA", "live", "OnboardingView", "—"),
            R("Profile: Clubs/Sync/AniList/Concierge/Clear/SignOut/Delete", "live", "ProfileView", "—"),
            R("Streaming prefs + freshness card", "staged", "save_user_streaming_services", "—"),
          ]}
        />
      </CollapsibleSection>

      {/* FM */}
      <CollapsibleSection title="11. Apple FM — 7 capabilities">
        <Table
          headers={["API", "Used for", "Timeout", "Gate"]}
          rows={[
            ["classifyMode", "Mode id", "5s", "FM device"],
            ["disambiguate", "Title collision", "8s", "Concierge adaptations"],
            ["condenseSynopsis", "2-sentence hook", "10s", "Detail"],
            ["parseSearchIntent", "Collection NL", "5s", "onSubmit"],
            ["assistIntent", "6 intents", "3s", "fm_assist_v1 canary"],
            ["assistSlots", "status/progress/unit", "3s", "fm_assist path"],
            ["assistDisambiguate", "Ranked indices", "3s", "fm_assist path"],
          ]}
        />
        <Text size="small" tone="secondary">
          StubFMProvider on non-FM devices. No FM entitlement in Kuro.entitlements.
        </Text>
      </CollapsibleSection>

      {/* RPC INDEX */}
      <CollapsibleSection title="12. Client RPC index">
        <Table
          headers={["Domain", "RPCs"]}
          rows={[
            ["Auth", "check_email_exists"],
            ["Discover", "discover_bundle, fetch_daily_feature, fetch_because_you_rail, fetch_tonight_shelf, fetch_realm_hidden_gem"],
            ["Search/Browse", "search_anime_page, search_manga_page, browse_anime_page, browse_manga_page"],
            ["Collection", "collection_feed_page, collection_anime_page, collection_manga_page"],
            ["Taste", "fetch_taste_deck_batch, record_taste_deck_signal, fetch_my_taste_profile, fetch_personalized_new_to_you"],
            ["Clubs", "fetch_my_clubs_loading/enriched, create/join/leave_club, fetch_club_bundle(_loading), add_club_rail_item, create_club_rail/poll, cast_club_vote, toggle_club_reaction, check_club_activity_since, send/fetch_club_messages"],
            ["Ladder", "get_media_ladder, enqueue_media_relation_refresh"],
            ["Social", "fetch_friend_activity_for_title, upsert/delete_title_comment, toggle_comment_reaction, count_friends_tracking"],
            ["Streaming", "batch_provider_availability_for_media_v2, batch_providers_for_media, enqueue_media_availability_refresh, get_media_availability_status, get_provider_availability_refresh_queue_summary, save_user_streaming_services, club_shared_providers"],
            ["Misc", "recommend_ids_similar_to_seeds, get_manga_chapter_status, record_outbound_link"],
          ]}
        />
      </CollapsibleSection>

      {/* OPS */}
      <CollapsibleSection title="13. Ops pipelines (non-user)">
        <Table
          headers={["Pipeline", "Status", "How", "Output"]}
          rows={[
            R("AniList bulk import", "ops", "Cron + IMPORT_SECRET", "Catalog"),
            R("Image mirror", "ops", "Nightly batches", "Storage media"),
            R("MangaDex enrich + review", "ops", "*/15 + review-action", "chapters"),
            R("Synopsis enrichment (Mac)", "ops", "launchd + :8787", "reports/synopsis-enrichment"),
            R("Catalog safety (Mac)", "ops", "launchd + :8788", "Isolated"),
            R("Provider availability (Mac)", "ops", "Watchmode + :8789", "Product UI still 0%"),
            R("Media relations worker", "ops", "com.kuro.media-relations", "Ladder coverage"),
            R("Realm describe drain", "ops", "pg_cron + edge", "Shelf/Gem data"),
            R("Taste drain + tag vectors", "ops", "*/15 + nightly", "Taste math"),
            R("Unified dashboard", "ops", ":8791", "All pipeline status"),
            R("Quality gates + fastlane beta", "ops", "scripts/ + fastlane/", "CI / TestFlight"),
          ]}
        />
      </CollapsibleSection>

      <H2>14. Dead / staged checklist</H2>
      <Grid columns={3} gap={12}>
        <Card>
          <CardHeader trailing={<Pill tone="deleted" size="sm" active>Dead</Pill>}>
            Unwired
          </CardHeader>
          <CardBody>
            <Text size="small">
              ConciergeIntentDeck · GenreHubView · iOS→resolve/assist · club chat UI ·
              concierge_editorial flag ignored
            </Text>
          </CardBody>
        </Card>
        <Card>
          <CardHeader trailing={<Pill tone="warning" size="sm" active>0%</Pill>}>
            Staged
          </CardHeader>
          <CardBody>
            <Text size="small">
              Streaming surface · personalized NTY / Because You · Shelf + Hidden Gem
            </Text>
          </CardBody>
        </Card>
        <Card>
          <CardHeader trailing={<Pill tone="info" size="sm" active>5%</Pill>}>
            Canary DE/AT/CH
          </CardHeader>
          <CardBody>
            <Text size="small">fm_assist_v1 · clarify_v2 · rag_assist_v1 (flag only for RAG)</Text>
          </CardBody>
        </Card>
      </Grid>

      <Divider />
      <Text size="small" tone="tertiary" style={{ color: theme.text.tertiary }}>
        Sources: Kuro Swift views/services · SupabaseService+* · Map 1 for live flag %. Next: Map
        3/3 User Journeys (kuro-user-journeys.canvas.tsx)
      </Text>
    </Stack>
  );
}
