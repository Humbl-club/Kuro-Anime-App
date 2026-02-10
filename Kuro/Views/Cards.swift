import SwiftUI

// MARK: - Modern Card Design System
// Enhanced cards with glass morphism, micro-interactions, and progressive disclosure

// MARK: - Card Status Types
enum CardStatus {
    case none
    case watching
    case completed
    case onHold
    case dropped
    case planToWatch
    
    var color: Color {
        switch self {
        case .none: return .clear
        case .watching: return .blue.opacity(0.8)
        case .completed: return .green.opacity(0.8)
        case .onHold: return .orange.opacity(0.8)
        case .dropped: return .gray.opacity(0.6)
        case .planToWatch: return .purple.opacity(0.8)
        }
    }
    
    var icon: String {
        switch self {
        case .none: return ""
        case .watching: return "play.fill"
        case .completed: return "checkmark.circle.fill"
        case .onHold: return "pause.circle.fill"
        case .dropped: return "xmark.circle.fill"
        case .planToWatch: return "clock.fill"
        }
    }
}

// MARK: - Smart Badge View
struct SmartBadge: View {
    let score: Double?
    let isNew: Bool
    let isTrending: Bool
    
    private var scoreColor: Color {
        guard let score = score else { return .gray.opacity(0.8) }
        switch score {
        case 9.0...: return .green.opacity(0.9)
        case 7.0..<9.0: return .blue.opacity(0.9)
        case 5.0..<7.0: return .orange.opacity(0.9)
        default: return .red.opacity(0.9)
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Score Badge with color coding
            if let score = score {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(scoreColor)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                )
            }
            
            // Status Badges
            if isNew {
                Text("NEW")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.9))
                    )
            }
            
            if isTrending {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.9))
                    )
            }
        }
    }
}

// MARK: - Quick Action Bar
struct QuickActionBar: View {
    @Binding var isFavorited: Bool
    @Binding var isInList: Bool
    let onInfo: () -> Void
    let onAdd: () -> Void
    
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Add to List
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isInList.toggle()
                    isAnimating = true
                }
                onAdd()
                
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isAnimating = false
                }
            }) {
                Image(systemName: isInList ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isInList ? .green.opacity(0.8) : .black.opacity(0.6))
                    .scaleEffect(isAnimating && isInList ? 1.2 : 1.0)
                    .rotationEffect(.degrees(isAnimating && isInList ? 360 : 0))
            }
            
            // Favorite
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isFavorited.toggle()
                }
                
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }) {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isFavorited ? .red.opacity(0.8) : .black.opacity(0.3))
                    .scaleEffect(isFavorited ? 1.1 : 1.0)
            }
            
            // Info
            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.black.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Modern Vertical Card (Replaces SharedVerticalAnimeCard)
struct SharedVerticalAnimeCard: View {
    let anime: Anime
    let showBadge: Bool
    let tap: () -> Void
    
    @State private var isPressed = false
    @State private var isExpanded = false
    @State private var isFavorited = false
    @State private var isInList = false
    @State private var showDetail = false
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    
    init(anime: Anime, showBadge: Bool = true, tap: @escaping () -> Void) {
        self.anime = anime
        self.showBadge = showBadge
        self.tap = tap
    }
    
    private var isNew: Bool {
        // Check if added in last 7 days
        let createdAt = anime.createdAt
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return createdAt > sevenDaysAgo
    }
    
    private var isTrending: Bool {
        return anime.popularity ?? 0 > 10000
    }
    
