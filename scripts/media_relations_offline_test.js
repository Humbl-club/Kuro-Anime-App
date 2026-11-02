#!/usr/bin/env node
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const Module = require('module');
const { spawnSync } = require('child_process');

const workerPath = path.join(__dirname, 'media_relations_worker.js');
const tests = [];

function test(name, fn) {
  tests.push({ name, fn });
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message || 'assertion failed');
  }
}

function eqFilter(query, column) {
  const found = query.filters.find(entry => entry.op === 'eq' && entry.column === column);
  return found ? found.value : undefined;
}

function createFakeSupabase(seed) {
  const state = {
    queue: seed.queue.map(row => ({ ...row })),
    media: seed.media.map(row => ({ ...row })),
    upserts: [],
    deletes: [],
    updates: [],
  };

  function execute(query) {
    if (query.table === 'media_relation_refresh_queue' && query.op === 'select') {
      const statuses = query.filters.find(entry => entry.op === 'in' && entry.column === 'status');
      const allowed = statuses ? statuses.value : ['pending', 'error'];
      return {
        data: state.queue.filter(row => allowed.includes(row.status)).map(row => ({ ...row })),
        error: null,
      };
    }
    if (query.table === 'media_relation_refresh_queue' && query.op === 'update') {
      const mediaType = eqFilter(query, 'media_type');
      const mediaId = eqFilter(query, 'media_id');
      const row = state.queue.find(item => item.media_type === mediaType && item.media_id === mediaId);
      if (!row) return { error: { message: `missing queue row ${mediaType}:${mediaId}` } };
      Object.assign(row, query.patch);
      state.updates.push({
        media_type: mediaType,
        media_id: mediaId,
        patch: { ...query.patch },
      });
      return { error: null };
    }
    if ((query.table === 'anime' || query.table === 'manga') && query.op === 'select' && query.single) {
      const id = eqFilter(query, 'id');
      const anilistId = eqFilter(query, 'anilist_id');
      const row = state.media.find(item => {
        if (item.table !== query.table) return false;
        if (id !== undefined) return item.id === id;
        if (anilistId !== undefined) return item.anilist_id === anilistId;
        return false;
      });
      return { data: row ? { ...row } : null, error: null };
    }
    if ((query.table === 'anime' || query.table === 'manga') && query.op === 'select') {
      return { data: [], error: null };
    }
    if (query.table === 'media_relations' && query.op === 'delete') {
      state.deletes.push({ filters: query.filters.map(entry => ({ ...entry })) });
      return { error: null };
    }
    if (query.table === 'media_relations' && query.op === 'upsert') {
      state.upserts.push({
        rows: query.rows.map(row => ({ ...row })),
        onConflict: query.upsertOpts && query.upsertOpts.onConflict,
      });
      return { error: null };
    }
    if (query.table === 'media_relations' && query.selectOpts && query.selectOpts.head) {
      return { count: 0, error: null };
    }
    if (query.table === 'media_relations' && query.op === 'select') {
      return { data: [], error: null };
    }
    return { data: null, error: { message: `unexpected ${query.op} on ${query.table}` } };
  }

  function builder(table) {
    const query = {
      table,
      op: 'select',
      filters: [],
      single: false,
      selectOpts: null,
      patch: null,
      rows: null,
      upsertOpts: null,
    };
    const api = {
      select(_columns, options) {
        query.selectOpts = options || null;
        return api;
      },
      update(patch) {
        query.op = 'update';
        query.patch = patch;
        return api;
      },
      delete() {
        query.op = 'delete';
        return api;
      },
      upsert(rows, options) {
        query.op = 'upsert';
        query.rows = rows;
        query.upsertOpts = options || null;
        return api;
      },
      eq(column, value) {
        query.filters.push({ op: 'eq', column, value });
        return api;
      },
      in(column, value) {
        query.filters.push({ op: 'in', column, value });
        return api;
      },
      order() { return api; },
      limit() { return api; },
      range() { return api; },
      maybeSingle() {
        query.single = true;
        return api;
      },
      then(onFulfilled, onRejected) {
        return Promise.resolve().then(() => execute(query)).then(onFulfilled, onRejected);
      },
    };
    return api;
  }

  return {
    state,
    supabase: {
      from(table) { return builder(table); },
      rpc() {
        return Promise.resolve({ data: {}, error: null });
      },
    },
  };
}

