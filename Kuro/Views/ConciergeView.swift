import SwiftUI

struct ConciergeView: View {
    @Environment(SupabaseService.self) private var supabaseService

    let assistantEnabled: Bool

    @State private var input: String = ""
    @FocusState private var inputFocused: Bool
    @State private var messages: [ConciergeMessage] = []
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var selectedByItemId: [String: SupabaseService.ConciergeCandidate] = [:]
    @State private var lastApplySessionId: String? = nil
    @State private var selectedAnime: Anime? = nil
    @State private var selectedManga: Manga? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var assistantExpanded: Bool = false
    @State private var assistantOffset: CGSize = .zero
    @State private var assistantDragStart: CGSize = .zero

    private var hasActionBar: Bool {
        (activeItems?.isEmpty == false) || lastApplySessionId != nil
    }

    init(assistantEnabled: Bool = true) {
        self.assistantEnabled = assistantEnabled
    }

    var body: some View {
        ZStack {
            // Ambient background so glass has something to refract (kept very subtle).
            // Use a clear base so the sheet's material background stays visible.
            Color.clear.ignoresSafeArea()
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.06), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: -140, y: -220)
                .blur(radius: 0.5)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.05), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .frame(width: 420, height: 420)
                .offset(x: 160, y: -80)
                .blur(radius: 0.5)

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty {
                                ConciergeIntroCard()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 14)
                                    .padding(.bottom, 8)

                                ConciergeStarterActions(
                                    onPaste: { pasteFromClipboard() },
                                    onExampleImport: { seedExampleImport() },
                                    onExampleVibe: { seedExampleVibe() }
                                )
                                .frame(maxWidth: .infinity)
                            }

                            ForEach(messages) { msg in
                                ConciergeBubble(
                                    message: msg,
                                    selected: { item in selectedByItemId[item.id] },
                                    onSelect: { item, candidate in
                                        KuroAccessibility.impactHaptic(.light)
                                        selectedByItemId[item.id] = candidate
                                    },
                                    onOpenRecommendation: { rec in
                                        Task { await openRecommendation(rec) }
                                    },
                                    onQuickSave: { rec in
                                        Task { await quickSaveRecommendation(rec) }
                                    }
                                )
                                .id(msg.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            if isWorking {
                                ConciergeTypingIndicator()
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }

            if let activeItems, !activeItems.isEmpty {
                ConciergeActionBar(
                    selectedCount: activeSelectedCount,
                    hasAnySelection: activeSelectedCount > 0,
                    canUndo: lastApplySessionId != nil,
                    onApply: { Task { await applyActiveItems() } },
                    onUndo: { Task { await undoLastApply() } }
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    KuroGlassCard(cornerRadius: 22) { Color.clear }
                )
            } else if lastApplySessionId != nil {
                ConciergeActionBar(
                    selectedCount: 0,
                    hasAnySelection: false,
                    canUndo: true,
                    onApply: {},
                    onUndo: { Task { await undoLastApply() } }
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    KuroGlassCard(cornerRadius: 22) { Color.clear }
                )
            }

            Divider()
                .opacity(0.12)

                HStack(spacing: 10) {
                    TextField("Paste titles, or ask for a vibe…", text: $input, axis: .vertical)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.black.opacity(0.86))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .lineLimit(1...4)
                        .padding(.vertical, 10)
                        .focused($inputFocused)
                        .submitLabel(.send)
                        .onSubmit { Task { await send() } }

                    Button(action: { Task { await send() } }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking ? .black.opacity(0.2) : .black)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    KuroGlassCard(cornerRadius: 22) {
                        Color.clear
                    }
                )
                // Prevent the global pager swipe gesture from stealing drags/taps while typing.
                // This fixes "faulty" keyboard interactions and accidental page switches.
                .kuroSwipeExclusionZone()
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, hasActionBar ? 152 : 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if assistantEnabled {
                GeometryReader { geo in
                    KuroConciergeAssistant(
                        expanded: $assistantExpanded,
                        offset: $assistantOffset,
                        dragStart: $assistantDragStart,
                        baseBottomPadding: hasActionBar ? 168 : 104,
                        containerSize: geo.size
                    ) {
                        inputFocused = true
                    }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $selectedAnime) { anime in
            AnimeDetailView(anime: anime)
        }
        .sheet(item: $selectedManga) { manga in
            MangaDetailView(manga: manga)
        }
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorText = nil
        input = ""
        withAnimation(.easeInOut(duration: 0.18)) { isWorking = true }
        lastApplySessionId = nil

        let userMsg = ConciergeMessage(role: .user, text: text, items: nil)
        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
            messages.append(userMsg)
        }

        do {
            if looksLikeImport(text) {
                let response = try await supabaseService.conciergeParse(text: text, scope: .both)
                let auto = autoResolveForApply(items: response.items)

                var remaining = auto.remaining
                var llmItemsToApply: [[String: Any]] = []
                var appliedSummaryLines = auto.appliedSummaryLines

                if response.userId != nil, !remaining.isEmpty {
                    // Use the tiny LLM resolver to reduce taps for messy/typo inputs.
                    if let resolve = try? await supabaseService.conciergeResolve(items: remaining, maxCandidates: 6),
                       resolve.success,
                       let choices = resolve.choices,
                       !choices.isEmpty {
                        var appliedIds = Set<String>()

                        for choice in choices {
                            guard choice.pick >= 0 else { continue }
                            guard remaining.indices.contains(choice.i) else { continue }
                            let item = remaining[choice.i]
                            guard item.candidates.indices.contains(choice.pick) else { continue }
                            let picked = item.candidates[choice.pick]

                            selectedByItemId[item.id] = picked

                            // Only auto-apply LLM picks when confidence is high.
                            let titleSafe = isTitleAutoApplySafe(normalized: item.normalized, parsed: item.parsed, candidateTitle: picked.title_raw)
                            let canAutoApply = choice.confidence >= 0.88 && picked.score >= 0.70 && titleSafe
                            if !canAutoApply { continue }

                            let status = normalizedStatus(for: item.parsed.status, mediaType: picked.media_type)
                            var payload: [String: Any] = [
                                "raw": item.raw,
                                "mediaType": picked.media_type.uppercased(),
                                "mediaId": picked.media_id,
                                "status": status,
                                "confidence": picked.score,
                                "candidates": item.candidates.map { cand in
                                    [
                                        "media_type": cand.media_type,
                                        "media_id": cand.media_id,
                                        "variant_type": cand.variant_type,
                                        "title_raw": cand.title_raw,
                                        "score": cand.score,
                                    ]
                                },
                            ]

                            if let p = item.parsed.progressEpisodes { payload["progressEpisodes"] = p }
                            if let p = item.parsed.progressChapters { payload["progressChapters"] = p }
                            if let p = item.parsed.progressVolumes { payload["progressVolumes"] = p }
                            if let s = item.parsed.seasonNumber { payload["seasonNumber"] = s }
                            if let e = item.parsed.episodeInSeason { payload["episodeInSeason"] = e }
                            if let b = item.parsed.caughtUp { payload["caughtUp"] = b }
                            if let b = item.parsed.lastEpisode { payload["lastEpisode"] = b }
                            if let b = item.parsed.completed { payload["completed"] = b }

                            llmItemsToApply.append(payload)
                            appliedIds.insert(item.id)
                            appliedSummaryLines.append(
                                summaryLineForAppliedItem(title: picked.title_raw, mediaType: picked.media_type, status: status, parsed: item.parsed)
                            )
                        }

                        remaining = remaining.filter { !appliedIds.contains($0.id) }
                    }
                }

                let combinedToApply = auto.itemsToApply + llmItemsToApply

                if response.userId != nil, !combinedToApply.isEmpty {
                    let res = try await supabaseService.conciergeApply(items: combinedToApply)
                    if let sessionId = res.sessionId { lastApplySessionId = sessionId }
                    await supabaseService.fetchUserLists()
                    await supabaseService.fetchCollectionItems()

                    if remaining.isEmpty {
                        let details = appliedSummaryLines.isEmpty ? "" : ("\n" + appliedSummaryLines.prefix(6).map { "• \($0)" }.joined(separator: "\n"))
                        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                            messages.append(
                                ConciergeMessage(
                                    role: .assistant,
                                    text: res.success
                                        ? "Saved.\(details)"
                                        : "Applied with errors. You can undo and try again.",
                                    items: nil
                                )
                            )
                        }
                    } else {
                        // Preselect the top candidate for the rest so it feels fast.
                        for item in remaining {
                            guard let top = item.candidates.first else { continue }
                            if top.score >= 0.60 {
                                selectedByItemId[item.id] = top
                            }
                        }
                        let details = appliedSummaryLines.isEmpty ? "" : ("\n" + appliedSummaryLines.prefix(6).map { "• \($0)" }.joined(separator: "\n"))
                        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                            messages.append(
                                ConciergeMessage(
                                    role: .assistant,
                                    text: "Saved what I’m confident about.\(details)\n\nA few are still ambiguous — tap the right match, then APPLY.",
                                    items: remaining
                                )
                            )
                        }
                    }
                } else {
                    // Preselect obvious matches to reduce taps for common cases.
                    for item in response.items {
                        guard let top = item.candidates.first else { continue }
                        if top.score >= 0.60 {
                            selectedByItemId[item.id] = top
                        }
                    }
                    let missing = response.items.filter { !$0.candidateError.isNilOrEmpty }.count
                    let summaryText =
                        response.userId == nil
                        ? "Sign in to apply changes. I can still help you match titles:"
                        : (missing > 0
                            ? "Parsed \(response.items.count) item(s). Some titles didn’t match — tap candidates, then APPLY."
                            : "Parsed \(response.items.count) item(s). Tap candidates, then APPLY.")
                    withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                        messages.append(
                            ConciergeMessage(
                                role: .assistant,
                                text: summaryText,
                                items: response.items
                            )
                        )
                    }
                }
            } else {
                let rec = try await supabaseService.conciergeRecommend(text: text, scope: .both, limit: 8)
                let sets = (rec.sets ?? []).filter { ($0.items ?? []).isEmpty == false }
                let flattened = sets.flatMap { $0.items ?? [] }
                let displayItems = !flattened.isEmpty ? flattened : (rec.items ?? [])

                if rec.success, !displayItems.isEmpty {
                    // Prefetch covers so the recommendation rail renders instantly.
                    let urls = displayItems
                        .compactMap { URL(string: $0.coverImageMedium ?? "") }
                        .prefix(16)
                    if !urls.isEmpty {
                        Task { await ImagePipeline.shared.prefetch(urls: Array(urls), maxPixelSize: 520) }
                    }
                    withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                        messages.append(
                            ConciergeMessage(
                                role: .assistant,
                                text: rec.message ?? "Here are a few picks:",
                                items: nil,
                                recommendations: displayItems,
                                recommendationSets: sets.isEmpty ? nil : sets,
                                recommendationCategories: rec.categories
                            )
                        )
                    }
                } else {
                    withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                        messages.append(
                            ConciergeMessage(
                                role: .assistant,
                                text: rec.message ?? "Tell me a vibe (funny, sad, cozy, action) and I’ll recommend something new-to-you.",
                                items: nil,
                                recommendations: nil
                            )
                        )
                    }
                }
            }
        } catch {
            if let guardrail = error as? SupabaseService.ConciergeGuardrailsError {
                errorText = guardrail.localizedDescription
                showToast(.init(kind: .error, title: "Slow down", subtitle: guardrail.localizedDescription, actionTitle: nil, onAction: nil), autoDismissSeconds: 3.0)
            } else {
                errorText = "Concierge error: \(error.localizedDescription)"
                showToast(.init(kind: .error, title: "Concierge error", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil), autoDismissSeconds: 3.0)
            }
        }

        withAnimation(.easeInOut(duration: 0.18)) { isWorking = false }
    }

    private func looksLikeImport(_ text: String) -> Bool {
        // High precision: false positives feel like "wrong responses" because we route to import parsing
        // instead of recommendations. We prefer a few false negatives over misrouting vibes.
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = t.lowercased()

        if t.contains("\n") { return true }

        // Explicit import language (EN + DE)
        if l.contains("watching") || l.contains("reading") || l.contains("completed") || l.contains("finished") || l.contains("dropped") { return true }
        if l.contains("i watched") || l.contains("i'm watching") || l.contains("im watching") { return true }
        if l.contains("caught up") || l.contains("up to date") { return true }
        if l.contains("ich habe") || l.contains("ich schaue") || l.contains("ich gucke") || l.contains("ich sehe") || l.contains("ich lese") { return true }
        if l.contains("staffel") || l.contains("folge") || l.contains("kapitel") || l.contains("band") { return true }

        // Progress patterns
        if l.contains(" ep ") || l.contains("episode") || l.contains("chapter") || l.contains(" vol") { return true }
        if l.range(of: #"s\d{1,2}\s*e\d{1,4}"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"\b\d{1,2}\s*x\s*\d{1,4}\b"#, options: .regularExpression) != nil { return true }

        // Comma-separated lists are common for vibes ("funny, not childish") so only treat commas
        // as import if we have multiple title-like segments.
        if t.contains(",") {
            let parts = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count >= 2 {
                let titleLikeCount = parts.filter { segmentLooksTitleLike($0) }.count
                if titleLikeCount >= 2 { return true }
            }
        }

        // Short prompts like "funny anime" shouldn't be treated as import.
        if t.count <= 28 { return false }
        return false
    }

    private func segmentLooksTitleLike(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return false }
        let l = t.lowercased()

        // Natural language / vibe words are not titles.
        let vibeMarkers = ["something", "funny", "sad", "cozy", "vibe", "recommend", "suggest", "like", "but", "not", "please", "anime", "manga"]
        if vibeMarkers.contains(where: { l.contains($0) }) && t.split(separator: " ").count <= 6 {
            return false
        }

        // Strong title hints.
        if t.contains("(") || t.contains(")") { return true }
        if t.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"\b(ep|episode|ch|chapter|vol|volume|s\d+e\d+|\d+x\d+)\b"#, options: .regularExpression) != nil { return true }

        // Heuristic: multiple words + some uppercase characters.
        let words = t.split(separator: " ")
        if words.count >= 2 && t.range(of: #"[A-Z]"#, options: .regularExpression) != nil {
            return true
        }

        // If user pasted lowercased titles, allow "two+ words" as a weak signal.
        if words.count >= 3 { return true }

        return false
    }

    private struct AutoResolveResult {
        let itemsToApply: [[String: Any]]
        let remaining: [SupabaseService.ConciergeParseItem]
        let appliedSummaryLines: [String]
    }

    private func autoResolveForApply(items: [SupabaseService.ConciergeParseItem]) -> AutoResolveResult {
        var toApply: [[String: Any]] = []
        var remaining: [SupabaseService.ConciergeParseItem] = []
        var appliedSummaryLines: [String] = []

        for item in items {
            if !(item.candidateError?.isEmpty ?? true) { remaining.append(item); continue }
            guard let top = item.candidates.first else { remaining.append(item); continue }
            let secondScore = item.candidates.dropFirst().first?.score ?? 0

            // Confidence rules: high similarity and not too ambiguous.
            let margin = top.score - secondScore
            // Auto-apply must be extremely safe. We trade friction for avoiding wrong saves.
            // Score-only thresholds are not enough for ambiguous short titles; add a title plausibility gate.
            let confident =
                (top.score >= 1.10 && margin >= 0.10) ||
                (top.score >= 1.00 && margin >= 0.22)
            let titleSafe = isTitleAutoApplySafe(normalized: item.normalized, parsed: item.parsed, candidateTitle: top.title_raw)
            if !confident || !titleSafe { remaining.append(item); continue }

            let status = normalizedStatus(for: item.parsed.status, mediaType: top.media_type)
            var payload: [String: Any] = [
                "raw": item.raw,
                "mediaType": top.media_type.uppercased(),
                "mediaId": top.media_id,
                "status": status,
                "confidence": top.score,
                "candidates": item.candidates.map { cand in
                    [
                        "media_type": cand.media_type,
                        "media_id": cand.media_id,
                        "variant_type": cand.variant_type,
                        "title_raw": cand.title_raw,
                        "score": cand.score,
                    ]
                },
            ]

            if let p = item.parsed.progressEpisodes { payload["progressEpisodes"] = p }
            if let p = item.parsed.progressChapters { payload["progressChapters"] = p }
            if let p = item.parsed.progressVolumes { payload["progressVolumes"] = p }
            if let s = item.parsed.seasonNumber { payload["seasonNumber"] = s }
            if let e = item.parsed.episodeInSeason { payload["episodeInSeason"] = e }
            if let b = item.parsed.caughtUp { payload["caughtUp"] = b }
            if let b = item.parsed.lastEpisode { payload["lastEpisode"] = b }
            if let b = item.parsed.completed { payload["completed"] = b }

            toApply.append(payload)

            appliedSummaryLines.append(summaryLineForAppliedItem(title: top.title_raw, mediaType: top.media_type, status: status, parsed: item.parsed))
        }

        return AutoResolveResult(itemsToApply: toApply, remaining: remaining, appliedSummaryLines: appliedSummaryLines)
    }

    private func isTitleAutoApplySafe(
        normalized: String,
        parsed: SupabaseService.ConciergeParseItemParsed,
        candidateTitle: String
    ) -> Bool {
        func tokens(_ s: String) -> [String] {
            let stop: Set<String> = [
                // EN
                "the", "a", "an", "of", "and", "or", "to", "in", "on", "for", "with",
                // DE
                "der", "die", "das", "ein", "eine", "einer", "eines", "und", "oder", "zu", "im", "in", "am", "auf", "mit",
            ]
            let cleaned = s
                .lowercased()
                .replacingOccurrences(of: #"[^\\p{L}\\p{N}\\s]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cleaned.split(separator: " ").map(String.init)
            return parts.filter { !$0.isEmpty && !stop.contains($0) }
        }

        let q = tokens(normalized)
        let c = tokens(candidateTitle)
        guard !q.isEmpty, !c.isEmpty else { return false }

        // Single-token titles are the most ambiguous (e.g. Naruto vs Naruto Shippuden).
        // Only auto-apply if the candidate is also single-token and exact.
        // If the user also mentioned a season number, force disambiguation instead of guessing.
        if q.count == 1 {
            if let season = parsed.seasonNumber, season >= 2 { return false }
            return c.count == 1 && c[0] == q[0]
        }

        let qSet = Set(q)
        let cSet = Set(c)
        let overlap = Double(qSet.intersection(cSet).count) / Double(qSet.count)

        // Require that most query tokens appear in the chosen title.
        if overlap < 0.75 { return false }

        // Avoid auto-apply to long variants when the user gave a short base title.
        if c.count - q.count >= 4 { return false }

        return true
    }

    private func summaryLineForAppliedItem(
        title: String,
        mediaType: String,
        status: String,
        parsed: SupabaseService.ConciergeParseItemParsed
    ) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = status.uppercased()

        let verb: String
        switch s {
        case "COMPLETED": verb = "Completed"
        case "WATCHING": verb = "Watching"
        case "READING": verb = "Reading"
        case "PLANNING": verb = "Planned"
        case "DROPPED": verb = "Dropped"
        case "PAUSED": verb = "Paused"
        default: verb = s.capitalized
        }

        if mediaType.uppercased() == "ANIME" {
            if let season = parsed.seasonNumber, let ep = parsed.episodeInSeason {
                return "\(cleanTitle) — \(verb) (S\(season)E\(ep))"
            }
            if let ep = parsed.progressEpisodes {
                return "\(cleanTitle) — \(verb) (Ep \(ep))"
            }
            return "\(cleanTitle) — \(verb)"
        } else {
            if let ch = parsed.progressChapters {
                return "\(cleanTitle) — \(verb) (Ch \(ch))"
            }
            if let vol = parsed.progressVolumes {
                return "\(cleanTitle) — \(verb) (Vol \(vol))"
            }
            return "\(cleanTitle) — \(verb)"
        }
    }

    private var activeItems: [SupabaseService.ConciergeParseItem]? {
        messages.last(where: { $0.role == .assistant && ($0.items?.isEmpty == false) })?.items
    }

    private var activeSelectedCount: Int {
        guard let items = activeItems else { return 0 }
        return items.reduce(0) { acc, item in
            acc + (selectedByItemId[item.id] != nil ? 1 : 0)
        }
    }

    private func normalizedStatus(for raw: String?, mediaType: String) -> String {
        let s = (raw ?? "").uppercased()
        if mediaType == "MANGA", s == "WATCHING" { return "READING" }
        if mediaType == "ANIME", s == "READING" { return "WATCHING" }
        if s.isEmpty { return "PLANNING" }
        return s
    }

    private func applyActiveItems() async {
        guard let items = activeItems else { return }
        let chosen = items.compactMap { item -> [String: Any]? in
            guard let c = selectedByItemId[item.id] else { return nil }
            let status = normalizedStatus(for: item.parsed.status, mediaType: c.media_type)
            var payload: [String: Any] = [
                "raw": item.raw,
                "mediaType": c.media_type,
                "mediaId": c.media_id,
                "status": status,
                "confidence": c.score,
                "candidates": item.candidates.map { cand in
                    [
                        "media_type": cand.media_type,
                        "media_id": cand.media_id,
                        "variant_type": cand.variant_type,
                        "title_raw": cand.title_raw,
                        "score": cand.score,
                    ]
                },
            ]
            if let p = item.parsed.progressEpisodes { payload["progressEpisodes"] = p }
            if let p = item.parsed.progressChapters { payload["progressChapters"] = p }
            if let p = item.parsed.progressVolumes { payload["progressVolumes"] = p }
            if let s = item.parsed.seasonNumber { payload["seasonNumber"] = s }
            if let e = item.parsed.episodeInSeason { payload["episodeInSeason"] = e }
            if let b = item.parsed.caughtUp { payload["caughtUp"] = b }
            if let b = item.parsed.lastEpisode { payload["lastEpisode"] = b }
            if let b = item.parsed.completed { payload["completed"] = b }
            return payload
        }

        guard !chosen.isEmpty else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            let summaryLines: [String] = items.compactMap { item in
                guard let c = selectedByItemId[item.id] else { return nil }
                let status = normalizedStatus(for: item.parsed.status, mediaType: c.media_type)
                return summaryLineForAppliedItem(title: c.title_raw, mediaType: c.media_type, status: status, parsed: item.parsed)
            }

            let res = try await supabaseService.conciergeApply(items: chosen)
            if let sessionId = res.sessionId { lastApplySessionId = sessionId }
            await supabaseService.fetchUserLists()
            await supabaseService.fetchCollectionItems()
            await supabaseService.fetchCollectionFeed(status: nil)
            let details = summaryLines.isEmpty ? "" : ("\n" + summaryLines.prefix(8).map { "• \($0)" }.joined(separator: "\n"))
            messages.append(
                ConciergeMessage(
                    role: .assistant,
                    text: res.success
                        ? "Saved.\(details)"
                        : "Applied with errors. You can try again or undo the last batch.",
                    items: nil
                )
            )
            if res.success {
                let n = chosen.count
                showToast(
                    .init(
                        kind: .success,
                        title: "Saved \(n) item\(n == 1 ? "" : "s")",
                        subtitle: lastApplySessionId == nil ? nil : "You can undo the batch.",
                        actionTitle: lastApplySessionId == nil ? nil : "Undo",
                        onAction: lastApplySessionId == nil ? nil : { Task { await undoLastApply() } }
                    ),
                    autoDismissSeconds: lastApplySessionId == nil ? 2.0 : 4.5
                )
            } else {
                showToast(.init(kind: .error, title: "Applied with issues", subtitle: "Try again or undo.", actionTitle: nil, onAction: nil))
            }
        } catch {
            errorText = "Apply failed: \(error.localizedDescription)"
            showToast(.init(kind: .error, title: "Apply failed", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil))
        }
    }

    private func undoLastApply() async {
        guard let sessionId = lastApplySessionId else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            let res = try await supabaseService.conciergeUndo(sessionId: sessionId)
            await supabaseService.fetchUserLists()
            await supabaseService.fetchCollectionItems()
            await supabaseService.fetchCollectionFeed(status: nil)
            lastApplySessionId = nil
            messages.append(
                ConciergeMessage(
                    role: .assistant,
                    text: res.success ? "Undid last batch." : "Undo failed. Try again.",
                    items: nil
                )
            )
            showToast(.init(kind: res.success ? .success : .error, title: res.success ? "Undid last batch" : "Undo failed", subtitle: nil, actionTitle: nil, onAction: nil))
        } catch {
            errorText = "Undo failed: \(error.localizedDescription)"
            showToast(.init(kind: .error, title: "Undo failed", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil))
        }
    }

    private func openRecommendation(_ item: SupabaseService.ConciergeRecommendResponse.Item) async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            if item.mediaType.uppercased() == "ANIME" {
                let anime = try await supabaseService.fetchAnimeById(item.mediaId)
                guard let anime else {
                    errorText = "Couldn’t find that anime in the database."
                    return
                }
                selectedAnime = anime
            } else {
                let manga = try await supabaseService.fetchMangaById(item.mediaId)
                guard let manga else {
                    errorText = "Couldn’t find that manga in the database."
                    return
                }
                selectedManga = manga
            }
        } catch {
            errorText = "Couldn’t open: \(error.localizedDescription)"
        }
    }

    private func quickSaveRecommendation(_ item: SupabaseService.ConciergeRecommendResponse.Item) async {
        let mediaType = item.mediaType.uppercased() == "ANIME" ? "anime" : "manga"
        await supabaseService.upsertUserListEntry(
            mediaId: item.mediaId,
            mediaType: mediaType,
            status: .planning,
            progress: 0,
            rating: nil,
            notes: nil
        )
        showToast(.init(kind: .success, title: "Added to Planning", subtitle: item.title, actionTitle: nil, onAction: nil))
    }

    @MainActor
    private func showToast(_ next: KuroToastState, autoDismissSeconds: Double = 2.5) {
        toastDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            toast = next
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0.8, autoDismissSeconds) * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toast = nil
                }
            }
        }
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        guard let t = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty
        else {
            showToast(.init(kind: .info, title: "Clipboard is empty", subtitle: "Copy a list of titles, then tap Paste.", actionTitle: nil, onAction: nil))
            return
        }
        input = t
        inputFocused = true
        KuroAccessibility.impactHaptic(.light)
        #endif
    }

    private func seedExampleImport() {
        input = """
        Attack on Titan (completed)
        Jujutsu Kaisen up to ep 12
        Hunter x Hunter (2011)
        """
        inputFocused = true
        KuroAccessibility.impactHaptic(.light)
    }

    private func seedExampleVibe() {
        input = "Something funny, premium, not childish."
        inputFocused = true
        KuroAccessibility.impactHaptic(.light)
    }
}

