# Judging: three Discover + Clubs directions (2026-11-03)

**Judge:** design lead lane.
**Inputs:**
- `editorial.html` ("Discover is an issue. Clubs are rooms.")
- `calm.html` ("Calm density.")
- `personal.html` ("For you first. Your people, right now.")
- `../understand/HOME_GRAMMAR.md`
- `../understand/DISCOVER_CLUBS_AUDIT.md` (P1–P16)
- The code on `kuro/discover-clubs-redesign` (da47def, main = ff8059d)

**Outputs:**
- the binding spec, `docs/superpowers/specs/2026-11-03-discover-clubs-redesign-design.md`
- the final mockup, `final.html`

## How the mockups were judged

- **Rendering.** Each mockup was rendered in headless Chrome over CDP on a private port and profile (not the shared Playwright browser), at 1600 px wide and full height. Rows were then cropped at full resolution.
  - editorial: 45/45 images loaded.
  - calm: 77/77 images loaded.
  - personal: 31/48 images loaded. The 17 that failed are its remote "Kuro storage URL" fallbacks, which a sandboxed file render can't reach; one example is the empty "Chainsaw Man" cover. This is a problem with how the mockup was built, not with the design, and the score below ignores it.
- **Text.** Each page's written rationale, component map, copy table and breakpoints were read in full, from `document.body.innerText`.
- **Code checks.** Every claim that decides feasibility was checked against the code. Each verdict below cites the file it came from.

## The four criteria

| Criterion | Weight | What it measures |
|---|---|---|
| Consistency with Home | 40% | Canvas, type ramp, palette, artwork materials, keys, medium switch, headings, motion, branded states. Does tapping between Home, Discover and Clubs feel like one app? |
| Clarity / usability | 25% | Can a reader see what is there, how many, and where each tap goes? Navigation contract (N1–N11, H1–H3). Accessibility. |
| Delight without noise | 20% | Does the page have a point of view and a rhythm? Is anything there just for decoration? |
| Feasibility | 15% | Uses only fields that are already loaded and components that exist. No backend change, no flag change. Lanes can build it overnight. |

## Scores (0–10 per criterion; total = weighted, out of 10)

| Direction | Home (40%) | Clarity (25%) | Delight (20%) | Feasibility (15%) | **Total** |
|---|---|---|---|---|---|
| **Editorial** | 9.0 | 8.0 | 9.0 | 7.0 | **8.45** |
| Calm | 8.5 | 8.5 | 6.5 | 9.0 | 8.18 |
| Personal-first | 7.0 | 7.0 | 7.5 | 6.5 | 7.03 |

**Winner: Editorial.** It grafts in Calm's feasibility fixes and a few ideas from Personal-first.

### Editorial: 8.45

**Home consistency (9.0)**
- It is the only direction where every Discover block is one of Home's own component shapes:
  - the opening row
  - a cover story, which is the scene-card anatomy on the title's material foot
  - Home's coming-up glance card for Airing today
  - Home's 24 pt headings with a 10 pt summary
  - the quiet-row recipe for the index
  - Home's footer
- Clubs use Home's room on all three surfaces: the list, the empty page and the club hero. That solves P4 in the most literal way: the club the reader taps on Home lands on a page that is visibly the same club.
- Club tabs and sub-headings use the switch's 28 × 2 rule and Home's 15 pt heading.
- Why it loses one point: the Plan key is drawn as a `KuroAdvanceKey` "+" face. That is Home's +1 progress key, not its plan grammar. Home and Taste already plan with `TastePlanKey` (`TastePicksView.swift:1455`), so the final spec uses that instead.

**Clarity (8.0)**
- Section sizes drop from 8–10 items to 3–5, and the page from about 3,400 pt to about 1,900 pt.
- "Browse the catalogue" moves into the first screen and a half.
- The club keys are labelled.
- "This week" does what its name says.
- Deductions:
  - The "In this issue" contents line risks reading as a second navigation layer.
  - The "Mina's note ›" link scrolls back up the page, which is surprising (fixed in the final).
  - The 11 pt rail filter is small, though it still has a 44 pt target.

**Delight (9.0)**
- The "issue" framing gives the page a point of view: today's issue, "Edited for you.", a cover story and a contents line.
- The three-word art-filled switch is the boldest moment in any of the three directions, and it is still Home's grammar.
- Each section takes a different form (feature, then three covers, an index, one rail), so the page has rhythm, and nothing is there as decoration.

**Feasibility (7.0): three real defects, all fixable without changing the design**
1. The Invite key is shown to every member. The bundle returns `invite_code` only to owners and admins: `CASE WHEN _my_membership.role IN ('owner','admin')` in every `fetch_club_bundle` version, up to `20261005150000_club_membership_lifecycle_and_privacy.sql:625`. For a member, Invite would be a dead tap (N9). Calm got this right.
2. The Plan key is `KuroAdvanceKey`. In the tracked state that key is `.caughtUp`: disabled, with the VoiceOver value "Caught up" (`KuroAdvanceKey.swift:105`). On Discover that value is wrong, and the disabled key is a dead tap.
   - Graft: `TastePlanKey` + `TastePlanController` (`TastePicksView.swift:638, 1455`). It plans and unplans with Undo, and a tracked title opens the tracking editor.
   - `TasteCard(anime:)` and `TasteCard(manga:)` already map Discover's bundle rows (`TastePicksView.swift:441, 449`).
