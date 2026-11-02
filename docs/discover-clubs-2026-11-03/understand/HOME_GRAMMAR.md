# Home design grammar (extracted 2026-11-03, read-only)

Purpose: the exact visual language of the shipped Home (the approved Poster prototype) so the Discover and
Clubs lanes can make those pages feel like the same app. Everything here is read from code at `main`
(`ff8059d`) and from the measured prototype capture.

Sources, in order of authority:
1. `docs/prototype-fidelity/PROTOTYPE_SPEC.md` (measured capture of `tools/design-directions/instrument.html?switch=poster`; reference PNGs `docs/prototype-fidelity/reference/ref-home-{busy,full,quiet,undated,new}-{anime,manga}-{320,390,430}.png`)
2. `docs/prototype-fidelity/LANE_AMENDMENTS.md` (lead rulings 1–23; "the prototype wins")
3. The native code under `Kuro/Views/Home/`, `Kuro/Views/Shared/`, `Kuro/Design/`, `Kuro/Views/ClubRoomStyle.swift`

> The CLAUDE.md "DESIGN SYSTEM" section (`kuroBlack80` / `kuroTextSecondary` era) is stale for this work.
> Use PROTOTYPE_SPEC + LANE_AMENDMENTS + the tokens/inks below. Statuses stay monochrome; red only for destructive.

All file:line references are to `Kuro/…` unless noted.

---

## 0. Ten rules in one screen

1. **Canvas:** warm paper `kuroCanvasHome` #FFFEF8 (anime), `kuroCanvasHomeManga` #F5F5F3 (manga); crossfade over `KuroMotion.medium` (320 ms). Header paints the same canvas, so a page and `KuroMainView.Section.canvas` must change together (§1).
2. **Gutter 20 pt (16 at ≤ 330 pt column)**, top 7, top-level stack spacing 12, shelf spacing 24, paper feed 2 pt inside the gutter, readable column 680 on iPad (§7).
3. **Type is SF sans, sized by hand:** `Font.kuroCustom(size, weight:, relativeTo:, maxSize:)` + explicit `.tracking(…)`. Serif (`kuroEditorial`) only for club name, club quote and the few listed editorial headings (§3).
4. **Eyebrow:** 9 pt (8 compact), tracking 1.05, uppercase, `HomeInk.kicker` #666C68, with a right-aligned 14 pt semibold −0.3 ink headline on the same baseline (`HomeOpeningLineView`).
5. **Section heading:** 24 pt semibold −0.85 ink + 10 pt #656C66 summary on the right ("Coming up."); in-feed sub-heading 15 pt semibold −0.2 + 10 pt `kuroMuted` count ("Also watching"). **Not** `KuroSectionHeader` (§4).
6. **Artwork carries colour:** each title's `ArtworkMaterial` (`base → deep` gradient, white ink ≥ 7:1) from `@Environment(ArtworkMaterialStore.self).material(for:seedHex:)`; never a per-title colour table (§9).
7. **Cards are quiet:** small radii (5 scene, 8 glance/quiet, 18 calendar, 24 club room), 1 pt hairline borders, near-invisible drops (`0 1 2` at 2–8 % alpha) (§8).
8. **Keys are physical:** `KuroAdvanceKey` 44 pt target with a raised 34 pt face (light / material / ink / dark leaf), confirm + restore stamp after a durable save only (§6).
9. **Motion is short and one-shot:** contact 120 ms, settle 220 ms, medium 320 ms on the prototype ease; artwork entrance 380 ms; count roll 220 ms; everything still under Reduce Motion / Low Power (§10).
10. **States are branded:** `KuroSkeleton` shapes of the real component, `KuroStateView` / `KuroErrorView` / `KuroOfflineView` / `KuroEmptyView`; never `ProgressView(` outside `KuroBrandedStates.swift`; failures are never shown as empty (§11).

---

## 1. Canvas and page frame

