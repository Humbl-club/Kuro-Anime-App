// Curated rail copy of concierge-recommend: hand-authored EN/DE display titles, subtitles and taste axes
// per mode, and the deterministic curator note (moved verbatim from index.ts, 2026-10-05, F51; only
// `export` keywords added). Pure presentation, no I/O. Hand-authored German copy: do not auto-translate.
import type { UserConstraints } from "./router.ts";

export type Locale = "en" | "de";

export type CuratedCopy = {
  displayTitle: string;
  displaySubtitle?: string;
  // A short axis used for deterministic curator notes.
  tasteAxis: { en: string; de: string };
};

export const CURATED_MODE_COPY: Record<string, CuratedCopy> = {
  premium_picks: {
    displayTitle: "The Cut",
    displaySubtitle: "High-confidence picks, new to you",
    tasteAxis: { en: "craft-forward picks", de: "Handwerk und Qualität" },
  },
  gateway_start_here: {
    displayTitle: "Start Here",
    displaySubtitle: "A clean entry point",
    tasteAxis: { en: "approachable, high-signal stories", de: "zugänglich und treffsicher" },
  },
  premium_action: {
    displayTitle: "Action With Craft",
    displaySubtitle: "Clean choreography, real momentum",
    tasteAxis: { en: "momentum and clarity", de: "Tempo und Klarheit" },
  },
  premium_comedy_grownup: {
    displayTitle: "Comedy With Bite",
    displaySubtitle: "Smart, dry, character-led",
    tasteAxis: { en: "dry wit and precision", de: "trockener Witz und Präzision" },
  },
  cozy_comfort: {
    displayTitle: "Soft Evenings",
    displaySubtitle: "Gentle, restorative stories",
    tasteAxis: { en: "gentle pacing", de: "sanft und wohltuend" },
  },
  dark_serious: {
    displayTitle: "Dark, Not Empty",
    displaySubtitle: "Serious tone, strong craft",
    tasteAxis: { en: "serious tone", de: "ernst, aber mit Substanz" },
  },
  hidden_gems: {
    displayTitle: "Underseen",
    displaySubtitle: "Quiet classics, overlooked hits",
    tasteAxis: { en: "under-discussed brilliance", de: "unter dem Radar" },
  },
  classics_expanded: {
    displayTitle: "The Canon",
    displaySubtitle: "Anchors worth knowing",
    tasteAxis: { en: "foundational works", de: "Grundpfeiler" },
  },
  short_one_season: {
    displayTitle: "Short, Complete",
    displaySubtitle: "One season, clean finish",
    tasteAxis: { en: "tight structure", de: "straff und abgeschlossen" },
  },
  movie_night: {
    displayTitle: "One Perfect Film",
    displaySubtitle: "Stand-alone nights",
    tasteAxis: { en: "one-shot impact", de: "ein Abend, ein Treffer" },
  },
  romance_serious: {
    displayTitle: "Romance That Lands",
    displaySubtitle: "Earned, not fluffy",
    tasteAxis: { en: "emotional weight", de: "emotionale Wucht" },
  },
  romcom: {
    displayTitle: "Light, Sharp Romance",
    displaySubtitle: "Warmth with timing",
    tasteAxis: { en: "warm timing", de: "warm und pointiert" },
  },
  fantasy_non_isekai: {
    displayTitle: "Fantasy With Texture",
    displaySubtitle: "Myth, wonder, discipline",
    tasteAxis: { en: "mythic texture", de: "Mythos und Textur" },
  },
  isekai: {
    displayTitle: "Other Worlds, Cleanly",
    displaySubtitle: "Escapism with craft",
    tasteAxis: { en: "clear escapism", de: "klare Eskapismus-Linie" },
  },
  sports: {
    displayTitle: "Competition, Pure",
    displaySubtitle: "Training arcs that work",
    tasteAxis: { en: "earned momentum", de: "verdientes Momentum" },
  },
  scifi: {
    displayTitle: "Ideas With Heat",
    displaySubtitle: "Speculation, not noise",
    tasteAxis: { en: "clean sci-fi ideas", de: "klare Sci-Fi-Ideen" },
  },
  horror_supernatural: {
    displayTitle: "Unease, Done Right",
    displaySubtitle: "Atmosphere over gore",
    tasteAxis: { en: "atmosphere and tension", de: "Atmosphäre und Spannung" },
  },
  mecha: {
    displayTitle: "Steel and Stakes",
    displaySubtitle: "Big machines, real themes",
    tasteAxis: { en: "scale and conviction", de: "Groesse und Haltung" },
  },
  mystery_detective: {
    displayTitle: "Cases With Discipline",
    displaySubtitle: "Puzzles that hold",
    tasteAxis: { en: "sharp mystery logic", de: "scharfe Logik" },
  },
  music_performance: {
    displayTitle: "Sound and Feeling",
    displaySubtitle: "Performance that moves",
    tasteAxis: { en: "rhythm and emotion", de: "Rhythmus und Gefühl" },
  },
  historical: {
    displayTitle: "Period Weight",
    displaySubtitle: "History with texture",
    tasteAxis: { en: "weight and texture", de: "Gewicht und Textur" },
  },
  school_coming_of_age: {
    displayTitle: "Coming-of-Age, Quietly",
    displaySubtitle: "Youth, rendered cleanly",
    tasteAxis: { en: "intimate growth", de: "intimes Wachsen" },
  },
  shoujo_josei: {
    displayTitle: "Emotion, With Clarity",
    displaySubtitle: "Character-first, precise",
    tasteAxis: { en: "emotional clarity", de: "emotionale Klarheit" },
  },
  similar_to_seed: {
    displayTitle: "In the Same Orbit",
    displaySubtitle: "Close to your anchor",
    tasteAxis: { en: "adjacent craft", de: "nahe am Anker" },
  },
};

