# Concierge "Modes Router" Plan (Variation 1)

> **Prototype fidelity, 2 November — COMPLETE ON LOCAL BRANCH `kuro/prototype-fidelity`, NOT DEPLOYED.** Home, detail, first run, Taste and restyled screens follow the approved prototype; 784/784 tests; visual acceptance is the owner's.

> **Prototype-fidelity pass, 1 November — LOCAL BRANCH `kuro/prototype-fidelity`, IN PROGRESS, NOT DEPLOYED.** Plan `docs/superpowers/plans/2026-11-01-prototype-fidelity.md`. Done: Task 1 (reference pack), Task 2 (prototype tokens, sans type ramp, on-device artwork materials), Task 3 (prototype raised keys, confirm/restore/count motion, branded loading/error/offline/empty family, prototype header, `check_branded_states.sh` reported gate), Phase 1 review follow-up (fixes for the Task 2-3 review; gate now scans all of `Kuro/`). Screen lanes 4–9 merged. Task 10 integration done locally (Home embeds the calendar card, club room, manga leaves, footer and new-account block; one span rule; German counts; Taste uses Home's switch; Folio manga key; skeleton visibility; `check_branded_states.sh` blocking with 0 offenders; SessionSDKTests Keychain isolation fix). Native captures done; Home fidelity review (anime + manga, 2 Nov) fixed or justified in `docs/prototype-fidelity/FIDELITY_REVIEW.md`, with three items open for an owner ruling (club verbs, manga released-chapter count, edition language). Pending in Task 10: fidelity review of Detail/Taste/first run, gallery.
>
> **Overnight production pass, 1 November — LOCAL BRANCH `kuro/overnight-2026-11-01`, NOT DEPLOYED.** Release schedule (episode/chapter/volume with certainty) + songs end to end (prepared RPCs/intake, app with silent fallback), DB hot-path fixes prepared, Folio lists, Profile/Discover/Clubs/Auth/Onboarding redesign, auth callback hardening + set-new-password. Owner decisions (licensing, deploy, legal URLs, icon, visual acceptance) open: `docs/overnight-2026-11-01/REPORT.md`.

> **Repository checkpoint, 31 October — OCTOBER WORK COMMITTED LOCALLY; GATES PASS.** Five grouped local commits on `codex/integrated-testflight` (not pushed) plus backup ref `refs/backup/kuro-snapshot-20261031`. Architecture, docs-count and migration gates pass; runtime force unwraps guarded. Native design visual acceptance still open; no deployment or flag change.

> **Native design polish, 9 October — FULL POSTER HOME; VISUAL ACCEPTANCE OPEN.** Empty invitation unchanged. Saved Anime is shallow scenes with a white foot. Saved Manga is the equal-cover library with the chapter ticket on the cover. Acceptance is still open.

> **Native design polish, 9 October — EMPTY AND SAVED HOME SPLIT; VISUAL ACCEPTANCE OPEN.** Invitation keeps the picture. A saved medium uses the white shelf. Acceptance is still open.

> **Native design polish, 9 October — HOME CONTINUES; VISUAL ACCEPTANCE OPEN.** Full-phone wash, readable Home chrome and medium words, Find opens Discover, import sheet matches the invitation type. Sample titles are a debug launch only. Acceptance is still open.

> **Native design polish, 9 October — INVITATION TYPE; VISUAL ACCEPTANCE OPEN.** Cover line is light serif with tight tracking and a 46×2 ink rule. Find and Import use `kuroKicker` plus a serif line, a full rule, and an arrow. Acceptance is still open.

> **Native design polish, 9 October — PICTURE THROUGH HEADER; VISUAL ACCEPTANCE OPEN.** Home’s picture is pinned full-screen behind the status bar and header when Home is selected; the Home header fill is clear; the selected Anime/Manga word still masks the same image. Snapshot suite re-rendered at 390; Debug installed on the owned simulator with `home-picture-through-header.png`. Acceptance is still open.

> **Native design polish, 9 October — ONE COVER THEN PAPER; VISUAL ACCEPTANCE OPEN.** Empty and populated Home share one cover (ink medium words, one full-bleed image, shared type band and action line) then a paper index for later titles, Coming up and club. Snapshot suite re-rendered at 390; Debug installed on the owned simulator. Acceptance is still open.

> **Native design polish, 9 October — COVER POLISHED; VISUAL ACCEPTANCE OPEN.** The rejected form was replaced by a magnified mountain cover, display type in the ridges, a paired Find/Import line, gradient title feet, circular advance marks, and three large Library figures. Snapshot suite passed. Installed on the owned simulator. Acceptance is still open.

> **Native design polish, 9 October — FIRST PASS INSTALLED; VISUAL ACCEPTANCE OPEN.** The scoped Home, detail and Profile compositions are in the app and on the owned simulator. Empty, saved and in-progress shelves are distinct. Find and Import use existing search and import owners. Owner review of the rendered screens is still required before calling the direction accepted. Import/Library qualification, MAL account access and the recorded Storage CDN failure are unchanged. No deploy, commit or TestFlight.

> **Fresh-session continuation, 8 October — HANDOFF SAVED; IMPLEMENTATION STATUS UNCHANGED.** Prepared the handoff and executor prompt for the current native design-polish plan and remaining import/Library qualification. It preserves the simulator-only target, two presentation passes, existing functional contracts and proportionate checks. Fresh Git/live/installed provenance distinguishes completed deployment from unmerged local work. Corrected stale current-summary statements about pending deployment, an open MAL login and an uninstalled Manga fix; historical evidence retained. No runtime work. [Full handoff](docs/handoffs/2026-10-08-fresh-session/HANDOFF.md) · [Paste-ready prompt](docs/handoffs/2026-10-08-fresh-session/START_PROMPT.md).

> **Home and Profile visual polish, 8 October — PLANNED.** User-requested presentation scope now includes image-led animated empty Home, shared neutral colors, populated Home/detail fidelity and Profile reorganization. The saved plan defines two native passes: shared direction and preview, then reviewed integration and simulator delivery. The import completion plan and single finding register remain the functional authority; this is a linked visual workstream. [Full plan](docs/plans/2026-10-08-native-design-polish.md).

> **Import/Library/Home execution, 8 October — approved backend deployed; installed qualification in progress.** The canonical two-wave implementation remains the scope. Exact four-SQL/six-Edge deployment completed and effective identities verified. Real v2 import/replay/Keep/update/conflict/Stop/Undo/owner isolation and Realtime pass with administrative disposable cleanup. Origin deletion and old-token upload denial pass; cached-public-URL propagation remains disclosed. Accepted Home/detail presentation repairs and actual Library reader correction are built and installed; restored Home is visible. First-time Manga cache-selection repair is independently accepted, built, exactly installed and actual Anime→Manga selection verified. A controlled MAL user account is unavailable; real account-connector qualification is specifically blocked. Other included provider/recovery/navigation journeys and final simulator verdict remain pending. No TestFlight/public submission/global Home activation/backfill/worker scheduling. [Current evidence](docs/handoffs/2026-10-08-backend-integration/approved-deployment-live-evidence.md). Earlier conflicting status notes are historical.


> **Import integration, 8 October — REQUEST CHANGES / TWO-WAVE REPAIR REQUIRED.** The deeper27-finding review supersedes previous broad backend source/local acceptance. Six structured database defects and focused XML parser defects were reproduced locally. Wave1 repairs typed existing-title policy, ingestion fidelity, recoverable manifests, terminal cleanup, stop/results contracts and authoritative Library projections. Wave2 wires actual AniList/MAL entrypoints, persistent review/results/navigation, bounded refresh and installed simulator/live qualification after an approved revised deployment. Prior accepted legacy Apply/Undo remains accepted; no blanket retest or new framework is required. Deployment manifest is HOLD; no code repair/deployment/rollout/TestFlight in this review. [Full findings and risk-matched execution](docs/handoffs/2026-10-08-backend-integration/import-user-journey-review.md).

> **Backend execution checkpoint, 8 October — IN PROGRESS / NOT DEPLOYED.** Fresh effective live/source audit expands the obsolete two-SQL proposal to exactly3SQL+6Edge closures. New status/precise Undo/lifecycle repair and atomic assembly are independently source accepted; exact rehearsal118assertions passes (9 history/install/data,40SQL81,69SQL94), original input hashes retained. Six Edge closures match prior accepted checkpoint. Existing CLI administration and read-only Auth/Storage cleanup verification are available. Preserve live5% RAG and disabled global Home; use Debug simulator override only after live contracts verified. Disclose legacy_lifecycle_unavailable for older Undo journals; no session backfill/scheduler. Remaining: specific live deploy approval, named deployment and postflight, installed Home/import/recovery/MAL consent and changed live service/cleanup proof. Simulator-only target; release/physical requirements remain historical/out of current delivery. [Complete backend integration](docs/handoffs/2026-10-08-backend-integration/backend-integration.md).

> **MAL registration/configuration, 8 October — SIMULATOR CONFIGURED; SERVER INTEGRATION BLOCKED.** User screenshots verify the published native iOS registration and exact kuro://mal/callback. Debug.xcconfig enables the public client only for iphonesimulator; Shared/Release remain disabled and no confidential secret is embedded. Normal signed build/install and matching built Info.plist pass. Actual Profile exposes Connect and import MAL, which reports Library synchronization is not enabled yet before any provider consent. Existing sign-in survives the update. Exact Home/import SQL is still prepared/rehearsed, not deployed; controlled OAuth and real import/recovery remain pending. No live schema/grant/flag changes, archive or TestFlight. [Evidence](docs/handoffs/2026-10-08-simulator-qualification/qualification.md). Earlier banners are historical where superseded.

> **Latest simulator qualification, 8 October — SIGN-IN / RESTORE / SIGN-OUT PASS; MAL CLIENT ID PENDING.** Actual normal password-form sign-in and restart restore pass on com.Kuro.app. A dedicated iPhone17Pro/iOS26.0 simulator also proves supported SDK callback, same-account restore and immediate sign-out to AuthView. Earlier callback FAIL is not current-artifact proof: the original simulator has a canvas preview also claiming kuro://; old observations remain historical. Existing preview apps/data were preserved; no production auth repair or unchanged broad suite rerun. Owner reports MAL registration complete; site policy blocks reading issued client values, public Client ID requested, connector remains disabled. Home/import candidate RPCs still absent live. No new live account, admin/schema/flag/deploy/TestFlight changes. [Current installed proof](docs/handoffs/2026-10-08-simulator-qualification/qualification.md). Earlier banners are superseded where they conflict.

> **Latest access initiative, 7 October — SIGN-IN PASS / RESTORE FAIL / MAL HANDOFF.** One owner-authorized ordinary persistent GoTrue development account was created; credentials retained privately outside the repo. Genuine password sign-in and authenticated identity pass, and the simulator Profile shows the expected development email/build1.0(17). Ordinary restart returns to welcome, including after normal signed build/install; root cause unresolved, no auth-code repair claimed. Final simulator is signed in again. MAL registration is confirmed open in the sidebar for manual owner completion under the existing site-security restriction; client remains unconfigured. No existing account changes, admin grants, schema/flags/deploy/TestFlight. Prior unchanged local evidence remains valid at its layer; installed restore is a new failed check. [Evidence](docs/handoffs/2026-10-07-integrated-release-evidence/development-account-sidebar-handoff.md). Earlier banners are historical where superseded.

> **Latest simulator execution, 7 October — LOCAL CHECKS PASS / LIVE INTEGRATION PENDING.** All387 distinct native cases have passing evidence across the initial362-case run, affected-suite repairs and the previous19SDK/6import cases; no unchanged whole-suite rerun. Four test files repaired with focused independent acceptance; production guards unchanged. The selected16SQL suites pass511assertions, and the exact two-migration atomic transaction/history rehearsal passes31assertions. Backend imports pass52tests/typecheck. Latest Debug1.0(17) is installed/launched on iPhone17Pro/iOS26.0 and the real sign-in form is open; signed-in workflows remain unverified. Live read-only preflight confirms all20newfoundation tables absent/all31existing prerequisites present, no orphan list rows, current deletion helper reviewed. No live changes/deployment/global rollout or TestFlight. Actual sign-in, specific production-grant approval and controlled MAL registration/consent remain pending. [Current evidence](docs/handoffs/2026-10-07-integrated-release-evidence/simulator-integration-progress.json). Earlier banners are historical where superseded.

> **Latest simulator follow-through, 7 October — INTEGRATION IN PROGRESS.** Owner authorized live sign-in/Home/import/recovery checks. Focused Xcode SDK authentication: 19 PASS, 0 failures; import apply/outcome/retry/Undo: 6 PASS. Controlled HTTP is used, so these are native SDK proof, not live UI/GoTrue/Home proof. Initial 21-pass/4-fail run is retained. Two fixture issues were corrected without weakening assertions: per-scenario real SQLite/WAL injection prevents shared-file cleanup contention, and the stale-account fixture now really returns A then B. Independent review accepted the narrow change; production storage defaults are unchanged. Two further read-only live audits confirm eight new Home/tracking/import RPCs and eight checked foundation tables are absent; live has nine 5 October migrations plus 6 October import-session policy. Aggregate existing list rows: 37 Anime, 11 Manga. Exact two-migration deployment draft is prepared, not applied; global flags stay off. Real simulator login and concrete production-grant approval are pending. Native UI automation timed out after the clone test run. No live account/customer/schema/flag changes, TestFlight or upload. [Evidence](docs/handoffs/2026-10-07-integrated-release-evidence/simulator-auth-import-recovery.md). Earlier status banners below are historical and superseded where they conflict.

> **Current target, 7 October — SIMULATOR ONLY / INTEGRATION IN PROGRESS.** Max explicitly removed TestFlight upload and physical-device delivery from this initiative. Debug 1.0 (17), bundle com.Kuro.app, built successfully and is installed/launched on iPhone 17 Pro / iOS 26.0; onboarding is visually verified, not a signed-in workflow pass. Supabase browser administration now works through existing GitHub sign-in. Two bounded read-only live audits found no malformed/noncanonical/colliding legacy list IDs, and confirmed exact auth.uid()::text owner policies. The six Home/detail/page RPCs, Home flag rows and feature_flag_overrides table are absent on the live project. No schema/customer/flag changes or deployment. MAL registration is pending: the browser site policy blocks apiconfig/create; the user must complete the prepared form and provide the Client ID. Existing 81 package / 5 snapshot / 3 contract passes remain valid; the broader native runner stays incomplete. Signing agreements, archive, upload, TestFlight and physical qualification are outside the current target. [Execution and evidence](docs/handoffs/2026-10-07-integrated-testflight-execution.md).

> **Access refresh, 7 October — NOT RELEASED.** Xcode27.0 first-launch validation passes. Actual package81tests, Home snapshot5cases and credential/permission contract3cases PASS. Native compilation errors (missing KuroCore import and duplicate Home declaration) and three outdated test fixtures are repaired and independently source-accepted. The broader native runner stalled after its logged host exited; it was interrupted and has no finalized acceptance result. No whole-native PASS is claimed. Physical iPhone “Max” is paired/booted on iOS26.6; one development and one distribution signing identity are present. Existing ASC key4Y9VLAQLQN returns403 `FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`; the Account Holder must review agreements, then team/app/upload permissions can be checked. Fastlane references an absent older key. Supabase administration and controlled MAL registration/consent are still unavailable. No credential changes, backend deployment, upload or physical installation. Earlier license/hardware absence notes are superseded by these observations.


> **Current implementation-stage result — IN PROGRESS / NOT RELEASED.** Proportionate gates are implemented in Fastlane: affected local checks during development, one integrated native/package/backend/selected-SQL verification, then real service and installed TestFlight proof. Future signing/live/device access is not due during development; correctness/privacy/replay and required workflows remain mandatory for release. MAL account ingestion for both media is implemented, primary contracts retrieved and source-reviewed, with controlled registration/consent still unavailable. Original-account/mount admission, Collection batch isolation, stale conflict controls and Profile deletion/preferences are repaired and independently source-accepted. Actual Core action tests, MAL reader, Library/Home/SQLite and Collection policy checks pass. Ten affected PostgreSQL suites pass253assertions, all12prepared migrations apply; historical baseline replay stays incomplete. No deployment, archive, upload or installation. Xcode license, Supabase administration, signing, controlled MAL consent and physical-device proof remain the precise release prerequisites. See [the complete executor/evidence/checklist](docs/handoffs/2026-10-07-integrated-testflight-execution.md).


> **Approved integrated scope — IN PROGRESS / NOT COMPLETE.** Execute exactly two waves covering modularity and accepted Home/series together; end at qualified installed TestFlight with App Store submission prepared. Required AniList/MAL account/XML for both media, bounded live qualification, five binary gates and proportionate checks supersede old separate-scope/extreme-load requirements. Current source/local repairs and all114findings are in [the integrated executor](docs/handoffs/2026-10-07-integrated-testflight-execution.md). No deployment/upload/device qualification by this continuation.



> **Home/detail R01–R16 repair status (2026-10-07): IN PROGRESS.** Source repair and local regression evidence are recorded in [REPAIR_LEDGER.md](docs/handoffs/2026-10-07-home-series-evidence/REPAIR_LEDGER.md): 76 package tests, actual Home/SQLite drain and exact cursor PASS; AniList 7 PASS; enrichment 8 PASS. Current SQL95/96, native SDK/visual/device, revised EXPLAIN and hosted/released proof remain blocked or unrun. Earlier independent review remains the historical findings baseline; focused producer/privacy deltas are source-accepted, not whole-candidate approval. Exactly two waves remain. The later user-approved [integrated execution contract](docs/handoffs/2026-10-07-integrated-testflight-execution.md#bounded-launch-envelope) supersedes extreme concurrency acceptance with its measured bounded launch envelope; no thousands-session claim. Global flags stay off and the foundation SQL remains prepared, not deployed.

**Modular architecture migration status (2026-10-07): LOCAL + PARTIAL LIVE (uncommitted; not an App Store release).** Stages E0–E8 of the [execution brief](docs/plans/2026-10-05-modular-architecture-plan.md) were carried out in this checkout; the brief entry below ("execution NOT STARTED") is superseded. Gate status remains: **G0–G7 are not all passed** (see the [completion ledger](docs/plans/2026-10-05-modularity-completion-ledger.md) and [register](docs/plans/2026-10-05-modularity-completion-register.csv)). Live on `bkdifromsqxkndnllmdj`: October SQL (incl. `20261006120000` import-session SELECT-only), `delete-account` v9, Apply v26, Undo v17, `concierge-retrieve-assist` v8 (`rag_assist_v1` still off). Client switches now match that server: `sendsStoredRatingAndNotes=false`; `listensToLegacyContentTables=false` after a live member/non-member `club_activity_signals` check; `ClubError` reads PostgREST `details`; account-switch clears Concierge/Clubs/Collection private state. Locked product rules: ambiguous parse does not auto-apply when `clarify_v2` is off; Finished with no title stores no status; bare numbers stay in titles; AniList 200 / Apply first 100 with omitted copy; private club cards show count only. The sixteen route smoke journeys in `docs/modules/README.md` stay a simulator checklist, not a claimed pass. Home/detail v1.1 waves remain separate and NOT STARTED. Multi-user verification harness (2026-10-07): `test_leftovers_verify.sh` + `MultiUserPageOrchestrationTests` (passed) + `scripts/live/probe_*.js` (import SELECT-only + club_activity_signals realtime). Still not G0–G7; 16 journeys still NOT run.

**Modularity execution brief (2026-10-05):** [Claude Code execution brief](docs/plans/2026-10-05-modular-architecture-plan.md) supersedes the earlier architecture order/effort assessment with a prompt-first autonomous multi-agent contract, 35/25/20/10/10 decision weights, mandatory G0–G7 gates, risk-specific tests, coordinated E0–E8 integration and independent review. No source-length caps, target quota, schedule or effort estimates. Explicit lifecycle repair precedes packages; current production ownership includes social/provider preferences/realm/telemetry, shared UI/routes and active operations. Architectural execution NOT STARTED; every stage and gate remains unverified. Existing Home/detail v1.1 scope and two delivery waves remain separate and unchanged. Documentation only; no app/backend/prototype/CI changes or deployment/capacity proof.

**Home/detail production handoff v1.1 (2026-10-05):** Planning COMPLETE for requested scope. New start-ready Claude Code handout exports the same singular master plan with initial database audit, every-call growth review, concurrency/rapid-edit/lifecycle guarantees, revocation-safe private clubs, both-provider import fidelity and1000/5000-session qualification. Exactly F1–F3 and X1–X3 in two waves; execution NOT STARTED, wave gates NOT PASSED, capacity/staging/live/released NOT VERIFIED.46 preview/dependency files pinned; no implementation, deployment or new sharing/automation.

**Home/detail execution specification v1.0 (2026-10-04):** Planning COMPLETE FOR REQUESTED HOME/DETAIL SCOPE in the existing singular master plan. Exactly two waves: F1–F3 foundation and X1–X3 native/wiring/qualification, with the original16 task IDs retained for traceability. Both execution waves NOT STARTED, gates NOT PASSED, staging/live/released NOT VERIFIED. Previous incomplete draft snapshots below are historical and superseded by v1.0 planning status. No implementation, deployment or public share in this initiative.

**Master-plan retention (2026-10-04):** At Max’s request, the existing singular series/Home master plan now explicitly lists ID-based Anime/Manga matching and real Manga story overview copy in its decision register. Existing detailed requirements and success criteria are retained. Documentation-only; no prototype/native/backend changes. v0.8 remains INCOMPLETE, exactly two waves/16 tasks, native/backend NOT STARTED.

**Manga story overview checkpoint (2026-10-04):** Browser-only story-copy gap closed for all six Library reads; four missing publisher-backed fixtures added and unknown generic Manga copy uses an unavailable state. Optional synopsis disclosure and Anime season copy checked, Home/progress unchanged. Four existing prototype files edited (detail-data54/JS61, Library iframe61). Identity-safe adaptation matching and deferred missing-target resolution recorded in the existing singular draft. v0.8 remains INCOMPLETE; exactly two waves/16 parent tasks, native/backend work NOT STARTED. No deploy, commit, new public share or device proof.

**iPad preview recovery (2026-10-03, 21:34 Berlin):** Owner reported the replacement link did not work. The previous8814 listener and temporary binary were absent; the cage-sustained-copy-when link did not resolve. Restored the same45-file allowlisted preview with official Cloudflare2026.9.3 in the visualization runtime folder, using a detached subprocess rather than a foreground chat-terminal session. Current link: https://ratio-yarn-raise-scholarships.trycloudflare.com/instrument.html?switch=poster&medium=manga. Original automatic stop remains4October02:39 Europe/Berlin; no renewed duration, recurring service or expanded public files. Fresh HTTP200 for HTML/CSS/Instrument/Library modules and404 for .env/current-state docs. Browser tool is currently unavailable, so no new screenshot, Safari or iPad visual proof claimed. No UI/native/backend source changes; two-wave v0.8 implementation plan remains INCOMPLETE and unstarted.

**Temporary preview restored (2026-10-03):** Browser/app restart stopped the earlier preview and removed its temporary binary/screenshot. The old trees-marc-amongst-obtain link is unavailable. Restored the same45-file design-only allowlist via official Cloudflare2026.9.3; current link: https://cage-sustained-copy-when.trycloudflare.com/instrument.html?switch=poster&medium=manga&embed=1. Only the remaining authorized duration is used, still stopping4October02:39 Europe/Berlin. No account/backend data, share-scope expansion, recurring automation or TTL renewal. Replacement public page and loaded artwork verified; original Coming Up local/browser checks remain valid.

**Coming Up phone checkpoint (2026-10-03):** Local Instrument adds a first-viewport release summary, using the existing calendar fixture source and one accessible jump to the full calendar.320x568/390x667/390x844, both media, keyboard/focus/reduced motion,48 releases/8 dates, undated/new/caught-up/Taste checks pass. Library per-book foundation liked by owner; this new summary still awaits review. No native/backend execution, deployment, share scope expansion or TTL renewal. Singular v0.8 remains INCOMPLETE, exactly two unstarted waves.

**Temporary review access (2026-10-03):** Owner requested a phone-accessible public preview. Current allowlisted Instrument share runs for12hours, stopping by4October02:39 Europe/Berlin. Public file/access and390px browser rendering checks pass; native Safari/device proof remains open. This review link does not complete native/backend work or imply owner design approval; v0.8 remains INCOMPLETE with two unstarted waves.

**Library per-book tracking checkpoint (2026-10-03):** Owner rejected previous Open-button/shared-selection design. New local proposal removes that model and attaches existing chapter actions to each read. Equal artwork and44px controls checked with navigation, independent updates and failure/completion/Undo. Approval and native testing remain open. Singular v0.8 plan stays INCOMPLETE, exactly two unstarted native/backend waves.

**Library independent-actions checkpoint (2026-10-03):** Replaced rejected select-via-details model: whole-book selection stays on Home; each book has its own full-width44px Open action that preserves selection. Removed redundant workbench Details action. Local320/390px functional/focus/progress failure/completion/Undo/reduced-motion checks pass. Physical-device usability remains open. Singular v0.8 plan stays INCOMPLETE, exactly two unstarted native/backend waves.

**Library direct-detail checkpoint (2026-10-03):** Removed the bar-only detail restriction. One whole-book tap opens its story and synchronises the shared workbench; existing Details is an optional shortcut. Local navigation/focus/phone/progress failure/completion/Undo/reduced-motion checks pass. Physical-device gesture checks remain open. Singular v0.8 series/Home plan stays INCOMPLETE, exactly two unstarted native/backend waves.

**Library touch-target checkpoint (2026-10-03):** Unified artwork/title/chapter selection and moved detail navigation to a labelled83x44 workbench button. Local320/390px geometry, selection/detail/focus and chapter failure/completion/Undo checked. Native translation and physical-device usability remain open. Singular series/Home draft remains v0.8 INCOMPLETE, exactly two unstarted native/backend waves.

**Selected Library checkpoint (2026-10-03):** Max selected Library for Manga Home. Local Poster Manga now defaults to the selected composition; `manga-library.html` shows its polish. Equal artwork, selected frame, aligned labels, shared Next control, known-total trace and keyboard selection checked locally with failure/completion/Undo and navigation. No native/backend production task is complete. The singular series/Home plan stays v0.8 INCOMPLETE, exactly two unstarted implementation waves.

**Four Manga philosophy checkpoint (2026-10-03):** Crosscut is rejected: no offset or unequal manga artwork/containers. Added Library (cover index/shared workbench), Chapter Board (uniform tracking instrument), Journal (sample recency timeline), and Club Room (shared/private reading table plus solo reads) in `manga-four.html`, with equal artwork sizing per study. Local functional/phone/failure/Undo/reduced-motion checks pass; none is selected or native implementation. The singular series/Home draft remains v0.8 INCOMPLETE with two unstarted native/backend waves.

**Manga composition checkpoint (2026-10-03):** Owner rejected Edition/Contact/Index, including the dark-skin approach. New Crosscut browser proposal uses alternating artwork panels and chapter gutters, with existing tracking and navigation behavior. Reviewed 320/390px fit, six loaded covers, 44px keys, failure/completion/Undo, unknown totals, dense releases, empty/caught-up/undated fixtures, details/clubs/Taste/Anime and reduced motion. Owner approval remains open. Singular series/Home plan remains v0.8 INCOMPLETE, exactly two unstarted native/backend waves. No production task is completed by this study.

**Manga design options checkpoint (2026-10-03):** Added three opt-in browser Home studies and `manga-options.html` comparison: Edition, Contact and Index. They reuse existing fixture interactions, with local phone/failure/Undo/calendar checks. No option has owner approval. Default v53 remains unchanged; the singular series/Home plan stays v0.8 INCOMPLETE, exactly two unstarted native/backend waves. These studies do not mark a production task complete.

**Design research checkpoint (2026-10-03):** Local `manga-reference-study.html` compares five official product references with explicit Kuro translations. Home v53 remains unchanged and owner review is pending. The singular series/Home plan remains v0.8 INCOMPLETE with exactly two waves and native/backend execution NOT STARTED. Phone-width/reference-board checks are browser proof only; no app implementation task is completed by this research.

**Manga reading jackets (2026-10-02, v53):** User requested a more attractive, distinctive and easy-to-navigate Manga Home from the reader's perspective. Replaced the v52 narrow side margins with chapter bookmarks attached to the two lead artworks, giving covers more visual space. Four additional reads now share a compact two-column index rather than four full-width rows; chapter controls and title labels align, with club readers and new-chapter notices retained. Light existing surface; creativity comes from attached paper geometry, typography and density, without a new colored background or asset. All covers, chapter keys and reader links have at least 44px targets. Existing in-place count/page feedback, failure, undo and Reduce Motion guards reused. Local checks: 320px page, phone and all six article widths without overflow; full-image containment; six chapter targets; failed change leaves 24 unchanged; completion to 25 disables key; undo to 24; unknown-total Berserk update/undo; private club detail access; release-day expansion; caught-up and new-account states; Taste access; Anime/Manga keyboard selection under Reduce Motion. Browser fixtures only, not physical-device, backend or durable-offline proof. Poster, Anime, details, Coming Up and Sunday Club retained. Proposal pending owner review. No new/deleted repository files or assets, native/backend changes, commit or deployment.

**Manga chapter margins (2026-10-02, v52):** Owner rejected v51 as excessive and explicitly requested structural creativity rather than a large colored surface. Poster Manga now uses two unboxed reading leaves with intact covers, narrow chapter margins and 44px shallow paper keys; four other current reads sit in a compact index below with aligned chapter labels and controls. Removed the v51 cabinet/grid markup and styles. Calm existing light surface, no new decorative color or asset dependency. Coming Up, Sunday Club, selected Poster switch, Anime layout and detail pages retained. Local browser checks: 320px page/phone and leaf widths without overflow, full-cover containment, six 44px chapter controls, failed update leaves chapter 24 unchanged, completion to 25 and disabled caught-up control, undo to 24, unknown-total Berserk 12 to 13 and undo, club discussion access, and tap/arrow-key medium switching under Reduce Motion. No new animation system. All proof is browser-fixture/local only; native, physical touch, backend and durable offline behavior are untested here. v52 is a new proposal awaiting review; v51 is rejected. No new/deleted repository files, native/backend changes, commit, deployment or public hosting.

**Poster Manga ink shelf (2026-10-02, v51):** Owner rejected v50 horizontal reading spreads. Poster Manga now uses a continuous edge-to-edge ink shelf with all six current sample reads in a consistent two-column artwork grid. Intact covers, title, chapter progress and club readers share one hierarchy; there are no individual row cards or separate secondary-title list. Coming Up and Sunday Club retain their existing sections after the shelf. v50-specific markup/styles replaced; other medium-switch families, selected Poster switch, Anime layout and details preserved. Local checks: six covers contained, 320px page/phone without horizontal overflow, 44px chapter targets, failed progress unchanged at 24, completion to 25 and undo to 24, unknown-total Berserk progress/undo without invented totals, title club discussion access, Anime/Manga keyboard selection. Reduce Motion retains the shared animation guard; no new animation system added. All are browser-fixture checks, not native/backend/offline proof. Direction remains a proposal awaiting owner review. No new/deleted repository files, backend/native changes, commits, deployment or public hosting.

**Poster Manga reading spreads (2026-10-02, v50):** Local Poster Manga leads now use two stacked horizontal reading spreads: intact cover on the left; title, prominent chapter progress, release notice and club readers on the right. A restrained artwork-derived paper wash and consistent geometry replace the floating chapter slips for Poster only; Anime and older visual families are preserved. Controls reuse existing progress, undo, failure and detail handlers. Local checks: 320px page/phone fit, 44px chapter targets, complete-cover containment, both medium selections, failure leaves chapter 24 unchanged, completion to 25, undo to 24, Solo Leveling detail opening/closing, and zero selector transitions under Reduce Motion. All activity is fixture data, not native/offline/database proof. Header letter artwork is still the first fixed fixture cover per medium (Demon Slayer/Chainsaw Man), assigned at preview load; no user personalization. Proposed real-app policy: a stable recent-active artwork pick per user/medium for the session, reusing cached artwork with neutral ink for an empty list. Not implemented or approved as production policy. No new/deleted repository files; no native/backend, commit, deployment or public hosting changes. New Manga composition awaits owner review; Poster remains the selected switch direction.

**Poster polish (2026-10-02, v49):** Owner selected Poster from the five visual families ("the poster feels right just needs a polish"). Local Instrument now defaults to `switch=poster`; comparison labels it as the selected direction. Refined 36px artwork typography (30px at narrow widths), readable inactive lettering, a finer baseline with a restrained selection mark, 56px-high targets, press feedback, aligned 5px scene corners and 7px key corners, and quieter Manga chapter-slip edges. Existing Home/Taste, list fixtures, detail interactions and artwork-season markers preserved. Local browser checks: both media at 320px without horizontal overflow, tap/ArrowLeft selection, Home/Taste navigation, and zero selector transitions under Reduce Motion. No new/deleted repository files, native/backend changes, commits, releases or public hosting. Direction selected; exact polish still awaits owner review. Catalogue-wide artwork contrast and native touch/haptics remain unverified.

**Five visual families (2026-10-02, v48):** Owner rejected the v47 material-object switch and requested five substantially different design styles. Local `switch-options.html` now compares Noir (graphite Home with floating bottom control), Poster (artwork-filled type and squared cards), Glass (translucent selector over artwork), Edgewise (vertical publication tabs with reserved margin), and Keys (shallow tactile controls beside release count). Each changes placement and surrounding Home styling; shared tracking/detail fixtures and approved artwork-season badges are preserved. Default local `switch=keys` is an unapproved proposal. All five passed click/arrow-key selection and Anime/Manga 320px overflow checks; targets are at least 44px in both dimensions, and reduced-motion selector transitions are zero. Contrast/cascade fixes cover glass surfaces, key labels, dark reading metadata and edge-tab overflow; empty Glass accounts use a selector in normal flow. No repository files added/deleted. Browser-only samples; physical touch, native haptics, catalogue-wide contrast and safe-area behavior remain unverified. No native/backend, commit, deployment or public hosting changes.

**Material switch study (2026-10-02, v47):** Owner rejected v46 as insufficiently creative. Local comparison now focuses on Frames/Pages: an original generated transparent sprite pairs smoked-glass cinematic panes with ivory folded-paper sheets. Live Anime/Manga buttons remain fixed below navigation, with a fine selection mark, opacity/press states and distinct cancellable settling motion; Reduce Motion disables it. New default `switch=objects` is unapproved. Previous five studies remain under a collapsed disclosure. Local checks: 320px fit, 140×62px targets, taps/ArrowLeft, reduced-motion transitions, blocked-material fallback with working selection and subsequent image recovery. Two new repository files: `assets/medium-objects-v47.png` (2172×724 RGBA, 856277 bytes) and its exact `.prompt.txt`. Original PNG retained unchanged; image is prototype material, not catalogue art. No native/backend, release or public hosting changes; physical touch/haptics unverified.

**Five compact medium studies (2026-10-02, v46):** Owner rejected v45 header positioning and requested five more creative, considered options. Comparison now offers Margin (registration tabs), Exposure (slim artwork windows), Relay (active cover identity plus direct alternate link), Interlock (ink/paper plates sharing a diagonal seam), and Signature (type with a selection bracket). All sit beneath the unchanged navigation, 48–54px high. Each includes design intent/tradeoff outside product UI. Shared semantic medium actions, ArrowLeft/Right and persistence retained; Reduce Motion removes transitions. Local checks: both medium tap and keyboard actions in all five, Anime/Manga 320px fit, targets at least 46px high, and reduced-motion CSS. Relay adds cancellable identity settling; only imagery-based variants render selector images. Default `switch=margin` is a proposal, not approval. No repository files added/deleted; no native/backend, public hosting or release changes. Physical touch gestures/haptics remain unverified.

**Compact Home header (2026-10-02, v45):** Owner rejected the space and composition of v44 and requested a compact, deliberate medium switch. New default `switch=compact` places a 44px-high Anime/Manga control inside the sticky navigation header, removing the separate selector row. Equal targets, small frame/page SVGs, restrained moving surface and press state retain clear medium access; earlier studies remain available. Local checks: 320px Home without horizontal overflow, equal 83×44px targets at that width, tap/arrow-key selection, Taste/Home navigation, normal Anime type and reduced-motion transition removal. Comparison shows both medium layouts. No new/deleted repository files or native/backend/deployment changes. Design proposal awaits owner review; physical iOS gestures/haptics unverified.

**Replacement medium studies (2026-10-02, v44):** Owner rejected v43. Local comparison now presents Shelf (small sample-title cover stacks in two material selections) and Masthead (active editorial name with a cover thumbnail and moving baseline). Shared tap, keyboard and medium persistence logic retained. Local default is `switch=shelf`, not owner approval; v43 remains query-accessible. Verified both tap/arrow-key paths, 320px Home fit, selector targets above 44px, normal Anime/italic Manga styling and reduced-motion transitions for both proposals. Narrow Masthead label spacing corrected. No new/deleted repository files, native/backend changes or deployment; physical touch/haptics remain unverified. Manga folio and approved Home season treatment retained.

**Generated editorial switch (2026-10-02, v43):** Added a custom image-generated continuous Anime-to-Manga panorama, optimized local JPEG, bundled Bodoni Moda normal/italic variable fonts with OFL license, and accessible live medium buttons. Local default is `switch=diptych`; previous variants remain query-accessible. Selection uses live type and a moving ink rule, with restrained press/transition states and Reduce Motion. Missing imagery falls back to neutral surfaces with intact labels and controls. Verified medium taps/keyboard, 320/390px fit, 146px-high targets at 320px, rendered normal/italic style, successful image loading and blocked-image fallback/recovery. Manga folio, detail content and Sunday Club retained. Six asset/provenance files added; no native/backend/release changes. Owner review pending.

**Page-edge switch and Manga folio (2026-10-02, v42):** Local Home replaces the default Ribbon with a medium heading and folded alternate-medium edge button. Manga featured titles use full-cover two-column folios with attached chapter slips, concise release context and named club readers; other reading titles become uniform compact full-width rows. Scene/page entry motion uses the existing cancellable motion helper. Comparison now shows Anime and Manga together, with v41 switches retained under Earlier switch studies. Verified 320/390px fit, equal cover geometry, 44px minimum primary targets, chapter failure/retry/cap/Undo, medium taps/keyboard, Manga detail access, Reduce Motion and new-account state. No native/backend changes; proposal awaits review.

**Switch mechanism redesign (2026-10-02, v41):** Replaced rejected Splice/Fold/Lens studies with Ribbon (film and paper strip), Dial (central media control with rotating index), and Window (expanding artwork panes). All are local proposals selectable through `switch-options.html`; none is owner-approved. Checked all three Anime/Manga tap paths, Dial centre toggle and arrow keys, 320px fit without horizontal overflow, and targets of at least 44px. Reduced-motion styles retained; physical touch scrubbing and native iOS behavior remain unverified. Manga desk and club content retained. No native/backend or deployment changes.

**Manga desk and switch studies (2026-10-02, v40):** Local Manga Home now uses wide reading cards with full-cover artwork, prominent bookmark counts and club-reader context. Coming-up material refined; Sunday Club rendering retained. Added `tools/design-directions/switch-options.html` with three live proposed switch styles: Splice, Fold and Lens. Query parameters select each style; none is owner-approved yet. Moved the existing page-swipe handlers inside the prototype closure to fix their inaccessible state references. Checked 320px fit, matched main heights, chapter failure/retry/Undo, all three medium tap paths and Fold keyboard arrows. Browser proposal only; no native/backend change.

**Manga materials and motion (2026-10-02, v39):** Local Manga Home adds a low-opacity wash from the two featured artwork palettes, softer card/control outlines, bookmark-shaped chapter accents, settling cover presses and a restrained chapter-number page-turn animation. Shelf artwork receives a once-per-session reveal through the existing observer; Reduce Motion disables nonessential motion. Checked 320px fit, chapter increment/Undo and reduced-motion CSS; JavaScript syntax/diff checks passed. Browser prototype only.

**Home and detail closure (2026-10-07):** Local closure of the v1.1 contract is in the working tree and is not a release. Prepared migration `20261007040000_series_home_foundation_v1.sql` is not deployed. `series_foundation_v1` and `series_home_native_v1` stay at 0%. Progress, status and removal use the receipt when the foundation flag is on. MAL XML and AniList structured rows share the import job. Collection, Home load-more and detail season changes use the bundle RPCs when the native flag is on. Throwaway races and import counts passed.

**Finish first Home plan (2026-10-07):** Import-session apply/undo progress/status now share the internal receipt writer in the prepared migration (`81_import_session_receipt.sql` PASS). Concierge remains a sheet. One pending progress map is shared across Home, both series details, and series Collection (not chat UI). Inner EXPLAIN at 1M rows is recorded; 10M optional. Native vs Poster screenshots at 320/390/430 are recorded with a clean rule checklist. Ledger: `docs/handoffs/2026-10-07-home-series-evidence/ledger.md`.

**Home gate recalibration (2026-10-07, docs only):** 1000/5000-session burst/soak demoted from hard release blocker to optional pre-user load tooling. Hard bar: owner-approved migrate; flags still owner-gated; existing throwaway races/receipt/import + 1M plans; device VoiceOver/haptics before native flag at 100%; live check after deploy. Stop before `supabase db push`, edge deploy, or flag enablement until you approve.

 Local Manga Home replaces the plain shared spread with two matched individual book frames, artwork-derived paper materials, inset chapter controls and coordinated compact shelf tiles. Covers retain their full composition; reader/new-chapter context remains available. Anime unchanged. Browser checks: equal main-card heights, no horizontal overflow at 320/390px, 44px main progress targets, simulated failure/retry/Undo. Prototype only; native/backend/offline execution remains planned.

**Horizontal detail and offline plan (2026-10-02, v37):** Corrected the owner request to a shallow full-width Anime image, rather than a taller portrait header. Manga retains a compact book opening and refined bookmark/next-chapter controls. Plan v0.8 remains INCOMPLETE with the same two waves; adds durable account-scoped progress outbox, idempotent revision-checked server writes, reconnect/backoff, account isolation, Undo and conflict criteria. Inspected native progress writes have no durable queue; offline support is planned, not implemented. Local browser checks: 320px Anime/Manga fit and simulated chapter failure/retry/Undo; no native/backend changes.

**Home/Taste and import planning (2026-10-02, v36):** Local detail artwork is larger and joined to the Anime header; Manga uses a larger book-like cover. Existing recommendation cards now live on a separate Taste view, with Home reserved for tracking, upcoming and clubs. New-account Home has an honest import-first empty state. The existing two-wave plan is extended to v0.7 (INCOMPLETE) with structured resumable import, incremental Home revisions, release evidence/precision, provider permission and coverage gates, data contracts and failure/performance criteria. AniList current published terms restrict competing tracker use; expansion requires resolving permission. No native/backend execution or release.

**Anime opening polish (2026-10-02, v35):** Local Instrument Anime details now give the cover up to 160px of width, retain the artwork-derived header colour, and show one season-specific hook before an expandable synopsis. Manga presentation is unchanged. Verified 320/390px dialog fit, synopsis disclosure and season-specific copy switching; JavaScript syntax and diff checks pass. Browser prototype only, not native or deployed. The existing two-wave plan remains INCOMPLETE.

**Artwork continuity and Manga structure (2026-10-02, v34):** Local Instrument now shares saved artwork palettes between Home and details, preserving the approved AoT blue and Demon Slayer teal. Added deterministic `build_art_materials.py` and generated `instrument-art-materials.js` (24 artwork palettes; minimum measured white/base contrast 7.41:1). Manga has chapter bookmarks without Parts navigation. Jujutsu Kaisen links Anime and Manga internally; the finished-season guide never changes reading or anime progress. Missing season images use series artwork; chapter mappings remain unverified. Existing plan v0.6 stays INCOMPLETE with native/backend waves NOT STARTED. No native changes or deployment.

**Detail refinement (2026-10-02, v33):** Local prototype introductions now follow the inspected season/part. Club presentation is artwork-led with “Between us.”, expandable member statuses, retained spoiler disclosures and a redesigned “Leave a thought” entry. Source review confirms flat shared-club title comments/editing/reactions, not reply threads or individual-club rooms; persisted season spoiler scope remains planned. Existing plan v0.5 stays INCOMPLETE. No native/backend changes.

**Detail clubs and manga handoff (2026-10-02, v32):** Local detail prototype now separates shared-club watching/reading/finished activity from club-only comments, with collapsed spoilers and a local-only editable comment preview. Season manga guides distinguish start, end and recommended continuation; unverified chapters remain unknown. Existing two-wave plan is v0.4 and INCOMPLETE. Browser checks covered 320/390/768px fit, empty comment validation, save/edit, failure/retry, spoiler disclosure, new-account omission and reduced-motion navigation. Native/backend/privacy enforcement and exact chapter mappings remain unimplemented by this change.

**Detail polish (2026-10-02, v31):** Local browser detail mockups now have a compact artwork-lit opening, connected season content, next-episode/chapter-first rows, separate completion action, floating Undo and portrait/bio feedback. Extra copy expands on demand; Manga keeps paper styling. Existing series plan extended to v0.3, still INCOMPLETE with two waves. Cover thumbnails and OP/ED stamps are honest artwork fallbacks; no verified chapter mapping or new ingestion. Approved Home markers retained. Native/backend unchanged.

**Detail preview and plan extension (2026-10-02, v30):** Extended the existing [Series and Home rebuild draft](docs/plans/2026-10-02-series-and-home-rebuild-DRAFT.md) to v0.2, still INCOMPLETE with the same two waves and 16 tasks. Added season-scoped detail hierarchy, cast/credits, music source verification, manga continuation mapping, bounded enrichment/caching and failure-path success criteria. Browser cards now open richer details; Jujutsu Kaisen and Chainsaw Man are the main examples. New `instrument-detail-data.js` and seven public catalogue character images support fixtures. Spotify buttons are labelled search links; exact continuation chapters remain unverified. Approved Home markers retained. No native/backend/production implementation.

**Home research status (2026-10-02):** Home v29 saves the owner-selected Artwork tab treatment: only a white Season N marker on main Anime images and an S-number stamp on mapped Also watching covers. Numbered season rows are removed from both sizes. Tapping the marker/compact cover opens the existing full season overview; episode progress remains separate. The comparison board marks Artwork tab as selected and reflects the same simplification. Approval applies to this season treatment, not the complete Home or implementation plan. Browser prototype only; no native/backend deployment.

**Series rebuild planning (2026-10-02):** [Series and Home rebuild draft](docs/plans/2026-10-02-series-and-home-rebuild-DRAFT.md) is explicitly **INCOMPLETE**, with 16 tasks in exactly two waves: catalogue/import foundation, then UI integration and staged delivery. Both waves are NOT STARTED. The draft includes dependencies, success criteria, failure cases, open decisions and space for further owner requirements. No execution or deployment is authorized by the draft.

**Home design status (2026-10-02):** Owner selected Artwork tab, simplified to current-season markers only on main/compact images. Applied to browser Home v29 and saved as the season-design decision. Liked detail overview preserved. Series draft INCOMPLETE; both implementation waves NOT STARTED.

**Architecture/design planning update (2026-09-26):** [Current decisions and audit](docs/research/2026-09-26-kuro-plan/CURRENT_DECISIONS_AND_AUDIT.md), [complete research and execution draft](docs/research/2026-09-26-kuro-plan/KURO_FULL_REVIEW.md), [short visual brief](docs/research/2026-09-26-kuro-plan/MAX_BRIEF.pdf), and [copyable execution prompt](docs/research/2026-09-26-kuro-plan/EXECUTION_PROMPT_DRAFT.md). Seven audit lanes cover all 93 Swift files, 16 local Edge entry points, 235 migrations and 87 operational executable files. Separate registers contain 381 client records, 55 social sites, 229 Edge sites, 427 operational/history records and 57 SQL entries; these are not additive request totals. Sixteen sampled live function bodies match local. Live similarity maintenance ran 287 times/24h, mean 25.89s; background duration is not screen latency. Priorities: rating/mutation correctness, account/cache isolation, redundant refreshes, bounded ingestion/retries, idle/global maintenance, schema replay and metadata freshness. Runtime traces, query plans, installed visuals and full replay remain unverified. No application/backend changes.

**Latest owner direction — 26 September 2026:** Animation belongs to welcome/authentication only. Preserve top navigation and swiping; persist Anime/Manga selection across screens and requests; make Home distinct from Discover/search. Collection is a visual shelf with statuses and optional named shelves. Social relationships are club-only; profiles show identity by default and activity only when enabled. Earlier first-login, Home, agenda, Collection and email concepts, including the moving-landscape Home, are withdrawn. Exact screen layouts and navigation order remain to agree. No implementation or rollout is authorized by these planning documents.

**Approved welcome reference (2026-09-25):** Max confirmed GitHub `b943e457` on `codex/kuro-onboarding-no-tv` as the intended welcome/onboarding: painted scene, grouped wordmark/headline, TV removed. Preserve that composition; the separate local 72%-height composition edits remain untouched and are not the approved baseline. Email/auth logic matches the reference; improvement proposals concern the form and signed-in experience. The GitHub upload is verified, while TestFlight/public release and installed visual equivalence remain unverified. The detailed review now consolidates market, monetization and design decisions; no app implementation.

**Design-review status (2026-09-25):** Documentation-only proposals in `docs/research/2026-09-25-kuro-design-review/`; 16 decisions cover auth continuity, state-aware Home, list reliability, personal agenda and social reuse. Proposed order: (1) rating/save and auth/accessibility correctness, (2) whole-library search/import fidelity, (3) compact personal home, (4) schedule freshness and alert intent, (5) staged recommendation/social exposure, (6) named lists and volume/edition models. None implemented here. Read-only live checks confirm personalized/realm/provider rollout at 0%, sparse future schedules, and rating constraints 1–10; phone build 19 does not establish source-build-17 equivalence. Fresh runtime checks and an explicit implementation initiative remain outstanding.

This file documents the idea of routing free-text "vibe" prompts into curated recommendation rails (modes), with the LLM used only as an optional presentation layer.

## Current status (design/architecture planning addendum 2026-09-26; implementation snapshot 2026-08-06)

Current initiative status: imported-source review, recovery and Library/Home integration is source-repaired; see the current banner and canonical8October specification. Historical feature statuses below retain their original evidence layer.

**Research only — 2026-09-25, revised edition 02:** [Comparative tracking research and free-core monetization](docs/research/2026-09-25-anime-tracking/RESEARCH_AND_DECISIONS.md) now draws on six research lanes, 110 selected source records across 37 hosting domains, and 28 proposed decisions (18 product, 10 monetization), with a [two-page owner brief](docs/research/2026-09-25-anime-tracking/MAX_VISUAL_BRIEF.pdf). Evaluate trust/import/export/progress, separate collection views from status, preserve manga units and optional information depth, then improve contextual discovery/releases. Existing +1 controls, import preview, Taste Deck, adaptation tools and private clubs should be evaluated before adding duplicates. Superseding the first report's paid-convenience idea, the proposed useful core stays free; optional neutral next-volume referrals and labelled publisher-funded benefits require permissions, actual partner terms and measured usefulness/economics before a pilot. Provider permissions, edition/availability-source coverage and direct research access gaps remain explicit. This addendum does not approve implementation, partner outreach, spending, flag changes or deployment, and provides no new hosted/production proof. The implementation record below remains historical to its stated dates.

The core plan is fully implemented, expanded, and quality-hardened. All major feature work completed. Production-readiness session completed: Apple FM integration, on-device intelligence features, and comprehensive security/stability hardening across DB, edge functions, storage, and iOS. The February 2026 follow-up added the curated concierge copy layer and club activity status clarity pass. P2 production blockers completed (2026-02-16): backend hardening (NOT NULL on catalog created_at, 12 unused indexes dropped, merged duplicate policies, mirror health check, AVIF support), iOS bug fixes (vote error handling, task cancellation, discover error state), accessibility pass (6 views), and deep linking infrastructure (kuro:// scheme). Detail page error feedback (2026-02-17): markWatched/markRead now show error toasts, chapter accessibility hint fixed. Branded email templates + auth callback (2026-02-17): 5 editorial email templates, auth-callback edge function. Direct kuro:// redirect (2026-02-18): Supabase redirects straight to app after email verification, URL scheme registered, Resend MCP configured for production SMTP. Pre-ship quality audit (2026-02-18): 7-agent audit fixed withRetry force-unwrap, auth callback silent failure, precondition crash, BrowseGrid ForEach identity, Unicode URL encoding (1,417 links), Privacy Manifest, join_club archived check. Audit follow-up (2026-02-18): 4-agent team fixed 21 remaining findings — error handling across auth/clubs/chat, deleted ~2,100 lines dead code, fixed force-unwraps, backend hardening (storage path restriction, description validation, input limits, RPCs in migrations). Database health audit (2026-02-18): comprehensive audit of 70 tables, 67 functions, 15 cron jobs — all healthy; dropped 2 duplicate indexes + 1 dead function; backfilled 3 remote-only migrations locally; Postgres 17.6 confirmed. Auth simplification (2026-02-25): removed email verification requirement from sign-up, added inline email validation (format + uniqueness check via `check_email_exists` RPC), pending Dashboard steps reduced from 3 to 1 (just disable email confirmations). Gesture regression fix (2026-02-26): fixed 3 regressions (vertical scroll stuck, horizontal rails unswipeable, cards untappable) caused by `KuroDeliberateTap`'s `DragGesture(minimumDistance: 0)` + 5 over-strict guards; replaced with standard `.onTapGesture` + `suppressCardTaps` guard; `swipe_tap_guard_v1` stays at 100% (gates the correct pager suppression, not the removed deliberate-tap logic); TestFlight build 9 shipped. FM intent classification (2026-02-28): hybrid FM-primary + keyword-fallback intent routing wired into ConciergeView.send(); `fm_assist_v1` flag at 0% staged rollout; `looksLikeImport()` + `segmentLooksTitleLike()` extracted to TextNormalization for testability; 22 unit tests (14 original + 8 edge cases added in post-review remediation 2026-03-01). Streaming Availability v1 (2026-03-01): canonical service registry, user subscription preferences, collection filters (service + language), provider badges on cards, club shared availability toggle. Follow-up country/language metadata scaffold (2026-03-01, migration `20260301153000`) remains intentionally deferred behind the same flag pending provider API cost/coverage decision. Feature flag: `streaming_availability_v1` at 0%. Free-source streaming research spike added on 2026-03-06 under `research/streaming_availability/`; it produced partial anime-only signal and no viable manga path, so it remains research-only and does not change rollout posture. Streaming note contract hardening (2026-03-06): follow-up migration `20260306113000_provider_availability_note_contract.sql` is now the source of truth for `batch_provider_availability_for_media_v2` fields (`audio_languages`, `subtitle_languages`, `countries_by_sub_lang`), and iOS note rendering now distinguishes `dub`, `audio`, `subtitles`, and generic availability without overclaiming manga locale coverage. Concierge stabilization (2026-03-06): removed the partial disk-backed chat restore path; Concierge is intentionally session-local again rather than restoring stripped text-only transcripts. Adaptation Ladder v1 (2026-03-07): `20260307120000_media_relations_ladder_v1.sql` is applied remotely, `bulk-import-anime` and `bulk-import-manga` are redeployed with AniList relation persistence, and the detail-page `ADAPTATION PATH` UI is live. Controlled backfill seeded the first production relation rows, and ongoing normal imports will continue expanding ladder coverage. Adaptation Ladder v2 (2026-03-07): `20260307150000_adaptation_ladder_v2_editorial_context.sql` is now applied remotely; `get_media_ladder(...)` returns editorial picks (`entry_point`, `next_step`, `primary_source`, `primary_adaptation`, `franchise_note`, `coverage_status`), detail/discover/concierge surfaces opportunistically queue strict AniList refreshes when ladder coverage is weak, and the local `com.kuro.media-relations` launchd worker now handles queue processing, top-catalog backfills, and coverage reports. Search refinement cleanup (2026-03-07): Search chips now execute backend filter-only searches even with an empty query, public-read scripts load non-secret Supabase project config from `scripts/project_public.env`/`scripts/lib` instead of scraping Swift source, and current-state docs now carry explicit live inventory markers checked by `scripts/quality-gates/check_docs_current_state.py`. Archive/release warning cleanup (2026-03-09): removed the remaining code-level archive warnings in `SupabaseService`, `GenreHubView`, `KuroRefinedCard`, and `KuroTests`; only the Xcode `appintentsmetadataprocessor` tool warning remains during builds. Runtime cleanup pass (2026-03-10): remaining delayed main-queue UI resets in `ContentView`, `Cards`, and `ConciergeInputField` were converted to cancellable task-based timing so dismissed views no longer keep stale `DispatchQueue.main.asyncAfter` callbacks alive. Documentation hierarchy cleanup (2026-03-10): current-vs-reference-vs-historical doc roles are now spelled out in `docs/documentation-surface-map.md`, archived material has an explicit `archive/README.md` disclaimer, and the docs quality gate now also enforces the intentional-overlap note for `KNOWLEDGE/` plus the presence of the hierarchy docs.

**Independent review + fix wave (2026-08-06)**: Two external adversarial review waves (reports: `docs/superpowers/specs/2026-08-06-independent-review.md`, `2026-08-06-independent-review-wave2.md`) re-verified the engineering record live and shipped same-day fixes: migration `20260806000000_security_and_mirror_repair` (rec-edges grant revoked + poison cleanup + penalty CHECK constraint + `rate_limit_hit` revoked), migration `20260806010000_serving_fixes_v1` (shelf franchise cap ≤2, hidden-gem argument trim/capitalize, craft lift requires score ≥70), remote re-arm of 7 dead cron jobs (5 mirror + 2 chapter-enrich — they had been 401ing since Jul 31 on empty GUCs), and iOS commit `49f3227` (deck gesture trap, signal retry queue, loading watchdog, accessibility, prefetch downsampling). Repo now 93 Swift files / 231 migrations. Open: similar-titles store coverage check (service-role), baseline migration capture (chain unreproducible), owner veto pass on the self-graded scoreboard, descriptor corpus regeneration.

**Senior stability audit pass (2026-02-20)**: Published evidence-backed audit artifacts in `/Applications/Kuro/docs/` (`audit-2026-02-20-manifest.md`, `audit-2026-02-20-findings.md`, `audit-2026-02-20-remediation-plan.md`, `audit-2026-02-20-release-gate.md`). Current gate is **NO-GO** pending remediation of one P0 (plaintext import secret exposure in migration SQL) and one P1 (deployed migration/function artifacts not yet committed).

**Backend parity re-check + deploy closeout (2026-02-20)**: Re-ran Supabase CLI health checks (`functions list`, `migration list --linked`, `db lint --linked`, `inspect db db-stats`) plus iOS generic build, then applied pending migrations and deployed chapter-enrichment functions. Result: parity gap closed (remote now has `20260221150000` and `20260221162000`; function versions `manga-chapter-enrich:v4`, `manga-source-review-action:v2`). DB remains healthy with warnings-only lint and iOS build remains green.

**Chapter-enrichment collision hardening (2026-02-20)**: `manga-chapter-enrich` upgraded to `v6` with looser collision thresholds, English-title preference in tiebreak selection, stronger chapter-coverage weighting, and a race-safe chapter insert path (replacing failing PostgREST upsert conflict target). Verified on AniList `86707` (`Tales of Demons and Gods`): mapping now resolves, 321 chapter rows inserted, max chapter 468, status is `ready`.

**Import orchestration hardening (2026-02-20)**: `scripts/run_full_import.js` now includes automatic timeout fallback. When heavy anime/manga import calls return timeout-class failures (e.g. 504), the script automatically executes a schedule-safe lightweight batch and continues the loop. This keeps cursor progress moving during long backfills without manual restarts.

**Import cursor persistence fix (2026-02-20)**: `ensureImportState()` in `scripts/run_full_import.js` no longer rewinds `import_state.last_page` to zero. It now seeds ANIME/MANGA rows only when missing (`onConflict: media_type`, `ignoreDuplicates: true`) so existing cursor progress is preserved.

**Synopsis enrichment runtime hardening (2026-02-23)**: Applied migration `20260223002000_synopsis_retry_backoff_and_resume.sql` remotely and hardened the local continuous enrichment loop. `scripts/synopsis_enrichment_worker.swift` now tracks due backlog before/after, emits quality counters (`tone_polish_used`, `fallback_used`, `autodeduped_sentences`), and writes generated samples (`reports/synopsis-enrichment/generated-samples-latest.md`). `scripts/run_synopsis_enrichment.sh` now guards overlap via `.worker.lock` and self-heals stale locks via PID+TTL fallback (`SYNOPSIS_LOCK_TTL_SECONDS`), and `scripts/install_synopsis_enrichment_launchd.sh` preserves existing env values while validating required Supabase secrets before install. Dashboard (`scripts/synopsis_dashboard_server.js`) now shows cumulative/24h totals plus generated-sample visibility, and `/api/status` now backfills `updated_at` from latest run metadata when missing in status JSON.

**Catalog safety runner split (2026-02-24)**: Added a fully separate catalog-safety runtime so synopsis and safety pipelines are operationally isolated. New migration `20260224101000_catalog_safety_runner_v1.sql` adds safety state fields on `anime`/`manga`, lexicon/audit tables, and service-role RPCs (`get_catalog_safety_candidates`, `upsert_catalog_safety_result`, `mark_catalog_safety_failed`, `get_catalog_safety_open_gaps`, `get_catalog_safety_backlog_count`). New scripts: `scripts/catalog_safety_worker.swift`, `scripts/run_catalog_safety.sh`, `scripts/install_catalog_safety_launchd.sh`, and `scripts/catalog_safety_dashboard_server.js` (localhost `:8788`). Safety reports now live under `reports/catalog-safety/` (`uncertain-latest.md` + per-run uncertain files), independent from synopsis report files and launchd label.

**Catalog safety audit remediation (2026-02-24)**: Removed silent open-gap fallback in `scripts/catalog_safety_worker.swift`. Open-gap fetch now uses explicit error handling, increments `open_gaps_fetch_failed`, logs warning lines to worker log, preserves `uncertain-latest.md` when fetch fails to avoid false empty/open-gap dashboards, and now includes `open_gaps_fetch_failed` in run summary lines for faster ops triage. Technical inventory in `CURRENT_APP_STATE.md` was regenerated to remove stale file/count claims, `CLAUDE.md` runtime function-version snapshot was synchronized with live deployed versions, and the safety dashboard now visualizes queue completion progress (baseline/remaining/reduced + %).

**Catalog safety uncertain-rate fix (2026-02-24)**: Investigated high uncertain runs and confirmed dominant pattern was `model_uncertain + no_strong_signal`. Updated worker decisioning to mark titles as safe when there is no meaningful porn signal (low rule score + no rule hits), added `safe_fallback_no_signal` metric, and surfaced it on the safety dashboard. Forced validation run showed expected behavior (`processed=240`, `safe=235`, `uncertain=0`, `blocked=5`).

**Detail page scrolling fixes (2026-02-24)**: Fixed two bugs on anime/manga detail sheets. (1) Vertical dead zone at bottom: hero `.offset(y: -safeTop)` was visual-only, leaving a phantom layout gap; added `.padding(.bottom, -safeTop)` to compensate. (2) Horizontal rails ("More Like This") couldn't scroll: removed `.kuroSwipeExclusionZone()` from `SimilarSection`/`MangaSimilarSection` — these sections only appear inside sheets where the pager gesture doesn't apply, so the exclusion zone just added a competing drag recognizer. Build: SUCCEEDED.

**Social Activity Layer + Add to Club Context Menu (2026-02-24)**: Replaced club-level ephemeral chat with title-level social activity. New migration `20260224150000_social_activity_layer.sql` adds `title_comments` and `title_comment_reactions` tables, `shares_club_with()` SECURITY DEFINER helper, RLS policies gating visibility to club co-members, and 5 RPCs (`upsert_title_comment`, `delete_title_comment`, `toggle_comment_reaction`, `fetch_friend_activity_for_title`, `count_friends_tracking`). Rate-limited (10 comments/5min, 30 reactions/min). Feature flag `social_activity_v1` at 0% for staged rollout. iOS: new `FriendsActivitySection.swift` on detail pages (friend tracking pills, comments, reactions), friend count indicators on all card types (Portrait/Compact/Hero/SharedVertical/SharedHorizontal), batch prefetch on Discover/Browse/Collection, "Add to Club..." context menu on cards, `AddToClubRailSheet` made public. Club chat tab removed from `ClubDetailView` (~315 lines), `clubs_chat_v1` disabled, `prune_club_messages` cron unscheduled. 2 new files, 12 modified, 64 Swift files, 142 migrations. Build: SUCCEEDED.

**Auth simplification + inline email validation (2026-02-25)**: Removed email verification requirement from sign-up flow — `signUpWithEmail` no longer passes `redirectTo`, eliminating the email confirmation redirect entirely. Added inline email validation to `AuthView.swift`: real-time format validation plus server-side uniqueness check via new `check_email_exists` RPC. New migration `20260225100000_check_email_exists_rpc.sql` adds the RPC. Pending manual Supabase Dashboard steps reduced from 3 to 1 (just disable email confirmations in Dashboard → Auth → Email). The `kuro://auth/callback` redirect URL and email template paste steps are no longer required.

**Gesture regression fix (2026-02-26)**: Fixed 3 regressions introduced by `KuroDeliberateTap`: (1) vertical scroll stuck on main pages, (2) horizontal rails hard to swipe, (3) cards untappable without long-press. Root cause: `KuroDeliberateTap`'s `DragGesture(minimumDistance: 0)` was intercepting all touch events, and 5 over-strict guard conditions (`isScrolling`, `isInSwipeExclusionZone`, `isAnimating`, `isDragging`, `suppressCardTaps`) were blocking legitimate taps. Fix: replaced `KuroDeliberateTap` with standard `.onTapGesture` gated only by the `suppressCardTaps` environment key (which correctly suppresses taps during pager drags). The `swipe_tap_guard_v1` feature flag remains at 100% — it gates the pager-level suppression logic in `KuroPagingGesture`, which is working correctly and was not the source of the regressions. TestFlight build 9 shipped.

**UX Density + Clarity Improvements (2026-02-27)**: 4 changes across 4 files. (1) EditorialDiscoverView: progressive disclosure — 6 primary sections always visible, 7 secondary behind "Show More" button with UserDefaults persistence. (2) ConciergeComponents: first-time contextual hint on intro card (expanded two-row explanation for new users, slim text for returning users, `kuro_concierge_used` flag). (3) ClubDetailView: compact reaction row for unreacted items (single smiley icon, expands on tap). (4) ConciergeView: `kuro_concierge_used` flag set in `send()` + error dedup in `handleError()` (guardrail → inline only, network → toast only). Build: SUCCEEDED.

**Manga matching hardening v2 (2026-02-20)**: `manga-chapter-enrich` now supports runtime matcher mode (`strict`/`fuzzy_v2`), weighted fuzzy title scoring with confidence+margin gates, hard conflict filtering on external IDs, persistent mapping verification memory (`next_verify_at`, `verify_status`, fail counters), and automatic safety degrade to strict mode when 24h wrong-map proxy exceeds threshold. Added migration `20260220103000_manga_fuzzy_matcher_v2.sql` (new verification columns + candidate priority class 4 + quality metrics RPC + daily auto-expire for stale pending review rows). `scripts/check_cron_health.js` now prints a dedicated fuzzy quality scorecard (auto-resolve, wrong-map proxy, unresolved trend, verify deactivation, mode/degraded flag).

**FM intent classification wired (2026-02-28)**: Apple Foundation Models `assistIntent()` (already implemented in AppleFMService.swift) is now the primary intent classifier in ConciergeView.send(). Hybrid architecture: FM-primary with keyword fallback. FM classifies into 6 intents with confidence scoring (threshold 0.65). Falls back to `looksLikeImport()` keywords on FM unavailable/timeout/low-confidence. Analytics distinguish `"source": "fm"` vs `"source": "keywords"`. No new files, no backend changes.

**Additional backend pipeline (2026-02-19)**: Implemented Manga Chapter Enrichment v1 as a separate additive path (no router behavior changes): new edge function `manga-chapter-enrich`, new mapping/review tables (`manga_source_links`, `manga_source_link_review`), candidate + metrics RPCs, and 15-minute cron schedule. Follow-up migration `20260219234000_fix_manga_chapter_enrich_cron_secret.sql` hardens the cron header path so `x-import-secret` is always sent. Added `manga-source-review-action` edge function plus migration `20260219235500_manga_review_approved_mapping_method.sql` so unresolved review rows can be approved/rejected and immediately re-enriched in one call. iOS manga chapter-open behavior now uses strict legal-provider link allowlist and no longer falls back to generic `siteUrl`.

**Add-to-rail + adaptive sizing (2026-02-16)**: "+" button per club rail in ClubDetailView opens AddItemToRailSheet with server-side search and typed PostgrestError handling. Member identity labels stabilized (UUID hex prefix). Adaptive card widths across all surfaces (Discover, GenreHub, detail similar sections) — removed hardcoded 393pt default, cards scale via `floor((screenWidth - 56) / 2.8)` clamped [112, 144].

**Clubs Enhancement completed (2026-02-16)**: 6-phase expansion shipped — list enrichment (member counts, activity previews, unread dots), emoji reactions (fire/heart/eyes/100 with anonymous aggregate counts), watch-together pace sync (median-based "3 ep behind the group"), Supabase Realtime subscriptions (live updates without pull-to-refresh), ephemeral club chat (280 char, 30-day auto-prune, rate-limited), and in-app notification badges. 4 new DB migrations, 6 new feature flags (staged rollout: 0-100%), 9 tables total, 12 RPCs. All privacy-preserving: anonymous reaction counts, median-only pace, ephemeral chat with GDPR cascade delete.

**5-page navigation restored (2026-02-15)**: Swipe pager expanded from 3 to 5 pages: Concierge ← [Discover] → Browse → Collection → Clubs. Browse promoted from sheet modal to page. Clubs elevated from ProfileView to own page. Distance-based mounting, `.snappy` animation, 120fps ProMotion, viewport-filtered exclusion zones. Search remains global sheet.

**First TestFlight build live (2026-02-15)**: 43 UX improvements shipped via 16-agent team. Fastlane configured for automated TestFlight builds (`fastlane beta`). Build 2 (v1.0) uploaded to App Store Connect. Bundle ID: `com.Kuro.app`. Foundation Models compiled in — no entitlement needed (confirmed via ASC API). Placeholder app icon added.

**Production readiness completed (2026-02-09)**: Apple FM migration (on-device classify, disambiguate, condense, search intent), synopsis condenser, NL collection search, Next Up picks, NetworkMonitor, lifecycle handling, IMPORT_SECRET auth, storage MIME + RLS + 5MB limits, 11 DB fixes, 5 edge function hardening items, mirror cron contention fix, 64 print→DEBUG, withRetry helper, UIScreen.main deprecation fix, 6 migrations applied, 6 edge functions deployed.

**Concierge redesign completed (2026-02-09)**: State machine removed, inline chat architecture, visual token alignment with KuroDesignSystem, German NLP hardening (vibe allowlist, intent keywords, umlaut normalization), 6 new vibe modes (23 total), 12 new curated rails (50 total), auth+rate-limit parallelized, edge function warmup, and auto-apply for high-confidence imports.

**Clubs feature completed (2026-02-09)**: Full social feature with 7 tables, 22 RLS policies, 6+ RPCs, analytics, iOS views (ClubsView, ClubDetailView, ClubActivitySection, ProfileView clubs tab), import reconciliation with Add/Update/Skip and previous_values tracking, concierge-undo edge function, monochrome palette polish, member detail, security fixes.

**Security hardening completed (2026-02-09)**: Rail lock bypass fixed in RLS, function search paths pinned (`generate_invite_code`, `sharing_level_rank`), secrets gate no false-positive on anon key.

**Performance optimizations completed (2026-02-09)**: `fetch_club_bundle` LEFT JOIN refactor, auth+rate-limit parallelized in all three concierge edge functions, iOS post-apply fetches parallelized with `async let`.

Implemented:
- Config-driven "modes" (curated rails) stored in DB config JSON.
- Deterministic router that picks up to 2 modes per prompt (fast, predictable, cheap).
- Backend returns grouped rails (`sets`) plus backward-compatible flattened items.
- iOS renders rails from backend `sets`.
- Classics rail expanded (do not remove existing classic boosts; return more classics by heuristic + config filters).
- **23 modes** (v8, deployed): internal IDs map to butler-facing copy in `ConciergeCuratedCopy`:
  - `premium_picks` → **The Cut**
  - `gateway_start_here` → **Start Here**
  - `premium_action` → **Action With Craft**
  - `premium_comedy_grownup` → **Comedy With Bite**
  - `cozy_comfort` → **Soft Evenings**
  - `dark_serious` → **Dark, Not Empty**
  - `hidden_gems` → **Underseen**
  - `classics_expanded` → **The Canon**
  - `short_one_season` → **Short, Complete**
  - `movie_night` → **One Perfect Film**
  - `romance_serious` → **Romance That Lands**
  - `romcom` → **Light, Sharp Romance**
  - `fantasy_non_isekai` → **Fantasy With Texture**
  - `isekai` → **Other Worlds, Cleanly**
  - `sports` → **Competition, Pure**
  - `scifi` → **Ideas With Heat**
  - `horror_supernatural` → **Unease, Done Right**
  - `mecha` → **Steel and Stakes**
  - `mystery_detective` → **Cases With Discipline**
  - `music_performance` → **Sound and Feeling**
  - `historical` → **Period Weight**
  - `school_coming_of_age` → **Coming-of-Age, Quietly**
  - `shoujo_josei` → **Emotion, With Clarity**
- **50 curated rails** (27 original + 23 new: sports, sci-fi, horror/supernatural, mecha, mystery/detective, music/performance, historical, school/coming-of-age, shoujo/josei anime+manga, plus existing seinen anime+manga, josei manga).
- Intent detectors in `scoreMode()` for movie, short, isekai/non-isekai, romcom/serious-romance, sports, sci-fi, horror disambiguation.
- Enriched synonyms with German translations across all modes.
- **Negative genre filtering**: "action but no romance", "fantasy without harem" — parsed and applied to both curated/algorithmic rails AND mode selection (excluded genres suppress conflicting mode matches in `mapStrongGenreToModeId` and penalize conflicting modes in `scoreMode`).
- **30 abbreviations** in parser (up from 10): OP, DB/DBZ/DBS, SAO, NGE/Eva, LOTGH, MP100, BC, ToG, MiA, ReZero, KonoSuba, TPN, BNHA, DM, COTE, etc.
- **Phase 0 quality overhaul** (2026-02-08): cross-rail overlap reduced from 94% to ~36%, sequels/misclassified items removed, all rails slimmed to 30-80, classics cleaned (0 post-2014 titles), isekai rebuilt (114 bogus → 14 genuine).
- **Mode analytics table** (`concierge_mode_analytics`) for tracking mode selection patterns.
- **Enhanced audit script** with 5 quality checks: overlap, franchise duplication, classics year, rail size, score floors.
- Foundation migration consolidating all core catalog tables + import tracking + materialized views + lock RPCs (schema drift resolved).
- Migration to fix legacy production drift (`tags.kitsu_id`, `comments.user_id` type): `/Applications/Kuro/supabase/migrations/20260206143000_fix_legacy_tags_and_comments.sql`.

Not implemented yet:
- On-device Core ML classifier.
- Active learning loop ("not my vibe", "too childish", etc.) feeding training data.
- Admin UI to edit modes (today: DB JSON only).


### Free-source streaming research spike (2026-03-06) -- RESEARCH ONLY

- Added a standalone research harness under `research/streaming_availability/`:
  - `free_streaming_availability_spike.py`
  - `benchmark_manifest.json`
  - `provider_mappings.json`
  - `README.md`
- Output reports are local only under `reports/streaming-availability-research/`.
- Scope guard:
  - no Supabase writes
  - no UI wiring
  - no use of `provider_availability*` tables
- Source handling:
  - `simple-justwatch-python-api` is the only title-level source used in the spike
  - `justwatch-selenium-api` stays optional and is currently unavailable in this environment because Selenium/browser dependencies are missing
  - `anime-streaming` is parsed only as service-region hint data and never treated as title-level truth
- Benchmark result on a fixed 50-title Kuro catalog manifest:
  - overall deterministic JustWatch matches: `13/50`
  - titles with title-level locale evidence: `12/50`
  - anime split: `13/25` matches, `12/25` locale-evidence titles
  - manga split: `0/25` matches, `0/25` locale-evidence titles
- Decision:
  - useful as research for anime provider/country plus locale hints
  - not strong enough to replace the deferred paid/provider-backed production path

- 2026-03-06: Detail CTA fallback copy hardened. Existing legal-link CTAs now show honest region/licensing disclaimer copy when metadata is absent, and `Link coming soon.` when no legal link exists.
- 2026-03-06: Streaming note derivation hardened. Provider availability notes now use typed audio/subtitle/dub logic, mixed anime+manga entity rails key on composite media identity, and the research spike's repo paths + search country are CLI-configurable while remaining non-production.

## What happened to this plan file

`/Applications/Kuro/IMPLEMENTATION_PLAN_Variation1.md` started as a historical plan document and now tracks implementation status and follow-up refinements.

## Why this architecture is strong

It makes Concierge feel premium without paying LLM costs for every request:
- Deterministic routing + DB queries are fast and consistent.
- LLM is optional narration (and guarded by per-user + global budgets).
- The "taste" is controlled by mode constraints and editorial boosts, not prompt randomness.

## Current implementation (where it lives)

### 1) Modes config
- Migrations write `config.modes` into the single-row JSON config:
  - v1: `/Applications/Kuro/supabase/migrations/20260205190000_concierge_modes_config.sql` (6 modes)
  - v2: `/Applications/Kuro/supabase/migrations/20260205233000_concierge_modes_v2_config.sql` (8 modes + rail_id + router_llm knobs)
  - v3: `/Applications/Kuro/supabase/migrations/20260206100000_concierge_modes_v3_expanded.sql` (14 modes + enriched synonyms)
  - v7: `/Applications/Kuro/supabase/migrations/20260209100000_concierge_modes_v7_german_synonyms.sql` (German synonyms for all modes)
  - v8: `/Applications/Kuro/supabase/migrations/20260209110000_concierge_modes_v8_expanded.sql` (23 modes: +mecha, mystery_detective, music_performance, historical, school_coming_of_age, shoujo_josei)
- Modes are stored at:
  - `public.concierge_config.config.modes`

Each mode supports (subset may be omitted):
- `id`, `title`
- `synonyms` (phrase matches, including German translations)
- `required_genres`
- `exclude_genres`
- `min_score`, `min_popularity`, `max_popularity`
- `exclude_formats`
- `classic_year_max` (for classics mode)
- `rail_id` (maps media type to a pinned curated rail)

### 2) Mode router + rails output
- Implemented in:
  - `/Applications/Kuro/supabase/functions/concierge-recommend/index.ts`

Key behaviors:
- Picks up to 2 rails ("modes") for each prompt.
- Biases toward including a Classics rail as a stable second rail.
- If prompt includes a seed ("like Vagabond"), replaces the primary rail with `Similar to "X"` (deterministic similarity RPC), while keeping Classics as the other rail.
- Returns:
  - `modes`: selected rails with `confidence` + `reason`
  - `sets`: array of rails, each with `title` + `items` (`set.title` is backend/internal; UI replaces with curated copy)
  - `items`: flattened (backwards compatibility and for narration)

Perf note:
- The Edge function reuses shared candidate pools and media context across rails to avoid extra DB roundtrips.

### 3) iOS rendering
- Decoding:
  - `/Applications/Kuro/Kuro/Services/SupabaseService.swift`
- UI:
  - `/Applications/Kuro/Kuro/Views/ConciergeView.swift`

Behavior:
- If backend returns `sets`, Concierge renders each set as a titled horizontal rail (internal title -> curated/locale title at render time).
- If `sets` is missing (older backend), it falls back to the previous single list rendering.

## Reanalysis: should we do more, and what's the "better way"

### What we should keep (recommended)

Keep the current design as the default:
- Backend deterministic router + config-driven modes is the best cost/perf/iteration point.
- It already gets you 90 percent of the "premium" feel without ML complexity.

### What to improve next (highest leverage)

1. ~~Expand and tune modes in config~~ **(DONE as of v6)**
- All originally planned modes have been added, plus 3 new genre modes:
  - `Gateway / First Anime` (v2)
  - `Short One-Season` (v3: `short_one_season`)
  - `Movie Night` (v3: `movie_night`)
  - `Romance (serious)` vs `Romcom` (v3: `romance_serious`, `romcom`)
  - `Fantasy (non-isekai)` vs `Isekai` (v3: `fantasy_non_isekai`, `isekai`)
  - `Sports` (v6: `sports`) — Haikyuu, Blue Lock, Slam Dunk, Hajime no Ippo
  - `Sci-Fi` (v6: `scifi`) — Cowboy Bebop, Ghost in the Shell, Steins;Gate, Psycho-Pass
  - `Horror & Supernatural` (v6: `horror_supernatural`) — Shiki, Higurashi, Parasyte, Junji Ito
  - `Mecha` (v8: `mecha`) — Mecha (giant robots, Gundam, Evangelion)
  - `Mystery & Detective` (v8: `mystery_detective`) — Mystery & Detective (Monster, Death Note, Hyouka)
  - `Music & Performance` (v8: `music_performance`) — Music & Performance (K-On, Your Lie in April, Bocchi)
  - `Historical & Period` (v8: `historical`) — Historical & Period (Vinland Saga, Kingdom, Golden Kamuy)
  - `School & Coming of Age` (v8: `school_coming_of_age`) — School & Coming of Age (Toradora, Oregairu, Kaguya-sama)
  - `Shoujo & Josei` (v8: `shoujo_josei`) — Shoujo & Josei (Fruits Basket, Nana, Skip and Loafer)
- Demographic rails added (not full modes): seinen, shoujo, josei
- Current count: **23 modes** (within the recommended 20-50 ceiling). Room for more.

2. Add a feedback loop (active learning)
- Add UI actions like:
  - "Not my vibe" (for the whole rail)
  - "More like this" / "Less like this" (for a title)
  - "Too childish" / "Too dark" quick toggles
- Log this as labeled data (user prompt -> selected mode(s) -> feedback).
- Use it to improve synonyms and scoring (and later train ML).

3. Add a lightweight evaluation harness
- Reuse the existing scripts/corpus infrastructure to measure routing stability and result quality:
  - `/Applications/Kuro/scripts/concierge_eval_parse.js` (pattern to follow)
  - Add a similar `concierge_eval_modes.js` if needed (prompt -> expected modes).

### Core ML vs server-side embedding router

Core ML (on-device):
- Pros: instant, free per request, private, works offline.
- Cons: requires a training + versioning pipeline and shipping app updates to improve routing.
- When to do it: only after we have enough real labeled data (from feedback) and we see misrouting is a real problem.

Server-side embeddings (router):
- Pros: easy to iterate without app update (update mode vectors or examples).
- Cons: embedding calls cost money and add latency; also introduces a new provider dependency.
- If you want "ML but cheap", do it offline:
  - Precompute mode centroids from synonyms.
  - Only embed user text when deterministic scoring confidence is low.
  - Cache (prompt_norm -> chosen_modes) for a while.

Pragmatic recommendation:
- Keep deterministic router as primary (already done).
- Add feedback logging + mode tuning first.
- Add ML only if metrics show it meaningfully improves routing.

## Two-mode vs one-mode routing

You previously asked for up to 2 modes. That is implemented and is a good default:
- Mode A: best-fit vibe rail
- Mode B: Classics (expanded) rail (stable, always good)

If you ever want to switch to 1-mode:
- Keep Classics as a separate fixed section in Discover (not in Concierge).
- Let Concierge always return one rail for "vibe" only.

## Deployment notes

To get the latest 23-mode router live, you must deploy:
- DB migrations (in order): **93 total migrations (91 local + 2 remote-applied)** — see `supabase/migrations/` for full list
  - Key mode migrations:
    - `20260205190000_concierge_modes_config.sql` (v1: 6 modes)
    - `20260205233000_concierge_modes_v2_config.sql` (v2: 8 modes + rail_id + router_llm)
    - `20260206100000_concierge_modes_v3_expanded.sql` (v3: 14 modes)
    - `20260208022110_add_sports_mode.sql` (sports rails)
    - `20260208022153_add_scifi_mode.sql` (sci-fi rails)
    - `20260208022239_add_horror_supernatural_mode.sql` (horror/supernatural rails)
    - `20260208022342_add_demographic_rails.sql` (seinen, shoujo, josei)
    - `20260208022356_update_concierge_config_new_modes.sql` (v6: 17 modes in config)
    - `20260209100000_concierge_modes_v7_german_synonyms.sql` (v7: German synonyms)
    - `20260209110000_concierge_modes_v8_expanded.sql` (v8: 23 modes)
  - Key quality migrations:
    - `20260208022035_phase0_remove_sequels.sql`
    - `20260208022136_phase0_remove_misclassified.sql`
    - `20260208022250_phase0_dedup_rails.sql`
    - `20260208022326_phase0_slim_and_rerank.sql`
    - `20260208022404_phase0_fix_classics.sql`
- Edge functions (deployed):
  - `concierge-parse` (year mention extraction + boost; strips years from trigram search queries)
  - `concierge-resolve` (includes year/format tags in LLM prompt and passes them through in response)
  - `concierge-recommend` (negative-genre suppression in routing + scoring; improved seed/classics intent)
- Note: Avoid pinning Edge Function version numbers in docs. Verify actual deployed versions with:
  - `supabase functions list --project-ref bkdifromsqxkndnllmdj`
- **Adaptation disambiguation** (iOS): auto-apply guard blocks when top candidates share base title but differ in media_id. Year override: if user mentions a year matching the top candidate, auto-apply proceeds.

The iOS UI is already compatible (renders `sets` when present).

## Quality infrastructure

- **Audit script**: `scripts/audit_curated_rails_quality.js` — 5 checks: cross-rail overlap (>15%), franchise duplication, classics year (>2014), rail size (>80), score floor (category-specific). Run with `node scripts/audit_curated_rails_quality.js`.
- **Router eval**: `scripts/eval_router.js` — 63 test cases against live endpoint, 90% pass threshold. Exponential backoff for 429/5xx (up to 3 retries, honours Retry-After). Infra errors excluded from pass rate.
- **Rail generator**: `scripts/generate_rail_migration.js` — deterministic SQL from `scripts/rail_config.json`. Validates: no duplicates, max 100 items/rail, valid media types. Same config always produces same SQL.
- **Mode analytics**: `concierge_mode_analytics` table logs mode selections, synonyms matched, confidence scores, and whether the request was LLM-routed.
- **Overlap target**: No rail pair should exceed 15% overlap (was 94%, now ~36% worst-case).

## Concierge redesign (2026-02-09) -- COMPLETED

Full redesign across 8 phases:

### Phase 1: State machine killed, inline chat -- COMPLETED
- Removed complex state machine architecture from ConciergeView
- Replaced with inline chat-style interaction model
- Dead code removed: ConciergeOverlay.swift, KuroChanMascot.swift, getByMood(), SearchViewNew (~500 lines total)

### Phase 2: Visual token alignment -- COMPLETED
- KuroDesignSystem token alignment across all concierge UI
- Consistent spacing, typography, and color usage

### Phase 3: Editorial rec cards -- COMPLETED
- Recommendation cards redesigned with editorial styling
- Cover art integration via `cover_image_medium` in `search_titles()` return type

### Phase 4: Inline confirm -- COMPLETED
- Import confirmation now inline (no modal overlay)
- Confirm bubble shows diff groups (new vs update vs skip)

### Phase 5: Performance (warmup, parallel auth, auto-apply) -- COMPLETED
- Edge function warmup for cold-start mitigation
- Auth + rate-limit checks parallelized across all 3 edge functions
- Auto-apply for high-confidence single-item imports (with adaptation disambiguation guard)

### Phase 6: Dead code cleanup -- COMPLETED
- ConciergeOverlay.swift removed
- KuroChanMascot.swift removed
- `getByMood()` removed
- `#if false` SearchViewNew block removed (~500 lines total)

### Phase 7: German NLP -- COMPLETED
- Inflection allowlist for German vibe words
- Intent keywords expanded with German translations
- Synonym lists enriched with German equivalents across all 23 modes
- Umlaut normalization in parser
- Migration: `20260209100000_concierge_modes_v7_german_synonyms.sql`

### Phase 8: Curation expansion -- COMPLETED
- 6 new modes added (17 -> 23 total):
  - Mecha, Mystery & Detective, Music & Performance, Historical & Period, School & Coming of Age, Shoujo & Josei
- 12 new curated rails (38 -> 50 total)
- Migration: `20260209110000_concierge_modes_v8_expanded.sql`

## Security hardening (2026-02-09) -- COMPLETED

- **Rail lock bypass fixed**: RLS policies updated to prevent bypass of rail lock mechanism
  - Migrations: `20260206150000_security_hardening_rls_and_views.sql`, `20260206164200_security_hardening_rls_and_views.sql`
- **Function search paths pinned**: `generate_invite_code` and `sharing_level_rank` RPCs use explicit `SET search_path = public` to prevent search path injection
- **Secrets gate no false-positive**: Quality gate `check_secrets.sh` updated to not flag the Supabase anon key (which is public/publishable) as a leaked secret

## Concierge images (2026-02-09) -- COMPLETED

- **Migration**: `20260209000000_search_titles_add_cover_image.sql` adds `cover_image_medium` to `search_titles()` return type.
- **Swift model**: `ConciergeCandidate` gains `cover_image_medium: String?`.
- **Import preview (ConfirmRow)**: Now renders `KuroCachedAsyncImage` with gradient fallback instead of static gradient.
- **Recommendation carousel (PresentCard)**: Same — actual cover art from `item.imageURL` instead of gradient.
- **`ConciergeConfirmItem`**: Gains `imageURL: String?` wired from `topCandidate?.cover_image_medium`.

## Performance optimizations (2026-02-09) -- COMPLETED

All three concierge edge functions parallelized for snappiness:

- **concierge-parse**: Per-item processing now runs via `Promise.all` (was serial `for` loop). Within each item, search queries + denoised queries also parallelized. Auth + rate-limit checks parallelized. Expected 3-5x latency improvement for multi-item pastes.
- **concierge-apply**: Per-item upserts now run via `Promise.all` (was serial). Auth + rate-limit + body parsing parallelized. Expected 3-5x improvement for multi-item imports.
- **concierge-recommend**: Primary + secondary rail building now runs via `Promise.all` (was sequential). Inside `fetchMediaContext`, 3 independent DB queries parallelized. Curated rail anime/manga fetches parallelized. Seed similarity fetches parallelized. Config + tag mapping + editorial boosts fetch parallelized. LLM feature flag checks parallelized. Expected 2-3x improvement overall.
- **fetch_club_bundle RPC**: Refactored from N+1 subselects to LEFT JOIN pattern for club data fetching.
- **iOS (ConciergeView)**: Post-apply fetches (`fetchUserLists`, `fetchCollectionItems`, `fetchCollectionFeed`) now run with `async let` instead of sequential `await`.

## Clubs feature (2026-02-09) -- COMPLETED

Full feature launch across 5 phases:

### Phase 0: Product spec -- COMPLETED
- Product spec written: `/Applications/Kuro/docs/clubs-spec.md`

### Phase 1: Backend -- COMPLETED
- **7 tables**: clubs, club_members, club_activity, club_polls, club_poll_votes, club_watchlist, club_discussions
- **22 RLS policies**: Full row-level security across all club tables
- **6+ RPCs**: Including `fetch_club_bundle` (LEFT JOIN refactor for performance), `generate_invite_code`, `log_club_event`, etc.
- **Analytics table**: `club_analytics` for tracking club events
- Migrations:
  - `20260209200000_clubs_foundation.sql` (tables + indexes)
  - `20260209201000_clubs_rls_policies.sql` (22 RLS policies)
  - `20260209202000_clubs_rpcs.sql` (RPCs with pinned search paths)
  - `20260209220000_club_analytics.sql` (analytics + housekeeping)

### Phase 2: iOS UI -- COMPLETED
- `/Applications/Kuro/Kuro/Views/ClubsView.swift` — Club listing, create/join sheets
- `/Applications/Kuro/Kuro/Views/ClubDetailView.swift` — Club detail, settings, member management
- `/Applications/Kuro/Kuro/Views/DetailPages/ClubActivitySection.swift` — Activity feed section
- `/Applications/Kuro/Kuro/Views/ProfileView.swift` — Clubs tab added to user profile

### Phase 3: Import reconciliation -- COMPLETED
- Concierge parse detects existing entries in user's library
- Apply respects Add/Update/Skip actions with TOCTOU protection
- `previous_values` tracking for undo support
- iOS confirm bubble shows diff groups (new vs update vs skip)
- **concierge-undo** edge function: `/Applications/Kuro/supabase/functions/concierge-undo/index.ts`
- Migration: `20260209135229_import_reconciliation.sql`

### Phase 4: Quality gates -- COMPLETED
- **6 scripts** in `/Applications/Kuro/scripts/quality-gates/`:
  - `check_secrets.sh` — Scans for leaked secrets (no false-positive on anon key)
  - `check_migrations.sh` — Lints migration files
  - `test_router_offline.sh` — Offline router test cases
  - `audit_rails.sh` — Curated rail quality audit
  - `build_ios.sh` — iOS build verification
  - `run_all.sh` — Orchestrator: runs all gates, prints summary, exits 1 on hard-fail
- Pre-commit hook wired to quality gates

### Phase 5: Polish -- COMPLETED
- Monochrome palette applied across club UI
- Member detail views refined
- Security fixes: function search paths pinned (`generate_invite_code`, `sharing_level_rank`)
- Haptics tuned (medium for create/join/confirm, light for vote/nav)
- Empty states improved
- Owner transfer UX context-aware
- Build verified on iPhone 17 Pro simulator

## Concierge Import UX Improvements (2026-02-28) -- COMPLETED

Redesigned import preview cards and confirmation flow for a premium editorial feel:
- **Import cards**: larger 80x114pt posters, media type badge, parsed intent row (status + progress), tap-to-preview via MediaDetailSheet, auto-expand candidates when score < 0.80, press feedback animation
- **Confirm button**: loading state with spinner during apply, disabled while in-flight
- **Applied state**: persistent summary in bubble ("2 added, 1 updated") with UNDO + VIEW COLLECTION buttons (no longer toast-only)
- **Auto-apply**: chat message now includes bulleted title list
- Files changed: ConciergeImportCards.swift, ConciergeComponents.swift, ConciergeView.swift, ContentView.swift

## Bug fix: Concierge import false success toast (2026-02-28) -- COMPLETED

**P0 fix**: `autoApplyImport()` and `confirmImport()` in ConciergeView.swift showed a success toast ("N items added to collection") unconditionally after calling `concierge-apply`, even when the server returned `success: false`. Users saw "added" but items weren't saved. Fixed by adding `guard res.success` check in both functions. On failure: error toast with server error detail. On success: uses `res.applied?.count` for accurate count. Production `user_id` column types confirmed as TEXT (not INTEGER) — no backend migration needed.

## Bug fix: Progress data forwarding (2026-02-09) -- COMPLETED

**P0 fix**: `confirmImport()` in ConciergeView.swift now forwards all parsed progress fields (`progressEpisodes`, `progressChapters`, `progressVolumes`, `seasonNumber`, `episodeInSeason`, `caughtUp`, `lastEpisode`, `completed`) to the `concierge-apply` edge function. Previously these were all dropped, causing every import to land with progress=0 regardless of user input.

## Production readiness (2026-02-09) -- COMPLETED

Comprehensive production-readiness pass covering Apple FM integration, on-device intelligence features, and security/stability hardening across the full stack.

### Apple FM Migration (Partial) -- COMPLETED

On-device intelligence via Apple Foundation Models, replacing server-side LLM where possible:

- **AppleFMService.swift created** with 4 capabilities:
  - `classify` — on-device intent classification
  - `disambiguate` — on-device disambiguation for ambiguous matches
  - `condenseSynopsis` — on-device synopsis summarization
  - `parseSearchIntent` — on-device natural language search intent extraction
- **FMProvider protocol** + **StubFMProvider** for non-FM-capable devices (graceful fallback)
- **Integrated into SupabaseService.fmService** — available app-wide
- **groqRouteMode removed** from concierge-recommend: LLM router deleted entirely (only 1.36% fallback rate did not justify the cost/latency)
- **groqNarrate kept** — narration still uses Groq server-side (Apple FM not suited for long-form creative text)

### New Features -- COMPLETED

Three new on-device intelligence features shipped:

1. **Synopsis Condenser**
   - `AnimeDetailView` and `MangaDetailView` call `fmService.condenseSynopsis()` to generate concise summaries
   - Runs entirely on-device via Apple FM; falls back gracefully on non-FM devices

2. **Natural Language Collection Search**
   - `parseSearchIntent()` in AppleFMService extracts structured search parameters from free-text queries
   - Enables queries like "show me my completed manga from 2023" against local collections

3. **Next Up Pick**
   - `NextUpSection` (anime) and `MangaNextUpSection` (manga) added to detail views
   - Surfaces contextual "what to watch/read next" recommendations within series pages

### Production Blockers (P0) -- COMPLETED

| ID | Issue | Fix |
|----|-------|-----|
| P0-2 | No network monitoring | `NetworkMonitor.swift` created with `NWPathMonitor` |
| P0-3 | No lifecycle handling | `scenePhase` handling added to `KuroApp.swift` |
| P0-4 | Bulk imports unauthenticated | `IMPORT_SECRET` auth header required on all bulk import edge functions |
| P0-6 | Storage accepts any MIME type | MIME type restrictions applied to storage buckets |
| P0-7 | Storage missing RLS | RLS policies added to storage buckets |

### Production Hardening (P1) -- COMPLETED

| ID | Issue | Fix |
|----|-------|-----|
| P1-1 through P1-6 | DB schema issues | NOT NULL constraints, RLS initplan optimization, anon policies, indexes |
| P1-10 | pg_trgm in wrong schema | Moved to `extensions` schema |
| P1-11 | concierge-parse no input limit | 5,000 character limit enforced |
| P1-12 | concierge-apply no item cap | 100 item cap per request |
| P1-13 | LLM prompt injection | Input sanitization added to all LLM-facing prompts |
| P1-14 | mirror-images lock leak | Lock release guaranteed in finally block |
| P1-15 | Storage no size limit | 5MB per-file limit enforced |
| P1-16 | Mirror cron contention | Per-batch advisory locks, 120s TTL, 200-item batches, 15-min spacing between cron runs |
| P1-17 | 64 print() in production | All converted to `#if DEBUG` conditional compilation |
| P1-18 | No retry logic | `withRetry` helper added (exponential backoff, applied to 5 call sites) |
| P1-19 | UIScreen.main deprecated | Replaced with `displayScale` / window scene APIs |
| P1-20 | fatalError in SupabaseService.init | Replaced with `configError` property + UI gate (2026-03-13) |
| P1-21 | No memory pressure handling | `trimCachesForMemoryPressure()` + `UIApplication.didReceiveMemoryWarningNotification` listener (2026-03-13) |

### Infrastructure -- COMPLETED

- **6 DB migrations applied** to production
- **6 edge functions deployed** (concierge-parse, concierge-recommend, concierge-apply, concierge-resolve, concierge-undo, mirror-images)
- **IMPORT_SECRET** environment variable set in Supabase project + **4 pg_cron jobs** updated to include secret header
- **xcconfig files created and wired** into Xcode project as `baseConfigurationReference`. Info.plist uses `$(SUPABASE_URL)` and `$(SUPABASE_ANON_KEY)` variable references (hardcoded fallback removed).
- **Mock SupabaseService** cleaned up for testability

### Production Quality (P2) -- COMPLETED

| ID | Category | Issue | Fix |
|----|----------|-------|-----|
| P2-1 | Backend | `created_at` nullable on catalog tables | Migration `catalog_created_at_not_null`: backfilled NULLs + NOT NULL on 8 tables (anime, manga, episodes, chapters, volumes, characters, studios, staff) |
| P2-2 | Backend | 12 unused indexes (FTS/trigram superseded) | Migration `drop_unused_indexes_merge_policies_health_check`: dropped 12 indexes (FTS, duplicate genre GIN, unused sort) |
| P2-3 | Backend | Duplicate DELETE policies on club_members | Same migration: merged into single `club_members_delete_self_or_admin` |
| P2-4 | Backend | No mirror health monitoring | Same migration: created `check_mirror_health()` function returning JSONB (run stats, consecutive failures, alert boolean) |
| P2-5 | Backend | Mirror-images missing AVIF support | `getExtFromContentType()` now handles `image/avif`; cache-control changed to `max-age=31536000, immutable` |
| P2-6 | iOS | Vote errors silently swallowed | ClubDetailView: `castVote` wrapped in do/catch with `.error` toast + `errorHaptic()` |
| P2-7 | iOS | Task.detached leak on ConciergeView disappear | Tracked `@State` task refs (warmupTask, prefetchTask, prefetchTask2, backgroundRefreshTask, backgroundRefreshTask2) with consolidated `.onDisappear` cancellation |
| P2-8 | iOS | EditorialDiscoverView blank on first-load failure | `@State loadError` with inline retry view when `fetchDiscoverBundle()` fails |
| P2-9 | Accessibility | Missing VoiceOver traits across views | `.accessibilityAddTraits(.isHeader)` on section headers in ClubDetailView, EditorialCollectionView, EditorialDiscoverView, ConciergeRecommendationRails. `.accessibilityLabel` on ClubsView empty state + club cards. Message bubble labels ("You said:"/"Concierge:") and combined clarification card labels in ConciergeView/Components |
| P2-10 | Infrastructure | No deep linking | `DeepLinkRouter.swift` (enum DeepLink: anime/manga/club/collection/discover/concierge), `KuroApp.swift` `.onOpenURL`, `ContentView.swift` navigation/sheet handling, Associated Domains placeholder in entitlements |
| P2-11 | Infrastructure | Default Supabase emails, no auth callback flow | **Code complete.** 5 branded email templates in `emails/` (confirm, reset, magic-link, change-email, invite) with monochrome editorial styling (Cormorant serif, warm gray `#f5f5f0`, MSO-compatible). `auth-callback` edge function deployed (315 lines, dark-themed HTML fallback with animated K logo, type-specific messages, "Open Kuro" CTA after 4s). `Info.plist` at project root registers `kuro://` URL scheme via `CFBundleURLTypes`. `INFOPLIST_FILE = Info.plist` in both Debug+Release configs. `DeepLinkRouter` extended with `.authCallback(accessToken:, refreshToken:)` + `parseAuthParams()` (fragment priority, query fallback). `KuroApp.swift:37` intercepts auth callbacks before auth gate. `SupabaseService`: `authCallbackURL`, `handleAuthCallback()` via `setSession()`, `resetPassword` passes `redirectTo`. Resend MCP server configured in `.mcp.json`. **Auth simplified (2026-02-25)**: Email verification requirement removed — `signUpWithEmail` no longer passes `redirectTo`. Inline email validation added to `AuthView.swift` (real-time format check + server-side uniqueness via `check_email_exists` RPC, migration `20260225100000_check_email_exists_rpc.sql`). **1 manual Supabase Dashboard step pending**: disable email confirmations in Dashboard → Auth → Email. Previous steps (redirect URL, email templates, SMTP) no longer required for sign-up flow. |

### 2026-02-18: Database Health Audit
- Full audit: 15 cron jobs healthy (1,177/1,177 OK), 70 tables (~420 MB), 67 functions, zero Swift-DB mismatches
- Dropped 2 duplicate indexes (~19 MB), 1 dead function
- Backfilled 3 remote-only migration files locally
- Postgres 17.6 confirmed, pending Dashboard items reduced to 3

### Backend Quality Remediation (2026-02-19) -- COMPLETE
- 5-phase remediation based on 7-agent backend audit
- Phase 1: Critical security — dropped 5 dangerous functions, revoked 4 admin functions, fixed analytics policy
- Phase 2: Edge function auth — added IMPORT_SECRET to mirror-images, deployed concierge-import-anilist
- Phase 3: Swift model fixes — fixed CodingKeys (mal_id, kitsu_id), removed dead properties (tags, trailerUrl), added Realtime publication, made is_adult NOT NULL
- Phase 4: RPC hardening — rate limits on reactions/club creation, emoji allowlist, tightened 5 policies to authenticated, fixed storage policy, added FK indexes, dropped ambiguous overloads
- Phase 5: Cron cleanup — added history cleanup, removed duplicate job, fixed scheduling overlap, updated mirror cron auth

### 2026-02-19: Pre-Ship Audit P0 Remediation — COMPLETE
- 7-agent full-stack audit identified 13 P0, 21 P1, 24 P2, 10 P3 issues
- All 13 P0 issues fixed:
  - 9 nullable DB columns constrained to NOT NULL (1 migration, 17 ALTER statements)
  - Import rating field carried through parse→apply pipeline (SupabaseService + ConciergeView)
  - Club Realtime subscriptions extended to polls + messages tables
  - Silent error handling replaced with user-visible error messages (4 locations)
  - Deep link prompt injection wired end-to-end (ContentView → ConciergeView)
  - Club chat error/retry UI added
  - Club reaction error feedback via toast
  - Mock initializer fixed for new struct properties
- Build verified: BUILD SUCCEEDED

## Streaming Availability v1 (2026-03-01) -- COMPLETED

Canonical streaming/reading availability layer across the app:
- **Canonical service registry**: normalized provider catalog with service IDs, names, logos, and regional availability
- **User subscription preferences**: users can select which streaming/reading services they subscribe to (profile-level setting)
- **Collection filters**: new filter facets on Collection page — filter by streaming service and language availability
- **Provider badges on cards**: availability indicators on card surfaces showing where a title can be watched/read
- **Club shared availability toggle**: clubs can surface titles available on services shared by all members
- **Feature flag**: `streaming_availability_v1` at 0% staged rollout

### Still Pending (deferred)

These items were evaluated and intentionally deferred:

| ID | Issue | Reason Deferred |
|----|-------|-----------------|
| P0-1 | Anon key hardcoded in SupabaseService.swift | Actually safe — this is the public anon key (not service_role). xcconfig infrastructure created for future migration. |
| P0-5 | Image mirroring backlog (2.7%) | Long-term data backfill issue, not a code fix. Mirror cron will catch up over time. |
| P1-7 | ~~Postgres version upgrade~~ | **Done** (2026-02-18): Postgres 17.6 confirmed via DB health audit |
| P1-8 | OTP configuration | Dashboard-only operation (Supabase console) — kept as-is after review |
| P1-9 | ~~Leaked password detection~~ | **Skipped** (2026-02-18): evaluated and deprioritized during DB health audit |
| — | Email confirmations | Dashboard-only: disable email confirmations in Dashboard → Auth → Email. Previous 3-step setup (redirect URL, email templates, SMTP) no longer required after auth simplification (2026-02-25). |
| — | Concierge Redesign phases 1-8 | Already completed in earlier session (see above) |
| — | On-device Core ML classifier | Deferred until sufficient labeled data from feedback loop |
| — | Active learning / feedback loop | Next priority after production stabilization |
| — | Admin UI for modes | Low priority — DB JSON editing sufficient for now |
| — | Documentation cleanup (2026-03-10) | **Done**: 17 stale docs archived, inventory counts fixed (68 Swift / 153 migrations), cross-refs updated, quality gate patched |
| — | Production readiness rollup (2026-03-14) | **Done**: graceful config error (no fatalError), memory pressure handler, 127+ prints in #if DEBUG, feature flags retry (3 attempts), 8 quality gates in CI/Fastlane, club bundle LIMIT clauses, social_activity_v1 at 100%, xcconfig wired, Build 16 shipped |


## Personalization execution contract (2026-03-29) -- ADDED

A new strict planning surface now lives at `/Applications/Kuro/docs/personalization_execution_contract.md`. This is the execution contract for future personalization work, not shipped feature code. It locks v1 to durable list-state signals, keeps Search/Browse non-personalized in v1, makes `New to You` the first personalized surface, and defines glossary terms, ranking constraints, sprint-specific gates, rollback policy, ticket-style execution backlog items, and LLM-proof `Done only if` checklists before any implementation begins.

## Personalization Sprint 01 (2026-07-30) -- SHIPPED (backend capture)

- Migration `20260730160000_taste_signal_events_v1.sql` applied on linked project.
- Captures durable signals from `anime_user_lists` / `manga_user_lists` into `taste_signal_events`; optional `taste_profile_recompute_queue`.
- Rating thresholds use live DB **1–10** scale (`high>=8`, `low<=4`).
- Import-origin via `taste_import_context` + `concierge-apply` hooks (no list column; SET LOCAL not viable across PostgREST upserts).
- Next: Sprint 02 profile computation. Not yet: Discover `New to You` personalization (Sprint 03).

## KIMI K3 Agent Swarm overnight epic (2026-07-31) -- EXECUTED / SHIPPED

- Spec: `docs/superpowers/specs/2026-07-31-kimi-k3-agent-swarm-overnight-epic.md` (creativity-first rewrite).
- Phase 0 mandatory first: full-system + design check, creative ideation deck (≥3 concepts per problem space), Red Team, ADRs — then implement winners.
- Problem spaces: taste learning/representation, lists/IA, left-page destiny, CDN/images, clubs, ad-free monetization, design unity.
- Human priors (swipe, CDN, clubs, money) are hunches, not the prescribed solution.
- Frozen: Auth light redesign UI in progress.
- Status: **executed overnight 2026-07-31; shipped to production** (all 6 migrations applied, 2 edge functions redeployed, iOS build + KuroTests green). See the next section for what landed.

## K3 overnight ship (2026-07-31) -- SHIPPED

Phase 0 artifacts: `docs/superpowers/specs/2026-07-31-phase0-full-system-check.md`, `2026-07-31-creative-ideation-deck.md`, and 6 ADRs (taste learning/representation, leftmost surface + concierge archive, image CDN strategy, clubs overnight posture, monetization posture, design direction).

- **Taste Deck v1 (Sprint 02 delivered)**: `fetch_taste_deck_batch` / `record_taste_deck_signal` (love +0.55, known +0.25, skip −0.45; 300/day; latest action wins; retract) / `fetch_my_taste_profile`; `recompute_user_taste_profile` (events × tag ranks + genres, import ×0.25, confidence tiers 0.05–0.20, title cap 8% / franchise cap 15%, avoidance floors) + 15-min pure-SQL drain cron. iOS: `TasteDeckView.swift` at pager index 0 behind `taste_deck_v1` (100%). Migration pair `20260731010000`/`20260731011000`.
- **Personalized New to You (Sprint 03 delivered, staged)**: `fetch_personalized_new_to_you` — editorial_prior×0.8 + fit×confidence (editorial stays dominant), avoided-tag penalty, 7-day impression rotation. Wired in `EditorialDiscoverView` behind `personalized_new_to_you_v1` (0%). Migration `20260731012000`.
- **Concierge archive**: out of the pager (index 0 is Taste now); entry via Profile row + `kuro://concierge` sheet (prompt preserved) + `--kuro-start=concierge`. Backend untouched.
- **Image convergence**: remote-only mirror selection, anti-unmirror triggers on 4 tables, `priority_at` queue + `enqueue_image_mirror` (60/day), 50-row priority drain per run, visibility-ordered char/staff candidates, coverage view. Baseline: anime 2.8%, manga 1.4%, characters 0.2%, staff 0.5%. Migration `20260731020000`.
- **Clubs trust pack**: `toggle_club_reaction` allowlist fixed (was API-dead); friend-activity RPCs enforce sharing levels (privacy hole closed); flags re-seeded (reactions/list-enriched 100%, realtime/pace/notifications 0% dark). iOS: `kuro://join/<code>` share links + prefilled join sheet, never-member copy fix, duo-club honesty copy. Migration `20260731040000`.
- **Monetization ledger**: `outbound_link_events` + `record_outbound_link` (120/hr) + 90-day purge cron; iOS instrumentation on watch/read/provider-sheet/external-reference taps. `affiliate_links_v1` seeded OFF (compliance review first); no ads ever. Migration `20260731030000`.
- **Edge functions**: `mirror-images` (remote-only, visibility ordering, priority drain) and `concierge-import-anilist` (getUser 401 gate) redeployed.
- **Design law (ADR)**: one hero grammar (club-hero grain recipe), `KuroAnimation` tokens only, one placeholder spec for new UI.
- Open follow-ups: define ramp criteria for `personalized_new_to_you_v1` and the three dark clubs flags; compliance review before `affiliate_links_v1`; watch `deck_known` (+0.25) for false-positive profile drift.


## Realm Graph Stages 1–4 progress (2026-08-02)

- **Stage 1/2:** signatures, matviews, descriptors, ±0.2 deltas, Spirited Away gate harden — DONE.
- **Stage 3:** edges imported; gold harness live (`eval/realm_rec_gold` + `scripts/eval_realm_rec_gold.js`). Heuristic run: **do not ship** edges into ranking. Owner shortlists ready (`owner_shortlists.jsonl` / `owner_judgments.template.jsonl`) — fill `owner_judgments.jsonl` next.
- **Stage 4 (partial):** `fetch_tonight_shelf` + `fetch_realm_hidden_gem` + iOS behind `discover_realm_rails_v1` @ 0%. Hidden Gem now boosts `curation_seasonal_signal` hits. Still open: maintenance cron, co-occurrence, Bridge/This Week, flag ramp.
- **Curation ingest (2026-08-02):** research doc + migration `20260802150000` pushed (JCAA, Annecy expand, Taishō/Kono backfill, Critic Consensus → named desks, seasonal table).
- Deferred: taste indicators; owner canon unbless pass if needed; concurrent `media_realm_tier` refresh after large canon inserts.

## Realm repair + critique ingestion — direction locked (2026-08-04)

- Verification audit (repo + live DB + iOS) confirmed: penalty term inert, tier-refresh cron 0/4 (timeouts), raw-vs-effective membership split-brain, ~600 visible titles tier-less, similarity RPC timeouts, gold set unfilled, realm flags dark at 0%.
- Owner locked the fix direction: three measurement layers (tags = subject only; craft lineage first-class; **critic ingestion** from trust-tiered niche sites parsed into fixed axes + quotes), verdict voice copy table, deadpan content-notes table, beautiful-trash shelf (joy ≠ acclaim), gates→costs, precomputed `media_similar_titles`.
- Order: Repair → owner gold set → 10-site/200-title parser pilot → swarm → LLM regrade. Spec: `docs/superpowers/specs/2026-08-04-realm-repair-and-critique-plan.md`.
- Status: ~~plan saved, nothing implemented yet~~ → **Phase 1 (Repair) EXECUTED + verified 2026-08-04/05** (autonomous run, `docs/superpowers/plans/2026-08-04-claude-code-autonomous-phase123-prompt.md`): migrations `20260804100000`–`150000` live + committed; acceptance 13 PASS / 0 FAIL / G3 SOFT-FAIL documented; p95 42–105ms (was 3.6s), gold eval 100/100 (was 53/100 timeouts), advisor ERRORs 0. Evidence `reports/realm-repair/`. One incident on record: 25-min OOM outage during the build (fixed, guarded).
- **Phase 2 (Scoreboard):** BLOCKED ON OWNER — `owner_judgments.jsonl` still unfilled; handoff package prepared under `reports/realm-repair/`.
- **Phase 3 Round 0:** 12 site dossiers written (`reports/critique-pilot/dossiers/`), slate PROPOSED not blessed; Round 1 title shortlist DRAFT only. Round 2 (fetch/parse) does not start until owner blesses sites + titles.
- Owner security follow-up: rotate IMPORT_SECRET + move out of cron-command literal (Vault/GUC); decide weekly-vs-nightly similar-store re-stale; flag ramp decision (both realm flags still 0%).


## Edges-first serving + critique ingestion Round 2 (2026-08-05)

- **Edges-first fork SHIPPED + measured**: gold gated P@10 0.512 → **0.823** (raw ceiling 0.850). Builder ranks community edges first, safety gates demote, cosine backfills; store `src` column; RPC unchanged; revert = restore 140000 builder body. Harness P1/P2 re-scoped to junk-class intent; 13 PASS / 0 FAIL.
- **393 realm corrections live** via conditional-ordering override layer (absorption-tracked); realm audit evidence in `reports/realm-audit/`.
- **Round 2 pilot STARTED** (owner blessed slate by direction 2026-08-05): schema migration + parse pilot on compliant sites (Wrong Every Time, Manga Bookshelf, Fujitsu column). Medium = owner-session lane only; Japan Powered pending permission email (draft in `reports/critique-pilot/kincaid-permission-email.md`).
- Owner items unchanged: veto pass (tool f026a849…), IMPORT_SECRET rotation, flag ramp, re-stale cadence, mahou-shoujo realm proposal (`reports/realm-audit/mahou-shoujo-realm-proposal.md`).


### 2026-09-25 — Approved GitHub welcome and consolidated review

Pinned the owner-approved welcome to `b943e457`, separated it from local composition edits, rechecked auth/collection/home source differences, and continued the review of authentication, phone home, lists, releases, friends and free-core monetization. Updated detailed review, two-page brief and browser concepts. GitHub branch/manual release facts verified; no deployment or current phone rendering claimed. No app source or backend changed; inventory remains 93 app Swift files and 235 migrations.

### 2026-09-25 — Visual concepts withdrawn after owner critique

Owner rejected all five proposed email/first-login/Home/Collection/Agenda layouts and specified that the approved animation sets the visual direction. Replaced browser proposal with an unapproved two-screen animation-led study; updated brief/review to withdraw old layouts. Research requirements remain proposals; first-login/Collection/Agenda visuals remain unresolved. No app source/backend changes.


### 2026-09-26 — Design contract and every-call architecture audit (documentation only)

Recorded auth-only animation, retained top swipe, persistent media scope, Home/Discover separation, optional shelves and club-only opt-in activity. Added the complete review, concise visual brief, comprehensive draft execution prompt, five call registers, coverage inventories and sanitized hosted evidence under `docs/research/2026-09-26-kuro-plan/`. Withdrew earlier moving-Home prototype. Source remains 93 Swift files and 235 migrations; existing AuthView edits preserved. Sixteen sampled function bodies match live; runtime, full schema replay and deployment equivalence remain unverified. No app/backend/flags/jobs changed; no implementation commit created.

### 2026-09-27 — Discover issue (local)

The agreed Discover page is in the app: one color field, title, teaser, unnumbered rows, two color blocks, and a swipe between opened titles. Home is not restyled. Not deployed.

### 2026-09-27 — Issue-style execution prompt

`docs/research/2026-09-27-issue-style/EXECUTION_PROMPT.md` is the wave brief for the rest of the app: picture first, one line, the same open and stamp, with a pass/fail check on each wave. Discover is the only surface already on that frame.

### 2026-09-27 — Issue frame on the product pages (local)

Discover, Browse, Search, and Collection use `KuroIssueFrame`. Detail tops and club rail items use the same picture and type rules. Collection +1 and a confirmed title-page progress save stamp only after the server accepts the write. Welcome and profile are unchanged. Not deployed. See All grids, detail metadata under the jacket, Taste, and Concierge rails are still the previous chrome.

### 2026-09-28 — Route motions and staged OP/ED credits (local)

Discover’s issue is a route. Detail stills scrub when a banner and cover both exist. Collection draws plate marks from confirmed progress. Press brightens title buttons on Discover, Browse, Search, Collection, and club rails. Anime music credits are a staged, flag-off catalogue with official-link playback only. Migration is local and not applied remotely. Pager unchanged.

### 2026-09-28 — Taste page is a short recommendation list (local)

Left pager slot remains Taste. `TastePicksView` replaces the deck on that slot with at most four titles per medium, preferring Because You, then New To You, then Essentials. The judgment deck is not removed from the project. Other pages stay on the committed layouts. Not deployed.

Validation for this documentation initiative: current-state gate PASS (93 Swift / 235 migrations); all 93 Swift source hashes unchanged; CSV source locations valid; two-page brief and 143-page full report checked for page bounds and sampled visually. No new app build/runtime or deployment proof.

### 2026-09-30 — Local live-window viewer

Added `tools/live-preview/index.html` and `scripts/serve_live_preview.py`. Localhost-only server at port8799 serves only its page (other paths404). Browser window-sharing displays the selected Simulator window with requested60fps and measured presentation rate; no recording/upload or backend changes. User must select the window; actual stream/framerate not yet verified. This is a live current-window mirror, not an all-screens gallery or automatic Swift rebuild. Original app edits preserved; no scheduled automation added. Validation: HTTP200 page, non-page404; browser page opens.


### 2026-09-30 — Current original-project screen canvas

Supersedes the single-window viewer above. `tools/live-preview/index.html` now renders simultaneous phone captures with pan, zoom, Fit all, search and full-size inspection. `scripts/capture_screen_canvas.py` snapshots current original source (including local edits), builds a separate `com.Kuro.canvaspreview` app and captures registered SwiftUI screens; `--watch` rebuilds on source fingerprint changes. `scripts/serve_live_preview.py` serves only the viewer, manifest and PNG captures on loopback port 8799. Instructions: `tools/live-preview/README.md`.

The original app's Swift files/designs are unchanged by this initiative. Capture-only routing and local club sample injection occur in a disposable `/tmp` source copy. No account credentials, deployments, scheduled automations or backend writes were added. Account-dependent screens are anonymous; club detail is a labeled empty local sample. This is a screen-review canvas, not exhaustive scroll/alert/state coverage or instant Swift hot reload. Build failures retain previous captures with a stale warning. Initial 16-frame native build/capture and browser search, enlargement and Fit all verified; expanded capture verification is recorded below when complete.


### 2026-09-30 — Portable screen canvas

Added `tools/screen-canvas/index.html` with 52 representative layout captures, bundled PNGs, offline data and source provenance. Open after downloading/cloning; no Simulator or localhost server needed for viewing. `scripts/export_screen_canvas.py` exports completed captures and rejects incomplete or missing assets. Capture, export, commit and push alongside UI changes to refresh GitHub. Initial captures include local original-app edits not bundled into this canvas-only commit. Anonymous/sample states and scroll/dialog coverage limits remain labeled. No app source or production changes. Validation: 52 unique frames, local asset references and Python/JavaScript syntax checked. Direct file opening could not be browser-tested because the browser tool blocks file URLs.


### 2026-09-30 — Copyable canvas screen references

Each of the 52 canvas frames now has Copy reference (screen name/ID, SwiftUI source, screenshot path, capture fingerprint and edit instruction), Copy image (PNG clipboard) and Save PNG. Text clipboard denial opens a selectable reference; unsupported image copying points to Save PNG. All frame IDs have explicit source mappings. Updated both localhost template and portable export. Verified sign-in text clipboard contents and image/png clipboard entry in browser; JavaScript syntax passes. No native app source changes.


### 2026-09-30 — Three editorial design directions

Design review stage: three local Home/Taste/title/club-activity prototypes completed in `tools/design-directions/`, using the same content to compare editorial, Swiss typographic and gallery compositions. Browser interaction checks passed. Selection and native implementation are pending user design review; no SwiftUI replacement, backend change or deployment is claimed.


### 2026-09-30 — Reduce prototype text

Simplified all three local design directions following user feedback: removed introductory slogans, duplicate labels, main-feed descriptions and comparison essays. Home now emphasizes covers, titles, progress, upcoming dates and compact club signals. Taste keeps only a short vibe phrase; fuller descriptions appear on title tap. Core demo controls remain. Prototype-only change; native application and backend unchanged.


### 2026-09-30 — Folio design study

User rejected the initial prototypes as generic. Added `tools/design-directions/folio.html` with a new shared visual composition across Home, Taste and Title: offset numbered artwork, progress marks, compact release spines and staggered selections. Earlier concepts remain available. Progress/Undo, current-title switch, save, Anime/Manga and protected club notes were browser-checked. Design review remains pending; this is local sample-data HTML, with no app/backend/deployment changes. Prototype folder now has 13 files.


### 2026-09-30 — Personal Home replaces numbered Folio

The user rejected decorative numbering and asked for a more useful, distinctive Home. Rebuilt `tools/design-directions/folio.html` around current titles with immediate progress controls, a followed-release horizon, a compact club conversation, and a route into Taste. Two previews distinguish anime and manga; Returning / Caught up / New here show different content states. No decorative ordinals or padded counts. Meaningful episode/chapter progress remains. Progress/Undo, medium isolation, list access, title/save, spoiler reveal and first-visit behavior verified locally in the browser. Current folder remains 13 files. Design acceptance is pending; no SwiftUI, backend or deployment change.


### 2026-09-30 — Sharp artwork and direct Home interaction

Refined the accepted-for-further-exploration Personal Home direction in `tools/design-directions/folio.html`: four bundled 1800–1900 px catalogue banners replace stretched thumbnail art in the primary presentation; compact covers preserve proportions. Current titles switch through artwork swipe, thumbnail tap or keyboard. Progress targets the selected title, provides animated confirmation and Undo; title detail uses the same visual composition. Browser verified pointer drag, keyboard/tap switching, progress recovery, medium isolation, source dimensions and no console errors. AniList extraLarge cover lookup returned 403; no full-resolution cover upgrade is claimed. Prototype folder: 17 files. Native haptics, source-image ingestion improvements and final design approval remain pending. No SwiftUI, hosted data or release changes.


### 2026-09-30 — Panels alternative Home study

User rejected the latest visual treatment; it is not approved. Added `tools/design-directions/panels.html`, preserving the previous Home. Unequal artwork panels put both current titles and progress controls in view; releases occupy a compact band and club comments sit within their title artwork. No decorative numbering. Added two sourced high-resolution club banners; prototype folder now has 20 files. Browser checks covered per-title progress/Undo, medium isolation, detail routing, protected club comments and save/Undo. This is an unapproved local sample-data design study; no SwiftUI, hosted backend or deployment change.


### 2026-09-30 — Distinct medium layouts in one Home

User requires Anime and Manga to have different layouts within a coherent app. `tools/design-directions/panels.html` now opens one Home preview: Anime is scene/episode/schedule-led; Manga is book/bookmark/chapter/edition-led. Both retain the same navigation and common controls. Optional Compare layouts is review-only. Medium selection persists only under a localhost prototype key; progress is sample memory state. Browser checked medium persistence, independent progress with Undo, reading-title switching, different structural layouts, image loading and no console errors. Design approval remains pending. No SwiftUI, backend or deployment changes; prototype folder remains 20 files.


### 2026-09-30 — Personal context in the Home design prototype

Status: local design hypothesis, awaiting review. `tools/design-directions/panels.html` now derives Home from one coherent fictional account in new `home-profile.js`: list status/progress, saved titles, followed releases, shared-club relevance and manga edition language. Anime and Manga retain distinct compositions. Compact summary, saved-title start, paused-manga resume, follow-filtered releases and an inspectable context panel add useful information without long feed copy. Returning/new-member fixtures are explicitly labelled; no real account connection, recommendation engine or verified release/news feed is claimed. Medium preference alone persists; account changes reset on reload.

Browser checks: episode count responds to progress and caps at sample availability; progress/Undo and start/Undo restore list state, with previous primary title restored; resuming manga retains chapter 12 and Undo restores paused state; German hides English-only releases; unfollow removes the title's release card; a new account has no invented club/continue activity, and saving from Taste creates a personal queue entry. Both layouts inspected; all 13 displayed images loaded and no console errors observed. Cover-only titles avoid landscape stretching. New prototype folder count: 21 files. Original SwiftUI, backend and release state unchanged. Native integration, haptics, real recommendation quality and production behavior remain unverified.


### 2026-09-30 — Interactive scenes and open-shelf Home study

Design status: previous Panels composition rejected as insufficiently creative; do not treat it as approved. New local `tools/design-directions/interlude.html` explores interactive scenes for Anime and a selectable book arrangement for Manga, with consistent selected-title context tabs. Existing personal data fixtures retained; progress/list/follow changes remain local and reversible. Browser interaction and failure/empty-state checks completed for this prototype. Awaiting design feedback before any native integration; not shipped, not connected to a real account. One new HTML file; prototype folder 22 files.


### 2026-09-30 — Home design correction: multiple titles, no context tabs

Status: Interlude rejected; its selected-title/overlapping-book/context-tab approach is not approved. New `tools/design-directions/flow.html` demonstrates multiple current titles, variable-size grouped schedules, new releases and club context in one image-led vertical scroll. Local browser checks complete for progress/save Undo, independent media, multi-event follows, empty language results and inline detail. Design approval, real-data mapping, production scalability and native integration are still pending. No app/backend release. One new HTML file; prototype folder 23 files.


### 2026-09-30 — Divergent visual exploration after Flow rejection

Status: Flow is not approved. Added `tools/design-directions/studies.html` with three structurally different compositions (Thread, Cut, Journal) and full-phone review mode. Retains four current titles and multi-title release groups without context submenus. Local progress/cap/Undo, saving/Undo, inline club spoiler and medium-isolation checks completed. Design review pending; no native/backend/release implementation. Prototype folder 24 files.


### 2026-10-01 — Home design reference gate

Status: Thread/Cut/Journal rejected; no Home redesign approved. Added local `tools/design-directions/references.html` with source-attributed MUBI/Cosmos visual references and Sofa/Sequel tracking references. Eight promotional screenshots load and enlarge. Next native implementation remains pending design agreement; retain multiple ongoing titles, full day release groups, medium-specific layouts and continuous scroll. No claim of Mobbin library access, tested native motion/haptics or retention gains. Prototype folder 25 files; no native/backend/deployment changes.


### 2026-10-01 — Personal Home prototype ready for design review

Implemented local `journal.html` + `journal.css` + `journal.js` + `journal-data.js`, with ten additional public artwork assets (design folder 39 files). Distinct medium layouts, four active titles each, multiple releases per date, separate new releases/discovery, title details, progress/save/Undo and club spoiler interaction. Busy/quiet/new/missing-data and failed-save scenarios checked locally, including phone-width overflow and no fabricated club data for a new account. Design acceptance remains pending. Native implementation, native motion/haptics and real data/performance validation are not complete or released. This prototype is separate from the rejected Journal option in `studies.html`.


### 2026-10-01 — Living-world direction ready for review

User authorized a radical alternative to previous editorial layouts. Local `world.html`/CSS/JS plus two generated landscape assets and `world-art.json` are complete as an interactive design experiment; folder 45 files. Four initial titles per medium, pan/zoom/overview/recenter, direct progress, arrivals [3,2], discovery/add/find, completion/history/Undo and club spoilers implemented against fixtures. New/failed-write cases and narrow-phone controls checked; action overlap and pointer-transform issues fixed. User design approval, native build, scalable dynamic scenery, real data, native haptics and performance verification remain pending. Pinch/audio not implemented. Original app and prior studies preserved; no deployment.


### 2026-10-01 — Modern Home comparison pending selection

Living-world direction rejected by user. Added three local alternatives in `tools/design-directions/modern.html` with separate CSS/JS: Shelf (collection first), Screen (graphite imagery), Today (activity first). Same six ongoing titles and three initial updates, Anime/Manga variations, [3,2] followed-release groups, two new releases and club context. Progress/caps/Undo, state isolation, failed save, details/Escape, save/Undo, spoilers, loaded images and narrow responsive layout verified in browser; source syntax checked. Folder 48 files. No native implementation or deployment; selection, native accessibility/motion/haptics and real account/large-list validation remain pending. Existing app preserved.


### 2026-10-01 — Aperture Home / artwork medium switch

User rejected the modern comparison as insufficiently creative and explicitly requested a different top switch/visual. Added `tools/design-directions/aperture.html`, `aperture.css`, `aperture.js` (design folder 51 files). Prototype replaces medium tabs with a single full-width artwork selector: tap or horizontal pointer swipe changes medium; selected medium persists separately. Anime uses staggered frame compositions; Manga uses open-volume layouts with intact covers and margin progress. Six active titles per medium, follow-release groups [3,2], new releases and protected club commentary remain continuously scrollable. Existing sourced artwork is reused; data is fictional. No native/backend changes.

Local browser verification: tap and pointer-swipe switch, independent medium progress, caps/Undo, failure leaves progress unchanged, in-dialog progress/Undo feedback, save/Undo, spoilers, six-title capacity, [3,2] release groups, image loading, 390px no horizontal overflow, no captured console errors; JS syntax and diff checks. Native touch/haptics, empty/large accounts, full accessibility review, backend integration and user design approval remain pending. Header navigation/profile are visual context only. Mutations reset on reload; medium alone persists. Prior variants and unrelated source preserved.


### 2026-10-01 — Aperture material and interaction polish

Refined existing `tools/design-directions/aperture.css` and `aperture.js` at the user's request. Anime has inset translucent mounts, cutout seams, layered shadows and recessed progress buttons; Manga has paper/cloth-like CSS backgrounds, layered page edges, folded corners and ribbon bookmarks. Medium selector has an inset artwork tray, highlight sweep and swipe-follow feedback. Added press compression, progress spring/ring confirmation, animated progress fill, staggered medium entrances, artwork-origin detail opening and animated close/Escape. Motion is bounded to interactions; no ambient animation loop. Reduced-motion CSS and JS guards are present. No new files/assets in design folder (51 files), no additional copy or native/backend changes.

Browser checked: progress cap, Undo, failed save unchanged state, in-dialog progress/Undo, animated close and Escape, save/Undo, spoiler reveal and 390px no horizontal overflow. Reduced-motion emulation confirmed content animation name `none`; all-animation enumeration was unavailable in the read-only browser scope, so full runtime animation inventory was not verified. Temporary emulation/viewport overrides reset. JS syntax and whitespace checks passed. Native haptics, real device motion/performance, comprehensive accessibility and design acceptance remain pending. Fictional local account only; unrelated source edits preserved.


### 2026-10-01 — Pinterest-informed Aperture palettes

Reviewed actual Pinterest images for editorial mobile, book-app and movie-app layouts, plus burgundy/cream and blue/butter palette grids. Refined `tools/design-directions/aperture.html`, `.css`, `.js` in place: explicit reusable palette tokens, Oxblood/parchment (default), Ink/powder and Olive/butter controls; a compact high-contrast artwork switch, calmer borders/shadows, larger small text, full Anime covers instead of portrait crops of scene banners, simplified Manga page surfaces, and restrained confirmation motion. Removed the prior dense textures/gloss/curls. Palette controls are review UI and remain accessible at phone widths. Palette and medium persist under separate prototype keys; palette changes do not rerender or reset account state. `?palette=ink|oxblood|olive` selects a shareable starting palette. Reference links are in the desktop review panel and design README. Asset query versions avoid stale CSS/JS during local review. Three existing files changed; design folder remains 51 files, no imported reference media.

Verification: palette persistence/reload, progress/cap/Undo across palette changes, failed-save unchanged state, list saving/Undo across palettes, detail/Escape, spoilers, all displayed images loaded, Anime and Manga fit 390px without horizontal overflow, reduced-motion content animation computes to none (temporary overrides reset), JS syntax and diff checks. Calculated secondary-text contrast on the soft release-panel surface: Oxblood 4.84:1, Ink 4.76:1, Olive 4.52:1; these token checks are not a full accessibility audit. User approval/native integration, haptics and device performance remain unverified. Fictional local account; native source/backend unchanged.


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

### 2026-10-01 — Home v11: aligned composition and deliberate controls

Owner requested the studio/reference board in the sidebar and questioned the mismatched banner arrangement. Interpreted that as staggered card rows and inconsistent container corners; aligned active and recommended titles, normalized release/club corner radii, and straightened the club artwork. Preserved curved progress openings and distinct six-title Anime/Manga layouts. Extended cancellable contact feedback to club art/title/secondary rows, release-detail, close and Undo controls. Replaced progress overshoot with a 180ms settle, clarified enabled secondary actions, and made selector dragging use its actual half-width travel. Removed decorative inactive Home arrows. Studio now links directly to `boring-study.html`; reference summary updated.

Changed only `tools/design-directions/instrument.html`, `instrument.css`, `instrument.js`, `boring-study.html`, the design README and required state/plan documentation. No new repository files (65 design files); pre-edit v10 copies at `/tmp/kuro-home-v10-before-refinement/`. Existing local studio tab was stale and was refreshed. Board opened in the sidebar; public preview verified serving v11 with original expiry unchanged. Browser checks: aligned equal-height Manga row pairs, 16 loaded images, no 320px overflow in either medium, six 44px progress targets, cap/Undo, failed progress preserving count, spoiler expand/collapse, no warning/error logs. JavaScript syntax and whitespace checks pass. Screenshot `/tmp/kuro-home-aligned-refinement.png`. This is prototype evidence only, not native haptic/physical iPad or release proof; visual approval remains pending.

### 2026-10-01 — Home v12: continuous artwork surface

Implemented the proposed Home-only composition in `tools/design-directions/instrument.html`, `instrument.css`, and `instrument.js`. Ongoing covers share one rounded white surface rather than individual masked card backings. Each progress well responds to contact; successful updates add a 620ms edge highlight alongside the count/check. Reduced Motion removes the highlight and transitions. Action targets stay fixed and 44px. Anime keeps a six-title compact grid; Manga retains larger paired artwork. Upcoming groups follow a fine date spine with room for three simultaneous releases. Club artwork, identity and comment share an open composition, and recommendations no longer have separate white backings.

Browser checks: cap at 5, Undo, failed progress preserving count at 4, cancelled vertical drag preserving count, inline release expansion, club spoiler expand/collapse, both media at 320px without horizontal overflow or progress-label/button overlap, six 44px Manga progress targets, and 768px layout with all 16 images loaded. Reduced Motion reported highlight animation none and 0s transitions while the count updated. Warning/error log empty; JS syntax and diff whitespace checks pass. Public URL verified serving v12; original approved expiry unchanged (2026-10-02 02:44 UTC). Screenshot: `/tmp/kuro-home-continuous-phone.png`. Pre-edit v11 copies: `/tmp/kuro-home-v11-before-surface/`. No new repo files (design inventory65); required documentation updated. No native/backend changes or physical iPad/haptic proof; owner review pending.

### 2026-10-01 — Home v13: foreground and ongoing composition

Owner clarified that visual hierarchy and the overall experience needed a substantive rethink. Changed `tools/design-directions/instrument.html`, `instrument.css`, and `instrument.js`: reduced the opening headline, emphasized two available titles with larger artwork, and moved four ongoing titles into a compact two-column layout. Anime gets dark artwork framing and Manga gets light print-like margins. The existing release timeline and open club composition retain different visual roles. All six titles have direct 44px progress controls; compact club shortcuts remain visible over the artwork edge. The new heading derives singular/plural availability from the two featured fixtures and falls back to Keep watching/reading when caught up. Featured slots remain fixed during progress updates.

Browser proof: both media at 320px have no document overflow or progress-label/button overlap; Manga has six 44px progress targets. At 390px, a direct pointer tap updated progress 4→5 and heading 2→1, while all six card coordinates and scrollTop=0 remained unchanged. Semantic browser clicks were observed to auto-scroll 13px before interaction; the direct pointer check separates that automation behavior from app reflow. Undo restored progress/header, failure preserved both, club shortcut opened the correct title context, caught-up fixture disabled all known-total Anime actions, and new-account fixture showed two suggestions with no active cards. Reduced Motion yielded no artwork transforms. At 768px, no horizontal overflow and all16 images loaded. JS syntax and whitespace checks pass; warning/error log empty. Public preview verified v13 with2 featured/4 compact entries; original sharing expiry unchanged. Screenshots: `/tmp/kuro-composition-anime.png`, `/tmp/kuro-composition-manga.png`.

Pre-edit v12 files preserved at `/tmp/kuro-home-v12-before-composition/`. No new repo files (65 design files). Updated the reference summary, README and three required state/plan documents. Native/backend files untouched. Physical-device/haptic feel and owner acceptance remain unverified. This fixture study is not a complete availability ranking algorithm: a production Home must handle additional new titles in the ongoing group and use genuine release metadata.

### 2026-10-01 — Home v14: story discovery and complete control pass

Owner asked for more deliberate UI across every element and a short story sentence only on new recommendations. Updated `tools/design-directions/instrument.html`, `instrument.css`, and `instrument.js`: recommendations now immediately follow ongoing titles; their cards combine artwork, title, format and a concise premise into one opening target, with separate 44px Plan to watch/read toggles. Planned state is visibly filled and reversible. Ongoing title names now open details with cancellable press feedback; no premise is shown on ongoing cards or their tracked-title sheet. Internal arrows use forward chevrons. Static avatar decoration became plain For Max identity text. New-account content starts directly with recommendations, removing repeated empty-state headings/artwork. Notifications now have a 44px dismiss action that restores focus to the triggering control. Found and corrected four compact cover targets that were39px wide at320px.

Verification: all visible Home buttons in both Anime and Manga meet44px width/height at320px, with no horizontal overflow. Both story layouts retain19–35px between premise and save control at320px. Verified save/remove/Undo, failed save preserving false state, failed progress→retry→cap→Undo, notification dismissal/focus return, full story opening, tappable ongoing title, no tracked-title premise, keyboard Enter/Escape with correct focus restoration, cancelled title drag, release expansion/detail opening, spoiler reveal/conceal, reduced-motion0s story image transition, and768px layout with all16 images loaded. Console warning/error log empty; JavaScript syntax and diff checks passed. Public allowlisted link servesv14; original expiry2026-10-02 02:44UTC unchanged. Screenshots `/tmp/kuro-home-v14.png` and `/tmp/kuro-story-cards-v14.png`. Public verification tab closed to preserve the user's single-tab workspace.

Saved pre-editv13 files at `/tmp/kuro-home-v13-before-story-cards/`. No new repository files (65 design files). Required docs/README/reference summary updated; no native/backend edits. Story copy is four manually authored, publisher-checked fixture sentences, not a production generation pipeline. Physical iPad/native haptics and owner design acceptance remain unverified.

### 2026-10-01 — Home v15 implementation checkpoint

Distinct Anime scene composition and Manga reading spread implemented throughout the Home browser prototype; current CSS consolidated. Six direct progress actions per medium, new-title premises, separate planning controls, release/club composition, material-changing labeled switch and image-only motion implemented. Browser happy/failure, keyboard, gesture cancellation, 320px targets/overflow and 768px image/layout checks passed. Native integration and owner approval remain open gates. Three existing catalog banners added to the approved share allowlist; refreshed temporary URL retains the original 02:44 UTC expiry. See the current-state changelog and design README for exact evidence.


### 2026-10-01 — Home v16: deliberate polish of the accepted direction

The owner explicitly liked v15 and authorized the full next refinement. Preserved its distinct Anime scenes and Manga reading spread; this is not a new art direction. Six areas completed in `tools/design-directions/instrument.html`, `instrument.css` and `instrument.js`: aligned Manga title/progress/metadata rows using subgrid (with a flex fallback), equal Anime caption docks, quieter inset action materials, clearer compact typography, persistent caught-up/check states with known availability denominators, and a coordinated 320ms medium transition that animates images rather than hit targets. Unknown Manga totals remain unbounded and omit fractions/percentage tracks. Removed a redundant recommendation label.

The interaction audit found that mutations rebuilt the entire feed and title sheet. Replaced that path with `syncActions(k)`: update only affected progress, save state, accessible labels, availability, heading and open-sheet summary. Spoilers likewise change only their own disclosure. Undo retains focus within the replacement result message, and dismiss returns to the source. In-place updates preserve surrounding controls and scroll. Release-detail entrance now fades its copy without translating the next action.

Browser evidence: at390px both Anime captions measure89px including the border, and both Manga title/progress/metadata rows share identical y coordinates. At320px, both layouts have zero horizontal overflow and all visible Home buttons are at least44x44. Compact labels do not overlap progress buttons; recommendation premises retain11–20px before saving in Anime and12–20px in Manga. Tested cap→Undo, failure→retry, independent media, unknown Manga totals, synchronized Home/sheet progress and save removal, notification focus and unchanged scroll (683px before/after save Undo), new-account saving, caught-up fixtures, release switching/collapse, protected club spoiler reveal/hide and correct club context. Keyboard arrows and reload retain the chosen medium; rapid medium switching settles to one selected state with no cover-button transforms. A14px cancelled pointer drag leaves progress at4 and clears contact. Reduced Motion removes transitions and retains completion feedback. At768px, no page/phone overflow and all16 displayed images loaded. Browser warning/error log empty. JavaScript syntax and diff whitespace checks pass.

Files: three Instrument files, reference-board summary, design README and the three required root state/plan documents. No new repository files/assets; design inventory remains65. Backup: `/tmp/kuro-home-v15-before-polish/`. Screenshots: `/tmp/kuro-home-v16-anime.png`, `/tmp/kuro-home-v16-manga.png`. Public browser verified `instrument.js?v=16`, equal caption docks and loaded artwork at https://graduate-sullivan-aside-floyd.trycloudflare.com/instrument.html . Original expiry remains2026-10-02 02:44UTC /04:44CEST, subject to Mac/tunnel availability. No server restart, new public files or extension of access.

Scope and proof: owner endorsement applies to v15 direction, not automatic acceptance of every v16 detail. Native SwiftUI, backend/auth, real-account data, release/news accuracy, physical iPad/Safari behavior and haptics are unchanged/unverified. This is local and temporarily hosted browser-fixture proof only. Required project memory is recorded through the allowed memory extension mechanism, not by overwriting the memory registry.


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

### 2026-10-02 — Withdraw rejected compact list

Home v23 withdraws the rejected v22 full-width Also watching list and restores the v21 two-column layout. The compact season treatment is still unresolved; this restoration is not design approval. The owner-liked v20 detail selector, large cards and Manga remain unchanged. Browser fixture only; no native/backend change. CSS matches the pre-v22 layout after removing its override block; JavaScript is unchanged. Cache version incremented to 23. No files added or deleted.

### 2026-10-02 — Home v24 compact Anime sleeve proposal

Home v24 proposes compact Anime sleeves for Also watching: intact larger poster artwork, a numbered season edge with the current season highlighted, and an integrated episode/progress/+ footer. Two-column layout retained. Season edge opens the existing overview without changing tracking. Owner-liked detail panels, large Anime cards and Manga remain unchanged. Design awaits owner review; browser fixture only. Checked 320/390/768px fit, minimum 44px compact targets, opening/inspecting seasons without tracking changes, +1, Undo and simulated save failure. Browser error log empty. JS syntax and diff checks pass. No native/backend changes; no new/deleted repository files.

### 2026-10-02 — Home v25 minimal compact season line

Home v25 restores the original compact Also watching cards after rejection of v24 sleeves. Season numbers now interrupt a fine line under the episode count, with a ring around the current season. The combined progress/season summary is a 44px overview target; + remains a separate mutation. Large Anime cards, Manga and the liked detail selector remain unchanged. Browser proposal awaiting owner review. Restored 92px compact card height. Verified 320/390/768px fit, 44px targets, season preview independent of tracking, focus return, +1, Undo and simulated failure. Noncompact progress markup is identical for anime/manga, known/unknown totals and completion cases. Syntax/diff checks passed. Existing approved public preview serves v25; expiry unchanged. Three prototype files and existing docs updated; no repository files added/deleted, native/backend work or deployment.

### 2026-10-02 — Home v26 centered season indexes

Home v26 extends the minimal season index to main Anime cards: centered beneath each card, separated from title/progress and club context. A softly raised current-season ring and fine connecting line are shared with the compact treatment through one renderer. Compact cards stay 92px tall. Liked detail selector and Manga remain unchanged. Design proposal awaits review; browser fixture only. Verified centered alignment and no overflow at 320/390/768px, 44px controls, preview-without-tracking changes, focus return, episode cap, Undo and failed saves. Detail/overview/Manga rendering functions unchanged. No new/deleted repo files, native/backend writes or deployment. The two-wave series plan remains INCOMPLETE and NOT STARTED.

### 2026-10-02 — Home v27 season cut-outs

Home v27 replaces the rejected detached v26 number line with a centered season index inside the lower edge of each main Anime card. The current number forms a paper-colored cut-out tab; other numbers remain unboxed. Compact cards retain the v25 plain outlined marker and original 92px height. Liked detail selector and Manga are unchanged. Browser fixture proposal awaiting owner review, not an approved design or native implementation. Verified 320/390/768px fit, 44px season targets, exact main-index centering and bottom-edge alignment, season preview independent of tracking, focus return, episode cap, Undo and simulated save failure. Detail, Manga, compact and progress rendering functions unchanged; JS syntax and diff checks passed. No browser errors observed. No new/deleted repository files, native/backend changes or deployment. Series plan remains INCOMPLETE with both waves NOT STARTED.

### 2026-10-02 — Three season-label treatments

Home label comparison v28 is available at `instrument.html?seasons=compare`: Caption notch, Rail caption and Artwork tab, each demonstrated on one main Anime card and two compact cards. The default Home remains v27; the liked detail selector and Manga are unchanged. No option selected or approved. This is an isolated browser fixture comparison. Verified 320/390/768/1280px layouts (320px overflow corrected), 92px compact heights, season targets of at least 44px, large/compact/artwork season entry points, preview without tracking changes, focus return, progress and Undo across the shared examples. Default Home/detail/Manga/progress renderer parity, JavaScript syntax and diff checks pass. No new/deleted repository files; design directory stays at 65 files. No native/backend changes or deployment.


### 2026-10-02 — Local preview server restored

The local design server on 127.0.0.1:8803 was stopped and has been restarted, bound to localhost and serving only `tools/design-directions`. Verified HTTP 200 for the season comparison page and v28 JavaScript. Browser reload was blocked by the browser URL policy on its internal error page; owner must refresh the existing tab. No design/source/backend change, new automation, public tunnel renewal or deployment.

### 2026-10-02 — Selected artwork season markers

Home v29 saves the owner-selected Artwork tab treatment: only a white Season N marker on main Anime images and an S-number stamp on mapped Also watching covers. Numbered season rows are removed from both sizes. Tapping the marker/compact cover opens the existing full season overview; episode progress remains separate. The comparison board marks Artwork tab as selected and reflects the same simplification. Approval applies to this season treatment, not the complete Home or implementation plan. Browser prototype only; no native/backend deployment. Checked 320/390/768px fit, main targets at least 44px high and small-cover targets 44×66px, correct full-season counts in details, preview independent of tracking, compact progress/Undo, and Manga preservation. Liked detail/Manga helper/progress functions remain identical. JS syntax and diff checks pass. No new/deleted repository files; design directory remains 65 files.


### 2026-10-02 — Scoped Home design checkpoint

Prepared a scoped local Git checkpoint of the selected v29 Home prototype, required sample data/artwork, linked reference board and focused run instructions (`tools/design-directions/INSTRUMENT_README.md`). Only relevant current-state/plan documentation is staged; unrelated working-tree changes remain local. No push or deployment. One run-instructions file added; design directory now contains 66 local files.

- 2026-10-02 — Extended the existing incomplete two-wave series plan and added v30 interactive Anime/Manga detail mockups. Selected-season context, characters, music search, creator credits, source handoff and club presentation are local design fixtures; no ingestion, native or production changes.

- 2026-10-02 — v31 detail visual/interaction polish in the local prototype; existing plan updated in place. Checked responsive fit, touch targets, season isolation, next-unit progress/Undo/failure and manga caught-up behavior. No native, hosted or released claim.

- 2026-10-03 — Added five-source local visual reference board; current Home unchanged, next Manga design pending review.

- 2026-10-03 — Added three opt-in Manga Home compositions and live comparison; local checks passed, owner selection pending.


### 2026-10-03 — Rejected study checkpoint and Crosscut proposal

**Manga composition checkpoint (2026-10-03):** Owner rejected Edition/Contact/Index, including the dark-skin approach. New Crosscut browser proposal uses alternating artwork panels and chapter gutters, with existing tracking and navigation behavior. Reviewed 320/390px fit, six loaded covers, 44px keys, failure/completion/Undo, unknown totals, dense releases, empty/caught-up/undated fixtures, details/clubs/Taste/Anime and reduced motion. Owner approval remains open. Singular series/Home plan remains v0.8 INCOMPLETE, exactly two unstarted native/backend waves. No production task is completed by this study.


### 2026-10-03 — Equal artwork and four Manga Home philosophies

**Four Manga philosophy checkpoint (2026-10-03):** Crosscut is rejected: no offset or unequal manga artwork/containers. Added Library (cover index/shared workbench), Chapter Board (uniform tracking instrument), Journal (sample recency timeline), and Club Room (shared/private reading table plus solo reads) in `manga-four.html`, with equal artwork sizing per study. Local functional/phone/failure/Undo/reduced-motion checks pass; none is selected or native implementation. The singular series/Home draft remains v0.8 INCOMPLETE with two unstarted native/backend waves.


### 2026-10-03 — Library selection and polish

**Selected Library checkpoint (2026-10-03):** Max selected Library for Manga Home. Local Poster Manga now defaults to the selected composition; `manga-library.html` shows its polish. Equal artwork, selected frame, aligned labels, shared Next control, known-total trace and keyboard selection checked locally with failure/completion/Undo and navigation. No native/backend production task is complete. The singular series/Home plan stays v0.8 INCOMPLETE, exactly two unstarted implementation waves.


### 2026-10-03 — Library unified touch targets

**Library touch-target checkpoint (2026-10-03):** Unified artwork/title/chapter selection and moved detail navigation to a labelled83x44 workbench button. Local320/390px geometry, selection/detail/focus and chapter failure/completion/Undo checked. Native translation and physical-device usability remain open. Singular series/Home draft remains v0.8 INCOMPLETE, exactly two unstarted native/backend waves.


### 2026-10-03 — Library direct detail access

**Library direct-detail checkpoint (2026-10-03):** Removed the bar-only detail restriction. One whole-book tap opens its story and synchronises the shared workbench; existing Details is an optional shortcut. Local navigation/focus/phone/progress failure/completion/Undo/reduced-motion checks pass. Physical-device gesture checks remain open. Singular v0.8 series/Home plan stays INCOMPLETE, exactly two unstarted native/backend waves.


### 2026-10-03 — Library independent selection/navigation

**Library independent-actions checkpoint (2026-10-03):** Replaced rejected select-via-details model: whole-book selection stays on Home; each book has its own full-width44px Open action that preserves selection. Removed redundant workbench Details action. Local320/390px functional/focus/progress failure/completion/Undo/reduced-motion checks pass. Physical-device usability remains open. Singular v0.8 plan stays INCOMPLETE, exactly two unstarted native/backend waves.


### 2026-10-03 — Library per-book tracking proposal

**Library per-book tracking checkpoint (2026-10-03):** Owner rejected previous Open-button/shared-selection design. New local proposal removes that model and attaches existing chapter actions to each read. Equal artwork and44px controls checked with navigation, independent updates and failure/completion/Undo. Approval and native testing remain open. Singular v0.8 plan stays INCOMPLETE, exactly two unstarted native/backend waves.


### 2026-10-03 — Temporary phone preview

**Temporary review access (2026-10-03):** Owner requested a phone-accessible public preview. Current allowlisted Instrument share runs for12hours, stopping by4October02:39 Europe/Berlin. Public file/access and390px browser rendering checks pass; native Safari/device proof remains open. This review link does not complete native/backend work or imply owner design approval; v0.8 remains INCOMPLETE with two unstarted waves.


### 2026-10-03 — Coming Up first-viewport summary

**Coming Up phone checkpoint (2026-10-03):** Local Instrument adds a first-viewport release summary, using the existing calendar fixture source and one accessible jump to the full calendar.320x568/390x667/390x844, both media, keyboard/focus/reduced motion,48 releases/8 dates, undated/new/caught-up/Taste checks pass. Library per-book foundation liked by owner; this new summary still awaits review. No native/backend execution, deployment, share scope expansion or TTL renewal. Singular v0.8 remains INCOMPLETE, exactly two unstarted waves.


### 2026-10-03 — Restore remaining phone-preview session

**Temporary preview restored (2026-10-03):** Browser/app restart stopped the earlier preview and removed its temporary binary/screenshot. The old trees-marc-amongst-obtain link is unavailable. Restored the same45-file design-only allowlist via official Cloudflare2026.9.3; current link: https://cage-sustained-copy-when.trycloudflare.com/instrument.html?switch=poster&medium=manga&embed=1. Only the remaining authorized duration is used, still stopping4October02:39 Europe/Berlin. No account/backend data, share-scope expansion, recurring automation or TTL renewal. Replacement public page and loaded artwork verified; original Coming Up local/browser checks remain valid.


### 2026-10-03 — iPad preview recovery

**iPad preview recovery (2026-10-03, 21:34 Berlin):** Owner reported the replacement link did not work. The previous8814 listener and temporary binary were absent; the cage-sustained-copy-when link did not resolve. Restored the same45-file allowlisted preview with official Cloudflare2026.9.3 in the visualization runtime folder, using a detached subprocess rather than a foreground chat-terminal session. Current link: https://ratio-yarn-raise-scholarships.trycloudflare.com/instrument.html?switch=poster&medium=manga. Original automatic stop remains4October02:39 Europe/Berlin; no renewed duration, recurring service or expanded public files. Fresh HTTP200 for HTML/CSS/Instrument/Library modules and404 for .env/current-state docs. Browser tool is currently unavailable, so no new screenshot, Safari or iPad visual proof claimed. No UI/native/backend source changes; two-wave v0.8 implementation plan remains INCOMPLETE and unstarted.


### 2026-10-04 — Reopen local studio preview

Restarted the loopback-only design server on8803 (detached PID70343) and visibly opened manga-library.html in the Codex browser. Confirmed the embedded current Library/Coming Up renders. No UI/native/backend changes, public tunnel renewal, commit or deployment. Series/Home plan remains INCOMPLETE; native/backend waves unstarted.


### Change Log — 4 October 2026: Manga story overview

**Manga story overview checkpoint (2026-10-04):** Browser-only story-copy gap closed for all six Library reads; four missing publisher-backed fixtures added and unknown generic Manga copy uses an unavailable state. Optional synopsis disclosure and Anime season copy checked, Home/progress unchanged. Four existing prototype files edited (detail-data54/JS61, Library iframe61). Identity-safe adaptation matching and deferred missing-target resolution recorded in the existing singular draft. v0.8 remains INCOMPLETE; exactly two waves/16 parent tasks, native/backend work NOT STARTED. No deploy, commit, new public share or device proof.


### Change Log — 4 October 2026: Master-plan retention

Retained adaptation matching and story-overview requirements in the single master plan; no execution status changed.


### Change Log — 4 October 2026: Home/detail execution specification v1.0

**Home/detail execution specification v1.0 (2026-10-04):** Planning COMPLETE FOR REQUESTED HOME/DETAIL SCOPE in the existing singular master plan. Exactly two waves: F1–F3 foundation and X1–X3 native/wiring/qualification, with the original16 task IDs retained for traceability. Both execution waves NOT STARTED, gates NOT PASSED, staging/live/released NOT VERIFIED. Previous incomplete draft snapshots below are historical and superseded by v1.0 planning status. No implementation, deployment or public share in this initiative.


### Change Log — 5 October 2026: Production executor handout v1.1

**Home/detail production handoff v1.1 (2026-10-05):** Planning COMPLETE for requested scope. New start-ready Claude Code handout exports the same singular master plan with initial database audit, every-call growth review, concurrency/rapid-edit/lifecycle guarantees, revocation-safe private clubs, both-provider import fidelity and1000/5000-session qualification. Exactly F1–F3 and X1–X3 in two waves; execution NOT STARTED, wave gates NOT PASSED, capacity/staging/live/released NOT VERIFIED.46 preview/dependency files pinned; no implementation, deployment or new sharing/automation.

### Change Log — 5 October 2026: Modular architecture and measured migration plan

**Modularity migration planning (2026-10-05):** [Modular architecture and migration plan](docs/plans/2026-10-05-modular-architecture-plan.md) and its measured baseline define the architectural companion to Home/detail v1.1. Planning complete; checkpoints A–I NOT STARTED, no architecture gates passed. Defaults: review production files above 400 lines and modules above 2000; hard ceilings 600/3000 with narrower responsibility budgets, recorded exceptions and no-growth legacy baselines. Current native source: 94 files / 46,537 lines, 34 above 600; shared service family 7154 lines and 30 environment consumer files. Full scope estimate 55–94 engineer days, subject to reestimation. No implementation/release proof and no changes to the existing two product waves.

### Change Log — 5 October 2026: Judgment based modularity review policy

**Modularity migration planning (2026-10-05, revised policy):** [Modular architecture and migration plan](docs/plans/2026-10-05-modular-architecture-plan.md) replaces the initial LOC ceilings with responsibility-based review, keep/split/defer records and structural correctness gates. Adds first ownership assignments, an end-to-end extraction recipe, review examples/template and explicit Home/detail overlap without new product waves. Architectural checkpoints A–I remain NOT STARTED, no gates passed; baseline remains 94 native files / 46,537 physical lines and 7154 shared-service lines. Provisional scope estimate 55–94 engineer days remains subject to reestimation. No implementation, deployment or capacity proof.

### Change Log — 5 October 2026: Autonomous modular architecture execution brief

**Modularity execution brief (2026-10-05):** [Claude Code execution brief](docs/plans/2026-10-05-modular-architecture-plan.md) supersedes the earlier architecture order/effort assessment with a prompt-first autonomous multi-agent contract, 35/25/20/10/10 decision weights, mandatory G0–G7 gates, risk-specific tests, coordinated E0–E8 integration and independent review. No source-length caps, target quota, schedule or effort estimates. Explicit lifecycle repair precedes packages; current production ownership includes social/provider preferences/realm/telemetry, shared UI/routes and active operations. Architectural execution NOT STARTED; every stage and gate remains unverified. Existing Home/detail v1.1 scope and two delivery waves remain separate and unchanged. Documentation only; no app/backend/prototype/CI changes or deployment/capacity proof.

### Change Log — 5 October 2026: Modular architecture executed locally

**Modular architecture execution (2026-10-05):** Brief executed locally across E0–E8 (ledger: [execution ledger](docs/plans/2026-10-05-modular-architecture-execution-ledger.md); final owner map: [ownership map](docs/plans/2026-10-05-modular-architecture-ownership-map.md); developer guide: [docs/modules/README.md](docs/modules/README.md)). `SupabaseService` retired; 16 owner folders under `Kuro/` plus `Packages/KuroModules` (3 targets); typed routes, shared cards, detail decomposition and Concierge rules landed in the final lanes; lifecycle, Library, import-safety and club-revocation corrections integrated with tests; backend changes prepared but NOT deployed; open items and blockers as listed in the status entry at the top of this file. Gate status and final counts are recorded in the ledger only; no gate is claimed passed here. Inventory: 129 app Swift files, 14 package Swift files, 235 migrations (+3 prepared). No commit, deployment, production data access or release.

### Change Log — 5 October 2026: Cross-layer integration continuation

**Not complete (2026-10-05):** Native Apply/Undo v2 presentation, signal subscriptions with a legacy-content bridge, fail-closed limiters on the remaining Concierge functions, credential leases for provider preferences and Concierge recommend/warmup/feedback, nullable club authors and silent cancellation. Register rows F11, F12, F15, F32, F33, F42, F65, F80, F85, F86 updated. Selected simulator tests succeeded; Deno limiter tests 7 passed. G0–G7 not passed. No deployment.

### Change Log — 7 October 2026: Independent Home/series review

R01–R16 in [the independent review](docs/handoffs/2026-10-07-home-series-evidence/INDEPENDENT_REVIEW.md) leave both integrated delivery waves incomplete. Actual-source local reproductions confirm progress/outbox defects; narrow tests and intact browser files do not qualify native fidelity or capacity. Earlier closure/demoted-gate entries remain history and are superseded for readiness. No app/SQL/hosted change.

Review documentation check initially found stale current inventory labels; corrected only those labels in the two state docs and CLAUDE to the verified local counts: 133 app Swift files, 20 package Swift files and 245 migration files. No source files were added to app/package targets, and file counts do not establish deployed migration parity.


### Change Log — 7 October 2026: Codex migration repair execution

Executed targeted migration repairs with proportionate verification: rag-v2 scopes Anime/Manga/unscoped cache and avoids outage poisoning; recommendation rejects wrong-medium seeds; exact deletion barrier becomes terminal rather than retryable in server/client. Live probes now prove real delivery and genuine journal denial with bounded cleanup. Existing native owner journey now exercises real dispatch and passed1test. Backend affected suites16+32passed, script checker12passed, focused independent review accepted. Fresh live journal Apply/Undo and six42501denials passed; both disposable users deleted. No deployment/flag change/App Store upload. Native terminal-error contract also passed exactly 1 test (0 failed, 0 skipped); the earlier zero-test selector was corrected and not counted as a pass. The concurrent Home compile mismatch was repaired by its owner. Release access and remaining findings stay open. Evidence: docs/handoffs/2026-10-07-modularity-execution-evidence/README.md. New files: retrieval recommendation repository test, probe support/checker, native runner helper, active execution note and sanitized evidence files. Existing files retained; no deletion by this initiative.

- 2026-10-07: Started authorized independent-review repairs (durable sync, import replay/fidelity, account/privacy, selected-season and schema/query contracts). See repair ledger for exact proof and open work; not production closure.

### Change Log — 7 October 2026: Cursor, ops and register reconciliation

F20 shared production/test PostgREST DB encoder emits fractional UTC Z, retains millisecond precision and leaves Auth/decoding intact. Two existing cursor contracts passed (structured2/0/0), independently accepted. F57 three dashboard/six installer root defaults use established resolver with tuning preserved;13 offline checks plus syntax checks and independent acceptance, no jobs executed. New file: Kuro/Composition/PostgrestRequestEncoding.swift; current inventory134 app/20 package/245 migration files. Parser/alias F27–F31 source acceptance and no-backfill/no-cron residuals reconciled. Current Swift manifest185rows and generator expanded for packages and operational source types. Historical source/ownership/completion claims explicitly superseded. Remaining architecture/native/deployment work remains NOT COMPLETE; no deployment/flag/upload.

### Change Log — 7 October 2026: Home repair evidence reconciliation

Preserved unrelated dirty work while repairing R01–R16; shared integration is now on `codex/integrated-testflight`. Detailed source/proof matrix and logs: [repair ledger](docs/handoffs/2026-10-07-home-series-evidence/REPAIR_LEDGER.md). Producer backfill locks source before queue mutation; completion locks catalogue before job; source revisions/leases reject stale writes. Club disclosure purges enriched/private caches immediately, rejects stale uncached provider responses and separates privacy refresh from membership loss. New files for this initiative include `scripts/series_enrichment_worker.py`, its offline test, actual Home drain runner/repro, `KuroTests/ClubDisclosureRepairTests.swift`, SQL94/95 and SQL96 backfill race specifications, and repair evidence/docs. No repository file was deleted by this repair. Package76/Home/AniList7/enrichment8 PASS; native parse only. SQL94 historical50 PASS is not latest SQL qualification. Current SQL/performance/native/device/live/release remain incomplete; no IPC cleanup, deployment, flag activation, scheduled worker or upload. The new integrated envelope is an explicit later user scope decision, not a silent waiver.

- Repair documentation gate PASS: current shared inventory 150 app Swift files, 22 package Swift files, 245 migrations. Inventory markers in the two current-state docs and CLAUDE were refreshed without changing rules. SQL96 specification independently reviewed; still NOT RUN.


### Change Log — 7 October 2026: Integrated TestFlight source continuation

Approved integrated two-wave scope and preserved dirty/untracked migration inputs on codex/integrated-testflight. Added Library-owned progress/status recovery, exact unit/string cursors, bounded personal Home offline snapshot/partial tracking knowledge, initial SDK reconciliation and transport-only expired-session presentation restore, account-scoped tester enrollment cache, captured-account deletion cleanup/admission SQL95/96, capability-specific model/RPC ownership, Profile import workflow coordinator, Concierge action lifetime, native selected-season/unit/edition controls and legacy detail loader/paging cancellation. Staged Fastlane freezes/validates exact inputs and separates real live-service evidence from valid local SQL; no zero-test or partial release pass.

Evidence: actual compiled Library/Home/SQLite/precision/cache harness passes; focused high-risk source review repairs discovered defects; Fastlane10tests44assertions, live-evidence/SQL-partition9tests, native-runner5offlinecases and20distinct offline probe cases passed (12 affected legacy-probe cases rerun after the bounds delta; unchanged8 reused). Swift syntax and architecture boundaries passed. These are local/owner/offline/source proofs. Final SQL cannot start with exhausted shared-memory resources left untouched per user; Xcode license blocks typed native/package/SDK runs; management/admin/signing/MAL registration/consent/physical-device proof are unavailable. MAL account list importer and final release qualification remain incomplete. No backend deployment, new hosted writes, archive or upload by this continuation. Source/evidence checkpoint at docs/handoffs/2026-10-07-integrated-release-evidence/source-checkpoint.json is not a frozen release artifact. Full checklist/executor: docs/handoffs/2026-10-07-integrated-testflight-execution.md.

New capability files: fourteen shared model/RPC owner files, Kuro/Home/HomePersonalSnapshot.swift, Kuro/Imports/MALNativeAccountConnector.swift, Kuro/Imports/ProfileImportCoordinator.swift, Kuro/Concierge/ConciergeWorkflowLifetime.swift, Packages/KuroModules/Sources/KuroLibrary/LibraryProgress.swift and focused regression sources. Central SupabaseModels/SupabaseRPCParams retired. Prepared flag/account lifecycle SQL and regressions95/96 are not deployed. Backend review repaired rejected mapping reuse, failed mapping/deactivation reads, malformed deletion acknowledgments and provider deadlines; the final alias-decision read fails closed and is independently source-accepted. Chapter8/deletion22/recommendation9 focused Deno cases pass, with unchanged relevant evidence reused. Provider URL normalization and retrieval confidence/identity validation passed actual Foundation/Deno checks. App Store metadata/reviewer draft, eight-category privacy manifest and source-reviewed FileTimestamp reasons are prepared; vendor/archive/Connect privacy qualification remains open. Runtime/release/probe helper files are listed in the ownership/evidence snapshot; unrelated work retained. Inventory below is current; older point-in-time counts remain historical.


### 2026-10-07 — proportionate gates and remaining integrated source

Proportionate gates are implemented in Fastlane: affected local checks during development, one integrated native/package/backend/selected-SQL verification, then real service and installed TestFlight proof. Future signing/live/device access is not due during development; correctness/privacy/replay and required workflows remain mandatory for release. MAL account ingestion for both media is implemented, primary contracts retrieved and source-reviewed, with controlled registration/consent still unavailable. Original-account/mount admission, Collection batch isolation, stale conflict controls and Profile deletion/preferences are repaired and independently source-accepted. Actual Core action tests, MAL reader, Library/Home/SQLite and Collection policy checks pass. Ten affected PostgreSQL suites pass253assertions, all12prepared migrations apply; historical baseline replay stays incomplete. No deployment, archive, upload or installation. Xcode license, Supabase administration, signing, controlled MAL consent and physical-device proof remain the precise release prerequisites. See [the complete executor/evidence/checklist](docs/handoffs/2026-10-07-integrated-testflight-execution.md).

New source: `Kuro/Imports/ImportsService+MALAccount.swift`, `Packages/KuroModules/Sources/KuroCore/AccountActionScope.swift`, `Packages/KuroModules/Sources/KuroLibrary/MALAccountList.swift`. Existing rendering, identity, tracking, import and release owners were repaired in place; required regressions reuse existing suites. Inventory:151app/24package Swift files,29native test files,245migrations; no new SQL migration. Legacy uppercase list rows require read-only live counts before any reviewed repair. Unrelated work and local servers were preserved. This entry supersedes the earlier IPC-blocked/MAL-source-incomplete notes; it does not qualify a release.


### 2026-10-07 — Xcode and release-access refresh

**Access refresh, 7 October — NOT RELEASED.** Xcode27.0 first-launch validation passes. Actual package81tests, Home snapshot5cases and credential/permission contract3cases PASS. Native compilation errors (missing KuroCore import and duplicate Home declaration) and three outdated test fixtures are repaired and independently source-accepted. The broader native runner stalled after its logged host exited; it was interrupted and has no finalized acceptance result. No whole-native PASS is claimed. Physical iPhone “Max” is paired/booted on iOS26.6; one development and one distribution signing identity are present. Existing ASC key4Y9VLAQLQN returns403 `FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`; the Account Holder must review agreements, then team/app/upload permissions can be checked. Fastlane references an absent older key. Supabase administration and controlled MAL registration/consent are still unavailable. No credential changes, backend deployment, upload or physical installation. Earlier license/hardware absence notes are superseded by these observations.

### 2026-10-07 — Simulator-only delivery and live administrative inspection

**Current target, 7 October — SIMULATOR ONLY / INTEGRATION IN PROGRESS.** Max explicitly removed TestFlight upload and physical-device delivery from this initiative. Debug 1.0 (17), bundle com.Kuro.app, built successfully and is installed/launched on iPhone 17 Pro / iOS 26.0; onboarding is visually verified, not a signed-in workflow pass. Supabase browser administration now works through existing GitHub sign-in. Two bounded read-only live audits found no malformed/noncanonical/colliding legacy list IDs, and confirmed exact auth.uid()::text owner policies. The six Home/detail/page RPCs, Home flag rows and feature_flag_overrides table are absent on the live project. No schema/customer/flag changes or deployment. MAL registration is pending: the browser site policy blocks apiconfig/create; the user must complete the prepared form and provide the Client ID. Existing 81 package / 5 snapshot / 3 contract passes remain valid; the broader native runner stays incomplete. Signing agreements, archive, upload, TestFlight and physical qualification are outside the current target. [Execution and evidence](docs/handoffs/2026-10-07-integrated-testflight-execution.md).

Evidence: `simulator-only-install-receipt.json`, `simulator-only-build-pass.log`, `simulator-only-installed.png` and `simulator-live-readonly-audit.json` under `docs/handoffs/2026-10-07-integrated-release-evidence/`. Two read-only5second-bounded queries return metadata/aggregates only; no customer identities/content or administrative credentials retained. Sixteen deployed function slugs observed; exact versions/source not inspected. No Swift files added/removed and no code changed in this initiative;151app/24package/29unit/3UI Swift files and245migrations remain. The current directive supersedes earlier mandatory TestFlight/physical delivery clauses without waiving safety or required advertised workflows.


### 2026-10-07 — Focused native authentication/import recovery and live contract preflight

**Latest simulator follow-through, 7 October — INTEGRATION IN PROGRESS.** Owner authorized live sign-in/Home/import/recovery checks. Focused Xcode SDK authentication: 19 PASS, 0 failures; import apply/outcome/retry/Undo: 6 PASS. Controlled HTTP is used, so these are native SDK proof, not live UI/GoTrue/Home proof. Initial 21-pass/4-fail run is retained. Two fixture issues were corrected without weakening assertions: per-scenario real SQLite/WAL injection prevents shared-file cleanup contention, and the stale-account fixture now really returns A then B. Independent review accepted the narrow change; production storage defaults are unchanged. Two further read-only live audits confirm eight new Home/tracking/import RPCs and eight checked foundation tables are absent; live has nine 5 October migrations plus 6 October import-session policy. Aggregate existing list rows: 37 Anime, 11 Manga. Exact two-migration deployment draft is prepared, not applied; global flags stay off. Real simulator login and concrete production-grant approval are pending. Native UI automation timed out after the clone test run. No live account/customer/schema/flag changes, TestFlight or upload. [Evidence](docs/handoffs/2026-10-07-integrated-release-evidence/simulator-auth-import-recovery.md). Earlier status banners below are historical and superseded where they conflict.

Changed native files: `Kuro/Composition/AppComposition.swift`, `KuroTests/IdentityCompositionTests.swift`. Added read-only preflight, pinned deployment draft and finalized test summaries/logs/receipt under the integrated evidence directory. Inventory unchanged: 151 app Swift, 24 package Swift, 245 historical migration files. No new tests, deployment or hosted mutations.


### Change Log — 7 October 2026: Final scoped simulator checks and exact SQL rehearsal

**Latest simulator execution, 7 October — LOCAL CHECKS PASS / LIVE INTEGRATION PENDING.** All387 distinct native cases have passing evidence across the initial362-case run, affected-suite repairs and the previous19SDK/6import cases; no unchanged whole-suite rerun. Four test files repaired with focused independent acceptance; production guards unchanged. The selected16SQL suites pass511assertions, and the exact two-migration atomic transaction/history rehearsal passes31assertions. Backend imports pass52tests/typecheck. Latest Debug1.0(17) is installed/launched on iPhone17Pro/iOS26.0 and the real sign-in form is open; signed-in workflows remain unverified. Live read-only preflight confirms all20newfoundation tables absent/all31existing prerequisites present, no orphan list rows, current deletion helper reviewed. No live changes/deployment/global rollout or TestFlight. Actual sign-in, specific production-grant approval and controlled MAL registration/consent remain pending. [Current evidence](docs/handoffs/2026-10-07-integrated-release-evidence/simulator-integration-progress.json). Earlier banners are historical where superseded.

This initiative changed four native fixture files (CollectionContractTests, IdentityCompositionTests, ClubsContractTests, LibraryFacadeTests), preserving real SDK credentials, batch ordering, immediate private-cache purge and successful progress assertions. No production source file changed in this follow-through. Evidence includes failed initial runs and a stopped owned clone-start/diagnostics attempt; no zero-test or interrupted run counted as acceptance. No app/package/migration files added or removed; inventory remains151app/24package/29native-unit/3UI Swift files and245migrations. Operational SQL assembly/evidence added under the integrated handoff. Global flags stay off; live trigger behavior also affects existing clients when eventually deployed. Historical migration replay remains incomplete.


### Change Log — 7 October 2026: Requested sign-in and MAL registration attempt

Actual simulator login fields are empty; the normal saved-password option supplied no credentials. No sign-in/reset/new account. The existing MyAnimeList registration page is explicitly blocked by browser site-security policy; no bypass attempted and no form filled/submitted. Native public-client/callback values checked and owner handoff prepared in docs/handoffs/2026-10-07-integrated-release-evidence/simulator-sign-in-mal-handoff.md. The owner must enter Kuro credentials locally and complete the blocked MAL form with actual applicant/homepage and agreement acceptance. Existing MAL configuration remains empty/not approved; no production source, live account/schema/provider/flag changes or TestFlight. Prior valid local evidence remains unchanged.


### Change Log — 7 October 2026: Reusable development login and sidebar handoff

**Latest access initiative, 7 October — SIGN-IN PASS / RESTORE FAIL / MAL HANDOFF.** One owner-authorized ordinary persistent GoTrue development account was created; credentials retained privately outside the repo. Genuine password sign-in and authenticated identity pass, and the simulator Profile shows the expected development email/build1.0(17). Ordinary restart returns to welcome, including after normal signed build/install; root cause unresolved, no auth-code repair claimed. Final simulator is signed in again. MAL registration is confirmed open in the sidebar for manual owner completion under the existing site-security restriction; client remains unconfigured. No existing account changes, admin grants, schema/flags/deploy/TestFlight. Prior unchanged local evidence remains valid at its layer; installed restore is a new failed check. [Evidence](docs/handoffs/2026-10-07-integrated-release-evidence/development-account-sidebar-handoff.md). Earlier banners are historical where superseded.

No app/package/migration files added or removed. Added sanitized auth/install evidence and handoff; credentials stay outside repo and evidence. Actual restart failure remains open, with prior local proof retained.


### Change Log — 8 October 2026: Actual sign-in, callback identity and restore qualification

**Latest simulator qualification, 8 October — SIGN-IN / RESTORE / SIGN-OUT PASS; MAL CLIENT ID PENDING.** Actual normal password-form sign-in and restart restore pass on com.Kuro.app. A dedicated iPhone17Pro/iOS26.0 simulator also proves supported SDK callback, same-account restore and immediate sign-out to AuthView. Earlier callback FAIL is not current-artifact proof: the original simulator has a canvas preview also claiming kuro://; old observations remain historical. Existing preview apps/data were preserved; no production auth repair or unchanged broad suite rerun. Owner reports MAL registration complete; site policy blocks reading issued client values, public Client ID requested, connector remains disabled. Home/import candidate RPCs still absent live. No new live account, admin/schema/flag/deploy/TestFlight changes. [Current installed proof](docs/handoffs/2026-10-08-simulator-qualification/qualification.md). Earlier banners are superseded where they conflict.

No app/package/migration inventory changes. Added targeted installed-app evidence and one isolated simulator; only ignored callback orchestration and state/evidence documents changed. Secrets remain privately retained outside repo.

### Change Log — 8 October 2026: Published MAL registration configured for simulator

**MAL registration/configuration, 8 October — SIMULATOR CONFIGURED; SERVER INTEGRATION BLOCKED.** User screenshots verify the published native iOS registration and exact kuro://mal/callback. Debug.xcconfig enables the public client only for iphonesimulator; Shared/Release remain disabled and no confidential secret is embedded. Normal signed build/install and matching built Info.plist pass. Actual Profile exposes Connect and import MAL, which reports Library synchronization is not enabled yet before any provider consent. Existing sign-in survives the update. Exact Home/import SQL is still prepared/rehearsed, not deployed; controlled OAuth and real import/recovery remain pending. No live schema/grant/flag changes, archive or TestFlight. [Evidence](docs/handoffs/2026-10-08-simulator-qualification/qualification.md).

### Change Log — 8 October 2026: Effective backend integration and precise import repair

**Backend execution checkpoint, 8 October — IN PROGRESS / NOT DEPLOYED.** Fresh effective live/source audit expands the obsolete two-SQL proposal to exactly3SQL+6Edge closures. New status/precise Undo/lifecycle repair and atomic assembly are independently source accepted; exact rehearsal118assertions passes (9 history/install/data,40SQL81,69SQL94), original input hashes retained. Six Edge closures match prior accepted checkpoint. Existing CLI administration and read-only Auth/Storage cleanup verification are available. Preserve live5% RAG and disabled global Home; use Debug simulator override only after live contracts verified. Disclose legacy_lifecycle_unavailable for older Undo journals; no session backfill/scheduler. Remaining: specific live deploy approval, named deployment and postflight, installed Home/import/recovery/MAL consent and changed live service/cleanup proof. Simulator-only target; release/physical requirements remain historical/out of current delivery. [Complete backend integration](docs/handoffs/2026-10-08-backend-integration/backend-integration.md).


### Change Log — 8 October 2026: Deep import user-journey review and deployment hold

**Import integration, 8 October — REQUEST CHANGES / TWO-WAVE REPAIR REQUIRED.** The deeper27-finding review supersedes previous broad backend source/local acceptance. Six structured database defects and focused XML parser defects were reproduced locally. Wave1 repairs typed existing-title policy, ingestion fidelity, recoverable manifests, terminal cleanup, stop/results contracts and authoritative Library projections. Wave2 wires actual AniList/MAL entrypoints, persistent review/results/navigation, bounded refresh and installed simulator/live qualification after an approved revised deployment. Prior accepted legacy Apply/Undo remains accepted; no blanket retest or new framework is required. Deployment manifest is HOLD; no code repair/deployment/rollout/TestFlight in this review. [Full findings and risk-matched execution](docs/handoffs/2026-10-08-backend-integration/import-user-journey-review.md).

### Change Log — 8 October 2026: Import review, recovery and shared Library integration

Implemented the two-wave specification without replacing existing capability owners. New source files: `ImportsService+Workflow.swift`, `ImportsService+WorkflowRPC.swift`, `ImportsService+WorkflowSources.swift`, `ImportWorkflowPresentation.swift`, `ImportWorkflowSheet.swift`, `ImportCatalogMatchPicker.swift`, `ImportHistorySection.swift`, `CollectionStore+ImportedTitles.swift`, package `LibraryImportWorkflow.swift`, `LibraryImportWorkflowJournal.swift`, `ImportWorkflowJournalTests.swift` and native `ImportWorkflowIntegrationTests.swift`. Added forward `20261008110000_import_review_recovery_v2.sql` and SQL97 regression suite. Existing AniList/MAL adapters, journal, Library transport/sequencing, projection consumers, actual entrypoints and composition were repaired in place; legacy Concierge compatibility stays available.

Default Keep, selected-field approval, coupled progress/score identity, provider-ID namespace, strict XML/status/range checks, staged coverage, immutable receipts, Stop, lifecycle/revision-guarded Undo, persistent results and same-device recovery are implemented. Final independent review also closed an Apply/Resume race with newer unsent progress or admitted removal/notes. Terminal retirement is receipt-first/manifest-last; a saved result awaiting projection keeps its full recovery input. Imported navigation remains a Collection filter. No lossless claim is added to legacy text export.

Evidence: exact four-input guarded SQL rehearsal265 assertions, package95 tests, native r5 41 distinct methods/54 executions and two affected generic-reservation tests pass. The final affected11-import/3-publication run passes14/14 methods, zero failures/skips and222 unchanged candidate inputs. Exact tested simulator candidate installed; all bundle hashes match and normal launch restores the existing account. SQL and high-risk source independent acceptance is recorded in the same27-finding register. Historical full schema replay is incomplete; fixtures are not hosted GoTrue/Storage/PostgREST/Realtime proof. Production approval and controlled live provider/simulator journeys/cleanup remain pending.

Inventory:159 app Swift,27 package Swift,30 native test Swift;245 historical migrations;14 prepared top-level SQL inputs plus one opt-in historical backfill (excluded). No applied-history rewrites, customer backfill, deletion-barrier cron, deployment, TestFlight or global Home activation. Rules: one lifecycle owner/typed API, immutable attempted actions, missing-versus-clear semantics, current account/permission guards, persistent partial outcomes, semantic line-length review signals and focused independent high-risk review. Unrelated dirty changes were preserved.

Final local delivery addendum: affected native14/14 PASS,222 candidate inputs unchanged; exact tested simulator1.0(17) installed with complete bundle-hash match. Actual launch restores the existing account; MAL pauses safely with foundation disabled. [Evidence and four gates](docs/handoffs/2026-10-08-backend-integration/import-v2-implementation-evidence.md). Full completion remains BLOCKED pending exact live deployment approval and subsequent included provider/installed/live journeys and cleanup. No deployment or TestFlight.


### Change Log — 8 October 2026: Exact approved backend deployment and native Home qualification

**Import/Library/Home execution, 8 October — approved backend deployed; installed qualification in progress.** The canonical two-wave implementation remains the scope. Exact four-SQL/six-Edge deployment completed and effective identities verified. Real v2 import/replay/Keep/update/conflict/Stop/Undo/owner isolation and Realtime pass with administrative disposable cleanup. Origin deletion and old-token upload denial pass; cached-public-URL propagation remains disclosed. Accepted Home/detail presentation repairs and actual Library reader correction are built and installed; restored Home is visible. First-time Manga cache-selection repair is independently accepted, built, exactly installed and actual Anime→Manga selection verified. A controlled MAL user account is unavailable; real account-connector qualification is specifically blocked. Other included provider/recovery/navigation journeys and final simulator verdict remain pending. No TestFlight/public submission/global Home activation/backfill/worker scheduling. [Current evidence](docs/handoffs/2026-10-08-backend-integration/approved-deployment-live-evidence.md). Earlier conflicting status notes are historical.

Inventory:160 app Swift,27 package Swift,30 native test Swift;245 historical migrations remain unchanged. Added HomeCalendarPresentation.swift (display-only) and probe_import_workflow_v2.js (bounded existing harness); repaired the existing Storage/Realtime producers and Library selector. No new lifecycle owner, test framework or scheduler. Ownership map updated. Prior r6/r3 and presentation-only install evidence remains scoped historical; current reader-build install has223 stable inputs and matching bundle hashes.


**Simulator visibility and MAL clarification, 8 October:** The user clarified that no MAL user account is available. The browser login was dismissed; the separate Xcode Simulator window was raised with Home visible. “Qualification” is the device name, not a product screen or completed verdict. The final independently accepted Manga cache correction is now installed with exact bundle identity, retained app data/Keychain and local Debug flags; actual Anime→Manga selection remains selected. No provider login, consent or real account-list ingestion is claimed. Only controlled MAL account qualification depends on obtaining a test account; other Home/Library/AniList/XML/recovery journeys remain independently executable and pending. No backend change or TestFlight action. [Installed state](docs/handoffs/2026-10-08-backend-integration/approved-installed-home-readiness.json).


### Change Log — 8 October 2026: Native design polish planning

Tracked the new visual workstream with scoped ownership, first-action routes, artwork continuity, Profile groups, accessibility/motion safeguards and proportionate acceptance. Current native visual translation is not owner accepted. No runtime implementation, tests, backend deployment or TestFlight action occurred. [Plan](docs/plans/2026-10-08-native-design-polish.md).


### Change Log — 8 October 2026: Fresh-session continuation

Prepared the handoff and executor prompt for the current native design-polish plan and remaining import/Library qualification. It preserves the simulator-only target, two presentation passes, existing functional contracts and proportionate checks. Fresh Git/live/installed provenance distinguishes completed deployment from unmerged local work. Corrected stale current-summary statements about pending deployment, an open MAL login and an uninstalled Manga fix; historical evidence retained. No runtime work. Handoff provenance includes a dirty-file manifest, checkout snapshot and read-only live metadata. No app/package/migration files added or removed; runtime inventory is unchanged. [Handoff and next-session prompt](docs/handoffs/2026-10-08-fresh-session/HANDOFF.md).

### Change Log — 9 October 2026: Native design polish first pass

Implemented the plan's shared neutral roles and the Home, detail and Profile compositions. Shelf decisions are `HomeShelfPolicy`. Import from Home uses `ImportSourceChooser` over the existing coordinator. `HomeShelfPolicyTests` and `HomeCompositionSnapshotTests` pass. Controlled screenshots and the installed empty-account launch are under `docs/handoffs/2026-10-08-fresh-session/native-polish-screenshots/`. Visual acceptance remains open. Functional import journeys, MAL account qualification and the Storage CDN observation are not closed by this pass.

### Change Log — 9 October 2026: Full Poster Home

Saved Home uses the Poster compositions with the chosen adjustments. The empty invitation is unchanged. Visual acceptance remains open.

### Change Log — 9 October 2026: Empty and saved Home

The picture is limited to the empty invitation. Saved shelves use the white original layout. Visual acceptance remains open.

### Change Log — 9 October 2026: Home continues

Full-phone Home wash, readable chrome and medium words, Find opens Discover, import sheet matches the invitation type. `--kuro-seed-samples` writes four catalog titles through the library. Visual acceptance remains open.

### Change Log — 9 October 2026: Invitation type

Home invitation uses the cover-line plus kicker pair. `kuroKicker()` is the shared small voice. Find and Import stay the same actions. Visual acceptance remains open.

### Change Log — 9 October 2026: Picture through header

Pinned `HomePagePicture` behind the status bar and header on Home; cleared Home header chrome; soft wash only over lower type. Snapshot suite and owned-sim install updated (`home-picture-through-header.png`). Visual acceptance remains open.

### Change Log — 2 November 2026: Contact form (website + app)

Status: implemented locally on `kuro/prototype-fidelity`, NOT deployed. Prepared migration `20261102100000_contact_messages.sql`, Edge Function `contact-submit` (deploy `--no-verify-jwt`), legal site `kontakt.html` + privacy §4.15, app owner `SupportStore` + `ContactSheet`. Go-live needs owner approval: migration, function, `CONTACT_IP_HASH_SECRET`, optional Resend env, legal-site redeploy.

### Change Log — 2 November 2026: Contact form review fixes

Status: fixed locally on `kuro/prototype-fidelity`, NOT deployed. `contact-submit` limiter (IPv6 /64 buckets, IP check before token verification, app IP cap 30/h, per-account 5/h, web global 200/h, notification ceiling 50/h), CORS for `kuro-legal.vercel.app`, Resend alert required for go-live; app consent link to the contact-form section, UTF-16 length rules, reset on reopen, Art. 16 DSA hint; legal pages lead with Max Hufschlag. Go-live is now a hard release prerequisite: `docs/go-live/2026-11-02/CONTACT_FORM_RELEASE.md`.

### Change Log — 2 November 2026: Go-live

Status: LIVE on `bkdifromsqxkndnllmdj`. Release schedule + songs RPCs and intake (jobs 116/117), AnimeThemes backfill, catalogue import restored (secret rotation, page-depth stop, item-error fixes), contact form (migration + `contact-submit`, secret-keyed buckets). TestFlight build 20 (prototype redesign, icon M, Contact sheet). Open: Resend e-mail alert, `20261101030000_auth_hardening` after release, series flag rollout, legal site production deploy + domain, App Store submission. Records: `docs/go-live/2026-11-02/`.

### Change Log — 2 November 2026: Navigation contract foundation

Status: foundation implemented locally on `kuro/prototype-fidelity`, NOT deployed. Journeys (`JourneyHost`, `JourneyPage`, `JourneyPolicy`), chrome + shrinking header, edge swipe-back fix, fold memory, root collapse coordinator (N10) and the WARN gate `check_navigation.sh` exist; screen migrations (detail, club, person pages, Search/Profile/see-all/season sheets, ContentView deep-link wiring) are open for the navigation lanes.

### Change Log — 2 November 2026: Navigation lane "clubs"

Status: implemented locally on `kuro/nav-clubs` (from foundation `b03c885`), NOT deployed, NOT pushed. Club detail is a journey page (chrome with back/settings/✕, shrinking paper bar, swipe-back restored; rail items and This-week entries push titles), creating a club opens it, Home season overview is a journey with ✕ + grabber, verdict sheets have a grabber + Cancel, create club/rail/poll + tracking editor + contact block swipe-down on unsaved input and confirm "Discard changes?", the import chooser keeps Stop reachable while busy. Gate offenders 16 → 14. Open: UI tests on the owned simulator (§5) for Club → rail item → detail → add to club → cancel.
