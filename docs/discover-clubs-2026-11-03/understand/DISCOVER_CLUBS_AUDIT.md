# Discover + Clubs audit against Home (2026-11-03, "before")

**Owner request (2026-11-02, night):** "We still need to adjust the way or the design of the Discover page. We have to design the Clubs page, which is good actually, but it could be a bit better. Really think about this and execute overnight. Take the homepage as the main thing."

**Design authority:**
- Home (`Kuro/Views/Home/*`)
- the approved prototype `tools/design-directions/instrument.html?switch=poster`
- `docs/prototype-fidelity/PROTOTYPE_SPEC.md` and `LANE_AMENDMENTS.md`
- the navigation contract `docs/superpowers/specs/2026-11-02-navigation-contract-design.md`

The sibling extraction `understand/HOME_GRAMMAR.md` (another lane, same night) states Home's rules in detail. This audit uses the same rules and does not repeat them.

**Scope:**
- Discover: `Kuro/Views/EditorialDiscoverView.swift`, `EditorialDiscoverFrames.swift`, `DiscoverOneThingCard.swift`, `Kuro/Discovery/*`
- Clubs: `ClubsView.swift`, `ClubDetailView.swift`, `ClubDetailShellComponents.swift`, `ClubDetailTabComponents.swift`, `ClubCreateSheets.swift`, `ClubRoomStyle.swift`, `Home/HomeClubRoom.swift`

Read-only: no source was changed. The audit commit contains only this file and the PNGs in `../before/`.

---

## 0. The short version (ranked)

