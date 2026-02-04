// MARK: - KURO REFINED CARD SYSTEM
// Premium, Elegant, Evolved Design
// Philosophy: "Gallery-quality presentation with editorial restraint"

import SwiftUI

// MARK: - Refined Score Badge
struct KuroScoreBadge: View {
    let score: Double?
    
    private var displayScore: String {
        guard let score = score, score > 0 else { return "--" }
        return String(format: "%.1f", score)
    }
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 7, weight: .bold))
            Text(displayScore)
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

// MARK: - Year Badge (on poster)
struct KuroYearBadge: View {
    let yearText: String

    var body: some View {
        Text(yearText)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
            )
    }
}

// MARK: - Collection Status Indicator
struct KuroStatusIndicator: View {
    let isInCollection: Bool
    
    var body: some View {
        if isInCollection {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(4)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.75))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Refined Portrait Card (Primary)
struct KuroPortraitCard: View {
    let media: any MediaDisplayable
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    
    @State private var showDetail = false
    @State private var isPressed = false
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    
    private var mediaType: String {
        media.kind.rawValue
    }
    
    private var isInCollection: Bool {
        supabaseService.isInCollection(mediaId: media.id, mediaType: mediaType)
    }
    
    private var imageHeight: CGFloat {
        cardWidth / 0.7 // Standard poster ratio
    }

    private var yearBadgeText: String? {
        let digits = media.year.filter(\.isNumber)
        guard digits.count >= 4 else { return nil }
        return String(digits.prefix(4))
    }

    private var episodesLine: String? {
        if let episodes = media.episodes, episodes > 0 {
            return "\(KuroCardText.countString(episodes)) eps"
        }
        if let chapters = media.chapters, chapters > 0 {
            return "\(KuroCardText.countString(chapters)) ch"
        }
        if let status = media.statusRaw?.uppercased() {
            if status == "RELEASING" { return "airing" }
            if status == "FINISHED" { return "finished" }
        }
        if let format = media.formatRaw, !format.isEmpty {
            return format.lowercased()
        }
        return nil
    }
    
    var body: some View {
        Button(action: {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Image Container
                ZStack(alignment: .top) {
                    KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 520) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth, height: imageHeight)
                                .clipped()
                        case .failure, .empty:
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                                .frame(width: cardWidth, height: imageHeight)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .tint(.black.opacity(0.3))
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: cardWidth, height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    HStack(alignment: .top) {
                        if let yearBadgeText {
                            KuroYearBadge(yearText: yearBadgeText)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            if let rating = media.rating, rating > 0 {
                                KuroScoreBadge(score: rating)
                            }

                            if isInCollection {
                                KuroStatusIndicator(isInCollection: true)
                            }
                        }
                    }
                    .padding(8)
                }
                
                // Text Block
                VStack(alignment: .leading, spacing: 4) {
                    Text(KuroCardText.sanitizeTitleForCard(media.title))
                        .font(.system(size: 13, weight: .light, design: .serif))
                        .textCase(.uppercase)
                        .tracking(media.title.count >= 26 ? 0.3 : 0.6)
                        .foregroundColor(.black.opacity(0.9))
                        .lineLimit(2)
                        .minimumScaleFactor(0.92)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                        .frame(height: 38, alignment: .top)

                    if let episodesLine {
                        Text(episodesLine)
                            .font(.system(size: 9, weight: .light))
                            .foregroundColor(.black.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .frame(width: cardWidth, alignment: .topLeading)
                .padding(.top, 10)
            }
            .frame(width: cardWidth, height: cardHeight, alignment: .top)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .pressable($isPressed)
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }
}

// MARK: - Refined Compact Card (Horizontal Scroll)
struct KuroCompactCard: View {
    let media: any MediaDisplayable
    let width: CGFloat = 110
    
    @State private var showDetail = false
    @State private var isPressed = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    
    private var height: CGFloat {
        width / 0.7
    }

    private var yearBadgeText: String? {
        let digits = media.year.filter(\.isNumber)
        guard digits.count >= 4 else { return nil }
        return String(digits.prefix(4))
    }

    private var episodesLine: String? {
        if let episodes = media.episodes, episodes > 0 {
            return "\(KuroCardText.countString(episodes)) eps"
        }
        if let chapters = media.chapters, chapters > 0 {
            return "\(KuroCardText.countString(chapters)) ch"
        }
        if let status = media.statusRaw?.uppercased() {
            if status == "RELEASING" { return "airing" }
            if status == "FINISHED" { return "finished" }
        }
        if let format = media.formatRaw, !format.isEmpty {
            return format.lowercased()
        }
        return nil
    }
    
    var body: some View {
        Button(action: {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .top) {
                    KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 300) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: width, height: height)
                                .clipped()
                        case .failure, .empty:
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                                .frame(width: width, height: height)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    
                    HStack(alignment: .top) {
                        if let yearBadgeText {
                            KuroYearBadge(yearText: yearBadgeText)
                        }
                        Spacer()
                        if let rating = media.rating, rating > 0 {
                            KuroScoreBadge(score: rating)
                        }
                    }
                    .padding(6)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(KuroCardText.sanitizeTitleForCard(media.title))
                        .font(.system(size: 12, weight: .light, design: .serif))
                        .textCase(.uppercase)
                        .tracking(media.title.count >= 24 ? 0.25 : 0.55)
                        .foregroundColor(.black.opacity(0.9))
                        .lineLimit(2)
                        .minimumScaleFactor(0.90)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                        .frame(height: 38, alignment: .top)

                    if let episodesLine {
                        Text(episodesLine)
                            .font(.system(size: 9, weight: .light))
                            .foregroundColor(.black.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .frame(width: width, alignment: .topLeading)
                .padding(.top, 10)
            }
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .opacity(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .pressable($isPressed)
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }
}

// MARK: - Refined Hero Card
struct KuroHeroCard: View {
    let media: any MediaDisplayable
    let width: CGFloat
    
    @State private var showDetail = false
    @State private var isPressed = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    
    private var height: CGFloat {
        max(220, floor(width * 0.54))
    }
    
    var body: some View {
        Button(action: {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.medium)
            showDetail = true
        }) {
            ZStack(alignment: .bottomLeading) {
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 700) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                    default:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.08))
                            .frame(width: width, height: height)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                // Gradient overlay
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.7)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text("FEATURED")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(media.title)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Text(media.year)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.85))
                        
