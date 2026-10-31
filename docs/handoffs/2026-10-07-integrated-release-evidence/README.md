# Integrated continuation evidence — not release qualification

This index records the source/local work on `codex/integrated-testflight`. The full executor/checklist is [the integrated document](../2026-10-07-integrated-testflight-execution.md). [source-checkpoint.json](source-checkpoint.json) hashes current production inputs and this evidence; it is **not a build-number freeze, gate receipt, artifact or deployed identity**. There is no IPA/TestFlight artifact. Debug simulator installation and onboarding launch are now verified; private workflows are not qualified by that launch. Implementation-stage proof is recorded below. Final delivery gates are NOT DUE during implementation and remain unqualified; Safety/Integration are in progress. No future-stage requirement is waived.

| Evidence | What actually ran / was reviewed | Limit |
| --- | --- | --- |
| actual-library-home-sqlite-pass.log | Actual compiled Library/Home/outbox/SQLite owner path;100overlapping taps, committed response loss/immutable retry/successor ACK, exact cursor/label/lifecycle/account isolation, coherent protected personal offline cache, deletion late-write fence | Injected transport on macOS; not mounted iOS/live services |
| actual-concierge-lifetime-pass.log | Actual Swift helper: account change, new chat and disappearance reject old tickets/results | Three focused owner cases; not mounted view/SDK behavior |
| actual-provider-url-policy-pass.log | Actual production URL function body compiled verbatim with Foundation; explicit non-HTTP schemes rejected, valid host/HTTP(S)/IDNA retained | Bare host:port now requires explicit HTTP(S) scheme; not corpus/native link opening |
| retrieval-contract-pass.log | Two Deno repository cases: medium collision, malformed confidence/fractional identity | Controlled repository; flag remains disabled; no deployed source identity |
| backend-focused-repairs.log | Chapter8/deletion22/recommendation9 cases; affected chapter rerun after mapping/alias reads changed; relevant unchanged cases reused. Final module type checks and independent changed-boundary source review | No real database, Apple/Groq or deployed behavior. Earlier historical probes explicitly labelled |
| release-offline-checks.log | Current stage/release policy: Ruby16tests73assertions; previous producer tests retained: Python evidence/SQL-partition9; native runner5;20distinct Node probe cases. Affected12legacy probe cases rerun after bound enforcement, unchanged8reused | Producers/validators and process tests offline; no qualification requests |
| architecture-local-pass.log | Existing representative ownership scanner: retired facade/SDK/view/tracking writer/package boundaries | Source text checks, not full semantic/compiled dependency graph |
| docs-local-pass.log | Existing inventory/docs check:151app Swift/24package Swift/245migration files | Documentation consistency only |
| swift-syntax-only.log | Direct Swift frontend parse of207 app/package/test files; plist lint also passed | Parse is not type checking, native execution, build or SDK acceptance |
| focused-source-acceptance.md | Independent acceptance of changed high-risk identity/cache/lifetime/import/release/backend/privacy boundaries | Not independent acceptance of every untouched finding or the whole release |
| prerequisites-blocked.json | Read-only current tool/access presence checks; no credentials output | Xcode27.0 first launch now passes; paired iPhone and signing identities present. Existing ASC key returns agreement403; old pipeline key absent. Management/admin and approved manifest still unavailable |

| stage-account-actions-pass.log | Actual KuroCore AccountActionScope through Swift Testing:2 tests/3 cases; queued account/remount/foreign-scope admission and canceled late reply | macOS SDK-free owner; not mounted native UI |
| stage-collection-batch-pass.log | Actual Collection batch policy with A→B transition preserves B deferral/filter/refresh and stops A writes | Injected recorder/owner shell; not SDK or native screen |
| stage-mal-reader-pass.log | Actual production LibraryImportBatch/MALAccountList reader mapping, namespace, unavailable fields, safe pagination/limits, independent cursors | Host harness; no provider credentials/OAuth/live requests |
| stage-sql-summary.json + stage-sql/ | Private PG17.10:ten affected suites/253 assertions PASS; all12prepared SQL apply; one Home query sample | Not full historical replay, final16suite gate, real services or p95/capacity |

