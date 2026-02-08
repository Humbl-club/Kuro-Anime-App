// MARK: - CONCIERGE VIEW (PRODUCTION-READY)
// Fully wired with 4 new states, proper error handling, and complete integration

import SwiftUI

// MARK: - Display State
enum ConciergeDisplayState: Equatable {
    case initial
    case thinking(context: String)
    case presenting
    case confirming
    case done(summary: ConciergeDoneSummary)
}

// MARK: - Data Models
struct ConciergePresentItem: Identifiable {
    let id: String
    let mediaId: Int
    let mediaType: String // "anime" or "manga"
    let title: String
    let meta: String
    let score: Double
    let imageURL: String?
    let posterColors: [Color]
}

struct ConciergeConfirmItem: Identifiable {
    let id = UUID()
    let itemId: String // Original parse item ID
    let parsedText: String
    let matchedTitle: String
    let mediaType: String
    let mediaId: Int
    let status: String
    let progress: String?
    let thumbnailColors: [Color]
    let candidates: [SupabaseService.ConciergeCandidate]
}

struct ConciergeDoneSummary: Equatable {
    let totalItems: Int
    let added: Int
    let updated: Int
    let breakdown: String
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
    @State private var lastApplySessionId: String? = nil
    @State private var selectedAnime: Anime? = nil
    @State private var selectedManga: Manga? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var assistantExpanded: Bool = false
    @State private var assistantOffset: CGSize = .zero
    @State private var assistantDragStart: CGSize = .zero
    
    // MARK: New State Management
    @State private var displayState: ConciergeDisplayState = .initial
    @State private var presentItems: [ConciergePresentItem] = []
    @State private var confirmItems: [ConciergeConfirmItem] = []
    @State private var currentParseResponse: SupabaseService.ConciergeParseResponse? = nil
    
    private var hasActionBar: Bool {
        (activeItems?.isEmpty == false) || lastApplySessionId != nil
    }
    
    init(assistantEnabled: Bool = true) {
        self.assistantEnabled = assistantEnabled
    }
    
