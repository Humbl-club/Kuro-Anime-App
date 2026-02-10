#if DEBUG
// MARK: - CONCIERGE RECOMMENDATION RAILS
// Cinematic horizontal scrolling recommendation cards for the Concierge
// iOS 26+ optimized with snap-to-card, scale-on-center, and rich interactions

import SwiftUI
import Observation

// MARK: - Recommendation Item Type
typealias ConciergeRecItem = SupabaseService.ConciergeRecommendResponse.Item

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

// MARK: - View Model for Rail State
@MainActor
@Observable
final class RecommendationRailViewModel {
    var hiddenItemIds: Set<String> = []
    var selectedItemForReasoning: (ConciergeRecItem)?
    var showWhyThisSheet = false
    var recentlyHiddenItem: (ConciergeRecItem)?
    var showHiddenToast = false
    
    func hideItem(_ item: ConciergeRecItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            hiddenItemIds.insert(item.id)
            recentlyHiddenItem = item
            showHiddenToast = true
        }
        
        // Auto-dismiss toast after delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.2)) {
                    showHiddenToast = false
                }
            }
        }
    }
    
    func undoHide() {
        guard let item = recentlyHiddenItem else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            hiddenItemIds.remove(item.id)
            recentlyHiddenItem = nil
            showHiddenToast = false
        }
    }
    
    func showWhyThis(for item: ConciergeRecItem) {
        selectedItemForReasoning = item
        showWhyThisSheet = true
    }
}

// MARK: - Recommendation Rail
struct RecommendationRail: View {
    let title: String
    let items: [ConciergeRecItem]
    let onOpen: (ConciergeRecItem) -> Void
    let onSave: (ConciergeRecItem) -> Void
    let onHide: ((ConciergeRecItem) -> Void)?
    
    @State private var viewModel = RecommendationRailViewModel()
    @State private var scrollPosition: String?
    @State private var centeredItemId: String?
    
    // Card metrics
    private let cardWidth: CGFloat = 140
    private let cardHeight: CGFloat = 268 // 200 poster + 68 text
    private let cardSpacing: CGFloat = 12
    private let edgePadding: CGFloat = 20
    
    // Computed property for visible items
    private var visibleItems: [ConciergeRecItem] {
        items.filter { !viewModel.hiddenItemIds.contains($0.id) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            sectionHeader
                .padding(.horizontal, edgePadding)
                .padding(.bottom, 12)
            
            // Horizontal Scrolling Cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(visibleItems) { item in
                        RecommendationCard(
                            item: item,
                            isCentered: centeredItemId == item.id,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight,
                            onOpen: { onOpen(item) },
                            onSave: { onSave(item) },
                            onHide: { viewModel.hideItem(item) },
                            onWhyThis: { viewModel.showWhyThis(for: item) }
                        )
                        .id(item.id)
                        .scrollTransition(.animated(.spring(response: 0.3, dampingFraction: 0.8))) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.95)
                                .opacity(phase.isIdentity ? 1.0 : 0.7)
                        }
                    }
                }
                .padding(.horizontal, edgePadding)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollPosition)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .onChange(of: scrollPosition) { oldValue, newValue in
                centeredItemId = newValue
            }
            .frame(height: cardHeight + 8) // Extra space for shadow
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
    }
    
    // MARK: - Section Header
    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .default))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundColor(.black.opacity(0.6))
            
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Recommendation Card
struct RecommendationCard: View {
    let item: ConciergeRecItem
    let isCentered: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onOpen: () -> Void
    let onSave: () -> Void
    let onHide: () -> Void
    let onWhyThis: () -> Void
    
    @State private var isPressed = false
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var showDetail = false
    
    private let posterAspectRatio: CGFloat = 0.7 // 140:200
    
    private var posterHeight: CGFloat {
        cardWidth / posterAspectRatio
    }
    
    private var displayScore: String? {
        guard let score = item.averageScore, score > 0 else { return nil }
        return String(format: "%.1f", Double(score) / 10.0)
    }
    
