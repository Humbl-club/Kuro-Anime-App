#!/usr/bin/env node

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = '/Applications/Kuro';
const REPORTS = path.join(ROOT, 'reports');
const PORT = Number(process.env.KURO_UNIFIED_DASHBOARD_PORT || 8791);
const AUTO_REFRESH_MS = 15000;

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
    extraFiles: ['missing-top-catalog.md'],
    logFile: 'worker.log',
    processMatchers: ['run_media_relations_refresh.sh', 'media_relations_worker.js'],
    dashboardUrl: null,
    summarize(status, run, service) {
      const coverage = status?.top_catalog_coverage || {};
      const mode = run?.mode || run?.queue?.mode || run?.backfill?.mode || null;
      const progress = service.extra?.progress;
      return [
        metric('Relations', status?.total_media_relations_rows),
        metric('Strong', coverage.strong),
        metric('Partial', coverage.partial),
        metric('Mode', mode || 'n/a'),
        metric('Coverage sample', status?.top_catalog_sample_size),
        metric('Backfill', progress ? `${progress.done}/${progress.total}` : 'idle'),
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

function escapeHtml(input) {
  return String(input ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[char]));
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

function tailText(filePath, lineCount = 24) {
  const text = readText(filePath, '');
  if (!text) return '';
  return text.split('\n').slice(-lineCount).join('\n').trim();
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
  if (service.processes.length > 0 || service.launchd?.state === 'running') {
    return { tone: 'live', label: 'Running now' };
  }
  if (service.status && service.freshness && (Date.now() - new Date(service.freshness).getTime()) < 24 * 60 * 60 * 1000) {
    return { tone: 'steady', label: 'Healthy recent run' };
  }
  if (service.status) {
    return { tone: 'stale', label: 'Stale status' };
  }
  return { tone: 'quiet', label: 'No status yet' };
}

function parseMediaRelationsProgress(logTail) {
  if (!logTail) return null;
  const matches = Array.from(logTail.matchAll(/top-catalog progress (\d+)\/(\d+) \(refreshed=(\d+), errors=(\d+)\)/g));
  if (!matches.length) return null;
  const m = matches[matches.length - 1];
  return {
    done: Number(m[1]),
    total: Number(m[2]),
    refreshed: Number(m[3]),
    errors: Number(m[4]),
  };
}

function getExtraForService(def, service) {
  if (def.key !== 'media_relations') return {};
  const missingPath = path.join(def.reportDir, 'missing-top-catalog.md');
  return {
    missingTopCatalog: readText(missingPath, ''),
    progress: parseMediaRelationsProgress(service.log_tail),
  };
}

function loadService(def) {
  const statusPath = path.join(def.reportDir, def.statusFile);
  const status = readJson(statusPath, null);
  const run = def.runFile ? readJson(path.join(def.reportDir, def.runFile), null) : null;
  const launchd = launchdState(def.label);
  const processes = listProcesses(def.processMatchers || []);
  const freshness = def.freshness ? def.freshness(status, run) : null;
  const logPath = def.logPathFromStatus ? status?.log_file : path.join(def.reportDir, def.logFile || 'worker.log');
  const log_tail = logPath ? tailText(logPath, 28) : '';
  const service = {
    key: def.key,
    title: def.title,
    dashboard_url: def.dashboardUrl,
    report_dir: def.reportDir,
    status_path: statusPath,
    run_path: def.runFile ? path.join(def.reportDir, def.runFile) : null,
    log_path: logPath || null,
    status,
    run,
    launchd,
    processes,
    freshness,
    freshness_relative: relativeTime(freshness),
    log_tail,
  };
  service.extra = getExtraForService(def, service);
  service.metrics = def.summarize ? def.summarize(status, run, service) : [];
  service.health = serviceHealth(service);
  return service;
}

function buildLadderPanel(service) {
  if (!service || service.key !== 'media_relations') return null;
  const status = service.status || {};
  const coverage = status.top_catalog_coverage || {};
  const missing = status.top_missing_titles || [];
  const progress = service.extra?.progress;
  return {
    relations: status.total_media_relations_rows || 0,
    distinct: status.distinct_source_titles_with_relations || 0,
    sampleSize: status.top_catalog_sample_size || 0,
    coverage,
    progress,
    generated_at: status.generated_at || service.freshness,
    topMissing: missing.slice(0, 8),
    rawMissingText: service.extra?.missingTopCatalog || '',
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
  const ladder = buildLadderPanel(services.find((svc) => svc.key === 'media_relations'));
  return { overview, ladder, services };
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

function text(res, body, status = 200, contentType = 'text/plain; charset=utf-8') {
  res.writeHead(status, {
    'Content-Type': contentType,
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function renderSummaryCard(label, value, note) {
  return [
    '<article class="summary-card">',
    `<div class="eyebrow">${escapeHtml(label)}</div>`,
    `<div class="summary-value">${escapeHtml(String(value))}</div>`,
    `<div class="summary-note">${escapeHtml(note)}</div>`,
    '</article>',
  ].join('');
}

function renderMetric(metricObj) {
  return [
    '<div class="metric">',
    `<div class="metric-label">${escapeHtml(metricObj.label)}</div>`,
    `<div class="metric-value">${escapeHtml(metricObj.value)}</div>`,
    '</div>',
  ].join('');
}

function renderAction(label, href) {
  return `<a class="action" href="${escapeHtml(href)}">${escapeHtml(label)}</a>`;
}

function renderServiceCard(service) {
  const metrics = service.metrics.length
    ? service.metrics.map(renderMetric).join('')
    : renderMetric({ label: 'Status', value: '—' });
  const actions = [
    service.dashboard_url ? renderAction('Open dashboard', service.dashboard_url) : '',
    renderAction('Status JSON', `/service/${service.key}/status`),
    service.run_path ? renderAction('Run JSON', `/service/${service.key}/run`) : '',
    service.log_path ? renderAction('Log tail', `/service/${service.key}/log`) : '',
  ].filter(Boolean).join('');
  const processes = service.processes.length
    ? service.processes.map((proc) => `<div>${escapeHtml(proc.pid)} · ${escapeHtml(proc.etime)} · ${escapeHtml(proc.command)}</div>`).join('')
    : '<div class="muted">No matching process</div>';

  return [
    '<article class="service-card">',
    '<div>',
    '<div class="service-header">',
    `<div class="status-pill tone-${escapeHtml(service.health.tone)}">${escapeHtml(service.health.label)}</div>`,
    `<div class="service-title">${escapeHtml(service.title)}</div>`,
    '</div>',
    `<div class="service-meta">Last update: ${escapeHtml(service.freshness_relative)}${service.freshness ? ' · ' + escapeHtml(service.freshness) : ''}</div>`,
    `<div class="metrics">${metrics}</div>`,
    '</div>',
    '<div class="service-side">',
    '<div class="side-block">',
    '<div class="side-label">Launchd</div>',
    `<div class="side-value">${escapeHtml(service.launchd.state || 'unknown')}</div>`,
    `<div class="side-value muted">runs ${escapeHtml(service.launchd.runs || '—')} · exit ${escapeHtml(service.launchd.last_exit_code || '—')}</div>`,
    '</div>',
    '<div class="side-block">',
    '<div class="side-label">Processes</div>',
    `<div class="side-value">${processes}</div>`,
    '</div>',
    '<div class="side-block">',
    '<div class="side-label">Actions</div>',
    `<div class="actions">${actions}</div>`,
    '</div>',
    '</div>',
    '</article>',
  ].join('');
}

function renderLadderPanel(ladder) {
  if (!ladder) return '';
  const coverage = ladder.coverage || {};
  const progressText = ladder.progress
    ? `${ladder.progress.done}/${ladder.progress.total} refreshed · ${ladder.progress.errors} errors`
    : 'No active backfill at the moment';
  const missingRows = ladder.topMissing.length
    ? ladder.topMissing.map((item) => `<li><strong>${escapeHtml(item.title)}</strong><span>${escapeHtml(item.media_type)} · pop ${escapeHtml(String(item.popularity))}</span></li>`).join('')
    : '<li><strong>No urgent gaps</strong><span>The sampled ladder set is covered.</span></li>';

  return [
    '<section class="ladder-panel">',
    '<div class="ladder-head">',
    '<div>',
    '<div class="eyebrow">Adaptation Ladder Coverage</div>',
    '<h2>Editorial franchise context</h2>',
    `<p>Last sampled ${escapeHtml(relativeTime(ladder.generated_at))}. This is the live top-catalog ladder picture, not a guessed estimate.</p>`,
    '</div>',
    `<div class="ladder-status">${escapeHtml(progressText)}</div>`,
    '</div>',
    '<div class="ladder-grid">',
    renderSummaryCard('Relation rows', ladder.relations, 'Directional AniList-backed edges stored in Kuro'),
    renderSummaryCard('Distinct titles', ladder.distinct, 'Titles with at least one persisted relation edge'),
    renderSummaryCard('Strong ladders', coverage.strong || 0, 'Top-sample titles with a convincing main path'),
    renderSummaryCard('Partial / minimal', `${coverage.partial || 0} / ${coverage.minimal || 0}`, 'Useful but incomplete franchise guidance'),
    '</div>',
    '<div class="ladder-columns">',
    '<article class="ladder-card">',
    '<div class="eyebrow">Top missing</div>',
    '<ul class="missing-list">',
    missingRows,
    '</ul>',
    `<div class="actions">${renderAction('Coverage report', '/service/media_relations/coverage')} ${renderAction('Status JSON', '/service/media_relations/status')}</div>`,
    '</article>',
    '<article class="ladder-card">',
    '<div class="eyebrow">Coverage mix</div>',
    `<div class="coverage-bars">
      <div><span>Strong</span><strong>${escapeHtml(String(coverage.strong || 0))}</strong></div>
      <div><span>Partial</span><strong>${escapeHtml(String(coverage.partial || 0))}</strong></div>
      <div><span>Minimal</span><strong>${escapeHtml(String(coverage.minimal || 0))}</strong></div>
      <div><span>None</span><strong>${escapeHtml(String(coverage.none || 0))}</strong></div>
      <div><span>Errors</span><strong>${escapeHtml(String(coverage.errors || 0))}</strong></div>
    </div>`,
    `<p class="ladder-note">Sample size: ${escapeHtml(String(ladder.sampleSize))}. The queue worker fills gaps from detail opens, Discover hero rails, and Concierge recommendation surfaces.</p>`,
    '</article>',
    '</div>',
    '</section>',
  ].join('');
}

function renderLogCard(service) {
  return [
    '<article class="log-card">',
    '<div class="log-head">',
    `<div class="log-title">${escapeHtml(service.title)}</div>`,
    '<div class="eyebrow">tail</div>',
    '</div>',
    `<pre>${escapeHtml(service.log_tail || 'No log output yet.')}</pre>`,
    '</article>',
  ].join('');
}

function appHtml(payload) {
  const summaryCards = [
    renderSummaryCard('Running now', payload.overview.live_count, 'Processes currently active on this machine'),
    renderSummaryCard('Healthy recent', payload.overview.steady_count, 'Recent successful runs, not active right now'),
    renderSummaryCard('Stale', payload.overview.stale_count, 'Have status files but need attention'),
    renderSummaryCard('Quiet', payload.overview.quiet_count, 'No report file yet'),
  ].join('');

  return [
    '<!doctype html>',
    '<html lang="en">',
    '<head>',
    '<meta charset="utf-8" />',
    '<meta name="viewport" content="width=device-width, initial-scale=1" />',
    '<title>Kuro Local Operations</title>',
    `<meta http-equiv="refresh" content="${Math.round(AUTO_REFRESH_MS / 1000)}">`,
    '<style>',
    ':root {',
    '--bg:#f4f0e8;--paper:#fbfaf7;--ink:#111111;--muted:#66645f;--line:#d7d0c4;--accent:#d12a1b;--soft:#ece6db;--live:#111111;--steady:#47443f;--stale:#996000;--quiet:#8a8882;--shadow:0 10px 30px rgba(17,17,17,0.05);',
    '}',
    '*{box-sizing:border-box} body{margin:0;background:linear-gradient(180deg,#f8f4ee 0%,#f1ece4 100%);color:var(--ink);font-family:"Helvetica Neue","Neue Haas Grotesk Text Pro",Helvetica,Arial,sans-serif}',
    '.page{max-width:1440px;margin:0 auto;padding:32px 28px 56px}',
    '.masthead{display:grid;grid-template-columns:180px 1fr;gap:24px;align-items:start;margin-bottom:28px;padding-bottom:20px;border-bottom:2px solid var(--ink)}',
    '.mark{font-size:13px;font-weight:700;letter-spacing:.22em;text-transform:uppercase;color:var(--accent);padding-top:6px}',
    'h1{margin:0;font-size:clamp(2.8rem,5vw,5.4rem);line-height:.92;letter-spacing:-.06em;font-weight:700}',
    '.subtitle{margin-top:10px;max-width:920px;font-size:1rem;line-height:1.5;color:var(--muted)}',
    '.meta-strip{margin-top:16px;font-size:12px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted)}',
    '.summary,.ladder-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}',
    '.summary{margin-bottom:30px}',
    '.summary-card,.service-card,.log-card,.ladder-card{background:var(--paper);border:1px solid var(--line);box-shadow:var(--shadow)}',
    '.summary-card{padding:18px 18px 16px;min-height:128px}',
    '.eyebrow{font-size:12px;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);margin-bottom:18px}',
    '.summary-value{font-size:3rem;line-height:.9;letter-spacing:-.05em;font-weight:700;margin-bottom:8px}',
    '.summary-note{font-size:.95rem;color:var(--muted)}',
    '.service-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}',
    '.service-card{padding:18px;display:grid;grid-template-columns:1fr auto;gap:16px;min-height:300px}',
    '.service-header{display:flex;flex-direction:column;gap:10px;margin-bottom:18px}',
    '.service-title{font-size:1.7rem;line-height:.95;font-weight:700;letter-spacing:-.04em}',
    '.status-pill{align-self:flex-start;padding:6px 10px 5px;border:1px solid currentColor;font-size:12px;font-weight:700;letter-spacing:.1em;text-transform:uppercase}',
    '.tone-live{color:var(--live)} .tone-steady{color:var(--steady)} .tone-stale{color:var(--stale)} .tone-quiet{color:var(--quiet)}',
    '.service-meta{font-size:.95rem;color:var(--muted);line-height:1.45;margin-bottom:18px}',
    '.metrics{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px 14px}',
    '.metric{padding-top:10px;border-top:1px solid var(--line)}',
    '.metric-label,.side-label{font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:8px}',
    '.metric-value{font-size:1.4rem;line-height:1;letter-spacing:-.04em;font-weight:700}',
    '.service-side{min-width:230px;border-left:1px solid var(--line);padding-left:16px;display:flex;flex-direction:column;gap:14px}',
    '.side-block{border-top:1px solid var(--line);padding-top:10px}',
    '.side-value{font-size:.95rem;line-height:1.5;color:var(--ink);word-break:break-word}',
    '.muted{color:var(--muted)}',
    '.actions{display:flex;flex-wrap:wrap;gap:8px}',
    '.action{display:inline-flex;align-items:center;justify-content:center;padding:8px 10px;border:1px solid var(--ink);text-decoration:none;color:var(--ink);font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase}',
    '.action:hover{background:var(--ink);color:var(--paper)}',
    '.ladder-panel{margin:30px 0 24px;padding:22px;background:var(--paper);border:1px solid var(--line);box-shadow:var(--shadow)}',
    '.ladder-head{display:grid;grid-template-columns:1fr auto;gap:20px;align-items:end;margin-bottom:18px}',
    '.ladder-head h2{margin:0;font-size:2rem;letter-spacing:-.04em;line-height:1}',
    '.ladder-head p{margin:8px 0 0;color:var(--muted);max-width:760px;line-height:1.5}',
    '.ladder-status{font-size:13px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--accent)}',
    '.ladder-columns{display:grid;grid-template-columns:1.2fr 1fr;gap:14px;margin-top:14px}',
    '.ladder-card{padding:18px}',
    '.missing-list{list-style:none;margin:0;padding:0;display:grid;gap:10px}',
    '.missing-list li{display:flex;justify-content:space-between;gap:16px;padding:10px 0;border-top:1px solid var(--line)}',
    '.missing-list li:first-child{border-top:0;padding-top:0}',
    '.missing-list strong{font-size:1rem;letter-spacing:-.02em}',
    '.missing-list span{font-size:.92rem;color:var(--muted);white-space:nowrap}',
    '.coverage-bars{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px;margin-bottom:14px}',
    '.coverage-bars div{padding-top:10px;border-top:1px solid var(--line)}',
    '.coverage-bars span{display:block;font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:6px}',
    '.coverage-bars strong{font-size:1.6rem;letter-spacing:-.04em}',
    '.ladder-note{margin:0;color:var(--muted);line-height:1.5}',
    '.logs{margin-top:30px;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}',
    '.log-card{padding:18px}',
    '.log-head{display:flex;justify-content:space-between;gap:12px;align-items:baseline;margin-bottom:14px}',
    '.log-title{font-size:1.15rem;font-weight:700;letter-spacing:-.02em}',
    'pre{margin:0;background:#efebe4;border:1px solid #dfd9cf;padding:14px;font-size:12px;line-height:1.5;white-space:pre-wrap;word-break:break-word;min-height:180px;max-height:340px;overflow:auto}',
    '@media (max-width:1180px){.summary,.ladder-grid,.service-grid,.logs,.ladder-columns{grid-template-columns:1fr}.service-card{grid-template-columns:1fr}.service-side{border-left:0;padding-left:0;border-top:1px solid var(--line);padding-top:14px}.masthead,.ladder-head{grid-template-columns:1fr}.coverage-bars{grid-template-columns:repeat(2,minmax(0,1fr))}.missing-list li{flex-direction:column}}',
    '</style>',
    '</head>',
    '<body>',
    '<main class="page">',
    '<section class="masthead">',
    '<div class="mark">Kuro / Local Ops</div>',
    '<div>',
    '<h1>Unified Script Dashboard</h1>',
    '<div class="subtitle">One local surface for the actual background systems on this machine: worker pipelines, launchd agents, CI/CD runners, ladder coverage, and live log tails.</div>',
    `<div class="meta-strip">Refreshed ${escapeHtml(shortTime(payload.overview.generated_at))} · auto-refresh every ${Math.round(AUTO_REFRESH_MS / 1000)}s</div>`,
    '</div>',
    '</section>',
    `<section class="summary">${summaryCards}</section>`,
    renderLadderPanel(payload.ladder),
    `<section class="service-grid">${payload.services.map(renderServiceCard).join('')}</section>`,
    `<section class="logs">${payload.services.map(renderLogCard).join('')}</section>`,
    '</main>',
    '</body>',
    '</html>',
  ].join('');
}

function sendServiceFile(res, payload, key, kind) {
  const service = payload.services.find((svc) => svc.key === key);
  if (!service) return json(res, { error: 'unknown_service' }, 404);

  if (kind === 'status') {
    return text(res, JSON.stringify(service.status ?? null, null, 2) + '\n', 200, 'application/json; charset=utf-8');
  }
  if (kind === 'run') {
    return text(res, JSON.stringify(service.run ?? null, null, 2) + '\n', 200, 'application/json; charset=utf-8');
  }
  if (kind === 'log') {
    return text(res, service.log_tail || 'No log output yet.\n');
  }
  if (kind === 'coverage' && key === 'media_relations') {
    return text(res, service.extra?.missingTopCatalog || 'No coverage report yet.\n');
  }
  return json(res, { error: 'unknown_kind' }, 404);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);
  const payload = loadPayload();

  if (url.pathname === '/api/status') {
    return json(res, payload);
  }

  const serviceRoute = url.pathname.match(/^\/service\/([a-z_]+)\/(status|run|log|coverage)$/);
  if (serviceRoute) {
    return sendServiceFile(res, payload, serviceRoute[1], serviceRoute[2]);
  }

  if (url.pathname === '/' || url.pathname === '/index.html') {
    return text(res, appHtml(payload), 200, 'text/html; charset=utf-8');
  }

  return json(res, { error: 'not_found' }, 404);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Unified local dashboard listening on http://127.0.0.1:${PORT}`);
});
