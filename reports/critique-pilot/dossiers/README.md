# Round 0 — dossiers + PROPOSED pilot slate (2026-08-05)

**Status: PROPOSED, NOT BLESSED.** Site blessing is owner-only (plan §5 Round 0).
12 dossiers in this directory: 7 EN + 5 JP, each with robots.txt/TOS forensics,
archive estimates (counted vs estimated, labeled), activity status, and a proposed
trust tier. Nothing was fetched for ingestion; no reviews were parsed.

## Proposed 3–4 site pilot slate (all automated-fetch compliant)

| # | Site | Lang | Covers | Tier | Why |
|---|---|---|---|---|---|
| 1 | **ANN review desk** (`ann-review-desk.md`) | EN | anime+manga | B | Named critics, long-form argued reviews, archive to 2001, permissive robots (`Crawl-delay: 2`), copyright policy explicitly permits attributed excerpts. Honest caveat: mainstream-professional, not strictly "niche" — it's the strongest *compliant* EN volume source. |
| 2 | **Wrong Every Time** (`wrong-every-time.md`) | EN | anime | B | One respected critic (Nick Creamer), 13-year archive (~3.5–4.5k posts), deeply argued craft+theme criticism, fully permissive robots + sitemaps. The "accustomed voice" archetype. |
| 3 | **Manga Bookshelf** (`manga-bookshelf.md`) | EN | manga | C | Active manga-first desk (Sean Gaffney through 2026-08-03), ~10–11k posts network-wide, fully permissive + complete sitemaps. Carries the EN manga axis. |
| 4 | **藤津亮太のアニメの門V** (`fujitsu-ryota-anime-no-mon.md`) | JP | anime | B | Real-name JP critic, monthly 4,000+-char argued essays, 132回 archive — and robots **explicitly permits ClaudeBot** (`Crawl-delay: 5`). The compliant JP anchor. |

**Alternate #5 (owner's call):** Mangasplaining (`mangasplaining.md`) — DORMANT since
2025-06 but permissive, with a quotable 120-episode archive of ~8.5k-word show-notes.
Reviews don't expire; an archival parse would thicken the manga axis, which is the
slate's thinnest side (1 of 4 sites). WEBアニメスタイル (`web-anime-style.md`, JP craft,
D — insider-conflict caveat) is the JP craft alternate.

## Excluded from automated pilot — and why (the honest part)

- **Sakuga Blog** (tier A on merit) — Cloudflare `ai-train=no`, ClaudeBot/GPTBot
  `Disallow: /`, EU Art.4 rights reservation, 403s. **Manual-path only** (human
  reading, or a future permission arrangement). Do not fetch.
- **Anime Feminist** (tier B; the natural `media_content_notes` source) — robots.txt
  open but WAF 403s automated fetchers. Manual-path until resolved; its
  content-warning-forward format remains the best fit for the warnings table.
- **THEM Anime Reviews** — same Cloudflare AI-block class. Manual-path only.
- **マンバ通信** — ClaudeBot sitewide disallow + Art.4 reservation. Do not fetch.
- **Filmarks / コミックナタリー** — E for critique ingestion (rating-farm culture /
  news-promo desk) + robots/WAF blocks. Out.
- **Open gap:** no compliant JP *manga* critique desk found. Candidates exist only
  behind blocks. Carry as a scouting follow-up; do not force it for the pilot.

Legal posture per plan §9 applies to all of the above: quotes ≤40 words + attribution
+ link, robots/TOS respected (recorded per dossier), no full-prose storage, per-site
takedown honored by construction.

Seed SQL draft (commented, not runnable as-is): `../critic_sources.seed.OWNER_BLESS_REQUIRED.sql`

## Owner redirect (2026-08-05) — slate v2 direction

Owner feedback on the proposed slate: prefers **real articles** (essays/critique) over
review-desk content; wants **Medium** as the primary pilot source (owner has a paid
subscription; per-title search surfaces multiple articles per anime; pilot ~100–200
titles), plus **Japan Powered**; keeps **Manga Bookshelf**; "Wrong Every Time is
alright"; ANN and the rest of the EN slate read as weak to the owner. Preference for
Asian/JP voices and article-form criticism stands.

Status: Medium + Japan Powered dossiers commissioned (in progress). Slate v2 will be
proposed after those land — likely: Medium (per-publication/author tiering, owner-session
reading path), Japan Powered, Manga Bookshelf, Fujitsu column (the compliant JP
real-article anchor), Wrong Every Time as alternate. Still PROPOSED-not-blessed;
Medium's TOS/robots posture must clear the §9 legal bar before any fetch design.
