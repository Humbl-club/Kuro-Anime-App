# Medium (platform) as an anime/manga critique source — dossier (Round 0 extension, 2026-08-05)

**Status: ACTIVE platform (owner-proposed, NOT BLESSED).** Owner has a paid Medium
membership and proposed per-title search + ingestion of real articles for ~100–200 titles.
This dossier is a platform assessment; the blessing unit it recommends is **per publication
/ per author**, never platform-wide.

- **Name:** Medium (medium.com) — open publishing platform, not an editorial site
- **URL:** https://medium.com/
- **Anime/manga/both:** Both (plus everything else; anime/manga is a niche among millions of posts)
- **Language:** Primarily EN; meaningful PT-BR/ES/ID/TR anime writing exists (e.g. PT-BR critique pubs `medium.com/nanicriticas`, `medium.com/betaredacao` both surfaced in manga sampling)
- **Named critics:** No platform-level bylines — anyone can publish. Named recurring voices exist *inside publications and author pages* (see below). That asymmetry is the whole story of this dossier.

## Platform mechanics (verified logged-out, 2026-08-05)

- **Per-title search (`medium.com/search?q=naruto`)**: tested logged-out for `naruto` and
  `berserk`. Both return an **empty client-side skeleton** — tab headers ("Stories, People,
  Publications, Topics, Lists") with zero results rendered server-side. Results populate only
  via JS in a real browser. On top of that, Medium's robots.txt **disallows `/search?q=` for
  all user agents**. So the owner's proposed "search per title" flow works only in their own
  logged-in browser; it is not automatable even in principle.
- **Practical enumeration path that does work:** Google `site:medium.com <title> analysis`.
  Sampled richly (table below). Tag hubs (`medium.com/tag/anime-analysis`) and publication
  archives are secondary indexes.
- **Paywall behavior:** non-member-only stories render **full text logged-out** (verified:
  "Spirited Away — A Marxist Analysis", ~2,900 words, rendered completely without login).
  Member-only stories truncate for logged-out readers; the owner's paid membership unlocks
  them **in their browser session only**.

## Quality spread (sampled searches — honest read)

Wide. Every title sampled surfaces a mix of (a) genuinely argued essays, (b) personal-
reflection / "what X taught me" pieces, (c) philosophy-lite listicles, (d) SEO-ish recaps.
No gatekeeping outside publications. Sampling for coverage (via Google site-search, counting
apparently substantive pieces in the first ~10 results):

| Title (class) | Findings |
|---|---|
| Naruto (big shounen) | Many; mostly life-lessons/philosophy-lite; some argued (e.g. Kisame morality essay). Signal:noise poor. |
| Spirited Away (film classic) | Rich; incl. a cited, co-authored ~2,900-word Marxist analysis (Marx/Napier citations). Several substantive. |
| Berserk (seinen manga) | Rich; arc-level essays (Zsoro's Golden Age essay), feminist analysis, Miura legacy pieces. |
| Goodnight Punpun (cult manga) | Surprisingly strong: 6+ substantive EN pieces + PT-BR critiques. |
| Blood on the Tracks (cult manga) | 8+ pieces incl. per-volume reviews (VS Virsus) and psychological analyses. |
| Mushishi (quiet classic) | Covered: EN + PT essays, an iyashikei comparative piece. |
| Made in Abyss (anchor title) | Covered: morality + visual-art essays (Naumande, multiple), chapter analyses, AniTAY review (DoctorKev). |

**Coverage estimate for a 100–200 title pilot:** big shounen, Ghibli/film canon, cult seinen
manga — yes, usually several ≥800-word argued pieces each. Mid-tier anime (Golden Time /
Mushishi class) — 2–6 pieces, mixed language. Genuinely obscure manga (older josei, minor
titles) — thin to zero. ESTIMATE: ~60–75% of a popularity-skewed 150-title list gets ≥1
substantive piece; materially lower if the list leans obscure-manga.

## Publications / authors that concentrate quality (the blessing unit)

- **AniTAY-Official** (`medium.com/anitay-official`) — VERIFIED and **ACTIVE** (RSS latest
  2026-07-29). Community anime/manga collective founded 2014 (ex-Kinja, moved to Medium late
  2020). Co-editors-in-chief: Dexomega, Protonstorm, Raitzeno; best-known byline DoctorKev.
  Sections: Guides / Reviews / Podcasts / Features. Honest caveat: the current feed is
  dominated by one writer (Marquan) doing short manga reviews/first-impressions plus podcast
  posts; the deep collaborative features are mostly back-catalog. Hobbyist, self-described.
- **The Ugly Monster** (`medium.com/theuglymonster`) — multi-media pub ("Movies, TV, Anime,
  and Other Vile Media"), 10k followers, active (posts Feb 2026), anime tag maintained
  (Dark Aether's anime year-end essays). Anime is a minority share.
- **Named individual authors** (candidate per-author blessings, examples found in sampling):
  Danny Guan ("My Manga Journal" — numbered manga retrospectives, #93+ observed → 90+ title
  archive, manga-first), Naumande (multiple Made in Abyss essays), VS Virsus (per-volume manga
  reviews), Zsoro (Berserk arc essays). Each needs owner eyes before blessing.
- No Medium equivalent of an ANN-class desk was found; AniTAY is the closest thing to an
  anime institution on the platform.

## robots.txt + TOS posture (the hard part)

robots.txt (fetched 2026-08-05, relevant rules):
- `User-Agent: ClaudeBot` / `GPTBot` / `Amazonbot` / `FacebookBot` / `Bytespider` → **`Disallow: /`**
  (narrow `Allow:` exceptions only for corporate pages: `/about`, `/business`, `/membership`, …)
- All agents: **`Disallow: /search?q=`**, `Disallow: /media/`, `Disallow: /*/edit$`
- `Sitemap: https://medium.com/sitemap/sitemap.xml`

Medium Rules (policy.medium.com) prohibit, verbatim: use of "any software, script, robot,
spider or other automatic device, process or means (including crawlers, browser plugins and
add-ons or any other technology) to access the Services for any purpose, including without
limitation to scrape or otherwise copy any of the data or content on the Services" — and even
"any manual process to monitor or copy any of the data or content on the Services, or to
engage in any other unauthorized purpose."

Three paths, assessed:
- **(a) Automated mass scraping — OUT.** Explicitly TOS-prohibited AND ClaudeBot is
  robots-disallowed sitewide. Fails the plan §9 posture on both axes. Do not build a fetcher.
- **(b) Owner-session-assisted reading — the only plausible path.** Owner (a paying member)
  reads articles in their own logged-in browser; only structured claims + ≤40-word attributed
  quotes + URL enter the DB; no prose stored. This is ordinary reading plus note-taking, and
  short attributed quotes are standard fair-use/quotation-right territory. Honest caveats:
  Medium's "any manual process to… copy" clause is written broadly enough that a maximalist
  reading covers even this; membership paywall content adds a contractual layer (the member
  license is personal). Defensible at pilot scale as human reading with citations — but it
  consumes **owner hours**, does not scale to a swarm, and should stay clearly below any
  systematic-harvest threshold (think tens of articles, not thousands).
- **(c) Official surfaces:** the Medium API was **closed to new integrations on 2025-01-01**
  (no new tokens; write-oriented anyway). **RSS still works** — verified
  `medium.com/feed/anitay-official` returns full item lists (latest ~10 items, title/author/
  date). RSS is legitimate for *monitoring new posts of blessed publications/authors*, useless
  for archive ingestion.

## Proposed trust tier

- **Platform-wide: E** (definitionally — unvetted open platform; same class as user-review farms
  for trust purposes even though real essays live on it).
- **Per publication/author (the only unit worth blessing):** AniTAY-Official **C** (named
  recurring bylines, light community editing, active; hobbyist depth-variance keeps it out of B —
  DoctorKev's byline individually is arguably C+/B−). The Ugly Monster **D+/C−** (anime minority
  share). Vetted individual authors: case-by-case **C** ceiling (e.g. Danny Guan's 90+ manga
  retrospectives would usefully thicken the manga axis) — every author blessing needs an owner
  read of 2–3 pieces first.
- Ingestion mode for anything blessed here: **manual-path only** (owner-session reading),
  RSS for new-post monitoring. No automated fetch, ever, per robots+TOS above.

## Example URLs (visited/verified)

- https://medium.com/anitay-official/about (publication, verified active via `medium.com/feed/anitay-official`, latest 2026-07-29)
- https://luxliterarius.medium.com/spirited-away-a-marxist-analysis-f11ac2bcd981 (full text logged-out, ~2,900 words, cited)
- https://medium.com/search?q=naruto (verified: empty logged-out skeleton, robots-disallowed)