| # | Problem | Where | Severity |
|---|---|---|---|
| P1 | **Discover and Clubs paint pure white `#FFFFFF`; Home paints warm `#FFFEF8` / `#F5F5F3`.** Paging Home → Discover → Collection → Clubs jumps from warm paper to clinical white. This is the single biggest "different app" signal. | `EditorialDiscoverView.swift:118`, `ClubsView.swift:52`, `ClubDetailView.swift:98`, `ContentView.swift:982-988` (`Section.canvas` falls to `kuroBackground` = `kuroCanvasPage`) | High |
| P2 | **Discover is one grammar repeated: a 19 pt regular heading, then poster frames, ten times.** There is no card, key, material, count or rhythm change. "New to you." is a 2-column grid of 8 tall frames (≈1 100 pt). The full All page is ≈3 400 pt of near-identical rows. Home, by contrast, alternates glance card → scene cards → tiles → calendar → club room. | `EditorialDiscoverView.swift:188-326`, `DiscoverGridSection` (`EditorialDiscoverFrames.swift:525`) | High |
| P3 | **Section headings don't speak Home's type.** Discover and the Clubs list use `KuroSectionHeader(.title)`, which is 19 pt **regular**, untracked (`KuroSectionHeader.swift:38`). Home's "Coming up." is 24 pt w550 at −0.85, and its in-feed heads ("Also watching") are 15 pt w550 at −0.2 with a 10 pt muted count. Club detail uses yet another head (`kuroRoleText(.title)`, 19 semibold, tracked). That gives three heading styles across three pages. | `EditorialDiscoverFrames.swift:579-596`, `ClubsView.swift:156`, `ClubDetailTabComponents.swift:262,596` | High |
| P4 | **Four different "club" surfaces.** (a) Home: the rounded dark **room** with glow, seal, kicker, serif name, positional member fills and a warm note card (`#F5F6EF`, serif quote). (b) Clubs invitation: the same room. (c) Clubs **list**: white hairline cards with an art strip; the room colour shows only in empty art slots. (d) Club **detail** hero: a flat full-bleed `#252B28` band with no radius, glow or seal, white circle initials, and a **white** sans note card. The club the reader taps on Home does not look like the club page it opens. | `ClubsView.swift:509-593`, `ClubDetailShellComponents.swift:134-216, 229-293`, `HomeClubRoom.swift` | High |
| P5 | **Discover's medium choice is a 13 pt word row ("All · Anime · Manga")**, not Home's medium switch (36 pt heavy words, art clipped into the selected word, hairline + ink rule). It is the first control on the page and reads as a filter chip strip. | `EditorialDiscoverFrames.swift:152-203`, `EditorialDiscoverView.swift:198` | Medium-high |
| P6 | **Nothing on Discover or Clubs uses the artwork material** (`ArtworkMaterialStore`). Home's colour comes only from each title's material; Discover's lead frame is a bare picture on white, and club rail cards are bare covers. Neither page reads `@Environment(ArtworkMaterialStore.self)` (grep: 0 hits in the audited files). | all audited view files | Medium-high |
| P7 | **Club detail duplicates the same member note** in the hero ("Mina on Frieren …") and again under its rail, both hidden behind "May contain spoilers. Tap to read.". On a fresh club that is the only "voice" on screen, shown twice and closed twice. | `ClubDetailShellComponents.swift:202-206` (`ClubRoomCopy.firstNote`) + `ClubDetailTabComponents.swift:350-358` | Medium |
| P8 | **Club bottom bar is three unlabeled SF Symbols in a floating white capsule with a drop shadow** (`plus`, `person.badge.plus`, `chart.bar`). No other Kuro page has a floating toolbar, and Home's controls are keys. Two behaviours are also wrong: "Invite members" opens **Settings** (`ClubDetailView.swift:351`), and "Add a title" always targets `rails.first` (`:350`), so with no rails the tap does nothing (N9 dead tap). | `ClubDetailShellComponents.swift:295-357`, `ClubDetailView.swift:348-353` | Medium |
| P9 | **The "This Week" tab is labelled "Active" / "Aktivität".** It is an undated feed of every member status ever, with no covers, although each entry already carries `coverImage` (`ClubDetailTabComponents.swift:497, 553`, never drawn). It reads as a plain log, while Home shows the same kind of activity as a room row with a title and an arrow. | `ClubDetailView.swift:29-44`, `ClubDetailTabComponents.swift:485-717` | Medium |
| P10 | **Skeletons are nearly invisible.** Discover and the Clubs list draw `kuroBlack05` (5 % black). Amendment 18 set skeleton blocks to 8 % ink (`KuroSkeleton.blockInkOpacity`) so they read on warm canvases. The bespoke skeletons bypass `KuroSkeleton`. | `EditorialDiscoverFrames.swift:425-441, 599-640`, `ClubsView.swift:465-504` | Medium |
| P11 | **Clubs list cards wrap their meta badly at 390.** "Progress shared · 5 members · 3 hr. ago" breaks beside the initials row. A club with two covers shows two dark empty slots that read like broken images. A club with no covers is a 120 pt black band with one serif letter. | `ClubsView.swift:541-592`, `ClubArtStrip` `:597-635` (render `clubs-list-full-390.jpg`) | Medium |
| P12 | **Poll options that are titles are text only.** `ClubPollOption.media_type/media_id` exist (e.g. "Mushishi"), but the row draws only the label: no cover, and no way to open the title (N9). `closes_at` is never shown, so open polls give no deadline. | `ClubDetailTabComponents.swift:971-1049`, `ClubModels.swift:79-97` | Medium |
| P13 | **Two retry styles inside one state family.** Discover empty shows an outline capsule "Try again" (`KuroStateView`); Discover and Clubs offline and failed show an ink-rule "Try again →" (`KuroOfflineView` / `KuroErrorView`). Empty also says "browse the catalogue" while offering no browse action where Browse is a pager page. | `EditorialDiscoverView.swift:168-182`, renders `discover-empty-390.jpg` vs `discover-offline-390.jpg` | Low-medium |
| P14 | **The manga lead frame is a 4:5 cover up to 560 pt tall** (`DiscoverLeadFrame.pictureHeight`). On the Manga page the first screen is one cover and nothing else. | `EditorialDiscoverFrames.swift:374-376`, render `discover-manga-top-390.jpg` | Low-medium |
| P15 | **The viewer appears as a stranger in their own club.** Initials include the viewer, so Max and Mina both show as "M". The closed poll reads "Max asks", not "You asked". Initials are white rings on the room instead of Home's positional fills (`ClubRoomPalette.memberFills`). | `ClubDetailShellComponents.swift:156-161`, `ClubDetailTabComponents.swift:890` (`askerLine`) | Low-medium |
| P16 | **Joining a club doesn't open it; creating one does.** `JoinClubResponse.club_id` is available, but join only shows a toast. | `ClubsView.swift:114-119` vs `:219-225` | Low |

