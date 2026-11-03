MORNING REPORT: details, songs & platform, review-fix round (3 November 2026, evening)

Plain English first. All 13 owner items were already built and integrated on the local branch kuro/details-songs-platform. Tonight I checked every review finding against the code, the renders and the tests, and fixed the real problems. Everything is in one new commit, 5c5638a. Nothing was pushed, no migration was applied, no function was deployed, no flag was changed and no production data was written.

The review list I was given was cut off partway through its last entry ("Apple worker rate-limit behaviour, file scrip…"). I read that entry as "when Apple keeps refusing, the Apple pass keeps waiting and retrying for every remaining song" and fixed it so the pass stops. I could not see any findings after that point.

You can see everything in docs/details-songs-2026-11-03/index.html. The Report section has a new "Review fixes" subsection, and the after renders are refreshed.

PER ITEM: what changed tonight and where to see it
1. More like this. The title of each card now always takes two lines, so the Plan keys line up across the rail. See after/detail-anime-full-390.jpg.
2. Richer hero.
   - On iPad, the text under the artwork now starts at the same left edge as the page body (the manga band too).
   - A title too long for two lines beside "Watching / Add" now puts that mark underneath instead of cutting the title off.
   - The facts line keeps "·" with the part before it and never splits a part.
   - The manga facts use the full width beside the cover.
   - The two iOS 26 deprecation warnings are gone.
   - See after/detail-anime-top-ipad.jpg and after/detail-manga-top-390.jpg.
3. Episode timeline.
   - The next episode's date now comes only from the release schedule, so the hero and the timeline show the same day ("Ep. 8 · Fri, Nov 6" in both) and the rows stay in order.
   - Only the up-to-three schedule rows that are actually drawn replace catalogue rows, so every episode still appears exactly once.
   - AniList titles like "Episode 2 - Stray Dog Strut" now read "Stray Dog Strut".
   - The Watch link has a proper VoiceOver label.
   - See after/detail-anime-full-390.jpg.
4. Cast. Voice chips line up across the rail (same two-line title fix). Voice-actor data is still prepared only.
5. Branded tiles: no change tonight.
6. Entity pages.
   - On a studio's "By year." list, each title in a quiet year is its own row that wraps inside the column with a "›". In a busy year the "N more" count can no longer be cut off.
   - The leading year column shows only under the Year sort. Under Rating or Era the year moves into the small line under the title.
   - Character pages no longer start their bio with "Height: 190 cm". Such lines move into the facts line at the top (at most two, never age or gender). Staff and author bios are unchanged.
   - See after/entity-studio-390.jpg (now with two long-title fixtures) and after/entity-character-390.jpg.
7. Song previews.
   - Previews now use the audio mode the spec asks for, so they play even when the phone is on silent.
   - A stream that hasn't started after 10 seconds gives up and shows "Preview unavailable".
   - The About text now says that song artwork loads from Apple as soon as the songs are shown, matching the privacy policy.
8. Songs layout. When none of a title's songs has an artist, the shelf shows one note at the bottom ("Artists not listed by the source.") instead of "Artist not listed" on every row.
9. Widget.
   - The widget never says "Today" or "Tomorrow" any more. Those words are fixed when Kuro writes the widget data, so while Kuro stays closed it would still have said "Tomorrow" on the release day. Days are now always written out.
   - The medium widget drops the "Up next ·" prefix so the date fits.
   - On a waiting +1, only the button face fades; the "+1" stays readable.
   - A waiting +1 can no longer go past the episode or chapter count Kuro itself knows.
   - A cover still downloading at sign-out is never written back into the widget's storage.
   - See after/widget-now-medium-de.jpg.
10. Notifications.
   - A bell you turned on for one title now stops when that title is paused, planned, finished or removed. Before, nothing in the app could stop those notifications.
   - At app launch, nothing already scheduled is removed while your list is still loading; the plan is made once it has loaded.
11. Profile stats: no change.
12. Import screens.
   - If reading your import history fails, the screen shows the error card plus "Try again" instead of "No recent imports."
   - App-wide change: a disabled main button now has a light face, a thin outline and dark grey text (about 5:1 contrast) instead of white text on light grey (about 2:1). This affects every disabled main button in the app. See after/import-anilist-390.jpg.