private struct ConciergeBubble: View {
    let message: ConciergeMessage
    let selected: (SupabaseService.ConciergeParseItem) -> SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeParseItem, SupabaseService.ConciergeCandidate) -> Void
    let onOpenRecommendation: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onQuickSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    @State private var hiddenRecommendationIds: Set<String> = []
    @State private var stepIndex: Int = 0

    private func glassBubble<Content: View>(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.72), Color.white.opacity(0.18), Color.black.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 10)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if message.role == .user {
                Text(message.text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.92))
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                glassBubble(cornerRadius: 18) {
                    Text(message.text)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.black.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let items = message.items, !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.raw)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black)
                                Spacer()
                                if let hint = item.parsed.mediaTypeHint {
                                    Text(hint)
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(1.0)
                                        .foregroundColor(.black.opacity(0.45))
                                }
                            }

                            if !item.candidates.isEmpty {
                                let top = item.candidates.prefix(5)
                                let picked = selected(item)
                                ForEach(Array(top.enumerated()), id: \.offset) { _, c in
                                    Button(action: { onSelect(item, c) }) {
                                        HStack(spacing: 10) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(c.title_raw)
                                                    .font(.system(size: 13, weight: .regular))
                                                    .foregroundColor(.black.opacity(0.85))
                                                    .lineLimit(1)
                                                Text("\(c.media_type) • \(String(format: "%.2f", c.score))")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .tracking(1.0)
                                                    .foregroundColor(.black.opacity(0.35))
                                            }
                                            Spacer()
                                            Image(systemName: picked == c ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 16, weight: .regular))
                                                .foregroundColor(picked == c ? .black : .black.opacity(0.2))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(picked == c ? Color.black.opacity(0.06) : Color.black.opacity(0.03))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else if let err = item.candidateError, !err.isEmpty {
                                Text("No candidates (missing title_search/search_titles?)")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.black.opacity(0.5))
                            } else {
                                Text("No candidates")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.black.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.03))
                        )
                    }
                }
            }

            if let cats = message.recommendationCategories, !cats.isEmpty,
               ((message.recommendationSets ?? []).isEmpty == false || (message.recommendations ?? []).isEmpty == false) {
                ConciergeCategoryPills(categories: cats)
            }

            if let sets = message.recommendationSets, !sets.isEmpty {
                ConciergeRecommendationSetsDeck(
                    sets: sets,
                    hiddenIds: $hiddenRecommendationIds,
                    onOpen: onOpenRecommendation,
                    onSave: onQuickSave
                )
            } else if let recs = message.recommendations, !recs.isEmpty {
                ConciergeRecommendationDeck(
                    items: recs,
                    hiddenIds: $hiddenRecommendationIds,
                    onOpen: onOpenRecommendation,
                    onSave: onQuickSave
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct ConciergeCategoryPills: View {
    let categories: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { c in
                    Text(c.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.3)
                        .foregroundColor(.black.opacity(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.05))
                        )
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 26)
        .kuroSwipeExclusionZone()
    }
}

