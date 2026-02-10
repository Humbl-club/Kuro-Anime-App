import SwiftUI

// Concierge UI components used by `ConciergeView` for the chat surface
// and the floating assistant orb/panel.

struct KuroConciergeAssistant: View {
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
                KuroGlassCard(cornerRadius: KuroRadius.lg) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            KuroConciergeMark(size: 34)
                                .matchedGeometryEffect(id: "kurochan", in: mascotNS)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("CONCIERGE")
                                    .font(.kuroCaption(weight: .medium))
                                    .tracking(2.4)
                                    .foregroundColor(.black.opacity(0.78))
                                Text("Imports + recommendations")
                                    .font(.kuroCaption())
                                    .foregroundColor(.black.opacity(0.55))
                            }
                            Spacer(minLength: 0)

                            Button(action: { withAnimation(KuroAnimation.fast) { expanded = false } }) {
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
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.62))

                        Button(action: {
                            KuroAccessibility.impactHaptic(.light)
                            onTapMascot()
                        }) {
                            HStack(spacing: 10) {
                                Text("START CHAT")
                                    .font(.kuroCaption(weight: .medium))
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
                    .padding(KuroDesignSpacing.md)
                    .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
                }
                .overlay(alignment: .topTrailing) {
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
                            withAnimation(KuroAnimation.editorial) {
                                offset = next
                            }
                            dragStart = next
                        }
                )
            } else {
                Button(action: {
                    withAnimation(KuroAnimation.editorial) { expanded = true }
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
                            withAnimation(KuroAnimation.editorial) {
                                offset = next
                            }
                            dragStart = next
                        }
                )
            }
        }
        .padding(.leading, KuroDesignSpacing.md)
        .padding(.bottom, baseBottomPadding)
        .offset(clamped)
        .onAppear {
            if dragStart == .zero, offset == .zero {
                dragStart = .zero
                offset = .zero
            }

            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func clamp(offset: CGSize) -> CGSize {
        let maxRight = max(0, containerSize.width - (panelWidth + 32))
        let minX: CGFloat = 0
        let maxX: CGFloat = maxRight

        let minY: CGFloat = -max(120, containerSize.height * 0.70)
        let maxY: CGFloat = 0

        return CGSize(
            width: min(maxX, max(minX, offset.width)),
            height: min(maxY, max(minY, offset.height))
        )
    }
}

// MARK: - Message Model

struct ConciergeMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    let showClarifyActions: Bool
    let items: [SupabaseService.ConciergeParseItem]?
    let recommendations: [SupabaseService.ConciergeRecommendResponse.Item]?
    let recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]?
    let recommendationCategories: [String]?
    let parseResponse: SupabaseService.ConciergeParseResponse?

    init(
        role: Role,
        text: String,
        showClarifyActions: Bool = false,
        items: [SupabaseService.ConciergeParseItem]? = nil,
        recommendations: [SupabaseService.ConciergeRecommendResponse.Item]? = nil,
        recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]? = nil,
        recommendationCategories: [String]? = nil,
        parseResponse: SupabaseService.ConciergeParseResponse? = nil
    ) {
        self.role = role
        self.text = text
        self.showClarifyActions = showClarifyActions
        self.items = items
        self.recommendations = recommendations
        self.recommendationSets = recommendationSets
        self.recommendationCategories = recommendationCategories
        self.parseResponse = parseResponse
    }
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isEmpty
        }
    }
}

// MARK: - Action Bar

struct ConciergeActionBar: View {
    let selectedCount: Int
    let hasAnySelection: Bool
    let canUndo: Bool
    let onApply: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onUndo) {
                Text("UNDO")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(canUndo ? .black : .black.opacity(0.25))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                            .fill(Color.black.opacity(canUndo ? 0.04 : 0.02))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)

            Spacer()

            Button(action: onApply) {
                HStack(spacing: KuroDesignSpacing.sm) {
                    Text("APPLY")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                    Text("\(selectedCount)")
                        .font(.kuroCaption(weight: .medium))
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
                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                        .fill(hasAnySelection ? Color.black : Color.black.opacity(0.2))
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasAnySelection)
        }
    }
}

// MARK: - Typing Indicator (500ms cycle)

