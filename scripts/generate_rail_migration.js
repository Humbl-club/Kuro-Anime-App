/*
  Deterministic rail migration generator.

  Reads scripts/rail_config.json and produces a SQL migration that
  seeds all curated rails and their items. Same config always produces
  the same SQL output (deterministic).

  Validates constraints before generating:
  - No duplicate anilist_ids within a rail
  - Item count <= max_items_per_rail (default 120)
  - No empty rails
  - Rail ids must be non-empty strings
  - Media type must be ANIME or MANGA

  Usage:
    node scripts/generate_rail_migration.js [output_path]

  If output_path is omitted, writes to stdout.
*/

const fs = require("fs");
const path = require("path");

function formatSQLString(s) {
  return String(s).replace(/'/g, "''");
}

function loadConfig() {
  const configPath = path.join(__dirname, "rail_config.json");
  const raw = fs.readFileSync(configPath, "utf8");
  return JSON.parse(raw);
}

function validate(config) {
  const errors = [];
  const maxItems = (config.global_constraints && config.global_constraints.max_items_per_rail) || 100;
  const allRailIds = new Set();

  if (!Array.isArray(config.rails) || config.rails.length === 0) {
    errors.push("Config has no rails defined.");
    return errors;
  }

  for (const rail of config.rails) {
    const rid = rail.id;

    // Rail id checks
    if (!rid || typeof rid !== "string" || rid.trim().length === 0) {
      errors.push("Rail has empty or missing id.");
      continue;
    }
    if (allRailIds.has(rid)) {
      errors.push(`Duplicate rail id: '${rid}'.`);
    }
    allRailIds.add(rid);

    // Media type
    if (!["ANIME", "MANGA"].includes(rail.media_type)) {
      errors.push(`Rail '${rid}': invalid media_type '${rail.media_type}'. Must be ANIME or MANGA.`);
    }

    // Title
    if (!rail.title || typeof rail.title !== "string") {
      errors.push(`Rail '${rid}': missing title.`);
    }

    // Items
    if (!Array.isArray(rail.items) || rail.items.length === 0) {
      errors.push(`Rail '${rid}': no items defined.`);
      continue;
    }

    if (rail.items.length > maxItems) {
      errors.push(`Rail '${rid}': has ${rail.items.length} items, exceeds max of ${maxItems}.`);
    }

    // Duplicate anilist_id within rail
    const seen = new Set();
    for (let i = 0; i < rail.items.length; i++) {
      const item = rail.items[i];
      const aid = item.anilist_id;
      if (!Number.isFinite(aid) || aid <= 0) {
        errors.push(`Rail '${rid}' item[${i}]: invalid anilist_id '${aid}'.`);
        continue;
      }
      if (seen.has(aid)) {
        errors.push(`Rail '${rid}': duplicate anilist_id ${aid}.`);
      }
      seen.add(aid);
    }
  }

  return errors;
}

function generateSQL(config) {
  const lines = [];
  lines.push(`-- Curated rails migration generated from rail_config.json`);
  lines.push(`-- Rails: ${config.rails.length}`);
  lines.push(`-- Total items: ${config.rails.reduce((sum, r) => sum + r.items.length, 0)}`);
  lines.push(`--`);
  lines.push(`-- This file is auto-generated. Do not edit manually.`);
  lines.push(`-- Edit scripts/rail_config.json and re-run scripts/generate_rail_migration.js`);
  lines.push(``);
  lines.push(`begin;`);
  lines.push(``);

  // Upsert all rails (sorted by id for determinism)
  const sortedRails = [...config.rails].sort((a, b) => a.id.localeCompare(b.id));

  for (const rail of sortedRails) {
    lines.push(
      `insert into public.curated_rails(id,title,media_type,description) values ` +
      `('${formatSQLString(rail.id)}','${formatSQLString(rail.title)}','${formatSQLString(rail.media_type)}','${formatSQLString(rail.description || "")}') ` +
      `on conflict (id) do update set title = excluded.title, media_type = excluded.media_type, description = excluded.description;`
    );
  }

  lines.push(``);

  // Delete all items for these rails
  const railIdList = sortedRails.map((r) => `'${formatSQLString(r.id)}'`).join(",");
  lines.push(`delete from public.curated_rail_items where rail_id in (${railIdList});`);
  lines.push(``);

  // Insert items in chunks, sorted by rail_id then rank
  const allItems = [];
  for (const rail of sortedRails) {
    for (let i = 0; i < rail.items.length; i++) {
      const item = rail.items[i];
      allItems.push({
        rail_id: rail.id,
        media_type: rail.media_type,
        anilist_id: item.anilist_id,
        rank: i + 1,
        note: item.note || null,
      });
    }
  }

  const chunkSize = 500;
  for (let i = 0; i < allItems.length; i += chunkSize) {
    const chunk = allItems.slice(i, i + chunkSize);
    lines.push(`insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values`);
    lines.push(
      chunk
        .map((it) => {
          const note = it.note ? `'${formatSQLString(it.note)}'` : "null";
          return `('${formatSQLString(it.rail_id)}','${formatSQLString(it.media_type)}',${Number(it.anilist_id)},${Number(it.rank)},${note})`;
        })
        .join(",\n") +
      "\n" +
      "on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;"
    );
    lines.push(``);
  }

  lines.push(`commit;`);
  lines.push(``);

  return lines.join("\n");
}

function main() {
  const config = loadConfig();

  // Validate
  const errors = validate(config);
  if (errors.length > 0) {
    console.error("Validation failed:");
    for (const e of errors) {
      console.error(`  - ${e}`);
    }
    process.exit(1);
  }

  // Generate
  const sql = generateSQL(config);

  // Output
  const outPath = process.argv[2];
  if (outPath) {
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, sql, "utf8");
    console.error(`Wrote ${outPath}`);
    console.error(`Rails: ${config.rails.length}`);
    console.error(`Total items: ${config.rails.reduce((sum, r) => sum + r.items.length, 0)}`);
  } else {
    process.stdout.write(sql);
  }
}

main();
