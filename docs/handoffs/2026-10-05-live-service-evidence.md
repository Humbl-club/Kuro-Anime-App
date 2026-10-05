# Live service checks — 2026-10-05

Project: `bkdifromsqxkndnllmdj` (AniThing is Possible, eu-central-1, ACTIVE_HEALTHY). URL `https://bkdifromsqxkndnllmdj.supabase.co`. GoTrue `v2.197.0`. These results are LIVE-DEPLOYED proof of what is running now. They do not prove the undeployed candidate source.

No migrations or functions were deployed. No policies, buckets, or credentials were changed. No existing customer account was used.

## Deployed baseline

- `supabase migration list --linked` shows the remote chain through `20260810120000`. The prepared files under `supabase/prepared-migrations/`, including the deletion barrier and `20261005160000_club_realtime_signals.sql`, are not in that chain.
- `delete-account` is deployed as version 8, updated 2026-02-24. The local `deletion.ts` storage purge is not that deployed bundle. Candidate deletion and storage-barrier proof is BLOCKED-BY-DEPLOYMENT.
- Supabase MCP was not available. Schema grants were not queried. Permissions below are from user-session HTTP calls, not the service role.

## Accounts created and deleted

Runs `kuro-live-20261005T200551` and `kuro-live-r2-20261005T200651`. Each account was created with sign-up and removed only through `POST /functions/v1/delete-account` with `{ "confirm": "true" }`. All eight returned `success: true`.

## F44 — LIVE-PARTIAL

- Sign-up returned a session (`mailer_autoconfirm` true). Password sign-in returned the same user. Refresh returned the same user.
- The signed-in user upserted and read their own `profiles` row.
- An anonymous read of that row returned no rows. Another user's PATCH changed nothing; the owner still saw `adult_opt_in: false`.
- A missing RPC returned HTTP 404 with keys `code`, `details`, `hint`, `message` (`PGRST202`). The live body uses `details`. The Swift decoder reads `detail`.
- The iOS app was not driven. That portion stays open.

## F45 — LIVE-FAIL for storage objects

- Owner `image/jpeg` upload to `media/<user id>/…jpg` returned 200 and was publicly readable.
- Another user's upload into that folder returned `AccessDenied` / row-level security.
- `text/plain` is rejected (`InvalidMimeType`). That was a probe mistake, not a product change.
- The deployed delete function returned success. `GET /auth/v1/user` with the old token then returned 403, and password sign-in returned invalid credentials.
- The JPEG was still publicly readable after that success. The deployed function does not leave the auth user in place, and it does leave the media object in place.

## F88 — LIVE-FAIL

- A JPEG body was still uploading when delete-account was called. The upload and the delete both returned 200. The raced object is still public.
- After deletion returned, a second JPEG upload with the same token also returned 200 and is still public. `GET /auth/v1/user` was already 403.
- This is not a pass, and it is not inconclusive: the upload after deletion was sequential and succeeded.

## Realtime — LIVE-PARTIAL

- Member of disposable club `25856d37-c224-46a1-a6f0-9fa9337b2801`: join ok, then `postgres_changes` for `club_polls` filtered by that club.
- Nonmember, and the member after `leave_club`: join ok, no `postgres_changes`.
- Subscriptions were filtered. An unfiltered listen was not opened.
- `club_activity_signals` accepted a join and delivered no event. Whether that table is published stays unproven. The legacy poll subscription is the one that delivered.
- Native channel teardown and account switching were not run.

## Cleanup

Auth users from both runs were deleted through the application function.

These objects are still publicly readable. This run had no service-role credential, and another user's token cannot delete them. Cleanup failed for these three paths only:

- `media/5b0f1230-deb3-417c-a84d-49a2a48409e9/kuro-live-r2-20261005T200651.jpg`
- `media/cbf426d5-f475-4efb-adaf-281a7a198e66/kuro-live-r2-20261005T200651-race.jpg`
- `media/cbf426d5-f475-4efb-adaf-281a7a198e66/kuro-live-r2-20261005T200651-after.jpg`

## Follow-up after deploying the barrier (same day)

Applied `20261005140000` and `20261005150000`. Deployed `delete-account` version 9 at 2026-10-05 20:16:44 UTC. The media insert and update policies now call `account_deletion_storage_guard()`, which takes the same per-user advisory lock as the table barrier and rejects the write once a barrier row exists.

A new disposable account uploaded a JPEG (public 200), then `delete-account` returned success while a second JPEG was still uploading. GoTrue then returned 403. A cache-busted public read of the original file, the raced file, and a follow-up upload all returned 400. The follow-up upload body was `ACCOUNT_DELETION_IN_PROGRESS`. `storage ls` of that user prefix was empty. The in-flight upload's own HTTP response was 200, and the object was not present afterward.

The three earlier orphan JPEGs were removed with `supabase storage rm` of those exact paths. Cache-busted reads now return 400, and both prefixes list empty.

The two disposable clubs from the earlier run were not deleted. Their owners were already gone, and a non-member read cannot prove the rows are absent. They were not part of a broader delete.

Apply/Undo SQL, the realtime signal cutover, and a native App Store release are not part of this deploy. The migration is not complete.
