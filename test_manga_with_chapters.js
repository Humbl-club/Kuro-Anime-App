// ============================================
// TEST MANGA IMPORT WITH CHAPTERS
// Tests the updated manga edge function
// ============================================

const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://bkdifromsqxkndnllmdj.supabase.co';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!supabaseKey) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function testMangaWithChapters() {
  console.log('📚 TESTING MANGA EDGE FUNCTION WITH CHAPTERS...\n');
  
  try {
    // Test with a small batch (1 page = 50 manga)
    const testPayload = {
      startPage: 1,
      pagesPerBatch: 1
    };
    
    console.log('📤 Calling updated manga edge function...');
    console.log('Payload:', JSON.stringify(testPayload, null, 2));
    
    // Try different possible function names
    const functionNames = [
      'bulk-import-manga',
      'manga-import',
      'import-manga',
      'manga-import-function',
      'manga-with-chapters'
    ];
    
    let success = false;
    
    for (const funcName of functionNames) {
      try {
        console.log(`\n🔍 Trying function: \${funcName}\`);
        
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
          await checkImportedMangaWithChapters();
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
      console.log('Please deploy the updated manga edge function first:');
      console.log('1. Go to Supabase Dashboard > Edge Functions');
      console.log('2. Update your manga function with 07_manga_edge_function_with_chapters.js');
      console.log('3. Deploy');
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  }
}

async function checkImportedMangaWithChapters() {
  console.log('\n🔍 CHECKING IMPORTED MANGA WITH CHAPTERS...');
  
  // Check manga
  const { data: manga, error: mangaError } = await supabase
    .from('manga')
    .select('id, anilist_id, title_english, title_romaji, chapters, volumes')
    .order('popularity', { ascending: false })
    .limit(5);
  
  if (!mangaError && manga) {
    console.log(\`\n📚 MANGA IMPORTED (\${manga.length} records):\`);
    manga.forEach((m, i) => {
      console.log(\`  \${i+1}. ID: \${m.id} | \${m.title_english || m.title_romaji} (\${m.chapters} ch, \${m.volumes} vol)\`);
    });
  }
  
  // Check chapters
  const { data: chapters, error: chaptersError } = await supabase
    .from('chapters')
    .select('manga_id, number, title')
    .order('manga_id, number')
    .limit(20);
  
  if (!chaptersError && chapters) {
    console.log(\`\n📖 CHAPTERS IMPORTED (\${chapters.length} records):\`);
    
    // Group by manga
    const chaptersByManga = {};
    chapters.forEach(ch => {
      if (!chaptersByManga[ch.manga_id]) {
        chaptersByManga[ch.manga_id] = [];
      }
      chaptersByManga[ch.manga_id].push(ch);
    });
    
    Object.entries(chaptersByManga).forEach(([mangaId, mangaChapters]) => {
      console.log(\`  Manga ID \${mangaId}: Chapters \${mangaChapters[0].number}-\${mangaChapters[mangaChapters.length-1].number} (\${mangaChapters.length} total)\`);
    });
  }
  
  // Check volumes
  const { data: volumes, error: volumesError } = await supabase
    .from('manga_volumes')
    .select('manga_id, number, title')
    .order('manga_id, number')
    .limit(20);
  
  if (!volumesError && volumes) {
    console.log(\`\n📚 VOLUMES IMPORTED (\${volumes.length} records):\`);
    
    // Group by manga
    const volumesByManga = {};
    volumes.forEach(vol => {
      if (!volumesByManga[vol.manga_id]) {
        volumesByManga[vol.manga_id] = [];
      }
      volumesByManga[vol.manga_id].push(vol);
    });
    
    Object.entries(volumesByManga).forEach(([mangaId, mangaVolumes]) => {
      console.log(\`  Manga ID \${mangaId}: Volumes \${mangaVolumes[0].number}-\${mangaVolumes[mangaVolumes.length-1].number} (\${mangaVolumes.length} total)\`);
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
  
  // Summary
  console.log('\n📊 MANGA WITH CHAPTERS IMPORT SUMMARY:');
  console.log('=====================================');
  console.log(\`✅ Manga: \${manga?.length || 0} records\`);
  console.log(\`✅ Chapters: \${chapters?.length || 0} records\`);
  console.log(\`✅ Volumes: \${volumes?.length || 0} records\`);
  console.log(\`✅ Authors: \${authors?.length || 0} records\`);
  console.log(\`✅ Manga-Author relationships: \${mangaAuthors?.length || 0} records\`);
  
  // Verify chapter creation
  if (chapters && chapters.length > 0) {
    console.log('\n✅ CHAPTERS: SUCCESSFULLY CREATED');
    console.log('   - Placeholder chapters created based on chapter count');
    console.log('   - Each chapter has: manga_id, number, title');
    console.log('   - Ready for user progress tracking');
  } else {
    console.log('\n❌ CHAPTERS: NOT CREATED');
    console.log('   - Check if manga have chapter counts');
    console.log('   - Verify edge function is working');
  }
  
  if (volumes && volumes.length > 0) {
    console.log('\n✅ VOLUMES: SUCCESSFULLY CREATED');
    console.log('   - Placeholder volumes created based on volume count');
    console.log('   - Each volume has: manga_id, number, title');
    console.log('   - Ready for user progress tracking');
  } else {
    console.log('\n❌ VOLUMES: NOT CREATED');
    console.log('   - Check if manga have volume counts');
    console.log('   - Verify edge function is working');
  }
}

// Run the test
testMangaWithChapters();
