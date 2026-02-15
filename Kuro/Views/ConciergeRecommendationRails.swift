// MARK: - CONCIERGE RECOMMENDATION RAILS
// Cinematic horizontal scrolling recommendation cards for the Concierge
// iOS 26+ optimized with snap-to-card, scale-on-center, and rich interactions

import SwiftUI
import Observation

// MARK: - Recommendation Item Type
typealias ConciergeRecItem = SupabaseService.ConciergeRecommendResponse.Item

// Preview mocks live under DEBUG at the bottom of the file.

// MARK: - Selection Haptics (Snap-to-Card)

// MARK: - View Model for Rail State
@MainActor
@Observable
final class RecommendationRailViewModel {
    var hiddenItemIds: Set<String> = []
    var selectedItemForReasoning: (ConciergeRecItem)?
    var showWhyThisSheet = false
    var recentlyHiddenItem: (ConciergeRecItem)?
    var showHiddenToast = false
    private var hideToastDismissTask: Task<Void, Never>?
    
    func hideItem(_ item: ConciergeRecItem) {
        hideToastDismissTask?.cancel()
        withAnimation(KuroAnimation.editorial) {
            hiddenItemIds.insert(item.id)
            recentlyHiddenItem = item
            showHiddenToast = true
        }
        
        // Auto-dismiss toast after delay
        hideToastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(KuroAnimation.fast) {
                showHiddenToast = false
            }
        }
    }
    
    func undoHide() {
        guard let item = recentlyHiddenItem else { return }
        hideToastDismissTask?.cancel()
        withAnimation(KuroAnimation.editorial) {
            hiddenItemIds.remove(item.id)
            recentlyHiddenItem = nil
            showHiddenToast = false
        }
    }
    
    func showWhyThis(for item: ConciergeRecItem) {
        selectedItemForReasoning = item
        showWhyThisSheet = true
    }

    func cancelPendingTasks() {
        hideToastDismissTask?.cancel()
        hideToastDismissTask = nil
    }
}

// MARK: - Recommendation Rail
struct RecommendationRail: View {
    let title: String
    let subtitle: String?
    let items: [ConciergeRecItem]
    let onOpen: (ConciergeRecItem) -> Void
    let onSave: (ConciergeRecItem) -> Void
    let onHide: ((ConciergeRecItem) -> Void)?

    @State private var viewModel = RecommendationRailViewModel()
    @State private var appeared = false

    private let cardWidth: CGFloat = 140
    private let cardSpacing: CGFloat = 16
    private let edgePadding: CGFloat = 4
    
