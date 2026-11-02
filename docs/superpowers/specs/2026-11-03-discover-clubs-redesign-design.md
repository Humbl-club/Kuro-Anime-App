# Discover + Clubs redesign: "Discover is an issue. Clubs are rooms." (binding spec)

**Date:** 2026-11-03
**Branch:** `kuro/discover-clubs-redesign` (local, not pushed)
**Status:** binding for the two build lanes (Discover lane, Clubs lane) and their integrator.

**Owner request (2026-11-02, night):** "We still need to adjust the way or the design of the Discover page. We have to design the Clubs page, which is good actually, but it could be a bit better. Really think about this and execute overnight. Take the homepage as the main thing."

**Inputs, in order of authority:**
1. Home as shipped (`Kuro/Views/Home/*`, main `ff8059d`).
2. The prototype `tools/design-directions/instrument.html?switch=poster`, through `docs/prototype-fidelity/PROTOTYPE_SPEC.md` and `LANE_AMENDMENTS.md`.
3. `docs/discover-clubs-2026-11-03/understand/HOME_GRAMMAR.md` (Home's grammar with file:line; cited below as **G§n**).
4. `docs/discover-clubs-2026-11-03/understand/DISCOVER_CLUBS_AUDIT.md` (problems P1–P16, cited as **Pn**).
5. The navigation contract `docs/superpowers/specs/2026-11-02-navigation-contract-design.md` (N1–N11, H1–H4).

**Supporting design documents:**
- Judging: `docs/discover-clubs-2026-11-03/design/JUDGING.md`. Editorial won with 8.45; Calm 8.18; Personal-first 7.03.
- Final mockup: `docs/discover-clubs-2026-11-03/design/final.html` (390 × 844 frames plus one SE 320 frame).
- The three candidate mockups stay in the same folder as the record.

> **Precedence.** If this spec and `final.html` disagree, this spec wins. If this spec and Home's code disagree on a measured value, Home's code wins; use Home's constant and note the difference in the lane report. CLAUDE.md's old "DESIGN SYSTEM" section (`kuroBlack80` era) does not apply to this work (G, header note).

---

## 1. Intent

Discover and Clubs should feel like the same app as Home:
- the same warm paper
- the same hand-set SF type and headings
- colour that comes from artwork
- the same physical keys, quiet cards, short motion and branded states

The work has two parts:
- **Discover becomes a daily issue.** Today it repeats one pattern about ten times: a 19 pt heading, then poster frames. Instead it gets:
  - an opening row
  - an art-filled All · Anime · Manga switch
  - one cover story on the title's own material
  - a glance card
  - a contents line that brings "Browse the catalogue" into the first screen and a half
  - a few sections, each in a different form: a feature plus three covers, a numbered index, one rail
- **Clubs become rooms.** The dark club room the owner already likes on Home becomes the one surface for a club: on the list, on the empty page and as the club page's hero. Inside the club, actions are labelled keys, the tabs use Home's switch rule, and "This week" shows only this week.

Both pages keep their content, order, data sources and journeys. This is a visual and interaction redesign.

## 2. Goals and non-goals

### Goals
- **G1. One canvas, no seam.** Fixes P1.
  - Discover: `#FFFEF8` for All and Anime, `#F5F5F3` for Manga.
  - Clubs list and club page: `#FFFEF8`.
  - The header paints the same colour.
- **G2. One heading family.** Fixes P3. Use Home's page heading (24/−0.85), in-feed sub-heading (15/−0.2) and eyebrow (9/1.05) on both pages and on the club tabs.
- **G3. Discover has rhythm.** Fixes P2 and P14.
  - The All page drops from about 3,400 pt to about 1,900 pt.
  - The curated order and every source stay the same.
  - Rail chips stay local refinements.
- **G4. Medium choice in Home's switch language.** Fixes P5.
- **G5. Colour from artwork.** Fixes P6. `ArtworkMaterialStore` provides the colour behind the cover story, the feature, and the switch fill.
- **G6. A visible Plan key on Discover.** Uses the existing Taste/Home plan grammar and keeps the context menu.
- **G7. One club surface.** Fixes P4, P11 and P15. The same room on the list, the empty page, the club hero and the Home room, with one seal size and one compact threshold.
- **G8. Club actions are labelled keys that never dead-tap.** Fixes P8. Invite opens an invite tool. Joining a club opens it (P16).
- **G9. "This week" is this week.** Fixes P9. Entries are grouped by day and have covers. Polls show "You asked", deadlines, and title covers that can be opened (P12, P15). Each note appears exactly once (P7).
- **G10. States.** Fixes P10 and P13. `KuroSkeleton` at ink .08 / .13, one retry style, and a failure is never shown as empty.

### Non-goals
- No backend change of any kind: no migrations, RPCs, edge functions or deploys.
- No feature-flag change and no production data write.
- No push.
- No new event types and no new fields. Every pixel maps to data that is already loaded (§9).
- No change to Browse, Search, Taste, Collection, Detail or Profile, or to their use of the shared `DiscoverFrame` / `DiscoverWordPicker` / `DiscoverLayout` / `DiscoverPicture` / `KuroSectionHeader`.
  - "Retired" in this spec means "this page stops using it". It never means "restyled" or "deleted".
- No change to Home's own files except `Views/Home/HomeClubRoom.swift`. The Clubs lane changes it, and only for the seal and threshold unification in §7.6.
- No score or genre on the cover story (rulebook §14.5 stays in force).
- No English rename of "rails". It stays "rails" / "Listen" across the app (§3, D8).
- No change to the create-club, create-rail or create-poll forms beyond what §7.7 lists.

## 3. Decisions (D1–D16)

| # | Decision | Why |
|---|---|---|
| D1 | **Base direction: Editorial.** Grafts are listed in JUDGING.md. | Highest weighted score. It is the only direction where every block is a Home component shape. |
| D2 | **Discover canvas follows the issue switch:** All and Anime use `kuroCanvasHome`, Manga uses `kuroCanvasHomeManga`. The crossfade uses `KuroMotion.medium` and is skipped under Reduce Motion or Low Power. | Same as Home and Taste (amendment 8). |
| D3 | **Discover's selection moves up into `KuroMainView`,** the same way `tasteMedium` does, so `Section.canvas` can follow it. The header and page change in the same commit. | Seam rule, G§1. |
| D4 | **The three-word switch is a new Discover-owned view, `DiscoverIssueSwitch`.** `KuroPosterMediumSwitch` is not generalized. | It hard-codes `.anime` / `.manga` (`HomePagePicture.swift:175-176`), and Home and Taste depend on it. |
| D5 | **The Plan key is `TastePlanKey`, driven by one page `TastePlanController`** (`.tastePlanHost(plans)`). Cards map through `TasteCard(anime:)` / `TasteCard(manga:)`. For `DailyFeature`, a Discover-file extension builds `Media(...)` (internal memberwise init, `Catalog/MediaDisplayModels.swift:32`) and calls the internal `TasteCard(media:bannerURL:premise:)`. The private `TasteCard.media(kind:…)` factory is not needed, and `TastePicksView.swift` is not edited. `KuroAdvanceKey` is **not** used on Discover. | This is the existing plan grammar: plan and unplan with an Undo toast, and a tracked title opens the tracking editor. `KuroAdvanceKey` is the +1 key, and its tracked state is a disabled "Caught up" key. |
| D6 | **Fewer items per section; "See all" carries the rest.** New to you shows 1 feature + 3 covers. The index shows 5 rows. Trending is a rail of up to 10. | Rhythm (P2). The See all journeys already exist. **Owner choice:** see §11. |
| D7 | **Clubs: one compact room per club on the list,** sorted by `last_activity_at` (newest first; nil last). | One club surface everywhere (P4). |
| D8 | **"Rails" stays in English; German keeps "Listen".** The tab is "Rails · This week · Polls" / "Listen · Diese Woche · Umfragen". | The English word is used across the app: "Create a rail", "No rails yet.", "In your club rails", the add-to-club sheet. |
| D9 | **Invite is for owners and admins only.** Members don't see the key. | Only owners and admins receive `invite_code` (every `fetch_club_bundle` since `20260209202000`). Showing the key to members would be a dead tap (N9). |
| D10 | **"Add a title" is shown only when the viewer can add to at least one rail.** It opens a rail chooser, or goes straight to the only rail. When there are no rails, owners and admins get "Start a rail"; members don't see the key. | This is the existing `canAddToRail` rule (`ClubDetailView.swift:530`). It never guesses `rails.first` and never dead-taps (P8). |
| D11 | **Each note appears exactly once.** The first note in rail order (`ClubRoomCopy.firstNote`) appears in the hero card. Its tile shows "{name}'s note ↑", which scrolls to the hero card. Every other note stays under its own tile as a spoiler-gated disclosure. | Fixes P7. Rail notes carry no spoiler scope, so they stay gated, and no timestamp, so no time is shown. |
| D12 | **"This week" keeps entries whose `updated_at` is within the last 7 × 24 h of device time,** grouped by calendar day in `Europe/Berlin`. Entries with a nil or unparseable `updated_at`, and older ones, go under "Earlier". | P9. No data is dropped. There is no "club time zone". |
| D13 | **The viewer is "You" on the club page only.** It is identified there by `members[].user_id`. The list room shows initials the way Home's room does (the first three `member_names`) and counts members. | `ClubListRow.member_names` has no ids (P15). |
| D14 | **Joining a club opens it** (`JoinClubResponse.club_id` → `routes.openClub`), the same way creating one does today. The join sheet gets the N7 discard guard. | Fixes P16. |
| D15 | **Seal 36 / 30 pt and compact threshold ≤ 328 on all club surfaces.** `ClubSeal` and `ClubKnot` move from `HomeClubRoom.swift` (private) to `ClubRoomStyle.swift`, and `ClubRoomMetrics` is aligned to these values. | G§14.1–2: Home measures 36 / 30. |
| D16 | **Collection keeps its white canvas.** In the live pager this means the page colour goes warm → white → warm from Discover to Clubs. That is recorded as an owner decision (§11), not fixed here. | DO-NOT #16. |

## 4. Home grammar used (reference card)

The exact values are in G§1–§13. Lanes copy Home's constants or literals and do not invent new ones.

| Role | Value | Source |
|---|---|---|
| Canvas | `kuroCanvasHome` #FFFEF8 / `kuroCanvasHomeManga` #F5F5F3; ink `kuroInk` #252625; muted `kuroMuted` #696C6B | G§1 |
| Gutter / top / stack | 20 (16 when the measured container ≤ 330); 7 under the header; 12 between opening blocks; 24 between shelf sections; footer 28/28 | G§7 |
| Width source | the measured container (`onGeometryChange`), never the screen; compact = column ≤ 328 (`KuroMediumSwitch.smallPhoneContainer`); iPad `.kuroReadableWidth()` 680 | G§7 |
| Eyebrow + headline row | `HomeOpeningLineView(kicker:headline:compact:)`: kicker 9/8 pt, tracking 1.05, #666C68, uppercase; headline 14/13 semibold −0.3, right-aligned; stacks at accessibility sizes | G§4.1 |
| Page section heading | `kuroCustom(24 / 22c, .semibold, relativeTo: .title2, maxSize: 40)` tracking −0.85, ink, `.isHeader`; summary 10/9 pt `HomeInk.calendarSummary` #656C66 on the right, first-baseline HStack, gap 9; 17 pt to the content below; stacks at accessibility sizes | G§4 |
| In-feed sub-heading | `HomeAlsoWatchingHeading` (15 semibold −0.2 + 10 pt `kuroMuted` count); 12 pt below | G§4 |
| Medium switch tokens | `.kuroMediumWordStyle(size:)`, `HomeInk.switchUnselected` #6E786F, `HomeInk.switchHairline`, `HomeInk.switchMark` 28 × 2, `KuroArtWordFill(raw:fallback:)` | G§5 |
| Scene-card anatomy | artwork radius 5, near-invisible drop; foot `ArtworkMaterial` base → deep; title 17 semibold −0.35 `HomeInk.footTitle`; facts 10/9 pt `HomeInk.footFact`; `.homeEntrance()` 380 ms; `HomeArtworkPressStyle` | G§8.3 |
| Glance card | `HomeInk.glanceFill` #FFFEFA, radius 8, 1 pt `glanceBorder`, padding 10/12, min height 72, three 27 × 38 thumbs, count 21 pt mono | G§8.1 |
| Quiet card | `HomeQuietCard(text:)` | G§8.2 |
| Quiet row | 40 × 60 cover (radius 2), gap 16, min height 60, 0.5 pt `kuroHairline` under each row | G§7 |
| Calendar card | radius 18, `HomeCalendarCard` grammar (date chip, day label/count, stacked covers, open rows) | G§8.6 |
| Club room | `ClubRoomBackground`, `ClubRoomPalette`, `ClubRoomMetrics` | G§8.7 |
| Keys | `TastePlanKey` (Plan); `ClubRoomPalette.key` faces on the room; the paper key face is the `KuroKeyFace(.light)` recipe | G§6 |
| Invitation link row | kicker (`.kuroKicker()`), 19 pt title, → 13 pt, 1 pt ink rule, min height 52, rows 22 apart | G§6 |
| Footer | `HomeFooter` | G§8.8 |
| Toast | `TastePlanToastView` through `.tastePlanHost` | G§8.9 |
| Motion | contact 120 / settle 220 / medium 320 on the prototype ease; `KuroMotionAllowance`, `KuroMotion.playsMotionNow`; everything holds still under Reduce Motion or Low Power | G§10 |
| States | `KuroBrandedState.resolve`, `KuroSkeleton` (ink .08 / .13), `KuroStateView(..., layout: .inline)`, `KuroErrorView`, `KuroOfflineView`, `HomeClubRoomFailureLine`; no `ProgressView(` | G§11 |
| Missing art | `HomeInk.posterFill` (#E9E9E6), not `kuroMissingArt` | G§12 |

Literal values copied from Home keep Home's comment style ("measured: …"). A value used by both lanes goes in that lane's own layout enum (`DiscoverIssueLayout`, `ClubRoomLayout`), never in a new shared token file (§12).

## 5. Shared page frame

- **Canvas.**
  - `KuroMainView.Section.canvas(...)` gains `.discover` (follows `discoverIssue`: `.manga` → `kuroCanvasHomeManga`, else `kuroCanvasHome`) and `.clubs` (`kuroCanvasHome`).
  - `EditorialDiscoverView`, its See all page, `ClubsView` (all states) and `ClubDetailView` paint the same token.
  - The existing `.animation(KuroMotion.medium, value: canvas)` covers the crossfade.
- **Header.** `KuroHeaderNew` is unchanged. It paints `selection.canvas(...)`.
- **iPad.** The canvas fills the window, so there are no white side bands. The content column uses `.kuroReadableWidth()`.
- **Light mode only**, as everywhere else.

---

## 6. Discover

Discover is a pager page with no back control. The order of blocks is fixed, and each block is drawn only when its data is non-empty, exactly as today. The section order and flags (`discover_realm_rails_v1`, `personalized_new_to_you_v1`) are unchanged.

### 6.1 Layout at 390 pt (column 350)

| # | Block | Spacing above | Notes |
|---|---|---|---|
| 0 | Offline band (only when offline with content) | 7 | §6.4 |
| 1 | Opening row | 7 | |
| 2 | Issue switch | 6 | |
| 3 | Cover story (DailyFeature) | 12 | |
| 4 | Airing today glance (All and Anime only, when `airingToday` is non-empty) | 12 | |
| 5 | In this issue + Browse the catalogue | 12 | |
| 6 | New to you, or Because you… (All); Manga new to you replaces it on Manga | 28 | |
| 7 | Tonight's shelf (flag, rail grammar) | 32 | |
| 8 | Essential anime (index) | 32 | |
| 9 | Hidden gem (flag; cover-story grammar at 3.25:1, no "Today's pick" tab, eyebrow "Hidden gem" / "Verborgenes Juwel" in the tab position) | 32 | |
| 10 | Manga new to you (All only; feature + three, using manga covers) | 32 | |
| 11 | Trending (the one horizontal rail, with a local refinement) | 32 | |
| 12 | Essential manga (index) | 32 | |
| 13 | Fold: "Show N more sections" → Classics, This season, Top rated (with its local refinement), Just added, and the manga secondaries, all in index grammar | 24 | |
| 14 | `HomeFooter` | 28 | |

Measured estimate for the All page: about 1,900 pt (down from about 3,400).

### 6.2 Blocks

**1. Opening row.** `HomeOpeningLineView`.
- Kicker: "TODAY'S ISSUE · {EEE d MMM}" / "HEUTIGE AUSGABE · {EEE d. MMM}".
  - The date is the device date in `Europe/Berlin`, formatted with `de_DE` or `en_GB` patterns (EN "MON 3 NOV", DE "MO 3. NOV").
- Headline: "Edited for you." / "Für dich zusammengestellt."

**2. Issue switch** (`DiscoverIssueSwitch`, new, Discover-owned).
- Words: All · Anime · Manga / Alle · Anime · Manga.
  - The labels are the existing `DiscoverMediaTypeFilter.title(german:)`.
  - Uppercased by `.kuroMediumWordStyle(size:)`.
- Layout:
  - Three words spread edge to edge: the first leading, the second centred, the third trailing.
  - They sit over a 1 pt `HomeInk.switchHairline`. Min row height 50.
- Size:
  - 28 pt (tracking −1.45), or 24 pt when the column is ≤ 328.
  - Measured: 244 pt of words in 350, 210 pt in 280.
  - Keep `minimumScaleFactor(0.6)` as a safety net only.
- Selected word:
  - Masked over `KuroArtWordFill(raw:fallback: .solid)`, fed with the cover story's art (banner, else cover).
  - A 28 × 2 `HomeInk.switchMark` rule sits on the hairline under it, aligned to the word's leading, centre or trailing edge.
  - The rule fades in place (`KuroMotion.settle`); it never travels.
- Unselected words: solid `HomeInk.switchUnselected`.
- Interaction: `HomeContactStyle` press; a light haptic on change; 44 pt minimum height for each word's target.
- Accessibility sizes: the words stack vertically (VStack spacing 0, like `KuroPosterMediumSwitch`).
- VoiceOver: a group labelled "Show" / "Anzeigen". Each word is a button with `.isSelected` on the current one.
- Changing the word changes the page content as today, and crossfades the canvas (D2).

**3. Cover story** (`DiscoverCoverStory`, new, replacing `DiscoverLeadFrame` on this page only). Built with scene-card anatomy.
- **With a banner** (`DailyFeature.bannerImage`):
  - **Art window:**
    - The banner at 2.2:1 (159 pt tall at 350), radius 5 on the top corners.
    - `HomeArtwork` + `.homeEntrance()`.
    - A 1 pt white @ .15 rim, and a lower-half shade #000 @ .18.
    - A tab at leading 12 on the bottom edge, in the season-tab style (`HomeInk.tabFace`): 7 pt uppercase "TODAY'S" + 13 pt semibold "pick" (DE "TIPP" + "des Tages").
    - The tab text is the existing `DiscoverOneThingCard.defaultEyebrow`, split at the first space, or the feature's own eyebrow when one is given.
  - **Foot:**
    - A `base → deep` gradient (135°) from `@Environment(ArtworkMaterialStore.self).material(for: bannerURL ?? coverURL, seedHex:)`; neutral base #3a3d3c until it is derived.
    - Leading: title 17 semibold −0.35 `HomeInk.footTitle` (2 lines, 3 at accessibility sizes), then the argument at 11 pt `HomeInk.footSecondary` (3 lines).
    - Trailing: a 1 pt white @ .14 divider, then `TastePlanKey(card:, variant: .landscape)` in a 112 pt column (96 compact).
  - **Fact row:**
    - The same material, 40 pt, 10 pt `HomeInk.footFact`.
    - Leading: "{year} · {format}". Format uses the existing format words; skip a missing part, and hide the row if both are missing.
    - Trailing, when `friendCount > 0`: a 17 pt disc with the first friend's initial plus "{n} in your clubs ›" / "{n} in deinen Clubs ›".
- **Cover only** (manga, or anime without a banner), the capped spread (P14):
  - A 132 × 198 cover (radius 5 on the leading side) beside a material panel.
  - The panel has a 7 pt 1.4-tracked kicker, a 20 pt semibold title, an 11 pt argument, and a bottom row with the facts and the Plan key.
  - Total height ≤ 220.
  - At ≤ 328 the cover is 104 × 156.
- **Tap targets:**
  - The art or the title opens the title (`routes.openMedia`).
  - The Plan key plans or edits (D5).
  - "{n} in your clubs ›" opens the title too.
  - Long press keeps today's `DiscoverFrameMenu`.

**4. Airing today glance** (All and Anime only).
- In Home's glance-card grammar, drawn by a Discover-local `DiscoverGlanceCard`.
  - It copies the glance anatomy from G§8.1; `HomeComingUpGlance` itself is bound to `HomeGlanceSummary`.
- Title: "Airing today" / "Läuft heute" (existing route title).
- Caption: "Next: {title} · Ep. {n} at {HH:mm}" / "Als Nächstes: {Titel} · Folge {n} um {HH:mm}".
  - From the earliest `airingSlots` entry still ahead of now.
  - When every slot has passed: "Last: {title} · Ep. {n}" / "Zuletzt: {Titel} · Folge {n}".
  - Times use `Europe/Berlin` and are 24 h.
- Thumbs: three covers from `airingToday`.
- Count: `airingToday.count` over "today" / "heute".
- The card is one button, opening the existing Airing-today See all journey (`DiscoverSeeAllPolicy`).
- Hidden on Manga.

**5. In this issue.**
- A 1 pt `kuroHairline` top rule, then the eyebrow "IN THIS ISSUE" / "IN DIESER AUSGABE" (9/1.05).
- Then a wrapping `FlowLayout` (gap 6 × 14) of the sections shown below. Each entry is a 12 pt medium name plus a 10 pt `kuroMuted` count, using the section's real item count.
  - At most 5 names, then "+{n} more" / "+{n} weitere".
  - Tapping a name scrolls to its section (`ScrollViewReader`, `KuroMotion.settle`; instant under Reduce Motion).
  - Tapping "+n more" opens the fold, then scrolls to it.
  - Each entry is a button at least 44 pt tall (the visual row is 22; the hit area expands vertically).
- Then the **Browse row**, shown only when `DiscoverBrowseEntry.isOffered(flags:)` is true, as today:
  - The invitation link-row grammar: kicker "EVERYTHING" / "ALLES", title "Browse the catalogue" / "Den Katalog durchstöbern" (existing), → glyph, 1 pt ink rule, min height 52.
  - Opens Browse as a journey (`routes.openBrowse()`, N11).
- The old end-of-page `KuroInkButton` "Browse the catalogue" is removed from this page.
- If fewer than 2 sections are shown, the contents list is omitted and only the Browse row remains (when offered).

**6. New to you / Because you… / Manga new to you** (`DiscoverFeatureTrio`, new).
- **Heading:** page section heading.
  - Title: the existing route title + ".", e.g. "New to you." / "Neu für dich." or "Because you loved {X}.".
  - Summary: "Unseen by you · changes daily" / "Noch nicht gesehen · täglich neu"; for Because-you, "From your favourites" / "Aus deinen Favoriten".
- **Feature:** the first item, in cover-story grammar.
  - The banner at 3.25:1 (108 pt at 350), with no tab.
  - The foot holds the title, "{year} · {format} · {n} eps" (or "{n} ch."), and `TastePlanKey(.landscape)`.
  - Without a banner, the feature is the capped spread at 160 pt max.
- **Trio:** items 2–4, as three columns, 14 pt apart.
  - Each is a 2:3 cover (radius 4, drop `0 2 3 #242C2514`), a 12 pt medium title (2 lines, no reserved second line), and one 10 pt `kuroMuted` line.
  - The line is "{n} in your clubs" when the friend count is above 0, else "{year} · {format}".
  - When the title is tracked, a 9 pt "On your list" / "Auf deiner Liste" mark (1 pt #D7DBD5 border, radius 4) sits under the line.
  - No key on the trio; long press keeps the menu.
- **See all:** "See all {n} ›" / "Alle {n} ansehen ›" (`text-action`, 13 pt medium, 44 pt target), when the section holds more than 4 items. Opens the existing See all journey.

**7. Essential anime / Essential manga** (index; `DiscoverIndexRow`, new).
- **Heading:** page section heading + summary "The canon, in our order" / "Der Kanon, in unserer Reihenfolge".
- **Rows:** 5, using the quiet-row recipe with the min height raised to 76.
  - Leading: number "01" (13 pt medium mono, `kuroMuted`, 22 pt column).
  - Cover 40 × 60 (radius 2).
  - Title 15 pt medium −0.2 (2 lines).
  - Meta at 10 pt: "{year} · {format} · {n} eps" (or "{n} ch.").
  - Trailing: `TastePlanKey(.leaf, compact: true)` constrained to 96 pt wide (84 compact).
  - 0.5 pt `kuroHairline` under each row.
- The number is the curated order, not a rank or a score. VoiceOver reads "Number 1 in our order" / "Nummer 1 in unserer Reihenfolge".
- **See all:** "See all {n} ›" when the section has more than 5 items.

**8. Trending** (the one rail).
- **Heading:** page section heading "Trending." / "Gerade beliebt." + summary "This week on Kuro" / "Diese Woche auf Kuro".
- **Local refinement** (existing filter values; the refinement is a local filter):
  - A row of 11 pt medium words "All · Short · Long · Finished", using the existing filter labels and `DiscoverWordPicker` values.
  - Drawn by a new Discover-local `DiscoverRefineRow`: unselected `kuroMuted`, selected ink with a 16 × 1.5 rule; 16 pt gap; each word 44 pt tall.
  - Its VoiceOver group label is "Refine this rail" / "Diese Leiste eingrenzen".
- **Rail:** 106 × 150 covers (radius 4) with a 12 pt title and a 10 pt line, 14 apart. It bleeds past the trailing gutter.
- **See all ›** in the heading's summary slot once the rail is scrolled. Simpler alternative: keep "See all" at the end of the rail, as today.

**13. Fold.**
- A `HomeQuietCard`-shaped button: radius 10, fill `#F6F8F4`, 1 pt `#D9E0D7`, 44 pt.
- Leading: "Show {n} more sections" / "{n} weitere Bereiche zeigen".
- Trailing, at 10 pt muted: the first two section names + "+{k} ⌄".
- Open state: "Show fewer" / "Weniger zeigen".
- **Memory:** `KuroFoldMemory` (`\.kuroFoldMemory`, key `KuroFold.key(page: "discover", section: "more")`). Under rule F3 this is session memory: one per app run, never persisted, held by `KuroRootView`, and a new launch starts folded.
  - This replaces the device-wide `UserDefaults` key `kuro_discover_show_more`, so one account's choice no longer carries over to another account or to a later launch.
  - Discover stops reading that key; it does not need to be deleted.
- Folded sections use the index grammar (5 rows + See all). Top rated keeps its local refinement row.

### 6.3 Interaction and navigation (Discover)

| Tap | Goes to | Rule |
|---|---|---|
| Issue word | Changes the page medium and the canvas | — |
| Cover story art / title / "{n} in your clubs ›" | `routes.openMedia`: a root title journey (✕ only) | N3, N9 |
| Plan key (any) | `TastePlanController.tap`: plan / unplan + toast with Undo; a tracked title → `routes.presentTrackingEditor` (a tool that returns to Discover) | N7 |
| Glance card | The Airing-today See all journey | N3, N5 |
| Contents entry | Scrolls within the page | — |
| Browse the catalogue | `routes.openBrowse()`: Browse pushed as a journey | N11 |
| Feature / trio / index / rail item | `routes.openMedia` | N9 |
| See all ›, "+n more" | See all journey (deduped by `DiscoverSeeAllPolicy.pageID`) / opens the fold | N5 |
| Long press on any title | The existing `DiscoverFrameMenu` (quick add, list editor, add to club) | N7 |

The See all journey page keeps its chrome. It gets the warm canvas, plus `HomeInk.posterFill` behind missing art, and nothing else.

### 6.4 States (Discover)

All states are resolved by `KuroBrandedState.resolve`, as today.
- **Loading:** a `DiscoverIssueSkeleton` (new, built from `KuroSkeleton` blocks at ink .08, deep parts .13) with this anatomy:
  - an opening-row bar
  - three switch blocks
  - cover-story art (159) + foot (58)
  - a glance (72)
  - two index rows
  - then `KuroScrubLine`
  - It replaces `DiscoverLoadingSkeleton` on this page.
- **Offline with content:** an 8 pt-radius quiet band at the top of the content (white @ .5, 1 pt `HomeInk.quietBorder`, 11 pt).
  - Text: "**You're offline.** Showing the last issue you loaded." / "**Du bist offline.** Du siehst die zuletzt geladene Ausgabe."
  - A trailing "Try again →" (ink rule). This keeps the band's existing retry behaviour.
- **Offline on first load:** `KuroOfflineView` (existing copy).
- **Failed:** `KuroErrorView` "Couldn't load Discover." (existing).
- **Empty:** `KuroStateView(.empty)` "Nothing to show yet." with the **ink-rule** "Try again →" (P13).
  - Where Browse is offered, the Browse link row follows the state.
  - The message is "Pull to refresh, or browse the catalogue." only when the Browse row is shown; otherwise "Pull to refresh." / "Zum Aktualisieren ziehen."
- **Refresh failure with content:** the existing transient banner.
- **Plan failure:** the toast shows "Not saved. Your list is unchanged." (existing `TastePlanCopy`). The key keeps its previous state.

### 6.5 Adaptive (Discover)

| Width | Rule |
|---|---|
| SE 320 (column 288 at gutter 16) | Switch 24 pt. Cover-story key column 96. Spread cover 104 × 156. Trio stays at 3 columns (≈ 84 pt covers). Index key 84 wide. Opening kicker 8 pt, headline 13. |
| 390 / 393 | As drawn. |
| Pro Max 430 / 440 | Same grammar from the measured width; the rail shows about 3.5 frames. |
| iPad (680 column) | Trio becomes 4 columns (feature + 4). Index rows keep a single column. The canvas fills the window. |
| Accessibility sizes | The switch words stack. The opening row stacks. The cover-story foot puts the key under the text (full width). Index rows put the key under the title. The trio becomes 2 columns. The glance hides its thumbs. Every target stays at least 44 pt. |

### 6.6 Accessibility (Discover)
- Headings get `.isHeader`. The cover story is one element ("Today's pick: {title}. {argument}. {year}, {format}."), with the Plan key as a separate element.
- Card rows (trio, index, rail, glance) use `.accessibilityElement(children: .combine)` with explicit actions: an "Open" default activation plus the Plan key as its own element. Don't use `children: .ignore` without an `.accessibilityAction` (audit A4).
- Contents entries are buttons labelled "{section}, {n} titles".
- Contrast: the foot text on material is ≥ 7:1 white (`ArtworkMaterial` guarantees it). `kuroMuted` on #FFFEF8 is ≥ 4.5:1.

---

## 7. Clubs

### 7.1 Clubs list (pager page)

**Order:** offline band (when offline with content) → opening row → rooms → invitation rows → footer. Top 7, 12 between blocks.

**Opening row** (`HomeOpeningLineView`):
- Kicker: "YOUR PRIVATE CLUBS · {n}" / "DEINE PRIVATEN CLUBS · {n}".
- Headline:
  - when some are unread: "{k} with something new." / "{k} mit Neuem."
  - when none are: "All caught up." / "Alles gesehen."
- k counts the clubs whose unread dot shows today (`ClubsListCardRules`).

**One `ClubRoomCard` per club** (new; Clubs-owned).
- **Surface:** `ClubRoomBackground(cornerRadius: 24)`, 14 pt apart, `ClubRoomMetrics.forRoomWidth`.
- **Masthead** (HStack, gap `metrics.mastheadGap`):
  - `ClubSeal` (36 / 30, promoted, D15).
  - A VStack holding:
    - the audience kicker: 7 pt, 1.4 tracking, `ClubRoomPalette.kicker`, uppercase. The existing `ClubsListCardRules.audienceLabel(sharingLevel:german:)` words: "PROGRESS SHARED" / "STATUSES SHARED" / "TOTALS ONLY" (DE "FORTSCHRITT GETEILT" / "STATUS GETEILT" / "NUR SUMMEN").
    - the club name: `kuroEditorial(size: 22 / 19c)`, −0.6, `ClubRoomPalette.text`, up to 3 lines.
    - when unread, a 6 pt `ClubRoomPalette.text` dot after the name (monochrome).
  - Trailing: a **cover fan** of up to 3 covers from `cover_images` (30 × 44, radius 2, 1.5 pt `memberRim` border, overlap −9, drop `-2 0 3 #0000002a`).
    - Only real covers are drawn. With no covers, no fan and no empty slots (P11).
- **Meta line** (12 pt below the masthead, on its own line):
  - Member fills: Home's `initials(member_names)`, up to 3, positional `ClubRoomPalette.memberFills`, 22 pt, 2 pt rim.
  - Then 10 pt `rowSecondary`: "{member_count} members · {rail_count} rails · {poll_count} open poll(s)" / "{n} Mitglieder · {n} Listen · {n} offene Umfrage(n)".
    - Zero parts are dropped.
    - "no rails yet" / "noch keine Listen" when `rail_count == 0`.
- **Activity row**, only when `activity_preview` is non-empty: Home's dark room-row grammar.
  - A 1 pt `#c5d2b81c` top rule.
  - A 30 × 44 cover (the first `cover_images` entry, else none).
  - The preview at 11 pt medium `rowInk`, plus the relative time of `last_activity_at` at 10 pt `rowSecondary`.
  - A › glyph.
- **The whole room is one button** → `routes.openClub` (journey root, ✕ only).
  - Press: `HomeContactStyle`.
  - VoiceOver label: the existing `ClubsListCardRules` label (name, audience, members, unread). Hint: "Opens the club".

**Invitation rows** after the rooms, using Home's invitation link-row grammar (existing strings):
- "NEW · Start a club." (existing "Start a club." / "Gründe einen Club.")
- "INVITE CODE · Join a club." ("Join a club." / "Tritt einem Club bei.")
- Rows are 22 apart. They are plain `Button`s with `.accessibilityElement(children: .combine)` (fixes the A4 activation failure on `ClubInvitationAction`).

**Footer:** `HomeFooter`.

### 7.2 Clubs empty

This is the existing branded invitation on the warm canvas.
- Opening row: "YOUR PRIVATE CLUBS" / "DEINE PRIVATEN CLUBS" (fixes the untranslated `ClubsEmptyCopy.kicker`) with "Just your people." / "Nur deine Leute.".
- The room (radius 24, padding 22/18/12), in order:
  - the seal + the kicker "YOUR PRIVATE CLUB" (existing)
  - the existing serif headline (`ClubsEmptyCopy.headline`, 30 pt)
  - the existing 12 pt line (`ClubsEmptyCopy.line`)
  - the dark `ClubRoomPalette.key` "Start a club" (existing `ClubsEmptyCopy.create`)
  - the quiet row "Join with a code ›" (existing `ClubsEmptyCopy.join`)
  - the room footer "Shared stories. Your people." · "2–20 people" (existing)
- A `HomeQuietCard` below explains the sharing levels:
  - EN: "You choose what members see: totals only, statuses, or your progress. You can change it later in the club's settings."
  - DE: "Du bestimmst, was Mitglieder sehen: nur Summen, Status oder deinen Fortschritt. Das kannst du später in den Club-Einstellungen ändern."
- Then `HomeFooter`.
- A failed read never shows this page (`ClubsListRules`, as today).

### 7.3 Club page (journey; root shows ✕ only, N3)

**Hero room** (replaces `JournalHeroSection`'s flat band).
- **Surface:** full-bleed `ClubRoomBackground` with a rounded bottom (0, 0, 24, 24), the radial glow, and the room drop.
  - It extends under the sheet's top safe area, as today.
  - Padding 22 / 18 / 16 (compact 18 / 12 / 12).
- **Chrome:** the existing `JournalStatusBar` behaviour stays:
  - grabber
  - back when pushed (N1)
  - ··· (settings) and ✕ on round material buttons, 44 pt (H2)
  - `KuroInteractivePopEnabler` (N2)
- **Content, top to bottom:**
  1. Masthead: `ClubSeal` + kicker "YOUR PRIVATE CLUB · {AUDIENCE}" / "DEIN PRIVATER CLUB · {AUDIENCE}".
  2. Name: `kuroEditorial(size: 30 / 26c)`, −0.9, up to 3 lines.
  3. Description: 12 pt `rowSecondary`, as today.
  4. Member row:
     - A **"You" ring** (24 pt, 1 pt `ClubRoomPalette.text` @ .6 border, 6.5 pt "You" / "Du"), then the other members' positional fills.
     - The others come from `members` minus the viewer (by `user_id`), at most 4, then "+{n}".
     - Then 10 pt: "{n} members · {r} rails · {p} open poll(s)".
     - VoiceOver: "You and {n−1} members" / "Du und {n−1} Mitglieder".
  5. **Note card**, only when `ClubRoomCopy.firstNote(in:)` is non-nil. It is Home's warm note card (`ClubRoomPalette.note`, `noteShadow`, `noteBorder`, radius 14, padding 15):
     - a 60 × 90 cover
     - the author (11 semibold) + the rail title (10 pt `noteMeta`, trailing); no time (D11)
     - "A note on {title}" / "Eine Notiz zu {Titel}"
     - the existing spoiler disclosure "May contain spoilers. Tap to read." (existing `ClubNoteCard` gate). Opened, it shows the quote in `kuroEditorial(size: 18 / 16c)`.
     - "{title} ›", which pushes the title
- **Key row on paper** (replaces `JournalBottomBar`; no floating capsule):
  - A grid of equal cells, 8 apart, padding 14 / 18 / 4.
  - Each key: 44 pt, radius 7, the `KuroKeyFace(.light)` recipe, 12 pt medium label with a 15 pt glyph.
  - Which keys appear (D9, D10):

    | Key | Who sees it | Action |
    |---|---|---|
    | "Add a title" / "Titel hinzufügen" (existing), glyph ＋ | anyone for whom some rail passes `canAddToRail` | one eligible rail → the existing add-item sheet for it; several → `ClubRailChooserSheet` (new tool: the eligible rails as rows, locked rails only for admins) → add-item sheet |
    | "Start a rail" / "Liste anlegen" (existing "Create a rail" German), glyph ＋ | owners and admins when the club has no rails | the existing create-rail sheet |
    | "Invite" / "Einladen" (existing), glyph ↗ | owners and admins (`invite_code` non-nil) | `ClubInviteSheet` (new tool, §7.4) |
    | "Ask" / "Fragen", glyph ? | owners and admins | the existing create-poll sheet |

  - Members who can't add see no key row at all. The tabs then follow the hero directly.
  - Offline: keys are drawn disabled at .45 opacity, with the VoiceOver value "Offline", as the bottom bar does today.
- **Tabs** (replaces `JournalTabBar`'s look; keeps its identifiers):
  - "Rails · This week · Polls" / "Listen · Diese Woche · Umfragen".
    - The `.active` case keeps its identifier and gets the new label (P9).
  - Style: 15 pt semibold −0.2; unselected `HomeInk.switchUnselected`; a 10 pt `kuroMuted` count after each word.
    - Rails = rail count; This week = this-week entry count; Polls = open polls. A zero count is omitted.
  - 22 apart, 44 pt tall, on a 1 pt `HomeInk.switchHairline`.
  - Selected: ink + the 28 × 2 `switchMark` rule, fading in place (no matchedGeometry travel).
  - **Pinned:** when the hero scrolls away, the existing compact paper bar (H1: club name, ···, ✕; scroll-tied fade, H3) appears, and the tabs pin under it on the canvas.

### 7.3.1 Rails tab
- Each rail is a block with padding 18 / 18 / 4, with 16 pt hairlines between blocks.
  - `HomeAlsoWatchingHeading`-style sub-heading: the rail title + "{n} titles"; when locked, " · locked" / " · gesperrt".
  - The rail description at 11 pt `kuroMuted`.
- **Tiles:** a two-column grid in `HomeAlsoWatchingTile` style (16 apart, 12 compact; one column below 300 pt or at accessibility sizes).
  - Cover: 44 × 66 (radius 4, drop `0 3 3.5 #22222255`).
  - Title: 12 pt medium (3 lines).
  - Line 1: the viewer's progress, "You · Ep. 7 of 24" (`ClubRoomCopy.progress` with the "You · " / "Du · " prefix), when `my_progress` > 0.
  - Line 2: who else, from `member_statuses`, using the existing wording ("Mina, Jules watching", "Ari finished it", "Planned by 2") in the existing EN/DE helpers. Falls back to "Added by {added_by}" / "Hinzugefügt von {Name}".
  - Line 3: the note link.
    - On the first-note item: "{name}'s note ↑" / "Notiz von {Name} ↑", which scrolls to the hero note card (settle; instant under Reduce Motion).
    - On any other item with a note: "{name}'s note · may contain spoilers ⌄" / "Notiz von {Name} · kann Spoiler enthalten ⌄", which expands inline to the serif quote.
  - The live **reaction row** (`clubs_reactions_v1`, 100% live): the existing `ClubReactionMenu` under the tile text, with 20 pt chips and 44 pt hit areas.
  - Tapping a tile pushes the title (N9). Long press keeps the existing menu.
- **Rail end:** "＋ Add to {rail}" / "＋ Zu {Liste} hinzufügen" (existing string), 44 pt, when `canAddToRail`. It opens the add-item sheet for that rail. This replaces the dashed placeholder card.
- **Empty rail:** `HomeQuietCard` "Nothing here yet." / "Noch nichts hier.", plus the add link when allowed.

### 7.3.2 This week tab
1. **Pace glance** (when the existing pace rule applies: a progress club with ≥ 3 members).
   - Glance-card grammar: "You're {n} episodes behind" / "Du bist {n} Folgen zurück"; caption "{rail} · the group is on Ep. {g} of {title}"; count {n} over "behind" / "zurück"; ›.
   - The glance pushes the title.
   - The count uses the existing pace math; the wording is new.
2. **Heading:** page section heading "This week." / "Diese Woche." + summary "{n} updates since {EEE d MMM}" / "{n} Neuigkeiten seit {EEE d. MMM}".
3. **Calendar card** (`ClubWeekCard`, new, in `HomeCalendarCard` grammar; radius 18).
   - **Day rows:**
     - A 40 × 44 date chip: day 17 pt mono, month 8 pt uppercase.
     - The label: "Today" / "Heute", "Yesterday" / "Gestern", else the weekday.
     - "{n} updates" / "{n} Neuigkeiten".
     - Stacked covers, up to 3 (23 × 34).
     - A disclosure ⌃/⌄. Today is open by default; other days are closed.
   - **Entry rows** (white, leading inset 63):
     - A 32 × 48 cover from the entry's existing `coverImage`.
     - 12 pt prose using the existing activity wording, with **"You"** for the viewer ("You reached episode 4" / "Du bist bei Folge 4").
     - The title at 10 pt; the time `HH:mm` at 10 pt; ›.
     - The row pushes the title (N9).
4. **"Earlier" fold** (`KuroFoldButton` grammar): "Earlier" / "Früher" + "Show {n} older updates" / "{n} ältere Neuigkeiten zeigen". Opened, it shows the same day-grouped grammar (D12).
5. **Quiet week:** `HomeQuietCard` "Quiet week. Nobody has moved on since {weekday}." / "Ruhige Woche. Seit {Wochentag} ist niemand weitergekommen.", followed by the Earlier fold.
6. **Duo clubs** (fewer than 3 members): the existing "Activity shows from 3 members…" copy in a `HomeQuietCard`.
7. A room-style footer line: "Shared stories. Your people." (existing).

### 7.3.3 Polls tab
- **Open polls:** each in a glance-style card (radius 8, padding 14/14/6).
  - Kicker (9/1.05): "YOU ASKED · CLOSES {EEE d MMM}" / "DEINE FRAGE · ENDET {EEE d. MMM}".
    - "{name} asked" / "{Name} fragt" for anyone else.
    - The closing part is omitted when `closes_at` is nil.
  - The total votes on the right, at 10 pt.
  - The question at 17 semibold −0.35.
- **Option rows** (min height 58, 1 pt `#E3E7E1` top rule):
  - Cover: when `media_type` / `media_id` are set, a 27 × 38 cover from the rail item with the same id, else none (keep the 27 pt indent).
  - The label: when the option is a title, "{label} ›" is a **separate button** that pushes the title.
  - The percentage on the right, a 3 pt ink bar, and "{n} votes" / "{n} Stimmen"; "· yours" / "· deine" on the viewer's vote.
  - Trailing: a **vote target**, a 22 pt circle in a 44 pt hit area (filled ink with ✓ when it is the viewer's vote). The vote action is the existing one.
  - Voting and opening the title are separate targets.
- **Ask link** (owners and admins): an invitation link row, "ADMINS · Ask the club." / "ADMINS · Frag den Club.". It opens the create-poll sheet.
- **Closed:** the sub-heading "Closed" / "Geschlossen" (existing) + count, then each poll as a `HomeQuietCard`.
  - Text: "{name} asked: {question} · {winner} won, {a} to {b}" / "{Name} fragte: {Frage} · {Sieger} gewann, {a} zu {b}".
  - For a tie: "Tied" / "Unentschieden".
  - Tapping opens the poll results inline, as today.

### 7.4 Tools (sheets; each `.kuroLeavesJourney()`, grabber + Cancel, N7/N8)
- **`ClubInviteSheet`** (new). It shows only what Settings already shows, in the room language:
  - the kicker "INVITE CODE" / "EINLADUNGSCODE"
  - the code in 24 pt mono with 3 tracking
  - Copy / "Copied" (existing strings and behaviour)
  - a `ShareLink` with the existing share payload
  - the existing hint line
  - Settings keeps its own copy of the invite block.
- **`ClubRailChooserSheet`** (new): the heading "Add to which rail?" / "Zu welcher Liste hinzufügen?", then rows with the rail name, count and a locked mark. Choosing a rail goes to the existing add-item sheet.
- **Join sheet:** the N7 discard guard (`KuroDiscardGuard`) once a code is typed. On success it dismisses, then `routes.openClub(response.club_id)` (D14), the same way create does (`ClubsListRules.clubToOpen`). The toast stays.
- **Create club / rail / poll:** unchanged, except that the 26 pt sheet title gets the seal above it (visual only).

### 7.5 States (Clubs)
- **List loading:** a `ClubRoomSkeleton`, built from `KuroSkeleton` blocks shaped like two rooms, on the room colour.
  - Blocks are `ClubRoomPalette.text` @ .08 / .13 on the room; on paper, ink .08.
  - Then `KuroScrubLine`. It replaces the `kuroBlack05` card skeleton.
- **Offline with content:** the same quiet band as Discover: "**You're offline.** Showing your clubs from earlier." / "**Du bist offline.** Du siehst deine Clubs von vorhin." + "Try again →".
- **Offline on first load / failed:** `KuroOfflineView` / `KuroErrorView` with the existing copy, in the ink-rule retry style.
- **Club page loading:** the hero room drawn with skeleton blocks (seal, name bar, member row), then two tile skeletons.
- **Club page, a failed tab read:** `KuroStateView(..., layout: .inline)` on paper. On the room, `HomeClubRoomFailureLine`.
- **Archived:** the existing copy.

### 7.6 Home club room (consistency only)
`HomeClubRoom.swift` changes three things and nothing else:
1. `ClubSeal` and `ClubKnot` move to `ClubRoomStyle.swift` (internal), and Home uses them from there.
2. The compact threshold becomes `ClubRoomMetrics.compactRoomWidth` (328) instead of `< 330`.
3. Home's 36 / 30 seal becomes `ClubRoomMetrics.regular/compact.seal`.

Home's pixels must not change. The Home room renders must match before and after at 320, 390 and 430.

### 7.7 Adaptive (Clubs)

| Width | Rule |
|---|---|
| SE 320 | Room padding 12, seal 30, name 19 (list) / 26 (hero). The fan shows 2 covers. The hero keys show the icon over the label in the same cells. Tiles become one column below 300. |
| 390 | As drawn. |
| Pro Max | Same grammar from the measured width. |
| iPad 680 | The list's rooms use the readable column. The club page tiles stay two columns. |
| Accessibility sizes | Masthead: the fan moves under the name. The meta line wraps below the fills. The keys stack vertically at full width. Tiles become one column. Day rows keep their chip; entry text wraps to 3 lines and the time moves under it. Poll options wrap, and the vote target stays at 44. |

### 7.8 Accessibility (Clubs)
- **Rooms:** one button each with a combined label. The cover fan and fills are `accessibilityHidden`, and the label carries the members.
- **Tabs:** `.isSelected` on the current tab; the count is included ("This week, 5 updates").
- **Keys:** the visible labels are the accessibility labels.
- **Poll options:** two elements each, "Vote for {label}, {n} votes, {p} percent" and "Open {title}".
- **Note:** the spoiler disclosure reads "Note by {name}, may contain spoilers. Double tap to read."
- **Every target is at least 44 pt.** Use `children: .combine` + explicit actions (A4).

---

## 8. Copy (EN / DE)

Every string goes through `KuroLocale.text(en, de)` or the existing `german ? :` copy helpers in the owning lane's copy enum.
- **EXISTING** means: reuse the shipped string exactly. Grep it, don't retype it.
- **NEW** strings go into a lane-owned copy enum: `DiscoverIssueCopy` (Discover) or `ClubRoomCopy` additions (Clubs).

| Where | English | Deutsch | |
|---|---|---|---|
| Discover opening | TODAY'S ISSUE · MON 3 NOV / Edited for you. | HEUTIGE AUSGABE · MO 3. NOV / Für dich zusammengestellt. | NEW |
| Issue switch | All · Anime · Manga | Alle · Anime · Manga | EXISTING |
| Cover story tab | Today's pick | Tipp des Tages | EXISTING |
| Plan key | Plan to watch / Plan to read / Planned / On your list | Vormerken / Geplant / Auf deiner Liste | EXISTING (`TastePageCopy.planLabel`) |
| Plan toast | Added to your list. / Removed from your list. / Undone. / Not saved. Your list is unchanged. / Undo | Zu deiner Liste hinzugefügt. / Von deiner Liste entfernt. / Rückgängig gemacht. / Nicht gespeichert. Deine Liste ist unverändert. / Rückgängig | EXISTING (`TastePlanCopy`) |
| Friend line | {n} in your clubs › | {n} in deinen Clubs › | EXISTING wording + › |
| Glance | Airing today / Next: {title} · Ep. {n} at {time} / Last: {title} · Ep. {n} / today | Läuft heute / Als Nächstes: {Titel} · Folge {n} um {Zeit} / Zuletzt: {Titel} · Folge {n} / heute | title EXISTING, rest NEW |
| Contents | IN THIS ISSUE / +{n} more | IN DIESER AUSGABE / +{n} weitere | NEW |
| Browse row | EVERYTHING / Browse the catalogue | ALLES / Den Katalog durchstöbern | kicker NEW, title EXISTING |
| Summaries | Unseen by you · changes daily / From your favourites / The canon, in our order / This week on Kuro | Noch nicht gesehen · täglich neu / Aus deinen Favoriten / Der Kanon, in unserer Reihenfolge / Diese Woche auf Kuro | NEW |
| Section titles | route titles + "." | route titles + "." | EXISTING (`EditorialDiscoverRoute.title`) |
| Marks / See all | On your list / See all {n} › | Auf deiner Liste / Alle {n} ansehen › | "On your list", "See all" EXISTING |
| Index VoiceOver | Number {n} in our order | Nummer {n} in unserer Reihenfolge | NEW |
| Refine group | Refine this rail | Diese Leiste eingrenzen | NEW |
| Fold | Show {n} more sections / Show fewer | {n} weitere Bereiche zeigen / Weniger zeigen | "Show fewer" EXISTING |
| Offline band | You're offline. Showing the last issue you loaded. / Try again → | Du bist offline. Du siehst die zuletzt geladene Ausgabe. / Erneut versuchen → | NEW / retry EXISTING |
| Discover empty | Nothing to show yet. / Pull to refresh. | Noch nichts zu zeigen. / Zum Aktualisieren ziehen. | first EXISTING |
| Clubs opening | YOUR PRIVATE CLUBS · {n} / {k} with something new. / All caught up. | DEINE PRIVATEN CLUBS · {n} / {k} mit Neuem. / Alles gesehen. | NEW |
| Audience kickers | PROGRESS SHARED / STATUSES SHARED / TOTALS ONLY / PRIVATE | FORTSCHRITT GETEILT / STATUS GETEILT / NUR SUMMEN / PRIVAT | EXISTING (`ClubsListCardRules.audienceLabel`, `ClubViewLifecycle.swift:169`), uppercased |
| Room meta | {n} members · {r} rails · {p} open poll(s) / no rails yet | {n} Mitglieder · {r} Listen · {p} offene Umfrage(n) / noch keine Listen | NEW (built from existing count words) |
| List rows | NEW · Start a club. / INVITE CODE · Join a club. | NEU · Gründe einen Club. / EINLADUNGSCODE · Tritt einem Club bei. | EXISTING |
| Empty | Just your people. / sharing-levels card (§7.2) | Nur deine Leute. / (§7.2) | NEW |
| Empty kicker | YOUR PRIVATE CLUBS | DEINE PRIVATEN CLUBS | fix of EXISTING |
| Hero kicker | YOUR PRIVATE CLUB · {AUDIENCE} | DEIN PRIVATER CLUB · {AUDIENCE} | first part EXISTING |
| Member ring | You / You and {n} members | Du / Du und {n} Mitglieder | NEW |
| Note | A note on {title} / May contain spoilers. Tap to read. / {name}'s note ↑ / {name}'s note · may contain spoilers ⌄ | Eine Notiz zu {Titel} / Kann Spoiler enthalten. Zum Lesen tippen. / Notiz von {Name} ↑ / Notiz von {Name} · kann Spoiler enthalten ⌄ | spoiler line EXISTING |
| Keys | Add a title / Start a rail / Invite / Ask | Titel hinzufügen / Liste anlegen / Einladen / Fragen | first three EXISTING ("Create a rail" German); "Ask" NEW |
| Tabs | Rails · This week · Polls | Listen · Diese Woche · Umfragen | "This week" NEW label |
| Rails | {n} titles / · locked / ＋ Add to {rail} / Nothing here yet. | {n} Titel / · gesperrt / ＋ Zu {Liste} hinzufügen / Noch nichts hier. | EXISTING where found |
| Tile lines | You · Ep. 7 of 24 / Added by {name} | Du · F. 7 von 24 / Hinzugefügt von {Name} | prefix NEW, progress EXISTING |
| This week | This week. / {n} updates since {date} / Today / Yesterday / {n} updates / Earlier / Show {n} older updates / Quiet week. Nobody has moved on since {weekday}. | Diese Woche. / {n} Neuigkeiten seit {Datum} / Heute / Gestern / {n} Neuigkeiten / Früher / {n} ältere Neuigkeiten zeigen / Ruhige Woche. Seit {Wochentag} ist niemand weitergekommen. | NEW |
| Pace glance | You're {n} episodes behind / {rail} · the group is on Ep. {g} of {title} / behind | Du bist {n} Folgen zurück / {Liste} · die Gruppe ist bei Folge {g} von {Titel} / zurück | NEW wording |
| Polls | YOU ASKED · CLOSES {date} / {name} asked / {n} votes / · yours / ADMINS · Ask the club. / Closed / Tied | DEINE FRAGE · ENDET {Datum} / {Name} fragt / {n} Stimmen / · deine / ADMINS · Frag den Club. / Geschlossen / Unentschieden | "Closed" EXISTING |
| Tools | INVITE CODE / Copy / Copied / Add to which rail? | EINLADUNGSCODE / Kopieren / Kopiert / Zu welcher Liste hinzufügen? | first three EXISTING |
| Clubs offline band | You're offline. Showing your clubs from earlier. | Du bist offline. Du siehst deine Clubs von vorhin. | NEW |

**Numbers and dates:**
- Dates use the device's `Locale` formatted through `KuroLocale` (`de_DE` or `en_GB` style) and the `Europe/Berlin` time zone.
- Plurals follow the existing helpers (`ClubRoomCopy.titleCount` pattern).

## 9. Data map (nothing new is fetched)

| UI | Field | Store |
|---|---|---|
| Cover story | `DailyFeature.title/coverImageLarge/bannerImage/year/format/argument/mediaType/mediaId` | `DiscoveryStore` (existing) |
| Material | `ArtworkMaterialStore.material(for:seedHex:)` | injected (existing) |
| Plan state | `LibraryStore.entry(for:)`, `TastePlanAction` | existing |
| Friend count | `SocialActivityStore.friendCount` | existing |
| Glance | `airingToday`, `airingSlots` (`next_airing_at`, episode) | `DiscoveryStore` |
| Sections, counts | the existing view-model arrays | `DiscoverViewModel` |
| Club rooms | `ClubListRow.name/sharing_level/member_count/rail_count/poll_count/last_activity_at/activity_preview/cover_images/member_names` + unread | `ClubsStore` |
| Hero | `ClubBundle.club` (name, description, sharing_level, invite_code for admins), `members[].user_id/display_name/role`, `my_role` | `ClubsStore` |
| Tiles | `ClubRailItem.title_display/cover_image_medium/my_progress/episode_count/chapter_count/member_statuses/added_by/note/reactions/my_reactions` | `ClubsStore` |
| This week | the existing activity entries (`member_statuses[].updated_at`, entry `coverImage`) | existing derivation in `ClubDetailTabComponents` |
| Polls | `ClubPoll.question/closes_at/created_by/is_closed/options/my_vote_option_id`, `ClubPollOption.media_type/media_id/vote_count` | `ClubsStore` |
| Join | `JoinClubResponse.club_id` | `ClubsStore.joinClub` |

If a lane finds that a field it needs is not actually decoded, it drops that line from the design and records it in the lane report. It never adds a fetch.

## 10. Out of scope
- **Collection's canvas** (D16). Owner decision.
- Browse, Search, See all internals, Taste, Detail, Profile and Onboarding visuals. The See all page gets only the canvas and missing-art changes.
- The streaming "our services" club providers (flag at 0%).
- Score or genre on Discover.
- Any change to the create-club form beyond the seal; club chat; notifications.
- The `add_club_rail_item` DETAIL caveat (CLAUDE.md).
- Renaming "rails" in English.
- The `KuroSectionHeader` file comment drift (G§14.6).
- `kuroRoom` cleanup (G§14.4).
- Documentation files (Rule 1/2): the integrator updates them once, after both lanes (§12.4).

## 11. Owner choices (recorded; defaults applied)
1. **Density (D6):** a feature + 3 / 5-row index / See all. The default is applied. If the owner wants more on the page, change the trio to 6 (two rows) without changing anything else.
2. **A visible Plan key on Discover (G6):** a new visible write on this page, using the existing Taste behaviour with Undo. The default is ON.
3. **"This week" is a 7-day filter on the device (D12),** with older entries under Earlier.
4. **Collection stays white (D16).** The live pager goes warm → white → warm. Recommended follow-up: give Collection the warm canvas in a separate, explicit request.
5. **Three-word switch at 28 pt rather than Home's 36,** so three words fit the SE column.
6. **Rooms for every club on the list (D7)** rather than Calm's one room + quiet rows.

## 12. Build lanes: file ownership (no overlap)

Two lanes build in parallel from this commit. Each lane works in its own git worktree on its own branch off `kuro/discover-clubs-redesign` (`kuro/dc-discover`, `kuro/dc-clubs`). An integrator merges both, Discover first, then Clubs, and runs the full verification (§14). The integrator ships both lanes together: the seam rule needs both pages warm at the same moment.

The project uses file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so new Swift files need no edit to `Kuro.xcodeproj/project.pbxproj`. **Neither lane edits the pbxproj.**

### 12.1 Discover lane: owns (may edit or create)

| File | Scope |
|---|---|
| `Kuro/ContentView.swift` | **Only** `KuroMainView`'s Discover selection state (`discoverIssue`, lifted like `tasteMedium` and passed to `EditorialDiscoverView` as a binding) and `KuroMainView.Section.canvas(...)`, which gains the `.discover` **and** `.clubs` cases (D3). No other change. The Clubs lane never edits this file. |
| `Kuro/Views/EditorialDiscoverView.swift` | The Discover page and its See all page (canvas, missing art). |
| `Kuro/Views/EditorialDiscoverFrames.swift` | **Additive only for shared types.** `DiscoverFrame`, `DiscoverWordPicker`, `DiscoverWordButton`, `DiscoverPicture`, `DiscoverLayout` and `DiscoverBrowseEntry` keep their API and pixels, because Browse, Search, Taste and Detail use them. Discover-only types (`DiscoverLeadFrame`, `DiscoverLeadSkeleton`, `DiscoverRail`, `DiscoverGridSection`, `DiscoverSectionHeading`, `DiscoverLoadingSkeleton`) may change or stop being used; delete one only if a grep shows no other user. |
| `Kuro/Views/DiscoverOneThingCard.swift` | May wrap `DiscoverCoverStory`. |
| `Kuro/Views/EditorialDiscoverRouting.swift` | Route titles stay; summaries may be added. |
| `Kuro/Views/DiscoverViewModel.swift` | Read-model shaping only (e.g. counts for the contents line). |
| `Kuro/Views/Discover/` (new folder) | `DiscoverIssueSwitch.swift`, `DiscoverCoverStory.swift`, `DiscoverGlanceCard.swift`, `DiscoverContents.swift`, `DiscoverFeatureTrio.swift`, `DiscoverIndexRow.swift`, `DiscoverRefineRow.swift`, `DiscoverIssueSkeleton.swift`, `DiscoverIssueLayout.swift` (literals), `DiscoverIssueCopy.swift` (EN/DE), `DiscoverPageHeading.swift` (the 24 pt page heading as a Discover-local view; see 12.3). |
| `KuroTests/DiscoverLaneTests.swift` | Update expectations that the redesign changes. |
| `KuroTests/DiscoverIssueTests.swift` (new) | Pure rules: switch sizing, the fold key, contents entries, the glance caption, the cover-only spread height, adaptive breakpoints. |
| `KuroTests/DiscoverAfterSnapshotTests.swift` (new) | Writes only `docs/discover-clubs-2026-11-03/after/discover-*.png`, and only with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`. |

### 12.2 Clubs lane: owns (may edit or create)

| File | Scope |
|---|---|
| `Kuro/Views/ClubsView.swift` | List, empty, states, create/join sheets (join discard guard, join opens club). |
| `Kuro/Views/ClubDetailView.swift` | Page shell, key row wiring, tabs, tools. |
| `Kuro/Views/ClubDetailShellComponents.swift` | Hero room, status bar, key row (replaces `JournalBottomBar`). |
| `Kuro/Views/ClubDetailTabComponents.swift` | Tabs, rails, This week, polls. |
| `Kuro/Views/ClubDetailSheets.swift` | `ClubInviteSheet` and `ClubRailChooserSheet` may live here or in new files. Settings keeps its invite block. |
| `Kuro/Views/ClubCreateSheets.swift` | The seal above the sheet title only. |
| `Kuro/Views/ClubRoomStyle.swift` | Promoted `ClubSeal` / `ClubKnot`; `ClubRoomMetrics` seal 36/30 (D15). |
| `Kuro/Views/ClubViewLifecycle.swift` | Pure rules and copy (`ClubRoomCopy`, `ClubsListCardRules`, the This-week filter, "You" naming). |
| `Kuro/Views/Home/HomeClubRoom.swift` | **Only** the three §7.6 changes. Home's pixels must not change. |
| `Kuro/Views/Clubs/` (new folder) | `ClubRoomCard.swift`, `ClubWeekCard.swift`, `ClubKeyRow.swift`, `ClubRoomSkeleton.swift`, `ClubInviteSheet.swift`, `ClubRailChooserSheet.swift`, `ClubPageHeading.swift` (a lane-local 24 pt heading; see 12.3), `ClubRoomLayout.swift`. |
| `Kuro/Clubs/*` | **Read-only** unless a decoded field from §9 is missing from a model. Then it may only add a `let` to a `Decodable` model, and must record that in the lane report. No RPC change. |
| `KuroTests/ClubsLaneTests.swift`, `ClubsViewRulesTests.swift`, `ClubsContractTests.swift`, `NavclubsTests.swift`, `ClubDisclosureRepairTests.swift` | Update expectations ("Active" → "This week", the key row, join opens the club). |
| `KuroTests/ClubsRoomTests.swift` (new) | The This-week 7-day/Berlin grouping and nil `updated_at`, key visibility by role and rail lock, "You" exclusion by `user_id`, note-once placement, the list room meta, the seal/threshold metrics. |
| `KuroTests/ClubsAfterSnapshotTests.swift` (new) | Writes only `docs/discover-clubs-2026-11-03/after/club*.png` plus `after/home-room-*.png` (the Home room before/after check), and only with the write variable set. |

The Clubs lane must also run the Home suites that cover the room (`HomeLaneTests`, `HomeAnimeLaneTests`, `HomeMangaLaneTests`, `HomeCompositionSnapshotTests` without the write variable), because it owns `HomeClubRoom.swift`.

### 12.3 Shared new components: one owner each
- **Page section heading (24/−0.85 + summary).** Each lane builds its own copy (`DiscoverPageHeading`, `ClubPageHeading`) with identical values from §4. No shared file is created during the lanes.
  - Integrator task: if both copies match, fold them into one `Kuro/Views/Shared/KuroPageHeading.swift`. The integrator owns that file and replaces both call sites in one commit.
- **Quiet offline band.** Lane-local in each lane (`DiscoverIssue…` / `ClubRoom…`). The integrator may unify it the same way.
- **`ClubSeal` / `ClubKnot`.** Clubs lane only. Discover does not use them.
- **Consumed read-only by both lanes (nobody edits them):**
  - `Views/Home/*` other than `HomeClubRoom.swift`: `HomeOpeningLineView`, `HomeQuietCard`, `HomeFooter`, `HomeAlsoWatchingHeading`/`Tile`, `HomeInk`, `HomeArtwork`, `HomeArtworkPressStyle`, `HomeContactStyle`, `KuroArtWordFill`, `HomeCalendarCard` (as reference)
  - `Views/Shared/*`: `KuroBrandedStates`, `KuroFold`, `KuroSectionHeader`, `KuroMediumSwitch`, `KuroAdvanceKey`, `KuroInkButton`, `KuroReadableWidth`, `KuroDiscardGuard`, `KuroMotionEffects`
  - `Views/TastePicksView.swift` (`TastePlanKey`, `TastePlanController`, `TasteCard`, `TastePlanToastView`, `.tastePlanHost`)
  - `Kuro/Design/*`
  - `Views/Routing/*`, `KuroJourneyChrome.swift`, `JourneyHost.swift`
  - `SharedCards/AddToClubRailSheet.swift`
  - If a lane believes it needs a change in one of these files, it stops and reports. It does not edit.

### 12.4 Owned by nobody until integration
- `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md`, and the CLAUDE.md file map and counts.
  - The integrator updates these once, after both lanes.
  - Lanes add new Swift files, which moves the counts the docs-current-state gate checks. That gate is **blocking** in `run_all.sh` (`docs-current-state:…:1`), so `run_all.sh` will FAIL on a lane branch.
    - Lanes run only the individual gates in §14. They don't run `run_all.sh`, and they don't edit docs to make the gate pass.
    - The integrator updates the docs, then runs `run_all.sh`.
- `KuroTests/RestyleSnapshotTests.swift`, `ScreenMapSnapshotTests.swift`, `NavigationEvidenceTests.swift`, `FirstRunSnapshotTests.swift` and their committed PNGs.
  - Lanes treat them as read-only and never run them with the write variable.
  - If a lane run rewrites a committed PNG outside `docs/discover-clubs-2026-11-03/`, revert it with `git checkout -- <file>`.
- `Kuro.xcodeproj/*`, `Packages/*`, `supabase/*`, `scripts/*`.

### 12.5 Lane rules (both)
- Builds and tests:
  - `CODE_SIGNING_ALLOWED=NO`
  - `-parallel-testing-enabled NO`
  - your own `-derivedDataPath` under `/Users/max/.claude/jobs/1fb75ce2/tmp/<lane>/`
- Simulator:
  - Only a clone of `7FC4B58A-430C-457D-A017-6B0095723F3F` named `Kuro-Lane-dc-<lane>`. If that one is booted, create a fresh "iPhone 17 Pro" on the newest runtime with the same name.
  - Use it by UUID and delete it when done.
- No backend, no flags, no production data, no push.
- Commits end with the session attribution lines.
- **Source compatibility with tests neither lane owns** (checked by grep on 2026-11-03):
  - `RestyleSnapshotTests` calls `EditorialDiscoverView()`, `ClubsView()` and `ClubDetailView(clubId:)`. `ScreenMapSnapshotTests` calls `ClubsView()`. Those initializers keep compiling.
    - The lifted Discover selection is an optional binding with a default, e.g. `init(issue: Binding<DiscoverMediaTypeFilter>? = nil)`, falling back to internal `@State` when nil.
  - `RestyleLaneTests` uses `ClubsEmptyCopy.kicker/headline/line/create/join/footer/size(german:)`. `HomeAnimeLaneTests` and `HomeMangaLaneTests` use `HomeClubRoom.pick`, `.roomNotes`, `.Note` and `.spoilerLine`. These keep their signatures.
  - Types a lane retires from its page may be deleted only if a grep over `Kuro/`, `KuroTests/` and `KuroUITests/` finds no other user. Otherwise they stay.
  - If a behaviour change in a lane makes a test in a file it doesn't own fail, the lane stops and reports to the integrator. It doesn't edit that test.
  - `KuroUITests/NavigationContractUITests.swift` looks up "Add to your list" (the tracking editor), which neither lane changes.
- Code rules:
  - `@Observable` only
  - no force unwraps
  - `print` only inside `#if DEBUG`
  - no SDK imports in views
  - every string through `KuroLocale`
  - no `ProgressView(`
  - widths from the measured container

## 13. Acceptance checklist

**Shared**
- [ ] Swiping Home → Discover (All / Anime) shows no colour change in the header or body. Discover Manga matches manga Home (#F5F5F3). Clubs list and club page are #FFFEF8. There is no white band under the header or beside the iPad column.
- [ ] No `KuroSectionHeader(.title)` and no `.kuroKicker()` 2.1-tracked kicker remain on the Discover page or on the Clubs list or club page. They remain wherever else they are used.
- [ ] Browse, Search, Taste, Collection, Detail and Profile render pixel-identical to before (the lanes compare the existing evidence renders without rewriting them).
- [ ] `scripts/quality-gates/check_branded_states.sh`, `check_architecture.sh` and `check_navigation.sh` pass (blocking gates, 0 offenders).

**Discover**
- [ ] Opening row, three-word switch (28 / 24 pt; fits at 320 without scaling), cover story on material with a working `TastePlanKey` (plan → toast with Undo; tracked → editor), glance (anime only), and contents + Browse row inside the first 1.5 screens at 390 when Browse is offered.
- [ ] New to you shows a feature + 3 + "See all {n} ›". The Essentials index shows 5 rows. Trending is the only horizontal rail. The fold uses session memory (`KuroFoldMemory`, F3) and no longer reads `kuro_discover_show_more`.
- [ ] The manga cover-only pick is ≤ 220 pt tall (P14).
- [ ] The All page height at 390 is ≤ 2,100 pt in the after render.
- [ ] Section order and flag gating are unchanged (`DiscoverLaneTests` green).
- [ ] Every tap follows §6.3. Long press still offers the existing menu.
- [ ] States: skeleton at .08 / .13, the offline band, offline/failed/empty all with the ink-rule retry (one style).

**Clubs**
- [ ] Every club on the list is a room (seal 36 / 30, kicker, serif name, fan of real covers only, meta on its own line). A long German name wraps inside the room. There are no dark empty slots.
- [ ] The empty page has a German kicker, the quiet sharing-levels card and the warm canvas.
- [ ] The club hero is the room: rounded foot, glow, seal, "You" ring with no duplicate initial, and one note card.
- [ ] The note appears exactly once (D11).
- [ ] Key row:
  - members see only "Add a title", and only when allowed
  - owners and admins see Add / Invite / Ask, or "Start a rail" when there are no rails
  - Invite opens `ClubInviteSheet`
  - no floating capsule remains
- [ ] Tabs read "Rails · This week · Polls" / "Listen · Diese Woche · Umfragen", with counts, and the rule fades in place. They pin under the compact bar (H1–H3).
- [ ] This week: the last 7 days grouped by day with covers and "You". Nil or old entries go under Earlier. The quiet week has its own copy. Duo clubs keep the existing line.
- [ ] Polls: "You asked", the deadline when `closes_at` is set, title options with a cover and a separate open target, votes as well as a percentage.
- [ ] Joining a club opens it. The join sheet blocks swipe-down once a code is typed (N7).
- [ ] Home room pixels are unchanged at 320 / 390 / 430 after the seal and threshold move.

**Accessibility and localisation**
- [ ] Every new control is at least 44 pt. Rows activate programmatically (no `.ignore` without actions).
- [ ] At accessibility sizes the switch, keys and tiles stack as specified.
- [ ] Reduce Motion: no travel, no entrance, instant scrolls.
- [ ] Every new string has German. EXISTING strings are byte-identical to the shipped ones.

## 14. Verification (each lane, then the integrator)

```bash
# Build (own derived data; never the owned simulator)
xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'id=<lane-sim-uuid>' \
  -derivedDataPath /Users/max/.claude/jobs/1fb75ce2/tmp/<lane>/dd CODE_SIGNING_ALLOWED=NO build

# Unit tests for the lane's suites (no write variable)
xcodebuild ... test -parallel-testing-enabled NO -only-testing:KuroTests/<Suite>

# After renders (only the lane's own suite, only into docs/discover-clubs-2026-11-03/after/)
TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1 xcodebuild ... test -parallel-testing-enabled NO \
  -only-testing:KuroTests/DiscoverAfterSnapshotTests   # or ClubsAfterSnapshotTests

# Gates
scripts/quality-gates/check_branded_states.sh
scripts/quality-gates/check_architecture.sh
scripts/quality-gates/check_navigation.sh
git status --short   # no committed PNG outside docs/discover-clubs-2026-11-03/ changed
```

The integrator also runs `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh` and the full `KuroTests` once on the integration simulator. It then updates the Rule 1/2 documents and commits the after renders next to `../before/`.
