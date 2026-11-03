# Discover usability: "Every touch answers. And the issue ends." (binding spec)

**Date:** 2026-11-04
**Branch:** `kuro/discover-usability`, created from `kuro/details-songs-platform` at 56d7239. Local only; not pushed.
**Status:** binding for the data lane (C), the two UI lanes (A: the Discover page; B: preview, See all and mood journeys) and their integrator. CLAUDE.md Rule 6 points here.

**Owner request (2026-11-03):** "The Discover page has to be made more usable for users and more satisfying to interact with — think about UI patterns, rules, and where most people are lost." Then: "go ahead with the Discover plan".

**Inputs, in order of authority:**
1. The approved plan: where people get lost, the Discover contract R1–R8, and build items 1–12.
2. The shipped daily issue (`docs/superpowers/specs/2026-11-03-discover-clubs-redesign-design.md`, cited as **DC§n**) and the code on 56d7239.
3. Home's grammar (`docs/discover-clubs-2026-11-03/understand/HOME_GRAMMAR.md`, cited as **G§n**).
4. The navigation contract (`docs/superpowers/specs/2026-11-02-navigation-contract-design.md`, N1–N11, H1–H4, F1–F3).

**Design record:**
- Judging: `docs/discover-usability-2026-11-04/design/JUDGING.md`. Tactile scored 8.35 and Guided 7.73.
- Final mockup: `docs/discover-usability-2026-11-04/design/final.html`. These are Tactile's frames, plus a box of binding differences.
- The candidates `guided.html` and `tactile.html` stay in the same folder as the record.

> **Precedence.** This spec beats `final.html`, and `final.html`'s "differences" box beats its drawn frames. When this spec and the shipped code disagree on a measured value, the shipped constant wins and the lane notes it. DC§ rules that this spec does not change stay in force.

---

## 1. Where people get lost (observed in the live build) → what fixes it

| # | Problem | Fixed by |
|---|---|---|
| U1 | The same series repeats: Attack on Titan in both New to you and Essential anime; two Demon Slayer entries side by side. | R2, item 1 |
| U2 | There is no way to say "not for me" or "seen it". | R5, items 2–3 |
| U3 | Section purposes and filter words are unclear (Trending "Short · Long · Finished"). | R1, R6, item 6 |
| U4 | "In this issue" reads as tags, not jump links. | item 10 |
| U5 | Good sections are hidden behind "Show 8 more sections". | R7, item 7 |
| U6 | See all is a dead-end grid: no sort, no filters, no Plan. | R3, R6, item 5 |
| U7 | The page has no end. | R7, item 7 |
| U8 | All mixes anime and manga without labels. | item 11 |

---

## 2. The Discover contract (R1–R8)

The rule text is quoted verbatim from the approved plan. Notes give the reading this spec locks in. The acceptance tests are what the integrator proves, using pure tests, snapshot renders and UI tests (§15).

**R1: one question per section, stated in its subtitle; personal sections say why ("Because you finished X").**
- Reading:
  - Every section heading has a one-line purpose under it (§8, "Purpose").
  - The page's personal section uses the existing truthful title, "Because you loved {X}." (`EditorialDiscoverRoute.title(german:reason:)`, from `reason_title`).
  - The "Like {title}" mood journey says "Because you finished {title}." There the seed really is a finished title (D9).
- Acceptance:
  - Every section rendered on All, Anime and Manga has exactly one purpose line, of 1–2 lines.
  - A personal section's title or eyebrow names its reason.
  - Test: `DiscoverIssueTests.everySectionHasPurpose` covers all section ids in both languages.

**R2: never the same series twice on one page (franchise-level dedupe across sections; titles already on your list hidden or clearly marked — lead decision: hide in personal/new sections, mark with the status word in essentials/trending).**
- Reading:
  - One dedupe pass per page build, in the claim order of D5.
  - **Hidden** when owned: New to you, Because you loved…, Manga new to you, mood journeys.
  - **Marked** with the status word when owned: the cover story, Essentials, This season, Trending, Classics, Tonight's shelf, Hidden gem, and See all lists.
- Acceptance:
  - `DiscoverPagePolicyTests` covers:
    - no franchise key appears in two sections, or twice in one section
    - the claim order
    - Essentials keeps its canon
    - owned titles are hidden or marked per section
  - The after render of the All fixture shows no repeated franchise.

**R3: every card = one tap (open) + one quick action (Plan), everything else in a long-press menu.**
- Reading:
  - "Every card" means:
    - the cover story
    - the feature, the trio, rail and index rows
    - glance rows that are titles
    - See all rows and mood-journey rows
  - The Plan key is `TastePlanKey`, under the cover and never on the artwork. This reverses DC§6.2 "no key on the trio".
- Acceptance:
  - A UI test long-presses one card per grammar and finds the five menu items.
  - Each card exposes exactly one Plan key, plus the open action (VoiceOver: one element plus the key element).

**R4: every quick action gives instant feedback (haptic + stamp, KuroMotion) and an Undo.**
- Reading:
  - Every quick action answers in two beats (D6).
  - Undo comes from the toast, for Plan, Not interested and Seen it.
- Acceptance:
  - `DiscoverFeedbackTests` checks the toast for each action, and that Undo reverses exactly once and only for the same account.
  - The snapshot shows the planned key with its stamp.

**R5: feedback changes the page: Not interested / Seen it remove the title immediately and teach Taste.**
- Reading:
  - The title leaves the page model before any network call.
  - Not interested sends `.skip`; Seen it sends `.known`; Undo sends `.retract` (D2).
  - Hidden titles stay hidden across launches (D4).
- Acceptance:
  - After `hide`, the section's next render lacks the title and is refilled from the section's reserve.
  - After a relaunch (a new `DiscoverHiddenTitles` over the same storage), the title is still hidden.
  - `TasteStore.submitSignal` was called with the mapped action.

**R6: filters visible and local with plain words ("Under 13 episodes", "Finished") and a clear selected state, never resetting the page.**
- Reading:
  - The words follow the shipped rules: short is ≤ 13 episodes, so the chip says "Up to 13 episodes"; long is > 50 episodes, so it says "Over 50 episodes" (D10).
  - Selected chips use the ink fill with a ✓. Unselected chips use the hairline face.
  - Changing a filter keeps the scroll offset of everything above the filtered list.
- Acceptance:
  - A filter test asserts the scroll offset above the section is unchanged and the issue segment is unchanged.
  - The words in §8 are copied exactly.

**R7: the page ends: about 6 sections then "You're caught up for today" with Browse + Search.**
- Reading:
  - At most 6 sections, by the deterministic cap in D7. The fold is removed.
  - The end block holds the tally, Browse, Search, and More lists.
- Acceptance:
  - `DiscoverIssueTests.capAndMoreLists` covers All, Anime and Manga with flags on and off.
  - The render shows the end block.
  - `kuro_discover_show_more` and the Discover fold are no longer read.

**R8: place respected (scroll + segment kept; navigation contract).**
- Reading:
  - The scroll offset and the issue segment survive a journey and come back unchanged.
  - Removals and refills never move content above the viewport.
  - Journeys and tools follow N1–N11.
- Acceptance: a UI test runs Discover → title → ✕ and checks that the offset and segment are unchanged. A hide while scrolled keeps the first visible section's offset.

---

## 3. Decisions (D1–D18)

