# Kuro: final screen map (2026-11-01)

These are the final visual evidence for every screen in the app after the overnight redesign. The inventory and IDs come from `docs/overnight-2026-11-01/understand/screens.md`.

- **Build:** branch `kuro/overnight-2026-11-01` at `e874ce2`. HEAD moved past `a2ad7e8` during this pass when two commits landed: Auth legal line and the deploy checklist. Both runs below used `e874ce2`.
- **Fixture renders** (`fixture/`):
  - Source: `KuroTests/ScreenMapSnapshotTests.swift`. The views are hosted in `UIHostingController` and drawn at 3x.
  - No network: graphs use a nil client, `FakeLibraryBackend`, or the in-process `StubPostgREST` endpoint.
  - Fixture artwork comes from `tools/design-directions/assets`. Two manga titles carry cover art from other works (the "Berserk" row shows a JJK cover, "Vagabond" shows Berserk). That is a fixture labelling artefact, not an app bug.
  - Skips and their reasons are in `fixture/NOTES.txt`.
- **Simulator captures** (`app/`):
  - Debug build installed over the existing signed-in app on `7FC4B58A…` (data kept), light appearance, content size large, status bar 9:41.
  - Read-only: nothing was tapped.
  - **World A** = server flags. **World B** = `--ff-on=series_foundation_v1 --ff-on=series_home_native_v1`.
  - Detail pages were opened by deep link using internal ids (`kuro://anime/21` = Assassination Classroom, `kuro://manga/30013` = Almight Network).
- **`--kuro-start` in World B now works.** `B-discover.png` and `B-collection.png` land on Discover and Collection about 9 s after launch, after flag hydration, and differ from `B-home.png` by md5. Last night they were byte-identical to Home. `B-collection` is byte-identical to `A-collection` for a valid reason: it is the same Folio page in both worlds, at the same pager index 3.
- **World B detail = legacy body.** `SeriesAnimeDetailView` falls back to the legacy sections because the live series tables are empty (spec D15; REPORT.md §"Series grouping has no producer"). `B-detail-*` therefore matches `A-detail-*`. The native series detail shell exists only as a fixture: see `../snapshot-final/detail-*.png`.
- **German: not captured.** `KuroLocale` reads `Locale.preferredLanguages` and has no override hook. Writing `AppleLanguages` would change the real app's preferences.

Verdict key: **good** = ship as is; **needs polish** = visible flaw, not blocking; **broken** = wrong or illegible on a primary path.

## Gates, chrome, pager pages

