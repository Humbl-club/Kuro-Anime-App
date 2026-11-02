-- Realm audit corrections F1+F2 — override layer for 393 double-judged realm
-- reassignments (audit: reports/realm-audit/summary.md, 2026-08-05).
--
-- DOUBLE-JUDGE GATE: the 3,000-title audit produced 396 misassignments
-- (verify_f1 = 187 r1/r2-swap candidates, verify_f2 = 209 deeper corrections).
-- Every one was re-judged independently; 381 were double-agreed
-- ('fable5-audit-x2-2026-08-05') and 12 resolved by the second judge
-- ('fable5-audit-secondjudge-2026-08-05') = 393 applied here; 3 were HELD for
-- the signature-level regrade (held_for_regrade.jsonl) and are NOT in this set.
--
-- WHY AN OVERRIDE LAYER (not deltas, not matview edits): the corrections must
-- reach the effective membership layer without touching the rules matview
-- (inspectable, rebuilt nightly) or the LLM descriptor data (model-tagged,
-- recomputed by recompute_media_realm_llm_deltas — hand-edits there would be
-- erased on the next recompute, and the ±0.2 delta clamp cannot express most
-- of these corrections anyway). So: a third layer, applied inside
-- media_realm_membership_effective on top of (rules ⟗ llm-delta).
--
-- WEIGHT-SWAP SEMANTICS (per overridden title, computed on the layer-1+2
-- effective weights w_demote / w_promote):
--   * both realms present, weights differ  -> promote takes greatest(w_d, w_p),
--     demote takes least(w_d, w_p) — a pure rank swap, weight mass preserved.
--   * promote row missing (or clamped to 0) -> promote row is CREATED with the
--     demoted realm's old weight w_d; demote keeps 0.6 * w_d. 60% chosen over
--     "least-of" (undefined with no promote weight to take): it guarantees
--     strict promote > demote for every w_d > 0 while keeping the demoted
--     realm as a live secondary membership — the audit demotes RANK, it does
--     not deny membership. Created rows carry rules_weight = 0, delta = 0,
--     family from realm_meta (same convention as delta-only rows).
--   * weights exactly tied -> same 0.6 rule (a bare swap would keep the tie and
--     the demote realm could win the top-realm tiebreak alphabetically).
--   * demote row absent/zero in layer 1+2 (possible after future rules
--     refreshes; zero titles today) -> override is inert (no weight to move).
--   Invariant: for every ACTIVE override, promote ends STRICTLY above demote.
--   For overridden rows, `weight` intentionally deviates from
--   clamp(rules_weight + delta); rules_weight/delta keep reporting the
--   underlying layers.
--
-- ACL DEVIATION (documented): the plan called for zero policies +
-- service_role-only grants (the media_franchise_components pattern). That
-- pattern cannot work here: media_realm_membership_effective is
-- security_invoker = true and is read by SECURITY INVOKER RPCs
-- (fetch_tonight_shelf, fetch_realm_hidden_gem) EXECUTE-granted to
-- anon/authenticated — with a client-invisible override table every such call
-- would fail with permission-denied. This table therefore follows its sibling
-- layer-2 table media_realm_membership_delta (20260802123000): read-open
-- (select policy + SELECT grant — the content is editorial correction
-- metadata, same sensitivity class as the delta reasons already public),
-- write-locked (no write policies; default-privileges write bits revoked in
-- this file; service_role full for ops).
--
-- PROPAGATION (deliberately NOT forced here):
--   * media_realm_tier: rebuilt once post-push via a one-off pg_cron job using
--     the SET-first technique (20260804120000: the API session's 2-min
--     statement_timeout cannot be re-armed by an in-function SET LOCAL; the
--     cron command raises the session timeout as its OWN first statement).
--     The nightly realm-tier-refresh (04:50 UTC) keeps it converged after.
--   * media_similar_titles: NO forced rebuild — the nightly 05:10 UTC
--     realm-similar-nightly re-stales every seed and the 5-min driver
--     propagates the corrected memberships through the store overnight.
--
-- View cost: the view already could not push predicates below its FULL OUTER
-- JOIN, so point reads were always full-scan (~230 ms scan / ~730 ms 100-title
-- probe pre-change). The override layer adds one 393-row materialized CTE
-- (indexed lookups) + two small hash left joins + a UNION ALL arm bounded by
-- the override count — measured post-change in the rollout report.

