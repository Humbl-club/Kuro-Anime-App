/*
  Generate a SQL migration that refines the pinned curated rails that were
  producing "off-vibe" picks:
  - short_one_season_*: should feel genuinely short and complete
  - fantasy_non_isekai_*: should avoid huge long-runners and ongoing titles

  This script uses the app's Supabase fallback URL + anon key extracted from
  `Kuro/Services/SupabaseService.swift`. Catalog + curated tables are readable
  to anon in this project.

  Usage:
    node scripts/generate_refined_short_and_fantasy_rails_migration.js \
      supabase/migrations/20260208090000_refine_short_and_fantasy_rails.sql
*/

const fs = require("fs");
const path = require("path");
const { createClient } = require("@supabase/supabase-js");

function extractSupabaseConfigFromSwift() {
  const swiftPath = path.join(__dirname, "..", "Kuro", "Services", "SupabaseService.swift");
  const text = fs.readFileSync(swiftPath, "utf8");

  const urlMatch = text.match(/fallbackURL\s*=\s*URL\(string:\s*"([^"]+)"\)/);
  const keyMatch = text.match(/fallbackKey\s*=\s*"([^"]+)"/);

  const urlFallback = text.match(new RegExp("https://[a-z0-9]+\\.supabase\\.co", "i"));
  const keyFallback = text.match(new RegExp("eyJhbGci[0-9A-Za-z._-]+"));

  const url = (urlMatch && urlMatch[1]) || (urlFallback ? urlFallback[0] : null);
  const anonKey = (keyMatch && keyMatch[1]) || (keyFallback ? keyFallback[0] : null);
  if (!url || !anonKey) throw new Error("Could not extract Supabase URL/key from SupabaseService.swift");
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
  if (!Number.isFinite(row.anilist_id) || row.anilist_id <= 0) return false;
  return true;
}

