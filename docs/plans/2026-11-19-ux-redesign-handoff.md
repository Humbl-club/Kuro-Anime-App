# Handoff: Home, Discover and Clubs redesign (2026-11-19)

For the next agent working in this repo. Read root `AGENTS.md` and `CLAUDE.md` first; they
override personal defaults. This document is the brief; the owner's words below are the authority.

## 1. What the owner said (19 November 2026, after using TestFlight builds on their iPhone)

Close paraphrase, kept in the owner's terms:

- **Discover:** "the user experience on the Discover screen is still terrible, really terrible."
- **Home → You page:** everything sits under Plan to Watch. They added many Plan to Watch titles to
  their collection on the phone, "but it doesn't change the actual Home screen".
- **Clubs:** there is one club, and it is "also terrible". On the club/profile page they had open
  (the club the owner refers to as "JN L JN LN"; confirm the exact name with them), "the rails that
  are in there are terribly done."
- **What they like:** "the only things that I really, really like are the anime/manga detail parts.
  These are really, really nice." They want the app "to work more like that in terms of design."

**Still unanswered (ask this first):** *what* about the detail pages works for them: the look, how
much they show, how they feel to use, or something else. The answer is the design reference for all
three screens. Do not assume it.

## 2. What is already known

### Home: the cause of the "Plan to Watch doesn't change Home" complaint

Working as designed. The design does not suit the owner.

- `HomeShelfPolicy.showsNewAccount` ([Kuro/Views/Home/HomeShelfPolicy.swift](../../Kuro/Views/Home/HomeShelfPolicy.swift), around line 64)
  keeps the new-account block (`HomeNewAccount`: "Your stories belong here.", Import, "A first
  favourite.") while the account was latched as new **and every Library entry is a bare plan**
  (`onlyBarePlans` → `TastePlanAction.isBarePlan`: planned, no progress, rating, notes, dates).
- The latch (`TastePageCopy.latchNewAccount`) is decided once in `ContentView` when the Library first
  loads empty. So an account that starts empty and only adds Plan to Watch titles **never leaves the
  new-account block** until something is watching/reading or otherwise edited.
- Planned titles otherwise go to `HomeShelfPartition.planned` (`HomeShelfPolicy.partition`), which
  renders as "a quiet row that opens their page". Planned titles never get a scene, book or +1 key.
- Mounted owner: [Kuro/Views/Home/HomeView.swift](../../Kuro/Views/Home/HomeView.swift) (`showsNewAccount`, `newAccountShelf`,
  `partition` use around lines 232–520). Store: `Kuro/Home/HomeStore.swift` (`home_bundle_v1` pages).
- Tests that pin today's behaviour: `KuroTests/HomeShelfPolicyTests.swift`, `FirstRunLaneTests.swift`, `HomeAnimeLaneTests.swift` (search `showsNewAccount`, `onlyBarePlans`,
  `HomeShelfPolicy` in `KuroTests/`); a deliberate behaviour change updates them test-first.

### Discover, Clubs, detail pages: where things live (not yet analysed)

| Surface | Main files | Governing spec |
| --- | --- | --- |
| Discover | `Kuro/Views/EditorialDiscoverView.swift`, `Kuro/Views/Discover/*` (issue layout, cover story, feature trio, index rows, moods, preview, See all), `Kuro/Discovery/DiscoveryStore*.swift` | `docs/superpowers/specs/2026-11-04-discover-usability-design.md` (contract named in `AGENTS.md`), earlier `2026-11-03-discover-clubs-redesign-design.md` |
| Clubs | `Kuro/Views/ClubsView.swift`, `ClubDetailView.swift`, `ClubDetail*Components.swift`, `ClubRoomStyle.swift`, `Kuro/Views/Clubs/*` (`ClubRoomLayout`, `ClubRoomCard`, `ClubWeekCard`, `ClubRailChooserSheet`), Home's `HomeClubRoom.swift` | `docs/clubs-spec.md`, `2026-11-03-discover-clubs-redesign-design.md` |
| Profile | `Kuro/Views/ProfileView.swift`, `Kuro/Views/Profile/*` | none |
| Detail pages (the liked reference) | `Kuro/Views/DetailPages/Prototype/*` (`DetailPage`, `AnimeDetailSections`, `MangaDetailSections`, `DetailBetweenUs`, `DetailSectionPolicy`), `Kuro/Views/DetailPages/Detail/*` (`DetailHeroParts`, `DetailRails`, `DetailRailPeek`, `DetailEpisodeTimeline`) | `docs/modules/detail-pages.md`, `2026-11-03-details-songs-platform-design.md` |
| Shared building blocks | `Kuro/Design/KuroDesignSystem.swift` (tokens), `Kuro/Views/Shared/*` (`KuroRailPeek`, `KuroSectionHeader`, `KuroFold`, `KuroBrandedTile`, `KuroReadableWidth`) | `docs/superpowers/specs/2026-11-02-navigation-contract-design.md` |