Positive baseline worth keeping:
- Discover: the editorial-first order and the lead "Today's pick" frame; "See all" as a journey page with ✕ and the compact bar.
- Clubs list: the branded empty invitation in the room language.
- Club detail: the compact paper bar with back/settings/✕, the Active tab's prose rows, the poll results' ink bars, the honest duo-club empty copy, and the create/join sheets' copy and discard guard.

---

## 1. Renders ("before", 390 pt, 1x)

All renders are in `../before/` (33 PNGs, 390 px wide; tall ones are full pages). How they were made:
- built on a fresh lane simulator `Kuro-Lane-dc-audit` (iPhone 17 Pro, iOS 27.0; the owned simulator was booted, so cloning was refused)
- built with `CODE_SIGNING_ALLOWED=NO` and `-parallel-testing-enabled NO`
- rendered by a temporary Swift Testing suite over the in-process stub PostgREST endpoint (`ClubsHarness` / `StubServer`)
- hosted in a scene-attached window and rasterized with `FixtureRaster` (box-averaged 1x)

| Area | Files |
|---|---|
| Home (comparison) | `home-anime-top-390.jpg`, `home-anime-full-390.jpg`, `home-manga-top-390.jpg`, `home-manga-full-390.jpg` |
| Discover, content | `discover-{all,anime,manga}-top-390.png`, `discover-{all,anime,manga}-full-390.png`, `discover-all-more-sections-full-390.jpg` |
| Discover, states | `discover-loading-390.jpg`, `discover-empty-390.jpg`, `discover-offline-390.jpg` (first load), `discover-offline-with-content-390.jpg` (band over content), `discover-failed-390.jpg` |
| See all | `discover-see-all-top-390.jpg`, `discover-see-all-scrolled-390.jpg` (journey page in `JourneyHost`) |
| Clubs list | `clubs-list-top-390.jpg`, `clubs-list-full-390.jpg` (3 clubs: full art, partial art, no art + long German name), `clubs-empty-390.jpg`, `clubs-loading-390.jpg`, `clubs-offline-390.jpg` |
| Club detail (journey) | `club-detail-rails-top-390.jpg`, `club-detail-rails-scrolled-390.jpg` (compact bar), `club-detail-rails-bottom-390.jpg`, `club-detail-rails-full-390.jpg`, `club-detail-active-full-390.jpg`, `club-detail-polls-full-390.jpg` |
| Sheets | `club-create-sheet-390.jpg` (from the empty invitation's "Start a club"), `club-join-sheet-prefilled-390.jpg` (through the `kuro://join/<code>` prefill path), `club-create-rail-sheet-390.jpg`, `club-create-poll-sheet-390.jpg` |

Fixture caveats (read before judging pixels):
- **Page bodies only.** The app header (`KuroHeaderNew`) and pager are not composed. The top ~44 pt of each page shows the iOS 26 scroll-edge blur over the first row ("All · Anime · Manga", "Your clubs."). In the app the header sits there.
- **Artwork is fixture art.** Covers come from `tools/design-directions/assets/` and do not match their titles. Judge layout, not pairing.
- **English only.** `KuroLocale` has no override hook. The simulator region gives "Monday, 2. November" and "75 %" (en_DE formatting).
- **Flags are the test graph's defaults.** Club reactions, streaming "our services", realm rails (Tonight's shelf, Hidden gem) and Because-You did not render, so they are audited from code only.
  - **The live app differs in two visible ways.** `clubs_reactions_v1` is 100% live, so live rail cards carry a reaction row (`ClubReactionMenu`) under every title, which these renders omit. With the series flags at 100% live, Discover shows "Browse the catalogue" at the end of the page and in the empty state (`DiscoverBrowseEntry`). The renders show the legacy pager order without that button, so the empty state in P13 is the legacy world.
- **Create sheet from the list.** "Start another club." could not be activated programmatically (see §6, "Programmatic activation fails"). The create sheet was rendered from the empty invitation's button, which presents the same `CreateClubSheet`.
- **Join sheet.** Rendered prefilled with a fixture code (`AbC12xYz`) through the deep-link path; `PasteButton` shows disabled with no pasteboard.
- **Accessibility setting.** Programmatic activation needed app accessibility enabled on the lane simulator (`com.apple.Accessibility ApplicationAccessibilityEnabled`). It only matters for re-running the renders.

