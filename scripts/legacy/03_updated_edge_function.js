// ============================================
// UPDATED EDGE FUNCTION
// Proper data distribution across normalized tables
// Uses internal IDs + external references
// ============================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ANILIST_API = 'https://graphql.anilist.co';
const DELAY_BETWEEN_REQUESTS = 670; // milliseconds

serve(async (req) => {
  console.log('🚀 UPDATED EDGE FUNCTION: Starting comprehensive import...');
  
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const supabase = createClient(supabaseUrl, supabaseKey);
  
  const { startPage = 1, pagesPerBatch = 5, mediaType = 'ANIME' } = await req.json().catch(() => ({}));
  
  const results = {
    anime: 0,
    manga: 0,
    episodes: 0,
    chapters: 0,
    volumes: 0,
    characters: 0,
    studios: 0,
    authors: 0,
    staff: 0,
    tags: 0,
    relationships: 0,
    errors: 0
  };
  
  try {
    console.log(`📊 Importing pages ${startPage} to ${startPage + pagesPerBatch - 1} for ${mediaType}`);
    
    for (let page = startPage; page < startPage + pagesPerBatch; page++) {
      try {
        console.log(`🔍 Fetching page ${page}...`);
        
        const media = await fetchAniListData(page, mediaType);
        
        if (media.length === 0) {
          console.log(`✅ No more data at page ${page} - import complete!`);
          break;
        }
        
        console.log(`📊 Page ${page}: Processing ${media.length} ${mediaType}`);
        
        for (const item of media) {
          try {
            if (mediaType === 'ANIME') {
              await processAnimeItem(supabase, item, results);
            } else {
              await processMangaItem(supabase, item, results);
            }
          } catch (error) {
            console.error(`❌ Failed to process ${mediaType} ${item.id}:`, error.message);
            results.errors++;
          }
        }
        
        console.log(`✅ Page ${page} complete: ${media.length} ${mediaType} processed`);
        await new Promise(resolve => setTimeout(resolve, DELAY_BETWEEN_REQUESTS));
        
      } catch (error) {
        console.error(`❌ Page ${page} failed:`, error.message);
        results.errors++;
      }
    }
    
    console.log(`✅ Import complete:`, results);
    
    return new Response(JSON.stringify({
      success: true,
      results,
      message: `Import complete! ${mediaType}: ${results.anime + results.manga}, Characters: ${results.characters}, Studios: ${results.studios}`
    }), {
      headers: { "Content-Type": "application/json" }
    });
    
  } catch (error) {
    console.error('❌ Import failed:', error);
    return new Response(JSON.stringify({
      success: false,
      error: error.message
    }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
});

// ============================================
// FETCH DATA FROM ANILIST
// ============================================
async function fetchAniListData(page, mediaType) {
  const query = `
    query ($page: Int, $type: MediaType) {
      Page(page: $page, perPage: 50) {
        pageInfo { total currentPage lastPage hasNextPage }
        media(sort: POPULARITY_DESC, type: $type) {
          id idMal
          title { romaji english native userPreferred }
          synonyms hashtag
          coverImage { extraLarge large medium color }
          bannerImage
          type format status
          description(asHtml: false)
          source countryOfOrigin isAdult
          
          startDate { year month day }
          endDate { year month day }
          
          episodes duration chapters volumes
          season seasonYear
          
          averageScore meanScore
          popularity trending favourites
          
          genres
          
          trailer { id site thumbnail }
          siteUrl updatedAt
          
          nextAiringEpisode {
            id episode airingAt timeUntilAiring
          }
          
          studios {
            nodes {
              id name isAnimationStudio siteUrl favourites
            }
          }
          
          tags {
            id name description category rank
            isGeneralSpoiler isMediaSpoiler isAdult
          }
          
          characters(sort: ROLE, perPage: 10) {
            edges { role }
            nodes {
              id
              name { full native }
              image { large }
              description
              gender age
            }
          }
          
          staff(sort: RELEVANCE, perPage: 10) {
            edges { role }
            nodes {
              id
              name { full native }
              image { large }
              description
              primaryOccupations
            }
          }
        }
      }
    }
  `;
  
  const response = await fetch(ANILIST_API, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query,
      variables: { page, type: mediaType }
    })
  });
  
  const data = await response.json();
  return data?.data?.Page?.media || [];
}

