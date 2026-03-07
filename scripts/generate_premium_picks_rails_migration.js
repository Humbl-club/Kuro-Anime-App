/*
  Generate a SQL migration that seeds pinned "Premium Picks" rails.

  Why:
  - `premium_picks` is the default fallback mode for vague prompts.
  - Pinning it improves consistency and the "one-shot magic" feel.

  Uses Supabase public URL + anon key loaded from scripts/project_public.env.

  Usage:
    node scripts/generate_premium_picks_rails_migration.js \
      supabase/migrations/20260208091500_curated_rails_premium_picks_seed.sql
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");
const { getPublicProjectConfig } = require("./lib/project_config");

function extractSupabaseConfigFromSwift() {
  return getPublicProjectConfig();
}

function formatSQLString(s) {
  return String(s).replace(/'/g, "''");
}

function isClean(row) {
  if (!row) return false;
  if (row.is_adult === true) return false;
  const gs = Array.isArray(row.genres) ? row.genres : [];
  if (gs.includes("Hentai")) return false;
  if (gs.includes("Ecchi")) return false;
  if (gs.includes("Kids")) return false;
  return Number.isFinite(row.anilist_id) && row.anilist_id > 0;
}

function formatOk(row, excludedFormats) {
  const f = String(row.format || "").toUpperCase();
  if (!f) return true;
  return !excludedFormats.includes(f);
}

function sortBySignalsDesc(a, b) {
  const fa = Number(a.favourites || 0);
  const fb = Number(b.favourites || 0);
  if (fa !== fb) return fb - fa;
  const sa = Number(a.average_score || 0);
  const sb = Number(b.average_score || 0);
  if (sa !== sb) return sb - sa;
  const pa = Number(a.popularity || 0);
  const pb = Number(b.popularity || 0);
  if (pa !== pb) return pb - pa;
  return Number(a.anilist_id || 0) - Number(b.anilist_id || 0);
}

async function fetchAll(supabase, table, opts) {
  const pageSize = Math.min(1000, Math.max(200, opts.pageSize || 800));
  const maxRows = Math.max(200, opts.maxRows || 4000);
  const out = [];

  for (let offset = 0; offset < maxRows; offset += pageSize) {
    let q = supabase.from(table).select(opts.select);
    if (opts.filters) q = opts.filters(q);
    q = q.range(offset, offset + pageSize - 1);
    if (opts.order) q = opts.order(q);
    const { data, error } = await q;
    if (error) throw new Error(`${table} query failed: ${error.message}`);
    if (!Array.isArray(data) || data.length === 0) break;
    out.push(...data);
    if (data.length < pageSize) break;
  }

  return out;
}

function chunkedInsertItems(items) {
  const lines = [];
  const chunkSize = 500;
  for (let i = 0; i < items.length; i += chunkSize) {
    const chunk = items.slice(i, i + chunkSize);
    lines.push("insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values");
    lines.push(
      chunk
        .map((it) => {
          const note = it.note ? `'${formatSQLString(it.note)}'` : "null";
          return `('${formatSQLString(it.rail_id)}','${formatSQLString(it.media_type)}',${Number(it.anilist_id)},${Number(it.rank)},${note})`;
        })
        .join(",\n") + "\n" + "on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;"
    );
    lines.push("");
  }
  return lines;
}

async function main() {
  const outPath = process.argv[2];
  if (!outPath) {
    console.error("Missing output path argument.");
    process.exit(1);
  }

  const { url, anonKey } = extractSupabaseConfigFromSwift();
  const supabase = createClient(url, anonKey, { auth: { persistSession: false } });

  const animeBase = await fetchAll(supabase, "anime", {
    select: "anilist_id,is_adult,genres,average_score,favourites,popularity,format,status,episodes",
    filters: (q) =>
      q
        .eq("is_adult", false)
        .gte("average_score", 72)
        .gte("popularity", 800)
        .not("anilist_id", "is", null),
    order: (q) =>
      q.order("favourites", { ascending: false })
        .order("average_score", { ascending: false })
        .order("popularity", { ascending: false }),
    maxRows: 4200,
    pageSize: 900,
  });

  const mangaBase = await fetchAll(supabase, "manga", {
    select: "anilist_id,is_adult,genres,average_score,favourites,popularity,format,status,chapters,volumes",
    filters: (q) =>
      q
        .eq("is_adult", false)
        .gte("average_score", 72)
        .gte("popularity", 800)
        .not("anilist_id", "is", null),
    order: (q) =>
      q.order("favourites", { ascending: false })
        .order("average_score", { ascending: false })
        .order("popularity", { ascending: false }),
    maxRows: 4200,
    pageSize: 900,
  });

  // Premium picks should be broadly appealing. Avoid very short formats and avoid
  // ultra long-running series that dominate but are rarely what users mean by "pick something".
  const EXCLUDED_ANIME_FORMATS = ["TV_SHORT", "SPECIAL", "MUSIC", "MOVIE"];

  const premiumAnime = animeBase
    .filter(isClean)
    .filter((r) => (r.average_score || 0) >= 80 && (r.popularity || 0) >= 2500)
    .filter((r) => formatOk(r, EXCLUDED_ANIME_FORMATS))
    .filter((r) => {
      const eps = r.episodes;
      // Keep approachable. Allow unknown.
      return eps == null || (Number(eps) > 0 && Number(eps) <= 120);
    })
    .sort(sortBySignalsDesc)
    .slice(0, 120);

  const premiumManga = mangaBase
    .filter(isClean)
    .filter((r) => (r.average_score || 0) >= 80 && (r.popularity || 0) >= 2000)
    .filter((r) => {
      const ch = r.chapters;
      return ch == null || (Number(ch) > 0 && Number(ch) <= 700);
    })
    .sort(sortBySignalsDesc)
    .slice(0, 120);

  const items = [];
  let rank = 1;
  for (const a of premiumAnime) items.push({ rail_id: "premium_picks_anime", media_type: "ANIME", anilist_id: a.anilist_id, rank: rank++, note: null });
  rank = 1;
  for (const m of premiumManga) items.push({ rail_id: "premium_picks_manga", media_type: "MANGA", anilist_id: m.anilist_id, rank: rank++, note: null });

  const lines = [];
  lines.push("-- Seed pinned rails for the default Concierge fallback: Premium Picks.");
  lines.push("-- Clean (no adult/ecchi/hentai) and broadly appealing.");
  lines.push("");
  lines.push("begin;");
  lines.push("");
  lines.push(
    "insert into public.curated_rails(id,title,media_type,description) values ('premium_picks_anime','Premium Picks','ANIME','Pinned premium picks used as the default fallback for vague prompts.') on conflict (id) do update set title = excluded.title, media_type = excluded.media_type, description = excluded.description;"
  );
  lines.push(
    "insert into public.curated_rails(id,title,media_type,description) values ('premium_picks_manga','Premium Picks','MANGA','Pinned premium picks used as the default fallback for vague prompts.') on conflict (id) do update set title = excluded.title, media_type = excluded.media_type, description = excluded.description;"
  );
  lines.push("");
  lines.push("delete from public.curated_rail_items where rail_id in ('premium_picks_anime','premium_picks_manga');");
  lines.push("");
  lines.push(...chunkedInsertItems(items));
  lines.push("commit;");
  lines.push("");

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, lines.join("\n"), "utf8");

  console.log(`Wrote ${outPath}`);
  console.log(`Counts: anime=${premiumAnime.length} manga=${premiumManga.length}`);
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});