How to re-render:
- The harness is kept outside the repo at `/Users/max/.claude/jobs/1fb75ce2/tmp/DiscoverClubsBeforeTests.swift`.
- Copy it into `KuroTests/`, then run with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1` and `-only-testing:KuroTests/DiscoverClubsBeforeTests`.
- Set `TEST_RUNNER_KURO_DC_FOLDER=after` to write into `../after/`.
- Always use `-only-testing`: four other suites also honour the write variable and would rewrite committed evidence.

---

## 2. Home, in five lines (what "the same app" means)

Full rules: `HOME_GRAMMAR.md` §0 and §14. In short:
1. **Warm paper canvas:** `#FFFEF8` for anime, `#F5F5F3` for manga, changing with the medium. Ink `#252625`, muted `#696C6B`.
2. **Type is SF sans, hand-set and tracked.**
   - Eyebrow: 9 pt, tracking 1.05, uppercase `#666C68`.
   - Section head: 24 pt w550 −0.85, with a 10 pt summary on the right.
   - In-feed head: 15 pt w550 −0.2, with a 10 pt count.
   - Titles: 17 pt w550 −0.35 on art, 12 pt w500 in tiles.
   - Serif only for the club name, the club quote and a few editorial lines.
3. **Colour comes from artwork:** each title's `ArtworkMaterial` (base→deep gradients, wash/edge).
4. **Quiet cards:** radius 5/8/18/24, 1 pt hairlines, near-invisible drops.
5. **Physical 44 pt keys:** `KuroAdvanceKey` light/material/ink/dark. Branded states; short one-shot motion.

---

## 3. Discover in detail

### 3.1 Page frame and palette
- **Canvas `#FFFFFF`** (P1). The header paints the page's canvas (`Section.canvas`), so the header turns white too. Under amendment 8 there must be no seam; today the seam is the whole page.
- **Gutter** 20/16 (`DiscoverLayout.gutter`) matches Home. **Section spacing** is a uniform `xl` 32 between every section (`EditorialDiscoverView.swift:190`), whereas Home varies its rhythm (12 / 18 / 24 / 32).
- **Missing art** shows `kuroMissingArt #E6E6E6`, a cold grey on warm paper.

### 3.2 Top of page
- **Word row "All · Anime · Manga"** (P5). It is 13 pt, and the selected word is semibold with a 16×1.5 rule. Home's switch has two words and no "All"; Discover's three-way choice (with All mixing both mediums) is a real product difference. Keep it, but in Home's switch language: the heavy words and rule, or at least the compact `KuroMediumSwitch` that Folio already uses. The canvas should follow the medium as Home's does (anime warm, manga `#F5F5F3`).
- **Lead frame "Today's pick"** (`DiscoverOneThingCard` → `DiscoverLeadFrame`).
  - It is a full-width picture (banner 2.2:1, or cover 4:5 up to 560 pt), then the kicker, a 26 pt semibold −0.85 title and the argument.
  - It is good editorially, but it is the only thing above the fold and it carries no material, no key, and nothing to do except open.
  - Home's scene card puts the title on the artwork's own material foot, with a key.
  - Data the RPC already returns but the frame doesn't show: `DailyFeature.score`, `genres`, `year`, `format`. The comment "No score or genre in the frame" is a rulebook §14.5 decision; revisit it only if the owner wants it.
- **Kicker tracking** is 2.1 (`kuroKicker()`), while Home's eyebrow is 1.05, so Discover's kickers read wider and lighter (HOME_GRAMMAR §14.6).

### 3.3 Sections
- **Headings** are `KuroSectionHeader(.title)` at 19 pt regular, with "See all" in 13 pt medium ink (P3). The file comments still say "serif section header" (`EditorialDiscoverFrames.swift:4, 471, 524, 578`); that is stale since 2026-11-01.
- **Frames** (`DiscoverFrame`) show a cover (radius 4), a 15 pt medium title on two reserved lines, and one 13 pt quiet line ("2024 · 12 eps" / "Ep. 7 · 21:30" / "2 in your clubs").
  - The frame is clean, but it is the only element type on the page.
  - The reserved second line leaves big gaps under short titles (see "Mushishi" in `discover-see-all-top-390.jpg`).
- **Grids:**
  - "New to you." / "Manga new to you." have 8 items; "Classics" and "Top rated" (behind "N more sections") likewise.
  - Each grid is a 2-column block of large frames (≈170×243 + text), so one grid fills more than a screen (P2).