private struct ConciergeRecommendationDeck: View {
    let items: [SupabaseService.ConciergeRecommendResponse.Item]
    @Binding var hiddenIds: Set<String>
    let onOpen: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void

    private var visible: [SupabaseService.ConciergeRecommendResponse.Item] {
        items.filter { !hiddenIds.contains($0.id) }
    }

    private var classics: [SupabaseService.ConciergeRecommendResponse.Item] {
        visible.filter { ($0.signals ?? []).map { $0.uppercased() }.contains("CLASSIC") }
    }
    private var picks: [SupabaseService.ConciergeRecommendResponse.Item] {
        let classicIds = Set(classics.map { $0.id })
        return visible.filter { !classicIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if picks.isEmpty && classics.isEmpty {
                Text("Nothing else in this set — try a different vibe.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.black.opacity(0.5))
            } else {
                if !picks.isEmpty {
                    ConciergeRecommendationRail(
                        title: "PICKS",
                        items: picks,
                        hiddenIds: $hiddenIds,
                        onOpen: onOpen,
                        onSave: onSave
                    )
                }
                if !classics.isEmpty {
                    ConciergeRecommendationRail(
                        title: "CLASSICS",
                        items: classics,
                        hiddenIds: $hiddenIds,
                        onOpen: onOpen,
                        onSave: onSave
                    )
                }
            }
        }
    }
}

private struct ConciergeRecommendationSetsDeck: View {
    let sets: [SupabaseService.ConciergeRecommendResponse.Set]
    @Binding var hiddenIds: Set<String>
    let onOpen: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sets) { set in
                let items = set.items ?? []
                if !items.isEmpty {
                    ConciergeRecommendationRail(
                        title: set.title.uppercased(),
                        items: items,
                        hiddenIds: $hiddenIds,
                        onOpen: onOpen,
                        onSave: onSave
                    )
                }
            }
        }
    }
}

