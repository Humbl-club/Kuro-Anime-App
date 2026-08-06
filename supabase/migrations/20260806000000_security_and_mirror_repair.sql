-- 2026-08-06: Security + ops repairs from the independent deep review
-- (docs/superpowers/specs/2026-08-06-independent-review.md, wave 2).
--
-- 1) Close the rec-edges write API (probationary grant that outlived its import window):
--    the import is complete, so authenticated no longer needs execute. Proven live:
--    a fresh account injected rating-100000 edges that flow into edges-first serving.
revoke execute on function public.upsert_rec_edges(jsonb) from authenticated;
-- 2) rate_limit_hit is an internal helper; every caller is SECURITY DEFINER (owner
--    executes regardless of grants). Anon/authenticated callers could inflate arbitrary
--    buckets (incl. the shared service_role import bucket) — revoke.
revoke execute on function public.rate_limit_hit(text, integer) from anon, authenticated;
-- 3) Remove the audit-probe poison (created during the security review; no client delete
--    path exists, so this is the cleanup): two fake edges + restore the inflated real edge
--    (Koe no Katachi 16 -> Kimi no Na wa 15, original rating 6003) + audit rate buckets.
delete from public.media_rec_edges where from_media_id in (1900000001, 1900000003);
update public.media_rec_edges set rating = 6003
 where from_media_type = 'ANIME' and from_media_id = 16 and to_media_type = 'ANIME' and to_media_id = 15
   and rating = 100000 and source = 'anilist';
delete from public.rate_limit_buckets where bucket_key like 'audit-%';
-- The served store rows for seed 16 were built with the poisoned rating: re-stale so the
-- driver rebuilds them.
update public.media_similar_seed_state set stale = true
 where seed_media_type = 'ANIME' and seed_media_id = 16;
-- 4) Penalty sign becomes structure, not custom (era-4 convention: negative = demote;
--    a positive row would silently become a boost — the July incident class).
alter table public.editorial_penalty_tags
  drop constraint if exists editorial_penalty_tags_penalty_check;
alter table public.editorial_penalty_tags
  add constraint editorial_penalty_tags_penalty_check check (penalty <= 0);
-- 5) Mirror-cron auth repair (mirror x5 + manga-chapter-enrich x2): their cron commands
--    read empty GUCs (app.settings.import_secret / supabase_url / supabase_anon_key) and
--    have been 401ing nightly since 2026-07-31 (mirror coverage flat 5 days; enrich dead).
--    Transplant executed 2026-08-06 via Management API (remote-only, matching the
--    kuro-import-* pattern — literals stay out of git): all 7 jobs re-armed with literals
--    extracted from kuro-import-anime-hourly's command. Verified post-state via API:
--    mirror jobs have literal + no GUC refs; enrich jobs have literal + URL/anon + 0 GUC
--    refs. NOTE: 20260731020000's GUC pattern remains in the repo for provenance only —
--    re-running it would re-break auth; a future cleanup migration should reconcile.
