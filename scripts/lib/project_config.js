const fs = require("fs");
const path = require("path");

const PROJECT_ENV_PATH = path.join(__dirname, "..", "project_public.env");

function parseEnvFile(text) {
  const values = {};
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx <= 0) continue;
    const key = trimmed.slice(0, idx).trim();
    let value = trimmed.slice(idx + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

function readProjectPublicEnv() {
  if (!fs.existsSync(PROJECT_ENV_PATH)) return {};
  return parseEnvFile(fs.readFileSync(PROJECT_ENV_PATH, "utf8"));
}

function getProjectUrl() {
  const values = readProjectPublicEnv();
  const url = process.env.SUPABASE_URL || values.SUPABASE_URL;
  if (!url) {
    throw new Error("Missing SUPABASE_URL. Set it explicitly or add scripts/project_public.env.");
  }
  return url;
}

function getPublicProjectConfig() {
  const values = readProjectPublicEnv();
  const url = process.env.SUPABASE_URL || values.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY || values.SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_ANON_KEY. Set them explicitly or add scripts/project_public.env.");
  }
  return { url, anonKey };
}

module.exports = {
  PROJECT_ENV_PATH,
  getProjectUrl,
  getPublicProjectConfig,
};
