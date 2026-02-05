#!/usr/bin/env node
/*
  Generates/refreshes auto sections inside CURRENT_APP_STATE.md:
  - Migration object map (tables/functions/policies/indexes/cron)
  - Edge function map (env vars, RPCs, tables touched, notes)
  - iOS RPC + Edge Function usage index

  Usage:
    node scripts/generate_app_state_maps.js
*/

const fs = require('fs');
const cp = require('child_process');
const path = require('path');

const ROOT = process.cwd();
const DOC = path.join(ROOT, 'CURRENT_APP_STATE.md');

const MARKERS = {
  migration: { start: '<!-- BEGIN AUTO-MIGRATION-MAP -->', end: '<!-- END AUTO-MIGRATION-MAP -->' },
  edge: { start: '<!-- BEGIN AUTO-EDGE-MAP -->', end: '<!-- END AUTO-EDGE-MAP -->' },
  ios: { start: '<!-- BEGIN AUTO-IOS-MAP -->', end: '<!-- END AUTO-IOS-MAP -->' },
};

function sh(cmd) {
  return cp.execSync(cmd, { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] }).toString('utf8');
}

function list(dir, filter) {
  const out = [];
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isFile() && filter(p)) out.push(p);
  }
  out.sort();
  return out;
}

function rel(p) { return path.relative(ROOT, p); }

