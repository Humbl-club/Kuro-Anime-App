# Kuro Home — selected artwork season design

**Production execution reference (5 October2026):** The singular [master plan](../../docs/plans/2026-10-02-series-and-home-rebuild-DRAFT.md) is now v1.1. The [Claude Code handout](../../docs/handoffs/2026-10-05-claude-code-production-handoff.md) includes its active specification, initial database audit and production privacy/concurrency/import/capacity gates, plus46 local preview/dependency hashes. Both native/backend waves remain NOT STARTED; visual fixtures are references only. Prior version notes below are historical.

**Execution reference (4 October2026):** The existing singular [Home/detail master plan](../../docs/plans/2026-10-02-series-and-home-rebuild-DRAFT.md) is v1.0, planning complete for this scope, with two implementation waves/six work packages. Native/backend execution remains NOT STARTED. The current selected browser screens are pinned visual references, not completed integration. Earlier incomplete-plan status notes below are historical. No prototype/code change in this planning initiative.

Local browser prototype, v53 (Poster selected; Manga reading jackets proposed; Home markers remain v29). The owner selected this season treatment on 2 October 2026; this is not a native app or backend release.

## Run

From the repository root:

```sh
python3 -m http.server 8803 --bind 127.0.0.1 --directory tools/design-directions
```

Open http://127.0.0.1:8803/instrument.html. Keep the server running while reviewing.
The comparison is at http://127.0.0.1:8803/instrument.html?seasons=compare.
No package installation, credentials or backend connection is required.

## Selected treatment

- Main Anime images show only the white **Season N** artwork tab.
- Compact covers show only **S2**, **S3**, etc. No separate numbered season rows.
- Tapping the main tab or a mapped compact cover opens the full season overview.
- Inspecting another season never changes the current season or episode progress.
- Anime retains its liked detail selector. Manga now uses a chapter bookmark, without a numbered Parts selector.

The comparison retains the two earlier alternatives and labels Artwork tab as selected. Other design studies in a local checkout are outside this checkpoint.

## Files and verification

`instrument.html`, `instrument.css` and `instrument.js` implement the prototype. `journal-data.js` holds sample catalogue fixtures and artwork provenance. Referenced local artwork is included in `assets/`. The linked `boring-study.html` reference board uses remote publisher media.

Progress, releases, club activity and season groupings are illustrative. Changes are local to the demo and reset on reload; the Anime/Manga preference is retained in local storage. No sign-in is required.

Checked at 320/390/768px: layout fit, accessible season targets, full-season entry points, preview independent of tracking, progress/Undo and Manga preservation. Browser checks do not establish native haptics, backend integration or production behavior.


## Detail exploration (v30)

Open Jujutsu Kaisen from Also watching, or `instrument.html?detail=anime-2`. Switch to Manga and open Chainsaw Man, or use `instrument.html?detail=manga-0`. Other titles use the shared layout with absent-data fallbacks. Season/part browsing, episode/chapter expansion, character notes, synopsis expansion, club disclosure and progress/Undo are interactive; no backend is called.

`instrument-detail-data.js` contains editorial demo fixtures. Character artwork is copied from the existing public catalogue Storage records 21–24 and 180–182, retained locally as `assets/detail-character-<id>.png`; character claims are minimal and spoiler-free. These files are catalogue artwork, not generated portraits. New fixture/asset files: eight. Native file/migration counts are unchanged.

Song examples: official JJK https://jujutsukaisen.jp/music/2nd_01.php and https://jujutsukaisen.jp/news/20260320_01.php. Spotify URLs explicitly open search, not verified recordings. Publisher URLs point to VIZ series chapter indexes, not an asserted exact continuation chapter. All progress, available episode counts, season grouping and club activity remain illustrative. Current season catalogue completeness is not asserted. Editorial hooks and expectation phrases are authored demo copy.

Source feasibility and the two-wave production work are recorded in the existing `docs/plans/2026-10-02-series-and-home-rebuild-DRAFT.md` (v0.2, INCOMPLETE). No parallel plan was created. No public-preview authorization was extended.

Verification (2 October): JS syntax; browser 320/390/768px fit with no detail overflow or sub-44px visible controls; season music/credit switching; browse without tracking mutation; +1 and Undo synchronized with Home; simulated write failure unchanged; manga part preview and no soundtrack; new-account save/Undo; loaded character assets. Native/backend behavior remains untested.


## Detail polish (v31)

The opening is more compact, with a soft cover-art light layer for Anime and printed edges for Manga. Descriptive expectations move into the synopsis disclosure. The selected season connects to one content area; the bookmark identifies the tracked section separately from the selection outline. Selection remains read-only.

The next episode/chapter leads the list and has a separate 44px completion button. Its thumbnail is title cover artwork, not a verified episode still. Completed rows recede. Expanding units preserves open disclosures; completion retains focus on the next action (or More when caught up), and Undo floats above the bottom edge without inserting space above episodes. Character portraits lift into short inline bios; music uses OP/ED typography when verified release artwork is absent (optional fixture artwork supported). The unknown chapter mapping presents a modest source-manga link instead of implying an exact handoff.

Verified locally: JS syntax; 320/390/768px width fit; settled targets >=44px; season isolation and music changes; next-unit +1, Undo, failure without mutation; manga caught-up, Undo and part browsing. Motion is browser-only; no native haptic proof. Approved Home artwork season treatment unchanged. No new files or catalogue ingestion in this pass.


### v32 — club context and season-first manga guidance

Jujutsu Kaisen and Chainsaw Man have fictional shared-club rosters with explicit watching/reading/finished section labels, club-only sample comments and collapsed spoiler notes. The early people link scrolls to this section. Other titles use an empty activity state; the new-account scenario omits it. One in-memory comment per title can be saved/edited; reset/reload clears it. Fail next change retains the draft; whitespace-only comments are rejected and input is limited to 500 characters. This does not implement server access control.

Anime source disclosure follows the selected season and distinguishes start/end/read-next; all chapter values are explicitly unverified. The existing plan v0.4 prioritizes season mapping and keeps episode mapping optional. No new files in this initiative. Checked 320/390/768px fit, 44px visible social controls, Manga wording, spoiler disclosure, comment save/edit/failure/retry, no-club state and reduced motion. JS syntax and diff checks passed. No native/backend deployment.


### v33 — season stories and a lighter club room

Jujutsu Kaisen seasons and Chainsaw Man parts now have separate sample hooks, premises, expanded synopsis and expectation copy. Unmapped sections use a labelled series-overview fallback. Story changes never alter tracking. Club artwork now anchors “Between us.” with a collapsed member roster and a distinct “Leave a thought” entry. Comments remain local-only; source review confirms native flat shared-club comments, not reply threads or per-club rooms. No repository files added/deleted. Approved Home markers unchanged.