                        if let rating = media.rating, rating > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white)
                        }
                        
                        if let episodes = media.episodes, episodes > 0 {
                            Text("· \(episodes) episodes")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                .padding(16)
                .allowsHitTesting(false)
            }
            .scaleEffect(isPressed ? 0.99 : 1.0)
            .opacity(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .pressable($isPressed, duration: 0.15)
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }
}

// MARK: - Press Effect Modifier
struct PressableModifier: ViewModifier {
    @Binding var isPressed: Bool
    let minimumDuration: Double
    
    func body(content: Content) -> some View {
        content
            .onLongPressGesture(
                minimumDuration: minimumDuration,
                maximumDistance: .infinity,
                pressing: { pressing in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = pressing
                    }
                },
                perform: {}
            )
    }
}

extension View {
    func pressable(_ isPressed: Binding<Bool>, duration: Double = 0.1) -> some View {
        modifier(PressableModifier(isPressed: isPressed, minimumDuration: duration))
    }
}

// MARK: - Section Header
struct KuroSectionHeader: View {
    let title: String
    let subtitle: String
    var showSeeAll: Bool = false
    var onSeeAll: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.3)
                    .foregroundColor(.black)
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(0.2)
                    .foregroundColor(.black.opacity(0.5))
            }
            
            Spacer()
            
            if showSeeAll, let onSeeAll = onSeeAll {
                Button(action: onSeeAll) {
                    Text("See All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Horizontal Section with Refined Cards
struct KuroHorizontalSection: View {
    let title: String
    let subtitle: String
    let items: [any MediaDisplayable]
    var onSeeAll: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KuroSectionHeader(
                title: title,
                subtitle: subtitle,
                showSeeAll: onSeeAll != nil,
                onSeeAll: onSeeAll
            )
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items, id: \.id) { media in
                        KuroCompactCard(media: media)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Two Column Grid Section with Refined Cards
struct KuroTwoColumnSection: View {
    let title: String
    let subtitle: String
    let items: [any MediaDisplayable]
    let geometry: GeometryProxy
    var onSeeAll: (() -> Void)? = nil
    var onLoadMore: (() async -> Void)? = nil
    
    private var gridMetrics: (columns: [GridItem], cardWidth: CGFloat, cardHeight: CGFloat) {
        let spacing: CGFloat = 12
        let padding: CGFloat = 20
        let availableWidth = geometry.size.width - (2 * padding) - spacing
        let cardWidth = floor(availableWidth / 2)
        let imageHeight = cardWidth / 0.7
        let cardHeight = imageHeight + 8 + 52 // image + spacing + text block
        
        let columns = [
            GridItem(.fixed(cardWidth), spacing: spacing),
            GridItem(.fixed(cardWidth), spacing: spacing)
        ]
        
        return (columns, cardWidth, cardHeight)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KuroSectionHeader(
                title: title,
                subtitle: subtitle,
                showSeeAll: onSeeAll != nil,
                onSeeAll: onSeeAll
            )
            
            let metrics = gridMetrics
            
            LazyVGrid(columns: metrics.columns, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, media in
                    KuroPortraitCard(
                        media: media,
                        cardWidth: metrics.cardWidth,
                        cardHeight: metrics.cardHeight
                    )
                    .onAppear {
                        if index == items.count - 1 {
                            Task { await onLoadMore?() }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
