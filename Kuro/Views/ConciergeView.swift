// MARK: - CONCIERGE VIEW (INLINE CHAT ARCHITECTURE)
// No full-screen state machine. Everything renders inline in the chat scroll.
// High-confidence imports auto-apply with undo toast. Recommendations appear as editorial rails.

import SwiftUI

// MARK: - Conversation Persistence (lightweight, text-only)

private struct PersistedMessage: Codable {
    let role: String  // "user" or "assistant"
    let text: String
    let timestamp: Date

    init(from message: ConciergeMessage) {
        self.role = message.role == .user ? "user" : "assistant"
        self.text = message.text
        self.timestamp = Date()
    }

    func toConciergeMessage() -> ConciergeMessage {
        ConciergeMessage(
            role: role == "user" ? .user : .assistant,
            text: text,
            items: nil
        )
    }
}

private enum ConciergeHistory {
    private static let key = "kuro_concierge_history"
    private static let maxMessages = 20

    static func save(_ messages: [ConciergeMessage]) {
        // Only persist text-only messages (drop interactive cards, recommendations, etc.)
        let persistable = messages.suffix(maxMessages).compactMap { msg -> PersistedMessage? in
            guard !msg.text.isEmpty else { return nil }
            // Skip messages with interactive content that can't be restored
            if msg.items != nil || msg.recommendations != nil || msg.recommendationSets != nil { return nil }
            if msg.showClarifyActions || msg.ambiguity != nil { return nil }
            return PersistedMessage(from: msg)
        }
        guard let data = try? JSONEncoder().encode(Array(persistable.suffix(maxMessages))) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> [ConciergeMessage] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let persisted = try? JSONDecoder().decode([PersistedMessage].self, from: data) else {
            return []
        }
        return persisted.map { $0.toConciergeMessage() }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

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
    @State private var focusRequest: Bool = false
    @State private var messages: [ConciergeMessage] = []
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var selectedByItemId: [String: SupabaseService.ConciergeCandidate] = [:]
    @State private var itemActions: [String: ImportItemAction] = [:]
    @State private var excludedItemIds: Set<String> = []
    @State private var autoReasonByItemId: [String: String] = [:]
    @State private var lastApplySessionId: String? = nil
    @State private var lastApplySessionResetTask: Task<Void, Never>? = nil
    @State private var selectedAnime: Anime? = nil
    @State private var selectedManga: Manga? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var assistantExpanded: Bool = false
    @State private var assistantOffset: CGSize = .zero
    @State private var assistantDragStart: CGSize = .zero
    @State private var containerSize: CGSize = CGSize(width: 393, height: 852)
    @State private var appliedImportMessageIds: Set<UUID> = []
    @State private var lastAppliedImportMessageId: UUID? = nil
    @State private var lastRecommendQuery: String? = nil
    @State private var lastRecommendWasRagAssist: Bool = false
    @State private var lastRagSeedEntityId: String? = nil
    @State private var ragFeedbackSentForQuery: Set<String> = []
    @State private var showAniListImportSheet: Bool = false
    @State private var aniListUsername: String = ""
    @State private var aniListIncludeAnime: Bool = true
    @State private var aniListIncludeManga: Bool = true
    @State private var aniListIncludeCurrent: Bool = true
    @State private var aniListIncludeCompleted: Bool = true
    @State private var aniListIncludePlanning: Bool = true
    @State private var aniListIncludePaused: Bool = false
    @State private var aniListIncludeDropped: Bool = false
    @State private var aniListIsImporting: Bool = false
    @State private var showTutorial: Bool = false
    @State private var tutorialStep: Int = 0

    private static let tutorialKey = "kuro_concierge_tutorial_completed"

    private var mascotState: ConciergeMascotState {
        if isWorking { return .thinking }
        if errorText != nil { return .concerned }
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .idle }
        return .listening
    }

    private var clarifyV2Enabled: Bool {
        FeatureFlags.shared.isClarifyV2Enabled
    }

    private var fmAssistEnabled: Bool {
        FeatureFlags.shared.isFmAssistEnabled && supabaseService.fmService.isAvailable
    }

    private var conciergePerfV2Enabled: Bool {
        FeatureFlags.shared.isConciergePerfV2Enabled
    }

    private var conciergeEditorialV1Enabled: Bool {
        // Concierge has fully migrated to the editorial shell.
        // Keep this as a fixed on-switch to avoid regressions to legacy UI in prod.
        true
    }

    private var isGermanLocale: Bool {
        let language = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        return language.hasPrefix("de")
    }

    private var editorialSubtitle: String {
        "Import from Kuro instantly — or tell me what you're in the mood for."
    }

    private var editorialFooterText: String {
        if isWorking {
            return isGermanLocale ? "Einen Moment." : "One moment."
        }
        return isGermanLocale ? "Importiere direkt aus deiner Bibliothek — oder lass mich zwei Rails kuratieren." : "Import from your list — or let me curate two rails."
    }

    init(assistantEnabled: Bool = true) {
        self.assistantEnabled = assistantEnabled
    }

    // MARK: Body
    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()

            editorialChatView