function queueSeed() {
  return {
    queue: [{
      media_type: 'ANIME',
      media_id: 10,
      reason: 'queued',
      retry_count: 0,
      status: 'pending',
    }],
    media: [
      {
        table: 'anime',
        id: 10,
        anilist_id: 999,
        title_english: 'Offline Title',
        title_romaji: 'Offline Title',
        popularity: 50,
      },
      {
        table: 'manga',
        id: 42,
        anilist_id: 888,
        title_english: 'Offline Manga',
        title_romaji: 'Offline Manga',
        popularity: 40,
      },
    ],
  };
}

async function quietly(fn) {
  const original = console.log;
  console.log = () => {};
  try {
    return await fn();
  } finally {
    console.log = original;
  }
}

function removeDir(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
}

let worker;

test('module load does not throw, create a client, or write reports', () => {
  const sentinel = path.join(os.tmpdir(), `kuro-mr-load-${process.pid}-${Date.now()}`);
  const repoReport = path.join(__dirname, '..', 'reports', 'media-relations', 'latest-run.json');
  const before = fs.existsSync(repoReport) ? fs.statSync(repoReport).mtimeMs : null;
  process.env.MEDIA_RELATIONS_REPORTS_DIR = sentinel;
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;

  const originalRequire = Module.prototype.require;
  let createClientCalls = 0;
  Module.prototype.require = function patchedRequire(id) {
    const exported = originalRequire.apply(this, arguments);
    if (id === '@supabase/supabase-js' && exported && typeof exported.createClient === 'function') {
      if (!exported.__kuroCreateClientWrapped) {
        const originalCreate = exported.createClient;
        exported.createClient = function wrappedCreateClient() {
          createClientCalls += 1;
          return originalCreate.apply(this, arguments);
        };
        exported.__kuroCreateClientWrapped = true;
      }
    }
    return exported;
  };

  try {
    worker = require('./media_relations_worker.js');
    assert(typeof worker.runMediaRelations === 'function', 'runMediaRelations was not exported');
    assert(createClientCalls === 0, `createClient calls during require: ${createClientCalls}`);
    assert(!fs.existsSync(sentinel), 'require created the report directory');
    const after = fs.existsSync(repoReport) ? fs.statSync(repoReport).mtimeMs : null;
    assert(before === after, 'require wrote reports/media-relations/latest-run.json');
  } finally {
    Module.prototype.require = originalRequire;
    removeDir(sentinel);
    delete process.env.MEDIA_RELATIONS_REPORTS_DIR;
  }
});

test('project root uses KURO_PROJECT_ROOT when it is set', () => {
  const root = worker.resolveProjectRoot({
    env: { KURO_PROJECT_ROOT: '/custom/kuro-root' },
    gitRoot: () => '/git/root',
    existsSync: () => true,
  });
  assert(root === '/custom/kuro-root', `got ${root}`);
});

test('project root uses git rev-parse when the override is unset', () => {
  const expected = fs.realpathSync(path.resolve(__dirname, '..'));
  const root = worker.resolveProjectRoot({ env: {} });
  assert(root === expected, `git root ${root} !== ${expected}`);
});

