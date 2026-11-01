# Kuro prototype-fidelity pass: design

Status: APPROVED by the owner on 2026-11-01 ("try and go for it"). Build in progress.

## 1. Intent

Make the native app look and behave like the approved browser prototype, and give every screen (including loading, error, offline and empty) a branded, animated, usable treatment.

The owner reviewed side-by-side captures of the prototype and the app (`docs/overnight-2026-11-01/gallery/prototype-vs-app/`). The verdict: the app does not follow the design he wanted. **When the prototype and the 9 October native adjustments disagree, the prototype wins** (owner, 2026-11-01). The reason given: the prototype's design results are better.

Success: a person who used the prototype opens the app and finds the same Home, the same detail pages and the same first-run experience, with real data. No screen looks generic or unfinished, including the moments when something is loading or broken.

## 2. Authority (which source wins)

1. Owner decisions in this conversation (2026-11-01): follow the prototype; every screen branded; loading and error states branded and animated.
2. **The prototype source** is the visual and behavioural spec:
   - Anime Home: `tools/design-directions/instrument.html?switch=poster` (states `scenario=busy|full|undated|quiet|new`).
   - Manga Home: same page with `&medium=manga`.
   - Detail pages: `&detail=anime-2` and `&detail=manga-0`; editorial structure and copy in `instrument-detail-data.js`.
   - Supporting files: `instrument.css`, `instrument.js`, `instrument-art-materials.js`, `manga-philosophies.css/.js`.
   - Served at `http://127.0.0.1:8803` (`python3 -m http.server 8803 --bind 127.0.0.1 --directory tools/design-directions`).
   - Reference captures: `docs/overnight-2026-11-01/gallery/prototype-vs-app/prototype-captures/`.
3. `docs/overnight-2026-11-01/understand/DESIGN_RULEBOOK.md` still governs whatever the prototype does not specify: accessibility, Dynamic Type, EN/DE copy, 44 pt targets, Reduce Motion, honest states, and the forbidden list. **The rulebook rules this design overrides:**
   - §15.1: the medium switch now uses the prototype's heavy sans uppercase.
   - §14.1: Anime scene cards get the prototype's dark artwork-material foot instead of the white foot; "Coming up" becomes the prototype's card.
   - §15.6: Manga Home gets the prototype's per-book leaves (cover, title, then a "Ch. N" + key row).
   - §14.1 empty invitation: replaced by the prototype's new-account Home, with the additions in §5.3.
   - Any rule that the selected prototype is "geometry only, never palette": the prototype's component palette (keys, rails, material feet) now applies. See §3 for the page canvas.

## 3. Lead calls (reversible; flagged for the owner)

- **Prototype palette returns (owner, 2026-11-01, reversing the 8 Oct neutral call):** Home Poster canvas `#fffef8`, detail paper `#f5f5f4`, and the prototype's component tints (rails, keys, manga panels). Kept as tokens.
- **Every detail page and scene is tinted by its own artwork (owner, 2026-11-01).** Port the prototype's `art-hue-v1` algorithm (`tools/design-directions/build_art_materials.py`) to Swift, running on device:
  - downsample the artwork (banner 104×32, poster ≤64×96)
  - build a 24-bin hue histogram over pixels with value .12–.94 and saturation ≥ .12, weighted s·(1−|v−.55|)
  - `base` = HLS(hue, .24, .20), darkened until white text reaches ≥ 7:1
  - `deep` = base mixed 50% with #0f1212; `wash` = base mixed 92% with #fafaf5; `edge` = 72%; ink white
  - Cached per image URL (memory + disk). AniList `cover_image_color` gives an instant first paint, and the computed material replaces it with a short crossfade.
  - The detail sheet paper uses `wash`. The hero band, song panel, raised keys on art and Home scene feet use `base`/`deep`. Borders use `edge`.
  - No per-title override table ships. The prototype's three manual overrides were for its sample art only.
- **Typography follows the prototype:**
  - UI and titles use the system sans (SF Pro) at the prototype's sizes, weights and tight negative tracking (for example scene title 17 pt, −0.35; the medium words heavy, roughly −3.8 tracking at display size).
  - Editorial headings that the prototype sets in serif ("Coming up.", "Sunday Club", "Between us.", "The sound of it.") use the system serif (New York) as the native stand-in for Georgia.
  - The bundled Bodoni Moda ("Kuro Editorial") is **not** introduced: the selected Poster direction does not use it.
