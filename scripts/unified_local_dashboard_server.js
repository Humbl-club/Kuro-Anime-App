#!/usr/bin/env node

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = '/Applications/Kuro';
const REPORTS = path.join(ROOT, 'reports');
const PORT = Number(process.env.KURO_UNIFIED_DASHBOARD_PORT || 8791);

const SERVICE_DEFS = [
  {
    key: 'catalog_safety',
    title: 'Catalog Safety',
    label: 'com.kuro.catalog-safety',
    reportDir: path.join(REPORTS, 'catalog-safety'),
    statusFile: 'latest-status.json',
    logFile: 'worker.log',
    processMatchers: ['run_catalog_safety.sh', 'catalog_safety_worker'],
    dashboardUrl: 'http://127.0.0.1:8788',
    summarize(status) {
      if (!status) return [];
      return [
        metric('Processed', status.processed),
        metric('Blocked', status.blocked),
        metric('Open gaps', status.open_gaps_count),
      ];
    },
    freshness(status) {
      return status?.finished_at || status?.started_at || null;
    },
  },
  {
    key: 'synopsis_enrichment',
    title: 'Synopsis Enrichment',
    label: 'com.kuro.synopsis-enrichment',
    reportDir: path.join(REPORTS, 'synopsis-enrichment'),
    statusFile: 'latest-status.json',
    logFile: 'worker.log',
    processMatchers: ['run_synopsis_enrichment.sh', 'synopsis_enrichment_worker'],
    dashboardUrl: 'http://127.0.0.1:8787',
    summarize(status) {
      if (!status) return [];
      return [
        metric('Processed', status.processed),
        metric('Generated', status.generated),
        metric('Backlog', status.backlog_remaining_estimate ?? status.backlog_due_after),
      ];
    },
    freshness(status) {
      return status?.finished_at || status?.started_at || null;
    },
  },
  {
    key: 'provider_availability',
    title: 'Provider Availability',
    label: 'com.kuro.provider-availability',
    reportDir: path.join(REPORTS, 'provider-availability'),
    statusFile: 'latest-status.json',
    logFile: 'worker.log',
    processMatchers: ['run_provider_availability.sh', 'provider_availability_worker'],
    dashboardUrl: 'http://127.0.0.1:8789',
    summarize(status) {
      if (!status) return [];
      return [
        metric('Processed', status.processed),
        metric('Mapped', status.mapped_new),
        metric('Unresolved', status.mapping_unresolved),
      ];
    },
    freshness(status) {
      return status?.generated_at || status?.finished_at || status?.started_at || null;
    },
  },
  {
    key: 'media_relations',
    title: 'Media Relations',
    label: 'com.kuro.media-relations',
    reportDir: path.join(REPORTS, 'media-relations'),
    statusFile: 'latest-status.json',
    runFile: 'latest-run.json',
    logFile: 'worker.log',
    processMatchers: ['run_media_relations_refresh.sh', 'media_relations_worker.js'],
    dashboardUrl: null,
    summarize(status, run) {
      const coverage = status?.top_catalog_coverage || {};
      const mode = run?.mode || run?.queue?.mode || run?.backfill?.mode || null;
      return [
        metric('Relations', status?.total_media_relations_rows),
        metric('Strong', coverage.strong),
        metric('Partial', coverage.partial),
        metric('Mode', mode || 'n/a'),
      ];
    },
    freshness(status, run) {
      return run?.completed_at || status?.generated_at || run?.started_at || null;
    },
  },
  {
    key: 'local_ci',
    title: 'Local CI',
    label: 'com.kuro.local-ci',
    reportDir: path.join(REPORTS, 'local-cicd'),
    statusFile: 'latest-ci-status.json',
    logPathFromStatus: true,
    processMatchers: ['run_local_ci_logged.sh', 'local_ci.sh'],
    dashboardUrl: null,
    summarize(status) {
      if (!status) return [];
      return [
        metric('Status', status.status || 'unknown'),
        metric('Exit', status.exit_code),
        metric('Ended', shortTime(status.ended_at)),
      ];
    },
    freshness(status) {
      return status?.ended_at || status?.started_at || null;
    },
  },
  {
    key: 'local_cd',
    title: 'Local CD',
    label: 'com.kuro.local-cd',
    reportDir: path.join(REPORTS, 'local-cicd'),
    statusFile: 'latest-cd-status.json',
    logPathFromStatus: true,
    processMatchers: ['run_local_cd_logged.sh', 'local_cd.sh'],
    dashboardUrl: null,
    summarize(status) {
      if (!status) return [];
      return [
        metric('Status', status.status || 'unknown'),
        metric('Exit', status.exit_code),
        metric('Ended', shortTime(status.ended_at)),
      ];
    },
    freshness(status) {
      return status?.ended_at || status?.started_at || null;
    },
  },
];