    // MARK: Body
    var body: some View {
        ZStack {
            Color(hex: "fafafa").ignoresSafeArea()
            
            contentView
            
            // Toast overlay
            if let toast {
                VStack {
                    Spacer()
                    KuroToast(toast: toast)
                        .padding(.horizontal, 16)
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
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch displayState {
        case .initial:
            initialStateView
            
        case .thinking(let context):
            ConciergeThinkingView(context: context)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            
        case .presenting:
            ConciergePresentingView(
                items: presentItems,
                onAdd: { item in
                    Task { await addToList(item: item) }
                },
                onDetails: { item in
                    Task { await showDetails(item: item) }
                },
                onDismiss: {
                    withAnimation(.spring(response: 0.35)) {
                        displayState = .initial
                        presentItems = []
                    }
                }
            )
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            
        case .confirming:
            ConciergeConfirmingView(
                items: confirmItems,
                selectedByItemId: selectedByItemId,
                onSelect: { item, candidate in
                    selectedByItemId[item.itemId] = candidate
                },
                onConfirm: {
                    Task { await confirmImport() }
                },
                onReview: {
                    withAnimation(.spring(response: 0.35)) {
                        displayState = .initial
                    }
                }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            
        case .done(let summary):
            ConciergeDoneView(
                summary: summary,
                onDismiss: {
                    withAnimation(.spring(response: 0.35)) {
                        displayState = .initial
                        resetState()
                    }
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
    
    // MARK: Initial State (Existing Chat UI)
    private var initialStateView: some View {
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
                KuroGlassCard(cornerRadius: 22) { Color.clear }
            )
            .kuroSwipeExclusionZone()
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.top, 8)
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
        
        // Add user message
        let userMsg = ConciergeMessage(role: .user, text: text, items: nil)
        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
            messages.append(userMsg)
        }
        
        do {
            if looksLikeImport(text) {
                // IMPORT FLOW
                await handleImportFlow(text: text)
            } else {
                // RECOMMENDATION FLOW
                await handleRecommendationFlow(text: text)
            }
        } catch {
            handleError(error)
        }
        
        isWorking = false
    }
    
    // MARK: Import Flow
    private func handleImportFlow(text: String) async {
        // Show thinking
        withAnimation {
            displayState = .thinking(context: "Matching your titles...")
        }
        
        do {
            let response = try await supabaseService.conciergeParse(text: text, scope: .both)
            currentParseResponse = response
            
            // Convert to confirm items
            confirmItems = response.items.map { item in
                let topCandidate = item.candidates.first
                return ConciergeConfirmItem(
                    itemId: item.id,
                    parsedText: item.raw,
                    matchedTitle: topCandidate?.title_raw ?? item.raw,
                    mediaType: topCandidate?.media_type ?? "anime",
                    mediaId: topCandidate?.media_id ?? 0,
                    status: normalizedStatus(for: item.parsed.status, mediaType: topCandidate?.media_type),
                    progress: progressString(from: item.parsed),
                    thumbnailColors: thumbnailColors(for: topCandidate?.media_type ?? "anime"),
                    candidates: item.candidates
                )
            }
            
            // Pre-select top candidates
            for item in response.items {
                if let top = item.candidates.first, top.score >= 0.60 {
                    selectedByItemId[item.id] = top
                }
            }
            
            // Show confirming state
            withAnimation(.spring(response: 0.4)) {
                displayState = .confirming
            }
            
        } catch {
            handleError(error)
            withAnimation { displayState = .initial }
        }
    }
    
    // MARK: Recommendation Flow
    private func handleRecommendationFlow(text: String) async {
        // Show thinking
        withAnimation {
            displayState = .thinking(context: "Finding recommendations...")
        }
        
        do {
            let rec = try await supabaseService.conciergeRecommend(text: text, scope: .both, limit: 8)
            let sets = (rec.sets ?? []).filter { ($0.items ?? []).isEmpty == false }
            let flattened = sets.flatMap { $0.items ?? [] }
            let displayItems = !flattened.isEmpty ? flattened : (rec.items ?? [])
            
            if rec.success, !displayItems.isEmpty {
                // Convert to present items
                presentItems = displayItems.map { item in
                    ConciergePresentItem(
                        id: "\(item.mediaId)_\(item.mediaType)",
                        mediaId: item.mediaId,
                        mediaType: item.mediaType,
                        title: item.title,
                        meta: "\((item.year.map(String.init)) ?? "Unknown") · \(item.mediaType.capitalized)",
                        score: Double(item.averageScore ?? 0) / 10.0,
                        imageURL: item.coverImageMedium,
                        posterColors: posterColors(for: item.mediaType)
                    )
                }
                
                // Show presenting state
                withAnimation(.spring(response: 0.4)) {
                    displayState = .presenting
                }
                
            } else {
                // Fall back to chat with message
                withAnimation { displayState = .initial }
                messages.append(
                    ConciergeMessage(
                        role: .assistant,
                        text: rec.message ?? "Tell me a vibe (funny, sad, cozy, action) and I'll recommend something new-to-you.",
                        items: nil
                    )
                )
            }
            
        } catch {
            handleError(error)
            withAnimation { displayState = .initial }
        }
    }
    
    // MARK: Actions
    private func addToList(item: ConciergePresentItem) async {
        do {
            let status: ListStatus = .planning
            try await supabaseService.upsertUserListEntry(
                mediaId: item.mediaId,
                mediaType: item.mediaType,
                status: status,
                progress: 0,
                rating: nil,
                notes: nil
            )
            showToast(.init(kind: .success, title: "Added to \(status.displayName)", subtitle: item.title, actionTitle: nil, onAction: nil))
        } catch {
            showToast(.init(kind: .error, title: "Failed to add", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil))
        }
    }
    
    private func showDetails(item: ConciergePresentItem) async {
        do {
            if item.mediaType == "anime" {
                if let anime = try await supabaseService.fetchAnimeById(item.mediaId) {
                    selectedAnime = anime
                }
            } else {
                if let manga = try await supabaseService.fetchMangaById(item.mediaId) {
                    selectedManga = manga
                }
            }
        } catch {
            showToast(.init(kind: .error, title: "Failed to load details", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil))
        }
    }
    
    private func confirmImport() async {
        guard let response = currentParseResponse else { return }
        
        isWorking = true
        
        do {
            // Build payload from selected candidates
            let chosen = confirmItems.compactMap { item -> [String: Any]? in
                guard let c = selectedByItemId[item.itemId] else { return nil }
                let status = normalizedStatus(for: item.status, mediaType: item.mediaType)
                
                var payload: [String: Any] = [
                    "raw": item.parsedText,
                    "mediaType": item.mediaType.uppercased(),
                    "mediaId": c.media_id,
                    "status": status,
                    "confidence": c.score,
                ]
                return payload
            }
            
            guard !chosen.isEmpty else {
                showToast(.init(kind: .error, title: "No items selected", subtitle: nil, actionTitle: nil, onAction: nil))
                isWorking = false
                return
            }
            
            let res = try await supabaseService.conciergeApply(items: chosen)
            if let sessionId = res.sessionId {
                lastApplySessionId = sessionId
            }
            
            await supabaseService.fetchUserLists()
            await supabaseService.fetchCollectionItems()
            
            // Create summary
            let summary = ConciergeDoneSummary(
                totalItems: chosen.count,
                added: chosen.count,
                updated: 0,
                breakdown: "\(chosen.count) item(s) added to your collection"
            )
            
            withAnimation(.spring(response: 0.4)) {
                displayState = .done(summary: summary)
            }
            
        } catch {
            handleError(error)
        }
        
        isWorking = false
    }
    
    // MARK: Helper Methods
    private func resetState() {
        presentItems = []
        confirmItems = []
        currentParseResponse = nil
        selectedByItemId = [:]
        lastApplySessionId = nil
    }
    
    private func handleError(_ error: Error) {
        if let guardrail = error as? SupabaseService.ConciergeGuardrailsError {
            errorText = guardrail.localizedDescription
            showToast(.init(kind: .error, title: "Slow down", subtitle: guardrail.localizedDescription, actionTitle: nil, onAction: nil), autoDismissSeconds: 3.0)
        } else {
            errorText = error.localizedDescription
            showToast(.init(kind: .error, title: "Error", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil), autoDismissSeconds: 3.0)
        }
    }
    
    private func progressString(from parsed: SupabaseService.ConciergeParseItemParsed) -> String? {
        if let ep = parsed.progressEpisodes { return "Ep \(ep)" }
        if let ch = parsed.progressChapters { return "Ch \(ch)" }
        if let vol = parsed.progressVolumes { return "Vol \(vol)" }
        return nil
    }
    
    private func thumbnailColors(for mediaType: String) -> [Color] {
        mediaType == "anime" 
            ? [Color(hex: "8B4513"), Color(hex: "654321")]
            : [Color(hex: "4B0082"), Color(hex: "301934")]
    }
    
    private func posterColors(for mediaType: String) -> [Color] {
        let gradients: [[Color]] = [
            [Color(hex: "667eea"), Color(hex: "764ba2")],
            [Color(hex: "fa709a"), Color(hex: "fee140")],
            [Color(hex: "4facfe"), Color(hex: "00f2fe")],
            [Color(hex: "2d5016"), Color(hex: "1a3009")],
            [Color(hex: "4a1c6f"), Color(hex: "2d0f47")],
            [Color(hex: "8b4513"), Color(hex: "5c2e0c")]
        ]
        return gradients.randomElement() ?? gradients[0]
    }
    
    private func normalizedStatus(for raw: String?, mediaType: String?) -> String {
        let s = (raw ?? "").uppercased()
        if mediaType == "manga", s == "WATCHING" { return "READING" }
        if mediaType == "anime", s == "READING" { return "WATCHING" }
        if s.isEmpty { return "PLANNING" }
        return s
    }
    
    // MARK: Existing Helper Methods (Wired)
    private var activeItems: [SupabaseService.ConciergeParseItem]? {
        messages.last(where: { $0.role == .assistant && ($0.items?.isEmpty == false) })?.items
    }
    
    private var activeSelectedCount: Int {
        guard let items = activeItems else { return 0 }
        return items.reduce(0) { acc, item in acc + (selectedByItemId[item.id] != nil ? 1 : 0) }
    }
    
    private func applyActiveItems() async {
        await confirmImport()
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

            if res.success {
                showToast(.init(kind: .success, title: "Undid last batch", subtitle: nil, actionTitle: nil, onAction: nil))
            } else {
                showToast(.init(kind: .error, title: "Undo failed", subtitle: "Try again.", actionTitle: nil, onAction: nil))
            }
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

    private func looksLikeImport(_ text: String) -> Bool {
        // High precision: false positives feel like wrong responses because we route to import parsing.
        // Prefer a few false negatives over misrouting vibes.
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
}

// MARK: - Supporting Views

struct ConciergeThinkingView: View {
    let context: String
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.black.opacity(0.08), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .trim(from: 0, to: 0.25)
                            .stroke(Color.black, lineWidth: 2)
                            .rotationEffect(.degrees(-90))
                    )
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
                
                Image(systemName: "person.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.black.opacity(0.4))
            }
            
            VStack(spacing: 8) {
                Text("One moment")
                    .font(.system(size: 32, weight: .light, design: .serif))
                    .foregroundColor(.black)
                
                Text(context)
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "fafafa"))
    }
}

struct ConciergePresentingView: View {
    let items: [ConciergePresentItem]
    let onAdd: (ConciergePresentItem) -> Void
    let onDetails: (ConciergePresentItem) -> Void
    let onDismiss: () -> Void
    
    @State private var currentIndex = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(items.count) matches found")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.black.opacity(0.35))
                        .textCase(.uppercase)
                    
                    Text("Recommendations")
                        .font(.system(size: 28, weight: .light, design: .serif))
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.5))
                        .padding(12)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.05))
                        )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 20)
            
            // Carousel
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PresentCard(
                        item: item,
                        onAdd: { onAdd(item) },
                        onDetails: { onDetails(item) }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            
            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<items.count, id: \.self) { index in
                    Capsule()
                        .fill(index == currentIndex ? Color.black : Color.black.opacity(0.2))
                        .frame(width: index == currentIndex ? 24 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: currentIndex)
                }
            }
            .padding(.vertical, 30)
        }
        .background(Color(hex: "fafafa"))
    }
}

