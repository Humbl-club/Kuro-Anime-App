/*
  Apply a SQL file to the Supabase project via the Management API.
  Usage:
    SUPABASE_ACCESS_TOKEN=sbp_... node scripts/apply_remote_sql.js supabase/migrations/<file>.sql
*/

const fs = require("fs");
const path = require("path");

const PROJECT_REF = "bkdifromsqxkndnllmdj";

async function main() {
  const token = process.env.SUPABASE_ACCESS_TOKEN;
  if (!token) {
    throw new Error("Missing SUPABASE_ACCESS_TOKEN env var.");
  }

  const rel = process.argv[2];
  if (!rel) {
    throw new Error("Missing SQL file path argument.");
  }

  const filePath = path.resolve(process.cwd(), rel);
  const sql = fs.readFileSync(filePath, "utf8");

  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ query: sql }),
  });

  const text = await res.text();
  if (!res.ok) {
    throw new Error(`SQL apply failed (${res.status}): ${text}`);
  }

  console.log(`Applied: ${rel}`);
}

main().catch((err) => {
  console.error(err?.message || String(err));
  process.exit(1);
});

