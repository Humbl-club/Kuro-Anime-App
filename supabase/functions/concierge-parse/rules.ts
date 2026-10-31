// Pure parsing / normalization rules of concierge-parse.
//
// Extracted MECHANICALLY from index.ts (2026-10-05, E7): every function, constant and type
// below is the production code moved verbatim with an `export` keyword added. `parseLine`
// is the former per-line body of `itemsRaw.map(...)` in the handler, unchanged.
// Only local import: ../_shared/alias_normalization.ts (the one alias key policy shared with
// concierge-apply, F31, re-exported here for the parse handler; and its progress-phrase vocabulary, F82).
// No I/O, no LLM: the parse handler and the Deno corpus tests share this code.
// Rule repairs since the move (F27/F29, 2026-10-05) are marked "F27"/"F29" at the changed lines.
import { PROGRESS_PHRASE_SOURCES } from "../_shared/alias_normalization.ts";
export { normalizeAliasKey } from "../_shared/alias_normalization.ts";

export type MediaType = "ANIME" | "MANGA";
export type ListStatus = "WATCHING" | "READING" | "PLANNING" | "COMPLETED" | "DROPPED" | "PAUSED";

export type Ambiguity = {
  kind: "status_unclear" | "unit_unclear" | "intent_unclear";
  options: string[];
  suggested_question: string;
  suggested_question_de: string;
  title_context?: string;
  number_context?: string;
} | null;

export type ParsedItem = {
  raw: string;
  normalized: string;
  mediaTypeHint?: MediaType;
  status?: ListStatus;
  progressEpisodes?: number;
  progressChapters?: number;
  progressVolumes?: number;
  progressTotal?: number;
  progressUnit?: string;
  seasonNumber?: number;
  episodeInSeason?: number;
  caughtUp?: boolean;
  lastEpisode?: boolean;
  completed?: boolean;
  yearMention?: number;
  rating?: number;
  ambiguity?: Ambiguity;
};

