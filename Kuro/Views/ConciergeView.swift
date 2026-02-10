// MARK: - CONCIERGE VIEW (INLINE CHAT ARCHITECTURE)
// No full-screen state machine. Everything renders inline in the chat scroll.
// High-confidence imports auto-apply with undo toast. Recommendations appear as editorial rails.

import SwiftUI

// MARK: - Import Reconciliation Types

enum ImportItemAction: String, Sendable {
    case add
    case update
    case skip
}

struct ImportDiff: Sendable {
    struct FieldDiff<T: Sendable>: Sendable {
        let from: T
        let to: T
    }
    var status: FieldDiff<String>?
    var progressEpisodes: FieldDiff<Int>?
    var progressChapters: FieldDiff<Int>?
    var progressVolumes: FieldDiff<Int>?
    var rating: FieldDiff<Int?>?

    var isEmpty: Bool {
        status == nil && progressEpisodes == nil && progressChapters == nil && progressVolumes == nil && rating == nil
    }
}

// MARK: - Main View
struct ConciergeView: View {
    @Environment(SupabaseService.self) private var supabaseService

    let assistantEnabled: Bool

    // MARK: Input & Core State
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool
    @State private var messages: [ConciergeMessage] = []
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var selectedByItemId: [String: SupabaseService.ConciergeCandidate] = [:]
    @State private var itemActions: [String: ImportItemAction] = [:]
    @State private var excludedItemIds: Set<String> = []
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

    // MARK: Body
    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()

            chatView

