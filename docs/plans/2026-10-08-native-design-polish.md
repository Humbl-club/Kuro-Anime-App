# Kuro native design polish plan

Refine Home, Anime and Manga details, and Profile into one coherent native experience. Preserve the selected Poster switch, shallow Anime scenes, equal Manga covers and existing tracking, import and privacy behavior. The opening for an empty Library must feel alive through artwork, large readable type and restrained motion. Use a neutral page palette and make Profile a clear personal account hub.

Status: first native pass built on 9 October 2026 and installed on the owned simulator. Owner visual acceptance is still open. The compositions are scoped to Home, series detail and Profile; other pages keep their previous surfaces. No deployed contract changed. The existing import completion plan and its finding register remain the functional authority; this plan governs presentation and the Profile refinement.

## Executor brief

> Read this plan, the accepted Home design decisions and current source before editing. Preserve unrelated dirty changes and previously accepted behavior. Create a cohesive native refinement using existing Kuro assets, components and capability owners. Start with shared palette, typography and motion rules, then demonstrate the empty Home, populated Anime and Manga Home, their detail screens and Profile together. Keep tracking, source identity, account isolation, import recovery and Undo on their existing owners. Implement approved visual compositions with proportional checks and deliver them on the existing owned simulator. Do not deploy, enable global Home rollout, upload to TestFlight, introduce a second navigation or persistence system, or turn a passing build into visual acceptance. Expose remaining connector qualification separately from design review.

## Current design problems

- Home and detail use hardcoded cream surfaces such as `FFFEF8`; the login welcome uses white and Profile uses a separate glass/backdrop system. The color and surface languages diverge.
- The empty Home repeats absence through the Library message, zero-count calendar and empty private-club section. Its import action is plain text and leads into a long Profile menu.
- Anime cards devote excessive space to their dark metadata block. Progress, season labels and artwork compete for attention.
- Manga titles, chapter positions and advance keys lack a consistent shelf rhythm. Equal covers alone do not resolve alignment and control weight.
- Detail uses large utility panels and numbered season tiles that lose the selected artwork-led treatment.
- Profile prioritizes a glass initial badge, generic account label, six statistic tiles and a long undifferentiated action stack. Provider states and technical limitations interrupt the hierarchy.

The source currently uses `AuthSceneryLoop` and the bundled `KuroZenMountains` artwork for the login welcome. The current onboarding source uses a card pager and ordinary transition animation. Reuse the welcome's visual language; do not assume both surfaces already share an animation component. The existing scenery loop also needs explicit visibility and Reduce Motion controls before reuse.

## Shared visual rules

### Palette

Use clean white as the proposed primary page background. A neutral off-white is suitable for secondary surfaces; neither should have a yellow or green cast. Review white and neutral gray with the same artwork before freezing the tokens. Do not build a large theme comparison.

| Role | Proposed starting value | Use |
| --- | --- | --- |
| Page | `#FFFFFF` | Home, detail and Profile canvas |
| Quiet surface | `#F6F6F6` | Secondary groups and contained controls |
| Primary ink | `#181818` | Headlines, title names and primary actions |
| Secondary ink | `#5C5C5C` | Explanatory text and ordinary metadata |
| Quiet readable ink | `#6B6B6B` | Small captions on white |
| Hairline | Black at 8–12% | Separators where grouping needs them |
| Artwork material | Existing verified material for the displayed image | Local Anime scene or private-room treatment |

These are proposed role values, not instructions to scatter hex literals. Freeze them in `KuroDesignSystem` and adopt them in the scoped screens. Avoid changing unrelated global tokens without inspecting their consumers. Let actual artwork retain its own colors. Keep statuses monochrome and destructive actions red. Choose foreground and overlays for the actual background, including bright artwork; no reliance on a pale placeholder being readable.

### Typography and geometry

Use Kuro's scaled serif roles for the main invitation and editorial headings. Use its scaled sans-serif roles for title labels, buttons and settings. Map the typography roles once; avoid independent font choices per screen. Aim for readable body text around 15–17 points and ordinary control/metadata text around 12–15 points at default size. Reserve tiny captions for nonessential decoration.

Keep outer gutters consistent, normally 20 points with adaptive narrow-phone behavior. Use the existing 4/8/16/24/32 spacing scale. Align titles, artwork and controls deliberately. Retain equal Manga frames, natural artwork ratios and at least 44-point interactive targets. The visible button can be quieter than its touch area. Let large text reflow instead of clipping or shrinking essential copy.

### Motion

Give motion three jobs: a calm welcome scene, a clear context change and immediate action feedback. Empty Home may use one slow ambient pan or drift; text and controls stay stable. Medium changes and opening details use a short, restrained transition. Progress confirmation responds beside the changed title and keeps Undo discoverable.

Do not make the whole Home or Profile animate continuously. Stop decorative work when the surface is offscreen, backgrounded or dismissed. Reduce Motion shows a deliberately composed still frame and preserves every action. Low Power Mode uses the still treatment. Assets are decoded once and cached; frame updates cannot trigger networking or rebuild the Library. No new animation framework is needed.

## Empty Home and first actions

### Composition