test('project root uses /Applications/Kuro only when git is unavailable and that directory exists', () => {
  const missingGit = worker.resolveProjectRoot({
    env: {},
    gitRoot: () => '',
    existsSync: candidate => candidate === '/Applications/Kuro',
  });
  assert(missingGit === '/Applications/Kuro', `got ${missingGit}`);

  const gitThrows = worker.resolveProjectRoot({
    env: {},
    gitRoot: () => { throw new Error('git missing'); },
    existsSync: () => false,
    scriptsDir: path.join('/tmp', 'kuro-scripts'),
  });
  assert(gitThrows === path.resolve('/tmp', 'kuro-scripts', '..'), `got ${gitThrows}`);
});

test('project root falls back to the parent of scripts when git and /Applications/Kuro are unavailable', () => {
  const root = worker.resolveProjectRoot({
    env: {},
    gitRoot: () => '',
    existsSync: () => false,
    scriptsDir: path.join('/tmp', 'kuro-scripts'),
  });
  assert(root === '/tmp', `got ${root}`);
});

test('a successful queue item is marked ok, inserts the relation, and writes reports to the override', async () => {
  const reportDir = fs.mkdtempSync(path.join(os.tmpdir(), 'kuro-mr-ok-'));
  const backstop = fs.mkdtempSync(path.join(os.tmpdir(), 'kuro-mr-ok-env-'));
  const fetchCalls = [];
  process.env.MEDIA_RELATIONS_REPORTS_DIR = backstop;
  const harness = createFakeSupabase(queueSeed());
  try {
    const summary = await quietly(() => worker.runMediaRelations({
      supabase: harness.supabase,
      fetch: async (url) => {
        fetchCalls.push(url);
        return {
          ok: true,
          status: 200,
          json: async () => ({
            data: {
              Media: {
                relations: {
                  edges: [{ relationType: 'ADAPTATION', node: { id: 888, type: 'MANGA' } }],
                },
              },
            },
          }),
          text: async () => '',
        };
      },
      clock: () => new Date('2026-10-05T12:00:00.000Z'),
      sleep: async () => {},
      reportDir,
      projectUrl: 'https://example.test',
      mode: 'queue',
    }));

    assert(fetchCalls.length === 1 && fetchCalls[0] === 'https://graphql.anilist.co', 'injected fetch was not used');
    assert(harness.state.queue[0].status === 'ok', `status ${harness.state.queue[0].status}`);
    assert(harness.state.updates.map(update => update.patch.status).join(',') === 'processing,ok', 'status sequence');
    assert(harness.state.upserts.length === 1, `upserts ${harness.state.upserts.length}`);
    assert(harness.state.upserts[0].rows.length === 1, 'inserted row count');
    const row = harness.state.upserts[0].rows[0];
    assert(row.from_media_type === 'ANIME' && row.from_media_id === 10, 'source identity');
    assert(row.relation_type === 'ADAPTATION' && row.to_media_type === 'MANGA' && row.to_media_id === 42, 'relation target');
    assert(row.source === 'anilist', 'relation source');
    assert(summary.queue.refreshed === 1 && summary.queue.errors === 0, 'queue summary');
    assert(summary.queue.items[0].status === 'ok', 'summary item status');

    for (const name of ['latest-run.json', 'latest-status.json', 'missing-top-catalog.md']) {
      assert(fs.existsSync(path.join(reportDir, name)), `missing ${name} in override dir`);
      assert(!fs.existsSync(path.join(backstop, name)), `${name} was written to MEDIA_RELATIONS_REPORTS_DIR`);
    }
    const run = JSON.parse(fs.readFileSync(path.join(reportDir, 'latest-run.json'), 'utf8'));
    const status = JSON.parse(fs.readFileSync(path.join(reportDir, 'latest-status.json'), 'utf8'));
    const markdown = fs.readFileSync(path.join(reportDir, 'missing-top-catalog.md'), 'utf8');
    assert(run.mode === 'queue' && run.queue.refreshed === 1, 'latest-run.json');
    assert(status.generated_at === '2026-10-05T12:00:00.000Z', 'clock was not used for latest-status.json');
    assert(status.project_url === 'https://example.test', 'project url');
    assert(markdown.startsWith('# Media Relations Coverage\n'), 'coverage markdown');
  } finally {
    delete process.env.MEDIA_RELATIONS_REPORTS_DIR;
    removeDir(reportDir);
    removeDir(backstop);
  }
});

