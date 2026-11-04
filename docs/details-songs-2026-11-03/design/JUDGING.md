# Judging: three directions for details, songs and platform (2026-11-03)

**Judge:** the design lead lane.

**Inputs:**
- The three candidate mockups:
  - `archive.html`: "The title page as a beautifully indexed archive."
  - `companion.html`: "The title page is your watch companion."
  - `cinematic.html`: "The title page as a poster that unfolds."
- `docs/discover-clubs-2026-11-03/understand/HOME_GRAMMAR.md`
- `docs/prototype-fidelity/PROTOTYPE_SPEC.md` §4 (detail D1–D11) and `LANE_AMENDMENTS.md`
- Last night's spec, `docs/superpowers/specs/2026-11-03-discover-clubs-redesign-design.md`
- The code on `kuro/discover-clubs-redesign` (`a59a5e4`)
- The two foundation lanes as they stood at judging time:
  - `kuro/details-songs-platform-data` (`d6e7739` plus working tree)
  - `kuro/details-songs-platform-platform` (`d390caa` plus working tree)

**Outputs:**
- The binding spec: `docs/superpowers/specs/2026-11-03-details-songs-platform-design.md`
- The final mockup: `final.html`, forked from `companion.html` with the grafts applied

## How the mockups were judged

**Rendering.** Each file was rendered with headless Chrome on a private profile (not the shared browser), 1600 px wide, then cropped into tiles at 2/3 scale. Everything rendered:
- **Companion** uses live Kuro Storage covers and real Apple artwork.
- **Cinematic** uses AniList, Crunchyroll and mzstatic URLs.
- **Archive** uses the prototype's committed assets.

**Text.** Each page's rationale, captions, notes, copy tables and open items were read in full (tags stripped).

**Code checks.** Every claim that decides feasibility was checked against the code:

| Claim | Checked against |
|---|---|
| Prototype section order | `DetailSectionPolicy` |
| The D1 hero's measured 150.6 pt artwork | PS§4 |
| `LibraryEntry` fields | `Packages/KuroModules/Sources/KuroLibrary/LibraryValues.swift`: only `createdAt` / `updatedAt`, no finish date |
| `Episode` fields | `CatalogDetailModels.swift`: thumbnail, title, airDate, duration |
| `ThemeSong` fields | `ReleaseModels.swift`: no Apple fields yet |
| The live similarity RPC | `RecommendationsReader.fetchSimilarIdsViaRPC` |
| `TastePlanKey` variants | `TastePicksView.swift:1455` |
| The import button literal | `ConciergeView+AniListImport.swift:267`: upper case |
| `DetailCharactersRail.shown` | drops BACKGROUND |
| `ReminderScheduler` | asks for permission from the Library sink |
| The platform lane's widget model | `AdvanceProgressIntent` queues only; `LibraryActions.advanceQueuedProgress` applies |
| The data lane's voice readers | `CatalogStore+Voices.swift` |

**Discover length.** The committed `docs/discover-clubs-2026-11-03/after/discover-all-full-390.jpg` was measured, and its content ends at about **1,641 pt** with the fold closed. Archive's annex reported the same figure. It is recorded in spec D17.

## The four criteria

| Criterion | Weight | What it measures |
|---|---|---|
| Consistency with Home and the new Discover/Clubs | 40% | Is every block one of Home's shapes (scene card, glance, quiet row, cover line, keys, eyebrow, headings)? Is the prototype order and measure kept? Does the page avoid inventing new component families? |
| Clarity | 25% | Can a reader tell where they are, what is next and how sure the date is? Is every tap's target obvious? Are there two targets where two are needed? Is the VoiceOver order sane? |
| Delight without noise | 20% | Does the page have a point of view? Is anything there only for decoration? |
| Feasibility | 15% | Is it buildable tonight on the existing and prepared data? Is it honest about what the data cannot say? Does it fit the foundation lanes' actual interfaces? |

## Scores (0–10 per criterion; total weighted, out of 10)

| Direction | Home (40%) | Clarity (25%) | Delight (20%) | Feasibility (15%) | **Total** |
|---|---|---|---|---|---|
| **Companion** | 8.5 | 8.5 | 7.5 | 7.5 | **8.15** |
| Archive | 8.0 | 8.5 | 7.0 | 7.5 | 7.85 |
| Cinematic | 7.0 | 8.0 | 9.0 | 7.0 | 7.65 |

**Winner: Companion.** It takes Archive's hero and order rule, and Cinematic's data findings, match rule and several states.

