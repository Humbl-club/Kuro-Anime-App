// ============================================
// ANIME EDGE FUNCTION WITH EPISODES
// Imports anime data + individual episodes
// ============================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ANILIST_API = 'https://graphql.anilist.co';
const DELAY_BETWEEN_REQUESTS = 670; // milliseconds

serve(async (req) => {
  console.log('📺 ANIME EDGE FUNCTION WITH EPISODES: Starting import...');
  
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const supabase = createClient(supabaseUrl, supabaseKey);
  
  const { startPage = 1, pagesPerBatch = 5 } = await req.json().catch(() => ({}));
  
  const results = {
    anime: 0,
    episodes: 0,
    characters: 0,
    studios: 0,
    staff: 0,
    tags: 0,
    relationships: 0,
    errors: 0
  };
  
  try {
    console.log(`📊 Importing anime pages ${startPage} to ${startPage + pagesPerBatch - 1}`);
    
    for (let page = startPage; page < startPage + pagesPerBatch; page++) {
      try {
        console.log(`🔍 Fetching anime page ${page}...`);
        
        const anime = await fetchAniListAnimeData(page);
        
        if (anime.length === 0) {
          console.log(`✅ No more anime data at page ${page} - import complete!`);
          break;
        }
        
        console.log(`📊 Page ${page}: Processing ${anime.length} anime`);
        
        for (const item of anime) {
          try {
            await processAnimeItem(supabase, item, results);
          } catch (error) {
            console.error(`❌ Failed to process anime ${item.id}:`, error.message);
            results.errors++;
          }
        }
        
        console.log(`✅ Page ${page} complete: ${anime.length} anime processed`);
        await new Promise(resolve => setTimeout(resolve, DELAY_BETWEEN_REQUESTS));
        
      } catch (error) {
        console.error(`❌ Page ${page} failed:`, error.message);
        results.errors++;
      }
    }
    
    console.log(`✅ Anime import complete:`, results);
    
    return new Response(JSON.stringify({
      success: true,
      results,
      message: `Anime import complete! Anime: ${results.anime}, Episodes: ${results.episodes}, Characters: ${results.characters}`
    }), {
      headers: { "Content-Type": "application/json" }
    });
    
  } catch (error) {
    console.error('❌ Anime import failed:', error);
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
// FETCH ANIME DATA FROM ANILIST
// ============================================
async function fetchAniListAnimeData(page) {
  const query = `
    query ($page: Int) {
      Page(page: $page, perPage: 50) {
        pageInfo { total currentPage lastPage hasNextPage }
        media(sort: POPULARITY_DESC, type: ANIME) {
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
          
          episodes duration
          season seasonYear
          
          nextAiringEpisode {
            episode
            airingAt
            timeUntilAiring
          }
          
          averageScore meanScore
          popularity trending favourites
          
          genres
          
          siteUrl updatedAt
          
          streamingEpisodes {
            title
            thumbnail
            url
            site
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
      variables: { page }
    })
  });
  
  const data = await response.json();
  return data?.data?.Page?.media || [];
}

// ============================================
// PROCESS ANIME ITEM
// ============================================
async function processAnimeItem(supabase, anime, results) {
  console.log(`📺 Processing Anime: ${anime.title?.english || anime.title?.romaji}`);
  
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
  
  // 2. INSERT EPISODES (from streamingEpisodes)
  if (anime.streamingEpisodes && anime.streamingEpisodes.length > 0) {
    console.log(`📺 Importing ${anime.streamingEpisodes.length} episodes...`);

    // Ensure idempotency: remove existing episodes for this anime before inserting
    await supabase
      .from('episodes')
      .delete()
      .eq('anime_id', insertedAnime.id);

    for (let i = 0; i < anime.streamingEpisodes.length; i++) {
      const ep = anime.streamingEpisodes[i];

      // Extract episode number from title (e.g., "Episode 1 - Title")
      const episodeMatch = ep.title?.match(/Episode\s+(\d+)/i);
      const episodeNumber = episodeMatch ? parseInt(episodeMatch[1], 10) : i + 1;

      const episodeData = {
        anime_id: insertedAnime.id,
        number: episodeNumber,
        title: ep.title,
        thumbnail: ep.thumbnail,
        duration: anime.duration || null
      };

      const { error: episodeError } = await supabase
        .from('episodes')
        .insert(episodeData);

      if (!episodeError) {
        results.episodes++;
      }
    }
  }
  
  // 3. INSERT STUDIOS
  if (anime.studios?.nodes) {
    for (const studio of anime.studios.nodes) {
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
            studio_id: insertedStudio.id
          });
        
        results.relationships++;
      }
    }
  }
  
  // 4. INSERT TAGS
  if (anime.tags) {
    for (const tag of anime.tags) {
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
  
  // 5. INSERT CHARACTERS
  if (anime.characters?.nodes && anime.characters?.edges) {
    for (let i = 0; i < anime.characters.nodes.length; i++) {
      const char = anime.characters.nodes[i];
      const edge = anime.characters.edges[i];
      
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
  
  // 6. INSERT STAFF
  if (anime.staff?.nodes && anime.staff?.edges) {
    for (let i = 0; i < anime.staff.nodes.length; i++) {
      const person = anime.staff.nodes[i];
      const edge = anime.staff.edges[i];
      
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

