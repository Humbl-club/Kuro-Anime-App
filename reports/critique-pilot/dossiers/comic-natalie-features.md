# Dossier: コミックナタリー 特集・インタビュー desk (Comic Natalie features)

**Scouted:** 2026-08-05 (JP scout, Phase 3 Round 0) · **Class:** manga desk candidate — judged honestly against the critique bar

| Field | Finding |
|---|---|
| Name | コミックナタリー (Comic Natalie), feature desk = 特集・インタビュー ("Power Push"); operator 株式会社ナターシャ (Natasha, Inc.), founded Dec 2008 |
| URL | https://natalie.mu/comic (feature index: https://natalie.mu/comic/pp) |
| Scope | Manga primarily (plus anime-adjacent media-mix news) |
| Language | Japanese |
| Named critics? | No critics. Staff reporters write 3,500+ news items/month across the Natalie network (operator's own figure, natasha.co.jp/natalie.html); features are creator/voice-actor interviews, typically without a critical byline persona. |
| Review depth | **This is not a critique desk.** Honest judgment: content is (a) high-volume short news — 新刊/magazine release lists, announcements (July 2026 samples: 発売分マンガ雑誌リスト, 2026夏アニメ放送開始) — and (b) professional but promotional creator interviews timed to releases. No review section, no verdict essays, no argued criticism. Interview content can carry authorial-intent context, which is a different (and weaker) signal than critique. |
| Archive size (honest) | Enormous as news (~17M PV/month per operator, archives to 2008); as *critique*, effectively zero. |
| Active? | **ACTIVE** — daily publication confirmed via search index (multiple July 2026 items). |
| robots.txt | Fetched verbatim: `user-agent:*` / `Allow: /` with only utility-path Disallows (galleries, search, cinema schedule endpoints, /my). **No AI-agent blocks on paper.** |
| Server access reality | **Blocked in practice.** All programmatic fetches — homepage, /comic/pp, the TOS page, and even RSS (/comic/feed/news) — return an AWS WAF "Human Verification" challenge (verified with browser-UA curl and with WebFetch, both 2026-08-05). Ingestion would require real-browser automation, i.e. deliberately working around a bot challenge — against §9 posture. |
| TOS posture | TOS exists at https://natalie.mu/info/termsofuse but is itself behind the WAF challenge; **not read this pass** (recorded honestly). Operator is a professional publisher; assume strict 無断転載 prohibition. |
| Accessibility | Index/RSS exist structurally but are WAF-challenged; no accessible machine path. |
| Lens/voice | Trade news + promotional interview desk; neutral-to-promotional register, no evaluative stance. |
| Proposed tier | **E for critique ingestion** — not critique (fails the "argues, not reacts" bar by content type) and fetch-blocked at the WAF layer; interviews could someday serve authorial-context enrichment, but that is a different pipeline with permission. |
| Example visited | None successfully — every fetch attempt returned the WAF challenge page (homepage, /comic/pp, feed). Feature index URL for reference only: https://natalie.mu/comic/pp |
