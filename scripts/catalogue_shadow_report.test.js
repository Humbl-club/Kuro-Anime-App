'use strict';
// Offline tests for scripts/catalogue_shadow_report.js (catalogue Task 8). No network, no database:
// the RPC is an injected fake. Run: node --test scripts/catalogue_shadow_report.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {
  gateEvaluation,
  parseArgs,
  renderMarkdown,
  runReport,
  runIdFromOut,
  MIN_COMPARED,
} = require('./catalogue_shadow_report.js');

const cell = (total, covered, compared, agreed, disagree_sample = []) => ({ total, covered, compared, agreed, disagree_sample });
const tiers = (c) => ({ top1k: c, top5k: c, in_lists: c, curated: c, all: c });

function report(overrides = {}) {
  const big = cell(100, 100, 100, 100);
  return {
    medium: 'anime',
    generated_at: '2026-11-18T12:00:00Z',
    sample: 20,
    tiers: { top1k: 100, top5k: 100, in_lists: 100, curated: 100, all: 100 },
    groups: {
      identity: tiers(cell(100, 100, 0, 0)),
      titles: tiers(big),
      titles_native: tiers(cell(100, 100, 0, 0)),
      facts_start_year: tiers(big),
      facts_format: tiers(big),
      facts_status: tiers(big),
      facts_episodes: tiers(big),
      adult: tiers(big),
    },
    identity_gate: { accepted_links: 100, proposed_links: 0, duplicate_accepted_links: 0, proposed_only_titles: 0 },
    adult: { review_size: 0, becomes_non_adult: 0, newly_adult: 0 },
    ...overrides,
  };
}

const find = (ev, group, metric, tier) => ev.gates.find((g) => g.group === group && g.metric === metric && (tier === undefined || g.tier === tier));

test('gateEvaluation passes every measured gate on a clean large report', () => {
  const ev = gateEvaluation(report());
  // identity also holds the owner-sample precision gate, which this report cannot decide.
  assert.equal(ev.summary.identity, 'insufficient');
  assert.deepEqual(ev.gates.filter((g) => g.group === 'identity' && g.metric !== 'title_match_precision').map((g) => g.status), ['pass', 'pass', 'pass', 'pass']);
  assert.equal(ev.summary.facts, 'pass');
  assert.equal(ev.summary.adult, 'pass');
  assert.equal(ev.summary.titles, 'pass');
});

test('fewer than 30 compared rows is insufficient, never pass', () => {
  const small = cell(10, 10, MIN_COMPARED - 1, MIN_COMPARED - 1);
  const r = report();
  r.groups.facts_start_year = tiers(small);
  const ev = gateEvaluation(r);
  const g = find(ev, 'facts', 'start_year_exact', 'all');
  assert.equal(g.status, 'insufficient');
  assert.equal(ev.summary.facts === 'pass', false);
  // exactly 30 is enough
  r.groups.facts_start_year = tiers(cell(30, 30, 30, 30));
  assert.equal(find(gateEvaluation(r), 'facts', 'start_year_exact', 'all').status, 'pass');
});

test('facts thresholds: 98% year, 97% format, 97% episodes', () => {
  const r = report();
  r.groups.facts_start_year = tiers(cell(100, 100, 100, 97)); // 97% < 98%
  r.groups.facts_format = tiers(cell(100, 100, 100, 97)); // 97% >= 97%
  r.groups.facts_episodes = tiers(cell(100, 100, 100, 96)); // 96% < 97%
  const ev = gateEvaluation(r);
  assert.equal(find(ev, 'facts', 'start_year_exact', 'all').status, 'fail');
  assert.equal(find(ev, 'facts', 'format_mapped', 'all').status, 'pass');
  assert.equal(find(ev, 'facts', 'episodes_finished', 'all').status, 'fail');
  assert.equal(ev.summary.facts, 'fail');
});

test('identity: 100% of in_lists and curated, 95% anime / 85% manga top5k, zero duplicates', () => {
  const r = report();
  r.groups.identity = {
    top1k: cell(100, 100, 0, 0), top5k: cell(100, 90, 0, 0),
    in_lists: cell(100, 99, 0, 0), curated: cell(100, 100, 0, 0), all: cell(100, 100, 0, 0),
  };
  let ev = gateEvaluation(r);
  assert.equal(find(ev, 'identity', 'linked_share', 'in_lists').status, 'fail');
  assert.equal(find(ev, 'identity', 'linked_share', 'curated').status, 'pass');
  assert.equal(find(ev, 'identity', 'linked_share', 'top5k').status, 'fail', 'anime needs 95%');
  r.medium = 'manga';
  ev = gateEvaluation(r);
  assert.equal(find(ev, 'identity', 'linked_share', 'top5k').status, 'pass', 'manga needs 85%');
  r.identity_gate.duplicate_accepted_links = 1;
  assert.equal(find(gateEvaluation(r), 'identity', 'duplicate_accepted_links').status, 'fail');
});

test('identity match precision needs the owner sample and is never pass here', () => {
  const g = find(gateEvaluation(report()), 'identity', 'title_match_precision');
  assert.equal(g.status, 'insufficient');
});

