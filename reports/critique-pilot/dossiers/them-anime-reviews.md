# THEM Anime Reviews — site dossier (Round 0, 2026-08-05)

**Status: ACTIVE (recency unverified first-hand)** — Wikipedia article updated June 2026 lists current staff and describes the site as active; direct fetch of the site is bot-blocked, so I could not confirm the date of the most recent review myself. Treat "active" as second-hand.

- **Name:** THEM Anime Reviews (4.0)
- **URL:** https://www.themanime.org/
- **Anime/manga/both:** Anime only
- **Language:** English
- **Named critics:** Yes — real-name byline culture with per-reviewer credits pages (`/credits.php?id=SH` etc.). Long-tenured reviewers: Stig Høgset (since 2003), Tim Jones (since 2002), Nicole MacLean, Robert Nelson, Melissa Sternenberg, Enoch Lau, Robert Lu; earlier: Raphael See, Jason Bustard, Eric Gaede. (Names from Wikipedia + THEM fan wiki.)
- **Review depth:** Full-length reviews, star rating (out of 5) + prose; typically ~800-1,500 words based on the site's long-standing format. ARGUES at a plain-spoken consumer-critic level — honest "should you watch this" verdicts with reasons, less craft-technical than Sakuga Blog. (Depth characterization is from prior familiarity + secondary sources; fetch-blocked this pass.)
- **Archive size estimate:** "Over 1,500 full-length reviews" as of 2020 per Wikipedia — the one number I can cite. 2026 total plausibly 1,600-1,800 (ESTIMATE, not counted). Full alphabetical review index exists at `/reviewlist.php`.
- **robots.txt + TOS posture:** **PROMINENT: AI crawlers explicitly disallowed.** Identical Cloudflare managed content-signals robots.txt to Sakuga Blog:
  - `User-agent: *` / `Content-Signal: search=yes,ai-train=no,use=reference` / `Allow: /`
  - `User-agent: ClaudeBot` / `Disallow: /` (likewise GPTBot, CCBot, Google-Extended, Bytespider, Amazonbot, Applebot-Extended, meta-externalagent)
  - EU 2019/790 Art. 4 rights-reservation header.
  - Observed: robots.txt itself fetched fine; homepage and `/reviewlist.php` returned 403. No TOS page verified (fetch-blocked).
  - **Consequence:** manual/owner-mediated quote path only.
- **Accessibility:** Alphabetical review list (`reviewlist.php`), numeric review IDs (`viewreview.php?id=NNNN`), per-reviewer credit pages. Old-school PHP site, no RSS confirmed. All bot-blocked.
- **Lens/voice:** Independent, veteran, consumer-honest. One of the oldest EN anime review desks (club founded 1993 at Arizona State; website since 1996). Covers old and obscure shows mainstream desks skip — exactly the "would Kuro shelve this?" signal the 2026-08-02 research memo noted.
- **Proposed trust tier:** **B** — long-lived named-critic desk with a real archive and honest verdicts, but reviews are less craft-argumentative than Tier A material and automated access is forbidden.
- **Example review URL:** https://themanime.org/viewreview.php?id=1524 (review of "K") — verified to exist via search index; direct fetch returned 403, contents not read first-hand this pass.
