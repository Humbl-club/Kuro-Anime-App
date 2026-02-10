import SwiftUI

// MARK: - CONCIERGE UI COMPONENTS
// "The Editorial Concierge" — a luxury curator experience.
// Assistant messages are open editorial compositions, not chat bubbles.
// The concierge speaks through typography, whitespace, and restraint.

// MARK: - Floating Concierge Assistant (Orb + Panel)

struct KuroConciergeAssistant: View {
    @Binding var expanded: Bool
    @Binding var offset: CGSize
    @Binding var dragStart: CGSize
    let baseBottomPadding: CGFloat
    let containerSize: CGSize
    let onTapMascot: () -> Void

    @Namespace private var mascotNS
    @State private var pulse: Bool = false
    @State private var innerPulse: Bool = false

    private let panelWidth: CGFloat = 280
    private let panelHeight: CGFloat = 220

    var body: some View {
        let clamped = clamp(offset: offset)

        VStack(spacing: 0) {
            if expanded {
                expandedPanel
                    .gesture(panelDrag)
            } else {
                collapsedOrb
                    .simultaneousGesture(panelDrag)
            }
        }
        .padding(.leading, KuroDesignSpacing.md)
        .padding(.bottom, baseBottomPadding)
        .offset(clamped)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(0.5)) {
                innerPulse = true
            }
        }
    }

    private var panelDrag: some Gesture {
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
    }

    // MARK: Expanded Panel — editorial card with cinematic reveal
    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Close button — top right, minimal
            HStack {
                Spacer()
                Button(action: { withAnimation(KuroAnimation.editorial) { expanded = false } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.black.opacity(0.35))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.black.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)

            // Butler mark
            KuroConciergeMark(size: 32)
                .matchedGeometryEffect(id: "kurochan", in: mascotNS)
                .padding(.bottom, 16)

            // Title — dramatic serif, the signature moment
            Text("Concierge")
                .font(.kuroHeadline(weight: .thin))
                .foregroundColor(.black.opacity(0.85))
                .tracking(0.6)
                .padding(.bottom, 6)

            // Thin editorial rule
            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(width: 36, height: 0.5)
                .padding(.bottom, 12)

            Text("Your private curator.\nImport or describe a mood.")
                .font(.kuroCaption())
                .foregroundColor(.black.opacity(0.42))
                .lineSpacing(3)
                .padding(.bottom, 16)

            // CTA — ultra-minimal, just text and an arrow
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                onTapMascot()
            }) {
                HStack(spacing: 8) {
                    Text("BEGIN")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(2.8)
                        .foregroundColor(.black.opacity(0.75))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.black.opacity(0.30))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 0.5)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: panelWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.70), Color.white.opacity(0.15), Color.black.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                )
                .shadow(color: Color.black.opacity(0.14), radius: 24, x: 0, y: 12)
                .shadow(color: Color.white.opacity(0.45), radius: 1, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
    }

    // MARK: Collapsed Orb — living, breathing presence
    private var collapsedOrb: some View {
        Button(action: {
            withAnimation(KuroAnimation.editorial) { expanded = true }
        }) {
            ZStack {
                // Outer aura — slow, atmospheric pulse
                Circle()
                    .strokeBorder(Color.black.opacity(pulse ? 0.08 : 0.02), lineWidth: 0.6)
                    .frame(width: 58, height: 58)
                    .scaleEffect(pulse ? 1.15 : 1.0)

                // Middle ring — offset rhythm
                Circle()
                    .strokeBorder(Color.black.opacity(innerPulse ? 0.06 : 0.01), lineWidth: 0.4)
                    .frame(width: 52, height: 52)
                    .scaleEffect(innerPulse ? 1.08 : 1.0)

                // Glass core
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.60), Color.white.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.6
                            )
                    )
                    .frame(width: 46, height: 46)
                    .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 8)

                KuroConciergeMark(size: 21)
                    .matchedGeometryEffect(id: "kurochan", in: mascotNS)
            }
        }
        .buttonStyle(.plain)
    }

    private func clamp(offset: CGSize) -> CGSize {
        let maxRight = max(0, containerSize.width - (panelWidth + 32))
        return CGSize(
            width: min(maxRight, max(0, offset.width)),
            height: min(0, max(-max(120, containerSize.height * 0.70), offset.height))
        )
    }
}