- **Artwork material colour** (scene feet, song panel, keys on art): AniList's `cover_image_color`, already decoded in the app, clamped for white text contrast (≥ 4.5:1). The prototype's hand-tuned overrides (`instrument-art-materials.js`) stay prototype-only; no title-to-colour table is shipped.
- **Seasons** come from the existing franchise/ladder data (`get_media_ladder`, `media_franchise_components`), not the empty series tables. Season tiles use real artwork where it exists; otherwise a numbered tile in the prototype's style.

### 3b. Owner answers (2026-11-01)

- **Detail actions are kept.** Favourite, Verdict and List settings (status, score, notes, remove) fold into the hero status mark: tapping "Watching" opens List settings, and its menu holds Favourite and Verdict. The watch/read provider sheet is reached from the same area. Nothing live users have today is removed.
- **Prototype tints and paper come back** (§3).

### 3a. Lead calls from the builder check

- **What one detail page is.**
  - A detail page is one catalogue entry (one AniList season or one manga), as it is live.
  - Season tiles open that season's own detail (a sibling route); they never write progress.
  - The progress row, +1 and Add always act on the entry that is open.
  - **Season numbering:** TV/ONA entries in prequel→sequel ladder order are "Season N". Films, OVAs and specials appear as "Also in this story" tiles, unnumbered. Split-cour parts keep their own label ("Part 2").
  - Home's "SEASON N" tab and "S2" stamps use the same ladder computation. They are omitted when the ladder is unknown, so no invented labels.
- **The new detail replaces both** the legacy body and `SeriesAnimeDetailView`/`SeriesMangaDetailView`. `series_detail_bundle_v1` is read opportunistically when the series flags are on and it has data.
- **Header:** one header on every pager page in the prototype's style.
  - Left: the `KURO` wordmark.
  - Centre: the page name in the prototype's small sans.
  - Right: the existing Search and Profile controls as quiet ink glyphs.
  - Page dots stay, smaller, under the page name.
  - Home additionally shows the prototype's "‹ Taste" neighbour link.
- **Type ramp:** the shared roles change globally so every screen speaks the prototype's language.
  - `kuroHero/Display/Headline/Title` become the prototype's heavy, tightly tracked sans.
  - A new `kuroEditorial` serif role covers the editorial headings ("Coming up.", "Between us.", "Your bookmark", club names).
  - Snapshot references are re-rendered.
- **Taste page is in scope:** the prototype's "FOR YOUR TASTE · Another world." / "Another chapter." view with story cards, plus the new-account "A first favourite.".
- **Home club room:** shows the club with the most recent real activity, with "+N other clubs ›" when there are more. Any extra club reads go through the existing ClubsStore paths.

## 4. Constraints (same as the overnight pass)

- **No live writes:** no migration apply, no function deploy, no flag/cron/secret change, no push, no TestFlight. Backend additions, if any, are prepared files only, and the app silently falls back without them.
- **Simulator:** the owned simulator `7FC4B58A-430C-457D-A017-6B0095723F3F` only, by UUID; never erase it; read-only use of the dev account.
- **Library** (`LibraryStore` via `LibraryActions` / the existing advance paths) stays the only tracking authority. Account isolation, club permission checks, guarded Undo and import recovery stay intact.
- **Both flag worlds work** (live: flags off; target: series flags on). The new Home and detail are visible to live users only where they do not depend on the flags. The Home page itself remains behind `series_home_native_v1` (unchanged decision); the detail pages become the one detail for everybody.
- **No fabricated data:** a section without real data is hidden, never filled with sample copy. The prototype's editorial hooks ("Old friendships. A city on the edge.") come from `detail_copy` when it has rows; until then the page opens with the synopsis (§5.2).
- **Every string ships in English and German** via `KuroLocale`.
- **Verification:**
  - Release build and full `KuroTests` on the owned UUID.
  - Architecture, secrets, migrations and docs gates.
  - Side-by-side screenshots against the prototype for every screen and state.
  - Adversarial review before reporting.
- **Licensing (D11):** nothing new is scheduled.

## 5. Screens

### 5.1 Home (anime and manga)

Compose exactly the prototype's Poster Home, top to bottom:

1. **Header:** `KURO` wordmark, page location ("Home"), "‹ Taste".
2. **Medium switch:** heavy sans uppercase ANIME / MANGA. The selected word is filled with the current title's artwork and has a short ink underline. The other word is solid muted ink.
3. **"Coming up" glance card:** caption ("Today · 3 releases"), up to 3 artwork thumbnails, a count with "this week" (or "6 weeks" or "pending"), and ↓, which scrolls to the calendar. Hidden for a new account. Fed by the ReleasesStore schedule with the honest coverage states from the overnight work.
4. **Opening line:** "NOW WATCHING" / "NOW READING" kicker, then a right-aligned headline: "2 new episodes", "Keep watching.", or "Nothing new today. Stay at your own pace." for a caught-up account.
5. **Anime: scene cards** (first two active titles):
   - shallow artwork window with the white season tab ("SEASON 2")
   - **dark artwork-material foot**: white bold sans title, "Ep. 4 / 5" counter with the progress scrub underline, and a raised light key (+)
   - footer row with one honest fact: "New episode available", club members "Mina + Jules ›", or nothing.
