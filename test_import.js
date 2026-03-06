// ============================================
// TEST IMPORT SCRIPT
// Tests the edge function with a small batch
// ============================================

const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://bkdifromsqxkndnllmdj.supabase.co';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const importSecret = process.env.IMPORT_SECRET ?? process.env.SUPABASE_IMPORT_SECRET;
if (!supabaseKey) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
}
if (!importSecret) {
  throw new Error('Missing IMPORT_SECRET (or SUPABASE_IMPORT_SECRET) env var.');
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function testImport() {
  console.log('🧪 TESTING EDGE FUNCTION IMPORT...\n');
  
  try {
    // Test with a small batch (1 page = 50 anime)
    const testPayload = {
      startPage: 1,
      pagesPerBatch: 1,
      mediaType: 'ANIME'
    };
    
    console.log('📤 Calling edge function...');
    console.log('Payload:', JSON.stringify(testPayload, null, 2));
    
    // Call the edge function
    const response = await fetch(`${supabaseUrl}/functions/v1/bulk-import-anime`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${supabaseKey}`,
        'x-import-secret': importSecret,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(testPayload)
    });
    
    const result = await response.json();
    
    if (response.ok) {
      console.log('✅ Edge function response:');
      console.log(JSON.stringify(result, null, 2));
      
      // Check what was imported
      console.log('\n🔍 CHECKING IMPORTED DATA...');
      
      const { data: anime, error: animeError } = await supabase
        .from('anime')
        .select('id, anilist_id, title_english, title_romaji, episodes, genres')
        .limit(5);
      
      if (!animeError && anime) {
        console.log(`\n📊 ANIME IMPORTED (${anime.length} records):`);
        anime.forEach(a => {
          console.log(`  - ID: ${a.id} | AniList: ${a.anilist_id} | Title: ${a.title_english || a.title_romaji}`);
        });
      }
      
      const { data: characters, error: charError } = await supabase
        .from('characters')
        .select('id, anilist_id, name_full')
        .limit(5);
      
      if (!charError && characters) {
        console.log(`\n👤 CHARACTERS IMPORTED (${characters.length} records):`);
        characters.forEach(c => {
          console.log(`  - ID: ${c.id} | AniList: ${c.anilist_id} | Name: ${c.name_full}`);
        });
      }
      
      const { data: studios, error: studioError } = await supabase
        .from('studios')
        .select('id, anilist_id, name')
        .limit(5);
      
      if (!studioError && studios) {
        console.log(`\n🏢 STUDIOS IMPORTED (${studios.length} records):`);
        studios.forEach(s => {
          console.log(`  - ID: ${s.id} | AniList: ${s.anilist_id} | Name: ${s.name}`);
        });
      }
      
      const { data: tags, error: tagError } = await supabase
        .from('tags')
        .select('id, anilist_id, name')
        .limit(5);
      
      if (!tagError && tags) {
        console.log(`\n🏷️ TAGS IMPORTED (${tags.length} records):`);
        tags.forEach(t => {
          console.log(`  - ID: ${t.id} | AniList: ${t.anilist_id} | Name: ${t.name}`);
        });
      }
      
      // Check relationships
      const { data: animeChars, error: animeCharError } = await supabase
        .from('anime_characters')
        .select('anime_id, character_id')
        .limit(5);
      
      if (!animeCharError && animeChars) {
        console.log(`\n🔗 ANIME-CHARACTER RELATIONSHIPS (${animeChars.length} records):`);
        animeChars.forEach(ac => {
          console.log(`  - Anime ID: ${ac.anime_id} → Character ID: ${ac.character_id}`);
        });
      }
      
    } else {
      console.log('❌ Edge function error:');
      console.log('Status:', response.status);
      console.log('Response:', JSON.stringify(result, null, 2));
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  }
}

// Run the test
testImport();
