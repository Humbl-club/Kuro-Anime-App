# Kuro editorial directions — local prototypes

**Latest reference study:** `boring-study.html` collects official !Boring screens, six animated interaction breakdowns and publisher videos. Selected visual ideas are applied in the current Home study. This directory contains 66 files. Public access covers only the approved board, Home and sample artwork for the original 12-hour window.

**Latest study:** Home v29 uses the selected Artwork tab: white Season N on main images and S-number on compact covers, with no numbered rows. Full overview remains on tap. Backup: `/tmp/kuro-home-v28-before-artwork-selection/`.

**Latest:** [Selected artwork season treatment](http://127.0.0.1:8803/instrument.html). The [comparison board](http://127.0.0.1:8803/instrument.html?seasons=compare) retains earlier options and marks the simplified Artwork tab selected. Liked details preserved. Browser fixture only.

Run from the repository root:

```sh
python3 -m http.server 8803 --bind 127.0.0.1 --directory tools/design-directions
```

Open http://127.0.0.1:8803/. No dependencies, API keys or build step.

## Compare

- **The Edition:** publication hierarchy, a lead image and short dispatches.
- **The Index:** Swiss sans-serif structure, compact covers and release timeline.
- **The Gallery:** intact lead covers, asymmetric compositions and more space.

Switch Home/Taste and Anime/Manga across the three. Open a title, change list status, add/remove with Undo, increment progress with Undo, or open sample club activity and reveal a protected comment. Reset clears the in-memory demo state; reloading also resets it. Scroll inside each phone to inspect its whole page.

## Research and product decisions represented

The qualitative findings in `docs/research/2026-09-25-anime-tracking/RESEARCH_AND_DECISIONS.md` motivate visible progress controls, recoverable list actions, separate episode/chapter semantics, followed-title releases, a bounded recommendation selection, and club-scoped activity. These prototypes compare composition; they are not evidence that any layout increases retention.

The short editorial descriptions explore the critique/voice direction from `docs/superpowers/specs/2026-08-04-realm-repair-and-critique-plan.md`. The copy here is authored sample copy, not a fetched or verified critic verdict.

## Boundaries

These are HTML design studies, not SwiftUI or a live account. Dates, list state, recommendation reasons, club members and comments are illustrative. Cover assets are public catalog artwork; `art.json` records their source URLs. No authentication, database writes, haptics, notification delivery, persistent storage or native swipe gestures are implemented. Profile is outside this comparison. Core screens beyond Home/Taste/title/club activity remain in the existing screen canvas.

## Verification — 2026-09-30

Browser-checked: Home/Taste switching; separate Anime/Manga progress; synchronized +1 and Undo; add and Undo; list status selection; title-to-club transition; explicit spoiler reveal; closing with button and Escape; replacing a panel in another phone without duplicate panels; reset; all Home images loaded. No browser console errors observed. Home and Taste visually inspected. Native app source, backend, deployed state and existing canvas were unchanged.

## Copy reduction

User feedback: substantially less visible text. Removed feed explanations, duplicated introductions and comparison essays; retained essential labels, a brief Taste phrase and expanded title copy. This supersedes the initial verbose presentation.

## Folio — composition revision

Open http://127.0.0.1:8803/folio.html. User rejected the initial concepts as generic even after text reduction. Folio compares three related screens (Home, Taste, Title), rather than three restyled feeds: offset numbered cover plates, an interactive progress-mark strip, compact upcoming cover spines, and a staggered Taste contact sheet. Same local assets and fixture-only boundary. Controls include next current title, title selection, progress/Undo, save/Undo, status, medium switch and protected club notes. No claims of user validation, backend integration or native haptics.

## Personal Home — supersedes the numbered Folio

The user rejected decorative numbering and the generic composition. `folio.html` now shows two coordinated Home previews (Anime and Manga), with Returning / Caught up / New here sample states. All decorative ordinals, padded progress counts, tick marks and selection numbers were removed. Episode/chapter values remain meaningful tracking information.

Home hierarchy: an active title paired with a tracking bookmark and immediate progress action; a second current title; a short release horizon restricted to followed titles; one club conversation with a cover fan; a quiet route into Taste. Caught up compacts the current titles; New here offers finding a title/import instead of pretending to have personal activity. Manga retains chapters, volume language and edition distinctions. The composition uses image/text balance and state changes rather than oversized cover-first headings.

Research rationale: the qualitative tracker research emphasizes convenient progress, awareness of followed releases, manga-specific semantics and private spoiler-safe social context. This is a design hypothesis, not evidence that the visual treatment improves retention. A full source-verified news feed, recommendation engine, import connection, native gestures/haptics and backend persistence are outside this HTML study. Release details and all activity are explicitly samples.

Browser verification: marking progress changes availability to Up to date and Undo restores the count; Anime updates leave Manga alone. My list, title, release and club panels open; comments reveal only on action. The first-visit title offers Save rather than preexisting progress. Save/Undo and import-preview boundaries checked. Returning, Caught up and New here inspected visually. Original SwiftUI app and hosted data unchanged.

## Artwork clarity and direct interaction

The original covers are only 230 px wide. The catalogue importer requests AniList `extraLarge` but persists `large`. A direct extraLarge lookup returned HTTP 403 during this prototype pass, so it was not retried or represented as successful. Instead, four existing public catalogue banners were bundled locally: 1800–1900 px wide. `art.json`/`art.js` record banner sources. Main art uses these banners; compact covers retain native proportions, and no AI upscaling or artificial sharpening was used. Full-size cover quality remains a future native source-ingestion consideration.

Current-title artwork now switches by thumbnail tap, horizontal pointer swipe or left/right keyboard keys. Both visible current titles retain direct progress controls. The main progress action animates its check, announces success and offers Undo; reduced-motion removes those animations. Title detail carries the same banner/cover combination. No blur or animation is applied continuously. Native haptics and touch-device feel are not verified by this browser prototype.

Verification: browser thumbnail switch, physical pointer drag, keyboard switch, correct selected-title progress, Undo, unchanged Manga progress after Anime updates, and title detail checked. Rendered main banners measured 307 CSS pixels against 1800/1900 source pixels in the current viewport. No browser console errors observed. Four local images added; folder now 17 files.

## Panels — alternate composition, awaiting review

The user rejected the latest Home as insufficiently creative. Added `panels.html` as a deliberately different proposal, preserving `folio.html` for comparison. The same jobs (continue, releases, club context) are arranged as a restrained manga spread: two unequal image panels with their own immediate progress controls, a compact release band, and a contextual club note embedded in the artwork. Decorative ordinals remain excluded. The editorial appearance is a design hypothesis, not validated user preference or evidence of retention.

Both current titles are reachable immediately, without cycling the main image. Title taps open details; the plus control updates only its title, with Undo. Club notes stay scoped to the illustrated title and spoilers require explicit reveal. Taste has two illustrative unsaved picks, rather than recycling current titles as recommendations.

Added two high-resolution club banners (1721px and 1900px), with provenance in art.json/art.js. Existing smaller covers remain used at compact sizes; the earlier extraLarge cover limitation remains. Folder now has 20 files. Browser checked progress and Undo, medium isolation, title routing, club spoiler reveal, saving with Undo, and local image loading. Native app, hosted data and release state unchanged. Native gestures/haptics are not claimed.

## One Home, distinct Anime and Manga layouts

User correction: changing images and episode/chapter labels inside the same layout is insufficient. `panels.html` now defaults to a single shared Home shell with a persistent Anime/Manga control. `animeHome()` and `mangaHome()` are different compositions. Anime uses a landscape scene with an episode action, another current show, a chronological release rail and a group-viewing prompt. Manga uses a cover plus bookmark/progress leaf, switching between current books, edition/language-oriented releases and a margin-style club note. Neither is a reader or player. No fictitious chapter totals or edition ownership are implied.

Shared: navigation, typography, neutral colors, spacing, detail/list sheets, save and progress confirmation with Undo. Compare layouts is an optional review tool, not an app feature; single preview is the default. Only the medium preference persists in this localhost prototype (`kuro-home-study-medium`); sample progress still resets on reload. No real application preferences are changed. Native haptics remain untested.

Browser verified: default single preview, medium remembered after reload, structurally absent reading desk in Anime, chapter update/Undo, switching reading titles, independent episode progress, restoring the selected reading title across a medium switch, optional comparison, all images loaded and no console errors. Existing source-image-resolution limitation still applies to portrait covers. Prototype folder remains 20 files; no app source/backend/release changes. Awaiting user design review.


### 2026-09-30 — Personal context in the Home design prototype

Status: local design hypothesis, awaiting review. `tools/design-directions/panels.html` now derives Home from one coherent fictional account in new `home-profile.js`: list status/progress, saved titles, followed releases, shared-club relevance and manga edition language. Anime and Manga retain distinct compositions. Compact summary, saved-title start, paused-manga resume, follow-filtered releases and an inspectable context panel add useful information without long feed copy. Returning/new-member fixtures are explicitly labelled; no real account connection, recommendation engine or verified release/news feed is claimed. Medium preference alone persists; account changes reset on reload.

Browser checks: episode count responds to progress and caps at sample availability; progress/Undo and start/Undo restore list state, with previous primary title restored; resuming manga retains chapter 12 and Undo restores paused state; German hides English-only releases; unfollow removes the title's release card; a new account has no invented club/continue activity, and saving from Taste creates a personal queue entry. Both layouts inspected; all 13 displayed images loaded and no console errors observed. Cover-only titles avoid landscape stretching. New prototype folder count: 21 files. Original SwiftUI, backend and release state unchanged. Native integration, haptics, real recommendation quality and production behavior remain unverified.

Implementation boundary: the fixture separates account inputs (`HOME_FIXTURES`) from catalogue/release examples (`HOME_EVENTS`). Collection, Recommendations and Social service files were inspected for potential native input mapping only. Collection progress and club context have existing service surfaces; a production Home aggregation contract, release provenance/coverage, news relevance and loading/error behavior still require native/backend design and verification. This change does not connect those services or change database calls. The four-title-per-medium sample excludes already-listed titles from Taste, so a returning fixture can exhaust it; that is intentionally not presented as a recommendation engine.


## Home in motion — interactive exploration

Added `tools/design-directions/interlude.html` as a separate local Home exploration after the user rejected Panels as boring. Existing prototypes preserved. Anime: swipe/tap/keyboard scene rotation, selected-title progress/release/club context tabs, followed-release appointments and saved/club entry points. Manga: selectable overlapping covers, bookmark progress, edition language and margin conversation. Shared collection/detail drawers, status changes, follow toggles, Undo, spoiler reveal and reduced-motion rules. Reuses existing fictional account/art assets. Only medium preference persists; account mutations reset on reload. Prototype folder now 22 files; native file counts unchanged.

Browser checks covered episode cap and Undo, starting saved anime, medium independence, paused manga resume/Undo, language-empty state, follow removal/restoration (2→1→2 release cards), title-specific empty club comments, spoiler reveal, keyboard navigation and pointer swipe without opening details. Both compositions visually inspected. No backend, SwiftUI, auth or deployment change. This is an unapproved design study, not real-account, retention, native-haptics or production proof.

Open http://127.0.0.1:8803/interlude.html. Try swiping the Anime artwork, selecting a thumbnail/book, switching the three title-context tabs, resuming Berserk, changing edition language, opening the collection, and changing follow/status with Undo. Compare mediums is a review control only. There is no new-account demo in this variant; the previous Panels prototype retains that exercise. The four-title sample and dates are illustrative, not an actual recommendation or release service. No new artwork was generated or ingested. Portrait-source resolution limitations remain.


### 2026-09-30 — Multi-title, image-led vertical Home

User rejected Interlude's selected-title hero, overlapping books and Your Place/What's Next/Club tabs. Added `tools/design-directions/flow.html` as a separate local study; prior files preserved. Home is a continuous vertical feed with four active titles per medium, independent progress controls, follow-filtered release groups (three concurrent releases plus two later), separate new-release grids (two Anime, three Manga), and club imagery. No context tabs, carousel selection or modal navigation. Optional details expand inline. Anime uses compact landscape mosaics; Manga uses full cover/bookplate pairs with progress beside each cover. Group renderers map their full supplied arrays; no one-title-per-day or slice cap. Native scrolling, sticky day headings and reduced-motion support; no custom wheel interception.

Browser verified: 4 current titles, release groups [3,2], new grids [2 Anime/3 Manga], zero context tabs; progress caps with Undo and unchanged other-medium progress; saving/Undo; German missing-edition state; unfollow removes both relevant scheduled events (groups [2,1]) and Undo restores; detail opens inline with zero dialogs; all 27 comparison images loaded, no console errors observed. Source JavaScript syntax and diff whitespace checked. Source/local proof only: no SwiftUI, hosted data, auth or deployment changes. Fictional releases reuse existing title artwork to demonstrate layout capacity; they are not actual announcements. Production pagination, real catalogue/release mapping, native feel/haptics, broader accessibility and performance validation remain pending. Prototype folder now 23 files.

Open http://127.0.0.1:8803/flow.html. Compare mediums is an external review control. Anime and Manga selection is the only persisted prototype preference. Progress, saved releases and follows reset on reload. New-release saves are release-level demo state, not native collection writes.


### 2026-09-30 — Three divergent Home composition studies

User rejected Flow as boring. Added `tools/design-directions/studies.html` for a visual comparison using identical fictional personal content: Thread connects artwork along a vertical timeline; Cut interlocks edge-to-edge image frames with paper captions; Journal alternates covers and annotations. Manga has separate cover-led layout rules. External review controls switch Anime/Manga, open a direction at full phone size, or reset samples. Direct URL `studies.html?direction=cut` opens Cut. No in-app context tabs or modal routing.

Each variant renders four current titles, release groups of three and two, two new-release examples and inline club notes. Progress and saved-release state are shared across variants for comparison but independent by medium. Browser checked episode cap/Undo, save/Undo, inline spoiler reveal with zero dialogs, medium isolation, content counts and full-size visual presentation. Samples reuse existing local artwork; no real account or actual-release claims. No new media ingested, no SwiftUI/backend/deployment changes. Design approval, native implementation/haptics, real data and production-scale behavior remain pending. One added HTML file; prototype folder now 24 files.

Open http://127.0.0.1:8803/studies.html for all three, or http://127.0.0.1:8803/studies.html?direction=cut for the full-size Cut direction. Review controls are not app navigation. All state resets on reload; the query parameter only selects a composition.


## 2026-10-01 — Actual reference board

Open http://127.0.0.1:8803/references.html. Eight official App Store promotional screenshots from MUBI, Cosmos, Sofa and Sequel can be enlarged. Sources are linked directly. Images remain on Apple's CDN and need internet; no external media bundled. Prior Home studies are rejected/unapproved, not a baseline to implement. Mobbin's public site was reachable but its library was not accessed. The board separates visual inspiration from tracking patterns and does not claim native interaction or retention testing. Image loading and enlargement/close verified. Folder now 25 files.


## 2026-10-01 — Personal Home prototype

Open http://127.0.0.1:8803/journal.html. This is a new prototype based on the reference discussion, not the rejected Journal composition inside `studies.html`. Start with Busy, then compare Quiet, New member and Missing information. Simulate save failure verifies unchanged state. Tap artwork, mark progress, Undo, save a suggestion, start watching/reading from details, and reveal a club spoiler. Single phone respects the selected medium; comparison is a review tool. All account mutations are temporary; only medium preference persists. Header navigation/profile are visual context, not additional implemented pages.

Four source files separate markup, presentation, behavior and fixtures. Ten additional catalogue artwork files have provenance in `journal-data.js`; all artwork is locally served. Catalogue identities are real; release labels/dates and user/club activity are fictional. No authenticated network calls or hosted writes. Browser-checked main/failure flows, first-use, multi-release groups, 390px layout, image loading and console errors. Original SwiftUI app unchanged; native haptics and shared-image animation remain future work. Folder now 39 files.


## 2026-10-01 — Living world

Open http://127.0.0.1:8803/world.html. This is the explicitly requested radical spatial experiment, independent of the previous editorial studies. Default comparison has Anime night islands and Manga paper terrain. Mouse-drag blank terrain or scroll; zoom +/−, Overview and recenter are functional. Tap artwork for details, increment progress, finish a title, and Undo. Use Arrivals for concurrent release groups and separate new releases. Open discovery, Add, then Visit to locate the new place. Titles provides direct location lookup. Club comments have spoiler protection. New member has no invented history or social relationships; Fail next save leaves state unchanged.

Authored backdrops created with built-in image_gen are at `assets/world-landscape.png` and `assets/world-paper.png`; full prompts are in `world-art.json`. Existing title artwork is reused from `journal-data.js`. All media serves locally; no API/auth calls or production writes. There is no procedural world generation: additional title markers extend below the fixed illustration. Scenery and sample recommendations do not prove personalisation. Release dates, progress and social activity are fictional. Medium preference persists; mutations reset on reload.

Verification: per-title progress and cap, medium isolation, failure, Undo, add/find/start, finish/Undo, empty account, clubs/spoilers, [3,2] release groups, physical pointer pan, zoom/overview/recenter, 390px viewport layout, images and source checks. Reduced-motion supported in CSS. Native touch, pinch, haptics, audio, large collections and full accessibility validation remain future work. Prototype folder now 45 files; six added in this initiative. Original SwiftUI app unchanged.


## 2026-10-01 — Modern Home options (current comparison)

The living-world experiment above was explicitly rejected. Open http://127.0.0.1:8803/modern.html for three options using the same six titles and three initial updates. Shelf gives covers priority; Screen pairs scene artwork on graphite (intact Manga covers); Today gives updates priority. Use Open full size, or direct links `?view=shelf`, `?view=screen`, `?view=today`. Switch Anime/Manga with the review selector or inside a phone. Scroll each phone for grouped followed releases, separate new releases and club commentary.

Progress is synchronized between variants, independent per medium, capped and undoable. Tap artwork for details, save a release and Undo, reveal club spoilers or simulate a failed save. Only `kuro-modern-medium` persists; mutations reset on reload. Header navigation/profile are context only. All account activity, release labels and dates are fictional. Artwork and its source references reuse `journal-data.js`; no API/auth/backend integration. Three source files added, folder now 48 files.

Verified: six active titles each, release groups [3,2], loaded images, progress/cap and update count synchronization, medium isolation, Undo, failure leaves state unchanged, detail/Escape, save/Undo, spoilers and 390px responsive layout. Native haptics, real-account integration, empty/large-account coverage for these variants and full accessibility validation remain pending. These are unapproved local options, not native app changes; the dark option does not change the native light-only design system.


## 2026-10-01 — Aperture Home / artwork medium switch

User rejected the modern comparison as insufficiently creative and explicitly requested a different top switch/visual. Added `tools/design-directions/aperture.html`, `aperture.css`, `aperture.js` (design folder 51 files). Prototype replaces medium tabs with a single full-width artwork selector: tap or horizontal pointer swipe changes medium; selected medium persists separately. Anime uses staggered frame compositions; Manga uses open-volume layouts with intact covers and margin progress. Six active titles per medium, follow-release groups [3,2], new releases and protected club commentary remain continuously scrollable. Existing sourced artwork is reused; data is fictional. No native/backend changes.

Local browser verification: tap and pointer-swipe switch, independent medium progress, caps/Undo, failure leaves progress unchanged, in-dialog progress/Undo feedback, save/Undo, spoilers, six-title capacity, [3,2] release groups, image loading, 390px no horizontal overflow, no captured console errors; JS syntax and diff checks. Native touch/haptics, empty/large accounts, full accessibility review, backend integration and user design approval remain pending. Header navigation/profile are visual context only. Mutations reset on reload; medium alone persists. Prior variants and unrelated source preserved.

Open http://127.0.0.1:8803/aperture.html. Only `kuro-aperture-medium` persists. Desktop failure checkbox simulates one rejected write. Native light-only styling remains unchanged.


### 2026-10-01 — Aperture material and interaction polish

Refined existing `tools/design-directions/aperture.css` and `aperture.js` at the user's request. Anime has inset translucent mounts, cutout seams, layered shadows and recessed progress buttons; Manga has paper/cloth-like CSS backgrounds, layered page edges, folded corners and ribbon bookmarks. Medium selector has an inset artwork tray, highlight sweep and swipe-follow feedback. Added press compression, progress spring/ring confirmation, animated progress fill, staggered medium entrances, artwork-origin detail opening and animated close/Escape. Motion is bounded to interactions; no ambient animation loop. Reduced-motion CSS and JS guards are present. No new files/assets in design folder (51 files), no additional copy or native/backend changes.

Browser checked: progress cap, Undo, failed save unchanged state, in-dialog progress/Undo, animated close and Escape, save/Undo, spoiler reveal and 390px no horizontal overflow. Reduced-motion emulation confirmed content animation name `none`; all-animation enumeration was unavailable in the read-only browser scope, so full runtime animation inventory was not verified. Temporary emulation/viewport overrides reset. JS syntax and whitespace checks passed. Native haptics, real device motion/performance, comprehensive accessibility and design acceptance remain pending. Fictional local account only; unrelated source edits preserved.


### 2026-10-01 — Pinterest-informed Aperture palettes

Reviewed actual Pinterest images for editorial mobile, book-app and movie-app layouts, plus burgundy/cream and blue/butter palette grids. Refined `tools/design-directions/aperture.html`, `.css`, `.js` in place: explicit reusable palette tokens, Oxblood/parchment (default), Ink/powder and Olive/butter controls; a compact high-contrast artwork switch, calmer borders/shadows, larger small text, full Anime covers instead of portrait crops of scene banners, simplified Manga page surfaces, and restrained confirmation motion. Removed the prior dense textures/gloss/curls. Palette controls are review UI and remain accessible at phone widths. Palette and medium persist under separate prototype keys; palette changes do not rerender or reset account state. `?palette=ink|oxblood|olive` selects a shareable starting palette. Reference links are in the desktop review panel and design README. Asset query versions avoid stale CSS/JS during local review. Three existing files changed; design folder remains 51 files, no imported reference media.

Verification: palette persistence/reload, progress/cap/Undo across palette changes, failed-save unchanged state, list saving/Undo across palettes, detail/Escape, spoilers, all displayed images loaded, Anime and Manga fit 390px without horizontal overflow, reduced-motion content animation computes to none (temporary overrides reset), JS syntax and diff checks. Calculated secondary-text contrast on the soft release-panel surface: Oxblood 4.84:1, Ink 4.76:1, Olive 4.52:1; these token checks are not a full accessibility audit. User approval/native integration, haptics and device performance remain unverified. Fictional local account; native source/backend unchanged.

#### Pinterest reference decisions

Read-only visual research; no Pins saved, comments posted or reference artwork copied into the product. Pins may be reposts, so links are inspiration provenance rather than proof of authorship or usability. Historical pin dates were not used as trend evidence.

| Reference viewed | Applied to Kuro | Not carried over |
| --- | --- | --- |
| [One Two Dot — winery/hotel mobile](https://www.pinterest.com/pin/11259067814172913/) | Dark burgundy against warm cream; serif accents; deliberate separation of images and controls | Long hospitality copy and full-screen text panels |
| [Cherry × warm ivory](https://www.pinterest.com/pin/16536723628742539/) — viewed in Pinterest result grid | Starting palette relationship for Oxblood | Glossy material imagery |
| [Butter / pale blue palette](https://www.pinterest.com/pin/1125968743879724/) — viewed in Pinterest result grid | Cool powder/ink alternative against a light surface | Literal lifestyle imagery; no claim that palette is proven for app usability |
| [Shahzaib Ahmad — Book Reading Mobile app](https://www.pinterest.com/pin/1122874119603993345/) | Recognisable book covers, concise secondary metadata, distinct action areas | Generic search/banner stack and unrelated author carousel |
| [Giovano Lumoindong — Movie Streaming App UI](https://www.pinterest.com/pin/1024006034026156101/) | Clear action contrast and stronger separation of artwork from information | Streaming controls, bright yellow CTA and dark app baseline |

Olive/butter is our own controlled comparison against the prior olive direction. These are design interpretations, not evidence of conversion or retention. Existing `journal-data.js` retains catalogue artwork provenance. The earlier [reading-settings Pin](https://www.pinterest.com/pin/455848793512742421/) was inspected and not adopted: it depicts a settings-heavy reader instead of the required personal Home.


### 2026-10-01 — Composition diagnosis after palette rejection

User rejected Aperture colours and the broader composition. Added local `tools/design-directions/composition-review.html` with `assets/original-discover-review.png` (copied saved 30 September SwiftUI preview) and `assets/aperture-review.png` (current browser frame); design folder now contains 54 files. Compared official promotional screenshots for MUBI, Cosmos and Sequel; these are visual references, not tested app sessions. Findings: oversized medium control, expensive nested/book containers, and six-title queue burying personal updates. At the measured 412 × 878 scroll area, first artwork starts at 295px; upcoming Anime/Manga sections start at 1363/1692px and club sections at 2166/2495px. Fixture layout measurements are not user-study evidence.

Next-study targets (proposed, not implemented or approved): neutral composition study, compact switch alongside familiar pager, four identifiable active titles plus start of personal updates in the 390 × 844 opening view, multiple releases and club context in the following view; shared controls with distinct media proportions/progress units. Test new, quiet and busy accounts before sign-off. Aperture implementation, native source and backend unchanged by this review. Existing unrelated edits preserved. Local server restarted on 127.0.0.1:8803. Verified five review images load, enlargement/Escape and visual comparison; no release claim.


### 2026-10-01 — New references after MUBI/Sequel rejection

Added `tools/design-directions/reference-atlas.html` (55 design files total), with original externally hosted screenshots, two optional video clips, enlargement/Escape and clearly labelled palette interpretations. New shortlist: Savee July 2026 native redesign (image density/reflow), Family (collection controls/transitions), Not Boring Calculator (material/interaction precision; older reference), Gentler Streak (varied personal recap composition). Read primary product/designer sources and inspected media visually. DICE and Not Boring Vibes/Guava/Sesame also explored; loud Guava and whole-world metaphors not selected. MUBI/Sequel rejected; Cosmos partial only. Existing composition review now labels earlier references superseded and links the new atlas. No current prototype, native/backend or feature-flag changes.

Recommendation is a study proposal, not acceptance: Savee image composition plus Family component craft; selective Not Boring touch feedback; distinct release/club modules informed by Gentler. Palette strips are interpretive relationships, not exact brand tokens or implemented Kuro themes. Native monochrome status controls remain the contract. Browser proof: four reference images loaded, two clips ready and playable, playing one pauses the other, enlargement/Escape, no horizontal overflow at 390px (viewport reset). Demos are publisher media, not hands-on native testing. External media requires internet. Prior dirty work preserved.


### 2026-10-01 — !Boring-led tactile Home study

User explicitly selected !Boring as the strongest reference, replacing the prior Savee/Family lead, then authorized building it. Added `tools/design-directions/instrument.html`, `instrument.css`, `instrument.js` (58 design files total). Local URL: `http://127.0.0.1:8803/instrument.html`. Silver/graphite surfaces, recessed full-cover artwork, dimensional episode numerals and pressable progress controls; compact mechanical medium rocker supports tap, arrow keys and horizontal pointer swipe. Anime has four initial compact dark panels; Manga has four lighter horizontal rows with chapter readouts. Releases follow these four, before the remaining two ongoing items; three tomorrow releases, three later announcements, club context/spoiler protection and two new-release samples. Uses existing local artwork/provenance, not copied !Boring assets. Episode/chapter numerals are real fixture progress, not decorative numbering.

Interaction proof (local browser): known progress cap/disabled control; Undo restores; simulated failure leaves state unchanged; in-detail update/Undo; list save/Undo and detail reflects saved state; spoiler reveal/hide; three-announcement dialog; six active titles per medium; medium persists across reload; pointer swipes both ways; new-account hides active/follow sections, quiet scenario supports caught-up known totals. At 390 × 844, four full active titles and release-section beginning visible in both media with no horizontal overflow. Images loaded; captured console warnings/errors empty. Reduced-motion emulation gives no counter animation and zero switch transition; override and viewport reset. JS syntax/diff checks passed. No native/backend calls or release claims.

Scope limitations: fictional release dates/activity, in-memory mutations reset on reload, only medium persists under `kuro-instrument-medium`; Home pager label/profile are visual context, not implemented navigation. Native haptics, live-account integration, full accessibility/performance audit and user design acceptance remain unverified. Existing original/overnight designs and unrelated Swift edits preserved.


### 2026-10-01 — Instrument composition revision after owner rejection

The first !Boring-led implementation was rejected as superficial. Revised the existing `tools/design-directions/instrument.html`, `.css`, `.js` in place (58 design files, no new catalogue media). Anime now uses one graphite housing with a six-title, three-column contact sheet, full printed covers, attached compact progress keys and on-cover club access. Manga uses a light surface, two-column bound-book objects with page blocks, four initial titles and the remaining two after personal updates. Removed giant episode readouts and individual beveled card housings. A cobalt/graphite rocker, coordinated artwork/key progress response and staggered medium transitions are local design experiments. Three release samples, three later announcements, club spoiler controls and two new-title samples remain. Catalogue art provenance remains in `journal-data.js`.

Reviewed official !Boring [checkbox design rationale](https://notbor.ing/words/the-most-satisfying-checkbox) and [Camera](https://notbor.ing/product/camera), including the Camera hero visually. Applied coherent material and repeated-action feedback principles; did not copy their media or claim a full 3D rendering/native haptic implementation. All actions remain local fixtures. Header pager/profile are visual context only.

Local browser verification: six active titles per medium; episode/chapter cap and Undo; failed save keeps prior value; club-context details; three-announcement dialog; new-account add/Undo with no existing activity; caught-up known totals; images loaded; no horizontal document overflow at 320px or 390px. Reduced-motion counter animation computes `none` and rocker transition `0s`. Captured console warnings/errors empty; JS syntax and whitespace checks passed. Anime exposes all six titles in the opening phone view; Manga prioritizes larger book covers and requires more vertical scrolling. This explicitly supersedes the prior four-title-plus-release-first-fold target. Screenshots are local browser proof, not native/release/acceptance proof. Native haptics, device performance and comprehensive accessibility remain unverified. No native/backend/deployment changes; unrelated edits preserved.


### 2026-10-01 — Home hierarchy and action-depth refinement

Owner feedback now supports the material direction but identifies clumsy sections and controls. Revised `tools/design-directions/instrument.{html,css,js}` in place; inventory remains 58 design files. The six-cover Anime / bound-book Manga compositions remain. Quiet episode/chapter readouts now sit beside separate 44px progress keys, so reading a number cannot mutate progress. Shared action tokens define shallow resting depth, 2px press travel and recessed saved/caught-up states. Capping a title moves keyboard focus back to its artwork (or detail close control) instead of trying to focus a newly disabled button.

Replaced the separate later-announcement dialog with a continuous Tomorrow / Later timeline containing three releases and three visible announced-title rows. Club content now associates the person, progress and comment with the specific title; second sample member activity is visible and spoiler content remains hidden until requested. Recommendations retain cover artwork and show brief original vibe copy. Clear Watching / Reading, Coming up, Sunday Club and For you labels replace ambiguous headings. Fixed desktop device-shell stretching and phone outer-page overflow. Kept catalogue provenance, fixture isolation and distinct medium layouts. No backend or native changes.

Local browser checks: episode/chapter increments and caps, Undo, unchanged progress on failed update, failed list save remains unsaved, recommendation save/Undo, announced-title details, matching club detail context, spoiler reveal/hide, new-account absence of fictitious prior activity, known-total caught-up states, all six active titles and three-plus-three upcoming items per medium. Both media fit 320px without horizontal document overflow; progress buttons remain 44px wide. At 390px visual review covers progress, timeline, club activity and recommendation sections. Reduced-motion counter animation is none and button transition is 0s. No captured console errors/warnings; images loaded, JS syntax and diff checks pass. Emulation reset after verification. Local server was no longer running and was restarted bound only to 127.0.0.1:8803; a fresh browser tab recovered from the stale connection-error document.

Limitations: local fictional account only; recommendation copy is creative fixture copy, not live personalized inference. Native haptics, live/released behavior, comprehensive accessibility and design acceptance remain pending. Earlier first-fold and announcement-dialog descriptions are historical. Current screenshots: `/tmp/kuro-refined-controls.png`, `/tmp/kuro-refined-timeline.png`, `/tmp/kuro-refined-clubs.png`.


### 2026-10-01 — Restrained material and motion finish

Owner explicitly likes member names, Coming up and Sunday Club, but rejects childish depth and heavy controls. Kept those sections and their content/behavior. Refined existing `tools/design-directions/instrument.{html,css,js}`: 32px tonal circular progress faces within unchanged 44px targets; SVG action glyphs; no extruded edges, white keycaps, button travel or gloss; neutral medium indicator without decorative grip; quieter cover shadows/book edges and Sunday Club panel. List saving uses fine borders and tonal selected feedback. Removed progress cover-flips, counter bounce, staggered 3D medium changes and failed-save shake; shortened detail transitions. Dark empty-account actions have explicit legible foreground/background treatment. No new files (58 design files), native code, backend or deployment changes.

Local browser verification: progress cap/Undo and unchanged value on simulated failure; chapter update/Undo; spoiler reveal/hide; new-account save/Undo; both media fit 320px without horizontal overflow and retain 44px targets; 390px visual inspection; six active titles, three releases and three later announcements remain. Reduced motion disables the counter animation and pseudo-element transitions; emulation reset. Images loaded; JS syntax and diff checks pass. Design acceptance, native haptics and real-device performance remain pending. Prior decorative-motion/depth descriptions are historical, not the current presentation.


### 2026-10-01 — Porcelain surfaces and direct medium selection

Owner requested a broader polish of the underlying color, depth, buttons and Anime/Manga switch. Revised existing `tools/design-directions/instrument.{html,css,js}` in place; no new design files (58 remain). Consolidated CSS into one surface system: cool porcelain base, one ink tray for six anime covers, lighter bound-book manga surfaces, gentle contact shadows and a quieter white club panel. Member names, three tomorrow releases, three later announcements, Sunday Club and brief recommendation copy remain.

Replaced the prior small toggle with typographic Anime/Manga labels and a draggable selection rail. Tap and arrow keys also work; horizontal threshold/capture and vertical rejection prevent accidental mode changes while scrolling. Progress actions retain 44px targets and show a real known-total ring; unknown chapter totals have a dashed track with no false percentage. Save controls use filled bookmark confirmation. Removed obsolete illustrative percentage styling. Scoped selector rendering to buttons so medium dataset attributes on containers cannot be mistaken for controls. Reduced motion removes transitions and animated ring updates.

Local checks: 390px visual inspection of both media and club panel; both media fit 320px with no horizontal document overflow and 44px visible progress targets. Tap, bidirectional drag, vertical rejection and arrow switching checked. Episode cap, Undo, failed update preserving prior count/ring, uncapped unknown-total chapter update, new-account save/Undo, club-context details and spoiler reveal/hide passed. Six active titles, three releases and three later announcements retained. Images loaded; captured browser warning/error log empty. Reduced-motion counter animation is none and ring/selector transitions are 0s; viewport/media emulation reset. JavaScript syntax and whitespace checks passed. Screenshots: `/tmp/kuro-porcelain-anime.png`, `/tmp/kuro-porcelain-manga.png`, `/tmp/kuro-porcelain-clubs.png`.

All data/actions are local fixtures; only medium persists across reload. This is an unapproved visual iteration, not native, backend, live-account, haptic, comprehensive accessibility or release proof. No native/backend changes or deployment; unrelated edits preserved.


### 2026-10-01 — Extend the porcelain/ink Home idea

Owner requested continuing the current direction after reviewing screenshots on iPad. Updated existing `instrument.html`, `instrument.css`, and `instrument.js` under `tools/design-directions/`; no files added/removed. Upcoming titles share a white day tray, with time/volume labels beneath artwork. Selecting a cover expands one inline release summary; selecting it again collapses it. Selection uses `aria-expanded` / `aria-controls`, clears on medium/account reset, and survives progress rerenders. Three later announcements stay in the continuous scroll.

Compact title sheets now pair artwork with title/vibe, one progress control, and named club context when entered from a club action. Anime uses ink and manga paper/book depth. Removed duplicate progress readouts. Added exact source-control restoration when a mutation replaces the original DOM node. Club-title touch target increased to 44px and spoiler control uses the shared subtle-depth treatment. Tablet preview shell fits 768px without overflow.

Local browser verification: release open/change/collapse, anime episode and manga volume summaries, progress cap/Undo, failed save leaving count unchanged, unknown-total chapter increment/Undo, new-account detail save/Undo, Escape and close dismissal, exact release-origin focus after rerender. Both media and long-title sheets fit 320px without horizontal overflow; detail progress target 44px. 390px visual checks and 768px document fit passed. Reduced-motion chevron/selector transitions 0s; shared JS animation helper retains reduced-motion guard. Captured browser warning/error log empty; JS syntax and diff checks passed. Emulation reset. Screenshots: `/tmp/kuro-next-release-tray.png`, `/tmp/kuro-next-anime-sheet.png`, `/tmp/kuro-next-manga-sheet.png`.

Prototype scope only: release dates/numbers, activity and mutations are sample fixtures. Screenshots are provided directly in chat for iPad; localhost is still bound to the Mac and no external hosting was created. No native/backend/deployment changes; unrelated edits preserved. Final design acceptance, native haptics and comprehensive accessibility/device-performance validation remain pending.


### 2026-10-01 — Initial Home polish; further flows deferred

Owner corrected the previous scope expansion: polish the initial page's containers, buttons, scroll animations, visuals and hierarchy before developing subsequent interactions. Existing detail/release interactions are retained but were not expanded this pass. Modified only `tools/design-directions/instrument.{html,css,js}` plus documentation; no new design files (58 remain).

Refined the initial Anime/Manga selector alignment and recessed rail; artwork trays use softer layered edges and controlled contact shadows. Titles now allow two lines, including Fullmetal Alchemist, with stable metadata spacing. Each card's progress readout and 44px action share a subtle recessed dock. Manga club badges move onto the cover to avoid uneven metadata heights. Recommendation covers/copy/save controls now share one quiet surface. Lower sections have a clearer spacing rhythm; the slim Home header remains visible with a translucent scroll state.

Native overflow scrolling is preserved. One IntersectionObserver rooted in the phone applies a 10px / 340ms entrance to upcoming/club/recommendation sections once per medium/account mode. Content is never hidden waiting for JavaScript. Rerenders disconnect the old observer and preserve seen-section keys; no repeating animation on mutations. A passive, requestAnimationFrame-coalesced scroll listener toggles the header state. Reduced motion skips entrances and cancels any current Home animation; pagehide disconnects the observer and cancels pending work.

Local verification: 390px visual inspection of both initial Homes and lower Home sections; six active fixtures retained. Known chapter cap/Undo and failed episode save preserving its prior count passed. Club rerender reports settled motion rather than replay. Reduced-motion sections report static, header/progress transitions 0s. Both media have no document/tray horizontal overflow at 320px and retain 44px progress targets; 768px preview fits. Images loaded; JS syntax/diff checks passed. Browser emulation reset. Screenshots `/tmp/kuro-home-polish-anime.png`, `/tmp/kuro-home-polish-manga.png`, `/tmp/kuro-home-polish-lower.png` show Home only, cropped to the app viewport rather than review controls.

No new native/backend/deployment work or claim of final visual acceptance. Scroll verification is local browser evidence, not physical iPad/iPhone frame-rate or native haptic proof. All release/activity data remain fictional fixtures. Unrelated dirty native files preserved.


### 2026-10-01 — !Boring research and approved temporary iPad preview

Added `tools/design-directions/boring-study.html` and `scripts/serve_design_share.py`. Studied official Calculator, Habits, Timer, Weather and Camera pages plus the maker's checkbox breakdown. The board distinguishes observed publisher behavior from proposed Kuro adaptations. Its focus is the initial Home: consistent depth and lighting, complete press/cancel/commit/settle states, image-led hierarchy, direct scrolling, coherent Anime/Manga selection and quiet feedback. Exact reference timings, physical haptics and native frame rates were not measured. No native application, backend, account or Home design changes in this pass; unrelated dirty work preserved.

Temporary public base: https://criterion-vice-contributions-thinking.trycloudflare.com
- Research: `/boring-study.html`; current Home: `/instrument.html`.
- Owner explicitly approved public sharing of only these preview files and sample artwork for 12 hours.
- Started 2026-10-01 14:44 UTC; scheduled stop 2026-10-02 02:44 UTC (04:44 CEST). Availability depends on the Mac and tunnel remaining online. This is not durable hosting or a released app.
- Loopback port 8814; 21-file allowlist; no directory browsing; no repository documents, accounts or backend access. Refresh reads current allowed files. No cron or recurring automation created.
- Official Cloudflare executable resides temporarily at `/tmp/kuro-preview-bin/cloudflared`. Supervisor invocation: `python3 scripts/serve_design_share.py --cloudflared /tmp/kuro-preview-bin/cloudflared --hours 12`. A future public run requires authorization for that run's scope/duration.

Verification: all 21 allowlisted resources returned HTTP 200; `.git/config`, `CURRENT_APP_STATE.md`, encoded traversal to Info.plist, the assets directory and AGENTS.md returned 404. Both public pages returned HTTP 200. At 768px browser width, research and Home fit without document overflow; Home switched to Manga and exposed Currently reading. Reference image loading was checked for Weather/Camera; the embedded checkbox recording played and paused. Browser viewport override reset. Python source compiles. These are browser/HTTP checks, not a physical iPad test. Screenshot: `/tmp/kuro-boring-research-board.png`.


### 2026-10-01 — Build out reference-led initial Home

Updated `tools/design-directions/instrument.html`, `instrument.css`, `instrument.js`, and the research board's implementation notes. No new files; 59 design-directory files remain. Added a shared sliding selector with small film/book material symbols, coherent monochrome surfaces, distinct graphite anime and paper manga stages, and restrained local progress-control depth. Kept multiple active titles, simultaneous releases and club context. Removed the IntersectionObserver/fade-rise entrances; content stays static and readable while scrolling adjusts header depth. Reduced Motion disables transitions and feedback animation.

Press state follows pointer contact and clears on release, movement, cancellation or blur. A movement threshold suppresses the resulting click; keyboard activation remains available. Successful mutations settle locally; failed saves preserve their prior value and show a dashed failed control plus an explicit message. Existing cap/Undo and medium persistence behavior retained. No expansion of subsequent screens or changes to Swift/backend/auth. Native dirty work preserved.

Verification on the public temporary preview: anime cap/disabled state, Undo, failed progress save; manga unknown-total increment/Undo; new-account failed list save, retry and Undo; caught-up state; pointer drag away from a progress action left its count unchanged; horizontal selector drag and keyboard arrows switched medium. Both media fit 320px; progress targets are 44x44. At 768px all artwork loaded and no document overflow occurred. Reduced-motion emulation showed zero selector transition and static sections; emulation reset. Console warning/error capture empty; `node --check` and `git diff --check` passed. Screenshots: `/tmp/kuro-material-home-anime.png`, `/tmp/kuro-material-home-manga.png`, `/tmp/kuro-material-home-releases.png`.

Native touch-event injection was unsupported by the in-app browser. Pointer-drag checks do not establish physical iPad/iPhone gesture behavior, haptics or frame-rate quality. Final design acceptance is pending. Existing public link remains under the original 12-hour approval, ending approximately 2026-10-02 02:44 UTC; no new tunnel, timer or automation created.


### 2026-10-01 — Fluid direction after rejection of raised materials

Owner said the material v8 direction was wrong and selected “fluid and just more creative.” Reworked `instrument.html`, `instrument.css`, and `instrument.js` around a continuous artwork composition. Anime has a three-column staggered rhythm; Manga has wider paired covers. Six active titles appear together in each medium. Removed the shared graphite tray, faux hardware symbols, beveled controls and per-title dial appearance. Thin progress traces and compact 44px actions sit below the covers. Releases share a light date rule; club context and suggestions remain in the same scroll.

Medium switching maps cover positions between layouts with a 460ms transform transition; title/control text settles separately. Rapid switching cancels prior reflow animations. Reduced Motion disables the reflow and CSS transitions. Existing local mutation failure handling, progress caps, Undo, keyboard switching and cancelled-press guard retained. No native/backend changes, no new product flows. Saved the prior study in `tools/design-directions/archive/material-v8/` (HTML/CSS/JS with adjusted local asset references and separate medium preference). Current design folder now has 62 files.

Checks: public preview loaded; anime cap and Undo; failed progress write preserved count; keyboard medium switching; visible intermediate cover transform and settled layout; Reduced Motion reports no cover transform and 0s selector transition; six active entries per medium; 320px layouts have no document overflow and retain 44px progress targets; 768px fits with all artwork loaded. Warning/error log empty. JS syntax and diff checks pass. Screenshot: `/tmp/kuro-fluid-home-anime.png`. Physical iPad/iPhone gestures, native haptics and frame-rate quality are not established by these browser checks; user design acceptance pending.

Previous local/public servers had stopped. Restarted local port 8803 and restored the same approved 21-file public preview, without adding the archive or extending access time. New base: https://checked-hospitals-clocks-asset.trycloudflare.com ; Home `/instrument.html`, board `/boring-study.html`. Supervisor started 2026-10-01 19:05 UTC with only the time remaining until 2026-10-02 02:44 UTC (04:44 CEST). Old `criterion-vice-contributions-thinking` URL no longer resolves. No cron or recurring automation created. Mac/tunnel must stay online.

### 2026-10-01 — Home v10: soft forms and action detail (browser prototype)

Changed `tools/design-directions/instrument.html`, `instrument.css`, and `instrument.js`. Artwork containers have a curved opening for a 44px progress control; only the backing is masked, so cover artwork and touch targets remain intact. Anime uses six staggered compact covers; Manga uses six larger paired covers. New-release actions get stronger monochrome contrast. The selected Anime/Manga surface morphs during direct manipulation, while existing artwork reflow remains cancellable. Confirmation briefly replaces the plus with a check; failed mutations preserve state and offer explicit feedback. Progress traces now measure against their own track, correcting premature apparent completion; unknown chapter totals hide the trace. Releases, recommendations and club notes use related soft shapes with restrained depth. Club-title target increased to 44px. All Web Animations are tracked for cancellation; offscreen covers skip reflow.

Preserved v9 in three files under `tools/design-directions/archive/fluid-v9/`, with corrected asset paths and a separate stored medium preference. Design directory inventory: 65 files. No native, auth or backend edits for this initiative. The public allowlisted prototype URL is https://checked-hospitals-clocks-asset.trycloudflare.com/instrument.html, with the original authorized expiry of 2026-10-02 02:44 UTC (04:44 CEST), dependent on the Mac/tunnel remaining online.

Verified browser fixtures: 16 artwork images load; six active titles per medium; no horizontal document overflow at 320/390/768px; all six progress targets remain 44px at 320px; cap and Undo; failed progress mutation; cancelled selector drag and cancelled progress press; unknown-total chapter increment/Undo; release preview; new-account failed save, retry and Undo; keyboard and rapid medium switching. Reduced Motion produces no cover transforms and a 0s selector transition. Warning/error log empty; JavaScript syntax and whitespace checks pass. Screenshot: `/tmp/kuro-soft-home-anime.png`. These checks do not establish physical iPad gesture quality, native haptics, backend correctness or owner design approval.

Design decisions:
- Shape clarifies the action: a cutout makes room for a progress button without obscuring the poster.
- Contrast communicates priority: new releases use ink actions; ordinary progress stays lighter.
- Motion follows input: switch surface follows the finger, cover positions reflow, successful progress confirms locally. Scroll content does not wait for decorative entrances.
- Information stays honest: an unknown manga total gets a chapter count without a fabricated completion percentage.
- Social context remains attached to a person and title, with spoilers concealed until requested.
- Multiple simultaneous releases share a surface instead of competing for one hero slot.

### 2026-10-01 — Home v11: aligned composition and deliberate controls

Owner requested the studio/reference board in the sidebar and questioned the mismatched banner arrangement. Interpreted that as staggered card rows and inconsistent container corners; aligned active and recommended titles, normalized release/club corner radii, and straightened the club artwork. Preserved curved progress openings and distinct six-title Anime/Manga layouts. Extended cancellable contact feedback to club art/title/secondary rows, release-detail, close and Undo controls. Replaced progress overshoot with a 180ms settle, clarified enabled secondary actions, and made selector dragging use its actual half-width travel. Removed decorative inactive Home arrows. Studio now links directly to `boring-study.html`; reference summary updated.

Changed only `tools/design-directions/instrument.html`, `instrument.css`, `instrument.js`, `boring-study.html`, the design README and required state/plan documentation. No new repository files (65 design files); pre-edit v10 copies at `/tmp/kuro-home-v10-before-refinement/`. Existing local studio tab was stale and was refreshed. Board opened in the sidebar; public preview verified serving v11 with original expiry unchanged. Browser checks: aligned equal-height Manga row pairs, 16 loaded images, no 320px overflow in either medium, six 44px progress targets, cap/Undo, failed progress preserving count, spoiler expand/collapse, no warning/error logs. JavaScript syntax and whitespace checks pass. Screenshot `/tmp/kuro-home-aligned-refinement.png`. This is prototype evidence only, not native haptic/physical iPad or release proof; visual approval remains pending.

Interaction intent for the current Home:

| Element | Purpose | Contact / result | Cancellation |
|---|---|---|---|
| Artwork | Open the title | Slight image compression; title sheet opens on release | Dragging away cancels |
| Progress + | Record one episode/chapter | Button compresses; local check/count confirms; Undo available | Scroll or pointer cancellation preserves count |
| Anime / Manga | Change medium | Selected shape follows drag; covers reflow | Vertical drag never selects |
| Release cover | Show release information inline | Cover responds; chevron and expanded state agree | Same press-cancellation guard |
| Club identity / title | Open that title's club context | Quiet image/text/row response, no bounce | Same press-cancellation guard |
| Spoiler | Reveal or conceal comment | Disclosure mark and expanded state agree | Drag cancels; concealed by default |
| Save | Toggle planned status | Bookmark fills; accessible label changes; Undo available | Failed mutation preserves list |
| Undo / close | Reverse mutation / dismiss sheet | Small local press response | Drag cancels; closing restores focus |

Scope: these controls have browser implementations. Header profile identity is a static preview label; broader navigation remains outside this Home-only pass. Timings are Kuro study choices, not measured !Boring values.

### 2026-10-01 — Home v12: continuous artwork surface

Implemented the proposed Home-only composition in `tools/design-directions/instrument.html`, `instrument.css`, and `instrument.js`. Ongoing covers share one rounded white surface rather than individual masked card backings. Each progress well responds to contact; successful updates add a 620ms edge highlight alongside the count/check. Reduced Motion removes the highlight and transitions. Action targets stay fixed and 44px. Anime keeps a six-title compact grid; Manga retains larger paired artwork. Upcoming groups follow a fine date spine with room for three simultaneous releases. Club artwork, identity and comment share an open composition, and recommendations no longer have separate white backings.

Browser checks: cap at 5, Undo, failed progress preserving count at 4, cancelled vertical drag preserving count, inline release expansion, club spoiler expand/collapse, both media at 320px without horizontal overflow or progress-label/button overlap, six 44px Manga progress targets, and 768px layout with all 16 images loaded. Reduced Motion reported highlight animation none and 0s transitions while the count updated. Warning/error log empty; JS syntax and diff whitespace checks pass. Public URL verified serving v12; original approved expiry unchanged (2026-10-02 02:44 UTC). Screenshot: `/tmp/kuro-home-continuous-phone.png`. Pre-edit v11 copies: `/tmp/kuro-home-v11-before-surface/`. No new repo files (design inventory65); required documentation updated. No native/backend changes or physical iPad/haptic proof; owner review pending.

### 2026-10-01 — Home v13: foreground and ongoing composition

Owner clarified that visual hierarchy and the overall experience needed a substantive rethink. Changed `tools/design-directions/instrument.html`, `instrument.css`, and `instrument.js`: reduced the opening headline, emphasized two available titles with larger artwork, and moved four ongoing titles into a compact two-column layout. Anime gets dark artwork framing and Manga gets light print-like margins. The existing release timeline and open club composition retain different visual roles. All six titles have direct 44px progress controls; compact club shortcuts remain visible over the artwork edge. The new heading derives singular/plural availability from the two featured fixtures and falls back to Keep watching/reading when caught up. Featured slots remain fixed during progress updates.

Browser proof: both media at 320px have no document overflow or progress-label/button overlap; Manga has six 44px progress targets. At 390px, a direct pointer tap updated progress 4→5 and heading 2→1, while all six card coordinates and scrollTop=0 remained unchanged. Semantic browser clicks were observed to auto-scroll 13px before interaction; the direct pointer check separates that automation behavior from app reflow. Undo restored progress/header, failure preserved both, club shortcut opened the correct title context, caught-up fixture disabled all known-total Anime actions, and new-account fixture showed two suggestions with no active cards. Reduced Motion yielded no artwork transforms. At 768px, no horizontal overflow and all16 images loaded. JS syntax and whitespace checks pass; warning/error log empty. Public preview verified v13 with2 featured/4 compact entries; original sharing expiry unchanged. Screenshots: `/tmp/kuro-composition-anime.png`, `/tmp/kuro-composition-manga.png`.

Pre-edit v12 files preserved at `/tmp/kuro-home-v12-before-composition/`. No new repo files (65 design files). Updated the reference summary, README and three required state/plan documents. Native/backend files untouched. Physical-device/haptic feel and owner acceptance remain unverified. This fixture study is not a complete availability ranking algorithm: a production Home must handle additional new titles in the ongoing group and use genuine release metadata.

Composition rationale:

| Decision | User benefit | Constraint |
|---|---|---|
| Two featured + four compact | New content has priority without hiding the ongoing list | This is sample prioritization, not backend ranking |
| Availability replaces Continue heading | Opening answers what changed since the last visit | Count reflects fixture state and handles singular/plural |
| Larger primary artwork, smaller ongoing covers | Varies visual rhythm while retaining recognition | Avoid a single-title hero or extra navigation layer |
| Dark Anime / light Manga framing | Gives each medium an identity within common spacing/control placement | No colored status indicators or ornamental hardware |
| Fixed slot order during progress | The next target stays beneath the user's finger | Do not immediately reorder when a title becomes caught up |
| Compact direct progress + club badges | Frequent actions stay accessible without opening a submenu | 44px targets retained and overlap checked |
| Date spine and open club notes | Time, activity and recommendations have different compositions | One continuous vertical scroll |

Next design review should assess the balance between large foreground artwork and compact list legibility. Acceptance is visual/user-led; passing fixture checks does not establish that this is the final art direction.

### 2026-10-01 — Home v14: story discovery and complete control pass

Owner asked for more deliberate UI across every element and a short story sentence only on new recommendations. Updated `tools/design-directions/instrument.html`, `instrument.css`, and `instrument.js`: recommendations now immediately follow ongoing titles; their cards combine artwork, title, format and a concise premise into one opening target, with separate 44px Plan to watch/read toggles. Planned state is visibly filled and reversible. Ongoing title names now open details with cancellable press feedback; no premise is shown on ongoing cards or their tracked-title sheet. Internal arrows use forward chevrons. Static avatar decoration became plain For Max identity text. New-account content starts directly with recommendations, removing repeated empty-state headings/artwork. Notifications now have a 44px dismiss action that restores focus to the triggering control. Found and corrected four compact cover targets that were39px wide at320px.

Verification: all visible Home buttons in both Anime and Manga meet44px width/height at320px, with no horizontal overflow. Both story layouts retain19–35px between premise and save control at320px. Verified save/remove/Undo, failed save preserving false state, failed progress→retry→cap→Undo, notification dismissal/focus return, full story opening, tappable ongoing title, no tracked-title premise, keyboard Enter/Escape with correct focus restoration, cancelled title drag, release expansion/detail opening, spoiler reveal/conceal, reduced-motion0s story image transition, and768px layout with all16 images loaded. Console warning/error log empty; JavaScript syntax and diff checks passed. Public allowlisted link servesv14; original expiry2026-10-02 02:44UTC unchanged. Screenshots `/tmp/kuro-home-v14.png` and `/tmp/kuro-story-cards-v14.png`. Public verification tab closed to preserve the user's single-tab workspace.

Saved pre-editv13 files at `/tmp/kuro-home-v13-before-story-cards/`. No new repository files (65 design files). Required docs/README/reference summary updated; no native/backend edits. Story copy is four manually authored, publisher-checked fixture sentences, not a production generation pipeline. Physical iPad/native haptics and owner design acceptance remain unverified.

Current control and content contract:

| Surface | Information | Action and feedback |
|---|---|---|
| Ongoing artwork/title | Name and progress; no synopsis | Either opens details; deliberate press state, movement cancels |
| Progress | Current episode/chapter | Single increment, cap, local confirmation, failure preserves state, Undo |
| Recommendation | Artwork + format + one brief premise | Full main area opens title; save remains a separate44px action |
| Planned recommendation | Same premise (not yet started) | Filled Planned button, accessible removal label, reversible toggle |
| Medium control | Two persistent labeled choices | Tap, horizontal drag, keyboard arrows; vertical drag cancels |
| Release | Title, time/volume, grouped date | Inline disclosure, then forward navigation |
| Club shortcut | Shared-club identity | Opens the correct title's shared activity |
| Spoiler | Concealed ending note | Explicit reveal/hide; expanded state matches content |
| Toast | Result and Undo | User dismissal; focus returns to last action, capped action falls back to title |
| Header identity | Plain For Max text | No fake profile button in this Home-only prototype |

Copy rule: one spoiler-light premise, roughly8–12 words; title-specific and concrete, not generic praise. Show on new/unstarted recommendations. Suppress on already-followed entries. Do not invent a personalized explanation such as Because you liked X without actual evidence. Preserve copy/source provenance for later native integration.

Manually paraphrased fixture copy checked2026-10-01 against primary sources:
- Your Name.: [GKIDS](https://gkids.com/films/your-name/) — Two strangers wake up in each other’s lives.
- A Silent Voice: [GKIDS](https://gkids.com/films/a-silent-voice/) — A former bully seeks forgiveness from the deaf girl he hurt.
- Vinland Saga: [Kodansha](https://beta.kodansha.us/series/vinland-saga/) — A young Viking dreams of a land beyond war.
- Dandadan: [VIZ](https://www.viz.com/dandadan) — Two teens test their beliefs in ghosts and aliens.

No live synopsis generation, ranking or database enrichment is introduced by these fixture edits. Publisher copy is research input, not reproduced verbatim as long excerpts.


### 2026-10-01 — Home v15: scenes and printed pages

Owner authorized building the proposed distinct Anime/Manga Home experience. Anime now uses two existing, high-resolution catalog banners in landscape frames, a dark caption dock with subtle artwork-related color and separate episode controls, then four compact ongoing titles. Manga uses an asymmetric bordered reading spread, preserves each cover and its lettering, and places chapter controls inside precise rectangular caption strips. An open-book/scene glyph accompanies each readable medium label; the selected frame changes material while tap, horizontal drag and keyboard semantics remain shared. Six current titles remain directly actionable in each medium without an extra submenu.

Recommendations differ structurally: Anime pairs a panoramic Your Name illustration with an intact A Silent Voice portrait card; Manga uses two cover plates, compact story captions and aligned planning actions. Premises remain exclusive to unstarted recommendations. Anime releases follow a fine chronological line; Manga releases use volume plates and ruled dates. Club context has a restrained Anime surface and a Manga margin/quotation treatment. Short press responses, reversible mutations, failure feedback, disabled caps, explicit spoilers, focus return and artwork-to-detail motion remain implemented. The CSS was consolidated from accumulated historical overrides into one current system. No generated imagery, fake Manga preview panels, autoplay, native haptics, or backend connections added.

Testing found that animating a whole entering section could move a save target during its first tap. Fixed by animating only images inside stationary controls. Retested an immediate offscreen-to-visible save successfully. Reveals occur once per section and medium, do not replay after progress mutations, and respect Reduced Motion. Removed a decorative double rule that could be mistaken for a menu button.

Verification completed in the browser: both media at 320px have no horizontal overflow and no Home button below 44x44; story-copy/save spacing is 11–22px Anime and 12–20px Manga. Tested six ongoing entries, direct title opening, absent tracked-title premises, independent episode/chapter caps and Undo, failed progress preserving count, save/remove/Undo, failed save preserving membership, notification dismissal/focus return, release expansion/detail opening, spoiler reveal/conceal, keyboard Enter/Escape/focus return and cancelled pointer drag preserving progress. New-account fixtures show only two recommendations; all six known-total Anime actions disable in the caught-up fixture. Reduced Motion yields 0s transition and no image transform. At 768px, no page/phone overflow and all 16 images loaded. No console warning/error entries observed. JS syntax, Python source compilation and diff whitespace checks pass. Initial Python bytecode-cache write was sandbox-blocked; the source-only compile passed without needing cache permissions.

Files: instrument.html, instrument.css, instrument.js, boring-study.html, README.md, scripts/serve_design_share.py and the three required root state/plan documents. No new repository files or assets; design inventory remains 65. Before-change backup: /tmp/kuro-home-v14-before-medium-layouts/. Screenshots: /tmp/kuro-home-v15-anime.png, /tmp/kuro-home-v15-manga.png, /tmp/kuro-home-v15-manga-stories.png.

Public preview refreshed at 21:00 UTC to serve the three selected existing catalog banners in addition to the original 21 approved files (24 allowlisted files total). Current URL: https://graduate-sullivan-aside-floyd.trycloudflare.com/instrument.html . Public browser verified v15 and all 16 Anime images loaded, including all three banners. Expiry remains 2026-10-02 02:44 UTC /04:44 CEST; access was not extended. Supervisor session 27617. The previous checked-hospitals-clocks-asset URL was retired. No cron, recurring automation, private repository exposure, database changes or native release. Temporary public verification tab was closed.

These are local/sample-account browser proofs and temporary hosted preview proofs only. Native SwiftUI, physical touch/haptics, live accounts, production ranking/release data and final owner approval remain outside this pass.

Current implementation choices:

| Surface | Anime | Manga | Shared behavior |
|---|---|---|---|
| Opening | Two full-width selected banners, dark caption docks | Asymmetric cover spread, shallow paper edge and ruled caption controls | Two available titles, four compact ongoing entries; stable ordering |
| Progress | Light recessed action beside an episode count | Chapter strip with a rectangular end action | Tap increments once; cap, failure and Undo remain explicit |
| Discoveries | One landscape illustration plus one intact portrait | Two cover plates with concise captions | Unstarted story premise, separate planned toggle, reversible state |
| Releases | Date spine, simultaneous title group | Volume plates, edition labels and ruled dates | Inline disclosure; no submenu needed for the day group |
| Club context | Clear white supporting surface | Margin artwork and restrained typographic quotation | Title-bound context, named members, hidden spoilers |
| Medium selector | Scene aperture glyph and shaded selected surface | Page glyph and precise white selected tab | Both names readable; tap, drag and arrow keys |
| Motion | Brief artwork translation/opacity; smooth control settle | Brief artwork reveal; precise control settle | Controls stationary, cancellation, Reduced Motion |

Artwork contract: catalog covers remain uncropped and recognizable. The three landscape assets are existing catalog banners, not newly sourced episode stills. Their public provenance remains in journal-data.js. No official Manga preview panels were available in this asset set, so no panel content or rights are invented. Future native integration should use approved preview assets when available and retain these cover-only fallbacks.


### 2026-10-01 — Home v16: deliberate polish of the accepted direction

The owner explicitly liked v15 and authorized the full next refinement. Preserved its distinct Anime scenes and Manga reading spread; this is not a new art direction. Six areas completed in `tools/design-directions/instrument.html`, `instrument.css` and `instrument.js`: aligned Manga title/progress/metadata rows using subgrid (with a flex fallback), equal Anime caption docks, quieter inset action materials, clearer compact typography, persistent caught-up/check states with known availability denominators, and a coordinated 320ms medium transition that animates images rather than hit targets. Unknown Manga totals remain unbounded and omit fractions/percentage tracks. Removed a redundant recommendation label.

The interaction audit found that mutations rebuilt the entire feed and title sheet. Replaced that path with `syncActions(k)`: update only affected progress, save state, accessible labels, availability, heading and open-sheet summary. Spoilers likewise change only their own disclosure. Undo retains focus within the replacement result message, and dismiss returns to the source. In-place updates preserve surrounding controls and scroll. Release-detail entrance now fades its copy without translating the next action.

Browser evidence: at390px both Anime captions measure89px including the border, and both Manga title/progress/metadata rows share identical y coordinates. At320px, both layouts have zero horizontal overflow and all visible Home buttons are at least44x44. Compact labels do not overlap progress buttons; recommendation premises retain11–20px before saving in Anime and12–20px in Manga. Tested cap→Undo, failure→retry, independent media, unknown Manga totals, synchronized Home/sheet progress and save removal, notification focus and unchanged scroll (683px before/after save Undo), new-account saving, caught-up fixtures, release switching/collapse, protected club spoiler reveal/hide and correct club context. Keyboard arrows and reload retain the chosen medium; rapid medium switching settles to one selected state with no cover-button transforms. A14px cancelled pointer drag leaves progress at4 and clears contact. Reduced Motion removes transitions and retains completion feedback. At768px, no page/phone overflow and all16 displayed images loaded. Browser warning/error log empty. JavaScript syntax and diff whitespace checks pass.

Files: three Instrument files, reference-board summary, design README and the three required root state/plan documents. No new repository files/assets; design inventory remains65. Backup: `/tmp/kuro-home-v15-before-polish/`. Screenshots: `/tmp/kuro-home-v16-anime.png`, `/tmp/kuro-home-v16-manga.png`. Public browser verified `instrument.js?v=16`, equal caption docks and loaded artwork at https://graduate-sullivan-aside-floyd.trycloudflare.com/instrument.html . Original expiry remains2026-10-02 02:44UTC /04:44CEST, subject to Mac/tunnel availability. No server restart, new public files or extension of access.

Scope and proof: owner endorsement applies to v15 direction, not automatic acceptance of every v16 detail. Native SwiftUI, backend/auth, real-account data, release/news accuracy, physical iPad/Safari behavior and haptics are unchanged/unverified. This is local and temporarily hosted browser-fixture proof only. Required project memory is recorded through the allowed memory extension mechanism, not by overwriting the memory registry.


#### V16 element-by-element intent

| Element | Decision and purpose | Behavior / constraint |
|---|---|---|
| Header | Wordmark, Home and quiet identity text establish location | Sticky separation appears after scrolling; no fake profile button |
| Opening summary | One short availability statement gives the first useful answer | Singular/plural and caught-up fallback; based on sample featured titles |
| Medium selector | Two named targets remain visible; scene material changes to a precise paper tab | Tap/drag/arrows, remembered choice,320ms settle; no moving hitbox |
| Anime artwork | Existing wide banners convey scene and atmosphere | Catalog illustration, not episode-still proof; avoid stretching portraits |
| Anime captions | Matching89px rendered docks create consistent title and action positions |44px title and metadata rows; no extra synopsis on tracked titles |
| Manga spread | Unequal intact covers establish print identity | Shared rows align both titles, chapter strips and social/availability lines |
| Depth | One quiet surface edge separates artwork from the page | Anime action has a shallow inset; Manga action is the end of a ruled strip |
| Current-title names | Names are useful opening targets as well as identifiers |44px minimum; cancelled movement does not open details |
| Progress labels | The count is primary; units and available total are secondary | Known totals on featured/detail controls; no invented Manga denominator |
| Progress action | Plus records one episode/chapter without opening a sheet |120ms contact, small count/trace settle, state cap, failure and Undo |
| Completion | A persistent check and Caught up replace the invitation to increment | Slot order and card height stay stable; Undo restores the action |
| Compact ongoing titles | Four additional titles remain immediately accessible | Larger compact type, fixed48px name row,44px progress row |
| Recommendations | Image, title and a concrete premise make an unfamiliar title understandable | Premise only for unstarted recommendations; removed redundant header copy |
| Plan control | Clear separate action rather than an ambiguous icon over artwork | Filled Planned state, accessible remove label, Undo and explicit failure |
| Coming up | Multiple titles share a visible date group | Anime timeline / Manga volume plates; title detail is an inline disclosure |
| Later releases | Small artwork plus status handles uncertain dates compactly | No fake day precision; fixtures are not actual announcements |
| Club names | Names remain attached to the title to explain relevance | Direct access to the correct shared-club context |
| Club note | Smaller supporting Anime surface / Manga margin quotation | Public-safe density, limited copy and visible source identity |
| Spoiler control | A full-width disclosure makes intentional reveal obvious | Hidden by default; reveal/hide updates locally and retains focus |
| Scroll motion | Motion belongs to newly encountered artwork | One entrance per section/medium; no wheel interception or delayed target |
| Feedback | Local result and reversible action protect confidence | No state change on failure; Undo focus remains valid; dismiss returns focus |
| Narrow layout | Preserve real hit areas while simplifying secondary text | Verified44px Home controls and no overflow at320px |
| Reduced Motion | State changes remain understandable without movement | CSS/WAAPI motion stops; labels, checks and result messages remain |

Motion timings are Kuro prototype choices, not measured !Boring timings. Browser press feedback cannot reproduce native haptics. The native implementation should retain this information/action hierarchy and validate real touch response on device before calling the polish complete for iOS.


### 2026-10-01 — Home v17: matching Manga frames and reusable context

Owner reported that Solo Leveling and Chainsaw Man looked inconsistently framed and liked the named club-reader treatment. Replaced the1.2:1 columns with equal columns and identical2:3 outer frames,6px inset and border. Natural artwork proportions remain intact through contain; inner whitespace may differ with source aspect ratios. Shared caption/progress baselines and the paper-spread material remain. This supersedes the unequal featured-cover layout fromv15/v16, without changing Anime.

Added Manga context to both featured cards and relevant compact shelf entries. A small page mark identifies chapter updates; reader names are a separate44px club action. Neither substitutes for the other. Title-specific sample readers replace the identical hardcoded pair on Manga cards; opening the action shows those same people reading that title. Empty/unknown activity adds no invented reader count or chapter badge. A small fixture map separates newly released chapter ranges from unread backlog: Jujutsu Kaisen has5 unread but2 new, and reading an older chapter leaves2 new. Manga's heading includes current unread new chapters across all six sample titles. Progress/cap/Undo patches the update label and total while preserving the reader action.

Verification:390px frames both155x232.5 at the same y position;320px both129x193.5 with no page overflow, no compact context overlap and all Home buttons at least44x44. At768px the frames both162px wide, no horizontal overflow and all images loaded. Featured and compact reader actions opened correct title/name context. Cap changed1 new chapter→Up to date and heading4→3 while retaining Mina; Undo restored both, failure retained count24 and4 new chapters. Advancing the backlog16→17 left2 new releases. Caught-up retained all4 reader actions. Unknown-total entries show no fake chapter update. Anime retained2 scene cards, its2-new-episodes summary and no Manga context. Console warnings/errors empty; JS syntax and diff whitespace checks passed.

Public browser verifiedv17 at https://graduate-sullivan-aside-floyd.trycloudflare.com/instrument.html . Expiry remains2026-10-02 02:44UTC /04:44CEST; no access extension, restart or new public files. Changed three Instrument files, README and three required root docs. No new repo files/artwork; design inventory65. Screenshot `/tmp/kuro-home-v17-manga.png`; backup `/tmp/kuro-home-v16-before-manga-consistency/`. All names/releases are illustrative browser fixtures. No real club/chapter data, native implementation, physical-device haptics or release proof is claimed. Required memory saved through the permitted extension-note mechanism.

### 2026-10-02 — Home v18: controls, busy calendars and private-club identity

Owner requested a closer review of individual buttons and the Anime/Manga switch, a release section that supports many followed titles, and a more distinctive Sunday Club. Updated the three Instrument files in place; the accepted Anime scenes and equal Manga cover frames remain.

- Medium choice: full-width named Anime/Manga targets with custom frame/book line icons and a shared moving ink rule. Each target is 64px high. The availability summary sits beneath it. Tap, horizontal drag, arrow keys and remembered choice remain supported; a vertical drag does not commit a switch. Stable hit areas stay separate from artwork transition.
- Button hierarchy: progress has a consistent shallow 44px key with an inset face; dark Anime surfaces use the inverse face. Plan actions use labelled, lower-emphasis buttons with a filled Planned state. Navigation rows remain light; disclosures use chevrons, preserving plus for incrementing progress. Contact, cancellation, completed/disabled, failed, saved and Undo states remain distinct. Failure uses an outlined face as well as a result message.
- Coming up: compact date headings contain a meaningful calendar date, count and small cover fan. Only the nearest group opens initially, with three rows visible. Busy days expand in place through Show more/Show fewer; later groups open in the same vertical feed. Four dates render initially; Next 4 dates appends the next batch and focuses its first header. No separate calendar page or context submenu. Undated announcements have their own Dates to come group and Date TBA labels. Manga distinguishes chapter releases from volume/English-edition releases; Anime uses episode/time labels. Release-unit fixtures are independent of mutable progress.
- Sunday Club: dark ink enclosure, small custom club seal, member initials and an inset light conversation card. Title artwork, named member actions and protected spoilers retain their existing behavior. A lighter secondary activity row stays inside the club enclosure. The new visual identity does not invent a separate club-navigation destination.

Verification: the Full calendar fixture has 48 scheduled events across six followed titles and eight dates. Initial render has four date groups and three visible event rows. Expanding all groups and rows reached 48 unique event IDs with no lost events; loading later dates removed the exhausted control and transferred focus correctly. Collapse/Show fewer restored the three-row preview. Undated-only showed no fabricated scheduled dates; a new account omitted calendar/club/current-title content. Caught-up used Keep reading and retained reader context. At 320px both media had no horizontal overflow and all rendered Home buttons were at least 44x44; 390px and 768px previews were also inspected, with loaded artwork. Failed progress remained unchanged; retry, cap, Undo and plan/Undo worked. Updating progress did not change future release numbers. Spoiler reveal/hide, correct club title context and focus return were checked. Keyboard medium changes, pointer contact/cancel and Reduced Motion (zero CSS transition) were checked. Console warnings/errors were empty; JavaScript syntax and diff-whitespace checks passed.

Public preview verified instrument.js?v=18 and loaded artwork at https://graduate-sullivan-aside-floyd.trycloudflare.com/instrument.html . The original expiry remains 2026-10-02 02:44 UTC / 04:44 CEST, subject to Mac/tunnel availability. No new public files, restart or access extension. Changed three Instrument files, the reference-board summary, design README and three required root state/plan documents. No new repository files/artwork; prototype inventory remains 65. Backup: /tmp/kuro-home-v17-before-controls-calendar/. Screenshots: /tmp/kuro-home-v18-anime.png, /tmp/kuro-home-v18-manga.png, /tmp/kuro-home-v18-calendar.png and /tmp/kuro-home-v18-club.png. Required project memory is recorded through the permitted extension-note mechanism.

Boundary: this is local and temporarily hosted browser-fixture evidence. The 48-event case is not 48 distinct followed titles or a production load test. Backend paging, real release provenance, real club privacy/data, native SwiftUI, physical iPad/Safari behavior and haptics remain unchanged or unverified. The user has not yet reviewed v18; previous endorsement covers the direction, not every new detail.


### 2026-10-02 — Incomplete series plan and Home v19 sketch

Created `docs/plans/2026-10-02-series-and-home-rebuild-DRAFT.md`: an explicitly INCOMPLETE living draft with 16 tasks across exactly two waves, neither started. Covers stable series identity above preserved catalogue entries, logical seasons/parts, structured provider imports, reversible mapping/backfill, bounded server grouping, tracking/privacy preservation and design changes across Home, detail, Collection, Discover, clubs and profiles. Success criteria, dependencies, failure cases and owner additions remain visible. No migration, production API contract, native implementation or deployment was executed.

The three Instrument files now demonstrate current-season strips on two large and two compact Anime cards, an optional Manga part strip and a read-only section overview. The full strip is one accessible 44px target; tiny digits are not separate controls. Opening it never changes progress. Current-season progress updates and Undo refresh the overview; other seasons remain Progress unknown. Upcoming Anime rows include sample season context. Existing matching Manga cover frames and reader links remain.

Verified browser evidence: 320/390/768px layouts without document overflow or Home targets below 44px; equal 390px Manga frames 155 × 232.5; large and compact strips open the correct title; Manga opens Parts without invented strips on other titles; +1/cap/Undo preserves the selected season; simulated failure leaves progress unchanged; Escape returns focus to the initiating strip. JS syntax passed and no browser error logs observed. Sample data does not prove catalogue accuracy, native behavior or backend performance. Long-series paging and true per-season writes remain planned work.

Temporary public preview served v19 with loaded images at https://graduate-sullivan-aside-floyd.trycloudflare.com/instrument.html . Original expiry remains 2026-10-02 02:44 UTC / 04:44 CEST, dependent on Mac/tunnel availability. No public files were added and access was not extended. Draft plan remains local. Screenshots: /tmp/kuro-home-v19-anime.png, /tmp/kuro-home-v19-manga.png, /tmp/kuro-home-v19-seasons.png. Backup: /tmp/kuro-home-v18-before-series/. One new repository plan; design directory remains 65 files. Required memory saved through the permitted extension-note mechanism. Changes remain uncommitted.


### 2026-10-02 — Home v20: season control design

Reworked the three Instrument files after owner feedback that the initial season treatment needed stronger design. Anime uses a continuous inset rail with engraved stops and a shallow light current-position face; the whole rail remains one 44px target. Compact cards retain that grammar. Manga uses joined paper-index tabs and a cut bookmark silhouette, without changing the matched cover frames or reader context. Only the current marker has emphasis; other numbers do not imply completed seasons.

The overview replaces repetitive progress-unknown rows with larger browsable panels. The actual current section stays marked independently of the inspected section. Choosing another panel shows an unknown-progress preview and hides current-season progress controls; Back to season/part restores them and returns focus. Preview selection never changes resume or tracking. Contact depth is small and releases on pointer cancellation; status changes settle in 180ms through the existing reduced-motion-aware helper. No new artwork or invented season-specific images.

Checked local browser layouts at 320/390/768px, including compact rails: no horizontal card overflow and no narrow-phone Home controls below 44px. Equal Manga frames remain. Anime Season 3/4 and Manga Part 2 browsing leave Home progress/current markers unchanged; return-to-current, cap, Undo and simulated failure passed. Escape returns focus to the source strip. Reduced motion sets transitions to 0s and keeps browsing functional. JS syntax passed, browser error logs empty. This is browser-fixture evidence only; native touch/haptics, catalogue accuracy and backend integration remain unverified.

Existing approved public preview serves v20; original expiry remains 2026-10-02 02:44 UTC /04:44 CEST while Mac/tunnel stays online. No extension, new public files or native/backend writes. The two-wave plan remains INCOMPLETE and neither wave has started. Updated its design specification and evidence log, the three required root documents and design README. No new repository files; design directory remains 65 files. Backup: /tmp/kuro-home-v19-before-season-design/. Screenshots: /tmp/kuro-home-v20-anime.png, /tmp/kuro-home-v20-manga.png, /tmp/kuro-home-v20-seasons.png. Required memory recorded through the extension-note mechanism.


### 2026-10-02 — Home v21: seasons belong to the title

Owner's screenshot rejected the boxed Home season rail while explicitly retaining the v20 detail-page design. Replaced Anime Home rails with a quiet numbered sequence directly below the title. The current number uses brighter/heavier text plus a short underline. The title and sequence form one accessible target, avoiding tiny digit buttons and a separate compact-card footer. Compact titles align at the top of their shared card area. Progress stays a separate action; release and club context stay in their existing footer.

The detail rendering/browsing functions are byte-identical to the v20 backup and their styles are preserved. Manga parts remain as v20. Checked at 320/390/768px: no card/title overflow, narrow-phone Home controls at least 44px, correct large/compact overview navigation, current-state preservation while inspecting another season, Escape focus return, progress cap and Undo. Tablet Manga frames remain equal at 162x243. JS syntax/diff whitespace passed; browser error logs empty. Browser fixture evidence only.

Three Instrument files plus README, the three required root docs and existing incomplete plan updated. No new/deleted repository files; design directory remains 65 files. Plan still INCOMPLETE with two unstarted waves. No native/backend writes. Backup: /tmp/kuro-home-v20-before-inline-seasons/. Screenshots: /tmp/kuro-home-v21-anime.png and /tmp/kuro-home-v21-season-context.png. Existing approved preview retains its original 2026-10-02 02:44 UTC /04:44 CEST expiry; no extension or new public files. Required memory saved through the extension-note mechanism.

### 2026-10-02 — v23 restoration

Withdrawn v22 full-width list; restored pre-v22 CSS, keeping JavaScript unchanged. Compact season design remains open. No native/backend changes; no files added/deleted. Existing share expiry unchanged.

### 2026-10-02 — v24 compact Anime sleeves

Poster area and season edge share one surface. The entire edge is a 44px target opening the unchanged overview; numbers are not tiny individual controls. Current season is distinct without implying other seasons were completed. Single-entry titles omit invented season metadata. Episode value, progress trace and + form one footer. Shared press/cancel behavior includes the new season edge; reduced-motion transforms are disabled.

320px: four 140×220px cards, no overflow or compact targets below 44px. 390/768px fit checked. Season browsing kept current marker 2 and progress 6; +1, Undo and simulated failure passed. Manga covers remain 162×243px at tablet width. Detail rendering and browsing functions are byte-identical to v23; JS syntax/diff checks pass and browser error log is empty. No native/backend writes or release. Three Instrument files and existing documentation changed; no files added/deleted, directory still 65 files. Original approved public-share expiry unchanged.

### 2026-10-02 — v25 minimal season line

Home v25 restores the original compact Also watching cards after rejection of v24 sleeves. Season numbers now interrupt a fine line under the episode count, with a ring around the current season. The combined progress/season summary is a 44px overview target; + remains a separate mutation. Large Anime cards, Manga and the liked detail selector remain unchanged. Browser proposal awaiting owner review. Restored 92px compact card height. Verified 320/390/768px fit, 44px targets, season preview independent of tracking, focus return, +1, Undo and simulated failure. Noncompact progress markup is identical for anime/manga, known/unknown totals and completion cases. Syntax/diff checks passed. Existing approved public preview serves v25; expiry unchanged. Three prototype files and existing docs updated; no repository files added/deleted, native/backend work or deployment. The neutral season line indicates sequence, not completion of prior seasons. Individual numbers are not tiny buttons: the full 44px summary opens details. Titles without section metadata retain their original progress display. Screenshot: `/tmp/kuro-home-v25-season-line.png`.

### 2026-10-02 — v26 centered main-card indexes

Home v26 extends the minimal season index to main Anime cards: centered beneath each card, separated from title/progress and club context. A softly raised current-season ring and fine connecting line are shared with the compact treatment through one renderer. Compact cards stay 92px tall. Liked detail selector and Manga remain unchanged. Design proposal awaits review; browser fixture only. Verified centered alignment and no overflow at 320/390/768px, 44px controls, preview-without-tracking changes, focus return, episode cap, Undo and failed saves. Detail/overview/Manga rendering functions unchanged. No new/deleted repo files, native/backend writes or deployment. The two-wave series plan remains INCOMPLETE and NOT STARTED. A scene unit groups card and index for motion and title-context lookup. Each index is one 210×44px overview target, not separate small digit buttons. Unknown groupings do not gain invented seasons. Shared renderer is `seasonNumbers`; detailed season browsing is unchanged. Screenshot: `/tmp/kuro-home-v26-centered-seasons.png`. Original public preview authorization/expiry unchanged. Three Instrument files and existing docs updated; design directory remains 65 files.

## 2 October — v27 edge index

Home v27 replaces the rejected detached v26 number line with a centered season index inside the lower edge of each main Anime card. The current number forms a paper-colored cut-out tab; other numbers remain unboxed. Compact cards retain the v25 plain outlined marker and original 92px height. Liked detail selector and Manga are unchanged. Browser fixture proposal awaiting owner review, not an approved design or native implementation. Verified 320/390/768px fit, 44px season targets, exact main-index centering and bottom-edge alignment, season preview independent of tracking, focus return, episode cap, Undo and simulated save failure. Detail, Manga, compact and progress rendering functions unchanged; JS syntax and diff checks passed. No browser errors observed. No new/deleted repository files, native/backend changes or deployment. Series plan remains INCOMPLETE with both waves NOT STARTED. Screenshot: `/tmp/kuro-home-v27-edge-seasons.png`. Existing public-preview scope and original expiry unchanged. Directory remains 65 files.

## 2 October — three label studies

Home label comparison v28 is available at `instrument.html?seasons=compare`: Caption notch, Rail caption and Artwork tab, each demonstrated on one main Anime card and two compact cards. The default Home remains v27; the liked detail selector and Manga are unchanged. No option selected or approved. This is an isolated browser fixture comparison. Verified 320/390/768/1280px layouts (320px overflow corrected), 92px compact heights, season targets of at least 44px, large/compact/artwork season entry points, preview without tracking changes, focus return, progress and Undo across the shared examples. Default Home/detail/Manga/progress renderer parity, JavaScript syntax and diff checks pass. No new/deleted repository files; design directory stays at 65 files. No native/backend changes or deployment. Screenshot: `/tmp/kuro-season-label-options.png`. Existing public-preview files and original expiry unchanged. Comparison state is local to the page; no preference is saved. The artwork option uses the full small-cover target for season browsing so its corner stamp does not create overlapping tiny targets.

## 2 October — selected artwork treatment, v29

Home v29 saves the owner-selected Artwork tab treatment: only a white Season N marker on main Anime images and an S-number stamp on mapped Also watching covers. Numbered season rows are removed from both sizes. Tapping the marker/compact cover opens the existing full season overview; episode progress remains separate. The comparison board marks Artwork tab as selected and reflects the same simplification. Approval applies to this season treatment, not the complete Home or implementation plan. Browser prototype only; no native/backend deployment. Checked 320/390/768px fit, main targets at least 44px high and small-cover targets 44×66px, correct full-season counts in details, preview independent of tracking, compact progress/Undo, and Manga preservation. Liked detail/Manga helper/progress functions remain identical. JS syntax and diff checks pass. No new/deleted repository files; design directory remains 65 files. Screenshot: `/tmp/kuro-home-v29-artwork-seasons.png`. No public-preview renewal.
