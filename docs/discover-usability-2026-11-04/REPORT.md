# Discover usability pass: morning report (4 November 2026)

## In plain English

Discover is easier to use on the local branch `kuro/discover-usability`. Nothing is pushed, applied, deployed or switched on.

- Each series appears once per page.
- Every section says what it is for. Personal sections say why a title is there.
- Every card opens with one tap and has a Plan key. A long press shows a preview with Plan, Seen it / Already read, Not interested, Add to club and Open.
- Not interested and Seen it remove the title at once, teach your Taste profile and can be undone.
- Mood shortcuts open short, cozy or intense journeys. "See all" is a real page with sorting and filters.
- The page ends after about six sections with "You're caught up for today."

A review last night raised 20 findings, and all of them are now handled:
- The page renews when you open it the next morning, instead of showing yesterday's sections under today's date.
- Section numbers no longer promise more than the page behind them holds.
- Later seasons are no longer offered as the way into a series.
- The Trending length filter searches the whole list, and See all keeps your choice.
- Plan keys line up and are never cut off. German text wraps instead of being cut.
- Undo can no longer quietly put a title back on your list.
- The phone remembers every hidden title, not just the newest 2,000 rows.
- The prepared server readers fill whole pages even for people with many titles on their list.

## Per contract rule (where to see it: `docs/discover-usability-2026-11-04/index.html`, renders in `after/`)

- **R1 One question per section.** A purpose line sits under every heading, and "Because you…" names its reason. *Fix:* "See all {n}" and the contents number now appear only where the See all page draws the page's own loaded rows: Essentials, Classics, Because you and Airing today. They count that list after the rules. Open-ended lists (Trending, Top rated, Just added, New to you, This season) read "See all ›" with no number. The Essentials purpose line uses the same number. See `page-all-full-390.jpg` and `page-contents-390.jpg`.
- **R2 Never the same series twice.**
  - One build per visit claims titles in this order: the lead, then Essentials, then page order. Franchises are matched by server component, or by title stem until the SQL is applied.
  - Owned titles are hidden in personal sections and marked with the status word elsewhere.
  - *Fix:* a section's tail (the titles beyond what it shows) is deduped within that section only. `DiscoverSequel` keeps "Season N", "Nth Season", "Final", "Part N", "R2", "II–IV" and "…Arc" out of personal lists and moods. Bare numbers such as "Kaiju No. 8" are never treated as sequels.
- **R3 One tap plus one quick action.** *Fix:* tiles reserve two title lines and one fact line, so Plan keys share a baseline and the rail never clips one. See `page-all-full-390.jpg` and `page-all-full-ipad.jpg`.
- **R4 Instant feedback and Undo.** Haptic and stamp on Plan, a toast with Undo on hides. Unchanged.
- **R5 Feedback changes the page.**
  - Not interested is stored as the deck signal 'skip' and Seen it as 'known'. The title is removed at once and the answer is remembered on the device and on the server.
  - *Fix:* Undo never replays a deck 'love', because the live `record_taste_deck_signal` inserts every love into the list as PLANNING. In that case it retracts instead.
  - *Fix:* the hidden set is now read in full: skip and known in pages of 1,000 rows (at most 10 pages), love and pass separately.
- **R6 Visible, local filters.** *Fix:* the Trending choice filters the section's whole unclaimed list and counts the matches, and See all opens with the same chip selected. "Hide my list" appears only where owned titles are kept. Chip groups no longer split across lines.
- **R7 The page ends.** About six sections, then the end block with Browse and Search. *Fix:* the end tally says "as read" on Manga and "as seen or read" on All.
- **R8 Place respected.** Scroll position and the Anime/Manga/All segment are kept, and the navigation contract is unchanged. Navigation UI tests: 15/15.

## Per build item

1. Franchise dedupe and the owned rule. Also: section-local tail dedupe and the sequel rule.
2. Long-press preview and menu on Discover cards, See all and moods. *Fix:* the preview kicker no longer repeats the medium ("ESSENTIAL ANIME").
3. Not interested / Seen it wired to Taste, with Undo and "Add as Completed ›". *Fix:* Undo no longer replays a love, and the hidden set is read completely. Manga wording: "Marked as read.", "unread by you".
4. Mood keys and journeys. *Fix:* "Something short · An evening or a weekend" (DE "Für einen Abend oder ein Wochenende"). It no longer says "complete", because the fallback rail means one season, not a finished series. Subtitles get two lines.
5. A real See all page. *Fix:* Hide my list only on mark lists, chip groups kept whole, the status word leads on rows. Journeys end only on an empty page.
6. Purpose lines and Trending words. *Fix:* honest counts.
7. End state with at most six sections. Unchanged.
8. "New since your last visit" markers. *Fix:* a same-day return reads "since your last visit", and German uses the full weekday ("seit Dienstag"). *Fix:* a page left alive overnight reads the new day's bundle on the next visit (`DiscoveryStore.hasCurrentDayBundle`, `DiscoverPageRules.visitStart`).
9. Essentials progress hook. Unchanged.
10. Header title tap scrolls to top; contents jump links; pinned index. *Fix:* contents names wrap to two lines. The pinned "ahead" words use `kuroMuted` (4.86:1 on the Manga canvas).
11. ANIME/MANGA labels on All. *Fix:* the plain "Manga" format word is dropped when the kicker already shows MANGA.
12. Telemetry through `InteractionTelemetry`. Unchanged. *Fix:* first paint no longer waits for the hidden-set and franchise reads. The page builds at once and rebuilds once, only if nothing was tapped and you have not scrolled past the first screen.

