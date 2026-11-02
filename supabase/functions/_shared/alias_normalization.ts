// The one title-alias key policy shared by concierge-parse (lookup) and concierge-apply (record) (F31).
//
// `title_aliases` rows are keyed by (user_id, alias_norm, media_type). Apply records the key of the
// import line the user confirmed; Parse looks the same line up on the next import so the confirmed
// title gets an alias boost. Both must therefore derive `alias_norm` with the SAME function:
//
//   normalizeAliasKey(raw)  the strong key (moved from concierge-parse/rules.ts, 2026-10-05): strips
//                           fillers, pronouns, status verbs (incl. started/begun, angefangen, noch dabei),
//                           explicit progress phrases (F82), rating expressions (9/10, 8 von 10, eine 8,
//                           8 Punkte, stars), progress marker words and punctuation, then folds umlauts.
//                           F82 (lead ruling): explicit progress ("episode 50", "ep 51", "e50",
//                           "bis Kapitel 200", "up to episode 5", "Folge 3 von 220", "Band 3") never enters
//                           the key, so an alias carries across progress updates; bare numbers stay
//                           ("Mob Psycho 100", "86"). Seasons are catalog IDENTITY, not progress: every
//                           notation ("season 2", "Staffel 2", "S2E5", "2x05") becomes the token "s2" and only
//                           its episode part is dropped (deviation from the literal ruling, see below).
//   aliasLookupKeys(raw)    what Parse reads: the strong key first, then the LEGACY key when different.
//
// Compatibility (no data migration): until concierge-apply switches to `normalizeAliasKey`, deployed
// Apply records `legacyApplyAliasKey` (its former local copy, kept here byte-identical). Rows already
// written with that weaker key ("attack on titan 9 10", "kämpfer") stay readable because Parse also
// looks up the legacy key; a strong-key row wins over a legacy-key row for the same line.
// Pure, no I/O, no remote imports; identity of the aliased title stays the stored (media_type, media_id).
//
// Why seasons stay in the key: the catalog keeps one entry per season, `title_aliases` maps one key to one
// media_id (PK user_id, alias_norm, media_type), an alias adds +0.80 to that title's score while a season
// match adds +0.18 (concierge-parse search_plan.ts), and the import auto-applies at >= 0.85. A season-free
// key would let an alias learned on "AoT season 2 episode 5" pull the Season 2 entry above Season 3 for
// "AoT season 3 episode 1" and write that progress onto the wrong row. To strip seasons as well, drop the
// first statement of `normalizeAliasKey` (`SEASON_TOKEN`) and add `staffel|season` to the progress units.
import { umlautFold } from "./normalization.ts";

/**
 * Explicit progress phrases: a progress unit WITH its number, with an optional leading preposition, as
 * case-insensitive regex sources. Shared by the alias key (F82) and the parser's post-participle phrase
 * rule (concierge-parse/rules.ts), so both read progress with one vocabulary. Seasons are not progress here.
 */
export const PROGRESS_PHRASE_SOURCES: readonly string[] = [
  String.raw`\b(?:(?:up\s*to|until|till|to|bis|bei)\s+)?(?:folge|episode|ep|kapitel|chapter|ch|band|volume|vol)\s*\d{1,5}\b(?:\s+(?:von|of)\s+\d{1,5}\b)?`,
  String.raw`\b\d{1,5}\s+(?:von|of)\s+\d{1,5}\s*(?:folgen|folge|episodes|episode|eps|ep|kapitel|chapters|chapter|bände|baende|band|volumes|volume)\b`,
  String.raw`\be\d{1,4}\b`,
];
const PROGRESS_PHRASE_RE = new RegExp(PROGRESS_PHRASE_SOURCES.join("|"), "giu");

/** Every season notation (SxE, NxM, "season N", "Staffel N") becomes the identity token "s{N}". */
const SEASON_TOKEN: Array<[RegExp, (m: string, n: string) => string]> = [
  [/\bs(\d{1,2})\s*e\d{1,4}\b/giu, (_m, n) => ` s${Number(n)} `],
  [/\b(\d{1,2})\s*x\s*\d{1,4}\b/giu, (_m, n) => ` s${Number(n)} `],
  [/\b(?:season|staffel)\s*(\d{1,2})\b/giu, (_m, n) => ` s${Number(n)} `],
];

/** The strong alias key: the one key Parse looks up first and Apply records. Max 160 chars. */
export function normalizeAliasKey(raw: string): string {
  let s = String(raw ?? "").toLowerCase();
  s = s.replace(/\u00a0/g, " ");
  // F82: season identity token first, then explicit progress phrases (a marker with its number).
  for (const [re, token] of SEASON_TOKEN) s = s.replace(re, token);
  s = s.replace(PROGRESS_PHRASE_RE, " ");
  // strip filler + verbs/status
  s = s.replace(/\b(um+|uh+|erm+|eh+|like|also|äh+|ae+h+|so|halt)\b/giu, " ");
  s = s.replace(/\b(i\s+have|i'?m|im|i\s+am|i)\b/giu, " ");
  s = s.replace(/\b(ich\s+habe|ich\s+hab|ich|bin)\b/giu, " ");
  s = s.replace(
    /\b(watched|watching|finished|completed|dropped|paused|planning|read|reading|caught up|up to date|seen|saw|started|begun)\b/giu,
    " ",
  );
  s = s.replace(
    /\b(geschaut|gesehen|gelesen|fertig|abgeschlossen|beendet|abgebrochen|pausiert|geplant|aktuell|komplett|vollständig|vollstaendig|angefangen|noch dabei)\b/giu,
    " ",
  );
  // strip rating patterns
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s*\/\s*\d{1,2}\b/giu, " ");
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s+(?:von|out of)\s+\d{1,2}\b/giu, " ");
  s = s.replace(/\beine?\s+\d{1,2}\b/giu, " ");
  s = s.replace(/\b\d{1,2}(?:\.\d)?\s+(?:punkte|points?|stars?|sterne?)\b/giu, " ");
  s = s.replace(/⭐/g, " ");
  // strip progress marker words left without a number (SxE / NxM are season tokens by now)
  s = s.replace(/\b(?:season|staffel|episode|ep|folge|chapter|ch|kapitel|volume|vol|band)\b/giu, " ");
  // keep only letters/numbers/spaces (unicode)
  s = s.replace(/[^\p{L}\p{N}\s]+/gu, " ");
  // Fold umlauts for consistent alias matching
  s = umlautFold(s);
  s = s.replace(/\s+/g, " ").trim();
  return s.slice(0, 160);
}

/**
 * The key deployed concierge-apply has written so far (its former `normalizeAliasKey`, verbatim from
 * concierge-apply/apply_plan.ts on 2026-10-05). READ-COMPATIBILITY ONLY: never record new rows with it.
 */
export function legacyApplyAliasKey(raw: string): string {
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

/**
 * Keys Parse looks a line up with, in preference order: the strong key, then the legacy Apply key when
 * it differs. Empty keys are dropped; the result is deduplicated (at most two keys).
 */
export function aliasLookupKeys(raw: string): string[] {
  const keys: string[] = [];
  for (const key of [normalizeAliasKey(raw), legacyApplyAliasKey(raw)]) {
    if (key && !keys.includes(key)) keys.push(key);
  }
  return keys;
}
