// ============================================
// TEST MANGA IMPORT SCRIPT
// Tests the manga edge function
// ============================================

const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://bkdifromsqxkndnllmdj.supabase.co';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!supabaseKey) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function testMangaImport() {
  console.log('📚 TESTING MANGA EDGE FUNCTION...\n');
  
  try {
    // Test with a small batch (1 page = 50 manga)
    const testPayload = {
      startPage: 1,
      pagesPerBatch: 1,
      mediaType: 'MANGA'
    };
    
    console.log('📤 Calling manga edge function...');
    console.log('Payload:', JSON.stringify(testPayload, null, 2));
    
    // Try different possible function names
    const functionNames = [
      'bulk-import-manga',
      'manga-import',
      'import-manga',
      'manga-import-function'
    ];
    
    let success = false;
    
    for (const funcName of functionNames) {
      try {
        console.log(\`\n🔍 Trying function: \${funcName}\`);
        
        const response = await fetch(\`\${supabaseUrl}/functions/v1/\${funcName}\`, {
          method: 'POST',
          headers: {
            'Authorization': \`Bearer \${supabaseKey}\`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(testPayload)
        });
        
        if (response.ok) {
          const result = await response.json();
          console.log(\`✅ \${funcName}: SUCCESS!\`);
          console.log('Response:', JSON.stringify(result, null, 2));
          success = true;
          
          // Check what was imported
          await checkImportedMangaData();
          break;
        } else {
          const error = await response.json();
          console.log(\`❌ \${funcName}: \${response.status} - \${error.message}\`);
        }
      } catch (err) {
        console.log(\`❌ \${funcName}: \${err.message}\`);
      }
    }
    
    if (!success) {
      console.log('\n❌ No working manga function found.');
      console.log('Please deploy the manga edge function first:');
      console.log('1. Go to Supabase Dashboard > Edge Functions');
      console.log('2. Create new function: bulk-import-manga');
      console.log('3. Copy code from 04_manga_edge_function.js');
      console.log('4. Deploy');
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  }
}

async function checkImportedMangaData() {
  console.log('\n🔍 CHECKING IMPORTED MANGA DATA...');
  
  // Check manga
  const { data: manga, error: mangaError } = await supabase
    .from('manga')
    .select('id, anilist_id, title_english, title_romaji, chapters, volumes, genres')
    .order('popularity', { ascending: false })
    .limit(10);
  
  if (!mangaError && manga) {
    console.log(\`\n📚 MANGA IMPORTED (\${manga.length} records):\`);
    manga.forEach((m, i) => {
      console.log(\`  \${i+1}. ID: \${m.id} | AniList: \${m.anilist_id} | \${m.title_english || m.title_romaji} (\${m.chapters} ch, \${m.volumes} vol)\`);
    });
  }
  
  // Check authors
  const { data: authors, error: authorError } = await supabase
    .from('authors')
    .select('id, anilist_id, name_full')
    .limit(10);
  
  if (!authorError && authors) {
    console.log(\`\n✍️ AUTHORS IMPORTED (\${authors.length} records):\`);
    authors.forEach((a, i) => {
      console.log(\`  \${i+1}. ID: \${a.id} | AniList: \${a.anilist_id} | \${a.name_full}\`);
    });
  }
  
  // Check manga-author relationships
  const { data: mangaAuthors, error: mangaAuthorError } = await supabase
    .from('manga_authors')
    .select('manga_id, author_id')
    .limit(10);
  
  if (!mangaAuthorError && mangaAuthors) {
    console.log(\`\n🔗 MANGA-AUTHOR RELATIONSHIPS (\${mangaAuthors.length} records):\`);
    mangaAuthors.forEach((ma, i) => {
      console.log(\`  \${i+1}. Manga ID: \${ma.manga_id} → Author ID: \${ma.author_id}\`);
    });
  }
  
  // Check manga-character relationships
  const { data: mangaChars, error: mangaCharError } = await supabase
    .from('manga_characters')
    .select('manga_id, character_id')
    .limit(10);
  
  if (!mangaCharError && mangaChars) {
    console.log(\`\n🔗 MANGA-CHARACTER RELATIONSHIPS (\${mangaChars.length} records):\`);
    mangaChars.forEach((mc, i) => {
      console.log(\`  \${i+1}. Manga ID: \${mc.manga_id} → Character ID: \${mc.character_id}\`);
    });
  }
  
  // Check manga-tag relationships
  const { data: mangaTags, error: mangaTagError } = await supabase
    .from('manga_tags')
    .select('manga_id, tag_id')
    .limit(10);
  
  if (!mangaTagError && mangaTags) {
    console.log(\`\n🔗 MANGA-TAG RELATIONSHIPS (\${mangaTags.length} records):\`);
    mangaTags.forEach((mt, i) => {
      console.log(\`  \${i+1}. Manga ID: \${mt.manga_id} → Tag ID: \${mt.tag_id}\`);
    });
  }
  
  // Summary
  console.log('\n📊 MANGA IMPORT SUMMARY:');
  console.log('========================');
  console.log(\`✅ Manga: \${manga?.length || 0} records\`);
  console.log(\`✅ Authors: \${authors?.length || 0} records\`);
  console.log(\`✅ Manga-Author relationships: \${mangaAuthors?.length || 0} records\`);
  console.log(\`✅ Manga-Character relationships: \${mangaChars?.length || 0} records\`);
  console.log(\`✅ Manga-Tag relationships: \${mangaTags?.length || 0} records\`);
}

// Run the test
testMangaImport();
