# Kuro — issue style, full application

Status: visual direction Max confirmed on 27 September 2026. This prompt is the brief for changing the app to that look. It does not authorize a hosted deploy, a flag rollout, a migration push, or a TestFlight upload.

Execute the waves in order. Finish a wave only when every success parameter in that wave passes. If one fails, stop, fix it, and recheck that wave. Do not start the next wave on a failed one.

Read before writing: `AGENTS.md`, `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, and this file. The checkout is `/Users/max/Kuro-Anime-App`. Keep SwiftUI and `@Observable`. No Combine. No second networking stack. No new database. Wrap every `print` in `#if DEBUG`. Light mode stays on. Do not create `Kuro/Info.plist`. Do not hardcode a 393-point card width. Update the three state documents and the memory note after the work.

The 26 September research still governs product behavior: tracking stays free, clubs are the only social graph, Taste stays optional, music stays staged, welcome scenery stays on welcome and auth. This prompt changes how titles are shown. It does not reopen those product decisions.

## The look

People look for the picture of a title. They are not looking for a contents page, a numbered index, or a paragraph before the image.

Every title is a frame:

- The picture is first. Cover or banner, cropped, edge to edge in the frame.
- The jacket color is the field behind the type, and the field that shows until the image arrives. Read `cover_image_color`. If it is missing, use the stable muted fallback in `DiscoverIssueCopy.fieldHex`. Do not invent a rainbow. Do not color a status.
- Under the picture: the title, then one sentence. The lead of an issue may keep two short sentences. Nothing else in that block. No episode count, no chapter count, no score chip, no genre pills, no “01 / 02 / 03”.
- The sentence is a teaser, not a synopsis dump. Prefer, in order: a daily-feature `argument` that is already short; else `synopsis_enhanced` when its state is `ready`; else display `description` after `TextNormalization.sanitizeMediaDescription`. Never show `description_normalized`. If there is no sentence, show the picture and the title and omit the line. Do not print “No description available”.
- Paper is `#F6F4EF`. Ink is black. Type on a dark field is `#F4F1EA`. Type on a light field is black. Choose with `DiscoverIssueCopy.usesLightType`.
- Serif for the title (`kuroHero`, `kuroDisplay`, `kuroTitle`). Sans for the sentence (`kuroBody`, `kuroCaption`). Small caps only for a kicker such as THIS ISSUE, OPEN, CLOSE, DETAILS. Use the existing helpers in `Kuro/Design/KuroDesignSystem.swift`.

The frame the owner liked is the issue block: still on top, title and line on the color underneath, a hairline, then OPEN. Repeat that frame smaller for every other title. Do not return to a text list.

## Viewpoints

Judge every wave from these eyes. A wave fails if any of them cannot complete the job.

| Viewpoint | What they need to see first | What must not be in the way |
|---|---|---|
| Returning, anime | The picture of a title they can recognize, then one line | A numbered list, a score grid, a paragraph |
| Manga only | The same frame, manga pictures, the word Manga selected | Anime art left on screen, a second hidden catalog |
| Empty library | One action: find a title, or bring a list | A fake issue, empty numbered rows |
| Large text | The picture still first, the line wraps, OPEN stays reachable | Clipped type, a control under the keyboard |
| Reduce Motion | The same poses, a short fade via `KuroMotion.resolve` | Travel, bounce, a finger-tracking drag |
| Offline | The last pictures, with an honest cached line | A blank issue that looks like there is no library |
| Pager swipe | The page changes | A title opening because the finger moved sideways |

## Motion

Motion confirms a change. It does not decorate a wait, a failure, or a status. Nothing loops after welcome. Welcome and auth keep their existing scene. Do not spread that scene into Discover, Home, Collection, or Clubs.

One easing family: ease-out, then a 40ms settle. No spring overshoot. Haptic only when the act is confirmed. A rejected write plays the gesture backward and stays silent. A pager swipe sets `kuroSuppressCardTaps`; title taps must honor it.

| Gesture | What moves | Duration | Haptic | Where |
|---|---|---|---|---|
| Lift | The frame the finger touched becomes the only object | 320ms | Light, as it leaves its place | Opening a title from any list |
| Rise | The still stays. The paper with the title and the one line is already the lower part of the frame | 280ms, after Lift | Medium, when it seats | The open spread |
| Field | The jacket color is the ground of that spread. It arrives with the picture and leaves with it | 240ms, with Rise | None | Open spread |
| Turn | The whole plane moves to the next title. The picture changes. The chrome does not bounce | 360ms | Light, on the snap | Sideways swipe inside the open spread |
| Stamp | The old progress count leaves upward. The new count locks from below. Undo reverses it | 160ms | Medium, only after the server confirms | Collection `+1`, which already calls `incrementProgress`. The title page saves an absolute count through `setUserProgress`; Stamp that confirmed save. Do not invent a second +1 there |
| Return | The spread drops. The picture is back in the frame it came from | 260ms | None, unless the flick commits | Close, or a short drag that does not cross the threshold |

