# Development and TestFlight pipeline

The release target is qualified TestFlight. These lanes record local verification,
artifact identity and processing, but do not claim installed-device or live-service
acceptance. Public App Store submission is disabled in `release`.

Development does not require a release candidate, administrator access, a live
stack, signing or an installed device. Choose the affected local check:

```bash
fastlane check_development checks:architecture
fastlane check_development checks:swift-packages,edge-functions
# Include docs or local-db only when their proof is relevant and available.
```

This records **development/local checks**, never release acceptance. Checks use
fixed existing scripts. Successful evidence is reused only while its scoped
source/test/dependency hashes, executable/toolchain identity, configuration and
raw log hash remain unchanged. Failed checks are not cached. Change an affected
input and the check runs again; unrelated changes do not force a complete rerun.
Stored outputs live under ignored `.codex-artifacts/verification/`.
Current edge entrypoints use mutable remote `@supabase/supabase-js@2` imports
without a frozen Deno lock. Edge checks therefore run once per verification;
they are not reused across candidates until dependency resolution is pinned.
The live rails dataset is also checked fresh when relevant. Both retain unique
immutable logs, so a later candidate cannot replace an earlier receipt's proof.
SQL reuse fingerprints the same PostgreSQL directory/tools and major-version
configuration selected by the fixture runner; native reuse includes its Python
helper and actual selected Xcode toolchain.

`run_all.sh` remains a broad optional diagnostic. The canonical release path uses
the stage-aware Fastlane checks below; it does not depend on that command's
all-gates summary.

Finish the integrated changes and canonical state documents before preparing a
candidate. Coordinate active writers first. Required tracked **and untracked**
inputs are fingerprinted by path, mode and SHA-256, with Git HEAD and branch.
The allowlist in `release_candidate.rb` includes app/resources, packages/locks,
native tests, backend source/migrations/tests, gates/scripts, configuration,
release pipeline, App Store metadata, the integrated executor/checklist, plans/contracts, the retained design references/assets and
canonical state docs. Reports, build output,
local operation logs and Xcode user state are excluded. Add any new production
input outside that list before freezing. Symlinks and unpinned submodules in
candidate inputs are rejected. The receipt identifies the dirty candidate; it
does not create a Git commit or preserve a checkout backup.

Use a new receipt path for a changed candidate. Default output is ignored under
`.codex-artifacts/release/`.

```bash
# Assign the next ASC build number, then freeze. Needs ASC access.
fastlane freeze_beta candidate:.codex-artifacts/release/candidate.json

# Or reserve an explicit unique build number before local preparation.
fastlane freeze_beta build_number:18 candidate:.codex-artifacts/release/candidate.json

# Collect real service/deployment reports bound to this receipt's snapshot hash.
# Set KURO_LIVE_SERVICE_EVIDENCE to their bundle, then run verification once.
fastlane verify_beta candidate:.codex-artifacts/release/candidate.json

# Archive the unchanged candidate without repeating successful gates.
fastlane archive_beta candidate:.codex-artifacts/release/candidate.json

# Authorized TestFlight upload: pinned IPA, wait for processing, internal only.
fastlane upload_beta candidate:.codex-artifacts/release/candidate.json

# Compose/resume these stages; an unchanged verified candidate is not retested.
fastlane beta candidate:.codex-artifacts/release/candidate.json
```

The explicit number above is illustrative; reserve one that is newer than the
actual App Store Connect build. All Xcode targets must have the assigned number
before the fingerprint is captured. Archive signing uses the project's automatic
signing and existing team, with provisioning updates allowed; it does not create
or change credentials through this helper.

`verify_beta` retries a failed/blocked check on an unchanged prepared receipt.
Changed candidate inputs require a new receipt. Relevant unchanged local proof
can be reused across receipts; all reused logs are pinned and recorded. Release
checks include secrets, migration hygiene, required edge/import/recovery paths,
SQL transaction/authorization assertions, packages, native tests, architecture
and current-state docs. The native test command builds its test host, so a
separate `ios-build` would duplicate work; the later signed archive is necessary
artifact production. Native verification precedes SQL execution, so blocked
native access does not start another fixture run. The final SQL profile selects
these exact required cases through the existing runner's `--only` argument:

- Import transactions/receipts/counts: `70_import_apply_undo_transactions`,
  `81_import_session_receipt`, `81_library_import_counts`.
- Home/tracking/recovery: `80_series_home_foundation`, `92_series_progress_race`,
  `93_series_fence_races`, `94_series_home_review_repairs`.
- Flags, producer privacy and account lifecycle: `95_feature_flag_overrides`,
  `95_series_producers_disclosure`, `96_series_account_lifecycle`,
  `96_series_enrichment_backfill_races`.