// MARK: - Message Model

struct ConciergeMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    let items: [SupabaseService.ConciergeParseItem]?
    let recommendations: [SupabaseService.ConciergeRecommendResponse.Item]?
    let recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]?
    let recommendationCategories: [String]?
    let parseResponse: SupabaseService.ConciergeParseResponse?

    init(
        role: Role,
        text: String,
        items: [SupabaseService.ConciergeParseItem]? = nil,
        recommendations: [SupabaseService.ConciergeRecommendResponse.Item]? = nil,
        recommendationSets: [SupabaseService.ConciergeRecommendResponse.Set]? = nil,
        recommendationCategories: [String]? = nil,
        parseResponse: SupabaseService.ConciergeParseResponse? = nil
    ) {
        self.role = role
        self.text = text
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
        HStack(spacing: 0) {
            // Undo — ghost text
            if canUndo {
                Button(action: onUndo) {
                    Text("UNDO")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(2.0)
                        .foregroundColor(.black.opacity(0.40))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Apply — the confident action
            Button(action: onApply) {
                HStack(spacing: 8) {
                    Text("APPLY")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(2.0)

                    // Count pill
                    Text("\(selectedCount)")
                        .font(.kuroMicro(weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.15))
                        )
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(hasAnySelection ? Color.black : Color.black.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasAnySelection)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Typing Indicator (Breathing Thread)
// A single thin thread that breathes — contemplative, not anxious.
// Paired with the butler glyph, this signals curation in progress.

struct ConciergeTypingIndicator: View {
    @State private var phase1: Bool = false
    @State private var phase2: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Butler glyph — the curator is at work
            KuroConciergeGlyph(size: 13)
                .opacity(phase1 ? 0.42 : 0.18)
                .padding(.trailing, 12)

            // Breathing thread — two segments at different rhythms
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(Color.black.opacity(phase1 ? 0.22 : 0.06))
                .frame(width: phase1 ? 28 : 12, height: 0.8)

            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(Color.black.opacity(phase2 ? 0.16 : 0.04))
                .frame(width: phase2 ? 16 : 6, height: 0.8)
                .padding(.leading, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                phase1 = true
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.3)) {
                phase2 = true
            }
        }
    }
}

// MARK: - Intro Card (Full Editorial Spread)
// The first thing users see. This is a magazine opening — dramatic, spacious, confident.

struct ConciergeIntroCard: View {
    @State private var phase: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Generous top breathing room
            Spacer()
                .frame(height: 40)

            // Butler mark — the brand signature
            KuroConciergeMark(size: 36)
                .opacity(phase >= 1 ? 1 : 0)
                .offset(y: phase >= 1 ? 0 : 8)
                .padding(.bottom, 28)

            // "Concierge" — large serif, the magazine title
            Text("Concierge")
                .font(.kuroDisplay(weight: .thin))
                .foregroundColor(.black.opacity(0.82))
                .tracking(1.2)
                .opacity(phase >= 2 ? 1 : 0)
                .offset(y: phase >= 2 ? 0 : 10)
                .padding(.bottom, 16)

            // Editorial rule — animates in from left
            Rectangle()
                .fill(Color.black.opacity(0.14))
                .frame(width: phase >= 3 ? 56 : 0, height: 0.8)
                .padding(.bottom, 20)

            // Tagline — delicate, spaced, editorial voice
            VStack(alignment: .leading, spacing: 6) {
                Text("Import your collection.")
                    .font(.kuroBody())
                    .foregroundColor(.black.opacity(0.48))
                Text("Or describe a mood.")
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.black.opacity(0.38))
            }
            .opacity(phase >= 4 ? 1 : 0)
            .offset(y: phase >= 4 ? 0 : 6)

            Spacer()
                .frame(height: 20)
        }
        .padding(.horizontal, KuroDesignSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Concierge. Import titles or describe a mood for recommendations.")
        .task {
            for step in 1...4 {
                try? await Task.sleep(nanoseconds: UInt64(step == 1 ? 200_000_000 : 250_000_000))
                withAnimation(.easeOut(duration: 0.65)) {
                    phase = step
                }
            }
        }
    }
}

