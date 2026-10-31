# Current-project screen canvas

Run from the original checkout:

```sh
python3 scripts/serve_live_preview.py --port 8799
python3 scripts/capture_screen_canvas.py --device B9BC0BAE-3BBA-49C9-9591-B24BC5612804 --watch
```

Open http://127.0.0.1:8799/. Drag to pan, scroll to zoom, Fit all to see every registered frame, click an image to enlarge it. Search filters screen names.

Captures use a disposable copy of the current checkout under `/tmp/kuro-screen-canvas/source`, including uncommitted Swift/UI edits. A separate `com.Kuro.canvaspreview` app renders original SwiftUI views. Original Swift sources and the normal app installation are unchanged. Source changes trigger serialized rebuilds and recaptures; this is not instant hot reload. Stop the foreground commands with Ctrl-C. No cron, launchd or hosted changes.

Coverage: the capture registry is `SCREENS` in the Python script. Initial viewport screenshots are not full scroll documents or recordings. Catalog content comes through existing app reads. Account-dependent screens use the existing anonymous preview path; private populated collections, deeper scroll positions and every error/confirmation state are still gaps. Club tabs/settings use an explicitly labeled empty local sample; character/staff/studio/author pages use public catalog reads. Screenshots are visual review material, not authentication or production proof. Build failures keep old captures visibly marked stale. Logs: `/tmp/kuro-screen-canvas/build.log`.

Newly introduced app routes need a corresponding entry in `SCREENS` and the temporary capture host switch. Existing registered screen edits refresh automatically while the watcher remains running. The canvas uses a fixed iPhone 17 Pro viewport; it does not represent every device size.