            // Toast overlay
            if let toast {
                VStack {
                    Spacer()
                    KuroToast(toast: toast)
                        .padding(.horizontal, KuroDesignSpacing.md)
                        .padding(.bottom, 92)
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
        .sheet(isPresented: $showAniListImportSheet) {
            aniListImportSheet
        }
        .task {
            // Whisper mode is intentionally ephemeral to match the prototype.
            if !conciergeEditorialV1Enabled {
                if messages.isEmpty {
                    let restored = ConciergeHistory.load()
                    if !restored.isEmpty {
                        messages = restored
                    }
                }
            } else if !messages.isEmpty {
                messages = []
            }

            // Whisper mode: keep the opening scene minimal (no tutorial overlay).
            if !conciergeEditorialV1Enabled && !UserDefaults.standard.bool(forKey: Self.tutorialKey) {
                showTutorial = true
            }

            // Warm up the edge function isolate on view appear (fire-and-forget)
            Task.detached(priority: .background) {
                await supabaseService.conciergeWarmup()
            }
        }
        .onDisappear {
            lastApplySessionResetTask?.cancel()
            if !conciergeEditorialV1Enabled {
                ConciergeHistory.save(messages)
            }
        }
        .onChange(of: messages.count) { _, _ in
            if !conciergeEditorialV1Enabled {
                ConciergeHistory.save(messages)
            }
        }
        .overlay {
            if showTutorial {
                ConciergeTutorialOverlay(
                    step: $tutorialStep,
                    isGerman: isGermanLocale,
                    onDismiss: {
                        withAnimation(KuroAnimation.fast) {
                            showTutorial = false
                        }
                        UserDefaults.standard.set(true, forKey: Self.tutorialKey)
                    }
                )
                .transition(.opacity)
                .zIndex(200)
            }
        }
        .preferredColorScheme(.light)
    }

    private var editorialChatView: some View {
        ConciergeEditorialShell(
            title: "Concierge",
            subtitle: editorialSubtitle,
            errorText: errorText,
            showsIntentDeck: messages.isEmpty
        ) {
            EmptyView()
        } responseStage: {
            ConciergeResponseStage {
                messageTimeline(
                    horizontalPadding: 24,
                    topPadding: 20,
                    bottomPadding: 20,
                    messageSpacing: 20,
                    includeStarter: false
                )
            }
        } composer: {
            ConciergeInputField(
                text: $input,
                isSending: isWorking,
                focusRequest: $focusRequest,
                onSend: { text in
                    Task { await send(text: text) }
                }
                ,onAutoSend: { text in
                    // Auto-send only when the input field detects a real paste import list.
                    Task { await send(text: text) }
                }
            )
            .kuroSwipeExclusionZone()
        } footer: {
            EmptyView()
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { containerSize = geo.size }
            }
        }
    }

    private var aniListImportSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(isGermanLocale ? "AniList importieren" : "Import AniList")
                        .font(.system(size: 26, weight: .ultraLight, design: .serif))
                        .foregroundStyle(.black.opacity(0.84))

