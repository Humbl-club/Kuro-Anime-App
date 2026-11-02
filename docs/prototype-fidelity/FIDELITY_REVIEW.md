# Fidelity review: Home (Task 10)

Compares the references in `reference/` with the native renders in `native/` (see `native/INDEX.md` for the pairs).

**Scope.** This file covers the review of Home anime and Home manga (busy, full, undated and quiet, at 320, 390 and 430), plus the confirmed code-review findings from the same pass. Detail, Taste and first-run pages were not reviewed in this round.

**How the renders are made.** The English renders run under `-testLanguage en -testRegion GB` (see "Date format" below). The German renders run under `-testLanguage de -testRegion DE`. Native renders have no app header, so native y = reference y − 71.

## Status of every finding

Each finding is marked **fixed**, **justified** (the difference stays, with its reason), or **open** (it needs an owner ruling or backend work).

### Home anime

| Finding | Status | What changed or why it stays |
|---|---|---|
| Scene card foot colour (Demon Slayer teal, Attack on Titan slate) | **justified** | See note A. |
| Calendar row unit "S1 · Episode 6" | **fixed** | `HomeCalendarPresentation.rowUnit`: "S{n} · " prefix from the card's ladder season (`HomeView.seasonPrefix`). German "S2 · Folge 9". There is no prefix without a known season. |
| Undated: headline "2 new episodes" and the Demon Slayer footer row | **fixed (fixture)** | The undated fixture announces Demon Slayer episode 6 and Attack on Titan episode 9 without a date. Episodes 5 and 8 are therefore out (`availableUnits`, one before the next announced unit), so the page reads "2 new episodes" and "New episode available" through the product rule. Mob Psycho 100's new season is the third announcement. |
| Undated calendar card body | **fixed** | "No confirmed dates yet." band (§7.1, EN/DE) when no group is dated. Dates to come starts closed (`HomeCalendarPresentation.initiallyOpenGroup`: only dated groups open first). Open lists sit on the events fill (white on anime). |
| Club room width / bleed | **fixed** | `HomeFeedInsets.room` = −3 against the page gutter: 17–373 at 390, 13–307 at 320, 17–413 at 430. 32 pt above the room. |
| Paper feed side padding and card shadow | **fixed** | The calendar section and footer sit 2 pt inside the gutter (`HomeFeedInsets.feed`): 22 at 390 and 430, 18 at 320. The shadow is `0 2 6 −4`, cast by a shape inset 4 pt (`HomeCalendarPalette.cardShadowInset`), so there is no side spread. |
| Also watching tile at 320 ("Mob Psycho 100" wraps) | **fixed** | The text column is fixed: the prototype's `44px 114px` grid, 89 at ≤ 360. SF sets "Mob Psycho 100" at 88.5 pt, which the browser still fits in 88. The column stays flexible at accessibility sizes. |
| Also watching vertical composition | **fixed** | The 44 pt title button sits at the top of its 48 pt row. The 44 pt progress row has the count centred, and the 1 pt track sits 5 pt above the row foot, level with the key face's bottom. At accessibility sizes the track follows the count instead (2 pt under it), so a large count never sits on it. |
| Club note link "Finished Death Note ›" and activity "Jules started" | **open** | See note B. |
| Calendar day label "Fri 9 Oct" | **fixed (render locale)** | See note C. |
| Scrub / track / hairline half-point blur | **justified** | See note D. |
| Season tab face | **fixed** | The face is 31 pt tall (min height 31 with 8 pt sides), and the word and number are centred. |
| Light +1 glyph weight | **fixed** | Key caps are a light-weight symbol, matching the prototype's thin 16 × 16 SVG stroke. |
| Also watching material key glyph | **fixed** | Same light cap. The ink stays white. |
| Poster radius / shadow and S2 stamp | **fixed** | Radius 4. The shadow `0 3 7 −4` is cast by a 4 pt inset shape behind the poster, so the stamp no longer carries a shadow. The stamp is flush bottom-right, with only its top-left corner rounded (5). |
| Vertical rhythm, scenes → Also watching | **fixed** | The heading row has its 21 pt line box (SF 15/21), so the 25 / 12 margins measure as in the CSS. The scene stack spacing is 18; what remains is within about 1 pt (not measured further). |
| Calendar disclosure mark | **fixed** | Text glyph ⌄ / ⌃, SF 21 light, `#727d73`, placed off-centre as in the prototype. |
| Day label / chip weights 550 | **justified** | See note E. Row time is already `#58665b`. |
| Quiet: progress control width | **fixed** | The progress column has a minimum of 112 pt (104 at ≤ 360). The caught-up word wraps inside a 54 pt readout, so the divider stays put. |
| Club note cover art radius / shadow | **justified** | The code already uses the spec values (radius 3; `#252b2625`, y 3, blur 6 via radius 3). The remaining difference is the continuous corner curve against CSS circular corners, about 0.3 pt at radius 3. |
| Fixture: today's releases / "Show N more" | **fixed (fixture)** | The schedule is anchored to calendar days: today's rows are at 16:00, 17:00 and 18:00 while those times are still ahead, later days at noon. Busy and quiet have 3 today, 2 tomorrow and 1 in six days. Full has 6 on each of 8 days, giving "Show 3 more releases" and "Next 4 dates · 24 releases". Before this, the 23:40 render pushed the rows past midnight. |
| Fixture: club spoiler row | **fixed (fixture)** | Mina's ending-scoped note on Death Note is paired into the lead card (`HomeClubRoom.layout`). See note F for the glyph. |
| Fixture: caught-up totals (quiet) | **fixed** | The totals are the reference's (Demon Slayer 5, Attack on Titan 8), so quiet reads "Caught up 5 / 5" and "8 / 8". A caught-up tile shows a full trace: a tile shows no total, so its trace is everything out so far. |

