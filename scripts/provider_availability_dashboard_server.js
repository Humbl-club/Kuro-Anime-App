#!/usr/bin/env node

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const REPORT_DIR = process.env.PROVIDER_AVAILABILITY_REPORTS_DIR || '/Applications/Kuro/reports/provider-availability';
const PORT = Number(process.env.PROVIDER_AVAILABILITY_DASHBOARD_PORT || 8789);
const LABEL = process.env.PROVIDER_AVAILABILITY_LAUNCHD_LABEL || 'com.kuro.provider-availability';

function readJson(filePath, fallback = null) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function readText(filePath, fallback = '') {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return fallback;
  }
}

function parseRunLine(line) {
  const out = {};
  for (const token of line.trim().split(/\s+/)) {
    const idx = token.indexOf('=');
    if (idx < 1) continue;
    const key = token.slice(0, idx);
    const raw = token.slice(idx + 1);
    const num = Number(raw);
    out[key] = Number.isFinite(num) ? num : raw;
  }
  return out;
}

function parseRunTime(name) {
  const m = name.match(/^run-(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})Z\.log$/);
  if (!m) return null;
  return `${m[1]}T${m[2]}:${m[3]}:${m[4]}Z`;
}

function listRuns(limit = 50) {
  let files = [];
  try {
    files = fs.readdirSync(REPORT_DIR)
      .filter((name) => /^run-.*\.log$/.test(name))
      .sort();
  } catch {
    return [];
  }

  return files.slice(-Math.max(1, limit)).map((file) => ({
    file,
    started_at_guess: parseRunTime(file),
    ...parseRunLine(readText(path.join(REPORT_DIR, file), '')),
  }));
}

