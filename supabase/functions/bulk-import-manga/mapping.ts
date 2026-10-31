// Manga catalog mapping. AniList media becomes manga rows plus optional chapter
// and volume placeholders, authors, tags, characters, staff and source-owned
// relations. Anime mapping stays in bulk-import-anime; the row shapes differ.

const SUPPORTED_MEDIA_RELATIONS = new Set(['SOURCE', 'ADAPTATION', 'PREQUEL', 'SEQUEL', 'SIDE_STORY', 'SPIN_OFF']);

// Primary catalog writes throw. Optional enrichments (external links, chapter and
// volume placeholders, authors, tags, characters, staff, their join rows, and
// media_relations) record the returned error and continue, so they cannot hide a
// failed primary write.
function noteOptionalFailure(results: { errors: number }, error: unknown, label: string): boolean {
  if (!error) return false;
  console.error(label, error);
  results.errors++;
  return true;
}

// deno-lint-ignore no-explicit-any
export async function processMangaItem(
  supabase: any,
  manga: any,
  results: any,
  includeRelations: boolean,
  includeChapters: boolean,
  includeVolumes: boolean,
  forceRefresh: boolean,
  maxPlaceholderChapters: number,
  maxPlaceholderVolumes: number
) {
  const updatedAtAnilist = manga.updatedAt ? new Date(manga.updatedAt * 1000).toISOString() : null;
  const { data: existing, error: existingError } = await supabase
    .from('manga')
    .select('id, updated_at_anilist')
    .eq('anilist_id', manga.id)
    .maybeSingle();
  if (existingError) {
    console.error('Existing manga lookup failed:', existingError);
    throw existingError;
  }
  const isStale = forceRefresh || !existing || !existing.updated_at_anilist || (updatedAtAnilist && existing.updated_at_anilist !== updatedAtAnilist);
  if (existing && !isStale) {
    const { error: updateError } = await supabase.from('manga').update({ last_synced_at: new Date().toISOString() }).eq('id', existing.id);
    if (updateError) {
      console.error('manga update failed:', updateError);
      throw updateError;
    }
    return;
  }

  const mangaData = {
    anilist_id: manga.id,
    mal_id: manga.idMal,
    title_english: manga.title?.english,
    title_romaji: manga.title?.romaji,
    title_native: manga.title?.native,
    title_synonyms: manga.synonyms,
    cover_image_large: manga.coverImage?.large,
    cover_image_medium: manga.coverImage?.medium,
    cover_image_color: manga.coverImage?.color,
    banner_image: manga.bannerImage,
    format: manga.format,
    status: manga.status,
    description: manga.description,
    chapters: manga.chapters,
    volumes: manga.volumes,
    next_chapter_number: null as number | null,
    next_chapter_at: null as string | null,
    start_date_year: manga.startDate?.year,
    start_date_month: manga.startDate?.month,
    start_date_day: manga.startDate?.day,
    end_date_year: manga.endDate?.year,
    end_date_month: manga.endDate?.month,
    end_date_day: manga.endDate?.day,
    average_score: manga.averageScore,
    mean_score: manga.meanScore,
    popularity: manga.popularity,
    trending: manga.trending,
    favourites: manga.favourites,
    genres: manga.genres,
    source: manga.source,
    country_of_origin: manga.countryOfOrigin,
    is_adult: manga.isAdult,
    site_url: manga.siteUrl,
    synopsis_enhanced_state: 'pending',
    updated_at_anilist: updatedAtAnilist,
    last_synced_at: new Date().toISOString()
  };
  const { data: insertedManga, error: mangaError } = await supabase.from('manga').upsert(mangaData, { onConflict: 'anilist_id' }).select('id').single();
  if (mangaError) throw mangaError; results.manga++;

  // External links (read on...) from AniList externalLinks
  if (Array.isArray(manga.externalLinks) && manga.externalLinks.length > 0) {
    for (const link of manga.externalLinks) {
      const url = link?.url;
      if (!url || typeof url !== 'string' || !url.startsWith('http')) continue;
      const payload = {
        media_type: 'MANGA',
        media_id: insertedManga.id,
        site: link?.site ?? null,
        url,
        language: link?.language ?? null,
        color: link?.color ?? null,
        is_disabled: false,
      };
      const { error } = await supabase.from('external_links').upsert(payload, { onConflict: 'media_type,media_id,url' });
      noteOptionalFailure(results, error, 'external_links upsert error:');
    }
  }

  // Chapters
  // AniList does not provide per-chapter rows; only materialize placeholders when explicitly requested.
  // Never delete existing rows here because chapter enrichment owns canonical chapter coverage.
  if (includeChapters && maxPlaceholderChapters > 0 && manga.chapters && manga.chapters > 0) {
    const { count: existingCount, error: countError } = await supabase
      .from('chapters')
      .select('*', { count: 'exact', head: true })
      .eq('manga_id', insertedManga.id);
    if (noteOptionalFailure(results, countError, 'chapters count failed:')) {
      // Skip placeholder inserts when the existing-row count could not be read.
    } else if ((existingCount ?? 0) === 0) {
      const count = Math.min(manga.chapters, maxPlaceholderChapters);
      const rows = Array.from({ length: count }, (_, i) => ({ manga_id: insertedManga.id, number: i + 1, title: `Chapter ${i + 1}` }));
      const { error } = await supabase.from('chapters').insert(rows);
      if (!noteOptionalFailure(results, error, 'chapters insert error:')) results.chapters += rows.length;
    }
  }

  // Volumes
  // AniList does not provide per-volume rows; only materialize placeholders when explicitly requested.
  // Never delete existing rows here because downstream enrichment can provide richer data.
  if (includeVolumes && maxPlaceholderVolumes > 0 && manga.volumes && manga.volumes > 0) {
    const { count: existingCount, error: countError } = await supabase
      .from('volumes')
      .select('*', { count: 'exact', head: true })
      .eq('manga_id', insertedManga.id);
    if (noteOptionalFailure(results, countError, 'volumes count failed:')) {
      // Skip placeholder inserts when the existing-row count could not be read.
    } else if ((existingCount ?? 0) === 0) {
      const count = Math.min(manga.volumes, maxPlaceholderVolumes);
      const rows = Array.from({ length: count }, (_, i) => ({ manga_id: insertedManga.id, number: i + 1, title: `Volume ${i + 1}`, cover_image_large: null, cover_image_medium: null }));
      const { error } = await supabase.from('volumes').insert(rows);
      if (!noteOptionalFailure(results, error, 'volumes insert error:')) results.volumes += rows.length;
    }
  }

  // Authors (from staff nodes)
  if (includeRelations && manga.staff?.nodes && manga.staff?.edges) {
    for (let i = 0; i < manga.staff.nodes.length; i++) {
      const person = manga.staff.nodes[i];
      const edge = manga.staff.edges[i];
      const { data: au, error: e } = await supabase
        .from('authors')
        .upsert({ anilist_id: person.id, name_full: person.name?.full, name_native: person.name?.native, image_large: person.image?.large, description: person.description, primary_occupations: person.primaryOccupations }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (noteOptionalFailure(results, e, 'authors upsert error:') || !au) continue;
      const { error: linkError } = await supabase.from('manga_authors').upsert({ manga_id: insertedManga.id, author_id: au.id, role: edge?.role });
      if (noteOptionalFailure(results, linkError, 'manga_authors upsert error:')) continue;
      results.relationships++; results.authors++;
    }
  }

  // Tags
  if (includeRelations && manga.tags) {
    for (const tag of manga.tags) {
      const { data: tg, error: e } = await supabase
        .from('tags')
        .upsert({ anilist_id: tag.id, name: tag.name, description: tag.description, category: tag.category, is_general_spoiler: tag.isGeneralSpoiler, is_media_spoiler: tag.isMediaSpoiler, is_adult: tag.isAdult }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (noteOptionalFailure(results, e, 'tags upsert error:') || !tg) continue;
      const { error: linkError } = await supabase.from('manga_tags').upsert({ manga_id: insertedManga.id, tag_id: tg.id, rank: tag.rank ?? 0 });
      if (noteOptionalFailure(results, linkError, 'manga_tags upsert error:')) continue;
      results.relationships++; results.tags++;
    }
  }

  // Characters
  if (includeRelations && manga.characters?.nodes && manga.characters?.edges) {
    for (let i = 0; i < manga.characters.nodes.length; i++) {
      const char = manga.characters.nodes[i];
      const edge = manga.characters.edges[i];
      const { data: ch, error: e } = await supabase
        .from('characters')
        .upsert({ anilist_id: char.id, name_full: char.name?.full, name_native: char.name?.native, image_large: char.image?.large, description: char.description, gender: char.gender, age: char.age }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (noteOptionalFailure(results, e, 'characters upsert error:') || !ch) continue;
      const { error: linkError } = await supabase.from('manga_characters').upsert({ manga_id: insertedManga.id, character_id: ch.id, role: edge?.role });
      if (noteOptionalFailure(results, linkError, 'manga_characters upsert error:')) continue;
      results.relationships++; results.characters++;
    }
  }

  // Staff (editors/publishers/etc.)
  if (includeRelations && manga.staff?.nodes && manga.staff?.edges) {
    for (let i = 0; i < manga.staff.nodes.length; i++) {
      const person = manga.staff.nodes[i];
      const edge = manga.staff.edges[i];
      const { data: stf, error: e } = await supabase
        .from('staff')
        .upsert({ anilist_id: person.id, name_full: person.name?.full, name_native: person.name?.native, image_large: person.image?.large, description: person.description, primary_occupations: person.primaryOccupations }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (noteOptionalFailure(results, e, 'staff upsert error:') || !stf) continue;
      const { error: linkError } = await supabase.from('manga_staff').upsert({ manga_id: insertedManga.id, staff_id: stf.id, role: edge?.role });
      if (noteOptionalFailure(results, linkError, 'manga_staff upsert error:')) continue;
      results.relationships++; results.staff++;
    }
  }

  if (includeRelations) {
    await replaceMediaRelationsForSource(supabase, 'MANGA', insertedManga.id, manga.relations?.edges, results);
  }
}

function normalizeRelationType(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const normalized = raw.trim().toUpperCase();
  return SUPPORTED_MEDIA_RELATIONS.has(normalized) ? normalized : null;
}

function normalizeAniListMediaType(raw: unknown): 'ANIME' | 'MANGA' | null {
  if (typeof raw !== 'string') return null;
  const normalized = raw.trim().toUpperCase();
  if (normalized === 'ANIME' || normalized === 'MANGA') return normalized;
  return null;
}

// deno-lint-ignore no-explicit-any
async function resolveLocalMediaId(supabase: any, mediaType: 'ANIME' | 'MANGA', anilistId: number, results: { errors: number }): Promise<number | null> {
  const table = mediaType === 'ANIME' ? 'anime' : 'manga';
  const { data, error } = await supabase
    .from(table)
    .select('id')
    .eq('anilist_id', anilistId)
    .maybeSingle();
  if (noteOptionalFailure(results, error, 'media_relations target lookup failed:')) return null;
  return data?.id ?? null;
}

// deno-lint-ignore no-explicit-any
async function replaceMediaRelationsForSource(
  supabase: any,
  fromMediaType: 'ANIME' | 'MANGA',
  fromMediaId: number,
  relationEdges: any[] | undefined,
  results: any
) {
  const { error: deleteError } = await supabase
    .from('media_relations')
    .delete()
    .eq('from_media_type', fromMediaType)
    .eq('from_media_id', fromMediaId)
    .eq('source', 'anilist');
  if (noteOptionalFailure(results, deleteError, 'media_relations delete failed:')) return;

  if (!Array.isArray(relationEdges) || relationEdges.length == 0) {
    return;
  }

  for (const edge of relationEdges) {
    const relationType = normalizeRelationType(edge?.relationType);
    const targetType = normalizeAniListMediaType(edge?.node?.type);
    const targetAniListId = Number(edge?.node?.id);
    if (!relationType || !targetType || !Number.isFinite(targetAniListId)) {
      continue;
    }

    const targetMediaId = await resolveLocalMediaId(supabase, targetType, targetAniListId, results);
    if (!targetMediaId) {
      continue;
    }

    const { error } = await supabase
      .from('media_relations')
      .upsert(
        {
          from_media_type: fromMediaType,
          from_media_id: fromMediaId,
          relation_type: relationType,
          to_media_type: targetType,
          to_media_id: targetMediaId,
          source: 'anilist',
        },
        { onConflict: 'from_media_type,from_media_id,relation_type,to_media_type,to_media_id,source' }
      );
    if (noteOptionalFailure(results, error, 'media_relations upsert failed:')) continue;
    results.relationships++;
  }
}