| Thing | Value | Where |
|---|---|---|
| Anime Home / Taste canvas | `Color.kuroCanvasHome` #FFFEF8 | `Design/KuroDesignSystem.swift:121` |
| Manga Home / manga Taste canvas | `Color.kuroCanvasHomeManga` #F5F5F3 | `Design/KuroDesignSystem.swift:124` |
| Detail paper (not a page canvas) | `Color.kuroPaper` #F5F5F4 | `Design/KuroDesignSystem.swift:126` |
| Every other page (today: Discover, Clubs, Collection…) | `Color.kuroBackground` = `kuroCanvasPage` #FFFFFF | `ContentView.swift:986`, `KuroDesignSystem.swift:63,88` |
| Canvas switch | `KuroMainView.Section.canvas(mangaHome:mangaTaste:)` | `ContentView.swift:982-988` |
| Canvas painted behind pager | `selection.canvas(...)…ignoresSafeArea()` + `.animation(KuroMotion.medium, value: canvas)` (only when `playsMotionNow`) | `ContentView.swift:308-310` |
| Empty-medium invitation | `HomePagePicture` (lead title's art, or the `KuroSceneryLoop` mountain) + `HomeInvitationWash` behind the header | `ContentView.swift:303-306`, `Views/Home/HomePagePicture.swift:8-59` |

Prototype: manga page ink measures #272C28 (`PROTOTYPE_SPEC.md` "Home, manga, busy" Page); native uses `kuroInk` #252625 on both media.

**Seam rule (amendment 8, 22).** The header (`KuroHeaderNew`) paints `selection.canvas(...)` (`ContentView.swift:1012, 1267`). Discover and Clubs today paint their own white: `EditorialDiscoverView.swift:118, 814`; `ClubsView.swift:52, 585, 766, 929`; `ClubDetailView.swift:98`. A lane that moves Discover/Clubs to #FFFEF8 must change the page background **and** add the section to `Section.canvas` in the same change, or a white band shows under the header / beside the iPad readable column.

## 2. Header (shared by every page; not Home-owned)

`KuroHeaderNew`, `ContentView.swift:991-1270`.
- Row: horizontal padding 22, top 4, bottom 4, `minHeight 54` (`:1222-1224, :1266`).
- Left: "KURO" wordmark SF 18 `.heavy` (`kuroCustom(18, weight: .heavy, relativeTo: .headline, maxSize: 26)`, `:1030`), tracking `KuroHeaderRowLayout.wordmarkTracking`, `kuroInk`.
- Centre: page name `HeaderPageName` (`:1273`), `kuroNavigation` 11 pt in `kuroMuted` (ink on the picture), sliding 24 pt on page change over `KuroMotion.settle`; 3 pt position dots 4 apart, current = ink, others ink @ .18 (.28 on picture); Clubs unseen badge = 5 pt `kuroBlack70` dot (monochrome) (`:1072-1120`).
- Right: neighbour link SF 12 (`:1032`), search glyph 15 pt, profile = 24 pt hairline ring (ink @ .55) with the initial 11 pt medium, all in 44 pt targets (`:1143-1186`).
- Bottom: 0.5 pt `kuroLine` hairline (omitted on the invitation picture) (`:1258-1263`).
- Background: the page canvas (clear on the picture), animating with `KuroMotion.medium` (`:1267-1268`).
- Prototype difference (spec §8.12): the prototype bar is `#fffef8eb` + blur 18 and has no Search/Profile/dots; native keeps them by design.

Home has no in-page title: the first thing under the header is the medium switch.

## 3. Type

### 3.1 How Home sets type
Home almost never uses the role ramp. It uses `Font.kuroCustom(_ size:, weight:, design:, relativeTo:, maxSize:)` (`Design/KuroDesignSystem.swift:332-341`; scales with Dynamic Type via `KuroTypeScale`, capped by `maxSize`) plus an explicit `.tracking(…)` at the call site (a `Font` cannot carry tracking). SwiftUI has no w550: prototype w550/w530 → `.semibold`, w450 → `.regular`, w500 → `.medium`, w850/w800 → `.heavy`.

### 3.2 Home's measured type table (390 pt; compact = column ≤ 328 pt)
| Element | Font call | Tracking | Ink | File:line |
|---|---|---|---|---|
| Medium word (selected / unselected) | `.kuroMediumWordStyle(size: 36)` (30 compact) = SF heavy, uppercase | −1.9/36 em | art fill / `HomeInk.switchUnselected` #6E786F | `HomePagePicture.swift:186-194`, `KuroDesignSystem.swift:450-456` |
| Opening kicker ("NOW WATCHING") | `kuroCustom(9 / 8c, relativeTo: .caption2, maxSize: 18)` uppercase | 1.05 | `HomeInk.kicker` #666C68 | `HomeOpeningLine.swift:73-78` |
| Opening headline ("2 new episodes") | `kuroCustom(14 / 13c, .semibold, .subheadline, 28)` right-aligned | −0.3 | `kuroInk` | `HomeOpeningLine.swift:80-86` |
| Glance title "Coming up" | `kuroCustom(14, .semibold, .subheadline, 28)` | −0.3 | `HomeInk.glanceInk` #303932 | `HomeComingUpGlance.swift:122-125` |
| Glance caption | `kuroCustom(10 / 9c, .caption2, 22)` | 0 | `HomeInk.glanceMuted` #687064 | `HomeComingUpGlance.swift:126-130` |
| Glance count / label | `kuroCustom(21, .title3, 36)` monospaced / `kuroCustom(8, .caption2, 16)` | −0.6 / 0 | glanceInk / glanceMuted | `HomeComingUpGlance.swift:138-148` |
| Scene title (white on material) | `kuroCustom(17, .semibold, .headline, 34)`, 2 lines (3 AX) | −0.35 | `HomeInk.footTitle` #FAFAFA | `HomeSceneCard.swift:242-247` |
| Scene readout unit / count / total | 9 pt / `kuroCustom(19 / 17c, .medium, .title3, 34)` monospaced / 11 pt @ .8 | 0 | `footSecondary` #DCE3DF / white | `HomeSceneCard.swift:338-358` |
| Scene fact line | `kuroCustom(10 / 9c, .caption2, 22)` | 0 | `HomeInk.footFact` #DCE2DF | `HomeSceneCard.swift:297-312` |
| Season tab word / number | 7 pt uppercase / `kuroCustom(17, .semibold)` monospaced | 0.3 / 0 | `HomeInk.tabInk` #26372C | `HomeSceneCard.swift:214-222` |
| "Also watching" heading / count | `kuroCustom(15, .semibold, .subheadline, 30)` / `kuroCustom(10, .caption2, 20)` | −0.2 / 0 | ink / `kuroMuted` | `HomeAlsoWatching.swift:167-175` |
| Tile title | `kuroCustom(12 / 11c, .medium, .footnote, 26)`, 3 lines (4 AX) | 0 | ink | `HomeAlsoWatching.swift:44-48` |
| Tile unit / count | 10 / 9c pt `HomeInk.tileUnit` #5B635C / `kuroCustom(14 / 13c, .medium)` mono ink | 0 | — | `HomeAlsoWatching.swift:128-137` |
| Manga leaf title | SF 11 w500 (via `HomeMangaLeafTitle.font`) | −0.2 | — | `HomeMangaLeaves.swift:193-222` |
| Manga leaf "Ch." / count | 9 pt #59665A / `kuroCustom(24, .medium, .title2, 40)` #27322B | 0 / −0.8 | — | `HomeMangaLeaves.swift:97-111` |
| Calendar heading "Coming up." | `kuroCustom(24 / 22c, .semibold, .title2, 40)` | −0.85 | ink | `HomeCalendarCard.swift:103-107` |
| Calendar summary | `kuroCustom(10 / 9c, .caption2, 20)` | 0 | #656C66 (`HomeInk.calendarSummary`) | `HomeCalendarCard.swift:109-111` |
| Calendar day label / count | `kuroCustom(12, .semibold)` ink / `kuroCustom(10)` #68736A | 0 | — | `HomeCalendarCard.swift:209-217` |
| Date chip day / month | `kuroCustom(19, .medium)` mono / `kuroCustom(9)` #667267 | −0.6 / 0.4 | — | `HomeCalendarCard.swift:243-251` |
| Release row title / unit / when | `kuroCustom(12, .medium)` ink / 10 pt #68736A / 10 pt #58665B | 0 | — | `HomeCalendarCard.swift:349-391` |
| Quiet card line | `kuroCustom(11, .footnote, 24)` | 0 | `kuroMuted` | `HomeOpeningLine.swift:98-100` |
| Planned/Paused/Saved shelf kicker | `.kuroKicker()` = `kuroMicro(.medium)` 9 pt, uppercase | **2.1** | `kuroInkQuiet` #6B6B6B | `HomeView.swift:585`, `KuroDesignSystem.swift:459-464` |
| Quiet row title | `kuroTitleName(weight: .regular)` 17 pt, 2 lines | 0 | ink | `HomeView.swift:596-600` |
| Invitation / resting cover line | `kuroDisplay(weight: .light)` → 44 pt **semibold** (light is mapped up by `KuroTypeRole.displayWeight`, `KuroDesignSystem.swift:285-290`) | −0.8 | ink | `HomeView.swift:1018-1024, 544-548` |
| Invitation action kicker / title | `.kuroKicker()` / `kuroTitle()` 19 pt semibold + 13 pt arrow | 2.1 / 0 | quiet / ink | `HomeView.swift:990-1002` |
| Club kicker "YOUR PRIVATE CLUB" | `kuroCustom(7, .caption2, 14)` uppercase | 1.4 | `ClubRoomPalette.kicker` | `HomeClubRoom.swift:318-322` |
| Club name | `kuroEditorial(size: 22 / 19c)` serif | −0.6 | `ClubRoomPalette.text` | `HomeClubRoom.swift:323-329` |
| Club note author / time | `kuroCustom(11/10c, .semibold)` / `kuroCustom(10/9c)` | 0 | noteInk / noteMeta | `HomeClubRoom.swift:381-388` |
| Club quote | `kuroEditorial(size: 18 / 16c)`, lineSpacing 3, ≤ 4 lines | −0.3 | noteInk | `HomeClubRoom.swift:392-400` |
| Club row line 1 / 2 | `kuroCustom(11, .medium)` / `kuroCustom(10)` | 0 | rowInk / rowSecondary | `HomeClubRoom.swift:499-507` |
| Club footer | `kuroCustom(8, .caption2, 16)` | 0 | `ClubRoomPalette.footer` | `HomeClubRoom.swift:530-538` |
| Page footer "Your pace. Your place." / KURO | `kuroCustom(10, .caption2, 20)` / same `.bold` | 0 / 2 | `kuroMuted` | `HomeFooter.swift:12-20` |
| Toast | `kuroCustom(12, .footnote, 22)` white, Undo `.semibold` | 0 | white | `TastePicksView.swift:781-790` |
| Branded state headline | `kuroCustom(24, .bold, .title2, 44)` | −0.8 | ink | `KuroBrandedStates.swift:641-647` |
| New-account headline / line | `kuroCustom(24, .bold)` −0.8 / `kuroCustom(13)` #646B65 | — | — | `HomeNewAccount.swift:197-212` |

### 3.3 Role ramp (for reference; display roles are SF sans since 2026-11-01)
`KuroTypeRole.spec` (`KuroDesignSystem.swift:250-267`): hero 64, display 44, feature 34, headline 26, title 19, body 15, caption 11, micro 9, navigation 11, titleName 17, meta 13, buttonLabel 17, mediumWord 36. Tracking em (`:272-280`): hero/mediumWord −1.9/36, display/feature −1.1/27, headline −0.85/24, title −0.7/18. Use `.kuroRoleText(.headline)` to get font + tracking together (`:445-447`). Serif: `Font.kuroEditorial(size:weight:)` (`:377-386`) — **only** the amendment-1 list (club name and quote, "Between us.", manga detail title/hook, "Your bookmark", manga row numbers, "Seen the anime?").

## 4. Headers and eyebrows (two families; pick deliberately)

1. **Prototype opening row** (measured): `HomeOpeningLineView(kicker:headline:compact:)` (`Views/Home/HomeOpeningLine.swift:60-91`). Kicker 9/8 pt, tracking 1.05, #666C68, uppercase, one line; headline right-aligned 14/13 pt semibold −0.3 ink, `.isHeader`; HStack on first baseline, gap 12; stacks (VStack spacing 4) at accessibility sizes. Followed by 6 pt (`HomeView.swift:463`). Taste re-implements it inline (`TastePicksView.swift:902-953`); new pages should use `HomeOpeningLineView` instead of copying.
2. **Native quiet-shelf kicker** (not in the prototype; `PROTOTYPE_SPEC.md` has no Planned/Paused shelf): `.kuroKicker()` 9 pt medium, tracking **2.1**, `kuroInkQuiet` (`HomeView.swift:584-586`). It is also the invitation-action kicker. It is a native addition, so do not treat it as the measured prototype eyebrow.

Section headings:
- **Page section heading** (prototype "Coming up."): 24 pt (22 compact) semibold, tracking −0.85, ink, `.isHeader`; summary on the right in 10/9 pt #656C66, first-baseline HStack, gap 9; stacks at AX sizes; 17 pt to the card below (`HomeCalendarCard.swift:78-113`). Equivalent role call: `kuroCustom(24, weight: .semibold, relativeTo: .title2, maxSize: 40)` + `.tracking(-0.85)`. (`.kuroRoleText(.headline)` gives 26/−0.92, close but not the measured value.)
- **In-feed sub-heading** (prototype "Also watching"): 15 pt semibold −0.2 ink + right count 10 pt `kuroMuted`; 21 pt line box; 25 above, 12 below (`HomeAlsoWatching.swift:147-180`, `HomeView.swift:732, 753`).
- **`KuroSectionHeader`** (`Views/Shared/KuroSectionHeader.swift:7-57`): its file comment says serif, but it renders `kuroHeadline(weight: .light)`. `displayWeight` maps that to 26 pt SF **semibold, untracked**, or `kuroTitle(.regular)` 19 pt. The optional kicker is `.kuroKicker()` (2.1), and the action is a 13 pt medium text button. **Home's headings do not use it.** Discover (`EditorialDiscoverFrames.swift:584`) and Clubs (`ClubsView.swift:156`) do today, which is one visible reason they read differently from Home.

## 5. Medium switch

- **Poster switch (Home, Taste):** `KuroPosterMediumSwitch(selection:contentWidth:onSelect:fill:)` (`Views/Home/HomePagePicture.swift:152-227`).
  - Two equal columns, 12 apart, over a 1 pt `HomeInk.switchHairline` (#203027 @ 0x44).
  - Word size 36 (30 when `contentWidth ≤ KuroMediumSwitch.smallPhoneContainer` 328), `.kuroMediumWordStyle`, `minimumScaleFactor(0.6)`.
  - The selected word is masked over `fill`. The unselected word is solid #6E786F.
  - The selected rule is 28 × 2 `HomeInk.switchMark` #203027. It fades in place on the hairline and never travels.
  - Row min height 58 (53 stacked). The words stack at AX sizes.
  - Light haptic on change; press style `HomeContactStyle`.
- **Fill:** `KuroArtWordFill(raw:fallback:)` (`HomePagePicture.swift:91-144`).
  - The artwork itself, under the scrim `HomeMediumWordInk.scrimTop/Bottom` (#15221C @ 0x15 → 0x38), on #253A2A.
  - Adaptive contrast floor: `HomeMediumWordInk.targetLuma` 0.33 and the `highlightCeiling` #8E938C (`:231-289`).
  - Fallback `.solid` #253A2A or `.mountain`. Home's lead-title wrapper is `HomePagePictureFill` (`:65-79`, reads `HomeStore`).
- **Compact switch:** `KuroMediumSwitch(selection:size:material:)` (`Views/Shared/KuroMediumSwitch.swift:16-132`), used by Collection, Browse, club sheets and onboarding.
  - Differs from the Poster switch: unselected `kuroMuted`, a `kuroInk` rule that travels (matchedGeometry), selected fill = material gradient or #253A2A, gap 24/16, sizes 36/30 (`.large`) or 24 (`.compact`).
  - Amendment 7 allows this for compact callers.
  - **Rule for new surfaces:**
    - A page that leads with the medium (as Home and Taste do) uses `KuroPosterMediumSwitch` + `KuroArtWordFill`.
    - A secondary in-section filter uses `KuroMediumSwitch(size: .compact)`.

## 6. Keys and controls

- **+1 key** `KuroAdvanceKey(style:phase:accessibilityText:confirmTrigger:action:)` (`Views/Shared/KuroAdvanceKey.swift:21-110`). 44 × 44 target, raised face drawn by `KuroKeyFace` (`:113-164`):
  - `.light`: 34 pt face, radius 7, `kuroKeyLightTop → kuroKeyLightBottom`, ink #29352C. Used on the scene foot.
  - `.material(m)`: 34 / 7, `m.base → m.deep`, white ink. Used on Also watching and the detail Up next key.
  - `.ink`: 34 / 7, `kuroKeyDarkTop → kuroKeyDarkBottom`. For keys without artwork (Folio).
  - `.dark`: 40 / 6, solid #2B342E, 10 pt cap @ .75. The manga leaf key.
  - Shared face details: border #202823 @ 0x26, inset highlight white @ 0x35, drop #142319 @ 0x12 0/1/1.
  - Pressed: scale .95, darkened 14 %, inset 0 2 3 #151D24 @ 0x30.
  - Phases: `.advance`, `.caughtUp`, `.needsChoice`, `.pending`.
  - Copy: `KuroAdvanceCopy.label/caughtUpLabel` (`:199-242`).
- **Caught-up ghost keys** (Home-only): `HomeCaughtUpKey(onArt:accessibilityText:)` (`HomeSceneCard.swift:401-437`, ✓ 12 pt light #B9C5C1 on art / #767B77 on paper) and `HomeLeafCaughtUpKey` (`HomeMangaLeaves.swift:226`).
- **Press styles:**
  - `HomeContactStyle`: opacity .8, scale .98, `KuroMotion.contact` (`HomeView.swift:1246-1253`; already used by `ImportSourceChooser`).
  - `HomeArtworkPressStyle`: brightness −.08, scale .987 (`HomeSceneCard.swift:459-468`).
  - `KuroPressStyle(pressedScale:)`: scale .98 (`Views/Shared/KuroInkButton.swift:11-19`).
- **Buttons:**
  - `KuroInkButton(title, role: .primary/.secondary/.destructive, isLoading:)` (`KuroInkButton.swift:21`). Home uses `.secondary` for "More titles", "Keep that" and "Keep mine" (`HomeView.swift:532, 642-647`).
  - `KuroOutlineButton(title, action:)`: 44 pt, 1 pt #BFC4BD, radius 12, SF 14 (`KuroBrandedStates.swift:590`).
- **Invitation link row** (Home-private helper `invitationAction`, `HomeView.swift:982-1013`): kicker, 19 pt title, → glyph, 1 pt ink rule, min height 52, rows 22 apart. This is the "text action with an ink rule" pattern. `KuroInkButton(role: .secondary)` is the shared equivalent.
- **Section action "Try again"**: 13 pt medium ink, 44 pt target, `HomeContactStyle` (`HomeView.swift:1088-1097`).

## 7. Spacing and layout rhythm

| Rule | Value | Where |
|---|---|---|
| Page gutter | `KuroDesignSpacing.padding` 20; `KuroDesignSpacing.md` 16 when the measured container ≤ 330 | `HomeView.swift:262-264` |
| Top of content under header | 7 | `HomeView.swift:102` |
| Top-level stack (switch → banner → shelf → footer) | VStack spacing 12 | `HomeView.swift:90` |
| Bottom padding without footer | 40 | `HomeView.swift:103` |
| iPad | `.kuroReadableWidth()` (max 680, centred) on the content column | `HomeView.swift:105`, `Views/Shared/KuroReadableWidth.swift:26-35` |
| Width source | measured container (`onGeometryChange`), never the screen; fallback 375 | `HomeView.swift:113-114, 266-271` |
| Compact column | `HomeSceneMetrics.isCompact(columnWidth:)` = ≤ `KuroMediumSwitch.smallPhoneContainer` (328) | `HomeSceneCard.swift:69-71`, `KuroMediumSwitch.swift:44` |
| Populated shelf sections | VStack spacing `KuroDesignSpacing.lg` 24 | `HomeView.swift:452` |
| Opening block (glance → opening → feed) | spacing 12; opening +6 bottom; quiet card +8 bottom | `HomeView.swift:455-467` |
| Scene cards | 18 apart | `HomeView.swift:699` |
| Also watching block | +13 top (25 under the last scene), heading → grid 12; grid columns 16 apart (12 compact), rows 16 (14 compact); one column at AX | `HomeView.swift:732, 753`, `HomeAlsoWatching.swift:183-197` |
| Quiet shelf | kicker + rows spacing 8; row = 40 × 60 cover (radius 2), gap 16, min height 60, vertical padding 4, 0.5 pt `kuroHairline` under each row | `HomeView.swift:581-613` |
| Calendar | +8 top (32 under the shelf above); heading → card 17 | `HomeView.swift:1117`, `HomeCalendarCard.swift:78` |
| Paper feed inset | `HomeFeedInsets.feed` = 2 (22 pt from edge at 390) for calendar + footer | `HomeView.swift:1207-1210, 98, 1119` |
| Club room | +8 top, `HomeFeedInsets.room` = −3 (bleeds 3 past the gutter) | `HomeView.swift:1165-1166` |
| Footer | padding top 28, bottom 28 | `HomeFooter.swift:22-23` |
| Invitation | spacer `min(max(0, h × 0.3), 280)`, copy max width 300, 46 × 2 ink rule, copy stack 14 | `HomeView.swift:388, 1015-1036` |
| Cover-line + rule pattern | 44 pt semibold −0.8 line, 14 gap, **46 × 2 ink rule**, body `kuroBody()` `kuroInkSecondary` | `HomeView.swift:540-576, 1015-1036` |

Tokens available: `KuroDesignSpacing.xs 4 / sm 8 / md 16 / lg 24 / xl 32 / xxl 48 / padding 20` (`KuroDesignSystem.swift:468-481`). Home mixes these with measured literals (7, 12, 13, 17, 18, 22). Copy the literal where Home does, and comment the measurement as Home does.

## 8. Components (anatomy)

### 8.1 Coming-up glance (the quiet info card)
`HomeComingUpGlance(summary:compact:artURL:)` (`HomeComingUpGlance.swift:111-183`).
- Card: fill `HomeInk.glanceFill` #FFFEFA, radius 8, 1 pt `glanceBorder` #293129 @ 0x18, shadow `glanceShadow` (#293129 @ 0x05, r 1, y 1). Padding 10 / 12 (10 / 10 compact), min height 72, gap 12 (8 compact).
- Contents: title over caption (spacing 4).
- Art strip: three 27 × 38 (34 compact) thumbs, radius 2, 1 pt #FFFEFA rim, overlap −7, shadow #26352B @ 0x14. Hidden at AX sizes.
- Then the count over its label, min width 39, trailing, and "↓" 16 pt.
- The whole card is a `HomeContactStyle` button when it links somewhere. The summary is pure data (`HomeGlanceSummary`, `:54-108`).

### 8.2 Quiet card ("Nothing new today.")
`HomeQuietCard(text:)` (`HomeOpeningLine.swift:94-109`): 11 pt `kuroMuted`, padding 12, fill white @ .5, radius 8, 1 pt `HomeInk.quietBorder` #DCE1DC. This is the shape for a one-line "nothing here, and that's fine" note.

### 8.3 Scene card (one title, artwork-led)
`HomeSceneCard(title:artURL:material:season:readout:fact:compact:onOpen:onSeason:onClub:key:)` (`HomeSceneCard.swift:154-206`):
- **Artwork window:** full width, aspect `HomeSceneMetrics.artworkAspect` 3.25 (350 × 107.7 at 390). `HomeArtwork(url:maxPixelSize:1200, placeholder: material.base)`. Shade `clear → black @ .18` from the centre down. 1 pt white @ 0x25 rim, top corners 5. `.homeEntrance()`. It is a button (`HomeArtworkPressStyle`), hidden from VoiceOver because the title button speaks.
- **Season tab:** bottom-left, 12 in. Face `HomeInk.tabFace` #F3F4F4, top corners 8, min 31 tall, white @ 0x65 top lip. Word 7 pt + number 17 semibold #26372C. 44 pt target (`:210-238`).
- **Foot:** background `LinearGradient(base, deep, topLeading → bottomTrailing)`. Min 58 tall, padding leading 14 (11 compact), trailing 10, 1 pt white @ 0x18 top rule.
  - Title button: 17 semibold −0.35 #FAFAFA, flexible.
  - A 1 pt white @ 0x24 divider, 48 tall.
  - Fixed 112 pt (104 compact) progress column: `HomeSceneReadoutView` + key in a 44 pt column.
  - At AX sizes the readout and key stack under the title (`:256-290`).
- **Fact row:** optional. Min 40/44 tall, 1 pt white @ 0x0D top rule, 10 pt #DCE2DF. A club fact adds a 17 pt initial disc (white @ 0x14 fill, @ 0x44 rim) and "›" (`:293-328`).
- **Card:** radius 5, shadow #19221B @ 0x0A r 1 y 1. Material changes animate with `KuroMotion.medium`.
- **Targets:** artwork, title, key and season tab are separate targets, never nested.

### 8.4 Also watching tile (compact title + progress)
`HomeAlsoWatchingTile(title:posterURL:material:stamp:readout:compact:onOpen:key:)` (`HomeAlsoWatching.swift:14-144`):
- **Poster:** 44 × 66, radius 4, fill `HomeInk.posterFill` #E9E9E6. Shadow #222222 @ 0x55 r 3.5 y 3, cast by a 4 pt-inset shape so it shows below only. 1 pt black @ 0x0B rim. Optional "S2" stamp (#F3F4F4, top-leading corner 5).
- **Layout:** gap 9 (7 compact). Fixed text column 114 (89 compact; flexible at AX).
- **Text column:** a title button, min 44 in a 48 pt row, then a 44 pt progress row: the count over a 1 pt `HomeScrub` (#D7D9D7 / #626962) and the material key.

### 8.5 Manga leaves (equal covers)
`HomeMangaLeaves(cards:containerWidth:readout:onOpen:key:)` (`HomeMangaLeaves.swift:28-125`), metrics in `HomeMangaLeafMetrics` (`:128`):
- Three fixed columns: 106 wide, gaps 26 row / 14 column, cover 138. Compact: 88, gaps 24 / 11, cover 119.
- Cover: radius 4, shadow #242C25 @ 0x14 r 1.5 y 2, top-biased crop.
- Title: 44 pt box.
- Action row: 1 pt #D8DDD2 top rule, "Ch." over count, and the `.dark` key in a 44 pt column.
- Typed on `HomeCard`.

### 8.6 Calendar card (grouped list in one rounded card)
`HomeCalendarCard(groups:coverage:coverFor:titleFor:seasonFor:now:medium:)` (`HomeCalendarCard.swift:27-420`), palette `HomeCalendarPalette.anime/.manga` (`:423-469`):
- **Anime card:** #FAFCF9, radius 18, 1 pt #D8DDD9. Drop #1D291C @ 0x20 r 3 y 2, cast by a 4 pt-inset shape so it shows under the card only.
- **Manga card:** #FAFBF7, radius 14/14/5/5, no rule, drop #2D3027 @ 0x09 r 8 y 5.
- **Day toggle row:** min 76, padding 12, gap 11 (`:205-235`).
  - Date chip 40 × 44: anime white with a #D4DBD4 rule, radius 10; manga #ECEEE4 with corners 4/10/4/4.
  - Label over count.
  - Stacked 23 × 34 covers: overlap −6, 2 pt rim, shadow #243A21 @ 0x20 x −2.
  - Disclosure "⌃ / ⌄" 21 pt light #727D73.
- **Open state:** an open day sits on white; the events fill is white (anime) or #F5F6F0 (manga).
- **Release row:** min 74, padding 13 vertical, 1 pt #E3E7E1 top rule (`:338-386`).
  - 32 × 48 cover (radius 3 / 1).
  - Title over unit line.
  - A trailing "when" column, max 62.
  - Chevron 12 pt #798679.
- **"Show N more":** 44 pt, #F6F8F4 fill, radius 10, 1 pt #D9E0D7 (`:309-331`).
- **"Next N dates":** 48 pt, #F6F8F4, 1 pt #D9E0D7 top rule (`:396-419`).
- **Loading:** `HomeCalendarLoading(manga:)` (`:473-505`).
- **Open state memory:** the open/closed state is kept per medium.
- **Use as a pattern:** this is the template for "a list of grouped rows that expand", e.g. a club's This Week.

### 8.7 Club room (dark private-club card)
`HomeClubRoom(club:notes:otherClubCount:medium:now:notesFailed:notesOffline:onRetry:onOpenClubs:)` (`HomeClubRoom.swift:68-560`), styled only by `ClubRoomStyle.swift` (amendment 20):
- **Shell:** `ClubRoomBackground(cornerRadius:)` (`ClubRoomStyle.swift:73-99`).
  - #252B28 under a radial #444A46 glow from the top-left (end radius 260).
  - 1 pt #535A55 @ 0x4C border and a white @ 0x21 top highlight.
  - Drop #101710 @ 0x66: inset 14, offset y 10, blur 10. Only the lower edge shows.
  - Radius 24 (anime) or 13 (manga). Padding top 20, horizontal 16 (12 compact), bottom 12.
  - Compact when the room is under 330 wide (`HomeClubRoom.swift:278, 301-303`).
- **Masthead:** a button to the club, min 44, padding below 19 (`:312-341`).
  - `ClubSeal(ring: 36 / 30c)`: a ring in #899C8C around a 28 pt knot in #D2DACD, turned −12°.
  - Kicker 7 pt, tracking 1.4, #C0CBBB.
  - Club name: serif 22 (19 compact), −0.6, #F0F4EF.
  - Member initials: 22 pt (20 compact) discs, overlap −6. Fills `ClubRoomPalette.memberFills`, 2 pt #2F3730 rim, 7 pt #33412E ink.
- **Note card (light):** fill #F5F6EF, radius 14 (3 manga), 1 pt white @ 0x88 border, shadow black @ 0x22 r 3.5 y 3, padding 16 (14 compact) (`:369-434`).
  - Cover 60 × 90 (48 × 72 compact, 40 × 60 at AX), radius 3 (1 manga), shadow #252B26 @ 0x25.
  - Author, time ago, the serif quote, and "{title} ›" in 10 pt #66705D in a 44 pt box.
  - Spoiler line: #E9EDE2 fill, 1 pt #CCD4C3, radius 8, min 46, 10 pt #59664E (`:437-460`).
- **Dark rows:** min 70, padding 13/2, optional 30 × 44 art. Line 1 is 11 pt medium #F1F5ED; line 2 is 10 pt #C1CDB7; a chevron 13 pt (`:490-522`).
- **Footer:** "Shared stories. Your people. · N updates", 8 pt #B4C2A9, 1 pt #C5D2B8 @ 0x1C top rule, padding top 10. Optional "+N other clubs ›" at 44 pt (`:526-555`).
- **Failure:**
  - `HomeClubRoomFailure(medium:offline:onRetry:)` (`:600-629`) and `HomeClubRoomFailureLine(kind:onRetry:)` (`:635-697`).
  - The ridge is stroked in #C1CDB7.
  - 15 pt semibold headline, an 11 pt line, and "Try again →" with a 1 pt rule.
- **Palette:** `ClubRoomPalette` (`ClubRoomStyle.swift:10-45`) holds every room ink, plus `key` #2B342E / `keyInk` for a primary action on the room. The older `Color.kuroRoom` #222222 (`KuroDesignSystem.swift:105`) is **not** used by any room; use `ClubRoomPalette`.
- **Data honesty:** only real clubs and notes. No invented verbs ("Finished …"). Spoiler text is never shown on Home. See the header comment (`HomeClubRoom.swift:9-29`).

### 8.8 Page footer
`HomeFooter()` (`HomeFooter.swift:9-27`): "Your pace. Your place." left, KURO (bold, tracking 2) right, 10 pt `kuroMuted`, padding 28 / 28, no background. It is the last element of the scroll content, on the paper-feed inset.

### 8.9 Toast
`TastePlanToastView(message:showsUndo:german:onUndo:onDismiss:)` (`TastePicksView.swift:757-816`):
- #282F2B @ 0xF5, radius 18, padding 5/5/5/14, inset 13/13/12 from the foot, shadow #18241C @ 0x30 r 15 y 8.
- Content: the message, "Undo", and a ×. One result toast at a time.
- Installed outside the ScrollView: `.overlay(alignment: .bottom)` + `.kuroAnimation(KuroMotion.contact, value:)` (`HomeView.swift:118-121`).

### 8.10 New-account block
`FirstRunInvitation(headline:line:bottomPadding:actions:)` (`HomeNewAccount.swift:172-228`):
- ＋ 42 pt thin #858B84.
- Headline 24 bold −0.8.
- Line 13 pt #646B65, max about 24ch.
- Actions with spacing 10.
- Padding 50 / 25 / 70.
- Already shared with the Collection empty state.

## 9. Artwork material

- Model: `ArtworkMaterial { base, deep, wash, edge, ink, contrast, method }` (`Design/ArtworkMaterial.swift:78-132`).
  - `deep` = base mixed 50 % toward (.06, .07, .07).
  - `wash` = 92 % and `edge` = 72 % toward paper.
  - `ink` is always white. White on `base` is ≥ 7:1.
  - `ArtworkMaterial.neutral` = #3A3D3C.
- Lookup: `@Environment(ArtworkMaterialStore.self) private var materials`, then `materials.material(for: artworkURL, seedHex: card.material?.base)` (`Design/ArtworkMaterialStore.swift:103-110`). It returns the seed at once and publishes the derived material later. Home derives from the banner (fallback cover): `HomeView.swift:658-666`.
- Where Home uses it:
  - Scene foot: `base → deep`, top-leading to bottom-trailing.
  - Material key faces.
  - The artwork placeholder colour (`material.base.color`), so the window never flashes white.
  - The medium word uses the artwork itself, not the material.
- Where the prototype puts `wash`/`edge`: only the detail progress card and Up next row (amendment 2). Home cards stay neutral paper. Material only colours surfaces that sit **on or under the title's own art**.

## 10. Motion

| Motion | Value | Where |
|---|---|---|
| Prototype ease | `KuroMotion.ease(d)` = `.timingCurve(0.2, 0.8, 0.25, 1, d)` | `KuroDesignSystem.swift:632-634` |
| Contact (press) | `KuroMotion.contact` 120 ms | `:637` |
| Settle | `KuroMotion.settle` 220 ms (scroll-to, header title, dots) | `:639` |
| Medium / canvas | `KuroMotion.medium` 320 ms (canvas, material change) | `:641` |
| Stamp / context change | `KuroMotion.stamp` 160 ms ease-out; `.contextChange` 220 ms ease-in-out | `:643-645` |
| Gate | `KuroMotion.playsMotionNow(reduceMotion:)` for one-off sites; `KuroMotionAllowance { plays in … }` for running motion (observes Low Power live); `.kuroAnimation(_:value:)` | `Views/Shared/KuroMotionEffects.swift:15-61`, `KuroDesignSystem.swift:664-670` |
| Artwork entrance | `.homeEntrance()`: opacity .8 → 1, y 9 → 0, 380 ms `(.2,.75,.25,1)`, once per mount; final frame under RM / Low Power | `HomeSceneCard.swift:473-495` |
| Count roll | `.kuroCountRoll(value:pageTurn:)`: 220 ms lift, or a 280 ms page turn (manga) | `KuroMotionEffects.swift:78-80, 175-208` |
| Scrub trace | `HomeScrub`: 280 ms `(.22,.8,.24,1)` | `HomeSceneCard.swift:371-395` |
| Key confirm / restore / settle | `.kuroConfirmStamp`, `.kuroRestore` (650 ms), `.kuroPressSettle` (160 ms); trigger only after a durable save | `KuroMotionEffects.swift:66-85` |
| Curves | `KuroMotion.easeCurve`, `cssEaseCurve`, `pressSettleCurve`, `rollCurve` | `KuroMotionEffects.swift:27-37` |

Nothing loops except the loading scrub line, which runs only while visible, the scene is active and motion is allowed. Haptics: light impact on a medium change; selection tick on a key tap; success only after a durable accept.

## 11. Empty, loading, offline and failure states

- One rule: `KuroBrandedState.resolve(isLoading:hasContent:isOffline:failed:)` (`KuroBrandedStates.swift:38`). Content online → none; offline is named before failed; failed before loading; else empty.
- Loading in place, shaped like the real thing: `KuroSkeleton(kind: .sceneCard / .coverLeaf / .calendarDay / .detailSection / .row)` (`KuroBrandedStates.swift:338-446`).
  - Blocks are ink @ .08, deep @ .13, so they stay visible on #FFFEF8, #F5F5F3 and #F5F5F4.
  - A `KuroScrubLine` (max 96 wide) sits under them.
  - Home's first load: `sceneCard` + `row` at spacing 24 (`HomeView.swift:427-434`). The calendar's own: `HomeCalendarLoading`.
- Section-scoped failure: `KuroStateView(.failed(hasCachedContent:) / .offline(...), title:, layout: .inline, retry:)` under the content it failed to refresh (`HomeView.swift:365-377`; `Views/Shared/KuroStateView.swift:14-44`).
- Page-level states:
  - `KuroLoadingView(scope:label:)`, `KuroErrorView`, `KuroOfflineView(hasContent:retry:)`, `KuroEmptyView` + `KuroOutlineButton`.
  - All are laid out by `KuroStateLayout`: a ridge stroke 148 × 36, headline 24 bold −0.8, line 13 pt `kuroMuted`, centred, padding 20 / 32 (`KuroBrandedStates.swift:624-662`).
- On dark (club room): `HomeClubRoomFailureLine`, because `KuroRidgeStroke` is ink and disappears on the room.
- Honest "nothing" copy instead of empty:
  - `restingBand`: "Ready when you are." / "You're caught up." with the 46 × 2 rule (`HomeView.swift:539-576`).
  - The quiet card.
  - "Dates and club activity appear after you save a title." (`:391-396`).
  - A failed read is never "no clubs" (`HomeClubRoom.presentation`, `HomeClubRoom.swift:158-163`).
- Gate: `scripts/quality-gates/check_branded_states.sh` (blocking) fails on any `ProgressView(` outside `KuroBrandedStates.swift`.

## 12. Hairlines, radii and shadows (Home uses literals)

- **Hairlines:**
  - Header: `kuroLine` (#272B29 @ 0x20), 0.5 pt.
  - Quiet rows and season rows: `kuroHairline` (black @ .10), 0.5 pt.
  - On material: 1 pt white @ 0x18 / 0x24 / 0x0D.
  - Calendar: 1 pt #E3E7E1 / #DDE2DD.
  - Manga leaf: 1 pt #D8DDD2.
  - Switch: 1 pt #203027 @ 0x44.
- **Radii:**

  | Element | Radius |
  |---|---|
  | Scene card | 5 |
  | Glance, quiet card, spoiler | 8 |
  | Show-more pill, date chip | 10 |
  | Calendar | 18 (manga 14/14/5/5) |
  | Club room | 24 (manga 13) |
  | Note card | 14 (manga 3) |
  | Posters | 4 (tile, leaf); 2 (quiet row, glance thumbs); 3 (calendar row) |
  | Keys | 7 (dark 6) |
  | Toast | 18 |
  | Outline button | 12 |

  `KuroRadius` (4/8/12/16, `KuroDesignSystem.swift:529-534`) is not what Home uses. Match Home's literal, not the nearest token.
- **Shadows:** all tight and low alpha.
  - Card drop `0 1 2` at 0x05–0x0A.
  - The calendar and room drops are cast by an inset shape, so they show only under the bottom edge (`HomeCalendarCard.swift:144-150`, `ClubRoomStyle.swift:90-97`, `HomeAlsoWatching.swift:75-81`).
  - No soft halos (`KuroShadow.card` / `KuroDesignSpacing.modernShadowRadius 20` are pre-prototype).

## 13. Reusability

Classified by access control and coupling, not by folder. All are `internal` to the app module unless marked private.

**Reusable as-is (plain inputs, no Home store):**
- **Styles and primitives:**
  - `HomeContactStyle` (`HomeView.swift:1246`; already used by `ImportSourceChooser`)
  - `HomeArtworkPressStyle` (`HomeSceneCard.swift:459`)
  - `HomeArtwork(url:maxPixelSize:placeholder:)` (`:441`)
  - `HomeScrub(fraction:track:trace:)` (`:371`)
  - `.homeEntrance()` (`:493`; the extension is internal, the modifier private)
  - `HomeCalendarArt(raw:)` (`HomeCalendarCard.swift:508`)
- **Inks and metrics:**
  - `HomeInk` (`HomeSceneCard.swift:19-60`, all measured inks; consider moving it to Design if several lanes use it)
  - `HomeSceneMetrics.isCompact` (`:69`)
- **Text blocks:**
  - `HomeOpeningLineView(kicker:headline:compact:)` and `HomeQuietCard(text:)` (`HomeOpeningLine.swift:60, 94`)
  - `HomeFooter()` (`HomeFooter.swift:9`)
- **Medium switch:**
  - `KuroPosterMediumSwitch` + `KuroArtWordFill` + `HomeMediumWordInk` (`HomePagePicture.swift:91-289`; Taste already uses them)
- **Cards and layouts:**
  - `HomeComingUpGlance(summary:compact:artURL:)` (needs a `HomeGlanceSummary`; for another summary, copy its card style)
  - `HomeSceneCard` and `HomeAlsoWatchingTile`. Both are generic in `Key` and take plain values, but their props are progress-shaped (`HomeProgressReadout` is required), so reuse them only for tracked titles.
  - `HomeAlsoWatchingGrid(compact:content:)`, a generic two-column grid
  - `HomeCalendarCard` (display-only, `ReleaseScheduleItem` groups)
- **Club room:**
  - `ClubRoomPalette`, `ClubRoomBackground(cornerRadius:)`, `ClubRoomMetrics.forRoomWidth` (`ClubRoomStyle.swift`)
  - `HomeClubRoomFailure`, `HomeClubRoomFailureLine`
- **Elsewhere:**
  - `TastePlanToastView`, `TastePlanHost` (`TastePicksView.swift:757, 820`)
  - `FirstRunInvitation` (`HomeNewAccount.swift:172`)
- **Shared foundation** (meant for everyone):
  - `KuroAdvanceKey`, `KuroMediumSwitch`, `KuroInkButton`/`KuroPressStyle`, `KuroOutlineButton`
  - `KuroStateView` and the branded family, `KuroSkeleton`
  - `.kuroReadableWidth()`, `KuroFold`/`KuroFoldButton`, `KuroReleaseLine`, `KuroThemeSongRow`

**Home-coupled (read `HomeStore` / `HomeCard` / Home slices):**
- `HomePagePicture`, `HomePagePictureFill` (read `HomeStore`)
- `HomeMangaLeaves`, `HomeMangaLeavesLoading` (`[HomeCard]`)
- `HomeNewAccount` (Discovery/Library env + Home callbacks)
- `HomeFeedInsets` (Home's paper-feed constants)
- `HomeOpeningLine` (Home copy), `HomeShelfPolicy`, `HomeGlanceSummary`, `HomeCalendarPresentation`, `HomeProgressToasts`, `HomeSeasonTab`/`HomeSceneFact` (Home semantics)
- `HomeClubRoom`: its notes are `HomeClubItem`. The room renders fine with a `ClubSummary` (from `ClubSummary(row: ClubListRow)`) and `notes: []`: masthead, activity row and footer. It routes with `routes.openClub` / `openMedia`.
- `HomeView`'s private helpers: `quietShelf`, `invitationAction`, `restingBand`, `invitationCopy` (private funcs). Copy their recipe or extract them.

**Private; must be promoted before reuse:**
- `ClubSeal` and `ClubKnot` (`HomeClubRoom.swift:565, 581`, `private`). The Clubs list and detail will want the same seal. Move them to `ClubRoomStyle.swift` (`ClubsView.swift:287-291` currently draws a plain ＋ in a ring instead).
- `HomeMediumScroll` (`HomeView.swift:1214`; per-medium scroll restore)
- `HomeLeafCover` (`HomeMangaLeaves.swift:248`)
- `HomeEntranceModifier` (reach it through `.homeEntrance()`)

## 14. Drift a Discover/Clubs lane should know

1. **Club room compact threshold:** Home `width < 330` (`HomeClubRoom.swift:278`) vs `ClubRoomMetrics.compactRoomWidth` ≤ 328 (`ClubRoomStyle.swift:59`).
2. **Seal size:** Home ring 36 / 30 (`HomeClubRoom.swift:315`) vs `ClubRoomMetrics` seal 43 / 36 (`ClubRoomStyle.swift:61-62`). The spec measures the seal box at 42.7. Pick one when unifying the Clubs list, detail and Home room.
3. **Inline note styles:** `ClubsView.swift:321-324` re-inlines the note-card shadow (black @ 0x22) and border (white @ 0x88) instead of `ClubRoomPalette.noteShadow` / `noteBorder`.
4. **Unused room token:** `kuroRoom` #222222 exists but every room draws `ClubRoomPalette.room` #252B28.
5. **Duplicated opening row:** `TasteOpening` copies `HomeOpeningLineView` inline (`TastePicksView.swift:937-952`).
6. **`KuroSectionHeader` mismatch:** its file comment says serif; it renders 26 pt SF semibold untracked. Home's headings are hand-set (§4). Discover and Clubs currently use `KuroSectionHeader` + `.kuroKicker()` (2.1 tracking), Home's opening uses 1.05 tracking, so their eyebrows read wider and lighter than Home's.
7. **Two switch styles:** compact `KuroMediumSwitch` vs `KuroPosterMediumSwitch` (§5).
8. **Canvas:** Discover and Clubs (list and detail) paint #FFFFFF. Home and Taste paint #FFFEF8 / #F5F5F3 (§1 seam rule).
9. **Hairline weights:** `kuroLine` 0.5 (header) vs `kuroHairline` 0.5 (rows) vs measured 1 pt literals in cards.
10. **Manga ink:** the prototype manga page ink is #272C28; native uses `kuroInk` everywhere.