struct PresentCard: View {
    let item: ConciergePresentItem
    let onAdd: () -> Void
    let onDetails: () -> Void
    @State private var showActions = false
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: item.posterColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 260, height: 370)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showActions.toggle()
                    }
                }
                
                // Score
                if item.score > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                        Text(String(format: "%.1f", item.score))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .padding(16)
                }
                
                // Actions
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Button(action: onAdd) {
                            Text("Add")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.95))
                                )
                        }
                        
                        Button(action: onDetails) {
                            Text("Details")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.95))
                                )
                        }
                    }
                    .padding(20)
                    .opacity(showActions ? 1 : 0)
                    .offset(y: showActions ? 0 : 10)
                }
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            
            VStack(spacing: 4) {
                Text(item.title)
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .foregroundColor(.black)
                    .lineLimit(2)
                
                Text(item.meta)
                    .font(.system(size: 12))
                    .foregroundColor(.black.opacity(0.5))
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ConciergeConfirmingView: View {
    let items: [ConciergeConfirmItem]
    let selectedByItemId: [String: SupabaseService.ConciergeCandidate]
    let onSelect: (ConciergeConfirmItem, SupabaseService.ConciergeCandidate) -> Void
    let onConfirm: () -> Void
    let onReview: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import Preview")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.black.opacity(0.35))
                    .textCase(.uppercase)
                
                Text("\(items.count) items to add")
                    .font(.system(size: 32, weight: .light, design: .serif))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 30)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        ConfirmRow(
                            item: item,
                            selected: selectedByItemId[item.itemId],
                            onSelect: { candidate in
                                onSelect(item, candidate)
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
            
            HStack(spacing: 12) {
                Button(action: onReview) {
                    Text("Review")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.05))
                        )
                }
                
                Button(action: onConfirm) {
                    Text("Confirm All")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black)
                        )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(hex: "fafafa"))
    }
}