### Companion: 8.15

**Home consistency (8.5)**

Nearly every block is a Home or Discover shape:
- the coming-up glance for "Coming up"
- the scene readout and material key for progress
- `TastePlanKey` (leaf face) for More like this, which is Discover's plan grammar (DC D5)
- Home quiet rows for staff roles
- Home's cover line with the 46 × 2 rule for the studio name
- glance cards for "Japanese voice" and "In your list"
- initials discs instead of stock faces
- the Home eyebrow (9 / 1.05) everywhere
- Home paper and material keys on the widgets

Why it loses points:
- **It reorders the prototype page.** "Your place leads" puts progress and Coming up above the story, but `DetailSectionPolicy` and PS§4 fix story before progress. The spec keeps the prototype order and moves Coming up into the hero (graft from Archive).
- **"The facts." grid duplicates the hero's fact line.** It is dropped.
- **The songs panel adds a "Season 1 · Season 2" word switch.** A season is its own title page, so the switch is dropped.

**Clarity (8.5)**
- The page answers "where am I, what's next" at once.
- The timeline nodes (filled ✓ / material ring / open / dashed) are readable at a glance.
- The two-target cast row is explicit, including its VoiceOver order: character, then voice.
- The certainty is labelled: CONFIRMED · VIA ANILIST, and ESTIMATE · WEEKLY RHYTHM.

What costs it:
- **The notification body says "You're on Ep. 7"**, a progress claim that can be stale by the time it fires. It is dropped.
- **The import screen replaces Form / Preview with a Read → Review → Confirm thread.** That changes the control's meaning. The spec keeps the binding and uses refine words (graft from Archive).

**Delight (7.5)**
- The companion idea is a real point of view.
- "Characters you know." and "In your list" lines make the person pages personal without inventing anything.

What costs it:
- The songs are an ordinary list. They are good, but quiet.

**Feasibility (7.5)**
- Nearly everything maps to existing or prepared data.

Two problems:
- **"Your 2026 so far: 412 episodes. 9 series finished" cannot be computed.** There is no finish date, and no episode dates. The spec uses Cinematic's honest "saved or changed in 2026" with the note.
- **Its widget note says the app snapshot is "re-read after the write"**, which is close to the platform lane's model. The spec states the platform's model exactly: queue → app drain → `isQueued`.

### Archive: 7.85

**Home consistency (8.0)**
- **Its hero is the best of the three.** It keeps the prototype D1 window and turns the heading block into Home's scene card, with a scene-fact line (10 pt `footFact`) and the next release on the material with the bell. This is grafted as spec D3.
- **It keeps the prototype section order.**
- **Its entity pages use Home's opening row, quiet rows and Discover's refine row**, which retires the black pills.

What costs it:
- **Its signature habit, the mono index numeral on every ordered list, is new to Kuro.** That includes the "01 The record." section numbers. The direction itself calls it "one extra habit". It is noise on a detail page, and the section numbers fight the prototype headings.
- **The year-axis season map is a new component family**, alongside the existing D4 season tiles.
- **"The record." ledger repeats the hero's facts.**

**Clarity (8.5)**
- **Its certainty typesetting is the clearest:** solid stamps for Confirmed and Announced, a dashed stamp for Estimate, "Date to come" with neither. This is grafted as spec §5.3.
- **Its two-sided cast index has explicit 44 pt halves.**
- **Its annex measures Discover's length from the committed render.**

**Delight (7.0)**
- It is elegant but clerical. The numerals and ledgers make the title page read like a catalogue card, rather than a story you are inside.

**Feasibility (7.5)**
- **It is honest:** "Your year" is hidden without dated events, and the voice-actor rows are hidden until the data lands.
- **The map depends on ladder years** for every station.
- **The "announced day, notify at 10:00" proposal is left open.** The spec decides against it (D14).

### Cinematic: 7.65

**Home consistency (7.0)**
- **It replaces the measured D1 hero (150.6 pt) with a 428 pt poster window.**
- **It introduces three new families:** a perforated ticket, record sleeves that slide out, and a persistent mini-player.
- Each is well made, but the prototype is the authority for the detail page, and none of these is a Home shape.

What it gets right:
- the season tabs on the art
- the facts strip in readout language
- Home leaves on the studio page

**Clarity (8.0)**
- The voice chip as its own labelled 44 pt target under the portrait is the cleanest cast interaction. It is grafted as spec D8.
- The facts strip is legible.