Use a substantial image-led opening, sized to fit the available phone height while keeping the primary actions reachable. The scene fills the upper composition and blends into the neutral page. Place large editorial type over a quiet region of the artwork, with a localized neutral contrast layer where required. On larger text sizes, allow the type to move below the image while keeping the same composition and hierarchy.

Proposed headline: **Your next story starts here.** Supporting copy: **Find something to watch or read, or bring the list you already have.** These are draft product strings, to be reviewed in English and German.

Reuse the existing Kuro landscape as the reliable offline starting asset. Review its warm sky against the new neutral canvas; adjust the local display treatment or choose another existing Kuro asset if it still creates the unwanted yellow cast. Keep image color local to the scene. Do not manufacture anime characters or suggest that decorative artwork represents a particular catalog title.

### Actions

- **Find your first title** is a prominent composed button within or immediately beneath the image treatment. It opens the existing Discover/search experience for the chosen medium through a typed route. It must not silently save a title or alter progress.
- **Import your list** is a second clearly designed action, using the same typography and material language. Open a focused source chooser for AniList, MAL account or MAL XML. It should not make the user navigate the full Profile action stack first.
- Both actions respond immediately and remain available if animation or networking is unavailable. The image conveys atmosphere; labels explain what each action does.
- The source chooser renders actual connector availability and existing connection identity. An unavailable MAL connector is explained within that option, without blocking AniList/XML or the rest of Home. No new login or credential owner is introduced.

### State rules

The large first-title invitation applies to a genuinely empty selected-medium Library. If another medium is populated, keep its visible medium choice and an honest shortcut; never switch automatically. If saved/planned or completed titles exist but nothing is currently in progress, show an appropriate caught-up or saved-title state using existing data and Collection navigation. Do not tell that user they have no titles.

Hide empty private-club furniture and collapse empty release information to a quiet contextual note in this state. Preserve an actual pending import/recovery banner above the invitation. Treat loading, offline, denied/private and failed refresh as their real states; they cannot become a successful empty Library. Once real eligible titles arrive, transition to populated Home without another onboarding step.

## Populated Home

### Anime

Retain shallow landscape scenes and approved season artwork tabs. Tighten the metadata area so image, title and progress feel like one object. Put progress beside its own title; make the advance key consistent with detail. Use restrained material taken from the displayed image, with readable contrast and an honest neutral fallback. Preserve compact secondary titles and the selected medium's scroll position.

### Manga

Retain the Library direction: equal covers, readable names and each book's own chapter position and advance key. Use aligned title regions and progress baselines. Keep cover/title as one detail target and progress as a separate sibling control. Use subtle paper edges and press feedback. Adapt columns to width and text size without offset artwork, masonry, a selected-book workbench or remote controls.

### Calendar and private activity

Keep a compact artwork summary when useful, followed by the complete grouped calendar. Avoid repeating identical headings at equal weight. Dates, unknown announcements and simultaneous releases remain accurate and reachable.

Use private activity as a distinct, inhabited scene when current authorization permits it: actual club identity, title artwork and concise human activity. Reserve the heavier material for meaningful content. Never insert fictional people, club messages or activity into the running account. Failed permission checks clear private content rather than leaving attractive stale artwork.

## Detail screens

Carry each title's displayed artwork and material from Home into detail. Use the same ink, control and spacing roles across both media.

- Anime opens with a shallow scene and compact title/context, followed by the selected season and real story. Replace plain numbered tiles with the intended artwork panels where verified artwork exists; make a deliberate neutral panel when it does not. Selection changes the information below and never changes tracking.
- Manga opens with its portrait book, compact title and bookmark. Keep chapters and any genuine edition/volume identity together. Use a concise tracking control instead of a large empty utility box.
- Preserve supported status, rating, notes, precise unit identity, pending changes and Undo. Make the distinction between an immediate advance and an explicit editor Save legible.
- Keep music, cast, source guidance and private discussion secondary. Missing optional metadata must not dominate the page or break tracking.
- Use one consistent accessible close control whose contrast remains reliable while scrolling. Replace internal-sounding metadata absence messages with concise user wording, without inventing content.

## Profile

Profile becomes a personal account hub with a readable hierarchy. Preserve its current presentation route and account-scoped coordinators.

1. **Identity opening:** a compact avatar/initial, real existing account identity and a restrained artwork band on the neutral canvas. Use already available account-authorized artwork or the bundled Kuro scene. Do not add display-name editing, avatar upload or invented names to this visual initiative. Avoid making a raw email address the dominant headline.
2. **Your Library:** a compact summary of real Anime, Manga and completed counts, with an existing Collection route. Replace the six large statistic tiles with a quieter line or small group. Put supplementary existing statistics in an expandable section only when their semantics and data coverage are accurate. Current progress sums cannot be labeled lifetime viewing history.
3. **Imports and connections:** one coherent group with AniList, MAL account and file import. Show only relevant connected/disconnected state and actions; do not show Disconnect as a primary action when nothing is connected. Keep technical provider-field limitations inside the source review. Preserve persistent results and guarded Undo.
4. **Pending work:** resumable imports and important synchronization failures remain easy to see. If already emphasized near the top, recent history need not duplicate the same active operation. Use the existing server/job and local journal owners.
5. **Clubs and preferences:** a compact route into actual Clubs. Provider preferences remain conditional on their existing feature flag. Do not mount a disabled capability to fill the layout.
6. **Account and privacy:** a separate group for sign out, account deletion, privacy and version information. Keep deletion clearly destructive with its current confirmation and account ticket. Put cache maintenance in a quiet advanced disclosure rather than treating it as a headline account action. A cache reset is not equivalent to deleting customer data.

