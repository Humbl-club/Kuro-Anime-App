import {
  Callout,
  Card,
  CardBody,
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
  useHostTheme,
} from "cursor/canvas";

/**
 * KURO CANONICAL MAP 3/3 — User Journeys (+ non-happy)
 * Sister maps:
 *   1) kuro-reconciled-truth-map.canvas.tsx — System Truth & Sources
 *   2) kuro-functionality-map.canvas.tsx — Capability Inventory
 * Verified against Swift error paths · 2026-08-09
 */

type Step = { n: string; where: string; does: string; outcome: string };

function JourneySteps({ steps }: { steps: Step[] }) {
  return (
    <Table
      headers={["#", "Where", "User does", "What happens"]}
      rows={steps.map((s) => [s.n, s.where, s.does, s.outcome])}
    />
  );
}

function BranchTable({ rows }: { rows: Array<[string, string, string]> }) {
  return (
    <Table headers={["Branch", "User sees", "Recovery"]} rows={rows} />
  );
}

function Flow({ parts }: { parts: string[] }) {
  return (
    <Row gap={6} align="center" wrap>
      {parts.map((p, i) => (
        <>
          {i > 0 ? (
            <Text tone="tertiary" size="small">
              →
            </Text>
          ) : null}
          <Pill
            size="sm"
            active={i === 0 || i === parts.length - 1}
            tone={i === parts.length - 1 ? "success" : "neutral"}
          >
            {p}
          </Pill>
        </>
      ))}
    </Row>
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
            <Pill tone="neutral" size="sm">
              1/3 System Truth
            </Pill>
            <Pill tone="neutral" size="sm">
              2/3 Capability Inventory
            </Pill>
            <Pill tone="info" size="sm" active>
              3/3 User Journeys ← you are here
            </Pill>
          </Row>
        </Stack>
      </CardBody>
    </Card>
  );
}