Verified v33 locally: Anime season 1/2 and Manga part 2 show distinct introductions; returning to the current season preserves progress. Member disclosure, spoiler reveal and local comment saving work. No horizontal detail overflow at 320/390px; social controls measure 47/44/62px. Browser error log empty; JavaScript syntax and diff whitespace checks pass. No live/native verification.


### v34 — artwork materials and Manga adaptation guide

A shared `visualFor` resolver uses optional `sections[n].artwork = {cover, banner}` references, otherwise series artwork. The exact displayed scene selects a stored palette; the same source/resolver supplies Home and detail. Current fixtures have no verified per-season image associations and therefore honestly retain series art. Do not assign arbitrary alternate images to seasons just to make colour changes visible.

Generate palettes after adding/replacing local artwork:

```sh
python3 tools/design-directions/build_art_materials.py
```

The script requires Pillow, reads local assets, crops banners to the Home scene ratio for sampling, selects a restrained hue, enforces white-on-base contrast and writes `instrument-art-materials.js`. Each entry records the image digest, algorithm/override choice and base/deep/wash/edge values. Manual overrides preserve the owner-liked AoT and Demon Slayer colours. Browser runtime does no image analysis or palette network requests; regeneration is explicit, not a filesystem watcher. Missing palettes use a neutral fallback. Rebuilding unchanged images is deterministic. The current set is 24 palettes; minimum measured white/base contrast is 7.41:1. This is not a full accessibility audit.

Manga no longer shows the Parts selector on Home or details. Chapter progress is “Your bookmark”; real volume support awaits volume/edition data. Jujutsu Kaisen has internal Anime ↔ Manga links with independent material/medium context. Chainsaw Man uses its official external anime link rather than mislabelling manga art as anime art. The finished-season guide remembers a selection in memory only; it never changes either collection's progress. It shows existing anime progress as context without treating an in-progress season as completed. Only evidence-approved coverage can show chapter bounds/read-next. No real mappings are currently verified; all sample guides show that limitation. No new native source, database calls, migrations or hosting changes.

Checks: 320/390/768px no horizontal detail overflow; guide controls >=44px; exact Home/detail colour equality for AoT and Demon Slayer; inspected-season isolation; bidirectional JJK routing; independent chapter increment/Undo/failure and caught-up state; read-only guide selection; reduced-motion guide flow; missing palette/section fallbacks and evidence-gated recommendations; deterministic generation; JS syntax and diff whitespace. Browser error log empty. Two new repository files this pass: palette generator and generated JS. Local preview only, not native or production proof.

## v35 — Anime opening

**Anime opening polish (2026-10-02, v35):** Local Instrument Anime details now give the cover up to 160px of width, retain the artwork-derived header colour, and show one season-specific hook before an expandable synopsis. Manga presentation is unchanged. Verified 320/390px dialog fit, synopsis disclosure and season-specific copy switching; JavaScript syntax and diff checks pass. Browser prototype only, not native or deployed. The existing two-wave plan remains INCOMPLETE.

Preview screenshot: `/tmp/kuro-anime-v35.png`. No repository files added or removed.

## v36 — Detail artwork and Home/Taste boundary

**Home/Taste and import planning (2026-10-02, v36):** Local detail artwork is larger and joined to the Anime header; Manga uses a larger book-like cover. Existing recommendation cards now live on a separate Taste view, with Home reserved for tracking, upcoming and clubs. New-account Home has an honest import-first empty state. The existing two-wave plan is extended to v0.7 (INCOMPLETE) with structured resumable import, incremental Home revisions, release evidence/precision, provider permission and coverage gates, data contracts and failure/performance criteria. AniList current published terms restrict competing tracker use; expansion requires resolving permission. No native/backend execution or release.

Header Taste/Home buttons navigate the local views; horizontal page gesture is implemented outside controls. Browser checks cover tap navigation, 320px details including long titles, and new-account empty-state/Taste behavior. Native touch gesture testing remains outstanding. Recommendation card rendering is preserved. Import is a plan, not a working button or simulated backend. Release dates remain explicit sample fixtures. Screenshots: `/tmp/kuro-anime-v36.png`, `/tmp/kuro-manga-v36.png`. No repository files added/deleted in this initiative.

## v37 — Horizontal opening and offline planning

**Horizontal detail and offline plan (2026-10-02, v37):** Corrected the owner request to a shallow full-width Anime image, rather than a taller portrait header. Manga retains a compact book opening and refined bookmark/next-chapter controls. Plan v0.8 remains INCOMPLETE with the same two waves; adds durable account-scoped progress outbox, idempotent revision-checked server writes, reconnect/backoff, account isolation, Undo and conflict criteria. Inspected native progress writes have no durable queue; offline support is planned, not implemented. Local browser checks: 320px Anime/Manga fit and simulated chapter failure/retry/Undo; no native/backend changes.

Prefer actual banner artwork; cover-only titles use a deliberate crop (not new season-specific artwork). Local header is approximately 254px high at the full detail width and 210px at 320px viewport. Offline queue behavior is specified in the existing plan, not simulated as a durable feature. No repository files added or removed.

## v38 — Manga reading shelf

**Manga Home shelf refinement (2026-10-02, v38):** Local Manga Home replaces the plain shared spread with two matched individual book frames, artwork-derived paper materials, inset chapter controls and coordinated compact shelf tiles. Covers retain their full composition; reader/new-chapter context remains available. Anime unchanged. Browser checks: equal main-card heights, no horizontal overflow at 320/390px, 44px main progress targets, simulated failure/retry/Undo. Prototype only; native/backend/offline execution remains planned.

No repository files added/deleted. Existing two-wave plan remains INCOMPLETE.

## v39 — Reading material and motion

**Manga materials and motion (2026-10-02, v39):** Local Manga Home adds a low-opacity wash from the two featured artwork palettes, softer card/control outlines, bookmark-shaped chapter accents, settling cover presses and a restrained chapter-number page-turn animation. Shelf artwork receives a once-per-session reveal through the existing observer; Reduce Motion disables nonessential motion. Checked 320px fit, chapter increment/Undo and reduced-motion CSS; JavaScript syntax/diff checks passed. Browser prototype only.

No repository files added/deleted. Existing plan remains INCOMPLETE.

## v40 — Reading desk and switch choices

**Manga desk and switch studies (2026-10-02, v40):** Local Manga Home now uses wide reading cards with full-cover artwork, prominent bookmark counts and club-reader context. Coming-up material refined; Sunday Club rendering retained. Added `tools/design-directions/switch-options.html` with three live proposed switch styles: Splice, Fold and Lens. Query parameters select each style; none is owner-approved yet. Moved the existing page-swipe handlers inside the prototype closure to fix their inaccessible state references. Checked 320px fit, matched main heights, chapter failure/retry/Undo, all three medium tap paths and Fold keyboard arrows. Browser proposal only; no native/backend change.