### Home manga

| Finding | Status | What changed or why it stays |
|---|---|---|
| Whole page at 320 (clipped ~390 layout) | **fixed** | Root cause: Home measured its container on the scroll view. On the first pass, the manga leaves grid (fixed column widths, laid out from the 375 pt fallback) widened the scroll view to 374 pt, and the page never shrank to 320. Home now measures outside anything the content can widen: a frame with both bounds takes the proposed size. Small metrics now apply (88/11/119/10, 30 pt words). `mangaHomeRenders` asserts that the outer 8 pt on both sides stay canvas over the first 900 rows. |
| Quiet: caught-up leaves | **fixed** | PF-QA-1: the leaf key uses `homeKeyCaughtUp` with the released count, as the opening line and the detail page do. Chainsaw Man 25, Solo Leveling 9 and Jujutsu Kaisen 21 read Caught up. |
| Quiet: caught-up key face | **fixed** | `HomeLeafCaughtUpKey`: the light raised key (40 pt pale face, 1 pt `#c5cac4` rule, radius 6, 10 pt light check in `#767b77`), not interactive. |
| Quiet: caught-up readout | **fixed** | "Caught up" takes the "Ch." slot and the count stays under it. German keeps amendment 14: "Auf dem neuesten Stand" takes the count's lines, and the spoken label still has the position. |
| Undated: calendar card composition | **fixed** | Same as anime: the "No confirmed dates yet." band (13 pt on manga, on the card fill), and Dates to come closed. |
| Undated: headline "4 new chapters" | **open** | See note G. |
| Full: calendar content and "Show N more releases" | **fixed (fixture)** | 6 per day on 8 days: Today "6 releases" with "Show 3 more releases", then Tomorrow, +4 and +7 days, then "Next 4 dates · 24 releases". The button is radius 10, with a 1 pt `#d9e0d7` rule, inset 12. |
| Club room: spoiler disclosure | **fixed (fixture)** | Mina's ending note on Berserk is now in the fixture, and it renders as the in-card bordered row. See note F. |
| Club room: note link and activity copy | **open** | See note B. |
| Club room: size | **fixed** | Same −3 bleed (17–373 at 390). The height now includes the spoiler row. The remaining height difference is the missing "Finished" line (note B) and the quote's line break (note H). |
| Gap opening line → leaves | **fixed** | The leaves moved into the opening stack (12 + the opening's 6), so they sit 21 pt under the row and 20 under the quiet card. |
| Gap calendar → club room | **fixed** | 32 pt (`.club-room` margin-top). |
| Gap club room → footer | **fixed** | The footer's top padding is 28: the feed's 20 bottom plus `.app-end`'s 20, less Home's 12 stack spacing. |
| Manga leaf +1 face | **fixed** | 40 pt face (38 plus its border). The inner top highlight `#ffffff1f` and the drop `0 1 2 #28372a14` were already in `KuroKeyFace(.dark)`. |
| Manga leaf key glyph | **fixed** | 10 pt light cap at 0.75 of `#f8faf7`. |
| Calendar row "English edition" (Solo Leveling Volume 11) | **open** | See note I. |
| Calendar day label date format | **fixed (render locale)** | See note C. |
| Fixture: Berserk / Vinland Saga keys | **fixed (fixture)** | They are on hiatus in the fixture, so their released count is unknown. Their keys keep the +1, as the reference draws them, and they never block the quiet line. SPY x FAMILY in quiet reads Caught up (chapter 6 is tomorrow), where the reference draws a +1. That +1 would mark an unreleased chapter, which PF-QA-1 forbids. |

## Notes

**A. Scene foot material.** The prototype's two scene banners use hand-set colours. `build_art_materials.py` has an `OVERRIDES` table for exactly `anime1-banner.jpg` (#28484b) and `anime0-banner.jpg` (#465471), "to preserve the owner-liked Home colours". Without the overrides, the prototype's own algorithm gives #314049 / #20292e and #313a49 / #20262e. The native port derives the same values, and they match the measured native foot (#2e3c45/#212a2f and #2c3440/#2d3542, sampled across the gradient). The native card already paints base → deep at 135° from the title's material, as the Also watching keys do. `ArtworkMaterial.swift` ships no per-title override table, because the overrides were for the sample art only. Faking them in the fixture would hide the real behaviour, so the difference stays.

**B. Club verbs ("Finished {title} ›", "{name} started").** These need the note author's list status for that title. Home's club slice (`home_bundle_v1`, prepared migration `20261007040000`) carries no author id or status. `home_bundle_v1` is SECURITY INVOKER, so a lookup into a peer's `*_user_lists` returns nothing under RLS.

- **Exact path:** a SECURITY DEFINER helper gated by `shares_club_at_least(author, 'status')`, added to the slice as `author_status`, plus a client decode and the verb. That is backend work for a prepared migration and the local DB tests.
- **Rejected path:** a client join with `fetch_friend_activity_for_title` would match on display name, which can attach a verb to the wrong person.

Home keeps "{title} ›" and "{name} shared a thought" until the helper exists. Related fixture choice: Mina's notes are on Death Note (the reference's lead) and Jules's on Attack on Titan, so the Attack on Titan scene reads "Jules ›" where the reference reads "Mina + Jules ›". The alternative was a second Mina note on Attack on Titan, which would add a second row to the room.