                    Text(isGermanLocale
                        ? "Gib deinen AniList-Namen ein. Wir importieren deine öffentlichen Listen und gleichen sie mit deiner Kuro-Bibliothek ab."
                        : "Enter your AniList username. We’ll import your public lists and reconcile them into your Kuro library."
                    )
                    .font(.kuroBody(weight: .light))
                    .foregroundStyle(.black.opacity(0.62))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isGermanLocale ? "Benutzername" : "Username")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.8)
                            .foregroundColor(.kuroTextTertiary)

                        TextField(isGermanLocale ? "z.B. maxmustermann" : "e.g. yourname", text: $aniListUsername)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.kuroBody())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                                    .fill(Color.white.opacity(0.92))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                                            .stroke(Color.black.opacity(0.08), lineWidth: 0.7)
                                    )
                            )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isGermanLocale ? "Typ" : "Type")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.8)
                            .foregroundColor(.kuroTextTertiary)

                        HStack(spacing: 10) {
                            togglePill(
                                title: isGermanLocale ? "Anime" : "Anime",
                                isOn: $aniListIncludeAnime
                            )
                            togglePill(
                                title: isGermanLocale ? "Manga" : "Manga",
                                isOn: $aniListIncludeManga
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isGermanLocale ? "Status" : "Status")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.8)
                            .foregroundColor(.kuroTextTertiary)

                        HStack(spacing: 10) {
                            togglePill(
                                title: isGermanLocale ? "Aktuell" : "Current",
                                isOn: $aniListIncludeCurrent
                            )
                            togglePill(
                                title: isGermanLocale ? "Fertig" : "Completed",
                                isOn: $aniListIncludeCompleted
                            )
                            togglePill(
                                title: isGermanLocale ? "Plan" : "Planning",
                                isOn: $aniListIncludePlanning
                            )
                        }

                        HStack(spacing: 10) {
                            togglePill(
                                title: isGermanLocale ? "Pausiert" : "On hold",
                                isOn: $aniListIncludePaused
                            )
                            togglePill(
                                title: isGermanLocale ? "Abgebrochen" : "Dropped",
                                isOn: $aniListIncludeDropped
                            )
                        }
                    }

                    Button(action: {
                        Task { await runAniListImport() }
                    }) {
                        HStack(spacing: 10) {
                            if aniListIsImporting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isGermanLocale ? "IMPORTIEREN" : "IMPORT")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(2.0)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule(style: .continuous)
                                .fill(canRunAniListImport ? Color.black.opacity(0.88) : Color.black.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRunAniListImport || aniListIsImporting)
                    .padding(.top, 6)

                    Text(isGermanLocale
                        ? "Hinweis: Private AniList-Listen brauchen später OAuth. Dieses MVP nutzt öffentliche Listen."
                        : "Note: private AniList lists will require OAuth later. This MVP uses public lists."
                    )
                    .font(.kuroMicro())
                    .foregroundColor(.kuroTextTertiary)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isGermanLocale ? "Fertig" : "Done") { showAniListImportSheet = false }
                        .font(.kuroCaption(weight: .medium))
                }
            }
        }
        .presentationDetents([.large])
    }

    private var canRunAniListImport: Bool {
        !aniListUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (aniListIncludeAnime || aniListIncludeManga)
            && (aniListIncludeCurrent || aniListIncludeCompleted || aniListIncludePlanning || aniListIncludePaused || aniListIncludeDropped)
    }

    private func togglePill(title: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            Text(title)
                .font(.kuroCaption(weight: .medium))
                .foregroundStyle(isOn.wrappedValue ? .white : .black.opacity(0.68))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn.wrappedValue ? Color.black.opacity(0.86) : Color.black.opacity(0.04))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.black.opacity(0.10), lineWidth: 0.6)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
        .accessibilityHint("Toggles \(title) filter")
    }

    private func runAniListImport() async {
        guard canRunAniListImport else { return }
        if aniListIsImporting { return }

        aniListIsImporting = true
        defer { aniListIsImporting = false }

        let u = aniListUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        var types: [String] = []
        if aniListIncludeAnime { types.append("ANIME") }
        if aniListIncludeManga { types.append("MANGA") }

        var statuses: [String] = []
        if aniListIncludeCurrent { statuses.append("CURRENT") }
        if aniListIncludeCompleted { statuses.append("COMPLETED") }
        if aniListIncludePlanning { statuses.append("PLANNING") }
        if aniListIncludePaused { statuses.append("PAUSED") }
        if aniListIncludeDropped { statuses.append("DROPPED") }

        do {
            let resp = try await supabaseService.conciergeImportAniList(
                username: u,
                types: types,
                statuses: statuses,
                maxItems: 200
            )
            guard resp.success, let text = resp.text, !text.isEmpty else {
                showToast(.init(
                    kind: .error,
                    title: isGermanLocale ? "Import fehlgeschlagen" : "Import failed",
                    subtitle: resp.error ?? (isGermanLocale ? "Bitte prüfe den Namen." : "Please check the username."),
                    actionTitle: nil,
                    onAction: nil
                ), autoDismissSeconds: 4.0)
                return
            }

            showAniListImportSheet = false

            let count = resp.itemCount ?? 0
            await sendExternalImport(
                sourceLabel: "AniList",
                displayText: isGermanLocale
                    ? "AniList-Import — \(count) Titel"
                    : "AniList import — \(count) items",
                sourceText: text,
                truncated: resp.truncated ?? false
            )
        } catch {
            handleError(error)
        }
    }

    private func sendExternalImport(sourceLabel: String, displayText: String, sourceText: String, truncated: Bool) async {
        let t = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard !isWorking else { return }

        errorText = nil
        let sendStartedAt = supabaseService.beginInteractionTiming()

        // Compact user bubble (avoid dumping 200 lines into chat).
        let userMsg = ConciergeMessage(role: .user, text: displayText, sourceUserText: t, items: nil)
        withAnimation(KuroAnimation.editorial) {
            messages.append(userMsg)
        }

        isWorking = true
        defer { isWorking = false }

        await handleImportFlow(text: t, interactionStartedAt: sendStartedAt)

        if truncated {
            showToast(.init(
                kind: .info,
                title: isGermanLocale ? "Teilimport" : "Partial import",
                subtitle: isGermanLocale ? "Ich habe zuerst 200 Titel importiert. Du kannst später mehr importieren." : "Imported the first 200 items. You can import more later.",
                actionTitle: nil,
                onAction: nil
            ), autoDismissSeconds: 4.0)
        }
    }

    // MARK: Chat View (Always Visible)
    private var chatView: some View {
        VStack(spacing: 0) {
            messageTimeline(
                horizontalPadding: KuroDesignSpacing.padding,
                topPadding: KuroDesignSpacing.md,
                bottomPadding: KuroDesignSpacing.md,
                includeStarter: true
            )

            if let errorText {
                Text(errorText)
                    .font(.kuroCaption())
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.vertical, 10)
            }

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)

            ConciergeInputField(
                text: $input,
                isSending: isWorking,
                focusRequest: $focusRequest,
                onSend: { text in
                    Task { await send(text: text) }
                }
            )
            .kuroSwipeExclusionZone()
            .padding(.horizontal, KuroDesignSpacing.md)
            .padding(.bottom, 14)
            .padding(.top, KuroDesignSpacing.sm)
        }
        .overlay(alignment: .bottomLeading) {
            if assistantEnabled {
                KuroConciergeMascot(
                    expanded: $assistantExpanded,
                    offset: $assistantOffset,
                    dragStart: $assistantDragStart,
                    baseBottomPadding: 104,
                    containerSize: containerSize,
                    state: mascotState
                ) {
                    focusRequest = true
                }
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { containerSize = geo.size }
            }
        }
    }

    private func messageTimeline(
        horizontalPadding: CGFloat,
        topPadding: CGFloat,
        bottomPadding: CGFloat,
        messageSpacing: CGFloat = KuroDesignSpacing.md,
        includeStarter: Bool
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: messageSpacing) {
                    if includeStarter && messages.isEmpty {
                        ConciergeIntroCard()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                            .padding(.bottom, KuroDesignSpacing.sm)

                        ConciergeStarterActions(
                            onPaste: { pasteFromClipboard() },
                            onImportLibrary: {
                                Task { await importFromLibrary() }
                            },
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
                            onClarifyPaste: { pasteFromClipboard() },
                            onClarifyImportLibrary: {
                                Task { await importFromLibrary() }
                            },
                            onClarifyExampleImport: { seedExampleImport() },
                            onClarifyExampleVibe: { seedExampleVibe() },
                            onClarifyAmbiguity: clarifyV2Enabled ? { kind, value, sourceText in
                                Task { await handleClarification(kind: kind, value: value, sourceText: sourceText) }
                            } : nil,
                            onConfirmItems: { response in
                                Task { await confirmImport(response: response, sourceMessageId: msg.id) }
                            },
                            onReparse: {
                                reparse(message: msg)
                            },
                            isImportApplied: appliedImportMessageIds.contains(msg.id),
                            autoReasonByItemId: autoReasonByItemId,
                            itemActions: itemActions,
                            excludedItemIds: $excludedItemIds
                        )
                        .id(msg.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if isWorking && !messages.isEmpty {
                        ConciergeTypingIndicator()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
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
    }

    // MARK: Send (Main Entry Point)
    private func send(text: String) async {
        guard !text.isEmpty else { return }
        guard !isWorking else { return }
        errorText = nil
        let sendStartedAt = supabaseService.beginInteractionTiming()

        #if DEBUG
        let sendStart = CFAbsoluteTimeGetCurrent()
        #endif

        // Add user message immediately (optimistic)
        let userMsg = ConciergeMessage(role: .user, text: text, items: nil)
        withAnimation(KuroAnimation.editorial) {
            messages.append(userMsg)
        }

        #if DEBUG
        let optimisticEnd = CFAbsoluteTimeGetCurrent()
        print("[Concierge Timing] send() called -> optimistic append: \(String(format: "%.1f", (optimisticEnd - sendStart) * 1000))ms")
        #endif

        // Low-signal prompts ("ADD", random letters, etc.) should not guess.
        // Ask a clarifying question with examples instead of hitting the network.
        if shouldAskClarifyingQuestion(text) {
            let assistantMsg = ConciergeMessage(
                role: .assistant,
                text: "What would you like to do?",
                showClarifyActions: true,
                items: nil
            )
            withAnimation(KuroAnimation.editorial) {
                messages.append(assistantMsg)
            }
            supabaseService.analytics.track("clarify_shown", payload: [
                "reason": "low_signal",
                "input_length": Double(text.count),
                "surface": "concierge_chat",
                "result": "clarify",
            ])
            supabaseService.trackInteractionEvent(
                "concierge_first_response_ms",
                surface: "concierge_chat",
                result: "clarify",
                startedAt: sendStartedAt
            )
            return
        }

        isWorking = true

        if looksLikeImport(text) {
            supabaseService.analytics.track("intent_detected", payload: [
                "intent": "import",
                "input_length": Double(text.count),
            ])
            await handleImportFlow(text: text, interactionStartedAt: sendStartedAt)
        } else {
            supabaseService.analytics.track("intent_detected", payload: [
                "intent": "recommend",
                "input_length": Double(text.count),
            ])
            await handleRecommendationFlow(text: text, interactionStartedAt: sendStartedAt)
        }

        isWorking = false
    }

    private func reparse(message: ConciergeMessage) {
        // Only assistant messages that were generated from a specific user input can re-parse.
        guard message.role == .assistant, let source = message.sourceUserText, !source.isEmpty else { return }
        input = source
        focusRequest = true
    }

    // MARK: Clarification Re-Parse (Disambiguated)
    private func handleClarification(kind: String, value: String, sourceText: String) async {
        guard clarifyV2Enabled else { return }
        errorText = nil
        isWorking = true

        // Dismiss keyboard
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif

        // Intent-level clarify can switch flows directly.
        if kind == "intent_unclear" {
            if value.lowercased() == "recommend_seed" {
                supabaseService.analytics.track("clarify_selected", payload: [
                    "kind": kind,
                    "value": value,
                    "routed_to": "recommend",
                    "surface": "concierge_chat",
                    "result": "recommend",
                ])
                await handleRecommendationFlow(text: sourceText)
                isWorking = false
                return
            }
        }

        let clarification = [kind: value]
        supabaseService.analytics.track("clarify_selected", payload: [
            "kind": kind,
            "value": value,
            "routed_to": "import_reparse",
            "surface": "concierge_chat",
            "result": "import_reparse",
        ])

        do {
            let response = try await supabaseService.conciergeParse(
                text: sourceText,
                scope: .both,
                clarification: clarification
            )

            // Pre-select top candidates
            for item in response.items {
                autoReasonByItemId[item.id] = nil
                if let top = item.candidates.first, top.score >= 0.60 {
                    if !hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention) {
                        selectedByItemId[item.id] = top
                    }
                }
                let action = computeItemAction(item: item)
                itemActions[item.id] = action
            }

            // Check if there are still ambiguities in the re-parsed response
            let remainingAmbiguity = response.items.compactMap(\.ambiguity).first

            if remainingAmbiguity != nil, clarifyV2Enabled {
                // Still ambiguous -- show another clarify card
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: "",
                    sourceUserText: sourceText,
                    items: response.items,
                    parseResponse: response,
                    ambiguity: remainingAmbiguity
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
            } else {
                // Resolved -- show the confirm bubble
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: "",
                    sourceUserText: sourceText,
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

        isWorking = false
    }

    private func shouldAskClarifyingQuestion(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }

        // If it already looks like an import (multi-line, progress/status cues), don't block.
        if looksLikeImport(t) { return false }

        // Single-token short inputs are most likely noise unless they are known abbreviations.
        let tokens = t.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
        if tokens.count == 1 {
            let s = String(tokens[0])
            let upper = s.uppercased()

            // Known short anime abbreviations we should treat as a seed instead of asking.
            // Keep this set small and high-signal; the server still handles the rich parsing.
            let knownAbbrev: Set<String> = [
                "AOT", "HXH", "NGE", "EVA", "DB", "DBZ", "DBS", "SAO",
                "TPN", "BNHA", "OP"
            ]
            if knownAbbrev.contains(upper) { return false }

            // Obvious low-signal (very short or command-like).
            if s.count <= 3 { return true }
            if upper == "ADD" || upper == "IMPORT" { return true }

            // Random letters (no vowels) tends to be noise: "AGBTT".
            if s.count <= 6,
               s.range(of: #"^[A-Za-z]{3,6}$"#, options: .regularExpression) != nil
            {
                let lower = s.lowercased()
                let hasVowel = lower.contains(where: { "aeiouy".contains($0) })
                if !hasVowel { return true }
            }
        }

        // If it's extremely short and has no structure, ask.
        if t.count < 5, t.range(of: #"[0-9\(\)]"#, options: .regularExpression) == nil {
            return true
        }

        return false
    }

    // MARK: Import Flow (Inline)
    private func handleImportFlow(text: String, interactionStartedAt: SupabaseService.InteractionStartedAt? = nil) async {
        let parseStartedAt = supabaseService.beginInteractionTiming()
        do {
            var firstResponseTracked = false

            func trackFirstResponseIfNeeded(_ result: String) {
                guard let interactionStartedAt, !firstResponseTracked else { return }
                firstResponseTracked = true
                supabaseService.trackInteractionEvent(
                    "concierge_first_response_ms",
                    surface: "concierge_chat",
                    result: result,
                    startedAt: interactionStartedAt
                )
            }

            #if DEBUG
            let parseStart = CFAbsoluteTimeGetCurrent()
            #endif

            let response = try await supabaseService.conciergeParse(text: text, scope: .both)

            supabaseService.analytics.track("parse_completed", payload: [
                "item_count": Double(response.items.count),
                "has_ambiguity": response.items.contains { $0.ambiguity != nil },
            ])
            supabaseService.trackInteractionEvent(
                "concierge_parse_ms",
                surface: "concierge_parse",
                result: "ok",
                startedAt: parseStartedAt,
                extra: ["item_count": response.items.count]
            )

            #if DEBUG
            let parseEnd = CFAbsoluteTimeGetCurrent()
            print("[Concierge Timing] parse response returned: \(String(format: "%.0f", (parseEnd - parseStart) * 1000))ms")
            #endif

            // Prefetch top candidate covers so the confirm bubble feels instant.
            #if canImport(UIKit)
            let maxPrefetchItems = conciergePerfV2Enabled ? 12 : 8
            let coverUrls: [URL] = Array(response.items.flatMap { item in
                item.candidates.prefix(1).compactMap { c in
                    guard let s = c.cover_image_medium, let url = URL(string: s) else { return nil }
                    return url
                }
            }.prefix(maxPrefetchItems))
            #if DEBUG
            let prefetchStart = CFAbsoluteTimeGetCurrent()
            print("[Concierge Timing] image prefetch started: \(String(format: "%.1f", (prefetchStart - parseEnd) * 1000))ms after parse")
            #endif
            Task.detached(priority: .background) {
                await ImagePipeline.shared.prefetch(urls: coverUrls, maxPixelSize: 520)
            }
            #endif

            // Pre-select top candidates (skip when adaptations are ambiguous)
            var hasAnyExistingEntry = false
            var ambiguousItemsNeedingHelp: [SupabaseService.ConciergeParseItem] = []
            for item in response.items {
                autoReasonByItemId[item.id] = nil
                if let top = item.candidates.first, top.score >= 0.60 {
                    if hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention) {
                        ambiguousItemsNeedingHelp.append(item)
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

            // Check for parser-level ambiguities that need user clarification
            let parserAmbiguity = response.items.compactMap(\.ambiguity).first

            if let ambiguity = parserAmbiguity, clarifyV2Enabled {
                // Dismiss keyboard when clarify card appears
                #if os(iOS)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif

                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: ambiguity.suggested_question ?? "",
                    sourceUserText: text,
                    items: response.items,
                    parseResponse: response,
                    ambiguity: ambiguity
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
                trackFirstResponseIfNeeded("clarify")
                #if DEBUG
                print("[Concierge Timing] clarify card rendered: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - parseStart) * 1000))ms total from parse start")
                #endif
            } else {
                // Auto-apply safety: disabled when ANY item has an existing_entry
                let allHighConfidence = !hasAnyExistingEntry && response.items.allSatisfy { item in
                    guard let top = item.candidates.first else { return false }
                    return top.score >= 0.85 && !hasAmbiguousAdaptations(candidates: item.candidates, yearMention: item.parsed.yearMention)
                }

                if allHighConfidence && !response.items.isEmpty {
                    // Auto-apply: skip confirm UI entirely
                    await autoApplyImport(response: response, interactionStartedAt: interactionStartedAt)
                } else {
                    // Show inline confirm bubble in chat
                    let assistantMsg = ConciergeMessage(
                        role: .assistant,
                        text: "",
                        sourceUserText: text,
                        items: response.items,
                        parseResponse: response
                    )
                    withAnimation(KuroAnimation.editorial) {
                        messages.append(assistantMsg)
                    }
                    trackFirstResponseIfNeeded("confirm")
                    #if DEBUG
                    print("[Concierge Timing] confirm bubble rendered: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - parseStart) * 1000))ms total from parse start")
                    #endif
                }
            }

            // On-device Apple FM can help pick the correct adaptation when candidates share a base title
            // (e.g. "Hunter x Hunter" 1999 vs 2011). This runs after the confirm bubble is visible
            // so the UI stays snappy, and it never overrides a user-made selection.
            if !ambiguousItemsNeedingHelp.isEmpty {
                Task {
                    await autoDisambiguateAmbiguousAdaptations(items: ambiguousItemsNeedingHelp, userText: text)
                }
            }
        } catch {
            supabaseService.trackInteractionEvent(
                "concierge_parse_ms",
                surface: "concierge_parse",
                result: "error",
                startedAt: parseStartedAt
            )
            handleError(error)
        }
    }

    private func autoDisambiguateAmbiguousAdaptations(
        items: [SupabaseService.ConciergeParseItem],
        userText: String
    ) async {
        // FM assist is optional and flag-gated.
        guard fmAssistEnabled else { return }

        for item in items {
            if Task.isCancelled { return }

            // Respect manual selections and "excluded" toggles.
            if excludedItemIds.contains(item.id) { continue }
            if selectedByItemId[item.id] != nil { continue }

            // Keep the candidate set small to reduce latency.
            let topCandidates = Array(item.candidates.prefix(4))
            guard topCandidates.count >= 2 else { continue }

            let fmCandidates: [DisambiguationCandidate] = topCandidates.enumerated().map { i, c in
                DisambiguationCandidate(
                    index: i,
                    title: c.title_raw,
                    year: c.year,
                    format: c.format,
                    score: c.score,
                    variantType: c.media_type
                )
            }

            guard let picked = await supabaseService.fmService.disambiguate(
                candidates: fmCandidates,
                userText: userText,
                rawTitle: item.raw
            ) else {
                continue
            }

            let idx = picked.selectedIndex
            guard topCandidates.indices.contains(idx) else { continue }

            // Apply only if the user still hasn't chosen something else.
            if selectedByItemId[item.id] == nil && !excludedItemIds.contains(item.id) {
                selectedByItemId[item.id] = topCandidates[idx]
                autoReasonByItemId[item.id] = picked.reasoning
            }
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
    private func autoApplyImport(
        response: SupabaseService.ConciergeParseResponse,
        interactionStartedAt: SupabaseService.InteractionStartedAt? = nil
    ) async {
        do {
            let chosen = buildApplyPayload(from: response)
            guard !chosen.isEmpty else { return }

            let res = try await supabaseService.conciergeApply(items: chosen)
            if let sessionId = res.sessionId {
                setLastApplySession(sessionId)
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
                onAction: {
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
            if let interactionStartedAt {
                supabaseService.trackInteractionEvent(
                    "concierge_first_response_ms",
                    surface: "concierge_chat",
                    result: "auto_apply",
                    startedAt: interactionStartedAt
                )
            }

        } catch {
            handleError(error)
        }
    }

    // MARK: Recommendation Flow (Inline Rails)
    private func handleRecommendationFlow(
        text: String,
        interactionStartedAt: SupabaseService.InteractionStartedAt? = nil
    ) async {
        let recommendStartedAt = supabaseService.beginInteractionTiming()
        do {
            var firstResponseTracked = false

            func trackFirstResponseIfNeeded(_ result: String) {
                guard let interactionStartedAt, !firstResponseTracked else { return }
                firstResponseTracked = true
                supabaseService.trackInteractionEvent(
                    "concierge_first_response_ms",
                    surface: "concierge_chat",
                    result: result,
                    startedAt: interactionStartedAt
                )
            }

            #if DEBUG
            let recStart = CFAbsoluteTimeGetCurrent()
            #endif

            let rec = try await supabaseService.conciergeRecommend(text: text, scope: .both, limit: 8)
            supabaseService.trackInteractionEvent(
                "concierge_recommend_ms",
                surface: "concierge_recommend",
                result: "ok",
                startedAt: recommendStartedAt,
                extra: ["item_count": (rec.items ?? []).count]
            )
            lastRecommendQuery = text
            lastRecommendWasRagAssist = rec.assist?.ragUsed == true
            lastRagSeedEntityId = rec.assist?.seedEntityId
            let sets = (rec.sets ?? []).filter { ($0.items ?? []).isEmpty == false }
            let flattened = sets.flatMap { $0.items ?? [] }
            let displayItems = !flattened.isEmpty ? flattened : (rec.items ?? [])
            let note = (rec.curatorNote ?? sets.first?.curatorNote ?? rec.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            #if DEBUG
            let recEnd = CFAbsoluteTimeGetCurrent()
            print("[Concierge Timing] recommend response returned: \(String(format: "%.0f", (recEnd - recStart) * 1000))ms")
            #endif

            // Prefetch recommendation posters for a snappy first render.
            #if canImport(UIKit)
            let maxPrefetchItems = conciergePerfV2Enabled ? 12 : 8
            let recUrls: [URL] = Array(displayItems.compactMap { item in
                guard let s = item.coverImageMedium, let url = URL(string: s) else { return nil }
                return url
            }.prefix(maxPrefetchItems))
            #if DEBUG
            print("[Concierge Timing] rec image prefetch started: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - recEnd) * 1000))ms after response")
            #endif
            Task.detached(priority: .background) {
                await ImagePipeline.shared.prefetch(urls: recUrls, maxPixelSize: 560)
            }
            #endif

            if rec.success, !displayItems.isEmpty {
                // Append inline recommendation message with editorial rails
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: note,
                    items: nil,
                    recommendations: !sets.isEmpty ? nil : displayItems,
                    recommendationSets: !sets.isEmpty ? sets : nil
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
                trackFirstResponseIfNeeded("recommend")
                #if DEBUG
                print("[Concierge Timing] rec bubble rendered: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - recStart) * 1000))ms total from rec start")
                #endif
            } else {
                lastRecommendWasRagAssist = false
                lastRagSeedEntityId = nil
                // No results — show text message
                let locale = (rec.locale ?? "en").lowercased()
                let fallback = locale.hasPrefix("de")
                    ? "Sag mir eine Stimmung oder eine klare Kante (kurz, ohne Romance, ein Jahr) — ich kuratiere es neu fuer dich."
                    : "Give me a mood or one constraint (short, no romance, a year) and I’ll curate it — new to you."
                let assistantMsg = ConciergeMessage(
                    role: .assistant,
                    text: rec.message ?? fallback,
                    items: nil
                )
                withAnimation(KuroAnimation.editorial) {
                    messages.append(assistantMsg)
                }
                trackFirstResponseIfNeeded("recommend_empty")
            }

        } catch {
            supabaseService.trackInteractionEvent(
                "concierge_recommend_ms",
                surface: "concierge_recommend",
                result: "error",
                startedAt: recommendStartedAt
            )
            handleError(error)
        }
    }

    // MARK: Confirm Import (From Inline Bubble)
    private func confirmImport(response: SupabaseService.ConciergeParseResponse, sourceMessageId: UUID? = nil) async {
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
                setLastApplySession(sessionId)
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

            if let sourceMessageId {
                appliedImportMessageIds.insert(sourceMessageId)
                lastAppliedImportMessageId = sourceMessageId
            }

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
                recordRagFeedbackIfNeeded(accepted: true)
            } else {
                let manga = try await supabaseService.fetchMangaById(item.mediaId)
                guard let manga else {
                    errorText = "Couldn't find that manga in the database."
                    return
                }
                selectedManga = manga
                recordRagFeedbackIfNeeded(accepted: true)
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
        recordRagFeedbackIfNeeded(accepted: true)
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

            setLastApplySession(nil)

            if res.success {
                if let lastAppliedImportMessageId {
                    appliedImportMessageIds.remove(lastAppliedImportMessageId)
                    self.lastAppliedImportMessageId = nil
                }
                showToast(.init(kind: .success, title: "Import undone", subtitle: nil, actionTitle: nil, onAction: nil))
            } else {
                showToast(.init(kind: .error, title: "Undo failed", subtitle: "Try again.", actionTitle: nil, onAction: nil))
            }
        } catch {
            errorText = "Undo failed: \(error.localizedDescription)"
            showToast(.init(kind: .error, title: "Undo failed", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil))
        }
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

    private func setLastApplySession(_ sessionId: String?) {
        lastApplySessionResetTask?.cancel()
        lastApplySessionId = sessionId
        guard let sessionId else { return }
        // Avoid stale sticky undo controls if the user moves on.
        lastApplySessionResetTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            guard !Task.isCancelled else { return }
            if lastApplySessionId == sessionId {
                lastApplySessionId = nil
            }
        }
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

    private func recordRagFeedbackIfNeeded(accepted: Bool, rejectedReason: String? = nil) {
        guard lastRecommendWasRagAssist, let query = lastRecommendQuery else { return }
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        guard !ragFeedbackSentForQuery.contains(key) else { return }
        ragFeedbackSentForQuery.insert(key)

        let locale = Locale.current.identifier
        let entityId = lastRagSeedEntityId

        Task(priority: .utility) {
            await supabaseService.conciergeRetrieveFeedback(
                query: query,
                locale: locale,
                selectedEntityId: entityId,
                accepted: accepted,
                rejectedReason: rejectedReason
            )
        }
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

    private func importFromLibrary() async {
        guard !isWorking else { return }
        errorText = nil

        let result = await supabaseService.conciergeLibraryExportText(
            includeStatus: Set(ListStatus.allCases),
            includeMediaTypes: ["anime", "manga"],
            maxItems: 400
        )

        guard let result else {
            showToast(.init(
                kind: .info,
                title: isGermanLocale ? "Bibliothek leer" : "Library is empty",
                subtitle: isGermanLocale ? "Bitte füge zuerst Titel zu deiner Bibliothek hinzu." : "Add titles to your library first.",
                actionTitle: nil,
                onAction: nil
            ))
            return
        }

        await sendExternalImport(
            sourceLabel: isGermanLocale ? "Kuro-Liste" : "Kuro library",
            displayText: isGermanLocale
                ? "Kuro-Liste importieren (\(result.exportedItemCount) Titel)"
                : "Importing from Kuro library (\(result.exportedItemCount) items)",
            sourceText: result.text,
            truncated: result.truncated
        )
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        guard let t = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty
        else {
            showToast(.init(
                kind: .info,
                title: isGermanLocale ? "Zwischenablage ist leer" : "Clipboard is empty",
                subtitle: isGermanLocale ? "Kopiere eine Liste von Titeln und tippe dann auf Einfügen." : "Copy a list of titles, then tap Paste.",
                actionTitle: nil,
                onAction: nil
            ))
            return
        }
        input = t
        focusRequest = true
        KuroAccessibility.impactHaptic(.light)
        #endif
    }

    private func seedExampleImport() {
        input = """
        Attack on Titan (completed)
        Jujutsu Kaisen up to ep 12
        Hunter x Hunter (2011)
        """
        focusRequest = true
        KuroAccessibility.impactHaptic(.light)
    }

    private func seedExampleVibe() {
        input = isGermanLocale
            ? "Etwas lustig, trocken, figurengetrieben — nicht kindisch."
            : "Something funny, dry, character-led — not childish."
        focusRequest = true
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

// MARK: - Guided Tutorial Overlay

private struct ConciergeTutorialOverlay: View {
    @Binding var step: Int
    let isGerman: Bool
    let onDismiss: () -> Void

    private let steps: [(iconEN: String, titleEN: String, bodyEN: String, iconDE: String, titleDE: String, bodyDE: String)] = [
        (
            iconEN: "text.bubble",
            titleEN: "Describe a mood",
            bodyEN: "Type something like \"dark, not gory, short\" and the Concierge curates two rails for you.",
            iconDE: "text.bubble",
            titleDE: "Beschreibe eine Stimmung",
            bodyDE: "Schreibe z.B. \"dunkel, kein Gore, kurz\" und der Concierge kuratiert zwei Rails fur dich."
        ),
        (
            iconEN: "doc.on.clipboard",
            titleEN: "Or paste your list",
            bodyEN: "Paste your anime list from any source. The Concierge matches, reconciles, and imports it.",
            iconDE: "doc.on.clipboard",
            titleDE: "Oder fuge deine Liste ein",
            bodyDE: "Fuge deine Anime-Liste ein. Der Concierge gleicht ab, erkennt Konflikte und importiert."
        ),
        (
            iconEN: "sparkles",
            titleEN: "Curated for you",
            bodyEN: "Recommendations come filtered against your library. No duplicates, no noise.",
            iconDE: "sparkles",
            titleDE: "Kuratiert fur dich",
            bodyDE: "Empfehlungen werden gegen deine Bibliothek gefiltert. Keine Duplikate, kein Rauschen."
        ),
    ]

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { advance() }

            VStack(spacing: 20) {
                Spacer()

                // Tutorial card
                VStack(spacing: 18) {
                    let s = steps[step]

                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: isGerman ? s.iconDE : s.iconEN)
                                .font(.system(size: 22, weight: .light))
                                .foregroundColor(.white.opacity(0.88))
                        )

                    Text(isGerman ? s.titleDE : s.titleEN)
                        .font(.system(size: 22, weight: .ultraLight, design: .serif))
                        .foregroundColor(.white.opacity(0.92))

                    Text(isGerman ? s.bodyDE : s.bodyEN)
                        .font(.kuroBody(weight: .light))
                        .foregroundColor(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)

                    // Step indicator
                    HStack(spacing: 6) {
                        ForEach(0..<steps.count, id: \.self) { i in
                            Circle()
                                .fill(Color.white.opacity(step == i ? 0.80 : 0.25))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.top, 4)

                    Button(action: { advance() }) {
                        Text(step < steps.count - 1
                             ? (isGerman ? "WEITER" : "NEXT")
                             : (isGerman ? "VERSTANDEN" : "GOT IT"))
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.8)
                            .foregroundColor(.black.opacity(0.88))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.92))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 20)

                Spacer()

                // Skip
                if step < steps.count - 1 {
                    Button(action: { onDismiss() }) {
                        Text(isGerman ? "Uberspringen" : "Skip")
                            .font(.kuroCaption(weight: .medium))
                            .foregroundColor(.white.opacity(0.42))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 48)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isGerman ? "Concierge-Anleitung" : "Concierge tutorial")
    }

    private func advance() {
        KuroAccessibility.impactHaptic(.light)
        if step < steps.count - 1 {
            withAnimation(KuroAnimation.fast) {
                step += 1
            }
        } else {
            onDismiss()
        }
    }
}

// MARK: - Preview
#Preview {
    ConciergeView()
}