| # | Decision | Why |
|---|---|---|
| D1 | **Base: Tactile.** Grafts are listed in JUDGING.md. | Highest weighted score. It is the only direction that meets R3 on every card. |
| D2 | **Signals.** Not interested → `TasteStore.submitSignal(mediaType:mediaId:action: .skip)`. Seen it → `.known`. Undo → `.retract`. `.pass` is **not** used. | `pass` is stored at strength 0.00 and excluded from the recompute (`20260731090000_taste_deck_pass_memory.sql`), so it teaches nothing. `skip` is −0.45, the deck's own "NOT FOR ME" (`TasteDeckView.swift:450`). `known` is +0.25. `retract` deletes the user's signal row for that title. **Accepted:** if the title had an earlier love, skip replaces it (one signal per user and title), and Undo removes the signal rather than restoring the love. Discover titles are unseen titles, so this case is rare. |
| D3 | **Personal title wording.** The page keeps "Because you loved {X}." (the existing route title). "Because you finished X" is used only where it is true: the "Like {title}" mood journey (D9). | Nothing stores a "finished" seed for `fetch_because_you_rail`; `reason_title` is the top positive seed. |
| D4 | **Hidden memory.** `DiscoverHiddenTitles` (data lane) keeps a per-account, on-device list that hides a title instantly and across launches. A prepared RPC hydrates it from the server's `deck_skip` / `deck_known` rows, so other devices agree. Prepared server exclusions keep sections full once they are deployed (§10). Until deployment, the client hides and the sections simply get shorter. | The server hides nothing today: `discover_bundle` never reads `taste_signal_events`. |
| D5 | **Claim order for dedupe.** The cover story first, then Essentials (the fixed canon), then the remaining sections in page order. A section that loses a title to an earlier claim shows its next unclaimed item. Claims are computed **once per page build** (first load, pull to refresh, issue change, a new visit). A hide only removes the title and refills from **the same section's** reserve. Claims never move between sections mid-visit (R8). | Essentials is a canon list with a progress hook, so it must not lose titles to New to you. Stable claims mean a hide never re-lays out other sections. |
| D6 | **Two-beat feedback.** Beat 1 (0 ms): the haptic and the visual state change. Beat 2, after the durable result: `.kuroConfirmStamp` + `.sensoryFeedback(.success)` + toast. On failure: `.kuroRestore` + `.sensoryFeedback(.warning)` + "Not saved. Your list is unchanged." Hides finish beat 2 at once, because the local hide is the durable result and the signal goes through the outbox. | Home grammar rule 8: the stamp plays only after a durable save. |
| D7 | **Section cap.** The candidates, in order, are given below. At most **6** are shown. While there are more than 6, drop from the end in this order: Classics, then Manga new to you, then Hidden gem, then Tonight's shelf. Every dropped section, and the D17 fold sections, appear as **More lists** links in the end block. No content becomes unreachable. | R7. Deterministic and testable. Both realm flags are at 0% live, so the live All page is the six base sections. |
| D8 | **The Airing-today glance moves into This season,** as that section's first block (All and Anime). The top of the page keeps only the opening row, the switch, the moods, the cover story and the contents. | Keeps the first screen short, and the glance sits next to the airing titles. |
| D9 | **Moods.** The four keys are Something short · Cozy · Intense · Like {title}. Short, Cozy and Intense read the live editorial rails through `curated_rail_cards`: `short_one_season_{anime\|manga}`, `cozy_comfort_{…}`, `dark_serious_{…}`. "Like {title}" uses the Library entry with status Completed and the highest rating ≥ 8, most recently updated (else the latest Completed), and `RecommendationsReader.fetchSimilar(kind:id:limit:)`. With no Completed entry, that key is not shown. | Existing data only, so no realm RPC is needed. `curated_rail_cards` is granted to `authenticated` and excludes the caller's list (`20260205231000_curated_rails.sql:62-189`). Each rail has about 120–170 items. |
| D10 | **Filter words** live in Discover's own copy enum, not in `DiscoverRailFilter`, whose labels stay as they are for Entities (`EntityRefineWords`). The refine words are Any length · Up to 13 episodes · Over 50 episodes · Finished (DE "Jede Länge · Bis 13 Folgen · Über 50 Folgen · Fertig erschienen"). | "Abgeschlossen" is also the Completed status word, and the ≤ 13 / > 50 rules are shipped. |
| D11 | **Preview.** The preview uses `.contextMenu(menuItems:preview:)`. Tapping the lifted preview only dismisses it; **Open** is the last menu item. | SwiftUI has no preview-commit action. |
| D12 | **One toast slot per page.** The plan toast (`TastePlanController`) and the feedback toast (`DiscoverFeedbackController`) never show together: showing one dismisses the other. | Tactile's "one toast at a time" constraint. |
| D13 | **Seen it never writes a status.** Its toast offers "Add as Completed ›". That opens the tracking editor route, preset to Completed, through an additive `TrackingEditorRequest.initialStatus`. The user saves or cancels there (N7). | Approved plan item 3. |
| D14 | **Franchise key.** It is the server's `media_franchise_components.component_label`, same type only, read through a prepared RPC (§10). Until that RPC exists, the fallback is `DiscoverFranchiseKey.fallback(kind:titles:)`, a conservative title stem; failing that, the id. Anime and manga are **not** merged into one franchise on All (owner choice O3). | No client-readable key exists: the table has no client grants, `SeriesGrouping` is a decision function, and the cards carry no field. Same-type components are the only real data. |
| D15 | **Trending copy never says "on Kuro".** | The source is AniList's `trending` value (`mv_anime_trending`), not Kuro activity. |
| D16 | **Not interested is franchise-wide on Discover.** The signal goes for the one title; the local entry stores its franchise key, and every Discover surface hides that key. **Seen it is title-only**, so a later season can still appear. | "Not for me" is about the story. "Seen it" is about one title. |
| D17 | **The fold is retired.** `DiscoverIssueSections.fold` becomes the More-lists source. `DiscoverFoldButton` and the `KuroFoldMemory` key `discover/more` are no longer used by the page. The details-songs §14.2 rule (Essential manga first in the fold) becomes "Essential manga is the first More-lists link on All". | R7. |
| D18 | **Visits.** A visit starts when Discover becomes the current pager page after at least 30 minutes away, or on a new launch. It ends when Discover stops being current or the app goes to the background. NEW markers compare against the snapshot from the previous visit. The first visit ever shows no markers. | Item 8. Simple and on-device. |

**Cap candidates (D7), in this order:**

| Issue | Candidates |
|---|---|
| All | personal (Because you loved… else New to you) · Tonight's shelf* · This season · Essential anime · Hidden gem* · Manga new to you · Trending · Classics |
| Anime | New to you · Tonight's shelf* · This season · Essential anime · Hidden gem* · Trending · Classics |
| Manga | Manga new to you · Essential manga · Hidden gem* (manga) · Trending manga · Manga classics |

\* Shown only when the flag is on and the section has content, as today.

**More lists:**

| Issue | Links |
|---|---|
| All | Essential manga · Top rated · Just added, plus any section dropped by the cap |
| Anime | Top rated · Just added, plus any dropped |
| Manga | Top rated manga · Manga just added, plus any dropped |

---

## 4. Page anatomy at 390 pt (column 350)

Spacing values are DC§6.1's. Only new blocks get new values; every new literal goes in `DiscoverIssueLayout`.

| # | Block | Above | Notes |
|---|---|---|---|
| 0 | Offline band (offline with content) | 7 | DC§6.4 |
| 1 | Opening row | 7 | DC§6.2.1 |
| 2 | Issue switch | 6 | DC§6.2.2 |
| 3 | **Mood keys** | 12 | §5.4 |
| 4 | Cover story | 12 | DC§6.2.3. Gains the ANIME / MANGA kicker on All (§5.11). Owned → status word on the key. |
| 5 | **Contents** (jump list) + Browse row | 12 | §5.10 |
| 6–11 | Sections, ≤ 6, in cap order | 28 / 32 | §5.6 per section |
| 12 | **End block** | 32 | §5.7 |
| 13 | `HomeFooter` | 28 | |
| — | **Pinned index** (overlay under the header) | — | §5.10 |

**Section forms:**

| Section | Form |
|---|---|
| Because you loved… / New to you / Manga new to you (Manga issue) | `DiscoverFeatureTrio`: feature + 3. The trio gains Plan keys. |
| This season | The airing glance (D8), then a 3-cover trio row without a feature, then See all |
| Essential anime / Essential manga | `DiscoverIndexRow` × 5 + the progress hook |
| Manga new to you (All) | A rail (DC§14.2) with Plan keys |
| Trending / Trending manga | A rail with the refine row |
| Classics / Manga classics | `DiscoverIndexRow` × 5 |
| Tonight's shelf* | A rail |
| Hidden gem* | Cover-story grammar (DC§6.1 row 9) |

Measured target: the All page at 390 is ≤ 2,300 pt in the after render, end block included. The old fold no longer hides anything.

---

## 5. Build items

### 5.1 Item 1: franchise dedupe and the owned-title rule (data lane C pure policy; lane A applies it)

- `DiscoverPagePolicy.dedupe(lead:sections:)` is pure, `nonisolated`, and lives in `Kuro/Discovery/DiscoverPagePolicy.swift` (§11). It applies:
  - the D5 claim order
  - D14 keys
  - within-section dedupe (the first occurrence wins)
  - removal of hidden keys, including D16 franchise hides
  - the per-section owned rule (R2)
- Each section asks for `shown + reserve` items. It shows its count (trio 4, index 5, rail ≤ 10) and keeps up to 6 unclaimed items behind them as the refill reserve.
- **Status word** on owned titles in "mark" sections:
  - The Plan key's existing state shows "Planned" or "On your list" (`TastePageCopy.planLabel`).
  - Index rows also show the Folio status word on the meta line: "Watching · Ep 5" / "Schaue · F. 5", "Completed" / "Abgeschlossen". These are the existing `ListStatus` display words via the Folio copy helper.
- The "See all {n}" counts on the page count only the titles the page would show after dedupe and hiding.

### 5.2 Item 2: long-press preview (lane B builds; lanes A and B apply it)

- `.discoverTitleMenu(_ item: DiscoverMenuItem)`, a view modifier in `Kuro/Views/Discover/Preview/DiscoverTitleMenu.swift`. Its API is in §11.
- **Preview view** (`DiscoverTitlePreview`): 300 pt wide, radius 14.
  - Artwork: the banner at 2.2:1, or the cover at 2:3 capped at 260 pt tall. `HomeInk.posterFill` behind it.
  - Foot on the title's `ArtworkMaterial` (`base → deep`, white text ≥ 7:1):
    - kicker 8 pt tracked 1.05: "ANIME · NEW TO YOU"
    - title 17 semibold −0.35
    - facts 10 pt: "{year} · {format} · {n} eps · {status word}", skipping missing parts
    - synopsis 12 pt, 3 lines
    - a 1 pt white @ .14 rule
    - "Why it's here: {reason}" at 10 pt
  - The synopsis comes from `CatalogStore.fetchAnimeById` / `fetchMangaById`. It is cached, and it warms the detail page. While it loads, the synopsis area shows `KuroScrubLine(tint: .white.opacity(0.5), track: .white.opacity(0.12))` on the material. `KuroSkeleton.Kind` has no line kind, so none is added. If there is no synopsis, the area collapses.
  - The reason comes from the section (§8, "Why it's here").