- **Rails:** "Airing today.", "Essential anime.", "Trending" and "Essential manga." are horizontal rails of 132–170 pt frames. Rails and grids alternate, but at the same scale and on the same white, so there is no visible hierarchy.
- **"Trending." and "Top rated." rail filters** ("All · Short · Long · Finished") are local refinements, correct per the editorial-first rule. They reuse the 13 pt word row, which then appears twice on the page in two meanings: page medium, and rail filter.
- **"N more sections"** is a secondary `KuroInkButton` (outline capsule). The expanded state persists in `UserDefaults.standard` (`kuro_discover_show_more`) for the whole device, not per account.
- **"Browse the catalogue"** is an outline capsule at the very end, offered only where Browse is not a pager page (`DiscoverBrowseEntry`). In the live order (series flags at 100%) Browse is not a page, so this button is the only path to the full catalogue from Discover, and it sits after ten sections (≈3 400 pt down).

### 3.4 Interaction
- Frames open the title through `routes.openMedia` (journey, N9 ✔). Quick add, the list editor and Add to club exist **only** in the long-press context menu (`DiscoverFrameMenu`), so nothing on the page shows a way to save a title. Home makes saving a visible key.
- No motion: no entrance and no count roll. Home's artwork entrance (380 ms) and press settle apply to its own components only.

### 3.5 States
- **Loading:** a bespoke skeleton (lead block, two rails) in `kuroBlack05`, plus `KuroScrubLine`. Almost invisible at 5 % (P10). The shapes match the real layout ✔.
- **Empty** (`discover-empty-390.jpg`): `KuroStateView(.empty)` with "Nothing to show yet." and an **outline-capsule** "Try again" (P13).
- **Offline first load:** `KuroOfflineView` (mountain line, ink-rule "Try again →") ✔ branded.
- **Offline band over content:** shown at the top of the content, above the word row. In the render it sits under the scroll-edge blur. In the app it sits under the header and pushes the page down by ~50 pt.
- **Failed:** `KuroErrorView`, "Couldn't load Discover." ✔.
- **Refresh failure with content:** a transient banner, "Couldn't refresh. Try again." ✔.

### 3.6 See all (journey page)
- Has the real ✕ and compact bar ✔ (N3, H1). Headline 26 semibold, a count line, the "Filter these titles" field (hairline underline), and a 2-column grid of the same frames.
- Good and consistent with the journey chrome. It inherits P1 (white) and the reserved-line gaps.

### 3.7 Data available but not shown (no backend changes needed)

| Source | Field | Shown? | Note |
|---|---|---|---|
| `AnimeCard` / `MangaCard` (`discover_bundle`) | `averageScore`, `genreList`, `popularity`, `favourites`, `bannerImage` (anime) | no | Banners exist for rail items but only the lead uses one. A Home-like "scene" treatment for one item per section is possible from data already loaded. |
| `DailyFeature` | `score`, `genres`, `year`, `format` | no | Only kicker, title and argument are drawn. |
| `DiscoveryStore.airingSlots` / `ReleasesStore.upcomingAirings` | stated air time + episode | yes, Airing today only | Could also feed a Home-style "Coming up" glance on Discover; the data is the same `next_airing_at`. |
| `SocialActivityStore.friendCount` | friends tracking | yes, as the frame's line ("2 in your clubs") | Replaces the year line; fine. |
| `LibraryStore.isTracked` | saved state | VoiceOver value only | No visible "on your list" mark on frames. |
| `vm.tonightShelfSubtitle` (flag `discover_realm_rails_v1`, 0%) | realm blurb | **assigned, never rendered** | `EditorialDiscoverView.swift:644`. |
| `BecauseYouCard.reasonTitle` (flag `personalized_new_to_you_v1`, 0%) | "Because you liked X" | yes, in the heading | |

---

## 4. Clubs in detail