- Existing deletion/club protections: `51_account_deletion_barrier`,
  `64_club_privacy_aggregates`, `65_club_membership_lifecycle`,
  `90_deletion_write_barrier`, `91_club_lifecycle_join_race`.

Every required filename must exist unambiguously. The selector, selected source,
fixture helpers, migrations and PostgreSQL tools are pinned in the check identity.
All prepared migrations still must apply. Missing selected prerequisites, failed
assertions and zero executions cannot pass. The other historical fixture cases
remain available in the broad diagnostic. Existing 253-assertion scoped evidence
is retained as actual local proof; it is not retroactively labeled a whole
candidate execution. Parser/router corpus cases run once in an affected edge
suite, without separately rerunning the corpus/router wrappers. The curated
rails audit runs only for a changed audit or curated-rails SQL input and is never
cached because its dataset is live.

Edge selection always retains Apply, Undo, deletion, AniList import and shared
safety/recovery tests. Actual changed production directories and consumers of
changed relative-import dependencies are added. Changed corpus fixtures add
parser/recommendation consumers. Empty/invalid selections or zero executed tests
fail; source without tests gets a separate entrypoint typecheck and no behavioral
proof claim. Comparison uses the complete dirty checkout against HEAD, including
untracked dependencies. Do not commit away an unqualified delta merely to shrink
the selection: retain its reviewed baseline/evidence when preparing the candidate.

Skipping mandatory release checks or substituting partial proof is forbidden.
Live/admin evidence is mandatory at this final qualification stage, not during
development. A failed or blocked required check cannot advance the receipt. Source drift during checks or archive,
changed verification logs, wrong bundle/build and replaced IPA files block
continuation. Tests/archives use the current checkout, so do not edit production
inputs concurrently with these stages.

Measured latency/payload percentiles are observations and investigation signals,
not arbitrary shipping vetoes. Investigate misses and retain dataset/sample/error
context. A reproducible user-path failure, unsafe behavior, runaway query/provider
fan-out or severe degraded experience still blocks qualification.

The recorded states are `prepared`, `verified`, `archived`, `processed`.
`processed` explicitly retains `installed_native_qualification: PENDING`.
App Store Connect processing success does not demonstrate that testers can
install or that the native/live journeys pass. Record those separately in the
release evidence. Exact installed-artifact proof must cover the six approved
journeys, advertised Anime/Manga imports including MAL account OAuth and MAL file,
account isolation, durable recovery, club revocation and account/Storage deletion.
Local receipts, typechecks or simulator tests cannot replace that evidence. If upload succeeds but the process is interrupted before the
receipt advances, inspect ASC for this exact version/build before retrying;
do not upload a different IPA under that receipt.

Local regression checks (no signing, network, upload or whole-repo gates):

```bash
ruby fastlane/release_candidate_test.rb
python3 fastlane/test_ios_unit_runner.py
ruby -c fastlane/Fastfile
```

`KURO_GIT` can select an existing Git executable when the system Git is
unavailable. It does not accept the Xcode license or bypass a build requirement.

The standard native unit gate resolves the actual available iPhone 17 Pro UUID,
records every run in a unique result directory, and requires executed passing
test method paths as well as a successful `xcodebuild` exit. An empty selection
cannot produce a release verification receipt. This runner qualification is
tested with offline tool doubles; it is not native execution evidence.

## Local SQL and real service evidence

The SQL fixture now uses `tests.requires_live` for exactly four separate
requirements: effective deployed `user_lists`, Storage account cleanup, GoTrue
account deletion and actual Realtime delivery. These are reported as **LIVE
REQUIRED**, never passing assertions. Missing `taste_tag_stats`, the latest
deletion RPC body, dblink or any other SQL prerequisite remains **BLOCKED**.
Failed SQL assertions/prepared migrations and zero executed SQL assertions fail.

`verify_beta` includes a mandatory `live-services` gate; the broad diagnostic also reports it. No supplied evidence is
exit 4/BLOCKED at release qualification; development checks stay usable. Partial
release verification cannot become an archive receipt.
The gate reads files only; running it does not authorize or trigger live writes.
Collect live reports after freezing, avoiding a repeated integrated test run just
to obtain the candidate fingerprint. `prepare_beta` remains a convenience when
evidence is already ready; `freeze_beta` followed by `verify_beta` is the normal
ordered flow. Missing the evidence environment variable refuses verification
before running the expensive gates.

The `KURO_LIVE_SERVICE_EVIDENCE` file has this structure (all paths relative to
the bundle; replace placeholders with real sanitized outputs):

```json
{
  "schema": 1,
  "candidate_sha256": "<frozen snapshot sha256>",
  "deployment": {"path": "deployment.json", "sha256": "<file sha256>"},
  "reports": {
    "journal": {"path": "journal.json", "sha256": "<file sha256>"},
    "realtime": {"path": "realtime.json", "sha256": "<file sha256>"},
    "auth_api": {"path": "auth-api.json", "sha256": "<file sha256>"},
    "account_storage": {"path": "account-storage.json", "sha256": "<file sha256>"}
  }
}
```