Compare at `switch-options.html`. Full previews use `?switch=splice`, `?switch=fold`, or `?switch=lens`, with optional `&medium=manga`. Comparison frames use `embed=1` to hide studio controls. Switch variants retain semantic buttons, arrow-key access, medium persistence and shared scrub behavior. Physical iOS gestures remain unverified. Screenshot `/tmp/kuro-switch-options-v40.png`. One HTML file added; no files deleted.

## v41 — Three distinct medium mechanisms

**Switch mechanism redesign (2026-10-02, v41):** Replaced rejected Splice/Fold/Lens studies with Ribbon (film and paper strip), Dial (central media control with rotating index), and Window (expanding artwork panes). All are local proposals selectable through `switch-options.html`; none is owner-approved. Checked all three Anime/Manga tap paths, Dial centre toggle and arrow keys, 320px fit without horizontal overflow, and targets of at least 44px. Reduced-motion styles retained; physical touch scrubbing and native iOS behavior remain unverified. Manga desk and club content retained. No native/backend or deployment changes.

Full previews use `?switch=ribbon`, `?switch=dial` or `?switch=window` with optional `&medium=manga`. Supersedes the v40 switch choices. Ribbon is the current prototype fallback, not an approved selection. Screenshot: `/tmp/kuro-switch-options-v41.png`. No repository files added or removed in v41.

## v42 — Page edge and Manga folio

**Page-edge switch and Manga folio (2026-10-02, v42):** Local Home replaces the default Ribbon with a medium heading and folded alternate-medium edge button. Manga featured titles use full-cover two-column folios with attached chapter slips, concise release context and named club readers; other reading titles become uniform compact full-width rows. Scene/page entry motion uses the existing cancellable motion helper. Comparison now shows Anime and Manga together, with v41 switches retained under Earlier switch studies. Verified 320/390px fit, equal cover geometry, 44px minimum primary targets, chapter failure/retry/cap/Undo, medium taps/keyboard, Manga detail access, Reduce Motion and new-account state. No native/backend changes; proposal awaits review.

Current local default is `switch=edge`; use `instrument.html?switch=edge&medium=manga`. Default selection is not owner approval. Earlier switches remain accessible with ribbon/dial/window queries. Cover geometry is identical across manga/manhwa without cropping the full cover. Dense shelf rows retain progress and club access. Physical iOS gestures/haptics and actual server saves remain unverified. Screenshot `/tmp/kuro-home-folio-v42.png`. No repository files added/deleted.

## v43 — Generated editorial material

**Generated editorial switch (2026-10-02, v43):** Added a custom image-generated continuous Anime-to-Manga panorama, optimized local JPEG, bundled Bodoni Moda normal/italic variable fonts with OFL license, and accessible live medium buttons. Local default is `switch=diptych`; previous variants remain query-accessible. Selection uses live type and a moving ink rule, with restrained press/transition states and Reduce Motion. Missing imagery falls back to neutral surfaces with intact labels and controls. Verified medium taps/keyboard, 320/390px fit, 146px-high targets at 320px, rendered normal/italic style, successful image loading and blocked-image fallback/recovery. Manga folio, detail content and Sunday Club retained. Six asset/provenance files added; no native/backend/release changes. Owner review pending.

