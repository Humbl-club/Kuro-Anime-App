/*
  Generate a synthetic "hard cases" corpus for Concierge parsing (EN + DE).

  Output: JSON lines to stdout. Each line is:
    {
      "text": "...",
      "expected": [
        { "kind": "ANIME"|"MANGA", "query": "title to resolve", "status": "...",
          "seasonNumber": 2, "episodeInSeason": 5, "progressChapters": 12, "completed": true }
      ]
    }

  Usage:
    node scripts/concierge_corpus_generate.js > /tmp/concierge_corpus.jsonl
*/

function mulberry32(seed) {
  return function () {
    let t = (seed += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function pick(rng, arr) {
  return arr[Math.floor(rng() * arr.length)];
}

function maybe(rng, p) {
  return rng() < p;
}

function typo(rng, s) {
  if (s.length < 5) return s;
  const ops = ["drop", "swap", "replace"];
  const op = pick(rng, ops);
  const i = 1 + Math.floor(rng() * (s.length - 2));
  if (op === "drop") return s.slice(0, i) + s.slice(i + 1);
  if (op === "swap" && i + 1 < s.length) return s.slice(0, i) + s[i + 1] + s[i] + s.slice(i + 2);
  const alpha = "abcdefghijklmnopqrstuvwxyz";
  const c = alpha[Math.floor(rng() * alpha.length)];
  return s.slice(0, i) + c + s.slice(i + 1);
}

function noiseTitle(rng, title) {
  let t = title;
  // Sometimes users paste/commonly type acronyms. This is a big real-world win for deterministic parsing.
  const abbrev = {
    "Attack on Titan": "AoT",
    "My Hero Academia": "MHA",
    "Hunter x Hunter (2011)": "HxH",
    "Fullmetal Alchemist: Brotherhood": "FMAB",
  }[title];
  if (abbrev && maybe(rng, 0.18)) t = abbrev;

  if (maybe(rng, 0.30)) t = typo(rng, t);
  if (maybe(rng, 0.15)) t = t.replace(/\bMy\b/i, "Hopi Faraka My"); // emulate ASR weirdness
  if (maybe(rng, 0.20)) t = t.replace(/\s+/g, " ").trim();
  if (maybe(rng, 0.10)) t = `${t} ${pick(rng, ["um", "uh", "äh", "like"])}`;
  return t.trim();
}

const ANIME = [
  { title: "One Piece", query: "One Piece", kind: "ANIME" },
  { title: "Naruto", query: "Naruto", kind: "ANIME" },
  { title: "My Hero Academia", query: "My Hero Academia", kind: "ANIME" },
  { title: "Attack on Titan", query: "Attack on Titan", kind: "ANIME" },
  { title: "Fullmetal Alchemist: Brotherhood", query: "Fullmetal Alchemist: Brotherhood", kind: "ANIME" },
  { title: "Hunter x Hunter (2011)", query: "Hunter x Hunter (2011)", kind: "ANIME" },
  { title: "Death Note", query: "Death Note", kind: "ANIME" },
];

const MANGA = [
  { title: "Vagabond", query: "Vagabond", kind: "MANGA" },
  { title: "Kingdom", query: "Kingdom", kind: "MANGA" },
  { title: "20th Century Boys", query: "20th Century Boys", kind: "MANGA" },
  { title: "Monster", query: "Monster", kind: "MANGA" },
  { title: "Berserk", query: "Berserk", kind: "MANGA" },
  { title: "Vinland Saga", query: "Vinland Saga", kind: "MANGA" },
];

function makeCase(rng, items, locale, mode) {
  const parts = [];
  const expected = [];
  const includeRoman = process.env.INCLUDE_ROMAN === "1";
  const roman = (n) => {
    const map = [
      ["X", 10],
      ["IX", 9],
      ["V", 5],
      ["IV", 4],
      ["I", 1],
    ];
    let x = n;
    let out = "";
    for (const [sym, val] of map) {
      while (x >= val) {
        out += sym;
        x -= val;
      }
    }
    return out || String(n);
  };
  for (const it of items) {
    const noisy = noiseTitle(rng, it.title);
    if (locale === "en") {
      if (mode === "completed") {
        if (it.kind === "MANGA") {
          parts.push(`I read ${noisy} completely`);
        } else {
          parts.push(`I watched ${noisy} completely`);
        }
        expected.push({ kind: it.kind, query: it.query, status: "COMPLETED", completed: true });
      } else if (mode === "watching_season") {
        if (it.kind === "MANGA") {
          const ch = 1 + Math.floor(rng() * 200);
          parts.push(`I'm reading ${noisy} up to chapter ${ch}`);
          expected.push({ kind: it.kind, query: it.query, status: "READING", progressChapters: ch });
        } else {
          const season = 1 + Math.floor(rng() * 4);
          const ep = 1 + Math.floor(rng() * 12);
          const seasonToken = includeRoman && season >= 2 && maybe(rng, 0.25) ? roman(season) : String(season);
          parts.push(`I just watched ${noisy} until season ${seasonToken} episode ${ep}`);
          const q = season <= 1 ? it.query : `${it.query} Season ${season}`;
          expected.push({ kind: it.kind, query: q, status: "WATCHING", seasonNumber: season, episodeInSeason: ep, progressEpisodes: ep });
        }
      } else if (mode === "watching_ep") {
        if (it.kind === "MANGA") {
          const ch = 1 + Math.floor(rng() * 200);
          parts.push(`I'm reading ${noisy} ch ${ch}`);
          expected.push({ kind: it.kind, query: it.query, status: "READING", progressChapters: ch });
        } else {
          const ep = 1 + Math.floor(rng() * 200);
          parts.push(`I'm watching ${noisy} ep ${ep}`);
          expected.push({ kind: it.kind, query: it.query, status: "WATCHING", progressEpisodes: ep });
        }
      } else {
        parts.push(`${noisy}`);
        expected.push({ kind: it.kind, query: it.query, status: "PLANNING" });
      }
    } else {
      if (mode === "completed") {
        const verb = it.kind === "MANGA" ? "gelesen" : "gesehen";
        parts.push(`Ich habe ${noisy} komplett ${verb}`);
        expected.push({ kind: it.kind, query: it.query, status: "COMPLETED", completed: true });
      } else if (mode === "watching_season") {
        if (it.kind === "MANGA") {
          const ch = 1 + Math.floor(rng() * 200);
          parts.push(`Ich lese ${noisy} bis Kapitel ${ch}`);
          expected.push({ kind: it.kind, query: it.query, status: "READING", progressChapters: ch });
        } else {
          const season = 1 + Math.floor(rng() * 4);
          const ep = 1 + Math.floor(rng() * 12);
          const seasonToken = includeRoman && season >= 2 && maybe(rng, 0.25) ? roman(season) : String(season);
          parts.push(`Ich schaue ${noisy} Staffel ${seasonToken} Folge ${ep}`);
          const q = season <= 1 ? it.query : `${it.query} Season ${season}`;
          expected.push({ kind: it.kind, query: q, status: "WATCHING", seasonNumber: season, episodeInSeason: ep, progressEpisodes: ep });
        }
      } else {
        if (it.kind === "MANGA") {
          parts.push(`Ich lese ${noisy}`);
          expected.push({ kind: it.kind, query: it.query, status: "READING" });
        } else {
          parts.push(`Ich schaue ${noisy}`);
          expected.push({ kind: it.kind, query: it.query, status: "WATCHING" });
        }
      }
    }
  }

  const joiner = locale === "en" ? " and " : " und ";
  const text = parts.join(joiner);
  return { text, expected };
}

function main() {
  const seed = Number(process.env.SEED || "1337");
  const rng = mulberry32(seed);

  const modes = ["completed", "watching_season", "watching_ep"];
  const locales = ["en", "de"];
  const corpus = [];

  for (let i = 0; i < 180; i++) {
    const locale = pick(rng, locales);
    const mode = pick(rng, modes);
    const count = 1 + Math.floor(rng() * 4);

    const pool = maybe(rng, 0.5) ? ANIME : MANGA;
    const items = [];
    for (let k = 0; k < count; k++) items.push(pick(rng, pool));

    corpus.push(makeCase(rng, items, locale, mode));
  }

  // A few fixed "anchor" cases
  corpus.push({
    text: "I watched all of One Piece until the last episode",
    expected: [{ kind: "ANIME", query: "One Piece", status: "COMPLETED", completed: true, lastEpisode: true }],
  });
  corpus.push({
    text: "Ich habe Vagabond komplett gelesen, und ich schaue Naruto Staffel 3 Folge 5",
    expected: [
      { kind: "MANGA", query: "Vagabond", status: "COMPLETED", completed: true },
      { kind: "ANIME", query: "Naruto", status: "WATCHING", seasonNumber: 3, episodeInSeason: 5, progressEpisodes: 5 },
    ],
  });

  for (const row of corpus) {
    process.stdout.write(JSON.stringify(row) + "\n");
  }
}

main();
