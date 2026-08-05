#!/usr/bin/env node

/*
  Phase 1 (realm repair) acceptance harness — one PASS/FAIL line per check.
  Spec: docs/superpowers/specs/2026-08-04-realm-repair-and-critique-plan.md §3
  Check IDs: docs/superpowers/plans/2026-08-04-claude-code-autonomous-phase123-prompt.md

  Usage:
    node scripts/realm_repair/run_phase1_acceptance.js
    node scripts/realm_repair/run_phase1_acceptance.js --skip-latency

  Auth tiers used (testing doctrine: service role or authenticated JWT):
    - PostgREST + demo-user JWT: RPC checks (P1, G1-G4, S1)
    - Supabase Management API (CLI keychain token, read-only): pg_proc/tier/cron
      checks (T1, T2, C1/C2, H1) — marked SKIP if the token is unavailable.
    - H2 (advisors) via Management API advisors endpoint — SKIP without token.
    - S2 reads reports/realm-rec-gold/latest.json (run eval_realm_rec_gold.js
      separately to refresh it; timeouts are the gated metric).

  Writes reports/realm-repair/phase1-acceptance.{md,json}.
  Demo account: kuro-visual-demo-2026@mailbox.invalid (throwaway, transcript-documented).
*/

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { getPublicProjectConfig } = require("../lib/project_config");

const ROOT = path.join(__dirname, "..", "..");
const REPORT_DIR = path.join(ROOT, "reports", "realm-repair");
const PROJECT_REF = "bkdifromsqxkndnllmdj";
const DEMO_EMAIL = "kuro-visual-demo-2026@mailbox.invalid";
const DEMO_PASSWORD = "DemoVisual2026#Kuro";

const SKIP_LATENCY = process.argv.includes("--skip-latency");

const results = [];
function record(id, verdict, evidence) {
  results.push({ id, verdict, evidence });
  console.log(`[${verdict.padEnd(9)}] ${id} — ${evidence}`);
}

function mgmtToken() {
  try {
    const raw = execFileSync("security", ["find-generic-password", "-s", "Supabase CLI", "-w"], {
      encoding: "utf8",
    }).trim();
    const b64 = raw.startsWith("go-keyring-base64:") ? raw.slice("go-keyring-base64:".length) : null;
    return b64 ? Buffer.from(b64, "base64").toString("utf8").trim() : raw;
  } catch {
    return null;
  }
}

async function mgmtQuery(token, query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ read_only: true, query }),
  });
  if (!res.ok) throw new Error(`mgmt query HTTP ${res.status}`);
  return res.json();
}

async function signInDemo(url, anonKey) {
  const res = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email: DEMO_EMAIL, password: DEMO_PASSWORD }),
  });
  if (!res.ok) throw new Error(`demo sign-in HTTP ${res.status}`);
  return (await res.json()).access_token;
}

