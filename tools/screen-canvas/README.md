# Kuro screen canvas — open on any machine

Download this repository's ZIP (or clone/pull it), then open **tools/screen-canvas/index.html** in a browser. No Xcode, Simulator, Python, account or internet is required to view the saved canvas. Keep the `captures` folder and `snapshot.js` beside the HTML file.

52 representative screens and variants: one example per distinct layout, not every anime, manga or creator. Drag to pan, scroll to zoom, click a frame to enlarge, or search by screen name.

## Freshness

The canvas shows its capture time. `manifest.json` records the captured source fingerprint and the base source commit. This initial snapshot includes original-checkout local app edits which are not bundled into the canvas-only Git commit. It is not a production/release screenshot claim. Club details use a labeled local sample; account views are anonymous. Full scroll positions and all dialogs are not covered.

## Update with app changes (Mac with Xcode)

1. Run `xcrun simctl list devices booted` to find your local simulator ID.
2. Run `python3 scripts/capture_screen_canvas.py --device YOUR_SIMULATOR_ID`.
3. Run `python3 scripts/export_screen_canvas.py` after capture completes successfully.
4. Commit `tools/screen-canvas/` together with the corresponding UI changes, then push.

`--watch` on the capture command refreshes local native captures when source files change. Export, commit and push are still required to update the copy on GitHub. Newly introduced routes need capture-registry entries. See `tools/live-preview/README.md` for the optional live localhost viewer.
