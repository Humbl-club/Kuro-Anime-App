#!/usr/bin/env node
'use strict';
/*
  Catalogue shadow comparator report (docs/superpowers/plans/2026-11-09-catalogue-sources.md Task 8).

  Calls the service-only RPC catalogue_shadow_report_v1 (prepared migration
  20261112100100_catalogue_shadow_report_v1.sql) and writes
    <out>.json   the raw report plus the gate evaluation
    <out>.md     a Markdown summary of every spec section 6 gate: pass / fail / insufficient
  The RPC only reads. It compares composed shadow values with today's published columns.

  Usage:
    SUPABASE_SERVICE_ROLE_KEY=... node scripts/catalogue_shadow_report.js \
      --medium anime|manga [--out docs/catalogue-sources-2026-11/runs/<date>-<medium>.json] [--sample 20]

  Database access is an injected dependency (callRpc), so the evaluation and the file output are
  tested offline. main() builds the real one with supabase-js. Run folder and run-id rule:
  docs/catalogue-sources-2026-11/README.md. The service key is read from the environment and never printed.
*/

const path = require('node:path');

const RPC_NAME = 'catalogue_shadow_report_v1';
/** A tier with fewer compared rows than this can only be 'insufficient', never 'pass'. */
const MIN_COMPARED = 30;
const DEFAULT_RUN_DIR = 'docs/catalogue-sources-2026-11/runs';

// ---------------------------------------------------------------------------------------------
// Gate evaluation (spec section 6)

const RANK = { fail: 2, insufficient: 1, pass: 0 };

function worst(statuses) {
  if (statuses.length === 0) return 'insufficient';
  return statuses.reduce((a, b) => (RANK[b] > RANK[a] ? b : a));
}

/** n = the sample the ratio rests on; below MIN_COMPARED the answer is insufficient, never pass. */
function ratioGate({ group, metric, tier, threshold, num, den, n, note }) {
  const value = den > 0 ? num / den : null;
  let status;
  if (n < MIN_COMPARED || value === null) status = 'insufficient';
  else status = value >= threshold ? 'pass' : 'fail';
  return { group, metric, tier, threshold, value, n, status, ...(note ? { note } : {}) };
}

const cellOf = (report, group, tier) => report.groups?.[group]?.[tier] ?? { total: 0, covered: 0, compared: 0, agreed: 0, disagree_sample: [] };

const UNMEASURED = {
  relations: '>= 90% of today\'s SEQUEL/PREQUEL pairs among linked titles reproduced (not in the shadow report yet)',
  popularity: 'Spearman >= 0.7 on top 5k (Task 10)',
  tags: 'median top-5 tag overlap >= 60% (Task 11)',
  episodes: 'next airing within 24 h of the provider (Task 9, gate L1)',
  synopsis: 'own synopsis on >= 95% of top 5k (Task 12, gate L2)',
  images: 'licensed or Kuro artwork on 100% of visible titles (Task 13, gate L3)',
};

