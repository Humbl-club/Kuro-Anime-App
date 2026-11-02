# Kuro design rulebook (overnight 2026-11-01)

**Lane:** design-rulebook. This is a read-only audit. No source, git, simulator or remote state was changed.
**Purpose:** this is the single set of rules that every screen lane follows tonight.
**Scope:** iPhone first, adaptive from 320 pt to 430 pt content widths, with iPad layouts kept coherent. The app is light mode only (`Kuro/KuroApp.swift:82`).

Notation used throughout:
- **[APPROVED]** means an explicit owner decision with a citation.
- **[CURRENT, ACCEPTANCE OPEN]** means it is built natively, but the owner has not visually accepted it.
- **[EXTRAPOLATION]** means my derivation from approved material. No owner has seen it.
- **[OPEN]** means an owner call is needed. A screen lane must not treat it as settled.

File and line citations are against the working tree at `d8aeae7` on `kuro/overnight-2026-11-01`.

---

## 0. Precedence: which source wins when sources disagree

1. **The latest explicit owner requests and rejections.**
   - `docs/handoffs/2026-10-08-fresh-session/HANDOFF.md:37-40`: "begin with Home/details/Profile; large type over artwork; reconsider the yellow page tint".
   - `HANDOFF.md:83`: "Do not resurrect rejected Crosscut, offset/masonry or old workbench alternatives. The new neutral palette and empty-Home/Profile request supersede the old cream styling; retain the accepted composition decisions."
   - The nine 9 October change-log entries: `CURRENT_APP_STATE.md:19568-19602` and `CURRENT_APP_STATE_PLAIN.md:1953-1983`.
2. **The native polish plan, 8 October:** `docs/plans/2026-10-08-native-design-polish.md`. It governs palette (`:24-38`), type and geometry (`:40-44`), motion (`:46-50`), empty Home (`:52-73`), populated Home (`:75-89`), detail (`:91-99`) and Profile (`:101-112`).
3. **Series/Home master plan v1.1:** `docs/plans/2026-10-02-series-and-home-rebuild-DRAFT.md`.
   - Section 1 decisions (`:40-69`).
   - Artwork and data-honesty rules (`:170-192`).
   - Section 7 composition and wiring (`:210-255`).
   - Section 12.7 design transfer (`:504-510`).
   - The "Historical draft record" from `:533` onward is explicitly non-executable.
4. **The selected prototype** (`tools/design-directions/instrument.*`, `manga-philosophies.*`). Use it for **geometry, hierarchy and interaction only, never palette.**
   - Its Poster canvas is `#fffef8` (`instrument.css`, rule `.phone[data-switch=poster] { background:#fffef8 }`), and its strokes and inks are green-greys. Both are superseded by rank 1 and rank 2.
5. **The 26 September product decisions** (`docs/research/2026-09-26-kuro-plan/CURRENT_DECISIONS_AND_AUDIT.md:13-30`) and **the 27 September issue-style brief** (`docs/research/2026-09-27-issue-style/EXECUTION_PROMPT.md`). They apply only where nothing above supersedes them. The issue brief's paper `#F6F4EF` (`EXECUTION_PROMPT.md`, "The look") is superseded.
6. **Project rules in CLAUDE.md.** Examples: monochrome statuses, red only for destructive actions, design-system tokens only, no `UIScreen.main`, no hardcoded 393 pt widths. These sit across all ranks as hard constraints.

Where a rule below conflicts with an older document, the rule names what it supersedes.

---

## 1. Owner decision ledger: approvals and rejections

### 1.1 Approved

| Date | Decision | Evidence |
|---|---|---|
| 2026-08-16 / 09-25 | The welcome screen is `b943e457` (painted scenery loop, grouped "Kuro" wordmark and serif headline, TV removed). Preserve the composition. | `git show b943e457 --stat` (removes `AuthZenTV`, −34 lines); `CURRENT_APP_STATE.md:146`; `CURRENT_DECISIONS_AND_AUDIT.md:17` |
| 2026-09-26 | Scenery animation belongs to welcome/auth only. Keep top swipe navigation. Launch into Home. Search belongs to Discover. Persistent Anime/Manga choice. Clubs are the only social graph. Taste is secondary. Statuses are monochrome, with no constant animation. | `CURRENT_DECISIONS_AND_AUDIT.md:7,17-28` |
| 2026-09-27 | Issue-style title frame: picture first, then title, then at most one line. No numbered contents, no score chips or genre pills in the frame. "Motion confirms a change." | `docs/research/2026-09-27-issue-style/EXECUTION_PROMPT.md:3,12-24,49-66`. **Palette superseded. No native code for it exists in `Kuro/`** (`DiscoverIssue*` appears only in docs commit `9580268`, checked with `git log -S DiscoverIssueSpread`). |
| 2026-10-01 | !Boring is the primary reference: considered controls, one exceptional progress control, careful response. MUBI and Sequel are not the direction. | `CURRENT_APP_STATE_PLAIN.md:1440,1445`; `tools/design-directions/reference-atlas.html` (!Boring card) |
| 2026-10-01 | Liked: member names, the upcoming timeline, the Sunday Club arrangement. Removed: chunky buttons, glossy switching, cover flipping, bouncy feedback. | `CURRENT_APP_STATE_PLAIN.md` (session "Less decorative depth", around `:1462`) |
| 2026-10-02 | **Artwork season tab:** a white "Season N" tab on main artwork, an "S2" stamp on compact covers, no numbered season rows. Inspecting a season never changes progress. | `tools/design-directions/INSTRUMENT_README.md:7,21-27`; `CURRENT_APP_STATE_PLAIN.md:1647` |
| 2026-10-02 | **Poster medium switch** ("the poster feels right just needs a polish"). | `INSTRUMENT_README.md:180`; `switch-options.html` ("Selected by the owner") |
| 2026-10-02 | Anime detail opens with a **shallow, full-width, horizontal** image, not a tall portrait hero. | `INSTRUMENT_README.md:106-108`; series plan `:52` |
| 2026-10-03 | **Manga Library:** equal covers, a per-book chapter position, and a separate advance key of at least 44 pt. Cover and title form one detail target. No workbench, no selection step, no repeated Open rows. | `INSTRUMENT_README.md:250,280-282,294` ("Owner liked the per-book Library rework"); series plan `:49` |
| 2026-10-03 | A **Coming Up glance** sits directly below the medium switch, visible on short phones. One tap goes to the full calendar. | `INSTRUMENT_README.md:294-296`; series plan `:50` |
| 2026-10-02/05 | Private club: Sunday Club artwork treatment, member names when allowed, "Between us." on details. No public network or comments. | series plan `:51`; `INSTRUMENT_README.md:69-71` |
| 2026-10-05 | Artwork-derived material color is allowed. Statuses stay monochrome. No arbitrary title-to-color map. Liked blue/teal overrides are kept explicitly. | series plan `:56`; `INSTRUMENT_README.md:86` |
| 2026-10-08 | **Neutral palette:** a white page with no yellow or green cast; color stays local to artwork. Empty Home is image-led with large type and gentle motion. Profile is rethought as an account hub. | `CURRENT_APP_STATE.md:15`; `HANDOFF.md:37-40`; polish plan `:24-38` |
| 2026-10-09 | Empty Home, the mountain invitation: "Your next story starts here." Find and Import are two actions. The picture runs through the status bar and header. **Only for an empty selected-medium shelf.** | `CURRENT_APP_STATE.md:19590-19602`; `HomeView.swift:834-890`; `ContentView.swift` `homeInvitation` |
| 2026-10-09 | A saved shelf uses the **original Poster Home with owner adjustments**: an ink Coming-up row under the switch, shallow Anime scenes with a white ink foot and a light raised plus, equal Manga covers with the chapter ticket on the art and a dark raised plus, then the calendar, then the dark club room only when real notes exist. | `CURRENT_APP_STATE.md:3,19586` |

