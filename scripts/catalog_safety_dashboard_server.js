#!/usr/bin/env node

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const REPORT_DIR = process.env.CATALOG_SAFETY_REPORTS_DIR || '/Applications/Kuro/reports/catalog-safety';
const PORT = Number(process.env.CATALOG_SAFETY_DASHBOARD_PORT || 8788);
const LABEL = process.env.CATALOG_SAFETY_LAUNCHD_LABEL || 'com.kuro.catalog-safety';

function readJsonSafe(filePath, fallback = null) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
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

function parseRunLogLine(line) {
  const output = {};
  for (const token of line.trim().split(/\s+/)) {
    const idx = token.indexOf('=');
    if (idx <= 0) continue;
    const key = token.slice(0, idx);
    const raw = token.slice(idx + 1);
    const num = Number(raw);
    output[key] = Number.isFinite(num) ? num : raw;
  }
  return output;
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
    const parsed = parseRunLogLine(readTextSafe(path.join(REPORT_DIR, name), ''));
    return {
      file: name,
      started_at_guess: parseStartedAtFromRunName(name),
      ...parsed,
    };
  });
}

function summarizeRuns(entries) {
  const now = Date.now();
  const dayAgo = now - (24 * 60 * 60 * 1000);
  const summary = {
    run_count_total: 0,
    processed_total: 0,
    blocked_total: 0,
    safe_total: 0,
    uncertain_total: 0,
    failed_total: 0,
    blocked_by_rules_total: 0,
    blocked_by_model_total: 0,
    run_count_24h: 0,
    processed_24h: 0,
    blocked_24h: 0,
    safe_24h: 0,
    uncertain_24h: 0,
    failed_24h: 0,
    blocked_by_rules_24h: 0,
    blocked_by_model_24h: 0,
    progress_baseline: 0,
    progress_remaining: 0,
    progress_reduced: 0,
    progress_pct: 0,
    backlog_delta_last_run: 0,
  };

  for (const run of entries) {
    const processed = Number(run.processed) || 0;
    const blocked = Number(run.blocked) || 0;
    const safe = Number(run.safe) || 0;
    const uncertain = Number(run.uncertain) || 0;
    const failed = Number(run.failed) || 0;
    const blockedByRules = Number(run.blocked_by_rules) || 0;
    const blockedByModel = Number(run.blocked_by_model) || 0;

    summary.run_count_total += 1;
    summary.processed_total += processed;
    summary.blocked_total += blocked;
    summary.safe_total += safe;
    summary.uncertain_total += uncertain;
    summary.failed_total += failed;
    summary.blocked_by_rules_total += blockedByRules;
    summary.blocked_by_model_total += blockedByModel;

    const startedAtMs = run.started_at_guess ? Date.parse(run.started_at_guess) : NaN;
    if (Number.isFinite(startedAtMs) && startedAtMs >= dayAgo) {
      summary.run_count_24h += 1;
      summary.processed_24h += processed;
      summary.blocked_24h += blocked;
      summary.safe_24h += safe;
      summary.uncertain_24h += uncertain;
      summary.failed_24h += failed;
      summary.blocked_by_rules_24h += blockedByRules;
      summary.blocked_by_model_24h += blockedByModel;
    }
  }

  const backlogRuns = entries
    .map((run) => {
      const before = Number(run.backlog_due_before);
      const after = Number(run.backlog_due_after);
      if (!Number.isFinite(before) || !Number.isFinite(after) || before <= 0) return null;
      return { before, after };
    })
    .filter(Boolean);

  if (backlogRuns.length > 0) {
    const first = backlogRuns[0];
    const latest = backlogRuns[backlogRuns.length - 1];
    const baseline = first.before;
    const remaining = Math.max(0, latest.after);
    const reduced = Math.max(0, baseline - remaining);
    summary.progress_baseline = baseline;
    summary.progress_remaining = remaining;
    summary.progress_reduced = reduced;
    summary.progress_pct = baseline > 0 ? (reduced / baseline) * 100 : 0;
    summary.backlog_delta_last_run = latest.before - latest.after;
  }

  return summary;
}

