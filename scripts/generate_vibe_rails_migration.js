/*
  Generate a SQL migration that seeds additional pinned curated rails for common "vibe" modes.

  Why:
  - The router selects a mode ("Premium Action", "Cozy", etc.)
  - If that mode has rail_id configured, concierge-recommend can return pinned items via curated_rail_cards()
    for consistent, premium-quality output (still excludes "seen" titles per-user).

  This script uses Supabase URL + anon key from env or `scripts/project_public.env`.
  (Catalog tables are readable to anon; rails are editorial.)

  Usage:
    node scripts/generate_vibe_rails_migration.js supabase/migrations/20260207011000_curated_rails_vibes_seed.sql
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
  const maxRows = Math.max(200, opts.maxRows || 2000);
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
    select: "anilist_id,is_adult,genres,average_score,favourites,popularity,format,status,start_date_year,episodes",
    filters: (q) =>
      q
        .eq("is_adult", false)
        .gte("average_score", 70)
        .gte("popularity", 600)
        .not("anilist_id", "is", null),
    order: (q) => q.order("favourites", { ascending: false }).order("average_score", { ascending: false }).order("popularity", { ascending: false }),
    maxRows: 2600,
    pageSize: 800,
  });

  const mangaBase = await fetchAll(supabase, "manga", {
    select: "anilist_id,is_adult,genres,average_score,favourites,popularity,format,status,start_date_year,chapters,volumes",
    filters: (q) =>
      q
        .eq("is_adult", false)
        .gte("average_score", 70)
        .gte("popularity", 600)
        .not("anilist_id", "is", null),
    order: (q) => q.order("favourites", { ascending: false }).order("average_score", { ascending: false }).order("popularity", { ascending: false }),
    maxRows: 2600,
    pageSize: 800,
  });

  const EXCLUDED_FORMATS_DEFAULT = ["TV_SHORT", "SPECIAL", "MUSIC"];

  const railDefs = [
    {
      id: "premium_action",
      title: "Premium Action",
      desc: "Pinned premium action picks (high quality, clean).",
      media: "BOTH",
      build: () => {
        const anime = animeBase
          .filter(isClean)
          .filter((r) => (r.average_score || 0) >= 75 && (r.popularity || 0) >= 3500)
          .filter((r) => hasGenre(r, "Action"))
          .filter((r) => !hasGenre(r, "Kids"))
          .filter((r) => formatOk(r, EXCLUDED_FORMATS_DEFAULT))
          .sort(sortBySignalsDesc)
          .slice(0, 160);

        const manga = mangaBase
          .filter(isClean)
          .filter((r) => (r.average_score || 0) >= 75 && (r.popularity || 0) >= 2500)
          .filter((r) => hasGenre(r, "Action"))
          .filter((r) => !hasGenre(r, "Kids"))
          .sort(sortBySignalsDesc)
          .slice(0, 120);

        return { anime, manga };
      },
    },
    {
      id: "premium_comedy_grownup",
      title: "Premium Comedy (grown-up)",
      desc: "Pinned premium comedy picks (clean, not kids).",
      media: "BOTH",
      build: () => {
        const anime = animeBase
          .filter(isClean)
          .filter((r) => (r.average_score || 0) >= 75 && (r.popularity || 0) >= 3500)
          .filter((r) => hasGenre(r, "Comedy"))
          .filter((r) => !hasGenre(r, "Kids"))
          .filter((r) => formatOk(r, EXCLUDED_FORMATS_DEFAULT))
          .sort(sortBySignalsDesc)
          .slice(0, 160);

        const manga = mangaBase
          .filter(isClean)
          .filter((r) => (r.average_score || 0) >= 74 && (r.popularity || 0) >= 2200)
          .filter((r) => hasGenre(r, "Comedy"))
          .filter((r) => !hasGenre(r, "Kids"))
          .sort(sortBySignalsDesc)
          .slice(0, 120);

        return { anime, manga };
      },
    },
    {
      id: "cozy_comfort",
      title: "Cozy / Comfort",
      desc: "Pinned cozy comfort picks (slice-of-life, clean).",
      media: "BOTH",
      build: () => {
        const anime = animeBase
          .filter(isClean)
          .filter((r) => (r.average_score || 0) >= 70 && (r.popularity || 0) >= 1000)
          .filter((r) => hasAnyGenre(r, ["Slice of Life"]))
          .filter((r) => !hasGenre(r, "Kids"))
          .filter((r) => formatOk(r, ["MUSIC"]))
          .sort(sortBySignalsDesc)
          .slice(0, 160);

        const manga = mangaBase
          .filter(isClean)
          .filter((r) => (r.average_score || 0) >= 70 && (r.popularity || 0) >= 1000)
          .filter((r) => hasAnyGenre(r, ["Slice of Life"]))
          .filter((r) => !hasGenre(r, "Kids"))
          .sort(sortBySignalsDesc)
          .slice(0, 120);

        return { anime, manga };
      },
    },
    {
      id: "dark_serious",
      title: "Dark / Serious",
      desc: "Pinned dark/serious picks (psychological/drama/thriller, clean).",
      media: "BOTH",
      build: () => {
        const anime = animeBase
          .filter(isClean)
          .filter((r) => (r.average_score || 0) >= 78 && (r.popularity || 0) >= 2500)
          .filter((r) => hasGenre(r, "Drama"))
          .filter((r) => hasAnyGenre(r, ["Thriller", "Psychological", "Mystery"]))
          .filter((r) => !hasGenre(r, "Kids"))
          .filter((r) => formatOk(r, EXCLUDED_FORMATS_DEFAULT))
          .sort(sortBySignalsDesc)
          .slice(0, 160);

        const manga = mangaBase
          .filter(isClean)
          .filter((r) => (r.average_score || 0) >= 78 && (r.popularity || 0) >= 2200)
          .filter((r) => hasAnyGenre(r, ["Thriller", "Psychological", "Mystery", "Drama"]))
          .filter((r) => !hasGenre(r, "Kids"))
          .sort(sortBySignalsDesc)
          .slice(0, 120);

        return { anime, manga };
      },
    },
    {
      id: "hidden_gems",
      title: "Hidden Gems",
      desc: "Pinned hidden gems (high score, lower popularity, clean).",
      media: "BOTH",
      build: () => {
        const anime = animeBase
          .filter(isClean)
          .filter((r) => (r.average_score || 0) >= 78 && (r.popularity || 0) > 0 && (r.popularity || 0) <= 45000)
          .filter((r) => !hasGenre(r, "Kids"))
          .filter((r) => formatOk(r, EXCLUDED_FORMATS_DEFAULT))
          .sort(sortHiddenGems)
          .slice(0, 160);

        const manga = mangaBase
          .filter(isClean)
          .filter((r) => (r.average_score || 0) >= 78 && (r.popularity || 0) > 0 && (r.popularity || 0) <= 45000)
          .filter((r) => !hasGenre(r, "Kids"))
          .sort(sortHiddenGems)
          .slice(0, 120);

        return { anime, manga };
      },
    },
  ];

  const rails = [];
  const items = [];

  for (const def of railDefs) {
    const built = def.build();

    // Rail IDs are explicit per media type to keep curated_rail_cards simple.
    const railAnimeId = `${def.id}_anime`;
    const railMangaId = `${def.id}_manga`;

    rails.push({ id: railAnimeId, title: def.title, media_type: "ANIME", description: def.desc });
    rails.push({ id: railMangaId, title: def.title, media_type: "MANGA", description: def.desc });

    let rank = 1;
    for (const row of built.anime) items.push({ rail_id: railAnimeId, media_type: "ANIME", anilist_id: row.anilist_id, rank: rank++, note: null });
    rank = 1;
    for (const row of built.manga) items.push({ rail_id: railMangaId, media_type: "MANGA", anilist_id: row.anilist_id, rank: rank++, note: null });
  }

  const lines = [];
  lines.push("-- Seed additional curated rails for vibe modes (generated).");
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

  const counts = railDefs.map((d) => {
    const { anime, manga } = d.build();
    return `${d.id}: anime=${anime.length} manga=${manga.length}`;
  });
  console.log(`Wrote: ${outPath}`);
  console.log(counts.join("\n"));
}

main().catch((e) => {
  console.error(e?.message || String(e));
  process.exit(1);
});