function extractSqlObjects(sql) {
  const lines = sql.split(/\r?\n/);
  const objects = {
    tables: new Set(),
    views: new Set(),
    functions: new Set(),
    policies: new Set(),
    indexes: new Set(),
    triggers: new Set(),
    extensions: new Set(),
    cron: new Set(),
  };

  const add = (set, v) => { if (v) set.add(v.trim()); };

  for (const line of lines) {
    const l = line.trim();
    let m;

    m = l.match(/^create\s+extension\s+if\s+not\s+exists\s+([a-z0-9_]+)\b/i);
    if (m) add(objects.extensions, m[1]);

    m = l.match(/^create\s+table\s+if\s+not\s+exists\s+([a-z0-9_\.]+)\b/i);
    if (m) add(objects.tables, m[1]);
    m = l.match(/^create\s+table\s+([a-z0-9_\.]+)\s*\(/i);
    if (m) add(objects.tables, m[1]);

    m = l.match(/^create\s+(or\s+replace\s+)?view\s+([a-z0-9_\.]+)\b/i);
    if (m) add(objects.views, m[2]);

    m = l.match(/^create\s+(or\s+replace\s+)?function\s+([a-z0-9_\.]+)\s*\(/i);
    if (m) add(objects.functions, m[2]);

    m = l.match(/^create\s+policy\s+"?([^"]+)"?\s+on\s+([a-z0-9_\.]+)/i);
    if (m) add(objects.policies, `${m[2]}:${m[1]}`);

    m = l.match(/^create\s+index\s+if\s+not\s+exists\s+([a-z0-9_]+)\b/i);
    if (m) add(objects.indexes, m[1]);

    m = l.match(/^create\s+trigger\s+([a-z0-9_]+)\b/i);
    if (m) add(objects.triggers, m[1]);

    // pg_cron scheduling
    m = l.match(/cron\.schedule\(\s*'([^']+)'\s*,\s*'([^']+)'/i);
    if (m) add(objects.cron, `${m[1]} @ ${m[2]}`);
  }

  return objects;
}

function extractTsThings(ts) {
  const env = new Set();
  const rpc = new Set();
  const tables = new Set();

  for (const m of ts.matchAll(/Deno\.env\.get\(\s*["']([A-Z0-9_]+)["']\s*\)/g)) env.add(m[1]);
  for (const m of ts.matchAll(/\.rpc\(\s*["']([a-z0-9_]+)["']/gi)) rpc.add(m[1]);
  for (const m of ts.matchAll(/\.from\(\s*'([a-z0-9_]+)'\s*\)/gi)) tables.add(m[1]);
  for (const m of ts.matchAll(/\.from\(\s*"([a-z0-9_]+)"\s*\)/gi)) tables.add(m[1]);

  return { env, rpc, tables };
}

function extractSwiftRpcAndFunctions(swift) {
  const rpc = new Set();
  const fn = new Set();

  for (const m of swift.matchAll(/\.rpc\(\s*"([a-z0-9_]+)"/gi)) rpc.add(m[1]);
  // Edge Functions are called via Functions client; we pattern match endpoints.
  for (const m of swift.matchAll(/functions\.invoke\(\s*"([a-z0-9\-]+)"/gi)) fn.add(m[1]);
  // Also catch raw paths if used.
  for (const m of swift.matchAll(/functions\/v1\/([a-z0-9\-]+)/gi)) fn.add(m[1]);

  return { rpc, fn };
}

function replaceSection(doc, start, end, replacement) {
  const s = doc.indexOf(start);
  const e = doc.indexOf(end);
  if (s === -1 || e === -1 || e <= s) throw new Error(`Missing markers: ${start}`);
  return doc.slice(0, s + start.length) + '\n\n' + replacement + '\n\n' + doc.slice(e);
}

function main() {
  let doc = fs.readFileSync(DOC, 'utf8');

  const now = new Date().toISOString();
  const head = sh('git rev-parse --short HEAD').trim();

  // 1) Migration map
  const migDir = path.join(ROOT, 'supabase', 'migrations');
  const migFiles = list(migDir, p => p.endsWith('.sql'));
  const migLines = [];
  migLines.push('## 7.1) Auto migration map (objects by migration)');
  migLines.push('');
  migLines.push(`Generated: **${now}** (git: \`${head}\`)`);
  migLines.push('');
  migLines.push('Each migration is summarized by the objects it defines. For full SQL, open the file.');
  migLines.push('');

  for (const f of migFiles) {
    const sql = fs.readFileSync(f, 'utf8');
    const o = extractSqlObjects(sql);
    const name = rel(f);
    migLines.push(`### ${name}`);

    const fmt = (label, set) => {
      const arr = [...set];
      if (!arr.length) return;
      arr.sort();
      migLines.push(`- ${label} (${arr.length}): ${arr.map(x => `\`${x}\``).join(', ')}`);
    };

    fmt('Extensions', o.extensions);
    fmt('Tables', o.tables);
    fmt('Views', o.views);
    fmt('Functions', o.functions);
    fmt('Policies', o.policies);
    fmt('Indexes', o.indexes);
    fmt('Triggers', o.triggers);
    fmt('Cron', o.cron);

    migLines.push('');
  }

  // 2) Edge function map
  const fnDir = path.join(ROOT, 'supabase', 'functions');
  const fnIndex = [];
  for (const d of fs.readdirSync(fnDir)) {
    const p = path.join(fnDir, d, 'index.ts');
    if (fs.existsSync(p)) fnIndex.push(p);
  }
  fnIndex.sort();

  const edgeLines = [];
  edgeLines.push('## 8.2) Auto edge-function map (contracts + dependencies)');
  edgeLines.push('');
  edgeLines.push(`Generated: **${now}** (git: \`${head}\`)`);
  edgeLines.push('');

  for (const f of fnIndex) {
    const name = path.basename(path.dirname(f));
    const ts = fs.readFileSync(f, 'utf8');
    const x = extractTsThings(ts);
    edgeLines.push(`### ${name}`);
    edgeLines.push(`- Source: \`${rel(f)}\``);
    if (x.env.size) edgeLines.push(`- Env vars: ${[...x.env].sort().map(v => `\`${v}\``).join(', ')}`);
    if (x.rpc.size) edgeLines.push(`- RPCs: ${[...x.rpc].sort().map(v => `\`${v}\``).join(', ')}`);
    if (x.tables.size) edgeLines.push(`- Tables touched: ${[...x.tables].sort().map(v => `\`${v}\``).join(', ')}`);
    edgeLines.push('');
  }

  // 3) iOS usage index
  const svcPath = path.join(ROOT, 'Kuro', 'Services', 'SupabaseService.swift');
  const svc = fs.existsSync(svcPath) ? fs.readFileSync(svcPath, 'utf8') : '';
  const swiftAll = svc;
  const u = extractSwiftRpcAndFunctions(swiftAll);

  const iosLines = [];
  iosLines.push('## 3.2) Auto iOS backend usage index');
  iosLines.push('');
  iosLines.push(`Generated: **${now}** (git: \`${head}\`)`);
  iosLines.push('');
  iosLines.push('- Swift file scanned: `Kuro/Services/SupabaseService.swift`');
  iosLines.push('');
  iosLines.push(`### RPCs used by iOS (count: ${u.rpc.size})`);
  iosLines.push([...[...u.rpc].sort()].map(v => `- \`${v}\``).join('\n') || '- (none found)');
  iosLines.push('');
  iosLines.push(`### Edge Functions invoked by iOS (count: ${u.fn.size})`);
  iosLines.push([...[...u.fn].sort()].map(v => `- \`${v}\``).join('\n') || '- (none found)');
  iosLines.push('');

  // Apply replacements.
  doc = replaceSection(doc, MARKERS.migration.start, MARKERS.migration.end, migLines.join('\n'));
  doc = replaceSection(doc, MARKERS.edge.start, MARKERS.edge.end, edgeLines.join('\n'));
  doc = replaceSection(doc, MARKERS.ios.start, MARKERS.ios.end, iosLines.join('\n'));

  fs.writeFileSync(DOC, doc);
  console.log('Updated AUTO maps in CURRENT_APP_STATE.md');
}

main();
