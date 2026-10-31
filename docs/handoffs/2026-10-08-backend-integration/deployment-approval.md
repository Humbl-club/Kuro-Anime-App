# Reviewed live deployment — approved and applied

Target: Kuro `bkdifromsqxkndnllmdj`, eu-central-1. Client delivery remains the simulator. The user approved this exact set. The SQL transaction and six named closures are deployed; effective postflight is verified. The hashes below remain the original approved inputs. Hosted and installed journey qualification is separate.

## Exact SQL transaction

[Atomic candidate](backend-atomic-DRAFT.sql): SHA256 `ca18fb6931c3afac3f8eec9fe85e0de9c9a903132780dbdb2448cf62a3a11fd8`, 662,555 bytes. Execute once, in one transaction, after rechecking live prerequisites and source hashes.

| New migration identity | Purpose | SHA256 |
|---|---|---|
| 20261007040000 | Additive Library revision/series/Home foundation and compatible readers/writers | `9803ed3ec24a10d5e80a4388835c09f5a0eda8f2a2ca2095f77b91cb7cf1d651` |
| 20261007130000 | Authenticated account lifecycle and deletion coordination | `8cfb01f295f013dc2562b8a8f74ce865ffe7fe9c5bae071b7f15617d5f73b777` |
| 20261008100000 | Preserve precise units and lifecycle-safe legacy Apply/Undo | `af22886f86a23d7e5314f49de59b63185a28b3c5b47c98a4f84f2a00b7f4eccd` |
| 20261008110000 | Staged review, explicit approvals, immutable replay, results, stop and guarded structured Undo | `552fcafe1e98d98ce9ec23e59c627f3ccfdbd3261517e4cff74c86a472cd2e6d` |

Original source text is recorded under each new migration identity. Existing migration statements/checksums remain intact. The transaction checks prerequisite identities, locks the two tracking tables with bounded waits, verifies their legacy values remain unchanged, verifies RLS and disabled Home flags, then reloads PostgREST. Any failure rolls back the transaction.

## Six named Edge deployments

Deploy only `concierge-import-anilist`, `concierge-apply`, `concierge-undo`, `delete-account`, `concierge-recommend`, and `concierge-retrieve-assist`. Preserve JWT verification. The [manifest](backend-deployment-DRAFT.json) pins every runtime closure file; current deployed identities are in [the read-only preflight](live-functions-v2-preflight.txt). Their previously accepted source is unchanged.

These repair structured AniList pages, compatible legacy retry/error contracts, deletion acknowledgment, recommendation medium identity and retrieved-candidate checks. No unrelated function pruning or worker activation is authorized by this set.

## Customer impact and recovery

- Existing production clients receive compatible tracking revision/deletion triggers, legacy Apply/Undo repairs and club/social authorization changes. Simulator-only client delivery does not make the backend changes simulator-only.
- Additive tables/columns preserve customer tracking values. New import jobs default to Keep; explicit updates compare reviewed revision/lifecycle. Stop preserves committed titles. Undo skips later edits/replacements.
- Terminal-job maintenance retains ten detailed results/Undo histories per account. Older summaries/provenance remain and explicitly report unavailable detail/Undo. No scheduler is added.
- Global Home flags remain disabled at 0%. Existing RAG rollout stays unchanged. No historical catalog backfill, deletion-barrier cron, provider-worker scheduling or TestFlight operation.
- Disable the local simulator feature overrides to return to current navigation. Keep added data, receipts and pending actions. Server corrections use a reviewed forward repair; do not drop customer data or replay an already-recorded migration.

## Verification before and after approval

Independent review accepted the exact SQL and execution/history assembly. [Exact disposable rehearsal](import-v2-atomic-rehearsal-summary.json) passed 265 assertions, including populated readers, compatibility, account lifecycle and v2 policy/replay/Undo. This is PostgreSQL fixture evidence; historical replay is incomplete and hosted services are unqualified.

After approval: recheck live identities, apply the exact transaction, deploy the six pinned closures, verify effective signatures/grants/RLS, then enable local simulator overrides and exercise the included real workflows. Bounded live checks use recorded disposable resources, at most five accounts/concurrent requests/requests per second and 1,000 API requests per run. Verify cleanup administratively. Controlled MAL consent remains a separate native/provider proof.

**Approved deployment completed:** four migration identities are recorded, original source hashes unchanged. Edge identities: AniList6, Apply27, Undo18, delete-account10, recommend50, retrieve-assist9. See [SQL receipt](approved-sql-deployment-receipt.json), [effective SQL](approved-deployment-postflight.json), [effective v2 grants](approved-import-v2-effective-grants.json) and [Edge postflight](approved-functions-postflight.json). No broader deployment or global rollout occurred.