private struct ConciergeRecommendationRail: View {
    let title: String
    let items: [SupabaseService.ConciergeRecommendResponse.Item]
    @Binding var hiddenIds: Set<String>
    let onOpen: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void

    private var visible: [SupabaseService.ConciergeRecommendResponse.Item] {
        items.filter { !hiddenIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.black.opacity(0.55))
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(visible) { item in
                        ConciergeRecommendationCompactCard(
                            item: item,
                            onOpen: { onOpen(item) },
                            onSave: {
                                onSave(item)
                                hiddenIds.insert(item.id)
                            },
                            onSkip: {
                                KuroAccessibility.impactHaptic(.light)
                                hiddenIds.insert(item.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
            .kuroSwipeExclusionZone()
        }
    }
}

private struct ConciergeRecommendationCompactCard: View {
    let item: SupabaseService.ConciergeRecommendResponse.Item
    let onOpen: () -> Void
    let onSave: () -> Void
    let onSkip: () -> Void

    private let width: CGFloat = 176
    private var height: CGFloat { width / 0.72 }

    private var displayScore: Double? {
        guard let s = item.averageScore else { return nil }
        return Double(s) / 10.0
    }

    private var badges: [String] {
        var out: [String] = []
        if let s = item.averageScore, s >= 88 { out.append("MASTERPIECE") }
        else if let y = item.year, y > 0 && y <= 2010, (item.averageScore ?? 0) >= 80 { out.append("CLASSIC") }
        if (item.matchCount ?? 0) >= 2 { out.append("MATCH") }
        return out
    }

    private var signals: [String] {
        let raw = (item.signals ?? []).map { $0.uppercased() }
        // De-dup and keep tight.
        var seen: Set<String> = []
        var out: [String] = []
        for s in (badges + raw) {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty { continue }
            if seen.contains(v) { continue }
            seen.insert(v)
            out.append(v)
            if out.count >= 4 { break }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                onOpen()
            }) {
                ZStack(alignment: .topTrailing) {
                    KuroCachedAsyncImage(url: URL(string: item.coverImageMedium ?? ""), maxPixelSize: 220) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: width, height: height)
                                .clipped()
                        case .failure, .empty:
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                                .frame(width: width, height: height)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let s = displayScore, s > 0 {
                        KuroScoreBadge(score: s)
                            .padding(8)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.92))
                    .lineLimit(2)
                    .frame(height: 34, alignment: .top)

                HStack(spacing: 6) {
                    if let y = item.year { Text(String(y)) }
                    if let f = item.format, !f.isEmpty {
                        if item.year != nil { Text("·") }
                        Text(f)
                    }
                }
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.black.opacity(0.55))
                .frame(height: 14, alignment: .topLeading)

                if let blurb = item.blurb, !blurb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(blurb)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.black.opacity(0.62))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button(action: onSkip) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black.opacity(0.55))
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.03))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onSave) {
                        HStack(spacing: 8) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("SAVE")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.4)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.90))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint("Recommendation. Save or open details.")
    }
}