| stage-development-pass.log | Actual new development runner:architecture and docs PASS with current151app/24package/245migration inventory | Selected source/local scope; no release receipt or delivery access |

| xcode-unblocked-packages-pass.log | Actual SwiftPM package execution:12+60+9 Swift Testing cases,81 PASS | Current packages only; not iOS SDK or installed qualification |
| xcode-unblocked-native-initial-fail.log | Actual native compiler reports missing KuroCore import in MAL stream; no tests executed | Repaired explicit import; rerun separate, initial failure retained |

Logs preserve completed actual output; where transcribed, they say so and do not imply a second execution. Changed source invalidates affected evidence; retain unaffected relevant checks rather than repeating all suites. The snapshot carries evidence hashes, production-input path/mode/content hashes, dirty summary and current HEAD/branch. Earlier peer SQL/package/enrichment logs are historical when source changed.

## Reproduction and continuation

- MAL reader: compile actual `LibraryImportBatch.swift` and `MALAccountList.swift` with the recorded host smoke source; no browser consent/provider traffic. Core admission cases live in `Packages/KuroModules/Tests/KuroCoreTests/AccountSessionTests.swift`; the preserved log ran its two action-scope tests with actual KuroCore.
- Library/Home drain: bundled Python `scripts/test_home_repair_drain.py`; use actual configured Swift compiler/SDK and explicit module cache as recorded by the harness. No SDK/GoTrue/Storage/PostgREST/Realtime qualification is inferred.
- Backend: `deno test --frozen --cached-only --no-prompt supabase/functions/manga-chapter-enrich/run_test.ts supabase/functions/delete-account/handler_test.ts supabase/functions/concierge-recommend/handler_test.ts`; run only affected modules during edits. Final frozen integrated set still required.
- Release offline reproduction commands are recorded in release-offline-checks.log; native/gate failure detectors must not be confused with their unavailable production test leg.
- Packages now pass81tests and Xcode is available. Native SDK fixtures are being repaired; exact installed TestFlight iPhone proof remains due. Private local PostgreSQL qualification succeeded without touching foreign IPC/servers; historical baseline replay remains incomplete and final selected SQL profile is separate.
- Live runbook `scripts/live/README.md` requires secure management/admin preflight, exact reviewed deployment and source/bundle identities, separate sequential cohorts and administrative physical cleanup. No blanket migration push. MAL account ingestion is implemented and locally source-reviewed; registration/controlled consent cannot be replaced with XML.
- Prepare metadata is `docs/app-store-metadata.md`, marked DRAFT/NOT SUBMITTED. Effective vendor retention, policy URL, archive SDK/privacy report and final Connect answers remain open.

No backend deployment, new hosted writes, archive, upload, installation or public submission occurred in this continuation. The previous5October deployed Storage v9 evidence remains historical acceptance of that deployed version; final integrated deletion races require fresh qualification.

| native-unblocked-initial-summary.json | Actual simulator SDK host:104PASS,284failures with one identical host crash; independent diagnosis identified missing LibraryActions in snapshot roots | Failed run; not284independent assertion defects. Compiler errors and fixture dependency repaired; rerun pending |
| native-snapshot-method-filter-zero-tests.json | Xcode method filter exited0 with zero tests | Explicitly rejected as acceptance; existing suite rerun required |

| native-snapshot-suite-repair-pass.log + .json | Actual iPhone17Pro simulator:all5existing Home composition cases PASS, including both populated Home and detail render cases after LibraryActions injection | Fixture rendering/contract proof, not physical design acceptance or live/installed artifact proof |

| native-lease-fixture-repair-pass.log + .json | Actual simulator:3exact SwiftTesting identifiers PASS (warmup/feedback wire shape, account-transition cancellation, same-account revocation/next current read) | Independent fixture repairs retain assertions; no live/installed proof |
| native-broad-run-interrupted.log + .json | Actual broader run observed two outdated fixture failures, then stalled/unfinalized after logged host exit; own runner bounded and evidence retained | No finalized count or whole-native PASS; exact affected3case rerun separately passes |

