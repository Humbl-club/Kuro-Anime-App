#!/usr/bin/env node

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const REPORT_DIR = process.env.SYNOPSIS_REPORTS_DIR || '/Applications/Kuro/reports/synopsis-enrichment';
const PORT = Number(process.env.SYNOPSIS_DASHBOARD_PORT || 8787);
const LABEL = process.env.SYNOPSIS_LAUNCHD_LABEL || 'com.kuro.synopsis-enrichment';

function readJsonSafe(filePath, fallback = null) {
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

function readTextSafe(filePath, fallback = '') {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return fallback;
  }
}

function fileMtimeIso(filePath) {
  try {
    return fs.statSync(filePath).mtime.toISOString();
  } catch {
    return null;
  }
}

function parseRunLogLine(line) {
  const out = {};
  for (const token of line.trim().split(/\s+/)) {
    const idx = token.indexOf('=');
    if (idx <= 0) continue;
    const key = token.slice(0, idx);
    const valueRaw = token.slice(idx + 1);
    const num = Number(valueRaw);
    out[key] = Number.isFinite(num) ? num : valueRaw;
  }
  return out;
}

function parseStartedAtFromRunName(name) {
  const m = name.match(/^run-(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})Z\.log$/);
  if (!m) return null;
  return `${m[1]}T${m[2]}:${m[3]}:${m[4]}Z`;
}

function listRunEntries(limit = null) {
  let files = [];
  try {
    files = fs.readdirSync(REPORT_DIR)
      .filter((name) => /^run-.*\.log$/.test(name))
      .sort();
  } catch {
    return [];
  }

  const selected = limit == null ? files : files.slice(-Math.max(1, limit));
  return selected.map((name) => {
    const fullPath = path.join(REPORT_DIR, name);
    const content = readTextSafe(fullPath, '').trim();
    const parsed = parseRunLogLine(content);
    const startedAt = parseStartedAtFromRunName(name);
    return {
      file: name,
      started_at_guess: startedAt,
      ...parsed,
    };
  });
}

function listHistory() {
  return listRunEntries(50);
}

function summarizeRuns(entries) {
  const now = Date.now();
  const dayAgo = now - (24 * 60 * 60 * 1000);
  const base = {
    run_count_total: 0,
    processed_total: 0,
    generated_total: 0,
    tone_polish_used_total: 0,
    fallback_used_total: 0,
    autodeduped_sentences_total: 0,
    rejected_total: 0,
    weak_source_total: 0,
    failed_total: 0,
    run_count_24h: 0,
    processed_24h: 0,
    generated_24h: 0,
    tone_polish_used_24h: 0,
    fallback_used_24h: 0,
    autodeduped_sentences_24h: 0,
    rejected_24h: 0,
    weak_source_24h: 0,
    failed_24h: 0,
  };

  for (const run of entries) {
    const processed = Number(run.processed) || 0;
    const generated = Number(run.generated) || 0;
    const polished = Number(run.tone_polish_used) || 0;
    const fallback = Number(run.fallback_used) || 0;
    const autodeduped = Number(run.autodeduped_sentences) || 0;
    const rejected = Number(run.rejected_quality) || 0;
    const weak = Number(run.insufficient_source) || 0;
    const failed = Number(run.failed) || 0;
    base.run_count_total += 1;
    base.processed_total += processed;
    base.generated_total += generated;
    base.tone_polish_used_total += polished;
    base.fallback_used_total += fallback;
    base.autodeduped_sentences_total += autodeduped;
    base.rejected_total += rejected;
    base.weak_source_total += weak;
    base.failed_total += failed;

    const startedAtMs = run.started_at_guess ? Date.parse(run.started_at_guess) : NaN;
    if (Number.isFinite(startedAtMs) && startedAtMs >= dayAgo) {
      base.run_count_24h += 1;
      base.processed_24h += processed;
      base.generated_24h += generated;
      base.tone_polish_used_24h += polished;
      base.fallback_used_24h += fallback;
      base.autodeduped_sentences_24h += autodeduped;
      base.rejected_24h += rejected;
      base.weak_source_24h += weak;
      base.failed_24h += failed;
    }
  }
  return base;
}

function getWorkerLogTail(lines = 120) {
  const logPath = path.join(REPORT_DIR, 'worker.log');
  const text = readTextSafe(logPath, '');
  if (!text) return '';
  const arr = text.split('\n');
  return arr.slice(-lines).join('\n');
}

