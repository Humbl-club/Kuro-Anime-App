/*
  Generate a SQL migration to seed pinned curated rails (Classics + Gateway/Start Here).

  - Reads Supabase URL + anon key from env or `scripts/project_public.env`.
  - Queries public catalog tables (`anime`, `manga`) for candidates.
  - Picks a stable top-N set and writes a migration inserting into:
      public.curated_rails
      public.curated_rail_items (keyed by AniList IDs)

  Usage:
    node scripts/generate_curated_rails_migration.js supabase/migrations/20260205234000_curated_rails_seed.sql
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");
const { getPublicProjectConfig } = require("./lib/project_config");

function extractSupabaseConfigFromSwift() {
  return getPublicProjectConfig();
}

function isCleanMedia(row) {
  if (!row) return false;
  if (row.is_adult === true) return false;
  const gs = Array.isArray(row.genres) ? row.genres : [];
  if (gs.includes("Hentai")) return false;
  if (gs.includes("Ecchi")) return false;
  return Number.isFinite(row.anilist_id) && row.anilist_id > 0;
}

function pickTop(rows, n) {
  return rows.slice(0, n);
}

function formatSQLString(s) {
  return String(s).replace(/'/g, "''");
}

function buildSeedSQL({ rails, items }) {
  const lines = [];
  lines.push("-- Seed curated rails (generated).");
  lines.push("begin;");
  lines.push("");

  for (const r of rails) {
    lines.push(
      `insert into public.curated_rails(id,title,media_type,description) values (` +
        `'${formatSQLString(r.id)}','${formatSQLString(r.title)}','${formatSQLString(r.media_type)}','${formatSQLString(r.description || "")}'` +
        `) on conflict (id) do update set title = excluded.title, media_type = excluded.media_type, description = excluded.description;`
    );
  }

  lines.push("");
  lines.push("-- Replace items for these rails to keep seed deterministic.");
  const railIds = rails.map(r => `'${formatSQLString(r.id)}'`).join(",");
  lines.push(`delete from public.curated_rail_items where rail_id in (${railIds});`);
  lines.push("");

  const chunkSize = 500;
  for (let i = 0; i < items.length; i += chunkSize) {
    const chunk = items.slice(i, i + chunkSize);
    lines.push("insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values");
    const values = chunk.map((it) => {
      const note = it.note ? `'${formatSQLString(it.note)}'` : "null";
      return `('${formatSQLString(it.rail_id)}','${formatSQLString(it.media_type)}',${Number(it.anilist_id)},${Number(it.rank)},${note})`;
    });
    lines.push(values.join(",\n") + ";");
    lines.push("");
  }

  lines.push("commit;");
  lines.push("");
  return lines.join("\n");
}

async function fetchAll(supabase, table, opts) {
  // PostgREST max rows per request varies. Keep it conservative and paginate.
  const pageSize = Math.min(1000, Math.max(200, opts.pageSize || 600));
  const maxRows = Math.max(200, opts.maxRows || 1200);
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

async function main() {
  const outPath = process.argv[2];
  if (!outPath) {
    console.error("Missing output path argument.");
    process.exit(1);
  }

  const { url, anonKey } = extractSupabaseConfigFromSwift();
  const supabase = createClient(url, anonKey, { auth: { persistSession: false } });

  // Candidate pulls: broad, then filtered client-side. This avoids relying on PostgREST array negation ops.
  const animeClassicCandidates = await fetchAll(supabase, "anime", {
    select: "anilist_id,is_adult,genres,average_score,favourites,popularity,start_date_year,season_year",
    filters: (q) => q.gte("average_score", 80).lte("start_date_year", 2012).eq("is_adult", false).not("anilist_id", "is", null),
    order: (q) => q.order("favourites", { ascending: false }).order("average_score", { ascending: false }).order("popularity", { ascending: false }),
    maxRows: 1800,
    pageSize: 800,
  });

  const mangaClassicCandidates = await fetchAll(supabase, "manga", {
    select: "anilist_id,is_adult,genres,average_score,favourites,popularity,start_date_year",
    filters: (q) => q.gte("average_score", 80).lte("start_date_year", 2012).eq("is_adult", false).not("anilist_id", "is", null),
    order: (q) => q.order("favourites", { ascending: false }).order("average_score", { ascending: false }).order("popularity", { ascending: false }),
    maxRows: 1600,
    pageSize: 800,
  });

  const animeGatewayCandidates = await fetchAll(supabase, "anime", {
    select: "anilist_id,is_adult,genres,average_score,favourites,popularity,start_date_year",
    filters: (q) => q.gte("average_score", 85).eq("is_adult", false).not("anilist_id", "is", null),
    order: (q) => q.order("favourites", { ascending: false }).order("average_score", { ascending: false }).order("popularity", { ascending: false }),
    maxRows: 1600,
    pageSize: 800,
  });

  const mangaGatewayCandidates = await fetchAll(supabase, "manga", {
    select: "anilist_id,is_adult,genres,average_score,favourites,popularity,start_date_year",
    filters: (q) => q.gte("average_score", 85).eq("is_adult", false).not("anilist_id", "is", null),
    order: (q) => q.order("favourites", { ascending: false }).order("average_score", { ascending: false }).order("popularity", { ascending: false }),
    maxRows: 1400,
    pageSize: 800,
  });

  const classicsAnime = pickTop(animeClassicCandidates.filter(isCleanMedia), 120);
  const classicsManga = pickTop(mangaClassicCandidates.filter(isCleanMedia), 80);
  const gatewayAnime = pickTop(animeGatewayCandidates.filter(isCleanMedia), 60);
  const gatewayManga = pickTop(mangaGatewayCandidates.filter(isCleanMedia), 50);

  const rails = [
    { id: "classics_anime", title: "Classics", media_type: "ANIME", description: "Pinned classics (expanded)." },
    { id: "classics_manga", title: "Classics", media_type: "MANGA", description: "Pinned classics (expanded)." },
    { id: "gateway_anime", title: "Start Here", media_type: "ANIME", description: "Pinned starters for first-time watchers." },
    { id: "gateway_manga", title: "Start Here", media_type: "MANGA", description: "Pinned starters for first-time readers." },
  ];

  const items = [];
  let rank = 1;
  for (const row of classicsAnime) items.push({ rail_id: "classics_anime", media_type: "ANIME", anilist_id: row.anilist_id, rank: rank++, note: null });
  rank = 1;
  for (const row of classicsManga) items.push({ rail_id: "classics_manga", media_type: "MANGA", anilist_id: row.anilist_id, rank: rank++, note: null });
  rank = 1;
  for (const row of gatewayAnime) items.push({ rail_id: "gateway_anime", media_type: "ANIME", anilist_id: row.anilist_id, rank: rank++, note: null });
  rank = 1;
  for (const row of gatewayManga) items.push({ rail_id: "gateway_manga", media_type: "MANGA", anilist_id: row.anilist_id, rank: rank++, note: null });

  const sql = buildSeedSQL({ rails, items });
  fs.writeFileSync(path.resolve(outPath), sql, "utf8");
  console.log(`Wrote curated rails seed migration: ${outPath}`);
  console.log(`Counts: classics_anime=${classicsAnime.length} classics_manga=${classicsManga.length} gateway_anime=${gatewayAnime.length} gateway_manga=${gatewayManga.length}`);
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});
