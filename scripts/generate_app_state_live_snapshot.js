#!/usr/bin/env node
/*
  Generates/refreshes the AUTO-LIVE-DB-SNAPSHOT section in CURRENT_APP_STATE.md
  by calling the admin-only RPC public.admin_schema_snapshot() using the
  Supabase service role key.

  This is optional (env required) but provides "live DB" truth to detect drift.

  Usage:
    SUPABASE_URL="..." SUPABASE_SERVICE_ROLE_KEY="..." node scripts/generate_app_state_live_snapshot.js
*/

const fs = require('fs');
const cp = require('child_process');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');

const ROOT = process.cwd();
const DOC = path.join(ROOT, 'CURRENT_APP_STATE.md');

const START = '<!-- BEGIN AUTO-LIVE-DB-SNAPSHOT -->';
const END = '<!-- END AUTO-LIVE-DB-SNAPSHOT -->';

function sh(cmd) {
  return cp.execSync(cmd, { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] }).toString('utf8').trim();
}

function replaceSection(doc, start, end, replacement) {
  const s = doc.indexOf(start);
  const e = doc.indexOf(end);
  if (s === -1 || e === -1 || e <= s) throw new Error(`Missing markers: ${start}`);
  return doc.slice(0, s + start.length) + '\n\n' + replacement + '\n\n' + doc.slice(e);
}

function safeErr(e) {
  const msg = (e && (e.message || e.toString())) || 'unknown error';
  // Avoid leaking anything that looks like a JWT/key in logs or docs.
  return msg.replace(/eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/g, '[REDACTED_JWT]');
}

async function main() {
  const doc = fs.readFileSync(DOC, 'utf8');
  const now = new Date().toISOString();
  // Use HEAD only (not --dirty) so regenerated docs don't perpetually claim "dirty".
  const head = sh('git rev-parse --short HEAD');

  const url = process.env.SUPABASE_URL || '';
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

  let body = '';
  body += `Generated: **${now}** (git: \`${head}\`)\n\n`;

  if (!url || !key) {
    body += 'Status: **SKIPPED** (missing `SUPABASE_URL` and/or `SUPABASE_SERVICE_ROLE_KEY` in environment).\n\n';
    body += 'To enable live snapshot generation, set env vars locally (do not commit secrets) and ensure the RPC is deployed:\n';
    body += '```bash\n';
    body += 'SUPABASE_URL=\"https://<project>.supabase.co\" \\\n';
    body += 'SUPABASE_SERVICE_ROLE_KEY=\"<service_role_key>\" \\\n';
    body += 'node scripts/generate_app_state_live_snapshot.js\n';
    body += '```\n';
    const out = replaceSection(doc, START, END, body);
    fs.writeFileSync(DOC, out, 'utf8');
    console.log('Updated AUTO-LIVE-DB-SNAPSHOT (skipped; env missing)');
    return;
  }

  const supabase = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const { data, error } = await supabase.rpc('admin_schema_snapshot');
    if (error) throw new Error(error.message || JSON.stringify(error));

    body += 'Status: **OK**\n\n';
    body += '```json\n';
    body += JSON.stringify(data, null, 2);
    body += '\n```\n';
  } catch (e) {
    body += 'Status: **FAILED**\n\n';
    body += 'Reason:\n';
    body += '```text\n';
    body += safeErr(e);
    body += '\n```\n';
    body += '\nMost common causes:\n';
    body += '- The migration defining `public.admin_schema_snapshot()` has not been applied/deployed yet.\n';
    body += '- The project URL is wrong.\n';
    body += '- The service role key is invalid.\n';
  }

  const out = replaceSection(doc, START, END, body);
  fs.writeFileSync(DOC, out, 'utf8');
  console.log('Updated AUTO-LIVE-DB-SNAPSHOT in CURRENT_APP_STATE.md');
}

main().catch((e) => {
  console.error('Fatal:', safeErr(e));
  process.exit(1);
});
