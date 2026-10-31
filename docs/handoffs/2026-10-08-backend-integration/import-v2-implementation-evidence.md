# Import / Library / Home implementation evidence — 8 October 2026

**The exact approved backend is deployed; actual restored Home is visible. Full simulator/provider qualification remains incomplete.** See [fresh deployment/live/native evidence](approved-deployment-live-evidence.md). No TestFlight or global Home activation.

## What changed

Both waves use the existing Imports, Library, Catalog, Home, Collection, Releases and Identity owners. AniList and MAL account/XML converge on typed canonical pages and staged review. Existing titles default to Keep; explicit selected-field decisions retain target/revision/lifecycle baselines. SQL enforces coupled progress/score values, missing-field preservation, canonical provider identity, no-op revisions, atomic chunk receipts/counters and guarded compensation.

Protected account manifests retain immutable input and approvals, recover uncertain starts/application/Undo and discover jobs from Home/Profile. Stop keeps committed titles. Results are owner-paged and persistent; imported-title navigation filters the authoritative Collection. Latest ten terminal jobs retain detail/Undo, older provenance summaries disclose unavailable history. Crash-safe terminal retirement preserves unready Library refreshes and cleans only attributed account data in bounded passes.

Apply/Resume/Undo share Library's existing affected-key FIFO. The final regression specifically proves post-review durable progress blocks Apply and Resume before any apply/finish RPC, keeps the original local intent and immutable decision, and resumes after acknowledgment. No extra queue/framework or SQL was introduced for that repair.

## Verification and exact candidate

- Exact four-input PostgreSQL rehearsal: **265 assertions PASS**; [summary](import-v2-atomic-rehearsal-summary.json). Original historical replay remains incomplete. This fixture does not run GoTrue, Storage, PostgREST or Realtime.
- Integrated package baseline: **95 tests PASS**; log `/private/tmp/kuro-import-v2-package-final-reviewed.log`. Two final affected generic-reservation regressions PASS; `/private/tmp/kuro-import-mutation-reservation.log`.
- Native r5 compatibility/integration: **41 distinct methods / 54 executions PASS**, no failures/skips; source/config/dependency inputs unchanged. `/private/tmp/kuro-import-workflow-integration-20261008-r5/FinalImports.xcresult`.
- Final affected r6: **14/14 methods PASS** (eleven actual SDK/SQLite workflows and three publication cases), no failures/skips. [Summary](import-v2-native-final-summary.json); `/private/tmp/kuro-import-workflow-integration-20261008-r6/MutationGuard.xcresult`. All **222 candidate inputs** unchanged before/after; [source pin](import-v2-simulator-source-pin.json). Unchanged broad suites were not repeated.
- Focused changed-source acceptance: [pinned review](import-v2-source-review.json). SQL, authentication/account guards, journal recovery, application, compensation and deployment assembly received independent review.
- Installed **com.Kuro.app 1.0 (17), Debug, iPhone17Pro Kuro Qualification / iOS26.0**: [install receipt](import-v2-simulator-install-receipt.json), [build identity](import-v2-built-app-identity.json). Every installed bundle file matches the tested bundle. Bundle tree SHA256 `dd5304ded6b5ebb2d8a62e36c35ff80ed08367b00d5e719648c1ae18964079df`; compiled Swift image SHA256 `49ee785bd2e7e88603d71589d4f88ae927a4ba3b16a826bc62f57a5b270ed037`.
- Actual normal app launch restores the existing development account and opens Profile. Connect/import MAL truthfully reports **Library synchronization is not enabled yet**. Local foundation overrides remain off until deployed contracts are verified. [Installed Profile evidence](import-v2-installed-profile.png). This observation proves safe disabled behavior, not a completed MAL import.
- Documentation inventory check PASS:160 app Swift,27 package Swift,245 historical migration files;30 native test Swift;14 top-level prepared inputs plus one opt-in backfill excluded from deployment.

## Remaining required work

1. Implement and obtain native visual review of the [Home/detail/Profile polish plan](../../plans/2026-10-08-native-design-polish.md). The plan is saved; the requested presentation is not implemented or owner accepted.
2. Exercise actual AniList and MAL XML review, Keep/updates, interruption/restart, persistent results, Stop/Undo, imported/full Collection and shared projection/account transitions. Live synthetic-source RPC proof cannot substitute for those journeys.
3. Qualify MAL account OAuth/list ingestion when a controlled MAL user account becomes available. The user reports that no such account is available; the old login browser is dismissed. This specific blocker does not stop the other work.
4. Assess/disclose the measured public-CDN deletion propagation limitation without replacing failed evidence with a larger arbitrary deadline. Origin cleanup and old-token denial are verified; the later recorded URL checks returned NoSuchKey.

The independently accepted Manga cache-selection correction is already installed. Actual restore/Home/Anime→Manga selection passed. The current 223-input source pins and installed identity are recorded in [the medium-switch install receipt](home-medium-switch-install-receipt.json); earlier 222-input candidates remain historical. The [fresh-session handoff](../2026-10-08-fresh-session/HANDOFF.md) records the current Git, backend and simulator layers.

[Current gates](import-v2-gates.json) distinguish source acceptance, actual hosted contract passes, failed CDN observation and blocked provider/installed journey proof. The approved exact deployment is complete; no additional backend repair is proposed by these results. No TestFlight/global Home activation.

Canonical specification: [two-wave implementation](../../plans/2026-10-08-import-library-home-completion.md). Single finding register: [all27 implementation dispositions](import-user-journey-review.md). Future implementation rules remain in that specification and [module guide](../../modules/README.md): one owner/API, immutable attempted actions, missing-versus-clear semantics, account/permission leases, durable partial outcomes, semantic size review and focused independent high-risk review.
