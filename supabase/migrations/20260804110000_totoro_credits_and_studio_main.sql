-- 20260804110000_totoro_credits_and_studio_main.sql
--
-- Realm repair, Phase 1 Fixes 1+2 — loop 2 (post-acceptance repairs).
-- Evidence: reports/realm-repair/m1-verify.md (G2 FAIL + G3 FAIL sections).
--
-- Fix A (G2 — Totoro credits backfill, DATA gap, not RPC logic):
--   My Neighbor Totoro (anime id 221, AniList 523) had ZERO rows in
--   anime_staff and anime_studios, so the craft multiplier in
--   recommend_ids_similar_to_seeds could never fire against Spirited Away
--   (111) and Totoro ranked #48 instead of top-25 (m1-verify.md G2 trace).
--   This migration inserts Totoro's core credits, resolving entity ids from
--   the existing sibling-film rows (never hardcoded):
--     - anime_staff:   Hayao Miyazaki, role 'Original Creator'
--         (staff_id subselected from Spirited Away's own credit row)
--     - anime_studios: Studio Ghibli
--         (studio_id subselected from Spirited Away's own credit row;
--          role left NULL, matching every sibling Ghibli row)
--
--   Role choice note (deviation from the literal "Director" instruction,
--   forced by schema): anime_staff has UNIQUE (anime_id, staff_id) — one
--   role row per person per film. The dataset's convention for
--   Miyazaki-directed Ghibli films is a single 'Original Creator' row
--   (Spirited Away 111, Princess Mononoke 200, Ponyo 374 all carry exactly
--   that; none carries a 'Director' row for him). 'Original Creator' is also
--   the only single-row choice that lets the craft channel fire vs SA:
--   the RPC's shared_author test requires role ilike '%creator%' on BOTH
--   sides (SA side is 'Original Creator'), while its shared_creator test
--   requires '%director%' on both sides — and SA has no Miyazaki
--   '%director%' row, so a 'Director' row on Totoro would contribute
--   nothing against this seed. With these two inserts the craft multiplier
--   becomes 1 + 0.5 (shared_author) + 0.15 (shared_studio) = 1.65,
--   matching the Verifier's projected score 0.346 (~rank #9).
--
-- Fix B (G3 — main-studio restriction on shared_studio): DOCUMENTED SKIP.
--   The plan was to restrict the shared_studio EXISTS to main-studio credit
--   rows so Studio Hibari's animation-cooperation credit on Spirited Away
--   stops handing Toilet-bound Hanako-kun S2 a +15% craft boost. Live
--   inspection (2026-08-04) shows NO main-studio flag exists anywhere:
--     - anime_studios.role is NULL on 29,830 of 30,005 rows (the other 175
--       are 'Animation' annotations from an early import batch); SA's
--       Ghibli row and its Hibari cooperation row are both role NULL,
--       i.e. indistinguishable at the credit level.
--     - anime_studios.role_notes is NULL on all 30,005 rows.
--     - No is_main/isMain column or convention exists in any table or
--       migration; bulk-import-anime fetches AniList `studios { nodes }`,
--       so the per-edge isMain flag was never captured.
--     - studios.is_animation_studio cannot stand in for it: Studio Hibari
--       is itself an animation studio (is_animation_studio = true), so the
--       filter would not remove the bogus cooperation-credit match.
--   Per loop-2 scope rules we do not invent a heuristic; the function is
--   left unchanged and G3 is recorded SOFT-FAIL with the tag-space root
--   cause (Hanako's cosine 0.3053 > Wolf Children's 0.2384 — Fix 4 /
--   descriptor-pass territory, m1-verify.md G3 lever 2). The missing data
--   is AniList's studio-edge isMain; capturing it is importer work, not a
--   migration.
--
-- Idempotent: INSERT ... SELECT with ON CONFLICT DO NOTHING against the
-- natural unique keys (anime_id, staff_id) / (anime_id, studio_id).
-- No UPDATE/DELETE statements.

-- Fix A.1 — Totoro staff credit: Hayao Miyazaki, 'Original Creator'.
-- staff_id resolved from Spirited Away's existing credit row.
insert into public.anime_staff (anime_id, staff_id, role)
select a.id, s.staff_id, 'Original Creator'
from public.anime a
join public.anime_staff s on s.anime_id = 111 and s.role = 'Original Creator'
join public.staff st on st.id = s.staff_id and st.name_full = 'Hayao Miyazaki'
where a.id = 221
on conflict (anime_id, staff_id) do nothing;

-- Fix A.2 — Totoro studio credit: Studio Ghibli (role NULL, sibling
-- convention). studio_id resolved from Spirited Away's existing credit row.
insert into public.anime_studios (anime_id, studio_id)
select a.id, g.studio_id
from public.anime a
join public.anime_studios g on g.anime_id = 111
join public.studios st on st.id = g.studio_id and st.name = 'Studio Ghibli'
where a.id = 221
on conflict (anime_id, studio_id) do nothing;
