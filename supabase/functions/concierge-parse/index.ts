import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MediaType = "ANIME" | "MANGA";
type ListStatus = "WATCHING" | "READING" | "PLANNING" | "COMPLETED" | "DROPPED" | "PAUSED";

type ParsedItem = {
  raw: string;
  normalized: string;
  mediaTypeHint?: MediaType;
  status?: ListStatus;
  progressEpisodes?: number;
  progressChapters?: number;
  progressVolumes?: number;
  seasonNumber?: number;
  episodeInSeason?: number;
  caughtUp?: boolean;
  lastEpisode?: boolean;
  completed?: boolean;
  yearMention?: number;
};

function romanToInt(input: string): number | null {
  const s = String(input ?? "").trim().toUpperCase();
  if (!s) return null;
  // Keep this conservative: only accept typical roman numerals up to 40-ish.
  if (!/^[IVXLCDM]{1,6}$/.test(s)) return null;

  const map: Record<string, number> = { I: 1, V: 5, X: 10, L: 50, C: 100, D: 500, M: 1000 };
  let total = 0;
  let prev = 0;
  for (let i = s.length - 1; i >= 0; i--) {
    const v = map[s[i]];
    if (!v) return null;
    if (v < prev) total -= v;
    else total += v;
    prev = v;
  }
  if (total < 1 || total > 40) return null;
  return total;
}

function expandCommonAbbreviations(title: string): string | null {
  const raw = String(title ?? "").trim();
  if (!raw) return null;

  // Normalize to a compact key for exact-match abbreviations (e.g. "FMA:B" -> "fmab").
  const compact = raw.toLowerCase().replace(/[^a-z0-9]+/g, "");
  const map: Record<string, string> = {
    aot: "Attack on Titan",
    snk: "Attack on Titan", // Shingeki no Kyojin
    jjk: "Jujutsu Kaisen",
    mha: "My Hero Academia",
    bnha: "My Hero Academia", // Boku no Hero Academia
    hxh: "Hunter x Hunter",
    fmab: "Fullmetal Alchemist: Brotherhood",
    fma: "Fullmetal Alchemist",
    opm: "One Punch Man",
    csm: "Chainsaw Man",
    jjba: "JoJo's Bizarre Adventure",
    kny: "Demon Slayer: Kimetsu no Yaiba",
    op: "One Piece",
    db: "Dragon Ball",
    dbz: "Dragon Ball Z",
    dbs: "Dragon Ball Super",
    sao: "Sword Art Online",
    bc: "Black Clover",
    tog: "Tower of God",
    mia: "Made in Abyss",
    rezero: "Re:ZERO -Starting Life in Another World-",
    konosuba: "Kono Subarashii Sekai ni Shukufuku wo!",
    mp100: "Mob Psycho 100",
    nge: "Neon Genesis Evangelion",
    eva: "Neon Genesis Evangelion",
    lotgh: "Legend of the Galactic Heroes",
    logh: "Legend of the Galactic Heroes",
    tpn: "The Promised Neverland",
    dm: "Dungeon Meshi",
    cote: "Classroom of the Elite",
  };

  // Only expand when we have a known mapping. Avoid risky short acronyms like "DS".
  if (map[compact] && map[compact] !== raw) return map[compact];

  // If the abbreviation is the first token in a longer query, expand it too.
  const parts = raw.split(/\s+/g);
  if (parts.length >= 2) {
    const head = parts[0].toLowerCase().replace(/[^a-z0-9]+/g, "");
    const expanded = map[head];
    if (expanded) return [expanded, ...parts.slice(1)].join(" ");
  }

  return null;
}