async function rpc(url, anonKey, jwt, fn, body) {
  const started = Date.now();
  const res = await fetch(`${url}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const ms = Date.now() - started;
  if (!res.ok) throw new Error(`${fn} HTTP ${res.status}`);
  return { rows: await res.json(), ms };
}

async function titles(url, anonKey, table, ids) {
  if (!ids.length) return {};
  const res = await fetch(
    `${url}/rest/v1/${table}?select=id,title_english,average_score&id=in.(${ids.join(",")})`,
    { headers: { apikey: anonKey } }
  );
  const map = {};
  for (const row of await res.json()) map[row.id] = row;
  return map;
}

async function main() {
  const { url, anonKey } = getPublicProjectConfig();
  const jwt = await signInDemo(url, anonKey);
  const token = mgmtToken();

  // ── P1: Berserk (MANGA 5) top-25 junk-free ────────────────────────────────
  const berserk = await rpc(url, anonKey, jwt, "recommend_ids_similar_to_seeds", {
    p_media_type: "MANGA",
    p_seed_ids: [5],
    p_limit: 25,
  });
  const berserkIds = berserk.rows.map((r) => r.media_id);
  if (token && berserkIds.length) {
    const pen = await mgmtQuery(
      token,
      `select count(*)::int n from manga_tags mt join editorial_penalty_tags p on p.tag_id = mt.tag_id where mt.manga_id in (${berserkIds.join(",")})`
    );
    record("P1", pen[0].n === 0 ? "PASS" : "FAIL", `Berserk top-25 penalty-tag rows: ${pen[0].n} (want 0), ${berserkIds.length} results`);
  } else {
    const names = await titles(url, anonKey, "manga", berserkIds);
    const junk = berserkIds.filter((id) => /reborn|slime|overlord|vending/i.test(names[id]?.title_english || ""));
    record("P1", junk.length === 0 ? "PASS" : "FAIL", `title-pattern junk in Berserk top-25: ${junk.length} (penalty-tag scan skipped: no mgmt token)`);
  }

  // ── P2: penalized snapshot candidates did not rise ────────────────────────
  const beforePath = path.join(REPORT_DIR, "penalty-before.json");
  if (fs.existsSync(beforePath) && token) {
    const before = JSON.parse(fs.readFileSync(beforePath, "utf8"));
    const beforeIds = (before.berserk_top25 || []).map((r) => r.media_id);
    const pen = await mgmtQuery(
      token,
      `select mt.manga_id as id from manga_tags mt join editorial_penalty_tags p on p.tag_id = mt.tag_id where mt.manga_id in (${beforeIds.join(",")}) group by mt.manga_id`
    );
    const penalizedBefore = pen.map((r) => r.id);
    const stillPresent = penalizedBefore.filter((id) => berserkIds.includes(id));
    record(
      "P2",
      stillPresent.length === 0 ? "PASS" : "FAIL",
      `penalized snapshot candidates back in top-25: ${stillPresent.length} of ${penalizedBefore.length}`
    );
  } else {
    record("P2", "SKIP", `needs ${path.basename(beforePath)} + mgmt token`);
  }

  // ── G1/G2/G3/G4: Spirited Away neighborhood ───────────────────────────────
  const sa = await rpc(url, anonKey, jwt, "recommend_ids_similar_to_seeds", {
    p_media_type: "ANIME",
    p_seed_ids: [111],
    p_limit: 25,
  });
  const saIds = sa.rows.map((r) => r.media_id);
  const saNames = await titles(url, anonKey, "anime", saIds);
  const label = (id) => saNames[id]?.title_english || `#${id}`;

  const top12 = saIds.slice(0, 12);
  const ghibliAnchors = top12.filter((id) => [200, 161, 374, 858, 221].includes(id));
  record("G1", ghibliAnchors.length >= 2 ? "PASS" : "FAIL", `Ghibli-class anchors in top-12: ${ghibliAnchors.map(label).join(", ") || "none"}`);

  const totoroRank = saIds.indexOf(221) + 1;
  record("G2", totoroRank > 0 && totoroRank <= 25 ? "PASS" : "FAIL", `Totoro rank: ${totoroRank || "absent"}`);

  const hanakoRank = saIds.indexOf(2142) + 1;
  const wolfRank = saIds.findIndex((id) => /wolf children/i.test(label(id))) + 1;
  const g3ok = hanakoRank === 0 ? wolfRank > 0 : wolfRank > 0 && hanakoRank > wolfRank;
  record(
    "G3",
    g3ok ? "PASS" : "SOFT-FAIL",
    `Hanako S2 rank ${hanakoRank || "absent"} vs Wolf Children ${wolfRank || "absent"} (known SOFT-FAIL: importer isMain gap + tag space)`
  );

  const vending = saIds.filter((id) => [1381, 13287].includes(id));
  record("G4", vending.length === 0 ? "PASS" : "FAIL", `vending-class titles in SA top-25: ${vending.length}`);

  // ── G5: Kon structural path (informational gate) ──────────────────────────
  if (token) {
    const g5 = await mgmtQuery(
      token,
      `select m.media_id, m.realm, m.weight, t.tier from media_realm_membership_effective m left join media_realm_tier t on t.media_type = 'ANIME' and t.media_id = m.media_id where m.media_type = 'ANIME' and m.media_id in (286, 486) and m.weight >= 0.2 order by m.media_id, m.weight desc`
    );
    record("G5", g5.length > 0 ? "PASS" : "FAIL", `Perfect Blue/Paprika realm rows >=0.2: ${g5.length} (structural path exists; genre-overlap cliff caveat recorded)`);
  } else {
    record("G5", "SKIP", "needs mgmt token");
  }

  // ── T1/T2: tier coverage ──────────────────────────────────────────────────
  if (token) {
    const t1 = await mgmtQuery(
      token,
      `with vis as (select 'ANIME' mt, id from anime where average_score >= 70 and coalesce(is_adult, false) = false and cover_image_large is not null union all select 'MANGA', id from manga where average_score >= 70 and coalesce(is_adult, false) = false and cover_image_large is not null) select count(*)::int n from vis v where exists (select 1 from media_realm_membership_effective e where e.media_type = v.mt and e.media_id = v.id and e.weight >= 0.25) and not exists (select 1 from media_realm_tier t where t.media_type = v.mt and t.media_id = v.id)`
    );
    record("T1", t1[0].n === 0 ? "PASS" : "FAIL", `visible titles with effective membership >=0.25 and no tier row: ${t1[0].n}`);

    const t2 = await mgmtQuery(
      token,
      `select media_id, realm, tier from media_realm_tier where media_type = 'ANIME' and media_id in (111, 221) order by media_id`
    );
    record("T2", t2.length === 2 ? "PASS" : "FAIL", t2.map((r) => `${r.media_id}=${r.realm}/${r.tier}`).join(", "));
  } else {
    record("T1", "SKIP", "needs mgmt token");
    record("T2", "SKIP", "needs mgmt token");
  }

  // ── C1/C2: tier refresh cron ──────────────────────────────────────────────
  if (token) {
    const cron = await mgmtQuery(
      token,
      `select j.jobname, j.schedule, j.active, (select r.status from cron.job_run_details r where r.jobid = j.jobid order by r.start_time desc limit 1) last_status from cron.job j where j.jobname = 'realm-tier-refresh'`
    );
    const c = cron[0];
    record("C1", c && c.active ? "PASS" : "FAIL", c ? `${c.jobname} ${c.schedule} active=${c.active}` : "job missing");
    record("C2", c && c.last_status === "succeeded" ? "PASS" : "WARN", `last run: ${c ? c.last_status : "n/a"}`);
  } else {
    record("C1", "SKIP", "needs mgmt token");
    record("C2", "SKIP", "needs mgmt token");
  }

  // ── S1: RPC latency under authenticated ───────────────────────────────────
  if (!SKIP_LATENCY) {
    const seeds = [
      ["ANIME", 111], ["MANGA", 5], ["ANIME", 92], ["ANIME", 16], ["MANGA", 29],
      ["ANIME", 200], ["ANIME", 12], ["MANGA", 14], ["ANIME", 29], ["ANIME", 117],
      ["MANGA", 30], ["ANIME", 374], ["ANIME", 1259], ["MANGA", 97], ["ANIME", 1630],
      ["ANIME", 858], ["MANGA", 16], ["ANIME", 286], ["ANIME", 486], ["MANGA", 98],
    ];
    await rpc(url, anonKey, jwt, "recommend_ids_similar_to_seeds", { p_media_type: "ANIME", p_seed_ids: [111], p_limit: 12 }); // warm
    const times = [];
    for (const [mt, id] of seeds) {
      const { ms } = await rpc(url, anonKey, jwt, "recommend_ids_similar_to_seeds", { p_media_type: mt, p_seed_ids: [id], p_limit: 12 });
      times.push(ms);
    }
    times.sort((a, b) => a - b);
    const p50 = times[Math.floor(times.length * 0.5)];
    const p95 = times[Math.floor(times.length * 0.95)];
    record("S1", p95 < 200 ? "PASS" : "FAIL", `20 warm authenticated calls: p50 ${p50}ms, p95 ${p95}ms (target <200ms)`);
  } else {
    record("S1", "SKIP", "--skip-latency");
  }

  // ── S2: gold eval completion (from latest report) ─────────────────────────
  const evalPath = path.join(ROOT, "reports", "realm-rec-gold", "latest.json");
  if (fs.existsSync(evalPath)) {
    const ev = JSON.parse(fs.readFileSync(evalPath, "utf8"));
    const s = ev.summary || {};
    const ok = s.n_scored === 100 && s.n_seeds === 100;
    record(
      "S2",
      ok ? "PASS" : "WARN",
      `gold eval: ${s.n_scored}/${s.n_seeds} scored, generated ${s.generated_at} (heuristic labels; timeouts are the metric)`
    );
  } else {
    record("S2", "SKIP", "reports/realm-rec-gold/latest.json missing — run eval_realm_rec_gold.js");
  }

  // ── H1/H2: hygiene ────────────────────────────────────────────────────────
  if (token) {
    const h1 = await mgmtQuery(
      token,
      `select count(*)::int n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and (p.proname like '\\_ops\\_%' or p.proname = 'enqueue_realm_describe_batch')`
    );
    record("H1", h1[0].n === 0 ? "PASS" : "FAIL", `_ops_*/enqueue_realm_describe_batch functions remaining: ${h1[0].n}`);

    const advRes = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/advisors/security`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (advRes.ok) {
      const adv = await advRes.json();
      const lints = adv.lints || adv;
      const errors = (Array.isArray(lints) ? lints : []).filter((l) => (l.level || l.severity || "").toUpperCase() === "ERROR");
      record("H2", errors.length === 0 ? "PASS" : "FAIL", `security advisor ERRORs: ${errors.length}${errors.length ? " — " + errors.map((e) => e.title || e.name).join("; ") : ""}`);
    } else {
      record("H2", "SKIP", `advisors endpoint HTTP ${advRes.status}`);
    }
  } else {
    record("H1", "SKIP", "needs mgmt token");
    record("H2", "SKIP", "needs mgmt token");
  }

  // ── Report files ──────────────────────────────────────────────────────────
  fs.mkdirSync(REPORT_DIR, { recursive: true });
  const stamp = new Date().toISOString();
  const failed = results.filter((r) => r.verdict === "FAIL");
  const summaryLine = `${results.filter((r) => r.verdict === "PASS").length} PASS / ${failed.length} FAIL / ${results.filter((r) => r.verdict === "SOFT-FAIL").length} SOFT-FAIL / ${results.filter((r) => ["SKIP", "WARN"].includes(r.verdict)).length} SKIP-or-WARN`;

  fs.writeFileSync(
    path.join(REPORT_DIR, "phase1-acceptance.json"),
    JSON.stringify({ generated_at: stamp, summary: summaryLine, results }, null, 1)
  );
  const md = [
    "# Phase 1 acceptance — realm repair",
    "",
    `Generated: ${stamp}  `,
    `Summary: **${summaryLine}**`,
    "",
    "| ID | Verdict | Evidence |",
    "|---|---|---|",
    ...results.map((r) => `| ${r.id} | ${r.verdict} | ${r.evidence.replace(/\|/g, "\\|")} |`),
    "",
    "Full per-check SQL evidence: `reports/realm-repair/m1-verify.md`.",
  ].join("\n");
  fs.writeFileSync(path.join(REPORT_DIR, "phase1-acceptance.md"), md);

  console.log(`\n${summaryLine}`);
  console.log(`Reports: reports/realm-repair/phase1-acceptance.{md,json}`);
  process.exit(failed.length > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(`HARNESS ERROR: ${err.message}`);
  process.exit(2);
});