function hasGenre(row, g) {
  const gs = Array.isArray(row.genres) ? row.genres : [];
  return gs.includes(g);
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
    select: "id,anilist_id,is_adult,genres,average_score,favourites,popularity,format,status,start_date_year,episodes",
    filters: (q) =>
      q
        .eq("is_adult", false)
        .gte("average_score", 70)
        .gte("popularity", 300)
        .not("anilist_id", "is", null),
    order: (q) =>
      q.order("favourites", { ascending: false })
        .order("average_score", { ascending: false })
        .order("popularity", { ascending: false }),
    maxRows: 4200,
    pageSize: 900,
  });

  const mangaBase = await fetchAll(supabase, "manga", {
    select: "id,anilist_id,is_adult,genres,average_score,favourites,popularity,format,status,start_date_year,chapters,volumes",
    filters: (q) =>
      q
        .eq("is_adult", false)
        .gte("average_score", 70)
        .gte("popularity", 300)
        .not("anilist_id", "is", null),
    order: (q) =>
      q.order("favourites", { ascending: false })
        .order("average_score", { ascending: false })
        .order("popularity", { ascending: false }),
    maxRows: 4200,
    pageSize: 900,
  });

  const EXCLUDED_FORMATS_DEFAULT = ["TV_SHORT", "SPECIAL", "MUSIC"];

  // Isekai classification via tags (to exclude from non-isekai fantasy rail).
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
      maxRows: 200000,
      pageSize: 1000,
    }))
      .map((r) => Number(r.anime_id))
      .filter((x) => Number.isFinite(x) && x > 0)
  );

  const mangaIsekaiIds = new Set(
    (await fetchAll(supabase, "manga_tags", {
      select: "manga_id,tag_id",
      filters: (q) => q.in("tag_id", isekaiTagIds),
      order: (q) => q.order("manga_id", { ascending: true }),
      maxRows: 200000,
      pageSize: 1000,
    }))
      .map((r) => Number(r.manga_id))
      .filter((x) => Number.isFinite(x) && x > 0)
  );

  const rails = [
    {
      id: "short_one_season_anime",
      title: "Short & Complete",
      media_type: "ANIME",
      description: "Pinned short, complete anime (one cour).",
    },
    {
      id: "short_one_season_manga",
      title: "Short & Complete",
      media_type: "MANGA",
      description: "Pinned short, complete manga (approachable length).",
    },
    {
      id: "fantasy_non_isekai_anime",
      title: "Fantasy (no isekai)",
      media_type: "ANIME",
      description: "Pinned fantasy picks excluding isekai (tag-based), avoiding long-runners.",
    },
    {
      id: "fantasy_non_isekai_manga",
      title: "Fantasy (no isekai)",
      media_type: "MANGA",
      description: "Pinned fantasy picks excluding isekai (tag-based), avoiding long-runners.",
    },
  ];

  const items = [];

  function addItems(railId, mediaType, rows, limit) {
    let rank = 1;
    for (const row of rows.slice(0, limit)) {
      items.push({ rail_id: railId, media_type: mediaType, anilist_id: row.anilist_id, rank: rank++, note: null });
    }
  }

  // Refinement choices (product-driven):
  // - `short_one_season` should not return multi-season franchises disguised as "one season".
  //   We make this genuinely "short" by requiring <= 13 episodes and FINISHED.
  // - `fantasy_non_isekai` should not return huge long-runners or ongoing titles.
  //   We require FINISHED and cap length to keep it "approachable".

  const shortAnime = animeBase
    .filter(isClean)
    .filter((r) => String(r.status || "").toUpperCase() === "FINISHED")
    .filter((r) => String(r.format || "").toUpperCase() === "TV")
    .filter((r) => Number(r.episodes || 0) > 0 && Number(r.episodes || 0) <= 13)
    .filter((r) => (r.average_score || 0) >= 74 && (r.popularity || 0) >= 1200)
    .filter((r) => !hasGenre(r, "Kids"))
    .filter((r) => formatOk(r, EXCLUDED_FORMATS_DEFAULT))
    .sort(sortBySignalsDesc);

  const shortManga = mangaBase
    .filter(isClean)
    .filter((r) => String(r.status || "").toUpperCase() === "FINISHED")
    .filter((r) => Number(r.chapters || 0) > 0 && Number(r.chapters || 0) <= 80)
    .filter((r) => (r.average_score || 0) >= 74 && (r.popularity || 0) >= 1200)
    .filter((r) => !hasGenre(r, "Kids"))
    .sort(sortBySignalsDesc);

  const fantasyAnime = animeBase
    .filter(isClean)
    .filter((r) => hasGenre(r, "Fantasy"))
    .filter((r) => !animeIsekaiIds.has(Number(r.id)))
    .filter((r) => String(r.status || "").toUpperCase() === "FINISHED")
    .filter((r) => {
      const eps = r.episodes;
      return eps == null || (Number(eps) > 0 && Number(eps) <= 60);
    })
    .filter((r) => (r.average_score || 0) >= 76 && (r.popularity || 0) >= 1200)
    .filter((r) => !hasGenre(r, "Kids"))
    .filter((r) => formatOk(r, EXCLUDED_FORMATS_DEFAULT))
    .sort(sortBySignalsDesc);

  const fantasyManga = mangaBase
    .filter(isClean)
    .filter((r) => hasGenre(r, "Fantasy"))
    .filter((r) => !mangaIsekaiIds.has(Number(r.id)))
    .filter((r) => String(r.status || "").toUpperCase() === "FINISHED")
    .filter((r) => {
      const ch = r.chapters;
      // Allow unknown chapter count, but cap when known to avoid massive long-runners.
      return ch == null || (Number(ch) > 0 && Number(ch) <= 220);
    })
    .filter((r) => (r.average_score || 0) >= 76 && (r.popularity || 0) >= 1200)
    .filter((r) => !hasGenre(r, "Kids"))
    .sort(sortBySignalsDesc);

  addItems("short_one_season_anime", "ANIME", shortAnime, 120);
  addItems("short_one_season_manga", "MANGA", shortManga, 120);
  addItems("fantasy_non_isekai_anime", "ANIME", fantasyAnime, 120);
  addItems("fantasy_non_isekai_manga", "MANGA", fantasyManga, 120);

  const lines = [];
  lines.push("-- Refine curated rails to avoid off-vibe picks.");
  lines.push("-- - short_one_season_*: <= 13 eps, FINISHED");
  lines.push("-- - fantasy_non_isekai_*: FINISHED, cap length, exclude isekai via tags");
  lines.push("");
  lines.push("begin;");
  lines.push("");

  for (const r of rails) {
    lines.push(
      `insert into public.curated_rails(id,title,media_type,description) values ('${formatSQLString(r.id)}','${formatSQLString(
        r.title
      )}','${formatSQLString(r.media_type)}','${formatSQLString(r.description)}') on conflict (id) do update set title = excluded.title, media_type = excluded.media_type, description = excluded.description;`
    );
  }

  lines.push("");
  lines.push(
    "delete from public.curated_rail_items where rail_id in ('short_one_season_anime','short_one_season_manga','fantasy_non_isekai_anime','fantasy_non_isekai_manga');"
  );
  lines.push("");
  lines.push(...chunkedInsertItems(items));
  lines.push("commit;");
  lines.push("");

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, lines.join("\n"), "utf8");

  const counts = {
    shortAnime: Math.min(120, shortAnime.length),
    shortManga: Math.min(120, shortManga.length),
    fantasyAnime: Math.min(120, fantasyAnime.length),
    fantasyManga: Math.min(120, fantasyManga.length),
  };
  console.log(`Wrote ${outPath}`);
  console.log(`Counts: ${JSON.stringify(counts)}`);
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});

