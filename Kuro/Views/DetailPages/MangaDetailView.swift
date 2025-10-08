import SwiftUI

// MARK: - MANGA DETAIL VIEW - iOS 26 Mobile-First
// Comprehensive manga detail page with elegant minimalism

struct MangaDetailView: View {
    let manga: Manga
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var scrollOffset: CGFloat = 0
    @State private var showFullDescription = false
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero Section with Parallax Effect
                    MangaHeroSection(manga: manga, geometry: geometry, scrollOffset: $scrollOffset)
                    
                    // Content Section
                    VStack(spacing: KuroSpacing.adaptive(KuroSpacing.xl, for: geometry.size.width)) {
                        // Title & Quick Info
                        MangaTitleSection(manga: manga)
                        
                        // Stats Grid
                        MangaStatsGrid(manga: manga)
                        
                        // Description
                        DescriptionSection(
                            description: manga.displayDescription,
                            showFull: $showFullDescription
                        )
                        
                        // Genres
                        if let genres = manga.genreList, !genres.isEmpty {
                            GenresSection(genres: genres)
                        }
                        
                        // Chapters Section (if available)
                        if let chapterCount = manga.chapterCount {
                            ChaptersSection(manga: manga, chapterCount: chapterCount)
                        }
                        
                        // Volumes Section (if available)
                        if let volumeCount = manga.volumeCount {
                            VolumesSection(manga: manga, volumeCount: volumeCount)
                        }
                        
                        // Action Buttons
                        MangaActionButtons(manga: manga)
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

// MARK: - Manga Hero Section
struct MangaHeroSection: View {
    let manga: Manga
    let geometry: GeometryProxy
    @Binding var scrollOffset: CGFloat
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Cover Image with Parallax
            AsyncImage(url: URL(string: manga.displayImage)) { image in
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
                KuroStyle.mediaBadge("MANGA", isAnime: false)
            }
            .padding(.horizontal, ResponsiveLayout.padding())
            .padding(.bottom, KuroSpacing.lg)
        }
        .frame(height: ResponsiveLayout.imageHeight(400))
    }
}

// MARK: - Manga Title Section
struct MangaTitleSection: View {
    let manga: Manga
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            // Japanese/Native Title
            if let nativeTitle = manga.titleNative {
                Text(nativeTitle)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            // Main Title
            Text(manga.displayTitle.uppercased())
                .font(.system(size: ResponsiveLayout.fontSize(24), weight: .ultraLight, design: .serif))
                .tracking(0.5)
                .foregroundColor(.kuroBlack)
                .lineSpacing(4)
            
            // Year & Format
            HStack(spacing: KuroSpacing.sm) {
                Text(manga.year)
                    .font(.kuroMicro(weight: .regular))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack60)
                
                if let format = manga.format {
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

// MARK: - Manga Stats Grid
struct MangaStatsGrid: View {
    let manga: Manga
    
    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: KuroSpacing.md
        ) {
            if let score = manga.averageScore {
                StatCard(
                    label: "SCORE",
                    value: String(format: "%.1f", Double(score) / 10.0),
                    icon: "star.fill"
                )
            }
            
            if let chapters = manga.chapterCount {
                StatCard(
                    label: "CHAPTERS",
                    value: "\(chapters)",
                    icon: "book.fill"
                )
            }
            
            if let volumes = manga.volumeCount {
                StatCard(
                    label: "VOLUMES",
                    value: "\(volumes)",
                    icon: "books.vertical.fill"
                )
            }
        }
    }
}

// MARK: - Chapters Section
struct ChaptersSection: View {
    let manga: Manga
    let chapterCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text("CHAPTERS")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack80)
                
                Spacer()
                
                Text("\(chapterCount) TOTAL")
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            // Chapter list placeholder
            VStack(spacing: KuroSpacing.sm) {
                ForEach(1...min(chapterCount, 5), id: \.self) { chapter in
                    ChapterRow(chapterNumber: chapter)
                }
                
                if chapterCount > 5 {
                    Button(action: {
                        // Navigate to full chapter list
                        KuroAccessibility.impactHaptic(.light)
                    }) {
                        HStack {
                            Text("VIEW ALL \(chapterCount) CHAPTERS")
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

// MARK: - Chapter Row
struct ChapterRow: View {
    let chapterNumber: Int
    
    var body: some View {
        HStack {
            Text("CH \(chapterNumber)")
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

// MARK: - Volumes Section
struct VolumesSection: View {
    let manga: Manga
    let volumeCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text("VOLUMES")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack80)
                
                Spacer()
                
                Text("\(volumeCount) TOTAL")
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            // Volume grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: KuroSpacing.md
            ) {
                ForEach(1...min(volumeCount, 6), id: \.self) { volume in
                    VolumeCard(volumeNumber: volume)
                }
            }
            
            if volumeCount > 6 {
                Button(action: {
                    // Navigate to full volume list
                    KuroAccessibility.impactHaptic(.light)
                }) {
                    HStack {
                        Text("VIEW ALL \(volumeCount) VOLUMES")
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Volume Card
struct VolumeCard: View {
    let volumeNumber: Int
    
    var body: some View {
        VStack(spacing: KuroSpacing.xs) {
            Image(systemName: "book.fill")
                .font(.kuroBody())
                .foregroundColor(.kuroBlack30)
            
            Text("VOL \(volumeNumber)")
                .font(.kuroMicro(weight: .medium))
                .tracking(0.5)
                .foregroundColor(.kuroBlack80)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KuroSpacing.lg)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
    }
}

// MARK: - Manga Action Buttons
struct MangaActionButtons: View {
    let manga: Manga
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
                AddToListSheet(media: manga)
            }
            
            // Secondary Actions
            HStack(spacing: KuroSpacing.md) {
                SecondaryActionButton(icon: "heart", label: "FAVORITE")
                SecondaryActionButton(icon: "square.and.arrow.up", label: "SHARE")
            }
        }
    }
}