- **Menu**, in fixed order, with SF Symbols. Nothing is drawn destructive (red is kept for delete and leave):
  1. The Plan item, which mirrors `TastePlanAction` (symbol `bookmark`):
     - `.plan`: "Plan to watch" / "Plan to read" / "Vormerken"
     - `.unplan`: "Remove from Planned" / "Aus Geplant entfernen"
     - `.edit`: "Edit list entry" / "Listeneintrag bearbeiten"
  2. "Seen it" / "Schon gesehen" (manga: "Already read" / "Schon gelesen"), symbol `eye`. Subtitle: "Hides it here. You can add it as Completed." / "Blendet es hier aus. Du kannst es als abgeschlossen eintragen."
  3. "Not interested" / "Kein Interesse", symbol `nosign`. Subtitle: "Hides it and shows fewer like it." / "Blendet es aus und zeigt weniger davon."
  4. "Add to club…" / "Zu einem Club hinzufügen…" (existing), symbol `person.2`. Shown only when the viewer is in a club.
  5. "Open" / "Öffnen", symbol `arrow.up.forward`.
- Items 2 and 3 are hidden when the title is on the viewer's list, or when there is no session.
- **Haptics:** the system lift haptic, plus `.impact(.rigid)` when a hide is chosen.
- **Routes:** Plan goes through the page's `TastePlanController` (environment). Add to club → `routes.presentAddToClub`. Open → `routes.openMedia`. "Add as Completed" → `routes.presentTrackingEditor`. Every route is read from `\.kuroRoutes`, so the pager tap gate applies on pager pages.
- **VoiceOver:** every card also gets `.accessibilityAction(named:)` for Plan, Seen it, Not interested and Add to club, so nothing depends on a long press. A hide announces "Hidden. Undo available." / "Ausgeblendet. Rückgängig möglich."
- **Where it applies:**
  - Discover's cover story, feature, trio, rail, index and glance-title rows (lane A)
  - See all rows and mood-journey rows (lane B)
  - `DiscoverFrameMenu` stays unchanged for Search and `GridAnimeCard`.

### 5.3 Item 3: Not interested / Seen it (data lane C owner; lane B menu and toast)

1. The menu calls `hidden.hide(key, reason: .notInterested | .seen, franchise:)`. That updates local state and storage at once, then calls `taste.submitSignal(…, action: .skip | .known)`.
2. The page model drops the title, or its whole franchise for Not interested (D16). The card shrinks to 0.9 and fades over `KuroMotion.contact` (120 ms). The gap closes over `KuroMotion.settle` (220 ms). The refill enters with `.homeEntrance()`. Under Reduce Motion or Low Power the card cross-fades out and the gap closes instantly.
3. The feedback toast appears (§8): message + optional action + "Undo" + ×. It holds 4 s, or waits under assistive technology (`KuroToastHold`).
4. Undo → `hidden.undo(receipt)`: the local entry goes, `.retract` is sent, and the title goes back into its slot with `.kuroRestore`. The toast says "Undone."
5. Seen it's action "Add as Completed ›" → `routes.presentTrackingEditor(TrackingEditorRequest(media:, initialStatus: .completed))`. It returns to the page (N7). Nothing is saved until the user taps Save there.
6. If `submitSignal` returns nil (no session), the menu items are not shown. Outbox failures are retried by `TasteStore`, and the local hide stays.

### 5.4 Item 4: mood entry points (lane A keys; lane B journey; data lane C fetch)

**Keys** (`DiscoverMoodKeys`, lane A):
- A 2 × 2 grid with 10 pt gaps, each key 56 pt tall, built from the `KuroKeyFace(.light)` recipe. They press with `HomeContactStyle` and a light haptic.
- Each key has a 15 pt SF Symbol: `timer`, `cup.and.saucer`, `bolt`, `heart`. Then a 13 pt medium label and a 10 pt `kuroMuted` subtitle (§8).
- Eyebrow: "IN THE MOOD FOR" / "LUST AUF" (9/1.05).
- Medium follows the issue: All and Anime use the anime rails, and the journey opens on Anime. Manga uses the manga rails and the manga subtitles.
- When "Like {title}" is unavailable, three keys show: the grid's last cell is empty and the grid keeps its shape.
- At accessibility sizes, or a column ≤ 328 with long German labels, the grid becomes one column.

**Journey** (`DiscoverMoodPage`, lane B). It is a journey root (✕ only, N3), opened with `routes.openPage(.page(AnyJourneyPage(id: "discover:mood:\(mood)", title:)))`. From top to bottom:
1. The mood switch row: the four mood words in `DiscoverRefineRow` grammar. The current one is selected. Switching replaces the content in place, with no push.
2. The page heading: "{Mood}." with the purpose line (§8). For Like: the eyebrow "BECAUSE YOU FINISHED {TITLE}".
3. An Anime · Manga word pair (no All, because each rail is per medium).
4. Chips: "Films" · "Series" (format, from the row), and "Up to 13 episodes" (anime, once episode counts are hydrated).
5. Rows in `DiscoverIndexRow` grammar with Plan keys and the preview. The first row may be drawn as the feature ("Start here" / "Fang hier an").
6. The end line: "That's all {n}." / "Das sind alle {n}."

**Data:**
- `DiscoveryStore.fetchMood(_:kind:)` returns the curated rows, with the caller's list already excluded.
- The client also removes hidden keys and franchise duplicates, then hydrates display fields (episodes, large cover) through `CatalogStore.fetchAnimeByIdsPreservingOrder` / `fetchMangaByIdsPreservingOrder`.
- There is no paging; the rail caps the list at 120.

**Empty:** a `HomeQuietCard` with "Nothing {mood} left that you haven't seen." / "Nichts {Stimmung} mehr, das du noch nicht kennst.". When a chip is on, it is followed by a "Clear filters" ink-rule link.

**Failed / offline:** `KuroStateView(.failed/.offline, layout: .inline)` with the ink-rule retry.

### 5.5 Item 5: a real See all page (lane B)