## The 20 findings

| # | Finding | Outcome |
|---|---|---|
| 1 | Daily renewal | Fixed |
| 2 | Counts disagree | Fixed in substance. One number where See all is bounded, none where it pages. The canon exemption was **rejected**: R2 wins, and the Essentials purpose now uses the deduped number. |
| 3 | Rail key clipped / misaligned | Fixed |
| 4 | German contents and mood truncation | Fixed |
| 5 | Short-mood copy and sequels | Fixed in substance. New copy plus the sequel-word rule. Earliest-season ordering was not built. Consequence: a franchise whose only listed entry is a sequel now drops out of personal lists. |
| 6 | German index rows | Fixed in substance. Key width capped (the key's own 0.7 scale applies), facts get two lines, the status word leads on both surfaces. The "Schaue" word change was **rejected**: "Schaue ich" is the existing Folio word (Rule 4). |
| 7 | Dead "Hide my list" chip | Fixed |
| 8 | Pinned contrast | Fixed |
| 9 | Trending refine | Fixed. The German row still wraps "Fertig erschienen" onto a second line (open). |
| 10 | Chip groups split | Fixed |
| 11 | Redundant medium words | Fixed |
| 12 | NEW wording | Fixed |
| 13 | Manga "seen" wording | Fixed |
| 14 | iPad / German renders | Fixed: `page-all-top-ipad`, `page-all-full-ipad`, `page-all-full-390-de`, `page-all-full-320-de`, `page-manga-top-390-de` |
| 15 | SQL pool depth | Fixed. Exclusions run inside each candidate query, the pool grows up to 4,000 for franchise dedupe only, the client ends a journey only on an empty page. Suite 87 has +4 assertions (50). Mutation check: the old SQL returned NULL for page 1. |
| 16 | Undo replays a love | Fixed (`TasteStore.undoAction`). Cost: that title's deck love is lost from Taste. |
| 17 | Hidden set capped at 2,000 | Fixed |
| 18 | Unknown prior on Undo | Partly **rejected**. "Send nothing" would leave the skip on the server, so Undo still retracts. Residual: an unknown prior pass is lost (the deck may deal the title again). |
| 19 | Query cost | Partly done: top-N `ORDER BY … LIMIT` instead of a window. Measuring at production size is **deferred** to the apply step. |
| 20 | First paint | Fixed |

## What the lead must do live, in this order

None of this has been done.

1. **Measure query cost.** At production size, as an authenticated user with a large list, run `EXPLAIN ANALYZE` on:
   - `discover_section_page_v1('newly_added','MANGA')`
   - `discover_section_page_v1('new_to_you','ANIME')`
   - `discover_mood_v1('short','ANIME')`

   The `not exists` anti-joins now run over the whole candidate set. The indexes they need exist in the migrations: `taste_signal_events_user_media_idx (user_id, media_type, media_id, created_at)`, and the unique keys on `anime_user_lists(user_id, anime_id)` and `manga_user_lists(user_id, manga_id)`.
2. **Apply** `supabase/prepared-migrations/20261104100000_discover_usability_v1.sql` in one transaction. It depends on nothing pending.
3. **Run `get_advisors(security)`.** `media_franchise_ids_v1` makes the public franchise mapping readable by anon.
4. **No edge function, flag or client release is tied to it.** The app falls back silently before and after the apply.
5. **Then** do the owner and device check, and the TestFlight build.

## Verification (owned simulator 7FC4B58A, final tree `ee73fc2`)

| Check | Result |
|---|---|
| KuroTests | 1,167 / 1,167 |
| NavigationContractUITests + NavshellUITests | 15 / 15 |
| Release build (generic iOS, `CODE_SIGNING_ALLOWED=NO`) | BUILD SUCCEEDED |
| Local DB tests | 38 files, 1,318 assertions PASS (2 BLOCKED scopes, already there before this pass) |
| Suite 87 | 50 / 50 |
| `run_all.sh` (iOS build/test and rails audit skipped) | 10 passed, 0 failed; local-db and live-services BLOCKED as before |
| Architecture, branded states, secrets, migrations and docs gates | PASS |

Fixture page heights at 390 pt: All 3,842, Anime 3,698, Manga 2,740. They were 3,825 / 3,648 / 2,613; the reserved title lines and wrapped text add height.

## Open items

- **Page height.** All is still far over the spec's 2,300 pt target, and the fixes added a little. This needs an owner decision.
- **German opening kicker.** "HEUTIGE AUSGABE · MI 4…" truncates at 390 pt. It lives in the shared Home component `HomeOpeningLineView`, so it was not fixed here.
- **German Trending row.** "Fertig erschienen" wraps alone onto a second 44 pt line.
- **Pull to refresh after a tap.** It keeps the device's hidden memory, and the server's hidden set is only applied on the next visit (the D5 guard).
- **PostgREST `max_rows`.** The hidden-set paging assumes it is at least 1,000 (the hosted default). There is no `supabase/config.toml` in the repo; please confirm.
- **UI test not written.** `KuroUITests/DiscoverUsabilityUITests` (long press → Not interested → Undo on fixtures).
- **No real-device check yet.** VoiceOver on the preview, Reduce Motion on the hide.
- **Stale pending list.** `supabase/tests/pending_migrations.txt` still lists files recorded as applied.
- **Trending See all order.** It uses live `anime.trending`, while the rail uses the nightly view.