Built-in image generation created `assets/medium-diptych-v43.png` (2172×724 source). Display derivative `assets/medium-diptych-v43.jpg` is 1200×400, about 228 KiB; original retained. Exact generation prompt: `assets/medium-diptych-v43.prompt.txt`. Fonts are sourced, not AI-generated: [Bodoni Moda official Google Fonts directory](https://github.com/google/fonts/tree/main/ofl/bodonimoda). Bundled unchanged normal/italic TTFs and `assets/fonts/BodoniModa-OFL.txt`. Typeface styles are scoped to the proposed switch; other product typography remains intact.

Use `instrument.html?switch=diptych&medium=anime` or `&medium=manga`. Labels stay live semantic buttons instead of raster lettering. Asset failure retains selector dimensions, text, keyboard access and medium actions. Generation is illustrative brand material, not a catalogue image or content recommendation. Screenshot: `/tmp/kuro-editorial-switch-v43.png`. Existing draft remains INCOMPLETE.

## v44 — Shelf and Masthead

**Replacement medium studies (2026-10-02, v44):** Owner rejected v43. Local comparison now presents Shelf (small sample-title cover stacks in two material selections) and Masthead (active editorial name with a cover thumbnail and moving baseline). Shared tap, keyboard and medium persistence logic retained. Local default is `switch=shelf`, not owner approval; v43 remains query-accessible. Verified both tap/arrow-key paths, 320px Home fit, selector targets above 44px, normal Anime/italic Manga styling and reduced-motion transitions for both proposals. Narrow Masthead label spacing corrected. No new/deleted repository files, native/backend changes or deployment; physical touch/haptics remain unverified. Manga folio and approved Home season treatment retained.

Compare at `switch-options.html`; full previews use `instrument.html?switch=shelf&medium=manga` or `?switch=masthead&medium=manga`. Covers are catalogue fixtures, not authenticated user data. Existing v43 artwork and licensed fonts remain in the repository; no regeneration or new font assets. Screenshot: `/tmp/kuro-switch-studies-v44.png`. Local HTTP server restarted on 127.0.0.1:8803; no public tunnel.

## v45 — Compact navigation control

**Compact Home header (2026-10-02, v45):** Owner rejected the space and composition of v44 and requested a compact, deliberate medium switch. New default `switch=compact` places a 44px-high Anime/Manga control inside the sticky navigation header, removing the separate selector row. Equal targets, small frame/page SVGs, restrained moving surface and press state retain clear medium access; earlier studies remain available. Local checks: 320px Home without horizontal overflow, equal 83×44px targets at that width, tap/arrow-key selection, Taste/Home navigation, normal Anime type and reduced-motion transition removal. Comparison shows both medium layouts. No new/deleted repository files or native/backend/deployment changes. Design proposal awaits owner review; physical iOS gestures/haptics unverified.

Compare at `switch-options.html`. Full preview: `instrument.html?switch=compact&medium=anime` or `&medium=manga`. Header is 64px high and selector 44px; no new artwork/font dependencies. Screenshot `/tmp/kuro-compact-header-v45.png`. Compactness, deliberate selection and more room for artwork are current owner requirements; default choice is not approval.

## v46 — Five compact medium directions

**Five compact medium studies (2026-10-02, v46):** Owner rejected v45 header positioning and requested five more creative, considered options. Comparison now offers Margin (registration tabs), Exposure (slim artwork windows), Relay (active cover identity plus direct alternate link), Interlock (ink/paper plates sharing a diagonal seam), and Signature (type with a selection bracket). All sit beneath the unchanged navigation, 48–54px high. Each includes design intent/tradeoff outside product UI. Shared semantic medium actions, ArrowLeft/Right and persistence retained; Reduce Motion removes transitions. Local checks: both medium tap and keyboard actions in all five, Anime/Manga 320px fit, targets at least 46px high, and reduced-motion CSS. Relay adds cancellable identity settling; only imagery-based variants render selector images. Default `switch=margin` is a proposal, not approval. No repository files added/deleted; no native/backend, public hosting or release changes. Physical touch gestures/haptics remain unverified.

Compare at `switch-options.html`; full previews use `instrument.html?switch=margin`, `exposure`, `relay`, `interlock`, or `signature`, with optional `&medium=manga`. Each iframe is independently interactive and scrollable; rationale stays outside Home under Design intent. Earlier studies retained as links. Exposure overlays shade fixture artwork; catalogue-wide image contrast and source failure need native review before selection. Relay changes visual order while preserving both explicit medium labels. No new assets/font dependencies. Screenshot `/tmp/kuro-five-switches-v46.png`.

## v47 — Frames and pages material study

**Material switch study (2026-10-02, v47):** Owner rejected v46 as insufficiently creative. Local comparison now focuses on Frames/Pages: an original generated transparent sprite pairs smoked-glass cinematic panes with ivory folded-paper sheets. Live Anime/Manga buttons remain fixed below navigation, with a fine selection mark, opacity/press states and distinct cancellable settling motion; Reduce Motion disables it. New default `switch=objects` is unapproved. Previous five studies remain under a collapsed disclosure. Local checks: 320px fit, 140×62px targets, taps/ArrowLeft, reduced-motion transitions, blocked-material fallback with working selection and subsequent image recovery. Two new repository files: `assets/medium-objects-v47.png` (2172×724 RGBA, 856277 bytes) and its exact `.prompt.txt`. Original PNG retained unchanged; image is prototype material, not catalogue art. No native/backend, release or public hosting changes; physical touch/haptics unverified.

Use `instrument.html?switch=objects&medium=anime` or `&medium=manga`; review both at `switch-options.html`. Built-in image-generation tool created the custom material pair. Exact generation spec and exclusions: `assets/medium-objects-v47.prompt.txt`; transparent original preserved in `assets/medium-objects-v47.png`, with no raster lettering. CSS positions the two sprite halves; all text, hit areas, focus, selection and fallbacks remain code. The source asset is about 836KiB and is not a native shipping optimization. Image error uses a neutral code fallback while keeping both controls; no catalogue/account fetch needed. Screenshot `/tmp/kuro-material-switch-v47.png`. No public tunnel or new service integration.

## v48 — Five visual families

**Five visual families (2026-10-02, v48):** Owner rejected the v47 material-object switch and requested five substantially different design styles. Local `switch-options.html` now compares Noir (graphite Home with floating bottom control), Poster (artwork-filled type and squared cards), Glass (translucent selector over artwork), Edgewise (vertical publication tabs with reserved margin), and Keys (shallow tactile controls beside release count). Each changes placement and surrounding Home styling; shared tracking/detail fixtures and approved artwork-season badges are preserved. Default local `switch=keys` is an unapproved proposal. All five passed click/arrow-key selection and Anime/Manga 320px overflow checks; targets are at least 44px in both dimensions, and reduced-motion selector transitions are zero. Contrast/cascade fixes cover glass surfaces, key labels, dark reading metadata and edge-tab overflow; empty Glass accounts use a selector in normal flow. No repository files added/deleted. Browser-only samples; physical touch, native haptics, catalogue-wide contrast and safe-area behavior remain unverified. No native/backend, commit, deployment or public hosting changes.

Review `switch-options.html`. Full previews use `instrument.html?switch=noir`, `poster`, `glass`, `edgewise`, or `keys`, optionally `&medium=manga`. Noir and Edgewise anchor their controls outside the scrolling phone; keyboard/semantic selection uses the existing shared selector. Rationale and tradeoffs stay outside product UI. Poster uses existing catalogue fixture covers as type fill with solid-ink fallback; no new image/font dependencies. Reduced-motion checks were at 320px; settled Edgewise page and phone widths both 320px after clipping tab contents. Glass new-account fallback is flow-based. Screenshot: `/tmp/kuro-five-families-v48.png`. Earlier studies retained as links, no owner approval inferred.

## v49 — Selected Poster refinement

**Poster polish (2026-10-02, v49):** Owner selected Poster from the five visual families ("the poster feels right just needs a polish"). Local Instrument now defaults to `switch=poster`; comparison labels it as the selected direction. Refined 36px artwork typography (30px at narrow widths), readable inactive lettering, a finer baseline with a restrained selection mark, 56px-high targets, press feedback, aligned 5px scene corners and 7px key corners, and quieter Manga chapter-slip edges. Existing Home/Taste, list fixtures, detail interactions and artwork-season markers preserved. Local browser checks: both media at 320px without horizontal overflow, tap/ArrowLeft selection, Home/Taste navigation, and zero selector transitions under Reduce Motion. No new/deleted repository files, native/backend changes, commits, releases or public hosting. Direction selected; exact polish still awaits owner review. Catalogue-wide artwork contrast and native touch/haptics remain unverified.

Review `instrument.html?switch=poster&medium=anime` or `&medium=manga`. Default `instrument.html` also uses Poster, while retaining the remembered medium. Typography keeps stable equal hit areas and solid-ink fallback underneath image fill. No new fonts/artwork. Contact feedback stays subtle; Reduce Motion removes type transforms/transitions. Screenshots: `/tmp/kuro-poster-polish-v49-anime.png` and `/tmp/kuro-poster-polish-v49-manga.png`.

## v50 — Manga reading spreads and letter-art provenance

**Poster Manga reading spreads (2026-10-02, v50):** Local Poster Manga leads now use two stacked horizontal reading spreads: intact cover on the left; title, prominent chapter progress, release notice and club readers on the right. A restrained artwork-derived paper wash and consistent geometry replace the floating chapter slips for Poster only; Anime and older visual families are preserved. Controls reuse existing progress, undo, failure and detail handlers. Local checks: 320px page/phone fit, 44px chapter targets, complete-cover containment, both medium selections, failure leaves chapter 24 unchanged, completion to 25, undo to 24, Solo Leveling detail opening/closing, and zero selector transitions under Reduce Motion. All activity is fixture data, not native/offline/database proof. Header letter artwork is still the first fixed fixture cover per medium (Demon Slayer/Chainsaw Man), assigned at preview load; no user personalization. Proposed real-app policy: a stable recent-active artwork pick per user/medium for the session, reusing cached artwork with neutral ink for an empty list. Not implemented or approved as production policy. No new/deleted repository files; no native/backend, commit, deployment or public hosting changes. New Manga composition awaits owner review; Poster remains the selected switch direction.

Review `instrument.html?switch=poster&medium=manga`. `mangaFolio` branches for Poster only, reusing `step`, `mangaContext`, `materialStyle` and intact cover art. Title/card actions and adjacent state remain unchanged on mutations. Letter-fill source is `get(keys[m][0]).cover`, set during selector construction, not dynamically refreshed by progress changes. The sample sources are `assets/anime1.jpg` and `assets/manga0.jpg`; empty preview accounts still show those sample sources. No added image/font/request dependencies. Screenshot `/tmp/kuro-poster-manga-v50.png`.

## v51 — Continuous Manga ink shelf

**Poster Manga ink shelf (2026-10-02, v51):** Owner rejected v50 horizontal reading spreads. Poster Manga now uses a continuous edge-to-edge ink shelf with all six current sample reads in a consistent two-column artwork grid. Intact covers, title, chapter progress and club readers share one hierarchy; there are no individual row cards or separate secondary-title list. Coming Up and Sunday Club retain their existing sections after the shelf. v50-specific markup/styles replaced; other medium-switch families, selected Poster switch, Anime layout and details preserved. Local checks: six covers contained, 320px page/phone without horizontal overflow, 44px chapter targets, failed progress unchanged at 24, completion to 25 and undo to 24, unknown-total Berserk progress/undo without invented totals, title club discussion access, Anime/Manga keyboard selection. Reduce Motion retains the shared animation guard; no new animation system added. All are browser-fixture checks, not native/backend/offline proof. Direction remains a proposal awaiting owner review. No new/deleted repository files, backend/native changes, commits, deployment or public hosting.

Review `instrument.html?switch=poster&medium=manga`. `active` returns the single cabinet only for Poster Manga; `mangaFolio` renders each shelf print with the shared `step` and `mangaContext` handlers. Chapter actions update only the affected state. Header letter-fill source remains the fixed first sample cover per medium, not live personalization. No new fonts/assets/requests. The uniform image grid makes six title covers readable but increases vertical shelf length; assess navigation to releases before native translation. Screenshot `/tmp/kuro-manga-ink-shelf-v51.png`.

## v52 — Manga chapter margins

**Manga chapter margins (2026-10-02, v52):** Owner rejected v51 as excessive and explicitly requested structural creativity rather than a large colored surface. Poster Manga now uses two unboxed reading leaves with intact covers, narrow chapter margins and 44px shallow paper keys; four other current reads sit in a compact index below with aligned chapter labels and controls. Removed the v51 cabinet/grid markup and styles. Calm existing light surface, no new decorative color or asset dependency. Coming Up, Sunday Club, selected Poster switch, Anime layout and detail pages retained. Local browser checks: 320px page/phone and leaf widths without overflow, full-cover containment, six 44px chapter controls, failed update leaves chapter 24 unchanged, completion to 25 and disabled caught-up control, undo to 24, unknown-total Berserk 12 to 13 and undo, club discussion access, and tap/arrow-key medium switching under Reduce Motion. No new animation system. All proof is browser-fixture/local only; native, physical touch, backend and durable offline behavior are untested here. v52 is a new proposal awaiting review; v51 is rejected. No new/deleted repository files, native/backend changes, commit, deployment or public hosting.

Review `instrument.html?switch=poster&medium=manga`. `mangaFolio` renders the two reading leaves; Poster Manga `active` renders the four-entry index. Reuses `step`, `mangaContext`, `syncActions`, undo and existing detail/club actions. No new assets or requests. Screenshot `/tmp/kuro-manga-chapter-margins-v52.png`. Catalogue-wide title wrapping, physical touch and density with real user libraries remain unverified. Header artwork remains fixed sample artwork, not user personalization.

## v53 — Manga reading jackets

**Manga reading jackets (2026-10-02, v53):** User requested a more attractive, distinctive and easy-to-navigate Manga Home from the reader's perspective. Replaced the v52 narrow side margins with chapter bookmarks attached to the two lead artworks, giving covers more visual space. Four additional reads now share a compact two-column index rather than four full-width rows; chapter controls and title labels align, with club readers and new-chapter notices retained. Light existing surface; creativity comes from attached paper geometry, typography and density, without a new colored background or asset. All covers, chapter keys and reader links have at least 44px targets. Existing in-place count/page feedback, failure, undo and Reduce Motion guards reused. Local checks: 320px page, phone and all six article widths without overflow; full-image containment; six chapter targets; failed change leaves 24 unchanged; completion to 25 disables key; undo to 24; unknown-total Berserk update/undo; private club detail access; release-day expansion; caught-up and new-account states; Taste access; Anime/Manga keyboard selection under Reduce Motion. Browser fixtures only, not physical-device, backend or durable-offline proof. Poster, Anime, details, Coming Up and Sunday Club retained. Proposal pending owner review. No new/deleted repository files or assets, native/backend changes, commit or deployment.

`mangaFolio` moves the shared `step` component inside the lead art wrapper as `.chapter-bookmark`. Poster Manga retains two lead titles and four current reads, now in a two-column `.reading-index`. Stable action handlers and fixture state are unchanged. Preview `instrument.html?switch=poster&medium=manga`; screenshot `/tmp/kuro-manga-reading-jackets-v53.png`. Real catalogue title lengths, large chapter numbers, Dynamic Type and native touch/haptics require separate validation. Header artwork still uses the first fixed sample cover per medium; no personalization claim.

## Fresh Manga reference study — 3 October 2026

Open `http://127.0.0.1:8803/manga-reference-study.html`. Five official references: mymind content materials, !Boring interaction choreography, Panels cover density, MusicHarbor release chronology and Sublime visual fragments. Source links and optional reasoning accompany published images/demos; translations are proposals. Remote source media requires internet, stays owned by its creators and is not bundled into shipping assets. Current Home v53 and Poster remain unchanged. Verified 320/390px fit, remote image loads, disclosure and Vimeo player initialization; Panels controls/poster responded, sustained video playback unverified. No hands-on native, haptic, backend, public sharing or release proof. New repository file: `manga-reference-study.html`. Screenshot: `/tmp/kuro-fresh-design-reference-board.png`.

## Three Manga Home studies — 3 October 2026

Compare `http://127.0.0.1:8803/manga-options.html`. Full previews use `instrument.html?switch=poster&medium=manga&reading=edition`, `contact` or `index`. Add `scenario=full|quiet|new|undated` to an opt-in study for fixture review. The comparison changes all three scenarios; each progress state is independent. Full previews retain the external failure/reset controls.

Edition: two ivory publication spreads and a compact four-read index. Contact: six consistent artwork plates on neutral ink, pale chapter controls, releases as date-grouped contact sheets. Index: six full-width cover/title/chapter-cursor lines and chronological releases. Sunday Club and selected Poster stay recognisable. Shared Instrument owns all actions; `manga-directions.js` only renders compositions through existing helper functions. Styles are scoped to an opt-in Manga medium, so Anime and default Home keep their markup/style.

New files: `manga-options.html`, `manga-directions.js`, `manga-directions.css`; no assets added or deleted. Modified Instrument HTML to load the study module/styles and JS with opt-in renderer/scenario hooks and section observers. Historical `.study-art` collision required a unique `.reading-study-art` namespace. Existing default v53 remains review-pending and unchanged without `reading`. No native/backend changes, public tunnel or deployment.

Checks: 320/390px fit, six loaded covers and 44px current-read controls in all options; failure retains 24, completion 25, disabled advance, Undo 24, private club/detail/Taste/Anime access; Edition unknown-total update/Undo; six releases on one date/eight calendar dates; empty and caught-up scenarios; Index reduced-motion advance with 0s key transition; no captured console errors. JavaScript syntax and diff whitespace checks pass. Screenshots: `/tmp/kuro-three-manga-home-options.png`. Native touch, haptics, Dynamic Type, real account/data and durable offline writes remain unverified. No owner selection inferred.


## Crosscut — 3 October 2026, owner review pending

Owner rejected Edition, Contact and Index as recycled compositions and palette variants. `manga-options.html` now labels them rejected and links to `manga-crosscut.html`. Do not infer selection from their prior checks.

New opt-in preview: `instrument.html?switch=poster&medium=manga&reading=crosscut`. `manga-directions.js` renders three alternating wide/narrow pairs, preserving DOM reading order. Shared `step` controls sit in cut-outs along the artwork edge, with existing title and private club reader actions underneath. Covers use `object-fit:cover` at 50% 30%; they are intentionally cropped into panels and are not intact-cover proof. No new artwork/colour layer, request, persistence or mutation engine. Poster, Anime, default Home, release chronology and Sunday Club are retained. The existing observer animates Crosscut artwork once per medium/class and honors reduced motion/cancellation.

Checks: 320/390px page/phone without horizontal overflow, six loaded images, six 44x44 keys, no chapter-cursor overflow; failed change 24 stays 24, completion 25 disables next, Undo 24; unknown-total Berserk 12 to 13 and Undo; detail and named-reader club entry points; six same-date release events, eight date groups plus pending dates; three known-total caught-up keys disabled; empty account no active panels; undated fixture only pending dates; Taste and Anime paths; reduced-motion update with 0s artwork transition; no captured browser warnings/errors. Browser fixtures only. Real catalogue crops, four-digit counts, Dynamic Type, native touch/haptics and backend/offline are unverified.

One new repository file: `manga-crosscut.html`; updated existing renderer/styles/Instrument hooks and rejected-study board. No new/deleted assets, commit, deployment or public tunnel. Source rationale lives in the preview's optional disclosure, outside product UI.


## Four Manga Home philosophies — 3 October 2026

Crosscut is rejected: Max does not want offset or unequal manga artwork/containers. Comparison `manga-four.html` presents four opt-in studies under `instrument.html?switch=poster&medium=manga&reading=library|chapterboard|journal|clubroom`. No owner approval is inferred.

- Library rework: six equal covers; cover/title open details, per-title chapter actions update directly. Shared-selection/workbench and repeated Open models are rejected; current rework awaits review.
- Chapter Board: one two-column instrument with six equal cells, known-total unread metrics, current position and direct keys. Unknown totals remain pending. Metrics derive from local available total minus current progress, not a release prediction. Tradeoff: smaller artworks and more tracking information.
- Journal: equal cover windows along a recency timeline. Recency groups are explicit invented preview fixtures; reliable per-user activity is a native/backend requirement. Tradeoff: longer vertical page.
- Club Room: current reads overlapping the fixture club occupy a private shared table; solo reads remain visible below with matching artwork geometry. Tradeoff: social overlap displaces recency; actual multi-club/permission cases are not implemented.

Three new repository files: `manga-philosophies.js`, `manga-philosophies.css`, `manga-four.html`. Instrument HTML loads them; JS injects existing helper functions plus local position data into the module. Mutations remain owned by Instrument. The module's `sync` patches library mini-counts and board unread metrics for shared updates/Undo. Progress actions and private-club/detail routing are reused; there are no API/backend writes. Existing entrance observer includes module artwork and honors reduced motion. Crosscut review page records rejection. Default no-query Home and Anime are preserved. Artwork geometry is uniform but sources are cropped with `object-fit:cover` at 50% 30%; intact-cover visibility is not claimed.

Local checks all four: 320/390px fit, six loaded equal artwork frames (subpixel rounding in Library at 320), chapter keys 44x44, no control overflow; failed update stays24, completion25 disables, Undo24; unknown-total12->13 and Undo; Library keyboard selection, selected dock title, mini-count25; Board unread metric0 at completion; title/private club/Taste/Anime; caught-up selected Library control disabled and all3 known-total keys disabled in others; empty-account0active; reduced-motion chapter update with image transition0s; no captured console errors/warnings. Shared full-calendar fixture6same-dayevents,8datedgroups plus pending. Comparison outer320px retains no innerphone/control overflow. Native touch/haptics, Dynamic Type, real data/multiple clubs, durable offline and catalogue-wide crops/large counters remain unverified. Source syntax and diff-whitespace checked. No added assets, commit, deployment or public link.


## Library selected and polished — 3 October 2026

Max selected Library. Open `manga-library.html`, or `instrument.html?switch=poster&medium=manga`. For Poster, absence of a valid reading parameter now defaults to Library; explicit historical comparisons still render when requested. Anime and other switch families retain their previous rendering. The comparison labels Library selected; other philosophies remain unselected.

Equal cover frames and aligned title/count rows are retained. A thin selected frame/underline avoids size/position changes. Selection patches only the workbench, adds a polite title/chapter announcement, never advances progress, and does nothing when selecting the already active cover. Arrow keys move +/-1 horizontally and +/-3 vertically within bounds, focus the target without scrolling and reuse the same selection helper. A known-total workbench fraction/trace is displayed; unknown totals omit both. Next is92x48 with a persistent label outside the icon cap, so shared sync/Undo doesn't remove it. Its icon requires `position:absolute`; inherited `position:relative` caused label overlap during review and was corrected. Failure/completion/Undo and details remain owned by Instrument. No timer/request/mutation engine introduced.

Checks: no-reading default Library, 320/390px page/phone/dock fit, exact equal frames88x119 and106x138, all checked library controls>=44, Next92x48 and no icon/label overlap. Arrow right/down chooses the expected title/count, polite selection status; failure24unchanged, completion25disabled/shelfcount25, Undo24 retains Next; unknown12->13 and Undo with no total/trace. Details/clubs/Taste/Anime, quietselecteddisabled, new0library, reduced-motion selection0s, no captured warnings/errors. Source syntax/diff whitespace pass. Local fixtures only; native/Dynamic Type/account/library-scale/offline proof absent. Artwork cropped consistently. New repository file `manga-library.html`; non-ignored design-directions count94. No assets/commit/deployment/public sharing.


## Library unified touch targets — 3 October 2026

**Library unified touch targets (2026-10-03):** Removed the adjacent cover-select/title-detail split. Each book is now one semantic button containing artwork, title and chapter position; all three select the same workbench without changing progress or opening details. The workbench title is static, with a separate labelled Details button (83x44). Existing focus return, keyboard selection and shared chapter actions remain. Local browser checks: cover/title/chapter taps select the expected title with detail closed; Details opens that title and closing restores its button focus; arrow-right selection works. At320/390px there is no page overflow, equal artwork stays88x119/106x138, whole-book targets are88x187/106x208, Next92x48, no nested interactive elements or grid detail targets. Simulated failure retains24 with explicit feedback; completion25 disables and syncs shelf count; Undo24. No captured console warnings/errors. Physical touch, native accessibility, backend and offline persistence are unverified. Five prototype files changed, no files/assets added or deleted; design-directions count remains94. No commit, deployment or public sharing.

Cache versions for manga-philosophies CSS/JS are3. Artwork and selection marker now live inside `library-art`; the outer button includes title/chapter so there are no nested buttons. The workbench heading is plain text and Details has its own target. Preserve this interaction rule in native translation. Earlier cover-select/title-detail descriptions are historical and superseded.


## Library direct detail access — 3 October 2026

**Library direct detail access (2026-10-03):** Supersedes the selection-only book interaction. Tapping cover, title or chapter now opens that book’s details immediately and updates the shared workbench first. The existing Details control is an optional shortcut. Navigation buttons have Open-details labels and data-selected visual context instead of misleading toggle semantics. Closing details restores focus to the originating book; opening does not advance progress. Library book/Details controls now participate in Instrument’s existing movement/pointer-cancellation guard; actual touch-drag testing was unavailable because the in-app browser does not support CDP touch input. Local browser checks: image/title/chapter open correct Solo Leveling/Jujutsu Kaisen/Berserk details, workbench follows, progress unchanged; keyboard arrow selection plus Enter opens correct title; dismissal restores book focus. At320/390px no page overflow, artwork88x119/106x138, whole-book targets88x187/106x208, no nested interactive controls or toggle aria-pressed. Simulated failure retains24, completion25 disables/syncs shelf, Undo24; reduced-motion details work; no captured console errors/warnings. Six prototype files changed; no new/deleted files/assets (count94). Native touch/accessibility/backend/offline proof remains open; no commit, deployment or public sharing.

This supersedes the selection-only unified touch model above. Module click handling updates the workbench before Instrument’s existing detail dispatch. Both use the same whole-book button; keyboard arrows update controls without opening, Enter/Space use normal button activation. Visual selection is data-selected, not aria-pressed. Existing drag-cancellation guard now includes library-select/library-detail; no custom long-press or double-tap. Cache versions: manga-philosophies CSS/JS4, Instrument JS57.


## Library independent selection/navigation — 3 October 2026

**Library independent selection/navigation (2026-10-03):** Owner rejected forcing detail navigation to select a read. Supersedes both prior bar-only details and whole-book direct-open models. Cover/title/chapter form one selection button; each book has a separate full-width Open button beneath it. Selection updates only the workbench; Open navigates without changing selection or progress. Removed redundant workbench Details button. Selection uses aria-pressed; Open uses navigation labels and existing Instrument routing/cancellation. Detail artwork origin lookup includes library-art. Local browser checks: image/title/chapter select correctly with dialog closed, opening unselected Solo Leveling preserves Berserk selection, close restores Open-button focus, arrow/Enter selection does not navigate. At320/390px no page overflow, equal artwork88x119/106x138, six Open targets88x44/106x44 and no nested controls. Failure24unchanged, completion25disabled/shelfcount synced, Undo24; reduced-motion unselected-title navigation preserves selection; no captured console warnings/errors. Additional Open rows increase shelf height. Physical touch/scroll arbitration, VoiceOver/Dynamic Type, native/backend/offline proof remain open. Six existing prototype files changed, no added/deleted files/assets (count94); no commit, deployment or public sharing.

The direct-open model immediately above is rejected and superseded. Open and Select are sibling buttons with an8px visual gap, never nested or hidden behind a long-press/double-tap. The shared workbench is purely chapter controls/context. Arrow/Enter chooses a book; Tab reaches its Open action. CSS/JS module cache5, Instrument JS58. No new event/mutation engine. Owner review of added height remains pending.


## Library per-book tracking proposal — 3 October 2026

**Library per-book tracking proposal (2026-10-03):** Owner rejected the repeated Open rows/shared-selection approach. Removed selected-book state, selection handlers/announcements, shared workbench and Open buttons. Equal cover/title targets now open details; each read has its own adjacent44x44 chapter-advance key using existing Instrument progress/mutation/Undo. The counter belongs to that title; no selection step. Removed obsolete Library CSS while retaining other philosophy layouts. Existing entrance observer and cancellation guard now target library-story. Coming Up and Sunday Club remain. Local checks: cover/title open correct details with focus return; Berserk12->13 leaves Chainsaw24 and details closed, Undo12;320/390px no page overflow, equal artwork88x119/106x138, six44x44 keys, no obsolete UI/nested controls. Failure24retained, completion25disabled while Solo8unchanged, Undo24; reduced-motion keyboard detail activation, caught-up3disabled, new0library, no captured browser warnings/errors. Totals are hidden visually in compact footers but preserved in accessible progress labels/detail pages. No files/assets added/deleted (count94); six prototype files changed. New interaction proposal awaits owner review. Native touch/accessibility/backend/offline remain unverified; no commit/deployment/public sharing.

Previous selection/navigation models above are historical and rejected. No librarySelection, selectLibrary, dock or custom library keyboard listeners remain. Instrument owns normal button activation, progress state, completion, focus return and Undo. CSS/JS module cache6, Instrument JS59. No native implementation or API work.


## Temporary phone review link — 3 October 2026

**Temporary phone preview (2026-10-03):** Owner requested off-studio iPhone access. Updated existing scripts/serve_design_share.py for current Instrument dependencies:45 allowlisted sample UI/artwork/font files, no directory/repository/config/backend access. Existing local helper binds8814; official Cloudflare cloudflared2026.9.3 downloaded to /private/tmp/kuro-preview-tunnel and running a quick tunnel for12hours. Preview: https://trees-marc-amongst-obtain.trycloudflare.com/instrument.html?switch=poster&medium=manga&embed=1. Started3October14:39 Europe/Berlin; automatic stop by4October02:39 (earlier if host/process stops). Fresh HTTP200 for HTML/module/detail-data/art/font; configuration/doc probes404 and traversal400. Public browser390px fit, six loaded covers and Jujutsu Kaisen detail opening/closing verified. Physical Safari/iPhone not tested; fixture changes are browser-only. One existing script modified; no repository files/assets added/deleted, no native/backend deployment or account data shared. Refresh sees allowlisted local edits while running.

Runner: `python3 scripts/serve_design_share.py --port 8814 --hours 12 --cloudflared /private/tmp/kuro-preview-tunnel/cloudflared`. Do not renew automatically or expose the general8803 server. No recurring automation or system service installed. Source script expiry/cleanup retained.


## Phone-visible Coming Up — 3 October 2026

**Phone-visible Coming Up (2026-10-03):** Owner liked the per-book Library rework and requested a more visible Coming Up on short phones. Instrument now places a 72px artwork-led calendar summary between the Poster medium switch and Now Watching/Reading. It uses the existing releaseGroups() fixtures, shows next-day count and whole-range count, and is one full-width button to the complete calendar. No second schedule source, date invention, feed submenu, reduced cover geometry or progress-engine changes. All six reads remain; Library chapter keys remain44x44. Focus moves to the calendar without a second jump, scrolls only the phone, and uses instant scrolling for reduced motion. Unknown dates show pending announcements; new accounts and Taste hide the strip. Embed height uses100dvh. Browser checks:320x568,390x667,390x844, both media no horizontal overflow, summaryy147..219; landingy83 below71px header, keyboard/focus,48-release fixture/8 dates,6 same-day rows, undated/new/caught-up/Taste checked; three summary images loaded and no captured console warnings/errors. Source files instrument.html/css/js only; CSS54/JS60. Same45-file public share and original expiry retained; no scope/TTL extension. Physical Safari, VoiceOver, native/backend/offline proof remains open. No files/assets added or deleted, no commit or deployment. New summary awaits owner review; v0.8 remains INCOMPLETE with two native/backend waves NOT STARTED.

Design intent: expose an upcoming signal on first launch without moving the entire expanded calendar ahead of current reads. The summary and detailed calendar derive from the same release groups. Three thumbnails are a preview, not a cap; the aggregate count includes every dated event. Pending announcements are separate from dated totals. The complete scrollable calendar still handles same-day expansion and additional date batches. One72px button avoids tiny artwork targets; source/keyboard order is medium choice then summary. No sticky lower overlay, extra navigation tab or collapsed reading shelf. This does not shorten the distance to every individual calendar event; it gives that section a visible entry and one-tap access.


### Temporary share restored, original expiry retained

**Temporary preview restored (2026-10-03):** Browser/app restart stopped the earlier preview and removed its temporary binary/screenshot. The old trees-marc-amongst-obtain link is unavailable. Restored the same45-file design-only allowlist via official Cloudflare2026.9.3; current link: https://cage-sustained-copy-when.trycloudflare.com/instrument.html?switch=poster&medium=manga&embed=1. Only the remaining authorized duration is used, still stopping4October02:39 Europe/Berlin. No account/backend data, share-scope expansion, recurring automation or TTL renewal. Replacement public page and loaded artwork verified; original Coming Up local/browser checks remain valid.


### 3 October — iPad access recovery

**iPad preview recovery (2026-10-03, 21:34 Berlin):** Owner reported the replacement link did not work. The previous8814 listener and temporary binary were absent; the cage-sustained-copy-when link did not resolve. Restored the same45-file allowlisted preview with official Cloudflare2026.9.3 in the visualization runtime folder, using a detached subprocess rather than a foreground chat-terminal session. Current link: https://ratio-yarn-raise-scholarships.trycloudflare.com/instrument.html?switch=poster&medium=manga. Original automatic stop remains4October02:39 Europe/Berlin; no renewed duration, recurring service or expanded public files. Fresh HTTP200 for HTML/CSS/Instrument/Library modules and404 for .env/current-state docs. Browser tool is currently unavailable, so no new screenshot, Safari or iPad visual proof claimed. No UI/native/backend source changes; two-wave v0.8 implementation plan remains INCOMPLETE and unstarted.

Runtime: /Users/max/.codex/visualizations/2026/09/25/01a0d8bc-4563-78f3-a469-ddbd6dbe20e7/kuro-preview-runtime contains the official binary/archive and preview.log, outside the served allowlist. Python PID46077 uses start_new_session=True, DEVNULL stdin and file-backed logs. TTL calculated only to original2026-10-04T00:39Z deadline. Host shutdown/sleep may still interrupt access; no guaranteed availability.


## Manga story overview — 4 October 2026

The four missing story fixtures now separate a short editorial hook from an actual premise and a collapsed longer synopsis. All six current Library reads have story copy. Generic missing Manga copy states unavailable instead of duplicating its mood descriptor. Home, chapter counters, buttons, artwork and clubs stay unchanged. Four existing files changed: instrument-detail-data.js, instrument.js, instrument.html and manga-library.html; no asset/file additions or deletions. Detail-data54/JS61; Library iframe61 forces the updated document after a stale embedded preview was observed.

New copy is paraphrased from primary publisher sources; hooks/lenses are editorial: [Solo Leveling comic volume1](https://yenpress.com/titles/9781975319434-solo-leveling-vol-1-comic), [Berserk publisher catalogue](https://images.darkhorse.com/common/salestools/catalogs/DH_Backlist_2011.pdf), [SPY x FAMILY volume1](https://www.viz.com/manga-books/manga/spy-x-family-volume-1/product/6302/digital), [Vagabond](https://www.viz.com/vagabond). storySource records provenance in each new fixture; this is manually researched sample copy, not automatic ingestion. No new unverified casts or adaptation links were invented.

Checks: node syntax for both changed JS modules; local browser all six current reads have a premise and initially collapsed synopsis; Solo synopsis expands; opening/closing does not change chapter positions (24,8,16,12,5,40); anime JJK seasons1/2 retain distinct hooks;390x667 detail has no page overflow. Screenshot: visualization root/manga-story-overview.png. Historical MutationObserver errors predate this check; no new entries observed. This narrow copy change did not rerun progress mutation/failure suites. Native/Safari/VoiceOver/backend proof remains unverified.