13. Discover All. I corrected the spec. The "before" render it relied on was squashed to about 61 % of its height, so the old page was really about 2,700 pt long, not 1,641. The new page is 2,102 pt: about 600 pt shorter, but about 100 pt over the 2,000 pt limit. Getting under it needs your layout decision. Options: move Trending or Manga new to you into the fold, or drop the Airing-today strip on All. The two squashed before images are now captioned "NOT TO SCALE".

BACKEND STEPS FOR YOU (all prepared only, in this order; the runbook is docs/details-songs-2026-11-03/data/BACKFILL.md)
1. Apply the prepared migrations 20261103100000 (voice actors), 20261103100100 (More like this) and 20261103100200 (Apple fields on songs).
2. Deploy bulk-import-anime.
3. Run the voice-actor backfill. **The runbook is corrected.** The old text ("+4 per run") would have skipped 3 of every 4 pages while every run reported success. The correct procedure:
   - Each run imports 2 pages.
   - The next run's startPage is the nextStartPage from the previous response.
   - Wave A is 50 runs; wave B is 200 runs.
   - Do the first run as a single page.
   - Stop if a response shows `skipped`, or if nextStartPage is not startPage + 2.
   - Two new deno tests check this behaviour.
4. NEW section 3a: song artists. Measure artist coverage with the read-only query in the runbook. Then re-run the AnimeThemes theme pass for the titles missing artists. This must come before the Apple pass, because a song with no artist never gets an Apple match (live, all four Cowboy Bebop songs have no artist).
5. Apple pass: run --dry-run first and spot-check the matches, then the real pass. Matching is now stricter:
   - Titles must be equal after normalisation, with no fuzzy matching ("COLORS 2" no longer matches "COLORS").
   - Live recordings are rejected.
   - The Japanese long-vowel folding applies only to romanised Japanese titles ("Shout" no longer matches "Shot").
   - If Apple keeps refusing (403/429) after its retries, the pass stops and reports rate_limited.
6. Legal: the Apple Search API terms still need review before that privacy policy section is published.

VERIFICATION
- KuroTests (1,076 tests in 175 suites, owned simulator 7FC4B58A by UUID):
  - The full run passed 1,075 and failed one: the new "bell goes quiet when paused" test. Its setup used `save`, which never changes an existing entry.
  - With a real status change it passed in the re-run, together with all four render suites (19 of 19).
- Navigation UI tests (NavigationContractUITests + NavshellUITests): 15 of 15.
- Builds: the KuroWidgets target and a clean Release build (generic iOS) both succeeded. The Release build has 60 unique app warnings, the same as the CLAUDE.md baseline, and none in any file changed tonight.
- deno bulk-import-anime: 31 of 31. Python worker: 32 of 32.
- run_all.sh (with SKIP_IOS_BUILD, SKIP_IOS_TEST and SKIP_RAILS_AUDIT): 10 checks passed; local-db and live-services are blocked by the environment, as before. The docs check also passed after the docs update.
- No SQL changed tonight, so the earlier local-database result (1,268 assertions) still stands.
- Renders were written only to docs/details-songs-2026-11-03.

REJECTED OR RECORDED INSTEAD OF CHANGED
- Song preview stops rather than pauses, and the player is shared by the whole app rather than owned by each page: both recorded as deviations in spec §17.
- The account schedule returns one row per title, so only the next release per title is scheduled. Spec §11.2 and the report now say so.
- The manga read run keeps one row, as in the prototype; recorded in spec §17.
- The season tab on iPad stays at the artwork's edge, because it belongs to the artwork.
- The German "Wird gespeichert, wenn Kuro öffnet" caption on the widget still wraps to two lines; it is legible.
- Spec §15 now says English dates follow the device's locale. The render simulator is English with region Germany, which is why it shows "Score 8,6".

OPEN
- Discover All is 2,102 pt against the 2,000 pt limit (your decision).
- Not checked on a device: VoiceOver order, the widget +1, the widget gallery, the bell and Profile permission prompts, and delivered notifications.
- A widget +1 reaches the server only the next time Kuro runs.
- Renders still missing: import review rows and the match picker with a sample job, the bell toasts and the denied/failed states, and the club section ("Between us." after "More like this."). The Profile reminders switch renders without its knob in snapshots.
- The reminder API has no "failed" result, so the app can't show "Couldn't set the reminder".
- The widget's +1 action has English-only title and description.
- Pages opened from cast rows have no bio, because there is no way to read one character or staff member by id.
- Register the App Group and the widget App ID before archiving.
- supabase/tests/pending_migrations.txt still lists two migrations applied on 2 November.