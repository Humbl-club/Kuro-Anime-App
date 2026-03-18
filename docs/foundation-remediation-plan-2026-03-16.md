# Foundation Remediation Plan — 500-User Readiness (2026-03-16)

## Goal
Convert the audit into concrete structural work without inventing churn. This plan is ordered by engineering value: first reduce change risk in runtime hotspots, then reduce UI drift, then clean remaining workspace noise.

## P1 — Immediate foundation work
### 1. Split `SupabaseService` by domain
Target shape:
- `SupabaseService+Auth.swift`
- `SupabaseService+Discovery.swift`
- `SupabaseService+SearchBrowse.swift`
- `SupabaseService+Collection.swift`
- `SupabaseService+Clubs.swift`
- `SupabaseService+Details.swift`
- `SupabaseService+Streaming.swift`
- `SupabaseService+SocialActivity.swift`

Rules:
- Keep one `@Observable` root type for state ownership.
- Move methods by domain, not by arbitrary line count.
- Promote only the minimum required members from `private` to `fileprivate` when cross-file extensions need access.
- Do not move auth state, caches, or realtime handles into separate singleton services unless ownership becomes clearer.

### 2. Decompose the largest SwiftUI screens
First wave:
- `Kuro/Views/ClubDetailView.swift`
- `Kuro/Views/ConciergeView.swift`
- `Kuro/Views/EditorialCollectionView.swift`
- `Kuro/Views/EditorialDiscoverView.swift`
- `Kuro/Views/BrowseView.swift`
- `Kuro/Views/DetailPages/AnimeDetailView.swift`
- `Kuro/Views/DetailPages/MangaDetailView.swift`

Pattern:
- Extract section views first.
- Extract screen-local state containers only where the view file currently mixes workflow state and presentation.
- Keep navigation and cross-screen environment wiring where it already lives.

### 3. Break up `fetch_club_bundle` if usage grows
Current state:
- Recent safety caps bound the function.
- It is still the largest aggregate payload path.

Next step if club traffic grows:
- Keep `fetch_club_bundle` for club shell + membership summary.
- Add paged RPCs for rails and polls.
- Only fetch heavy sections when the user scrolls into them.

## P2 — Design-system hardening
### 4. Tokenize top offender views
Apply existing design tokens before inventing new primitives.

Order:
1. `Kuro/Views/EditorialCollectionView.swift`
2. `Kuro/Views/ClubDetailView.swift`
3. `Kuro/Views/ConciergeComponents.swift`
4. `Kuro/Views/BrowseView.swift`
5. `Kuro/Views/EditorialDiscoverView.swift`
6. `Kuro/Views/Cards.swift`
7. `Kuro/Views/KuroRefinedCard.swift`
8. `Kuro/Views/DetailPages/AnimeDetailView.swift`
9. `Kuro/Views/DetailPages/MangaDetailView.swift`

Acceptance rule:
- Raw `.black`, `.white`, and `.font(.system(...))` usage should live only in `Kuro/Design/` unless a file has a deliberate documented exception.

### 5. Normalize shared visual primitives
Before editing every screen independently, strengthen shared helpers for:
- card chrome
- badge typography
- divider treatments
- pill/tab styling
- skeleton/shimmer treatments

This removes repeated style math from screen files and reduces future drift.

## P2 — Backend efficiency follow-ups
### 6. Finish the similar-title path cleanup
Current improvement already shipped:
- batched `IN (...)` hydration with cache-first behavior

Next step if metrics show ongoing misses:
- replace ID-only recommendation + hydration with a display-ready recommendation RPC/view returning title, image, score, year, and media type in one call

### 7. Audit repeated function chains
For RPCs with multiple `CREATE OR REPLACE` migrations over time:
- identify the latest authoritative migration
- document function lineage in the audit appendix or inline comments
- avoid future edits landing in older migration files

## P3 — Workspace hygiene
### 8. Finish non-runtime root cleanup
Candidates:
- tracked design-output artifacts still sitting in repo root
- historical/operator helpers without a clear subfolder owner

Goal:
- root should read like an app workspace, not a dumping ground

## Validation requirements
After each refactor wave:
- `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build`
- `xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test -only-testing:KuroTests`
- `supabase db lint --linked`
- `scripts/quality-gates/run_all.sh`

## Exit criteria
This foundation pass is in a good state when:
- no runtime Swift source lives at repo root
- manual and legacy scripts are named by intent and foldered by role
- similar-title hydration no longer causes avoidable request fanout
- the audit and remediation surfaces are explicit enough that the next refactor wave can be executed without rediscovering the repo