6. **Anime: "Also watching"** in a 2-column grid. Each entry has a poster thumbnail with "S2" stamp, title, "Ep. N", and a dark raised key.
7. **Manga: "Now reading" leaves** in 3 columns. Each leaf is the equal cover, title, then a row with "Ch. N" and a dark key. "4 new chapters" headline.
8. **"Coming up." calendar card:**
   - Day groups with a date chip ("2 OCT"), "Today / Tomorrow / Fri 9 Oct", and a release count. The first group is expanded and shows rows with poster, title, unit and time (anime) or "Chapter release" / "English edition" (manga).
   - Then "Dates to come · N announcements".
   - Certainty wording from the overnight release model.
9. **Club room:** dark "Your private club · Sunday Club" card with member avatars, the latest note quoted on a light card with "Finished Death Note ›", a spoiler disclosure ("Mina's thought on the ending ⌄"), activity rows ("Jules started Attack on Titan ›"), and the footer "Shared stories. Your people. · 2 updates". **Only real clubs and real notes**; the room is hidden when the user has none.
10. **Page footer:** "Your pace. Your place." · KURO.

All interactions from the prototype carry over:
- +1 stamps with the `confirm` / `count` animations, and Undo restores with `restore`.
- Tapping a scene or cover opens detail; the card and the key are separate targets.
- The season tab opens the season overview.
- The calendar day toggles open and closed.
- The coming-up card scrolls to the calendar.

### 5.2 Detail (anime and manga): one page for everyone

The prototype's section order. Each section lists its data source and its empty rule.

| # | Section (anime / manga) | Data | Empty rule |
|---|---|---|---|
| 1 | **Hero**: wide artwork (anime) or cover beside the title (manga); kind kicker; title on an artwork-material band; status mark ("Watching" / "Reading" / "Not in your list") | catalog | always present |
| 2 | **Story**: headline hook, premise, "About this season / About this story +" expanding the synopsis | `detail_copy` hook when present, otherwise the synopsis opens the section | the synopsis is always present |
| 3 | **Club presence**: avatars + "3 people in your clubs ↓", expanding to who is watching | social/club activity | hidden when 0 |
| 4 | **Seasons** (anime): tiles with artwork, current marked; inspecting never changes progress | ladder/franchise | hidden when only one entry |
| 5 | **Progress**: "Season 2 progress · Ep. 6 / 9" with the scrub line (anime); "Your bookmark · Ch. 24 / 25" folio card (manga) | Library | "Not in your list" + Add when untracked |
| 6 | **Episodes / Chapters**: "Up next · Episode 7 +" raised row, then recent units ("06 Episode 6 · Completed", "08 Episode 8 · Tap for details"), "More episodes ↓" | episodes table; manga chapters only where real | manga: hidden while chapters are placeholders |
| 7 | **The original story** (anime) / **Seen the anime?** (manga): 原作 / 映 card, title, author, "Explore the manga →", "Where this season meets the manga +" | ladder/relations; adaptation coverage | coverage row hidden while empty |
| 8 | **The sound of it.**: material-coloured panel of OP/ED rows with Listen ↗ | `media_themes_v1` (prepared) | hidden until data |
| 9 | **The characters.**: portraits, "Tap to meet" | credits | hidden when none |
| 10 | **Behind the frames. / Behind the pages.**: original work, director, animation studio / story & art, publisher; "Read with the publisher ↗" | credits, studios, external links | rows without data are omitted |
| 11 | **Between us.**: club card with artwork, avatars, "Who's watching ⌄", member notes with spoiler reveal, "Leave a thought" | social activity | hidden outside clubs |

- **Navigation:** the close control and back behave like today's sheet.
- **Watch/read links:** keep the overnight provider sheet, opened from the hero status area.
- **Removed:** the legacy body (genre pills, the bottom dock).

### 5.3 First time / empty (every page)

- **Home, new account:**
  - The prototype's new-account Home: switch, "YOUR COLLECTION" + "Begin here.", "+ Your stories belong here. / Import your list to bring your place with you.", "Import" and "Explore Taste ←".
  - **Added:** "A first favourite." with 3–4 starter cards from the prototype's Taste new-account view (story card + one-tap Plan). The picks come from the existing Taste/Discover reads, never invented.