    // Computed property for visible items
    private var visibleItems: [ConciergeRecItem] {
        items.filter { !viewModel.hiddenItemIds.contains($0.id) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader
                .padding(.horizontal, edgePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        RecommendationCard(
                            item: item,
                            index: index,
                            appeared: appeared,
                            cardWidth: cardWidth,
                            onOpen: { onOpen(item) },
                            onSave: { onSave(item) },
                            onHide: {
                                viewModel.hideItem(item)
                                onHide?(item)
                            },
                            onWhyThis: { viewModel.showWhyThis(for: item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, edgePadding + 4)
                .padding(.vertical, 4)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .kuroSwipeExclusionZone()
            .onAppear {
                let prefetchUrls = visibleItems
                    .prefix(10)
                    .compactMap { URL(string: $0.coverImageMedium ?? "") }
                Task { await ImagePipeline.shared.prefetch(urls: prefetchUrls, maxPixelSize: 520) }
                withAnimation(.easeOut(duration: 0.5)) {
                    appeared = true
                }
            }
            .frame(height: 284)
        }
        .sheet(isPresented: $viewModel.showWhyThisSheet) {
            if let item = viewModel.selectedItemForReasoning {
                WhyThisSheet(item: item)
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.showHiddenToast, let item = viewModel.recentlyHiddenItem {
                HiddenToast(item: item, onUndo: { viewModel.undoHide() })
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDisappear {
            viewModel.cancelPendingTasks()
        }
    }
    
    // MARK: - Section Header
    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(.black.opacity(0.85))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(visibleItems.count)")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(.black.opacity(0.35))
                    .monospacedDigit()
            }

            if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(.black.opacity(0.35))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Recommendation Card
struct RecommendationCard: View {
    let item: ConciergeRecItem
    let index: Int
    let appeared: Bool
    let cardWidth: CGFloat
    let onOpen: () -> Void
    let onSave: () -> Void
    let onHide: () -> Void
    let onWhyThis: () -> Void
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    private let posterHeight: CGFloat = 210
    
    private var metaLine: String {
        var parts: [String] = []
        if let year = item.year {
            parts.append(String(year))
        }
        if let score = item.averageScore, score > 0 {
            let normalized = Double(score) / 10.0
            parts.append("★ \(String(format: "%.2f", normalized))")
        } else if let format = item.format {
            parts.append(format.capitalized)
        }
        return parts.joined(separator: " · ")
    }
    
    var body: some View {
        cardContent
            .frame(width: cardWidth)
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : 10)
            .animation(.easeOut(duration: 0.5).delay(Double(index + 1) * 0.1), value: appeared)
            .onTapGesture {
                guard !suppressCardTaps else { return }
                KuroAccessibility.impactHaptic(.light)
                onOpen()
            }
            .contextMenu {
                contextMenuContent
            }
    }
    
    // MARK: - Card Content
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Poster Image Container
            ZStack(alignment: .topTrailing) {
                // Poster Image
                posterImage
                
                // Score Badge
                if let score = item.averageScore, score > 0 {
                    KuroScoreBadge(score: Double(score) / 10.0)
                        .padding(8)
                }
            }

            Text(sanitizedTitle.uppercased())
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .tracking(0.8)
                .foregroundStyle(.black.opacity(0.85))
                .lineLimit(2)
                .frame(height: 36, alignment: .topLeading)

            if !metaLine.isEmpty {
                Text(metaLine)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(.black.opacity(0.35))
                    .lineLimit(1)
            }
        }
        .frame(width: cardWidth, alignment: .topLeading)
        .contentShape(Rectangle())
    }
    
    private var posterImage: some View {
        KuroCachedAsyncImage(
            url: URL(string: item.coverImageMedium ?? ""),
            maxPixelSize: 520
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure, .empty:
                placeholderView
            @unknown default:
                placeholderView
            }
        }
        .frame(width: cardWidth, height: posterHeight)
        .clipShape(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var placeholderView: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .overlay(
                Text("KURO")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(3.0)
                    .foregroundColor(.black.opacity(0.10))
            )
    }
    
    private var sanitizedTitle: String {
        KuroCardText.sanitizeTitleForCard(item.title)
    }
    
    // MARK: - Context Menu
    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            onSave()
        } label: {
            Label("Save to Planning", systemImage: "bookmark")
        }
        
        Button(role: .destructive) {
            KuroAccessibility.impactHaptic(.medium)
            onHide()
        } label: {
            Label("Hide", systemImage: "eye.slash")
        }
        
        Divider()
        
        Button {
            KuroAccessibility.impactHaptic(.light)
            onWhyThis()
        } label: {
            Label("Why this?", systemImage: "sparkles")
        }
    }
}

// MARK: - Why This Sheet
struct WhyThisSheet: View {
    let item: ConciergeRecItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with poster
                    headerSection
                    
                    // Reasoning content
                    reasoningSection
                    
                    // Signals section (if available)
                    if let signals = item.signals, !signals.isEmpty {
                        signalsSection(signals: signals)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Why This?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Small poster
            KuroCachedAsyncImage(
                url: URL(string: item.coverImageMedium ?? ""),
                maxPixelSize: 200
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    Color.black.opacity(0.06)
                }
            }
            .frame(width: 80, height: 114)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.kuroTitle(weight: .light))
                    .lineLimit(2)

                if let year = item.year {
                    Text(String(year))
                        .font(.kuroBody())
                        .foregroundColor(.secondary)
                }

                if let format = item.format {
                    Text(format.capitalized)
                        .font(.kuroCaption())
                        .foregroundColor(.black.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
        }
    }
    
    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended because:")
                .font(.kuroBody(weight: .medium))
                .foregroundColor(.primary)
            
