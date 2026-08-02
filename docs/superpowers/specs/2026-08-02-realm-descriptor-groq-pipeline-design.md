# Realm Descriptor Groq Pipeline — Design (2026-08-02)

Status: approved for implementation.
Spec parent: `2026-07-31-realm-graph-master-plan.md` §6.
Supersedes the abandoned agent-swarm writer path for Stage 2b.

## Goal

Finish the visible-pool LLM descriptors cheaply: salvage already-generated swarm JSONL, then generate the remainder via Groq (same stack as concierge narration), not agent quota.

## Out of scope

- Craft / taste indicators (animation+/story−)
- Applying LLM realm deltas (±0.2) into membership matviews
- Gold-set AniList edges evaluation
- Stage 4 Discover Shelf / Hidden Gem

## Architecture

```
media_realm_llm_pending
        │
        ▼
scripts/realm_descriptor_worker.js  ──(x-import-secret)──►  realm-describe edge fn
        │                                                      │
        │ checkpoint                                           ├─ load title context (service role)
        │                                                      ├─ Groq chat.completions (strict JSON)
        │                                                      ├─ validate (same rules as upsert RPC)
        ▼                                                      └─ upsert_media_realm_llm
media_realm_llm
```

Salvage (one-shot, first):
`/tmp/realm_out_*.jsonl` → filter/validate → `scripts/realm_llm_pass_submit.js` → `media_realm_llm`.

## Contracts (unchanged)

Row shape for `upsert_media_realm_llm`:
- `realms`: 1..3 of `{realm, weight}` from `realm_meta`
- `tone`: 1..3 of fixed 24-word vocabulary
- `register`: family | general | seinen-otaku | arthouse
- `pacing`: slow-burn | steady | relentless
- `confidence`: 0..1
- `descriptor`: 100..600 chars, Kuro voice
- `model`: writer id (`kimi-swarm-2026-08` for salvage; `groq-<model>` for pipeline)

## Auth

- Edge function: `x-import-secret` == `IMPORT_SECRET` (mirror-images pattern). `verify_jwt = false`.
- Worker: reads `IMPORT_SECRET` from env; Supabase URL/anon from xcconfig.
- No Groq key in the repo or worker.

## Prompt doctrine

Quiet editorial Kuro voice. Evidence from tags + current membership. Banned: "This anime is about…", genre laundry lists, hype, spoilers beyond synopsis. Retry once on invalid JSON.

## Verification

1. Salvage dry-run then submit; pending count drops.
2. Worker `--dry-run` prints 3 pending titles' request payloads.
3. Deploy function; smoke 1–3 live titles.
4. Spirited Away still Ghibli-class in similarity; `media_realm_profile` readable for a few titles.
5. Spot-check 20 random descriptors; note confidence < 0.7 for later QA.

## Self-review

- No placeholders.
- Taste indicators explicitly deferred.
- Membership delta apply deferred (descriptors land first).
- Rate limits: upsert RPC 60 calls/hour; worker concurrency 3 + checkpoint handles long runs.