export function softenFallbackTitle(raw: string): string {
  const t = String(raw ?? "").trim();
  if (!t) return "Selections";
  return t
    .replace(/\bpremium\b/gi, "")
    .replace(/\(.*?\)/g, "")
    .replace(/\s*\/\s*/g, " · ")
    .replace(/\s+/g, " ")
    .trim();
}

export function curatedCopyForMode(locale: Locale, modeId: string, modeTitleFallback: string): { displayTitle: string; displaySubtitle?: string; tasteAxis: string } {
  const c = CURATED_MODE_COPY[modeId];
  if (!c) {
    const softened = softenFallbackTitle(modeTitleFallback);
    return {
      displayTitle: softened,
      displaySubtitle: locale === "de" ? "Kuratiert, neu für dich" : "Curated, new to you",
      tasteAxis: locale === "de" ? "Ton und Handwerk" : "tone and craft",
    };
  }
  const deTitles: Record<string, string> = {
    // Hand-authored DE titles (do not auto-translate).
    premium_picks: "Die Auswahl",
    premium_comedy_grownup: "Komödie mit Biss",
    cozy_comfort: "Sanfte Abende",
    dark_serious: "Dunkel, nicht leer",
    hidden_gems: "Unterschätzt",
    classics_expanded: "Der Kanon",
    short_one_season: "Kurz, abgeschlossen",
    movie_night: "Ein perfekter Film",
    romance_serious: "Romantik, die trifft",
    romcom: "Leicht, aber scharf",
    fantasy_non_isekai: "Fantasy mit Textur",
    isekai: "Andere Welten, sauber",
    sports: "Wettkampf, pur",
    scifi: "Ideen mit Hitze",
    horror_supernatural: "Unbehagen, richtig",
    mecha: "Stahl und Einsatz",
    mystery_detective: "Fälle mit Disziplin",
    music_performance: "Klang und Gefühl",
    historical: "Zeitgewicht",
    school_coming_of_age: "Coming-of-Age, leise",
    shoujo_josei: "Gefühl, mit Klarheit",
    gateway_start_here: "Hier anfangen",
    premium_action: "Action mit Handwerk",
    similar_to_seed: "In derselben Umlaufbahn",
  };
  const deSubtitles: Record<string, string> = {
    premium_picks: "Sichere Picks, neu für dich",
    premium_comedy_grownup: "Trocken, klug, figurengetrieben",
    cozy_comfort: "Ruhig, warm, erholsam",
    dark_serious: "Ernst, aber mit Substanz",
    hidden_gems: "Übersehenes, das sitzt",
    classics_expanded: "Anker, die man kennt",
    short_one_season: "Eine Staffel, sauberer Abschluss",
    movie_night: "Standalone-Abende",
    romance_serious: "Verdient, nicht fluffig",
    romcom: "Wärme mit Timing",
    fantasy_non_isekai: "Mythos, Staunen, Disziplin",
    isekai: "Eskapismus mit Handwerk",
    sports: "Training, das funktioniert",
    scifi: "Spekulation, nicht Lärm",
    horror_supernatural: "Atmosphäre statt Gore",
    mecha: "Große Maschinen, echte Themen",
    mystery_detective: "Rätsel, die halten",
    music_performance: "Performance, die bewegt",
    historical: "Geschichte mit Textur",
    school_coming_of_age: "Jugend, klar gezeichnet",
    shoujo_josei: "Figuren zuerst, präzise",
    gateway_start_here: "Ein sauberer Einstieg",
    premium_action: "Choreo, Tempo, Klarheit",
    similar_to_seed: "Nahe an deinem Anker",
  };
  return {
    displayTitle: locale === "de" ? (deTitles[modeId] ?? c.displayTitle) : c.displayTitle,
    displaySubtitle: locale === "de" ? (deSubtitles[modeId] ?? c.displaySubtitle) : c.displaySubtitle,
    tasteAxis: locale === "de" ? c.tasteAxis.de : c.tasteAxis.en,
  };
}