**C. Date format.** English `KuroLocale` follows the device locale, so a US device reads "Sun, Nov 8" and a UK device "Sun 8 Nov". The reference's "Fri 9 Oct" (§7.1) and its 24-hour times are en_GB. The renders now run under `-testRegion GB` rather than forcing day-first dates on US readers. German reads "Mo. 9. Nov.".

**D. Half-point hairlines.** The fixture renders are drawn at 1 px = 1 pt. A 1 pt rule whose origin lands on a half point is blended over two pixel rows, so the scene trace reads grey instead of `#e9eeee`. Snapping every rule needs a display-scale-aware offset in each container, so it is left for a follow-up. On a 3x device the same rule covers 3 px with soft edges.

**E. Weight 550.** The type system maps weights to SF's named weights (`.medium` 500, `.semibold` 600). There is no 550 mechanism, and adding a variable-weight font path would be a new paradigm (Rule 4). Day labels stay semibold and the chip number medium.

**F. Spoiler row glyph.** The reference's ⌄ reveals the spoiler text in place. Home never receives spoiler text (the slice nulls it), so the row opens the title, where the reader can choose to read it. The row keeps a › to say it navigates. Its fill, rule and radius are the reference's (`#e9ede2`, `#ccd4c3`, 8).

**G. Manga undated headline.** With only undated volume announcements, Home cannot tell how many chapters are out: `availableUnits` needs a chapter row or a catalogue total. Server-side enrichment (`manga-chapter-enrich`, the chapters table) does know the latest released chapter, but `HomeBundle` does not carry it. Plumbing a `released_units` field through `home_bundle_v1` and `availableUnits` is backend work and needs an owner ruling. Until then the page says "Keep reading." with no count.

**H. Quote line break.** The prototype's Georgia quote breaks after "more." at 390. The native serif (`kuroEditorial`) sets "Famous" on the first line. The column and size match, so the difference is the face's metrics.

