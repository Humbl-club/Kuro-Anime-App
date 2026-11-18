# W4 precondition: adult titles in the live catalogue

Read-only query (Management API, `read_only: true`) run by the lead on 2026-11-18 13:01 UTC,
with the owner's 2026-11-18 instruction to finish the open plans:

```sql
select 'anime', count(*) filter (where is_adult), count(*) filter (where genres @> array['Hentai']) from public.anime
union all
select 'manga', count(*) filter (where is_adult), count(*) filter (where genres @> array['Hentai']) from public.manga;
```

| medium | is_adult | genres @> Hentai |
| --- | --- | --- |
| anime | 1713 | 1645 |
| manga | 8499 | 5012 |

## Known limits

Release notes for `20261118100000_search_hidden_adult_v1.sql` (prepared, not applied):

- Rows already staged before the migration are not guarded. The trigger only fires on writes, so an import job
  that is already in `reviewing` keeps any row that was matched to an 18+ title; the row is only re-evaluated if
  it is written again (for example a re-sent chunk that updates it). Finish or cancel such jobs before applying,
  or accept that they keep their existing matches.
- An import row keeps the catalogue's own title for 18+ titles. The guard clears `media_id` and marks the row
  unmatched/`ADULT_NOT_LISTED`, but `title` is whatever the source or the earlier match stored; this migration
  does not scrub or replace it.
- A manual mapping (`resolved_media_id`) onto an 18+ catalogue row is refused with `ADULT_NOT_LISTED` and aborts
  that `prepare_import_chunk_v2` call (like `INVALID_MAPPING`); the client does not offer or send a match for a
  row already marked `ADULT_NOT_LISTED`.
- A manual mapping onto an 18+ row combined with a mismatching `unit_id` is staged as `invalid` (outside the
  guard's `WHEN`), still carrying that media id; an `invalid` row cannot be applied.