function summarizeRuns(runs) {
  return runs.reduce((acc, run) => {
    acc.processed += Number(run.processed) || 0;
    acc.mapped_new += Number(run.mapped_new) || 0;
    acc.mapping_unresolved += Number(run.mapping_unresolved) || 0;
    acc.offers_upserted += Number(run.offers_upserted) || 0;
    acc.countries_written += Number(run.countries_written) || 0;
    acc.api_errors += Number(run.api_errors) || 0;
    return acc;
  }, {
    processed: 0,
    mapped_new: 0,
    mapping_unresolved: 0,
    offers_upserted: 0,
    countries_written: 0,
    api_errors: 0,
  });
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

function loadPayload() {
  const status = readJson(path.join(REPORT_DIR, 'latest-status.json'), null);
  const unresolvedMarkdown = readText(path.join(REPORT_DIR, 'unresolved-latest.md'), '# Provider Availability Unresolved\n\nNo report yet.\n');
  const runs = listRuns(60);
  const rollup = summarizeRuns(runs);
  const workerLogTail = readText(path.join(REPORT_DIR, 'worker.log'), '')
    .split('\n')
    .slice(-120)
    .join('\n');

  return {
    report_dir: REPORT_DIR,
    generated_at: new Date().toISOString(),
    status,
    launchd: getLaunchdState(),
    run_history: runs,
    run_rollup: rollup,
    unresolved_markdown: unresolvedMarkdown,
    worker_log_tail: workerLogTail,
  };
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
  <title>Provider Availability Dashboard</title>
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
    .section { margin-top:14px; }
    table { width:100%; border-collapse: collapse; }
    th, td { font-size:12px; text-align:left; padding:6px 8px; border-bottom:1px solid var(--line); }
    th { color:var(--muted); font-weight:600; }
    pre { margin:0; white-space:pre-wrap; word-break:break-word; font-size:12px; }
    .twocol { display:grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    @media (max-width: 1000px) {
      .grid { grid-template-columns: repeat(2, minmax(160px,1fr)); }
      .twocol { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>Provider Availability Dashboard <span id="stamp" class="muted"></span></h1>

    <div class="grid section">
      <div class="card"><div class="k">Processed (latest run)</div><div id="processed" class="v">0</div></div>
      <div class="card"><div class="k">Mapped new</div><div id="mappedNew" class="v ok">0</div></div>
      <div class="card"><div class="k">Unresolved</div><div id="unresolved" class="v warn">0</div></div>
      <div class="card"><div class="k">API errors</div><div id="apiErrors" class="v bad">0</div></div>
      <div class="card"><div class="k">Offers upserted</div><div id="offers" class="v">0</div></div>
      <div class="card"><div class="k">Countries written</div><div id="countries" class="v">0</div></div>
      <div class="card"><div class="k">Total processed</div><div id="processedTotal" class="v">0</div></div>
      <div class="card"><div class="k">Launchd state</div><div id="launchdState" class="v">unknown</div></div>
      <div class="card"><div class="k">Urgent pending</div><div id="urgentPending" class="v warn">0</div></div>
      <div class="card"><div class="k">Oldest pending age</div><div id="oldestPendingAge" class="v">0m</div></div>
    </div>

    <div class="twocol section">
      <div class="card">
        <div class="k">Run history (last 60)</div>
        <table>
          <thead>
            <tr><th>Run</th><th>Processed</th><th>Mapped</th><th>Unresolved</th><th>Offers</th><th>Errors</th></tr>
          </thead>
          <tbody id="history"></tbody>
        </table>
      </div>
      <div class="card">
        <div class="k">Unresolved mappings (latest)</div>
        <pre id="unresolvedMarkdown"></pre>
      </div>
    </div>

    <div class="card section">
      <div class="k">Pending request reasons</div>
      <table>
        <thead>
          <tr><th>Reason</th><th>Count</th></tr>
        </thead>
        <tbody id="requestReasonMix"></tbody>
      </table>
    </div>

    <div class="card section">
      <div class="k">Worker log tail</div>
      <pre id="workerTail"></pre>
    </div>
  </div>

  <script>
    const fmt = new Intl.NumberFormat();

    function num(v) { return fmt.format(v || 0); }
    function age(seconds) {
      const total = Number(seconds) || 0;
      if (total < 60) return total + 's';
      if (total < 3600) return Math.floor(total / 60) + 'm';
      const hours = Math.floor(total / 3600);
      const minutes = Math.floor((total % 3600) / 60);
      return minutes > 0 ? hours + 'h ' + minutes + 'm' : hours + 'h';
    }

    function render(payload) {
      document.getElementById('stamp').textContent = '(updated ' + new Date().toLocaleTimeString() + ')';
      const status = payload.status || {};
      const run = status.last_run || {};
      const totals = status.totals || {};
      const queue = status.queue_summary || {};

      document.getElementById('processed').textContent = num(run.processed);
      document.getElementById('mappedNew').textContent = num(run.mapped_new);
      document.getElementById('unresolved').textContent = num(run.mapping_unresolved);
      document.getElementById('apiErrors').textContent = num(run.api_errors);
      document.getElementById('offers').textContent = num(run.offers_upserted);
      document.getElementById('countries').textContent = num(run.countries_written);
      document.getElementById('processedTotal').textContent = num(totals.processed);
      document.getElementById('launchdState').textContent = payload.launchd?.state || 'unknown';
      document.getElementById('urgentPending').textContent = num(queue.urgent_pending_count);
      document.getElementById('oldestPendingAge').textContent = age(queue.oldest_pending_request_age_seconds);

      const rows = payload.run_history || [];
      document.getElementById('history').innerHTML = rows.map((row) => {
        return '<tr>' +
          '<td>' + (row.file || '-') + '</td>' +
          '<td>' + num(row.processed) + '</td>' +
          '<td>' + num(row.mapped_new) + '</td>' +
          '<td>' + num(row.mapping_unresolved) + '</td>' +
          '<td>' + num(row.offers_upserted) + '</td>' +
          '<td>' + num(row.api_errors) + '</td>' +
          '</tr>';
      }).join('');

      const reasonMix = Object.entries(queue.request_reason_mix || {})
        .sort((lhs, rhs) => rhs[1] - lhs[1] || lhs[0].localeCompare(rhs[0]));
      document.getElementById('requestReasonMix').innerHTML = reasonMix.length
        ? reasonMix.map(([reason, count]) => '<tr><td>' + reason + '</td><td>' + num(count) + '</td></tr>').join('')
        : '<tr><td colspan="2" class="muted">No pending requests.</td></tr>';

      document.getElementById('unresolvedMarkdown').textContent = payload.unresolved_markdown || '';
      document.getElementById('workerTail').textContent = payload.worker_log_tail || '';
    }

    async function tick() {
      try {
        const res = await fetch('/api/status', { cache: 'no-store' });
        const data = await res.json();
        render(data);
      } catch (err) {
        console.error(err);
      }
    }

    tick();
    setInterval(tick, 5000);
  </script>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
  const url = req.url || '/';
  if (url === '/api/status') {
    return json(res, loadPayload());
  }
  if (url === '/' || url === '/index.html') {
    return html(res, appHtml());
  }
  return json(res, { error: 'not_found' }, 404);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`provider availability dashboard listening on http://127.0.0.1:${PORT}`);
});