export function romanToInt(input: string): number | null {
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

export function expandCommonAbbreviations(title: string): string | null {
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

export function normalizeLine(s: string) {
  return s
    .trim()
    .replace(/\u00A0/g, " ")
    .replace(/\s+/g, " ");
}

// F27 + review R1: the phrases kept from what follows a German participle ("... gelesen bis Kapitel 200",
// "... gesehen, 9/10", "... gesehen bis zur letzten Folge"): progress, rating and completion phrases only,
// in order. Free commentary ("und fand es super", ", war ok", "aber ...") never reaches the title query.
// Progress phrases come from the shared vocabulary (PROGRESS_PHRASE_SOURCES, also used by the alias key);
// seasons, ratings and completion phrases are added here. Progress precedes ratings so "3 von 12 Folgen"
// is read as progress, not as the rating "3 von 12".
const TRAILING_SLOT_PHRASE_RE = new RegExp(
  [
    String.raw`\bbis\s+(?:zur|zum)\s+(?:letzten\s+folge|ende)\b`,
    ...PROGRESS_PHRASE_SOURCES,
    String.raw`\b(?:(?:bis|bei)\s+)?(?:staffel|season)\s*\d{1,5}\b(?:\s+(?:von|of)\s+\d{1,5}\b)?`,
    String.raw`\bs\d{1,2}\s*e\d{1,4}\b`,
    String.raw`\b\d{1,2}\s*x\s*\d{1,4}\b`,
    String.raw`\b\d{1,2}(?:\.\d)?\s*/\s*\d{1,2}\b`,
    String.raw`\b\d{1,2}(?:\.\d)?\s+(?:von|out of)\s+\d{1,2}\b`,
    String.raw`\beine?\s+\d{1,2}(?:\.\d)?\b`,
    String.raw`\b\d{1,2}(?:\.\d)?\s+(?:punkte|points?|stars?|sterne?)\b`,
    "⭐+",
    String.raw`\b(?:vollständig|vollstaendig)\b`,
  ].join("|"),
  "gi",
);

/** The progress/rating/completion phrases in `rest`, joined by spaces ("" when there are none). */
export function trailingSlotPhrases(rest: string): string {
  return (String(rest ?? "").match(TRAILING_SLOT_PHRASE_RE) ?? []).join(" ");
}

export function splitItems(text: string): string[] {
  const normalized = text.replace(/\r\n/g, "\n").trim();
  if (!normalized) return [];

  // F71: a '.' after an honorific (Dr. Stone, Mr. Osomatsu) or 'No.' before a number (Kaiju No. 8)
  // is title punctuation, not a sentence end.
  const splitOnClauseBoundaries = (s: string) =>
    s
      .split(/[\n]+|(?<=[.!?;])(?<!\b(?:dr|mr|mrs|ms)\.)(?!(?<=\bno\.)\s+\d)\s+/gi)
      .flatMap((part) => part.split(/,\s*(?=(?:i\s+|i'?m\s+|i\s+am\s+|ich\s+))/i))
      .map((x) => x.trim())
      .filter(Boolean);

  // F27: a ';' glued between two non-space characters is part of a title (Steins;Gate,
  // Robotics;Notes, Chaos;Head); only a ';' next to whitespace or at the end separates titles.
  const splitTitleList = (tail: string) =>
    tail
      .split(/\s*(?:,|(?<!\S);|;(?!\S)|\bund\b|\band\b|&|\u2022)\s*/i)
      .map((x) => x.trim())
      .filter(Boolean);

  const englishVerbRe =
    /^(?<verb>(?:i\s+(?:(?:just|recently|only)\s+)?(?:watched|finished|completed|dropped|paused|started|read)|i\s+have\s+(?:watched|seen|read)|i\s+am\s+(?:watching|reading)|i'?m\s+(?:watching|reading)|im\s+(?:watching|reading)|watching|reading))\s+(?<tail>.+)$/i;
  const germanPresentVerbRe =
    /^(?<verb>ich\s+(?:schaue|gucke|sehe|lese|bin)\b)\s+(?<tail>.+)$/i;
  // F27: `rest` keeps what follows the participle ("... gelesen bis Kapitel 200").
  const germanPerfectVerbRe =
    /^(?<head>ich\s+(?:habe|hab))\s+(?<tail>.+?)\s+(?<past>gesehen|geschaut|gelesen)\b(?<rest>.*)$/i;

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
        // F27: the slot phrases after the participle (progress/rating/completion, never commentary: R1)
        // are kept, attached to the LAST title only, as the English path does with a trailing phrase
        // ("A and B to the end"): other titles then ask for their status instead of silently receiving
        // another title's progress.
        const trailing = trailingSlotPhrases(germanPerfect.groups.rest ?? "");
        titles.forEach((t, idx) => {
          if (!t) return;
          const tail = idx === titles.length - 1 && trailing ? ` ${trailing}` : "";
          out.push(`${germanPerfect.groups?.head} ${t} ${germanPerfect.groups?.past}${tail}`.trim());
        });
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

/** Soft partial-progress words ("halfway", "zur Hälfte", "teilweise"): the user says they are NOT done. */
export function hasSoftPartialProgress(raw: string): boolean {
  const s = raw.toLowerCase();
  return /\b(halfway|half way|midway|partway|some of it|a bit|a few (?:eps|episodes|chapters))\b/.test(s) ||
    /\b(halb|hälfte|haelfte|zur hälfte|zur haelfte|teilweise|ein bisschen)\b/.test(s);
}

export function parseStatus(raw: string): { status?: ListStatus; completed?: boolean } {
  const s = raw.toLowerCase();
  const explicitCompletion =
    /\b(last episode|to the end|all of it|every season|fully|entirely|whole thing)\b/.test(s) ||
    /\b(bis zur letzten folge|bis zum ende|alles gesehen|komplett gesehen|vollständig|vollstaendig)\b/.test(s);
  const hasPartialProgress =
    /\b(?:until|till|up to|upto|to|bis)\b/.test(s) &&
    /\b(?:season|staffel|episode|ep|folge|chapter|ch|kapitel|band|vol|volume|\d{1,2}\s*x\s*\d{1,4}|s\d{1,2}\s*e\d{1,4})\b/.test(s);
  const hasSoftPartial = hasSoftPartialProgress(s);
  // F29 (parser_en_046): an explicit position inside the title (episode/chapter/volume N, SxE, NxM)
  // after "I finished" names where the user is, not the end of the title; COMPLETED would be a
  // stronger write than the text supports, so it reads as in-progress like the until/bis phrases.
  const hasPositionProgress =
    /\b(?:episode|ep|folge|chapter|ch|kapitel|volume|vol|band)\s*(?:\d{1,5}|one|two|three|four|five|six|seven|eight|nine|ten|eins|zwei|drei|vier|fünf|funf|sechs|sieben|acht|neun|zehn)\b/.test(s) ||
    /\bs\d{1,2}\s*e\d{1,4}\b/.test(s) ||
    /\b\d{1,2}\s*x\s*\d{1,4}\b/.test(s);

  // English + slang
  if (/\b(caught up|up to date|up-to-date|latest|current)\b/.test(s)) return { status: "WATCHING" };
  const iFinished =
    /\b(i\s+(?:just\s+)?finished|i\s+(?:just\s+)?completed)\b/.test(s);
  const iWatched =
    /\b(i\s+(?:just\s+)?watched|i\s+(?:just\s+)?saw|i\s+have\s+watched|i\s+have\s+seen)\b/.test(s);
  const iRead =
    /\b(i\s+(?:just\s+)?read|i\s+have\s+read)\b/.test(s);
  const iStarted =
    /\b(i\s+(?:just\s+)?started|i\s+(?:just\s+)?begun|i\s+have\s+started)\b/.test(s);

  if (iFinished) {
    if ((hasPartialProgress || hasSoftPartial || hasPositionProgress) && !explicitCompletion) return { status: "WATCHING" };
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
  if (iStarted) {
    // "I started X" → WATCHING unless manga context
    if (/\b(read|reading|manga|manhwa|manhua|chapter|ch|volume|vol|band|kapitel)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
  if (/\b(i'?m\s+watching|i\s+am\s+watching)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(i'?m\s+reading|i\s+am\s+reading)\b/.test(s)) return { status: "READING" };
  if (/\b(completed|finished|done)\b/.test(s)) {
    // F72: same partial/position rule as the "I finished" branch ("finished AoT up to episode 5",
    // "Naruto episode 220 completed" name a position, so the weaker in-progress write).
    if ((hasPartialProgress || hasSoftPartial || hasPositionProgress) && !explicitCompletion) return { status: "WATCHING" };
    return { status: "COMPLETED", completed: true };
  }
  if (/\b(started|begun)\b/.test(s)) {
    if (/\b(read|reading|manga|manhwa|manhua|chapter|ch|volume|vol|band|kapitel)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
  if (/\b(dropped)\b/.test(s)) return { status: "DROPPED" };
  if (/\b(paused|on hold|on-hold|hiatus)\b/.test(s)) return { status: "PAUSED" };
  if (/\b(planning|plan to watch|plan to read|ptw|ptr)\b/.test(s)) return { status: "PLANNING" };
  if (/\b(reading)\b/.test(s)) return { status: "READING" };
  if (/\b(watching)\b/.test(s)) return { status: "WATCHING" };

  // German
  if (/\b(aktuell|auf dem neuesten stand|up to date|auf dem aktuellen stand)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(ich\s+habe|ich\s+hab)\b/.test(s) && /\b(geschaut|gesehen|gelesen)\b/.test(s)) {
    // F29 (parser_de_050): explicit completion wins over a partial phrase, as in the English branches
    // ("bis zur letzten Folge" contains "bis ... Folge" and used to read as partial progress).
    if ((hasPartialProgress || hasSoftPartial) && !explicitCompletion) {
      if (/\b(gelesen)\b/.test(s)) return { status: "READING" };
      return { status: "WATCHING" };
    }
    if (explicitCompletion) return { status: "COMPLETED", completed: true };
    // "Ich habe X geschaut" is ambiguous; default to WATCHING unless explicit completion.
    if (/\b(gelesen)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
  if (/\b(ich\s+(?:schaue|gucke|sehe)|gerade\s+am\s+schauen|am\s+schauen|schaue\s+gerade)\b/.test(s)) return { status: "WATCHING" };
  if (/\b(ich\s+lese|gerade\s+am\s+lesen|am\s+lesen|lese\s+gerade)\b/.test(s)) return { status: "READING" };
  if (/\b(noch\s+dabei)\b/.test(s)) {
    if (/\b(lese|lesen|gelesen|manga|manhwa|manhua|kapitel|band)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
  if (/\b(fertig|abgeschlossen|beendet|zu ende|komplett)\b/.test(s)) {
    // F72 (German twin): "Naruto Folge 220 fertig" names a position; "zu Ende" / "komplett" state the
    // completion themselves and stay COMPLETED.
    const statedComplete = explicitCompletion || /\b(zu ende|komplett)\b/.test(s);
    if ((hasPartialProgress || hasSoftPartial || hasPositionProgress) && !statedComplete) return { status: "WATCHING" };
    return { status: "COMPLETED", completed: true };
  }
  if (/\b(abgebrochen|gedroppt|droppe|droppen)\b/.test(s)) return { status: "DROPPED" };
  if (/\b(pausiert|pause|auf eis)\b/.test(s)) return { status: "PAUSED" };
  if (/\b(plane|geplant|will schauen|will sehen|möchte schauen|möchte sehen|will lesen|möchte lesen)\b/.test(s)) return { status: "PLANNING" };
  if (/\b(angefangen)\b/.test(s)) {
    if (/\b(lese|lesen|gelesen|manga|manhwa|manhua|kapitel|band)\b/.test(s)) return { status: "READING" };
    return { status: "WATCHING" };
  }
  if (/\b(lese|am lesen|gerade am lesen)\b/.test(s)) return { status: "READING" };
  if (/\b(schaue|gucke|sehe|am schauen|gerade am schauen)\b/.test(s)) return { status: "WATCHING" };
  // F29 (parser_de_018): an explicit completion phrase with no other status rule ("Mob Psycho 100 alles
  // gesehen", "Naruto fully") is a completion, not a title-only line; reached only by lines that
  // previously got no status at all. Review A3: only for a list-style "<title> <completion>" line: a
  // subject pronoun, a wish/plan verb or a question ("I want to watch all of it", "should I ... ?") is
  // not a report of having finished, so those lines keep no status (the title-only question asks).
  const listStyleLine =
    !/\b(i|i'm|im|we|you|ich|wir|du|want|wanna|would|will|plan|should|möchte|moechte|würde|wuerde|soll|sollte)\b/.test(s) &&
    !s.includes("?");
  if (explicitCompletion && listStyleLine) return { status: "COMPLETED", completed: true };
  return {};
}

export function parseMagicFlags(raw: string): Pick<ParsedItem, "caughtUp" | "lastEpisode" | "completed"> {
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

export function parseRating(raw: string): number | undefined {
  const s = raw.toLowerCase();

  // Star emoji counting: ⭐⭐⭐ = 3
  const starEmojis = (raw.match(/⭐/g) ?? []).length;
  if (starEmojis >= 1 && starEmojis <= 10) return starEmojis;

  // "X/10" or "X/Y" rating format (e.g. 9/10, 8.5/10)
  const slashRating = s.match(/\b(\d{1,2}(?:\.\d)?)\s*\/\s*(\d{1,2})\b/);
  if (slashRating) {
    const num = parseFloat(slashRating[1]);
    const denom = parseInt(slashRating[2], 10);
    if (denom > 0 && num >= 0 && num <= denom) {
      return Math.round((num / denom) * 10 * 10) / 10; // Normalize to 0-10 scale
    }
  }

  // "X von 10" / "X out of 10"
  const outOfRating = s.match(/\b(\d{1,2}(?:\.\d)?)\s+(?:von|out of)\s+(\d{1,2})\b/);
  if (outOfRating) {
    const num = parseFloat(outOfRating[1]);
    const denom = parseInt(outOfRating[2], 10);
    if (denom > 0 && num >= 0 && num <= denom) {
      return Math.round((num / denom) * 10 * 10) / 10;
    }
  }

  // "eine 8" / "eine 9" (DE casual rating)
  const eineRating = s.match(/\beine?\s+(\d{1,2}(?:\.\d)?)\b/);
  if (eineRating) {
    const val = parseFloat(eineRating[1]);
    if (val >= 0 && val <= 10) return val;
  }

  // "8 Punkte" / "8 points"
  const punkteRating = s.match(/\b(\d{1,2}(?:\.\d)?)\s+(?:punkte|points?)\b/);
  if (punkteRating) {
    const val = parseFloat(punkteRating[1]);
    if (val >= 0 && val <= 10) return val;
  }

  // "8 stars" / "8 Sterne"
  const starsRating = s.match(/\b(\d{1,2}(?:\.\d)?)\s+(?:stars?|sterne?)\b/);
  if (starsRating) {
    const val = parseFloat(starsRating[1]);
    if (val >= 0 && val <= 10) return val;
  }

  return undefined;
}

export function parseProgress(
  raw: string,
): Pick<
  ParsedItem,
  "progressEpisodes" | "progressChapters" | "progressVolumes" | "progressTotal" | "progressUnit" | "seasonNumber" | "episodeInSeason"
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

  // "bis Folge X" / "bei Episode X" / "bei Folge X" (DE preposition + unit)
  const bisEp = s.match(/\b(?:bis|bei)\s+(?:folge|episode|ep)\s*(\d{1,4})\b/);
  if (bisEp && !out.progressEpisodes) out.progressEpisodes = parseInt(bisEp[1], 10);
  const bisKap = s.match(/\b(?:bis|bei)\s+(?:kapitel|chapter|ch)\s*(\d{1,5})\b/);
  if (bisKap && !out.progressChapters) out.progressChapters = parseInt(bisKap[1], 10);
  const bisBand = s.match(/\b(?:bis|bei)\s+(?:band|volume|vol)\s*(\d{1,4})\b/);
  if (bisBand && !out.progressVolumes) out.progressVolumes = parseInt(bisBand[1], 10);

  // "X of Y episodes/chapters/volumes" / "X von Y Folgen/Kapitel/Bände"
  const xOfYEp = s.match(/\b(\d{1,4})\s+(?:of|von)\s+(\d{1,4})\s*(?:episodes?|folgen?|eps?)\b/);
  if (xOfYEp) {
    out.progressEpisodes = out.progressEpisodes ?? parseInt(xOfYEp[1], 10);
    out.progressTotal = parseInt(xOfYEp[2], 10);
    out.progressUnit = "episode";
  }
  const xOfYCh = s.match(/\b(\d{1,5})\s+(?:of|von)\s+(\d{1,5})\s*(?:chapters?|kapitel)\b/);
  if (xOfYCh) {
    out.progressChapters = out.progressChapters ?? parseInt(xOfYCh[1], 10);
    out.progressTotal = parseInt(xOfYCh[2], 10);
    out.progressUnit = "chapter";
  }
  const xOfYVol = s.match(/\b(\d{1,4})\s+(?:of|von)\s+(\d{1,4})\s*(?:volumes?|bände|baende|band)\b/);
  if (xOfYVol) {
    out.progressVolumes = out.progressVolumes ?? parseInt(xOfYVol[1], 10);
    out.progressTotal = parseInt(xOfYVol[2], 10);
    out.progressUnit = "volume";
  }

  // "Folge X von Y" / "Episode X of Y" (unit before numbers)
  const folgeXvonY = s.match(/\b(?:folge|episode|ep)\s*(\d{1,4})\s+(?:von|of)\s+(\d{1,4})\b/);
  if (folgeXvonY) {
    out.progressEpisodes = out.progressEpisodes ?? parseInt(folgeXvonY[1], 10);
    out.progressTotal = out.progressTotal ?? parseInt(folgeXvonY[2], 10);
    out.progressUnit = out.progressUnit ?? "episode";
  }
  const kapXvonY = s.match(/\b(?:kapitel|chapter|ch)\s*(\d{1,5})\s+(?:von|of)\s+(\d{1,5})\b/);
  if (kapXvonY) {
    out.progressChapters = out.progressChapters ?? parseInt(kapXvonY[1], 10);
    out.progressTotal = out.progressTotal ?? parseInt(kapXvonY[2], 10);
    out.progressUnit = out.progressUnit ?? "chapter";
  }

  // Infer progressUnit from what was detected
  if (!out.progressUnit) {
    if (out.progressEpisodes != null) out.progressUnit = "episode";
    else if (out.progressChapters != null) out.progressUnit = "chapter";
    else if (out.progressVolumes != null) out.progressUnit = "volume";
  }

  return out;
}

export function mediaTypeHint(raw: string): MediaType | undefined {
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
export const YEAR_MENTION_MIN = 1960;
export const YEAR_MENTION_MAX = 2030;

export function isPlausibleYearMention(y: number): boolean {
  return Number.isFinite(y) && y >= YEAR_MENTION_MIN && y <= YEAR_MENTION_MAX;
}

export function extractYearMention(raw: string): number | undefined {
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

export function stripMeta(raw: string): string {
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
  // F72: "up to" / "to" before a progress unit and number is progress wording, not title ("AoT up to episode 5").
  s = s.replace(/\b(?:up\s*to|to)\b(?=\s+(?:season|staffel|episode|ep|folge|chapter|ch|kapitel|volume|vol|band)\s*\d)/gi, " ");
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
  // Strip rating patterns so they don't pollute title search.
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s*\/\s*\d{1,2}\b/gi, " ");
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s+(?:von|out of)\s+\d{1,2}\b/gi, " ");
  s = s.replace(/\beine?\s+\d{1,2}(?:\.\d)?\b/gi, " ");
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s+(?:punkte|points?|stars?|sterne?)\b/gi, " ");
  s = s.replace(/⭐/g, " ");
  // Strip new status keywords from title.
  s = s.replace(/\b(started|begun|angefangen|noch dabei)\b/gi, " ");
  // Strip "bis/bei" progress phrases from title.
  s = s.replace(/\b(?:bis|bei)\s+(?:folge|episode|ep|kapitel|chapter|ch|band|volume|vol)\s*\d{1,5}\b/gi, " ");
  // Strip "X of/von Y" progress phrases.
  s = s.replace(/\b\d{1,5}\s+(?:of|von)\s+\d{1,5}\s*(?:episodes?|folgen?|eps?|chapters?|kapitel|volumes?|bände|baende|band)\b/gi, " ");
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

export function detectAmbiguity(item: ParsedItem): Ambiguity {
  const s = item.raw.toLowerCase();
  const hasStatus = item.status != null;
  const hasProgress = (item.progressEpisodes != null || item.progressChapters != null || item.progressVolumes != null);
  const hasRating = item.rating != null;
  const titleContext = item.normalized || item.raw;
  const numberContext = firstNumber(item.raw);

  // "watched" / "geschaut" / "gesehen" without explicit completion signal
  // The parser defaults these to WATCHING, but the user may mean COMPLETED.
  // F29 (parser_en_055/de_046/de_052): a soft partial word ("halfway", "zur Hälfte", "teilweise")
  // already answers "Finished or still watching?" (still watching), so it is not asked again.
  const softPartial = hasSoftPartialProgress(s);
  const ambiguousWatched =
    (/\b(watched|saw|geschaut|gesehen)\b/.test(s) && !(/\b(i'?m\s+watching|i\s+am\s+watching|schaue\s+gerade|gerade\s+am\s+schauen|noch\s+dabei)\b/.test(s))) &&
    item.status === "WATCHING" &&
    !item.completed && !item.caughtUp && !item.lastEpisode &&
    !hasProgress && !softPartial;

  // "gelesen" / "read" without explicit completion signal
  const ambiguousRead =
    (/\b(read|gelesen)\b/.test(s) && !(/\b(i'?m\s+reading|i\s+am\s+reading|lese\s+gerade|gerade\s+am\s+lesen|noch\s+dabei)\b/.test(s))) &&
    item.status === "READING" &&
    !item.completed &&
    !hasProgress && !softPartial;

  if (ambiguousWatched || ambiguousRead) {
    return {
      kind: "status_unclear",
      options: ["COMPLETED", ambiguousRead ? "READING" : "WATCHING"],
      suggested_question: ambiguousRead ? "Finished or still reading?" : "Finished or still watching?",
      suggested_question_de: ambiguousRead ? "Fertig gelesen oder noch dabei?" : "Fertig geschaut oder noch dabei?",
      title_context: titleContext,
    };
  }

  // Progress number without clear unit context
  // A bare number attached to progress without a recognized unit keyword
  if (hasProgress && !item.progressUnit && !item.seasonNumber) {
    return {
      kind: "unit_unclear",
      options: ["episode", "season", "chapter", "volume"],
      suggested_question: "Which unit? Episode, season, chapter, or volume?",
      suggested_question_de: "Welche Einheit? Folge, Staffel, Kapitel oder Band?",
      title_context: titleContext,
      number_context: numberContext != null ? String(numberContext) : undefined,
    };
  }

  // Status + bare number without unit (e.g. "watched 203", "ich habe 12 gesehen").
  // Ask the user what the number refers to.
  const hasUnitKeyword = /\b(ep|episode|folge|season|staffel|chapter|ch|kapitel|volume|vol|band)\b/i.test(s);
  const numericHint =
    numberContext != null &&
    (item.yearMention == null || numberContext !== item.yearMention);
  // F29 (parser_de_018): not for a completion. A bare number cannot refine a COMPLETED write (Apply
  // takes completed progress from the catalog total), so on numbered titles ("Mob Psycho 100 alles
  // gesehen", "86 completed") the question was moot and a unit answer wrote title digits as progress.
  if (hasStatus && item.status !== "COMPLETED" && !hasProgress && !hasRating && numericHint && !hasUnitKeyword) {
    return {
      kind: "unit_unclear",
      options: ["episode", "season", "chapter", "volume"],
      suggested_question: "Does that number mean episode, season, chapter, or volume?",
      suggested_question_de: "Meint diese Zahl Folge, Staffel, Kapitel oder Band?",
      title_context: titleContext,
      number_context: String(numberContext),
    };
  }

  // Title-only without status, progress, or rating → unclear intent
  if (!hasStatus && !hasProgress && !hasRating && item.normalized.length > 0) {
    return {
      kind: "intent_unclear",
      options: ["import", "recommend_seed"],
      suggested_question: "Add to your list, or use as a recommendation seed?",
      suggested_question_de: "Zur Liste hinzufügen oder als Empfehlungsgrundlage nutzen?",
      title_context: titleContext,
    };
  }

  return null;
}

export function parseClarificationMap(input: unknown): Record<string, string> {
  if (!input || typeof input !== "object" || Array.isArray(input)) return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(input as Record<string, unknown>)) {
    if (typeof v !== "string") continue;
    const key = String(k).trim();
    const val = v.trim();
    if (!key || !val) continue;
    out[key] = val;
  }
  return out;
}

export function firstNumber(raw: string): number | undefined {
  const m = raw.match(/\b(\d{1,5})\b/);
  if (!m) return undefined;
  const n = parseInt(m[1], 10);
  return Number.isFinite(n) && n > 0 ? n : undefined;
}

export function applyClarification(item: ParsedItem, clarification: Record<string, string>): ParsedItem {
  if (!item.ambiguity) return item;

  const kind = item.ambiguity.kind;
  const pick = clarification[kind]?.toLowerCase();
  if (!pick) return item;

  if (kind === "status_unclear") {
    // Accept parser UI values plus common aliases.
    if (pick === "completed" || pick === "fertig") {
      item.status = "COMPLETED";
      item.completed = true;
      item.ambiguity = null;
    } else if (pick === "watching" || pick === "current" || pick === "noch dabei") {
      const lower = item.raw.toLowerCase();
      const looksLikeReading =
        item.mediaTypeHint === "MANGA" ||
        /\b(read|reading|gelesen|lese|kapitel|chapter|band|volume|manga|manhwa|manhua)\b/.test(lower);
      item.status = looksLikeReading ? "READING" : "WATCHING";
      item.completed = false;
      item.ambiguity = null;
    } else if (pick === "reading" || pick === "lesend") {
      item.status = "READING";
      item.completed = false;
      item.ambiguity = null;
    }
    return item;
  }

  if (kind === "unit_unclear") {
    const unit = pick;
    const n = firstNumber(item.raw);
    if (!n) return item;

    if (unit === "episode" || unit === "ep" || unit === "folge") {
      item.progressEpisodes = n;
      item.progressUnit = "episode";
      item.ambiguity = null;
    } else if (unit === "chapter" || unit === "ch" || unit === "kapitel") {
      item.progressChapters = n;
      item.progressUnit = "chapter";
      item.ambiguity = null;
    } else if (unit === "volume" || unit === "vol" || unit === "band") {
      item.progressVolumes = n;
      item.progressUnit = "volume";
      item.ambiguity = null;
    } else if (unit === "season" || unit === "staffel") {
      item.seasonNumber = n;
      item.progressUnit = "season";
      item.ambiguity = null;
    }
    return item;
  }

  if (kind === "intent_unclear") {
    // Parse endpoint can only return import-ready rows.
    // If user clarifies import, pin a safe default status.
    if (pick === "import") {
      item.status = item.status ?? "PLANNING";
      item.ambiguity = null;
    }
    return item;
  }

  return item;
}

export function tokenOverlapBoost(query: string, title: string): number {
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

export function variantPenalty(query: string, candidate: { title_raw?: string; variant_type?: string }): number {
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

export function seasonMatchBoost(titleRaw: string, seasonNumber: number): number {
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

export function buildSeasonQueries(baseTitle: string, seasonNumber: number): string[] {
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

export function buildDenoisedQueries(title: string): string[] {
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

/** Parse one split line exactly as the handler does (normalize, extract slots, ambiguity, clarification). */
export function parseLine(raw: string, clarification: Record<string, string>): ParsedItem {
  const cleaned = normalizeLine(raw);
  const status = parseStatus(cleaned);
  const progress = parseProgress(cleaned);
  const hint = mediaTypeHint(cleaned);
  const flags = parseMagicFlags(cleaned);
  const yearMention = extractYearMention(cleaned);
  const rating = parseRating(cleaned);
  const item: ParsedItem = {
    raw: cleaned,
    normalized: stripMeta(cleaned),
    mediaTypeHint: hint,
    status: status.status,
    completed: status.completed,
    yearMention,
    rating,
    ...flags,
    ...progress,
  };
  // Locked product rule: "Finished" / "fertig" with no title stores no status (nothing to write).
  if (!item.normalized.trim()) {
    item.status = undefined;
    item.completed = undefined;
  }
  item.ambiguity = detectAmbiguity(item);
  return applyClarification(item, clarification);
}
