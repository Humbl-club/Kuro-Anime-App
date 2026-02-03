# KURO — Master Plan (Production-Grade Concierge + Discovery)

This document is the source-of-truth plan for Kuro’s production launch scope and the systems required to ship:
- Supabase Auth (no anonymous-only mode)
- Deterministic-first “Concierge” (chat-like) that can recommend + bulk-import + bulk-edit
- Minimal-token LLM fallback (routing / disambiguation / narration only)
- Tag-driven discovery (no “curated lists for every question”, no rating-only ranking)

## 1) Launch scope (everything ships)

### 1.1 Authentication (Supabase Auth)
- Email/password sign up + sign in
- Apple Sign-In (minimum for iOS expectations)
- Session persistence + sign-out + account deletion
- `profiles` row created on first login

### 1.2 Concierge (chat-like UI)
Users can:
- Ask for recommendations (“funny”, “sad”, “like X”, “first anime”, etc.)
- Paste/import libraries (hundreds of titles) with progress/status extraction
- Bulk edit by text (“mark these completed”, “set AoT to ep 54”)
- Confirm/resolve ambiguities via clickable options
- Undo a batch import/apply

### 1.3 Discovery (premium, relevant, safe by default)
- Default excludes adult content and ecchi unless explicitly enabled later
- Recommendations are “fit + quality”, not rating-only
- “New to you” excludes titles already in user lists
- Diversity constraint to avoid repetitive results

### 1.4 Ops and guardrails
- RLS on all user-owned tables
- Rate limiting per user/IP for concierge endpoints
- Token/call budgets per user + per session
- Full observability: run logs + error reporting + latency metrics

## 2) Core concept: Intent Schema + Query Builder (no infinite curated lists)

We do **not** build “curated lists for all questions”.
We build:
- A strict **Intent JSON schema**
- A deterministic **Query Builder** that composes a small number of operators
- A small, editable config of **mood bundles** (tag weights)

### 2.1 Intent Schema (canonical)
Every concierge message resolves into a single JSON object:

```json
{
  "media_scope": "anime|manga|both",
  "seeds": [{ "title_raw": "string", "media_type": "ANIME|MANGA|null", "media_id": 123|null }],
  "moods": ["funny","sad","cozy","intense","mind_bending"],
  "constraints": {
    "format": ["TV","MOVIE","MANGA","ONE_SHOT"],
    "status": ["FINISHED","RELEASING"],
    "length": { "max_episodes": 13, "min_episodes": 0 },
    "year": { "min": 1990, "max": 2026 }
  },
  "exclusions": {
    "avoid_genres": ["Ecchi"],
    "avoid_tags": ["Gore"]
  },
  "exploration_mode": "safe_popular|new_to_you|deep_cuts|similar_to_seed",
  "output": { "count": 5, "style": "one_perfect|top5|top10" }
}
```

### 2.2 Query Builder operators (10–15 primitives)
Operators are deterministic and composable:
1) ResolveTitle (title_search + trigram)
2) SeedSimilarity (tags overlap)
3) MoodBundle (tag weights)
4) ConstraintFilter (status/format/year/length)
5) ExclusionFilter (adult/ecchi + user avoid list)
6) NewToYou (exclude user lists)
7) Diversity (penalize near-duplicates)
8) PremiumRank (multi-signal, not rating-only)
9) CandidateCap (limit before LLM)
10) Explain (reasons from tags/seeds)

## 3) Data model (launch)

### 3.1 Identity
- `profiles` (1:1 with `auth.users`)

### 3.2 Title search index (multilingual)
- `title_search` contains all title variants across English/Romaji/Native/Synonyms
- `pg_trgm` index enables fast fuzzy matching
- Server-side RPC `search_titles()` returns top candidates + similarity score

### 3.3 Concierge sessions (staging + undo)
- `import_sessions` (draft/applied/cancelled)
- `import_session_items` (raw, parsed, candidates, chosen, action)
- `concierge_runs` (metrics: latency, errors, token usage)

### 3.4 Taste profile (non-LLM personalization)
- `user_taste_profiles` stores tag weights derived from user lists

## 4) LLM usage (minimal by design)

### 4.1 LLM is not retrieval
The DB retrieves candidates. LLM only:
- routes/clarifies intent (tiny JSON)
- breaks ties among DB candidates (rare)
- narrates/explains (optional)

### 4.2 Token caps
- max candidates to LLM per item: 12
- batch resolve: N ambiguous titles per call (not per-title calls)
- hard per-user daily token budget; deterministic fallback continues to work

## 5) Milestones

Phase 1: DB foundation
- schema + RPCs + indexes + RLS

Phase 2: Concierge endpoints
- deterministic parse/resolve/apply + sessions + undo

Phase 3: iOS concierge UI
- chat view + staging + disambiguation + apply/undo

Phase 4: LLM router/resolver (optional but launch-complete)
- strict JSON outputs + caching + budgets

Phase 5: QA/observability
- test corpus + metrics + rate limits + perf validation