Visual history: galleries under `docs/discover-clubs-2026-11-03/`, `docs/discover-usability-2026-11-04/`,
`docs/prototype-fidelity/`. Feature flags change what is mounted: inspect flags and mounted code
before describing a screen (the Discover contract in `AGENTS.md` says so explicitly).

## 3. Constraints that apply

- `AGENTS.md` UI contracts: design-system tokens, monochrome statuses, serif editorial / sans body,
  adaptive widths, red only for destructive actions, light appearance preserved, no `UIScreen.main`
  or hard-coded widths, typed routes and the pager tap gate, working back/close, accessible controls.
- The navigation contract and the Discover usability spec are current contracts. A redesign that
  breaks them updates the spec in the same change, with the owner's approval.
- Views call typed capability APIs, never the store/SDK directly. Library stays the tracking
  authority. Account-scoped state must not leak across accounts.
- No backend change is expected for a visual redesign. Anything that needs new SQL goes to
  `supabase/prepared-migrations/` and is not applied without authorization.
- Simulator: verified available iPhone 17 Pro only, never iPhone 16 Pro; do not seize another
  session's simulator (owned UUID `7FC4B58A-430C-457D-A017-6B0095723F3F` is for the lead's serial runs).
- After changes: update `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`,
  `IMPLEMENTATION_PLAN_Variation1.md`; run `bash scripts/quality-gates/check_docs_current_state.sh`.
- Commit with explicit pathspecs; never reset, stash or overwrite others' work.

## 4. Suggested way of working

1. **Ask the owner the open question in §1** before designing anything. One question at a time,
   in plain language.
2. Look at the three screens as the owner sees them: build `main` for an iPhone 17 Pro simulator,
   sign in with a test account that has only Plan to Watch titles, one club, and a mixed library;
   take screenshots of Home (You), Discover and the club page. Compare with a detail page.
3. Treat it as **three projects, one at a time: Home first** (opened most, with a concrete fault),
   then Discover, then Clubs/profile rails. Each gets a short design doc in
   `docs/superpowers/specs/2026-11-19-<screen>-redesign-design.md`, approved by the owner before code.
4. Show options as mockups or screenshots, not prose: the look is the owner's decision.
5. Build test-first; verify on the simulator with screenshots before claiming done; ship through a
   TestFlight build only when the owner asks.

## 5. Release items still open (separate from this redesign)

- Owner installs TestFlight 27 (uploaded 2026-11-19, tag `testflight-27`), then builds 20–25 are
  expired, then B8 (`20261112100401` → `20261112100500`); see
  `docs/plans/open-work-deploy-2026-11-18/RUNBOOK.md`.
- Catalogue cutover: comparator gates for identity/titles/facts still fail (season-label titles,
  series-level episode counts, too few accepted links); no field group may switch until its gate passes.
- W6 series-membership pilot (~10 reviewed series), guest browsing decision, App Group registration
  for the widget.

## 6. Prompt for the next agent

> You are picking up the Kuro UX redesign. Read `AGENTS.md`, `CLAUDE.md` and
> `docs/plans/2026-11-19-ux-redesign-handoff.md` in full. The owner finds Discover, Home's You page
> and Clubs (including the rails on the club page) poor, and likes the anime/manga detail pages; they
> want the app to feel more like those pages. Home's "Plan to Watch doesn't change Home" is caused by
> `HomeShelfPolicy.showsNewAccount` keeping the new-account block while every entry is a bare plan.
> Start by asking the owner, in one plain question, what about the detail pages works for them. Then
> screenshot the current screens on an iPhone 17 Pro simulator, and work one screen at a time
> (Home, then Discover, then Clubs): a short design doc per screen, approved by the owner, then
> test-first implementation verified with screenshots. Keep the navigation contract, the Discover
> usability spec and the design-system rules unless the owner approves changing them, and update
> those specs in the same change. No hosted changes, deployments or TestFlight uploads unless the
> owner asks. Record what you changed in the three state/plan docs and report exactly what was
> verified.