begin;

-- ---------------------------------------------------------------------------
-- 1) Override table
-- ---------------------------------------------------------------------------

create table if not exists public.realm_audit_overrides (
  media_type    text        not null check (media_type in ('ANIME', 'MANGA')),
  media_id      integer     not null,
  demote_realm  text        not null references public.realm_meta(realm),
  promote_realm text        not null references public.realm_meta(realm),
  source        text        not null check (char_length(source) between 1 and 120),
  conf          real            null check (conf is null or (conf >= 0 and conf <= 1)),
  created_at    timestamptz not null default now(),
  primary key (media_type, media_id),
  constraint realm_audit_overrides_distinct_realms check (demote_realm <> promote_realm)
);

comment on table public.realm_audit_overrides is
  'Realm audit F1+F2 (2026-08-05): double-judged top-realm corrections applied as a weight swap inside media_realm_membership_effective (layer 3, on top of rules matview + LLM deltas). One override per title: promote_realm must end strictly above demote_realm. Seeded from reports/realm-audit/apply_set.jsonl (393 rows; 3 held for regrade). Read-open like media_realm_membership_delta (security_invoker view + invoker RPCs need client SELECT); writes service_role-only.';

alter table public.realm_audit_overrides enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'realm_audit_overrides'
      and policyname = 'realm_audit_overrides_select_all'
  ) then
    create policy realm_audit_overrides_select_all
      on public.realm_audit_overrides
      for select using (true);
  end if;
end $$;

-- Close the default-privileges trap IN THIS FILE (CREATE TABLE hands
-- anon/authenticated full DML bits): revoke everything, then re-grant SELECT
-- only. No write policies exist, so client writes stay double-locked
-- (no privilege AND RLS default-deny).
revoke all on public.realm_audit_overrides from public, anon, authenticated;
grant select on public.realm_audit_overrides to anon, authenticated;
grant all on public.realm_audit_overrides to service_role;

-- ---------------------------------------------------------------------------
-- 2) Seed: 393 double-judged corrections (idempotent upsert).
--    Generated from reports/realm-audit/apply_set.jsonl.
-- ---------------------------------------------------------------------------