The deployment report records `project_ref`, matching `candidate_sha256`, a fresh
`observed_at`, effective `migrations`/`functions`, and `effective_user_lists`
(`reloptions`, `authenticated_grants`, `anon_grants`). The journal and Realtime
reports use the actual existing disposable probe outputs. Every report requires
the exact live target, fresh timestamped run identity, bounded disposable account
inventory and correlated successful cleanup. Revisions alone cannot prove
Realtime delivery. Old reports cannot qualify a newly frozen candidate.
The four report producers enforce at most five accounts, five in-flight
requests, five request starts per second and 1,000 requests per separate run.
The bundle aggregates four distinct run IDs/cohorts (two journal, three
Realtime, two Auth/API and one Storage account), not a single eight-account
qualification run. Execute probes sequentially to preserve aggregate bounds.

Auth/API evidence includes sanitized `authResponses` for signup, passwordSignin,
refresh, restoredUser and a different outsiderSession, each with HTTP status and
returned user identity. `apiResponses` records ownerProfile, anonymousProfile,
outsiderUpdate (including its actorUserId), ownerBefore/ownerAfter rows, and a
structuredError with the real `details`/code response. Empty rows after a server
error or unauthenticated outsider request do not qualify isolation.

Storage evidence includes `storageResponses` for deleteAccount, overlappingUpload,
oldTokenUpload, deletedUserRead, adminAuthRead, adminObjects and originReads keyed
by each recorded disposable object path. Preserve actual HTTP statuses, deletion
response, operation start/end timestamps and the shared original token's SHA-256
(never the credential). Scope administrative verification to the exact user and
`media` prefix. The overlap must be real; old-token upload is attempted after
deletion. Physical absence and each origin response are required.

Actual Auth/API and Storage emitters are `scripts/live/probe_auth_api.js` and
`scripts/live/probe_account_storage.js`; see `scripts/live/README.md`. They require
administrative Auth/media access before creation, retain sanitized actual HTTP
traces and verify physical cleanup. These emitters have only been tested offline
here. Real deployment/protocol qualification remains BLOCKED until actually run.

The validator correlates signup/restored identities, scoped responses, actual
Apply/Undo, signal payloads/subscriber filters, a publicly readable seed image,
same-credential deletion/overlapping and post-deletion upload, and exact
administrative/origin absence responses. Overlap uses monotonic nanoseconds
alongside wall-clock timestamps; equal millisecond timestamps are not a failure.
Anonymous 200-empty or explicit authorization refusal is accepted. Storage may
return HTTP 400 carrying `statusCode` 401/403 or SQL 42501; arbitrary 400/500 is not
denial proof. Credentials, passwords and full customer listings are excluded.

A Markdown summary or metadata-only PASS cannot substitute. Evidence digests are
pinned before gates, checked unchanged afterward and retained in the receipt.
They are checked again before archive/upload, preventing evidence replacement.

## Intended backend inventory

Before freezing, create a reviewed `fastlane/backend_release_manifest.json`
from the actual intended deployment set (or use `KURO_BACKEND_RELEASE_MANIFEST`
for another file within the frozen input allowlist). No approved manifest is
supplied by this local implementation. Its absence is BLOCKED, not a waiver.
The structure below is only a template:

```json
{
  "schema": 1,
  "project_ref": "bkdifromsqxkndnllmdj",
  "migrations": [
    {"id": "<intended migration ID>", "path": "supabase/prepared-migrations/<file>.sql", "sha256": "<reviewed source hash>"}
  ],
  "functions": {
    "delete-account": {"files": [{"path": "supabase/functions/delete-account/index.ts", "sha256": "<source hash>"}]},
    "concierge-apply": {"files": [{"path": "supabase/functions/concierge-apply/index.ts", "sha256": "<source hash>"}]},
    "concierge-undo": {"files": [{"path": "supabase/functions/concierge-undo/index.ts", "sha256": "<source hash>"}]}
  }
}
```

Include every intended function and its complete local import dependency closure,
including shared modules. The manifest itself and all its source hashes must be
frozen candidate inputs. This is an explicit intended subset; unrelated prepared
migrations need not be deployed. The observed deployment report must contain
matching migration `{id, sha256}` records and function `{version, files}` records
with matching file hashes. An unrelated function version or a candidate label
alone cannot qualify the backend. Migration ID presence does not prove a source
checksum; preserve the reviewed deployment receipt/provenance and inspect actual
effective schema, grants and policies through management access. This helper
does not manufacture a deployment receipt or inspect/deploy the live project.

Offline enforcement checks:

```bash
python3 fastlane/test_live_service_evidence.py
```
