// ============================================
// MANGA EDGE FUNCTION
// Imports manga data with proper relationships
// Uses internal IDs + external references
// ============================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ANILIST_API = 'https://graphql.anilist.co';
const DELAY_BETWEEN_REQUESTS = 670; // milliseconds

serve(async (req) => {
  console.log('📚 MANGA EDGE FUNCTION: Starting manga import...');
  
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const supabase = createClient(supabaseUrl, supabaseKey);
  
  const { startPage = 1, pagesPerBatch = 5, mediaType = 'MANGA' } = await req.json().catch(() => ({}));
  
  const results = {
    manga: 0,
    chapters: 0,
    volumes: 0,
    characters: 0,
    authors: 0,
    staff: 0,
    tags: 0,
    relationships: 0,
    errors: 0
  };
  
  try {
    console.log(`📊 Importing manga pages ${startPage} to ${startPage + pagesPerBatch - 1}`);
    
    for (let page = startPage; page < startPage + pagesPerBatch; page++) {
      try {
        console.log(`🔍 Fetching manga page ${page}...`);
        
        const manga = await fetchAniListMangaData(page);
        
        if (manga.length === 0) {
          console.log(`✅ No more manga data at page ${page} - import complete!`);
          break;
        }
        
        console.log(`📊 Page ${page}: Processing ${manga.length} manga`);
        
        for (const item of manga) {
          try {
            await processMangaItem(supabase, item, results);
          } catch (error) {
            console.error(`❌ Failed to process manga ${item.id}:`, error.message);
            results.errors++;
          }
        }
        
        console.log(`✅ Page ${page} complete: ${manga.length} manga processed`);
        await new Promise(resolve => setTimeout(resolve, DELAY_BETWEEN_REQUESTS));
        
      } catch (error) {
        console.error(`❌ Page ${page} failed:`, error.message);
        results.errors++;
      }
    }
    
    console.log(`✅ Manga import complete:`, results);
    
    return new Response(JSON.stringify({
      success: true,
      results,
      message: `Manga import complete! Manga: ${results.manga}, Authors: ${results.authors}, Characters: ${results.characters}`
    }), {
      headers: { "Content-Type": "application/json" }
    });
    
  } catch (error) {
    console.error('❌ Manga import failed:', error);
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
// FETCH MANGA DATA FROM ANILIST
// ============================================
async function fetchAniListMangaData(page) {
  const query = `
    query ($page: Int) {
      Page(page: $page, perPage: 50) {
        pageInfo { total currentPage lastPage hasNextPage }
        media(sort: POPULARITY_DESC, type: MANGA) {
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
          
          chapters volumes
          
          averageScore meanScore
          popularity trending favourites
          
          genres
          
          siteUrl updatedAt
          
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
  
  // 2. INSERT AUTHORS (manga-specific)
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
  
  // 3. INSERT TAGS
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
  
  // 4. INSERT CHARACTERS
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
  
  // 5. INSERT STAFF (editors, publishers, etc.)
  if (manga.staff?.nodes && manga.staff?.edges) {
    for (let i = 0; i < manga.staff.nodes.length; i++) {
      const person = manga.staff.nodes[i];
      const edge = manga.staff.edges[i];
      
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
        
        // Link manga to staff
        await supabase
          .from('manga_staff')
          .upsert({
            manga_id: insertedManga.id,
            staff_id: insertedStaff.id,
            role: edge?.role
          });
        
        results.relationships++;
      }
    }
  }
  
  console.log(`✅ Complete: ${manga.title?.english || manga.title?.romaji}`);
}