### 4.1 Clubs list (`ClubsView`)
- **Page:** a white canvas (P1) and the heading "Your clubs." via `KuroSectionHeader` (26 pt) with the kicker "PRIVATE" (2.1 tracking) (P3).
- **Card** (`ClubListCard`):
  - a 4-cover art strip on a room-dark backing, 2 pt gaps, no radius inside
  - a serif 22 pt club name ✔ (amendment 1) and an ink unread dot
  - initials in grey circles, plus a 13 pt meta line with audience, members and relative time
  - the activity preview as a 15 pt light line
  - white card fill, radius 12, hairline border

  Problems:
  - It is the only white hairline card in the club family (P4).
  - The meta line wraps beside the initials (P11).
  - Empty art slots render as dark rectangles: the strip keeps four slots and fills the rest with `ClubRoomPalette.room`. That is deliberate per the code comment, but next to real covers it reads as missing images.
  - A club with no art becomes a black 4:1.4 band with one serif letter. It is heavy, and on the list it outweighs the clubs that have real art.
- **Unread:** an 8 pt ink dot after the name; VoiceOver label via `ClubsListCardRules` ✔.
- **Actions after the list:** "NEW / Start another club. →" and "INVITE CODE / Join a club. →" are ink-rule invitation rows, Discover's "See all" language. Home uses keys and the room's own buttons (the invitation's dark key and quiet disclosure). That is two button vocabularies on one page: the invitation buttons when empty, the ink rules when not.
- **Empty** (`clubs-empty-390.jpg`): the room invitation is the best-matched surface in the audit ✔. Minor issues:
  - The kicker "PRIVATE CLUBS" is not translated (`ClubsEmptyCopy.kicker` returns the English string for German).
  - The room sits at the top of an otherwise empty white page; a warm canvas would carry it.
- **Loading:** the card skeleton in `kuroBlack05` (P10).
- **Offline / failed:** branded ✔. The read never shows the invitation on failure ✔ (`ClubsListRules`).
- **Data available, not shown on the card** (`ClubListRow`):
  - `rail_count` and `poll_count`. The detail hero shows "3 rails · 1 open poll", the list does not.
  - `loading_state`.
  - `cover_images` beyond four (fine).

### 4.2 Club detail (`ClubDetailView`, journey page)
- **Chrome:** `JournalStatusBar` with white circles over the room, then a paper compact bar with the club name, ellipsis (settings) and ✕ ✔ (N1–N3, H1–H3, edge swipe restored with `KuroInteractivePopEnabler`).
- **Hero** (`JournalHeroSection`), which is P4:
  - It is a flat full-width band of `ClubRoomPalette.room`, with no radius, glow or drop. Home's and the invitation's room has all three.
  - Its content: the 4-cover strip (radius 8); the audience kicker "PROGRESS SHARED" (micro, 2.1 tracking); the serif 30 pt name; the description; white-ring initials; the summary "5 members · 3 rails · 1 open poll"; and a white note card.
  - What Home's room has and the detail doesn't:
    - the seal and the "YOUR PRIVATE CLUB" kicker
    - positional member fills (`#D0D8CB / #ADBBA6 / #899A82`)
    - the warm note card `#F5F6EF` with drop and white border
    - the note's cover, the **serif quote** and "{title} ›"
    - the footer "Shared stories. Your people."
  - The detail's note card is white, uses a sans byline, and is collapsed behind a spoiler gate. Home shows non-spoiler notes openly and gates only notes whose `spoiler_scope` says so. The detail treats every rail note as a possible spoiler (`ClubNoteCard`) because rail notes carry no scope. The behaviour is defensible, but it makes the room's one human line a grey "Tap to read" twice (P7).
- **Tabs** (`JournalTabBar`): Rails / Active / Polls at 15 pt, with the selected word semibold and a 2 pt ink rule that travels (matchedGeometry; a fade under Reduce Motion ✔). It matches nothing on Home. It is the same idea as Discover's word row, but at a different size and weight.
- **Rails tab:**
  - **Rail heads** are 19 pt semibold tracked, with "N titles" in 13 pt, a 44 pt grey circle "+" and the description.
  - **Cards** are 112–144 pt covers (radius 8) with a 13 pt medium title, progress ("Ep. 7 of 28"), and "Mina, Jules watching".
  - A dashed "+" placeholder card ends each rail for admins.
  - Empty rail: "Nothing here yet." in body size, which looks unstyled next to the rails.
  - Rails are separated by hairlines.
  - It works, but it is a third poster-rail grammar after Discover's frames and Home's leaves and tiles. There are no keys; Plan/Remove is in the context menu only.
- **Active tab** (P9):
  - **Grouping:** member status rows grouped by day under 19 pt semibold date heads; the prose is "**Mina** reached episode 14 of **Frieren**", with the time on the right.
  - **Data:** covers are available on every entry but unused. Statuses come from every rail item, so "Active" can show updates from months ago under their dates; the owner's word "This Week" is not what the tab does.
  - **Pace banner** ("You're 3 episodes behind the group …") is a grey rounded box after the list, `kuroCanvasQuiet`. It renders only for progress clubs with ≥ 3 members.
- **Polls tab:**
  - **Card:** white, hairline, radius 12, with "Mina asks", the 19 pt question, and option rows (circle/check glyph, label, %, 3 pt bar), then a vote count. Closed polls sit under a "Closed" head.
  - **Action:** "Ask a question →" as an ink-rule row for admins.
  - **Problems** (P12, P15):
    - Title options show no cover and can't be opened.
    - `closes_at` is missing.
    - The viewer's own poll reads "Max asks".
    - Percentages carry no count per option.
- **Bottom bar** (P8): a floating capsule overlapping content (`.safeAreaInset`), with icon-only buttons.
  - "Add a title" goes to `rails.first`, even if that rail is locked for members; admins can add anyway.
  - With no rails the tap does nothing.
  - "Invite members" opens Settings, where the invite code lives, but the label promises an invite flow.
  - At 390 the capsule covers the second rail's titles while scrolling (`club-detail-rails-scrolled-390.jpg`).
- **Data available, not shown** (`ClubBundle`):
  - `ClubRailItem`: `average_score`, `year`, `format`, `my_rating`, `my_status` (shown only as progress), `added_by` (used only to attribute notes), `reactions` (behind `clubs_reactions_v1`).
  - `ClubPoll`: `closes_at`, `created_at`.
  - `ClubPollOption`: `media_type` and `media_id` (titles).
  - `ClubMember`: `role` and `joined_at` (Settings only).
  - The activity entry's `coverImage`.
  - `ProviderAvailabilityStore.fetchClubSharedProviders` (flag `streaming_availability_v1`, 0%).

### 4.3 Sheets (tools)
- **Create club** (`club-create-sheet-390.jpg`):
  - Layout: Cancel (glass capsule, system), the kicker "NEW CLUB", the 26 pt "Start a club.", two grey filled fields (`kuroCanvasQuiet`, radius 12), and three audience rows with a check.
  - The "Create club" ink capsule shows grey while disabled.
  - Discard guard ✔ (N7), grabber ✔ (N8).
  - Visually it is a generic iOS form on white. Nothing from the room (the club's own surface) carries into the act of creating one.
- **Join club:** the code field in 24 pt monospaced with 3 tracking, a hint, the system `PasteButton` capsule and "Join club" ✔. Same white form language.
- **Create rail / poll:** the same form family (`ClubCreateSheets.swift`).
- After **join**, the club is not opened (P16).

### 4.4 Home club room (`HomeClubRoom`), for consistency
- It is the reference club surface: room, seal, kicker, serif name, member stack, warm note card with cover and serif quote, the "New in the club" row with ›, and the footer with "N updates".
- **Drift to unify** (HOME_GRAMMAR §14):
  - The compact threshold is 330 here vs 328 in `ClubRoomMetrics`.
  - The seal is 36/30 here vs 43/36.
  - `ClubsView` inlines note shadow and border literals.
- Tapping the masthead opens the club journey (`routes.openClub`), where the reader lands on the flat band of P4.

---

## 5. Navigation contract compliance

| Rule | Discover | Clubs |
|---|---|---|
| N1/N2 back, swipe-back | See all is a journey root: ✕ only ✔ | Club page: back when pushed, edge swipe restored ✔ |
| N3/N4 ✕ collapses | ✔ (See all, titles) | ✔ |
| N5 dedupe | `DiscoverSeeAllPolicy.pageID` ✔ | `JourneyPage.club(id:)` ✔ |
| N7 tools return | the tracking editor and add-to-club (context menu) go through routes ✔ | settings, rail, poll and add-item sheets `.kuroLeavesJourney()` ✔; discard guard on create club ✔; **join sheet has no discard guard** (code typed, swipe-down loses it; low) |
| N8 closable | — | ✔ Cancel + grabber on create/join |
| N9 every tap goes somewhere | frames ✔, lead ✔ | rail cards ✔, Active rows ✔; **poll title options are dead text** (P12); **bottom-bar "+" is a dead tap with no rails** (P8) |
| N11 leaving on purpose | "Browse the catalogue" opens Browse as a journey (`routes.openBrowse` → `show(.browse)`) ✔ | Home room → club journey ✔ |
| H1–H3 compact bar | See all ✔ | Club ✔ |

---

## 6. Accessibility

- **Headers.** Discover headings `.isHeader` ✔; club rail titles ✔; the lead frame's kicker is hidden and the frame is one element ✔.
- **Programmatic activation fails on rows built as `Button` + `.accessibilityElement(children: .ignore)` + `.isButton`** (A4).
  - Activation by label returned `false` for "Start another club." (`ClubInvitationAction`, `ClubsView.swift:456`).
  - It returned `true` for plain Buttons ("Start a club", the tab words, "Anime"/"Manga").
  - The same pattern wraps `DiscoverFrame` (`EditorialDiscoverFrames.swift:276`), `DiscoverLeadFrame` (`:417`) and the club list cards (`ClubsView.swift:179`).
  - VoiceOver usually falls back to a synthesized tap at the activation point, so this may work for VoiceOver users. Voice Control and Switch Control, which rely on the element's action, should be checked on a device. Low effort to fix: use `.accessibilityElement(children: .combine)`, or keep `.ignore` and add `.accessibilityAction { … }`.
- **Unlabeled toolbar.** The bottom-bar glyphs have labels ✔ but no visible text; at large text sizes they stay 18 pt icons (`maxSize 26`).
- **Dynamic Type.**
  - Most text scales (`kuroCustom` / roles) ✔.
  - Grids drop to 2 columns at AX sizes ✔.
  - Club list initials and meta stack vertically at AX ✔.
  - The poll % bars are fixed 3 pt and are `accessibilityHidden`, with the values in the label ✔.
- **Contrast.**
  - `kuroInkQuiet #6B6B6B` on white is 5.3:1 ✔.
  - The room's `kuroRoomTextSecondary` lines on `#252B28` look fine.
  - Skeletons at 5 % are below any useful contrast, but they are decorative and hidden ✔.
- **Localisation.** Every string audited goes through `KuroLocale` except:
  - `ClubsEmptyCopy.kicker` (German returns "PRIVATE CLUBS")
  - `JournalTabBar` raw identifiers (fine; labels are localised)
  - "Clubs" in the header (proper noun)

---

## 7. What the redesign lane should hold to (no backend changes)

1. **One canvas.** Discover and Clubs paint Home's warm canvas. Discover follows its medium (All/Anime warm, Manga `#F5F5F3`). Change `Section.canvas` and the pages together (seam rule).
2. **One type ramp.** Use Home's hand-set heads (24/w550/−0.85 section, 15/w550/−0.2 in-feed, 9 pt 1.05 eyebrow, 10 pt muted counts) on both pages and their tabs, instead of `KuroSectionHeader(.title)` regular.
3. **One club surface.** List cards, the detail hero and the Home room share `ClubRoomBackground`, the seal, the kicker, positional member fills and the warm note card. The detail hero becomes the room (rounded or full-bleed with glow), not a flat band. The note is shown once.
4. **Colour from artwork.** Use `ArtworkMaterialStore` for the Discover lead (material foot like the scene card) and for any featured item; never a per-title table.
5. **Keys, not hidden menus,** where a page invites an action: a visible plan key on the Discover lead and on featured frames, using `KuroAdvanceKey` faces. Leave the context menu as is.
6. **Rhythm.** Break Discover's repeated poster grids:
   - fewer, smaller grids (a 3-column or 4-item grid instead of 8 big frames)
   - one Home-like card per screen (a glance or scene style)
   - Browse surfaced earlier
7. **Club actions.** Replace the icon capsule with labeled room-language actions or keys. "Invite" opens the invite (the code and share). "Add" chooses or creates a rail. Join opens the club.
8. **Use data already loaded:**
   - the activity entry covers
   - poll title options with cover and link, and the `closes_at` deadline
   - list `rail_count` / `poll_count`
   - "You" for the viewer
9. **States:** skeletons via `KuroSkeleton` (8 % ink); one retry style.
10. **Keep:** the editorial-first order (rails curated; rail chips stay local refinements), the journey chrome, the branded empty invitation, the create/join copy and discard guard.
