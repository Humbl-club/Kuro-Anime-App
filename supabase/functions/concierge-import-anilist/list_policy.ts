// Cached text versus a fresh AniList list. Import reuses trimmed text/cachedText
// and echoes the caller's truncated flag. Preview, and import with no cached
// text, is a fresh list. No network.
import { dedupeAndJoinLines } from "./lines.ts";

export type ImportMode = "preview" | "import";

export type ListSource =
  | {
    kind: "cached";
    mode: ImportMode;
    text: string;
    itemCount: number;
    truncated: boolean;
  }
  | { kind: "fresh"; mode: ImportMode };

export function selectListSource(raw: {
  mode?: string;
  text?: string;
  cachedText?: string;
  truncated?: boolean;
}): ListSource {
  const mode: ImportMode = raw.mode === "preview" ? "preview" : "import";
  const cachedText = String(raw.text ?? raw.cachedText ?? "").trim();
  if (mode === "import" && cachedText.length > 0) {
    const { text, itemCount } = dedupeAndJoinLines(cachedText.split(/\r?\n/));
    return {
      kind: "cached",
      mode,
      text,
      itemCount,
      truncated: Boolean(raw.truncated ?? false),
    };
  }
  return { kind: "fresh", mode };
}