3. The tab is renamed "Lists", but English uses "rail" everywhere else: "Create a rail", "No rails yet.", "In your club rails" (detail), the add-to-club sheet. German already says "Listen" throughout.
   - Renaming only the tab would split the vocabulary. Renaming everywhere is out of scope (DO-NOT #16).
   - The final keeps "Rails" in English, "Listen" in German.

Smaller points:
- The note card shows "6h ago", but rail notes have no timestamp (`ClubRailItem` has no `created_at` for the note).
- The note is "the latest", but `ClubRoomCopy.firstNote` takes the first note in rail order (`ClubViewLifecycle.swift:567`).
- The list room says "You + 4", but `member_names` on `ClubListRow` has no user ids. Home's room shows the first three names as they come (viewer included), so the list room does the same and says "5 members".
- The German copy for "Browse the catalogue" and "Airing today" doesn't match the shipped strings ("Den Katalog durchstöbern", "Läuft heute").

### Calm: 8.18

- **Home consistency (8.5).**
  - Good:
    - the same canvas, headings, opening row, scene-card lead, calendar card and room
    - the tab rule fades in place, which matches Home's switch
    - missing art uses `HomeInk.posterFill` instead of the cold #E6E6E6
  - Deductions:
    - The Trending filter is drawn as hairline capsules. Home has no capsule chips.
    - The clubs list draws one room and then quiet paper rows for the other clubs. That copies Home's "one room + N other clubs" structure, but it leaves the list with two club looks, and P4's diagnosis was that one club has too many looks.
- **Clarity (8.5).** This is its strongest criterion:
  - Airing today as calendar rows with stated times
  - a ranked Trending list
  - counts everywhere
  - a separate vote target and title target on poll options
  - `accessibilityElement(children: .combine)` plus explicit actions for the A4 activation problem
- **Delight (6.5).** It says so itself: "The direction adds no new visual idea." The page is calm and correct, but it would read as Home's leftovers rather than as Discover's own page.
- **Feasibility (9.0).** It is the most rigorous of the three:
  - It found the admin-only `invite_code`.
  - It found that `KuroPosterMediumSwitch` hard-codes two `MediaKind` words (`HomePagePicture.swift:175-176`).
  - It noted that `KuroAdvanceKey` is the +1 key.
  - It kept the English "Rails".
  - Its tap table and data table are complete.
  - It loses a point for proposing a new `KuroSaveKey` when `TastePlanKey` already exists.

### Personal-first: 7.03

- **Home consistency (7.0).**
  - It reuses Home components by name and draws the room well.
  - But "From your list today" at the top of Discover repeats Home's coming-up glance on the next page over. The two pages then compete, which is exactly what Home is for.
  - The club page leads with the "This week" tab, which changes the club's information order away from both Home's room and the current page.
- **Clarity (7.0).**
  - "In your clubs" adds a new personal section to an editorial page.
  - With the pick, the glance and "New to you", the top three blocks are all "you".
  - The curated catalogue starts below the fold, which weakens the rule that Discover is editorial-first.
- **Delight (7.5).** Each club room leading with the latest human line is warm, and the pace glance on This week is a good idea.
- **Feasibility (6.5).**
  - The friend-count dedupe for "In your clubs" is new logic.
  - The mockup's images don't load.
  - Its Invite key has the same admin-only gap as Editorial's.

## What the final takes from each direction

**From Editorial (the base):**
- the issue framing, opening row and three-word art-filled switch
- the cover story, Airing-today glance, contents line with Browse, and the feature-plus-three section
- the numbered index for Essentials, one Trending rail, and the fold
- rooms on all three club surfaces, the hero room, labelled keys and the This-week calendar card
- poll covers and deadlines

**From Calm:**
1. Invite is owner/admin only, because only they receive `invite_code`. A member sees "Add a title" only, and only when at least one unlocked rail exists.
2. English keeps "Rails"; German keeps "Listen". The tab is "Rails · This week · Polls".
3. The three-word switch is a new Discover-owned view, `DiscoverIssueSwitch`, that reuses `KuroArtWordFill` and the `HomeInk` switch tokens. `KuroPosterMediumSwitch` is not changed.
4. Missing art uses `HomeInk.posterFill`.
5. Poll options get separate vote and open targets.
6. Card rows use `.accessibilityElement(children: .combine)` plus explicit `.accessibilityAction`s (A4).
7. The join sheet gets the N7 discard guard.
8. The tab rule fades in place; it never travels.
9. An entry with a missing `updated_at` goes under "Earlier".

**From Personal-first:**
1. Planned and tracked titles on Discover carry a visible state ("Planned" / "On your list" on the key), not only a VoiceOver value.
2. The pace glance sits at the top of This week, in Home's glance card.

**New in the final (the judge's fixes):**
1. The Plan key is `TastePlanKey` / `TastePlanController`, the existing plan grammar from Taste and Home's new-account block. It has Undo, and a tracked title opens the editor, so there is no dead tap and no "Caught up" VoiceOver value.
2. Every note appears exactly once.
   - The first note in rail order (`ClubRoomCopy.firstNote`) is in the hero card.
   - Its tile says "Mina's note ↑" and scrolls to the hero card.
   - Every other note stays under its own tile as a spoiler-gated line.
   - There is no time on rail notes, because none is stored.
3. The list room's meta line is "5 members · 3 rails · 1 open poll". The member fills follow Home's room (the first three `member_names`). "You" appears only on the club page, where `members[].user_id` identifies the viewer.
4. Shipped German strings are copied exactly ("Den Katalog durchstöbern", "Läuft heute", "Tipp des Tages", "Alle ansehen").