// ============================================
// PROCESS ANIME ITEM
// ============================================
async function processAnimeItem(supabase, anime, results) {
  console.log(`🎬 Processing Anime: ${anime.title?.english || anime.title?.romaji}`);
  
  // 1. INSERT ANIME (with internal ID)
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
    episodes: anime.episodes,
    duration: anime.duration,
    total_duration: anime.episodes && anime.duration ? anime.episodes * anime.duration : null,
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
    updated_at_anilist: anime.updatedAt ? new Date(anime.updatedAt * 1000).toISOString() : null,
    last_synced_at: new Date().toISOString()
  };
  
  const { data: insertedAnime, error: animeError } = await supabase
    .from('anime')
    .upsert(animeData, { onConflict: 'anilist_id' })
    .select('id')
    .single();
    
  if (animeError) throw animeError;
  results.anime++;
  console.log(`✅ Anime inserted with ID: ${insertedAnime.id}`);
  
  // 2. INSERT STUDIOS
  if (anime.studios?.nodes) {
    for (const studio of anime.studios.nodes) {
      // Insert studio
      const { data: insertedStudio, error: studioError } = await supabase
        .from('studios')
        .upsert({
          anilist_id: studio.id,
          name: studio.name,
          is_animation_studio: studio.isAnimationStudio,
          site_url: studio.siteUrl,
          favourites: studio.favourites
        }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      
      if (!studioError && insertedStudio) {
        results.studios++;
        
        // Link anime to studio
        await supabase
          .from('anime_studios')
          .upsert({
            anime_id: insertedAnime.id,
            studio_id: insertedStudio.id,
            role: 'Animation'
          });
        
        results.relationships++;
      }
    }
  }
  
  // 3. INSERT TAGS
  if (anime.tags) {
    for (const tag of anime.tags) {
      // Insert tag
      const { data: insertedTag, error: tagError } = await supabase
        .from('tags')
        .upsert({
          anilist_id: tag.id,
          name: tag.name,
          description: tag.description,
          category: tag.category,
          is_general_spoiler: tag.isGeneralSpoiler,
          is_media_spoiler: tag.isMediaSpoiler,
          is_adult: tag.isAdult
        }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      
      if (!tagError && insertedTag) {
        results.tags++;
        
        // Link anime to tag
        await supabase
          .from('anime_tags')
          .upsert({
            anime_id: insertedAnime.id,
            tag_id: insertedTag.id,
            rank: tag.rank
          });
        
        results.relationships++;
      }
    }
  }
  
  // 4. INSERT CHARACTERS
  if (anime.characters?.nodes && anime.characters?.edges) {
    for (let i = 0; i < anime.characters.nodes.length; i++) {
      const char = anime.characters.nodes[i];
      const edge = anime.characters.edges[i];
      
      // Insert character
      const { data: insertedChar, error: charError } = await supabase
        .from('characters')
        .upsert({
          anilist_id: char.id,
          name_full: char.name?.full,
          name_native: char.name?.native,
          image_large: char.image?.large,
          description: char.description,
          gender: char.gender,
          age: char.age
        }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      
      if (!charError && insertedChar) {
        results.characters++;
        
        // Link anime to character
        await supabase
          .from('anime_characters')
          .upsert({
            anime_id: insertedAnime.id,
            character_id: insertedChar.id,
            role: edge?.role
          });
        
        results.relationships++;
      }
    }
  }
  
  // 5. INSERT STAFF
  if (anime.staff?.nodes && anime.staff?.edges) {
    for (let i = 0; i < anime.staff.nodes.length; i++) {
      const person = anime.staff.nodes[i];
      const edge = anime.staff.edges[i];
      
      // Insert staff
      const { data: insertedStaff, error: staffError } = await supabase
        .from('staff')
        .upsert({
          anilist_id: person.id,
          name_full: person.name?.full,
          name_native: person.name?.native,
          image_large: person.image?.large,
          description: person.description,
          primary_occupations: person.primaryOccupations
        }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      
      if (!staffError && insertedStaff) {
        results.staff++;
        
        // Link anime to staff
        await supabase
          .from('anime_staff')
          .upsert({
            anime_id: insertedAnime.id,
            staff_id: insertedStaff.id,
            role: edge?.role
          });
        
        results.relationships++;
      }
    }
  }
  
  console.log(`✅ Complete: ${anime.title?.english || anime.title?.romaji}`);
}

// ============================================
// PROCESS MANGA ITEM
// ============================================
async function processMangaItem(supabase, manga, results) {
  console.log(`📚 Processing Manga: ${manga.title?.english || manga.title?.romaji}`);
  
  // 1. INSERT MANGA (with internal ID)
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
    updated_at_anilist: manga.updatedAt ? new Date(manga.updatedAt * 1000).toISOString() : null,
    last_synced_at: new Date().toISOString()
  };
  
  const { data: insertedManga, error: mangaError } = await supabase
    .from('manga')
    .upsert(mangaData, { onConflict: 'anilist_id' })
    .select('id')
    .single();
    
  if (mangaError) throw mangaError;
  results.manga++;
  console.log(`✅ Manga inserted with ID: ${insertedManga.id}`);
  
  // 2. INSERT AUTHORS (for manga)
  if (manga.staff?.nodes && manga.staff?.edges) {
    for (let i = 0; i < manga.staff.nodes.length; i++) {
      const person = manga.staff.nodes[i];
      const edge = manga.staff.edges[i];
      
      // Insert author
      const { data: insertedAuthor, error: authorError } = await supabase
        .from('authors')
        .upsert({
          anilist_id: person.id,
          name_full: person.name?.full,
          name_native: person.name?.native,
          image_large: person.image?.large,
          description: person.description
        }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      
      if (!authorError && insertedAuthor) {
        results.authors++;
        
        // Link manga to author
        await supabase
          .from('manga_authors')
          .upsert({
            manga_id: insertedManga.id,
            author_id: insertedAuthor.id,
            role: edge?.role
          });
        
        results.relationships++;
      }
    }
  }
  
  // 3. INSERT TAGS (same as anime)
  if (manga.tags) {
    for (const tag of manga.tags) {
      // Insert tag
      const { data: insertedTag, error: tagError } = await supabase
        .from('tags')
        .upsert({
          anilist_id: tag.id,
          name: tag.name,
          description: tag.description,
          category: tag.category,
          is_general_spoiler: tag.isGeneralSpoiler,
          is_media_spoiler: tag.isMediaSpoiler,
          is_adult: tag.isAdult
        }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      
      if (!tagError && insertedTag) {
        results.tags++;
        
        // Link manga to tag
        await supabase
          .from('manga_tags')
          .upsert({
            manga_id: insertedManga.id,
            tag_id: insertedTag.id,
            rank: tag.rank
          });
        
        results.relationships++;
      }
    }
  }
  
  // 4. INSERT CHARACTERS (same as anime)
  if (manga.characters?.nodes && manga.characters?.edges) {
    for (let i = 0; i < manga.characters.nodes.length; i++) {
      const char = manga.characters.nodes[i];
      const edge = manga.characters.edges[i];
      
      // Insert character
      const { data: insertedChar, error: charError } = await supabase
        .from('characters')
        .upsert({
          anilist_id: char.id,
          name_full: char.name?.full,
          name_native: char.name?.native,
          image_large: char.image?.large,
          description: char.description,
          gender: char.gender,
          age: char.age
        }, { onConflict: 'anilist_id' })
        .select('id')
        .single();
      
      if (!charError && insertedChar) {
        results.characters++;
        
        // Link manga to character
        await supabase
          .from('manga_characters')
          .upsert({
            manga_id: insertedManga.id,
            character_id: insertedChar.id,
            role: edge?.role
          });
        
        results.relationships++;
      }
    }
  }
  
  console.log(`✅ Complete: ${manga.title?.english || manga.title?.romaji}`);
}