function gateEvaluation(report) {
  const medium = report.medium === 'manga' ? 'manga' : 'anime';
  const gates = [];

  // identity
  const idCell = (tier) => cellOf(report, 'identity', tier);
  const top5kThreshold = medium === 'anime' ? 0.95 : 0.85;
  for (const [tier, threshold] of [['in_lists', 1], ['curated', 1], ['top5k', top5kThreshold]]) {
    const c = idCell(tier);
    gates.push(ratioGate({ group: 'identity', metric: 'linked_share', tier, threshold, num: c.covered, den: c.total, n: c.total, note: 'accepted non-AniList link' }));
  }
  const dup = report.identity_gate?.duplicate_accepted_links ?? 0;
  gates.push({
    group: 'identity', metric: 'duplicate_accepted_links', tier: 'all', threshold: 0, value: dup, n: idCell('all').total,
    status: dup > 0 ? 'fail' : idCell('all').total === 0 ? 'insufficient' : 'pass',
  });
  const orphans = report.identity_gate?.orphan_accepted_links ?? 0;
  gates.push({
    group: 'identity', metric: 'orphan_accepted_links', tier: 'all', threshold: 0, value: orphans, n: idCell('all').total,
    status: orphans > 0 ? 'fail' : 'pass', note: 'accepted links whose target title no longer exists',
  });
  const invalid = report.invalid_shadow_values ?? 0;
  gates.push({
    group: 'data', metric: 'invalid_shadow_values', tier: 'all', threshold: 0, value: invalid, n: null,
    status: invalid > 0 ? 'fail' : 'pass', note: 'shadow values that are not a valid integer/boolean for their field',
  });
  gates.push({
    group: 'identity', metric: 'title_match_precision', tier: 'sample', threshold: 0.99, value: null, n: 0, status: 'insufficient',
    note: 'needs the 200-title owner-reviewed sample; not computable from the shadow report',
  });

  // titles
  const linked = idCell('all').covered;
  gates.push(ratioGate({
    group: 'titles', metric: 'display_title_of_linked', tier: 'all', threshold: 1,
    num: cellOf(report, 'titles', 'all').covered, den: linked, n: linked,
  }));
  const nat = cellOf(report, 'titles_native', 'top5k');
  gates.push(ratioGate({ group: 'titles', metric: 'native_title', tier: 'top5k', threshold: 0.95, num: nat.covered, den: nat.total, n: nat.total }));

  // facts: where both sources have a value
  const facts = [['start_year_exact', 'facts_start_year', 0.98], ['format_mapped', 'facts_format', 0.97]];
  if (medium === 'anime') facts.push(['episodes_finished', 'facts_episodes', 0.97]);
  for (const [metric, group, threshold] of facts) {
    const c = cellOf(report, group, 'all');
    gates.push(ratioGate({ group: 'facts', metric, tier: 'all', threshold, num: c.agreed, den: c.compared, n: c.compared }));
  }

  // adult: zero tolerance for a title that is adult today and would become non-adult
  const becomes = report.adult?.becomes_non_adult ?? 0;
  const adultCompared = cellOf(report, 'adult', 'all').compared;
  gates.push({
    group: 'adult', metric: 'becomes_non_adult', tier: 'all', threshold: 0, value: becomes, n: adultCompared,
    status: becomes > 0 ? 'fail' : adultCompared < MIN_COMPARED ? 'insufficient' : 'pass',
    note: `newly adult (to list for review): ${report.adult?.newly_adult ?? 0}; review list size: ${report.adult?.review_size ?? 0}`,
  });

  for (const [group, note] of Object.entries(UNMEASURED)) {
    gates.push({ group, metric: 'not_measured', tier: '-', threshold: null, value: null, n: 0, status: 'insufficient', note });
  }

  const summary = {};
  for (const g of gates) (summary[g.group] ??= []).push(g.status);
  for (const k of Object.keys(summary)) summary[k] = worst(summary[k]);
  return { gates, summary, min_compared: MIN_COMPARED };
}

// ---------------------------------------------------------------------------------------------
// Rendering

const pct = (v) => (v === null || v === undefined ? 'n/a' : `${(v * 100).toFixed(1)}%`);

function renderMarkdown({ run_id, medium, generated_at, report, evaluation }) {
  const lines = [];
  lines.push(`# Catalogue shadow report ${run_id}`, '');
  lines.push(`Medium: ${medium}. Generated: ${generated_at}.`);
  lines.push('This compares composed shadow values with the published columns as they were at that moment. It is local-shadow evidence, not a cutover decision and not proof of hosted behaviour.', '');
  lines.push(`Tier sizes: ${JSON.stringify(report.tiers)}`, '');
  lines.push('## Gate summary', '', '| group | status |', '|---|---|');
  for (const [group, status] of Object.entries(evaluation.summary)) lines.push(`| ${group} | ${status} |`);
  lines.push('', `A tier with fewer than ${evaluation.min_compared} compared rows is insufficient, never pass.`, '');
  lines.push('## Gates', '', '| group | metric | tier | threshold | value | n | status | note |', '|---|---|---|---|---|---|---|---|');
  for (const g of evaluation.gates) {
    const threshold = typeof g.threshold === 'number' && g.threshold <= 1 && g.threshold > 0 ? pct(g.threshold) : g.threshold ?? '';
    const value = typeof g.value === 'number' && g.threshold !== 0 ? pct(g.value) : g.value ?? 'n/a';
    lines.push(`| ${g.group} | ${g.metric} | ${g.tier} | ${threshold} | ${value} | ${g.n} | ${g.status} | ${g.note ?? ''} |`);
  }
  lines.push('', '## Identity gate counts', '', '```json', JSON.stringify(report.identity_gate ?? {}, null, 2), '```', '');
  lines.push('## Adult', '', '```json', JSON.stringify(report.adult ?? {}, null, 2), '```', '');
  lines.push('## Disagreement samples (tier all)', '');
  let any = false;
  for (const [group, tiers] of Object.entries(report.groups ?? {})) {
    const sample = tiers?.all?.disagree_sample ?? [];
    if (sample.length === 0) continue;
    any = true;
    lines.push(`### ${group}`, '', '| id | today | shadow |', '|---|---|---|');
    for (const s of sample) lines.push(`| ${s.id} | ${JSON.stringify(s.today)} | ${JSON.stringify(s.shadow)} |`);
    lines.push('');
  }
  if (!any) lines.push('None in the sample.', '');
  return lines.join('\n');
}