// MARK: - Starter Actions
// Monoline editorial prompts — not buttons, more like magazine sidebar cues.

struct ConciergeStarterActions: View {
    let onPaste: () -> Void
    let onExampleImport: () -> Void
    let onExampleVibe: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            starterRow(
                label: "PASTE FROM CLIPBOARD",
                icon: "doc.on.clipboard",
                index: 0,
                action: onPaste
            )

            starterDivider()

            starterRow(
                label: "TRY AN EXAMPLE IMPORT",
                icon: "text.append",
                index: 1,
                action: onExampleImport
            )

            starterDivider()

            starterRow(
                label: "DESCRIBE A MOOD",
                icon: "sparkles",
                index: 2,
                action: onExampleVibe
            )
        }
        .padding(.horizontal, KuroDesignSpacing.padding)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.4)) {
                appeared = true
            }
        }
    }

    private func starterRow(label: String, icon: String, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.black.opacity(0.30))
                    .frame(width: 20)

                Text(label)
                    .font(.kuroCaption(weight: .light))
                    .tracking(1.8)
                    .foregroundColor(.black.opacity(0.55))

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundColor(.black.opacity(0.18))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -8)
    }

    private func starterDivider() -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 34)
    }
}

// MARK: - Chat Bubble

struct ConciergeBubble: View {
    let message: ConciergeMessage
    let selected: (SupabaseService.ConciergeParseItem) -> SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeParseItem, SupabaseService.ConciergeCandidate) -> Void
    let onOpenRecommendation: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onQuickSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    var onConfirmItems: ((SupabaseService.ConciergeParseResponse) -> Void)? = nil
    var itemActions: [String: ImportItemAction] = [:]
    @Binding var excludedItemIds: Set<String>
    @State private var hiddenRecommendationIds: Set<String> = []

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .assistant {
                assistantContent
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                userContent
            }
        }
    }

    // MARK: User Bubble — the only "contained" element
    // Dark, confident, asymmetric. The user's voice stands out from the editorial field.
    private var userContent: some View {
        Text(message.text)
            .font(.kuroBody())
            .foregroundColor(.white.opacity(0.90))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: KuroRadius.md,
                    bottomLeadingRadius: KuroRadius.md,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: KuroRadius.md,
                    style: .continuous
                )
                .fill(Color.black.opacity(0.88))
            )
            .frame(maxWidth: 320, alignment: .trailing)
    }

    // MARK: Assistant Content — open editorial layout (NOT a bubble)
    // The curator speaks through space, type, and structure — not containers.
    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Text message — open, airy, with the glyph
            if !message.text.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    KuroConciergeGlyph(size: 10)
                        .opacity(0.28)
                        .padding(.top, 1)

                    Text(message.text)
                        .font(.kuroBody())
                        .foregroundColor(.black.opacity(0.72))
                        .lineSpacing(3)
                }
                .frame(maxWidth: 340, alignment: .leading)
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
                .frame(maxWidth: 400, alignment: .leading)
            } else if let items = message.items, !items.isEmpty {
                // Simple match list (no confirm)
                VStack(alignment: .leading, spacing: 0) {
                    matchListHeader(count: items.count)

                    ForEach(items) { item in
                        ConciergeMatchRow(
                            item: item,
                            chosen: selected(item),
                            onSelect: { cand in onSelect(item, cand) }
                        )

                        if item.id != items.last?.id {
                            Rectangle()
                                .fill(Color.black.opacity(0.04))
                                .frame(height: 0.5)
                                .padding(.leading, 20)
                        }
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 6)
                )
                .frame(maxWidth: 400, alignment: .leading)
            }

            // Recommendation rails
            if let sets = message.recommendationSets, !sets.isEmpty {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.xl) {
                    ForEach(sets, id: \.id) { set in
                        let items = (set.items ?? []).filter { !hiddenRecommendationIds.contains("\($0.mediaId)_\($0.mediaType)") }
                        if !items.isEmpty {
                            ConciergeRail(
                                title: set.title ?? "Curated",
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
                    title: "Curated",
                    items: recs.filter { !hiddenRecommendationIds.contains("\($0.mediaId)_\($0.mediaType)") },
                    hiddenRecommendationIds: $hiddenRecommendationIds,
                    onOpen: onOpenRecommendation,
                    onQuickSave: onQuickSave
                )
                .frame(maxWidth: 520, alignment: .leading)
            }
        }
    }

    private func matchListHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 1.5, height: 10)

            Text("MATCHED")
                .font(.kuroMicro(weight: .medium))
                .tracking(2.0)
                .foregroundColor(.black.opacity(0.35))

            Spacer()

            Text("\(count)")
                .font(.kuroMicro(weight: .medium))
                .foregroundColor(.black.opacity(0.25))
                .monospacedDigit()
        }
        .padding(.bottom, 10)
    }
}