            // Toast overlay
            if let toast {
                VStack {
                    Spacer()
                    KuroToast(toast: toast)
                        .padding(.horizontal, KuroDesignSpacing.md)
                        .padding(.bottom, hasActionBar ? 152 : 92)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .sheet(item: $selectedAnime) { anime in
            AnimeDetailView(anime: anime)
        }
        .sheet(item: $selectedManga) { manga in
            MangaDetailView(manga: manga)
        }
        .task {
            // Warm up the edge function isolate on view appear (fire-and-forget)
            Task.detached(priority: .background) {
                await supabaseService.conciergeWarmup()
            }
        }
    }

    // MARK: Chat View (Always Visible)
    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                        if messages.isEmpty {
                            ConciergeIntroCard()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 14)
                                .padding(.bottom, KuroDesignSpacing.sm)

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
                                },
                                onConfirmItems: { response in
                                    Task { await confirmImport(response: response) }
                                },
                                itemActions: itemActions,
                                excludedItemIds: $excludedItemIds
                            )
                            .id(msg.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        if isWorking {
                            ConciergeTypingIndicator()
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.top, KuroDesignSpacing.md)
                    .padding(.bottom, KuroDesignSpacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation(KuroAnimation.fast) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.kuroCaption())
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, KuroDesignSpacing.padding)
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
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.vertical, 12)
                .background(
                    KuroGlassCard(cornerRadius: KuroRadius.lg) { Color.clear }
                )
            } else if lastApplySessionId != nil {
                ConciergeActionBar(
                    selectedCount: 0,
                    hasAnySelection: false,
                    canUndo: true,
                    onApply: {},
                    onUndo: { Task { await undoLastApply() } }
                )
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.vertical, 12)
                .background(
                    KuroGlassCard(cornerRadius: KuroRadius.lg) { Color.clear }
                )
            }

            Divider()
                .opacity(0.12)

            HStack(spacing: 10) {
                TextField("Paste titles, or ask for a vibe…", text: $input, axis: .vertical)
                    .font(.kuroBody())
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
            .padding(.horizontal, KuroDesignSpacing.md)
            .padding(.vertical, 10)
            .background(
                KuroGlassCard(cornerRadius: KuroRadius.lg) { Color.clear }
            )
            .kuroSwipeExclusionZone()
            .padding(.horizontal, KuroDesignSpacing.md)
            .padding(.bottom, 14)
            .padding(.top, KuroDesignSpacing.sm)
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
    }

    // MARK: Send (Main Entry Point)
    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorText = nil
        input = ""
        isWorking = true
        lastApplySessionId = nil

        // Add user message immediately (optimistic)
        let userMsg = ConciergeMessage(role: .user, text: text, items: nil)
        withAnimation(KuroAnimation.editorial) {
            messages.append(userMsg)
        }

        do {
            if looksLikeImport(text) {
                await handleImportFlow(text: text)
            } else {
                await handleRecommendationFlow(text: text)
            }
        } catch {
            handleError(error)
        }

        isWorking = false
    }

    // MARK: Import Flow (Inline)
    private func handleImportFlow(text: String) async {
        do {
            let response = try await supabaseService.conciergeParse(text: text, scope: .both)

            // Pre-select top candidates (skip when adaptations are ambiguous)
            var hasAnyExistingEntry = false
            for item in response.items {
                if let top = item.candidates.first, top.score >= 0.60 {
                    if hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention) {
                        continue
                    }
                    selectedByItemId[item.id] = top
                }

                // Compute reconciliation action per item
                let action = computeItemAction(item: item)
                itemActions[item.id] = action
                if item.existing_entry != nil {
                    hasAnyExistingEntry = true
                }
            }

            // Auto-apply safety: disabled when ANY item has an existing_entry
            let allHighConfidence = !hasAnyExistingEntry && response.items.allSatisfy { item in
                guard let top = item.candidates.first else { return false }
                return top.score >= 0.85 && !hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention)
            }

            if allHighConfidence && !response.items.isEmpty {
                // Auto-apply: skip confirm UI entirely
                await autoApplyImport(response: response)
            } else {
                // Show inline confirm bubble in chat
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: "",
                    items: response.items,
                    parseResponse: response
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
            }

        } catch {
            handleError(error)
        }
    }

    // MARK: Reconciliation Helpers

    private func computeItemAction(item: SupabaseService.ConciergeParseItem) -> ImportItemAction {
        guard let existing = item.existing_entry else { return .add }
        let diff = computeDiff(existing: existing, parsed: item.parsed)
        if let diff, !diff.isEmpty { return .update }
        return .skip
    }

    private func computeDiff(existing: SupabaseService.ConciergeExistingEntry, parsed: SupabaseService.ConciergeParseItemParsed) -> ImportDiff? {
        var diff = ImportDiff()

        if let parsedStatus = parsed.status,
           parsedStatus.uppercased() != existing.status.uppercased() {
            diff.status = ImportDiff.FieldDiff(from: existing.status, to: parsedStatus.uppercased())
        }
        if let ep = parsed.progressEpisodes,
           ep != (existing.progress_episodes ?? 0) {
            diff.progressEpisodes = ImportDiff.FieldDiff(from: existing.progress_episodes ?? 0, to: ep)
        }
        if let ch = parsed.progressChapters,
           ch != (existing.progress_chapters ?? 0) {
            diff.progressChapters = ImportDiff.FieldDiff(from: existing.progress_chapters ?? 0, to: ch)
        }
        if let vol = parsed.progressVolumes,
           vol != (existing.progress_volumes ?? 0) {
            diff.progressVolumes = ImportDiff.FieldDiff(from: existing.progress_volumes ?? 0, to: vol)
        }

        return diff.isEmpty ? nil : diff
    }

    // MARK: Auto-Apply (High Confidence, Pure Adds Only)
    private func autoApplyImport(response: SupabaseService.ConciergeParseResponse) async {
        do {
            let chosen = buildApplyPayload(from: response)
            guard !chosen.isEmpty else { return }

            let res = try await supabaseService.conciergeApply(items: chosen)
            if let sessionId = res.sessionId {
                lastApplySessionId = sessionId
            }

            // Refresh collection in background (don't block toast)
            Task.detached {
                async let _lists: () = supabaseService.fetchUserLists()
                async let _items: () = supabaseService.fetchCollectionItems()
                async let _feed: () = supabaseService.fetchCollectionFeed(status: nil)
                _ = await (_lists, _items, _feed)
            }

            // Show success toast with undo
            let count = chosen.count
            let sid = lastApplySessionId
            showToast(.init(
                kind: .success,
                title: "\(count) item\(count == 1 ? "" : "s") added to collection",
                subtitle: nil,
                actionTitle: "UNDO",
                onAction: { [weak supabaseService] in
                    guard let sid else { return }
                    Task {
                        await undoApply(sessionId: sid)
                    }
                }
            ), autoDismissSeconds: 4.0)

            // Add confirmation message to chat
            let confirmMsg = ConciergeMessage(
                role: .assistant,
                text: "\(count) item\(count == 1 ? "" : "s") added to your collection.",
                items: nil
            )
            withAnimation(KuroAnimation.editorial) {
                messages.append(confirmMsg)
            }

        } catch {
            handleError(error)
        }
    }

    // MARK: Recommendation Flow (Inline Rails)
    private func handleRecommendationFlow(text: String) async {
        do {
            let rec = try await supabaseService.conciergeRecommend(text: text, scope: .both, limit: 8)
            let sets = (rec.sets ?? []).filter { ($0.items ?? []).isEmpty == false }
            let flattened = sets.flatMap { $0.items ?? [] }
            let displayItems = !flattened.isEmpty ? flattened : (rec.items ?? [])

            if rec.success, !displayItems.isEmpty {
                // Append inline recommendation message with editorial rails
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: rec.message ?? "",
                    items: nil,
                    recommendations: !sets.isEmpty ? nil : displayItems,
                    recommendationSets: !sets.isEmpty ? sets : nil
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
            } else {
                // No results — show text message
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: rec.message ?? "Tell me a vibe (funny, sad, cozy, action) and I'll recommend something new-to-you.",
                    items: nil
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
            }

        } catch {
            handleError(error)
        }
    }

    // MARK: Confirm Import (From Inline Bubble)
    private func confirmImport(response: SupabaseService.ConciergeParseResponse) async {
        isWorking = true

        do {
            let chosen = buildApplyPayload(from: response)

            guard !chosen.isEmpty else {
                showToast(.init(kind: .error, title: "No items selected", subtitle: nil, actionTitle: nil, onAction: nil))
                isWorking = false
                return
            }

            let res = try await supabaseService.conciergeApply(items: chosen)
            if let sessionId = res.sessionId {
                lastApplySessionId = sessionId
            }

            // Refresh collection in background
            Task.detached {
                async let _lists: () = supabaseService.fetchUserLists()
                async let _items: () = supabaseService.fetchCollectionItems()
                async let _feed: () = supabaseService.fetchCollectionFeed(status: nil)
                _ = await (_lists, _items, _feed)
            }

            // Compute toast text based on action breakdown
            let addCount = chosen.filter { ($0["action"] as? String) == "add" || ($0["action"] as? String) == nil }.count
            let updateCount = chosen.filter { ($0["action"] as? String) == "update" }.count
            let conflictCount = res.conflicts?.count ?? 0

            var toastParts: [String] = []
            if addCount > 0 { toastParts.append("\(addCount) added") }
            if updateCount > 0 { toastParts.append("\(updateCount) updated") }
            let toastTitle = toastParts.isEmpty ? "\(chosen.count) items applied" : toastParts.joined(separator: ", ")

            let sid = lastApplySessionId
            showToast(.init(
                kind: conflictCount > 0 ? .info : .success,
                title: toastTitle,
                subtitle: conflictCount > 0 ? "\(conflictCount) conflict\(conflictCount == 1 ? "" : "s") -- review needed" : nil,
                actionTitle: "UNDO",
                onAction: {
                    guard let sid else { return }
                    Task {
                        await undoApply(sessionId: sid)
                    }
                }
            ), autoDismissSeconds: 4.0)

        } catch {
            handleError(error)
        }

        isWorking = false
    }

    // MARK: Build Apply Payload
    private func buildApplyPayload(from response: SupabaseService.ConciergeParseResponse) -> [[String: Any]] {
        response.items.compactMap { item -> [String: Any]? in
            guard let c = selectedByItemId[item.id] else { return nil }

            // Respect per-item exclusion toggles
            if excludedItemIds.contains(item.id) { return nil }

            let action = itemActions[item.id] ?? .add
            // Skip items produce no apply payload
            if action == .skip { return nil }

            let mediaType = c.media_type
            let status = normalizedStatus(for: item.parsed.status, mediaType: mediaType)

            var payload: [String: Any] = [
                "raw": item.raw,
                "mediaType": mediaType.uppercased(),
                "mediaId": c.media_id,
                "status": status,
                "confidence": c.score,
                "action": action.rawValue,
            ]

            let p = item.parsed
            if let v = p.progressEpisodes  { payload["progressEpisodes"] = v }
            if let v = p.progressChapters   { payload["progressChapters"] = v }
            if let v = p.progressVolumes    { payload["progressVolumes"] = v }
            if let v = p.seasonNumber       { payload["seasonNumber"] = v }
            if let v = p.episodeInSeason    { payload["episodeInSeason"] = v }
            if let v = p.caughtUp           { payload["caughtUp"] = v }
            if let v = p.lastEpisode        { payload["lastEpisode"] = v }
            if let v = p.completed          { payload["completed"] = v }

            // TOCTOU protection: send expected existing state for updates
            if action == .update, let existing = item.existing_entry {
                var expected: [String: Any] = ["status": existing.status]
                if let ep = existing.progress_episodes { expected["progress_episodes"] = ep }
                if let ch = existing.progress_chapters { expected["progress_chapters"] = ch }
                if let vol = existing.progress_volumes { expected["progress_volumes"] = vol }
                payload["expectedExisting"] = expected
            }

            return payload
        }
    }

    // MARK: Actions
    private func openRecommendation(_ item: SupabaseService.ConciergeRecommendResponse.Item) async {
        errorText = nil

        do {
            if item.mediaType.uppercased() == "ANIME" {
                let anime = try await supabaseService.fetchAnimeById(item.mediaId)
                guard let anime else {
                    errorText = "Couldn't find that anime in the database."
                    return
                }
                selectedAnime = anime
            } else {
                let manga = try await supabaseService.fetchMangaById(item.mediaId)
                guard let manga else {
                    errorText = "Couldn't find that manga in the database."
                    return
                }
                selectedManga = manga
            }
        } catch {
            errorText = "Couldn't open: \(error.localizedDescription)"
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

    // MARK: Undo
    private func undoApply(sessionId: String) async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            let res = try await supabaseService.conciergeUndo(sessionId: sessionId)

            // Refresh in background
            Task.detached {
                async let _lists: () = supabaseService.fetchUserLists()
                async let _items: () = supabaseService.fetchCollectionItems()
                async let _feed: () = supabaseService.fetchCollectionFeed(status: nil)
                _ = await (_lists, _items, _feed)
            }

            lastApplySessionId = nil

            if res.success {
                showToast(.init(kind: .success, title: "Import undone", subtitle: nil, actionTitle: nil, onAction: nil))
            } else {
                showToast(.init(kind: .error, title: "Undo failed", subtitle: "Try again.", actionTitle: nil, onAction: nil))
            }
        } catch {
            errorText = "Undo failed: \(error.localizedDescription)"
            showToast(.init(kind: .error, title: "Undo failed", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil))
        }
    }

    private func undoLastApply() async {
        guard let sessionId = lastApplySessionId else { return }
        await undoApply(sessionId: sessionId)
    }

    // MARK: Helpers
    private func handleError(_ error: Error) {
        if let guardrail = error as? SupabaseService.ConciergeGuardrailsError {
            errorText = guardrail.localizedDescription
            showToast(.init(kind: .error, title: "Slow down", subtitle: guardrail.localizedDescription, actionTitle: nil, onAction: nil), autoDismissSeconds: 3.0)
        } else {
            errorText = error.localizedDescription
            showToast(.init(kind: .error, title: "Error", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil), autoDismissSeconds: 3.0)
        }
    }

    private func normalizedStatus(for raw: String?, mediaType: String?) -> String {
        let s = (raw ?? "").uppercased()
        if mediaType == "manga", s == "WATCHING" { return "READING" }
        if mediaType == "anime", s == "READING" { return "WATCHING" }
        if s.isEmpty { return "PLANNING" }
        return s
    }

    // MARK: Adaptation Ambiguity Guard
    private func strippedBaseTitle(_ raw: String) -> String {
        var t = raw
        if let range = t.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            t.removeSubrange(range)
        }
        if let range = t.range(of: ": ") {
            t = String(t[t.startIndex..<range.lowerBound])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func hasAmbiguousAdaptations(
        candidates: [SupabaseService.ConciergeCandidate],
        yearMention: Int?
    ) -> Bool {
        guard candidates.count >= 2 else { return false }

        let top = candidates[0]
        let second = candidates[1]

        guard top.media_id != second.media_id else { return false }

        let baseTop = strippedBaseTitle(top.title_raw)
        let baseSecond = strippedBaseTitle(second.title_raw)
        guard baseTop == baseSecond else { return false }

        if let mentioned = yearMention, let topYear = top.year, topYear == mentioned {
            return false
        }

        return true
    }

    // MARK: Active Items (For Action Bar)
    private var activeItems: [SupabaseService.ConciergeParseItem]? {
        messages.last(where: { $0.role == .assistant && ($0.items?.isEmpty == false) })?.items
    }

    private var activeSelectedCount: Int {
        guard let items = activeItems else { return 0 }
        return items.reduce(0) { acc, item in
            let action = itemActions[item.id] ?? .add
            if action == .skip { return acc }
            if excludedItemIds.contains(item.id) { return acc }
            return acc + (selectedByItemId[item.id] != nil ? 1 : 0)
        }
    }

    private func applyActiveItems() async {
        guard let lastMsg = messages.last(where: { $0.role == .assistant && $0.parseResponse != nil }),
              let response = lastMsg.parseResponse else { return }
        await confirmImport(response: response)
    }

    @MainActor
    private func showToast(_ next: KuroToastState, autoDismissSeconds: Double = 2.5) {
        toastDismissTask?.cancel()
        withAnimation(KuroAnimation.fast) {
            toast = next
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0.8, autoDismissSeconds) * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(KuroAnimation.fast) {
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

    // MARK: Import vs Vibe Detection
    private func looksLikeImport(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = t.lowercased()

        if t.contains("\n") { return true }

        // Explicit import language (EN + DE)
        if l.contains("watching") || l.contains("reading") || l.contains("completed") || l.contains("finished") || l.contains("dropped") { return true }
        if l.contains("i watched") || l.contains("i'm watching") || l.contains("im watching") { return true }
        if l.contains("caught up") || l.contains("up to date") { return true }
        if l.contains("ich habe") || l.contains("ich schaue") || l.contains("ich gucke") || l.contains("ich sehe") || l.contains("ich lese") { return true }
        if l.contains("staffel") || l.contains("folge") || l.contains("kapitel") || l.contains("band") { return true }

        // German vibe markers — these are NOT imports
        let germanVibeMarkers = ["etwas", "empfiehl", "empfehlung", "zeig mir", "ich möchte", "ich will", "ich suche"]
        if germanVibeMarkers.contains(where: { l.contains($0) }) && !l.contains("staffel") && !l.contains("folge") {
            return false
        }

        // Progress patterns
        if l.contains(" ep ") || l.contains("episode") || l.contains("chapter") || l.contains(" vol") { return true }
        if l.range(of: #"s\d{1,2}\s*e\d{1,4}"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"\b\d{1,2}\s*x\s*\d{1,4}\b"#, options: .regularExpression) != nil { return true }

        // Comma-separated lists
        if t.contains(",") {
            let parts = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count >= 2 {
                let titleLikeCount = parts.filter { segmentLooksTitleLike($0) }.count
                if titleLikeCount >= 2 { return true }
            }
        }

        if t.count <= 28 { return false }
        return false
    }

    private func segmentLooksTitleLike(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return false }
        let l = t.lowercased()

        let vibeMarkers = ["something", "funny", "sad", "cozy", "vibe", "recommend", "suggest", "like", "but", "not", "please", "anime", "manga"]
        if vibeMarkers.contains(where: { l.contains($0) }) && t.split(separator: " ").count <= 6 {
            return false
        }

        if t.contains("(") || t.contains(")") { return true }
        if t.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"\b(ep|episode|ch|chapter|vol|volume|s\d+e\d+|\d+x\d+)\b"#, options: .regularExpression) != nil { return true }

        let words = t.split(separator: " ")
        if words.count >= 2 && t.range(of: #"[A-Z]"#, options: .regularExpression) != nil {
            return true
        }

        if words.count >= 3 { return true }

        return false
    }
}

// MARK: - Preview
#Preview {
    ConciergeView()
}
