// MARK: - CONCIERGE VIEW (INLINE CHAT ARCHITECTURE)
// No full-screen state machine. Everything renders inline in the chat scroll.
// High-confidence imports auto-apply with undo toast. Recommendations appear as editorial rails.

import KuroCore
import KuroLibrary
import SwiftUI

// Import reconciliation (Add / Update / Skip, diff, pre-selection, auto-apply plan, apply items) lives in
// `ImportReconciler` (Kuro/Imports/ImportReconciler.swift), shared with the Profile AniList import.
// Message routing (low-signal gate, on-device intent threshold, keyword router, clarify re-route,
// parser clarification) lives in `ConciergeRouting` (Kuro/Concierge/ConciergeRouting.swift).

// MARK: - Main View
struct ConciergeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(InteractionTelemetry.self) private var interactionTelemetry
    @Environment(FeatureFlags.self) private var flags
    @Environment(CatalogStore.self) private var catalog
    @Environment(CollectionStore.self) private var collection
    @Environment(ImportsService.self) private var imports
    @Environment(ConciergeStore.self) private var concierge
    @Environment(AppleFMService.self) private var deviceIntelligence
    @Environment(\.kuroRoutes) private var routes

    let assistantEnabled: Bool
    var initialPrompt: String? = nil
    var onImportNavigation: ((ImportResultDestination) -> Void)? = nil

    // MARK: Input & Core State
    @State private var workflow = ConciergeWorkflowLifetime()
    @State private var input: String = ""
    @State private var didConsumeInitialPrompt = false
    @State private var focusRequest: Bool = false
    @State private var messages: [ConciergeMessage] = []
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var selectedByItemId: [String: ConciergeCandidate] = [:]
    @State private var itemActions: [String: ImportItemAction] = [:]
    @State private var excludedItemIds: Set<String> = []
    @State private var autoReasonByItemId: [String: String] = [:]
    @State private var lastApplySessionId: String? = nil
    /// Frozen Apply identity. A lost response retries this action; a new gesture or an edit starts another.
    @State private var applyAttempt = ImportApplyAttempt()
    @State private var lastApplySessionResetTask: Task<Void, Never>? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var assistantExpanded: Bool = false
    @State private var assistantOffset: CGSize = .zero
    @State private var assistantDragStart: CGSize = .zero
    @State private var containerSize: CGSize = CGSize(width: 393, height: 852)
    @State private var appliedImportMessageIds: Set<UUID> = []
    @State private var lastAppliedImportMessageId: UUID? = nil
    @State private var applyingImportMessageId: UUID? = nil
    @State private var appliedImportSummary: String? = nil
    @State private var lastRecommendQuery: String? = nil
    @State private var lastRecommendWasRagAssist: Bool = false
    @State private var warmupTask: Task<Void, Never>? = nil
    @State private var prefetchTask: Task<Void, Never>? = nil
    @State private var prefetchTask2: Task<Void, Never>? = nil
    @State private var backgroundRefreshTask: Task<Void, Never>? = nil
    @State private var backgroundRefreshTask2: Task<Void, Never>? = nil
    @State private var undoRefreshTask: Task<Void, Never>? = nil
    @State private var disambiguationTask: Task<Void, Never>? = nil
    @State private var lastRagSeedEntityId: String? = nil
    @State private var ragFeedbackSentForQuery: Set<String> = []
    @State private var showAniListImportSheet: Bool = false
    @State private var pendingAniListReview: ImportOutcome?
    @State private var pendingAniListTicket: ConciergeWorkflowScope.Ticket?
    @State private var importWorkflowJob: ImportOutcome?
    private var mascotState: ConciergeMascotState {
        if isWorking { return .thinking }
        if errorText != nil { return .concerned }
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .idle }
        return .listening
    }

    private var clarifyV2Enabled: Bool {
        flags.isClarifyV2Enabled
    }

    private var fmAssistEnabled: Bool {
        flags.isFmAssistEnabled && deviceIntelligence.isAvailable
    }

    private var conciergePerfV2Enabled: Bool {
        flags.isConciergePerfV2Enabled
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

    init(assistantEnabled: Bool = true, initialPrompt: String? = nil,
         onImportNavigation: ((ImportResultDestination) -> Void)? = nil) {
        self.assistantEnabled = assistantEnabled
        self.initialPrompt = initialPrompt
        self.onImportNavigation = onImportNavigation
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
        .sheet(isPresented: $showAniListImportSheet, onDismiss: {
            guard let job = pendingAniListReview else { return }
            pendingAniListReview = nil
            let origin = pendingAniListTicket; pendingAniListTicket = nil
            guard workflow.isCurrent(origin, session: imports.accountSession) else { return }
            importWorkflowJob = job
        }) {
            let origin = workflow.capture(session: imports.accountSession)
            ConciergeAniListImportSheet(
                imports: imports,
                isGermanLocale: isGermanLocale,
                usesStructuredImport: flags.seriesFoundationV1Enabled,
                onPrepared: { job in
                    guard workflow.isCurrent(origin, session: imports.accountSession) else { return }
                    pendingAniListReview = job; pendingAniListTicket = origin
                }
            ) { response in
                let count = response.itemCount ?? 0
                perform(origin: origin) {
                    await sendExternalImport(
                        sourceLabel: "AniList",
                        displayText: isGermanLocale
                            ? "AniList-Import — \(count) Titel"
                            : "AniList import — \(count) items",
                        sourceText: response.text ?? "",
                        truncated: response.truncated ?? false
                    )
                }
            }
        }
        .sheet(item: $importWorkflowJob) { job in
            let origin = workflow.capture(session: imports.accountSession)
            ImportWorkflowSheet(imports: imports, job: job) { destination in
                guard workflow.isCurrent(origin, session: imports.accountSession) else { return }
                onImportNavigation?(destination)
            }
        }
        .onAppear { workflow.activate(session: imports.accountSession) }
        .task {
            // Warm up under the same account/chat lifetime as foreground actions.
            warmupTask = workflow.launch(origin: workflow.capture(session: imports.accountSession), session: imports.accountSession) {
                await concierge.conciergeWarmup()
            }

            // Pre-fill input from deep link prompt (consumed once)
            if !didConsumeInitialPrompt, let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
                didConsumeInitialPrompt = true
                input = prompt
                focusRequest = true
            }
        }
        .onDisappear {
            workflow.deactivate()
            cancelAuxiliaryTasks()
            isWorking = false
            applyAttempt.abandon()
        }
        .onChange(of: imports.accountSession.current) {
            startNewChat()
            workflow.activate(session: imports.accountSession)
        }
        .preferredColorScheme(.light)
    }

    private var editorialChatView: some View {
        let origin = workflow.capture(session: imports.accountSession)
        return ConciergeEditorialShell(
            title: "Concierge",
            subtitle: editorialSubtitle,
            errorText: errorText,
            showsIntentDeck: false
        ) {
            EmptyView()
        } responseStage: {
            ConciergeResponseStage {
                messageTimeline(
                    horizontalPadding: 24,
                    topPadding: 20,
                    bottomPadding: 20,
                    messageSpacing: 20,
                    includeStarter: true
                )
            }
        } composer: {
            ConciergeInputField(
                text: $input,
                isSending: isWorking,
                focusRequest: $focusRequest,
                onSend: { text in
                    perform(origin: origin) { await send(text: text) }
                }
                ,onAutoSend: { text in
                    // Auto-send only when the input field detects a real paste import list.
                    perform(origin: origin) { await send(text: text) }
                }
            )
            .kuroSwipeExclusionZone()
        } footer: {
            Button(isGermanLocale ? "Aus AniList importieren" : "Import from AniList") {
                guard workflow.isCurrent(origin, session: imports.accountSession) else { return }
                showAniListImportSheet = true
            }
            .font(.kuroCaption()).foregroundStyle(Color.kuroTextSecondary)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { containerSize = geo.size }
            }
        }
    }

    private func sendExternalImport(sourceLabel: String, displayText: String, sourceText: String, truncated: Bool) async {
        guard isWorkflowCurrent else { return }
        let t = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard !isWorking else { return }

        errorText = nil
        let sendStartedAt = interactionTelemetry.beginInteractionTiming()

        // Compact user bubble (avoid dumping 200 lines into chat).
        let userMsg = ConciergeMessage(role: .user, text: displayText, sourceUserText: t, items: nil)
        withAnimation(KuroAnimation.editorial) {
            messages.append(userMsg)
        }

        isWorking = true
        defer { if isWorkflowCurrent { isWorking = false } }

        await handleImportFlow(text: t, interactionStartedAt: sendStartedAt)
        guard isWorkflowCurrent else { return }

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
        let origin = workflow.capture(session: imports.accountSession)
        return VStack(spacing: 0) {
            messageTimeline(
                horizontalPadding: KuroDesignSpacing.padding,
                topPadding: KuroDesignSpacing.md,
                bottomPadding: KuroDesignSpacing.md,
                includeStarter: true
            )

            if let errorText {
                Text(errorText)
                    .font(.kuroCaption())
                    .foregroundColor(.kuroError)
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.vertical, 10)
            }

            Rectangle()
                .fill(Color.kuroBlack06)
                .frame(height: 0.5)

            ConciergeInputField(
                text: $input,
                isSending: isWorking,
                focusRequest: $focusRequest,
                onSend: { text in
                    perform(origin: origin) { await send(text: text) }
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
        let origin = workflow.capture(session: imports.accountSession)
        let undoSessionId = lastApplySessionId
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: messageSpacing) {
                    if includeStarter && messages.isEmpty {
                        ConciergeIntroCard()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                            .padding(.bottom, KuroDesignSpacing.sm)

                        ConciergeStarterActions(
                            onPaste: { if workflow.isCurrent(origin, session: imports.accountSession) { pasteFromClipboard() } },
                            onImportLibrary: {
                                perform(origin: origin) { await importFromLibrary() }
                            },
                            onExampleImport: { if workflow.isCurrent(origin, session: imports.accountSession) { seedExampleImport() } },
                            onExampleVibe: { if workflow.isCurrent(origin, session: imports.accountSession) { seedExampleVibe() } }
                        )
                        .frame(maxWidth: .infinity)
                    }

                    if !messages.isEmpty {
                        HStack {
                            Spacer()
                            Button {
                                guard workflow.isCurrent(origin, session: imports.accountSession) else { return }
                                startNewChat()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.message")
                                        .font(.kuroCustom(10, weight: .medium, relativeTo: .caption1))
                                    Text("NEW CHAT")
                                        .font(.kuroMicro(weight: .semibold))
                                        .tracking(1.2)
                                }
                                .foregroundColor(.kuroTextTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.kuroBlack06)
                                )
                            }
                        }
                    }

                    ForEach(messages) { msg in
                        ConciergeBubble(
                            message: msg,
                            selected: { item in
                                guard workflow.isCurrent(origin, session: imports.accountSession) else { return nil }
                                return selectedByItemId[item.id]
                            },
                            onSelect: { item, candidate in
                                guard workflow.isCurrent(origin, session: imports.accountSession) else { return }
                                KuroAccessibility.impactHaptic(.light)
                                selectedByItemId[item.id] = candidate
                            },
                            onOpenRecommendation: { rec in
                                perform(origin: origin) { await openRecommendation(rec) }
                            },
                            onQuickSave: { rec in
                                perform(origin: origin) { await quickSaveRecommendation(rec) }
                            },
                            onClarifyPaste: { if workflow.isCurrent(origin, session: imports.accountSession) { pasteFromClipboard() } },
                            onClarifyImportLibrary: {
                                perform(origin: origin) { await importFromLibrary() }
                            },
                            onClarifyExampleImport: { if workflow.isCurrent(origin, session: imports.accountSession) { seedExampleImport() } },
                            onClarifyExampleVibe: { if workflow.isCurrent(origin, session: imports.accountSession) { seedExampleVibe() } },
                            onClarifyAmbiguity: clarifyV2Enabled ? { kind, value, sourceText in
                                perform(origin: origin) { await handleClarification(kind: kind, value: value, sourceText: sourceText) }
                            } : nil,
                            onConfirmItems: { response in
                                perform(origin: origin) { await confirmImport(response: response, sourceMessageId: msg.id) }
                            },
                            onReparse: {
                                guard workflow.isCurrent(origin, session: imports.accountSession) else { return }
                                reparse(message: msg)
                            },
                            onUndoImport: undoSessionId != nil ? {
                                guard let sid = undoSessionId else { return }
                                perform(origin: origin) { await undoApply(sessionId: sid) }
                            } : nil,
                            onViewCollection: appliedImportMessageIds.contains(msg.id) ? {
                                guard workflow.isCurrent(origin, session: imports.accountSession) else { return }
                                navigateToCollection()
                            } : nil,
                            isImportApplied: appliedImportMessageIds.contains(msg.id),
                            isImportApplying: applyingImportMessageId == msg.id,
                            importAppliedSummary: appliedImportMessageIds.contains(msg.id) ? appliedImportSummary : nil,
                            autoReasonByItemId: autoReasonByItemId,
                            itemActions: itemActions,
                            excludedItemIds: Binding(
                                get: { workflow.isCurrent(origin, session: imports.accountSession) ? excludedItemIds : [] },
                                set: { if workflow.isCurrent(origin, session: imports.accountSession) { excludedItemIds = $0 } }
                            )
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
        guard isWorkflowCurrent else { return }
        guard !text.isEmpty else { return }
        guard !isWorking else { return }
        errorText = nil
        let sendStartedAt = interactionTelemetry.beginInteractionTiming()

        #if DEBUG
        let sendStart = CFAbsoluteTimeGetCurrent()
        #endif

        // Add user message immediately (optimistic)
        let userMsg = ConciergeMessage(role: .user, text: text, items: nil)
        withAnimation(KuroAnimation.editorial) {
            messages.append(userMsg)
        }

        // Mark first use (collapses intro hint on next visit)
        if !UserDefaults.standard.bool(forKey: "kuro_concierge_used") {
            UserDefaults.standard.set(true, forKey: "kuro_concierge_used")
        }

        #if DEBUG
        let optimisticEnd = CFAbsoluteTimeGetCurrent()
        print("[Concierge Timing] send() called -> optimistic append: \(String(format: "%.1f", (optimisticEnd - sendStart) * 1000))ms")
        #endif

        // Low-signal prompts ("ADD", random letters, etc.) should not guess.
        // Ask a clarifying question with examples instead of hitting the network.
        // NOTE: This runs BEFORE FM intent classification (by design).
        // Catches garbage/low-signal input without burning FM inference.
        if ConciergeRouting.shouldAskClarifyingQuestion(text) {
            let assistantMsg = ConciergeMessage(
                role: .assistant,
                text: "What would you like to do?",
                showClarifyActions: true,
                items: nil
            )
            withAnimation(KuroAnimation.editorial) {
                messages.append(assistantMsg)
            }
            interactionTelemetry.track("clarify_shown", payload: [
                "reason": "low_signal",
                "input_length": Double(text.count),
                "surface": "concierge_chat",
                "result": "clarify",
            ])
            interactionTelemetry.trackInteractionEvent(
                "concierge_first_response_ms",
                surface: "concierge_chat",
                result: "clarify",
                startedAt: sendStartedAt
            )
            return
        }

        isWorking = true

        if fmAssistEnabled {
            // FM-primary: use on-device model for intent classification
            let locale = isGermanLocale ? "de" : "en"
            let fmResult = await deviceIntelligence.assistIntent(text: text, locale: locale)
            guard isWorkflowCurrent else { return }

            if let result = fmResult,
               let flow = ConciergeRouting.onDeviceFlow(intent: result.selectedIntent, confidence: result.confidence) {
                let intent = result.selectedIntent

                interactionTelemetry.track("intent_detected", payload: [
                    "intent": intent,
                    "source": "fm",
                    "confidence": result.confidence,
                    "input_length": Double(text.count),
                ])

                #if DEBUG
                print("[Concierge] FM intent: \(intent) (confidence: \(String(format: "%.2f", result.confidence)), reasoning: \(result.reasoning))")
                #endif

                switch flow {
                case .importList:
                    await handleImportFlow(text: text, interactionStartedAt: sendStartedAt)
                case .clarify:
                    let clarifyMsg = ConciergeMessage(
                        role: .assistant,
                        text: "What would you like to do?",
                        showClarifyActions: true,
                        items: nil
                    )
                    withAnimation(KuroAnimation.editorial) {
                        messages.append(clarifyMsg)
                    }
                case .recommendation:
                    // recommend_vibe, recommend_seed, library_query, club_action
                    await handleRecommendationFlow(text: text, interactionStartedAt: sendStartedAt)
                }
            } else {
                // FM failed, timed out, or low confidence — fall back to keywords
                #if DEBUG
                if let result = fmResult {
                    print("[Concierge] FM low confidence (\(String(format: "%.2f", result.confidence))), falling back to keywords")
                } else {
                    print("[Concierge] FM unavailable, falling back to keywords")
                }
                #endif
                await routeByKeywords(text: text, sendStartedAt: sendStartedAt)
            }
        } else {
            // FM not available — keyword routing (current behavior)
            await routeByKeywords(text: text, sendStartedAt: sendStartedAt)
        }

        if isWorkflowCurrent { isWorking = false }
    }

    private func routeByKeywords(text: String, sendStartedAt: CFAbsoluteTime) async {
        guard isWorkflowCurrent else { return }
        if ConciergeRouting.keywordFlow(for: text) == .importList {
            interactionTelemetry.track("intent_detected", payload: [
                "intent": "import",
                "source": "keywords",
                "input_length": Double(text.count),
            ])
            await handleImportFlow(text: text, interactionStartedAt: sendStartedAt)
        } else {
            interactionTelemetry.track("intent_detected", payload: [
                "intent": "recommend",
                "source": "keywords",
                "input_length": Double(text.count),
            ])
            await handleRecommendationFlow(text: text, interactionStartedAt: sendStartedAt)
        }
    }

    private func reparse(message: ConciergeMessage) {
        // Only assistant messages that were generated from a specific user input can re-parse.
        guard message.role == .assistant, let source = message.sourceUserText, !source.isEmpty else { return }
        input = source
        focusRequest = true
    }

    // MARK: Clarification Re-Parse (Disambiguated)
    private func handleClarification(kind: String, value: String, sourceText: String) async {
        guard isWorkflowCurrent else { return }
        guard clarifyV2Enabled else { return }
        errorText = nil
        isWorking = true

        // Dismiss keyboard
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif

        // Intent-level clarify can switch flows directly.
        if ConciergeRouting.clarificationRoute(kind: kind, value: value) == .recommendation {
            interactionTelemetry.track("clarify_selected", payload: [
                "kind": kind,
                "value": value,
                "routed_to": "recommend",
                "surface": "concierge_chat",
                "result": "recommend",
            ])
            await handleRecommendationFlow(text: sourceText)
            guard isWorkflowCurrent else { return }
            isWorking = false
            return
        }

        let clarification = [kind: value]
        interactionTelemetry.track("clarify_selected", payload: [
            "kind": kind,
            "value": value,
            "routed_to": "import_reparse",
            "surface": "concierge_chat",
            "result": "import_reparse",
        ])

        do {
            // Repeated lines collapse; existing entries come from the Library, not the parse response.
            let parsed = try await imports.conciergeParse(
                text: sourceText, scope: .both, clarification: clarification
            )
            guard isWorkflowCurrent else { return }
            let response = ImportReconciler.prepared(parsed, existing: ImportReconciler.libraryLookup(library))

            // Pre-select top candidates (the re-parse also sets the action of ambiguous lines)
            let preselection = ImportReconciler.initialSelectionsClarificationReparse(for: response.items)
            for item in response.items {
                autoReasonByItemId[item.id] = nil
            }
            selectedByItemId.merge(preselection.selections) { _, new in new }
            itemActions.merge(preselection.actions) { _, new in new }

            // Check if there are still ambiguities in the re-parsed response
            if let remainingAmbiguity = ConciergeRouting.parserClarification(in: response.items, clarifyEnabled: clarifyV2Enabled) {
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
            guard isWorkflowCurrent else { return }
            handleError(error)
        }

        if isWorkflowCurrent { isWorking = false }
    }

    // MARK: Import Flow (Inline)
    private func handleImportFlow(text: String, interactionStartedAt: InteractionTelemetry.StartedAt? = nil) async {
        guard isWorkflowCurrent else { return }
        let parseStartedAt = interactionTelemetry.beginInteractionTiming()
        do {
            var firstResponseTracked = false

            func trackFirstResponseIfNeeded(_ result: String) {
                guard let interactionStartedAt, !firstResponseTracked else { return }
                firstResponseTracked = true
                interactionTelemetry.trackInteractionEvent(
                    "concierge_first_response_ms",
                    surface: "concierge_chat",
                    result: result,
                    startedAt: interactionStartedAt
                )
            }

            #if DEBUG
            let parseStart = CFAbsoluteTimeGetCurrent()
            #endif

            // Repeated lines collapse; existing entries come from the Library, not the parse response.
            let parsed = try await imports.conciergeParse(text: text, scope: .both)
            guard isWorkflowCurrent else { return }
            let response = ImportReconciler.prepared(parsed, existing: ImportReconciler.libraryLookup(library))

            interactionTelemetry.trackInteractionEvent(
                "parse_completed",
                surface: "concierge_parse",
                result: "ok",
                startedAt: parseStartedAt,
                extra: [
                    "item_count": Double(response.items.count),
                    "has_ambiguity": response.items.contains { $0.ambiguity != nil },
                ]
            )
            interactionTelemetry.trackInteractionEvent(
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
            prefetchTask = Task(priority: .background) {
                guard isWorkflowCurrent else { return }
                await ImagePipeline.shared.prefetch(urls: coverUrls, maxPixelSize: 520)
            }
            #endif

            // Pre-select top candidates (skip when adaptations are ambiguous; those lines get no action here)
            let preselection = ImportReconciler.initialSelectionsFirstParse(for: response.items)
            for item in response.items {
                autoReasonByItemId[item.id] = nil
            }
            selectedByItemId.merge(preselection.selections) { _, new in new }
            itemActions.merge(preselection.actions) { _, new in new }
            let ambiguousItemsNeedingHelp = preselection.ambiguousItems

            // Check for parser-level ambiguities that need user clarification
            if let ambiguity = ConciergeRouting.parserClarification(in: response.items, clarifyEnabled: clarifyV2Enabled) {
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
                // Auto-apply safety: every item >= 0.85, no ambiguous adaptations, nothing already in the library
                // (and the Library loaded for this account: an unknown tracking state never auto-applies).
                // Parser ambiguity blocks auto-apply (locked: same rule as Profile, clarify_v2 on or off).
                switch ImportReconciler.conciergeAutoApplyPlan(
                    for: response.items,
                    loadState: library.loadState,
                    excluded: excludedItemIds,
                    existing: ImportReconciler.libraryLookup(library)
                ) {
                case .apply(let applyItems, let omitted):
                    // Auto-apply: skip confirm UI entirely
                    await autoApplyImport(
                        response: response,
                        chosen: applyItems.map(\.payload),
                        interactionStartedAt: interactionStartedAt,
                        omittedBeyondLimit: omitted
                    )
                case .nothingToApply:
                    // Every line excluded: nothing is applied and no confirm bubble is shown (as before).
                    break
                case .review:
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

            guard isWorkflowCurrent else { return }
            // On-device Apple FM can help pick the correct adaptation when candidates share a base title
            // (e.g. "Hunter x Hunter" 1999 vs 2011). This runs after the confirm bubble is visible
            // so the UI stays snappy, and it never overrides a user-made selection.
            if !ambiguousItemsNeedingHelp.isEmpty {
                disambiguationTask = Task {
                    await autoDisambiguateAmbiguousAdaptations(items: ambiguousItemsNeedingHelp, userText: text)
                }
            }
        } catch {
            guard isWorkflowCurrent else { return }
            interactionTelemetry.trackInteractionEvent(
                "concierge_parse_ms",
                surface: "concierge_parse",
                result: "error",
                startedAt: parseStartedAt
            )
            handleError(error)
        }
    }

    private func autoDisambiguateAmbiguousAdaptations(
        items: [ConciergeParseItem],
        userText: String
    ) async {
        guard isWorkflowCurrent else { return }
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

            let result = await deviceIntelligence.disambiguate(
                candidates: fmCandidates,
                userText: userText,
                rawTitle: item.raw
            )
            guard isWorkflowCurrent else { return }
            guard let picked = result else { continue }

            let idx = picked.selectedIndex
            guard topCandidates.indices.contains(idx) else { continue }

            // Apply only if the user still hasn't chosen something else.
            if selectedByItemId[item.id] == nil && !excludedItemIds.contains(item.id) {
                selectedByItemId[item.id] = topCandidates[idx]
                autoReasonByItemId[item.id] = picked.reasoning
            }
        }
    }

    // MARK: Auto-Apply (High Confidence, Pure Adds Only)
    /// Applies `chosen` (the non-empty apply items of `ImportReconciler.conciergeAutoApplyPlan`) without a confirm step.
    private func autoApplyImport(
        response: ConciergeParseResponse,
        chosen: [[String: Any]],
        interactionStartedAt: InteractionTelemetry.StartedAt? = nil,
        omittedBeyondLimit: Int = 0
    ) async {
        guard isWorkflowCurrent else { return }
        let anchor = "auto:" + response.items.map(\.raw).joined(separator: "\n")
        let started = applyAttempt.begin(anchor: anchor, stamp: "auto") { chosen }
        do {
            let res = try await imports.conciergeApply(items: started.items, idempotencyKey: started.key)
            guard isWorkflowCurrent else { return }
            let presented = res.presentation
            guard presented.tone != .failed else {
                applyAttempt.complete()
                showToast(.init(kind: .error, title: "Failed to add items", subtitle: presented.firstError ?? "Unknown error", actionTitle: nil, onAction: nil))
                return
            }
            applyAttempt.complete()
            if let sessionId = presented.undoSessionId {
                setLastApplySession(sessionId)
            }

            // Refresh the Collection feed in background (don't block toast); `conciergeApply`
            // already re-reads the Library projection.
            backgroundRefreshTask = Task {
                guard isWorkflowCurrent else { return }
                await collection.fetchCollectionFeed(status: nil)
            }

            // Show success toast with undo when the session can still be reversed.
            let appliedCount = presented.acceptedCount
            var summaryText: String
            if presented.tone == .empty {
                summaryText = "Nothing to add"
            } else if presented.tone == .partial {
                summaryText = "\(appliedCount) item\(appliedCount == 1 ? "" : "s") added, some need review"
            } else {
                summaryText = "\(appliedCount) item\(appliedCount == 1 ? "" : "s") added to collection"
            }
            if let omitted = ImportReconciler.omittedApplyCopy(omitted: omittedBeyondLimit, german: false) {
                summaryText = "\(summaryText). \(omitted)"
            }
            let lines = applyConfirmationLines(response: response, result: res)
            let rejectedCount = presented.conflictCount + presented.errorCount
            let sid = presented.undoSessionId
            let origin = ConciergeWorkflowScope.ticket
            showToast(.init(
                kind: presented.tone == .applied ? .success : .info,
                title: summaryText,
                subtitle: rejectedCount > 0 ? "\(rejectedCount) need review" : nil,
                actionTitle: sid == nil ? nil : "UNDO",
                onAction: {
                    guard let sid else { return }
                    perform(origin: origin) {
                        await undoApply(sessionId: sid)
                    }
                }
            ), autoDismissSeconds: 4.0)

            let confirmMsg = ConciergeMessage(
                role: .assistant,
                text: ImportApplyConfirmation.text(summary: summaryText, applied: lines.applied, rejected: lines.rejected),
                items: nil
            )
            withAnimation(KuroAnimation.editorial) {
                appliedImportSummary = summaryText
                messages.append(confirmMsg)
            }
            if let interactionStartedAt {
                interactionTelemetry.trackInteractionEvent(
                    "concierge_first_response_ms",
                    surface: "concierge_chat",
                    result: "auto_apply",
                    startedAt: interactionStartedAt
                )
            }

        } catch {
            guard isWorkflowCurrent else { return }
            applyAttempt.observe(error)
            handleError(error)
        }
    }

    // MARK: Recommendation Flow (Inline Rails)
    private func handleRecommendationFlow(
        text: String,
        interactionStartedAt: InteractionTelemetry.StartedAt? = nil
    ) async {
        guard isWorkflowCurrent else { return }
        let recommendStartedAt = interactionTelemetry.beginInteractionTiming()
        do {
            var firstResponseTracked = false

            func trackFirstResponseIfNeeded(_ result: String) {
                guard let interactionStartedAt, !firstResponseTracked else { return }
                firstResponseTracked = true
                interactionTelemetry.trackInteractionEvent(
                    "concierge_first_response_ms",
                    surface: "concierge_chat",
                    result: result,
                    startedAt: interactionStartedAt
                )
            }

            #if DEBUG
            let recStart = CFAbsoluteTimeGetCurrent()
            #endif

            let rec = try await concierge.conciergeRecommend(text: text, scope: .both, limit: 8)
            guard isWorkflowCurrent else { return }
            interactionTelemetry.trackInteractionEvent(
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
            prefetchTask2 = Task(priority: .background) {
                guard isWorkflowCurrent else { return }
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
                let ladderCandidates: [(mediaType: String, mediaId: Int)] = displayItems
                    .prefix(8)
                    .map { item in
                        (mediaType: item.mediaType.uppercased(), mediaId: item.mediaId)
                    }
                catalog.prefetchMediaRelationRefreshRequests(
                    items: ladderCandidates,
                    reason: "concierge_recommend"
                )
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

        } catch is CancellationError {
            return
        } catch {
            guard isWorkflowCurrent else { return }
            interactionTelemetry.trackInteractionEvent(
                "concierge_recommend_ms",
                surface: "concierge_recommend",
                result: "error",
                startedAt: recommendStartedAt
            )
            handleError(error)
        }
    }

    // MARK: Confirm Import (From Inline Bubble)
    private func confirmImport(response: ConciergeParseResponse, sourceMessageId: UUID? = nil) async {
        guard isWorkflowCurrent else { return }
        isWorking = true
        if let sourceMessageId {
            applyingImportMessageId = sourceMessageId
        }

        // Apply gate: never while the Library is not loaded for this account (a line that looks
        // untracked may be tracked). The confirm control stays; the Library refreshes so the user can
        // confirm again.
        guard ImportReconciler.canApply(loadState: library.loadState) else {
            showToast(.init(kind: .info, title: "Your library is still loading. Try again in a moment.", subtitle: nil, actionTitle: nil, onAction: nil))
            isWorking = false
            applyingImportMessageId = nil
            await libraryActions.fetchUserLists()
            return
        }

        do {
            let anchor = "confirm:\(sourceMessageId?.uuidString ?? "current")"
            let started = applyAttempt.begin(anchor: anchor, stamp: selectionStamp()) {
                buildApplyPayload(from: response)
            }
            let chosen = started.items

            guard !chosen.isEmpty else {
                applyAttempt.abandon()
                showToast(.init(kind: .error, title: "No items selected", subtitle: nil, actionTitle: nil, onAction: nil))
                isWorking = false
                applyingImportMessageId = nil
                return
            }

            let res = try await imports.conciergeApply(items: chosen, idempotencyKey: started.key)
            guard isWorkflowCurrent else { return }
            let presented = res.presentation
            guard presented.tone != .failed else {
                applyAttempt.complete()
                showToast(.init(kind: .error, title: "Failed to apply items", subtitle: presented.firstError ?? "Unknown error", actionTitle: nil, onAction: nil))
                isWorking = false
                applyingImportMessageId = nil
                return
            }
            applyAttempt.complete()
            if let sessionId = presented.undoSessionId {
                setLastApplySession(sessionId)
            }

            // Refresh the Collection feed in background; `conciergeApply` already re-reads the
            // Library projection.
            backgroundRefreshTask2 = Task {
                guard isWorkflowCurrent else { return }
                await collection.fetchCollectionFeed(status: nil)
            }

            // Compute summary text based on the actual server outcome, including a reversible partial apply.
            let serverAddCount = presented.addCount
            let serverUpdateCount = presented.updateCount
            let conflictCount = presented.conflictCount

            var summaryParts: [String] = []
            if serverAddCount > 0 { summaryParts.append("\(serverAddCount) added") }
            if serverUpdateCount > 0 { summaryParts.append("\(serverUpdateCount) updated") }
            let summaryText = presented.tone == .empty
                ? "Nothing to add"
                : (summaryParts.isEmpty ? "\(presented.acceptedCount) items applied" : summaryParts.joined(separator: ", "))
            let rejectedCount = presented.conflictCount + presented.errorCount

            let sid = presented.undoSessionId
            let origin = ConciergeWorkflowScope.ticket
            showToast(.init(
                kind: presented.tone == .applied && rejectedCount == 0 ? .success : .info,
                title: summaryText,
                subtitle: rejectedCount > 0 ? "\(rejectedCount) need review" : nil,
                actionTitle: sid == nil ? nil : "UNDO",
                onAction: {
                    guard let sid else { return }
                    perform(origin: origin) {
                        await undoApply(sessionId: sid)
                    }
                }
            ), autoDismissSeconds: 4.0)

            withAnimation(KuroAnimation.editorial) {
                appliedImportSummary = summaryText
                applyingImportMessageId = nil
                if let sourceMessageId {
                    appliedImportMessageIds.insert(sourceMessageId)
                    lastAppliedImportMessageId = sourceMessageId
                }
            }

        } catch {
            guard isWorkflowCurrent else { return }
            applyAttempt.observe(error)
            handleError(error)
        }

        if isWorkflowCurrent { isWorking = false }
    }

    // MARK: Build Apply Payload
    /// Selected, non-excluded, non-skip items, reconciled against the Library entry of the chosen title
    /// (status kept unless the line states one, stored rating/notes sent back, expected state for updates).
    private func buildApplyPayload(from response: ConciergeParseResponse) -> [[String: Any]] {
        ImportReconciler.applyItems(
            for: response.items,
            selections: selectedByItemId,
            excluded: excludedItemIds,
            actions: itemActions,
            existing: ImportReconciler.libraryLookup(library)
        ).map(\.payload)
    }

    // MARK: Actions
    private func openRecommendation(_ item: ConciergeRecommendResponse.Item) async {
        guard isWorkflowCurrent else { return }
        errorText = nil

        do {
            if item.mediaType.uppercased() == "ANIME" {
                let anime = try await catalog.fetchAnimeById(item.mediaId)
                guard isWorkflowCurrent else { return }
                guard let anime else {
                    errorText = "Couldn't find that anime in the database."
                    return
                }
                routes.openMedia(MediaRoute(anime: anime))
                recordRagFeedbackIfNeeded(accepted: true)
            } else {
                let manga = try await catalog.fetchMangaById(item.mediaId)
                guard isWorkflowCurrent else { return }
                guard let manga else {
                    errorText = "Couldn't find that manga in the database."
                    return
                }
                routes.openMedia(MediaRoute(manga: manga))
                recordRagFeedbackIfNeeded(accepted: true)
            }
        } catch {
            guard isWorkflowCurrent else { return }
            errorText = "Couldn't open: \(error.localizedDescription)"
        }
    }

    /// Quick save = `save` semantics: adds the title as Planned; a title that is already tracked
    /// keeps its status, progress and everything else.
    private func quickSaveRecommendation(_ item: ConciergeRecommendResponse.Item) async {
        guard isWorkflowCurrent else { return }
        let key = MediaKey(kind: item.mediaType.uppercased() == "ANIME" ? .anime : .manga, id: item.mediaId)
        let outcome = await libraryActions.save(key, status: .planning)
        guard isWorkflowCurrent else { return }
        switch outcome {
        case .applied(let change):
            recordRagFeedbackIfNeeded(accepted: true)
            let title = change.kind == .added ? "Added to Planning" : "Already in your list"
            showToast(.init(kind: .success, title: title, subtitle: item.title, actionTitle: nil, onAction: nil))
        case .failed(let error):
            showToast(.init(kind: .error, title: "Couldn't update list", subtitle: friendlyListMutationMessage(error, isGerman: false), actionTitle: nil, onAction: nil))
        }
    }

    // MARK: Undo
    private func undoApply(sessionId: String) async {
        guard isWorkflowCurrent else { return }
        isWorking = true
        errorText = nil
        defer { if isWorkflowCurrent { isWorking = false } }

        do {
            let res = try await imports.conciergeUndo(sessionId: sessionId)
            guard isWorkflowCurrent else { return }

            // Refresh the Collection feed in background; `conciergeUndo` already re-reads the
            // Library projection.
            undoRefreshTask = Task {
                guard isWorkflowCurrent else { return }
                await collection.fetchCollectionFeed(status: nil)
            }

            if res.success {
                setLastApplySession(nil)
                if let lastAppliedImportMessageId {
                    appliedImportMessageIds.remove(lastAppliedImportMessageId)
                    self.lastAppliedImportMessageId = nil
                }
                let kept = res.keptCount
                showToast(.init(
                    kind: .success,
                    title: "Import undone",
                    subtitle: kept > 0 ? "\(kept) later edit\(kept == 1 ? "" : "s") kept" : nil,
                    actionTitle: nil,
                    onAction: nil
                ))
            } else {
                showToast(.init(kind: .error, title: "Undo failed", subtitle: "Try again.", actionTitle: nil, onAction: nil))
            }
        } catch is CancellationError {
            return
        } catch {
            guard isWorkflowCurrent else { return }
            errorText = "Undo failed: \(error.localizedDescription)"
            showToast(.init(kind: .error, title: "Undo failed", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil))
        }
    }

    /// Selected titles, actions and exclusions. A library refresh does not change it, so a lost
    /// response retries the frozen payload. Editing the form starts a new action.
    private func selectionStamp() -> String {
        let lineIds = Set(selectedByItemId.keys).union(itemActions.keys).union(excludedItemIds)
        let choices = lineIds.map { lineId in
            let candidate = selectedByItemId[lineId]
            return ImportSelectionStamp.Choice(
                lineId: lineId,
                mediaType: candidate?.media_type ?? "",
                mediaId: candidate?.media_id ?? 0,
                action: itemActions[lineId]?.rawValue,
                excluded: excludedItemIds.contains(lineId)
            )
        }
        return ImportSelectionStamp.make(choices: choices)
    }

    private func applyConfirmationLines(
        response: ConciergeParseResponse,
        result: ConciergeApplyResponse
    ) -> (applied: [ImportApplyConfirmation.Line], rejected: [ImportApplyConfirmation.Line]) {
        func line(type: String, id: Int) -> ImportApplyConfirmation.Line? {
            for item in response.items {
                guard let candidate = selectedByItemId[item.id] else { continue }
                guard candidate.media_type.uppercased() == type.uppercased(), candidate.media_id == id else { continue }
                return ImportApplyConfirmation.Line(mediaType: type.uppercased(), mediaId: id, title: candidate.title_raw)
            }
            return nil
        }
        let applied = (result.applied ?? []).compactMap { line(type: $0.mediaType, id: $0.mediaId) }
        let rejected = ((result.conflicts ?? []).compactMap { conflict -> ImportApplyConfirmation.Line? in
            guard let type = conflict.mediaType, let id = conflict.mediaId else { return nil }
            return line(type: type, id: id)
        }) + ((result.errors ?? []).compactMap { error -> ImportApplyConfirmation.Line? in
            guard let type = error.mediaType, let id = error.mediaId else { return nil }
            return line(type: type, id: id)
        })
        return (applied, rejected)
    }

    // MARK: Helpers
    private var isWorkflowCurrent: Bool {
        workflow.isCurrent(ConciergeWorkflowScope.ticket, session: imports.accountSession)
    }

    private func perform(origin: ConciergeWorkflowScope.Ticket?, _ operation: @escaping @MainActor () async -> Void) {
        workflow.launch(origin: origin, session: imports.accountSession, operation: operation)
    }

    private func cancelAuxiliaryTasks() {
        lastApplySessionResetTask?.cancel()
        warmupTask?.cancel()
        prefetchTask?.cancel()
        prefetchTask2?.cancel()
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask2?.cancel()
        undoRefreshTask?.cancel()
        toastDismissTask?.cancel()
        disambiguationTask?.cancel()
    }

    private func handleError(_ error: Error) {
        if error is CancellationError { return }
        if let guardrail = error as? ConciergeGuardrailsError {
            // Persistent: rate limit / guardrail errors stay inline until next action
            errorText = guardrail.localizedDescription
        } else {
            // Transient: network / server errors as auto-dismissing toast only
            errorText = nil
            showToast(.init(kind: .error, title: "Error", subtitle: error.localizedDescription, actionTitle: nil, onAction: nil), autoDismissSeconds: 3.0)
        }
    }

    private func navigateToCollection() {
        #if os(iOS)
        if let url = URL(string: "kuro://collection") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func startNewChat() {
        workflow.invalidate()
        cancelAuxiliaryTasks()
        isWorking = false
        toast = nil
        lastApplySessionId = nil
        showAniListImportSheet = false; pendingAniListReview = nil; pendingAniListTicket = nil
        importWorkflowJob = nil
        withAnimation(KuroAnimation.fast) {
            messages = []
        }
        input = ""
        focusRequest = true
        errorText = nil
        selectedByItemId = [:]
        itemActions = [:]
        excludedItemIds = []
        autoReasonByItemId = [:]
        appliedImportMessageIds = []
        lastAppliedImportMessageId = nil
        applyingImportMessageId = nil
        appliedImportSummary = nil
        lastRecommendQuery = nil
        lastRecommendWasRagAssist = false
        lastRagSeedEntityId = nil
        ragFeedbackSentForQuery = []
        applyAttempt.abandon()
    }

    private func setLastApplySession(_ sessionId: String?) {
        lastApplySessionResetTask?.cancel()
        lastApplySessionId = sessionId
        guard let sessionId else { return }
        // Avoid stale sticky undo controls if the user moves on.
        lastApplySessionResetTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            guard isWorkflowCurrent else { return }
            if lastApplySessionId == sessionId {
                lastApplySessionId = nil
            }
        }
    }

    private func recordRagFeedbackIfNeeded(accepted: Bool, rejectedReason: String? = nil) {
        guard isWorkflowCurrent else { return }
        guard lastRecommendWasRagAssist, let query = lastRecommendQuery else { return }
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        guard !ragFeedbackSentForQuery.contains(key) else { return }
        ragFeedbackSentForQuery.insert(key)

        let locale = Locale.current.identifier
        let entityId = lastRagSeedEntityId

        perform(origin: ConciergeWorkflowScope.ticket) {
            await concierge.conciergeRetrieveFeedback(
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
        let origin = workflow.capture(session: imports.accountSession)
        withAnimation(KuroAnimation.fast) {
            toast = next
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0.8, autoDismissSeconds) * 1_000_000_000))
            if workflow.isCurrent(origin, session: imports.accountSession) {
                withAnimation(KuroAnimation.fast) {
                    toast = nil
                }
            }
        }
    }

    private func importFromLibrary() async {
        guard isWorkflowCurrent else { return }
        guard !isWorking else { return }
        errorText = nil

        let result = await imports.conciergeLibraryExportText(
            includeStatus: Set(ListStatus.allCases),
            includeMediaTypes: ["anime", "manga"],
            maxItems: 400
        )
        guard isWorkflowCurrent else { return }

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
}

// MARK: - Preview
#Preview {
    ConciergeView()
}
