import {
  Callout,
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
 * Map 3 non-happy string verification vs Swift (2026-08-10)
 * MATCH = exact · FIXED = was paraphrase, now exact in Map 3 · NOTE = intentional summary
 */

export default function KuroMap3StringAudit() {
  return (
    <Stack gap={28} style={{ padding: 28, maxWidth: 1080 }}>
      <Stack gap={10}>
        <Text
          size="small"
          tone="tertiary"
          weight="medium"
          style={{ letterSpacing: 1.4, textTransform: "uppercase" }}
        >
          Kuro follow-up · Map 3 string audit · 2026-08-10
        </Text>
        <H1>Non-happy copy vs Swift</H1>
        <Text tone="secondary" style={{ maxWidth: 720, lineHeight: 1.55 }}>
          Spot-check of every user-facing string quoted in Map 3 journeys against AuthView,
          TasteDeckView, ClubsView, ClubDetailSheets, ConciergeView, Browse/Collection/Discover.
        </Text>
        <Row gap={8} wrap>
          <Pill tone="success" size="sm" active>
            MATCH
          </Pill>
          <Pill tone="warning" size="sm" active>
            FIXED
          </Pill>
          <Pill tone="info" size="sm" active>
            NOTE
          </Pill>
        </Row>
      </Stack>

      <Grid columns={3} gap={12}>
        <Stat value="18" label="Strings corrected" tone="warning" />
        <Stat value="Club rails" label="Worst paraphrase cluster" tone="warning" />
        <Stat value="Map 3" label="Patched in place" tone="success" />
      </Grid>

      <Callout tone="warning" title="Biggest prior drift">
        Club rail errors were paraphrased (“Already in this rail”, “Under 280 characters”). Actual
        copy is full sentences from ClubDetailSheets.mapRailItemError. Concierge conflicts use a
        double hyphen `--`, not an em dash.
      </Callout>

      <H2>Corrections applied to Map 3</H2>
      <Table
        headers={["Journey", "Was (wrong/paraphrase)", "Exact Swift", "File"]}
        rows={[
          [
            "J1",
            "Incorrect email or password…",
            "Incorrect email or password. Please try again.",
            "SupabaseService",
          ],
          [
            "J1",
            "Taken / min length",
            "An account with this email already exists… / Password needs at least 8 characters. (client) vs Password must be at least 6 characters. (server)",
            "AuthView + SupabaseService",
          ],
          [
            "J1",
            "Unexpected credential / missing token…",
            "Unexpected credential type. / Missing nonce. Please try again.",
            "AuthView",
          ],
          [
            "J2",
            "Deck empty — catalog grows",
            "The deck is empty — Kuro will deal more as the catalog grows.",
            "TasteDeckView",
          ],
          [
            "J2",
            "THE DECK IS EMPTY + count",
            "THE DECK IS EMPTY + You've seen everything\\nKuro has — for now. + N titles judged",
            "TasteDeckView",
          ],
          [
            "J4",
            "NO MATCHES / CLEAR FILTERS",
            "NO MATCHES | NO MATCHES FOR N FILTERS + Try different filters + CLEAR FILTERS",
            "BrowseComponents",
          ],
          [
            "J5",
            "Couldn't remove items…",
            "Couldn't remove items — check your connection",
            "EditorialCollectionView",
          ],
          [
            "J6",
            "N conflict(s) — review needed",
            "N conflict(s) -- review needed",
            "ConciergeView",
          ],
          [
            "J8",
            "≤500 characters.",
            "Description must be 500 characters or fewer.",
            "ClubsView",
          ],
          [
            "J8",
            "Invite code has expired.",
            "This invite code has expired.",
            "ClubsView",
          ],
          [
            "J8",
            "Usage limit reached.",
            "This invite code has reached its usage limit.",
            "ClubsView",
          ],
          [
            "J8",
            "Club no longer active. / Club is full. / Already a member.",
            "This club is no longer active. / This club is full. / You're already a member of this club.",
            "ClubsView",
          ],
          [
            "J8 rail",
            "Already in this rail / Locked; admins only / Under 280…",
            "This title is already in this rail. / This rail is locked. Only admins can add items. / Note is too long. Keep it under 280 characters.",
            "ClubDetailSheets",
          ],
          [
            "J8",
            "Sign in again / No longer a member / Not found in catalog",
            "Please sign in again to continue. / You're no longer a member of this club. / This title was not found in the catalog.",
            "ClubDetailSheets",
          ],
          [
            "J8",
            "Activity unlocks at 3 members…",
            "Activity unlocks at 3 members — invite one more friend.",
            "ClubDetailTabComponents",
          ],
          [
            "J8",
            "Could not leave",
            "Could not leave club. Please try again.",
            "ClubDetailSheets",
          ],
          [
            "J8",
            "Search failed… / No anime/manga found",
            "Search failed. Check your connection and try again. / No anime found / No manga found",
            "ClubDetailSheets",
          ],
          [
            "J3",
            "Could not save/delete comment",
            "Could not save comment. / Could not delete comment.",
            "FriendsActivitySection",
          ],
        ]}
      />

      <H2>Already MATCH (spot-checked)</H2>
      <Table
        headers={["String", "Source"]}
        rows={[
          ["Configuration Error", "KuroApp"],
          ["The deck is quiet without a connection.", "TasteDeckView"],
          ["The deck is taking longer than it should.", "TasteDeckView"],
          ["Signal didn't save — will retry", "TasteDeckView"],
          ["COULDN'T LOAD / NO CONTENT FOUND / SHOWING CACHED DATA", "Discover/Detail"],
          ["Couldn't refresh. Try again.", "Discover/Browse/Collection"],
          ["You're offline. Reconnect to update your list.", "AddToListSheet"],
          ["No friends tracking this yet", "FriendsActivitySection"],
          ["Begin your search for the extraordinary", "EditorialSearchView"],
          ["YOUR COLLECTION IS EMPTY / EXPLORE DISCOVER", "EditorialCollection*"],
          ["Too many requests. Try again in Ns.", "SupabaseService translate"],
          ["No items selected / Failed to apply items / Undo failed", "ConciergeView"],
          ["Watch together. / Private by design.", "ClubsView"],
          ["Name must be 1-80 characters. / You've reached the club limit.", "ClubsView"],
          ["You're offline. Reconnect to load this club.", "ClubDetailView"],
          ["This club no longer exists.", "ClubDetailView"],
          ["Vote failed + Please try again.", "ClubDetailView"],
          ["Deletion failed", "ProfileView"],
        ]}
      />

      <H2>Intentional NOTE rows (not full quotes)</H2>
      <Text size="small" tone="secondary">
        Staged-flag rows (“Personalized/realm OFF”, “Streaming filters OFF”, “rag_assist”) describe
        product state, not a single UI string. Leave confirm / ownership transfer copy stays
        summarized — multi-branch alert text.
      </Text>

      <Divider />
      <Text size="small" tone="secondary">
        Map 3 file patched: kuro-user-journeys.canvas.tsx. Sister: kuro-schema-crossref ·
        kuro-ecosystem-flows
      </Text>
    </Stack>
  );
}
