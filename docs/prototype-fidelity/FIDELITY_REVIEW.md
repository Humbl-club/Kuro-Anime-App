# Fidelity review: Home (Task 10)

Compares the references in `reference/` with the native renders in `native/` (see `native/INDEX.md` for the pairs).

**Scope.** This file covers the review of Home anime and Home manga (busy, full, undated and quiet, at 320, 390 and 430), plus the confirmed code-review findings from the same pass. Round 2 (2026-11-02, below) adds the new-account Home, Taste (busy and new, anime and manga) and the Home +1 toast. Detail pages are reviewed elsewhere.

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

## Round 2 (2026-11-02): new-account Home, Taste and the Home +1 toast

Measured at 1 px = 1 pt against `ref-home-new-{anime,manga}-{320,390,430}.png` and `ref-taste-{busy,new}-{anime,manga}-390.png` (native y = reference y − 70). The first-run renders are now 1 px = 1 pt too (they were 3x, which made weights look lighter than they are). Round 2 changes the shared art-filled word and the switch rule, so every Home render was re-rendered and re-checked against its reference (EN under en_GB, DE under de_DE).

### New-account Home

| Finding | Status | What changed or why it stays |
|---|---|---|
| Selected word shows the pale mountain, fainter than the unselected word | **fixed** | The word shows the first starter pick's cover, the same rule as Taste (amendment 16), so the switch reads the same on both pages (`HomeNewAccount.onLeadArt`). The mountain stays only for the invitation (an empty medium beside an occupied one). See note FR-A for the fill. |
| Position of the empty-home block (＋ about 20 pt high) | **fixed** | The opening row keeps `.home-opening`'s 18 pt bottom margin (plus the 1 pt the native row sets shorter than its 18.2 pt box). The ＋, headline, line and Explore Taste key now land on the reference's y at 320, 390 and 430 (±1 pt). |
| Selected underline above the hairline; rule 2 pt high | **fixed** | The 28 × 2 rule's bottom row is the hairline's row (`KuroPosterMediumSwitch`, 58 pt from the row top to the hairline's foot). The rule now sits on rows 63–64 as in the reference. The fixture draws it a third of a point lower, blended over two rows: the same 1x-render effect as note D. |
| Opening row 2 pt high | **fixed** | Follows the rule: the kicker starts at y 80 at 390 and 430, as the reference. At 320 it is 1 pt high (79, compact 8 pt kicker). |
| 320: words 4 pt high | **fixed** | The 30 pt word sits 4 pt lower in the same row on small phones (the prototype's ≤ 360 position): y 22–45, as the reference. |
| Headline → line 2 pt tight | **fixed** | The headline has its 33.6 pt line box and the line its 18.2 pt box (top padding 16.35), so the line starts at the reference's y. |
| App header (KURO / Home or Taste) not drawn | **open (outside this lane)** | The header is the pager's (`ContentView`, `KuroHeaderNew`); no lane fixture draws it. |

### Taste

| Finding | Status | What changed or why it stays |
|---|---|---|
| New anime and manga: no premise under the titles | **fixed** | Each shown pick is completed by a catalogue read (`TasteCardDetails`: `CatalogStore.fetchAnimeById` / `fetchMangaById`, cached in memory and on disk, at most four per medium, before the cards show so nothing reflows). The premise is the first sentence of the catalogue synopsis; a title without one shows none. The same read completes the new-account Home picks. |
| Busy anime: two portrait cards instead of the landscape card | **fixed** | The same catalogue read lends the first because-you pick its banner, so busy anime opens with the landscape card whenever the catalogue has a banner. The primary render now comes through that path; the "banner-joined" render is gone. A title with no banner anywhere stays a portrait card. |
| Selected word flattened to teal / grey-olive | **fixed** | Note FR-A. |
| Card shadow heavy at the sides | **fixed** | `0 4px 14px -11px #14222540` is cast by a shape 11 pt smaller (radius 7, y 4, opacity 0.25). Measured: one pixel below the card and beside it now match the reference's values. |
| New anime shows three cards (live page) | **fixed** | New-account Taste shows two cards (`TastePicksCopy.visibleCount`): anime one landscape and one portrait, manga one row of two. A busy account keeps up to four. |
| Heading and title about 2% small (anime) | **fixed** | The w550 roles use `.semibold` (anime heading, card titles). Glyph extents now match within 1 px: heading 155 × 17 (reference 154 × 18), "Your Name." 127 × 19 (126 × 19), manga title 112 × 19 (111 × 19). The manga heading (w500) stays `.medium`. |
| Plan key label lighter | **justified** | The label is already `.medium` (w500). The earlier comparison set a 3x render against the 1x reference; at 1 px = 1 pt the native label carries as much ink as the reference's (measured). |
| Medium switch underline and hairline (Taste) | **fixed** | Same switch as Home (above). |
| Opening row 2 pt high | **fixed** | Follows the rule: kicker at y 80, as the reference. |
| Busy manga: two-line heading pitch | **justified** | Note FR-C. Everything below it sits 2 pt deeper; the rest of the page matches within 1–3 pt. |
| Manga leaf frame offset | **fixed** | Two 1 pt layers: `#fafbf6` against the border, then `#e1e3da`. |
| Landscape premise breaks one word early | **justified** | Note FR-B. |
| Header bar colour on manga Taste (amendment 22 vs the captures) | **open (owner re-rule)** | The captures keep the cream `#fffef8eb` header over the `#f5f5f3` manga page; amendment 22 paints `#f5f5f3` under the header. The header is `ContentView`'s, outside this lane. The owner should re-rule amendment 22. |

### Home +1 toast (pathway finding, major)

| Finding | Status | What changed or why it stays |
|---|---|---|
| Home +1 has no toast; its Undo sits at the bottom of the feed, off-screen | **fixed** | A +1 on Home shows the prototype's toast at the screen foot (§3.4, §6): "Progress saved." or "Caught up." (when the key is now capped) with Undo and ×. Undo restores the count and says "Undone."; a save that did not happen says "Not saved. Your progress is unchanged." (no Undo). EN/DE copy from §7.1. It is drawn by the Taste Plan toast's view (`TastePlanToastView`), in one slot with the new-account Plan toast (showing either dismisses the other). Undo is offered only while `HomeStore.undo` would act on that title (`HomeProgressToasts.undoApplies`), only for the account and medium that made the +1, and once. The toast ends on an account change, a medium switch and when the Library leaves `.loaded`. The bottom status line lost its Undo. Render: `native/home-anime/home-busy-anime-toast-390.png` (and `-de`), after a real +1 through `HomeStore`. |
| "Saved on this device." stays after the save syncs | **open (outside this lane)** | Library sets `progressMessage` on every local save and clears it only on Undo and conflict resolution, not when a drain is acknowledged (`KuroLibrary/LibraryProgress.swift`). Until that is fixed there, Home shows the line only while offline (online, the save is on its way and the toast already said so). |

### Round 2 notes

**FR-A. The art-filled word.** The old fill took the per-channel minimum of the art and `#646d65`, which clamped every bright channel to about 0.4 and flattened the art to a single hue. The fill is now the artwork as it is, under the prototype's scrim (`#15221c15` → `#15221c38`) on its `#253a2a` fallback, with an adaptive contrast floor (`HomeMediumWordInk`): when the band of the art the word shows is lighter on average than luma 0.40, the whole fill is darkened by one uniform factor until it is not (a uniform factor keeps the hue), and no channel is lighter than `#a4a8a2`, so a white sky or page never erases a stroke. Art already dark enough passes through untouched. The lightest mean the word can have still passes AA on the canvas and is darker than the unselected `#6e786f` (pinned in `HomeAnimeLaneTests` and `HomeFirstRunRound2Tests`). The source art differs from the captures where amendment 16 rules the first pick's art (Taste and the new-account Home); busy Home manga now reads almost exactly as its reference.

**FR-B. Premise line break.** iOS's standard line-break strategy avoids a one-word last line, so "Two strangers wake up in each other's lives." breaks before "other's" rather than leaving "lives." alone, as the browser does. SwiftUI `Text` exposes no line-break strategy, and the premise is real catalogue text whose length varies, so this is left to the platform.

**FR-C. Two-line heading pitch.** The prototype sets the 24 pt heading on a 26.4 pt line; SF's own line is 28.6 pt and SwiftUI `Text` ignores a negative line spacing (measured: no change). Only the two-line manga heading ("Turn to something / new.") shows it, 2 pt deeper; single-line headings land on the reference's y.

**Not changed by request:** `HomeNewAccountCopy.pickCount` (the new-account Home's 3 anime / 4 manga starter picks) is the owner-approved addition (spec §5.3, amendment 5), not part of the references.