test('a provider failure marks the queue item error and does not insert relations', async () => {
  const reportDir = fs.mkdtempSync(path.join(os.tmpdir(), 'kuro-mr-err-'));
  const backstop = fs.mkdtempSync(path.join(os.tmpdir(), 'kuro-mr-err-env-'));
  let fetchCalls = 0;
  process.env.MEDIA_RELATIONS_REPORTS_DIR = backstop;
  const harness = createFakeSupabase(queueSeed());
  try {
    const summary = await quietly(() => worker.runMediaRelations({
      supabase: harness.supabase,
      fetch: async () => {
        fetchCalls += 1;
        throw new Error('anilist down');
      },
      clock: () => new Date('2026-10-05T12:00:00.000Z'),
      sleep: async () => {},
      reportDir,
      projectUrl: 'https://example.test',
      mode: 'queue',
    }));

    assert(fetchCalls >= 1, 'provider was not called');
    assert(harness.state.queue[0].status === 'error', `status ${harness.state.queue[0].status}`);
    assert(harness.state.queue[0].last_error === 'anilist down', `last_error ${harness.state.queue[0].last_error}`);
    assert(!harness.state.updates.some(update => update.patch.status === 'ok'), 'item was marked ok');
    assert(harness.state.upserts.length === 0, `upserts ${harness.state.upserts.length}`);
    assert(harness.state.deletes.length === 0, `deletes ${harness.state.deletes.length}`);
    assert(summary.queue.errors === 1 && summary.queue.refreshed === 0, 'queue summary');
    assert(summary.queue.items[0].status === 'error', 'summary item status');
    assert(fs.existsSync(path.join(reportDir, 'latest-run.json')), 'latest-run.json missing from override');
    assert(fs.existsSync(path.join(reportDir, 'latest-status.json')), 'latest-status.json missing from override');
    assert(fs.existsSync(path.join(reportDir, 'missing-top-catalog.md')), 'missing-top-catalog.md missing from override');
    assert(fs.readdirSync(backstop).length === 0, 'reports were written outside the override');
  } finally {
    delete process.env.MEDIA_RELATIONS_REPORTS_DIR;
    removeDir(reportDir);
    removeDir(backstop);
  }
});

test('production launch without SUPABASE_SERVICE_ROLE_KEY fails before writing reports', () => {
  const sentinel = path.join(os.tmpdir(), `kuro-mr-missing-key-${process.pid}-${Date.now()}`);
  const env = { ...process.env };
  delete env.SUPABASE_SERVICE_ROLE_KEY;
  delete env.SUPABASE_URL;
  env.MEDIA_RELATIONS_REPORTS_DIR = sentinel;
  const result = spawnSync(process.execPath, [workerPath], {
    env,
    encoding: 'utf8',
    timeout: 20000,
  });
  try {
    const output = `${result.stdout || ''}\n${result.stderr || ''}`;
    assert(result.status !== 0, `expected non-zero exit, got ${result.status}`);
    assert(output.includes('Missing SUPABASE_SERVICE_ROLE_KEY env var.'), 'missing-key error was not reported');
    assert(!fs.existsSync(sentinel), 'production launch wrote a report directory without the service role key');
  } finally {
    removeDir(sentinel);
  }
});

async function main() {
  global.fetch = async () => {
    throw new Error('global fetch must not be called');
  };
  let passed = 0;
  let failed = 0;
  for (const entry of tests) {
    try {
      await entry.fn();
      passed += 1;
      console.log(`ok ${entry.name}`);
    } catch (error) {
      failed += 1;
      console.error(`not ok ${entry.name}`);
      console.error(error && error.stack ? error.stack : error);
    }
  }
  console.log(`${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main();