All 9 October native passes are **[CURRENT, ACCEPTANCE OPEN]**. Every entry repeats "Visual acceptance remains open."

### 1.2 Rejected. Never reintroduce these

| What | Evidence |
|---|---|
| Five email/first-login/Home/Collection/Agenda layouts (2026-09-25) | `CURRENT_APP_STATE_PLAIN.md:1278` |
| The "moving-mountains Home" as a general Home language (Sept). The 9 October empty-shelf invitation is the only sanctioned exception. | `CURRENT_DECISIONS_AND_AUDIT.md:7` |
| Generic editorial directions (Edition, Index, Gallery) | `index.html`; `CURRENT_APP_STATE_PLAIN.md:1339` |
| Decorative numbering, ordinals and padded counts ("01 / 02") | `CURRENT_APP_STATE_PLAIN.md:1344`; issue brief `:16` |
| Folio, Panels and Interlude (selected-title hero, overlapping books, context tabs) | `CURRENT_APP_STATE_PLAIN.md:1339,1344,1354`; `tools/design-directions/README.md:93,102` |
| Flow ("boring"), then Thread, Cut and Journal studies | `CURRENT_APP_STATE_PLAIN.md:1385,1392` |
| World/map landscapes | `CURRENT_APP_STATE_PLAIN.md:1413` |
| Aperture colour directions (oxblood/parchment, ink/powder blue, olive/butter), and a dominant medium switch | `CURRENT_APP_STATE_PLAIN.md:1435`; `composition-review.html` |
| Raised material v8 (graphite tray, faux hardware, bevels, dials) | `CURRENT_APP_STATE_PLAIN.md:1531`; `archive/material-v8/` |
| Medium-switch studies v40-v47: Splice, Fold, Lens, Ribbon, Dial, Window, Edge, Diptych (generated banner), Shelf, Masthead, Compact header, Margin, Exposure, Relay, Interlock, Signature, Objects | `INSTRUMENT_README.md:130,150,156,162,168,174` |
| Noir, Glass, Edgewise and Keys (not selected when Poster was) | `switch-options.html`; `INSTRUMENT_README.md:180` |
| Manga horizontal reading spreads (v50), dark ink shelf or "large colored surface" (v51), chapter margins (v52, superseded) | `INSTRUMENT_README.md:192,198,204` |
| Manga Edition, Contact and Index ("recycled compositions and palette variants") | `INSTRUMENT_README.md:225`; `manga-options.html` |
| **Crosscut: offset or unequal manga artwork and containers** | `INSTRUMENT_README.md:236`; `manga-crosscut.html` ("Rejected by Max") |
| Library selected-book workbench, the select-then-track model, repeated Open rows, cover-select/title-detail split | `INSTRUMENT_README.md:273-282` |
| Chapter Board, Journal and Club Room manga philosophies (not selected) | `manga-four.html`; `INSTRUMENT_README.md:250` |
| Season labels as boxed rails, detached rows, or numbers under titles | `CURRENT_APP_STATE_PLAIN.md:1609-1647` |
| **Yellow/cream page tint** (`#FFFEF8`, `#F6F4EF`, `#fffef8`) | `CURRENT_APP_STATE.md:15`; polish plan `:13,26`; `HANDOFF.md:40,83` |
| **The form-like native pass** (9 Oct, first pass) | `CURRENT_APP_STATE.md:19574` |
| **The cover-then-white-paper mash-up** (9 Oct) | `CURRENT_APP_STATE.md:19582` |
| "One picture, one page" behind a populated Home (9 Oct). Superseded, not explicitly rejected: picture and wash are now invitation-only. | `CURRENT_APP_STATE.md:19586-19590` |
| The Zen TV on the welcome screen | `b943e457` |
| Prominent generic Journey/Adaptation Path UI | series plan `:58` |
| Glass/blur blobs and six statistic tiles on Profile | polish plan `:18,106,112` |

---

## 2. Prototype server inventory (http://127.0.0.1:8803, `tools/design-directions/`)

Every page below returned HTTP 200 during this audit. The selected compositions were rendered at 390×844 in a headless browser; temporary output was deleted afterward.

| Page | Classification | Evidence |
|---|---|---|
| `instrument.html` (default = `?switch=poster`) | **SELECTED: Anime Home (Poster switch, artwork season tab, scenes, Coming Up glance, calendar, Sunday Club) and detail interactions** | `INSTRUMENT_README.md:7,180`; series plan `:93-95` |
| `instrument.html?switch=poster&medium=manga` | **SELECTED: Manga Library (per-book keys)** | `INSTRUMENT_README.md:250,294`; series plan `:49` |
| `instrument.html?seasons=compare` | Only the **Artwork tab** inside it is SELECTED. The other two labelling options are historical. | `INSTRUMENT_README.md:18,29` |
| `instrument.html?detail=anime-2` / `?detail=manga-0` | **REFERENCE** for detail intent (season story, panels, bookmark, Between us.). The prototype's numbered season tiles are superseded by "artwork panels where verified artwork exists" (polish plan `:95`). | `INSTRUMENT_README.md:40-57` |
| `manga-library.html` | **SELECTED wrapper** for the Library. Its in-page copy still says "needs your review"; the selection evidence is the owner remarks cited above. | file text; `INSTRUMENT_README.md:294` |
| `instrument.html?switch=noir/glass/edgewise/keys` | NOT SELECTED | `switch-options.html` |
| `instrument.html?switch=splice/fold/lens/ribbon/dial/window/edge/diptych/shelf/masthead/compact/margin/exposure/relay/interlock/signature/objects` | REJECTED | §1.2 |
| `instrument.html?...&reading=edition/contact/index` | REJECTED | `manga-options.html` |
| `instrument.html?...&reading=crosscut` | REJECTED | `manga-crosscut.html` |
| `instrument.html?...&reading=chapterboard/journal/clubroom` | NOT SELECTED | `manga-four.html` |
| `switch-options.html` | Comparison board. Poster is labelled "Selected direction". | file text |
| `manga-four.html` | Comparison board. Library has since been reworked and selected; the others are not selected. | file text |
| `manga-options.html` | REJECTED studies board | file text ("Previous studies — rejected") |
| `manga-crosscut.html` | REJECTED | file text |
| `index.html` (Edition/Index/Gallery) | REJECTED (generic) | `CURRENT_APP_STATE_PLAIN.md:1339` |
| `folio.html` | REJECTED, twice | `CURRENT_APP_STATE_PLAIN.md:1339,1344,1354` |
| `panels.html` | REJECTED | `README.md:93` ("after the user rejected Panels as boring") |
| `interlude.html` | REJECTED | `README.md:102` |
| `flow.html` | REJECTED ("boring") | `CURRENT_APP_STATE_PLAIN.md:1385` |
| `studies.html` (Thread/Cut/Journal) | REJECTED | `CURRENT_APP_STATE_PLAIN.md:1392` |
| `journal.html` | SUPERSEDED (followed by world; no explicit verdict found) | `CURRENT_APP_STATE_PLAIN.md:1397-1404` |
| `world.html` | REJECTED | `CURRENT_APP_STATE_PLAIN.md:1413` |
| `modern.html` (Shelf/Screen/Today) | SUPERSEDED (followed by aperture; no explicit verdict found) | `CURRENT_APP_STATE_PLAIN.md:1411-1418` |
| `aperture.html` | REJECTED (colours and composition) | `CURRENT_APP_STATE_PLAIN.md:1435` |
| `archive/material-v8/instrument.html` | REJECTED | `CURRENT_APP_STATE_PLAIN.md:1531` |
| `archive/fluid-v9/instrument.html` | SUPERSEDED historical snapshot | `CURRENT_APP_STATE_PLAIN.md:1533-1539` |
| `boring-study.html` | RESEARCH: the chosen primary reference board | `CURRENT_APP_STATE_PLAIN.md:1445` |
| `reference-atlas.html` | RESEARCH (Savee, Family, !Boring, Gentler Streak) | `CURRENT_APP_STATE_PLAIN.md:1440` |
| `references.html` | RESEARCH, rejected as direction (MUBI, Sequel) | `CURRENT_APP_STATE_PLAIN.md:1440` |
| `manga-reference-study.html` | RESEARCH | `INSTRUMENT_README.md:208-210` |
| `composition-review.html` | DIAGNOSIS. Its conclusions still bind: the medium switch must not dominate; no expensive nested frames; releases and club must not be buried below a long queue; keep the neutral ground. | file text |