function json(res: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(res), {
    ...init,
    headers: { "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function normalizeLine(s: string) {
  return s
    .trim()
    .replace(/\u00A0/g, " ")
    .replace(/\s+/g, " ");
}

function normalizeAliasKey(raw: string): string {
  let s = String(raw ?? "").toLowerCase();
  s = s.replace(/\u00a0/g, " ");
  // strip filler + verbs/status
  s = s.replace(/\b(um+|uh+|erm+|eh+|like|also|äh+|ae+h+|so|halt)\b/giu, " ");
  s = s.replace(/\b(i\s+have|i'?m|im|i\s+am|i)\b/giu, " ");
  s = s.replace(/\b(ich\s+habe|ich\s+hab|ich|bin)\b/giu, " ");
  s = s.replace(
    /\b(watched|watching|finished|completed|dropped|paused|planning|read|reading|caught up|up to date|seen|saw)\b/giu,
    " ",
  );
  s = s.replace(
    /\b(geschaut|gesehen|gelesen|fertig|abgeschlossen|beendet|abgebrochen|pausiert|geplant|aktuell|komplett|vollständig|vollstaendig)\b/giu,
    " ",
  );
  // strip progress markers
  s = s.replace(/\b(?:season|staffel|episode|ep|folge|chapter|ch|kapitel|volume|vol|band)\b/giu, " ");
  s = s.replace(/\b\d{1,2}\s*x\s*\d{1,4}\b/giu, " ");
  s = s.replace(/\bs\d{1,2}\s*e\d{1,4}\b/giu, " ");
  // keep only letters/numbers/spaces (unicode)
  s = s.replace(/[^\p{L}\p{N}\s]+/gu, " ");
  s = s.replace(/\s+/g, " ").trim();
  return s.slice(0, 160);
}

function splitItems(text: string): string[] {
  const normalized = text.replace(/\r\n/g, "\n").trim();
  if (!normalized) return [];

  const splitOnClauseBoundaries = (s: string) =>
    s
      .split(/[\n]+|(?<=[.!?;])\s+/g)
      .flatMap((part) => part.split(/,\s*(?=(?:i\s+|i'?m\s+|i\s+am\s+|ich\s+))/i))
      .map((x) => x.trim())
      .filter(Boolean);

  const splitTitleList = (tail: string) =>
    tail
      .split(/\s*(?:,|;|\bund\b|\band\b|&|\u2022)\s*/i)
      .map((x) => x.trim())
      .filter(Boolean);

  const englishVerbRe =
    /^(?<verb>(?:i\s+(?:(?:just|recently|only)\s+)?(?:watched|finished|completed|dropped|paused|started|read)|i\s+have\s+(?:watched|seen|read)|i\s+am\s+(?:watching|reading)|i'?m\s+(?:watching|reading)|im\s+(?:watching|reading)|watching|reading))\s+(?<tail>.+)$/i;
  const germanPresentVerbRe =
    /^(?<verb>ich\s+(?:schaue|gucke|sehe|lese|bin)\b)\s+(?<tail>.+)$/i;
  const germanPerfectVerbRe =
    /^(?<head>ich\s+(?:habe|hab))\s+(?<tail>.+?)\s+(?<past>gesehen|geschaut|gelesen)\b/i;

  const clauses = splitOnClauseBoundaries(normalized);
  const out: string[] = [];

  for (const clause of clauses) {
    const parts = clause
      .split(/\b(?:and|und)\b\s+(?=(?:i\b|ich\b))/i)
      .map((x) => x.trim())
      .filter(Boolean);

    for (const part of parts) {
      const c = part.trim();
      if (!c) continue;

      const germanPerfect = c.match(germanPerfectVerbRe);
      if (germanPerfect?.groups?.tail && germanPerfect.groups?.head && germanPerfect.groups?.past) {
        const titles = splitTitleList(germanPerfect.groups.tail);
        for (const t of titles) {
          if (!t) continue;
          out.push(`${germanPerfect.groups.head} ${t} ${germanPerfect.groups.past}`.trim());
        }
        continue;
      }

      const english = c.match(englishVerbRe);
      if (english?.groups?.verb && english.groups?.tail) {
        // If the tail includes another clause ("... and I ..."), split that part out first.
        const tailParts = english.groups.tail
          .split(/\b(?:and|und)\b\s+(?=(?:i\b|ich\b))/i)
          .map((x) => x.trim())
          .filter(Boolean);

        const firstTail = tailParts[0] ?? "";
        const titles = splitTitleList(firstTail);
        for (const t of titles) {
          if (!t) continue;
          // If the chunk already begins with another verb clause, keep it as-is.
          if (englishVerbRe.test(t) || germanPresentVerbRe.test(t) || germanPerfectVerbRe.test(t)) out.push(t);
          else out.push(`${english.groups.verb} ${t}`.trim());
        }
        // Push remaining verb-clauses back into the pipeline.
        for (const extra of tailParts.slice(1)) out.push(extra);
        continue;
      }

      const germanPresent = c.match(germanPresentVerbRe);
      if (germanPresent?.groups?.verb && germanPresent.groups?.tail) {
        const tailParts = germanPresent.groups.tail
          .split(/\b(?:and|und)\b\s+(?=(?:i\b|ich\b))/i)
          .map((x) => x.trim())
          .filter(Boolean);
        const firstTail = tailParts[0] ?? "";

        const titles = splitTitleList(firstTail);
        for (const t of titles) {
          if (!t) continue;
          if (englishVerbRe.test(t) || germanPresentVerbRe.test(t) || germanPerfectVerbRe.test(t)) out.push(t);
          else out.push(`${germanPresent.groups.verb} ${t}`.trim());
        }
        for (const extra of tailParts.slice(1)) out.push(extra);
        continue;
      }

      // Fallback: treat as a plain title line (or a comma-separated list).
      if (c.includes(",") && c.length < 200) out.push(...c.split(",").map((x) => x.trim()).filter(Boolean));
      else out.push(c);
    }
  }

  return out.map((l) => l.replace(/^[\-\*\u2022]+\s*/, "").trim()).filter(Boolean);
}

function parseStatus(raw: string): { status?: ListStatus; completed?: boolean } {
  const s = raw.toLowerCase();
  const explicitCompletion =
    /\b(last episode|to the end|all of it|every season|fully|entirely|whole thing)\b/.test(s) ||
    /\b(bis zur letzten folge|bis zum ende|alles gesehen|komplett gesehen|vollständig|vollstaendig)\b/.test(s);
  const hasPartialProgress =
    /\b(?:until|till|up to|upto|to|bis)\b/.test(s) &&
    /\b(?:season|staffel|episode|ep|folge|chapter|ch|kapitel|band|vol|volume|\d{1,2}\s*x\s*\d{1,4}|s\d{1,2}\s*e\d{1,4})\b/.test(s);
  const hasSoftPartial =
    /\b(halfway|half way|midway|partway|some of it|a bit|a few (?:eps|episodes|chapters))\b/.test(s) ||
    /\b(halb|hälfte|haelfte|zur hälfte|zur haelfte|teilweise|ein bisschen)\b/.test(s);

  // English + slang
  if (/\b(caught up|up to date|up-to-date|latest|current)\b/.test(s)) return { status: "WATCHING" };
  const iFinished =
    /\b(i\s+(?:just\s+)?finished|i\s+(?:just\s+)?completed)\b/.test(s);
  const iWatched =
    /\b(i\s+(?:just\s+)?watched|i\s+(?:just\s+)?saw|i\s+have\s+watched|i\s+have\s+seen)\b/.test(s);
  const iRead =
    /\b(i\s+(?:just\s+)?read|i\s+have\s+read)\b/.test(s);

  if (iFinished) {
    if ((hasPartialProgress || hasSoftPartial) && !explicitCompletion) return { status: "WATCHING" };
    return { status: "COMPLETED", completed: true };
  }
  if (iWatched) {
    // "I watched X" is ambiguous; default to WATCHING unless explicitly completed.
    if ((hasPartialProgress || hasSoftPartial) && !explicitCompletion) return { status: "WATCHING" };
    if (explicitCompletion) return { status: "COMPLETED", completed: true };
    return { status: "WATCHING" };
  }
  if (iRead) {
    if ((hasPartialProgress || hasSoftPartial) && !explicitCompletion) return { status: "READING" };
    if (explicitCompletion) return { status: "COMPLETED", completed: true };
    return { status: "READING" };
  }
  if (/\b(i'?m\s+watching|i\s+am\s+watching)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(i'?m\s+reading|i\s+am\s+reading)\b/.test(s)) return { status: "READING" };
  if (/\b(completed|finished|done)\b/.test(s)) return { status: "COMPLETED", completed: true };
  if (/\b(dropped)\b/.test(s)) return { status: "DROPPED" };
  if (/\b(paused|on hold|on-hold|hiatus)\b/.test(s)) return { status: "PAUSED" };
  if (/\b(planning|plan to watch|plan to read|ptw|ptr)\b/.test(s)) return { status: "PLANNING" };
  if (/\b(reading)\b/.test(s)) return { status: "READING" };
  if (/\b(watching)\b/.test(s)) return { status: "WATCHING" };

  // German
  if (/\b(aktuell|auf dem neuesten stand|up to date|auf dem aktuellen stand)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(ich\s+habe|ich\s+hab)\b/.test(s) && /\b(geschaut|gesehen|gelesen)\b/.test(s)) {
    if (hasPartialProgress || hasSoftPartial) {
      if (/\b(gelesen)\b/.test(s)) return { status: "READING" };
      return { status: "WATCHING" };
    }
    if (explicitCompletion) return { status: "COMPLETED", completed: true };
    // "Ich habe X geschaut" is ambiguous; default to WATCHING unless explicit completion.
    if (/\b(gelesen)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
  if (/\b(ich\s+(?:schaue|gucke|sehe)|gerade\s+am\s+schauen|am\s+schauen)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(ich\s+lese|gerade\s+am\s+lesen|am\s+lesen)\b/.test(s)) return { status: "READING" };
  if (/\b(fertig|abgeschlossen|beendet|zu ende|komplett)\b/.test(s)) return { status: "COMPLETED", completed: true };
  if (/\b(abgebrochen|gedroppt|droppe|droppen)\b/.test(s)) return { status: "DROPPED" };
  if (/\b(pausiert|pause|auf eis)\b/.test(s)) return { status: "PAUSED" };
  if (/\b(plane|geplant|will schauen|will sehen|möchte schauen|möchte sehen)\b/.test(s)) return { status: "PLANNING" };
  if (/\b(lese|am lesen|gerade am lesen)\b/.test(s)) return { status: "READING" };
  if (/\b(schaue|gucke|sehe|am schauen|gerade am schauen)\b/.test(s)) return { status: "WATCHING" };
  return {};
}

function parseMagicFlags(raw: string): Pick<ParsedItem, "caughtUp" | "lastEpisode" | "completed"> {
  const s = raw.toLowerCase();
  const caughtUp =
    /\b(caught up|up to date|up-to-date|latest)\b/.test(s) ||
    /\b(auf dem neuesten stand|aktuell|up to date)\b/.test(s);

  const lastEpisode =
    /\b(last episode|to the end|all of it|every season|fully|entirely|whole thing)\b/.test(s) ||
    /\b(bis zur letzten folge|bis zum ende|alles gesehen|komplett gesehen|vollständig|ganz gesehen|komplett|vollstaendig)\b/.test(s);

  return {
    caughtUp: caughtUp || undefined,
    lastEpisode: lastEpisode || undefined,
    completed: lastEpisode || undefined,
  };
}

function parseProgress(
  raw: string,
): Pick<
  ParsedItem,
  "progressEpisodes" | "progressChapters" | "progressVolumes" | "seasonNumber" | "episodeInSeason"
> {
  let s = raw.toLowerCase();
  const out: any = {};

  // Normalize small number-words (EN/DE) so "season two episode five" works.
  const wordMap: Record<string, string> = {
    one: "1",
    two: "2",
    three: "3",
    four: "4",
    five: "5",
    six: "6",
    seven: "7",
    eight: "8",
    nine: "9",
    ten: "10",
    first: "1",
    second: "2",
    third: "3",
    fourth: "4",
    fifth: "5",
    sixth: "6",
    seventh: "7",
    eighth: "8",
    ninth: "9",
    tenth: "10",
    eins: "1",
    eine: "1",
    zwei: "2",
    drei: "3",
    vier: "4",
    fünf: "5",
    funf: "5",
    sechs: "6",
    sieben: "7",
    acht: "8",
    neun: "9",
    zehn: "10",
    erste: "1",
    zweite: "2",
    dritte: "3",
    vierte: "4",
    fünfte: "5",
    funfte: "5",
    sechste: "6",
    siebte: "7",
    achte: "8",
    neunte: "9",
    zehnte: "10",
  };
  s = s.replace(
    /\b(one|two|three|four|five|six|seven|eight|nine|ten|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eins|eine|zwei|drei|vier|fünf|funf|sechs|sieben|acht|neun|zehn|erste|zweite|dritte|vierte|fünfte|funfte|sechste|siebte|achte|neunte|zehnte)\b/g,
    (m) => wordMap[m] ?? m,
  );

  // Season/Episode formats:
  //  - S2E5, s02e05, 2x05
  //  - Season 2 Episode 5
  //  - Staffel 2 Folge 5
  //  - Season II Episode 5 / Staffel IV Folge 3
  const romanSeasonEp = s.match(
    /\b(?:season|staffel|part|cour)\s*([ivxlcdm]{1,6})\b(?:\s*[,.\- ]\s*)?(?:episode|ep|folge)\s*(\d{1,4})\b/,
  );
  if (romanSeasonEp) {
    const sn = romanToInt(romanSeasonEp[1]);
    if (sn != null) {
      out.seasonNumber = sn;
      out.episodeInSeason = parseInt(romanSeasonEp[2], 10);
      out.progressEpisodes = out.episodeInSeason;
    }
  }

  const sxe = s.match(/\bs(?:eason)?\s*(\d{1,2})\s*(?:e|ep|episode)?\s*(\d{1,4})\b/);
  const x = s.match(/\b(\d{1,2})\s*x\s*(\d{1,4})\b/);
  const seasonEp =
    s.match(/\b(?:season|staffel)\s*(\d{1,2})\b(?:\s*[,.\- ]\s*)?(?:episode|ep|folge)\s*(\d{1,4})\b/);
  const se = seasonEp ?? sxe ?? x;
  if (se && !out.seasonNumber) {
    out.seasonNumber = parseInt(se[1], 10);
    out.episodeInSeason = parseInt(se[2], 10);
    out.progressEpisodes = out.episodeInSeason;
  }

  const seasonOnly = s.match(/\b(?:season|staffel)\s*(\d{1,2})\b/);
  if (seasonOnly && !out.seasonNumber) out.seasonNumber = parseInt(seasonOnly[1], 10);

  const romanSeasonOnly = s.match(/\b(?:season|staffel|part|cour)\s*([ivxlcdm]{1,6})\b/);
  if (romanSeasonOnly && !out.seasonNumber) {
    const sn = romanToInt(romanSeasonOnly[1]);
    if (sn != null) out.seasonNumber = sn;
  }

  const ep = s.match(/\b(?:ep|episode)\s*(\d{1,4})\b/);
  if (ep) out.progressEpisodes = parseInt(ep[1], 10);
  const folge = s.match(/\b(?:folge)\s*(\d{1,4})\b/);
  if (folge) out.progressEpisodes = parseInt(folge[1], 10);

  const ch = s.match(/\b(?:ch|chapter)\s*(\d{1,5})\b/);
  if (ch) out.progressChapters = parseInt(ch[1], 10);
  const kap = s.match(/\b(?:kapitel)\s*(\d{1,5})\b/);
  if (kap) out.progressChapters = parseInt(kap[1], 10);

  const vol = s.match(/\b(?:vol|volume)\s*(\d{1,4})\b/);
  if (vol) out.progressVolumes = parseInt(vol[1], 10);
  const band = s.match(/\b(?:band)\s*(\d{1,4})\b/);
  if (band) out.progressVolumes = parseInt(band[1], 10);

  return out;
}

function mediaTypeHint(raw: string): MediaType | undefined {
  const s = raw.toLowerCase();
  // Explicit media words
  if (/\b(manga|manhwa|manhua)\b/.test(s)) return "MANGA";
  if (/\b(anime)\b/.test(s)) return "ANIME";

  // Verb hints (magic: "watched" => anime, "read" => manga)
  if (/\b(read|reading|i\s+read|i'?m\s+reading|im\s+reading|lese|gelesen|am\s+lesen)\b/.test(s)) return "MANGA";
  if (/\b(watched|watching|i\s+watched|i'?m\s+watching|im\s+watching|schaue|gucke|sehe|geschaut|gesehen|am\s+schauen)\b/.test(s)) return "ANIME";

  // Progress-unit hints
  if (/\b(volume|vol\.|band|chapter|ch\.|kapitel)\b/.test(s)) return "MANGA";
  if (/\b(episode|ep\.|folge|staffel)\b/.test(s)) return "ANIME";
  return undefined;
}

// Year mention policy (product): used to disambiguate adaptations (e.g. "HxH 2011").
// Keep this small to reduce false positives on random numbers in prompts.
const YEAR_MENTION_MIN = 1960;
const YEAR_MENTION_MAX = 2030;

function isPlausibleYearMention(y: number): boolean {
  return Number.isFinite(y) && y >= YEAR_MENTION_MIN && y <= YEAR_MENTION_MAX;
}

function extractYearMention(raw: string): number | undefined {
  // Must run BEFORE stripMeta() removes parenthesized content.
  // Collect all 4-digit numbers that look like plausible anime/manga years.
  const matches: number[] = [];

  // Parenthesized years: "Hunter x Hunter (2011)"
  for (const m of raw.matchAll(/\((\d{4})\)/g)) {
    const y = Number(m[1]);
    if (isPlausibleYearMention(y)) matches.push(y);
  }

  // Standalone 4-digit years (not part of larger number)
  for (const m of raw.matchAll(/(?<!\d)(\d{4})(?!\d)/g)) {
    const y = Number(m[1]);
    if (isPlausibleYearMention(y) && !matches.includes(y)) matches.push(y);
  }

  // If multiple distinct years found (e.g. "FMA 2003 vs 2009"), ambiguous: return nothing.
  const unique = Array.from(new Set(matches));
  if (unique.length !== 1) return undefined;
  return unique[0];
}

function stripMeta(raw: string): string {
  // remove parenthetical notes and common suffixes without nuking the title
  let s = raw;
  s = s.replace(/\((?:[^()]+)\)/g, " ");
  // Speech fillers (EN/DE)
  s = s.replace(/\b(um+|uh+|erm+|eh+|like|also|äh+|ae+h+|so|halt)\b/gi, " ");
  // Explicit completion phrases (keep as flags, remove from title query)
  s = s.replace(/\b(?:the\s+)?last\s+episode\b/gi, " ");
  s = s.replace(/\b(?:to\s+the\s+end|all\s+of\s+it|every\s+season)\b/gi, " ");
  s = s.replace(/\b(?:bis\s+(?:zur|zum)\s+letzten\s+folge|bis\s+zum\s+ende|zu\s+ende)\b/gi, " ");
  s = s.replace(/\b(until|till|bis)\b/gi, " ");
  s = s.replace(/\b(completed|finished|done|dropped|paused|planning|watching|reading|caught up|up to date)\b/gi, " ");
  s = s.replace(/\b(fully|entirely|whole\s+thing|whole|complete|completely)\b/gi, " ");
  s = s.replace(/\b(fertig|abgeschlossen|beendet|abgebrochen|pausiert|geplant|aktuell|auf dem neuesten stand|komplett)\b/gi, " ");
  s = s.replace(/\b(vollständig|vollstaendig|ganz)\b/gi, " ");
  s = s.replace(/\b(just|recently|only)\b/gi, " ");
  s = s.replace(/\b(watched|seen|saw|read)\b/gi, " ");
  s = s.replace(/\b(geschaut|gesehen|gelesen)\b/gi, " ");
  s = s.replace(/\b(all of|everything)\b/gi, " ");
  s = s.replace(/\b(alles)\b/gi, " ");
  // Remove leading chatty pronouns/aux verbs once we've stripped the meaningful verbs.
  s = s.replace(/^\s*i'?m\b\s*/i, " ");
  s = s.replace(/^\s*im\b\s*/i, " ");
  s = s.replace(/^\s*i\s+am\b\s*/i, " ");
  s = s.replace(/^\s*i\b\s*/i, " ");
  s = s.replace(/^\s*ich\b\s*(?:habe|hab)?\b\s*/i, " ");
  // Remove trailing progress phrases like "until the last episode" / "bis zur letzten Folge".
  s = s.replace(/\b(until|till|to)\b\s+(?:the\s+)?(?:last\s+episode|end)\b/gi, " ");
  s = s.replace(/\b(bis)\b\s+(?:zur|zum)\s+(?:letzten\s+folge|ende)\b/gi, " ");
  s = s.replace(/\b(?:season|staffel)\s*\d{1,2}\b/gi, " ");
  // Word-number season/episode (EN/DE): "season three", "staffel zwei", etc.
  s = s.replace(
    /\b(?:season|staffel)\s*(?:one|two|three|four|five|six|seven|eight|nine|ten|eins|eine|zwei|drei|vier|fünf|funf|sechs|sieben|acht|neun|zehn)\b/gi,
    " ",
  );
  s = s.replace(/\b(?:ep|episode|folge|ch|chapter|kapitel|vol|volume|band)\s*\d{1,5}\b/gi, " ");
  s = s.replace(
    /\b(?:ep|episode|folge|ch|chapter|kapitel|vol|volume|band)\s*(?:one|two|three|four|five|six|seven|eight|nine|ten|eins|eine|zwei|drei|vier|fünf|funf|sechs|sieben|acht|neun|zehn)\b/gi,
    " ",
  );
  s = s.replace(/\b\d{1,2}\s*x\s*\d{1,4}\b/gi, " ");
  s = s.replace(/\bs\d{1,2}\s*e\d{1,4}\b/gi, " ");
  // Strip standalone year mentions so they don't pollute trigram search.
  // Parenthesized years are already removed above. Keep year-only queries (e.g. manga "1984").
  s = s.replace(/\s+/g, " ").trim();
  if (!/^\d{4}$/.test(s)) {
    s = s.replace(/(?<!\d)(\d{4})(?!\d)/g, (m, yy) => {
      const y = Number(yy);
      return isPlausibleYearMention(y) ? " " : m;
    });
  }
  s = s.replace(/\s+/g, " ").trim();
  return s;
}

function tokenOverlapBoost(query: string, title: string): number {
  const stop = new Set(["the", "a", "an", "of", "and", "or", "to", "in", "on", "at", "for"]);
  const q = query
    .toLowerCase()
    .replace(/[^a-z0-9äöüß\s]/gi, " ")
    .split(/\s+/g)
    .filter(Boolean);
  const t = title
    .toLowerCase()
    .replace(/[^a-z0-9äöüß\s]/gi, " ")
    .split(/\s+/g)
    .filter(Boolean);
  if (q.length === 0 || t.length === 0) return 0;

  const qSet = new Set(q.filter((w) => w.length >= 3 && !stop.has(w)));
  const tSet = new Set(t.filter((w) => w.length >= 3 && !stop.has(w)));

  let overlap = 0;
  for (const w of qSet) if (tSet.has(w)) overlap++;

  // Special case: titles like "My Hero Academia" often get dictated with "my ... academia".
  if (overlap >= 1 && q.includes("my") && t.includes("my")) overlap++;

  if (overlap >= 3) return 0.42;
  if (overlap === 2) return 0.34;
  if (overlap === 1) return 0.14;
  return 0;
}

function variantPenalty(query: string, candidate: { title_raw?: string; variant_type?: string }): number {
  const q = query.toLowerCase();
  const t = String(candidate?.title_raw ?? "").toLowerCase();
  const v = String(candidate?.variant_type ?? "").toLowerCase();

  // Penalize spin-offs/variants unless the user asked for them.
  const wantsOva = /\b(ova|special|movie|film|recap)\b/.test(q);
  if (!wantsOva && (/\b(ova|special|movie|film|recap)\b/.test(t) || /\b(ova|special|movie|film|recap)\b/.test(v))) {
    return 0.12;
  }

  // Collab/collection titles (often include ×) should never beat the main title.
  if (t.includes("×") || t.includes(" x ")) return 0.18;

  // Many movies/spinoffs have ":" subtitles. Penalize unless user explicitly typed a subtitle.
  if (!q.includes(":") && t.includes(":")) return 0.10;

  // Season-labeled variants should not beat the base title unless the user mentioned a season.
  const userMentionsSeason = /\b(season|staffel|s\d{1,2})\b/.test(q);
  if (!userMentionsSeason && /\bseason\b/.test(t) && (/\bfinal\b/.test(t) || /\b\d{1,2}\b/.test(t))) {
    return 0.10;
  }

  return 0;
}

function seasonMatchBoost(titleRaw: string, seasonNumber: number): number {
  const t = titleRaw.toLowerCase();
  const n = String(seasonNumber);
  const patterns = [
    new RegExp(`\\bseason\\s*${n}\\b`, "i"),
    new RegExp(`\\bstaffel\\s*${n}\\b`, "i"),
    new RegExp(`\\bpart\\s*${n}\\b`, "i"),
    new RegExp(`\\b${n}(?:st|nd|rd|th)\\s+season\\b`, "i"),
    new RegExp(`第\\s*${n}\\s*期`, "i"),
    new RegExp(`${n}期`, "i"),
  ];
  return patterns.some((p) => p.test(t)) ? 0.18 : 0;
}

function buildSeasonQueries(baseTitle: string, seasonNumber: number): string[] {
  const n = seasonNumber;
  const ordinal = (x: number) => {
    const mod100 = x % 100;
    if (mod100 >= 11 && mod100 <= 13) return "th";
    const mod10 = x % 10;
    if (mod10 === 1) return "st";
    if (mod10 === 2) return "nd";
    if (mod10 === 3) return "rd";
    return "th";
  };
  const suffixes = [
    `season ${n}`,
    `s${n}`,
    `staffel ${n}`,
    `${n}${ordinal(n)} season`,
    `part ${n}`,
    `cour ${n}`,
  ];
  return suffixes.map((s) => `${baseTitle} ${s}`.trim());
}

function buildDenoisedQueries(title: string): string[] {
  const stop = new Set([
    "the",
    "a",
    "an",
    "of",
    "and",
    "or",
    "to",
    "until",
    "till",
    "up",
    "upto",
    "bis",
    "zur",
    "zum",
    "ich",
    "habe",
    "hab",
    "bin",
    "i",
    "im",
    "i'm",
    "am",
    "my",
    "just",
    "recently",
    "only",
    "watched",
    "watching",
    "read",
    "reading",
    "gesehen",
    "geschaut",
    "gelesen",
    "schaue",
    "gucke",
    "sehe",
    "lese",
    "season",
    "staffel",
    "episode",
    "ep",
    "folge",
    "chapter",
    "ch",
    "kapitel",
    "volume",
    "vol",
    "band",
  ]);

  const rawTokens = title
    .toLowerCase()
    .split(/\s+/g)
    .map((t) => t.replace(/[^a-z0-9äöüß]/gi, ""))
    .filter((t) => t.length >= 3)
    .filter((t) => !stop.has(t))
    .filter((t) => !/^\d+$/.test(t));

  const tokens = Array.from(new Set(rawTokens));
  if (tokens.length === 0) return [];

  const queries: string[] = [];

  // Strongest anchor tokens (longer words tend to be distinctive).
  const long = tokens.filter((t) => t.length >= 6).slice(0, 2);
  queries.push(...long);

  // Last 1–3 tokens often contain the core noun (e.g. "... academia").
  for (let len = Math.min(3, tokens.length); len >= 1; len--) {
    queries.push(tokens.slice(-len).join(" "));
  }

  // First 2 tokens can help for two-word titles.
  if (tokens.length >= 2) queries.push(tokens.slice(0, 2).join(" "));

  return Array.from(new Set(queries)).filter(Boolean).slice(0, 5);
}

function clientIp(req: Request): string | null {
  const xf = req.headers.get("x-forwarded-for");
  if (xf) {
    const first = xf.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  return null;
}

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, { status: 405 });

  // Warmup: short-circuit before auth/rate-limit to warm the Deno isolate
  const url = new URL(req.url);
  if (url.searchParams.get("warmup") === "true") {
    return json({ ok: true });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
  const supabaseService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const supabaseKey = supabaseAnon ?? supabaseService;
  if (!supabaseUrl || !supabaseKey) {
    return json({ error: "Missing SUPABASE_URL or a Supabase API key env (SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY)" }, { status: 500 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const client = createClient(supabaseUrl, supabaseKey, {
    global: { headers: authHeader ? { Authorization: authHeader } : {} },
  });

  const body = await req.json().catch(() => ({}));
  const text: string = String(body?.text ?? "");
  if (typeof text !== "string" || text.length > 5000) {
    return json({ error: "Text too long (max 5000 chars)" }, { status: 400 });
  }
  const scope: "anime" | "manga" | "both" = body?.scope ?? "both";
  const limitPerItem = Math.max(3, Math.min(15, Number(body?.limitPerItem ?? 10)));

  const itemsRaw = splitItems(text);
  if (itemsRaw.length === 0) {
    return json({ success: true, items: [] });
  }

  // Run rate-limit check and auth verification in parallel (they are independent).
  const ip = clientIp(req);
  const [rlResult, userResult] = await Promise.all([
    client.rpc("check_concierge_rate_limit", {
      p_kind: "parse",
      p_ip: ip,
      p_window_seconds: null,
      p_max_user: null,
      p_max_ip: null,
    }),
    client.auth.getUser(),
  ]);

  const rl = rlResult.data;
  if (rl && rl.allowed === false) {
    return json(
      { error: "Rate limited", retry_after_s: rl.retry_after_s ?? 30 },
      { status: 429, headers: { "Retry-After": String(rl.retry_after_s ?? 30) } },
    );
  }

  const userId = userResult.data?.user?.id ?? null;

  // Optional: configure feedback logging threshold (single DB roundtrip per request).
  let feedbackEnabled = Boolean(userId);
  let feedbackLowScore = 0.55;
  if (userId) {
    try {
      const { data: cfg } = await client.rpc("get_concierge_config");
      const pf = cfg?.parse_feedback ?? cfg?.parseFeedback ?? null;
      if (pf && typeof pf === "object") {
        if (typeof pf.enabled === "boolean") feedbackEnabled = pf.enabled;
        const v = Number(pf.low_confidence_score ?? pf.lowConfidenceScore ?? feedbackLowScore);
        if (Number.isFinite(v) && v >= 0 && v <= 1.5) feedbackLowScore = v;
      }
    } catch {
      // best-effort
    }
  }

  const parsed: ParsedItem[] = itemsRaw.map((raw) => {
    const cleaned = normalizeLine(raw);
    const status = parseStatus(cleaned);
    const progress = parseProgress(cleaned);
    const hint = mediaTypeHint(cleaned);
    const flags = parseMagicFlags(cleaned);
    const yearMention = extractYearMention(cleaned);
    return {
      raw: cleaned,
      normalized: stripMeta(cleaned),
      mediaTypeHint: hint,
      status: status.status,
      completed: status.completed,
      yearMention,
      ...flags,
      ...progress,
    };
  });

  // Process all parsed items in parallel — each item searches for a different title
  // so they are fully independent of each other.
  const outItems = await Promise.all(parsed.map(async (item) => {
    try {
      const mediaType =
        scope === "anime" ? "ANIME" : scope === "manga" ? "MANGA" : item.mediaTypeHint ?? null;

      let aliasTarget: { media_type: string; media_id: number; title_raw?: string | null } | null = null;
      if (userId && item.normalized) {
        const aliasNorm = normalizeAliasKey(item.raw);
        if (aliasNorm) {
          const mediaTypeFilter = mediaType ?? null;
          const q = client
            .from("title_aliases")
            .select("media_type,media_id,title_raw,hits")
            .eq("user_id", userId)
            .eq("alias_norm", aliasNorm);
          const res = mediaTypeFilter ? await q.eq("media_type", mediaTypeFilter).maybeSingle() : await q.order("hits", { ascending: false }).limit(1).maybeSingle();
          if (!res.error && res.data?.media_id && res.data?.media_type) {
            aliasTarget = res.data;
          }
        }
      }

      const queries: { q: string; seasonBoost: boolean }[] = [{ q: item.normalized, seasonBoost: false }];
      const expanded = expandCommonAbbreviations(item.normalized);
      if (expanded && expanded !== item.normalized) {
        // Treat the expanded form as an alternate query; it tends to help new users on acronyms (AoT/JJK/etc).
        queries.push({ q: expanded, seasonBoost: false });
      }
      if (item.seasonNumber && item.normalized && (mediaType === "ANIME" || item.mediaTypeHint === "ANIME")) {
        for (const q of buildSeasonQueries(item.normalized, item.seasonNumber)) {
          queries.push({ q, seasonBoost: true });
        }
      }

      const merged = new Map<string, any>();
      let candidateError: string | null = null;

      // Run all initial search queries for this item in parallel.
      const searchLimit = Math.max(5, Math.min(limitPerItem, 12));
      const searchResults = await Promise.all(
        queries.map((q) =>
          client.rpc("search_titles", {
            p_query: q.q,
            p_media_type: mediaType,
            p_limit: searchLimit,
          }).then((res) => ({ ...res, seasonBoost: q.seasonBoost }))
        )
      );

      for (const result of searchResults) {
        if (result.error) {
          candidateError = candidateError ?? result.error.message ?? "search error";
          continue;
        }
        for (const c of (result.data ?? [])) {
          const key = `${c.media_type}:${c.media_id}`;
          const baseScore = typeof c.score === "number" ? c.score : 0;
          const seasonBoost = result.seasonBoost && item.seasonNumber ? seasonMatchBoost(String(c.title_raw ?? ""), item.seasonNumber) : 0;
          const overlapBoost = tokenOverlapBoost(item.normalized, String(c.title_raw ?? ""));
          const penalty = variantPenalty(item.raw, { title_raw: c.title_raw, variant_type: c.variant_type });
          const aliasBoost =
            aliasTarget && aliasTarget.media_type === c.media_type && Number(aliasTarget.media_id) === Number(c.media_id) ? 0.80 : 0;
          const yearBoost = item.yearMention && typeof c.year === "number" && c.year === item.yearMention ? 0.25 : 0;
          // Allow a tiny score > 1 so "Season 2" variants can beat the base title when both match at 1.0.
          const adjusted = Math.max(0, Math.min(1.25, baseScore + seasonBoost + overlapBoost + aliasBoost + yearBoost - penalty));
          const existing = merged.get(key);
          if (!existing || (existing.score ?? 0) < adjusted) {
            merged.set(key, { ...c, score: adjusted });
          }
        }
      }

      const mergedCandidates = Array.from(merged.values())
        .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
        .slice(0, limitPerItem);

      // Second pass: if confidence is low, try denoised keyword queries in parallel.
      const bestScore = typeof mergedCandidates[0]?.score === "number" ? mergedCandidates[0].score : 0;
      if (bestScore < 0.55 && item.normalized.length >= 8) {
        const denoisedQueries = buildDenoisedQueries(item.normalized);
        const denoisedResults = await Promise.all(
          denoisedQueries.map((q) =>
            client.rpc("search_titles", {
              p_query: q,
              p_media_type: mediaType,
              p_limit: searchLimit,
            })
          )
        );

        for (const { data: extra, error } of denoisedResults) {
          if (error) continue;
          for (const c of (extra ?? [])) {
            const key = `${c.media_type}:${c.media_id}`;
            const baseScore = typeof c.score === "number" ? c.score : 0;
            const penalty = variantPenalty(item.raw, { title_raw: c.title_raw, variant_type: c.variant_type });
            const adjusted = Math.max(0, Math.min(1.25, baseScore + tokenOverlapBoost(item.normalized, String(c.title_raw ?? "")) - penalty));
            const existing = merged.get(key);
            if (!existing || (existing.score ?? 0) < adjusted) {
              merged.set(key, { ...c, score: adjusted });
            }
          }
        }
      }

      const finalCandidates = Array.from(merged.values())
        .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
        .slice(0, limitPerItem);

      if (feedbackEnabled) {
        try {
          const top = finalCandidates[0] ?? null;
          const bestScore = typeof top?.score === "number" ? top.score : null;
          // Only log low-confidence/no-match items to avoid added latency.
          if (bestScore == null || bestScore < feedbackLowScore || finalCandidates.length === 0) {
            await client.rpc("log_concierge_parse_feedback", {
              p_raw: item.raw,
              p_normalized: item.normalized,
              p_alias_norm: normalizeAliasKey(item.raw),
              p_best_score: bestScore,
              p_candidates_count: finalCandidates.length,
              p_top_media_type: top?.media_type ?? null,
              p_top_media_id: top?.media_id ?? null,
            });
          }
        } catch {
          // best-effort
        }
      }

      // --- Import reconciliation: look up existing user list entry ---
      let existingEntry: {
        media_type: string;
        media_id: number;
        status: string;
        progress_episodes: number | null;
        progress_chapters: number | null;
        progress_volumes: number | null;
        rating: number | null;
        updated_at: string;
      } | null = null;

      const topCandidate = finalCandidates[0] ?? null;
      const topScore = typeof topCandidate?.score === "number" ? topCandidate.score : 0;

      if (userId && topCandidate && topScore >= 0.60) {
        try {
          const cMediaType: string = topCandidate.media_type;
          const cMediaId: number = Number(topCandidate.media_id);
          // user_id in anime_user_lists/manga_user_lists is TEXT, auth.uid() is UUID — cast to text
          const userIdText = String(userId);

          if (cMediaType === "ANIME") {
            const { data: row } = await client
              .from("anime_user_lists")
              .select("list_type,progress,rating,updated_at")
              .eq("user_id", userIdText)
              .eq("anime_id", cMediaId)
              .maybeSingle();
            if (row) {
              existingEntry = {
                media_type: "ANIME",
                media_id: cMediaId,
                status: row.list_type ?? "PLANNING",
                progress_episodes: row.progress ?? null,
                progress_chapters: null,
                progress_volumes: null,
                rating: row.rating ?? null,
                updated_at: row.updated_at ?? new Date().toISOString(),
              };
            }
          } else if (cMediaType === "MANGA") {
            const { data: row } = await client
              .from("manga_user_lists")
              .select("list_type,progress,rating,updated_at")
              .eq("user_id", userIdText)
              .eq("manga_id", cMediaId)
              .maybeSingle();
            if (row) {
              existingEntry = {
                media_type: "MANGA",
                media_id: cMediaId,
                status: row.list_type ?? "PLANNING",
                progress_episodes: null,
                progress_chapters: row.progress ?? null,
                progress_volumes: null,
                rating: row.rating ?? null,
                updated_at: row.updated_at ?? new Date().toISOString(),
              };
            }
          }
        } catch {
          // best-effort: if lookup fails, treat as no existing entry
        }
      }

      return {
        raw: item.raw,
        normalized: item.normalized,
        parsed: {
          mediaTypeHint: item.mediaTypeHint ?? null,
          status: item.status ?? null,
          progressEpisodes: item.progressEpisodes ?? null,
          progressChapters: item.progressChapters ?? null,
          progressVolumes: item.progressVolumes ?? null,
          seasonNumber: item.seasonNumber ?? null,
          episodeInSeason: item.episodeInSeason ?? null,
          caughtUp: item.caughtUp ?? null,
          lastEpisode: item.lastEpisode ?? null,
          completed: item.completed ?? null,
          yearMention: item.yearMention ?? null,
        },
        candidates: finalCandidates,
        candidateError,
        aliasNorm: userId ? normalizeAliasKey(item.raw) : null,
        existing_entry: existingEntry,
      };
    } catch (err) {
      // Per-item error handling: don't let one item's failure abort others.
      return {
        raw: item.raw,
        normalized: item.normalized,
        parsed: {
          mediaTypeHint: item.mediaTypeHint ?? null,
          status: item.status ?? null,
          progressEpisodes: item.progressEpisodes ?? null,
          progressChapters: item.progressChapters ?? null,
          progressVolumes: item.progressVolumes ?? null,
          seasonNumber: item.seasonNumber ?? null,
          episodeInSeason: item.episodeInSeason ?? null,
          caughtUp: item.caughtUp ?? null,
          lastEpisode: item.lastEpisode ?? null,
          completed: item.completed ?? null,
          yearMention: item.yearMention ?? null,
        },
        candidates: [],
        candidateError: err instanceof Error ? err.message : "unknown error",
        aliasNorm: userId ? normalizeAliasKey(item.raw) : null,
        existing_entry: null,
      };
    }
  }));

  // Lightweight run logging (best-effort; table is RLS-deny by default for users).
  if (userId) {
    try {
      await client.rpc("log_concierge_run", {
        p_kind: "parse",
        p_status: "success",
        p_input_chars: text.length,
        p_items_count: outItems.length,
      });
    } catch {
      // Best-effort metrics only.
    }
  }

  return json({ success: true, userId, items: outItems });
});