test('adult: any title that would become non-adult fails, even on a tiny sample', () => {
  const r = report();
  r.groups.adult = tiers(cell(5, 3, 3, 2));
  r.adult.becomes_non_adult = 1;
  const g = find(gateEvaluation(r), 'adult', 'becomes_non_adult');
  assert.equal(g.status, 'fail');
  r.adult.becomes_non_adult = 0;
  assert.equal(find(gateEvaluation(r), 'adult', 'becomes_non_adult').status, 'insufficient', 'zero of 3 compared is not enough evidence');
});

test('titles: display title on every linked title, native title 95% of top5k', () => {
  const r = report();
  r.groups.titles = tiers(cell(100, 98, 100, 100)); // 98 of 100 linked have a title
  r.groups.titles_native = tiers(cell(100, 94, 0, 0));
  const ev = gateEvaluation(r);
  assert.equal(find(ev, 'titles', 'display_title_of_linked').status, 'fail');
  assert.equal(find(ev, 'titles', 'native_title', 'top5k').status, 'fail');
});

test('gates the shadow report does not measure stay insufficient', () => {
  const ev = gateEvaluation(report());
  for (const group of ['relations', 'popularity', 'tags', 'episodes', 'synopsis', 'images']) {
    assert.equal(ev.summary[group], 'insufficient', group);
  }
});

test('an empty report (no titles) evaluates to insufficient, not pass or a crash', () => {
  const empty = cell(0, 0, 0, 0);
  const r = report();
  for (const k of Object.keys(r.groups)) r.groups[k] = tiers(empty);
  const ev = gateEvaluation(r);
  assert.notEqual(ev.summary.identity, 'pass');
  assert.notEqual(ev.summary.facts, 'pass');
});

test('parseArgs requires a medium and a known value', () => {
  assert.deepEqual(parseArgs(['--medium', 'anime', '--out', 'x.json']).medium, 'anime');
  assert.throws(() => parseArgs(['--out', 'x.json']), /--medium/);
  assert.throws(() => parseArgs(['--medium', 'novel']), /anime or manga/);
  assert.equal(parseArgs(['--medium', 'manga', '--sample', '5']).sample, 5);
  assert.throws(() => parseArgs(['--medium', 'anime', '--bogus']), /unknown argument/);
});

test('runIdFromOut takes the file name without extension', () => {
  assert.equal(runIdFromOut('docs/catalogue-sources-2026-11/runs/2026-11-18-anime.json'), '2026-11-18-anime');
});

function memoryFs() {
  const files = new Map();
  return {
    files,
    exists: (p) => files.has(p),
    mkdir: () => {},
    writeFile: (p, content) => files.set(p, content),
  };
}

test('runReport calls the injected rpc with medium and sample and writes json plus markdown', async () => {
  const calls = [];
  const fs = memoryFs();
  const out = path.join('runs', '2026-11-18-anime.json');
  const result = await runReport({
    medium: 'anime', sample: 7, out,
    callRpc: async (name, args) => { calls.push([name, args]); return { data: report(), error: null }; },
    fs, now: () => new Date('2026-11-18T12:30:00Z'),
  });
  assert.deepEqual(calls, [['catalogue_shadow_report_v1', { p_medium: 'anime', p_sample: 7 }]]);
  const json = JSON.parse(fs.files.get(out));
  assert.equal(json.run_id, '2026-11-18-anime');
  assert.equal(json.medium, 'anime');
  assert.equal(json.evaluation.summary.facts, 'pass');
  const md = fs.files.get(path.join('runs', '2026-11-18-anime.md'));
  assert.match(md, /# Catalogue shadow report 2026-11-18-anime/);
  assert.match(md, /\| facts \| pass \|/);
  assert.equal(result.outPath, out);
});

test('runReport refuses to overwrite an earlier run', async () => {
  const fs = memoryFs();
  const out = 'runs/2026-11-18-anime.json';
  fs.files.set(out, '{}');
  await assert.rejects(
    runReport({ medium: 'anime', out, callRpc: async () => ({ data: report(), error: null }), fs, now: () => new Date() }),
    /already exists/,
  );
});

test('runReport surfaces an rpc error and writes nothing', async () => {
  const fs = memoryFs();
  await assert.rejects(
    runReport({ medium: 'anime', out: 'runs/x.json', callRpc: async () => ({ data: null, error: { message: 'permission denied for function' } }), fs, now: () => new Date() }),
    /permission denied/,
  );
  assert.equal(fs.files.size, 0);
});

test('renderMarkdown lists disagreement samples and never prints a secret-looking env', () => {
  const r = report();
  r.groups.facts_start_year.all = cell(100, 100, 100, 99, [{ id: 7, today: 2002, shadow: 2003 }]);
  const md = renderMarkdown({ run_id: 'r', medium: 'anime', generated_at: 'g', report: r, evaluation: gateEvaluation(r) });
  assert.match(md, /facts_start_year/);
  assert.match(md, /\b7\b.*2002.*2003/);
});
