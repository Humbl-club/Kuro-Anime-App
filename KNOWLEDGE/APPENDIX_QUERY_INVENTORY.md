APPENDIX Query Inventory (Client)
=================================

Purpose
- Catalog of Supabase client queries (tables, filters, ordering, ranges) with file anchors for traceability.

Paging (Discover prefetch)
- Kuro/Services/SupabaseService.swift:108
  - from("anime").order("popularity", false).range(offset, offset+pageSize-1)
- Kuro/Services/SupabaseService.swift:160
  - from("manga").order("popularity", false).range(offset, offset+pageSize-1)

Search (one-shot)
- Kuro/Services/SupabaseService.swift:196
  - from("anime").textSearch("title_english,title_romaji,description_normalized", query)
- Kuro/Services/SupabaseService.swift:204
  - from("manga").textSearch("title_english,title_romaji,description", query)

Search (paged with filters)
- Manga: Kuro/Services/SupabaseService.swift:247–265
  - from("manga").textSearch(...)
  - Filters: gt("trending",0), gte("start_date_year",2020), lt("start_date_year",2010), gte("average_score",85).lt("start_date_year",2015)
  - Order: trending desc if facet else popularity desc
  - Range: page window
- Anime: Kuro/Services/SupabaseService.swift:272–292
  - from("anime").textSearch(...)
  - Filters: gt("trending",0), gte("season_year",2020), lt("season_year",2010), gte("average_score",85).lt("season_year",2015), eq("status","RELEASING"), eq("season", <name>).eq("season_year", <year>)
  - Order: trending desc else popularity desc
  - Range: page window

Server-driven sections (Anime)
- Trending: Kuro/Services/SupabaseService.swift:309–312
  - from("anime").gt("trending",0) [optional eq("status","RELEASING")] → order("trending",false) → range(0,limit-1)
- Current season (year-only): Kuro/Services/SupabaseService.swift:319–322
  - from("anime").eq("season_year",yr) [optional eq("status","RELEASING")] → order("popularity",false) → range
- Season (season+year): Kuro/Services/SupabaseService.swift:328–331
  - from("anime").eq("season",season).eq("season_year",year) [optional eq("status","RELEASING")] → order("popularity",false).order("id",false) → range
- Newly added: Kuro/Services/SupabaseService.swift:337–339
  - from("anime").order("created_at",false).order("id",false) → range
- Top rated: Kuro/Services/SupabaseService.swift:345–347
  - from("anime").gte("average_score",minScore).order("average_score",false).order("id",false) → range
- Airing soon: Kuro/Services/SupabaseService.swift:359–363
  - from("anime").gt("next_airing_at",nowISO).lte("next_airing_at",endISO).order("next_airing_at",true) → range

User lists
- Load user lists: Kuro/Services/SupabaseService.swift:419–429
  - from("anime_user_lists").eq("user_id", uid)
  - from("manga_user_lists").eq("user_id", uid)
- Add to list: Kuro/Services/SupabaseService.swift:513
  - from(table).upsert(payload)
- Remove from list: Kuro/Services/SupabaseService.swift:537–539
  - from(table).delete().eq("user_id", uid).eq(idColumn, mediaId)
- Update score: Kuro/Services/SupabaseService.swift:663–665
  - from(table).update({ rating }).eq("user_id", uid).eq(idColumn, mediaId)

Filters by genres
- Kuro/Services/SupabaseService.swift:556–560
  - from("anime").contains("genres", [genre]).order("average_score",false).limit(50)