struct ConciergeTypingIndicator: View {
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
                .font(.kuroCaption())
                .foregroundColor(.black.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                // Avoid full-screen materials in a frequently-updating view.
                .fill(Color.kuroSecondaryBackground.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - Intro Card

struct ConciergeIntroCard: View {
    var body: some View {
        KuroGlassCard(cornerRadius: KuroRadius.lg) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    KuroConciergeMark(size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONCIERGE")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(2.4)
                            .foregroundColor(.black.opacity(0.80))
                        Text("Imports + recommendations")
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.55))
                    }

                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)

                Text("Paste titles to import, or describe the mood.\nDefaults are clean — no adult content.")
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.black.opacity(0.62))
                    .lineSpacing(3)
            }
            .padding(KuroDesignSpacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Concierge. Paste titles to import, or ask for a vibe.")
    }
}

// MARK: - Starter Actions

struct ConciergeStarterActions: View {
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
        .padding(.horizontal, KuroDesignSpacing.padding)
        .onAppear {
            withAnimation(KuroAnimation.fast) {
                appeared = true
            }
        }
    }
}

// MARK: - Chat Bubble

struct ConciergeBubble: View {
    let message: ConciergeMessage
    let selected: (SupabaseService.ConciergeParseItem) -> SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeParseItem, SupabaseService.ConciergeCandidate) -> Void
    let onOpenRecommendation: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onQuickSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onClarifyPaste: () -> Void
    let onClarifyExampleImport: () -> Void
    let onClarifyExampleVibe: () -> Void
    var onConfirmItems: ((SupabaseService.ConciergeParseResponse) -> Void)? = nil
    var itemActions: [String: ImportItemAction] = [:]
    @Binding var excludedItemIds: Set<String>
    @State private var hiddenRecommendationIds: Set<String> = []

    private func glassBubble<Content: View>(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.kuroSecondaryBackground.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 10) {
                    if !message.text.isEmpty {
                        glassBubble(cornerRadius: KuroRadius.md) {
                            Text(message.text)
                                .font(.kuroBody())
                                .foregroundColor(.black.opacity(0.82))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .frame(maxWidth: 360, alignment: .leading)
                    }

                    if message.showClarifyActions {
                        ConciergeStarterActions(
                            onPaste: onClarifyPaste,
                            onExampleImport: onClarifyExampleImport,
                            onExampleVibe: onClarifyExampleVibe
                        )
                        .frame(maxWidth: 420, alignment: .leading)
                    }

                    // Inline confirm bubble for import items
                    if let items = message.items, !items.isEmpty, let parseResponse = message.parseResponse {
                        ConciergeConfirmBubble(
                            items: items,
                            selected: selected,
                            onSelect: onSelect,
                            onConfirm: { onConfirmItems?(parseResponse) },
                            itemActions: itemActions,
                            excludedItemIds: $excludedItemIds
                        )
                        .frame(maxWidth: 420, alignment: .leading)
                    } else if let items = message.items, !items.isEmpty {
                        glassBubble(cornerRadius: KuroRadius.md) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("MATCHES")
                                        .font(.kuroCaption(weight: .medium))
                                        .tracking(1.6)
                                        .foregroundColor(.black.opacity(0.55))
                                    Spacer()
                                    Text("\(items.count)")
                                        .font(.kuroCaption(weight: .medium))
                                        .foregroundColor(.black.opacity(0.45))
                                }

                                VStack(spacing: 10) {
                                    ForEach(items) { item in
                                        ConciergeMatchRow(
                                            item: item,
                                            chosen: selected(item),
                                            onSelect: { cand in onSelect(item, cand) }
                                        )
                                    }
                                }
                            }
                            .padding(14)
                        }
                        .frame(maxWidth: 420, alignment: .leading)
                    }

                    if let sets = message.recommendationSets, !sets.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(sets, id: \.id) { set in
                                let items = (set.items ?? []).filter { !hiddenRecommendationIds.contains("\($0.mediaId)_\($0.mediaType)") }
                                if !items.isEmpty {
                                    ConciergeRail(
                                        title: set.title ?? "Recommendations",
                                        items: items,
                                        hiddenRecommendationIds: $hiddenRecommendationIds,
                                        onOpen: onOpenRecommendation,
                                        onQuickSave: onQuickSave
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: 520, alignment: .leading)
                    } else if let recs = message.recommendations, !recs.isEmpty {
                        ConciergeRail(
                            title: "Recommendations",
                            items: recs.filter { !hiddenRecommendationIds.contains("\($0.mediaId)_\($0.mediaType)") },
                            hiddenRecommendationIds: $hiddenRecommendationIds,
                            onOpen: onOpenRecommendation,
                            onQuickSave: onQuickSave
                        )
                        .frame(maxWidth: 520, alignment: .leading)
                    }
                }
                Spacer(minLength: 40)
            } else {
                // User bubble — direct black fill, no glass wrapper
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.kuroBody())
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                            .fill(Color.black)
                    )
                    .frame(maxWidth: 360, alignment: .trailing)
            }
        }
    }
}

