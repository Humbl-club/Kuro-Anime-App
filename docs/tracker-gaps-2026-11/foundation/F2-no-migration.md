# F2: no migration is needed for repeat count and dates

Task F2.2 (`LibraryEdit` / `LibraryEntry` v2). Checked on branch `kuro/tracker-gaps` at commit `5a80c1e`
(parent of the F2.2 commit). Every claim below quotes its source.

## Verdict

No `20261110090000_library_edit_v2.sql`. The three columns exist live, the owner may already write them
through PostgREST PATCH, no trigger blocks that, and the durable outbox never carries them. The value range of
`repeat_count` (0...999) is enforced on the client (`LibraryError.invalidValue(field: "repeatCount")`).

Optional owner follow-up, not part of this plan: a server `CHECK (repeat_count between 0 and 999)` if direct
writers other than the app appear.

## 1. The columns exist on both list tables

`supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql`, lines 16-25 (anime, `repeat_count` at 21, `started_raw` / `finished_raw` at 24-25) and 31-40
(manga, 36 and 39-40), applied on 2026-10-08 (see "Migration history caveat" in `CLAUDE.md`: this migration is one of the four
prepared files applied in one approved transaction):

```sql
alter table public.anime_user_lists
  ...
  add column if not exists repeat_count integer not null default 0,
  add column if not exists score_raw numeric,
  add column if not exists score_scale text,
  add column if not exists started_raw text,
  add column if not exists finished_raw text,
```

```sql
alter table public.manga_user_lists
  ...
  add column if not exists repeat_count integer not null default 0,
  ...
  add column if not exists started_raw text,
  add column if not exists finished_raw text,
```

`repeat_count` is `NOT NULL DEFAULT 0`, so the client can never clear it. `started_raw` and `finished_raw` are
free text and nullable, so `.clear` writes `null`.

There is no CHECK on any of the three columns:

```
$ grep -rniE "repeat_count|started_raw|finished_raw" supabase/migrations supabase/prepared-migrations | grep -iE "check|constraint"
(no output)
```

The only files that mention the three columns are `20261007040000_series_home_foundation_v1.sql` (the `alter table`
above) and `20261008110000_import_review_recovery_v2.sql` (import inserts).

## 2. The owner may write them through PATCH

The only policy on each list table is the owner policy for all commands.
`supabase/migrations/20260807000000_baseline_capture_v1.sql:2201` (anime) and `:2369` (manga):

```sql
create policy "Users can manage their own lists" on public.anime_user_lists as permissive for all to authenticated
  using (((( SELECT auth.uid() AS uid))::text = user_id))
  with check (((( SELECT auth.uid() AS uid))::text = user_id));
```

No column grant or revoke narrows UPDATE on the list tables:

```
$ grep -rniE "grant update *\(|revoke update" supabase/migrations supabase/prepared-migrations
supabase/migrations/20261005120000_club_members_role_column_guard.sql:64:revoke update on table public.club_members from anon, authenticated;
supabase/migrations/20261005120000_club_members_role_column_guard.sql:65:grant update (sharing_level) on table public.club_members to authenticated;
supabase/prepared-migrations/20261005120000_club_members_role_column_guard.sql:64:revoke update on table public.club_members from anon, authenticated;
supabase/prepared-migrations/20261005120000_club_members_role_column_guard.sql:65:grant update (sharing_level) on table public.club_members to authenticated;
```

Both matches are `club_members`; none is `anime_user_lists` or `manga_user_lists`. A search for a
`grant ... on ... (anime|manga)_user_lists` statement in the migrations also finds nothing, so the tables keep
the platform default table privileges for `authenticated`, and RLS is the only gate.

## 3. The list triggers do not block it

`supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql`:

- `list_account_write_lock` (lines 74-87), a statement trigger: it only takes
  `pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0))` and `return null`.
- `list_entry_revision_fence` (lines 89-141), a row trigger: on UPDATE it only runs
  `new.server_revision := old.server_revision + 1; new.lifecycle_id := old.lifecycle_id;`.
  A PATCH of the date columns therefore succeeds and advances the revision.
- `series_unit_owner` (lines 3943-3946) fires `before insert or update of unit_id,anime_id` (and
  `unit_id,manga_id`), so a PATCH of `started_raw`, `finished_raw` or `repeat_count` never fires it.

## 4. The durable outbox does not carry dates, so dates take the PATCH leg

`apply_progress_mutations_v1` and the SQLite `ProgressOutbox` carry only position and status
(`LibraryFenceProgressMutation` has `position` and `status`; `LibraryProgress.applyDurableProgress` builds a
`ProgressIntent` from `edit.touchesProgress` and `edit.status`). Everything else in an edit stays on the PATCH
leg: `LibraryEdit.patchBodyOmittingProgress` now includes `repeatCount`, `startedOn` and `finishedOn` next to
rating, notes and verdict.

When a progress intent is waiting, the PATCH leg does not create a fence conflict: the drain adopts the revision
the PATCH advanced. `Packages/KuroModules/Sources/KuroLibrary/LibraryProgress.swift`, `drainProgress()`, inside
`withMutationReservation(keys: heads.map(progressKey), account: account)`:

```swift
if let row = entries[key], row.lifecycleId == head.lifecycleId, row.progress == head.priorPosition,
   let lifecycle = head.lifecycleId, let revision = row.revision {
    try await state.outbox.rebaseUnsent(accountId: head.accountId, medium: head.medium, mediaId: head.mediaId,
        lifecycleId: lifecycle, revision: revision)
}
```

This is the same mechanism that already lets a notes PATCH and a progress mutation share one entry.

## Conclusion

The existing PATCH path is sufficient: F2.2 changes only the client (`LibraryEdit`, `LibraryEntry`,
`SupabaseLibraryBackend.body(for:kind:)`, the always-selected columns and `entry(from:)`). No SQL file is added,
so nothing needs to be applied, deployed or recorded in migration history.