| # | Screen | How reached | Screenshot | Verdict and issues |
|---|---|---|---|---|
| G1 | Config-error screen | `identity.configError` | not captured: needs a broken build config | — |
| G2 | Auth-bootstrap splash | cold launch while the session restores | not captured: under 1 s, not stable for a still | — |
| G3 | Offline strip | `!networkMonitor.isConnected` | not captured: needs the network cut | — |
| G4 | Auth welcome | signed out | `fixture/auth-welcome-390.png`, `-320.png` | **good.** At 390 the "Kuro" wordmark sits tight on the headline, inside the scenery. At 320 the headline fills the band and the wordmark and headline nearly touch, but nothing is clipped. |
| G5 | Auth email form: sign in | welcome → Sign in, or an auth notice | `fixture/auth-signin-390.png`, `-320.png` | **good.** Clean tabs, the notice line ("Check your email, then sign in."), and Forgot password. At 320 the Forgot link sits at the bottom edge of a 568 pt screen. |
| G5 | Auth email form: create account | welcome → Get started | `fixture/auth-signup-390.png`, `-320.png` | **good.** The live 8-character rule and the privacy line render. The privacy line is small (meta size) next to 17 pt fields. |
| G5b | Set new password (recovery) | `identity.requiresPasswordUpdate` | `fixture/auth-set-password-390.png`, `-320.png` | **good.** Same language as the form. |
| G6 | Auth "Genie" hero | DEBUG `-AuthGenieHero` only | not captured: debug only | — |
| G7 | Launch overlay | every signed-in mount, about 0.4 s | not captured: too brief | — |
| G8 | Onboarding frame 1: Anime or manga? | first run (fullScreenCover) | `fixture/onboarding-frame1-390.png` | **good.** Scenery still, serif line, ink rule, Continue. The "Skip" capsule floats on the scenery with no visual anchor. |
| G8 | Onboarding frames 2–3 | Continue / Not now | not captured: frame is private `@State`, and Continue writes the medium to the real `UserDefaults.standard` | — |
| C1 | Header (wordmark, section pill, dots, search, profile) | above the pager | every `app/*.png` | **needs polish.** "KURO" sits on a faint grey blurred blob. Search and avatar are filled grey circles while the section name sits in a white capsule: two treatments in one bar. |
| C2 | Transient banner / toast | `BannerCenter` | not captured: only after a write | — |
| P1 | Taste (`TastePicksView`) | pager index 0, `--kuro-start=taste` | `app/A-taste.png` | **needs polish.** Blurbs are still non-synopsis copy: Samurai Champloo's is "let's break it down." and Trigun's starts with a lowercase "vash the stampede…". "+ Plan" buttons sit at different heights in the two columns. |
| P2 | Home (series) | World B index 1 | `app/B-home.png`; fixture `../snapshot-final/*-home-*.png` | **needs polish.** The art-filled "Anime" title is still mottled (purple and brown patches inside the letters, no contrast floor). "Coming up: Nothing scheduled this week" is now a single honest line; last night it was a duplicate Calendar message. The continue card for Cowboy Bebop has a stacked "Ep. / 0 / 26" numeral beside a square "+", a third key style next to Folio's outlined and filled keys. |
| P2a | Home invitation picture | empty medium | `../snapshot-final/empty-home-390.png` | not re-captured; see the earlier evidence |
| P3 | Discover | pager, `--kuro-start=discover` | `app/A-discover.png`, `app/B-discover.png` | **good.** The Today's Pick synopsis truncates mid-word ("great gen…"). Only the left rail title wraps, so the two cards have uneven heights. |
| P4 | Browse | pager (World A only) | `app/A-browse.png` | **needs polish.** The dropdown row ends with "All genres ⌄" against the right edge and no scroll cue. Grid card titles wrap to two lines ("Demon Slayer: Kimetsu no Yaiba") while the neighbour stays on one, so meta lines are misaligned. |
| P5 / P5s | Collection = Folio lists | pager, `--kuro-start=collection` | `app/A-collection.png`, `app/B-collection.png` | **needs polish.** The live list has one row (Cowboy Bebop 0/26) and about 70% of the page is blank, with no footer or hint. The status strip clips at "Paused" (there is a fade now, which is better than last night). "Completed 0" is shown as a selectable word. |
| P5 | Folio Index, anime/manga, 320/390/430 | Collection → Index | `fixture/folio-{anime,manga}-index-{320,390,430}.png` | **good** at 390/430. **Needs polish at 320:** the controls row wraps to two rows (density words alone on the first), the next-release line wraps "Ep. 8 · Wed, / Nov 4" across lines, and titles wrap to two lines. A row with no known total shows a bare "1" with no unit. |
| P5 | Folio Shelf, anime (scene cells) | Collection → Shelf | `fixture/folio-anime-shelf-{320,390,430}.png` | **good.** Banner scenes with title and progress, and an outlined key at the right. Cells are tall, so only 3½ titles fit on a 390 screen. |
| P5 | Folio Shelf, manga (cover grid) | Collection → Shelf | `fixture/folio-manga-shelf-{320,390,430}.png` | **needs polish.** The advance key is a **filled black square** here and an outlined square in Index and anime Shelf. The key row floats about 40 pt below the title, detached from its cover. A title with progress 0 shows the key alone with no "Ch." line, so it reads as orphaned. |
| P6 | Clubs: empty | pager, `--kuro-start=clubs`; Profile → Clubs | `app/A-clubs.png`, `fixture/clubs-empty-390.png` | **good.** On brand. The "CLUBS" kicker repeats the header pill directly above it. |
| P6 | Clubs: first load | cold launch on Clubs | `app/A-clubs-loading-7s.png`, `fixture/clubs-loading-390.png` | **needs polish.** The skeleton is rounded grey cards with outlines, the only card-shaped chrome left in the app. On a cold launch it was still showing at 7 s and resolved by 10 s. |
| P6 | Clubs: failed | the read fails | `fixture/clubs-failed-390.png` | **good.** "Couldn't load your clubs. / Try again in a moment." plus an ink-rule Try again. It sits high on the page rather than centred. |
| P7 | Concierge page | both flags off only | not captured: unreachable in either world | — |

## Sheets and covers