`DiscoverSeeAllPage(source:)` replaces `DiscoverFullSectionSheet`. The page is a journey root with `.kuroJourneyChrome` and the H1 collapse, as today, on the warm canvas. From top to bottom:
1. **Heading:** the 24 pt title + the purpose line + "{n} titles" (`kuroMuted`).
2. **Sort row** (`DiscoverRefineRow` grammar, with the label "Sort" / "Sortieren" for VoiceOver):
   - **Bounded lists** (Essentials, Classics, New to you, Because you…, Manga new to you, This season, Airing today, Tonight's shelf): "{Own order}" · Popular · Newest · Top rated, all local.
     - The own-order word is "Our order" / "Unsere Reihenfolge" for curated lists, "For you" / "Für dich" for personal lists, and "Airing" / "Läuft" for This season and Airing today.
     - "Newest" sorts by release year, newest first.
   - **Catalogue lists** (Trending, Top rated, Just added and their manga twins): Trending · Popular · Top rated · Just added. Each maps to `DiscoveryStore.BrowseSort` (`trending`, `popular`, `topRated`, `newlyAdded`). The section's own sort is selected first.
3. **Chips** (a wrapping `FlowLayout`, 6 × 8 gaps; each chip is at least 44 pt tall in hit area, 30 pt drawn). Groups are separated by a 1 pt `kuroHairline`:
   - Format (anime): TV · Film
   - Length (anime): Up to 13 episodes · Over 50 episodes
   - Status: Finished · Airing (anime) / Ongoing (manga, "Läuft")
   - Hide my list
4. **Chip faces:**
   - Selected: an ink fill `kuroInk`, white 12 pt medium text, and a leading ✓.
   - Unselected: `HomeInk.glanceFill` with a 1 pt `HomeInk.glanceBorder` and ink text.
   - Chips in one group are exclusive. "Hide my list" is independent.
5. **Match line:** "{n} match · Clear filters" / "{n} Treffer · Filter löschen", shown when any chip is on.
6. **Rows:** `DiscoverIndexRow` grammar, without numbers, with Plan keys, the status word when owned, and the preview. Tapping a row pushes the title inside this journey (N9, N5).
7. **Paging:**
   - Catalogue lists page with `KuroLoadMoreSentinel` through `DiscoveryStore.browseAnimePage` / `fetchBrowseMangaPageKeyset`, keyset by the sort, 30 per page.
   - The chips map to Browse parameters:
     - Up to 13 → `maxEpisodes: 13`
     - Over 50 → `minEpisodes: 51`
     - Finished → `status: "FINISHED"`
     - Airing → `status: "RELEASING"`
     - TV → `format: "TV"`
     - Film → `format: "MOVIE"`
   - The footer shows `KuroBusyMark` + "Loading more" / "Lädt weitere" while a page loads.
   - Bounded lists end with "That's all {n}." / "Das sind alle {n}."
8. **Filtering never resets the page.** The heading and chips stay put; only the list below them changes. A changed catalogue query restarts paging from the first page and keeps the scroll offset at the chips.
9. **Empty:** "Nothing matches these filters." / "Nichts passt zu diesen Filtern." + "Clear filters".
10. Hidden and franchise rules apply here too. Owned titles are marked; "Hide my list" hides them.
11. The free-text filter field (`DiscoverFilterField`) is removed from this page, because the chips replace it. The type stays in place for its other users.

### 5.6 Item 6: section purposes, reasons and clearer filter words (lane A)

**Heading** (`DiscoverPageHeading`, unchanged API): the title + a right summary slot.
- The summary slot shows the NEW marker when the section has new titles: "● {n} new since {weekday}". The ● is a 5 pt ink @ .7 dot.
- Otherwise the summary slot is empty. The DC§6.2 summaries ("Unseen by you · changes daily", …) are retired, and the purpose line replaces them.

**Purpose line:** 12 pt `kuroMuted`, at most 2 lines, 6 pt under the heading, 14 pt above the content (§8).

**Trending refine row:** the D10 words, in a wrapping layout so they never clip at 288. The selected word is ink with the 16 × 1.5 rule, as today. Changing it filters the rail in place (R6).

### 5.7 Item 7: the end state and no fold (lane A)

The end block (`DiscoverIssueEnd`), from top to bottom:
1. A 1 pt `kuroHairline`, then a 24 pt seal glyph: the `HomeFooter` wordmark style, at 30% ink. It fades in once per issue with `KuroMotion.playsMotionNow`.
2. "You're caught up for today." at 24 / −0.85.
3. The tally at 12 pt `kuroMuted`: "{s} sections, {t} titles." Then, only for parts above zero: "You planned {p}, hid {h} and marked {k} as seen." Then "A new issue tomorrow morning." These are session counts from the page (not persisted).
4. Link rows in Home's invitation grammar:
   - "EVERYTHING · Browse the catalogue →" (existing, `routes.openBrowse()`, only when `DiscoverBrowseEntry.isOffered`). It becomes the end of the contents block when Browse is not offered there.
   - "SOMETHING SPECIFIC · Search →" (opens the header Search sheet through the closure that `KuroMainView` passes in, gated by `pagerTapGate`).
5. "MORE LISTS" / "WEITERE LISTEN" (9/1.05), then a wrapping row of the More-lists names (13 pt medium + ›). Each opens its See all journey.

### 5.8 Item 8: "New since your last visit" (data lane C owner; lane A UI)

- `DiscoverVisitMemory` (§11) stores, per account and section, the item keys **seen in the last visit**. A section counts as seen when at least half of it was on screen.
- NEW = shown now, and absent from that section's last-visit snapshot. The first visit ever, or a section with no snapshot, shows no NEW.
- **The card mark** is a NEW / NEU tab in the season-tab face (`HomeInk.tabFace` #F3F4F4, text #26372C, 7 pt caps). It sits top-left on the cover, 6 pt in.
- The heading marker is described in §5.6.
- **Contents entries** show "{n} new" in place of the count when n > 0.
- **The pinned index** shows a 4 pt dot after the word.
- Markers stay for the whole visit and never blink. At visit end the snapshot is committed.
- Nothing goes to the server. `clearPrivateState()` deletes the account's file.

### 5.9 Item 9: the progress hook on Essentials (lane A)

- It sits under the purpose line, as a glance-card-face row (radius 8, 1 pt border, padding 10 / 12). Leading: "{k}/{n}" at 21 pt mono. Then the text: "You've seen {k} of {n}." / "{k} von {n} gesehen." (manga: "You've read…" / "gelesen").
- The second line is "{title} is under way." / "{Titel} läuft gerade." when one essential is Watching (Reading). Otherwise it is "{r} to go." / "Noch {r}.".
- **Segments** (n ≤ 12): 1 pt gaps, 3 pt tall. Completed and Seen-it titles fill in ink. A Watching title fills half. The rest are #D7D9D7. If n > 12, a single 3 pt bar replaces them.
- **Counting:**
  - k = curated items (the full bundle list for that section) whose `LibraryStore` status is Completed, plus those hidden as `.seen`.
  - n = the list count minus the titles hidden as Not interested.
- The hook shows only when k ≥ 1. VoiceOver reads "You've seen {k} of {n} essential anime".

### 5.10 Item 10: header tap to top, jump-link contents and the pinned index (lane A)

**Header:**
- `KuroHeaderNew` gains `var onTitleTap: (() -> Void)? = nil`. While `selection == .discover`, the centred section name becomes a `Button`.
  - VoiceOver label: "Discover. Scroll to top" / "Entdecken. Nach oben".
- Tapping it scrolls to the top with `KuroMotion.settle`, instantly under Reduce Motion. On other pages the header doesn't change.

**Contents** (`DiscoverContentsLine` restyled):
- The eyebrow "IN THIS ISSUE · {n} SECTIONS" + trailing "TAP TO JUMP" (9/1.05).
- Then a two-column grid of entries, one column at accessibility sizes or ≤ 328. Each entry is a 44 pt row:
  - "01" (11 pt medium mono `kuroMuted`)
  - the name (13 pt medium)
  - the trailing count or "{n} new" (10 pt)
  - "↓" (11 pt)
  - a 0.5 pt hairline under it
- VoiceOver: "Jump to {section}, {n} titles" / "Zu {Rubrik} springen, {n} Titel".
- Then the Browse row (DC§6.2.5).

**Pinned index** (`DiscoverPinnedIndex`):
- It appears once the contents block has scrolled under the header. It is a 38 pt band on the canvas with a bottom 0.5 pt `kuroHairline`, sitting directly under the header.
- It holds one line of short words, scrolling horizontally if needed:
  - EN: New · Season · Essentials · Manga · Trending · Classics
  - DE: Neu · Season · Kanon · Manga · Beliebt · Klassiker (§8)
- **States:**
  - The current section is ink, with the 28 × 2 `HomeInk.switchMark` under it, fading in place with no travel.
  - Passed sections are ink.
  - Sections ahead are `HomeInk.switchUnselected`.
  - A NEW dot follows the word when the section has NEW titles.
- Tapping a word scrolls to that section (settle).
- The band fades in and out over settle; it appears without a fade under Reduce Motion.
- The current section is computed from `onScrollGeometryChange` plus section frames in the scroll coordinate space.
- At accessibility sizes the band keeps 44 pt targets and scrolls horizontally.
- The scroll offset and issue segment are kept per session (R8). The issue already lives in `KuroMainView`. The scroll position uses `ScrollPosition` held in `KuroMainView`, the same way `discoverIssue` is.

### 5.11 Item 11: ANIME / MANGA labels on All (lane A, lane B for See all and mood rows on mixed lists)

- On the All issue only, every card shows a kicker "ANIME" / "MANGA" (identical in German): 8 pt, 1.05 tracking, uppercase, `kuroMuted`, 3 pt above the title, or first in the fact row of the cover story and feature.
- Single-medium issues and single-medium lists don't show it.
- VoiceOver prefixes the label "Anime: {title}" / "Manga: {title}" only on All.

### 5.12 Item 12: telemetry (lanes A and B call; nothing new in the owners)

All events go through `InteractionTelemetry.trackInteractionEvent(_:surface:result:extra:)`.
- `surface` is `"discover"`, `"discover_see_all"` or `"discover_mood"`.
- Payloads carry section ids, positions, medium, counts, and catalogue ids (`media_type`, `media_id`), following the existing `club_id` pattern. There are no titles, no free text and no new third party.
- `user_id` stays the auth UID that the owner already attaches.

| Event | `result` | `extra` |
|---|---|---|
| `discover_visit_end` | `ended` | `issue`, `sections_total`, `sections_reached`, `reached_end` (bool), `depth_pct` (0–100, 10-step), `taps`, `plans`, `hides`, `seen`, `dwell` (`lt10s` / `10to60s` / `1to5m` / `gt5m`) |
| `discover_open` | `opened` | `section`, `position`, `media_type`, `media_id`, `via` (`card` / `menu`) |
| `discover_plan` | `added` / `removed` / `failed` / `undone` | `section`, `position`, `media_type`, `media_id`, `via` (`key` / `menu`) |
| `discover_not_interested` | `hidden` / `undone` | `section`, `position`, `media_type`, `media_id` |
| `discover_seen` | `marked` / `completed_via_editor` / `undone` | `section`, `position`, `media_type`, `media_id` |
| `discover_preview` | `shown` | `section`, `media_type`, `media_id` |
| `discover_jump` | `contents` / `pinned` / `header_top` | `target` (section id) |
| `discover_mood_open` | `opened` / `empty` | `mood`, `medium`, `count` |
| `discover_see_all` | `opened` / `sorted` / `filtered` / `paged` | `section`, `sort`, `filters` (count), `pages` |
| `journey_close` (surface `journey`) | `closed` | `root_kind` (`anime` / `manga` / `club` / `page`), `media_id` (nil unless a title), `seconds` (rounded), `depth` |

**Open-and-bounce** is derived in analysis: a `discover_open` followed by a `journey_close` for the same `media_id` within 5 s. `journey_close` is the single additive event in `JourneyHost` (lane B), tracked on the root page's appear and disappear.

---

## 6. Interaction and navigation (every tap)

| Tap | Goes to | Rule |
|---|---|---|
| Header "Discover" (on Discover) | Scroll to top | item 10 |
| Issue word | Changes medium and canvas, as today. Rebuilds the claims (D5). | DC§6 |
| Mood key | `routes.openPage` → mood journey root (✕ only) | N3 |
| Cover story / feature / trio / rail / index card | `routes.openMedia` → title journey root | N9 |
| Plan key | `TastePlanController.tap`: plan / unplan + toast; tracked → the editor tool | N7, R4 |
| Long press | Preview + menu (§5.2) | R3 |
| Menu: Seen it / Not interested | Remove + toast (§5.3) | R5 |
| Toast: Add as Completed › | Tracking editor tool preset to Completed; it returns here | N7, D13 |
| Contents row / pinned word | Scroll to the section | item 10 |
| See all {n} › | See all journey (deduped by `DiscoverSeeAllPolicy.pageID`) | N5 |
| In See all or a mood journey: a row | Pushes the title inside the journey | N9 |
| Refine word / chip | Filters in place | R6 |
| Glance (This season) | The Airing-today See all journey | N5 |
| End: Browse / Search / More lists | `routes.openBrowse()` / the Search sheet / See all journey | N11 |

**The swipe-tap gate:** every route on the Discover page is read from `\.kuroRoutes`, which `KuroPagerTapGateModifier` already wraps. The Search closure from `KuroMainView` checks `pagerTapGate.isSuppressed` itself. **No horizontal swipe on cards is introduced.** A removal happens only through the menu or the VoiceOver actions. A new field added to `KuroRoutes` must also be added to `gated(by:)`; this spec adds none.

---

## 7. States

| State | Discover page | See all / mood journey |
|---|---|---|
| Loading | `DiscoverIssueSkeleton`, plus 4 mood-key blocks (56 pt) and a 3-row contents block | `KuroSkeleton(.row)` × 6 under the heading |
| Offline, with content | Band (DC§6.4). Hides and plans still work: the outbox and `LibraryActions` queue them. | `KuroOfflineView(hasContent: true)` band |
| Offline, first load | `KuroOfflineView` | same |
| Failed | `KuroErrorView` | `KuroStateView(.failed, layout: .inline)` |
| Empty section after hides | The section disappears from the page and the contents; the cap is **not** refilled mid-visit (R8) | — |
| Empty list | — | `HomeQuietCard` + "Clear filters" |
| Plan failure | "Not saved. Your list is unchanged." + `.kuroRestore` | same |
| Hide without a session | The menu items are absent | same |
| Paging failure | — | The footer shows "Couldn't load more. Try again →" / "Weitere konnten nicht geladen werden. Erneut versuchen →" |

The branded-state gate stays at 0 offenders, so no `ProgressView(` is used anywhere.

---

## 8. Copy (EN / DE)

- **EXISTING** means: reuse the shipped string exactly (grep it).
- **NEW** strings go into `DiscoverIssueCopy` (lane A), `DiscoverMenuCopy` (lane B, preview, menu and toasts) or `DiscoverSeeAllCopy` (lane B).
- Every string goes through `KuroLocale` or the `german ? :` helpers.

| Where | English | Deutsch | |
|---|---|---|---|
| Moods eyebrow | IN THE MOOD FOR | LUST AUF | NEW |
| Mood: short | Something short · Up to 13 eps, or a film (manga: Short and complete) | Etwas Kurzes · Bis 13 Folgen oder ein Film (Manga: Kurz und abgeschlossen) | NEW |
| Mood: cozy | Cozy · Slow, warm, gentle | Gemütlich · Ruhig, warm, sanft | NEW |
| Mood: intense | Intense · Dark and gripping | Intensiv · Düster und packend | NEW |
| Mood: like | Like {title} · Because you finished it | Wie {Titel} · Weil du es beendet hast | NEW |
| Mood purpose | Short and complete: our picks for an evening or a weekend. / Warm, low-stakes stories to unwind with. / Dark, serious stories that grip. / Close to {title} in tone and themes. | Kurz und abgeschlossen: unsere Auswahl für einen Abend oder ein Wochenende. / Warme, entspannte Geschichten zum Abschalten. / Düstere, ernste Geschichten, die packen. / Nah an {Titel} in Ton und Themen. | NEW |
| Mood eyebrow (like) | BECAUSE YOU FINISHED {TITLE} | WEIL DU {TITEL} BEENDET HAST | NEW |
| Mood journey | Start here · That's all {n}. · Nothing {mood} left that you haven't seen. | Fang hier an · Das sind alle {n}. · Nichts {Stimmung} mehr, das du noch nicht kennst. | NEW |
| Contents | IN THIS ISSUE · {n} SECTIONS · TAP TO JUMP · {n} new · Jump to {section}, {n} titles | IN DIESER AUSGABE · {n} RUBRIKEN · TIPPEN ZUM SPRINGEN · {n} neu · Zu {Rubrik} springen, {n} Titel | NEW |
| Pinned words | New · Season · Essentials · Manga · Trending · Classics · (Shelf · Gem when flagged) | Neu · Season · Kanon · Manga · Beliebt · Klassiker · (Regal · Juwel) | NEW. EN says "Essentials" to match the section name. DE says "Kanon" to match the shipped German summary "Der Kanon, in unserer Reihenfolge". |
| Purpose: New to you | Series you haven't seen. A new set each morning. | Serien, die du noch nicht kennst. Jeden Morgen neu. | NEW |
| Purpose: Because you | Picked from what you loved most. | Ausgewählt nach dem, was du am meisten mochtest. | NEW (title EXISTING) |
| Purpose: This season | Airing now. {n} new episodes out today. / What's airing this season. | Läuft gerade. Heute {n} neue Folgen. / Was diese Season läuft. | NEW |
| Purpose: Essentials | {n} titles to know anime by. Our order, not a ranking. / {n} manga to know the medium by. Our order, not a ranking. | {n} Titel, an denen man Anime kennt. Unsere Reihenfolge, kein Ranking. / {n} Manga, an denen man das Medium kennt. Unsere Reihenfolge, kein Ranking. | NEW |
| Purpose: Manga new to you | Manga you haven't read. A new set each morning. | Manga, die du noch nicht kennst. Jeden Morgen neu. | NEW |
| Purpose: Trending | What anime fans are watching right now. / What manga readers are reading right now. | Was Anime-Fans gerade schauen. / Was Manga-Fans gerade lesen. | NEW (D15) |
| Purpose: Classics | Older series still worth an evening. / Older manga still worth a read. | Ältere Serien, die einen Abend wert sind. / Ältere Manga, die sich noch lohnen. | NEW |
| Purpose: flagged | One mood for tonight, picked from your taste. / One title most people miss. | Eine Stimmung für heute Abend, nach deinem Geschmack. / Ein Titel, den die meisten übersehen. | NEW |
| Why it's here | Why it's here: {reason}. Reasons: unseen by you · in our canon · airing now · popular this week · a classic · close to {X} | Warum es hier ist: {Grund}. Gründe: noch nicht gesehen · in unserem Kanon · läuft gerade · diese Woche beliebt · ein Klassiker · nah an {X} | NEW |
| NEW markers | NEW · ● {n} new since {weekday} · ● {n} new since your last visit (> 6 days) | NEU · ● {n} neu seit {Wochentag} · ● {n} neu seit deinem letzten Besuch | NEW |
| Refine (Trending) | Any length · Up to 13 episodes · Over 50 episodes · Finished | Jede Länge · Bis 13 Folgen · Über 50 Folgen · Fertig erschienen | NEW (D10) |
| Kind kicker | ANIME · MANGA | ANIME · MANGA | NEW |
| Status words | Planned / On your list · Watching · Ep {n} · Completed | Geplant / Auf deiner Liste · Schaue · F. {n} · Abgeschlossen | EXISTING (`TastePageCopy.planLabel`, Folio words) |
| Progress hook | You've seen {k} of {n}. / You've read {k} of {n}. · {title} is under way. · {r} to go. | {k} von {n} gesehen. / {k} von {n} gelesen. · {Titel} läuft gerade. · Noch {r}. | NEW |
| Menu | Plan to watch / Plan to read / Remove from Planned / Edit list entry · Seen it / Already read · Not interested · Add to club… · Open | Vormerken / Aus Geplant entfernen / Listeneintrag bearbeiten · Schon gesehen / Schon gelesen · Kein Interesse · Zu einem Club hinzufügen… · Öffnen | "Vormerken", "Edit list entry", "Add to club…" EXISTING; rest NEW |
| Menu subtitles | Hides it here. You can add it as Completed. · Hides it and shows fewer like it. | Blendet es hier aus. Du kannst es als abgeschlossen eintragen. · Blendet es aus und zeigt weniger davon. | NEW |
| Toasts | Hidden. You'll see fewer like it. · Marked as seen. · Add as Completed › · Undo · Undone. · Added to your list. · Not saved. Your list is unchanged. | Ausgeblendet. Du siehst weniger davon. · Als gesehen markiert. · Als abgeschlossen eintragen › · Rückgängig · Rückgängig gemacht. · Zu deiner Liste hinzugefügt. · Nicht gespeichert. Deine Liste ist unverändert. | last four EXISTING (`TastePlanCopy`) |
| VoiceOver hide | Hidden. Undo available. | Ausgeblendet. Rückgängig möglich. | NEW |
| End | You're caught up for today. · {s} sections, {t} titles. · You planned {p}, hid {h} and marked {k} as seen. · A new issue tomorrow morning. · SOMETHING SPECIFIC · Search → · MORE LISTS | Für heute bist du durch. · {s} Rubriken, {t} Titel. · {p} vorgemerkt, {h} ausgeblendet, {k} als gesehen markiert. · Morgen früh kommt eine neue Ausgabe. · ETWAS BESTIMMTES · Suchen → · WEITERE LISTEN | NEW (Browse row EXISTING) |
| Header | Discover. Scroll to top | Entdecken. Nach oben | NEW |
| See all | Sort · Our order · For you · Airing · Popular · Newest · Top rated · Trending · Just added · TV · Film · Up to 13 episodes · Over 50 episodes · Finished · Airing · Ongoing · Hide my list · {n} match · Clear filters · That's all {n}. · Loading more · Nothing matches these filters. · Couldn't load more. Try again → | Sortieren · Unsere Reihenfolge · Für dich · Läuft · Beliebt · Neueste · Bestbewertet · Gerade beliebt · Neu hinzugefügt · TV · Film · Bis 13 Folgen · Über 50 Folgen · Fertig erschienen · Läuft · Läuft · Meine Liste ausblenden · {n} Treffer · Filter löschen · Das sind alle {n}. · Lädt weitere · Nichts passt zu diesen Filtern. · Weitere konnten nicht geladen werden. Erneut versuchen → | "Gerade beliebt", "Neu hinzugefügt" EXISTING |

**Dates:**
- Weekdays use the device locale through `KuroLocale` (`de_DE` / `en_GB`) and `Europe/Berlin`.
- Plurals follow the existing helper pattern ("1 title" / "{n} titles").

---

## 9. Data map

| UI | Source | Status |
|---|---|---|
| Sections, cards | `discover_bundle`, `fetch_because_you_rail`, `fetch_daily_feature`, flagged realm RPCs via `DiscoveryStore` / `DiscoverViewModel` | exists |
| Owned / status word | `LibraryStore.entry(for:)` | exists |
| Plan | `TastePlanController` + `LibraryActions` | exists |
| Not interested / Seen it / Undo | `TasteStore.submitSignal` → `record_taste_deck_signal` (`skip` / `known` / `retract`) | exists; new client wiring |
| Hidden across launches | `DiscoverHiddenTitles` (on-device, per account) | new, data lane |
| Hidden across devices | `fetch_my_discover_hidden_v1()` | **prepared** (§10) |
| Server-side exclusion (keeps sections full) | `discover_bundle` NTY pools, `fetch_personalized_new_to_you`, `curated_rail_cards` exclude `deck_skip` / `deck_known` | **prepared** (§10) |
| Franchise key | `fetch_media_franchise_keys_v1(p_media_type, p_ids)` → `media_franchise_components` | **prepared** (§10); title-stem fallback |
| Synopsis in the preview | `CatalogStore.fetchAnimeById` / `fetchMangaById` | exists |
| Moods: short / cozy / intense | `curated_rail_cards('{short_one_season\|cozy_comfort\|dark_serious}_{anime\|manga}', 120, true)` | exists live; new client call |
| Mood: like | `LibraryStore` entries → `CatalogStore` title → `RecommendationsReader.fetchSimilar` | exists |
| See all paging | `DiscoveryStore.browseAnimePage` / `fetchBrowseMangaPageKeyset` | exists |
| NEW markers | `DiscoverVisitMemory` (on-device) | new, data lane |
| Progress hook | Essentials list ∩ `LibraryStore` + hidden `.seen` | exists + new |
| Telemetry | `InteractionTelemetry` | exists |
| Tracking editor preset | `TrackingEditorRequest.initialStatus` (additive) | new, lane B |

Each RPC listed as "prepared" is called with the **silent-fallback** pattern of `ReleasesStore`. A missing function (PostgREST `PGRST202` / 404) marks it unavailable for the session, and the client carries on without it.

---

## 10. Prepared backend (data lane C; PREPARE ONLY)

**One file:** `supabase/prepared-migrations/20261104100000_discover_feedback_v1.sql`.
- Never apply, deploy, change a flag or write production.
- Every function uses `SET search_path = public, extensions`.
- Every function is `SECURITY DEFINER` and derives the user from `auth.uid()`, never from a parameter.
- Execute is granted to `authenticated` only.
- No new table is created, so no new RLS is needed.

1. **`fetch_my_discover_hidden_v1()`**
   - Returns `table(media_type text, media_id int, reason text, created_at timestamptz)`.
   - It reads the caller's `taste_signal_events` with `event_type in ('deck_skip', 'deck_known')`, as the latest row per title. `reason` is `not_interested` or `seen`.
   - Limit 2,000, newest first.
2. **`fetch_media_franchise_keys_v1(p_media_type text, p_ids int[])`**
   - Returns `table(media_id int, franchise_key text)`.
   - The key is `lower(p_media_type) || ':' || coalesce(c.component_label, m.id)::text`, from `media_franchise_components`. Titles with no row label as themselves, which is the table's own convention.
   - It caps `p_ids` at 400.
   - It is `STABLE` and returns catalogue data only.
3. **Exclusions.** Recreate these functions byte-identical to their latest definitions, except that their candidate filters gain `and not exists (select 1 from taste_signal_events e where e.user_id = auth.uid() and e.media_type = … and e.media_id = … and e.event_type in ('deck_skip', 'deck_known'))`:
   - the New-to-you pools in `discover_bundle` (latest: `20260326221000_discover_new_to_you_rotation.sql`)
   - `fetch_personalized_new_to_you` (`20260731012000`)
   - `curated_rail_cards` (`20260205231000`), only when `p_exclude_seen` is true
   Each change carries a header comment citing its source file and the exact diff.

**Local DB tests:**
- File: `supabase/tests/rls/discover_feedback_v1_test.sql`, run by `scripts/db/run_local_db_tests.sh --only discover_feedback_v1`.
- The tests cover:
  - A caller sees only their own hidden rows.
  - `anon` gets `permission denied`.
  - Franchise keys label two seasons of one component the same, and a singleton as itself.
  - The exclusion hides a skipped title from New to you and from `curated_rail_cards(…, true)`, but not from `(…, false)`.
- Add the file to `supabase/tests/pending_migrations.txt` the way the other prepared files are added.

**Account deletion:** `taste_signal_events.user_id` references `auth.users(id) on delete cascade` (`20260730160000_taste_signal_events_v1.sql:7`), so `delete-account` removes the server rows. On-device files are removed by `clearPrivateState()`, which the session funnel runs on sign-out, switch and deletion.

---

## 11. Interfaces (fixed signatures)

The data lane delivers these first. Lanes A and B code against them exactly. A lane that needs a change stops and reports it; it does not edit another lane's file.

```swift
// Kuro/Discovery/DiscoverFeedbackModels.swift  (lane C)
enum DiscoverHideReason: String, Codable, Sendable { case notInterested, seen }

struct DiscoverHideReceipt: Equatable, Sendable {
    let key: MediaKey
    let reason: DiscoverHideReason
    let franchiseKey: String?
    let account: AccountContext
}

/// The section ids used by visit memory, telemetry and the policy: `EditorialDiscoverRoute.id`,
/// plus "tonightShelf" and "hiddenGem".
typealias DiscoverSectionID = String

// Kuro/Discovery/DiscoverHiddenTitles.swift  (lane C)
@MainActor @Observable
final class DiscoverHiddenTitles: AccountScopedState {
    init(accountSession: AccountSessionCoordinator, taste: TasteStore,
         client: SupabaseClient?, storageDirectory: URL? = nil)   // nil storage = in-memory (tests)
    /// Hidden title keys (title-level hides, both reasons).
    private(set) var hiddenKeys: Set<MediaKey>
    /// Franchise keys hidden by Not interested (D16).
    private(set) var hiddenFranchises: Set<String>
    /// Keys hidden as Seen it (for the progress hook).
    private(set) var seenKeys: Set<MediaKey>
    func isHidden(_ key: MediaKey, franchiseKey: String?) -> Bool
    /// Hides at once (memory + file), then sends .skip / .known. nil without a session.
    @discardableResult
    func hide(_ key: MediaKey, reason: DiscoverHideReason, franchiseKey: String?) -> DiscoverHideReceipt?
    /// Reverses one hide for the same account only; sends .retract. Returns false if stale.
    @discardableResult
    func undo(_ receipt: DiscoverHideReceipt) -> Bool
    /// Merges the server's hidden rows (prepared RPC; silent no-op while it is absent).
    func hydrate() async
    func cancelAccountWork()
    func clearPrivateState()   // wipes memory + this account's file
}

// Kuro/Discovery/DiscoverVisitMemory.swift  (lane C)
@MainActor @Observable
final class DiscoverVisitMemory: AccountScopedState {
    init(accountSession: AccountSessionCoordinator, storageDirectory: URL? = nil,
         now: @escaping () -> Date = Date.init)
    /// D18: starts a visit when ≥ 30 min have passed since the last end (or first call this launch).
    func beginVisit()
    func endVisit()                                          // commits seen snapshots
    func newKeys(in section: DiscoverSectionID, shown: [MediaKey]) -> Set<MediaKey>
    func lastVisitDate(for section: DiscoverSectionID) -> Date?
    func markSeen(_ keys: [MediaKey], in section: DiscoverSectionID)
    func cancelAccountWork()
    func clearPrivateState()
}

// Kuro/Discovery/DiscoverPagePolicy.swift  (lane C; pure)
nonisolated enum DiscoverOwnedRule: Sendable { case hide, mark }

nonisolated struct DiscoverPolicyItem: Hashable, Sendable {
    let key: MediaKey
    let franchiseKey: String          // never empty: server key, fallback stem, or "kind:id"
}

nonisolated struct DiscoverPolicySection: Sendable {
    let id: DiscoverSectionID
    let items: [DiscoverPolicyItem]   // source order
    let owned: DiscoverOwnedRule
    let isCanon: Bool                 // Essentials: claims right after the lead (D5)
    let shown: Int                    // trio 4, index 5, rail 10
    let reserve: Int                  // default 6
}

nonisolated enum DiscoverPagePolicy {
    /// One build: returns per section the keys to show (≤ shown) followed by its reserve.
    static func build(lead: DiscoverPolicyItem?, sections: [DiscoverPolicySection],
                      owned: Set<MediaKey>, hiddenKeys: Set<MediaKey>,
                      hiddenFranchises: Set<String>) -> [DiscoverSectionID: [MediaKey]]
    /// After a hide: the section's keys minus the hidden one, refilled from its own reserve only.
    static func removing(_ key: MediaKey, franchiseKey: String?, from keys: [MediaKey],
                         franchiseOf: (MediaKey) -> String) -> [MediaKey]
}

nonisolated enum DiscoverFranchiseKey {
    /// Conservative stem: lower-cased (TextNormalization), cut at the first ":" or " - ", trailing
    /// season markers removed ("season 2", "2nd season", "part 2", "final season", "the movie",
    /// roman II–X, trailing digits). Empty stems fall back to "kind:id".
    static func fallback(kind: MediaKind, id: Int, titles: [String?]) -> String
}

// Kuro/Discovery/DiscoverMood.swift  (lane C)
enum DiscoverMood: String, CaseIterable, Sendable {
    case short, cozy, intense, like
    func railID(kind: MediaKind) -> String?                   // nil for .like
}

nonisolated enum DiscoverMoodSeed {
    /// D9: Completed, highest rating ≥ 8, most recently updated; else latest Completed; else nil.
    static func pick(_ entries: [LibraryEntry], kind: MediaKind) -> MediaKey?
}

// DiscoveryStore additions (lane C, in Kuro/Discovery/DiscoveryStore+Usability.swift)
struct DiscoverMoodRow: Identifiable, Decodable, Sendable {   // curated_rail_cards row shape
    let mediaType: String
    let mediaId: Int
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?
    let coverImageMedium: String?
    let averageScore: Int?
    let year: Int?
    let format: String?
    let status: String?
    let genres: [String]?
    var id: String { "\(mediaType)-\(mediaId)" }
}

extension DiscoveryStore {
    func fetchMood(_ mood: DiscoverMood, kind: MediaKind, limit: Int = 120) async -> [DiscoverMoodRow]?
    /// Prepared RPC; [:] while it is absent (silent fallback, remembered for the session).
    func franchiseKeys(kind: MediaKind, ids: [Int]) async -> [Int: String]
}
```

```swift
// Lane B public API used by lane A
// Kuro/Views/Discover/Preview/DiscoverTitleMenu.swift
struct DiscoverMenuItem {
    let card: TasteCard                  // the Plan key's card (media + key)
    let section: DiscoverSectionID
    let position: Int
    let reason: String?                  // "Why it's here" text (already localized)
    let franchiseKey: String?
    var onHidden: (DiscoverHideReceipt) -> Void = { _ in }  // the page's refill hook
}

extension View {
    /// Preview + the five-item menu + VoiceOver actions. Reads TastePlanController,
    /// DiscoverHiddenTitles, DiscoverFeedbackController, LibraryStore, ClubsStore and \.kuroRoutes
    /// from the environment.
    func discoverTitleMenu(_ item: DiscoverMenuItem) -> some View
}

// Kuro/Views/Discover/Preview/DiscoverFeedbackController.swift
@MainActor @Observable
final class DiscoverFeedbackController {
    struct Toast: Identifiable, Equatable { let id: UUID; let message: String; let action: Action?; let receipt: DiscoverHideReceipt? }
    enum Action: Equatable { case addAsCompleted(MediaKey) }
    private(set) var toast: Toast?
    func showHidden(_ receipt: DiscoverHideReceipt, german: Bool)
    func undo(hidden: DiscoverHiddenTitles, german: Bool)
    func dismiss()
}

extension View {
    /// The page-foot toast for both controllers (D12): shows one, dismisses the other.
    func discoverFeedbackHost(_ feedback: DiscoverFeedbackController, plans: TastePlanController) -> some View
}

// Kuro/Views/Discover/SeeAll/DiscoverSeeAllPage.swift
enum DiscoverSeeAllSource: Hashable {
    case route(EditorialDiscoverRoute)
}

struct DiscoverSeeAllPage: View {
    init(source: DiscoverSeeAllSource, title: String, purpose: String,
         animeItems: [AnimeCard], mangaItems: [MangaCard],
         airingSlots: [Int: DiscoverAiringSlot] = [:])
}

// Kuro/Views/Discover/Mood/DiscoverMoodPage.swift
struct DiscoverMoodPage: View {
    init(mood: DiscoverMood, kind: MediaKind)
}

/// Builds the journey page for a mood key (lane A calls it from the key).
enum DiscoverMoodRoute {
    static func page(_ mood: DiscoverMood, kind: MediaKind, german: Bool) -> AnyJourneyPage
}
```

**Registration (lane C):**
- `AppComposition` builds one `DiscoverHiddenTitles` and one `DiscoverVisitMemory` over the single client. It registers both in `makeAccountScopedStates`, after `TasteStore`, and injects them with `.environment(...)` in `KuroApp`.
- Test graphs (`testingGraph`) build them with `storageDirectory: nil`.
- `hydrate()` runs from `SessionController.bootstrapAfterAuth`, through the same post-bootstrap hook the other owners use; the data lane picks the existing hook.

**Storage (lane C):**
- Location: `Application Support/Kuro/Discover/`, as `hidden-<id>.json` and `visits-<id>.json`.
- `<id>` is the first 16 hex characters of the SHA-256 of the auth user id.
- Files are written atomically with `.completeUntilFirstUserAuthentication` and excluded from backup.
- Bounds: 2,000 hidden entries (the oldest are dropped first), and 120 keys per section snapshot. Only kinds and ids are stored; never titles.

---

## 12. Owner choices (recorded; defaults applied)

| # | Choice | Default |
|---|---|---|
| O1 | Plan keys on every card (R3) | Applied |
| O2 | Not interested hides the whole franchise on Discover (D16) | Applied |
| O3 | Anime and manga of one franchise count once on All | **Not applied**: no data source backs it (D14). It needs a prepared cross-type mapping later. |
| O4 | Essential manga leaves All and becomes the first More-lists link on All (as in the shipped details-songs §14.2) | Applied |
| O5 | The End tally shows what you did today | Applied |
| O6 | A hidden title can only be restored with Undo for now. A Profile "Hidden on Discover" list is a follow-up. | Recorded |
| O7 | Deploying the §10 SQL is a separate, explicit approval | Recorded |

---

## 13. File ownership (no overlap)

Each lane works in its own worktree on its own branch off `kuro/discover-usability`:
- `kuro/du-data` (C)
- `kuro/du-page` (A)
- `kuro/du-journeys` (B)

**Merge and build order: C → B → A.** C's first commit must carry every §11 signature with a working local-only implementation. A and B merge `kuro/du-data` into their branch before building, and again whenever C moves. A uses B's `discoverTitleMenu`, `DiscoverFeedbackController`, `DiscoverSeeAllPage` and `DiscoverMoodRoute` only through the §11 signatures. Until B lands, A keeps `DiscoverFrameMenu` behind one local function, `discoverMenu(for:)`, in `Views/Discover/DiscoverCardActions.swift`. The integrator swaps that function's body after merging B. The project uses synchronized groups, so **nobody edits `project.pbxproj`**.

### 13.1 Data lane C: owns

| File | Scope |
|---|---|
| `Kuro/Discovery/DiscoverFeedbackModels.swift`, `DiscoverHiddenTitles.swift`, `DiscoverVisitMemory.swift`, `DiscoverPagePolicy.swift`, `DiscoverMood.swift`, `DiscoveryStore+Usability.swift` (new) | §11 |
| `Kuro/Composition/AppComposition.swift` | Build, register and inject the two owners (one line each in `makeGraph`, `testingGraph` and `makeAccountScopedStates`) |
| `Kuro/KuroApp.swift` | `.environment(...)` for the two owners only |
| `Kuro/Identity/SessionController.swift` | Only the `hidden.hydrate()` call in the post-bootstrap hook |
| `supabase/prepared-migrations/20261104100000_discover_feedback_v1.sql`, `supabase/tests/rls/discover_feedback_v1_test.sql`, `supabase/tests/pending_migrations.txt` | §10 |
| `KuroTests/DiscoverPagePolicyTests.swift`, `DiscoverHiddenTitlesTests.swift`, `DiscoverVisitMemoryTests.swift`, `DiscoverMoodTests.swift` (new) | Pure and owner tests: claim order, franchise fallback, hide/undo/account switch, persistence across instances, `clearPrivateState`, visit 30-minute rule, mood seed |

### 13.2 Lane A, the Discover page: owns

| File | Scope |
|---|---|
| `Kuro/ContentView.swift` | **Only** these changes: `KuroHeaderNew.onTitleTap`; in `KuroMainView`, the Discover scroll-to-top tick, the Discover `ScrollPosition` and the gated Search closure passed to `EditorialDiscoverView`. Nothing else. |
| `Kuro/Views/EditorialDiscoverView.swift` | The page: moods, contents, pinned index, sections with dedupe, purposes, NEW, progress hook, the end block, the cap (`DiscoverIssueSections.main` / `fold` → cap + More lists), visit begin/end, telemetry. `fullSection(for:)` becomes a call to `DiscoverSeeAllPage` (§11). `DiscoverFullSectionSheet`, `FullSectionView` and `FullMangaSectionView` are deleted once `fullSection` no longer uses them; a grep shows no other users. `DiscoverFilterField` and `GenrePickerSheet` stay. |
| `Kuro/Views/EditorialDiscoverFrames.swift` | Discover-only types (`DiscoverRail` and the like) may change. `DiscoverFrame`, `DiscoverFrameMenu`, `DiscoverWordPicker`, `DiscoverPicture`, `DiscoverLayout`, `DiscoverBrowseEntry` and `DiscoverRailFilter` keep their API and labels. |
| `Kuro/Views/Discover/*` (existing files) | `DiscoverContents`, `DiscoverCoverStory`, `DiscoverFeatureTrio` (Plan keys), `DiscoverIndexRow` (status word), `DiscoverRefineRow` (D10 words), `DiscoverIssueCopy`, `DiscoverIssueLayout`, `DiscoverIssueSkeleton`, `DiscoverPageHeading`, `DiscoverGlanceCard`, `DiscoverIssueSwitch` |
| `Kuro/Views/Discover/` (new) | `DiscoverMoodKeys.swift`, `DiscoverPinnedIndex.swift`, `DiscoverIssueEnd.swift`, `DiscoverProgressHook.swift`, `DiscoverNewMarker.swift`, `DiscoverCardActions.swift` |
| `Kuro/Views/EditorialDiscoverRouting.swift`, `Kuro/Views/DiscoverViewModel.swift` | Purposes, short words and read-model shaping |
| `KuroTests/DCdiscoverTests.swift`, `DiscoverLaneTests.swift` | Update the section and fold expectations that the cap changes |
| `KuroTests/DiscoverIssueTests.swift` | Cap/More lists, purposes, contents, pinned words, progress-hook counting, the end tally |
| `KuroTests/DiscoverUsabilitySnapshotTests.swift` (new) | Renders only into `docs/discover-usability-2026-11-04/after/` with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1` (JPEG q80, ≤ 603 px wide): All top, All scrolled (pinned + NEW), Essentials with hook, end block, Anime, Manga, SE 320, accessibility XL |

### 13.3 Lane B, the preview, See all and mood journeys: owns

| File | Scope |
|---|---|
| `Kuro/Views/Discover/Preview/` (new) | `DiscoverTitleMenu.swift`, `DiscoverTitlePreview.swift`, `DiscoverFeedbackController.swift`, `DiscoverFeedbackToastView.swift` (copies the `TastePlanToastView` anatomy: `#282f2bf5`, 12 pt white, radius 18, + one optional text action), `DiscoverMenuCopy.swift` |
| `Kuro/Views/Discover/SeeAll/` (new) | `DiscoverSeeAllPage.swift`, `DiscoverSeeAllChips.swift`, `DiscoverSeeAllCopy.swift` |
| `Kuro/Views/Discover/Mood/` (new) | `DiscoverMoodPage.swift`, `DiscoverMoodRoute` |
| `Kuro/Views/TastePicksView.swift` | **Additive only:** `TastePlanController.lastResult` (key, outcome, token), and `TastePlanKey(…, stampsOnConfirm: Bool = false)`, which plays `.kuroConfirmStamp` / `.kuroRestore` plus success/warning feedback on its key's result. Defaults keep Taste and Home pixel-identical: `HomeCompositionSnapshotTests` and the Taste suites must stay green without the write variable. Lane A passes `stampsOnConfirm: true` on Discover. |
| `Kuro/Views/Routing/KuroRoutes.swift` | **Additive only:** `TrackingEditorRequest.initialStatus: ListStatus? = nil` (memberwise default keeps every call site compiling). No other change. |
| `Kuro/Views/AddToListSheet.swift`, `Kuro/Views/TrackingDraft.swift` | When there is no entry and `initialStatus` is set, the draft starts at that status. The baseline stays `.planning`, so the N7 discard guard applies. |
| `Kuro/Views/Routing/JourneyHost.swift` | **Additive only:** the `journey_close` event (§5.12) |
| `KuroTests/DiscoverFeedbackTests.swift`, `DiscoverSeeAllTests.swift`, `DiscoverMoodPageTests.swift`, `DiscoverJourneySnapshotTests.swift` (new) | Toast slot rule, undo once / same account, chip → Browse parameter mapping, local sort order, the "That's all" end, mood empty state. Renders go only into `docs/discover-usability-2026-11-04/after/` (preview, Not-interested toast, Seen-it toast, See all with chips, mood journey). |
| `KuroUITests/DiscoverUsabilityUITests.swift` (new) | Long-press menu items; Not interested → gone → Undo → back; Discover → title → ✕ keeps the offset and segment (R8) |

### 13.4 Read-only for every lane

These files are read-only for all lanes. A lane that believes it needs a change stops and reports it.
- `Views/Home/*`
- `Views/Shared/*`
- `Kuro/Design/*`
- `Kuro/Taste/*`
- `Kuro/Library/*`
- `Packages/*`
- `KuroJourneyChrome.swift`
- other Routing files
- `SharedCards/*`
- `EditorialSearchView.swift`
- `Views/Entities/*`

### 13.5 Integrator only

- The `discoverMenu(for:)` swap, and merging C → B → A.
- `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, `MEMORY.md`, and the CLAUDE.md file map and counts. These are Rules 1 and 2, done once after all lanes. The docs-current-state gate is blocking, so lanes run individual gates only (§15).
- Committed PNGs outside `docs/discover-usability-2026-11-04/` are never rewritten. If a lane run rewrites one, revert it with `git checkout -- <file>`.

### 13.6 Lane rules (all three lanes)

**Builds and tests:**
- `CODE_SIGNING_ALLOWED=NO`
- `-parallel-testing-enabled NO`
- `-derivedDataPath /Users/max/.claude/jobs/1fb75ce2/tmp/<lane>/dd`

**Simulators:**
- Only simulators you create: `xcrun simctl create Kuro-Lane-du-<lane> "iPhone 17 Pro" <newest iOS runtime>`. Use them by UUID and delete them afterwards.
- `7FC4B58A-…` is for the integrator and fix agents only.

**Code:**
- `@Observable` only.
- No force unwraps.
- `print` only inside `#if DEBUG`.
- No SDK imports in views.
- Every string through `KuroLocale`.
- No `ProgressView(`.
- Widths come from the measured container.
- Tokens only: no colour that is not a `HomeInk` / `kuro*` token or a value quoted from Home with a "measured:" comment in `DiscoverIssueLayout`.

**Backend:** prepare only. Never push. Never print secrets.

**Commits** end with the session attribution lines.

---

## 14. Acceptance checklist

**Contract**
- [ ] R1–R8 acceptance tests in §2 pass.
- [ ] CLAUDE.md Rule 6 is present and points here.

**Page**
- [ ] Moods (2 × 2, all four visible at 390; three when there is no seed) open their journeys.
- [ ] Contents rows are numbered jump links with counts or "{n} new". The pinned index appears, tracks the current section and jumps. The header title scrolls to top.
- [ ] At most 6 sections. More lists holds the rest. "You're caught up for today." shows, with the tally, Browse and Search. No fold remains.
- [ ] No franchise appears twice on All, Anime or Manga (fixture with Attack on Titan in NTY + Essentials and two Demon Slayer entries).
- [ ] Owned titles are hidden in personal sections and marked elsewhere.
- [ ] Every card has one Plan key. The planned key stamps after save. Failure restores.
- [ ] Long press shows the preview and five items. Not interested and Seen it remove at once, refill, and toast with Undo. Seen it offers "Add as Completed ›" → the editor preset to Completed, with nothing saved silently.
- [ ] Hidden titles stay hidden after relaunch and on See all and mood journeys.
- [ ] NEW markers appear on the second visit only, and never blink.
- [ ] The Essentials hook counts correctly (Completed + Seen it, half for Watching).
- [ ] ANIME / MANGA kickers show on All only.
- [ ] Trending refine words are the D10 words and never clip at 320.
- [ ] Scroll offset and segment survive a journey round trip. A hide never moves content above the viewport.

**Journeys**
- [ ] See all: sorts, chips with ✓ selected state, match line, Plan keys, preview, paging (catalogue) or "That's all {n}." (bounded), and the empty state.
- [ ] The mood journey has its switch row, purpose, Anime · Manga, chips, rows and empty state.

**Platform**
- [ ] Every new control is at least 44 pt. VoiceOver custom actions on every card. Reduce Motion: no travel, no entrance, instant scrolls.
- [ ] Every new string has German. EXISTING strings are byte-identical.
- [ ] Telemetry events fire with the §5.12 names and payloads, and nothing else.
- [ ] Gates: `check_branded_states.sh`, `check_architecture.sh` and `check_navigation.sh` pass with 0 offenders. The Taste and Home snapshot suites are unchanged.
- [ ] The prepared SQL passes its local DB tests. Nothing is applied or deployed.

## 15. Verification

```bash
# Build (own derived data; own simulator by UUID)
xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'id=<lane-sim-uuid>' \
  -derivedDataPath /Users/max/.claude/jobs/1fb75ce2/tmp/<lane>/dd CODE_SIGNING_ALLOWED=NO build

# Lane suites (no write variable)
xcodebuild ... test -parallel-testing-enabled NO -only-testing:KuroTests/<Suite>

# After renders (lane A / B suites only; only into docs/discover-usability-2026-11-04/after/)
TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1 xcodebuild ... test -parallel-testing-enabled NO \
  -only-testing:KuroTests/DiscoverUsabilitySnapshotTests   # or DiscoverJourneySnapshotTests

# Package and DB (lane C)
cd Packages/KuroModules && swift test
scripts/db/run_local_db_tests.sh --only discover_feedback_v1

# Gates
scripts/quality-gates/check_branded_states.sh
scripts/quality-gates/check_architecture.sh
scripts/quality-gates/check_navigation.sh
git status --short   # no committed PNG outside docs/discover-usability-2026-11-04/ changed
```

The integrator also:
- runs the full `KuroTests` and `DiscoverUsabilityUITests` once on `7FC4B58A-430C-457D-A017-6B0095723F3F`
- runs `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh` after the Rule 1/2 docs are updated
- commits the after renders