Generated assets that are **not** approved brand material: `assets/medium-diptych-v43.*` (v43 rejected) and `assets/medium-objects-v47.*` (v47 rejected). `world-landscape.png` and `world-paper.png` belong to the rejected World study.

---

## 3. Palette

### 3.1 Roles

All roles are tokens in `Kuro/Design/KuroDesignSystem.swift:94-110`. Use only tokens; never scatter hex literals (polish plan `:38`).

| Role | Token | Value | Contrast on white | Use |
|---|---|---|---|---|
| Page | `kuroCanvasPage` | `#FFFFFF` | — | Canvas for every screen. **[EXTRAPOLATION]** Extend from Home/detail/Profile to all screens. In light mode `kuroBackground` already resolves to white, so this is a no-cast change. |
| Quiet surface | `kuroCanvasQuiet` | `#F6F6F6` | — | Contained controls and secondary groups only. Never a whole-page background. |
| Primary ink | `kuroInk` | `#181818` | 17.8:1 | Headlines, title names, primary buttons (filled), progress numerals |
| Secondary ink | `kuroInkSecondary` | `#5C5C5C` | 6.7:1 | Explanatory text, metadata |
| Quiet ink | `kuroInkQuiet` | `#6B6B6B` | 5.3:1 | Captions and kickers. This is the lightest ink allowed for any text that carries meaning. |
| Hairline | `kuroHairline` | black at 10% | — | Separators. The polish plan's range is 8-12%. |
| Missing art | `kuroMissingArt` | `#E6E6E6` | — | Stable geometry when art is missing or fails to decode |
| Destructive | `kuroError` | red at 85% | — | Destructive actions and inline errors only (CLAUDE.md) |
| Artwork material | per displayed image | stored digest-keyed palette | ≥ 4.5:1 required | Anime scene foot, private room. See §3.3. |

Legacy tokens still exist: `kuroBlack80`…`kuroBlack02`, `kuroTextSecondary` (black 55%, 4.7:1) and `kuroTextTertiary` (black 45%, **3.4:1, fails AA for normal text**).

**Rule:** do not use `kuroTextTertiary`, `kuroBlack45`, `kuroBlack40` or anything lighter for text a user must read. Use `kuroInkQuiet`. The CLAUDE.md design-token table lists `kuroTextTertiary`; that entry predates the neutral palette.

### 3.2 Cast leftovers that must be neutralized

These are green-grey prototype values still live in `Kuro/Views/Home/HomeView.swift`.

| Line | Literal | Replace with |
|---|---|---|
| 564 | `#DCDDD7` (stroke) | `kuroHairline` |
| 606, 614 | `#D7D9D2` (ticket stroke) | `kuroBlack12` (existing token). **[EXTRAPOLATION]** Alternatively add `kuroKeyRim` = black 12%. |
| 628 | `#60645E` (unit label) | `kuroInkQuiet` |
| 663 | `#30352E` (light key glyph) | `kuroInk` |
| 666 | `#2C322F` (dark key fill) | `kuroInk` **[EXTRAPOLATION]**. Keep the key dark; drop the green hue. |
| 670 | `#D7DAD2` (light key rim) | `kuroBlack12` |
| 1067 | `#252B28` (club room) | A neutral near-black, e.g. a new token `kuroRoom` = `#222222` **[EXTRAPOLATION, OPEN]**. Keep the room's darkness; remove the green. |

The prototype club text colors (`#f0f4ef`, `#b4c2a9`, see `.club-room-footer` in `instrument.css`) become `kuroWhite90` and `kuroWhite60`.

Superseded backgrounds, which must not be copied:
- Prototype Poster `#fffef8`.
- Prototype upcoming glance `#fffefa`.
- Library board frame `#e9ebe6` and `#f5f5f3` (`manga-library.html`, `manga-philosophies.css`).
- Issue brief `#F6F4EF`.

### 3.3 Artwork material

