#!/usr/bin/env node
/*
  Generates/refreshes the AUTO-INVENTORY section inside CURRENT_APP_STATE.md.

  Goal:
  - Keep the app-state doc reflective of the repo *without* pasting the entire codebase.
  - Provide an exhaustive file inventory so another LLM can orient quickly.

  Usage:
    node scripts/generate_app_state_inventory.js
*/

const fs = require('fs');
const cp = require('child_process');
const path = require('path');

const ROOT = process.cwd();
const TECH_DOC = path.join(ROOT, 'CURRENT_APP_STATE.md');

const START = '<!-- BEGIN AUTO-INVENTORY -->';
const END = '<!-- END AUTO-INVENTORY -->';

function sh(cmd) {
  return cp.execSync(cmd, { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] }).toString('utf8').trim();
}

function listFiles(dir, predicate = () => true) {
  const out = [];
  const stack = [dir];
  while (stack.length) {
    const cur = stack.pop();
    const entries = fs.readdirSync(cur, { withFileTypes: true });
    for (const e of entries) {
      const p = path.join(cur, e.name);
      if (e.isDirectory()) {
        // Skip build artifacts.
        if (e.name === 'node_modules' || e.name === 'DerivedData' || e.name === 'build' || e.name.startsWith('.git')) continue;
        stack.push(p);
      } else if (e.isFile()) {
        if (predicate(p)) out.push(p);
      }
    }
  }
  out.sort();
  return out;
}

function rel(p) {
  return path.relative(ROOT, p);
}

function mdList(items, { max = 4000 } = {}) {
  // Hard cap so we don't explode the doc; inventory remains comprehensive but bounded.
  // The list remains exhaustive because we still include counts and grouping; if truncated,
  // we include a note and suggest using find/grep.
  const lines = [];
  const truncated = items.length > max;
  const show = truncated ? items.slice(0, max) : items;
  for (const it of show) lines.push(`- \`${it}\``);
  if (truncated) {
    lines.push(`- … truncated (${items.length - max} more). Run \`node scripts/generate_app_state_inventory.js\` or \`find\` to enumerate.`);
  }
  return lines.join('\n');
}

function groupByPrefix(items, prefixes) {
  const groups = new Map(prefixes.map(p => [p, []]));
  groups.set('other', []);
  for (const it of items) {
    const hit = prefixes.find(p => it.includes(p));
    if (hit) groups.get(hit).push(it);
    else groups.get('other').push(it);
  }
  return groups;
}

function main() {
  if (!fs.existsSync(TECH_DOC)) {
    console.error(`Missing ${TECH_DOC}`);
    process.exit(1);
  }

  const doc = fs.readFileSync(TECH_DOC, 'utf8');
  const s = doc.indexOf(START);
  const e = doc.indexOf(END);
  if (s === -1 || e === -1 || e <= s) {
    console.error('AUTO-INVENTORY markers not found. Add them to CURRENT_APP_STATE.md.');
    process.exit(1);
  }

  const now = new Date();
  const iso = now.toISOString();
  // Use HEAD only (not --dirty) so regenerated docs don't perpetually claim "dirty".
  const head = sh('git rev-parse --short HEAD');
  const branch = sh('git rev-parse --abbrev-ref HEAD');

  const swift = listFiles(path.join(ROOT, 'Kuro'), p => p.endsWith('.swift')).map(rel);
  const migrations = listFiles(path.join(ROOT, 'supabase', 'migrations'), p => p.endsWith('.sql')).map(rel);
  const edgeIndex = listFiles(path.join(ROOT, 'supabase', 'functions'), p => p.endsWith('index.ts')).map(rel);
  const scripts = listFiles(path.join(ROOT, 'scripts'), p => p.endsWith('.js') || p.endsWith('.sql') || p.endsWith('.ts') || p.endsWith('.md')).map(rel);

  const inventory = [];
  inventory.push('## 2.1) Auto-generated inventory (exhaustive file lists)');
  inventory.push('');
  inventory.push(`Generated: **${iso}**  (git: \`${head}\` on \`${branch}\`)`);
  inventory.push('');
  inventory.push('This section is auto-generated. Rebuild it after any repo change:');
  inventory.push('```bash');
  inventory.push('node scripts/generate_app_state_inventory.js');
  inventory.push('```');
  inventory.push('');

  inventory.push(`### iOS (Swift) files (count: ${swift.length})`);
  inventory.push(mdList(swift, { max: 2000 }));
  inventory.push('');

  inventory.push(`### Supabase migrations (count: ${migrations.length})`);
  inventory.push(mdList(migrations, { max: 2000 }));
  inventory.push('');

  inventory.push(`### Supabase Edge Functions (index.ts) (count: ${edgeIndex.length})`);
  inventory.push(mdList(edgeIndex, { max: 2000 }));
  inventory.push('');

  inventory.push(`### Repo scripts (count: ${scripts.length})`);
  inventory.push(mdList(scripts, { max: 2000 }));
  inventory.push('');

  const out = doc.slice(0, s + START.length) + '\n\n' + inventory.join('\n') + '\n\n' + doc.slice(e);
  fs.writeFileSync(TECH_DOC, out);
  console.log(`Updated AUTO-INVENTORY in ${TECH_DOC}`);
}

main();