export default function KuroMap3Journeys() {
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
          Kuro canonical · Map 3 of 3 · Rechecked 2026-08-09
        </Text>
        <H1>User Journeys</H1>
        <Text tone="secondary" style={{ maxWidth: 720, lineHeight: 1.55 }}>
          How a person moves through Kuro: happy paths and non-happy branches (errors, empties,
          rate limits, offline, silent deep-link drops). Use with Map 2 for capability names and Map
          1 for whether a branch is live vs staged.
        </Text>
        <Row gap={8} wrap>
          <Pill tone="success" size="sm" active>
            Happy
          </Pill>
          <Pill tone="warning" size="sm" active>
            Non-happy
          </Pill>
          <Pill tone="deleted" size="sm" active>
            Silent / dead
          </Pill>
        </Row>
      </Stack>

      <TrilogyNav />

      <Callout tone="info" title="For the next LLM">
        When debugging UX, start here. Quote user-visible copy from the non-happy tables — it was
        pulled from AuthView, TasteDeckView, ConciergeView, ClubsView/ClubDetailSheets, Collection,
        Discover, MediaDetailSheet. Mental model: 5 swipe pages; Search + Concierge are sheets;
        social is title-level, not club chat.
      </Callout>

      <Grid columns={4} gap={12}>
        <Stat value="9" label="Core journeys" tone="info" />
        <Stat value="Taste→…" label="Teach path" />
        <Stat value="Discover" label="Default home" />
        <Stat value="Sheet" label="Concierge entry" />
      </Grid>

      <Callout tone="neutral" title="Canonical happy loop">
        Auth → Teach taste (12 cards) → Discover & save → Concierge import the rest → Club rail with
        friends → Comment on the title detail page.
      </Callout>

      {/* J1 */}
      <H2>J1 · First launch → taste taught</H2>
      <Flow parts={["Auth", "Onboarding", "Taste Deck", "Discover"]} />
      <JourneySteps
        steps={[
          {
            n: "1",
            where: "AuthView",
            does: "Apple or Email sign-in / create",
            outcome: "Session + bootstrap (lists, flags)",
          },
          {
            n: "2",
            where: "OnboardingView",
            does: "5 cards; TEACH KURO YOUR TASTE or Skip",
            outcome: "kuro_onboarding_completed → Taste when flag on",
          },
          {
            n: "3",
            where: "TasteDeckView",
            does: "Judge 12 cards (buttons or flicks)",
            outcome: "Signals recorded; recompute queued",
          },
          {
            n: "4",
            where: "Done / swipe",
            does: "BACK TO DISCOVER or swipe right",
            outcome: "Home = Discover",
          },
        ]}
      />
      <CollapsibleSection title="J1 non-happy" defaultOpen>
        <BranchTable
          rows={[
            ["Missing Supabase config", "Configuration Error full screen", "Deep links ignored"],
            ["Offline auth", "Typed: no internet / lost / timeout / can't reach server", "Retry online"],
            ["Bad credentials", "Incorrect email or password…", "Re-enter / Forgot password"],
            ["Email taken / weak password", "Taken / min length", "Client ≥8 vs server ≥6 mismatch possible"],
            ["Email unconfirmed (if dashboard on)", "Please check your email…", "Verify → callback"],
            ["Bad auth callback", "Verification failed… or silent ignore", "New link"],
            ["Apple credential/nonce fail", "Unexpected credential / missing token…", "Retry Apple"],
            ["taste_deck_v1 OFF", "GET STARTED only; Concierge pager page", "Legacy layout"],
            ["Skip Taste CTA", "Discover without teaching", "Open Taste later via pager"],
          ]}
        />
      </CollapsibleSection>

      {/* J2 */}
      <H2>J2 · Taste Deck ritual</H2>
      <Flow parts={["Taste", "Deal 12", "Judge", "Leanings / Discover"]} />
      <JourneySteps
        steps={[
          {
            n: "1",
            where: "Taste",
            does: "NOT FOR ME / I KNOW THIS / CALLS TO ME",
            outcome: "record_taste_deck_signal; brief Undo",
          },
          {
            n: "2",
            where: "Long-press / LEANINGS",
            does: "Synopsis overlay; leanings sheet",
            outcome: "Server profile / realms",
          },
        ]}
      />
      <CollapsibleSection title="J2 non-happy" defaultOpen>
        <BranchTable
          rows={[
            ["Offline, no card", "The deck is quiet without a connection.", "RETRY; auto on reconnect"],
            ["Load stall ~8s / fail", "The deck is taking longer than it should.", "RETRY"],
            ["Empty never-judged", "Deck empty — catalog grows", "Back to Discover"],
            ["Exhausted after judging", "THE DECK IS EMPTY + count", "Leanings / BACK TO DISCOVER"],
            ["Signal RPC fail", "Signal didn't save — will retry", "Queued; flagged after 3 fails"],
            ["Undo expires", "Chip clears", "Judgment sticks"],
          ]}
        />
      </CollapsibleSection>

      {/* J3 */}
      <H2>J3 · Discover → open → save</H2>
      <Flow parts={["Discover", "Card", "Detail", "List / Verdict"]} />
      <JourneySteps
        steps={[
          {
            n: "1",
            where: "Discover",
            does: "Scroll rails; Show More; ALL/ANIME/MANGA",
            outcome: "One Thing, Airing, NTY, Essentials, Trending…",
          },
          {
            n: "2",
            where: "Card",
            does: "Tap or Quick Add / Edit List / Add to Club…",
            outcome: "Detail or direct mutation",
          },
          {
            n: "3",
            where: "Detail dock",
            does: "Save / AddToList / Quick Verdict",
            outcome: "Status/progress/score/notes or MASTERPIECE/OKAY/BAD",
          },
        ]}
      />
      <CollapsibleSection title="J3 non-happy" defaultOpen>
        <BranchTable
          rows={[
            ["Hard fail", "COULDN'T LOAD + connection copy", "RETRY"],
            ["Soft empty", "NO CONTENT FOUND", "Pull refresh"],
            ["Offline + cache", "SHOWING CACHED DATA", "Browse stale"],
            ["Refresh fail w/ data", "Couldn't refresh. Try again.", "Stale kept"],
            ["Detail not found", "COULDN'T LOAD / Not found", "RETRY; disk cache possible"],
            ["Save offline", "You're offline. Reconnect to update your list.", "Reconnect"],
            ["Save/progress fail", "Couldn't save / Update failed…", "Retry toast"],
            ["Link open fail", "Couldn't open link", "Other link"],
            ["No friends tracking", "No friends tracking this yet", "Need shared club"],
            ["Comment fail", "Could not save/delete comment", "Retry; delete confirms"],
            ["Personalized/realm OFF", "Standard NTY; no Shelf/Gem", "Not an error — staged"],
          ]}
        />
      </CollapsibleSection>

      {/* J4 */}
      <H2>J4 · Catalog hunt (Browse + Search)</H2>
      <Grid columns={2} gap={12}>
        <Card>
          <CardBody>
            <Stack gap={8}>
              <Text weight="medium" size="small">
                Browse happy
              </Text>
              <Flow parts={["Browse", "Filters", "Hero/grid", "Detail"]} />
              <Text size="small" tone="secondary">
                Explicit format can surface SPECIAL/MUSIC/TV_SHORT that Discover hides.
              </Text>
            </Stack>
          </CardBody>
        </Card>
        <Card>
          <CardBody>
            <Stack gap={8}>
              <Text weight="medium" size="small">
                Search happy
              </Text>
              <Flow parts={["🔍", "Query/chips", "Results", "Detail"]} />
              <Text size="small" tone="secondary">
                Structured only. NL belongs to Collection (J5).
              </Text>
            </Stack>
          </CardBody>
        </Card>
      </Grid>
      <CollapsibleSection title="J4 non-happy" defaultOpen>
        <BranchTable
          rows={[
            ["Browse offline empty", "COULDN'T LOAD + RETRY", "Reconnect auto-retry"],
            ["Filters too tight", "NO MATCHES / CLEAR FILTERS", "Widen"],
            ["Browse refresh fail", "Couldn't refresh…", "Stale grid kept"],
            ["Search idle", "Begin your search for the extraordinary", "Type/chips"],
            ["Search no hits", "NO RESULTS + suggestions", "Change query"],
            ["Search service fail", "Often empty UI; service may set Search failed…", "Retry"],
          ]}
        />
      </CollapsibleSection>

      {/* J5 */}
      <H2>J5 · Manage Collection</H2>
      <Flow parts={["Collection", "Filter", "Edit / batch / NL"]} />
      <JourneySteps
        steps={[
          {
            n: "1",
            where: "Filters",
            does: "Status / verdict / sort / type / grid↔list",
            outcome: "Focused personal catalog",
          },
          {
            n: "2",
            where: "Search",
            does: "Type substring; submit NL",
            outcome: "Substring while typing; FM on submit",
          },
          {
            n: "3",
            where: "EDIT / menus",
            does: "Batch status/remove; +1; Quick Classify",
            outcome: "Bulk or quick mutations",
          },
        ]}
      />
      <CollapsibleSection title="J5 non-happy" defaultOpen>
        <BranchTable
          rows={[
            ["Truly empty", "YOUR COLLECTION IS EMPTY", "EXPLORE DISCOVER / TRY CONCIERGE"],
            ["Search no hits", "NO RESULTS", "Change query"],
            ["Load error online", "COULDN'T LOAD COLLECTION", "RETRY"],
            ["Load error offline", "YOU'RE OFFLINE…", "Reconnect; cached strip if data"],
            ["Batch remove partial", "Removed N of M — K failed", "Retry remaining"],
            ["Batch remove total fail", "Couldn't remove items…", "Reconnect"],
            ["Batch remove confirm", "Remove N item(s)…?", "Cancel / destructive"],
            ["Streaming filters OFF", "No SERVICE/LANG UI", "Staged — not broken"],
          ]}
        />
      </CollapsibleSection>

      {/* J6 */}
      <H2>J6 · Concierge import</H2>
      <Flow
        parts={[
          "Profile / deep link",
          "Paste / AniList",
          "Parse",
          "Clarify?",
          "Confirm",
          "Apply",
          "Undo?",
        ]}
      />
      <JourneySteps
        steps={[
          {
            n: "1",
            where: "Concierge sheet",
            does: "Library / clipboard / examples / AniList",
            outcome: "parse (or AniList → same pipeline)",
          },
          {
            n: "2",
            where: "Auto-apply gate",
            does: "—",
            outcome: "All ≥0.85, no existing_entry, no ambiguous adaptations → apply now",
          },
          {
            n: "3",
            where: "Confirm",
            does: "Add/Update/Skip → confirm",
            outcome: "apply; toast UNDO + optional View Collection",
          },
        ]}
      />
      <CollapsibleSection title="J6 non-happy" defaultOpen>
        <BranchTable
          rows={[
            ["429 rate limit", "Sticky: Too many requests. Try again in Ns.", "Wait"],
            ["Other errors", "Toast Error ~3s", "Retry"],
            ["clarify_v2 ON", "status/unit/intent unclear cards", "Answer → re-parse"],
            ["clarify_v2 OFF", "Chips skipped", "Confirm/auto without cards"],
            ["Adaptation ambiguity", "Background FM disambiguate", "User pick if still unclear"],
            ["Unknown intent", "What would you like to do?", "Library/paste/examples"],
            ["Empty clipboard/library", "Toast EN/DE", "Add content first"],
            ["Nothing selected", "No items selected", "Select"],
            ["Apply success=false", "Failed to apply items + detail", "Fix/retry"],
            ["Conflicts", "N conflict(s) — review needed + UNDO", "Review/undo"],
            [">200 titles", "Partial import — first 200", "Another pass"],
            ["Undo fail", "Undo failed / Try again", "Retry"],
            ["Open title fail", "Couldn't find that anime/manga…", "Stay in Concierge"],
            ["AniList offline/timeout", "Typed + RETRY IMPORT (+ retry_after)", "Retry / Profile handoff"],
            ["Already up to date", "Skip state", "No write"],
            ["Offline send", "Blocked", "Reconnect"],
            ["Session-local", "No honest restore next open", "NEW CHAT"],
          ]}
        />
      </CollapsibleSection>

      {/* J7 */}
      <H2>J7 · Concierge recommend</H2>
      <Flow parts={["Concierge", "Mood/seed", "Rails", "Open / save / hide"]} />
      <CollapsibleSection title="J7 non-happy" defaultOpen>
        <BranchTable
          rows={[
            ["Empty rails", "Server message or Give me a mood…", "Refine prompt"],
            ["429 / network", "Same sticky vs toast as import", "Wait/retry"],
            ["Quick save then open fails", "Added to Planning / couldn't find", "Open from Collection"],
            ["fm_assist OFF", "Keyword routing only", "Still works"],
            ["rag_assist", "No client call", "N/A"],
          ]}
        />
      </CollapsibleSection>

      {/* J8 */}
      <H2>J8 · Club night</H2>
      <Flow
        parts={[
          "Create/Join",
          "Rails",
          "Progress / react",
          "Active / Polls",
          "Title comments",
        ]}
      />
      <JourneySteps
        steps={[
          {
            n: "1",
            where: "Clubs",
            does: "CREATE or JOIN (UI 8 chars; deep link 6–12)",
            outcome: "Member; open Rails/Active/Polls",
          },
          {
            n: "2",
            where: "Rails",
            does: "Add titles; react; update progress",
            outcome: "Shared list; pace when ≥3 + progress sharing",
          },
          {
            n: "3",
            where: "Polls / Friends on detail",
            does: "Vote; one comment; thumbs",
            outcome: "Title-level social (no chat)",
          },
        ]}
      />
      <CollapsibleSection title="J8 non-happy — create/join" defaultOpen>
        <BranchTable
          rows={[
            ["Empty list", "Watch together. Private by design.", "CREATE / JOIN"],
            ["INVALID_NAME", "Name must be 1-80 characters.", "Fix"],
            ["DESCRIPTION_TOO_LONG", "≤500 characters.", "Shorten"],
            ["RATE_LIMITED create", "Too many create attempts…", "Wait"],
            ["TOO_MANY_CLUBS", "You've reached the club limit.", "Leave another"],
            ["INVALID_CODE", "Invalid invite code.", "Recheck"],
            ["CODE_EXPIRED", "Invite code has expired.", "New code"],
            ["CODE_EXHAUSTED", "Usage limit reached.", "Ask owner"],
            ["CLUB_ARCHIVED", "Club no longer active.", "Stop"],
            ["CLUB_FULL", "Club is full.", "Max 20"],
            ["ALREADY_MEMBER", "Already a member.", "Open list"],
            ["RATE_LIMITED join", "Too many attempts…", "Wait"],
            ["UI vs deep link length", "Sheet needs exactly 8; link 6–12", "Use matching path"],
            ["Bad join URL", "Silent drop — no toast", "User sees nothing"],
          ]}
        />
      </CollapsibleSection>
      <CollapsibleSection title="J8 non-happy — detail/rail/leave" defaultOpen>
        <BranchTable
          rows={[
            ["Load offline/timeout", "You're offline. Reconnect to load this club.", "Retry"],
            ["Club gone", "This club no longer exists.", "Back"],
            ["Stale refresh", "Refresh delayed / Offline + Retry", "Retry"],
            ["DUPLICATE_ITEM", "Already in this rail", "Other title"],
            ["RAIL_LOCKED", "Locked; admins only", "Ask admin"],
            ["NOT_A_MEMBER", "No longer a member", "Rejoin"],
            ["MEDIA_NOT_FOUND", "Not found in catalog", "Other title"],
            ["NOTE_TOO_LONG", "Under 280 characters", "Shorten"],
            ["RAIL_NOT_FOUND", "Rail no longer available", "Refresh"],
            ["UNAUTHENTICATED", "Sign in again", "Re-auth"],
            ["Search fail/empty", "Search failed… / No anime/manga found", "Retry"],
            ["Vote fail", "Vote failed / Please try again.", "Retry"],
            ["Rail/poll create error", "Raw localizedDescription", "Retry"],
            ["Poll create offline", "CTA disabled", "Reconnect"],
            ["Duo Active tab", "Activity unlocks at 3 members…", "Invite"],
            ["Leave confirm", "Rejoin code / sole delete / ownership transfer note", "Cancel/Leave"],
            ["Leave fail", "No longer a member / Could not leave", "Refresh"],
            ["Add to Club from detail fail", "Could not load/add rails / No rails yet", "Ask admin"],
          ]}
        />
      </CollapsibleSection>

      {/* J9 */}
      <H2>J9 · Offline, deep links, account teardown</H2>
      <CollapsibleSection title="Offline matrix" defaultOpen>
        <Table
          headers={["Surface", "Blocked", "Still works"]}
          rows={[
            ["Global", "—", "OFFLINE banner"],
            ["Discover/Browse/Collection/Detail", "Fresh loads", "Cache/disk when present"],
            ["List/verdict/club writes", "Mutations", "Read UI"],
            ["Taste signals", "Immediate persist", "Queued retry + banner"],
            ["Concierge send/AniList", "Network", "Composer UI"],
            ["Club poll create", "Disabled CTA", "Cached polls if any"],
            ["Analytics", "Flush deferred", "Queue ≤200; flush on reconnect"],
          ]}
        />
      </CollapsibleSection>
      <CollapsibleSection title="Deep link + Profile non-happy" defaultOpen>
        <BranchTable
          rows={[
            ["Invalid URL", "Nothing (silent)", "No toast"],
            ["Auth callback no tokens", "Ignored", "New link"],
            ["Config error up", "onOpenURL no-op", "Fix config"],
            ["Valid link, load fails", "Detail/club COULDN'T LOAD", "RETRY"],
            ["Delete account", "Confirm → Deleting… / Deletion failed", "Irreversible if ok"],
            ["Sign out", "Immediate, no confirm", "Sign in again"],
          ]}
        />
      </CollapsibleSection>

      <Divider />
      <H2>Journey connections</H2>
      <Table
        headers={["From", "Can jump to", "Via"]}
        rows={[
          ["Onboarding", "Taste → Discover", "CTA / Skip"],
          ["Discover/Browse/Search", "Detail → List / Club", "Tap / context menu"],
          ["Collection empty", "Discover or Concierge", "Empty CTAs"],
          ["Profile", "Concierge, Clubs, AniList, Delete", "Action rows"],
          ["Any header", "Search", "Magnifying glass"],
          ["Any card w/ clubs", "Club rail add", "Add to Club…"],
          ["Club rail", "Title detail → Friends", "Tap title"],
          ["Deep link", "Detail/Club/Join/Concierge/page", "kuro://…"],
          ["Concierge after apply", "Collection", "View Collection toast"],
        ]}
      />

      <H2>Most common real fails</H2>
      <Text size="small">
        Offline write blocks · Discover/detail RETRY · Concierge 429 sticky · Club bad/full codes ·
        Collection empty CTAs · Taste stall/exhausted · Silent bad deep links
      </Text>

      <Divider />
      <Text size="small" tone="tertiary" style={{ color: theme.text.tertiary }}>
        Sources: AuthView · TasteDeckView · ConciergeView · ClubsView/ClubDetailSheets ·
        Collection/Discover/Detail · SupabaseService error translators. Trilogy complete — return to
        Map 1 for flags/AniList or Map 2 for RPCs.
      </Text>
    </Stack>
  );
}
