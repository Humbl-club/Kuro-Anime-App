import SwiftUI

// MARK: - ANIME DETAIL VIEW - iOS 26 Mobile-First
// Comprehensive anime detail page with elegant minimalism

struct AnimeDetailView: View {
    let anime: Anime
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var scrollOffset: CGFloat = 0
    @State private var showFullDescription = false
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero Section with Parallax Effect
                    HeroSection(anime: anime, geometry: geometry, scrollOffset: $scrollOffset)
                    
                    // Content Section
                    VStack(spacing: KuroSpacing.adaptive(KuroSpacing.xl, for: geometry.size.width)) {
                        // Title & Quick Info
                        TitleSection(anime: anime)
                        
                        // Stats Grid
                        StatsGrid(anime: anime)
                        
                        // Description
                        DescriptionSection(
                            description: anime.displayDescription,
                            showFull: $showFullDescription
                        )
                        
                        // Genres
                        if let genres = anime.genreList, !genres.isEmpty {
                            GenresSection(genres: genres)
                        }
                        
                        // Episodes Section (if available)
                        if let episodeCount = anime.episodeCount {
                            EpisodesSection(anime: anime, episodeCount: episodeCount)
                        }
                        
                        // Action Buttons
                        ActionButtons(anime: anime)
                    }
                    .padding(.horizontal, ResponsiveLayout.padding())
                    .padding(.top, KuroSpacing.adaptive(KuroSpacing.xl, for: geometry.size.width))
                    .padding(.bottom, KuroSpacing.adaptive(KuroSpacing.xxxl, for: geometry.size.width))
                }
            }
            .background(Color.kuroBackground)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .topLeading) {
                // Custom Back Button
                BackButton(dismiss: dismiss)
                    .padding(.top, KuroScreen.safeAreaTop + KuroSpacing.sm)
                    .padding(.leading, ResponsiveLayout.padding())
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Hero Section with Parallax
struct HeroSection: View {
    let anime: Anime
    let geometry: GeometryProxy
    @Binding var scrollOffset: CGFloat
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Banner/Cover Image with Parallax
            AsyncImage(url: URL(string: anime.bannerImage ?? anime.displayImage)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.kuroBlack08, Color.kuroBlack.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: geometry.size.width, height: ResponsiveLayout.imageHeight(400))
            .clipped()
            .offset(y: scrollOffset * 0.5) // Parallax effect
            
            // Gradient Overlay
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.kuroBackground.opacity(0.8),
                    Color.kuroBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            
            // Media Type Badge
            HStack {
                Spacer()
                KuroStyle.mediaBadge("ANIME", isAnime: true)
            }
            .padding(.horizontal, ResponsiveLayout.padding())
            .padding(.bottom, KuroSpacing.lg)
        }
        .frame(height: ResponsiveLayout.imageHeight(400))
    }
}

// MARK: - Title Section
struct TitleSection: View {
    let anime: Anime
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            // Japanese/Native Title
            if let nativeTitle = anime.titleNative {
                Text(nativeTitle)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            // Main Title
            Text(anime.displayTitle.uppercased())
                .font(.system(size: ResponsiveLayout.fontSize(24), weight: .ultraLight, design: .serif))
                .tracking(0.5)
                .foregroundColor(.kuroBlack)
                .lineSpacing(4)
            
            // Year & Format
            HStack(spacing: KuroSpacing.sm) {
                Text(anime.displayYear)
                    .font(.kuroMicro(weight: .regular))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack60)
                
                if let format = anime.format {
                    Text("•")
                        .foregroundColor(.kuroBlack30)
                    Text(format)
                        .font(.kuroMicro(weight: .light))
                        .tracking(1.0)
                        .foregroundColor(.kuroBlack60)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stats Grid
struct StatsGrid: View {
    let anime: Anime
    
    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: KuroSpacing.md
        ) {
            if let score = anime.averageScore {
                StatCard(
                    label: "SCORE",
                    value: String(format: "%.1f", Double(score) / 10.0),
                    icon: "star.fill"
                )
            }
            
            if let episodes = anime.episodeCount {
                StatCard(
                    label: "EPISODES",
                    value: "\(episodes)",
                    icon: "play.circle.fill"
                )
            }
            
            if let status = anime.status {
                StatCard(
                    label: "STATUS",
                    value: status.capitalized,
                    icon: "circle.fill"
                )
            }
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: KuroSpacing.xs) {
            Image(systemName: icon)
                .font(.kuroMicro())
                .foregroundColor(.kuroBlack30)
            
            Text(value)
                .font(.kuroCardTitle(weight: .light))
                .foregroundColor(.kuroBlack)
            
            Text(label)
                .font(.kuroMicro(weight: .light))
                .tracking(0.5)
                .foregroundColor(.kuroBlack60)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KuroSpacing.lg)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
    }
}

// MARK: - Description Section
struct DescriptionSection: View {
    let description: String
    @Binding var showFull: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            Text("SYNOPSIS")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)
            
