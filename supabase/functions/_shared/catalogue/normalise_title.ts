// Title normalisation for matching Kuro titles against source titles (ANN, MangaUpdates).
// NFKC (full-width to ASCII), lower case, Latin diacritics removed (kana voicing marks stay),
// punctuation and symbols become spaces, a leading "the"/"a" is dropped, and a trailing season
// marker (`season N`, `Nth season`, `part N`, roman II..X) is folded into one ` sN` suffix.
// A lone "I" is never a numeral. Pure and idempotent.

const ROMAN: Record<string, number> = { ii: 2, iii: 3, iv: 4, v: 5, vi: 6, vii: 7, viii: 8, ix: 9, x: 10 };

function foldSeasonSuffix(tokens: string[]): string[] {
  const n = tokens.length;
  if (n >= 2 && (tokens[n - 2] === "season" || tokens[n - 2] === "part") && /^\d{1,2}$/.test(tokens[n - 1])) {
    return [...tokens.slice(0, n - 2), `s${Number(tokens[n - 1])}`];
  }
  if (n >= 2 && tokens[n - 1] === "season" && /^\d{1,2}(st|nd|rd|th)$/.test(tokens[n - 2])) {
    return [...tokens.slice(0, n - 2), `s${parseInt(tokens[n - 2], 10)}`];
  }
  if (n >= 2 && tokens[n - 1] in ROMAN) {
    return [...tokens.slice(0, n - 1), `s${ROMAN[tokens[n - 1]]}`];
  }
  return tokens;
}

export function normaliseTitle(raw: string): string {
  let s = raw.normalize("NFKC").toLowerCase();
  // Strip Latin combining diacritics only (U+0300-036F); NFKD would also split kana voicing marks.
  s = s.normalize("NFKD").replace(/[̀-ͯ]/g, "").normalize("NFC");
  // Anything that is not a letter, number or (kana/CJK) mark becomes a separator.
  s = s.replace(/[^\p{L}\p{N}\p{M}]+/gu, " ").trim();
  let tokens = s.split(" ").filter(Boolean);
  if (tokens.length > 1 && (tokens[0] === "the" || tokens[0] === "a")) tokens = tokens.slice(1);
  tokens = foldSeasonSuffix(tokens);
  return tokens.join(" ");
}

export function titleTokens(normalised: string): string[] {
  return normalised ? normalised.split(" ") : [];
}