- **Taste, new account:** the prototype's "A first favourite." story cards.
- **Collection empty:** the same invitation language (title, one line, Import / Find); never a blank page.
- **Clubs empty:** the "Watch together. Private by design." invitation restyled to the prototype's club room, with Create and Join.
- **Profile, new account:** no zero tiles; the library line reads "Nothing saved yet", followed by Import and Find.
- **Search with no history:** refinements plus "Start with a title you love."
- **Detail, untracked:** "Not in your list" with Add (status choice) in place of progress.

### 5.4 Branded states: loading, error, offline (new shared system)

The prototype only shows `confirm` / `count` / `restore` motions. These states are an **extrapolation**, built from its materials.

- **Loading, in place:** skeletons shaped like the real component (scene card with material foot, cover leaf, calendar day, detail sections) on `kuroCanvasQuiet`. A slow ink "scrub" line, the prototype's progress underline, travels once every 1.6 s.
- **Loading, page level:** the KURO wordmark with the letters settling in sequence, plus the travelling scrub line. Used for launch/bootstrap and first page loads.
- **Error:** one ink stroke draws the mountain ridge from `KuroZenMountains` once, about 1.2 s. Then a serif headline naming what happened ("Couldn't load your clubs."), one plain sentence, and an ink-rule "Try again →".
- **Offline:** the same stroke, held still, with "You're offline. Showing what you saw last." when content exists. Without content: "Connect to load this."
- **Empty:** the "+" mark from the prototype plus serif headline, used consistently.
- **All motion:**
  - Reduce Motion and Low Power show the composed final frame.
  - No motion loops beyond 2 cycles, except loading, which stops the moment content arrives.
  - Motion stops offscreen, is never on a timer that fires network requests, and uses the prototype's timings: contact 120 ms, settle 220 ms, medium 320 ms, ease `cubic-bezier(.2,.8,.25,1)`.
- One component family (`KuroLoadingView`, `KuroErrorView`, `KuroEmptyView`, `KuroSkeleton`) replaces ad-hoc spinners and the overnight `KuroStateView` copy-only states. A grep gate fails on stray `ProgressView()` outside these components.

### 5.5 Other screens: same language, lighter touch

Discover, Search, Clubs list/detail, Profile, Lists (Folio), Browse, Taste, Auth form and onboarding adopt the prototype's type ramp, key styles (raised light/dark keys) and branded states. The approved welcome stays frozen. Onboarding keeps its three frames, restyled to the prototype type.

## 6. Build approach

The same mechanics that worked overnight:

1. **Prototype extraction.** Capture every state at 390 (and 320/430) with Playwright into `docs/prototype-fidelity/reference/`. Write `PROTOTYPE_SPEC.md`: tokens (type ramp, colours, keys, radii, shadows, motion), component anatomy with measurements, and copy (EN, plus DE drafts).
2. **Foundation (serial):**
   - prototype tokens and type ramp in `KuroDesignSystem`
   - keys, the material-foot helper and the `confirm`/`count`/`restore` animations
   - the branded state family (§5.4) and the artwork-material colour clamp
   - shared header and medium switch
3. **Parallel lanes in git worktrees,** exclusive file ownership, two independent reviewers each:
   - Home anime
   - Home manga, calendar and club room
   - Detail anime
   - Detail manga
   - First-run and empty states across pages
   - Remaining screens restyle
   - Data, only if needed: a prepared detail bundle RPC as an optional speed-up; the client must work with today's reads
4. **Integration:** merge, Release build, full tests, gates.
5. **Fidelity review:**
   - Per screen, a side-by-side sheet (prototype vs native at 390, same state).
   - A reviewer lists every visible difference; each is either fixed or justified (data honesty, accessibility).
   - Plus the adversarial code review and a simulator pass in both flag worlds.
6. **Docs, memory, report, gallery.**

## 7. Acceptance

- For every prototype state (Home busy/full/undated/quiet/new × anime/manga; both details; new-account Taste), the native screen matches composition, hierarchy, component styles and copy. Remaining differences are listed with a reason.
- Every screen has branded loading, error/offline and empty states. No bare spinner or system-style empty text remains.
- Tests green, Release builds, both flag worlds work, no live writes.
- Visual acceptance is the owner's; screenshots are delivered as a gallery.

## 8. Left to the builder

Exact SwiftUI decomposition, file names inside each lane, skeleton geometry details, and the German copy wording (natural, matching the existing tone).