- Derive material from the exact displayed image, keyed by image digest and revision, never by title (series plan `:56,190`).
- Use it only for the Anime scene foot, the detail opening, and the private-club room. Selecting a season may change detail material, but never Home's current resume artwork (series plan `:190`).
- White-on-base contrast must be at least 4.5:1. The prototype's minimum was 7.41:1 (`INSTRUMENT_README.md:86`).
- The fallback is neutral (`kuroInk` foot with white type), never a placeholder color picked to look pleasant.
- Liked AoT and Demon Slayer overrides are preserved explicitly (`INSTRUMENT_README.md:86`).
- **The prototype pipeline is a reference, not a production source.** `tools/design-directions/build_art_materials.py` generates `instrument-art-materials.js`. Natively, use `cover_image_color` (already imported, see `CURRENT_DECISIONS_AND_AUDIT.md:161`) or a stored digest-keyed palette. Clamp both toward darker values until white text reaches 4.5:1. **[EXTRAPOLATION]**
- Manga uses only restrained material accents. Paper stays neutral white (series plan `:190`).
- Status is never encoded in color: no colored dots, pills or badges (CLAUDE.md DO-NOT #3; series plan `:56`).

---

## 4. Typography

Map roles once and never pick fonts per screen (polish plan `:42`). Serif carries editorial voice; sans carries title labels, buttons and settings.

| Role | Token / spec | Size (default) | Where |
|---|---|---|---|
| Cover line (one per screen at most) | `kuroDisplay(weight: .light)`, tight tracking, short ink rule underneath | 44 pt scaled, capped at 72 | Empty Home "Your next story starts here." (`HomeView.swift:890`); welcome uses its own approved 33 pt medium serif (`AuthView.swift:184-189`) |
| Section heading | `kuroHeadline(.light)` or `kuroTitle()` serif, with `.accessibilityAddTraits(.isHeader)` | 26 / 19 pt | "Coming up.", "Seasons", "Between us." |
| Medium switch word | **[OPEN]**. Native is `.system(size: 40 or 32, weight: .heavy, design: .serif)` with an artwork mask (`HomeView.swift:225-240`). The selected prototype is heavy sans uppercase, 36/30 px (`.selector[data-family=poster] .mode-name`). | 40 pt | Home only. Do not change without an owner call; series plan 12.7 requires owner approval for any visible deviation (`:506`). |
| Title name on a card | sans `kuroCustom(17, weight: .medium, relativeTo: .headline)` for leads; `kuroBody(.medium)` (15) for compact | 15-17 pt | Scenes, covers, rows. At most 2 lines, then truncate; the full title goes in the accessibility label. |
| Body | `kuroBody(.light/.regular)` | 15 pt | Premise, explanations. The plan's target is 15-17 pt (`:42`). |
| Metadata / control text | sans 12-15 pt via `kuroCustom(…, relativeTo: .footnote/.subheadline)` | 12-15 pt | Dates, counts, button labels |
| Progress numeral | sans regular, negative tracking (-0.9 large / -0.4 compact) | 28 / 19 pt | Matches native and prototype `.chapter-bookmark .progress-label b` |
| Kicker | `.kuroKicker()`: `kuroMicro` 9 pt, tracking 2.1, uppercase, `kuroInkQuiet` (`KuroDesignSystem.swift:239-248`) | 9 pt | **Decoration or redundant labels only.** It must never be the only carrier of meaning. |
| Caption | `kuroCaption` | 11 pt | Nonessential captions only (polish plan `:42`: "Reserve tiny captions for nonessential decoration") |
| Primary button label | sans 17 semibold | 17 pt | "Get started" (`AuthView.swift:196-205`) |
| Header wordmark | "KURO" in sans tracked caps, ink (Home on scenery) or quiet ink | — | `KuroHeaderNew`. Welcome uses "Kuro" serif 18 semibold with tracking 4 (`AuthView.swift:179-182`). |

Rules:

- **Dynamic Type is required.** Use `Font.kuroCustom(_:weight:design:relativeTo:)` (`KuroDesignSystem.swift:129-142`) or role tokens.
  - New code must not use `.system(size:)` without scaling.
  - Existing offenders to fix while touching them: `HomeView.swift:464` (7 pt "SEASON"), `:628` (9 pt unit label, raise to 11-12 pt), `:635`, `:1087`.
- Let text reflow; do not shrink essential copy (polish plan `:44`).
  - `minimumScaleFactor` is allowed only on the single-word medium switch (`HomeView.swift:230`). Prefer the existing accessibility-size step-down to 32 pt.
- Serif for the editorial voice: cover lines, section heads, "Between us.", the pull-quotes in the club room.
- Sans for everything a user operates or scans: titles in grids, buttons, settings, numbers.
- Use sentence case everywhere, except kickers and the header wordmark.

---

## 5. Space, gutters and adaptivity

- **Outer gutter:** 20 pt (`KuroDesignSpacing.padding = 20`, `KuroDesignSystem.swift:262`; polish plan `:44`). The welcome and auth screens keep their approved 28 pt (`AuthView.swift:191,231`). At content width ≤ 320 pt, use 16 pt **[EXTRAPOLATION]**, matching the prototype's 320-px rules (e.g. `.activity-stage { margin-inline:17px/18px }`).
- **Scale:** 4/8/16/24/32/48 (`KuroDesignSpacing`, `:250-258`).
  - Between major sections: 32 pt.
  - Between items in a section: 16-24 pt.
  - Title to meta: 4-8 pt.
- **Widths:** always derive from the container (`GeometryReader` / `containerRelativeFrame`) and pass explicit `containerWidth` (CLAUDE.md DO-NOT #5).
  - **Forbidden for new layout:** `KuroScreen.width` (hardcoded 393, `KuroDesignSystem.swift:450-452`).
  - Also forbidden, because they depend on it: `ResponsiveLayout.*` (`:493-520`) and `KuroRadius.adaptive(…, for: KuroScreen.width)` (`:659`).
  - Existing `?? 393` fallbacks to remove when touched: `ContentView.swift:220`, `KuroPagingGesture.swift:19`, `ConciergeView.swift:52`.
- **Verification widths:** 320, 375, 390 and 430 pt content widths, plus iPad (series plan `:508`). Test at the largest accessibility text size, with long English and German titles.
- **Touch targets:** at least 44×44 pt for every interactive element. The visible control may be quieter than its hit area (polish plan `:44`).
- **Safe areas:** artwork may bleed under the status bar only on Home's invitation scene and the detail opening. Controls never sit in unsafe areas.

---

## 6. Artwork geometry

| Object | Rule | Source |
|---|---|---|
| **Anime Home scene** (lead watching titles) | Full content width, **aspect about 3.15-3.25:1** (native `.aspectRatio(3.15, …)` at `HomeView.swift:455`; prototype `.scene-window { aspect-ratio:3.25 }`). Prefer banner art; for cover-only titles use a deliberate crop (`INSTRUMENT_README.md:108`). Corners are 5 pt (Poster `scene-card { border-radius:5px }`). The scene sits on a foot with the title and progress beside it: image, title and progress read as one object (polish plan `:79`). | [APPROVED composition] |
| **Season tab** | White tab bottom-left on the main artwork: kicker "SEASON" plus a serif numeral. Compact covers get an "S2" stamp. Tapping opens the season overview and never mutates tracking. | `INSTRUMENT_README.md:23-27`; `HomeView.swift:461-470` |
| **Anime compact** ("Also watching") | Portrait cover thumbnail plus title and its own advance key, in 2 columns | prototype screenshot; `INSTRUMENT_README.md:24` |
| **Manga cover** | **Equal frames for every book**, at the common cover ratio of about 0.70 (2:3; `KuroCardMetrics.imageAspectRatio = 0.7`, `KuroDesignSystem.swift:586`). Fill with a top-biased crop (prototype `.library-art img { object-fit:cover; object-position:50% 30% }`). Never crop to a non-cover ratio; never use offset, masonry or unequal frames. Corners are 2-4 pt with a subtle paper edge. | series plan `:49,190`; `INSTRUMENT_README.md:236` |
| **Manga Home grid** | Selected prototype: **3 columns** with equal frames, 106×138 at 390 and 88×119 at 320 (`INSTRUMENT_README.md:254`), a title of at least 44 pt height, then a "Ch. N" plus 44×44 key row. Current native (owner-adjusted, acceptance open): **2 columns** with the chapter ticket on the art and a dark raised plus (`CURRENT_APP_STATE.md:3`). **[EXTRAPOLATION]** Choose the column count from width: `columns = max(2, floor((w + 12) / (minCover + 12)))` with `minCover` 96 pt for the 3-column index, and 2 columns for the lead pair. Use 2 columns at accessibility text sizes; never use 1-column offset. | |
| **Detail: Anime** | Shallow wide opening, about 210 pt high at 320 width and about 254 pt at full width (`INSTRUMENT_README.md:108`), then a compact title and status | series plan `:52,218` |
| **Detail: Manga** | Full portrait cover with restrained paper edges, a compact title and a bookmark | series plan `:52,224` |
| **Season panels** (detail) | Artwork panels when verified section art exists; otherwise a deliberate neutral panel. Never use another title's art. | polish plan `:95`; series plan `:190` |
| **Missing art** | Stable geometry, filled `kuroMissingArt`, title still readable, controls live | series plan `:190` |
| **Calendar thumbnails** | Small portrait covers. The glance shows up to 3, but the count includes **all** events. | `INSTRUMENT_README.md:296` |

**Never** pass a cover crop off as season art. **Never** show anime art labelled as manga art, or the reverse (`INSTRUMENT_README.md:88`; series plan `:228`).

---

## 7. Controls and interaction feedback

| Control | Spec |
|---|---|
| **Advance key (+1)** | 44×44 pt. It is a sibling of the detail target and is never nested.<br>Light variant on Anime: a white face with a `kuroBlack12` inset rim.<br>Dark variant on Manga art: a `kuroInk` face with a white 18% inset rim.<br>Corner radius 5 pt (outer) and 4 pt (inset). Glyph is SF `plus`, 15 pt medium. It becomes `checkmark` when caught up (disabled) and `list.number` when the unit needs a choice (`HomeView.swift:642-672`). |
| **Press feedback** | Immediate and reversible. Use a shallow inset or highlight, plus a scale of about 0.985 or 0.98, only where artwork stays crisp. Prototype contact is 120 ms (`instrument.css :root --motion-contact:120ms`) and settle is 220 ms. Cancel on scroll or drag; there is no contact after cancellation (series plan `:253`). |
| **Progress change** | Optimistic, local-first, through the existing durable coordinator.<br>The number updates **beside its own title**, with an Undo toast; keep Undo discoverable (polish plan `:48`).<br>Pending, confirmed, conflict and error are distinct states. On failure the prior value stays, with a visible inline message, no success haptic and no false success.<br>A **Stamp** count change is allowed: the old count leaves upward and the new one locks from below, 160 ms (issue brief motion table). |
| **Primary button** | Filled `kuroInk` capsule, 54 pt high, white 17 pt semibold label (`AuthView.swift:196-205`). At most one per screen region. |
| **Secondary button** | Capsule with a `kuroBlack12` 1 pt stroke, 54 pt (Apple button, `AuthView.swift:207-212`). |
| **Invitation action** | Kicker, then a serif line, a full ink rule and an arrow (`CURRENT_APP_STATE.md:19598`). Use it for Find, Import, and the source chooser rows (`ImportSourceChooser.swift`). |
| **Text link** | Ink, underlined only when inline in prose. |
| **Close** | One consistent accessible close control: a 44 pt circle on scenery or detail. It keeps contrast while scrolling (polish plan `:99`). Label it "Close" / "Schließen". |
| **Segmented status / filters** | Typographic words with an ink underline mark (Poster-like). Unselected words use `kuroInkQuiet`. No colored chips. **[EXTRAPOLATION from Poster switch]** |
| **Haptics** | Use `KuroAccessibility.impactHaptic(.light)` for medium selection and for opening a detail (`HomeView.swift:234`; `SeriesDetailViews.swift:227`). Fire `successHaptic` **once, only after** a durable accept of progress or saves. Failure is haptically silent and visually explicit (resolves issue brief "silent" vs series plan `:255` "quiet error feedback"). Never vibrate on remote sync. |
| **Pager versus tap** | A horizontal pager swipe sets `kuroSuppressCardTaps`; title taps must honor it (issue brief `:51`). Vertical scroll always wins over horizontal paging inside rails. |

---

## 8. Motion

There are three jobs only: a calm welcome scene, a clear context change, and immediate action feedback (polish plan `:48`). Motion confirms a change. It never decorates a wait, a failure or a status (issue brief `:49`).

| Kind | Allowed where | Spec |
|---|---|---|
| **Ambient drift** | **Only** the welcome/auth scene and the empty-shelf Home invitation, plus the Profile identity band as a still image. **Nowhere else.** This resolves the 26 September "auth only" rule against the 8 October empty-Home request. | `KuroSceneryLoop`: 34 s loop period (`KuroSceneryLoop.swift:49`), at most 30 fps (`:34`). It stops when offscreen, backgrounded, under Reduce Motion or under Low Power (`KuroMotion.ambientDriftAllowed`, `KuroDesignSystem.swift:419-423`; `KuroSceneryLoop.swift:28-31`). The still frame is a composed frame. |
| **Context change** | Medium switch, opening or closing a detail, season selection | Crossfade or settle of 180-260 ms with no repeated stagger on refresh (series plan `:253`). Issue-brief timings are the reference for open and close: Lift 320, Rise 280, Return 260 ms, ease-out with no overshoot (`EXECUTION_PROMPT.md:53-64`). |
| **Feedback** | Press, progress, save, Undo | Contact 120 ms, settle 220 ms. Progress Stamp 160 ms. A once-per-session cover reveal on first appearance is allowed (`INSTRUMENT_README.md:118`). |
| **Reduce Motion** | Everywhere | Use `KuroMotion.resolve` or `.kuroAnimation` for a 0.2 s crossfade (`KuroDesignSystem.swift:407-445`). No travel, parallax or finger-tracking. The meaning is the same as with motion on. |
| **Low Power** | Everywhere | Use the still treatment for ambient motion. Feedback motion stays. |

**Forbidden:**
- `KuroAnimation.springBouncy` and `KuroAnimation.editorialBounce` (`KuroDesignSystem.swift:382,389`), or any spring with visible overshoot.
- Continuously animating Home or Profile.
- Asset decoding or network requests per frame (polish plan `:50`).
- New animation frameworks.
- Removing the Profile animation-suppression transaction without checking which mutation or toast animations it protects (polish plan `:112`).

---

## 9. States and the empty/error voice

Every surface distinguishes its real states. A failure, offline state or denial never renders as a successful empty state (polish plan `:73`).

| State | Rule | Example copy (EN / DE) |
|---|---|---|
| **Loading** | Stable geometry: skeletons in `kuroBlack05` with real frame sizes. No spinner-only screens after the first paint. | — |
| **Genuinely empty (selected medium)** | Home shows the invitation (scene, cover line, Find and Import). Hide club furniture; give release info one quiet note (polish plan `:52-73`). | "Your next story starts here." / "Deine nächste Geschichte beginnt hier." (`HomeView.swift:890`); "Dates and club activity appear after you save a title." |
| **Other medium populated** | Keep the selected medium. Show an honest shortcut and never auto-switch (polish plan `:71`). | "Your manga shelf has 4 titles." **[EXTRAPOLATION]** |
| **Caught up / planned only** | Show the saved shelf, not "you have nothing" (polish plan `:71`). | "You're caught up." / "Du bist auf dem neuesten Stand." |
| **No dates** | Say "Dates to come"; never invent a cadence or a midnight time (series plan `:178`). | "Dates to come." / "Termine folgen." ; "Nothing scheduled this week." / "Diese Woche ist nichts angekündigt." |
| **Offline** | Show the last pictures with an honest cached line. Controls queue durably. | "Offline. Showing what you saw last." / "Offline. Du siehst den letzten Stand." **[EXTRAPOLATION]** |
| **Failed refresh** | Inline, scoped to the section, with Retry. Prior data is kept. | "Couldn't refresh Coming up. Try again." / "Konnte nicht aktualisiert werden. Erneut versuchen." |
| **Denied / private** | Clear private content (no stale artwork); explain briefly. | "Club activity is private to members." / "Clubaktivität ist nur für Mitglieder sichtbar." |
| **Missing optional metadata** | Omit the section or show one quiet line. It must never dominate or break tracking (polish plan `:98`). | — |

**Voice rules:**
- Short, plain, true.
- Do not use internal words in the UI: "verified", "approved", "RPC", "bundle", "lifecycle", "server", "projection", "mapping".
- Do not use exclamation marks or apologies.
- Name the action that fixes the state.

Counter-examples found in source or screenshots, to rewrite:
- "No approved season grouping." (`HomeView.swift:1224`)
- "This entry is not in an approved season group." (`SeriesDetailViews.swift:157`)
- "Dates to come. No verified schedule yet." (`HomeView.swift:931`). Use "Dates to come."
- "Chapter boundaries unverified." (`SeriesDetailViews.swift:260,489`). Use "Where the anime ends in the manga isn't known yet." / "Wo der Anime im Manga endet, ist noch nicht bekannt."
- "No verified chapter rows yet." (seen in `native-polish-screenshots/detail-manga-390.png`; the string may no longer be in source)
- `"\(conflict.title) is at \(conflict.serverPosition) on the server."` / "Keep server" (`HomeView.swift:402-406`). Use "on another device" and "Keep that".

---

## 10. Copy tone (EN/DE)

- **Voice:** a quiet personal space. Use short declarative lines and an editorial full stop on cover lines and section heads: "Continue.", "Coming up.", "Between us.", "Your next story starts here."
- Use less text everywhere. The owner asked for "substantially less visible text" (`tools/design-directions/README.md`, "Copy reduction").
- **Medium words:** Anime is "Watching / Episode / Ep."; Manga is "Reading / Chapter / Ch. / Your bookmark" (`SeriesDetailViews.swift:751`). German: "Schaue ich / Folge / F." and "Lese ich / Kapitel / Kap." **[EXTRAPOLATION]** Check that existing DE strings agree before adding.
- **Story copy:**
  - A hook is not the story.
  - Manga premise: about 20-35 words, spoiler-light, then a collapsed synopsis.
  - Anime: a season hook, with a labelled series fallback.
  - A premise appears only for unfamiliar titles (Taste/detail), never under already-watched Home cards (series plan `:53,57`).
- **Never** fabricate people, club messages, activity, dates or scores in the running app (polish plan `:89`).
- **German:**
  - Every new user-facing string ships in EN and DE, using the existing inline pattern `isGerman ? "…" : "…"` (`HomeView.swift:179`; `ImportSourceChooser.swift:30-31`).
  - Use informal *du* ("Zeig Kuro deinen Geschmack", `OnboardingView.swift:158`). Capitalize nouns; otherwise use sentence case.
  - Allow about 30% extra length and verify reflow at 320 pt with the largest text size.
  - Use `de_DE` formatting and Europe/Berlin dates, e.g. "Fr., 9. Okt." for dates and 24-hour times.
- **Numbers:** show real counts only. Unknown totals are omitted, never written as 0 (`INSTRUMENT_README.md:192`).

---

## 11. Icons and brand marks

- **SF Symbols only**, weight light or regular, in ink. Use `plus`, `checkmark`, `list.number`, `xmark`, `magnifyingglass`, `arrow.right`, `arrow.down` and `chevron.down` for disclosure. Use `chevron.right` sparingly: Profile must lose "repeated icon/chevron noise" (polish plan `:112`).
- **No** colored icons, decorative icon circles (as in the 80 pt circles of `OnboardingView.swift:212-219`), glass badges or emoji.
- **Brand:**
  - `KuroMark` asset.
  - The "KURO" header wordmark.
  - The welcome "Kuro" serif.
  - `KuroZenMountains`, the only approved brand scenery. It is used by welcome, empty Home and the Profile band.
- Other assets in `Kuro/Assets.xcassets` have no Swift references (`grep` found only their `Contents.json`): `KuroFlowerBanner`, `KuroStoneLantern`, `KuroAnythingBand`, `KuroSceneryLoop` (imageset) and `KuroZenTV`. `KuroZenTV` is owner-removed and **forbidden**. The others are unapproved: do not introduce them without an owner call.
- **Generated assets:** allowed only as brand atmosphere, never presented as catalogue art and never manufacturing anime characters (polish plan `:60`). Missing-image fallbacks must keep labels and controls working.
- **AppIcon / AccentColor:** `AccentColor` is unset, which means system blue. Controls must set ink explicitly; never rely on the default tint. **[EXTRAPOLATION]** Set AccentColor to `#181818` when touched.

---

## 12. Accessibility

- VoiceOver separates the title action from the progress action. Example labels:
  - "Open Cowboy Bebop".
  - "Mark episode 12 of Cowboy Bebop watched, 11 of 26".
- Selected, current and pending states are exposed as traits or values. Section headers get `.isHeader`.
- Artwork is decorative (`accessibilityHidden`) unless it is informative (polish plan `:143`).
- Focus returns to the originating control after dismissal (`INSTRUMENT_README.md:266`).
- Color is never the only indicator, including for season and status (series plan `:255`).
- Run the contrast table in §3.1 for every text-on-art combination. On bright art, add a localized neutral contrast layer (polish plan `:56`).
- Never compress targets under large text; reflow instead.

---

## 13. Forbidden (all lanes)

**Palette**
1. Cream, ivory or yellow page tints (`#FFFEF8`, `#fffef8`, `#F6F4EF`, `#fffefa`), and green-grey ink or stroke hexes copied from the prototype.
2. Colored statuses, dots, pills or badges, and a rainbow per title. Red is used only for destructive actions and errors.

**Composition**
3. Offset, masonry or unequal Manga frames; the Crosscut layout; a selected-book workbench; repeated Open rows; image-select/text-navigate splits.
4. Season-number rows on Home, boxed season rails, and season art borrowed from another title.
5. Decorative ordinals or numbered contents ("01/02/03").
6. Generic discovery rails disguised as personalized Home. Suggestions belong on Taste and Discover (series plan `:46`).
7. A dominant medium selector, nested decorative frames, or big empty utility boxes. Native counter-example: the 9 October "Your progress / Your bookmark" grey box with −/+ and "Go to episode / Save" (`detail-*-390.png`; polish plan `:96`).
8. Glass/blur blobs, bevels, domes, faux hardware, and toy-like depth (series plan `:55`; polish plan `:112`).

**Motion and assets**
9. Bouncy springs, continuous animation outside the two scenery surfaces, scenery spread into Discover, Collection or Clubs (issue brief `:49`), and autoplay audio or video.
10. The Zen TV, the rejected v43/v47 generated switch art, and World study art.

**Content and data**
11. Fabricated data in the app: fake people, comments, dates, totals or activity. No public comments and no public friend graph.
12. Internal-voice copy (§9) and English-only new strings.

**Code**
13. `UIScreen.main`, `KuroScreen.width`, `ResponsiveLayout`, `KuroRadius.adaptive(…, for: KuroScreen.width)`, hardcoded 393 pt widths, and fixed `.system(size:)` text without Dynamic Type.
14. Hex literals in views. Add a token instead.
15. A second navigation system, second detail stack, second Supabase client, or SDK imports in views (CLAUDE.md Rule 4).
16. Silently changing the medium switch typeface, the welcome composition, or the empty-Home invitation copy.

---

## 14. Per-screen direction

Headers mark provenance. Anything not cited is **[EXTRAPOLATION]**.

### 14.1 Home [APPROVED composition; CURRENT, ACCEPTANCE OPEN natively]

**Order** (series plan `:212-214`):
1. Header (KURO, HOME with pager dots, search, profile initial).
2. Poster medium switch.
3. The **Coming up** ink row: a kicker, a serif status line ("Nothing scheduled" / "Dates still to come" / "N this week"), a down arrow, and a full ink rule. One target; it scrolls to the calendar and moves focus.
4. Current titles.
5. The full calendar.
6. The private club room, only with real notes.

**Empty selected medium:** the mountain invitation, with the picture pinned under the status bar and a clear header (`CURRENT_APP_STATE.md:19590,19602`).
- Find routes to Discover for that medium (`:19594`).
- Import opens `ImportSourceChooser` (AniList, MAL file, MAL account with real availability).
- One full-phone wash eases out at the bottom; there is no hard cut (`:19594`).

**Anime populated:**
- Lead titles are shallow scenes with a white ink foot (title left; "Ep. N / total" plus a light raised plus on the right).
- Season tab on the art. Use the compact "Also watching" pair below for the rest.
- Pagination comes from bounded cards plus load-more; never assume six (series plan `:214`).

**Manga populated:** equal covers with each book's own chapter position and dark raised plus. The cover/title opens the detail; the key is a sibling.

**Calendar:**
- Grouped by local date. Same-day expansion. "Dates to come" is kept separate.
- Must handle 100 or more events.
- No grey cards (`CURRENT_APP_STATE.md:19574`). Use hairline rows and ink type.
- The prototype's boxed calendar container is not to be copied in grey: it becomes hairlines on white **[EXTRAPOLATION consistent with :19574]**.

**Club room:** a dark neutral room (§3.2) with the club identity, member initials, one pull-quote card and spoiler-hidden notes. It appears only when authorized real items exist.

**Lane must fix:** the §3.2 hex leftovers, the §4 fixed sizes and the §9 copy.

### 14.2 Detail: Anime and Manga [APPROVED order; native first pass, ACCEPTANCE OPEN]

**Anime** (series plan `:218-222`):
1. Shallow wide art with a close circle.
2. Compact title and status.
3. Selected-season hook, with an optional story disclosure.
4. **Season artwork panels**: the selected panel gets an ink underline; the tracked season gets a bookmark marker. Selected and tracked are distinct.
5. The selected-season unit list: the next unit leads with a separate 44 pt completion key; completed rows recede (`INSTRUMENT_README.md:57`).
6. Source / continuation.
7. OP/ED links: verified URLs, or an explicitly labelled "Find on Spotify" search. Never autoplay (series plan `:174-175`).
8. Cast and principal creators.
9. **Between us.**

**Manga** (`:224-228`):
1. Book art and title.
2. True premise, then a collapsed story.
3. **Your bookmark**: exact chapter or edition, a concise control, and a next chapter.
4. Paged chapter list.
5. Genuine volumes or editions only.
6. **"I've watched the anime"** read-only guide.
7. Compact credits.
8. **Between us.**
9. No manga music and no fake parts selector.

**Tracking control:** replace the large grey utility box with a concise inline control.
- The number beside the unit name, with −/+ keys of 44 pt each.
- "Go to episode N" is an explicit editor with Save.
- Make the difference between an immediate advance and an explicit Save legible (polish plan `:97`) **[EXTRAPOLATION of form]**.

**Rules:**
- No unit titles that repeat the unit label (native shows "Episode 1 · Episode Episode 1").
- Missing metadata is concise.
- No eager irrelevant fetches; no franchise fetch when switching a panel (series plan `:220`).
- Carry Home's displayed artwork and material into the detail (polish plan `:93`).

### 14.3 Profile, and where the lists live [polish plan :101-112 APPROVED structure; list visual EXTRAPOLATION]

**Order:**
1. **Identity opening.**
   - A compact initial and real account identity. Do not make the raw email the headline.
   - A restrained mountain band, still or slow under the drift rules.
   - Not "Your account" / "Discover, track, enjoy." (`ProfileView.swift:234,268`); that is the generic label the plan rejects (`:18,105`).
2. **Your Library.**
   - A quiet line of real Anime, Manga and Completed counts. Three large figures are the current native state.
   - **[EXTRAPOLATION] Shelf preview:** per status (Watching/Reading, Planned, Completed), one row of up to 6 equal covers at 56-64 pt width. Tapping a row opens Collection filtered to it. "Open Collection" leads to the full shelf.
   - Never label current progress sums as lifetime history.
3. **Imports and connections.** One group: AniList, MAL account, MAL file. Show only relevant state (no Disconnect when nothing is connected). Pending and resumable imports are visible.
4. **Clubs.** A compact route.
5. **Preferences.** Provider preferences are flag-conditional.
6. **Account and privacy.** Sign out; Delete in red with the existing confirmation; Privacy; Version. Cache maintenance goes under a quiet "Advanced" disclosure.

**Rows:** common geometry (serif title 17-19 pt with a sans subtitle in `kuroInkSecondary`), hairline separators, and no chevrons on every row. Utility rows stay still.

### 14.4 Collection: the list experience [Sept 26 APPROVED content; issue brief frame; layout EXTRAPOLATION]

**Content:**
- Visual shelf with quick progress.
- Clear **Watching/Reading, Planned and Completed** states; Paused and Dropped are secondary.
- Optional named shelves, where one title can sit on several and deleting a shelf keeps history.
- Search covers unloaded records (`CURRENT_DECISIONS_AND_AUDIT.md:21-22`).

**Frame:** picture first, title, at most one line. +1 stamps in place on current titles (issue brief "Product pages" table).

**[EXTRAPOLATION] Proposed "easy list" design:**
- Header: the medium word switch (the same Poster control as Home, for one mental model).
- A typographic status line ("Watching 12 · Planned 40 · Completed 85") as a scrollable word strip with an ink underline mark.
- Two densities, chosen by a single toggle:
  - **Shelf**: equal covers for manga and shallow scenes for anime, adaptive columns per §6.
  - **Index**: 64 pt rows with a cover thumb, title, progress numeral and a 44 pt key.
- Sort uses words (Recent, Title, Score, Next release), never icons alone.
- Batch selection uses the existing batch bar.
- No colored pills, and no score grids in the frame.

### 14.5 Discover [Sept 27 issue style APPROVED, palette superseded; native code absent; EXTRAPOLATION for native]

**Current native:**
- The "One Thing" hero: a 4:5 crop with a glass panel, tracked eyebrow, serif title and argument (`DiscoverOneThingCard.swift:3-10,22-24`).
- Rails.
- The `discover_realm_rails_v1` Shelf/Hidden Gem rails behind a flag at 0%.

**Direction:** issue frames on white (§3.1).
- The lead frame keeps its full-width picture plus a title and at most two short sentences. Other titles use the same frame, smaller: picture, title, one line.
- The jacket color (`cover_image_color`, clamped per §3.3) may form the field under the type. No glass panel (polish plan `:112` direction against excess glass), no score chips, no genre pills in frames.
- Search is reachable from Discover, and the header search icon opens the same implementation (series plan `:44`).

**[OPEN]** Whether to keep the One Thing hero or move to the issue lead.

### 14.6 Search [EXTRAPOLATION from the issue brief and series plan :44]

- A sheet opened from the header magnifier. Scope is the selected medium by default and can be changed.
- Results are picture-first frames, or 64 pt index rows for long lists. Refinement chips become ink words with an underline mark (TRENDING, NEW, CLASSICS, HIDDEN GEMS, AIRING).
- Empty query shows recent searches. No results: "No titles match '…'." / "Keine Titel passen zu „…“."
- When Search is reached from Find on the empty Home, open it pre-scoped to that medium.

### 14.7 Clubs [series plan :51 APPROVED identity; list screen EXTRAPOLATION]

- Clubs are private (2-20 members). Never show a public network, public comments or fake rooms. Label a shared-club audience honestly (series plan `:51`).
- **Club list:** each club is an inhabited card made from real artwork of its current rail titles. It shows the club name (serif), member initials and one real recent line, or nothing. Show an unread mark as an ink dot, never a colored badge **[EXTRAPOLATION]**.
- **Club detail:** keep the existing 3 tabs (Rails / This Week / Polls). The dark neutral "room" treatment is the club's identity surface. Notes go on light cards inside it. Spoilers are hidden until tapped.
- **Empty:** Create and Join (invite code) as two invitation actions (§7) **[EXTRAPOLATION]**.

### 14.8 Welcome, sign-in/up and onboarding

**Welcome [APPROVED, frozen]:** `AuthView.swift:143-235` matches `b943e457` except for the `AuthSceneryLoop` → `KuroSceneryLoop` extraction (diff checked).
- Scenery band at 52% of height plus the top safe area, masked with a gradient.
- "Kuro" serif 18 semibold with tracking 4.
- Headline 33 pt medium serif, centred.
- "Get started" ink capsule 54 pt, Apple capsule 54 pt.
- Terms line 11 pt.
- **Do not change it.** **[OPEN]** The headline is anime-only ("Your next favorite anime, already waiting for you") although the app covers manga too.

**Email / sign-up / sign-in form [layout OPEN per `CURRENT_DECISIONS_AND_AUDIT.md:17`]:**
- Keep the curtain-rise transition (`AuthView.swift:70-75`).
- Use ink capsules (52-54 pt), sans 17 pt fields with `kuroCanvasQuiet` fills, and inline validation in `kuroInkSecondary`.
- **[EXTRAPOLATION]** Replace the form's red accent `#A02823` (`AuthView.swift:54`; used on the tab underline and "Forgot password?") and its blue focus ring (`AuthView.swift` focus colors) with an ink underline or ink focus, because red is reserved for destructive and error use. Branded: the same "Kuro" serif and the scenery visible behind the curtain.

**Onboarding [no approved design; current copy stale]:**
- `OnboardingView.swift:155-200` describes Taste-as-yes/no-deck, Discover, **Browse**, Collection and Clubs, in 80 pt icon circles.
- The live series-home pager is `[.taste, .home, .discover, .collection, .clubs]` (`ContentView.swift:144`), and Taste is now picks (`CURRENT_APP_STATE_PLAIN.md`, "Taste shows a few titles").
- It is presented as a `fullScreenCover` (`ContentView.swift:164,530`).
- **[EXTRAPOLATION, OPEN]** Either drop it and let the empty-Home invitation be the first-run experience, or reduce it to at most 3 frames in the welcome language: scenery still, a serif cover line, one sentence, the ink rule and arrow, no icon circles. Their subjects would be Home (medium choice), Find/Import, and Clubs. Persist the chosen medium.

### 14.9 Taste [APPROVED: secondary]

Up to four picks per medium, picture first. A story sentence is allowed **only** on new recommendations, with a separate 44 pt Plan toggle (`CURRENT_APP_STATE_PLAIN.md` Home v14 entry around `:1567`; series plan `:46,57`).

---

## 15. Open owner questions

These block treating an item as settled. They do not block the rest of the rulebook.

1. **Medium switch typeface:** native heavy serif mixed case (`HomeView.swift:228`) versus the selected prototype's heavy sans uppercase (36/30 px).
2. **Welcome headline:** keep the anime-only line, or add a manga-inclusive line under the frozen composition.
3. **Onboarding:** keep it (redesigned to ≤3 frames) or remove it in favour of the empty-Home invitation.
4. **Club room hue:** the green `#252B28` neutralized to `#222222`, or a per-club artwork material.
5. **Discover:** keep the One Thing glass hero, or adopt issue-style frames on white.
6. **Manga Home columns:** native 2-column with the chapter ticket on the art, versus the selected prototype's 3-column Library with the key below. Both have equal frames.

---

## 16. Lane checklist (run before declaring a screen done)

- [ ] Only tokens are used; no cream or green hexes. Ink contrast is ≥ 4.5:1 for every meaningful text, including text on artwork.
- [ ] Renders at 320, 375, 390 and 430 pt and on iPad with no clipping or overlap, at the default and the largest accessibility text size. German is checked.
- [ ] Every control is ≥ 44 pt. Title and progress are separate targets. Pager swipe never opens a title.
- [ ] Reduce Motion and Low Power produce a composed still. No ambient motion outside welcome and the empty invitation.
- [ ] Loading, empty, caught-up, offline, failed and denied states are all distinct, with honest copy and no internal words.
- [ ] No fabricated data. Unknown totals and dates are omitted or shown as "Dates to come."
- [ ] Every new string ships in EN and DE.
- [ ] No forbidden API (§13) and no new animation framework. Data access stays in owners; views read via `@Environment`.
- [ ] Before/after screenshots are recorded. The work is labelled "acceptance open"; it is not owner-approved.