// MARK: - Inline Confirm Bubble (Import Reconciliation)
// Structured like a curatorial exhibition checklist.

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — exhibition checklist style
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Rectangle()
                    .fill(Color.black.opacity(0.40))
                    .frame(width: 1.5, height: 10)

                Text("IMPORT PREVIEW")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.4)
                    .foregroundColor(.black.opacity(0.40))

                Spacer()

                Text("\(items.count)")
                    .font(.kuroMicro(weight: .medium))
                    .foregroundColor(.black.opacity(0.25))
                    .monospacedDigit()
            }
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
                .padding(.bottom, 12)

            // Sections
            if !addItems.isEmpty {
                reconcileSection(title: "NEW", items: addItems, action: .add)
            }

            if !updateItems.isEmpty {
                if !addItems.isEmpty { sectionSpacing }
                reconcileSection(title: "UPDATE", items: updateItems, action: .update)
            }

            if !skipItems.isEmpty {
                if !addItems.isEmpty || !updateItems.isEmpty { sectionSpacing }
                Group {
                    reconcileSection(title: "UNCHANGED", items: skipItems, action: .skip)
                }
                .opacity(0.40)
            }

            // Confirm button — a confident, minimal CTA
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
            .padding(.top, 16)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
    }

    private var sectionSpacing: some View {
        Rectangle()
            .fill(Color.black.opacity(0.04))
            .frame(height: 0.5)
            .padding(.vertical, 10)
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
    private func reconcileSection(title: String, items: [SupabaseService.ConciergeParseItem], action: ImportItemAction) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section label
            Text(title)
                .font(.kuroMicro(weight: .medium))
                .tracking(1.8)
                .foregroundColor(.black.opacity(0.30))
                .padding(.bottom, 8)

            ForEach(items) { item in
                ConciergeReconcileRow(
                    item: item,
                    action: action,
                    chosen: selected(item),
                    onSelect: { cand in onSelect(item, cand) },
                    isExcluded: excludedItemIds.contains(item.id),
                    onToggleExclude: action != .skip ? { toggleExclude(item.id) } : nil
                )

                if item.id != items.last?.id {
                    Rectangle()
                        .fill(Color.black.opacity(0.03))
                        .frame(height: 0.5)
                        .padding(.leading, 22)
                        .padding(.vertical, 2)
                }
            }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                // Selection toggle — minimal circle
                if action != .skip, let toggle = onToggleExclude {
                    Button(action: toggle) {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.black.opacity(isExcluded ? 0.15 : 0.60), lineWidth: 0.8)
                                .frame(width: 14, height: 14)

                            if !isExcluded {
                                Circle()
                                    .fill(Color.black.opacity(0.72))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Title
                    Text(item.normalized.isEmpty ? item.raw : item.normalized)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.black.opacity(isExcluded ? 0.30 : 0.82))
                        .lineLimit(2)

                    // Matched candidate name
                    if let c = chosen {
                        Text(c.title_raw)
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.38))
                            .lineLimit(2)
                    }

                    // Diff view for updates
                    if action == .update, let existing = item.existing_entry {
                        diffView(existing: existing, parsed: item.parsed)
                    }

                    if action == .skip {
                        Text("Already up to date")
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.28))
                    }
                }

                Spacer(minLength: 0)

                // Expand candidates
                if item.candidates.count > 1 && action != .skip {
                    Button(action: { withAnimation(KuroAnimation.fast) { expanded.toggle() } }) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.black.opacity(0.22))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.black.opacity(0.03)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(isExcluded ? 0.55 : 1.0)

            // Candidate list
            if expanded {
                candidateList
                    .padding(.leading, 24)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(item.candidates.prefix(4), id: \.media_id) { cand in
                Button(action: { onSelect(cand) }) {
                    HStack(spacing: 8) {
                        // Radio dot
                        Circle()
                            .fill(chosen?.media_id == cand.media_id ? Color.black.opacity(0.72) : Color.clear)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle().strokeBorder(Color.black.opacity(0.20), lineWidth: 0.6)
                            )

                        Text(cand.title_raw)
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.70))
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if let year = cand.year {
                            Text(String(year))
                                .font(.kuroMicro())
                                .foregroundColor(.black.opacity(0.30))
                                .monospacedDigit()
                        }

                        Text("\(Int(cand.score * 100))%")
                            .font(.kuroMicro(weight: .medium))
                            .foregroundColor(.black.opacity(0.30))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                            .fill(Color.black.opacity(chosen?.media_id == cand.media_id ? 0.04 : 0.01))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func diffView(existing: SupabaseService.ConciergeExistingEntry, parsed: SupabaseService.ConciergeParseItemParsed) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let parsedStatus = parsed.status,
               parsedStatus.uppercased() != existing.status.uppercased() {
                diffLine(from: existing.status, to: parsedStatus.uppercased())
            }
            if let ep = parsed.progressEpisodes,
               ep != (existing.progress_episodes ?? 0) {
                diffLine(from: "Ep \(existing.progress_episodes ?? 0)", to: "Ep \(ep)")
            }
            if let ch = parsed.progressChapters,
               ch != (existing.progress_chapters ?? 0) {
                diffLine(from: "Ch \(existing.progress_chapters ?? 0)", to: "Ch \(ch)")
            }
            if let vol = parsed.progressVolumes,
               vol != (existing.progress_volumes ?? 0) {
                diffLine(from: "Vol \(existing.progress_volumes ?? 0)", to: "Vol \(vol)")
            }
        }
    }

    @ViewBuilder
    private func diffLine(from: String, to: String) -> some View {
        HStack(spacing: 6) {
            Text(from)
                .font(.kuroCaption())
                .strikethrough()
                .foregroundColor(.black.opacity(0.25))

            Rectangle()
                .fill(Color.black.opacity(0.15))
                .frame(width: 10, height: 0.5)

            Text(to)
                .font(.kuroCaption(weight: .medium))
                .foregroundColor(.black.opacity(0.65))
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.normalized.isEmpty ? item.raw : item.normalized)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.black.opacity(0.82))
                        .lineLimit(2)

                    if let c = chosen {
                        Text(c.title_raw)
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.38))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if item.candidates.count > 1 {
                    Button(action: { withAnimation(KuroAnimation.fast) { expanded.toggle() } }) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.black.opacity(0.22))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.black.opacity(0.03)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(item.candidates.prefix(4), id: \.media_id) { cand in
                        Button(action: { onSelect(cand) }) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(chosen?.media_id == cand.media_id ? Color.black.opacity(0.72) : Color.clear)
                                    .frame(width: 6, height: 6)
                                    .overlay(
                                        Circle().strokeBorder(Color.black.opacity(0.20), lineWidth: 0.6)
                                    )

                                Text(cand.title_raw)
                                    .font(.kuroCaption())
                                    .foregroundColor(.black.opacity(0.70))
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                if let year = cand.year {
                                    Text(String(year))
                                        .font(.kuroMicro())
                                        .foregroundColor(.black.opacity(0.30))
                                        .monospacedDigit()
                                }

                                Text("\(Int(cand.score * 100))%")
                                    .font(.kuroMicro(weight: .medium))
                                    .foregroundColor(.black.opacity(0.30))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                                    .fill(Color.black.opacity(chosen?.media_id == cand.media_id ? 0.04 : 0.01))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Recommendation Rail (Gallery Exhibition)
// Each rail is an exhibition section — a vertical accent mark, then the gallery of works.

private struct ConciergeRail: View {
    let title: String
    let items: [SupabaseService.ConciergeRecommendResponse.Item]
    @Binding var hiddenRecommendationIds: Set<String>
    let onOpen: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onQuickSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Rail header — vertical accent + uppercase tracking
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.black.opacity(0.50))
                    .frame(width: 1.5, height: 12)

                Text(title.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.4)
                    .foregroundColor(.black.opacity(0.40))

                Spacer(minLength: 0)

                Text("\(items.count)")
                    .font(.kuroMicro())
                    .foregroundColor(.black.opacity(0.20))
                    .monospacedDigit()
            }

            // Gallery scroll
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
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

