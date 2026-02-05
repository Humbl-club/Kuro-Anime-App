#!/usr/bin/env node
/*
  Injects "source of truth" excerpts into CURRENT_APP_STATE.md.

  Why:
  - The technical doc should be readable, but LLMs need ground-truth sources.
  - We inline the most important runtime sources (pager/nav, Supabase client, concierge edge funcs)
    so another model can reason without opening the repo.

  Usage:
    node scripts/generate_app_state_sources.js
*/

const fs = require('fs');
const cp = require('child_process');
const path = require('path');

const ROOT = process.cwd();
const DOC = path.join(ROOT, 'CURRENT_APP_STATE.md');

const START = '<!-- BEGIN AUTO-SOURCE-EXCERPTS -->';
const END = '<!-- END AUTO-SOURCE-EXCERPTS -->';

function sh(cmd) {
  return cp.execSync(cmd, { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] }).toString('utf8').trim();
}

function replaceSection(doc, start, end, replacement) {
  const s = doc.indexOf(start);
  const e = doc.indexOf(end);
  if (s === -1 || e === -1 || e <= s) throw new Error(`Missing markers: ${start}`);
  return doc.slice(0, s + start.length) + '\n\n' + replacement + '\n\n' + doc.slice(e);
}

function readText(relPath) {
  const abs = path.join(ROOT, relPath);
  if (!fs.existsSync(abs)) return null;
  return fs.readFileSync(abs, 'utf8');
}

function fenceFor(p) {
  if (p.endsWith('.swift')) return 'swift';
  if (p.endsWith('.ts')) return 'ts';
  if (p.endsWith('.js')) return 'js';
  if (p.endsWith('.sql')) return 'sql';
  if (p.endsWith('.md')) return 'md';
  if (p.endsWith('.toml')) return 'toml';
  if (p.endsWith('.json')) return 'json';
  return '';
}

function excerptBlock(relPath, { title } = {}) {
  const src = readText(relPath);
  const lang = fenceFor(relPath);
  const header = title ? `### ${title}\n\n- Path: \`${relPath}\`\n` : `### \`${relPath}\``;
  if (src == null) {
    return `${header}\n\n_(Missing in repo at generation time.)_\n`;
  }
  // NOTE: For "minute detail" we inline the full file. This can be large, but remains authoritative.
  return `${header}\n\n\`\`\`${lang}\n${src}\n\`\`\`\n`;
}

function main() {
  const doc = fs.readFileSync(DOC, 'utf8');
  const now = new Date().toISOString();
  // Use HEAD only (not --dirty) so regenerated docs don't perpetually claim "dirty".
  const head = sh('git rev-parse --short HEAD');

  const blocks = [];
  blocks.push(`Generated: **${now}** (git: \`${head}\`)`);
  blocks.push('');
  blocks.push('This section is auto-generated. Rebuild after any change to the referenced files:');
  blocks.push('```bash');
  blocks.push('node scripts/generate_app_state_sources.js');
  blocks.push('```');
  blocks.push('');

  // Pager + navigation (swipe order, profile placement, concierge page).
  blocks.push(excerptBlock('Kuro/ContentView.swift', { title: 'iOS pager + swipe navigation (authoritative)' }));

  // Client/backend integration.
  blocks.push(excerptBlock('Kuro/Services/SupabaseService.swift', { title: 'iOS Supabase client + RPC/Edge wiring (authoritative)' }));

  // Concierge UI.
  blocks.push(excerptBlock('Kuro/Views/ConciergeView.swift', { title: 'Concierge UI (authoritative)' }));

  // Concierge edge functions (runtime behavior).
  blocks.push(excerptBlock('supabase/functions/concierge-parse/index.ts', { title: 'Edge Function: concierge-parse (deterministic parsing)' }));
  blocks.push(excerptBlock('supabase/functions/concierge-resolve/index.ts', { title: 'Edge Function: concierge-resolve (LLM disambiguation)' }));
  blocks.push(excerptBlock('supabase/functions/concierge-recommend/index.ts', { title: 'Edge Function: concierge-recommend (recommend + narration)' }));
  blocks.push(excerptBlock('supabase/functions/concierge-apply/index.ts', { title: 'Edge Function: concierge-apply (idempotent upserts)' }));
  blocks.push(excerptBlock('supabase/functions/concierge-undo/index.ts', { title: 'Edge Function: concierge-undo (session rollback)' }));

  // Budget + rate-limit DB contracts (so LLM can reason about protections).
  blocks.push(excerptBlock('supabase/migrations/20260204221500_concierge_rate_limits_and_llm_budgets.sql', { title: 'DB: Concierge rate limits + LLM budgets (source)' }));
  blocks.push(excerptBlock('supabase/migrations/20260205000500_concierge_global_llm_budget_and_default_tuning.sql', { title: 'DB: Global LLM budget + defaults (source)' }));
  blocks.push(excerptBlock('supabase/migrations/20260205160000_admin_schema_snapshot.sql', { title: 'DB: Admin schema snapshot RPC (source)' }));

  const out = replaceSection(doc, START, END, blocks.join('\n'));
  fs.writeFileSync(DOC, out);
  console.log('Updated AUTO-SOURCE-EXCERPTS in CURRENT_APP_STATE.md');
}

main();