function getWorkerLogTail(lines = 120) {
  const text = readTextSafe(path.join(REPORT_DIR, 'worker.log'), '');
  if (!text) return '';
  return text.split('\n').slice(-lines).join('\n');
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
  <title>Catalog Safety Dashboard</title>
  <style>
    :root { --bg:#0b0f14; --card:#141b24; --line:#273548; --muted:#93a4bc; --text:#e9eef7; --ok:#2ecc71; --warn:#f5b942; --bad:#ff6b6b; }
    body { margin:0; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, monospace; background:var(--bg); color:var(--text); }
    .wrap { max-width: 1260px; margin:0 auto; padding:20px; }
    h1 { margin:0 0 14px 0; font-size:22px; }
    .muted { color:var(--muted); }
    .grid { display:grid; grid-template-columns: repeat(4, minmax(160px,1fr)); gap: 10px; }
    .card { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:10px 12px; }
    .k { font-size:11px; color:var(--muted); margin-bottom:4px; }
    .v { font-size:22px; font-weight:700; }
    .ok { color:var(--ok); }
    .warn { color:var(--warn); }
    .bad { color:var(--bad); }
    .row { display:grid; grid-template-columns: 1fr 1fr; gap:10px; margin-top:10px; }
    table { width:100%; border-collapse: collapse; font-size:12px; }
    th, td { border-bottom:1px solid var(--line); padding:6px; text-align:left; }
    th { color:var(--muted); font-weight:600; }
    pre { margin:0; white-space:pre-wrap; word-break:break-word; font-size:12px; line-height:1.35; max-height:420px; overflow:auto; }
    .progress { height:12px; border:1px solid var(--line); border-radius:999px; overflow:hidden; background:#0f1620; }
    .progress > .fill { height:100%; width:0%; background:linear-gradient(90deg,#3ddc97,#2ecc71); transition:width .35s ease; }
    .footer { margin-top:10px; font-size:12px; color:var(--muted); }
    @media (max-width: 900px) { .grid { grid-template-columns: repeat(2, minmax(140px,1fr)); } .row { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>Catalog Safety Dashboard <span class="muted" id="stamp"></span></h1>
    <div class="grid" id="cards"></div>
    <div class="card" style="margin-top:10px;">
      <div class="k">Backlog progress (session)</div>
      <div class="progress"><div class="fill" id="progressFill"></div></div>
      <div id="progressText" class="muted" style="margin-top:6px; font-size:12px;"></div>
    </div>
    <div class="row">
      <div class="card">
        <div class="k">Recent Runs (last 50)</div>
        <div style="overflow:auto; max-height:420px;">
          <table>
            <thead><tr><th>Run</th><th>Scanned</th><th>Blocked</th><th>Safe</th><th>Uncertain</th><th>Failed</th><th>Rules</th><th>Model</th></tr></thead>
            <tbody id="history"></tbody>
          </table>
        </div>
      </div>
      <div class="card">
        <div class="k">Open Source Gaps (uncertain latest)</div>
        <pre id="uncertain"></pre>
      </div>
    </div>
    <div class="row">
      <div class="card">
        <div class="k">Worker Log Tail</div>
        <pre id="log"></pre>
      </div>
      <div class="card">
        <div class="k">Worker / launchd state</div>
        <pre id="launchd"></pre>
      </div>
    </div>
    <div class="footer">Auto-refresh every 5s · report dir: ${REPORT_DIR}</div>
  </div>
  <script>
    async function j(url){ const r = await fetch(url, { cache: 'no-store' }); return r.json(); }
    async function t(url){ const r = await fetch(url, { cache: 'no-store' }); return r.text(); }
    function num(v){ return (v ?? 0).toLocaleString(); }
    function pct(v){ return Number.isFinite(v) ? v.toFixed(1) + '%' : 'n/a'; }

    async function refresh() {
      try {
        const [status, history, uncertain, logs, launchd] = await Promise.all([
          j('/api/status'),
          j('/api/history'),
          t('/api/open-gaps'),
          j('/api/logs?lines=150'),
          j('/api/launchd'),
        ]);

        const cards = [
          ['Scanned (run)', num(status.processed), ''],
          ['Blocked (run)', num(status.blocked), status.blocked > 0 ? 'warn' : ''],
          ['Safe (run)', num(status.safe), 'ok'],
          ['Uncertain (run)', num(status.uncertain), status.uncertain > 0 ? 'warn' : ''],
          ['Failed (run)', num(status.failed), status.failed > 0 ? 'bad' : 'ok'],
          ['Blocked by rules', num(status.blocked_by_rules), ''],
          ['Blocked by model', num(status.blocked_by_model), ''],
          ['Safe fallback (run)', num(status.safe_fallback_no_signal), status.safe_fallback_no_signal > 0 ? 'ok' : ''],
          ['Open gaps', num(status.open_gaps_count), status.open_gaps_count > 0 ? 'warn' : 'ok'],
          ['Progress %', pct(Number(status.progress_pct)), Number(status.progress_pct) >= 80 ? 'ok' : ''],
          ['Backlog reduced', num(status.progress_reduced), ''],
          ['Backlog remaining', num(status.progress_remaining), status.progress_remaining > 0 ? 'warn' : 'ok'],
          ['Last run delta', num(status.backlog_delta_last_run), status.backlog_delta_last_run < 0 ? 'bad' : 'ok'],
          ['Scanned total', num(status.processed_total), ''],
          ['Blocked total', num(status.blocked_total), status.blocked_total > 0 ? 'warn' : ''],
          ['Uncertain total', num(status.uncertain_total), status.uncertain_total > 0 ? 'warn' : ''],
          ['Runs total', num(status.run_count_total), ''],
          ['Scanned (24h)', num(status.processed_24h), ''],
          ['Blocked (24h)', num(status.blocked_24h), status.blocked_24h > 0 ? 'warn' : ''],
          ['Uncertain (24h)', num(status.uncertain_24h), status.uncertain_24h > 0 ? 'warn' : ''],
          ['Avg latency ms', num(status.avg_latency_ms), ''],
          ['Backlog due (before)', num(status.backlog_due_before), ''],
          ['Backlog due (after)', num(status.backlog_due_after), ''],
          ['Model used (run)', num(status.model_used), ''],
          ['Model unavailable (run)', num(status.model_unavailable), status.model_unavailable > 0 ? 'warn' : ''],
        ];

        document.getElementById('cards').innerHTML = cards.map(([k, v, c]) =>
          '<div class="card"><div class="k">' + k + '</div><div class="v ' + c + '">' + v + '</div></div>'
        ).join('');

        const progressPct = Math.max(0, Math.min(100, Number(status.progress_pct) || 0));
        document.getElementById('progressFill').style.width = progressPct + '%';
        document.getElementById('progressText').textContent =
          'Baseline: ' + num(status.progress_baseline) +
          '  |  Remaining: ' + num(status.progress_remaining) +
          '  |  Reduced: ' + num(status.progress_reduced) +
          '  |  Completion: ' + pct(Number(status.progress_pct));

        document.getElementById('history').innerHTML = history.map((h) =>
          '<tr>' +
            '<td>' + h.file + '</td>' +
            '<td>' + num(h.processed) + '</td>' +
            '<td>' + num(h.blocked) + '</td>' +
            '<td>' + num(h.safe) + '</td>' +
            '<td>' + num(h.uncertain) + '</td>' +
            '<td>' + num(h.failed) + '</td>' +
            '<td>' + num(h.blocked_by_rules) + '</td>' +
            '<td>' + num(h.blocked_by_model) + '</td>' +
          '</tr>'
        ).join('');

        document.getElementById('uncertain').textContent = uncertain || 'No uncertain report yet.';
        document.getElementById('log').textContent = logs.tail || '';
        document.getElementById('launchd').textContent = JSON.stringify(launchd, null, 2);
        document.getElementById('stamp').textContent = '(updated ' + new Date().toLocaleTimeString() + ')';
      } catch (error) {
        document.getElementById('stamp').textContent = '(refresh failed: ' + error.message + ')';
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
    const runs = listRunEntries();
    const summary = summarizeRuns(runs);
    const payload = readJsonSafe(path.join(REPORT_DIR, 'latest-status.json'), {
      processed: 0,
      blocked: 0,
      safe: 0,
      uncertain: 0,
      failed: 0,
      blocked_by_rules: 0,
      blocked_by_model: 0,
      safe_fallback_no_signal: 0,
      model_used: 0,
      model_unavailable: 0,
      avg_latency_ms: 0,
      backlog_due_before: 0,
      backlog_due_after: 0,
      open_gaps_count: 0,
      updated_at: new Date().toISOString(),
    });
    Object.assign(payload, summary);
    return json(res, payload);
  }

  if (url.pathname === '/api/history') {
    return json(res, listRunEntries(50));
  }

  if (url.pathname === '/api/open-gaps') {
    const gaps = readTextSafe(path.join(REPORT_DIR, 'uncertain-latest.md'), 'No uncertain report yet.');
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
    return res.end(gaps);
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
  console.log(`Catalog safety dashboard running at http://127.0.0.1:${PORT}`);
  console.log(`Using report dir: ${REPORT_DIR}`);
});