function getLaunchdState() {
  const target = `gui/${process.getuid()}/${LABEL}`;
  try {
    const text = execSync(`launchctl print ${target}`, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    const pick = (regex) => {
      const m = text.match(regex);
      return m ? m[1] : null;
    };
    return {
      label: LABEL,
      state: pick(/\bstate = ([^\n]+)/),
      pid: pick(/\bpid = ([^\n]+)/),
      runs: pick(/\bruns = ([^\n]+)/),
      last_exit_code: pick(/\blast exit code = ([^\n]+)/),
    };
  } catch {
    return {
      label: LABEL,
      state: 'unknown',
      pid: null,
      runs: null,
      last_exit_code: null,
    };
  }
}

function json(res, payload, status = 200) {
  const body = JSON.stringify(payload, null, 2);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function html(res, body, status = 200) {
  res.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function appHtml() {
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Synopsis Enrichment Dashboard</title>
  <style>
    :root { --bg:#0b0e13; --card:#141922; --muted:#97a4b8; --text:#eaf0fa; --ok:#2ecc71; --warn:#f5b942; --bad:#ff6b6b; --line:#273040; }
    body { margin:0; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, monospace; background:var(--bg); color:var(--text); }
    .wrap { max-width: 1200px; margin: 0 auto; padding: 20px; }
    h1 { font-size: 20px; margin: 0 0 14px 0; }
    .muted { color: var(--muted); }
    .grid { display:grid; grid-template-columns: repeat(4, minmax(160px,1fr)); gap: 10px; }
    .card { background: var(--card); border:1px solid var(--line); border-radius:12px; padding: 10px 12px; }
    .k { font-size: 11px; color: var(--muted); margin-bottom: 4px; }
    .v { font-size: 22px; font-weight: 700; }
    .ok { color: var(--ok); } .warn{ color: var(--warn);} .bad{ color: var(--bad);}    
    .row { display:grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 10px; }
    pre { margin:0; white-space: pre-wrap; word-break: break-word; font-size: 12px; line-height: 1.35; max-height: 380px; overflow:auto; }
    table { width:100%; border-collapse: collapse; font-size: 12px; }
    th, td { border-bottom:1px solid var(--line); padding: 6px; text-align:left; }
    th { color: var(--muted); font-weight: 600; }
    .footer { margin-top: 10px; font-size: 12px; color: var(--muted); }
    @media (max-width: 900px) { .grid { grid-template-columns: repeat(2,minmax(120px,1fr)); } .row { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>Synopsis Enrichment Dashboard <span class="muted" id="stamp"></span></h1>
    <div class="grid" id="cards"></div>
    <div class="row">
      <div class="card">
        <div class="k">Run History (last 50)</div>
        <div style="overflow:auto; max-height:380px;">
          <table>
            <thead><tr><th>Run</th><th>Processed</th><th>Generated</th><th>Tone polish</th><th>Fallback</th><th>Auto dedupe</th><th>Rejected</th><th>Weak src</th><th>Failed</th></tr></thead>
            <tbody id="history"></tbody>
          </table>
        </div>
      </div>
      <div class="card">
        <div class="k">Generated Synopsis Samples (latest)</div>
        <pre id="generated"></pre>
      </div>
    </div>
    <div class="row">
      <div class="card">
        <div class="k">Weak Sources (latest)</div>
        <pre id="weak"></pre>
      </div>
      <div class="card">
        <div class="k">Worker Log Tail</div>
        <pre id="log"></pre>
      </div>
    </div>
    <div class="row">
      <div class="card">
        <div class="k">Launchd State</div>
        <pre id="launchd"></pre>
      </div>
    </div>
    <div class="footer">Auto-refresh every 5s · endpoint: /api/status</div>
  </div>
  <script>
    async function j(url){ const r = await fetch(url, { cache:'no-store' }); return r.json(); }
    async function t(url){ const r = await fetch(url, { cache:'no-store' }); return r.text(); }

    function num(v){ return (v ?? 0).toLocaleString(); }

    async function refresh(){
      try {
        const [status, history, generated, weak, logs, launchd] = await Promise.all([
          j('/api/status'),
          j('/api/history'),
          t('/api/generated-samples'),
          t('/api/weak'),
          j('/api/logs?lines=120'),
          j('/api/launchd')
        ]);

        const generatedRate = status.processed > 0 ? ((status.generated / status.processed) * 100).toFixed(1) : '0.0';
        const totalGeneratedRate = status.processed_total > 0 ? ((status.generated_total / status.processed_total) * 100).toFixed(1) : '0.0';
        const cards = [
          ['Processed', num(status.processed), ''],
          ['Generated', num(status.generated), 'ok'],
          ['Tone polish (run)', num(status.tone_polish_used ?? 0), ''],
          ['Fallback used (run)', num(status.fallback_used ?? 0), ''],
          ['Auto-deduped (run)', num(status.autodeduped_sentences ?? 0), ''],
          ['Rejected quality', num(status.rejected_quality), status.rejected_quality > 0 ? 'warn' : ''],
          ['Weak source', num(status.insufficient_source), status.insufficient_source > 0 ? 'warn' : ''],
          ['Failed', num(status.failed), status.failed > 0 ? 'bad' : 'ok'],
          ['Avg latency ms', num(status.avg_latency_ms), ''],
          ['Backlog due (before)', num(status.backlog_due_before ?? 0), ''],
          ['Backlog due (after)', num(status.backlog_due_after ?? status.backlog_remaining_estimate), ''],
          ['Generated % (run)', generatedRate + '%', generatedRate < 30 ? 'warn' : 'ok'],
          ['Processed total', num(status.processed_total ?? 0), ''],
          ['Generated total', num(status.generated_total ?? 0), 'ok'],
          ['Tone polish total', num(status.tone_polish_used_total ?? 0), ''],
          ['Fallback used total', num(status.fallback_used_total ?? 0), ''],
          ['Auto-deduped total', num(status.autodeduped_sentences_total ?? 0), ''],
          ['Runs total', num(status.run_count_total ?? 0), ''],
          ['Processed (24h)', num(status.processed_24h ?? 0), ''],
          ['Generated (24h)', num(status.generated_24h ?? 0), 'ok'],
          ['Generated % (total)', totalGeneratedRate + '%', totalGeneratedRate < 30 ? 'warn' : 'ok']
        ];

        document.getElementById('cards').innerHTML = cards.map(([k,v,c]) =>
          '<div class=\"card\"><div class=\"k\">' + k + '</div><div class=\"v ' + c + '\">' + v + '</div></div>'
        ).join('');

        document.getElementById('history').innerHTML = history.map(h =>
          '<tr>' +
            '<td>' + h.file + '</td>' +
            '<td>' + num(h.processed) + '</td>' +
            '<td>' + num(h.generated) + '</td>' +
            '<td>' + num(h.tone_polish_used) + '</td>' +
            '<td>' + num(h.fallback_used) + '</td>' +
            '<td>' + num(h.autodeduped_sentences) + '</td>' +
            '<td>' + num(h.rejected_quality) + '</td>' +
            '<td>' + num(h.insufficient_source) + '</td>' +
            '<td>' + num(h.failed) + '</td>' +
          '</tr>'
        ).join('');

        document.getElementById('generated').textContent = generated || 'No generated sample report yet.';
        document.getElementById('weak').textContent = weak || 'No weak source report yet.';
        document.getElementById('log').textContent = logs.tail || '';
        document.getElementById('launchd').textContent = JSON.stringify(launchd, null, 2);
        document.getElementById('stamp').textContent = '(updated ' + new Date().toLocaleTimeString() + ')';
      } catch (err) {
        document.getElementById('stamp').textContent = '(refresh failed: ' + err.message + ')';
      }
    }

    refresh();
    setInterval(refresh, 5000);
  </script>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (url.pathname === '/api/status') {
    const statusPath = path.join(REPORT_DIR, 'latest-status.json');
    const runs = listRunEntries();
    const summary = summarizeRuns(runs);
    const payload = readJsonSafe(statusPath, {
      processed: 0,
      generated: 0,
      tone_polish_used: 0,
      fallback_used: 0,
      autodeduped_sentences: 0,
      rejected_quality: 0,
      insufficient_source: 0,
      failed: 0,
      avg_latency_ms: 0,
      backlog_due_before: 0,
      backlog_due_after: 0,
      backlog_remaining_estimate: 0,
    });
    const latestRun = runs.length > 0 ? runs[runs.length - 1] : null;
    const latestRunPath = latestRun ? path.join(REPORT_DIR, latestRun.file) : null;
    const fallbackUpdatedAt =
      (latestRun && latestRun.started_at_guess) ||
      (latestRunPath && fileMtimeIso(latestRunPath)) ||
      fileMtimeIso(statusPath) ||
      new Date().toISOString();
    const parsedUpdatedAt = Date.parse(payload.updated_at || '');
    if (!Number.isFinite(parsedUpdatedAt)) {
      payload.updated_at = fallbackUpdatedAt;
    }
    Object.assign(payload, summary);
    return json(res, payload);
  }

  if (url.pathname === '/api/history') {
    return json(res, listHistory());
  }

  if (url.pathname === '/api/summary') {
    return json(res, summarizeRuns(listRunEntries()));
  }

  if (url.pathname === '/api/weak') {
    const weakPath = path.join(REPORT_DIR, 'weak-sources-latest.md');
    const weak = readTextSafe(weakPath, 'No weak source report yet.');
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
    return res.end(weak);
  }

  if (url.pathname === '/api/generated-samples') {
    const generatedPath = path.join(REPORT_DIR, 'generated-samples-latest.md');
    const generated = readTextSafe(generatedPath, 'No generated sample report yet.');
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
    return res.end(generated);
  }

  if (url.pathname === '/api/logs') {
    const lines = Math.max(20, Math.min(500, Number(url.searchParams.get('lines') || 120)));
    return json(res, { tail: getWorkerLogTail(lines) });
  }

  if (url.pathname === '/api/launchd') {
    return json(res, getLaunchdState());
  }

  if (url.pathname === '/' || url.pathname === '/index.html') {
    return html(res, appHtml());
  }

  return json(res, { error: 'Not found' }, 404);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Synopsis dashboard running at http://127.0.0.1:${PORT}`);
  console.log(`Using report dir: ${REPORT_DIR}`);
});