            Text(description)
                .font(.kuroBody(weight: .light))
                .tracking(0.5)
                .foregroundColor(.kuroBlack60)
                .lineSpacing(6)
                .lineLimit(showFull ? nil : 4)
            
            if description.count > 200 {
                Button(action: {
                    withAnimation(KuroAnimation.spring) {
                        showFull.toggle()
                    }
                    KuroAccessibility.impactHaptic(.light)
                }) {
                    Text(showFull ? "SHOW LESS" : "READ MORE")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.0)
                        .foregroundColor(.kuroBlack80)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Genres Section
struct GenresSection: View {
    let genres: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            Text("GENRES")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)
            
            FlowLayout(spacing: KuroSpacing.sm) {
                ForEach(genres, id: \.self) { genre in
                    GenreTag(genre: genre)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Genre Tag
struct GenreTag: View {
    let genre: String
    
    var body: some View {
        Text(genre.uppercased())
            .font(.kuroMicro(weight: .light))
            .tracking(0.5)
            .foregroundColor(.kuroBlack60)
            .padding(.horizontal, KuroSpacing.md)
            .padding(.vertical, KuroSpacing.xs)
            .background(
                Capsule()
                    .stroke(Color.kuroBlack.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - Episodes Section
struct EpisodesSection: View {
    let anime: Anime
    let episodeCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text("EPISODES")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack80)
                
                Spacer()
                
                Text("\(episodeCount) TOTAL")
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            // Episode list placeholder
            VStack(spacing: KuroSpacing.sm) {
                ForEach(1...min(episodeCount, 5), id: \.self) { episode in
                    EpisodeRow(episodeNumber: episode)
                }
                
                if episodeCount > 5 {
                    Button(action: {
                        // Navigate to full episode list
                        KuroAccessibility.impactHaptic(.light)
                    }) {
                        HStack {
                            Text("VIEW ALL \(episodeCount) EPISODES")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.0)
                                .foregroundColor(.kuroBlack80)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.kuroMicro())
                                .foregroundColor(.kuroBlack30)
                        }
                        .padding(KuroSpacing.md)
                        .background(Color.kuroBlack08)
                        .cornerRadius(KuroRadius.sm)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Episode Row
struct EpisodeRow: View {
    let episodeNumber: Int
    
    var body: some View {
        HStack {
            Text("EP \(episodeNumber)")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.0)
                .foregroundColor(.kuroBlack80)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.kuroMicro())
                .foregroundColor(.kuroBlack30)
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
    }
}

// MARK: - Action Buttons
struct ActionButtons: View {
    let anime: Anime
    @State private var showAddToList = false
    
    var body: some View {
        VStack(spacing: KuroSpacing.md) {
            // Add to List Button
            Button(action: {
                KuroAccessibility.impactHaptic(.medium)
                showAddToList = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.kuroBody())
                    
                    Text("ADD TO LIST")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.5)
                }
                .foregroundColor(.kuroWhite)
                .frame(maxWidth: .infinity)
                .padding(.vertical, KuroSpacing.lg)
                .background(Color.kuroBlack)
                .cornerRadius(KuroRadius.sm)
            }
            .sheet(isPresented: $showAddToList) {
                AddToListSheet(media: anime)
            }
            
            // Secondary Actions
            HStack(spacing: KuroSpacing.md) {
                SecondaryActionButton(icon: "heart", label: "FAVORITE")
                SecondaryActionButton(icon: "square.and.arrow.up", label: "SHARE")
            }
        }
    }
}

// MARK: - Secondary Action Button
struct SecondaryActionButton: View {
    let icon: String
    let label: String
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.kuroMicro())
                
                Text(label)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
            }
            .foregroundColor(.kuroBlack80)
            .frame(maxWidth: .infinity)
            .padding(.vertical, KuroSpacing.lg)
            .background(Color.kuroBlack08)
            .cornerRadius(KuroRadius.sm)
        }
    }
}

// MARK: - Back Button
struct BackButton: View {
    let dismiss: DismissAction
    
    var body: some View {
        Button(action: {
            KuroAccessibility.impactHaptic(.light)
            dismiss()
        }) {
            Circle()
                .fill(Color.kuroWhite.opacity(0.9))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.kuroBlack)
                )
                .shadow(color: .kuroBlack08, radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Flow Layout Helper
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > width {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                x += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.size = CGSize(width: width, height: y + lineHeight)
        }
    }
}
