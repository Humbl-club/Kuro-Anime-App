# MangaUpdates official-publisher groups (allowlist for `MU_OFFICIAL_GROUP_IDS`)

**Date:** 2026-11-02 · **Scope:** research only. No code, secrets or deployments were changed, and nothing was committed.
**Answers:** which MangaUpdates (MU) group ids stand for *official* English (and German) chapter releases, so that `release-intake` mode `manga` estimates the next manga chapter only from official dates (open decision D11).

---

## 1. Recommendation

| Option | `MU_OFFICIAL_GROUP_IDS` value | Covers |
|---|---|---|
| **Recommended (full)** | `49204242348,45251742061,3657285706` | Shueisha via MANGA Plus and VIZ, plus Naver/LINE WEBTOON originals |
| Conservative | `49204242348,45251742061` | Shueisha via MANGA Plus and VIZ only |

The owner decides between these two (see §5, LINE Webtoon caveats). Set the value as a Supabase Edge Function secret on project `bkdifromsqxkndnllmdj`. This research did not set it.

### Format: required exactly, or intake silently turns off
`supabase/functions/release-intake/index.ts:51` parses the value as follows:

```ts
function parseGroupIds(raw: string | undefined): number[] {
  return (raw ?? "").split(",").map((v) => Number(v.trim())).filter((n) => Number.isInteger(n) && n > 0);
}
```

- Use **decimal integer** MU `group_id`s, **comma-separated**, with no quotes and no brackets. Spaces around commas are fine.
- **Do not use the base36 slug** from the group URL (for example `mlqxodo`). `Number("mlqxodo")` is `NaN`, so the entry is **dropped silently**. If every entry is dropped, the allowlist ends up empty. `manga.ts` then makes no `/releases/search` call, writes no release rows and no cadence estimate, and **raises no error**.
- The ids are about 5×10¹⁰, well inside JS `Number.MAX_SAFE_INTEGER`, so they parse exactly.
- Matching is in `manga.ts:124` `isOfficialRelease`. A release record counts as official when **any** entry in `record.groups[].group_id` is on the list. VIZ and MANGA Plus usually co-credit the same record, and either id matches it.

---

## 2. The groups that qualify

All three are `active: true`, `admin.approved: true`, and appeared in MU's last-7-days release feed (§4). Each base36 slug was checked with `int(slug, 36) == group_id`.

| Group (MU name) | group_id (decimal, **use this**) | base36 slug | MU page | Release frequency (MU) | Series on MU |
|---|---|---|---|---|---|
| MANGA Plus (Shueisha) | **49204242348** | `mlqxodo` | https://www.mangaupdates.com/group/mlqxodo/manga-plus | Every day | 719 |
| Viz (VIZ Media / Shonen Jump) | **45251742061** | `ksdpvn1` | https://www.mangaupdates.com/group/ksdpvn1/viz | Often. About every 1 to 2 days | 234 |
| LINE Webtoon (WEBTOON official) | **3657285706** | `1ohgbpm` | https://www.mangaupdates.com/group/1ohgbpm/line-webtoon | Every day | 999 (list cap) |

### Evidence that each is official
MU has no "official" flag. **Only LINE Webtoon is described as official in MU's own notes.** For the other two, the evidence is indirect:

- **MANGA Plus 49204242348.** MU notes: none. The site link is `https://mangaplus.shueisha.co.jp/` (Shueisha's own domain). Other links: Twitter `mangaplus_o`, Facebook `mangaplus.en`, and the official Discord. Its releases are co-credited with Viz on the same day as Shonen Jump simulpub. MU's group page lists MANGA Plus under its generic "scanlator" layout; it does not call it official.
- **Viz 45251742061.** MU notes: none. The site link is `https://www.viz.com/shonenjump`, Twitter is `VIZMedia`, Facebook is `OfficialVIZMedia`, and Discord is `discord.com/invite/viz`.
- **LINE Webtoon 3657285706.** MU notes: *"Official digital publisher for Naver webtoons"*. The site link is `http://www.webtoons.com`, Twitter is `webtoonofficial`, Facebook is `linewebtoon`.

Sources: `GET https://api.mangaupdates.com/v1/groups/{id}` and `GET /v1/groups/{id}/series`, plus the public MU group pages fetched on 2026-11-02.

---

## 3. Spot checks (release dates from `POST /v1/releases/search`, the same request `manga.ts` sends)

### One Piece: MU series 55099564912 (`pb8uwds`), MANGA Plus + Viz
| Release date | Chapter | Groups |
|---|---|---|
| 2026-11-01 | 1197 | Viz, MANGA Plus |
| 2026-10-18 | 1196 | Viz, MANGA Plus |
| 2026-10-11 | 1195 | Viz, MANGA Plus |
| 2026-09-27 | 1194 | Viz, MANGA Plus |

In the newest 40 records, 39 are Viz+MANGA Plus and 1 is the scanlation "Manga Trend", which posted ch. 1187 on 2026-07-02, three days before the official 2026-07-05. The allowlist drops that leak as intended.

### The World After the Fall: MU series 39426575272, LINE Webtoon
| Release date | Chapter | Group |
|---|---|---|
| 2026-11-02 | 244 | LINE Webtoon |
| 2026-10-26 | 243 | LINE Webtoon |
| 2026-10-19 | 242 | LINE Webtoon |

Asura (scanlation) records are interleaved and run about 14 chapters ahead (ch. 258 on 2026-10-27). The allowlist drops them.

### Other recent MANGA Plus / Viz records (2026-11-01, from `/v1/releases/days`)
Sakamoto Days 281, Kagurabachi 137, Akane-banashi 228, Witch Watch 268 (Viz + MANGA Plus), and Red Cat Ramen 212 and Centuria 107 (MANGA Plus only).

### Verified by running Kuro's own filter (read-only)
A throwaway Deno script imported the unchanged `dedupeReleases` (`manga.ts`) and `estimateNextChapter` (`cadence.ts`). It ran them on the saved API responses with the full allowlist, with now = 2026-11-02:

| Series | Records | Official kept | Non-official dropped | Cadence result |
|---|---|---|---|---|
| One Piece | 40 | 39 | 1 | ch. 1198 ≈ 2026-11-15 (median 14 d, confidence 1.0) |
| The World After the Fall | 40 | 20 | 20 | ch. 245 ≈ 2026-11-09 (median 7 d, confidence 1.0) |
| Tower of God | 40 | 39 | 1 | rejected `stale` (last official record 2025-02-24) |
| Blue Lock (Kodansha) | 40 | 0 | 40 | rejected `too_few_dates` |
| Kusuriya no Hitorigoto (Square Enix) | 40 | 0 | 40 | rejected `too_few_dates` |

The One Piece median is 14 days, not 7, because its 2026 schedule on MU has regular break weeks. The estimate reflects the data and is not a bug.

---

## 4. Coverage gap: what this source **cannot** give us

In a survey of MU's latest-releases feed (`GET /v1/releases/days`, pages 1–3, 1,936 records dated 2026-10-28 to 2026-11-02), the **only** official publishers that appeared were LINE Webtoon (488 records), MANGA Plus (59) and Viz (24). Everything else was scanlation.

So with this allowlist, Kuro's next-chapter estimates cover:
- **Covered:** Shueisha titles (Weekly Shonen Jump, Jump+, Jump SQ and others via MANGA Plus/VIZ) and LINE WEBTOON originals.
- **Not covered (no official dates on MU):** Kodansha (K MANGA is inactive with 0 series, so Blue Lock has no official records), Square Enix (no Manga UP! group exists on MU), Kadokawa, Shogakukan, Yen Press, Seven Seas, TOKYOPOP, and **all German editions**.

### German publishers
MU group search found **no group** for Carlsen, Egmont Manga, Kazé, altraverse, Panini Manga or TOKYOPOP (search: 0 hits or only unrelated scanlation names). MU does not track German publisher releases, so a German next-volume or next-chapter date needs a different source (for example the publishers' own release calendars). That is outside this allowlist.

---

## 5. Caveats for LINE Webtoon (why a conservative option exists)

1. **Chapter numbers can be season-relative.** Tower of God records carry `vol='3' ch='235'`. `dedupeReleases` keys on the chapter number and ignores the volume. For multi-season webtoons, Kuro would therefore label rows "Ch. 235", which may not match what readers see in the WEBTOON app or AniList's chapter count.
2. **Free-episode timing.** WEBTOON chapters on MU follow the free release, which can run many episodes behind Fast Pass (and behind scanlations, as World After the Fall shows). The date is official, but it is the free-tier date.
3. **Stale history is still written.** For Tower of God the cadence estimate is correctly rejected as `stale`. The newest official rows (Feb 2025) would still be written as `released` history, up to `confirmedPastLimit` rows.
4. Some chapter strings are ranges (for example `1-3`). They are not plain numbers, so `parseChapterNumber` skips them. Nothing is guessed.

If those labels are unacceptable, use the conservative value `49204242348,45251742061`.

## 6. Limitation in the current intake (observation only, no change made)
`manga.ts` fetches the newest 40 release records **across all groups** (`perpage: 40`, `orderby: date desc`). On heavily scanlated series, official records share that window with others. World After the Fall kept only 20 of 40. A series with very active scanlators could push official records out of the window entirely, which would yield `too_few_dates`.

---

## 7. Candidates checked and excluded

| Candidate | MU group (id) | Why excluded |
|---|---|---|
| K MANGA (Kodansha) | K Manga (20977306229, `9mxch2t`) | `active: false`, frequency "Never", 0 series |
| Kodansha USA / Kodansha Comics | Kodansha USA (67085909306, `uth7uwq`) | `active: false`, "Never", 4 old series |
| Yen Press | Yen Press (56980946982, `q6czg2u`) | `active: false`, "Never", 1 series |
| Comikey | Comikey (20621979492, `9h1sl7o`) | `active: false`, "Never" (187 historical series) |
| INKR | INKR Comics (11282539598, `56lbz9q`) | `active: false`, "Never" |
| Tapas | Tapas (4290065293) / Tapastic (4634174132) | `active: false`, "Never" |
| Pocket Comics | Pocket Comics (10140796635) | `active: false`, "Never". Notes say listed dates are when chapters were **free without ads**, not publication dates |
| Crunchyroll Manga | Crunchyroll (28647132879) | `active: false`, "Never". Notes say listed releases were readable for free at one point, not publication dates |
| TappyToon | TappyToon (20199673456) | `active: false`, "Never" |
| Lezhin | Lezhin (47244143696) | `active: false`, "Never" |
| J-Novel Club | J-Novel Club (31439080110) | `active: false`, "Never" |
| Manga Planet | Manga Planet (2050241780) | `active: false`, "Never" |
| BiliBili Comics | BiliBili Comics (37471024509) | `active: false` (service defunct) |
| Comic Walker | Comic Walker (73655501745) | `active: false` |
| Webtoon Factory EN | Webtoon Factory EN (76092908951) | `active: false`, last update 2024 |
| **Azuki** | "Azuki" (9301441473, `49tu669`) | **Not the publisher.** Its site link is a MangaDex scanlation group (`mangadex.org/group/6763/azuki`) and it has one series (*Dramatic Irony (Namaco)*). Do not add it by name match |
| Seven Seas | none found | No MU group (searched "Seven Seas", "Seven Seas Entertainment", "Seas") |
| Square Enix Manga / Manga UP! | none found | No MU group (searched "Square Enix", "Square Enix Manga", "Manga UP!", "Enix") |
| TOKYOPOP | none found | 0 hits |
| Carlsen, Egmont, Kazé, altraverse, Panini (DE) | none found | 0 hits or unrelated scanlation names only |

If an inactive official group starts publishing on MU again, the owner can append its decimal id. Records from inactive groups are harmless but add nothing today.

---

## 8. Method
- API: `https://api.mangaupdates.com/v1`, with `User-Agent: KuroResearch/1.0` and at least 1.5 s between requests. Calls used: `POST /groups/search`, `GET /groups/{id}`, `GET /groups/{id}/series`, `POST /series/search`, `POST /releases/search` (`search_type: "series"`, the same body as `manga.ts`) and `GET /releases/days`.
- Confirmation: MU public group pages for MANGA Plus, Viz and LINE Webtoon fetched on 2026-11-02.
- Raw JSON responses were kept locally in `/tmp/mu_research/out/` (scratch, not in the repo).
