# Approved recommendation fan-out repair — deployed and warmed workload qualified

Deployed after explicit owner approval on 9 November 2026 as `concierge-recommend` v55. All eight downloaded repository source entries match the reviewed hashes; JWT verification remains enabled, and all other function versions/JWT settings and the selected Auth settings are unchanged. Receipt: `recommend-fanout-deployment-receipt.json`. The full unchanged wired R15 sequence passed16,500/16,500 requests, zero errors/missed starts, all endpoint/library/media gates, background/isolation/cleanup checks and final production readback. Cold-call limits remain unqualified. See [final measured results](REPORT.md).

Changed runtime file: `supabase/functions/concierge-recommend/catalog_repository.ts`.
SHA-256: `49b88d972cec80199a86ef58bca6cf0f17fb5d77300d50af918484c9ad7af92b`.
Exact eight-file runtime closure: `recommend-fanout-deployment-manifest.json`; seven dependencies match the earlier reviewed/deployed manifest unchanged. The pre-deployment v54 source was freshly read back and matched the saved verified bundle; production is now v55.

The wired R13 ten-minute stage completed12,000/12,000 requests, zero errors or missed starts, overall p95109.18ms. It still correctly failed: the2,000-title subgroup had three recommendation requests, one2,614.42ms (2,586ms upstream), above the2,500ms target. No burst or recovery followed. All previous failures, including the first834.55ms cold Search call, remain retained. No limit is being relaxed.

The handler builds a primary rail and up to five secondary candidates. Several can issue `recommend_ids_premium` with identical media/category/gimmick/focus/limit parameters. They are separate expensive catalogue queries even within one authenticated request. The repair shares successful identical candidate reads only inside that request's repository instance, including in-flight work. Each rail still applies its own quality/genre/diversification rules and receives independent returned arrays/rows.

Safety and behavior:

- The repository factory is created per verified request/caller; no global or cross-request cache, TTL, user data retention, role change or shared budget client.
- All normalized RPC arguments participate in the cache key. Media types and distinct filters remain separate; nullable/empty filter normalization matches the existing RPC call.
- Failed reads are removed. A secondary consumer retains its independent attempt if another rail's shared attempt fails; upstream attempts never exceed the former independent-call count. Primary failure handling remains unchanged.
- No query ranking, mode selection, response schema, RLS, Auth, provider credential, narration, rate limit, database schema or compute-plan change. The hydration reads are deliberately unchanged, including their existing degraded-error behavior.

Verification:26 focused handler/repository/router/corpus tests pass, including five new concurrency/key/caller/failure/mutation-isolation tests. The existing no-duplicate-fallback test still checks each rail's independent hydration rather than confusing query reuse with a skipped rail. Type checks pass.36 complete before/after handler responses match exactly against the saved source-only baseline and frozen current public mode configuration, covering six prompts, three scopes and empty/2,000-title libraries. These are offline contract results, not live capacity proof.

Premium RPC calls across those36 comparisons fall276→120. For the actual failing prompt/scope/library class (`premium action anime`, anime,2,000 titles), the synthetic frozen-response case falls6→1 with an identical full response. Artifacts: `recommend-fanout-tests.log`, `recommend-fanout-parity.ts`, `recommend-fanout-parity.json`, `recommend-fanout-baseline.json`.

All four previous cohorts are independently cleaned:400Auth identities and20clubs removed through the app route,41 user-bearing base-table checks per cohort empty except existing seven-day deletion barriers. That was the preparation checkpoint. After approval a fresh fifth100-account cohort was created, independently counted and smoke-tested; R14/R15 measurements and final cleanup are recorded in REPORT.md.

Reviewed deployment/retest sequence (completed as recorded in the receipts): recheck the exact closure hashes, current deployed source/version and JWT policy; save the current bundle privately for recovery; deploy only this slug; read back version/JWT/source entries; test ordinary authenticated responses; rerun the unchanged complete wired5rps gate,20rps ten-minute soak,40rps burst and20rps recovery with real fixture backlog and safety observers. Retain all original failures and independently verify final cleanup. This code-level reduction is not a guarantee that the complete target will pass.

Recovery: restore only the prior approved function closure if live behavior regresses, preserving JWT verification, environment, database security fixes and pool cap. Never revert unrelated source, weaken thresholds or conceal failed runs.

Explicit owner approval was received before deployment, as required by the user-supplied AGENTS guidance: “Ask before destructive actions, external communication, credential changes, deployments, or material scope expansion.” The user separately approved this new Edge Function deployment; the two-index approval was not reused as authority.