// MARK: - Recommendation Card (Gallery Piece)
// Each card is a gallery piece: the poster is the artwork, the title is the placard.
// Tall proportions, editorial typography, vignette for depth.

private struct ConciergeRecCard: View {
    let item: SupabaseService.ConciergeRecommendResponse.Item
    let onOpen: () -> Void
    let onQuickSave: () -> Void
    let onHide: () -> Void

    @State private var isPressed = false

    private let cardWidth: CGFloat = 130
    private let imageHeight: CGFloat = 195

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The artwork — poster with subtle vignette
            Button(action: onOpen) {
                ZStack(alignment: .bottomLeading) {
                    KuroCachedAsyncImage(url: URL(string: item.coverImageMedium ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Color.black.opacity(0.04)
                                .overlay(
                                    Text("KURO")
                                        .font(.kuroMicro(weight: .medium))
                                        .tracking(3.0)
                                        .foregroundColor(.black.opacity(0.08))
                                )
                        case .empty:
                            Color.black.opacity(0.02)
                        @unknown default:
                            Color.black.opacity(0.02)
                        }
                    }
                    .frame(width: cardWidth, height: imageHeight)
                    .clipped()

                    // Subtle bottom vignette — gives gallery depth
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.18)],
                        startPoint: .init(x: 0.5, y: 0.5),
                        endPoint: .bottom
                    )
                    .frame(height: 50)
                    .allowsHitTesting(false)
                }
                .frame(width: cardWidth, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous))
                // Score badge — top trailing
                .overlay(alignment: .topTrailing) {
                    if let score = item.averageScore {
                        KuroScoreBadge(score: Double(score) / 10.0)
                            .padding(5)
                    }
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.97 : 1.0)
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

            // The placard — serif title, metadata below
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12, weight: .light, design: .serif))
                    .foregroundColor(.black.opacity(0.82))
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)

                // Year · Format — quiet metadata
                Text(
                    [item.year.map(String.init), item.format?.lowercased()]
                        .compactMap { $0 }
                        .joined(separator: " \u{00B7} ")
                )
                .font(.kuroMicro())
                .foregroundColor(.black.opacity(0.32))
                .lineLimit(1)
            }
            .padding(.top, 8)
        }
        .frame(width: cardWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint("Recommendation. Long press for options.")
    }
}