    private var imageSection: some View {
        KuroCachedAsyncImage(url: URL(string: anime.coverImageLarge ?? anime.coverImageMedium ?? ""), maxPixelSize: 520) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color.black.opacity(0.04))
                    .overlay(ProgressView().scaleEffect(0.6).tint(.black.opacity(0.3)))
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .clear, .black.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            case .failure:
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(.black.opacity(0.2))
                    )
            @unknown default:
                EmptyView()
            }
        }
        .aspectRatio(2/3, contentMode: .fill)
        .clipped()
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(anime.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.black.opacity(0.95))
                .lineLimit(isExpanded ? nil : 2)
                .animation(.easeInOut(duration: 0.2), value: isExpanded)

            HStack(spacing: 8) {
                if let year = anime.seasonYear {
                    Label(String(year), systemImage: "calendar")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.black.opacity(0.6))
                }

                if let episodes = anime.episodeCount, episodes > 0 {
                    Label("\(episodes) ep", systemImage: "play.rectangle")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.black.opacity(0.6))
                }
            }
            .labelStyle(CompactLabelStyle())

            if isExpanded {
                expandedContent
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var expandedContent: some View {

        QuickActionBar(
            isFavorited: $isFavorited,
            isInList: $isInList,
            onInfo: {
                guard !suppressCardTaps else { return }
                showDetail = true
                tap()
            },
            onAdd: {
                if isInList {
                    Task { await supabaseService.addToList(mediaId: anime.id, mediaType: "anime", status: .planning) }
                } else {
                    Task { await supabaseService.removeFromList(mediaId: anime.id, mediaType: "anime") }
                }
            }
        )
        .padding(.top, 8)
        .transition(.scale.combined(with: .opacity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image Container with modern styling
            ZStack(alignment: .topTrailing) {
                imageSection

                // Smart Badges
                if showBadge {
                    VStack {
                        HStack {
                            Spacer()
                            SmartBadge(
                                score: anime.averageScore.map { Double($0) / 10.0 },
                                isNew: isNew,
                                isTrending: isTrending
                            )
                            .padding(8)
                        }
                        Spacer()
                    }
                }

                // Status Indicator (if in collection)
                if isInList {
                    VStack {
                        HStack {
                            Image(systemName: CardStatus.watching.icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(
                                    Circle()
                                        .fill(CardStatus.watching.color)
                                        .background(Circle().fill(.ultraThinMaterial))
                                )
                                .padding(8)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            cardContent
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 10)
                .shadow(color: .black.opacity(0.02), radius: 5, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .opacity(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
            
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .sheet(isPresented: $showDetail) {
            AnimeDetailView(anime: anime)
        }
        .onAppear {
            isInList = supabaseService.isInCollection(anime.id)
            isFavorited = supabaseService.isFavorited(anime.id)
        }
    }
}

// MARK: - Modern Horizontal Card (Replaces SharedHorizontalAnimeCard)
struct SharedHorizontalAnimeCard: View {
    let anime: Anime
    let width: CGFloat
    let height: CGFloat
    let showBadge: Bool
    let tap: () -> Void
    
    @State private var isPressed = false
    @State private var showActions = false
    @State private var didLongPress = false
    @State private var didDrag = false
    @State private var isFavorited = false
    @State private var isInList = false
    @Environment(SupabaseService.self) private var supabaseService
    
    init(anime: Anime, width: CGFloat, height: CGFloat, showBadge: Bool = true, tap: @escaping () -> Void) {
        self.anime = anime
        self.width = width
        self.height = height
        self.showBadge = showBadge
        self.tap = tap
    }
    
    private var horizontalImageView: some View {
        KuroCachedAsyncImage(url: URL(string: anime.coverImageLarge ?? anime.coverImageMedium ?? ""), maxPixelSize: 520) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color.black.opacity(0.04))
                    .overlay(ProgressView().scaleEffect(0.6).tint(.black.opacity(0.3)))
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundColor(.black.opacity(0.2))
                    )
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var horizontalContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(anime.displayTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.black.opacity(0.95))
                .lineLimit(2)

            HStack(spacing: 6) {
                if let year = anime.seasonYear {
                    Text(String(year))
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.black.opacity(0.6))
                }

                if anime.seasonYear != nil && anime.episodeCount != nil {
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 2, height: 2)
                }

                if let episodes = anime.episodeCount {
                    Text("\(episodes) ep")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.black.opacity(0.6))
                }
            }

            if showActions {
                horizontalActions
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var horizontalActions: some View {
        HStack(spacing: 12) {
            Button(action: {
                isInList.toggle()
                if isInList {
                    Task { await supabaseService.addToList(mediaId: anime.id, mediaType: "anime", status: .planning) }
                } else {
                    Task { await supabaseService.removeFromList(mediaId: anime.id, mediaType: "anime") }
                }
                KuroAccessibility.impactHaptic(.light)
            }) {
                Image(systemName: isInList ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 14))
                    .foregroundColor(isInList ? .green.opacity(0.8) : .black.opacity(0.5))
            }

            Button(action: {
                isFavorited.toggle()
                supabaseService.toggleFavorite(for: anime.id)
                KuroAccessibility.impactHaptic(.light)
            }) {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 14))
                    .foregroundColor(isFavorited ? .red.opacity(0.8) : .black.opacity(0.3))
            }
        }
        .padding(.top, 4)
        .transition(.scale.combined(with: .opacity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image with modern overlay
            ZStack(alignment: .topTrailing) {
                horizontalImageView
                
                // Smart Badge
                if showBadge, let score = anime.averageScore {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                Text(String(format: "%.1f", Double(score) / 10.0))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(scoreColor(for: Double(score) / 10.0))
                                    .background(
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                    )
                            )
                            .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            horizontalContent
        }
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 15, x: 0, y: 8)
                .shadow(color: .black.opacity(0.02), radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                )
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .opacity(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        // Intentional tap: if the user is swiping, do not open the detail sheet accidentally.
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 {
                        didDrag = true
                    }
                }
                .onEnded { value in
                    defer { didDrag = false }
                    guard !didLongPress else { return }
                    guard !didDrag else { return }
                    // Treat as a tap only if there was essentially no movement.
                    if abs(value.translation.width) < 10 && abs(value.translation.height) < 10 {
                        KuroAccessibility.impactHaptic(.light)
                        tap()
                    }
                }
        )
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: .infinity, pressing: { pressing in
            if pressing {
                isPressed = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    showActions = true
                }
                didLongPress = true
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            } else {
                isPressed = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showActions = false
                    }
                }
                // Release long-press suppression after the interaction settles.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    didLongPress = false
                }
            }
        }, perform: {})
        .onAppear {
            isInList = supabaseService.isInCollection(anime.id)
            isFavorited = supabaseService.isFavorited(anime.id)
        }
    }
    
    private func scoreColor(for score: Double) -> Color {
        switch score {
        case 9.0...: return .green.opacity(0.9)
        case 7.0..<9.0: return .blue.opacity(0.9)
        case 5.0..<7.0: return .orange.opacity(0.9)
        default: return .red.opacity(0.9)
        }
    }
}

// MARK: - Helper Label Style
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 9))
            configuration.title
        }
    }
}

// MARK: - Manga Card Support (using same components)
typealias SharedVerticalMangaCard = SharedVerticalAnimeCard
typealias SharedHorizontalMangaCard = SharedHorizontalAnimeCard
