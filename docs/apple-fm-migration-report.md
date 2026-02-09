# Apple Foundation Models Migration Report

**Generated**: 2026-02-09
**Source**: 10-agent team (5 experts + 5 devil's advocates)
**Status**: Ready for review

---

## Executive Summary

A 10-agent team audited replacing Groq (cloud LLM) with Apple Foundation Models (on-device LLM) for the Kuro concierge system. The team comprised 5 domain experts (Apple FM API, Apple Documentation, Backend, Swift, UX) and 5 devil's advocates who challenged each expert's findings.

**Verdict: Partial migration. Apple FM is suitable for classification tasks only. Keep Groq for narration.**

### Key Findings

| Use Case | Expert Rating | DA-Adjusted Rating | Decision |
|----------|---------------|-------------------|----------|
| Mode routing (classify user intent into 23 vibe modes) | Well Suited | Cautiously Viable | **Use Apple FM** where available, deterministic fallback |
| Disambiguation (pick best title match from 2-5 candidates) | Well Suited | Viable with Caveats | **Use Apple FM** where available, heuristic fallback |
| Narration blurbs (50-word editorial descriptions) | Feasible | **Not Recommended** | **Keep Groq** server-side. Quality too low, latency too high for batch, guardrail risk |

### Why Not Full Migration

1. **3B model quality gap**: Apple FM is competitive with other 3B models but significantly below Groq's 70B+ models for creative writing. Narration blurbs would be generic/formulaic.
2. **4096 token context window**: Adequate for single-turn classification, but mathematically incompatible with persistent sessions or collection-wide analysis.
3. **Guardrail risk**: Apple's non-configurable safety filters may reject anime content (violence, dark themes). ~15-25% of catalog at risk. Not yet tested.
4. **Device exclusion**: ~44-45% of active iPhones lack A17 Pro+. Building narration exclusively on Apple FM creates a two-tier experience.
5. **Batch latency**: 8 narration blurbs take ~17-20 seconds on-device vs ~3 seconds via Groq batch. 6.5x slower.

---

## Apple Foundation Models: Technical Profile

### Capabilities
- **Model**: ~3B parameters, 2-bit quantized, 150K vocabulary
- **Context window**: 4,096 tokens (fixed, input + output combined)
- **Performance**: ~30 tok/s on iPhone 15 Pro, ~0.6ms TTFT per prompt token
- **Languages**: 23 locales including English, German, Japanese (all relevant for Kuro)
- **Structured output**: `@Generable` macro guarantees valid Swift struct output
- **Cost**: Free, no API keys, no rate limits in foreground
- **Privacy**: 100% on-device, works offline after model download

### Constraints
- **Device support**: A17 Pro+ only (iPhone 15 Pro and later), iOS 26+
- **Guardrails**: Only `.default` available, NOT configurable, known false positives
- **No version pinning**: Model updates ship with OS updates, behavior may change
- **Knowledge cutoff**: ~October 2023 (no knowledge of recent anime)
- **One request per session** at a time (throws `rateLimited` if concurrent)
- **No multimodal input**: Text only

### Device Compatibility (TelemetryDeck Jan 2026)
- iPhone 15 Pro+: ~55% of active iPhones
- iPhone 15 (non-Pro) + older: ~45% excluded
- Additional requirement: Apple Intelligence must be enabled in Settings

---

## Groq Integration: Current State

### 3 Integration Points (All in Edge Functions)

| # | Function | File | Lines | Purpose |
|---|----------|------|-------|---------|
| 1 | `groqNarrate()` | concierge-recommend | L778-857 | Generate 50-word blurbs for top 8 recommendations |
| 2 | `groqRouteMode()` | concierge-recommend | L859-924 | LLM fallback when deterministic mode scoring has low confidence |
| 3 | `groqResolve()` | concierge-resolve | L61-123 | Disambiguate title matches (2-5 candidates) |

### Removal Impact
- ~570-650 lines removed across 2 files
- 4 env vars removed: `GROQ_API_KEY`, `GROQ_MODEL`, `GROQ_MODEL_ROUTER`, `GROQ_MODEL_RESOLVE`
- Budget system (RPCs + tables) kept but disabled via feature flag
- Core recommendation engine (scoreMode, buildAlgorithmicRail, fetchCurated, ~1200+ lines) untouched

---

## Migration Plan

### Phase 1: Server-Side Groq Cleanup (No Apple FM needed)

**Action**: Remove `groqRouteMode()` from concierge-recommend. Strengthen deterministic `scoreMode()`.

**Prerequisite**: Query production data first:
```sql
SELECT
  COUNT(*) FILTER (WHERE used_llm = true) as llm_routed,
  COUNT(*) as total,
  ROUND(100.0 * COUNT(*) FILTER (WHERE used_llm = true) / NULLIF(COUNT(*), 0), 2) as pct
FROM concierge_mode_cache;
```
If LLM fallback rate > 5%, add more synonym patterns before removing. If < 5%, safe to remove.

**Files**: `supabase/functions/concierge-recommend/index.ts`
**Risk**: Low-Medium
**Lines removed**: ~140

### Phase 2: Apple FM Client Integration (Classification Only)

**Action**: Create `AppleFMService` for on-device mode routing and disambiguation.

**Architecture** (incorporating DA feedback):

```
AppleFMService (@MainActor, @Observable)
├── isAvailable: Bool (runtime #available + availability check)
├── classifyMode(userText:, modes:) -> ModeClassificationResult?
├── disambiguate(candidates:, userText:) -> DisambiguationResult?
└── Internal: fresh LanguageModelSession per request (NOT persistent)
```

**Critical design decisions from DA review**:
1. **`@MainActor` + `@Observable`** (matching SupabaseService pattern) — NOT non-isolated
2. **Fresh session per request** — persistent sessions accumulate context and overflow 4096 tokens
3. **`#available(iOS 26, *)` as PRIMARY guard** at every public method — `#if canImport` as secondary
4. **Structured `Task {}` not `Task.detached`** — for reliable cancellation
5. **Make FM a dependency of SupabaseService** — not a separate `@Environment` object
6. **Protocol abstraction** (`FMProvider` protocol) for testability/mocking
7. **Validate `@Generable` output** — bounds-check selectedIndex, don't trust self-reported confidence
8. **Cache results** — keyed by `(mediaId, promptVersion)` using existing `TimedCache` pattern

**`@Generable` structs**:
```swift
@Generable
struct DisambiguationResult {
    @Guide(description: "Brief reason for selection")  // reasoning BEFORE index
    var reasoning: String
    @Guide(description: "0-based index of best candidate")
    var selectedIndex: Int
}

@Generable
enum VibeMode: String, CaseIterable, Codable {
    case premium_picks, dark_serious, premium_comedy_grownup, ...
}

@Generable
struct ModeClassificationResult {
    @Guide(description: "Brief reason for classification")  // reasoning first
    var reason: String
    @Guide(description: "The vibe mode that best matches")
    var mode: VibeMode
}
```

Note: Properties generate sequentially in declaration order. Place `reasoning` BEFORE `selectedIndex`/`mode` so the model "thinks" before answering.

**Files**: New `Kuro/Services/AppleFMService.swift` (~350-400 lines)
**Risk**: Medium

### Phase 3: Deprecate concierge-resolve

**Action**: iOS client does disambiguation locally using candidates from concierge-parse + Apple FM (or heuristic fallback).

**Disambiguation heuristic (no LLM needed for most cases)**:
1. If yearMention matches one candidate's year exactly → pick it
2. If mediaTypeHint matches one candidate's type → boost it
3. If seasonNumber matches → boost it
4. If top candidate score > second by 15%+ → pick top
5. Only invoke Apple FM for genuinely close calls (score gap < 10%)

**Migration coordination** (from DA backend review):
- Ship iOS update FIRST with local disambiguation
- New iOS client sends requests WITHOUT calling concierge-resolve
- Old clients continue to call concierge-resolve (it still works, just without Groq)
- Set `llm_enabled = false` in DB to disable Groq in resolve
- Remove Groq env vars from Supabase secrets

**Files**: `Kuro/Views/ConciergeView.swift`, `supabase/functions/concierge-resolve/index.ts`
**Risk**: Medium

### Phase 4: Narration (Keep Groq, Optimize)

**Decision**: Do NOT move narration to Apple FM.

**Reasoning**:
- 3B model narration quality is too low for Kuro's editorial brand
- Batch latency: ~20s on-device vs ~3s via Groq
- Guardrail risk with anime content unquantified
- 45% of users can't access it anyway

**Instead, optimize current Groq narration**:
- Pre-generate and cache blurbs in a new `media_narration_cache` table
- On first recommendation of an item, generate blurb via Groq and cache it
- Subsequent recommendations for the same item use cached blurb (zero latency)
- This eliminates per-request Groq costs for popular items over time

### Phase 5: New Features (Post-Migration)

**Surviving features from UX proposals** (after DA review):

| Feature | DA Verdict | Scope |
|---------|-----------|-------|
| **Synopsis Condenser** | KEEP | Condense AniList descriptions to 2-sentence hooks on detail pages. Cache by mediaId. Graceful fallback: show first 4 lines (current behavior). |
| **NL Collection Search** | MODIFY | Use Apple FM for intent parsing ONLY (extract filters: genre, status, year). Run standard query against collection. Do NOT stuff full collection into context. |
| **"Next Up" Pick** | MODIFY | Use existing similar-anime data + collection status for deterministic pick. Optionally use Apple FM for 1-sentence explanation. |

**Cut features**:
- Contextual Collection Narration — tech demo, non-deterministic text destabilizes UI
- Smart Progress Notes — no arc boundary data exists, spoiler risk catastrophic
- Discover Rail Reranking — simple heuristic outperforms LLM, unmeasurable impact
- Club Discussion Starters — premature for unproven feature, requires plot knowledge model lacks

---

## Critical Issues to Resolve Before Implementation

### From DA Swift (Ship-Blockers)
1. **`@Observable` without `@MainActor`** = data race crashes → Use `@MainActor`
2. **Persistent sessions accumulate context** → Use fresh sessions per request
3. **`#if canImport` doesn't gate iOS version** → `#available` as primary guard

### From DA Backend (Migration Risks)
4. **Query LLM router fallback rate** before removing it
5. **Client-first migration order** — ship iOS update before removing server Groq
6. **API contract preservation** — keep `blurb` field in response, return `narrated: false`

### From DA FM (Quality Risks)
7. **Test guardrails with 200+ anime synopses** before committing to synopsis condenser
8. **Battery monitoring** — cap on-device inference to max 10 calls per session
9. **Build evaluation benchmarks** — 500+ queries for mode routing accuracy

### From DA Docs (Documentation Gaps)
10. **Availability check is unreliable** — handle "available but broken" state
11. **Concurrent sessions undocumented** — test parallel access patterns
12. **Model download state** — handle `modelNotReady` gracefully on first launch

---

## Files Summary

| File | Action | Phase |
|------|--------|-------|
| `Kuro/Services/AppleFMService.swift` | CREATE (~350-400 lines) | 2 |
| `Kuro/Services/SupabaseService.swift` | MODIFY (integrate AppleFMService as dependency) | 2 |
| `Kuro/Views/ConciergeView.swift` | MODIFY (local disambiguation, mode routing) | 2-3 |
| `supabase/functions/concierge-recommend/index.ts` | MODIFY (remove groqRouteMode, ~140 lines) | 1 |
| `supabase/functions/concierge-resolve/index.ts` | DEPRECATE (remove Groq, keep endpoint alive) | 3 |
| `supabase/migrations/` (new) | ADD (media_narration_cache table) | 4 |

---

## Production Blockers Reference

All P0/P1/P2 findings from the production-readiness audit are tracked in:
`docs/production-blockers.md`

These should be addressed BEFORE the Apple FM migration.

---

## Next Steps

1. **Immediate**: Query `concierge_mode_cache` for LLM router fallback rate (Phase 1 prerequisite)
2. **Immediate**: Build guardrail test harness — 200+ anime synopses through Apple FM
3. **Week 1**: Phase 1 — remove groqRouteMode, strengthen deterministic scorer
4. **Week 2-3**: Phase 2 — create AppleFMService (classification only)
5. **Week 3-4**: Phase 3 — deprecate concierge-resolve, local disambiguation
6. **Week 4+**: Phase 5 — Synopsis Condenser feature (first new FM feature)
7. **Ongoing**: Phase 4 — narration cache optimization (Groq stays)
