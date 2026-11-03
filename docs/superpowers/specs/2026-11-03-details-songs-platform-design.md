# Details, songs & platform: "The companion page" (binding spec)

**Date:** 2026-11-03
**Branch:** `kuro/details-songs-platform` (integration branch, made from `kuro/discover-clubs-redesign` at `a59a5e4`; local, never pushed)
**Status:** binding for the four UI lanes (Detail; Songs + entities; Widget; Profile + import + finishes), for the two foundation lanes (Data, Platform) where §16 names an interface, and for the integrator.

**Owner request (2026-11-03, verbatim):** "Put all of these to work, please, all of them. Don't ask me anything. just implement it." This covers the 13 items listed in §2. The owner said not to ask, so every open choice is decided here and recorded in §18.

**Inputs, in order of authority:**
1. Home as shipped (`Kuro/Views/Home/*`) and last night's Discover/Clubs redesign (`docs/superpowers/specs/2026-11-03-discover-clubs-redesign-design.md`, cited as **DC§n**).
2. The prototype `tools/design-directions/instrument.html`, through `docs/prototype-fidelity/PROTOTYPE_SPEC.md` (cited as **PS§n**; detail anatomy D1–D11 at PS§4 "Detail, anime/manga") and `LANE_AMENDMENTS.md` ("the prototype wins").
3. `docs/discover-clubs-2026-11-03/understand/HOME_GRAMMAR.md` (cited as **G§n**).
4. The navigation contract `docs/superpowers/specs/2026-11-02-navigation-contract-design.md` (N1–N11, H1–H4, F1–F3).
5. The foundation lanes' code as merged on this branch (data: `kuro/details-songs-platform-data`; platform: `kuro/details-songs-platform-platform`).

**Supporting design documents:**
- Judging: `docs/details-songs-2026-11-03/design/JUDGING.md`. **Companion won with 8.15.** Archive scored 7.85 and Cinematic 7.65.
- Final mockup: `docs/details-songs-2026-11-03/design/final.html`. It is a fork of `companion.html`, with the grafts applied and a "Lead rulings" panel at the top.
- The three candidate mockups (`archive.html`, `companion.html`, `cinematic.html`) stay in the same folder as the record.

> **Precedence.**
> - This spec beats `final.html`.
> - Home's code beats this spec on a measured value. Use Home's constant and note the difference in the lane report.
> - A foundation lane's merged code beats §16 on a name or signature. The UI lane adapts to the merged code and notes it. It never edits the foundation file.
> - The old "DESIGN SYSTEM" section of CLAUDE.md (`kuroBlack80` era) does not apply (G, header note).

---

## 1. Intent

The title page becomes a **watch companion that still reads like Home**:
- **The hero becomes a Home scene card.** It keeps the artwork window and the material foot, and adds the title's facts and its next episode or chapter as the scene card's fact rows.
- **The episodes become a timeline** you have walked.
- **The cast leads from character to voice and back.**
- **The songs become a short player list** with real Apple previews.
- **Character, staff, studio and author pages move into Home's grammar.**

Beyond the page:
- a Home Screen widget with +1
- release notifications that never lie about time
- Profile numbers counted on the device
- import screens in the same language
- three finishes: edge peek, a shorter Discover All, and VoiceOver correct by construction

## 2. Goals (the 13 owner items) and non-goals

| # | Item | Where |
|---|---|---|
| 1 | "More like this." on detail pages from `media_similar_titles` (the Taste engine), as a Home-style rail with Plan keys | §6.8, §7.6, D7 |
| 2 | Richer hero: year, format, episodes or chapters, studio, score; the next episode or chapter from the release read model with `ReleaseCopy` certainty wording; Home's season tab | §6.2, §7.2, D3–D5 |
| 3 | Episodes as a timeline: thumbnail, title, air date, watched tick | §6.4, D6, D20 |
| 4 | Characters and cast with Japanese voice actors, linked both ways | §6.7, §9.1, §9.2, D8 |
| 5 | Replace the 映 / 原作 placeholders with the real cover or a branded tile | §5.2, §6.5, §7.5, D9 |
| 6 | Character, staff, studio and author pages in Home's grammar | §9 |
| 7 | Songs: Apple artwork, a 30-second preview that plays on the page, "Open in Apple Music", attribution; Spotify stays a search link | §8, D11, D12 |
| 8 | Songs grouped by part, the artist on every song, version tags, the spoiler cover kept | §8.2, D10 |
| 9 | Home Screen widget: next-release countdown and Now Watching with an interactive +1 | §10, D13, D22 |
| 10 | Local notifications for new episodes and chapters; permission asked only on an explicit action; EN/DE; no notification for estimates; cleared on sign-out | §11, D14 |
| 11 | Profile stats: episodes and chapters done, time spent, top genres, "your year" | §12, D15 |
| 12 | Restyle every import screen into Home's grammar, keeping every behaviour and copy rule | §13, D16 |
| 13 | Edge peek on every sideways rail; Discover All length; VoiceOver order correct by construction (device check open) | §5.1, §14, D17–D19 |

### Non-goals

**Backend: prepare only.**
- New SQL goes to `supabase/prepared-migrations/` with local DB tests.
- Edge-function changes come with deno tests.
- Never apply, deploy, change a flag, write production data, or push. The lead does that after review.

**Product limits.**
- No runtime call to the iTunes Search API from the app (D11). Matching is a server-side worker.
- No new Library fields. In particular there is no finish date (D15).
- No change to:
  - Home's own files (`Kuro/Views/Home/*`)
  - Taste, Browse, Search or Collection
  - the club pages
  - the shared foundation views listed in §19.6

**Out of scope for item 13.** Rails outside Discover, entity pages and detail pages, such as Browse, Search, Taste and Collection, are not touched.

**Copy.** No English or German rename of an EXISTING string (§15).

---

## 3. Decisions (D1–D24)

### Direction, hero and episodes (D1–D6)

**D1. Base direction: Companion, with grafts from Archive and Cinematic** (JUDGING.md).
- Why: it reads most like Home (glance cards, quiet rows, material keys, `TastePlanKey`, the cover line), its entity pages are the clearest, and its widget and import frames are already Home paper.

**D2. The prototype section order stays.**
- The order is hero → story → club presence → seasons → progress → units → source → songs → characters → credits → **more like this** (new) → between us.
- Companion's "your place first" reorder is not taken.
- Its progress and "Coming up" content moves into the hero's fact row (D3) and the existing progress card.
- Why: `DetailSectionPolicy` encodes the prototype order (PS§4), and "the prototype wins".

**D3. The anime hero is Home's scene card** (graft from Archive).
- The D1 artwork window stays at 150.6 pt (PS§4 D1) with its `clear → deep` shade.
- **Home's season tab** sits on the art's bottom-left edge when the proven chain has two or more numbered seasons.
- The heading block (the scene foot) gains two **fact rows**:
  1. the facts line
  2. the next-release row with the bell
- Cinematic's 428 pt poster window is not taken.
- Why: the scene card is Home's own anatomy (G§8.3). The prototype's hero height is measured.

**D4. Score is `averageScore / 10` with one decimal in the locale's separator** ("Score 8.6", "Wertung 8,6"), the same as the existing `MetaLineSection`.
- No score is shown when `averageScore` is nil or 0.
- The score is a fact of the source, and nothing is added to it.

**D5. The next release comes only from `ReleasesStore`.**
- The source is `mediaSchedule(kind:id:)` through the page's existing `.detailReleases`, falling back to the catalogue seed `DetailNextReleaseSection.seed`.
- The words come from `ReleaseCopy.line(_:)`.
- A time of day appears only when `item.showsTime`.
- Estimates carry the dashed **Estimate** mark and never a bell.
- Why: item 2's certainty rule, applied through one copy owner.

**D6. Episodes become the timeline inside the existing D6 units block** (§6.4).
- The progress card and the Up next row with its material +1 key are kept exactly.
- Watched runs of three or more fold into one line.
- Why: combines Companion's rail and Cinematic's collapse, with no new tracking path.

### Cast, songs and Apple (D7–D12)

**D7. More like this comes from `RecommendationsReader.moreLikeThis` (§16.1).**
- The reader is `media_similar_v1` first, then the live `recommend_ids_similar_to_seeds` and hydrate path.
- There is **no genre fallback**: an unavailable read hides the section.
- Keys are `TastePlanKey(card:variant: .leaf, compact: true)` under one page `.tastePlanHost`.
- Titles from the page's own ladder (numbered, extras, source) are dropped on the client as well.
- Results are held per account (§16.1).
- Why: it is the same engine as Taste, and it uses Discover's plan grammar (DC D5).

**D8. One cast rail; each card has two targets** (graft from Cinematic):
- the portrait and name push the character page
- a voice chip under them pushes the voice actor's staff page

Rules:
- When MAIN or SUPPORTING characters exist, BACKGROUND characters are dropped.
- When only BACKGROUND characters exist, they are shown, so the rail is "always populated when data exists".
- Companion's second "The cast." ledger is not drawn, because it showed the same data twice.

**D9. One branded tile replaces every missing picture** (§5.2): 映 / 原作, missing covers, no-match song art, episodes without stills, people and studios without an image.
- It never shows a kanji glyph or a stock face.

**D10. Songs are grouped by part, using episode ranges only.**
- An opening starts a part. Endings and insert songs join the part that holds their first episode.
- The part heading is the episode span ("Ep. 1–5"). **No arc names**, because the data has none: Companion's "Hidden Inventory" and Cinematic's "Shibuya Incident" were invented.
- The versions of one song collapse into one row with version tags.
- Songs need no season switch: each season is its own title page.

