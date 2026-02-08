import SwiftUI

// Legacy Concierge UI components that `ConciergeView` still uses for the initial chat surface
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
                KuroGlassCard(cornerRadius: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            KuroConciergeMark(size: 34)
                                .matchedGeometryEffect(id: "kurochan", in: mascotNS)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("CONCIERGE")
                                    .font(.system(size: 14, weight: .light, design: .serif))
                                    .tracking(2.4)
                                    .foregroundColor(.black.opacity(0.78))
                                Text("Imports + recommendations")
                                    .font(.system(size: 11, weight: .light))
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

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isEmpty
        }
    }
}

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

struct ConciergeIntroCard: View {
    var body: some View {
        KuroGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    KuroConciergeMark(size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONCIERGE")
                            .font(.system(size: 14, weight: .light, design: .serif))
                            .tracking(2.4)
                            .foregroundColor(.black.opacity(0.80))
                        Text("Imports + recommendations")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.black.opacity(0.55))
                    }

                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)

                Text("Paste titles to import, or describe the mood.\nDefaults are clean — no adult content.")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(.black.opacity(0.62))
                    .lineSpacing(3)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Concierge. Paste titles to import, or ask for a vibe.")
    }
}

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
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) {
                appeared = true
            }
        }
    }
}

struct ConciergeBubble: View {
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
        HStack(alignment: .bottom) {
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 10) {
                    if !message.text.isEmpty {
                        glassBubble(cornerRadius: 18) {
                            Text(message.text)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.black.opacity(0.82))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .frame(maxWidth: 360, alignment: .leading)
                    }

                    if let items = message.items, !items.isEmpty {
                        glassBubble(cornerRadius: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("MATCHES")
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(1.6)
                                        .foregroundColor(.black.opacity(0.55))
                                    Spacer()
                                    Text("\(items.count)")
                                        .font(.system(size: 10, weight: .semibold))
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
                Spacer(minLength: 40)
                glassBubble(cornerRadius: 18) {
                    Text(message.text)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.black)
                        )
                }
                .frame(maxWidth: 360, alignment: .trailing)
            }
        }
    }
}

private struct ConciergeMatchRow: View {
    let item: SupabaseService.ConciergeParseItem
    let chosen: SupabaseService.ConciergeCandidate?
    let onSelect: (SupabaseService.ConciergeCandidate) -> Void

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.normalized.isEmpty ? item.raw : item.normalized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.black.opacity(0.90))
                        .lineLimit(2)

                    if let c = chosen {
                        Text(c.title_raw)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.black.opacity(0.55))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                Button(action: { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.candidates.prefix(4), id: \.media_id) { cand in
                        Button(action: { onSelect(cand) }) {
                            HStack(spacing: 10) {
                                Text(cand.title_raw)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.black.opacity(0.82))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(String(format: "%.2f", cand.score))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.45))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.03))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ConciergeRail: View {
    let title: String
    let items: [SupabaseService.ConciergeRecommendResponse.Item]
    @Binding var hiddenRecommendationIds: Set<String>
    let onOpen: (SupabaseService.ConciergeRecommendResponse.Item) -> Void
    let onQuickSave: (SupabaseService.ConciergeRecommendResponse.Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
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

private struct ConciergeRecCard: View {
    let item: SupabaseService.ConciergeRecommendResponse.Item
    let onOpen: () -> Void
    let onQuickSave: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpen) {
                PosterView(url: URL(string: item.coverImageMedium ?? ""))
                    .frame(width: 120, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundColor(.black.opacity(0.92))
                    .lineLimit(2)
                    .frame(height: 34, alignment: .top)
                Text([item.year.map(String.init), item.format].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.black.opacity(0.50))
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Button(action: onQuickSave) {
                    Text("SAVE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundColor(.black.opacity(0.80))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onHide) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black.opacity(0.45))
                        .frame(width: 34, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 140, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint("Recommendation. Save or open details.")
    }
}
