# Sakuga Blog — site dossier (Round 0, 2026-08-05)

**Status: ACTIVE** (2026 articles confirmed via search index; direct fetch blocked — see robots)

- **Name:** Sakuga Blog ("The Art of Japanese Animation")
- **URL:** https://blog.sakugabooru.com/
- **Anime/manga/both:** Anime (production/craft focus; no manga reviews)
- **Language:** English
- **Named critics:** Yes — pseudonymous handles with stable identities: kViN (Kevin Cirugeda, main writer), Disgaeamad (Ryan, essays + JP interview translations), liborek (series/industry coverage). All are Sakugabooru admins; contributors page exists (`/contributors/`).
- **Review depth:** Long-form essays, typically 2,000-4,000+ words. Strongly ARGUES: staff-level production analysis (key animators, episode directors, studio pipelines), interview translations, annual animation awards. This is the most argument-dense EN craft desk that exists.
- **Archive size estimate:** ESTIMATE — direct counting impossible (403 on all pages incl. feed). Publishing since 2016, multi-post monthly cadence → plausibly 600-900 total articles; distinct titles covered in depth likely 200-350 (per-show tag archives exist, e.g. `/tag/jujutsu-kaisen/`). Do not treat these numbers as counted.
- **robots.txt + TOS posture:** **PROMINENT: AI crawlers explicitly disallowed.** Cloudflare managed content-signals robots.txt:
  - `User-agent: *` / `Content-Signal: search=yes,ai-train=no,use=reference` / `Allow: /`
  - `User-agent: ClaudeBot` / `Disallow: /` (likewise GPTBot, CCBot, Google-Extended, Bytespider, Amazonbot, Applebot-Extended, meta-externalagent, CloudflareBrowserRenderingCrawler)
  - Header asserts express reservation of rights under EU Directive 2019/790 Art. 4.
  - Observed behavior: HTTP 403 on homepage, article pages, and `/feed/` for our fetcher. No separate site TOS found (fetch-blocked).
  - **Consequence:** this site can only enter the pilot via a manual/owner-mediated quote path — no automated fetching, period.
- **Accessibility:** Per-show tag archives, per-author archives, category pages, WP permalink structure (`/YYYY/MM/DD/slug/`) — all confirmed to exist via search index, none fetchable by bot. RSS feed exists but is 403-blocked.
- **Lens/voice:** Sakuga culture: animation as authored craft. Cares about who animated what, direction, scheduling/production health, studio lineage. Effectively defines EN discourse on animation quality; also runs annual Sakuga Blog Animation Awards.
- **Proposed trust tier:** **A (craft axes only, manual-path)** — the single most authoritative EN source for animation/direction claims, but its robots posture forbids automated ingestion, so it is A-trust with hand-curated quotes or nothing.
- **Example review URL:** https://blog.sakugabooru.com/2026/04/10/shiboyugi-souta-ueno/ ("Shiboyugi: Playing Death Games To Put Food On The Table And Souta Ueno's Deranged World", kViN, 2026-04-10). Verified to exist via search index; direct fetch returned 403, so contents were not read first-hand.