            if let blurb = item.blurb, !blurb.isEmpty {
                Text(blurb)
                    .font(.kuroBody())
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            } else {
                Text("This title matches your taste profile based on your viewing history and preferences.")
                    .font(.kuroBody())
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func signalsSection(signals: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you might like:")
                .font(.kuroBody(weight: .medium))
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(signals.prefix(4), id: \.self) { signal in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.black.opacity(0.25))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        
                        Text(signal)
                            .font(.kuroBody())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Hidden Toast
struct HiddenToast: View {
    let item: ConciergeRecItem
    let onUndo: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash.fill")
                .font(.kuroBody())
                .foregroundColor(.white.opacity(0.8))

            Text("\(item.title) hidden")
                .font(.kuroBody(weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            Button(action: onUndo) {
                Text("UNDO")
                    .font(.kuroCaption(weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview Provider
#if DEBUG

extension ConciergeRecItem {
    static func mock(
        mediaType: String = "anime",
        mediaId: Int = Int.random(in: 1...10000),
        title: String,
        coverImageMedium: String? = nil,
        averageScore: Int? = nil,
        year: Int? = nil,
        format: String? = nil,
        status: String? = nil,
        signals: [String]? = nil,
        blurb: String? = nil,
        siteUrl: String? = nil,
        matchCount: Int? = nil
    ) -> ConciergeRecItem {
        ConciergeRecItem(
            mediaType: mediaType,
            mediaId: mediaId,
            matchCount: matchCount,
            title: title,
            coverImageMedium: coverImageMedium,
            averageScore: averageScore,
            year: year,
            format: format,
            status: status,
            siteUrl: siteUrl,
            signals: signals,
            blurb: blurb
        )
    }
}

#Preview("Recommendation Rail") {
    let mockItems: [ConciergeRecItem] = [
        .mock(
            title: "One Piece",
            coverImageMedium: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx21-YCDojbE4buUN.png",
            averageScore: 88,
            year: 1999,
            format: "TV",
            status: "RELEASING",
            signals: ["Epic world-building", "Memorable characters", "Long-running story", "Action & adventure"],
            blurb: "A legendary pirate adventure with incredible world-building and character development."
        ),
        .mock(
            title: "Attack on Titan",
            coverImageMedium: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx16498-73IhYXpVSJOC.png",
            averageScore: 91,
            year: 2013,
            format: "TV",
            status: "FINISHED",
            signals: ["Dark fantasy", "Political intrigue", "Plot twists", "High stakes"],
            blurb: "Dark fantasy with intense action and a complex, politically-charged narrative."
        ),
        .mock(
            title: "Steins;Gate",
            coverImageMedium: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx9253-7pdcVzQSkKxT.png",
            averageScore: 92,
            year: 2011,
            format: "TV",
            status: "FINISHED",
            signals: ["Time travel", "Sci-fi thriller", "Complex plot", "Emotional depth"],
            blurb: "A sci-fi thriller about time travel and the consequences of changing the past."
        ),
        .mock(
            title: "Vinland Saga",
            coverImageMedium: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx136381-sIHpS2VqohyD.png",
            averageScore: 89,
            year: 2019,
            format: "TV",
            status: "RELEASING",
            signals: ["Historical fiction", "Viking setting", "Philosophical themes", "Great animation"],
            blurb: "A viking saga exploring the cycle of violence and the meaning of true strength."
        ),
        .mock(
            title: "Hunter x Hunter (2011)",
            coverImageMedium: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx11061-TtJFr56o7cqR.png",
            averageScore: 90,
            year: 2011,
            format: "TV",
            status: "FINISHED",
            signals: ["Creative power system", "Strategic battles", "Character growth", "Unique arcs"],
            blurb: "A battle shonen that subverts expectations with complex power systems and narratives."
        )
    ]
    
    ScrollView {
        VStack(spacing: 32) {
            RecommendationRail(
                title: "If you like action",
                subtitle: "Clean choreography, real momentum",
                items: mockItems,
                onOpen: { item in
                    print("Open: \(item.title)")
                },
                onSave: { item in
                    print("Save: \(item.title)")
                },
                onHide: { item in
                    print("Hide: \(item.title)")
                }
            )
            
            RecommendationRail(
                title: "Critically acclaimed",
                subtitle: "Anchors worth knowing",
                items: Array(mockItems.reversed()),
                onOpen: { item in
                    print("Open: \(item.title)")
                },
                onSave: { item in
                    print("Save: \(item.title)")
                },
                onHide: { item in
                    print("Hide: \(item.title)")
                }
            )
        }
        .padding(.vertical, 20)
    }
    .background(Color.kuroBackground)
}

#Preview("Individual Card") {
    let mockItem = ConciergeRecItem.mock(
        title: "One Piece",
        coverImageMedium: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx21-YCDojbE4buUN.png",
        averageScore: 88,
        year: 1999,
        format: "TV",
        status: "RELEASING",
        signals: ["Epic world-building", "Memorable characters", "Long-running story"],
        blurb: "A legendary pirate adventure with incredible world-building and character development."
    )
    
    HStack {
        RecommendationCard(
            item: mockItem,
            index: 0,
            appeared: true,
            cardWidth: 140,
            onOpen: {},
            onSave: {},
            onHide: {},
            onWhyThis: {}
        )
        
        RecommendationCard(
            item: mockItem,
            index: 1,
            appeared: true,
            cardWidth: 140,
            onOpen: {},
            onSave: {},
            onHide: {},
            onWhyThis: {}
        )
    }
    .padding(40)
    .background(Color.kuroBackground)
}

#Preview("Why This Sheet") {
    let mockItem = ConciergeRecItem.mock(
        title: "Steins;Gate",
        coverImageMedium: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx9253-7pdcVzQSkKxT.png",
        averageScore: 92,
        year: 2011,
        format: "TV",
        status: "FINISHED",
        signals: ["Time travel mechanics", "Sci-fi thriller", "Complex plot", "Emotional depth", "Mind-bending twists"],
        blurb: "A sci-fi thriller about time travel and the consequences of changing the past. Follows a self-proclaimed mad scientist who accidentally discovers time travel."
    )
    
    WhyThisSheet(item: mockItem)
}

#Preview("Hidden Toast") {
    let mockItem = ConciergeRecItem.mock(
        title: "Attack on Titan",
        coverImageMedium: nil,
        averageScore: 91,
        year: 2013,
        format: "TV",
        status: "FINISHED"
    )
    
    HiddenToast(item: mockItem, onUndo: {})
        .padding(20)
}

#endif