function metric(label, value) {
  return { label, value: value == null ? '—' : String(value) };
}

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

function tailText(filePath, lineCount = 20) {
  const text = readText(filePath, '');
  if (!text) return '';
  return text.split('\n').slice(-lineCount).join('\n').trim();
}

function fileMtime(filePath) {
  try {
    return fs.statSync(filePath).mtime.toISOString();
  } catch {
    return null;
  }
}

function launchdState(label) {
  const target = `gui/${process.getuid()}/${label}`;
  try {
    const text = execSync(`launchctl print ${target}`, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    const pick = (regex) => {
      const match = text.match(regex);
      return match ? match[1] : null;
    };
    return {
      state: pick(/\bstate = ([^\n]+)/),
      pid: pick(/\bpid = ([^\n]+)/),
      runs: pick(/\bruns = ([^\n]+)/),
      last_exit_code: pick(/\blast exit code = ([^\n]+)/),
    };
  } catch {
    return { state: 'unknown', pid: null, runs: null, last_exit_code: null };
  }
}

function listProcesses(matchers) {
  let lines = [];
  try {
    lines = execSync('ps -ax -o pid=,etime=,command=', {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      maxBuffer: 1024 * 1024,
    }).split('\n');
  } catch {
    return [];
  }

  return lines
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const match = line.match(/^(\d+)\s+([^\s]+)\s+(.+)$/);
      if (!match) return null;
      return { pid: match[1], etime: match[2], command: match[3] };
    })
    .filter(Boolean)
    .filter((proc) => matchers.some((needle) => proc.command.includes(needle)));
}

