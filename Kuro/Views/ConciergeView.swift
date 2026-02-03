import SwiftUI

struct ConciergeView: View {
    @Environment(SupabaseService.self) private var supabaseService

    @State private var input: String = ""
    @State private var messages: [ConciergeMessage] = []
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var selectedByItemId: [String: SupabaseService.ConciergeCandidate] = [:]
    @State private var lastApplySessionId: String? = nil
    @State private var selectedAnime: Anime? = nil
    @State private var selectedManga: Manga? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
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
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
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
                .background(Color.white)
            }

            Divider()
                .opacity(0.12)

            HStack(spacing: 10) {
                TextField("Paste titles, or ask for a vibe…", text: $input, axis: .vertical)
                    .font(.system(size: 14, weight: .regular))
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(true)
                    .lineLimit(1...4)
                    .padding(.vertical, 10)

                Button(action: { Task { await send() } }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking ? .black.opacity(0.2) : .black)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 8)
            .background(Color.white)
        }
        .background(Color.white)
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
        isWorking = true
        lastApplySessionId = nil

        let userMsg = ConciergeMessage(role: .user, text: text, items: nil)
        messages.append(userMsg)

        do {
            if looksLikeImport(text) {
                let response = try await supabaseService.conciergeParse(text: text, scope: .both)
                // Preselect obvious matches to reduce taps for common cases.
                for item in response.items {
                    guard let top = item.candidates.first else { continue }
                    let second = item.candidates.dropFirst().first
                    let isClearLead = second == nil || (top.score - (second?.score ?? 0)) >= 0.18
                    if top.score >= 0.88, isClearLead {
                        selectedByItemId[item.id] = top
                    }
                }
                let missing = response.items.filter { !$0.candidateError.isNilOrEmpty }.count
                let summaryText =
                    missing > 0
                    ? "Parsed \(response.items.count) item(s). Title matching isn’t ready yet (\(missing) missing candidates)."
                    : "Parsed \(response.items.count) item(s). Tap candidates, then APPLY."
                let summary = ConciergeMessage(
                    role: .assistant,
                    text: summaryText,
                    items: response.items
                )
                messages.append(summary)
            } else {
                let rec = try await supabaseService.conciergeRecommend(text: text, scope: .both, limit: 8)
                if rec.success, let items = rec.items, !items.isEmpty {
                    messages.append(
                        ConciergeMessage(
                            role: .assistant,
                            text: "Here are a few picks:",
                            items: nil,
                            recommendations: items
                        )
                    )
                } else {
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
        } catch {
            errorText = "Concierge error: \(error.localizedDescription)"
        }

        isWorking = false
    }

    private func looksLikeImport(_ text: String) -> Bool {
        let t = text.lowercased()
        if text.contains("\n") { return true }
        if text.contains(",") && text.count < 180 { return true }
        if t.contains("watching") || t.contains("reading") || t.contains("completed") || t.contains("dropped") { return true }
        if t.contains(" ep ") || t.contains("episode") || t.contains("chapter") || t.contains(" vol") { return true }
        // Short prompts like "funny anime" shouldn't be treated as import.
        if text.count <= 28 { return false }
        return false
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
            return payload
        }

        guard !chosen.isEmpty else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            let res = try await supabaseService.conciergeApply(items: chosen)
            if let sessionId = res.sessionId { lastApplySessionId = sessionId }
            await supabaseService.fetchUserLists()
            await supabaseService.fetchCollectionItems()
            messages.append(
                ConciergeMessage(
                    role: .assistant,
                    text: res.success
                        ? "Applied \(res.applied?.count ?? 0) item(s)."
                        : "Applied with errors. You can try again or undo the last batch.",
                    items: nil
                )
            )
        } catch {
            errorText = "Apply failed: \(error.localizedDescription)"
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
            lastApplySessionId = nil
            messages.append(
                ConciergeMessage(
                    role: .assistant,
                    text: res.success ? "Undid last batch." : "Undo failed. Try again.",
                    items: nil
                )
            )
        } catch {
            errorText = "Undo failed: \(error.localizedDescription)"
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

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            Text(message.text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(message.role == .user ? Color.black.opacity(0.06) : Color.black.opacity(0.03))
                )
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

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

            if let recs = message.recommendations, !recs.isEmpty {
                ConciergeRecommendationStepper(
                    items: recs,
                    hiddenIds: $hiddenRecommendationIds,
                    index: $stepIndex,
                    onOpen: onOpenRecommendation,
                    onSave: onQuickSave
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct ConciergeRecommendationStepper: View {
    let items: [SupabaseService.ConciergeRecommendResponse.Item]
    @Binding var hiddenIds: Set<String>
    @Binding var index: Int
    let onOpen: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void

    private var visible: [SupabaseService.ConciergeRecommendResponse.Item] {
        items.filter { !hiddenIds.contains($0.id) }
    }

    private func clampIndex() {
        if index < 0 { index = 0 }
        if index >= visible.count { index = max(0, visible.count - 1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if visible.isEmpty {
                Text("Nothing else in this set — try a different vibe.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.black.opacity(0.5))
            } else {
                card(for: visible[index])
            }
        }
        .onAppear { clampIndex() }
        .onChange(of: hiddenIds) { _, _ in clampIndex() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("PICKS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(.black.opacity(0.55))

            Spacer()

            Button {
                KuroAccessibility.impactHaptic(.light)
                index = max(0, index - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(index > 0 ? 0.65 : 0.15))
            }
            .buttonStyle(.plain)
            .disabled(index == 0)

            Text("\(min(index + 1, max(visible.count, 1))) / \(max(visible.count, 1))")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(.black.opacity(0.4))

            Button {
                KuroAccessibility.impactHaptic(.light)
                index = min(max(visible.count - 1, 0), index + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(index < (visible.count - 1) ? 0.65 : 0.15))
            }
            .buttonStyle(.plain)
            .disabled(index >= visible.count - 1)
        }
        .padding(.top, 2)
    }

    private func card(for item: SupabaseService.ConciergeRecommendResponse.Item) -> some View {
        ConciergeRecommendationStepCard(
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

private struct ConciergeRecommendationStepCard: View {
    let item: SupabaseService.ConciergeRecommendResponse.Item
    let onOpen: () -> Void
    let onSave: () -> Void
    let onSkip: () -> Void

    private let width: CGFloat = 200
    private var height: CGFloat { width / 0.7 }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                onOpen()
            }) {
                ZStack(alignment: .topTrailing) {
                    KuroCachedAsyncImage(url: URL(string: item.coverImageMedium ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: width, height: height)
                                .clipped()
                        case .failure, .empty:
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                                .frame(width: width, height: height)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if let s = displayScore, s > 0 {
                        KuroScoreBadge(score: s)
                            .padding(8)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.92))
                    .lineLimit(2)
                    .frame(height: 38, alignment: .top)

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

                if !badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(badges, id: \.self) { b in
                            Text(b)
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.1)
                                .foregroundColor(.black.opacity(0.55))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                                        .fill(Color.black.opacity(0.04))
                                )
                        }
                    }
                    .padding(.top, 2)
                }

                HStack(spacing: 10) {
                    Button(action: onSkip) {
                        Text("SKIP")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundColor(.black.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.03))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onSave) {
                        Text("SAVE")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.9))
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

struct ConciergeMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    let items: [SupabaseService.ConciergeParseItem]?
    let recommendations: [SupabaseService.ConciergeRecommendResponse.Item]?

    init(
        role: Role,
        text: String,
        items: [SupabaseService.ConciergeParseItem]? = nil,
        recommendations: [SupabaseService.ConciergeRecommendResponse.Item]? = nil
    ) {
        self.role = role
        self.text = text
        self.items = items
        self.recommendations = recommendations
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