insert into public.realm_audit_overrides (media_type, media_id, demote_realm, promote_realm, source, conf) values
('ANIME', 131, 'coming-of-age', 'mind-game-strategy', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 141, 'quiet-melancholy', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 153, 'quiet-melancholy', 'sword-samurai', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 167, 'slice-of-life-iyashikei', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.85),
('ANIME', 180, 'time-parallel-worlds', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 237, 'battle-shounen', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 250, 'seinen-drama', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 239, 'dark-fantasy', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 257, 'cyberpunk-dystopia', 'mecha', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 251, 'seinen-drama', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 286, 'idol-showbiz', 'psychological-thriller', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 267, 'psychological-thriller', 'crime-underworld', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 302, 'horror-dread', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 293, 'cyberpunk-dystopia', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 309, 'dark-fantasy', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 8, 'tragedy-tearjerker', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.8),
('ANIME', 318, 'mecha', 'arthouse-experimental', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 324, 'crime-underworld', 'moe-cgdct', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 319, 'sword-samurai', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 327, 'psychological-thriller', 'crime-underworld', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 345, 'war-military', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.8),
('ANIME', 341, 'cyberpunk-dystopia', 'isekai-reincarnation', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 361, 'sword-samurai', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 358, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 381, 'mystery-detective', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 413, 'classic-serial-canon', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 421, 'moe-cgdct', 'coming-of-age', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 482, 'slice-of-life-iyashikei', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 763, 'isekai-reincarnation', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 544, 'sword-samurai', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 794, 'sports-competition', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 751, 'romance-slow-burn', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 777, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 809, 'grand-adventure', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 808, 'classic-serial-canon', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 798, 'sci-fi-space', 'family-generations', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 821, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 838, 'supernatural-yokai', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 856, 'war-military', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 28, 'dark-fantasy', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 882, 'romance-slow-burn', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 861, 'cyberpunk-dystopia', 'music-performance', 'fable5-audit-x2-2026-08-05', 0.8),
('ANIME', 870, 'battle-shounen', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 919, 'dark-fantasy', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 958, 'sci-fi-space', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.85),
('ANIME', 975, 'workplace-adult-life', 'romance-slow-burn', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 999, 'supernatural-yokai', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 985, 'cyberpunk-dystopia', 'psychological-thriller', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1003, 'battle-shounen', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.9),
('ANIME', 992, 'crime-underworld', 'seinen-drama', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 990, 'ecchi-fanservice', 'war-military', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 997, 'workplace-adult-life', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1016, 'cyberpunk-dystopia', 'coming-of-age', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 993, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1004, 'battle-shounen', 'time-parallel-worlds', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1024, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1091, 'cyberpunk-dystopia', 'sci-fi-space', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1044, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1124, 'grand-adventure', 'isekai-reincarnation', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1068, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1136, 'bl-yuri', 'moe-cgdct', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1170, 'horror-dread', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1332, 'idol-showbiz', 'coming-of-age', 'fable5-audit-x2-2026-08-05', 0.65),
('MANGA', 108, 'classic-serial-canon', 'coming-of-age', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 1175, 'romance-slow-burn', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 96, 'time-parallel-worlds', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 1249, 'moe-cgdct', 'ecchi-fanservice', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1215, 'moe-cgdct', 'bl-yuri', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1234, 'family-generations', 'coming-of-age', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1221, 'bl-yuri', 'war-military', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1260, 'comedy-parody', 'arthouse-experimental', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1251, 'battle-shounen', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 106, 'sword-samurai', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1306, 'war-military', 'moe-cgdct', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1299, 'food-craft', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.65),
('MANGA', 126, 'tragedy-tearjerker', 'isekai-reincarnation', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 1367, 'psychological-thriller', 'mind-game-strategy', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1348, 'music-performance', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1356, 'dark-fantasy', 'psychological-thriller', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1412, 'quiet-melancholy', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1380, 'battle-shounen', 'coming-of-age', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1416, 'bl-yuri', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 1369, 'moe-cgdct', 'idol-showbiz', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1391, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 127, 'time-parallel-worlds', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1409, 'moe-cgdct', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 134, 'crime-underworld', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1590, 'romantic-comedy', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1398, 'food-craft', 'workplace-adult-life', 'fable5-audit-x2-2026-08-05', 0.85),
('ANIME', 1576, 'supernatural-yokai', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1418, 'romantic-comedy', 'ecchi-fanservice', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1446, 'workplace-adult-life', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.85),
('ANIME', 1421, 'cyberpunk-dystopia', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1441, 'ecchi-fanservice', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 1436, 'romance-slow-burn', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 1601, 'romance-slow-burn', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1447, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.85),
('MANGA', 138, 'time-parallel-worlds', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1465, 'cyberpunk-dystopia', 'psychological-thriller', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1487, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 1478, 'moe-cgdct', 'coming-of-age', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 1485, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1503, 'kids-family', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 1530, 'war-military', 'sci-fi-space', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1481, 'food-craft', 'workplace-adult-life', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1531, 'supernatural-yokai', 'mystery-detective', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1569, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1764, 'war-military', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1525, 'ecchi-fanservice', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1542, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 152, 'sports-competition', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 1563, 'seinen-drama', 'arthouse-experimental', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1555, 'comedy-parody', 'arthouse-experimental', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1579, 'auteur-cinema', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1658, 'sci-fi-space', 'time-parallel-worlds', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1632, 'classic-serial-canon', 'isekai-reincarnation', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 154, 'seinen-drama', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1903, 'seinen-drama', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1666, 'war-military', 'crime-underworld', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1689, 'quiet-melancholy', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.8),
('ANIME', 1669, 'romance-slow-burn', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1623, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.85),
('ANIME', 2180, 'grand-adventure', 'food-craft', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1668, 'workplace-adult-life', 'gag-short-form', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1710, 'idol-showbiz', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 1698, 'psychological-thriller', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1693, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 166, 'gag-short-form', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1713, 'sci-fi-space', 'cyberpunk-dystopia', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1720, 'romantic-comedy', 'gag-short-form', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 186, 'dark-fantasy', 'sword-samurai', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1786, 'mecha', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 12489, 'bl-yuri', 'seinen-drama', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1848, 'slice-of-life-iyashikei', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1814, 'cyberpunk-dystopia', 'coming-of-age', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2040, 'tragedy-tearjerker', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1795, 'battle-shounen', 'moe-cgdct', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 202, 'classic-serial-canon', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 187, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 193, 'moe-cgdct', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 190, 'classic-serial-canon', 'mind-game-strategy', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1831, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 1866, 'comedy-parody', 'ecchi-fanservice', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2454, 'idol-showbiz', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.75),
('MANGA', 196, 'family-generations', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 200, 'bl-yuri', 'coming-of-age', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1917, 'music-performance', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 1923, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1982, 'quiet-melancholy', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.8),
('ANIME', 1951, 'war-military', 'historical-epic', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1974, 'moe-cgdct', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2318, 'supernatural-yokai', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1926, 'moe-cgdct', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1939, 'classic-serial-canon', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 1980, 'moe-cgdct', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 1968, 'family-generations', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2013, 'battle-shounen', 'crime-underworld', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 2009, 'quiet-melancholy', 'arthouse-experimental', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 1958, 'supernatural-yokai', 'time-parallel-worlds', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 231, 'time-parallel-worlds', 'psychological-thriller', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 210, 'moe-cgdct', 'bl-yuri', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2428, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2053, 'slice-of-life-iyashikei', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2031, 'moe-cgdct', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2022, 'food-craft', 'workplace-adult-life', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 233, 'mecha', 'psychological-thriller', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 2028, 'seinen-drama', 'music-performance', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2032, 'classic-serial-canon', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2067, 'romantic-comedy', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2131, 'romantic-comedy', 'coming-of-age', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 244, 'family-generations', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2151, 'crime-underworld', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2088, 'classic-serial-canon', 'historical-epic', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 238, 'classic-serial-canon', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2078, 'auteur-cinema', 'historical-epic', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2094, 'mecha', 'war-military', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2098, 'battle-shounen', 'classic-serial-canon', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2453, 'slice-of-life-iyashikei', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2138, 'sci-fi-space', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2125, 'classic-serial-canon', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2137, 'classic-serial-canon', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2182, 'mecha', 'cyberpunk-dystopia', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2117, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2113, 'battle-shounen', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 258, 'sword-samurai', 'historical-epic', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 2168, 'war-military', 'historical-epic', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2146, 'arthouse-experimental', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 12877, 'workplace-adult-life', 'bl-yuri', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2444, 'seinen-drama', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2162, 'supernatural-yokai', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2171, 'cyberpunk-dystopia', 'mystery-detective', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 2191, 'moe-cgdct', 'idol-showbiz', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2433, 'historical-epic', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2286, 'romantic-comedy', 'kids-family', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 6216, 'food-craft', 'music-performance', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2281, 'bl-yuri', 'classic-serial-canon', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2282, 'psychological-thriller', 'crime-underworld', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2292, 'cyberpunk-dystopia', 'time-parallel-worlds', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 2458, 'cyberpunk-dystopia', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 12996, 'grand-adventure', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2333, 'workplace-adult-life', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2190, 'bl-yuri', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2426, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3593, 'cyberpunk-dystopia', 'sci-fi-space', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 271, 'sci-fi-space', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.8),
('ANIME', 3984, 'classic-serial-canon', 'isekai-reincarnation', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2423, 'cyberpunk-dystopia', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 279, 'slice-of-life-iyashikei', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2430, 'food-craft', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 2460, 'crime-underworld', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 288, 'psychological-thriller', 'mind-game-strategy', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 12918, 'coming-of-age', 'gag-short-form', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 287, 'workplace-adult-life', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 22199, 'sci-fi-space', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 15670, 'mind-game-strategy', 'kids-family', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 15677, 'cyberpunk-dystopia', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 13046, 'gag-short-form', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.4),
('ANIME', 12964, 'sci-fi-space', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.4),
('ANIME', 15789, 'bl-yuri', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 12981, 'supernatural-yokai', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 12991, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 12993, 'supernatural-yokai', 'mind-game-strategy', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 13000, 'sci-fi-space', 'ecchi-fanservice', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 15797, 'workplace-adult-life', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2480, 'supernatural-yokai', 'mystery-detective', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 73490, 'psychological-thriller', 'arthouse-experimental', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 13217, 'auteur-cinema', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.4),
('MANGA', 329, 'classic-serial-canon', 'isekai-reincarnation', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2517, 'romantic-comedy', 'ecchi-fanservice', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2613, 'grand-adventure', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 16277, 'food-craft', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2509, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2548, 'kids-family', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 2505, 'dark-fantasy', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 2553, 'grand-adventure', 'classic-serial-canon', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 2557, 'comedy-parody', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.45),
('MANGA', 350, 'mystery-detective', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 3320, 'romantic-comedy', 'isekai-reincarnation', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 4939, 'supernatural-yokai', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 13216, 'family-generations', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.4),
('ANIME', 73614, 'food-craft', 'workplace-adult-life', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 13177, 'romance-slow-burn', 'classic-serial-canon', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 13179, 'ecchi-fanservice', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 13241, 'tragedy-tearjerker', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 22441, 'horror-dread', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 366, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 16269, 'seinen-drama', 'quiet-melancholy', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 365, 'dark-fantasy', 'horror-dread', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 13221, 'mecha', 'sci-fi-space', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 369, 'food-craft', 'music-performance', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 364, 'grand-adventure', 'isekai-reincarnation', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2941, 'sports-competition', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 13245, 'battle-shounen', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 13222, 'family-generations', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 374, 'horror-dread', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 13234, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 386, 'romance-slow-burn', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 444, 'coming-of-age', 'bl-yuri', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 73731, 'battle-shounen', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2562, 'mecha', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 387, 'romance-slow-burn', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 13281, 'sword-samurai', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 13312, 'food-craft', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.8),
('ANIME', 13334, 'tragedy-tearjerker', 'seinen-drama', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 2624, 'classic-serial-canon', 'historical-epic', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 13326, 'romance-slow-burn', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 13343, 'auteur-cinema', 'isekai-reincarnation', 'fable5-audit-x2-2026-08-05', 0.8),
('ANIME', 16693, 'seinen-drama', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 406, 'moe-cgdct', 'horror-dread', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 13351, 'moe-cgdct', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 13354, 'classic-serial-canon', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2600, 'moe-cgdct', 'music-performance', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 13371, 'workplace-adult-life', 'seinen-drama', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 2816, 'mystery-detective', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 430, 'dark-fantasy', 'horror-dread', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2565, 'time-parallel-worlds', 'battle-shounen', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 13399, 'moe-cgdct', 'food-craft', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2567, 'comedy-parody', 'food-craft', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2644, 'war-military', 'moe-cgdct', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 2597, 'historical-epic', 'seinen-drama', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 714, 'workplace-adult-life', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 784, 'family-generations', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 2647, 'sci-fi-space', 'cyberpunk-dystopia', 'fable5-audit-x2-2026-08-05', 0.45),
('MANGA', 926, 'historical-epic', 'isekai-reincarnation', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2765, 'cyberpunk-dystopia', 'mecha', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2696, 'grand-adventure', 'battle-shounen', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 2693, 'mystery-detective', 'workplace-adult-life', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 99388, 'slice-of-life-iyashikei', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2778, 'auteur-cinema', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 841, 'moe-cgdct', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 2858, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2755, 'romantic-comedy', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 3368, 'seinen-drama', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 506, 'auteur-cinema', 'classic-serial-canon', 'fable5-audit-secondjudge-2026-08-05', null),
('MANGA', 533, 'grand-adventure', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 2853, 'family-generations', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2822, 'classic-serial-canon', 'battle-shounen', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 2826, 'battle-shounen', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 2892, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 746, 'workplace-adult-life', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2905, 'moe-cgdct', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 753, 'cyberpunk-dystopia', 'sci-fi-space', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2898, 'bl-yuri', 'classic-serial-canon', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 2872, 'battle-shounen', 'crime-underworld', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 2893, 'moe-cgdct', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 976, 'romance-slow-burn', 'bl-yuri', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 2867, 'moe-cgdct', 'idol-showbiz', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2975, 'grand-adventure', 'kids-family', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2949, 'isekai-reincarnation', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 2954, 'grand-adventure', 'battle-shounen', 'fable5-audit-secondjudge-2026-08-05', null),
('ANIME', 2953, 'battle-shounen', 'mystery-detective', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2901, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 2982, 'cyberpunk-dystopia', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 763, 'seinen-drama', 'coming-of-age', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 761, 'romance-slow-burn', 'idol-showbiz', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 2956, 'sword-samurai', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 757, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.85),
('ANIME', 2976, 'battle-shounen', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 2985, 'sci-fi-space', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 2993, 'auteur-cinema', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 3004, 'mecha', 'arthouse-experimental', 'fable5-audit-x2-2026-08-05', 0.8),
('MANGA', 779, 'coming-of-age', 'crime-underworld', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3327, 'moe-cgdct', 'idol-showbiz', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 3664, 'cyberpunk-dystopia', 'mecha', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 820, 'dark-fantasy', 'crime-underworld', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3609, 'historical-epic', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3481, 'sci-fi-space', 'tragedy-tearjerker', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 3380, 'romantic-comedy', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.8),
('ANIME', 3670, 'sci-fi-space', 'moe-cgdct', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3943, 'classic-serial-canon', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.75),
('MANGA', 828, 'moe-cgdct', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3699, 'sci-fi-space', 'classic-serial-canon', 'fable5-audit-x2-2026-08-05', 0.4),
('ANIME', 3681, 'classic-serial-canon', 'quiet-melancholy', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 3704, 'classic-serial-canon', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3617, 'mystery-detective', 'crime-underworld', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 848, 'workplace-adult-life', 'gekiga-alternative', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 827, 'classic-serial-canon', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3625, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 3622, 'workplace-adult-life', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3743, 'mystery-detective', 'workplace-adult-life', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3796, 'quiet-melancholy', 'seinen-drama', 'fable5-audit-x2-2026-08-05', 0.4),
('ANIME', 3715, 'seinen-drama', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3608, 'bl-yuri', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3560, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.75),
('MANGA', 947, 'moe-cgdct', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 3584, 'family-generations', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 893, 'historical-epic', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 911, 'sword-samurai', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.75),
('MANGA', 885, 'dark-fantasy', 'horror-dread', 'fable5-audit-x2-2026-08-05', 0.8),
('ANIME', 3580, 'battle-shounen', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 3836, 'battle-shounen', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3808, 'mecha', 'grand-adventure', 'fable5-audit-x2-2026-08-05', 0.5),
('MANGA', 920, 'family-generations', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.85),
('ANIME', 3730, 'sci-fi-space', 'arthouse-experimental', 'fable5-audit-x2-2026-08-05', 0.4),
('ANIME', 3735, 'kids-family', 'quiet-melancholy', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 3799, 'sci-fi-space', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.85),
('ANIME', 3825, 'quiet-melancholy', 'coming-of-age', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 4570, 'cyberpunk-dystopia', 'kids-family', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3718, 'sword-samurai', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 3737, 'classic-serial-canon', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 3734, 'romantic-comedy', 'kids-family', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 3813, 'psychological-thriller', 'quiet-melancholy', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3840, 'crime-underworld', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.45),
('MANGA', 963, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 1098, 'coming-of-age', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('MANGA', 991, 'gekiga-alternative', 'crime-underworld', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3758, 'moe-cgdct', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 3838, 'ecchi-fanservice', 'supernatural-yokai', 'fable5-audit-x2-2026-08-05', 0.4),
('ANIME', 3757, 'sci-fi-space', 'moe-cgdct', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 972, 'classic-serial-canon', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 3819, 'romantic-comedy', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.6),
('MANGA', 971, 'seinen-drama', 'mystery-detective', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 5699, 'workplace-adult-life', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 3871, 'family-generations', 'food-craft', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3908, 'quiet-melancholy', 'sports-competition', 'fable5-audit-x2-2026-08-05', 0.8),
('MANGA', 996, 'time-parallel-worlds', 'dark-fantasy', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3923, 'classic-serial-canon', 'war-military', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3929, 'idol-showbiz', 'bl-yuri', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 5388, 'moe-cgdct', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3902, 'sports-competition', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.55),
('ANIME', 3891, 'cyberpunk-dystopia', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 3882, 'supernatural-yokai', 'mystery-detective', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 4000, 'supernatural-yokai', 'romance-slow-burn', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3981, 'romantic-comedy', 'slice-of-life-iyashikei', 'fable5-audit-x2-2026-08-05', 0.6),
('ANIME', 3983, 'battle-shounen', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.45),
('ANIME', 3991, 'time-parallel-worlds', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.55),
('MANGA', 1041, 'supernatural-yokai', 'moe-cgdct', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 4007, 'grand-adventure', 'battle-shounen', 'fable5-audit-x2-2026-08-05', 0.7),
('ANIME', 4080, 'ecchi-fanservice', 'romantic-comedy', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3971, 'coming-of-age', 'kids-family', 'fable5-audit-x2-2026-08-05', 0.5),
('ANIME', 3986, 'romantic-comedy', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.75),
('ANIME', 4037, 'romantic-comedy', 'comedy-parody', 'fable5-audit-x2-2026-08-05', 0.65),
('ANIME', 4052, 'romance-slow-burn', 'classic-serial-canon', 'fable5-audit-x2-2026-08-05', 0.4)
on conflict (media_type, media_id) do update
  set demote_realm = excluded.demote_realm,
      promote_realm = excluded.promote_realm,
      source = excluded.source,
      conf = excluded.conf;

-- ---------------------------------------------------------------------------
-- 3) media_realm_membership_effective — three-layer redefinition.
--    Layer 1+2 (base + clamp) byte-identical to 20260802123000; layer 3 applies
--    the override weight swap. Column contract unchanged:
--    (media_type, media_id, realm, family, weight, rules_weight, delta).
-- ---------------------------------------------------------------------------