| simulator-only-install-receipt.json + simulator-only-build-pass.log + simulator-only-installed.png | Actual Xcode Debug 1.0 (17) build, install and launch on iPhone 17 Pro / iOS 26.0; onboarding visually verified | Current owner target is simulator only. No signed-in/private workflow, TestFlight or physical delivery proof |
| simulator-live-readonly-audit.json | Actual browser-administrative live metadata/aggregate audit; two bounded read-only queries, both-media casing/collision counts 0, exact owner policies; six Home RPCs/flag rows/override table absent; 16 Edge slugs | UI results transcribed; no writer RPC/version pin, customer changes, deployment, Auth/Storage/Realtime or performance qualification |

| simulator-auth-import-recovery-receipt.json + simulator-auth-repaired-pass.json/log | 19 actual native SDK cases PASS after independently accepted fixture isolation | Controlled HTTP and actual per-test SQLite/WAL; not live native UI or whole-suite proof |
| simulator-auth-import-initial-fail.json/log | First run 21 PASS / 4 FAIL, with all 6 import outcome cases passing | Original failures preserved; owned stalled diagnostics collector stopped, result finalized |
| simulator-home-import-preflight.json + simulator-home-import-deployment-DRAFT.json | Actual read-only live contract/history/signature preflight and reviewed two-migration input pin | Prepared, not deployed; explicit production-grant confirmation and real simulator login pending |


## Latest simulator integration qualification

| Evidence | Result | Boundary |
| --- | --- | --- |
| simulator-native-reconciled.json plus finalized runs |362 distinct remaining native cases PASS using unaffected initial evidence and affected24/9case reruns; previous19SDK/6import cases retained,387distinct native cases total | Real Xcode/SDK/SQLite controlled HTTP; not signed-in live UI. Initial359/3fail and interrupted clone-start run retained. |
| simulator-backend-imports.log |4suites/52tests PASS and affected entrypoints typecheck | Existing offline handler/limiter/provider fixtures; unchanged deletion22/chapter8/recommendation9 remain separate accepted evidence. |
| simulator-sql-missing.log and simulator-sql-missing/ |6missing selected suites/258assertions PASS; combined with unchanged10/253,16distinct suites/511assertions | Disposable socket-only PG17.10; all12prepared apply; historical replay remains incomplete; no Supabase services inferred. |
| simulator-atomic-rehearsal-result.log and simulator-home-import-atomic-DRAFT.sql | Exact pinned transaction/history bytes applied to candidate-excluded disposable fixture;31assertions PASS, including original history/list data and reused import/deletion behavior | Source independently accepted; not a live clone or deployment. Existing20RLS/flags/digest guards run within transaction. |
| simulator-home-import-preflight.json | All20newtables absent,31existing prerequisites present, candidate history/14metadata columns absent, orphan rows0; fresh deletion helper semantic/hash/ACL review and history shape | Actual5secondbounded read-only live browser SQL; older different hash retained as historical; no mutation. |
| simulator-latest-install-receipt.json + simulator-latest-sign-in.png | Latest Debug1.0(17) install0/launch0; complete bundle hashes; actual native sign-in form visible | No account entered and no live Home/import journey passed. No archive/upload/TestFlight. |

Four existing test sources changed; independent review accepted actual credential installation, post-bootstrap request accounting, confirmed Home activation, immediate private cache purge before reauthorization and successful progress without notification/read fan-out. No production guard was weakened. SQL assembly installs server-wide list/catalogue/disclosure triggers and compatible contracts when approved, even with global Home flags disabled; client delivery remains simulator only.

Pending dependencies: real simulator sign-in, action-time confirmation of exact live production permissions/migration delta, and user-owned MAL registration/public client ID/consent. Then qualify hosted/installed Home, both-provider/both-medium imports, recovery, privacy, cleanup and normal-use performance. Local passes do not close those dependencies.