// MARK: - Inline Confirm Bubble (with Import Reconciliation)

struct ConciergeConfirmBubble: View {
    let items: [SupabaseService.ConciergeParseItem]
    let selected: (SupabaseService.ConciergeParseItem) -> SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeParseItem, SupabaseService.ConciergeCandidate) -> Void
    let onConfirm: () -> Void
    var itemActions: [String: ImportItemAction] = [:]
    @Binding var excludedItemIds: Set<String>

    private func actionFor(_ item: SupabaseService.ConciergeParseItem) -> ImportItemAction {
        itemActions[item.id] ?? .add
    }

    private var addItems: [SupabaseService.ConciergeParseItem] {
        items.filter { actionFor($0) == .add }
    }
    private var updateItems: [SupabaseService.ConciergeParseItem] {
        items.filter { actionFor($0) == .update }
    }
    private var skipItems: [SupabaseService.ConciergeParseItem] {
        items.filter { actionFor($0) == .skip }
    }

    private var confirmableCount: Int {
        items.reduce(0) { acc, item in
            let action = actionFor(item)
            if action == .skip { return acc }
            if excludedItemIds.contains(item.id) { return acc }
            if selected(item) == nil { return acc }
            return acc + 1
        }
    }

    private func glassBubble<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                    .fill(Color.kuroSecondaryBackground.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
            )
            .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
    }

    var body: some View {
        glassBubble {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                // Header
                HStack {
                    Text("IMPORT PREVIEW")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.black.opacity(0.55))
                    Spacer()
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(.kuroCaption())
                        .foregroundColor(.black.opacity(0.45))
                }

                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)

                // WILL ADD section
                if !addItems.isEmpty {
                    reconcileSection(title: "WILL ADD", count: addItems.count) {
                        ForEach(addItems) { item in
                            ConciergeReconcileRow(
                                item: item,
                                action: .add,
                                chosen: selected(item),
                                onSelect: { cand in onSelect(item, cand) },
                                isExcluded: excludedItemIds.contains(item.id),
                                onToggleExclude: { toggleExclude(item.id) }
                            )
                        }
                    }
                }

                // WILL UPDATE section
                if !updateItems.isEmpty {
                    reconcileSection(title: "WILL UPDATE", count: updateItems.count) {
                        ForEach(updateItems) { item in
                            ConciergeReconcileRow(
                                item: item,
                                action: .update,
                                chosen: selected(item),
                                onSelect: { cand in onSelect(item, cand) },
                                isExcluded: excludedItemIds.contains(item.id),
                                onToggleExclude: { toggleExclude(item.id) }
                            )
                        }
                    }
                }

                // WILL SKIP section
                if !skipItems.isEmpty {
                    reconcileSection(title: "WILL SKIP", count: skipItems.count) {
                        ForEach(skipItems) { item in
                            ConciergeReconcileRow(
                                item: item,
                                action: .skip,
                                chosen: selected(item),
                                onSelect: { _ in },
                                isExcluded: false,
                                onToggleExclude: nil
                            )
                        }
                    }
                    .opacity(0.4)
                }

                // Confirm button
                Button(action: {
                    KuroAccessibility.impactHaptic(.medium)
                    onConfirm()
                }) {
                    Text("CONFIRM \(confirmableCount) ITEM\(confirmableCount == 1 ? "" : "S")")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                .fill(confirmableCount > 0 ? Color.black : Color.black.opacity(0.2))
                        )
                }
                .buttonStyle(.plain)
                .disabled(confirmableCount == 0)
            }
            .padding(14)
        }
    }

    private func toggleExclude(_ id: String) {
        KuroAccessibility.impactHaptic(.light)
        if excludedItemIds.contains(id) {
            excludedItemIds.remove(id)
        } else {
            excludedItemIds.insert(id)
        }
    }

    @ViewBuilder
    private func reconcileSection<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            HStack(spacing: KuroDesignSpacing.sm) {
                Text(title)
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.black.opacity(0.50))
                Text("\(count)")
                    .font(.kuroCaption(weight: .medium))
                    .foregroundColor(.black.opacity(0.40))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.06))
                    )
                Spacer()
            }
            content()
        }
    }
}