function shortTime(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat('en-GB', {
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

function relativeTime(value) {
  if (!value) return 'no timestamp';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'invalid timestamp';
  const diffMs = Date.now() - date.getTime();
  const diffMin = Math.round(diffMs / 60000);
  if (diffMin < 1) return 'just now';
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.round(diffMin / 60);
  if (diffHr < 48) return `${diffHr}h ago`;
  const diffDay = Math.round(diffHr / 24);
  return `${diffDay}d ago`;
}

function serviceHealth(service) {
  const launchd = service.launchd?.state;
  const running = service.processes.length > 0;
  if (running) return { tone: 'live', label: 'Running now' };
  if (launchd === 'running') return { tone: 'live', label: 'Running now' };
  if (service.status && service.freshness && (Date.now() - new Date(service.freshness).getTime()) < 24 * 60 * 60 * 1000) {
    return { tone: 'steady', label: 'Healthy recent run' };
  }
  if (service.status) return { tone: 'stale', label: 'Stale status' };
  return { tone: 'quiet', label: 'No status yet' };
}

function loadService(def) {
  const statusPath = path.join(def.reportDir, def.statusFile);
  const status = readJson(statusPath, null);
  const run = def.runFile ? readJson(path.join(def.reportDir, def.runFile), null) : null;
  const launchd = launchdState(def.label);
  const processes = listProcesses(def.processMatchers || []);
  const freshness = def.freshness ? def.freshness(status, run) : fileMtime(statusPath);
  const logPath = def.logPathFromStatus ? status?.log_file : path.join(def.reportDir, def.logFile || 'worker.log');
  const logTail = logPath ? tailText(logPath, 24) : '';
  const metrics = def.summarize ? def.summarize(status, run) : [];
  return {
    key: def.key,
    title: def.title,
    dashboard_url: def.dashboardUrl,
    report_dir: def.reportDir,
    status_path: statusPath,
    status,
    run,
    launchd,
    processes,
    freshness,
    freshness_relative: relativeTime(freshness),
    metrics,
    log_tail: logTail,
    health: serviceHealth({ status, freshness, launchd, processes }),
  };
}

function loadPayload() {
  const services = SERVICE_DEFS.map(loadService);
  const overview = {
    generated_at: new Date().toISOString(),
    live_count: services.filter((svc) => svc.health.tone === 'live').length,
    steady_count: services.filter((svc) => svc.health.tone === 'steady').length,
    stale_count: services.filter((svc) => svc.health.tone === 'stale').length,
    quiet_count: services.filter((svc) => svc.health.tone === 'quiet').length,
  };
  return { overview, services };
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
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Kuro Local Operations</title>
  <style>
    :root {
      --bg: #f4f1eb;
      --paper: #fbfaf7;
      --ink: #111111;
      --muted: #66645f;
      --line: #d6d1c8;
      --accent: #d92d20;
      --soft: #ece7de;
      --live: #111111;
      --steady: #4d4b46;
      --stale: #9c5f00;
      --quiet: #8c8a84;
      --shadow: 0 10px 30px rgba(17,17,17,0.05);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: linear-gradient(180deg, #f7f4ee 0%, #f1ede6 100%);
      color: var(--ink);
      font-family: "Helvetica Neue", "Neue Haas Grotesk Text Pro", Helvetica, Arial, sans-serif;
    }
    .page {
      max-width: 1440px;
      margin: 0 auto;
      padding: 32px 28px 56px;
    }
    .masthead {
      display: grid;
      grid-template-columns: 180px 1fr;
      gap: 24px;
      align-items: start;
      margin-bottom: 28px;
      padding-bottom: 20px;
      border-bottom: 2px solid var(--ink);
    }
    .mark {
      font-size: 13px;
      font-weight: 700;
      letter-spacing: 0.22em;
      text-transform: uppercase;
      color: var(--accent);
      padding-top: 6px;
    }
    h1 {
      margin: 0;
      font-size: clamp(2.4rem, 5vw, 4.8rem);
      line-height: 0.95;
      letter-spacing: -0.05em;
      font-weight: 700;
    }
    .subtitle {
      margin-top: 10px;
      max-width: 880px;
      font-size: 1rem;
      line-height: 1.5;
      color: var(--muted);
    }
    .summary {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 14px;
      margin-bottom: 30px;
    }
    .summary-card,
    .service-card,
    .log-card {
      background: var(--paper);
      border: 1px solid var(--line);
      box-shadow: var(--shadow);
    }
    .summary-card {
      padding: 18px 18px 16px;
      min-height: 128px;
    }
    .eyebrow {
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.14em;
      text-transform: uppercase;
      color: var(--muted);
      margin-bottom: 24px;
    }
    .summary-value {
      font-size: 3rem;
      line-height: 0.9;
      letter-spacing: -0.05em;
      font-weight: 700;
      margin-bottom: 8px;
    }
    .summary-note {
      font-size: 0.95rem;
      color: var(--muted);
    }
    .service-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
    }
    .service-card {
      padding: 18px;
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 16px;
      min-height: 280px;
    }
    .service-header {
      display: flex;
      flex-direction: column;
      gap: 10px;
      margin-bottom: 18px;
    }
    .service-title {
      font-size: 1.7rem;
      line-height: 0.95;
      font-weight: 700;
      letter-spacing: -0.04em;
    }
    .status-pill {
      align-self: flex-start;
      padding: 6px 10px 5px;
      border: 1px solid currentColor;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.1em;
      text-transform: uppercase;
    }
    .tone-live { color: var(--live); }
    .tone-steady { color: var(--steady); }
    .tone-stale { color: var(--stale); }
    .tone-quiet { color: var(--quiet); }
    .service-meta {
      font-size: 0.95rem;
      color: var(--muted);
      line-height: 1.45;
      margin-bottom: 18px;
    }
    .metrics {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px 14px;
    }
    .metric {
      padding-top: 10px;
      border-top: 1px solid var(--line);
    }
    .metric-label {
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      color: var(--muted);
      margin-bottom: 8px;
    }
    .metric-value {
      font-size: 1.4rem;
      line-height: 1;
      letter-spacing: -0.04em;
      font-weight: 700;
    }
    .service-side {
      min-width: 180px;
      border-left: 1px solid var(--line);
      padding-left: 16px;
      display: flex;
      flex-direction: column;
      gap: 14px;
    }
    .side-block { border-top: 1px solid var(--line); padding-top: 10px; }
    .side-label {
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      color: var(--muted);
      margin-bottom: 8px;
    }
    .side-value {
      font-size: 0.95rem;
      line-height: 1.5;
      color: var(--ink);
      word-break: break-word;
    }
    .side-value.muted { color: var(--muted); }
    .link {
      color: var(--ink);
      text-decoration: none;
      border-bottom: 1px solid var(--ink);
    }
    .logs {
      margin-top: 30px;
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
    }
    .log-card {
      padding: 18px;
    }
    .log-head {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: baseline;
      margin-bottom: 14px;
    }
    .log-title {
      font-size: 1.15rem;
      font-weight: 700;
      letter-spacing: -0.02em;
    }
    pre {
      margin: 0;
      background: #efebe4;
      border: 1px solid #dfd9cf;
      padding: 14px;
      font-size: 12px;
      line-height: 1.5;
      white-space: pre-wrap;
      word-break: break-word;
      min-height: 180px;
      max-height: 340px;
      overflow: auto;
    }
    @media (max-width: 1080px) {
      .summary,
      .service-grid,
      .logs { grid-template-columns: 1fr; }
      .service-card { grid-template-columns: 1fr; }
      .service-side { border-left: 0; padding-left: 0; border-top: 1px solid var(--line); padding-top: 14px; }
      .masthead { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <main class="page">
    <section class="masthead">
      <div class="mark">Kuro / Local Ops</div>
      <div>
        <h1>Unified Script Dashboard</h1>
        <div class="subtitle">One live surface for the local pipelines, CI/CD runners, launchd agents, and active worker logs that currently drive this machine.</div>
      </div>
    </section>

    <section class="summary" id="summary"></section>
    <section class="service-grid" id="services"></section>
    <section class="logs" id="logs"></section>
  </main>

  <script>
    const fmt = new Intl.NumberFormat();
    function numberish(v) {
      return /^-?\d+(\.\d+)?$/.test(String(v || ''));
    }
    function escapeHtml(input) {
      return String(input || '').replace(/[&<>\"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
    }
    function renderSummary(payload) {
      const cards = [
        ['Running now', payload.overview.live_count, 'Processes currently active on this machine'],
        ['Healthy recent', payload.overview.steady_count, 'Recent successful runs, not active right now'],
        ['Stale', payload.overview.stale_count, 'Have status files but need attention'],
        ['Quiet', payload.overview.quiet_count, 'No report file yet'],
      ];
      document.getElementById('summary').innerHTML = cards.map(([label, value, note]) =>
        '<article class=\"summary-card\">' +
          '<div class=\"eyebrow\">' + label + '</div>' +
          '<div class=\"summary-value\">' + fmt.format(value) + '</div>' +
          '<div class=\"summary-note\">' + note + '</div>' +
        '</article>'
      ).join('');
    }
    function renderServices(payload) {
      document.getElementById('services').innerHTML = payload.services.map((svc) => {
        const metrics = svc.metrics.map((metric) =>
          '<div class=\"metric\">' +
            '<div class=\"metric-label\">' + escapeHtml(metric.label) + '</div>' +
            '<div class=\"metric-value\">' + (numberish(metric.value) ? fmt.format(Number(metric.value)) : escapeHtml(metric.value)) + '</div>' +
          '</div>'
        ).join('');
        const processes = svc.processes.length
          ? svc.processes.map((proc) => '<div>' + escapeHtml(proc.pid) + ' · ' + escapeHtml(proc.etime) + ' · ' + escapeHtml(proc.command) + '</div>').join('')
          : '<div class="muted">No matching process</div>';
        const freshnessSuffix = svc.freshness ? ' · ' + escapeHtml(svc.freshness) : '';
        const dashboardLink = svc.dashboard_url
          ? '<a class=\"link\" href=\"' + svc.dashboard_url + '\" target=\"_blank\" rel=\"noreferrer\">open dedicated dashboard</a>'
          : '<span class=\"muted\">unified view only</span>';
        return (
          '<article class=\"service-card\">' +
            '<div>' +
              '<div class=\"service-header\">' +
                '<div class=\"status-pill tone-' + svc.health.tone + '\">' + escapeHtml(svc.health.label) + '</div>' +
                '<div class=\"service-title\">' + escapeHtml(svc.title) + '</div>' +
              '</div>' +
              '<div class=\"service-meta\">Last update: ' + escapeHtml(svc.freshness_relative) + freshnessSuffix + '</div>' +
              '<div class=\"metrics\">' + (metrics || '<div class=\"metric\"><div class=\"metric-label\">Status</div><div class=\"metric-value\">—</div></div>') + '</div>' +
            '</div>' +
            '<div class=\"service-side\">' +
              '<div class=\"side-block\">' +
                '<div class=\"side-label\">Launchd</div>' +
                '<div class=\"side-value\">' + escapeHtml(svc.launchd.state || 'unknown') + '</div>' +
                '<div class=\"side-value muted\">runs ' + escapeHtml(svc.launchd.runs || '—') + ' · exit ' + escapeHtml(svc.launchd.last_exit_code || '—') + '</div>' +
              '</div>' +
              '<div class=\"side-block\">' +
                '<div class=\"side-label\">Processes</div>' +
                '<div class=\"side-value\">' + processes + '</div>' +
              '</div>' +
              '<div class=\"side-block\">' +
                '<div class=\"side-label\">Files</div>' +
                '<div class=\"side-value muted\">' + escapeHtml(svc.status_path) + '</div>' +
              '</div>' +
              '<div class=\"side-block\">' +
                '<div class=\"side-label\">Link</div>' +
                '<div class=\"side-value\">' + dashboardLink + '</div>' +
              '</div>' +
            '</div>' +
          '</article>'
        );
      }).join('');
    }
    function renderLogs(payload) {
      document.getElementById('logs').innerHTML = payload.services.map((svc) =>
        '<article class=\"log-card\">' +
          '<div class=\"log-head\">' +
            '<div class=\"log-title\">' + escapeHtml(svc.title) + '</div>' +
            '<div class=\"eyebrow\">tail</div>' +
          '</div>' +
          '<pre>' + escapeHtml(svc.log_tail || 'No log output yet.') + '</pre>' +
        '</article>'
      ).join('');
    }
    async function refresh() {
      const res = await fetch('/api/status', { cache: 'no-store' });
      const payload = await res.json();
      renderSummary(payload);
      renderServices(payload);
      renderLogs(payload);
      document.title = 'Kuro Local Operations · ' + payload.overview.live_count + ' live';
    }
    refresh();
    setInterval(refresh, 15000);
  </script>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);
  if (url.pathname === '/api/status') {
    return json(res, loadPayload());
  }
  if (url.pathname === '/' || url.pathname === '/index.html') {
    return html(res, appHtml());
  }
  return json(res, { error: 'not_found' }, 404);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Unified local dashboard listening on http://127.0.0.1:${PORT}`);
});
