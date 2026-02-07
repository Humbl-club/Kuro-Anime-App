/*
  Generate a SQL migration that seeds additional pinned curated rails for the newer vibe modes:
  - romcom
  - romance_serious
  - short_one_season
  - movie_night (anime only)
  - isekai
  - fantasy_non_isekai

  This script uses Supabase URL + anon key (catalog is public read), and uses tags join tables
  to classify isekai vs non-isekai fantasy.

  Usage:
    node scripts/generate_more_vibe_rails_migration.js supabase/migrations/20260207020000_curated_rails_more_vibes_seed.sql
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");

function extractSupabaseConfigFromSwift() {
  const swiftPath = path.join(__dirname, "..", "Kuro", "Services", "SupabaseService.swift");
  const text = fs.readFileSync(swiftPath, "utf8");

  const urlMatch = text.match(/fallbackURL\\s*=\\s*URL\\(string:\\s*\"([^\"]+)\"\\)/);
  const keyMatch = text.match(/fallbackKey\\s*=\\s*\"([^\"]+)\"/);

  const urlFallback = text.match(new RegExp("https://[a-z0-9]+\\.supabase\\.co", "i"));
  const keyFallback = text.match(new RegExp("eyJhbGci[0-9A-Za-z._-]+"));

  const url = urlMatch?.[1] ?? (urlFallback ? urlFallback[0] : null);
  const anonKey = keyMatch?.[1] ?? (keyFallback ? keyFallback[0] : null);
  if (!url || !anonKey) throw new Error("Could not extract `fallbackURL` / `fallbackKey` from SupabaseService.swift");
  return { url, anonKey };
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
  return Number.isFinite(row.anilist_id) && row.anilist_id > 0;
}

function hasGenre(row, g) {
  const gs = Array.isArray(row.genres) ? row.genres : [];
  return gs.includes(g);
}

function hasAnyGenre(row, gs) {
  for (const g of gs) if (hasGenre(row, g)) return true;
  return false;
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

function sortHiddenGems(a, b) {
  const sa = Number(a.average_score || 0);
  const sb = Number(b.average_score || 0);
  if (sa !== sb) return sb - sa;
  const pa = Number(a.popularity || 0);
  const pb = Number(b.popularity || 0);
  if (pa !== pb) return pa - pb; // lower popularity first
  const fa = Number(a.favourites || 0);
  const fb = Number(b.favourites || 0);
  if (fa !== fb) return fb - fa;
  return Number(a.anilist_id || 0) - Number(b.anilist_id || 0);
}

async function fetchAll(supabase, table, opts) {
  const pageSize = Math.min(1000, Math.max(200, opts.pageSize || 600));
  const maxRows = Math.max(200, opts.maxRows || 3000);
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

async function findTagIdsByPatterns(supabase, patterns) {
  const ids = new Set();
  for (const p of patterns) {
    const { data, error } = await supabase.from("tags").select("id,name").ilike("name", `%${p}%`).limit(200);
    if (error) throw new Error(`tags lookup failed: ${error.message}`);
    for (const row of data || []) {
      if (Number.isFinite(row.id)) ids.add(row.id);
    }
  }
  return Array.from(ids);
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
        .join(",\n") + "\n" + "on conflict (rail_id, media_type, anilist_id) do nothing;"
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
    select: "id,anilist_id,is_adult,genres,average_score,favourites,popularity,format,status,start_date_year,episodes",
    filters: (q) =>
      q
        .eq("is_adult", false)
        .gte("average_score", 70)
        .gte("popularity", 400)
        .not("anilist_id", "is", null),
    order: (q) => q.order("favourites", { ascending: false }).order("average_score", { ascending: false }).order("popularity", { ascending: false }),
    maxRows: 3200,
    pageSize: 900,
  });

  const mangaBase = await fetchAll(supabase, "manga", {
    select: "id,anilist_id,is_adult,genres,average_score,favourites,popularity,format,status,start_date_year,chapters,volumes",
    filters: (q) =>
      q
        .eq("is_adult", false)
        .gte("average_score", 70)
        .gte("popularity", 400)
        .not("anilist_id", "is", null),
    order: (q) => q.order("favourites", { ascending: false }).order("average_score", { ascending: false }).order("popularity", { ascending: false }),
    maxRows: 3200,
    pageSize: 900,
  });

  // Isekai classification via tags.
  const isekaiTagIds = await findTagIdsByPatterns(supabase, [
    "Isekai",
    "Reincarnation",
    "Transported to Another World",
    "Transmigration",
    "Another World",
  ]);

  const animeIsekaiIds = new Set(
    (await fetchAll(supabase, "anime_tags", {
      select: "anime_id,tag_id",
      filters: (q) => q.in("tag_id", isekaiTagIds),
      order: (q) => q.order("anime_id", { ascending: true }),
      maxRows: 120000,
      pageSize: 1000,
    })).map((r) => Number(r.anime_id)).filter((x) => Number.isFinite(x) && x > 0)
  );

  const mangaIsekaiIds = new Set(
    (await fetchAll(supabase, "manga_tags", {
      select: "manga_id,tag_id",
      filters: (q) => q.in("tag_id", isekaiTagIds),
      order: (q) => q.order("manga_id", { ascending: true }),
      maxRows: 120000,
      pageSize: 1000,
    })).map((r) => Number(r.manga_id)).filter((x) => Number.isFinite(x) && x > 0)
  );

  const EXCLUDED_FORMATS_DEFAULT = ["TV_SHORT", "SPECIAL", "MUSIC"];

  const rails = [];
  const items = [];

  function addRail(railId, title, mediaType, description) {
    rails.push({ id: railId, title, media_type: mediaType, description });
  }
  function addItems(railId, mediaType, rows, limit) {
    let rank = 1;
    for (const row of rows.slice(0, limit)) {
      items.push({ rail_id: railId, media_type: mediaType, anilist_id: row.anilist_id, rank: rank++, note: null });
    }
  }

  // ── ROMCOM ──
  addRail("romcom_anime", "Romcom", "ANIME", "Pinned romcom picks (romance + comedy).");
  addRail("romcom_manga", "Romcom", "MANGA", "Pinned romcom picks (romance + comedy).");

  const romcomAnime = animeBase
    .filter(isClean)
    .filter((r) => (r.average_score || 0) >= 72 && (r.popularity || 0) >= 2000)
    .filter((r) => hasGenre(r, "Romance") && hasGenre(r, "Comedy"))
    .filter((r) => !hasGenre(r, "Kids"))
    .filter((r) => formatOk(r, EXCLUDED_FORMATS_DEFAULT))
    .sort(sortBySignalsDesc);
  const romcomManga = mangaBase
    .filter(isClean)
    .filter((r) => (r.average_score || 0) >= 72 && (r.popularity || 0) >= 1800)
    .filter((r) => hasGenre(r, "Romance") && hasGenre(r, "Comedy"))
    .filter((r) => !hasGenre(r, "Kids"))
    .sort(sortBySignalsDesc);
  addItems("romcom_anime", "ANIME", romcomAnime, 120);
  addItems("romcom_manga", "MANGA", romcomManga, 120);

  // ── SERIOUS ROMANCE ──
  addRail("romance_serious_anime", "Romance (serious)", "ANIME", "Pinned serious romance picks (romance + drama, not comedy).");
  addRail("romance_serious_manga", "Romance (serious)", "MANGA", "Pinned serious romance picks (romance + drama, not comedy).");

  const romanceSeriousAnime = animeBase
    .filter(isClean)
    .filter((r) => (r.average_score || 0) >= 74 && (r.popularity || 0) >= 2000)
    .filter((r) => hasGenre(r, "Romance") && hasGenre(r, "Drama"))
    .filter((r) => !hasGenre(r, "Comedy"))
    .filter((r) => !hasGenre(r, "Kids"))
    .filter((r) => formatOk(r, EXCLUDED_FORMATS_DEFAULT))
    .sort(sortBySignalsDesc);
  const romanceSeriousManga = mangaBase
    .filter(isClean)
    .filter((r) => (r.average_score || 0) >= 74 && (r.popularity || 0) >= 1600)
    .filter((r) => hasGenre(r, "Romance") && hasGenre(r, "Drama"))
    .filter((r) => !hasGenre(r, "Comedy"))
    .filter((r) => !hasGenre(r, "Kids"))
    .sort(sortBySignalsDesc);
  addItems("romance_serious_anime", "ANIME", romanceSeriousAnime, 120);
  addItems("romance_serious_manga", "MANGA", romanceSeriousManga, 120);

  // ── SHORT ONE SEASON ──
  addRail("short_one_season_anime", "Short & Complete", "ANIME", "Pinned short, completed anime (one season).");
  addRail("short_one_season_manga", "Short & Complete", "MANGA", "Pinned short, completed manga (approachable length).");

  const shortAnime = animeBase
    .filter(isClean)
    .filter((r) => String(r.format || "").toUpperCase() === "TV")
    .filter((r) => String(r.status || "").toUpperCase() === "FINISHED")
    .filter((r) => Number.isFinite(r.episodes) && r.episodes >= 10 && r.episodes <= 26)
    .filter((r) => (r.average_score || 0) >= 74 && (r.popularity || 0) >= 2000)
    .filter((r) => !hasGenre(r, "Kids"))
    .sort(sortBySignalsDesc);
  const shortManga = mangaBase
    .filter(isClean)
    .filter((r) => String(r.status || "").toUpperCase() === "FINISHED")
    .filter((r) => Number.isFinite(r.chapters) && r.chapters >= 10 && r.chapters <= 120)
    .filter((r) => (r.average_score || 0) >= 72 && (r.popularity || 0) >= 1600)
    .filter((r) => !hasGenre(r, "Kids"))
    .sort(sortBySignalsDesc);
  addItems("short_one_season_anime", "ANIME", shortAnime, 120);
  addItems("short_one_season_manga", "MANGA", shortManga, 120);

  // ── MOVIE NIGHT (ANIME ONLY) ──
  addRail("movie_night_anime", "Movie Night", "ANIME", "Pinned movie picks (anime films).");
  const movieAnime = animeBase
    .filter(isClean)
    .filter((r) => String(r.format || "").toUpperCase() === "MOVIE")
    .filter((r) => (r.average_score || 0) >= 76 && (r.popularity || 0) >= 2000)
    .filter((r) => !hasGenre(r, "Kids"))
    .sort(sortBySignalsDesc);
  addItems("movie_night_anime", "ANIME", movieAnime, 120);

  // ── ISEKAI ──
  addRail("isekai_anime", "Isekai", "ANIME", "Pinned isekai picks (tag-based).");
  addRail("isekai_manga", "Isekai", "MANGA", "Pinned isekai picks (tag-based).");

  const isekaiAnime = animeBase
    .filter(isClean)
    .filter((r) => animeIsekaiIds.has(Number(r.id)))
    .filter((r) => (r.average_score || 0) >= 72 && (r.popularity || 0) >= 2500)
    .filter((r) => !hasGenre(r, "Kids"))
    .filter((r) => formatOk(r, EXCLUDED_FORMATS_DEFAULT))
    .sort(sortBySignalsDesc);
  const isekaiManga = mangaBase
    .filter(isClean)
    .filter((r) => mangaIsekaiIds.has(Number(r.id)))
    .filter((r) => (r.average_score || 0) >= 72 && (r.popularity || 0) >= 2200)
    .filter((r) => !hasGenre(r, "Kids"))
    .sort(sortBySignalsDesc);
  addItems("isekai_anime", "ANIME", isekaiAnime, 120);
  addItems("isekai_manga", "MANGA", isekaiManga, 120);

  // ── FANTASY (NO ISEKAI) ──
  addRail("fantasy_non_isekai_anime", "Fantasy (no isekai)", "ANIME", "Pinned fantasy picks excluding isekai (tag-based).");
  addRail("fantasy_non_isekai_manga", "Fantasy (no isekai)", "MANGA", "Pinned fantasy picks excluding isekai (tag-based).");

  const fantasyNonIsekaiAnime = animeBase
    .filter(isClean)
    .filter((r) => hasGenre(r, "Fantasy"))
    .filter((r) => !animeIsekaiIds.has(Number(r.id)))
    .filter((r) => (r.average_score || 0) >= 74 && (r.popularity || 0) >= 2000)
    .filter((r) => !hasGenre(r, "Kids"))
    .filter((r) => formatOk(r, EXCLUDED_FORMATS_DEFAULT))
    .sort(sortBySignalsDesc);
  const fantasyNonIsekaiManga = mangaBase
    .filter(isClean)
    .filter((r) => hasGenre(r, "Fantasy"))
    .filter((r) => !mangaIsekaiIds.has(Number(r.id)))
    .filter((r) => (r.average_score || 0) >= 74 && (r.popularity || 0) >= 1600)
    .filter((r) => !hasGenre(r, "Kids"))
    .sort(sortBySignalsDesc);
  addItems("fantasy_non_isekai_anime", "ANIME", fantasyNonIsekaiAnime, 120);
  addItems("fantasy_non_isekai_manga", "MANGA", fantasyNonIsekaiManga, 120);

  // Build SQL migration.
  const lines = [];
  lines.push("-- Seed additional curated rails for newer vibe modes (generated).");
  lines.push("-- Safe to re-run: rail upserts + item inserts are ON CONFLICT DO NOTHING.");
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
  lines.push(...chunkedInsertItems(items));
  lines.push("commit;");
  lines.push("");

  fs.writeFileSync(path.resolve(outPath), lines.join("\n"), "utf8");

  console.log(`Wrote: ${outPath}`);
  console.log(`Counts: rails=${rails.length} items=${items.length}`);
  console.log(`Isekai tag ids: ${isekaiTagIds.length}`);
  console.log(`Isekai anime ids: ${animeIsekaiIds.size}, manga ids: ${mangaIsekaiIds.size}`);
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});