Use stable section headings, common row geometry and short subtitles. Remove decorative blur blobs, excessive glass surfaces and repeated icon/chevron noise. The identity opening can have a brief entrance; utility rows remain still while the user acts. Do not wholesale remove the current animation-suppression transaction without checking which mutation/toast animations it protects.

## Ownership and implementation sequence

Deliver the refinement in two passes with no schedule estimates.

**Pass one establishes and demonstrates the shared direction.** Freeze scoped palette, typography, geometry and motion roles. Create the empty Home, one representative populated Anime/Manga composition, their detail screens and Profile in the existing native preview/test host. Use the actual SwiftUI components and existing catalog artwork with explicitly controlled preview data. Show the screens together, including the neutral background treatment, image-led first actions and Profile hierarchy. Obtain visual feedback before propagating a rejected composition throughout the app.

**Pass two completes native integration.** Apply the reviewed compositions to real states and routes. Reuse the existing import chooser/coordinator where possible; if presentation requires a focused chooser, expose one small source-selection view owned by Imports. Integrate Profile groups, accessibility, local failure states and motion lifecycle. Install the exact candidate on the owned simulator and demonstrate the scoped interactions. Update the canonical documents and record remaining unrelated release evidence separately.

| Owner | Scoped responsibility |
| --- | --- |
| Design system | Shared neutral palette, scaled type, spacing, control treatment and motion policy |
| Shared presentation | A small reusable artwork scene only if login/empty Home genuinely share it; preserve the login's accepted composition |
| Home presentation | First actions, current titles, calendar and private activity layout |
| Detail presentation | Artwork continuity, selected-season panels, book/bookmark and readable secondary sections |
| Profile presentation | Identity, summaries, grouping and routes |
| Existing capability owners | Identity, permissions, Library mutations, Imports recovery/results/Undo and provider credentials |

Primary source surfaces are `KuroDesignSystem.swift`, `HomeView.swift`, `SeriesDetailViews.swift` and `ProfileView.swift`. Inspect the existing `AuthView.swift`, `OnboardingView.swift`, `ProfileImportCoordinator.swift` and typed routes before any extraction. Keep one lifecycle owner. Split presentation by coherent responsibility where useful; no module-per-row framework. No hard line caps. Do not use parallel agents for planning; coordinate exclusive ownership if later implementation uses independent review or parallel work.

## Proportionate verification and acceptance

This is a visual and native integration initiative. It does not need another unchanged backend suite or live deletion probe. Reuse existing functional evidence unless a change invalidates it. Add a focused regression only where a changed route, state decision, account guard or animation lifecycle has an important unverified failure.

| Check | Required outcome |
| --- | --- |
| Visual fidelity | Owner can review actual native empty/populated Home, both details and Profile together; controls, surfaces and typography clearly belong to the same design |
| First actions | Find opens the chosen medium's existing discovery/search; Import opens focused source selection and existing review/recovery; cancellation preserves Home |
| State fidelity | Empty, caught-up, planned-only, missing artwork, pending import and failed/offline refresh are distinguished correctly |
| Readability | Representative narrow and standard phones, long English/German titles and largest text have no clipped essential content or overlapping actions |
| Accessibility | VoiceOver names and separates title/progress actions; artwork is decorative unless informative; focus follows actual navigation; readable contrast and 44-point targets |
| Motion | Preview shows ordinary motion and a composed Reduce Motion still; background/offscreen work stops; no asset/network requests on each frame |
| Profile | Actual identity/counts/connection state are honest; existing settings, history, Undo, sign out and deletion remain reachable and account guarded |
| Regression | Relevant existing tests and one integrated native compile pass for the final candidate; no repeated broad unchanged suites |

Use a small representative set rather than an exhaustive screenshot matrix. Actual provider consent remains a separate connector blocker; it does not block visual review with controlled preview data. Owner review of the native composition is necessary for visual acceptance. Passing tests establish behavior, not taste. Report visual acceptance, functional checks and installed candidate identity separately. No self-awarded weighted score establishes completion.

## Related authorities

- [Accepted Home and series decisions](2026-10-02-series-and-home-rebuild-DRAFT.md)
- [Import and Library execution plan](2026-10-08-import-library-home-completion.md)
- [Current import finding register](../handoffs/2026-10-08-backend-integration/import-user-journey-review.md)
- [Current deployment and installed evidence](../handoffs/2026-10-08-backend-integration/approved-deployment-live-evidence.md)
- [Original Instrument reference](../../tools/design-directions/instrument.html)
- [Selected Manga Library reference](../../tools/design-directions/manga-library.html)