// MARK: - Reconcile Row (Add / Update / Skip)

private struct ConciergeReconcileRow: View {
    let item: SupabaseService.ConciergeParseItem
    let action: ImportItemAction
    let chosen: SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeCandidate) -> Void
    let isExcluded: Bool
    let onToggleExclude: (() -> Void)?

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            HStack(alignment: .top, spacing: 10) {
                // Per-item toggle (add/update only)
                if action != .skip, let toggle = onToggleExclude {
                    Button(action: toggle) {
                        Image(systemName: isExcluded ? "square" : "checkmark.square.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(isExcluded ? .black.opacity(0.25) : .black.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.normalized.isEmpty ? item.raw : item.normalized)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.black.opacity(isExcluded ? 0.40 : 0.90))
                        .lineLimit(2)

                    if let c = chosen {
                        Text(c.title_raw)
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.55))
                            .lineLimit(2)
                    }

                    // Diff display for update items
                    if action == .update, let existing = item.existing_entry {
                        diffView(existing: existing, parsed: item.parsed)
                    }

                    // Skip caption
                    if action == .skip {
                        Text("Already up to date")
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.45))
                    }
                }

                Spacer(minLength: 0)

                if item.candidates.count > 1 && action != .skip {
                    Button(action: { withAnimation(KuroAnimation.fast) { expanded.toggle() } }) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black.opacity(0.4))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.black.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(isExcluded ? 0.5 : 1.0)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.candidates.prefix(4), id: \.media_id) { cand in
                        Button(action: { onSelect(cand) }) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(chosen?.media_id == cand.media_id ? Color.black : Color.clear)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
                                    )
                                Text(cand.title_raw)
                                    .font(.kuroCaption())
                                    .foregroundColor(.black.opacity(0.82))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let year = cand.year {
                                    Text(String(year))
                                        .font(.kuroCaption())
                                        .foregroundColor(.black.opacity(0.45))
                                }
                                Text("\(Int(cand.score * 100))%")
                                    .font(.kuroCaption(weight: .medium))
                                    .foregroundColor(.black.opacity(0.45))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                    .fill(Color.black.opacity(chosen?.media_id == cand.media_id ? 0.06 : 0.03))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func diffView(existing: SupabaseService.ConciergeExistingEntry, parsed: SupabaseService.ConciergeParseItemParsed) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Status diff
            if let parsedStatus = parsed.status,
               parsedStatus.uppercased() != existing.status.uppercased() {
                diffLine(from: existing.status, to: parsedStatus.uppercased())
            }

            // Episode progress diff
            if let ep = parsed.progressEpisodes,
               ep != (existing.progress_episodes ?? 0) {
                diffLine(from: "Ep \(existing.progress_episodes ?? 0)", to: "Ep \(ep)")
            }

            // Chapter progress diff
            if let ch = parsed.progressChapters,
               ch != (existing.progress_chapters ?? 0) {
                diffLine(from: "Ch \(existing.progress_chapters ?? 0)", to: "Ch \(ch)")
            }

            // Volume progress diff
            if let vol = parsed.progressVolumes,
               vol != (existing.progress_volumes ?? 0) {
                diffLine(from: "Vol \(existing.progress_volumes ?? 0)", to: "Vol \(vol)")
            }
        }
    }

    @ViewBuilder
    private func diffLine(from: String, to: String) -> some View {
        HStack(spacing: 4) {
            Text(from)
                .font(.kuroCaption())
                .strikethrough()
                .foregroundColor(.black.opacity(0.40))
            Text("\u{2192}")
                .font(.kuroCaption())
                .foregroundColor(.black.opacity(0.40))
            Text(to)
                .font(.kuroCaption(weight: .medium))
                .foregroundColor(.black.opacity(0.82))
        }
    }
}

