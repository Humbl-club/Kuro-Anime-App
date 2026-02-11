import SwiftUI

// Shared Concierge UI components used by `ConciergeView`:
// message model, assistant orb/panel, and chat bubble subviews.

enum ConciergeMascotState: Equatable {
    case idle
    case listening
    case thinking
    case celebrating
    case concerned
}

struct KuroConciergeMascot: View {
    @Binding var expanded: Bool
    @Binding var offset: CGSize
    @Binding var dragStart: CGSize
    let baseBottomPadding: CGFloat
    let containerSize: CGSize
    let state: ConciergeMascotState
    let onTapMascot: () -> Void

    @Namespace private var mascotNS
    @State private var pulse: Bool = false
    @State private var ringPhase: Bool = false

    private let panelWidth: CGFloat = 316
    private let panelHeight: CGFloat = 148

    var body: some View {
        let clamped = clamp(offset: offset)

        VStack(spacing: 0) {
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        KuroConciergeMark(size: 34)
                            .matchedGeometryEffect(id: "kurochan", in: mascotNS)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("CONCIERGE")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(2.4)
                                .foregroundStyle(.primary.opacity(0.82))
                            Text(statusLine)
                                .font(.kuroCaption())
                                .foregroundStyle(.secondary.opacity(0.65))
                        }
                        Spacer(minLength: 0)

                        Button(action: { withAnimation(KuroAnimation.fast) { expanded = false } }) {
                            Image(systemName: "chevron.down")
                                .font(.kuroBody(weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.45))
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle().fill(Color.black.opacity(0.04))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Paste a list to import, or ask for a vibe.\nClean results by default — no adult content.")
                        .font(.kuroCaption())
                        .foregroundStyle(.secondary.opacity(0.75))

                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        onTapMascot()
                    }) {
                        HStack(spacing: 10) {
                            Text("START CHAT")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.8)
                                .foregroundStyle(.primary.opacity(0.82))
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                                .font(.kuroCaption(weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.45))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.04))
                                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.8))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(KuroDesignSpacing.md)
                .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                        .fill(Color.kuroSecondaryBackground.opacity(0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 10)
                )
                .clipShape(RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous))
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
                            .fill(Color.kuroSecondaryBackground.opacity(0.96))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.9)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                            .frame(width: 56, height: 56)

                        Circle()
                            .strokeBorder(Color.black.opacity(pulse ? 0.12 : 0.04), lineWidth: 1.1)
                            .frame(width: 56, height: 56)
                            .scaleEffect(pulse ? 1.08 : 0.96)
                            .opacity(pulse ? 1.0 : 0.0)
                            .allowsHitTesting(false)

                        ZStack {
                            // State ring (subtle, monochrome).
                            if state == .thinking {
                                Circle()
                                    .trim(from: 0.0, to: 0.72)
                                    .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                                    .rotationEffect(.degrees(ringPhase ? 360 : 0))
                                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: ringPhase)
                                    .frame(width: 42, height: 42)
                                    .allowsHitTesting(false)
                            }

                            KuroConciergeMark(size: 24)
                                .matchedGeometryEffect(id: "kurochan", in: mascotNS)

                            if state == .concerned {
                                Image(systemName: "exclamationmark")
                                    .font(.kuroMicro(weight: .bold))
                                    .foregroundStyle(.primary.opacity(0.55))
                                    .offset(x: 14, y: -14)
                                    .allowsHitTesting(false)
                            }
                        }
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

            ringPhase = true
        }
    }

    private var statusLine: String {
        switch state {
        case .idle: return "Imports + recommendations"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .celebrating: return "Saved"
        case .concerned: return "Needs clarification"
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
    /// If this message was produced from a specific user input (e.g. an import parse),
    /// keep the originating text so actions like "Re-parse" target the correct input.
    let sourceUserText: String?
    let items: [SupabaseService.ConciergeParseItem]?
    let recommendations: [SupabaseService.ConciergeRecommendResponse.Item]?
    let recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]?
    let recommendationCategories: [String]?
    let parseResponse: SupabaseService.ConciergeParseResponse?

    init(
        role: Role,
        text: String,
        showClarifyActions: Bool = false,
        sourceUserText: String? = nil,
        items: [SupabaseService.ConciergeParseItem]? = nil,
        recommendations: [SupabaseService.ConciergeRecommendResponse.Item]? = nil,
        recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]? = nil,
        recommendationCategories: [String]? = nil,
        parseResponse: SupabaseService.ConciergeParseResponse? = nil
    ) {
        self.role = role
        self.text = text
        self.showClarifyActions = showClarifyActions
        self.sourceUserText = sourceUserText
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

// MARK: - Clarify Card (Two-Path Intent Picker)

struct ConciergeClarifyCard: View {
    let onPaste: () -> Void
    let onExampleImport: () -> Void
    let onExampleVibe: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Import path
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.kuroCaption(weight: .semibold))
                        .foregroundColor(.black.opacity(0.45))
                    Text("IMPORT")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.8)
                        .foregroundColor(.black.opacity(0.55))
                }

                KuroGlassPill(
                    title: "Paste from clipboard",
                    subtitle: "Titles, progress, ratings",
                    systemImage: "doc.on.clipboard",
                    action: onPaste
                )

                KuroGlassPill(
                    title: "Try an example",
                    subtitle: "Attack on Titan (completed), JJK ep 12...",
                    systemImage: "text.append",
                    action: onExampleImport
                )
            }
            .offset(y: appeared ? 0 : 6)
            .opacity(appeared ? 1 : 0)

            // Divider
            HStack(spacing: KuroDesignSpacing.sm) {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
                Text("OR")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.4)
                    .foregroundColor(.black.opacity(0.30))
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
            }
            .padding(.vertical, 14)
            .offset(y: appeared ? 0 : 8)
            .opacity(appeared ? 1 : 0)

            // Vibe path
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.kuroCaption(weight: .semibold))
                        .foregroundColor(.black.opacity(0.45))
                    Text("RECOMMEND")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.8)
                        .foregroundColor(.black.opacity(0.55))
                }

                KuroGlassPill(
                    title: "Describe a mood",
                    subtitle: "Funny, cozy, dark, premium...",
                    systemImage: "text.bubble",
                    action: onExampleVibe
                )
            }
            .offset(y: appeared ? 0 : 10)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(KuroAnimation.editorial) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose: import titles or get recommendations")
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
    var onReparse: (() -> Void)? = nil
    var autoReasonByItemId: [String: String] = [:]
    var itemActions: [String: ImportItemAction] = [:]
    @Binding var excludedItemIds: Set<String>
    @Environment(\.colorScheme) private var colorScheme

    private func glassBubble<Content: View>(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.kuroSecondaryBackground.opacity(colorScheme == .dark ? 0.92 : 0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.06), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.06), radius: 14, x: 0, y: 8)
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
                                .foregroundStyle(.primary.opacity(0.82))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .frame(maxWidth: 360, alignment: .leading)
                    }

                    if message.showClarifyActions {
                        ConciergeClarifyCard(
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
                            onReparse: onReparse,
                            autoReasonByItemId: autoReasonByItemId,
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
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(sets, id: \.id) { set in
                                let items = (set.items ?? [])
                                if !items.isEmpty {
                                    RecommendationRail(
                                        title: set.title.isEmpty ? "Recommendations" : set.title,
                                        items: items,
                                        onOpen: { onOpenRecommendation($0) },
                                        onSave: { onQuickSave($0) },
                                        onHide: nil
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: 520, alignment: .leading)
                    } else if let recs = message.recommendations, !recs.isEmpty {
                        RecommendationRail(
                            title: "Recommendations",
                            items: recs,
                            onOpen: { onOpenRecommendation($0) },
                            onSave: { onQuickSave($0) },
                            onHide: nil
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
                            .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.0), lineWidth: 0.6)
                            )
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
    var onReparse: (() -> Void)? = nil
    var autoReasonByItemId: [String: String] = [:]
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

    private var selectedByItemId: [String: SupabaseService.ConciergeCandidate] {
        Dictionary(
            uniqueKeysWithValues: items.compactMap { item in
                guard let c = selected(item) else { return nil }
                return (item.id, c)
            }
        )
    }

    private var autoSelectedIds: Set<String> {
        Set(items.compactMap { item in
            guard let c = selected(item) else { return nil }
            if excludedItemIds.contains(item.id) { return nil }
            if actionFor(item) == .skip { return nil }
            return (c.score >= 0.85 || autoReasonByItemId[item.id] != nil) ? item.id : nil
        })
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
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("IMPORT PREVIEW")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.8)
                        .foregroundStyle(.secondary.opacity(0.85))
                    Spacer(minLength: 0)
                    Text("\(items.count)")
                        .font(.kuroMicro(weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.75))
                        .monospacedDigit()
                }
                .padding(.bottom, 14)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.bottom, 12)

                ImportCardContainer(
                    items: items,
                    selectedByItemId: selectedByItemId,
                    autoSelectedIds: autoSelectedIds,
                    autoReasonByItemId: autoReasonByItemId,
                    itemActions: itemActions,
                    excludedItemIds: excludedItemIds,
                    onSelect: { item, candidate in onSelect(item, candidate) },
                    onToggleExclude: { toggleExclude($0) }
                )

                HStack(spacing: 10) {
                    // Re-parse: show when many items have low confidence
                    if showReparse, let reparse = onReparse {
                        Button(action: {
                            KuroAccessibility.impactHaptic(.light)
                            reparse()
                        }) {
                            Text("RE-PARSE")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.6)
                                .foregroundColor(.black.opacity(0.55))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.04))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Re-parse import text")
                    }

                    Button(action: {
                        KuroAccessibility.impactHaptic(.medium)
                        onConfirm()
                    }) {
                        HStack(spacing: 8) {
                            Text("CONFIRM")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(2.0)

                            Text("\(confirmableCount)")
                                .font(.kuroMicro(weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundColor(confirmableCount > 0 ? .white : .white.opacity(0.40))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule(style: .continuous)
                                .fill(confirmableCount > 0 ? Color.black.opacity(0.88) : Color.black.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(confirmableCount == 0)
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    /// Show re-parse when 2+ actionable items have low confidence (< 0.70).
    private var showReparse: Bool {
        let lowConfidenceCount = items.filter { item in
            let action = actionFor(item)
            guard action != .skip else { return false }
            guard let c = selected(item) else { return true }
            return c.score < 0.70
        }.count
        return lowConfidenceCount >= 2
    }

    private func toggleExclude(_ id: String) {
        KuroAccessibility.impactHaptic(.light)
        if excludedItemIds.contains(id) {
            excludedItemIds.remove(id)
        } else {
            excludedItemIds.insert(id)
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
                            .font(.kuroBody())
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
                            .font(.kuroCaption(weight: .semibold))
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
                            .font(.kuroCaption(weight: .semibold))
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
                        Color.primary.opacity(0.05)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.secondary.opacity(0.75))
                            )
                    @unknown default:
                        Color.primary.opacity(0.05)
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