    private var metaLine: String {
        var parts: [String] = []
        
        if let year = item.year {
            parts.append(String(year))
        }
        
        if let format = item.format {
            let formatLower = format.lowercased()
            switch formatLower {
            case "tv":
                parts.append("Series")
            case "movie":
                parts.append("Movie")
            case "ova", "ona":
                parts.append(format.uppercased())
            case "manga":
                parts.append("Manga")
            case "novel":
                parts.append("Novel")
            default:
                parts.append(formatLower.capitalized)
            }
        }
        
        return parts.joined(separator: " · ")
    }
    
    var body: some View {
        cardContent
            .frame(width: cardWidth, height: cardHeight)
            .scaleEffect(isPressed ? 0.98 : (isCentered ? 1.02 : 1.0))
            .offset(dragOffset)
            .opacity(dragOffset.width > 100 ? 0 : 1)
            .rotationEffect(.degrees(Double(dragOffset.width) / 20))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCentered)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
            .gesture(dragGesture)
            .onTapGesture {
                guard !isDragging else { return }
                KuroAccessibility.impactHaptic(.light)
                onOpen()
            }
            .onLongPressGesture(
                minimumDuration: 0.5,
                pressing: { pressing in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = pressing
                    }
                    if pressing {
                        KuroAccessibility.impactHaptic(.heavy)
                    }
                },
                perform: {}
            )
            .contextMenu {
                contextMenuContent
            }
    }
    
    // MARK: - Card Content
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Poster Image Container
            ZStack(alignment: .topTrailing) {
                // Poster Image
                posterImage
                
                // Score Badge
                if let score = displayScore {
                    ScoreBadge(score: score)
                        .padding(8)
                }
            }
            
            // Text Content
            VStack(alignment: .leading, spacing: 4) {
                Text(sanitizedTitle)
                    .font(.system(size: 13, weight: .light, design: .serif))
                    .textCase(.uppercase)
                    .tracking(item.title.count >= 26 ? 0.3 : 0.6)
                    .foregroundColor(.black.opacity(0.9))
                    .lineLimit(2)
                    .minimumScaleFactor(0.92)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .frame(height: 38, alignment: .top)
                
                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(.black.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth, alignment: .topLeading)
            .padding(.top, 10)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .top)
        .shadow(
            color: isPressed ? Color.black.opacity(0.15) : Color.black.opacity(0.08),
            radius: isPressed ? 12 : 8,
            x: 0,
            y: isPressed ? 8 : 4
        )
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.06))
            .overlay(
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.black.opacity(0.3))
            )
    }
    
    private var sanitizedTitle: String {
        KuroCardText.sanitizeTitleForCard(item.title)
    }
    
    // MARK: - Drag Gesture (Swipe to Hide)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                // Only allow horizontal drag for dismiss
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                if value.translation.width > threshold {
                    // Swiped right - hide with animation
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        dragOffset = CGSize(width: cardWidth + 50, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        KuroAccessibility.impactHaptic(.medium)
                        onHide()
                        dragOffset = .zero
                        isDragging = false
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isDragging = false
                    }
                }
            }
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

// MARK: - Score Badge
struct ScoreBadge: View {
    let score: String
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 7, weight: .bold))
            Text(score)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
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
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .lineLimit(2)
                
                if let year = item.year {
                    Text(String(year))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                if let format = item.format {
                    Text(format.capitalized)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
        }
    }
    
    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended because:")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            if let blurb = item.blurb, !blurb.isEmpty {
                Text(blurb)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            } else {
                Text("This title matches your taste profile based on your viewing history and preferences.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func signalsSection(signals: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you might like:")
                .font(.system(size: 14, weight: .semibold))
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(signals.prefix(4), id: \.self) { signal in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        
                        Text(signal)
                            .font(.system(size: 14))
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
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
            
            Text("\(item.title) hidden")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: onUndo) {
                Text("UNDO")
                    .font(.system(size: 13, weight: .semibold))
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
            isCentered: false,
            cardWidth: 140,
            cardHeight: 268,
            onOpen: {},
            onSave: {},
            onHide: {},
            onWhyThis: {}
        )
        
        RecommendationCard(
            item: mockItem,
            isCentered: true,
            cardWidth: 140,
            cardHeight: 268,
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
