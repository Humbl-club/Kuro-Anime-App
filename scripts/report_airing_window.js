/*
  Reports anime with a next episode timestamp inside a time window.
  Usage: node scripts/report_airing_window.js [days]
  - Defaults to 7 days.
*/

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://bkdifromsqxkndnllmdj.supabase.co';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MjU5ODY2MywiZXhwIjoyMDY4MTc0NjYzfQ.qmEd0lxjs_cVIa4GRisDY9sNz35foJBEIQcs8XRrA9E';

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

function fmt(ts) { return new Date(ts).toISOString(); }

async function main() {
  const days = parseInt(process.argv[2] || '7', 10);
  const now = new Date();
  const until = new Date(now.getTime() + days*24*60*60*1000);

  const { data: rows, error } = await supabase
    .from('anime')
    .select('id, anilist_id, title_english, title_romaji, next_episode_number, next_airing_at')
    .gte('next_airing_at', now.toISOString())
    .lt('next_airing_at', until.toISOString())
    .order('next_airing_at', { ascending: true })
    .limit(500);
  if (error) throw error;

  console.log(`Window: ${fmt(now)} to ${fmt(until)} (${days} days)`);
  console.log(`Count (<=500 shown): ${rows.length}`);
  for (const r of rows) {
    const title = r.title_english || r.title_romaji || `#${r.anilist_id}`;
    console.log(`${fmt(r.next_airing_at)} | E${r.next_episode_number ?? '?'} | ${title}`);
  }
}

main().catch(e => { console.error(e); process.exit(1); });