private struct ConciergeActionBar: View {
    let selectedCount: Int
    let hasAnySelection: Bool
    let canUndo: Bool
    let onApply: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onUndo) {
                Text("UNDO")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(canUndo ? .black : .black.opacity(0.25))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(canUndo ? 0.04 : 0.02))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)

            Spacer()

            Button(action: onApply) {
                HStack(spacing: 8) {
                    Text("APPLY")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                    Text("\(selectedCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.0)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hasAnySelection ? Color.black : Color.black.opacity(0.2))
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasAnySelection)
        }
    }
}

private struct ConciergeTypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Circle().fill(Color.black.opacity(0.25)).frame(width: 6, height: 6).opacity(phase == 0 ? 1 : 0.35)
                    .scaleEffect(phase == 0 ? 1.15 : 0.95)
                Circle().fill(Color.black.opacity(0.25)).frame(width: 6, height: 6).opacity(phase == 1 ? 1 : 0.35)
                    .scaleEffect(phase == 1 ? 1.15 : 0.95)
                Circle().fill(Color.black.opacity(0.25)).frame(width: 6, height: 6).opacity(phase == 2 ? 1 : 0.35)
                    .scaleEffect(phase == 2 ? 1.15 : 0.95)
            }
            Text("Thinking")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.black.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.72), Color.white.opacity(0.18), Color.black.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 10)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 220_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

