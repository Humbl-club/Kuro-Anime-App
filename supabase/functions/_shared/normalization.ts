// Shared text normalization utilities for EN/DE bilingual concierge.
// Used by concierge-parse, concierge-recommend, and concierge-resolve edge functions.
// The Swift mirror (Kuro/Services/TextNormalization.swift) MUST produce identical output.

// ---------------------------------------------------------------------------
// Umlaut folding
// ---------------------------------------------------------------------------

/**
 * Fold German umlauts and Eszett to ASCII equivalents.
 * Handles both lowercase and uppercase forms.
 */
export function umlautFold(text: string): string {
  return text
    .replace(/ä/g, "ae")
    .replace(/ö/g, "oe")
    .replace(/ü/g, "ue")
    .replace(/ß/g, "ss")
    .replace(/Ä/g, "Ae")
    .replace(/Ö/g, "Oe")
    .replace(/Ü/g, "Ue");
}

// ---------------------------------------------------------------------------
// Text normalization
// ---------------------------------------------------------------------------

/**
 * Normalize text for comparison: lowercase, collapse whitespace, strip
 * punctuation but preserve hyphens in compound words (e.g. "Lieblings-Anime").
 */
export function normalizeText(text: string): string {
  return text
    .toLowerCase()
    // Replace underscores and slashes/backslashes with space
    .replace(/[_/\\]+/g, " ")
    // Strip punctuation EXCEPT hyphens between word characters
    // First, protect hyphens between word chars by replacing with placeholder
    .replace(/(\p{L})-(\p{L})/gu, "$1\x00$2")
    // Strip remaining punctuation (non-letter, non-number, non-space)
    .replace(/[^\p{L}\p{N}\s\x00]/gu, " ")
    // Restore protected hyphens
    .replace(/\x00/g, "-")
    // Collapse whitespace
    .replace(/\s+/g, " ")
    .trim();
}

// ---------------------------------------------------------------------------
// German inflection normalization
// ---------------------------------------------------------------------------

// Common DE suffixes to strip, ordered longest-first to avoid partial matches.
const DE_SUFFIXES = [
  "ungen", // Empfehlungen → Empfehl
  "keit",  // Einsamkeit → Einsam
  "heit",  // Freiheit → Frei
  "ung",   // Empfehlung → Empfehl
  "en",    // geschauten → geschaut
  "er",    // schneller → schnell
  "es",    // großes → groß
  "em",    // großem → groß
  "e",     // große → groß
];

/**
 * Strip common German inflection suffixes to approximate the lemma.
 * Only strips if the remaining stem is longer than 4 characters to avoid
 * over-stripping short words (e.g. "Rede" should NOT become "R").
 * For compound words (hyphenated), each part is normalized independently.
 */
export function germanInflectionNormalize(word: string): string {
  // Handle compound words: normalize each part independently
  if (word.includes("-")) {
    return word.split("-").map((part) => germanInflectionNormalize(part)).join("-");
  }
  if (word.length <= 4) return word;
  for (const suffix of DE_SUFFIXES) {
    if (word.endsWith(suffix) && (word.length - suffix.length) > 4) {
      return word.slice(0, -suffix.length);
    }
  }
  return word;
}

// ---------------------------------------------------------------------------
// Stopword filtering
// ---------------------------------------------------------------------------

const STOPWORDS_DE = new Set([
  "der", "die", "das", "den", "dem", "des",
  "ein", "eine", "einen", "einem", "eines", "einer",
  "und", "oder", "ist", "sind",
  "war", "hat", "haben", "für", "fuer", "mit", "auf", "von", "zu",
  "aus", "nach", "bei", "durch", "über", "ueber", "in", "an", "um",
  "nicht", "kein", "keine",
]);

const STOPWORDS_EN = new Set([
  "the", "a", "an", "is", "are", "was", "has", "have", "for", "with",
  "on", "of", "to", "from", "at", "by", "through", "over", "in",
  "not", "no",
]);

/**
 * Remove locale-specific stopwords from a token array.
 * Recognizes "de" and "en" locales. Unknown locales return tokens unchanged.
 */
export function filterStopwords(tokens: string[], locale: string): string[] {
  const lang = locale.toLowerCase().slice(0, 2);
  let stops: Set<string>;
  if (lang === "de") {
    stops = STOPWORDS_DE;
  } else if (lang === "en") {
    stops = STOPWORDS_EN;
  } else {
    return tokens;
  }
  return tokens.filter((t) => !stops.has(t));
}

// ---------------------------------------------------------------------------
// Full search normalization pipeline
// ---------------------------------------------------------------------------

/**
 * Full normalization pipeline for search/matching:
 *   normalizeText → umlautFold → split → filterStopwords
 *   → germanInflectionNormalize (if DE) → join
 *
 * Produces a stable, comparable string for both client and server.
 */
export function normalizeForSearch(text: string, locale: string): string {
  const normalized = normalizeText(text);
  const folded = umlautFold(normalized);
  const tokens = folded.split(/\s+/).filter(Boolean);
  const filtered = filterStopwords(tokens, locale);
  const lang = locale.toLowerCase().slice(0, 2);
  const stemmed = lang === "de"
    ? filtered.map((t) => germanInflectionNormalize(t))
    : filtered;
  return stemmed.join(" ");
}

// ---------------------------------------------------------------------------
// Test corpus (reference — not executed at runtime)
// ---------------------------------------------------------------------------
//
// Input                              | Locale | Expected output
// -----------------------------------|--------|----------------------------------
// "Dragonball"                       | "en"   | "dragonball"
// "Dragon Ball"                      | "en"   | "dragon ball"
// "dragonball"                       | "en"   | "dragonball"
// "Shingeki no Kyojin"              | "en"   | "shingeki kyojin"
//   (stopword "no" removed in EN)
// "Ärzte"                           | "de"   | "aerzt"
//   (umlaut ae + suffix -e stripped: aerzte→aerzt, stem 5>4)
// "größe"                           | "de"   | "groess"
//   (umlaut oe+ss + suffix -e stripped: groesse→groess, stem 6>4)
// "Über"                            | "en"   | "ueber"
// "Lieblings-Anime"                 | "de"   | "lieblings-anime"
//   (hyphen preserved; each part normalized independently; "anime" 5 chars,
//    stem after -e would be 4 which is NOT > 4, so "anime" stays)
// "geschauten"                      | "de"   | "geschaut"
//   (suffix -en stripped, stem "geschaut" 8>4)
// "Empfehlungen"                    | "de"   | "empfehl"
//   (suffix -ungen stripped, stem "empfehl" 7>4)
// "der Angriff auf den Titan"       | "de"   | "angriff titan"
//   (stopwords der/auf/den removed, "titan" 5 chars, no suffix match)
// ""                                | "en"   | ""
// "x"                               | "en"   | "x"
// "!!!"                             | "en"   | ""
// "🎌🎬"                            | "en"   | ""
//   (emoji stripped as non-letter/non-number)
