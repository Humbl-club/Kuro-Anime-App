// Anime catalog mapping. AniList media becomes anime rows plus episodes, studios,
// tags, characters, staff and source-owned relations. Manga mapping is separate.

const SUPPORTED_MEDIA_RELATIONS = new Set(['SOURCE', 'ADAPTATION', 'PREQUEL', 'SEQUEL', 'SIDE_STORY', 'SPIN_OFF']);

// Primary catalog writes throw. Optional enrichments (external links, episodes,
// studios, tags, characters, staff, their join rows, and media_relations) record
// the returned error and continue, so they cannot hide a failed primary write.
function noteOptionalFailure(results: { errors: number }, error: unknown, label: string): boolean {
  if (!error) return false;
  console.error(label, error);
  results.errors++;
  return true;
}

// deno-lint-ignore no-explicit-any
export async function processAnimeItem(supabase: any, anime: any, results: any, includeRelations: boolean, includeEpisodes: boolean, forceRefresh: boolean) {
  const updatedAtAnilist = anime.updatedAt ? new Date(anime.updatedAt * 1000).toISOString() : null;
  const derivedEpisodes =
    anime.episodes ??
    (anime.nextAiringEpisode?.episode && anime.nextAiringEpisode.episode > 1
      ? Math.max(0, Number(anime.nextAiringEpisode.episode) - 1)
      : null);

  const { data: existing, error: existingError } = await supabase
    .from('anime')
    .select('id, updated_at_anilist, episodes, duration')
    .eq('anilist_id', anime.id)
    .maybeSingle();
  if (existingError) {
    console.error('Existing anime lookup failed:', existingError);
    throw existingError;
  }
  const isStale = forceRefresh || !existing || !existing.updated_at_anilist || (updatedAtAnilist && existing.updated_at_anilist !== updatedAtAnilist);
  if (existing && !isStale) {
    // Even when the AniList payload hasn't changed, airing metadata can drift (next episode),
    // and long-running shows may be missing a total episode count. Keep these fields fresh.
    const patch: any = {
      last_synced_at: new Date().toISOString(),
      next_episode_number: anime.nextAiringEpisode?.episode ?? null,
      next_airing_at: anime.nextAiringEpisode?.airingAt ? new Date(anime.nextAiringEpisode.airingAt * 1000).toISOString() : null,
    };
    if (derivedEpisodes && (!existing.episodes || Number(existing.episodes) < derivedEpisodes)) {
      patch.episodes = derivedEpisodes;
      const dur = anime.duration ?? existing.duration;
      patch.total_duration = dur ? derivedEpisodes * dur : null;
    }
    const { error: updateError } = await supabase.from('anime').update(patch).eq('id', existing.id);
    if (updateError) {
      console.error('anime update failed:', updateError);
      throw updateError;
    }
    return;
  }

  const animeData = {
    anilist_id: anime.id,
    mal_id: anime.idMal,
    title_english: anime.title?.english,
    title_romaji: anime.title?.romaji,
    title_native: anime.title?.native,
    title_synonyms: anime.synonyms,
    cover_image_large: anime.coverImage?.large,
    cover_image_medium: anime.coverImage?.medium,
    cover_image_color: anime.coverImage?.color,
    banner_image: anime.bannerImage,
    format: anime.format,
    status: anime.status,
    description: anime.description,
    // AniList sometimes leaves `episodes` null for long-running RELEASING shows.
    // For UX (and for our card metadata), derive a best-effort "episodes so far" from
    // `nextAiringEpisode.episode - 1` when available.
    episodes: derivedEpisodes,
    duration: anime.duration,
    total_duration: derivedEpisodes && anime.duration ? derivedEpisodes * anime.duration : null,
    season: anime.season,
    season_year: anime.seasonYear,
    next_episode_number: anime.nextAiringEpisode?.episode,
    next_airing_at: anime.nextAiringEpisode?.airingAt ? new Date(anime.nextAiringEpisode.airingAt * 1000).toISOString() : null,
    start_date_year: anime.startDate?.year,
    start_date_month: anime.startDate?.month,
    start_date_day: anime.startDate?.day,
    end_date_year: anime.endDate?.year,
    end_date_month: anime.endDate?.month,
    end_date_day: anime.endDate?.day,
    average_score: anime.averageScore,
    mean_score: anime.meanScore,
    popularity: anime.popularity,
    trending: anime.trending,
    favourites: anime.favourites,
    genres: anime.genres,
    source: anime.source,
    country_of_origin: anime.countryOfOrigin,
    is_adult: anime.isAdult,
    site_url: anime.siteUrl,
    synopsis_enhanced_state: 'pending',
    updated_at_anilist: updatedAtAnilist,
    last_synced_at: new Date().toISOString()
  };
  const { data: insertedAnime, error: animeError } = await supabase.from('anime').upsert(animeData, { onConflict: 'anilist_id' }).select('id').single();
  if (animeError) throw animeError; results.anime++;

  // External links (watch on...) from AniList externalLinks
  if (Array.isArray(anime.externalLinks) && anime.externalLinks.length > 0) {
    for (const link of anime.externalLinks) {
      const url = link?.url;
      if (!url || typeof url !== 'string' || !url.startsWith('http')) continue;
      const payload = {
        media_type: 'ANIME',
        media_id: insertedAnime.id,
        site: link?.site ?? null,
        url,
        language: link?.language ?? null,
        color: link?.color ?? null,
        is_disabled: false,
      };
      const { error } = await supabase.from('external_links').upsert(payload, { onConflict: 'media_type,media_id,url' });
      // External links are optional and do not fail the page.
      noteOptionalFailure(results, error, 'external_links upsert error:');
    }
  }

  if (includeEpisodes && anime.streamingEpisodes && anime.streamingEpisodes.length > 0) {
    const { error: episodeDeleteError } = await supabase.from('episodes').delete().eq('anime_id', insertedAnime.id);
    if (noteOptionalFailure(results, episodeDeleteError, 'episodes delete error:')) {
      // Leave existing episode rows in place when the delete did not succeed.
    } else {
      for (let i = 0; i < anime.streamingEpisodes.length; i++) {
        const ep = anime.streamingEpisodes[i];
        const match = ep.title?.match(/Episode\s+(\d+)/i);
        const number = match ? parseInt(match[1]) : (i + 1);
        const episodeData = {
          anime_id: insertedAnime.id,
          number,
          title: ep.title,
          thumbnail: ep.thumbnail,
          duration: anime.duration || null,
          stream_url: ep.url ?? null,
          stream_site: ep.site ?? null,
        };
        const { error: e } = await supabase.from('episodes').insert(episodeData);
        if (noteOptionalFailure(results, e, 'episodes insert error:')) continue;
        results.episodes++;
      }
    }
  }
  // Studios
  if (includeRelations && anime.studios?.nodes) {
    for (const studio of anime.studios.nodes) {
      const { data: st, error: e } = await supabase
        .from('studios')
        .upsert({ anilist_id: studio.id, name: studio.name, is_animation_studio: studio.isAnimationStudio, site_url: studio.siteUrl, favourites: studio.favourites }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (noteOptionalFailure(results, e, 'studios upsert error:') || !st) continue;
      const { error: linkError } = await supabase.from('anime_studios').upsert({ anime_id: insertedAnime.id, studio_id: st.id });
      if (noteOptionalFailure(results, linkError, 'anime_studios upsert error:')) continue;
      results.relationships++; results.studios++;
    }
  }
  // Tags
  if (includeRelations && anime.tags) {
    for (const tag of anime.tags) {
      const { data: tg, error: e } = await supabase
        .from('tags')
        .upsert({ anilist_id: tag.id, name: tag.name, description: tag.description, category: tag.category, is_general_spoiler: tag.isGeneralSpoiler, is_media_spoiler: tag.isMediaSpoiler, is_adult: tag.isAdult }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (noteOptionalFailure(results, e, 'tags upsert error:') || !tg) continue;
      const { error: linkError } = await supabase.from('anime_tags').upsert({ anime_id: insertedAnime.id, tag_id: tg.id, rank: tag.rank ?? 0 });
      if (noteOptionalFailure(results, linkError, 'anime_tags upsert error:')) continue;
      results.relationships++; results.tags++;
    }
  }
  // Characters
  if (includeRelations && anime.characters?.nodes && anime.characters?.edges) {
    for (let i = 0; i < anime.characters.nodes.length; i++) {
      const char = anime.characters.nodes[i];
      const edge = anime.characters.edges[i];
      const { data: ch, error: e } = await supabase
        .from('characters')
        .upsert({ anilist_id: char.id, name_full: char.name?.full, name_native: char.name?.native, image_large: char.image?.large, description: char.description, gender: char.gender, age: char.age }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (noteOptionalFailure(results, e, 'characters upsert error:') || !ch) continue;
      const { error: linkError } = await supabase.from('anime_characters').upsert({ anime_id: insertedAnime.id, character_id: ch.id, role: edge?.role });
      if (noteOptionalFailure(results, linkError, 'anime_characters upsert error:')) continue;
      results.relationships++; results.characters++;
    }
  }
  // Staff
  if (includeRelations && anime.staff?.nodes && anime.staff?.edges) {
    for (let i = 0; i < anime.staff.nodes.length; i++) {
      const person = anime.staff.nodes[i];
      const edge = anime.staff.edges[i];
      const { data: stf, error: e } = await supabase
        .from('staff')
        .upsert({ anilist_id: person.id, name_full: person.name?.full, name_native: person.name?.native, image_large: person.image?.large, description: person.description, primary_occupations: person.primaryOccupations }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      if (noteOptionalFailure(results, e, 'staff upsert error:') || !stf) continue;
      const { error: linkError } = await supabase.from('anime_staff').upsert({ anime_id: insertedAnime.id, staff_id: stf.id, role: edge?.role });
      if (noteOptionalFailure(results, linkError, 'anime_staff upsert error:')) continue;
      results.relationships++; results.staff++;
    }
  }

  if (includeRelations) {
    await replaceMediaRelationsForSource(supabase, 'ANIME', insertedAnime.id, anime.relations?.edges, results);
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