| # | Screen | How reached | Screenshot | Verdict and issues |
|---|---|---|---|---|
| S1 | Profile | header avatar → Profile | `fixture/profile-seeded-390.png` (6 anime + 6 manga seeded) | **good.** Library summary ("6 anime · 6 manga · 2 completed"), list rows with covers, and Open Collection. The identity band says "Signed in" and shows the email instead of a name. "Delete account" is the only red item, which is correct. |
| S1 | `ProfileListsPreview` | inside Profile | `fixture/profile-lists-preview-390.png`, `fixture/profile-lists-preview-failed-390.png` | **good.** "Watching & reading 8" shows 5 covers (the preview limit), which is consistent. The failure line is honest: "Covers couldn't load. The counts are current." |
| S1a | Streaming service picker | Profile, `streaming_availability_v1` (0%) | not captured: flag off | — |
| S1b | Import result / freshness / history | inside Profile | not captured: needs an import | — |
| S1c | Clubs in a sheet | Profile → Your clubs | same view as P6 | — |
| — | Data sources and credits | Profile → About | `fixture/data-sources-390.png` | **good.** Hairline rows, an underlined link per source, the music note and the non-affiliation line. The close button floats without a header bar. |
| S2 | Search: idle | header magnifier | `fixture/search-idle-390.png` | **good.** Field, scope words, refinements and "Type a title, or pick a refinement." The lower 70% is blank: no recent searches in the fixture. |
| S3 / S3a / S3b | Concierge sheet, AniList import, Why-this | Profile, `kuro://concierge` | not captured: Profile and Concierge need taps; `--kuro-start=concierge` was out of scope | — |
| S4 / S5 | Import chooser / workflow | Home invitation, Profile | not captured: would start an import flow | — |
| S6 | Home season overview | Home season chip | not captured: needs a tap and series data (empty live) | — |
| S7 / S7a | Detail: anime (legacy body) | `kuro://anime/21` | `app/A-detail-anime-21.png`, `app/B-detail-anime-21.png` | **good** (improved). The dock is now opaque with one capsule shape family: heart, Add to list, Verdict, play. The duplicate meta line is gone ("SCORE 7.9 · 2015 · TV · 22 EPS · FINISHED" once). The "ANIME" badge is still a dark filled pill on the banner, and the banner is a blurry crop at this size. |
| S7b | Detail: manga (legacy body) | `kuro://manga/30013` | `app/A-detail-manga-30013.png`, `app/B-detail-manga-30013.png` | **good.** Same dock, with the read button dropped and "No legal provider link is available yet." The small CJK native-title kicker above the English title is about 8 pt and grey, so it is hard to read. |
| S7c / S7d | Series detail shell (anime/manga) | World B detail with series data | `../snapshot-final/detail-*.png` (fixture) | not re-captured live: no series data exists live, so the live page falls back to the legacy body |
| S7e, S8–S13 | Unit chooser, episode/chapter lists, QuickVerdict, provider sheet, cast/credits/entity sheets, franchise path, next pick | taps inside detail | not captured: need taps; several would write (QuickVerdict) | — |
| S14 | AddToListSheet | Add to list | not captured: a tap that leads to a write | — |
| S15–S17 | Add to club rail, Club detail, Create/Join club | card menus, Clubs | not captured: the account has no clubs, and Create/Join write | — |
| S18 | Browse filters | Browse → Filters | not captured: needs a tap | — |
| S19 | Discover full sections | Discover → See all | not captured: needs a tap | — |

## Shared components

| Component | Screenshot | Verdict and issues |
|---|---|---|
| `KuroStateView` page layout, all 7 kinds | `fixture/shared-states-page-390.png` | **good.** Serif title, meta message, ink-rule Try again. Offline and failed both state whether earlier content is still shown. |
| `KuroStateView` inline, `KuroThemeSongRow`, `KuroReleaseLine` | `fixture/shared-states-inline-songs-releases-390.png` | **good.** Themes: "OP1 Kaikai Kitan / Eve · Ep. 1–13 · Listen", plus a spoiler row "Spoiler. Tap to show." with no Listen. Releases: confirmed "Ep. 7 · Tomorrow, 16:00", announced "Vol. 115 · November", estimated "Ch. 1197 · expected around Sun, Oct 18", each "via AniList". The certainty is carried by the wording, with no colour. |

## Top remaining visual issues

1. **Home medium title picture fill.** The art-filled "Anime" (and "Manga") lettering has no contrast floor and reads as mottled patches (`app/B-home.png`).
2. **Three advance-key styles.** Folio Index and anime Shelf use an outlined square, manga Shelf uses a filled black square, and the Home continue card uses an outlined square beside a stacked "Ep. 0/26". Pick one.
3. **Manga Shelf key placement.** The key and "Ch. N" row floats far below the cover title. With progress 0 the key stands alone (`fixture/folio-manga-shelf-*.png`).
4. **Taste blurbs** are taglines or lowercase source text ("let's break it down.", "vash the stampede…"), and the Plan buttons are misaligned (`app/A-taste.png`).
5. **Folio at 320.** The controls wrap to two rows and the next-release line breaks mid-date ("Wed, / Nov 4"). A row with an unknown total shows a bare numeral ("1").
6. **Short Collection lists leave the page about 70% blank** with no footer or hint (`app/A-collection.png`).
7. **Header chrome.** "KURO" sits on a grey blur blob, and filled grey icon circles sit beside a white section capsule (all `app/` shots).
8. **Clubs first-load skeleton.** Rounded outlined cards are off-language, and the skeleton was still showing 7 s into a cold launch (`app/A-clubs-loading-7s.png`).
9. **Browse.** The filter row runs into the right edge with no cue, and uneven title wraps misalign the grid meta lines (`app/A-browse.png`).
10. **Detail badge and kicker.** The dark filled "ANIME"/"MANGA" pill on the banner, and the tiny grey native-title kicker (`app/A-detail-*.png`).

Fixed since last night's pass (`../app/VISUAL_QA.md`):
- The detail dock no longer covers the synopsis and uses one shape family.
- The duplicate detail meta line is gone.
- Home no longer repeats "Nothing scheduled".
- `--kuro-start` is honoured in World B.
- Status strips now fade at the edge.