private struct ConciergeIntroCard: View {
    var body: some View {
        KuroGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    KuroConciergeMark(size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONCIERGE")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(2.0)
                            .foregroundColor(.black.opacity(0.80))
                        Text("Imports + recommendations")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.black.opacity(0.55))
                    }

                    Spacer(minLength: 0)
                }

                Text("Paste titles to import, or describe the mood.\nDefaults are clean — no adult content.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black.opacity(0.62))
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Concierge. Paste titles to import, or ask for a vibe.")
    }
}

private struct ConciergeStarterActions: View {
    let onPaste: () -> Void
    let onExampleImport: () -> Void
    let onExampleVibe: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KuroGlassPill(
                title: "Paste from clipboard",
                subtitle: "Fast import",
                systemImage: "doc.on.clipboard",
                action: onPaste
            )
            .offset(y: appeared ? 0 : 6)
            .opacity(appeared ? 1 : 0)

            KuroGlassPill(
                title: "Try an import example",
                subtitle: "Shows the format",
                systemImage: "text.append",
                action: onExampleImport
            )
            .offset(y: appeared ? 0 : 10)
            .opacity(appeared ? 1 : 0)

            KuroGlassPill(
                title: "Give me a vibe",
                subtitle: "Recommendations",
                systemImage: "sparkles",
                action: onExampleVibe
            )
            .offset(y: appeared ? 0 : 14)
            .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) {
                appeared = true
            }
        }
    }
}

