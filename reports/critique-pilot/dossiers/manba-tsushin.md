# Dossier: マンバ通信 (Manba Tsūshin)

**Scouted:** 2026-08-05 (JP scout, Phase 3 Round 0) · **Class:** manga-essay platform (マンガ批評)

> **INGESTION BLOCKED — record prominently.** robots.txt explicitly disallows ClaudeBot
> site-wide, declares `ai-train=no`, and a Cloudflare WAF returns 403 to every fetch
> attempted this pass (listing pages, old domain, individual article, browser-UA curl).
> Everything below the robots row is assembled from search-index snippets, not page reads.

| Field | Finding |
|---|---|
| Name | マンバ通信 (Manba Tsūshin) — editorial magazine of the manga community/review service マンバ |
| URL | https://manba.co.jp/manba_magazines (former standalone domain magazine.manba.co.jp also 403s) |
| Scope | Manga only |
| Language | Japanese |
| Named critics? | Historically yes — bylined freelance manga writers and interviewers (search snippets show e.g. a two-part 嶺岸信明 interview, a ティーンズラブコミック history essay). Could **not** verify current bylines directly this pass (fetch blocked). |
| Review depth | Essays and long interviews, not capsule reviews — genre histories, single-work readings, creator interviews. Historically genuine マンガ批評 with argumentation. Depth this pass is inferred from titles/snippets only; no article body was readable. |
| Archive size (honest) | Index reports 全88ページ of articles; at ~10–12 items/page that is roughly **900–1,100 articles** accumulated since ~2017. Estimate, not a count. |
| Active? | **ACTIVE but slow** — search-visible 2026 cadence: Jan 2, Feb 1, Mar 2, Apr 3, May 1 articles (~1–3/month). Well within the 6-month bar, but a fraction of its earlier pace. |
| robots.txt | Fetched verbatim (manba.co.jp/robots.txt), Cloudflare managed content-signals block: `User-agent: *` / `Content-Signal: search=yes,ai-train=no,use=reference` / `Allow: /` — then explicit full blocks: `User-agent: ClaudeBot` / `Disallow: /` (likewise Amazonbot, Applebot-Extended, Bytespider, CCBot, CloudflareBrowserRenderingCrawler, Google-Extended, GPTBot, meta-externalagent). Header asserts EU DSM Art. 4 rights reservation. |
| Server access reality | Cloudflare WAF: HTTP 403 on /manba_magazines and on article page /manba_magazines/26771 even with a desktop-browser UA. |
| TOS posture | Not readable this pass (403). robots content-signals already constitute an express reservation; treat as prohibition. |
| Accessibility | Structurally good (paginated index, category pages incl. インタビュー) — but inaccessible to us in practice. |
| Lens/voice | Reader-culture manga essays: genre archaeology, creator careers, "why this manga matters" pieces; adjacent to the マンバ review community. |
| Proposed tier | **D on merit / treat as E for this pilot** — a real manga-essay lens worth respecting, but robots + WAF are an explicit no; do not fetch unless the owner obtains permission from the operator. |
| Example visited | None — https://manba.co.jp/manba_magazines/26771 (嶺岸信明インタビュー 前編, found via search) returned 403. URL recorded for reference only. |