**I. "English edition".** The calendar row's right column says what kind of release a row is. Only the edition language would justify "English edition", and `ReleaseScheduleItem` has no edition-language field (the source is "anilist", "mangaupdates" or a publisher, not a language). The row keeps "Volume release" and needs an owner ruling or a schedule field.

## Code-review findings fixed in the same pass

- **PF-QA-1 (major):** the Home manga +1 now has the release ceiling (`HomeView.keyState` uses `homeKeyCaughtUp` for both media). Pinned by `HomeMangaLaneTests.mangaLeafKeyHasAReleaseCeiling`.
- **PF-QA-2:** the new-account block holds only while every entry is a bare plan (`HomeShelfPolicy.onlyBarePlans`, used by `HomeView` and `ContentView`). Pinned by `FirstRunLaneTests.newAccountEndsOnAStartedPlan`.
- **PF-QA-4:** the German club VoiceOver label agrees in number ("Mina hat", "Mina + Jules haben"; `HomeSceneFact.clubSpoken`).
- **SEC-1:** "Between us." hides member names while `social_activity_v1` is off and drops the loaded roster when the flag turns off (`DetailBetweenUs.headingNames`).
- **SEC-2:** Profile's "Clear cache" also clears the artwork-material cache, in memory and on disk. In-flight derivations cannot write a file back, because writes are gated by a generation counter. The disk folder is pruned to 1,500 files per launch (`ArtworkMaterialStore.clearAll`, `pruneDisk`). Not done: removing it on sign-out or account deletion. That matches the existing URLCache and detail-cache posture, as the finding notes.

## Truncated inputs (not reviewed)

- The Home manga findings list given to this pass was cut off mid-item at "Calendar day label date format". That item is fixed with the anime one (note C). Any findings after it were not received.
- The SEC-2 fix text was cut off at "call it from the". It was implemented as the Profile "Clear cache" call.

## Detail anime and manga (round 2)

This section covers the Detail screens. For those screens it replaces the scope line at the top of this file ("Detail … not reviewed in this round").

Pairs: `ref-detail-anime-390.png` / `native/detail/detail-anime-390.png`, `ref-detail-anime-top-390.png` / `detail-anime-top-390.png`, `ref-detail-manga-390.png` / `detail-manga-390.png`, `ref-detail-manga-top-390.png` / `detail-manga-top-390.png`. All detail renders were re-made under `-testLanguage en -testRegion GB`. Compare them unscaled: the reference sheet is 356 pt wide, and the native page fills the 390 pt window, so x offsets differ by the 17 pt sheet inset. The fixture host now drops the window's top inset (`safeAreaRegions = []`), because a page sheet has none. The `*-top-390` references show the sheet inside the app (header, 55 pt offset, 24 pt sheet radius). The native top renders are the page alone, without the system sheet chrome.

### Detail anime