export function clampWords(s: string, maxWords: number): string {
  const parts = String(s ?? "").trim().split(/\s+/).filter(Boolean);
  if (parts.length <= maxWords) return parts.join(" ");
  return parts.slice(0, maxWords).join(" ");
}

export function buildCuratorNote(args: {
  locale: Locale;
  primaryModeId: string;
  primaryModeTitle: string;
  constraints: UserConstraints;
  ragUsed: boolean;
  seedTitle?: string | null;
  avoidedGenres?: string[];
}): string {
  const { locale, constraints, primaryModeId, primaryModeTitle } = args;
  const copy = curatedCopyForMode(locale, primaryModeId, primaryModeTitle);

  const constraintBits: string[] = [];
  if (constraints.format === "MOVIE") constraintBits.push(locale === "de" ? "nur Filme" : "movie-only");
  if (constraints.max_episodes != null) constraintBits.push(locale === "de" ? "kurz gehalten" : "kept it short");
  if (constraints.year_min != null || constraints.year_max != null) {
    const a = constraints.year_min != null ? String(constraints.year_min) : "";
    const b = constraints.year_max != null ? String(constraints.year_max) : "";
    const span = a && b ? `${a}-${b}` : (a ? `ab ${a}` : (b ? `bis ${b}` : ""));
    if (span) constraintBits.push(locale === "de" ? `im Zeitraum ${span}` : `within ${span}`);
  }
  if (constraints.excluded_genres.length > 0) {
    const g = constraints.excluded_genres.slice(0, 2).join(locale === "de" ? " und " : " and ");
    constraintBits.push(locale === "de" ? `ohne ${g}` : `avoiding ${g}`);
  }

  const constraintPhrase = constraintBits.length
    ? constraintBits[0]
    : (locale === "de" ? "sauber gefiltert" : "cleanly filtered");

  const personalPhrase = (() => {
    if (args.ragUsed && args.seedTitle) {
      const t = clampWords(String(args.seedTitle), 6);
      return locale === "de" ? `in der Nähe von ${t}` : `near ${t}`;
    }
    return locale === "de" ? "neu für dich" : "new to you";
  })();

  return locale === "de"
    ? `Ich habe ${constraintPhrase} beachtet, in Richtung ${copy.tasteAxis} geneigt und ${personalPhrase} priorisiert.`
    : `I kept it ${constraintPhrase}, leaned toward ${copy.tasteAxis}, and prioritized ${personalPhrase}.`;
}

/** The message shown when no rail could be built (older clients render `message` as plain text). */
export function emptyRecommendationMessage(locale: Locale): string {
  return locale === "de"
    ? "Sag mir eine Stimmung oder eine klare Kante (kurz, ohne Romance, ein Jahr) — ich kuratiere es neu für dich."
    : "Give me a mood or one constraint (short, no romance, a year) and I’ll curate it — new to you.";
}