create or replace view public.media_realm_membership_effective
with (security_invoker = true)
as
with base as (
  select
    coalesce(m.media_type, d.media_type) as media_type,
    coalesce(m.media_id, d.media_id) as media_id,
    coalesce(m.realm, d.realm) as realm,
    coalesce(m.family, rm.family) as family,
    coalesce(m.weight, 0::real) as rules_weight,
    coalesce(d.delta, 0::real) as delta
  from public.media_realm_membership m
  full outer join public.media_realm_membership_delta d
    on d.media_type = m.media_type
   and d.media_id = m.media_id
   and d.realm = m.realm
  left join public.realm_meta rm
    on rm.realm = coalesce(m.realm, d.realm)
),
ov as materialized (
  -- Active overrides + their layer-1+2 weights, via indexed point lookups
  -- (media_realm_membership_uidx / media_realm_membership_delta_pkey) so this
  -- stays O(overrides), not O(view). Inert when the demote realm holds no
  -- positive layer-1+2 weight (nothing to move).
  select
    o.media_type,
    o.media_id,
    o.demote_realm,
    o.promote_realm,
    dw.w as w_demote_old,
    pw.w as w_promote_old,
    pw.found as promote_row_exists
  from public.realm_audit_overrides o
  cross join lateral (
    select least(1.0, greatest(0.0,
             coalesce((select dm.weight from public.media_realm_membership dm
                       where dm.media_type = o.media_type
                         and dm.media_id = o.media_id
                         and dm.realm = o.demote_realm), 0::real)
           + coalesce((select dd.delta from public.media_realm_membership_delta dd
                       where dd.media_type = o.media_type
                         and dd.media_id = o.media_id
                         and dd.realm = o.demote_realm), 0::real)
          ))::real as w
  ) dw
  cross join lateral (
    select
      least(1.0, greatest(0.0, coalesce(pm.weight, 0::real) + coalesce(pd.delta, 0::real)))::real as w,
      (pm.media_id is not null or pd.media_id is not null) as found
    from (select 1) one
    left join public.media_realm_membership pm
      on pm.media_type = o.media_type
     and pm.media_id = o.media_id
     and pm.realm = o.promote_realm
    left join public.media_realm_membership_delta pd
      on pd.media_type = o.media_type
     and pd.media_id = o.media_id
     and pd.realm = o.promote_realm
  ) pw
  where dw.w > 0
)
select z.media_type, z.media_id, z.realm, z.family, z.weight, z.rules_weight, z.delta
from (
  select
    s.media_type,
    s.media_id,
    s.realm,
    s.family,
    (case
       -- demote row of an active override: swap down (least of the two old
       -- weights), or 60% of its own old weight when there is no live promote
       -- weight to swap with (missing/zero) or the weights are exactly tied.
       when od.media_id is not null then
         case
           when od.w_promote_old > 0 and od.w_promote_old <> od.w_demote_old
             then least(od.w_demote_old, od.w_promote_old)
           else 0.6 * od.w_demote_old
         end
       -- promote row of an active override: swap up (greatest of the two).
       when op.media_id is not null then greatest(op.w_demote_old, op.w_promote_old)
       -- everyone else: layer-1+2 weight, untouched.
       else s.weight
     end)::real as weight,
    s.rules_weight,
    s.delta
  from (
    select
      b.media_type, b.media_id, b.realm, b.family,
      least(1.0, greatest(0.0, b.rules_weight + b.delta))::real as weight,
      b.rules_weight, b.delta
    from base b
  ) s
  left join ov od
    on od.media_type = s.media_type
   and od.media_id = s.media_id
   and od.demote_realm = s.realm
  left join ov op
    on op.media_type = s.media_type
   and op.media_id = s.media_id
   and op.promote_realm = s.realm
) z
where z.weight > 0

union all

-- Promote rows that do not exist in layer 1+2 at all: created with the demoted
-- realm's old weight; family from realm_meta; rules_weight/delta report 0
-- (same convention as delta-only rows in 20260802123000).
select
  o.media_type,
  o.media_id,
  o.promote_realm as realm,
  rm.family,
  o.w_demote_old as weight,
  0::real as rules_weight,
  0::real as delta
from ov o
left join public.realm_meta rm
  on rm.realm = o.promote_realm
where not o.promote_row_exists;

comment on view public.media_realm_membership_effective is
  'Three layers since 20260805110000: rules media_realm_membership + media_realm_membership_delta (±0.2, clamped [0,1]) + realm_audit_overrides weight swap (audited top-realm corrections; promote strictly above demote per overridden title). Similarity gates, tier rebuild, and deck stratification read this; the rules matview stays inspectable.';

grant select on public.media_realm_membership_effective to anon, authenticated, service_role;

commit;