Implement Turn and Return on `DiscoverIssueSpread` first, then reuse the same timings everywhere a title opens. Do not invent a second animation language per page. Reduce Motion calls `KuroMotion.resolve` so the pose cross-fades in 0.2s. Do not pass `nil` and do not follow the finger while Reduce Motion is on.

## Product pages

A product page is any place a title is chosen or kept. They all use the same frame and the same open.

| Page | Job | First paint | Open |
|---|---|---|---|
| Discover | Find a title | Issue: one lead frame, then more frames, picture first | Spread, then Details |
| Browse | Search the catalog on purpose | Same frames, filters as type, not colored chips | Same spread |
| Search sheet | Find a name | Results are frames, not text rows | Same spread |
| Collection | Continue and organize | Current titles as frames. +1 can Stamp on the row when the title is current | Same spread, or Stamp in place |
| Title page | Track one title | Picture first, title, one line, then progress | Already open. Stamp the confirmed `setUserProgress` save |
| Club rail | A shared title | The same frame, no extra social chrome before the picture | Same spread |
| Profile | Identity | Name and the activity control. Not a wall of posters | None |

Details stays the existing `MediaDetailSheet` (`AnimeDetailLoaderView` / `MangaDetailLoaderView`) until Wave 5 restyles its top. Do not build a second detail stack.

## Data

Do not add a table. Do not deploy a migration for this style.

- Lead copy: `DailyFeature.argument` when it is present (`Kuro/Services/SupabaseService+Discover.swift`). Trim with `DiscoverIssueCopy.sentences(from:limit:)`.
- Other titles: `fetchDiscoverIssueSources` already selects `description`, `synopsis_enhanced`, `synopsis_enhanced_state`, `cover_image_color`. Use `DiscoverIssueSource.displayText`.
- Pictures: banner when the lead has one (`DailyFeature.artURL`), otherwise `coverImageLarge` / `imageURL`. `DiscoverIssueStill` crops them.
- Scope today is local to each surface. Discover uses `medium` on `DiscoverIssuePage`. Browse uses `showAnime` on `BrowseView`. Search uses `SearchScope` on `EditorialSearchView`. Collection uses `MediaTypeFilter` on `EditorialCollectionView`. Changing one does not change the others. A later wave may share one choice, but it must say so. Do not pretend they already match.

`DiscoverIssueComposer.assemble` builds the issue: daily feature first when it matches the medium, then the pool, lead not repeated. Keep that rule.

## Wave 1 — Discover is only frames

The scroll in `EditorialDiscoverView` is already `DiscoverIssuePage`. Finish it so no title is text without a picture.

Files: `Kuro/Views/DiscoverIssuePage.swift`, `Kuro/Views/DiscoverIssueCopy.swift`, `Kuro/Views/EditorialDiscoverView.swift`.

The lead is the still, then THIS ISSUE, the title, at most two sentences, a hairline, OPEN. Every following title is `DiscoverIssueStill` (the picture), the title, one sentence. The two-up stays two pictures with one line under each. Further titles are the same frame, not a text list. Anime / Manga is a type switch, underline on the selected word, no colored pill.

Success parameters:

- The first screen shows a picture before any sentence.
- No view on Discover renders a contents number, an episode count, or a score chip.
- A title with no synopsis shows the picture and the title and no placeholder sentence.
- Switching to Manga replaces the pictures. Anime pictures are gone.
- Empty Discover still offers retry. It does not invent titles.
- Pull to refresh still calls `refreshSections`.
- `kuroSuppressCardTaps` still blocks Open.
- Unsigned generic iOS build with `CODE_SIGNING_ALLOWED=NO` succeeds.
- `DiscoverIssueCopyTests` still pass.

## Wave 2 — Open, turn, return

`DiscoverIssueSpread` is the opened issue. The still is full width at the top. CLOSE sits on the picture. The title and one or two sentences sit on the jacket color. DETAILS presents `MediaDetailSheet` for that kind and id. A horizontal drag past the threshold Turns to the next or previous item in the same issue array. A drag that falls short Returns. Reduce Motion does not track the finger.

Success parameters:

- Open from the lead, from a following frame, and from a two-up tile all land on that title’s picture.
- Swipe to the next title changes the picture and the sentence together.
- Swipe past the ends does not wrap and does not dismiss.
- CLOSE returns to Discover without opening Details.
- DETAILS opens the existing title sheet for the correct anime or manga id.
- Reduce Motion: the new picture appears with `KuroMotion.resolve`, no horizontal travel.
- One light haptic on Open, one light haptic on a committed Turn, none on a failed drag.

## Wave 3 — Collection uses the frame

`EditorialCollectionView` and `EditorialCollectionComponents` stay the tracking surface. Replace poster-grid chrome and text-only rows with the same frame: picture, title, one line. Current titles may show the progress count and +1. Stamp plays only after the server confirms. Undo reverses Stamp. A failure snaps the old count back and does not haptic.

Do not merge shelf membership into status. Do not delete tracking when a shelf is removed. Search must still find titles past the first page. Unknown totals stay unknown. The sentence for a saved title comes from the same teaser rule, loaded for the visible ids only, not a full-library description download.

Success parameters:

- The first Collection screen is pictures of the person’s titles, not a text index.
- +1 on a current title changes one count, preserves rating and notes, and does not reload both complete libraries.
- A title beyond the first page can be found.
- Manga Collection says Reading where anime says Watching, with one underlying status.
- Empty Collection offers a way to Discover or import. It does not show an empty numbered list.
- Offline shows the last pictures and does not claim a save succeeded.

## Wave 4 — Browse and Search are the same frames

`BrowseView` remains the deliberate catalog. `EditorialSearchView` remains the sheet opened from the header magnifier. Do not move search onto the Discover scroll. Results and browse cells use the frame. Filters stay typographic. Unsupported filters do not pretend to work. Each surface keeps its own Anime / Manga control until a shared preference is an explicit change. A stale response from the other medium on that surface must not paint.

Success parameters:

- A search result is a picture, a title, and at most one line.
- Changing Anime / Manga clears the other medium’s results.
- Typing a new query does not append the previous query’s rows.
- Browse still pages without gaps or duplicates on a stable set.
- The header search control still opens `EditorialSearchView`.

## Wave 5 — The title page

Restyle the top of `AnimeDetailView` and `MangaDetailView`, including when Concierge presents those views directly. Picture first, full width. Title and one line on the jacket color. The existing progress editor sits under that, on paper. Credits, music, and links stay below and stay collapsed until asked. Music stays hidden while `anime_music_credits_v1` is off. Do not autoplay. Unknown totals stay editable. A confirmed `setUserProgress` Stamps. Do not add a Collection-style +1 on this page.

Success parameters:

- The first thing on the title page is the picture.
- A confirmed progress save Stamps. A rejected save does not. There is still no +1 button on this page.
- Opening Details from the spread and from a deep link (`kuro://anime/…`, `kuro://manga/…`) shows the same top.
- No episode total is invented from “next airing minus one”. No manga chapter total is invented from the indexed maximum.

## Wave 6 — Clubs and profile

Club lists and rails may use the frame for titles. Identity stays the first thing on a profile. Activity stays off until the existing consent path allows it. Do not add followers. Do not put a magazine lead on top of someone else’s private list. Realtime still updates the visible club. A pager swipe still does not open a title.

Success parameters:

- A club rail item is a picture first.
- A profile with activity off shows no history.
- Leaving a club or turning activity off does not leave the old pictures described as current.
- No new public social graph.

## Wave 7 — Welcome stays where it is

Do not restyle `AuthView` into an issue. Do not remove the approved welcome scene. Do not run that scene on Discover. Auth failures still leave a usable path. Reduce Motion on auth still shows a still scene.

Success parameters:

- Welcome and the email form still match the approved auth composition already in the app.
- After sign-in, the first page is the existing pager destination (Discover), and it does not animate the welcome scenery.
- No catalog request is added to the welcome screen.

## Wave 8 — Proof

Success parameters for the whole pass:

- One frame component is the picture-plus-line used by Discover, Browse, Search, and Collection. Detail and club rails use the same crop and type rules.
- No screen in this pass shows contents numbers as navigation.
- No status is a colored pill.
- Reduce Motion, Dynamic Type, and `kuroSuppressCardTaps` are checked on Discover and Collection.
- Unsigned `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` succeeds.
- `DiscoverIssueCopyTests` pass, plus any new tests for Stamp failure and for “lead is not repeated”.
- `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, and `IMPLEMENTATION_PLAN_Variation1.md` describe what shipped in the app versus what is still the old chrome.
- No migration, edge deploy, flag change, or TestFlight upload happened as part of the style pass.

## Stop

Stop the pass when Wave 8 passes, or when a success parameter fails and cannot be fixed without a product decision. Do not fill the gap with a numbered list, a text-only row, or a second visual language.
