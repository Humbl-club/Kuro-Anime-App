# Native versus Poster composition

Pinned Poster references (Chrome headless, local `tools/design-directions/instrument.html`):

- `?switch=poster&medium=anime`
- `?switch=poster&medium=manga`
- `?switch=poster&detail=anime-2`
- `?switch=poster&detail=manga-0`

Captured at **320 / 390 / 430** CSS points under `screenshots/poster/`.

Native renders (fixed bundle, `HomeCompositionSnapshotTests`, UIHostingController) at the same widths under `screenshots/native/`. The views under test are `HomeView`, `SeriesAnimeDetailView`, and `SeriesMangaDetailView` (the `series_home_native_v1` surface).

## Rule checklist (first plan)

| Rule | Native 320/390/430 | Fix needed? |
| --- | --- | --- |
| Landscape art aspect **3.25** | Lead anime cards use `.aspectRatio(3.25, …)` | No |
| Season tab on artwork | White season control on the lead card art | No |
| Compact **S** stamp | Compact cards use `seasonStamp` (`S1`, …) | No |
| Progress key separate from title | Sibling `progressKey` next to / under the title | No |
| Equal **2:3** manga covers | Manga grid `.aspectRatio(2/3)` | No |
| **44pt** chapter / progress key | `minHeight` / `frame` 44 on keys | No |
| No selected-book bar | Manga home has no selection chrome | No |
| Pending dates say **"Dates to come"** | Glance + calendar copy | No |
| Club **"Between us."** | Club slice title | No |
| Season copy does not write progress | Season buttons only reload section copy | No |
| Missing fields stay missing | Coverage / cast / music empty copy preserved | No |
| No Parts selector on manga detail | Absent | No |

No listed composition rule was broken. No native layout change was made for this pass.

## Observed differences (prototype chrome, not rule breaks)

These are intentional Poster flourishes versus the accepted native shell. They are recorded; they are not treated as misses against the first-plan rules.

| Surface | Poster | Native |
| --- | --- | --- |
| Medium switch | Giant filled ANIME / MANGA letterforms | Compact Anime / Manga control |
| Coming up glance | “Today · N releases” + stacked thumbs | Count / “Dates to come” / “Nothing scheduled” + ↓ |
| Anime progress label | “Ep. N/” in the card footer | Absolute progress number + plus key |
| Manga progress | “Ch. N” + plus on a paper key under the cover | Number + plus key overlaid on the cover foot |
| Anime detail seasons | Large numbered season plates with “Current” | Capsule Season N tabs; selection refill is copy-only |
| Manga detail | Cover beside title, “SERIES OVERVIEW”, club avatars in the body | Cover above title, bookmark, editions, read-only anime guide |
| Instrument chrome | “KURO / !BORING STUDY” study bar | None (app chrome only) |

## Evidence paths

- Poster: `screenshots/poster/{anime-home,manga-home,detail-anime-2,detail-manga-0}-{320,390,430}.png`
- Native: `screenshots/native/{anime-home,manga-home,detail-anime,detail-manga}-{320,390,430}.png`
- Generator: `KuroTests/HomeCompositionSnapshotTests.swift`