What costs it:
- The mini-player adds a second place to control playback.

**Delight (9.0)**
- It has the most character: the poster, the record shelf, the record sliding out while it plays.
- Its real edge cases make the page feel alive:
  - "99" by MOB CHOIR has only covers in Apple's catalogue
  - "Refrain Boy" has no artist in AnimeThemes
  - Mob Psycho's spoiler endings stay wrapped

**Feasibility (7.0)**
- **The best research of the three.** Real AniList, AnimeThemes and iTunes data, and four genuine data findings, all recorded in spec §17:
  - Episode stills attached to the wrong season: JJK S2 (145064) carries Season 1's list, and Apothecary S1 (161645) carries Season 2's absolute-numbered list. This became `EpisodeStillPolicy` (D20).
  - No stills for any Fall 2026 title. The branded tile is therefore the common case.
  - The alias case: "Ao no Sumika" vs "Where Our Blue Is".
  - Artists missing from AnimeThemes.
- **Its match-rule table (cover, live, TV size) became D12.**
- **Its "Your year" is honest** (saved or changed), and was grafted as D15.

What costs it:
- **Its widget note 18 describes the intent running in the app process with the shared owners.** That is not what the platform lane built (the extension queues, the app drains).
- **The 428 pt hero, sleeve motion and mini-player add build risk** for one night.

## Grafts into the spec (what came from where)

| Spec | Taken from | What |
|---|---|---|
| D1, base | Companion | glance cards, quiet rows, `TastePlanKey`, cover line, initials discs, two-target cast, entity "In your list", Profile numbers, widget paper, import calendar-card shell and check rows |
| D2, D3 | Archive | the prototype order kept; the hero as Home's scene card (fact line plus next-release fact row with bell, on the material) |
| §5.3 | Archive | solid vs dashed certainty marks; "Date to come" with neither |
| D10 | Archive (liner notes), corrected | grouping by part from episode ranges; no invented arc names |
| §13 | Archive | Form / Preview becomes refine words (same binding), not a new thread |
| D8 | Cinematic | the voice chip as its own target; BACKGROUND characters shown when nothing else exists |
| D9 | Cinematic + Companion | one branded tile (Companion's paper stripes, Cinematic's ink tile for people and studios) |
| D12, §17 | Cinematic | the strict match rule (covers, live, karaoke rejected; TV size loses ties); aliases open; "Artist not listed" |
| D20 | Cinematic | the wrong-season still guard and the "No. 25" quiet absolute number |
| §6.4 | Cinematic | watched runs fold into one line |
| §8.3 | Cinematic | Apple artwork never fetched for a veiled song |
| D15 | Cinematic | "Your year" = saved or changed, with the honest note |
| §11.3 | Cinematic (wording), corrected | "Episode 6 just aired.": factual, no "in Japan", no progress claim |
| §9.3 | Companion | the studio name as Home's cover line, no logo |
| §12.3 | Companion + Cinematic | glance-card totals, scrub genre bars, the year as a small scene card in the most-time title's material |

## Not taken (and why)

| Not taken | Why |
|---|---|
| Cinematic's 428 pt poster, perforated ticket, record sleeves and mini-player | They are not Home shapes, they replace the measured D1, and one preview control is enough |
| Archive's index numerals, section numbers and year-axis season map | They are a new habit and a new component family, and D4 tiles already switch seasons |
| Companion's "The facts." grid, the songs season switch, "your place first" reorder, "9 series finished" and "You're on Ep. 7" | Duplicates, a broken prototype order, and claims the data cannot support |
| Archive's "announced day notifies at 10:00" | The spec decides that only times notify (D14) |
| Sentence-case import button (all three, or proposed) | It changes a copy literal. Kept upper case and recorded as an owner choice |

## Rulings the mockups left open (decided in the spec)

| Open in the mockups | Ruling | Spec |
|---|---|---|
| Song aliases | Strict tonight, recorded as open | D12, §17 |
| Import button case | Keep the literal | D16 |
| Announced day | No notification | D14 |
| The 1 h-before reminder | Retired | D14 |
| Widget +1 mechanism | The platform lane's queue → drain model, shown as "Saved when Kuro opens" | D13 |
| Discover length | Already 1,641 pt; the lead decision applied anyway | D17 |
| VoiceOver | Rules by construction (§14.3); the device pass stays open | D19 |
| Cast rail that would be empty with only BACKGROUND characters | Show them | D8 |