| Finding | Status | What changed or why it stays |
|---|---|---|
| w550 headings and titles read as regular | **fixed** | Every w550 role in the detail now uses `.semibold`: section headings, "The sound of it.", song titles, Up next and row titles, the original-story title, credit names and the adaptation title. `.medium` stays only on w500 roles. Section headings also get their 23.8 / 25.2 line height (`detailLineHeight`). |
| D2 synopsis with a dead "About this season +" | **fixed** | Synopsis-led (no `detail_copy` hook): the row appears only when the synopsis is cut at five lines or an expectation line waits behind it (`DetailStoryDisclosure`; two hidden probes measure the cut). It reads "More" / "Show less" ("Mehr" / "Weniger zeigen"). The fixture keeps the row because its genres make an expectation line. Leading with the synopsis is **justified**: hooks come only from `detail_copy`, and the series flags are off for live users. The hook-led state matches in `detail-anime-bundle-390.png`. |
| Overflow "···" beside the status mark | **fixed** | Removed. The mark is a `Menu` with a primary action, as §50 describes: a tap opens List settings, and touch-and-hold (or VoiceOver's actions) opens the menu with Save/Remove, Verdict, Where to watch, Add to a club and Share. The hint says "Touch and hold for more actions." |
| D1 band geometry and close position | **fixed** | The mark's touch area no longer adds height to the band (`.frame(minHeight: 44).padding(.vertical, -15)`), so the heading block is 4/24/19 around the title. The touch area is meant to stay 44 pt, but that is not verified on a device: a UIKit-backed `Menu` may clip its hit area to the 14 pt layout frame. The mark is centred on the title line. The close sat 29 pt low only because of the fixture window's inset. It now sits 12 pt from the top. The artwork keeps the 150.6/354 ratio at the full 390 width. |
| D6 Up next row height, key position and shadow | **fixed** | The summary is at least 58 pt with padding 7/9, so the row is 74. The key is centred (its one-sided 7 pt top padding is gone). The row shadow is on the row's shape, so it no longer doubles onto the key. |
| D8 song rows and footer | **fixed** | Rows are 78 pt (padding 12/0 around a 54 pt block, with line heights 11.2 / 16.25 / 14). A `#ffffff14` rule sits under every row, the last included, so the attribution has its rule and the 13 pt margin. "via AnimeThemes" stays in place of the sample "Find on Spotify · track links not yet matched": **justified**, it is the real source (§8.13). |
| D4 current tile ring, ribbon, "Current" | **fixed** | Added the 1 pt `#718478` inset ring and a 7 × 18 ribbon with a V notch in `base`. "Current" is `.medium`; the spec measures w400, and white 8 pt on the dark tile reads heavier. |
| D4 selection dot cut in half | **fixed** | The tile row draws above the thread rule, and the seasons section draws above the progress card. The 3 pt `#f1f3ef` halo now cuts the rule as in the reference. |
| D4 tile foot dash and stripes | **fixed** | The dash is 6 × 2. The light tile's ruling fades in toward the foot. |
| D6 episode row rules | **fixed** | The rule sits under each row, so one closes the list before "More episodes". |
| D7 title to author spacing | **fixed** | Title 17/23.8 with m 6/0/2, author 10/14. |
| D10 credit rows | **fixed** | 40.4 pt rows (12/0 around a 15.4 line). The content shape is meant to reach 2 pt past each rule (a 44 pt target). That is not verified on a device. The role colour was already `#69766c`. |
| D3 / D11 avatar tints | **fixed** | The three prototype fills `#d3ded3`, `#e2e3d7` and `#c8d4ce` cycle by index (`DetailAvatars.fillHex`). |
| D11 byline and reactions | **fixed** | The byline names the club the author provably shares with the viewer: the viewer's only club, or a club whose cached roster lists the author (`DetailBetweenUs.clubName`). Otherwise it shows the note's age; it never guesses. The age stays in the VoiceOver label. The reactions are a live feature, so they **stay** (spec §50: nothing live is removed). They now sit as quiet 9 pt keys in an overlay on the byline's trailing edge, which adds no height, so the 13/0/14 note rhythm and the ~26 pt divider-to-byline gap return. |
| D11 "Spoiler · Story" vs "Spoiler · Season 2" | **justified** | The stored scope is only none/story/ending (`title_comments` check). No season is recorded. |
| "Hidden Inventory / Shibuya Incident" season title, "Preview" notes, sample footnote | **justified** | Arc names and the "Preview"/sample lines are prototype sample data (§7.2). The catalogue has no arc name. |
| Song kickers "Opening · Hidden Inventory" | **justified** | AnimeThemes gives the sequence and episode range ("Opening 1 · Ep. 1–5"), not arc names. |
| Close control ring | **justified** | The reference's grey ring around the close appears to be the capture's focus outline. It is not part of the control's measured style (spec: a 1 pt `#ffffff45` rim). |

### Detail manga

| Finding | Status | What changed or why it stays |
|---|---|---|
| Typeface for every serif element | **fixed** | Georgia via a detail-local `Font.detailGeorgia` (Georgia / Georgia-Italic, Dynamic Type scaled and capped like `kuroCustom`) on the title, the hook, "Your bookmark", the italic chapter numbers, "Seen the anime?" and "Between us." (both media). The shared `kuroEditorial` token in `KuroDesignSystem.swift` still maps to New York; that file belongs to another lane. |
| D1 title layout and band size | **fixed** | The band has padding 28/24/24 and a cover of at most 107.1 pt (35 % of the prototype's 306 pt), and the heading column is at most 176 pt. "Chainsaw / Man" therefore breaks onto two lines and the band is about 214. A long title still wraps to three lines; a word wider than the column shrinks to 0.8 before truncation. |
| D1 overflow key | **fixed** | As on anime: the mark carries the menu. |
| D3 avatar tints | **fixed** | As on anime. |
| D6 extra "26 Chapter 26" row with ↗ | **fixed** | Collapsed and tracked: only the finished row follows Up next (`MangaChaptersSection.collapsedRows`). Chapter rows have no ↗ key. An unread row that opens the reading service says so in its VoiceOver hint. |
| D7 links | **fixed** | The fixture sets the adaptation's official site, and the card shows "Official anime site ↗" as its one link. The 映 tile and the title open the anime in the app (the live route, kept without an extra link). "Explore the anime →" shows only when no site is known. |
| D7 "I've watched the anime" row | **justified** | It needs the series bundle's season guide (series flags off for live users). Shown without coverage, it could only say "unknown". The bundle render (`detail-manga-bundle-390.png`) shows the rule, the 52 pt row and the full card. |
| D7 映 glyph | **fixed** | Hiragino Mincho (`HiraMinProN-W3`). The system serif falls back to Gothic for CJK. |
| Section heading weight | **fixed** | `.semibold`, tracking −0.4, 23.8 line. |
| Characters to credits spacing | **fixed** | The name box keeps two 15 pt lines (44 with the 9 pt top), and sections take the prototype's 30 pt top margin, with the Seen-the-anime card's bottom margin collapsing into it. Names to "Behind the pages." is now 76 pt, as in the reference. |
| D11 reaction keys, rhythm, spoiler, chevron, card corners | **fixed / justified** | The reactions stay as quiet overlay keys (see anime). The rhythm is about 27 pt from the divider to "Mina" and about 43 pt from "Jules" to the spoiler line. The chevron is 6 pt light. "Leave a thought" uses a 4 pt radius on the folio card. The spoiler label stays SF 10, the measured size (spec D11 `spoiler` 10/14); the reviewer's 11–12 is an estimate. |
| "Read with the publisher · Chapters & availability at VIZ", "English publisher VIZ Media" | **justified** | The legal read links carry no publisher marker, and the catalogue has no publisher field. The row reads "Read legally" with the real service name. |
| Top viewport | **fixed** | Follows from the band, hero and chapter fixes. The rest is the synopsis-led story (justified above). |

### Pathway findings (detail files)

| Finding | Status | What changed |
|---|---|---|
| BLOCKER: Up next +1 on a Planned title stayed Planned | **fixed** | `DetailAdvance` sends `LibraryEdit(status: .set(.current), progress: .set(n))` through `LibraryActions.apply` when the entry is Planned. Every other status stays progress-only, and an untracked title is created as Watching/Reading. Undo reverts the whole change: the count and the saved status, and a row the +1 created is removed. Pinned by `DetailPathwayTests.plannedAdvanceReachesBusyHome`: Planned → +1 → `HomeShelfPolicy.scene == .inProgress`, `showsNewAccount == false`, and Undo returns to Planned 0. |
| MAJOR: "Saved · remove" removed in one tap | **fixed** | The item reads "Remove from list" ("Von der Liste entfernen"). It asks first unless the entry is a bare plan (`DetailRemoval.needsConfirmation`). The toast "Removed from your list." has Undo, which re-saves every field of the removed row. Pinned by `removalUndoRestoresTheRow`. |
| Read failures shown as missing sections | **fixed (ladder) / open (others)** | A ladder answer without a coverage status is a failed read (`DetailReadState.ladderFailed`). The page then shows `KuroStateView(.failed, layout: .inline)` with Try again (`reloadToken`). Where to watch/read says "Still checking where to watch/read" while its read is out, instead of "no link". **Open:** the episode, chapter, credit and link reads in `CatalogStore` / `ProviderAvailabilityStore` answer a failure with `[]`, so the page cannot tell failure from none. Those owners need a throwing read. |
| Loading/failed sheet without a close | **fixed** | The loader's loading and failed states carry a neutral `DetailCloseButton`, and the sheet shows its grabber until the page has loaded (`DetailLoaderChrome`). |
| Credit rows without a target were buttons | **fixed** | Credit rows without a target are static text (`DetailCreditRow.isInteractive`). Episode rows are buttons only when they have details (`AnimeUnitsSection.isExpandable`). |

Reachability: the pages above are the only live detail write paths. `AnimeDetailView` / `MangaDetailView` render `AnimeDetailPage` / `MangaDetailPage`. Their leftover legacy structs (`EpisodesSection`, `ActionButtons`, `ChaptersSection`, `MangaActionButtons`, which hold the old `markProgress` and one-tap remove) and `SeriesAnimeDetailView` / `SeriesMangaDetailView` (`Kuro/Views/Home/SeriesDetailViews.swift`) have no callers outside their own files. They were left unchanged rather than deleted (DO-NOT 16).
