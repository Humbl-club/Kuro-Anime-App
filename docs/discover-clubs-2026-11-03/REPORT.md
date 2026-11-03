# Discover + Clubs: morning report (3 November 2026)

Everything is local on branch kuro/discover-clubs-redesign, commit 4f1e2eb. Nothing was pushed or deployed, and no backend, feature flag or production data was touched. The before/after pictures are in docs/discover-clubs-2026-11-03/index.html, with the raw renders in before/ and after/.

## In plain English
You asked for Discover and Clubs to feel like the same app as the new Home. Both pages now use Home's warm paper, type, keys, section headings, switch, and loading and offline screens.

**Discover is a daily issue.** From the top:
- today's date line;
- an All · Anime · Manga switch, drawn like Home's;
- one cover story (today's pick) in the title's own artwork colour, with a Plan key;
- an "Airing today" card;
- a short "In this issue" contents line that jumps to each section;
- a few hand-picked sections in different shapes: a feature with three covers, a numbered list, and one sideways rail with a small filter;
- the rest, folded away.

It is still editorial: the rails are curated, and a section's filter only changes that one section.

**Clubs was improved, not rebuilt.**
- On the list, each club is a dark "room" showing its covers, members and latest activity.
- A club's own page opens on the same room. It has clear keys (Add a title, Start a rail, Invite, Ask) and Home-style tabs.

## Last night's review pass
Reviewers raised 16 issues. I checked each one against the code and the renders: 13 are fixed, 3 are partly fixed, and none was rejected.

**Discover looked shifted.** Every Discover screen sat about 6 pt left of centre, so paging Home → Discover → Clubs made the content jump sideways.
- The cause: the row of three covers under "New to you" had an invisible spacer that made it 14 pt wider than its column.
- Discover now sits on Home's exact 20 pt edge (16 pt on small phones).
- A new test fails if any section is ever wider than its column. I confirmed it fails on the old code.

**Discover's All page was too long.**
- On All, each numbered list now shows 3 titles instead of 5, and "See all" opens the rest. Anime and Manga still show 5.
- The All page went from 3,006 pt to 2,702 pt. That is still above the ~1,900 pt goal; this is your call (below).

**Swipe safety.** A sideways swipe that started on a Plan key could add a title to your list or remove it. The key now ignores taps during a page swipe, like every other card does (on Taste too).

**Small text fixes.**
- "Ep. 7 at 21:30" and "Sunday won, 4 to 1" no longer break across lines.
- Today's pick's pitch is no longer cut off.
- "See all" counts the whole section, which is what it opens.
- Taps in the contents line no longer land on the line above.

**Clubs polish.**
- The line under the tabs is inset like Home's instead of running edge to edge.
- The note card no longer has an empty gap at the bottom.
- The two note links now share one plain text style.
- The unread mark is a real small dot instead of a stray "•".
- The "Couldn't load" and offline screens sit at the same height as on Discover.

**Club page scrolling.** The page used to redraw itself and build dozens of date formatters on every scroll frame. It now redraws only when the tabs pin or unpin, and the formatters are built once.

**iPad.** The Clubs iPad pictures were stretched phone layouts. They now use the 680 pt reading column, and I checked them.

## Before → after
| What | Before | After |
|---|---|---|
| Discover, first screen | before/discover-all-top-390.jpg | after/discover-all-top-390.jpg (also -320, -ipad, -de) |
| Discover All, whole page | before/discover-all-full-390.jpg | after/discover-all-full-390.jpg (2,702 pt) |
| Clubs list | before/clubs-list-top-390.jpg | after/clubs-list-top-390.jpg, after/clubs-list-ipad.jpg |
| Club page | before/club-detail-rails-top-390.jpg | after/club-detail-top-390.jpg, after/club-detail-top-ipad.jpg, after/club-detail-polls-full-390.jpg |

The live/ JPEGs were captured before these fixes; the gallery says so.

## Your decision: how long should the All page be?
The spec asks for five rows per list (§6.2) and also for a ~1,900 pt All page (§6.1); it can't have both. I made one change that's easy to undo: 3 rows on All. Current lengths:
- English: 2,702 pt
- German: 2,778 pt
- With the realm flag on: 3,262 pt

Further options. Each of the first two saves roughly 250 to 400 pt, and every title stays one "See all" away:
1. On All, draw "Manga new to you" as the sideways rail or as a numbered list, instead of a second feature with three covers.
2. On All, move "Essential manga" into the fold.
3. Go back to 5 rows: change the one constant `DiscoverIssueLayout.allIssueIndexRows`.

## Every finding and what happened
1. **Discover off centre (major): fixed.** I measured each part's width to find the cause: the cover-trio row reported 363 pt in a 350 pt column. Regression test: `DiscoverAfterSnapshotTests/columnFit()`. `DiscoverAtLeastWidth` was not the cause and is unchanged.
2. **All page rhythm (major): partly fixed.** 3 rows on All; the remaining length is your call (above).
3. **Tab hairline ran full width (major): fixed.**
4. **Clubs iPad renders were compact (major): fixed.** They now render at regular width.
5. **Plan key cut the pick's argument: fixed.** The argument may now use 4 lines. Kept as is: two-line titles in the index rows, which are the design.
6. **Note card had empty space at the bottom: fixed.** The 44 pt tap area now reaches into the card's padding instead of being drawn.
7. **Unread dot read as punctuation: fixed.** It is now a 6 pt dot after a no-break space.
8. **Failed/offline screens at different heights: fixed.** Clubs now uses the same rule as Discover.
9. **Airing caption split the time: fixed.**
10. **Poll result wrapped: fixed.**
11. **Note disclosure looked like a chip: partly fixed.** It is now the same text link as "note ↑", but at 390 it still wraps to two lines in the narrow two-column tile.
12. **Club page did work on every scroll frame (major): fixed.**
13. **Plan key ignored the pager's tap guard (major): fixed,** with a test.
14. **"See all" count was wrong: fixed.**
15. **Section order and flag gates were untested: fixed.** They are now a pure `DiscoverIssueSections` with tests for All, Anime and Manga, with the flags on and off.
16. **Contents tap targets overlapped the line above: fixed.**

## Verification
All runs used the owned simulator 7FC4B58A by UUID.
- KuroTests: 920/920 passed (152 suites).
- NavigationContractUITests + NavshellUITests: 15/15.
- Release build: generic, unsigned, SUCCEEDED.
- KuroModules package tests: PASS (14 + 73 + 9).
- Quality gates (`run_all.sh`, skipping the iOS build, iOS tests and rails audit): 10 passed, 0 failed. local-db and live-services were BLOCKED by the environment. The docs gate passed.
- Renders came from a fresh lane simulator (Kuro-Lane-dc-integrator), which I deleted afterwards. The owned simulator's settings were not changed.
- No evidence files outside after/ changed.
