# Kuro Home — selected artwork season design

Local browser prototype, v29. The owner selected this season treatment on 2 October 2026; this is not a native app or backend release.

## Run

From the repository root:

```sh
python3 -m http.server 8803 --bind 127.0.0.1 --directory tools/design-directions
```

Open http://127.0.0.1:8803/instrument.html. Keep the server running while reviewing.
The comparison is at http://127.0.0.1:8803/instrument.html?seasons=compare.
No package installation, credentials or backend connection is required.

## Selected treatment

- Main Anime images show only the white **Season N** artwork tab.
- Compact covers show only **S2**, **S3**, etc. No separate numbered season rows.
- Tapping the main tab or a mapped compact cover opens the full season overview.
- Inspecting another season never changes the current season or episode progress.
- The liked detail selector and Manga layout are preserved.

The comparison retains the two earlier alternatives and labels Artwork tab as selected. Other design studies in a local checkout are outside this checkpoint.

## Files and verification

`instrument.html`, `instrument.css` and `instrument.js` implement the prototype. `journal-data.js` holds sample catalogue fixtures and artwork provenance. Referenced local artwork is included in `assets/`. The linked `boring-study.html` reference board uses remote publisher media.

Progress, releases, club activity and season groupings are illustrative. Changes are local to the demo and reset on reload; the Anime/Manga preference is retained in local storage. No sign-in is required.

Checked at 320/390/768px: layout fit, accessible season targets, full-season entry points, preview independent of tracking, progress/Undo and Manga preservation. Browser checks do not establish native haptics, backend integration or production behavior.