struct ConfirmRow: View {
    let item: ConciergeConfirmItem
    let selected: SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeCandidate) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                LinearGradient(
                    colors: item.thumbnailColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 50, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("\"\(item.parsedText)\"")
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.4))
                        .lineLimit(1)
                    
                    Text(item.matchedTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.black)
                    
                    HStack(spacing: 4) {
                        Text("✓ \(item.status)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                        
                        if let progress = item.progress {
                            Text("· \(progress)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Candidate selection if multiple options
            if item.candidates.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(item.candidates, id: \.media_id) { candidate in
                            let isSelected = selected?.media_id == candidate.media_id
                            
                            Button(action: { onSelect(candidate) }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title_raw)
                                        .font(.system(size: 12))
                                        .foregroundColor(isSelected ? .white : .black)
                                        .lineLimit(1)
                                    
                                    Text(String(format: "%.0f%%", candidate.score * 100))
                                        .font(.system(size: 10))
                                        .foregroundColor(isSelected ? .white.opacity(0.8) : .black.opacity(0.5))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? Color.black : Color.black.opacity(0.05))
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

struct ConciergeDoneView: View {
    let summary: ConciergeDoneSummary
    let onDismiss: () -> Void
    @State private var showCheck = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 72, height: 72)
                    .scaleEffect(showCheck ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showCheck)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(showCheck ? 1 : 0)
                    .scaleEffect(showCheck ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.3).delay(0.2), value: showCheck)
            }
            .padding(.bottom, 24)
            .onAppear {
                showCheck = true
            }
            
            VStack(spacing: 8) {
                Text("All done")
                    .font(.system(size: 36, weight: .light, design: .serif))
                    .foregroundColor(.black)
                
                Text("Your collection has been updated")
                    .font(.system(size: 15))
                    .foregroundColor(.black.opacity(0.5))
            }
            .padding(.bottom, 32)
            
            VStack(spacing: 8) {
                Text("**\(summary.totalItems) items** added successfully")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.6))
                
                Text(summary.breakdown)
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.5))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.bottom, 32)
            
            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.black.opacity(0.15), lineWidth: 1)
                    )
            }
            
            Spacer()
        }
        .padding(40)
        .background(Color(hex: "fafafa"))
    }
}

// MARK: - Preview
#Preview {
    ConciergeView()
}
