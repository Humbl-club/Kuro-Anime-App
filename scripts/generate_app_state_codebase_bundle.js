#!/usr/bin/env node
/*
  Generates CURRENT_APP_STATE_CODEBASE.md: a (very large) markdown bundle of the
  repo's relevant source files for LLM consumption.

  This is intentionally exhaustive (for the app/backend) but excludes:
  - node_modules/
  - build artifacts (build/, DerivedData/)
  - git metadata

  Usage:
    node scripts/generate_app_state_codebase_bundle.js
*/

const fs = require('fs');
const cp = require('child_process');
const path = require('path');

const ROOT = process.cwd();
const OUT = path.join(ROOT, 'CURRENT_APP_STATE_CODEBASE.md');

function sh(cmd) {
  return cp.execSync(cmd, { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] }).toString('utf8').trim();
}

function isSkipDir(name) {
  return (
    name === 'node_modules' ||
    name === 'build' ||
    name === 'DerivedData' ||
    name === '.git' ||
    name === '.venv' ||
    name === 'mockups'
  );
}

function listFiles(dir, predicate) {
  const out = [];
  const stack = [dir];
  while (stack.length) {
    const cur = stack.pop();
    const entries = fs.readdirSync(cur, { withFileTypes: true });
    for (const e of entries) {
      const p = path.join(cur, e.name);
      if (e.isDirectory()) {
        if (isSkipDir(e.name)) continue;
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

function fenceFor(p) {
  if (p.endsWith('.swift')) return 'swift';
  if (p.endsWith('.ts')) return 'ts';
  if (p.endsWith('.js')) return 'js';
  if (p.endsWith('.sql')) return 'sql';
  if (p.endsWith('.md')) return 'md';
  if (p.endsWith('.json')) return 'json';
  if (p.endsWith('.toml')) return 'toml';
  if (p.endsWith('.plist')) return 'xml';
  if (p.endsWith('.pbxproj')) return '';
  return '';
}

function readUtf8(p) {
  // Only bundle files that are actually UTF-8 text. If decode fails, skip.
  try {
    return fs.readFileSync(p, 'utf8');
  } catch {
    return null;
  }
}

function section(title) {
  return `\n---\n\n# ${title}\n\n`;
}

function fileBlock(p) {
  const r = rel(p);
  const src = readUtf8(p);
  if (src == null) return null;
  const lang = fenceFor(r);
  return `## \`${r}\`\n\n\`\`\`${lang}\n${src}\n\`\`\`\n`;
}

function main() {
  const now = new Date().toISOString();
  // Use HEAD only (not --dirty) so regenerated bundles don't perpetually claim "dirty".
  const head = sh('git rev-parse --short HEAD');
  const branch = sh('git rev-parse --abbrev-ref HEAD');

  const header = [
    '# Kuro — Codebase Bundle (LLM Source of Truth)',
    '',
    `Generated: **${now}** (git: \`${head}\` on \`${branch}\`)`,
    '',
    'This file is **auto-generated**. It is intentionally large.',
    '',
    'Rebuild:',
    '```bash',
    'node scripts/generate_app_state_codebase_bundle.js',
    '```',
    '',
    'Included (exhaustive for app/backend):',
    '- iOS Swift: `Kuro/**/*.swift`',
    '- Supabase Edge Functions: `supabase/functions/**/index.ts`',
    '- Supabase migrations + ops docs: `supabase/migrations/*.sql`, `supabase/*.md`',
    '- Repo scripts: `scripts/**/*.(js|ts|sql|md)`',
    '- Root configs: `package.json`, `package-lock.json`, `.gitignore`, `Kuro.xcodeproj/project.pbxproj`',
    '',
    'Excluded:',
    '- `node_modules/`, `build/`, `.git/`, `.venv/`',
    '',
  ].join('\n');

  const allowExt = new Set([
    '.swift',
    '.ts',
    '.js',
    '.sql',
    '.md',
    '.json',
    '.toml',
    '.plist',
    '.pbxproj',
    '.txt',
  ]);

  const files = listFiles(ROOT, (p) => {
    const r = rel(p);
    if (r === 'CURRENT_APP_STATE_CODEBASE.md') return false; // avoid self-embedding
    const ext = path.extname(r).toLowerCase();
    if (allowExt.has(ext)) return true;
    // Allow a few root config files without extensions.
    if (r === '.gitignore') return true;
    return false;
  });

  const parts = [header];
  parts.push(section('Bundled Sources'));

  for (const p of files) {
    const b = fileBlock(p);
    if (b) parts.push(b);
  }

  fs.writeFileSync(OUT, parts.join('\n'), 'utf8');
  console.log(`Wrote ${OUT} (${files.length} files)`);
}

main();