**D11. The app never calls the iTunes Search API.**
- It shows only what the data lane's worker stored (`theme_links.apple_*`, served by `media_themes_v1`).
- It validates every Apple URL by host (§16.2).
- It **streams** the preview with `AVPlayer`. Audio is never downloaded or cached.
- One preview plays at a time.
- Playback stops when the user leaves the page, when the app is backgrounded, or on an interruption or route change.
- There is **no mini-player** (Cinematic's is not taken).

**D12. Matching stays strict.** The worker accepts a title plus artist after normalisation, with confidence ≥ 0.8.
- Karaoke, instrumental, off-vocal, cover, remix and live takes are rejected.
- A TV-size version loses a tie.
- A song with no artist gets no Apple request.
- **Aliases are not accepted tonight.** For example, "Ao no Sumika" is not matched to "Where Our Blue Is". This is recorded as open (§17).

### Widget and notifications (D13–D14)

**D13. The widget follows the platform lane's model, not Cinematic's.**
- `AdvanceProgressIntent` only queues a request in the App Group.
- The app drains the queue through `LibraryActions.advanceQueuedProgress`, which keeps the caught-up guard, the durable outbox and the revision fence.
- The widget shows a queued +1 at once (`isQueued`), with the caption "Saved when Kuro opens".
- The widget never plays a confirm stamp.
- The widget never uses a URL for a write. A URL is navigation only.

**D14. Notification rules.**
- **What can notify.** Only a release row with `item.showsTime` (precision instant and not an estimate) and a basis of confirmed or announced. An announced *day* does not notify.
- **When.** One notification at `releaseAt`. The legacy "1 h before" reminder is retired.
- **Asking for permission.** Only `ReleaseReminders.setFollowing(true)` (the Profile toggle) and `toggle(_:)` (the detail bell) may ask. The Library sink and every background path never prompt.
- **Default.** Off.
- **Per-title bell.** The bell sets a per-title override.
- **Clearing.** Everything is removed on sign-out or account switch.

### Profile, import and finishes (D15–D19)

**D15. Profile stats are computed on the device** from `LibraryStore` plus catalogue rows (§12).
- **"Your year"** counts titles **saved or changed** in the year, and says so, because `LibraryEntry` has only `createdAt` and `updatedAt`. Companion's "9 series finished" is not computable and is not shown.
- **Time** is episodes × each title's episode length. Titles without a length are counted in a caveat and never padded.

**D16. The import screens keep every string byte-identical**, including the upper-case literal `"READ COMPLETE LIST FOR REVIEW"` (`ConciergeView+AniListImport.swift:267`).
- "Form / Preview" becomes refine words with the same binding.
- Only the shells, fields, toggles and type change.
- Sentence case would change a copy literal. It is recorded as an owner choice (§18), not applied.

**D17. Discover All.**
- **Measured baseline (CORRECTED 2026-11-03 integration review).** The committed render `docs/discover-clubs-2026-11-03/after/discover-all-full-390.jpg` ends its content at about 1,641 px of a 2,702 px canvas, but that render is vertically squashed to about 61 % (2:3 covers measure about 106 × 92 px; the hero card is 170 pt tall there and 278 pt in an undistorted render). The real pre-change length was therefore about **2,700 pt**, not 1,641 pt, and "the aim of about 2,000 pt or less already holds" was false. The undistorted after render (this pass) is **2,102 pt**: a real reduction of about 600 pt, but about 100 pt over the 2,000 pt acceptance and about 600 pt over the 1,500 pt target. The next layout step (for example Trending or Manga new to you into the fold, or no Airing-today strip on All) is a lead decision, recorded open in §17.
- **The lead decision is applied anyway:**
  - On All, "Manga new to you" becomes **one rail**.
  - On All, "Essential manga" moves **into the fold** as its first section.
  - The Anime and Manga issues are unchanged.
- **Target:** 1,500 pt or less. Acceptance is 2,000 pt or less.

**D18. One edge-peek rule (§5.1) for every sideways rail** on Discover, entity pages and detail pages.
- Each lane writes a lane-local copy with the exact code in §5.1.
- The integrator folds the copies into `Kuro/Views/Shared/KuroRailPeek.swift` (§19.7).

**D19. VoiceOver order is correct by construction** (§14.3) and **not device-checked**. It stays open in the report.

### Data guard, widget views and process (D20–D24)

**D20. Episode stills pass a wrong-season guard before they are shown** (`EpisodeStillPolicy`, §6.4.3).
- The guard is a pure detail-lane policy with tests.
- Why: Cinematic found that AniList `streamingEpisodes` attaches Season 1 episodes to JJK S2 (145064) and Season 2's absolute-numbered list to Apothecary S1 (161645).

**D21. The entity pages' refine words copy the grammar of Discover's `DiscoverRefineRow`:** 11 pt medium, ink or `kuroMuted`, a 16 × 1.5 ink rule, a 44 pt row, `HomeContactStyle`.
- They are written as a lane-local generic view, because `DiscoverRefineRow` is typed to `DiscoverRailFilter`.
- The black filter pills (`EntityFilterBar`) stop being used.

**D22. The widget's SwiftUI content lives in a new synchronized folder, `KuroWidgetViews/`.**
- The folder is compiled into **both** the Kuro app target and the KuroWidgets target, so KuroTests can render it.
- The content views are generic over the +1 key slot. The extension passes `Button(intent:)`, and tests pass a plain view.
- The widget lane owns this one `project.pbxproj` edit.

**D23. The UI lanes branch from `kuro/details-songs-platform` only after both foundation lanes are merged into it.** Before that, the interfaces in §16 do not compile.

**D24. The integrator updates the Rule 1/2 documents once, after all lanes** (`CURRENT_APP_STATE*.md`, `IMPLEMENTATION_PLAN_Variation1.md`, MEMORY.md, the CLAUDE.md file map and counts). This follows DC§12.4.

---

## 4. Home grammar used (reference card)

Every value is in G§1–§13 and DC§4. Lanes copy Home's literals; they do not invent new ones. The values below are the ones this work leans on most.

| Role | Value | Source |
|---|---|---|
| Detail paper | `Color.kuroPaper` #F5F5F4 (anime detail, and character, staff, studio and author pages); manga detail keeps its prototype paper | G§1, PS§4 |
| Detail gutter | body padding 24 at every width (prototype `.detail-body` 23/24/24; the code has no compact case) | `AnimeDetailSections.swift` body `.padding(.horizontal, 24)` |
| Detail heading | `DetailSectionHeading(title:size:tracking:note:)`: 17 semibold −0.4, or 18/−0.7, with a 9/10 pt note | `Prototype/DetailPage.swift:130` (read-only API) |
| Page heading (Profile, import) | 24 semibold −0.85 + 10 pt #656C66 summary | G§4 |
| Eyebrow | 9 pt (8 compact), tracking 1.05, uppercase, `HomeInk.kicker` #666C68; on material use the detail kicker #C6CECA, 8 pt, tracking 1.7 | G§4, PS§4 D1 |
| Scene fact row | min 40/44, 1 pt white @ 0x0D top rule, 10/9 pt `HomeInk.footFact` #DCE2DF | G§8.3 |
| Glance card | `HomeInk.glanceFill` #FFFEFA, radius 8, 1 pt `glanceBorder`, padding 10/12, min 72 | G§8.1 |
| Quiet row | 40 × 60 cover (radius 2), gap 16, min 60, 0.5 pt `kuroHairline` | G§7 |
| Cover line | 44 semibold −0.8, 14 gap, **46 × 2 ink rule** | G§7 |
| Keys | `KuroAdvanceKey` (+1; `.material`, `.ink`, `.dark`); `TastePlanKey` (Plan); ghost ✓ #767B77 on paper / #B9C5C1 on art | G§6 |
| Refine words | 11 pt medium, ink/`kuroMuted`, 16 × 1.5 ink rule, 44 pt, `HomeContactStyle` | `Views/Discover/DiscoverRefineRow.swift` |
| Rail cover | 2 : 3, radius 4, 14 pt spacing, width from §5.1 | `DiscoverIssueLayout.railSpacing`, §5.1 |
| Motion | contact 120 / settle 220 / medium 320 on the prototype ease; `KuroMotion.playsMotionNow`, `KuroMotionAllowance`; nothing moves under Reduce Motion or Low Power | G§10 |
| States | `KuroBrandedState.resolve`, `KuroSkeleton(kind:)`, `KuroStateView(..., layout: .inline)`, `KuroOfflineView`, `HomeQuietCard`; never `ProgressView(` | G§11 |
| Toast | `TastePlanToastView` through `.tastePlanHost` (Plan); the page's existing `DetailToastOverlay` (bell) | G§8.9 |

---

## 5. Shared rules (every lane)

### 5.1 Edge peek (item 13; D18)

Every horizontal card rail:
- spans the full width of its page column, so it bleeds past the trailing gutter to the screen edge on iPhone, or to the readable-column edge on iPad
- starts at the page gutter
- ends with the gutter as trailing content inset
- shows a slice of the next card

The rail's `ScrollView` must **not** sit inside the page's horizontal padding. Either move it out of the padded stack, or give it a negative trailing padding equal to the gutter.

Card width is this pure function. Each lane copies it **verbatim** into its own layout enum (`DetailRailPeek`, `EntityRailPeek`, `DiscoverIssueLayout.railPeek…`), and the integrator folds the copies into one file:

```swift
/// Edge peek (details-songs spec §5.1). `visible` = the rail's frame width minus its leading content inset
/// (390 iPhone, detail gutter 24: 366; Discover gutter 20: 370; iPad readable column 680 − 20: 660).
nonisolated enum KuroRailPeek {
    static let preferredWidth: CGFloat = 100
    static let minWidth: CGFloat = 92
    static let maxWidth: CGFloat = 112
    static let peekTarget: CGFloat = 28
    static let peekMin: CGFloat = 18
    static let spacing: CGFloat = 14

    static func cardWidth(visible: CGFloat, spacing: CGFloat = spacing) -> CGFloat {
        guard visible > 0 else { return preferredWidth }
        let whole = max(2, Int(((visible - peekMin) / (preferredWidth + spacing)).rounded(.down)))
        let count = CGFloat(whole)
        let width = ((visible - count * spacing - peekTarget) / count).rounded(.down)
        return min(maxWidth, max(minWidth, width))
    }

    /// 2 : 3 covers and portraits.
    static func coverHeight(width: CGFloat) -> CGFloat { (width * 1.5).rounded() }
}
```

Expected values, which every lane's tests pin:

| visible | cards fully shown | width | slice of the next card |
|---|---|---|---|
| 366 (390, detail) | 3 | 98 | 30 |
| 370 (390, Discover) | 3 | 100 | 28 |
| 304 (320, gutter 16) | 2 | 112 | 52 |
| 410 (430, Discover) | 3 | 112 | 32 |
| 660 (iPad) | 5 | 112 | 30 |

**Exemptions:**
- The prototype's D4 season tiles (a measured two-up row)
- The club rails
- Home
- Browse, Search, Taste and Collection

### 5.2 Branded tile (item 5; D9)

One tile replaces every missing picture. The detail lane builds `DetailBrandedTile` and the songs + entities lane builds `EntityBrandedTile`, both lane-local with identical values. The integrator folds them into `Kuro/Views/Shared/KuroBrandedTile.swift`.

```swift
/// kind: "Anime · TV", "Manga", "Light novel", "Ep. 8", "OP 1", "ED 2" (already localised); title optional.
struct KuroBrandedTile: View {
    enum Style { case paper, ink, onMaterial }
    let kind: String
    var title: String? = nil
    var initials: String? = nil      // people/studios: "YN"
    var style: Style = .paper
    var cornerRadius: CGFloat = 4
}
```

**Paper** (covers, stills, the source and adaptation cards). This is the prototype's D4 season tile:
- Fill `linear-gradient(150°, #FFFFFF → #EEF1EE)`, 1 pt #D9DEDB border.
- Vertical stripes: 1 pt #232C24 @ 0x05 every 6 pt.
- "KURO" top-leading in 7 pt heavy, tracking 1.4, #7B847E.
- The kind word under it in 7 pt uppercase, tracking 1, #7B847E.
- The title bottom-leading in 11 pt medium #4F5A52, up to 3 lines. It is omitted when the tile is narrower than 60 pt.

**Ink** (people and studios without an image):
- `kuroKeyDarkTop → kuroKeyDarkBottom`.
- Initials 22 semibold, white @ .9, centred.
- No stripes.

**On material** (song art on the sound panel):
- `base → deep`, 1 pt white @ 0x24.
- The kind word ("OP 1") 11 pt semibold white @ .85, centred.
- A 14 × 1 rule under it.

**Rules for every style:**
- The tile is decorative (`accessibilityHidden(true)`). The row or card it sits in speaks.
- It never carries a kanji glyph, a stock silhouette or a per-title colour table.

### 5.3 Certainty marks (items 2, 9, 10)

A hairline stamp after the release line.

**Paper style:**
- 8 pt uppercase, tracking .6, #4F5A52.
- 1 pt #4F5A52 @ .35 border, radius 3, padding 2/5.

**On material:**
- Text #DCE2DF, border white @ .35.

**Words by basis:**

| Basis | Words (EN / DE) | Border |
|---|---|---|
| `confirmed` | **Confirmed** / **Bestätigt** | solid |
| `announced` | **Announced** / **Angekündigt** | solid |
| `estimated` | **Estimate** / **Schätzung** | dashed (#6B736C) |

**Times and the bell:**
- A time is shown only when `item.showsTime`.
- An estimate uses `ReleaseCopy`'s "expected around …" wording and **no bell**.
- An undated row says `ReleaseCopy.datesToCome` and has no mark.

**Source line:**
- `ReleaseCopy.sourceAttribution(item)` (for example "via AniList", "Kuro estimate from recent releases"), 9 pt muted.
- On the hero it is shown in the next-row VoiceOver value only. Under the manga glance it is shown as text.

### 5.4 Data honesty (every screen)

- A section, row or fact without real data is **left out**. It is never "—", never sample copy, never a zero.
- A failed read is never shown as empty (G§11). It is either the inline failed state, or the section is hidden when the owner cannot distinguish a failure (§17 lists these).
- Personal numbers are only ever the account's own Library values.

### 5.5 Navigation (every tap)

All movement follows the navigation contract:
- Every tap inside a journey **pushes** through `\.kuroRoutes` (`openMedia`, `openPage(.character / .staff / .studio / .author)`).
- N5 pops back to a page already in the stack. This makes Maomao → Aoi Yuuki → Maomao bounded.
- Tools close back to their page (N7).
- Back and ✕ are always reachable (N1–N3, H1–H4).
- Folds are session-remembered (F1–F3, `KuroFoldMemory`).
- No new `.sheet(` shows routed content without the journey host (`check_navigation.sh`).

---

## 6. Anime detail page (Detail lane)

### 6.1 Order and layout at 390 pt

| # | Section | Change |
|---|---|---|
| 1 | Hero (D1 + scene-card fact rows) | facts line, next-release row with bell, season tab (§6.2) |
| 2 | Story (D2) | unchanged |
| 3 | Club presence (D3) | unchanged |
| 4 | Seasons (D4) | unchanged; it is also the hero's season-tab target |
| 5 | Progress (D5) + Units (D6) | units become the timeline (§6.4); progress card and Up next unchanged |
| 6 | The original story (D7) | real cover or branded tile (§6.5) |
| 7 | The sound of it. (D8) | **Songs + entities lane** (§8); the detail lane does not touch this call site (§19.7) |
| 8 | The characters. (D9) | cast rail with voice chips (§6.7) |
| 9 | Behind the frames. (D10) | unchanged rows; studio and author rows already push their pages |
| 10 | **More like this.** (new) | §6.8 |
| 11 | Between us. | unchanged |

`DetailSection` gains `.moreLikeThis` between `.credits` and `.betweenUs`. `DetailSectionPolicy.sections` shows it when `similarCount > 0`. `DetailInput` gains `similarCount` and `hasNextRelease`.

### 6.2 Hero (item 2; D3–D5)

**Artwork window:** unchanged (150.6 pt, `HomeArtwork`, the shade).

**Season tab** (only when `content.chainIsProven` and `content.numbered.count ≥ 2`):
- Home's tab anatomy (G§8.3), drawn as a detail-local `DetailSeasonTab`, because Home's is a private function:
  - face `HomeInk.tabFace` #F3F4F4, top corners 8, min 31 tall, white @ 0x65 top lip
  - "SEASON" / "STAFFEL" 7 pt uppercase, tracking 0.3
  - the number 17 semibold mono `HomeInk.tabInk`
  - "of {n}" / "von {n}" 9 pt #6B776D
- Bottom-left, 12 pt in. A 44 pt target.
- **Tap:** scrolls to the Seasons section (`proxy.scrollTo(.seasons, anchor: .top)`, `KuroMotion.medium`, instant under Reduce Motion). There is no new picker.

**Heading block** (on `deep`, padding 4/24/19 as measured). In order:
1. Kind kicker and title row with the status mark: unchanged.
2. **Facts line** (new, `DetailFactsLine`). 10 pt (9 compact) `HomeInk.footFact`, parts joined by " · ", 2 lines max (wraps at AX sizes, never truncates mid-word). Parts, in order, each dropped when missing:
   - Year: `seasonYear`, else the start-date year.
   - Format word: TV · Film · OVA · ONA · Special · TV short / TV-Kurzserie · Music / Musik.
   - Count: "{n} episodes" / "{n} Folgen" when `episodeCount > 0`. When a releasing title has no total, the part is dropped.
   - Main studio name: plain text. The link is in "Behind the frames.", so targets are not nested.
   - Score (D4): "Score 8.6" / "Wertung 8,6", where the value is white @ .95 and medium.
   - VoiceOver reads the line as one element, joined by ", ".
3. **Next-release row** (new, `DetailNextReleaseRow`). Shown when the title is not finished and `upcoming.first` exists. The scene fact-row grammar:
   - **Container:** min 44, 1 pt white @ 0x0D top rule, padding top 9.
   - **Left column:**
     - Kicker "NEXT EPISODE" / "NÄCHSTE FOLGE" (chapter: "NEXT CHAPTER" / "NÄCHSTES KAPITEL"; volume: "NEXT VOLUME" / "NÄCHSTER BAND"), 7 pt, tracking 1.4, #C6CECA.
     - Under it, `ReleaseCopy.line(item)` in 12 pt medium #FAFAFA, 2 lines, then the certainty mark (§5.3, on material).
   - **Right column:**
     - The day count: "today" / "heute", "tomorrow" / "morgen", "in {n} days" / "in {n} Tagen", from `ReleaseCopy.daysFromToday`, in 10 pt #DCE2DF, hidden when nil.
     - Then the **bell**, only when `ReleaseReminders.isEligible(item)` (§11). The bell is 44 × 44 with a 15 pt glyph: outline when off and filled when on, white @ .9, with a 1 pt white @ 0x24 leading divider (48 tall, as on the scene foot).
   - **VoiceOver:**
     - Row: one element, label `ReleaseCopy.accessibilityLine(item)`, value = the basis word plus the source attribution.
     - Bell: its own button. Label "Remind me when episode {n} airs" / "Erinnere mich, wenn Folge {n} läuft". When on: "Reminder on for episode {n}" / "Erinnerung für Folge {n} an".
   - **Bell tap:** calls `await ReleaseReminders.toggle(item.key)` and shows the result in the page toast (§11.4). The bell is `HomeContactStyle`, with a light haptic only after `.on`.

**Accessibility sizes:**
- The right column moves under the line.
- The bell keeps 44 pt.

### 6.3 Progress and Up next (unchanged)

`DetailProgressCard`, `DetailUpNextKey`, `DetailAdvance` and the `LibraryActions.apply` path stay exactly as they are. The timeline (§6.4) sits around them.

### 6.4 Episode timeline (item 3; D6, D20)

#### 6.4.1 Layout

The timeline replaces the row list inside `AnimeUnitsSection`. The heading "Episodes" stays, with the note "{watched} of {total} watched" / "{watched} von {total} gesehen" (or "{n} episodes" when untracked).

A 1 pt #CFD6CF spine runs at x = 7. Each row:

| Part | Value |
|---|---|
| Node | 15 pt circle. **Watched** (number ≤ Library progress): #3B443D fill with a white ✓ (8 pt). **Up next**: a 2 pt `material.base` ring on white. **Later**: a 1 pt #AEB7AF ring on paper. **Estimate**: the same ring, dashed. Hidden from VoiceOver. |
| Still | 84 × 47 (16 : 9), radius 3. The guarded thumbnail (§6.4.3), or the paper branded tile with kind "Ep. {n}" / "F. {n}". Compact 72 × 40. Hidden at AX sizes. |
| Text | Small line: "Ep. {n}" / "F. {n}", plus " · watched" / " · gesehen" when watched, 9 pt #6B776D. Title: 12 pt semibold ink, 2 lines. It is **omitted** when nil, blank, or the generic pattern `^(Episode\|Folge\|Ep\.?)\s*\d+$`, so "Episode 7" is never written twice. Date: 9 pt muted, from `airDate` in `ReleaseCopy` day style ("Fri 17 Oct" / "Fr. 17. Okt."). When the source is absolute-numbered and an offset applies, "No. {n}" / "Nr. {n}" follows in 9 pt muted. |
| Gaps | 12 pt column gap, 9 pt vertical padding, rows min 60. |

**The Up next row** keeps its existing wash card and material +1 key, now with the node and still.

**Future rows** come from `upcoming` (at most 3 after Up next):
- `ReleaseCopy.line` and the certainty mark.
- No title is invented.
- No bell. The bell lives only in the hero.

**Watched runs.** When progress ≥ 3 and earlier watched rows exist above the last two watched rows, those earlier rows fold into one 44 pt line:
- "✓ Episodes 1–{k} · watched" / "✓ Folgen 1–{k} · gesehen", with "Show" / "Zeigen" and "Hide" / "Ausblenden".
- It is a `KuroFold` with memory key `DetailFold.watched` (F1–F3).

**"More episodes ↓"** (existing paging): unchanged.

**Row tap:** unchanged from today.

#### 6.4.2 Untracked titles

There is no tick and no Up next. Rows start at Episode 1.

#### 6.4.3 `EpisodeStillPolicy` (pure, tested)

```swift
nonisolated enum EpisodeStillPolicy {
    struct Verdict: Equatable { let showsSourceRows: Bool; let offset: Int }
    /// rows: the loaded `Episode` numbers; total: `anime.episodeCount`; priorEpisodes: the summed episode
    /// counts of the earlier numbered seasons when the ladder carries them (nil otherwise).
    static func verdict(numbers: [Int], total: Int?, priorEpisodes: Int?) -> Verdict
}
```

**The rules:**
1. When `total` is known and the source has more rows than `total`, show no source stills, titles or air dates for this title. This is the JJK S2 case: 24 rows for 23 episodes.
2. When every number lies in `1...total`, accept with offset 0.
3. When every number lies in `(prior + 1)...(prior + total)`, accept with offset `prior`. The row shows season number `n − prior`, and "No. {n}" quietly. This is the Apothecary absolute-numbering case.
4. Otherwise reject.
5. An unknown `total` with numbers starting at 1 is accepted with offset 0.

A rejected title still draws every row by number, with branded tiles and no titles. **Open (§17):** equal counts that belong to the wrong season cannot be detected.

### 6.5 The original story card (item 5)

- `DetailSourceCard` shows `MediaLadderItem.coverImage` in the prototype book frame (page-stack shadow kept).
- When there is no cover, it shows the paper branded tile with kind "Manga" / "Light novel" / "Novel" (from the ladder format) and the title.
- The 原作 glyph is removed. Everything else (the coverage fold, Explore →) is unchanged.

### 6.6 Songs slot

The Detail lane keeps the `.songs` case calling `DetailSoundPanel(...)` exactly as it is today. The integrator replaces it with `DetailSongShelf` (§8.1, §19.7).

### 6.7 Cast rail (item 4; D8)

**Data:**
- Anime: `catalog.fetchCast(forAnime:)` → `[CastMember]` (§16.1). It replaces the page's `fetchCharactersForAnime` read for this rail. The rest of the credits are unchanged.
- Manga: keeps its characters read and has no voice chips.

**Shown members:**
- MAIN and SUPPORTING first, in source order, capped at 25.
- When neither exists, BACKGROUND characters are shown instead.
- The section shows when at least one member is shown.

**Heading:** `DetailSectionHeading("The characters." EXISTING, note:)`. The note is "Japanese cast" / "Japanische Besetzung" when any member has a voice actor, otherwise "{n} characters" / "{n} Figuren".

**Rail:** peek width (§5.1, 98 at 390), 14 spacing.

**Each card has two targets.**
- **Character target.** Portrait 2 : 3 (98 × 147), radius 5, `HomeInk.posterFill` placeholder. Name 12 pt medium ink, 2 lines. Role 9 pt muted: "Main" / "Hauptrolle", "Supporting" / "Nebenrolle", "Background" / "Nebenfigur". Tap → `routes.openPage(DetailNavigation.characterPage(character))`.
- **Voice chip.** A separate button, min 44 tall, full card width, `HomeContactStyle`:
  - 20 pt disc: the staff image, or the ink branded tile with initials.
  - Gap 6.
  - The voice actor's name, 10 pt #5A695F, 1 line.
  - Tap → `routes.openPage(.staff(staff))`.
  - The chip is **left out** when there is no voice actor. No placeholder face.
- **VoiceOver:** the card reads "{character}, {role}". The chip reads "{name}, voice of {character}" / "{name}, Stimme von {character}".

### 6.8 More like this (item 1; D7)

**Data:**
- Call `recommendations.moreLikeThis(anime: anime, limit: 12)` (§16.1) once per account and title.
- Store it in `@State` keyed by `"\(accountId ?? "-")|\(anime.id)"`. Drop it when the account changes.
- Drop ids in `content.numbered`, `content.extras` and `content.source`.

**Visibility:**
- `.loaded` with ≥ 1 title → shown.
- `.loaded([])` or `.unavailable` → hidden. A recommendation rail is not a primary read, so it gets no failure line. The page's offline band already names offline.

**Heading:** `DetailSectionHeading("More like this." / "Mehr davon.", note: "From what this title shares" / "Nach Gemeinsamkeiten mit diesem Titel")`.

**Card** (peek width):
- Cover 2 : 3, radius 4.
- Title 12 pt medium, 2 lines.
- Line 10 pt muted: "{year} · {format word}".
- Under them, `TastePlanKey(card: TasteCard(anime:), variant: .leaf, compact: true)` at 44 pt.

**Taps:**
- Cover or title → `routes.openMedia`.
- Key → plan or unplan with an Undo toast. The page installs one `.tastePlanHost(plans)`.
- A tracked title's key opens the tracking editor (existing `TastePlanAction`).

**VoiceOver:** the card reads as one element (title, year, format), then the key.

### 6.9 States (anime detail)

The existing states are unchanged: hero and story at once, the skeleton until ladder, units and credits settle, the offline band, ladder-failed.

New:
- **Next row:** absent until either the schedule or the catalogue seed gives a row. It is never an error.
- **Cast:** `fetchCast` answers `[]` on failure, so the rail hides. This is open (§17).
- **More like this:** hidden (§6.8).
- **Stills:** a failed image shows the branded tile.

### 6.10 Adaptive (anime detail)

- **320 / compact (column ≤ 328):**
  - Facts 9 pt.
  - Stills 72 × 40.
  - Peek gives 2 cards and a 52 pt slice.
  - Gutter stays 24 (as the code has it).
- **iPad:** `.kuroReadableWidth()` 680. Rails bleed to the column edge (§5.1, 5 cards).
- **Accessibility sizes:**
  - The facts line wraps.
  - The next row stacks.
  - Stills are hidden.
  - Rail titles get 4 lines.
  - Keys and chips stay 44 pt.

### 6.11 VoiceOver order (anime detail; by construction)

1. Back (pushed) / Close
2. Kind kicker + title (header)
3. Status mark (opens list settings; actions as today)
4. Facts line
5. Next-release row
6. Bell
7. Season tab
8. Story eyebrow, hook (header), "About this season"
9. Club presence
10. Seasons (header, then tiles)
11. Progress card
12. Up next row, then its +1 key
13. Timeline rows in order (each a single element: "Episode 5, Premature Death, Friday 17 October, watched"), then the watched-run fold button and "More episodes"
14. Source card
15. Songs
16. "The characters." (header), then each card, then its voice chip
17. Credits
18. "More like this." (header), then each card, then its key
19. Between us

Construction:
- Wrap the hero in `.accessibilityElement(children: .contain)`.
- The season tab gets `.accessibilitySortPriority(-1)` inside it, so it is read after the bell.
- Nodes, stills, tiles and rules are hidden.

---

## 7. Manga detail page (Detail lane)

### 7.1 Order

The prototype order is unchanged: hero → story → seasons/volumes → bookmark (D5) → chapters (D6) → "Seen the anime?" (D7) → characters → credits → **More like this.** → publisher → between us. The new section is inserted before the publisher row.

### 7.2 Hero (item 2)

The prototype's book-on-paper hero, serif title and author are kept (amendment 1).

**Added under the author: a facts line**, 10 pt #6C786A (`DetailInk.author`), parts joined by " · ":
- start year
- format word: Manga · Light novel / Light Novel · Novel / Roman · One-shot / One-Shot · Manhwa · Manhua
- status: "Ongoing" / "Laufend", "Finished" / "Abgeschlossen", "On hiatus" / "Pausiert"
- volumes "{n} volumes" / "{n} Bände" when known
- chapters "{n} chapters" / "{n} Kapitel", only when finished
- score (D4)

### 7.3 Next chapter glance

Below the hero and above the story, when an upcoming chapter or volume row exists. This is Home's glance card (G§8.1) with the manga calendar's date chip:
- **Date chip** 40 × 44: #ECEEE4, corners 4/10/4/4. Day 19 medium mono, month 9 pt #667267. When the row has no day (month or quarter precision), the chip is replaced by the paper branded tile with "Ch."
- **Title line:** `ReleaseCopy.line(item)` in 14 semibold −0.3 `HomeInk.glanceInk`, for example "Ch. 68 · expected around Wed 26 Nov".
- **Mark:** the certainty mark (§5.3, paper).
- **Caption** in 10 pt `glanceMuted`:
  - the source attribution
  - for an estimate, also "Estimates don't send reminders." / "Für Schätzungen gibt es keine Erinnerung."
- **Bell:** trailing, only when eligible (a confirmed or announced publisher instant, which is rare). Behaviour as in §6.2.
- **VoiceOver:** one element, then the bell.

### 7.4 Bookmark and chapters

`MangaBookmarkCard` and its dark leaf key are unchanged. Chapter rows keep their serif numbers (amendment 1). Watched runs fold as in §6.4.1, with "Chapters 1–{k} · read" / "Kapitel 1–{k} · gelesen".

### 7.5 Seen the anime? (item 5)

- `MangaAdaptationCard` shows the anime cover (the ladder `coverImage`).
- When there is no cover, it shows the paper branded tile with kind "Anime · TV" (from the ladder format) and the title.
- The 映 glyph is removed.

### 7.6 More like this

Same as §6.8, with `moreLikeThis(manga:)`, `TasteCard(manga:)` and the note "From what this title shares".

### 7.7 VoiceOver order (manga detail)

1. Back / Close
2. Kicker, title (header), author, facts
3. Status mark
4. Next-chapter glance, then its bell
5. Story
6. Bookmark, then its key
7. Chapters
8. Seen the anime?
9. Characters
10. Credits
11. More like this
12. Publisher
13. Between us

---

## 8. Songs (Songs + entities lane; items 7, 8)

### 8.1 The view and its call signature (fixed, so the integrator can swap it in)

```swift
// Kuro/Views/DetailPages/Songs/DetailSongShelf.swift (Songs + entities lane)
struct DetailSongShelf: View {
    init(songs: [ThemeSong],
         material: ArtworkMaterial,
         progress: Int,                 // the Library progress of this title (0 when untracked)
         showsAll: Binding<Bool>,       // fold memory (DetailFold.songs), as DetailSoundPanel today
         onCollapse: @escaping () -> Void)
}
```

**Shell.** The prototype D8 panel is unchanged:
- `material.base → deep`, radius and padding as `DetailSoundPanel`.
- Heading "The sound of it." (EXISTING) with "{n} songs" (EXISTING form), where n counts collapsed songs.

### 8.2 Organisation (D10; pure `SongShelfGrouping`, tested)

**1. Collapse versions.** Key: `(kind, sequence, normalisedTitle)`.
- One row per song.
- Version tags: "v{n} Ep. {range}" for each version when there is more than one, otherwise none.
- "v1" is never shown alone.

**2. Parts.**
- Sort the openings by `sequence`. Each opening with a first episode starts a part that runs to the next opening's first episode − 1. The last part runs to the highest episode seen, or stays open ("Ep. 13–").
- Endings and insert songs join the part that holds their first episode.
- Songs with no episode range go into a final "Other songs" / "Weitere Songs" part. That part is used only when there are other parts.
- One part only → no part headings.

**3. Part heading.**
- "Ep. {a}–{b}" / "F. {a}–{b}", 8 pt uppercase, tracking 1.4, #B0C3B5 (`DetailInk.soundKicker`), on the left.
- 1 pt white @ 0x18 rule above, 12 pt above and 6 pt below.
- Hidden from VoiceOver as text. It is read as the row container's label ("Episodes 1 to 5").

**4. Order inside a part:** openings, then endings, then insert songs, each by sequence.

### 8.3 Row anatomy

The row is min 60 tall, with a 1 pt white @ 0x12 rule under each row. Left to right:

| Part | Value |
|---|---|
| Art | 44 × 44, radius 4. Apple artwork (`song.apple?.artworkURL(side: 132)`) when matched **and not veiled**. Otherwise the on-material branded tile with "OP 1" / "ED 2" / "IN". Artwork is never fetched for a veiled song. |
| Kind | `song.spokenLabel(german:)` short form ("Opening 1" / "Vorspann 1"), 7 pt uppercase, tracking 1.4, #B0C3B5, with the episode range when one part only. |
| Tags | Version tags (8.2.1) and "TV size" / "TV-Version" when the source title carries a TV-size marker (`(?i)tv[ -]?(size\|ver)`, `TVサイズ`). Outline 7 pt, 1 pt white @ .35, radius 3. |
| Title | 13 pt semibold #F0F5F1, 2 lines. |
| Artist | 10 pt #B4C6BA, **on every row**. When missing: "Artist not listed" / "Künstler nicht angegeben", in italic muted. |
| Action | **Matched with a preview:** a ▶ key (36 pt light face, `KuroKeyFace(.light)` recipe, ink glyph) in a 44 pt target. **Matched without a preview:** "Apple Music ↗". **Unmatched:** the existing "Listen" chooser (Apple Music search / Spotify search, `KuroThemeSongRow` behaviour). |

**Playing (that row only):**
- ▶ becomes ❚❚.
- An extra line opens under the row: a 1 pt scrub (track white @ .2, trace white @ .9), elapsed "0:12" and "0:30" in 9 pt mono, "Open in Apple Music ↗" (`song.apple.musicURL`, through `validatedOutboundURL`) and "Spotify ↗" (search).
- Reduce Motion: no height animation, and the scrub jumps by 1 s.

**Spoiler (`isSpoiler`):**
- The art shows the on-material tile with "Spoiler".
- The title reads "Spoiler. Tap to show." (EXISTING).
- No ▶ until revealed. The artist stays visible.
- A tap reveals that song for this visit (as `KuroThemeSongRow` does today).
- **Auto-reveal:** a song whose first episode ≤ `progress` is shown unveiled, because the viewer has seen it.

**NSFW (`isNSFW`):** treated as a spoiler (veiled). It is never auto-revealed.

### 8.4 Footer

- Left: "Song list: AnimeThemes" / "Songliste: AnimeThemes" (9 pt #A9BEB0).
- Right, when at least one visible row has an Apple match: **"Preview courtesy of Apple Music"** / **"Vorschau mit freundlicher Genehmigung von Apple Music"**.

### 8.5 Fold

- Show the first 6 rows, counting parts in order.
- Then "Show all {n} songs" / "Alle {n} Songs zeigen" and "Show fewer" / "Weniger zeigen", which are EXISTING forms.
- F1–F3 rules, with `onCollapse` scrolling back.

### 8.6 Preview player (D11)

`SongPreviewPlayer` is an `@MainActor @Observable final class` in `Kuro/Views/DetailPages/Songs/SongPreviewPlayer.swift`. It is **page-scoped**: the shelf holds it as `@State private var player = SongPreviewPlayer()`. It is not built by `AppComposition`, and no environment injection is needed.

```swift
@MainActor @Observable final class SongPreviewPlayer {
    enum Phase: Equatable { case idle, loading(String), playing(String), paused(String), failed(String) } // song id
    private(set) var phase: Phase
    private(set) var elapsed: TimeInterval   // 0...30, updated every 0.25 s
    func toggle(_ song: ThemeSong)           // starts this song (stopping any other), or pauses/resumes it
    func stop()                              // idle; deactivates the audio session (notifyOthersOnDeactivation)
}
```

**Behaviour:**
- **Start.** `AVPlayer(url:)` only for a URL that passes `AppleTrackMatch.isAllowedPreviewHost` (https, host suffix `.apple.com` or `.mzstatic.com`). Audio session category `.playback`, mode `.default`.
- **When it stops.** At the end of the item it returns to idle. It stops on the shelf's `onDisappear`, on scene phase not active, on `AVAudioSession.interruptionNotification` (began), and on `routeChangeNotification` (`oldDeviceUnavailable`, which pauses).
- **Failure.** The status `.failed` or a timeout of 10 s gives `.failed(id)`. The row shows "Preview unavailable." / "Vorschau nicht verfügbar." and falls back to "Apple Music ↗".
- **Offline.** ▶ is disabled, with the caption "You're offline." / "Du bist offline." (EXISTING if present).
- **Nothing is stored.** No caching or downloading of audio, and no telemetry of what was played beyond the existing outbound-link telemetry for "Open in Apple Music".

### 8.7 VoiceOver (songs)

- "The sound of it." (header).
- Each part is a container labelled "Episodes 1 to 5" / "Folgen 1 bis 5".
- Each song row is one element: "{Opening 1}, {title}, by {artist}", plus ", TV size" and ", version 2" when tagged.
- Then the action button:
  - "Play preview of {title}" / "Vorschau von {title} abspielen"
  - "Pause preview" / "Vorschau anhalten"
  - "Open in Apple Music" / "In Apple Music öffnen"
  - "Listen"
- A veiled row reads "Spoiler, {Opening 1}. Double tap to show." / "Spoiler, {Vorspann 1}. Zum Anzeigen doppeltippen."
- The footer is read last.

### 8.8 States (songs)

- **No songs:** the section is hidden (existing policy, `songCount > 0`).
- **The Apple columns are absent live** (the migration is not applied): every row is unmatched and the footer shows the AnimeThemes credit only.
- **Preview failure:** handled inline, as in §8.6.

---

## 9. Entity pages (Songs + entities lane; items 4, 6)

**Common frame:**
- Journey page on `kuroPaper`.
- `EntityPageCollapse` keeps the shrinking header (H1–H4).
- Gutter 24 at every width (the detail body's value).
- The black `EntityFilterBar` pills and the serif-caps titles are retired from these pages (D21). The types stay unless a grep shows no other user.

### 9.1 Character page

| Block | Spec |
|---|---|
| Hero | Portrait 96 × 144 (2 : 3), radius 5, or the ink branded tile with initials. Beside it: eyebrow "CHARACTER · {TITLE}" / "FIGUR · {TITEL}" (9 pt, tracking 1.05, #666C68). Name 27 semibold −1.1 ink (the prototype detail title). Native name 13 pt `kuroMuted`. A facts line in 10 pt muted: role word, "{n} appearances in Kuro" / "{n} Auftritte in Kuro", age / gender / birthday only when present. |
| Description | 13/21 #58635B, 4 lines, with a "Read more" / "Mehr lesen" fold (F1–F3). |
| Voiced by | One Home glance card per Japanese voice actor (at most 3) from `fetchVoiceActors(forCharacter:)`. Eyebrow "JAPANESE VOICE" / "JAPANISCHE STIMME". 34 pt disc (image or ink initials). Name 14 semibold −0.3 `glanceInk`. Line "Voice actor · {n} roles in Kuro" / "Sprecher·in · {n} Rollen in Kuro" (n from `fetchVoiceRoles`; the count part is omitted while loading). "›". Tap → `.staff(staff)`. Hidden when there are none. |
| Appears in. | `DetailSectionHeading("Appears in." / "Kommt vor in.", note: "{n} titles")`. Refine words on the left "All · Anime · Manga" (only when both media exist), and on the right the sort words from `EntitySortMode` ("Popular · Newest"). Then a peek rail of works: cover 2 : 3 radius 4, title 12 medium, line "Anime · 2020", and the status word in 9 pt muted when tracked ("Watching"). Tap → `openMedia`. |
| In your list | When any work is tracked: a glance line "In your list: {title} · Ep. 6 / 23 ›" / "In deiner Liste: …", which pushes that title. |

### 9.2 Staff page (voice actor, director, …)

| Block | Spec |
|---|---|
| Hero | As the character page. Eyebrow: "VOICE · JAPANESE" / "STIMME · JAPANISCH" when voice roles exist, otherwise the primary occupation words. Facts: "{n} roles in Kuro · {k} in your list" / "{n} Rollen in Kuro · {k} in deiner Liste", and "Active since {year}" only when present. |
| Roles. | When `fetchVoiceRoles(forStaff:)` is non-empty: `DetailSectionHeading("Roles." / "Rollen.", note: "Popular" sort word)`. Quiet rows (G§7), each with **two targets**: a leading 40 × 60 title cover button (→ the anime), and the text block button (→ the character) showing the character name in 15 pt medium, "{title} · {Main} · {year}" in 10 pt muted, and the status word trailing when tracked. Show 8, then "All {n} roles" / "Alle {n} Rollen" (fold). |
| Characters you know. | Roles whose anime is in the Library: a peek rail of character portraits with the title under them. Tap → the character. |
| Works. | Existing staff works (anime and manga). Refine words "All · Anime · Manga" plus the existing role options (`StaffRoleFilter`) as words in a horizontally scrolling refine row; the sort words on the right. Quiet rows: year numeral (13 pt mono muted), cover, title, "TV · {role}". |

### 9.3 Studio page

| Block | Spec |
|---|---|
| Hero | Home's **cover line**: the studio name 44 semibold −0.8 (34 compact, wraps), then the 46 × 2 ink rule, then the fact line "Animation studio · {n} titles in Kuro" / "Animationsstudio · {n} Titel in Kuro". **No logo is invented.** |
| In your list | Glance card with the tracked works (thumbs strip, as the coming-up glance) and "›" to the first one. |
| Most loved. | A peek rail by popularity (the existing sort). |
| By year. | Index rows: year 13 pt mono muted, then the titles of that year joined by " · " (each title a separate button when it is one of at most 3; otherwise the row pushes the year-filtered works list). |

### 9.4 Author page

This is the staff page layout: photo or ink initials, "AUTHOR" / "AUTOR·IN", and "Works." with the medium words.

### 9.5 VoiceOver and states (entity pages)

**VoiceOver:** hero (name as header, then facts) → description → voice glance cards → section headers → rows and cards in order, with keys and extra targets after their card.

**States:**
- **Works loading:** `KuroSkeleton(kind: .row)` ×3.
- **Works failure:** `KuroStateView(.failed(hasCachedContent:), layout: .inline)` with retry.
- **Voice and role readers answer `[]` while the contract is absent:** those blocks are hidden.

---

## 10. Home Screen widget (Widget lane; item 9; D13, D22)

### 10.1 Model (platform lane, read-only for the widget lane)

| Part | What it does |
|---|---|
| `WidgetSnapshot` (the app writes it, the extension reads it) | Carries `releases: [WidgetReleaseItem]` (≤ 8, pre-worded by `ReleaseCopy`), `nowWatching: [WidgetNowWatchingItem]` (≤ 6) and `german`. |
| `AdvanceProgressIntent(item:)` | Queues one `WidgetAdvanceRequest`. |
| `KuroSnapshotProvider` | Overlays the queued taps (`applyingPending` sets `isQueued`). |
| The app | Drains the queue on foreground, on the Darwin ping and after sign-in. |

**Timeline policy (platform's):**
- Entries: now, plus each release expiry within 24 h (at most 12 entries).
- Policy: `.after(6 h)`.
- The app reloads the timeline on every content change.
- Countdowns use system relative text, so there are no per-minute entries.

### 10.2 Families and anatomy

The canvas is #FFFEF8 (`WidgetPalette.canvas`). Content margins are the system's. Type is SF at the literal sizes below, with `dynamicTypeSize(...DynamicTypeSize.xxLarge)`.

**Up next** (`NextReleaseWidget`):

| Family | Content |
|---|---|
| Small (158 × 158) | Eyebrow "NEXT EPISODE" / "NÄCHSTE FOLGE" or "NEXT CHAPTER" / "NÄCHSTES KAPITEL" (9 pt, tracking 1.05, #666C68). Cover thumb 27 × 38, radius 2, top-trailing. Title 14 semibold −0.3 #303932, 2 lines. Bottom: `unitLabel` split as a 10 pt unit and a 28 pt medium mono number. Then, when `countdownTarget` is set, `Text(countdownTarget, style: .relative)` in 12 semibold, with `datePhrase` in 10 pt muted under it. Otherwise `datePhrase` and the dashed "Estimate" mark when `isEstimate`. |
| Medium (338 × 158) | Eyebrow, then up to 3 rows. Each row: 23 × 34 cover, title 12 medium 1 line, `line` 10 pt muted, and the trailing relative time when `countdownTarget` is set (the Estimate mark otherwise). 1 pt #E3E7E1 rules. |
| Large (338 × 354) | As medium, with up to 6 rows. |

**Now watching** (`NowWatchingWidget`):

| Family | Content |
|---|---|
| Small | Eyebrow "NOW WATCHING" / Home's existing German kicker. One title: cover 32 × 48, title 13 semibold 2 lines, readout `unitPrefix` 10 pt plus count 21 mono plus "/ total" 11 pt, and the key. |
| Medium | Eyebrow, then 2 rows. Each row: cover 32 × 48 radius 3, title 12 medium 1 line, the next-release line for that title when the snapshot has one ("Next · Ep. 8 · Fri 21:30", 9 pt muted), readout 14 mono, and the key. |
| Large | Up to 4 rows. |

**The key** (in a 44 pt target):
- **Face.** The raised `.ink` face (34 pt, radius 7, `kuroKeyDarkTop → Bottom`, white "+1" 12 semibold). It is not material, because the snapshot carries no material.
- **Caught up** (`isCaughtUp`). The ghost ✓, 12 pt light #767B77.
- **Queued** (`isQueued`).
  - The count shows the new value.
  - The face is at 60 % opacity.
  - A caption "Saved when Kuro opens" / "Wird gespeichert, wenn Kuro öffnet" (8 pt muted) sits under the readout.
  - There is no stamp and no confirm animation.

**Accessibility:**
- Each row is one combined element ("{title}, episode 6 of 23").
- The key is separate: "Mark episode 7 watched" / "Folge 7 als gesehen markieren", or "Mark chapter {n} read" / "Kapitel {n} als gelesen markieren".
- A caught-up row reads "Caught up" / "Auf dem neuesten Stand".

### 10.3 States and taps

**States:**

| When | What shows |
|---|---|
| `snapshot == nil` (signed out, first install, or an unsigned build) | Centred "Open Kuro to see what's next." / "Öffne Kuro, um zu sehen, was als Nächstes kommt." |
| No releases | "No dates yet." / "Noch keine Termine." |
| Nothing in progress | "Nothing in progress." / "Gerade nichts angefangen." |

**Taps:**
- Rows and the widget body use `Link(destination: deepLink)` → `kuro://anime/<id>` / `kuro://manga/<id>` (N10).
- The key is always `Button(intent:)`. **Never a URL.**

### 10.4 Code location (D22)

- **`KuroWidgetViews/`** is a synchronized group in both targets. It holds:
  - `WidgetPalette.swift` and `WidgetCopy.swift`: EN/DE by `snapshot.german` and `KuroLocale`-free, because the extension cannot import the app. This is the sanctioned exception, since the snapshot pre-renders the certainty strings.
  - `NextReleaseWidgetContent.swift` and `NowWatchingWidgetContent.swift`: generic over `Key: View`, with inputs `snapshot: WidgetSnapshot?`, `date: Date`, `family: WidgetFamily` and `key: (WidgetNowWatchingItem) -> Key`.
- **`KuroWidgets/KuroWidgetViews.swift`** becomes a thin wrapper that passes `Button(intent: AdvanceProgressIntent(item:))`.

---

## 11. Notifications (Platform lane builds the owner; Detail and Profile lanes call it; item 10; D14)

### 11.1 Owner

`ReleaseReminders` (§16.3):
- `@MainActor @Observable final class`, conforming to `AccountScopedState`
- built by `AppComposition`, injected with `.environment`
- it replaces the scheduling half of `ReminderScheduler`

### 11.2 Eligibility and scheduling

**Which rows are eligible:** `isEligible(item)` is true when all of these hold:
- `item.showsTime`
- `item.basis` is `.confirmed` or `.announced`
- `item.releaseAt > now + 60 s`
- `item.isPast == false`

**Which titles are on:** a title's effective state is `override[key] ?? (mode == .followed && status ∈ {.current, .repeating})`.

**What gets scheduled:**
- For every title that is on: its next two eligible rows. **As built:** the account schedule (`user_release_schedule_v1`, and its `user_airing_next` fallback) returns one row per title, so the planner (`perTitle = 2`) schedules only the **next** release per title; the following one is planned when the app runs again. Two rows per title need an RPC that returns two units per title (open, §17).
- Soonest first, capped at 48 pending requests in total.
- Each one triggers at `releaseAt` (`UNCalendarNotificationTrigger`, device time zone).

**Request format:**
- id: `release-<medium>-<mediaId>-<unitNumber or "x">-<epoch>`
- `threadIdentifier`: `kuro.title.<medium>.<mediaId>`
- `userInfo["url"]`: `kuro://anime/<id>` or `kuro://manga/<id>`
- An optional cover attachment from the image cache. It is skipped when the cover is not cached, and nothing is fetched for it.

**When it reschedules:**
- the schedule loads (`ReleasesStore`)
- a Library change (the existing sink, which now calls `reschedule()`)
- the app comes to the foreground
- `setFollowing` or `toggle` runs

**Never prompts:** `reschedule()` never prompts.

**Legacy cleanup:** on the first run, remove the pending `airing-*` requests. The legacy start + 1 h path is no longer called.

**Taps:** a tap on a delivered notification → `DeepLink.from(url:)` → the N10 collapse-then-open (platform lane; `UNUserNotificationCenterDelegate`).

**Account switch** (`AccountScopedState`):
- `clearPrivateState()` removes every pending and delivered `release-` request and clears the in-memory state.
- Preferences are stored per account under `com.kuro.releaseReminders.<WidgetAccountHash-style opaque key>`, never the raw user id.

### 11.3 Copy (`ReleaseReminderCopy`, platform lane, EN/DE)

| Case | Title | Body EN | Body DE |
|---|---|---|---|
| Episode | `item.title` | Episode {n} just aired. | Folge {n} wurde gerade ausgestrahlt. |
| Chapter | `item.title` | Chapter {n} is out. | Kapitel {n} ist erschienen. |
| Volume | `item.title` | Volume {n} is out. | Band {n} ist erschienen. |
| No number | `item.title` | A new episode just aired. / A new chapter is out. | Eine neue Folge wurde gerade ausgestrahlt. / Ein neues Kapitel ist erschienen. |

There is no marketing line, no progress claim, and the notification is not tied to a streaming service.

### 11.4 Permission and results (UI copy owned by the calling lanes)

```swift
enum ReleaseReminderChange: Equatable, Sendable { case on, off, denied, failed }
```

| Result | Bell toast (Detail lane, `DetailToastOverlay`) | Profile row (Profile lane) |
|---|---|---|
| `.on` | "Reminder on. Kuro tells you when it's out." / "Erinnerung an. Kuro sagt dir Bescheid, wenn es so weit ist." | toggle on |
| `.off` | "Reminder off." / "Erinnerung aus." | toggle off |
| `.denied` | "Notifications are off for Kuro. Turn them on in Settings." / "Mitteilungen für Kuro sind aus. Du kannst sie in den Einstellungen einschalten." + "Settings" / "Einstellungen" (`UIApplication.openSettingsURLString`) | toggle stays off; the same line under the row with "Open Settings" / "Einstellungen öffnen" |
| `.failed` | "Couldn't set the reminder." / "Erinnerung konnte nicht gesetzt werden." | the same line |

---

## 12. Profile stats (Profile + import + finishes lane; item 11; D15)

### 12.1 Placement

A new section **"Your numbers."** / **"Deine Zahlen."** sits after Identity and before Library in `ProfileView`:
- Page heading (24/−0.85).
- Summary "Counted on this device" / "Auf diesem Gerät gezählt".

### 12.2 Formulas (pure `ProfileStats`, tested; `entries` = the current account's `LibraryStore` entries)

**Episodes**
- Value: Σ `min(progress, episodeCount ?? progress)` over anime entries with progress > 0.
- Caption: "across {n} anime" / "aus {n} Anime".

**Chapters**
- Value: Σ `min(progress, chapters ?? progress)` over manga entries with progress > 0.
- Caption: "across {n} manga" / "aus {n} Manga".

**Time**
- `minutes` = Σ over anime entries with progress > 0 and duration > 0 of `min(progress, total) × duration`.
- `missing` = the anime entries with progress > 0 and no duration.
- Display:
  - < 48 h → "≈ {h} h" / "≈ {h} Std."
  - else "{d} d {h} h" / "{d} T {h} Std."
- Caveat (10 pt muted, always shown): "Episodes watched × each title's episode length." When `missing > 0`, add " {missing} titles have no length and aren't counted." / " {missing} Titel haben keine Länge und zählen nicht mit."

**Top genres**
- Count titles with status ∈ {current, completed, repeating, paused} per catalogue genre.
- Top 5, ties broken by locale compare.
- Each row: genre, a `HomeScrub` bar with fraction count / top count (monochrome), and the count.
- Summary: "by titles on your lists" / "nach Titeln auf deinen Listen".

**Your year**
- `year` is the current year in the device calendar (`KuroLocale.calendar`).
- `inYear` = entries with `createdAt` or `updatedAt` in `year`.
- The card is hidden when `inYear` is empty.
- Lines:
  - "{n} titles saved or changed" / "{n} Titel gespeichert oder geändert"
  - "{k} of them now completed" / "{k} davon abgeschlossen" (k = completed among `inYear`, omitted when 0)
  - "Most time: {title}" / "Meiste Zeit: {title}" (the anime in `inYear` with the most `min(progress, total) × duration`; omitted when unknown)

### 12.3 Anatomy

**Totals:** two glance cards side by side (episodes, chapters).
- Eyebrow 9/1.05.
- Count 24 medium mono (`.kuroCountRoll` on change).
- Caption 10 pt.

**Time:** the cover-line total (34 semibold −1.1) with the caveat beside it, stacked at AX sizes.

**Genres:** rows 36 pt.

**Your year:** a small scene card (G§8.3) in the "most time" title's material (`ArtworkMaterialStore`, banner then cover), or `ArtworkMaterial.neutral` when there is none.
- 3.25 : 1 artwork window (that title's banner) with a season-style tab "YEAR" / "JAHR" and the year in 17 semibold mono.
- Material foot: title 17 semibold −0.35 white "{n} titles this year" / "{n} Titel dieses Jahr".
- Fact row: the other lines.
- An honest note under the card (10 pt muted): "Kuro doesn't record finish dates, so {year} counts titles you saved or changed this year." / "Kuro speichert kein Enddatum. {year} zählt Titel, die du dieses Jahr gespeichert oder geändert hast."
- Taps: the card is not a button. The "Most time" line pushes that title.

**Reminders row:** "Release reminders" / "Erinnerungen an Neuerscheinungen", a `Toggle` styled as the existing Profile rows.
- Subtitle: "New episodes and chapters of what you're watching or reading. Confirmed times only, never estimates." / "Neue Folgen und Kapitel von dem, was du schaust oder liest. Nur bestätigte Zeiten, nie Schätzungen."
- It sits in Preferences, after "Refresh your lists".
- The toggle calls `setFollowing(_:)` (§11.4).

### 12.4 Data and states

**Where the catalogue facts come from:** `CatalogStore.fetchAnimeByIdsPreservingOrder` and `fetchMangaByIdsPreservingOrder`.
- They run in chunks of 50 ids, only when the section appears.
- Results are held in view `@State` keyed by the account id. They are dropped when the account changes, and only missing ids are refetched when the Library changes.
- Library-only values (counts, the year) recompute from `LibraryStore` at once.

| State | What shows |
|---|---|
| Loading | `KuroSkeleton(kind: .row)` ×2 in the card shapes |
| Catalogue failure | Episodes and chapters use raw progress. Time and genres show `KuroStateView(.failed(hasCachedContent: false), layout: .inline)` with retry. Never zeros. |
| Empty Library | `HomeQuietCard("Your numbers appear once you save a title." / "Deine Zahlen erscheinen, sobald du einen Titel speicherst.")` |

**VoiceOver:**
- Header.
- Each total is one element ("1,284 episodes across 61 anime").
- The time element includes the caveat.
- Each genre row is one element ("Action, 31 titles").
- The year card is one element, then the "Most time" button.
- Then the reminders toggle.

---

## 13. Import screens (Profile + import + finishes lane; item 12; D16)

**Scope:**
- AniList import (`ConciergeView+AniListImport.swift`, view code only)
- MAL XML and source chooser (`ImportSourceChooser.swift`)
- Review / match (`ImportWorkflowSheet.swift`, `ImportCatalogMatchPicker.swift`)
- History (`ImportHistorySection.swift`)

**Behaviour, bindings, busy states, Stop, the N7 discard guard and every string stay byte-identical.** `ImportWorkflowIntegrationTests` and `ProfileLaneTests` stay green.

| Old | New (Home grammar) |
|---|---|
| Serif page title | Eyebrow "IMPORT · ANILIST" (`HomeOpeningLineView` kicker style). The EXISTING title string at 24 semibold −0.85 sans. The description 13 pt #646B65. |
| "Form / Preview" black pills | Refine words with the same binding and the EXISTING words |
| Boxed field | A glance-style field: #FFFEFA, radius 8, 1 pt #293129 @ 0x18, min 44, 14 pt, label as the eyebrow |
| Black capsule toggles (type, statuses) | Check rows: 44 pt, a tick box 18 pt radius 4 (on: #303932 fill with a white ✓ 10 pt; off: 1 pt #BFC4BD), the label 13 pt ink, two columns, 1 pt #E3E7E1 rules. They sit in a calendar-card shell (#FAFCF9, radius 18, 1 pt #D8DDD9), and "both can be on" is kept. |
| Grey pill primary | `KuroInkButton(title: <EXISTING literal>, role: .primary, isLoading:)`. The upper-case literal is kept. If `KuroInkButton`'s disabled state measures below 4.5 : 1, the lane reports it and does not edit the shared file. |
| MAL XML file picker | The same shell. A glance-card file row: document glyph, file name, and the EXISTING choose action. |
| Review / match rows | Home quiet rows: 40 × 60 cover, title 15 pt, the `ImportCopy` state words in 10 pt muted. The Add / Update / Skip decision is refine words on the row. The batch footer uses `KuroInkButton`. |
| Match picker | Quiet rows with the candidate's year and format, and a ✓ for the selected one |
| Chooser | The existing ink-rule link rows are kept. Their kickers move to 9/1.05. |

**VoiceOver:**
- The title is the header.
- Each refine word is a button with `.isSelected`.
- Each check row is a toggle ("Completed, on").
- Review rows: one element, then the decision words as an adjustable control. Each word is a button with `.isSelected`.

---

## 14. Small finishes (item 13)

### 14.1 Edge peek everywhere (D18)

| Surface | Owner |
|---|---|
| Discover Trending, the new "Manga new to you" rail (All), and any other card `ScrollView(.horizontal` in the Discover files | Profile + import + finishes lane |
| Detail cast and More like this (anime and manga) | Detail lane |
| Entity: Appears in, Characters you know, Most loved | Songs + entities lane |

### 14.2 Discover All (D17)

**On the All issue only:**
- **"Manga new to you"** is drawn as one rail. It uses the existing Trending rail's card anatomy with §5.1 widths, at most 10 items, and "See all {n} ›" (EXISTING) when there are more.
- **"Essential manga"** becomes the first section inside the fold.
- **The contents line** ("In this issue") keeps naming sections in page order. Essential manga falls under "+{n} more". Tapping it opens the fold and scrolls there (DC§6.3).

**Unchanged:** the Anime and Manga issues, the section order and the flag gating (`DiscoverLaneTests`).

**Render:** `discover-all-full-390.jpg` is cropped to the content height. Report the measured height against the corrected baseline of about 2,700 pt (D17; the 1,641 pt figure came from a squashed render). Target 1,500 pt or less; acceptance 2,000 pt or less. Measured after this pass: 2,102 pt (acceptance missed by about 100 pt, open).

### 14.3 VoiceOver order (correct by construction; device check OPEN)

The rules every lane applies:
1. **The tree follows reading order:** top to bottom, then leading to trailing. Overlays that are visually first but secondary (the season tab on art, the bell) are ordered with `.accessibilitySortPriority` inside an `.accessibilityElement(children: .contain)` container.
2. **One element per card or row:** `.accessibilityElement(children: .combine)` on the open target. The extra targets (key, voice chip, cover button, ▶) are sibling elements **after** it. No nested buttons.
3. **Headings** have `.isHeader`. Decorative marks (nodes, tiles, numerals, rules, part-heading text) are `.accessibilityHidden(true)`.
4. **Labels use full words** (`ReleaseCopy.accessibilityLine`, `ThemeSong.spokenLabel`), never "Ep." or "F."
5. **Every target is 44 pt or more.** Rows activate programmatically.

Each lane adds unit tests for its accessibility-label helpers. The device pass stays **open** in the report.

---

## 15. Copy (EN / DE)

Every string goes through `KuroLocale.text(en, de)` or the owning lane's copy enum:
- `DetailPageCopy` (Detail)
- `SongShelfCopy` and `EntityPageCopy` (Songs + entities)
- `WidgetCopy` (Widget; snapshot-driven)
- `ProfileStatsCopy` (Profile + import + finishes)
- `ReleaseReminderCopy` (Platform)

**EXISTING** means: reuse the shipped string exactly. Grep it, don't retype it.

| Where | English | Deutsch | |
|---|---|---|---|
| Facts parts | {n} episodes · {n} chapters · {n} volumes · Ongoing · Finished · On hiatus · Score {x} | {n} Folgen · {n} Kapitel · {n} Bände · Laufend · Abgeschlossen · Pausiert · Wertung {x} | NEW |
| Format words | TV · Film · OVA · ONA · Special · TV short · Music · Manga · Light novel · Novel · One-shot | TV · Film · OVA · ONA · Special · TV-Kurzserie · Musik · Manga · Light Novel · Roman · One-Shot | NEW |
| Next kicker | NEXT EPISODE · NEXT CHAPTER · NEXT VOLUME | NÄCHSTE FOLGE · NÄCHSTES KAPITEL · NÄCHSTER BAND | NEW |
| Release line | `ReleaseCopy.line` / `datesToCome` / `sourceAttribution` | same | EXISTING |
| Marks | Confirmed · Announced · Estimate | Bestätigt · Angekündigt · Schätzung | NEW |
| Day count | today · tomorrow · in {n} days | heute · morgen · in {n} Tagen | NEW |
| Bell a11y | Remind me when episode {n} airs / Remind me when chapter {n} is out / Reminder on for episode {n} | Erinnere mich, wenn Folge {n} läuft / Erinnere mich, wenn Kapitel {n} erscheint / Erinnerung für Folge {n} an | NEW |
| Bell toasts | see §11.4 | see §11.4 | NEW |
| Estimate note | Estimates don't send reminders. | Für Schätzungen gibt es keine Erinnerung. | NEW |
| Season tab | SEASON {n} of {m} / a11y "Season {n} of {m}. Shows all seasons." | STAFFEL {n} von {m} / „Staffel {n} von {m}. Zeigt alle Staffeln.“ | NEW |
| Timeline | {w} of {t} watched · Ep. {n} · watched · Episodes 1–{k} · watched · Show · Hide · No. {n} | {w} von {t} gesehen · F. {n} · gesehen · Folgen 1–{k} · gesehen · Zeigen · Ausblenden · Nr. {n} | NEW |
| Manga runs | Chapters 1–{k} · read | Kapitel 1–{k} · gelesen | NEW |
| Up next / More episodes | UP NEXT / More episodes | (as shipped) | EXISTING |
| Cast | The characters. / Japanese cast / {n} characters / Main · Supporting · Background / "{name}, voice of {character}" | Die Figuren. (as shipped) / Japanische Besetzung / {n} Figuren / Hauptrolle · Nebenrolle · Nebenfigur / „{name}, Stimme von {character}“ | heading EXISTING, rest NEW |
| More like this | More like this. / From what this title shares | Mehr davon. / Nach Gemeinsamkeiten mit diesem Titel | NEW |
| Plan key and toast | `TastePageCopy.planLabel`, `TastePlanCopy` | same | EXISTING |
| Songs | The sound of it. / {n} songs / Opening {n} · Ending {n} · Insert song / Spoiler. Tap to show. / Listen / Show all {n} songs / Show fewer | (as shipped) | EXISTING |
| Songs, new | Ep. {a}–{b} · Other songs · TV size · v{n} · Artist not listed · Play preview of {title} · Pause preview · Open in Apple Music · Preview courtesy of Apple Music · Song list: AnimeThemes · Preview unavailable. · "Episodes {a} to {b}" | F. {a}–{b} · Weitere Songs · TV-Version · v{n} · Künstler nicht angegeben · Vorschau von {title} abspielen · Vorschau anhalten · In Apple Music öffnen · Vorschau mit freundlicher Genehmigung von Apple Music · Songliste: AnimeThemes · Vorschau nicht verfügbar. · „Folgen {a} bis {b}“ | NEW |
| Entities | CHARACTER · {TITLE} / {n} appearances in Kuro / JAPANESE VOICE / Voice actor · {n} roles in Kuro / Appears in. / In your list: … / VOICE · JAPANESE / {n} roles in Kuro · {k} in your list / Roles. / All {n} roles / Characters you know. / Works. / Animation studio · {n} titles in Kuro / Most loved. / By year. / AUTHOR / Read more | FIGUR · {TITEL} / {n} Auftritte in Kuro / JAPANISCHE STIMME / Sprecher·in · {n} Rollen in Kuro / Kommt vor in. / In deiner Liste: … / STIMME · JAPANISCH / {n} Rollen in Kuro · {k} in deiner Liste / Rollen. / Alle {n} Rollen / Figuren, die du kennst. / Werke. / Animationsstudio · {n} Titel in Kuro / Am beliebtesten. / Nach Jahr. / AUTOR·IN / Mehr lesen | NEW (filter and sort words EXISTING) |
| Widgets | NEXT EPISODE · NEXT CHAPTER · Saved when Kuro opens · Open Kuro to see what's next. · No dates yet. · Nothing in progress. · Estimate · Caught up · Mark episode {n} watched · Mark chapter {n} read | NÄCHSTE FOLGE · NÄCHSTES KAPITEL · Wird gespeichert, wenn Kuro öffnet · Öffne Kuro, um zu sehen, was als Nächstes kommt. · Noch keine Termine. · Gerade nichts angefangen. · Schätzung · Auf dem neuesten Stand · Folge {n} als gesehen markieren · Kapitel {n} als gelesen markieren | NEW ("NOW WATCHING" kicker EXISTING from Home) |
| Notifications | §11.3 | §11.3 | NEW |
| Profile | Your numbers. / Counted on this device / Episodes · Chapters / across {n} anime / across {n} manga / time strings and caveat §12.2 / Top genres / by titles on your lists / YEAR / {n} titles this year / {n} titles saved or changed / {k} of them now completed / Most time: {title} / honest note §12.3 / Your numbers appear once you save a title. / Release reminders + subtitle §12.3 / Open Settings | Deine Zahlen. / Auf diesem Gerät gezählt / Folgen · Kapitel / aus {n} Anime / aus {n} Manga / §12.2 / Top-Genres / nach Titeln auf deinen Listen / JAHR / {n} Titel dieses Jahr / {n} Titel gespeichert oder geändert / {k} davon abgeschlossen / Meiste Zeit: {title} / §12.3 / Deine Zahlen erscheinen, sobald du einen Titel speicherst. / Erinnerungen an Neuerscheinungen + §12.3 / Einstellungen öffnen | NEW |
| Import | every visible string | (as shipped) | EXISTING, byte-identical; the kicker "IMPORT · ANILIST" / "IMPORT · ANILIST" is NEW |
| Data sources (About) | "Apple Music: song artwork and 30-second previews from Apple's iTunes catalogue. The artwork loads from Apple when the songs are shown, and a preview streams from Apple only when you tap ▶; both times Apple sees your IP address." / "Widgets and release reminders stay on this device." | „Apple Music: Song-Cover und 30-Sekunden-Vorschauen aus Apples iTunes-Katalog. Die Cover lädt dein Gerät von Apple, sobald die Songs angezeigt werden, und eine Vorschau wird erst gestreamt, wenn du auf ▶ tippst; beide Male sieht Apple deine IP-Adresse.“ / „Widgets und Erinnerungen an Neuerscheinungen bleiben auf diesem Gerät.“ | NEW |

**Dates and numbers:**
- Dates are always worded by `ReleaseCopy`: German readers get `de_DE` and Europe/Berlin; English readers get the **device** locale and time zone (`KuroLocale`), so an English device in Germany (`en_US@rg=de`, as the render simulator is) reads "Score 8,6" and "Fri, Nov 6, 15:25". en_GB is an example, not a pinned locale. Text stored for later (the widget snapshot) never uses "today"/"tomorrow" (`ReleaseCopy.withoutRelativeDays()`).
- Numbers use `KuroLocale`'s locale: "1,284" / "1.284", "8.6" / "8,6".

---

## 16. Interfaces the UI lanes consume

The merged foundation code wins on exact spelling (precedence note). The UI lanes call these and nothing else new.

### 16.1 From the Data lane

**Exists on `kuro/details-songs-platform-data`, in the working tree:**

```swift
// Kuro/Catalog/CatalogVoiceModels.swift
struct CastMember: Identifiable { let character: Character; let role: String; let voiceActor: Staff?; let language: String?; var id: Int }
struct VoiceActorCredit: Identifiable { let staff: Staff; let language: String; let animeIds: [Int]; var id: Int }
struct VoiceRole: Identifiable { let character: Character; let role: String; let language: String; let anime: VoiceRoleAnime; var id: String }
struct VoiceRoleAnime { let id: Int; let titleEnglish, titleRomaji, titleNative, coverImageLarge, format: String?; let year: Int?
                        var key: MediaKey; var displayTitle: String }

// Kuro/Catalog/CatalogStore+Voices.swift: public data, silent fallback while the RPCs are absent
extension CatalogStore {
    func fetchCast(forAnime animeId: Int, language: String = CatalogVoiceContract.defaultLanguage, limit: Int = 25) async -> [CastMember]
    func fetchVoiceActors(forCharacter characterId: Int, language: String = CatalogVoiceContract.defaultLanguage) async -> [VoiceActorCredit]
    func fetchVoiceRoles(forStaff staffId: Int, limit: Int = 50) async -> [VoiceRole]
}
```

**To add (Data lane):**

```swift
// Kuro/Releases/ReleaseModels.swift
nonisolated struct AppleTrackMatch: Hashable, Sendable {
    let trackId: Int
    let artworkURL: URL?     // https, host suffix ".mzstatic.com"
    let previewURL: URL?     // https, host suffix ".apple.com" or ".mzstatic.com"
    let musicURL: URL        // https, host "music.apple.com" or "itunes.apple.com"
    let confidence: Double   // 0.8...1.0
    /// nil unless the track id is positive, the music URL is valid, confidence ≥ 0.8, and every given URL passes its host rule.
    static func validated(trackId: Int?, artwork: String?, preview: String?, music: String?, confidence: Double?) -> AppleTrackMatch?
    static func isAllowedPreviewHost(_ url: URL) -> Bool
    /// Apple's artwork sizing: replaces the trailing "{w}x{h}bb" segment with "{side}x{side}bb".
    func artworkURL(side: Int) -> URL?
}
// ThemeSong gains `let apple: AppleTrackMatch?` (init parameter `apple: AppleTrackMatch? = nil`, so every
// existing call site compiles). `ReleasesStore.themes(animeId:)` decodes media_themes_v1's five trailing columns.

// Kuro/Discovery/RecommendationsReader.swift
enum SimilarTitlesRead<Item> { case loaded([Item]); case unavailable }
extension RecommendationsReader {
    /// media_similar_v1 first (one round trip), then the live recommend_ids_similar_to_seeds + hydrate path.
    /// NO genre fallback. The answer depends on the caller's account (own list excluded server side):
    /// the reader keeps no cache across accounts (no cache at all is fine; callers key their @State by account).
    func moreLikeThis(anime seed: Anime, limit: Int = 12) async -> SimilarTitlesRead<Anime>
    func moreLikeThis(manga seed: Manga, limit: Int = 12) async -> SimilarTitlesRead<Manga>
}
```

**Server side (prepared):**
- `20261103100000_character_voice_actors_v1`, `20261103100100_media_similar_v1`, `20261103100200_theme_links_apple_v1` (with local DB tests 84–86).
- The `bulk-import-anime` opt-in `includeVoiceActors`.
- `series_enrichment_worker.py --apple` (strict match, D12).

### 16.2 Apple URL rule (Data lane implements; Songs lane relies on it)

- Decode only through `AppleTrackMatch.validated`.
- The player re-checks `isAllowedPreviewHost`.
- "Open in Apple Music" goes through `ProviderAvailabilityStore.validatedOutboundURL`.

### 16.3 From the Platform lane

**Exists on `kuro/details-songs-platform-platform`:**

```swift
// Packages/KuroModules/Sources/KuroWidgetSupport
public struct WidgetSnapshot { schema, account, generatedAt, german, releases, nowWatching
                               func releases(at:) ; func applyingPending(_:) }
public struct WidgetReleaseItem { id, medium, mediaId, title, unitLabel, datePhrase, line, accessibilityLine, basis,
                                  precision, countdownTarget, expiresAt, isEstimate, thumbnail, deepLink }
public struct WidgetNowWatchingItem { medium, mediaId, title, progress, total, unitPrefix, lifecycleId, revision,
                                      artworkURL, thumbnail, deepLink, isQueued; var isCaughtUp; var progressText }
public enum KuroAppGroup.WidgetKind { nextRelease, nowWatching }
public struct WidgetSnapshotStore   // read(); thumbnail files under thumbs/
// KuroWidgets (extension): KuroWidgetEntry { date, snapshot, releases, nowWatching, german }, KuroSnapshotProvider,
// AdvanceProgressIntent(item:), NextReleaseWidget / NowWatchingWidget (families small/medium/large)
// Kuro/Widgets (app): WidgetSnapshotWriter (AccountScopedState), WidgetIntentInbox (drain), LibraryActions.advanceQueuedProgress
```

The thumbnail images: `WidgetSnapshotStore` exposes the `thumbs/` file URL for `thumbnail`. The widget lane reads it as `UIImage(contentsOfFile:)` and never loads anything over the network.

**To add (Platform lane):**

```swift
// Kuro/Releases/ReleaseReminders.swift
enum ReleaseReminderMode: String, Codable, Sendable { case off, followed }
enum ReleaseReminderChange: Equatable, Sendable { case on, off, denied, failed }

@MainActor @Observable
final class ReleaseReminders: AccountScopedState {
    private(set) var mode: ReleaseReminderMode            // per account; default .off
    private(set) var permission: NotificationPermission   // last read (existing enum)
    /// Profile toggle. Turning on asks for permission only while it is undecided; denied → .denied (mode stays .off).
    func setFollowing(_ on: Bool) async -> ReleaseReminderChange
    /// Effective state for the detail bell: override ?? (mode == .followed && status ∈ {.current, .repeating}).
    func isOn(for key: MediaKey) -> Bool
    /// Detail bell: flips the per-title override; asks for permission only when turning on while undecided.
    func toggle(_ key: MediaKey) async -> ReleaseReminderChange
    /// §11.2 rule (pure): showsTime && basis ∈ {confirmed, announced} && releaseAt > now + 60 s && !isPast.
    nonisolated static func isEligible(_ item: ReleaseScheduleItem, now: Date = Date()) -> Bool
    /// Recomputes pending requests from the schedule and the Library; never prompts.
    func reschedule() async
    func cancelAccountWork()
    func clearPrivateState()   // removes every pending + delivered "release-" request, resets in-memory state
}
// Built in AppComposition (registered in makeAccountScopedStates), injected in KuroApp and in the test graph
// (`testingGraph` / FixtureHost) so `@Environment(ReleaseReminders.self)` resolves in every host and snapshot.
// ReleaseReminderCopy (EN/DE, §11.3). The UNUserNotificationCenterDelegate routes a tap to DeepLink (N10).
// The legacy ReminderScheduler.scheduleAiringNotifications path is no longer called from the Library sink.
```

### 16.4 Between UI lanes (fixed signatures)

- `DetailSongShelf(songs:material:progress:showsAll:onCollapse:)` (§8.1): built by the Songs + entities lane. The integrator swaps it into the detail page.
- Entity pages are reached only through the existing `JourneyPage.character / .staff / .studio / .author`. No other cross-lane type is used.

---

## 17. Open items (recorded, not blocking)

**Data and matching**
1. **Song aliases.** For example "Ao no Sumika" and "Where Our Blue Is" (the same artist; the Japanese store has 青のすみか). These stay no-match until the owner accepts an alias rule (D12).
2. **Missing artists in AnimeThemes** (Refrain Boy): no Apple match, and the row says "Artist not listed".
3. **Episode stills on the wrong season:** a list with an equal count and a matching start cannot be detected on the client. This needs a server-side check in `bulk-import-anime` (season and offset mapping).
4. **No stills for current seasons** (every Fall 2026 title): the branded tile is the common case.
5. **"TV size" coverage is thin:** the source titles rarely carry the marker, and `media_themes_v1` does not return the Apple track name.

**Reads that cannot report a failure**
6. **`fetchCast`, `fetchVoiceActors`, `fetchVoiceRoles` and the episode and credit reads answer `[]` on failure.** A failure therefore looks like "none". The owners need a throwing read; this pre-dates this work.

**Device checks**
7. **VoiceOver order:** by construction only. Not device-checked.
8. **Interactive widget +1 and local notifications:** they need a signed device build with the App Group (unsigned `CODE_SIGNING_ALLOWED=NO` builds have no App Group). The lead verifies them on device.

**Lead actions**
9. **Privacy policy page** (outside the app): add the Apple preview IP note, local reminders, and the on-device widget. Lead action.
10. **`media_similar_v1`, the voice-actor and the Apple-theme migrations, the importer deploy, the backfill and the worker run** are prepared only. Until they are live:
    - More like this uses the live RPC path.
    - Voice chips, the "Voiced by" cards and roles are hidden.
    - Songs have no previews.

**Not built tonight**
11. **"All characters" directory page:** not built tonight. The rail shows up to 25 characters.

**Recorded at integration (2026-11-03 review)**
12. **Discover All is 2,102 pt** against the 2,000 pt acceptance (D17, corrected baseline about 2,700 pt). The next cut is a lead layout decision.
13. **Song preview: stop, not pause.** The built player has no paused phase; ▶ / ■ stops and a second tap restarts at 0:00. The ■ glyph and "Stop preview" / "Hörprobe stoppen" are what ships (§8.3 and §15 asked for ❚❚ and "Pause preview").
14. **Song preview player is composition-owned** (`Kuro/Releases/SongPreviewPlayer.swift`, built once by `AppComposition`, `AccountScopedState`, injected with `.environment`), not the page-scoped `@State` of §8.6, so one preview at a time holds across pages and every account transition stops it. Audio session `.playback` / `.default` as §8.6 says (an interim `.soloAmbient` was corrected at integration), and a 10 s load timeout fails a stalled stream.
15. **Next release per title only** (§11.2 as built): two rows per title need a schedule read that returns two units per title.
16. **Manga read run keeps one row** (§7.4): the prototype's manga reference (ref-detail-manga-390.png) shows only the last read chapter under Up next, so the manga run folds `1…(progress − 1)` while the anime run folds `1…(progress − 2)`. Recorded as the prototype exception.
17. **Song artists missing live** (W15 Cowboy Bebop: all four songs). The app now shows one footer note instead of a per-row "Artist not listed" when no song on a shelf names its artist; the data fix is the theme pass re-run in `docs/details-songs-2026-11-03/data/BACKFILL.md` §3a, before the Apple pass (an artistless song gets no Apple request, D12).
18. **Evidence gaps:** no render of the import review rows / match-picker candidates with a fixture job, the bell toasts and the denied / Settings / failed states (§11.4), or club presence with "Between us." after "More like this." (the after detail fixtures have no club data). The Profile reminders Toggle renders as a knobless capsule in the snapshot (an `ImageRenderer` artefact; the live walk shows a real switch).

---

## 18. Owner choices (decided by the lead; the owner said "don't ask")

1. **Base direction:** Companion, with Archive's hero and the prototype order (D1–D3).
2. **Season tab tap:** scrolls to Seasons, with no new picker.
3. **No notification for an announced day.** Only times that are not estimates notify. The 1 h-before reminder is retired (D14). If the owner wants day-level reminders, add "on the day at 10:00" later.
4. **Reminders default off.** The bell sets a per-title override.
5. **Strict song matching, no aliases** (D12).
6. **No mini-player.** One preview at a time, page-scoped (D11).
7. **Import primary button stays upper case** (copy rule, D16). Sentence case ("Read complete list for review") is a one-line copy change if the owner wants it.
8. **"Your year" counts titles saved or changed,** with the honest note (D15).
9. **Discover All:** Manga new to you as a rail, and Essential manga into the fold (D17). The premise "the 2,000 pt aim already held" was wrong (squashed baseline render); after this change All is 2,102 pt, about 600 pt shorter than before and about 100 pt over the aim (§17 item 12).
10. **Entity pages use `kuroPaper`,** the same paper as the detail page they are pushed from.

---

## 19. Build lanes: file ownership (no overlap)

### 19.0 Sequencing (D23)

1. The Data and Platform lanes finish, and are merged into `kuro/details-songs-platform` (data first, then platform).
2. The four UI lanes branch from that merge, each in its own worktree:
   - `kuro/ds-detail`
   - `kuro/ds-songs-entities`
   - `kuro/ds-widget`
   - `kuro/ds-profile-finishes`
3. The integrator merges them in this order: detail → songs-entities → widget → profile-finishes. It then does §19.7 and runs the full verification.

The project uses file-system-synchronized groups, so new Swift files under existing folders need no `project.pbxproj` edit. **Only the Widget lane edits `project.pbxproj`** (§19.3).

### 19.1 Detail lane: owns

| File | Scope |
|---|---|
| `Kuro/Views/DetailPages/Prototype/AnimeDetailSections.swift` | Everything **except** the `DetailSoundPanel` struct and the `.songs` call site, which stay byte-identical (§6.6) |
| `Kuro/Views/DetailPages/Prototype/MangaDetailSections.swift` | Manga page (§7) |
| `Kuro/Views/DetailPages/Prototype/DetailPage.swift` | `DetailHero` gains its optional fact rows (additive). `DetailSectionHeading` API unchanged (the entities lane uses it). |
| `Kuro/Views/DetailPages/Prototype/DetailSectionPolicy.swift`, `MangaDetailRules.swift`, `DetailNavigation.swift` | `.moreLikeThis`, `similarCount`, `hasNextRelease`, fold keys, `DetailPageCopy` additions |
| `Kuro/Views/DetailPages/DetailReleaseSections.swift` | `DetailNextReleaseSection` helpers |
| `Kuro/Views/DetailPages/Detail/` (new) | `DetailFactsLine`, `DetailNextReleaseRow`, `DetailMangaNextGlance`, `DetailReminderBell`, `DetailSeasonTab`, `DetailEpisodeTimeline`, `EpisodeStillPolicy`, `DetailCastRail`, `DetailMoreLikeThis`, `DetailBrandedTile`, `DetailRailPeek`, `DetailCertaintyMark` |
| Tests | Update expectations in `DetailSectionPolicyTests`, `DetailCopyTests`, `DetailHitTargetTests`, `DetailPathwayTests`, `MangaDetailLaneTests`, `NavdetailTests`. New: `KuroTests/DetailsPassDetailTests.swift` (still policy, facts parts, next-row visibility, peek table, VoiceOver labels) and `KuroTests/DetailsPassDetailAfterSnapshotTests.swift` (writes `docs/details-songs-2026-11-03/after/detail-*.jpg` only). |

**Never run with the write variable:** `DetailAnimeSnapshotTests` and `DetailMangaSnapshotTests`. Their committed PNGs live outside this folder.

### 19.2 Songs + entities lane: owns

| File | Scope |
|---|---|
| `Kuro/Views/DetailPages/Songs/` (new) | `DetailSongShelf`, `SongShelfGrouping` (pure), `SongPreviewPlayer`, `SongShelfCopy`. The songs use `EntityBrandedTile` from `Kuro/Views/Entities/`. |
| `Kuro/Views/Shared/KuroThemeSongRow.swift` | It may restyle or reuse it. Its initializer `KuroThemeSongRow(_ song: ThemeSong)` must stay source-compatible, because its only caller, the legacy `DetailSongsSection` in `DetailReleaseSections.swift`, is owned by the Detail lane. |
| `Kuro/Views/DetailPages/EntityDetailSheets.swift` | Character, staff, author and studio pages (§9) |
| `Kuro/Catalog/EntityWorks.swift` | Pure grouping (by year, decade) only |
| `Kuro/Views/Entities/` (new) | `EntityPageHero`, `EntityVoiceCard`, `EntityRefineWords`, `EntityWorkRail`, `EntityRoleRow`, `EntityRailPeek`, `EntityBrandedTile`, `EntityPageCopy` |
| Tests | Update `NaventityTests`. New: `KuroTests/SongShelfTests.swift` (grouping, version collapse, part headings, auto-reveal, NSFW, URL host rule, player phase machine with an injected fake player), `KuroTests/EntityPagesTests.swift`, and `KuroTests/SongsEntitiesAfterSnapshotTests.swift` (writes `after/songs-*.jpg` and `after/entity-*.jpg` only). |

`CastSection.swift` (legacy, unreachable) is **not touched**.

### 19.3 Widget lane: owns

| File | Scope |
|---|---|
| `Kuro.xcodeproj/project.pbxproj` | **Only:** add the synchronized root group `KuroWidgetViews` to the Kuro app target **and** the KuroWidgets target. Nothing else. |
| `KuroWidgetViews/` (new folder) | `WidgetPalette`, `WidgetCopy`, `NextReleaseWidgetContent`, `NowWatchingWidgetContent`, `WidgetRows`, `WidgetKeyFace`, `WidgetCertaintyMark` |
| `KuroWidgets/KuroWidgetViews.swift` | Thin wrappers that inject `Button(intent:)` |
| `KuroWidgets/KuroWidgetsBundle.swift` | Display names and descriptions only (families stay as the platform set them) |
| Tests | New: `KuroTests/WidgetContentTests.swift` (row caps per family, queued caption, caught-up, estimate without a time, signed-out copy) and `KuroTests/WidgetAfterSnapshotTests.swift` (renders the content views at 158 × 158, 338 × 158 and 338 × 354, in EN and DE, into `after/widget-*.jpg`) |

**Read-only for this lane:** `KuroWidgets/KuroWidgetTimeline.swift`, `AdvanceProgressIntent.swift`, `Info.plist`, the entitlements, `Packages/*` and `Kuro/Widgets/*`.

### 19.4 Profile + import + finishes lane: owns

| File | Scope |
|---|---|
| `Kuro/Views/ProfileView.swift` | "Your numbers." placement, the reminders row |
| `Kuro/Views/Profile/` (new) | `ProfileStats` (pure), `ProfileStatsSection`, `ProfileYearCard`, `ProfileRemindersRow`, `ProfileStatsCopy` |
| `Kuro/Views/ConciergeView+AniListImport.swift`, `ImportSourceChooser.swift`, `ImportWorkflowSheet.swift`, `ImportCatalogMatchPicker.swift`, `ImportHistorySection.swift` | View code only (§13). `ImportCopy.swift` is read-only: its strings stay byte-identical. |
| `Kuro/Views/EditorialDiscoverView.swift`, `Kuro/Views/Discover/*`, `Kuro/Views/EditorialDiscoverFrames.swift` (Discover-only types; shared types keep their API and pixels, DC§12.1), `Kuro/Views/DiscoverViewModel.swift` | §14.1, §14.2 |
| `Kuro/Views/About/DataSourcesView.swift` | Apple Music and on-device lines (§15) |
| Tests | Update `ProfileLaneTests`, `DiscoverLaneTests` and `DCdiscoverTests`. New: `KuroTests/ProfileStatsTests.swift` (every formula, year boundary in the device calendar, missing duration, empty Library), `KuroTests/ImportRestyleTests.swift` (strings byte-identical, bindings unchanged) and `KuroTests/FinishesAfterSnapshotTests.swift` (writes `after/profile-*.jpg`, `after/import-*.jpg` and `after/discover-*.jpg` only). **`DiscoverAfterSnapshotTests` is never run with the write variable**, because it writes last night's folder. |

### 19.5 Foundation lanes (finished before the UI lanes start)

| Lane | Owns |
|---|---|
| **Data** | `supabase/*`, `scripts/*`, `Kuro/Catalog/CatalogStore*.swift`, `CatalogVoiceModels.swift`, `CatalogCreditsModels.swift`, `Kuro/Releases/ReleaseModels.swift` (Apple fields), `Kuro/Releases/ReleasesStore+Schedule.swift` (decode), `Kuro/Discovery/RecommendationsReader.swift` |
| **Platform** | `Kuro/Composition/AppComposition.swift`, `Kuro/KuroApp.swift`, `Kuro/Releases/ReleaseReminders.swift`, `ReminderScheduler.swift`, `ReleasesStore.swift` (sink), `Kuro/Identity/SessionController.swift` (cleanup), `Kuro/Library/LibraryActions.swift`, `Kuro/Widgets/*`, `KuroWidgets/*` (except §19.3's two files), `Packages/*`, `Kuro.xcodeproj` (target, App Group), the entitlements, `Kuro/Services/DeepLinkRouter.swift` (notification tap) |

UI lanes treat every file in this table as **read-only**. If a UI lane needs a change there, it stops and reports.

### 19.6 Read-only for every UI lane

- **`Kuro/Views/Home/*`:** `HomeInk`, `HomeArtwork`, `HomeArtworkPressStyle`, `HomeContactStyle`, `HomeScrub`, `HomeOpeningLineView`, `HomeQuietCard`, `HomeFooter`, `.homeEntrance()`.
- **`Kuro/Views/Shared/*`** except `KuroThemeSongRow.swift` (§19.2): `KuroBrandedStates`, `KuroFold`, `KuroAdvanceKey`, `KuroInkButton`, `KuroMediumSwitch`, `KuroReadableWidth`, `KuroMotionEffects`, `KuroDiscardGuard`, `KuroReleaseLine`, `KuroStateView`.
- **`Kuro/Views/TastePicksView.swift`:** `TastePlanKey`, `TastePlanController`, `TasteCard`, `.tastePlanHost`, `TastePlanToastView`.
- **Other shared code:**
  - `Kuro/Design/*`
  - `Kuro/Views/Routing/*`
  - `Kuro/Releases/ReleaseCopy.swift`
  - `Kuro/Views/DetailPages/Prototype/DetailPage.swift`'s `DetailSectionHeading`, for every lane other than Detail
- **Committed evidence outside `docs/details-songs-2026-11-03/`.** If a run rewrites it, restore it with `git checkout -- <file>`.

### 19.7 Integrator (owned by nobody until integration)

The integrator does these steps in order:
1. Merge the lanes in the order of §19.0.
2. **Songs swap:** in `AnimeDetailSections.swift`, replace `DetailSoundPanel(songs: songs, material: material, showsAll: …, onCollapse: …)` with `DetailSongShelf(songs: songs, material: material, progress: progress, showsAll: …, onCollapse: …)`. Delete `DetailSoundPanel` if a grep finds no other user.
3. **Peek fold:** create `Kuro/Views/Shared/KuroRailPeek.swift` with §5.1's code, and point `DetailRailPeek`, `EntityRailPeek` and Discover's copy at it in one commit. All the lane tables must agree first.
4. **Tile fold:** create `Kuro/Views/Shared/KuroBrandedTile.swift` from the two lane copies, after checking that their values are identical. Replace both copies.
5. **Rule 1/2 docs** (D24), including the CLAUDE.md file map and counts.
6. **Gates:** run `run_all.sh`. The docs-current-state gate is blocking, so it fails on lane branches until step 5 is done.
7. **Full `KuroTests`** on the owned simulator (by UUID), after renders and the device-only open items.

### 19.8 Lane rules (all UI lanes)

**Builds and tests**
- Use `CODE_SIGNING_ALLOWED=NO` and `-parallel-testing-enabled NO`.
- Use your own `-derivedDataPath` under `/Users/max/.claude/jobs/1fb75ce2/tmp/<lane>/`.

**Simulator**
- Create a new one with `xcrun simctl create Kuro-Lane-ds-<lane> "iPhone 17 Pro" <newest iOS runtime>`.
- Use it by UUID only, and delete it when done.
- **Never** use `7FC4B58A-430C-457D-A017-6B0095723F3F` (integrate and fix agents only) or any simulator you did not create.

**Renders**
- Write to `docs/details-songs-2026-11-03/after/` only, and only with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`.
- JPEG quality 80, at most 603 px wide.
- 390 pt for every screen. 320 pt and iPad (readable column) for the main screens: anime detail top, manga detail top, songs, character page, Profile numbers, AniList import and Discover All.
- Fixture data only, using the existing fixture and snapshot approach (`FixtureHost`, `testingGraph`). No network.

**Never**
- Backend, flags, production data or push.

**Commits** end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01EXnQobKNDuiWFN5zm6WcdH
  ```

**Code rules**
- `@Observable` only.
- No force unwraps.
- `print` only inside `#if DEBUG`.
- No SDK imports in views. AVFoundation in `SongPreviewPlayer` is fine: it is not the Supabase SDK.
- Every string through `KuroLocale` or the lane copy enum. `WidgetCopy` is the only exception.
- No `ProgressView(`.
- Widths from the measured container, never `UIScreen.main`.
- Account-scoped results keyed by the account and dropped on a switch.

**Source compatibility**
- The initializers that tests a lane does not own call must keep compiling: `AnimeDetailPage(anime:preview:)`, `MangaDetailPage`, the entity sheets' initializers, `EditorialDiscoverView()` and `ProfileView`'s.
- New `AnimeDetailContent` fields get defaults, so that fixture previews compile: `cast: [CastMember] = []`, `similar: [Anime] = []`, `reminderOn: Bool? = nil` for renders.
- If a behaviour change makes a test in a file the lane does not own fail, the lane stops and reports. It does not edit that test.

---

## 20. Acceptance checklist

**Detail (anime and manga)**
- [ ] The hero shows the facts line, and the next row when a row exists (anime). The manga page shows its facts line and the next-chapter glance.
- [ ] A time appears only for `showsTime`. An estimate has the dashed mark and no bell.
- [ ] The season tab appears only for a proven chain with two or more numbered seasons, and scrolls to Seasons.
- [ ] Timeline: ticks equal Library progress. The watched-run fold works. The Up next +1 path is unchanged.
- [ ] Generic titles are omitted. Rejected stills fall back to tiles (`EpisodeStillPolicy` tests: JJK S2 24 > 23 rejected; Apothecary 25–48 with prior 24 → offset 24; 1…12 accepted).
- [ ] The cast rail shows voice chips when a voice actor exists, with two separate targets. It shows BACKGROUND characters when nothing else exists.
- [ ] More like this appears with Plan keys and an Undo toast. Own-ladder titles are absent. The rail is hidden when unavailable.
- [ ] No 映 or 原作 glyph remains (`grep -rn "映\|原作" Kuro/Views/DetailPages` finds only comments, or nothing).

**Songs**
- [ ] Parts follow the episode ranges. Versions are collapsed with tags. The artist (or "Artist not listed") is on every row.
- [ ] ▶ plays only a validated preview URL. One plays at a time. It stops when leaving the page or going to the background.
- [ ] The attribution footer appears when a match is visible.
- [ ] A spoiler stays veiled (no artwork fetch) until tapped, or until progress ≥ the song's first episode. NSFW songs are never auto-revealed.

**Entity pages**
- [ ] No black pills and no serif caps remain on the entity pages.
- [ ] Character → voice actor → character pops back (N5).
- [ ] The staff page shows Roles when voice roles exist. The studio page uses the cover line without a logo.

**Widget**
- [ ] The views render in KuroTests from `KuroWidgetViews/`.
- [ ] The +1 is `Button(intent:)` only. The queued caption shows. There is no stamp.
- [ ] An estimate has no relative countdown. The signed-out copy shows.

**Notifications**
- [ ] Pure tests on `isEligible`: instant + confirmed yes; announced day no; estimate no; past no.
- [ ] The Library sink never calls `requestAuthorization`.
- [ ] `clearPrivateState` removes every `release-` request.

**Profile**
- [ ] Every formula matches §12.2 in its tests. "Your year" has the honest note.
- [ ] A catalogue failure shows the inline failed state, not zeros.
- [ ] The reminders toggle asks for permission only when turned on.

**Import**
- [ ] Every visible string is byte-identical (test).
- [ ] Bindings and busy, Stop and discard behaviour are unchanged. `ImportWorkflowIntegrationTests` is green.

**Finishes**
- [ ] Every listed rail uses §5.1, and its tests pin the table.
- [ ] The Discover All render is at most 2,000 pt (target 1,500), and the measured height is reported.
- [ ] VoiceOver rules §14.3 are applied. The device pass is listed as open.

**All lanes**
- [ ] `check_branded_states.sh`, `check_architecture.sh` and `check_navigation.sh` pass.
- [ ] No committed PNG outside `docs/details-songs-2026-11-03/` has changed.
- [ ] Every new string has German.

---

## 21. Verification (each lane, then the integrator)

```bash
SIM=$(xcrun simctl create Kuro-Lane-ds-<lane> "iPhone 17 Pro" <newest-iOS-runtime-id>)
xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination "id=$SIM" \
  -derivedDataPath /Users/max/.claude/jobs/1fb75ce2/tmp/<lane>/dd CODE_SIGNING_ALLOWED=NO build
xcodebuild ... test -parallel-testing-enabled NO -only-testing:KuroTests/<Suite>      # the lane's suites, no write variable
TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1 xcodebuild ... test -parallel-testing-enabled NO \
  -only-testing:KuroTests/<Lane>AfterSnapshotTests                                    # renders into docs/details-songs-2026-11-03/after/
scripts/quality-gates/check_branded_states.sh
scripts/quality-gates/check_architecture.sh
scripts/quality-gates/check_navigation.sh
(cd Packages/KuroModules && swift test)                                               # widget + data lanes
git status --short                                                                    # nothing outside the lane's files and after/
xcrun simctl delete "$SIM"
```

The integrator also runs:
- `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh`, after the docs (D24)
- the full `KuroTests` on the owned simulator `7FC4B58A-430C-457D-A017-6B0095723F3F`
- `scripts/db/run_local_db_tests.sh` and the deno suites for the prepared backend

It then writes `docs/details-songs-2026-11-03/REPORT.md`.
