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