// ---------------------------------------------------------------------------------------------
// Run

function runIdFromOut(out) {
  return path.basename(out).replace(/\.json$/i, '');
}

function parseArgs(argv) {
  const opts = { medium: null, out: null, sample: 20 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--medium') opts.medium = argv[++i];
    else if (a === '--out') opts.out = argv[++i];
    else if (a === '--sample') opts.sample = Number(argv[++i]);
    else throw new Error(`unknown argument: ${a}`);
  }
  if (!opts.medium) throw new Error('--medium anime|manga is required');
  if (opts.medium !== 'anime' && opts.medium !== 'manga') throw new Error('--medium must be anime or manga');
  if (!Number.isInteger(opts.sample) || opts.sample < 0 || opts.sample > 100) throw new Error('--sample must be an integer 0..100');
  return opts;
}

/** `callRpc(name, args)` resolves to { data, error } (the supabase-js shape). `fs` is { exists, mkdir, writeFile }. */
async function runReport({ medium, sample = 20, out, callRpc, fs, now = () => new Date() }) {
  const when = now();
  const outPath = out ?? path.join(DEFAULT_RUN_DIR, `${when.toISOString().slice(0, 10)}-${medium}.json`);
  const mdPath = outPath.replace(/\.json$/i, '') + '.md';
  for (const p of [outPath, mdPath]) {
    if (fs.exists(p)) throw new Error(`${p} already exists; pick a new run id (never overwrite an earlier run)`);
  }
  const { data, error } = await callRpc(RPC_NAME, { p_medium: medium, p_sample: sample });
  if (error) throw new Error(`${RPC_NAME} failed: ${error.message ?? JSON.stringify(error)}`);
  if (!data || typeof data !== 'object') throw new Error(`${RPC_NAME} returned no report`);
  const evaluation = gateEvaluation(data);
  const run = { run_id: runIdFromOut(outPath), medium, generated_at: when.toISOString(), rpc: RPC_NAME, report: data, evaluation };
  fs.mkdir(path.dirname(outPath));
  fs.writeFile(outPath, JSON.stringify(run, null, 2) + '\n');
  fs.writeFile(mdPath, renderMarkdown(run) + '\n');
  return { outPath, mdPath, run, evaluation };
}

async function main(argv = process.argv.slice(2)) {
  const nodeFs = require('node:fs');
  const opts = parseArgs(argv);
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY env var.');
  const { createClient } = require('@supabase/supabase-js');
  const { getProjectUrl } = require('./lib/project_config');
  const client = createClient(getProjectUrl(), key, { auth: { persistSession: false } });
  const result = await runReport({
    medium: opts.medium,
    sample: opts.sample,
    out: opts.out,
    callRpc: (name, args) => client.rpc(name, args),
    fs: {
      exists: (p) => nodeFs.existsSync(p),
      mkdir: (p) => nodeFs.mkdirSync(p, { recursive: true }),
      writeFile: (p, c) => nodeFs.writeFileSync(p, c),
    },
  });
  console.log(`wrote ${result.outPath} and ${result.mdPath}`);
  for (const [group, status] of Object.entries(result.evaluation.summary)) console.log(`${group}: ${status}`);
}

module.exports = { gateEvaluation, parseArgs, renderMarkdown, runReport, runIdFromOut, MIN_COMPARED, RPC_NAME };

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}