// MARK: - Match Row

private struct ConciergeMatchRow: View {
    let item: SupabaseService.ConciergeParseItem
    let chosen: SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeCandidate) -> Void

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.normalized.isEmpty ? item.raw : item.normalized)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.black.opacity(0.90))
                        .lineLimit(2)

                    if let c = chosen {
                        Text(c.title_raw)
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.55))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if item.candidates.count > 1 {
                    Button(action: { withAnimation(KuroAnimation.fast) { expanded.toggle() } }) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black.opacity(0.4))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.black.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.candidates.prefix(4), id: \.media_id) { cand in
                        Button(action: { onSelect(cand) }) {
                            HStack(spacing: 10) {
                                // Radio dot
                                Circle()
                                    .fill(chosen?.media_id == cand.media_id ? Color.black : Color.clear)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
                                    )

                                Text(cand.title_raw)
                                    .font(.kuroCaption())
                                    .foregroundColor(.black.opacity(0.82))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let year = cand.year {
                                    Text(String(year))
                                        .font(.kuroCaption())
                                        .foregroundColor(.black.opacity(0.45))
                                }
                                Text("\(Int(cand.score * 100))%")
                                    .font(.kuroCaption(weight: .medium))
                                    .foregroundColor(.black.opacity(0.45))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                    .fill(Color.black.opacity(chosen?.media_id == cand.media_id ? 0.06 : 0.03))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Recommendation Rail (Editorial)

private struct ConciergeRail: View {
    let title: String
    let items: [SupabaseService.ConciergeRecommendResponse.Item]
    @Binding var hiddenRecommendationIds: Set<String>
    let onOpen: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onQuickSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Rail header — editorial style
            HStack(spacing: 10) {
                Text(title.uppercased())
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.black.opacity(0.55))
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 0.5)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        ConciergeRecCard(
                            item: item,
                            onOpen: { onOpen(item) },
                            onQuickSave: { onQuickSave(item) },
                            onHide: { hiddenRecommendationIds.insert("\(item.mediaId)_\(item.mediaType)") }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Recommendation Card (Editorial Style)

private struct ConciergeRecCard: View {
    let item: SupabaseService.ConciergeRecommendResponse.Item
    let onOpen: () -> Void
    let onQuickSave: () -> Void
    let onHide: () -> Void

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            // Poster with score badge overlay
            Button(action: onOpen) {
                KuroCachedAsyncImage(url: URL(string: item.coverImageMedium ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Color.black.opacity(0.08)
                            .overlay(
                                Text("KURO")
                                    .font(.kuroCaption(weight: .medium))
                                    .tracking(2)
                                    .foregroundColor(.black.opacity(0.15))
                            )
                    case .empty:
                        Color.black.opacity(0.04)
                    @unknown default:
                        Color.black.opacity(0.04)
                    }
                }
                .frame(width: 140, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let score = item.averageScore {
                        KuroScoreBadge(score: Double(score) / 10.0)
                            .padding(6)
                    }
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(KuroAnimation.editorial, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .contextMenu {
                Button(action: onQuickSave) {
                    Label("Save to Planning", systemImage: "bookmark")
                }
                Button(action: onHide) {
                    Label("Hide", systemImage: "eye.slash")
                }
            }

            // Title + metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.kuroBody(weight: .regular))
                    .foregroundColor(.black.opacity(0.92))
                    .lineLimit(2)
                    .frame(height: 38, alignment: .top)
                Text([item.year.map(String.init), item.format].compactMap { $0 }.joined(separator: " · "))
                    .font(.kuroCaption())
                    .foregroundColor(.black.opacity(0.50))
                    .lineLimit(1)
            }
        }
        .frame(width: 140, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint("Recommendation. Long press for options.")
    }
}
