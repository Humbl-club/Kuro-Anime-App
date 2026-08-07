# Baseline capture (20260807000000_baseline_capture_v1.sql)

Captured 2026-08-06/07 from the live production database (project
`bkdifromsqxkndnllmdj`) via Supabase Management API **read-only** catalog
queries (`information_schema`, `pg_catalog`, `pg_get_viewdef`,
`pg_get_functiondef`, `pg_policies`, `cron.job`). It records, as a real
migration, the schema that previously existed only outside the chain:

- 24 core catalog / user-list / comments / `import_state` tables that lived
  only in `legacy_sql/` (plus `external_links`, same situation),
- `import_runs`, `import_locks`, and the `acquire_import_lock` /
  `release_import_lock` RPCs (production-only),
- the 7 `mv_*` materialized views + their 7 prod indexes + 7 **new** unique
  `(id)` indexes enabling `REFRESH MATERIALIZED VIEW CONCURRENTLY`,
- the `kuro-refresh-matviews` cron job (schedule/command verbatim from
  `cron.job`),
- `create_club_rail`, `create_club_poll`, `club_rail_item_reactions` —
  originals lost when the four 2026-02-15 migrations were hollowed to `;`,
- two remote-only trigger functions (`update_updated_at_column`,
  `normalize_description`) that prod triggers depend on.

Everything is guarded (`create ... if not exists`, `do $$ ... if not exists`,
dependency probes on `auth.users` / club tables / executor functions /
pg_cron), so applying over production is a no-op except the intentional
additions: the 7 matview unique indexes and the idempotent cron
re-registration (unschedule-by-name + schedule).

## What remains non-replayable

- **Data.** Table contents and sequence current values are not captured;
  a fresh rebuild gets empty tables and sequences starting at 1.
- **Supabase platform objects.** `auth.*`, `storage.*`, the
  `supabase_realtime` publication, and the `anon` / `authenticated` /
  `service_role` roles are provisioned by the platform, not migrations.
  Statements depending on them are dep-guarded and skip cleanly off-platform.
- **Extensions** (`pg_cron`, `pg_net`, `pg_trgm`, ...). The cron section
  self-guards on `pg_extension`; it does not install pg_cron.
- **The hollowed files' original SQL** (20260215124919 / 124946 / 125056 /
  125312). Unrecoverable — the files literally contain `;`. The objects they
  once created were re-captured from prod instead. The four hollow files stay
  in the chain to preserve remote migration history.
- **`media_realm_tier` divergence.** The chain (20260731150000) creates it as
  a materialized view; production has a **plain table** (manually converted,
  rebuilt by `rebuild_media_realm_tier()`). Left as-is; a fresh replay gets
  the matview version.
- **Other cron jobs with embedded secrets** (import/mirror/enrich crons
  carrying `x-import-secret` / anon JWT literals) are deliberately not
  captured — they invoke edge functions and contain credentials.
  `kuro-refresh-matviews` is pure SQL and was safe to capture.

## Residual replay blockers (full chain, fresh DB)

The baseline sits at the end of the chain (20260807000000), so **earlier**
migrations that eagerly touch baseline tables still fail on a from-scratch
replay, before the capture runs. Static scan (2026-08-07) of eager
(non-function-body) statements referencing baseline objects:

- `20260203223000` / `20260203235500` — `create index ... on public.anime/manga`
- `20260206143000` — `alter table public.tags`, policy rebuild on comments
- `20260206150000` / `20260206164200` — `alter table public.import_state`,
  policy on it
- `20260209224945` — `delete from public.import_locks`
- `20260216214050` — not-null alters on `authors` / `tags`
- `20260219003105` / `20260219100003` — `alter publication supabase_realtime
  add table anime_user_lists, manga_user_lists`
- `20260219003111` / `20260219100004` / `20260219114953` / `20260219120000` —
  not-null/default alters on `anime`, `manga`, `episodes`, `chapters`,
  `external_links`, `anime_user_lists`, `manga_user_lists`
- `20260322110000` — `alter table public.*_user_lists` (verdict columns)
- `20260731060000` / `20260731150000` — chain matviews
  (`media_tag_vectors`, `media_realm_membership`, `realm_affinity`,
  `media_realm_tier`) selecting from `anime` / `manga` / `tags`

Note the capture already includes the *final* prod shape of those tables
(later added columns included), so a replay that reaches 20260807000000 gets
the complete schema; making the chain fully replayable end-to-end requires
guarding or reordering the statements above (out of scope here).

## How replay was / would be tested

Done (2026-08-07, Homebrew PostgreSQL 17.10, throwaway cluster in /tmp):

1. `initdb` + `pg_ctl` scratch instance; `psql -v ON_ERROR_STOP=1 -f
   supabase/migrations/20260807000000_baseline_capture_v1.sql` on an empty
   database — **passes**. 27 tables, 7 matviews, 104/106 constraints (2 club
   FKs dep-skipped), 19/26 policies (7 `auth.uid()` ones dep-skipped), 12/20
   triggers (8 skip on chain-provided functions), 6 functions created.
2. Re-apply after stubbing platform deps (`auth.users`, `auth.uid()`, roles,
   club tables, `is_club_member`) — **passes**, and every previously skipped
   object is created: 106/106 constraints, 26/26 policies. Proves both
   idempotency and full-fidelity on a Supabase-shaped target.
3. Fidelity diffs scratch vs prod captures: 0/386 column diffs (type,
   nullability, default), 0/7 matview definition diffs (modulo whitespace and
   schema qualification), 0 missing constraints/indexes/policies by name.
4. `refresh materialized view concurrently public.mv_anime_trending` —
   **passes** on the fresh unique index.

For a CI equivalent: spin a scratch PG 17 (or `supabase db start` for the
platform pieces), apply the file with `ON_ERROR_STOP=1`, then compare
catalogs against a fresh prod capture as in step 3.