private struct KuroConciergeAssistant: View {
    @Binding var expanded: Bool
    @Binding var offset: CGSize
    @Binding var dragStart: CGSize
    let baseBottomPadding: CGFloat
    let containerSize: CGSize
    let onTapMascot: () -> Void

    @Namespace private var mascotNS
    @State private var pulse: Bool = false

    private let panelWidth: CGFloat = 316
    private let panelHeight: CGFloat = 148

    var body: some View {
        let clamped = clamp(offset: offset)

        VStack(spacing: 0) {
            if expanded {
                KuroGlassCard(cornerRadius: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            KuroConciergeMark(size: 34)
                                .matchedGeometryEffect(id: "kurochan", in: mascotNS)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("CONCIERGE")
                                    .font(.system(size: 12, weight: .semibold))
                                    .tracking(2.0)
                                    .foregroundColor(.black.opacity(0.78))
                                Text("Imports + recommendations")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.black.opacity(0.55))
                            }
                            Spacer(minLength: 0)

                            Button(action: { withAnimation(.easeInOut(duration: 0.18)) { expanded = false } }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.55))
                                    .frame(width: 34, height: 34)
                                    .background(
                                        Circle().fill(Color.white.opacity(0.35))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Paste a list to import, or ask for a vibe.\nClean results by default — no adult content.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.black.opacity(0.62))

                        Button(action: {
                            KuroAccessibility.impactHaptic(.light)
                            onTapMascot()
                        }) {
                            HStack(spacing: 10) {
                                Text("START CHAT")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1.8)
                                    .foregroundColor(.black.opacity(0.82))
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.42))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.32))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 0.8))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
                }
                .overlay(alignment: .topTrailing) {
                    // Subtle sheen that makes the glass feel premium.
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 180, height: 140)
                    .rotationEffect(.degrees(-20))
                    .offset(x: 40, y: -30)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                }
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            offset = CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            let next = clamp(offset: offset)
                            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.86)) {
                                offset = next
                            }
                            dragStart = next
                        }
                )
            } else {
                Button(action: {
                    withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.86)) { expanded = true }
                }) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.9)
                            )
                            .frame(width: 56, height: 56)

                        Circle()
                            .strokeBorder(Color.white.opacity(pulse ? 0.65 : 0.25), lineWidth: 1.1)
                            .frame(width: 56, height: 56)
                            .scaleEffect(pulse ? 1.08 : 0.96)
                            .opacity(pulse ? 1.0 : 0.0)
                            .allowsHitTesting(false)

                        KuroConciergeMark(size: 24)
                            .matchedGeometryEffect(id: "kurochan", in: mascotNS)
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            offset = CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            let next = clamp(offset: offset)
                            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.86)) {
                                offset = next
                            }
                            dragStart = next
                        }
                )
            }
        }
        .padding(.leading, 16)
        .padding(.bottom, baseBottomPadding)
        .offset(clamped)
        .onAppear {
            // Ensure a sensible initial position.
            if dragStart == .zero, offset == .zero {
                dragStart = .zero
                offset = .zero
            }

            // Soft pulse so the orb feels "alive".
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func clamp(offset: CGSize) -> CGSize {
        // Relative to bottom-leading with padding already applied.
        // Allow dragging right/up, but not off-screen.
        let maxRight = max(0, containerSize.width - (panelWidth + 32))
        let minX: CGFloat = 0
        let maxX: CGFloat = maxRight

        // Allow moving up roughly 70% of the screen; don't allow dragging below the base anchor.
        let minY: CGFloat = -max(120, containerSize.height * 0.70)
        let maxY: CGFloat = 0

        return CGSize(
            width: min(maxX, max(minX, offset.width)),
            height: min(maxY, max(minY, offset.height))
        )
	    }
	}

	struct ConciergeMessage: Identifiable {
	    enum Role { case user, assistant }
	    let id = UUID()
    let role: Role
    let text: String
    let items: [SupabaseService.ConciergeParseItem]?
    let recommendations: [SupabaseService.ConciergeRecommendResponse.Item]?
    let recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]?
    let recommendationCategories: [String]?

    init(
        role: Role,
        text: String,
        items: [SupabaseService.ConciergeParseItem]? = nil,
        recommendations: [SupabaseService.ConciergeRecommendResponse.Item]? = nil,
        recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]? = nil,
        recommendationCategories: [String]? = nil
    ) {
        self.role = role
        self.text = text
        self.items = items
        self.recommendations = recommendations
        self.recommendationSets = recommendationSets
        self.recommendationCategories = recommendationCategories
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isEmpty
        }
    }
}
