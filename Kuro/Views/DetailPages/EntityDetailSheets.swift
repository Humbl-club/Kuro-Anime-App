import SwiftUI

// MARK: - Entity Sort Mode

enum EntitySortMode: String, CaseIterable {
    case rating = "RATING"
    case year = "YEAR"
}

enum EntityWorkIdentity {
    static func make(media: Media, role: String?, index: Int) -> String {
        "\(media.stableKey)-\(role ?? "none")-\(index)"
    }
}

// MARK: - Character Detail Sheet

struct CharacterDetailSheet: View {
    let character: Character
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var works: [Media] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating

    private var sortedWorks: [Media] {
        switch sortMode {
        case .rating:
            return works.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .year:
            let yearVal: (Media) -> Int = { Int($0.year) ?? 0 }
            return works.sorted { yearVal($0) > yearVal($1) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: KuroSpacing.lg) {
                    EntityHeroSection(
                        imageURL: character.imageLarge,
                        isCircle: true,
                        name: character.nameFull ?? "Unknown",
                        nameNative: character.nameNative,
                        metadataLines: characterMetadata
                    )

                    EntityWorksRail(
                        title: "APPEARS IN",
                        items: sortedWorks.map { (media: $0, role: nil as String?) },
                        isLoading: isLoading,
                        sortMode: $sortMode
                    )
                }
                .padding(.horizontal, ResponsiveLayout.padding())
                .padding(.vertical, KuroSpacing.lg)
            }
            .background(Color.kuroBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.kuroBlack80)
                }
            }
        }
        .task {
            works = await supabaseService.fetchMediaByCharacter(characterId: character.id)
            isLoading = false
        }
    }

    private var characterMetadata: [String] {
        var lines: [String] = []
        if let gender = character.gender, !gender.isEmpty {
            lines.append(gender.uppercased())
        }
        if let age = character.age, !age.isEmpty {
            lines.append("AGE \(age)")
        }
        return lines
    }
}

// MARK: - Staff Detail Sheet

struct StaffDetailSheet: View {
    let staff: Staff
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var works: [(media: Media, role: String)] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating

    private var sortedWorks: [(media: Media, role: String)] {
        switch sortMode {
        case .rating:
            return works.sorted { ($0.media.rating ?? 0) > ($1.media.rating ?? 0) }
        case .year:
            let yearVal: ((media: Media, role: String)) -> Int = { Int($0.media.year) ?? 0 }
            return works.sorted { yearVal($0) > yearVal($1) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: KuroSpacing.lg) {
                    EntityHeroSection(
                        imageURL: staff.imageLarge,
                        isCircle: true,
                        name: staff.nameFull ?? "Unknown",
                        nameNative: staff.nameNative,
                        metadataLines: [],
                        occupations: staff.primaryOccupations
                    )

                    EntityWorksRail(
                        title: "FILMOGRAPHY",
                        items: sortedWorks.map { (media: $0.media, role: $0.role as String?) },
                        isLoading: isLoading,
                        sortMode: $sortMode
                    )
                }
                .padding(.horizontal, ResponsiveLayout.padding())
                .padding(.vertical, KuroSpacing.lg)
            }
            .background(Color.kuroBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.kuroBlack80)
                }
            }
        }
        .task {
            works = await supabaseService.fetchAnimeByStaff(staffId: staff.id)
            isLoading = false
        }
    }
}

// MARK: - Author Detail Sheet

struct AuthorDetailSheet: View {
    let author: Author
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var works: [(media: Media, role: String)] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating

    private var sortedWorks: [(media: Media, role: String)] {
        switch sortMode {
        case .rating:
            return works.sorted { ($0.media.rating ?? 0) > ($1.media.rating ?? 0) }
        case .year:
            let yearVal: ((media: Media, role: String)) -> Int = { Int($0.media.year) ?? 0 }
            return works.sorted { yearVal($0) > yearVal($1) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: KuroSpacing.lg) {
                    EntityHeroSection(
                        imageURL: author.imageLarge,
                        isCircle: true,
                        name: author.nameFull ?? "Unknown",
                        nameNative: author.nameNative,
                        metadataLines: []
                    )

                    EntityWorksRail(
                        title: "WORKS",
                        items: sortedWorks.map { (media: $0.media, role: $0.role as String?) },
                        isLoading: isLoading,
                        sortMode: $sortMode
                    )
                }
                .padding(.horizontal, ResponsiveLayout.padding())
                .padding(.vertical, KuroSpacing.lg)
            }
            .background(Color.kuroBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.kuroBlack80)
                }
            }
        }
        .task {
            works = await supabaseService.fetchMangaByAuthor(authorId: author.id)
            isLoading = false
        }
    }
}

// MARK: - Studio Detail Sheet

struct StudioDetailSheet: View {
    let studio: Studio
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService
    @State private var works: [Media] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating

    private var sortedWorks: [Media] {
        switch sortMode {
        case .rating:
            return works.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .year:
            let yearVal: (Media) -> Int = { Int($0.year) ?? 0 }
            return works.sorted { yearVal($0) > yearVal($1) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: KuroSpacing.lg) {
                    VStack(spacing: KuroSpacing.sm) {
                        Text((studio.name ?? "Unknown").uppercased())
                            .font(.kuroDisplay())
                            .foregroundColor(.kuroBlack80)
                            .multilineTextAlignment(.center)

                        if studio.isAnimationStudio == true {
                            Text("ANIMATION STUDIO")
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.4)
                                .foregroundColor(.kuroTextSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.black.opacity(0.06))
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, KuroSpacing.lg)

                    EntityWorksRail(
                        title: "PRODUCTIONS",
                        items: sortedWorks.map { (media: $0, role: nil as String?) },
                        isLoading: isLoading,
                        sortMode: $sortMode
                    )
                }
                .padding(.horizontal, ResponsiveLayout.padding())
                .padding(.vertical, KuroSpacing.lg)
            }
            .background(Color.kuroBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.kuroBlack80)
                }
            }
        }
        .task {
            works = await supabaseService.fetchAnimeByStudio(studioId: studio.id)
            isLoading = false
        }
    }
}

// MARK: - Shared Entity Hero Section

struct EntityHeroSection: View {
    let imageURL: String?
    var isCircle: Bool = true
    let name: String
    let nameNative: String?
    var metadataLines: [String] = []
    var occupations: [String]? = nil

    var body: some View {
        VStack(spacing: KuroSpacing.md) {
            if let urlStr = imageURL, let url = URL(string: urlStr) {
                KuroCachedAsyncImage(url: url, maxPixelSize: 120) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        heroPlaceholder
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
            } else {
                heroPlaceholder
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
            }

            VStack(spacing: 4) {
                Text(name)
                    .font(.kuroHeadline())
                    .foregroundColor(.kuroBlack80)
                    .multilineTextAlignment(.center)

                if let native = nameNative, !native.isEmpty {
                    Text(native)
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroTextTertiary)
                }

                if !metadataLines.isEmpty {
                    Text(metadataLines.joined(separator: " · "))
                        .font(.kuroMicro(weight: .light))
                        .tracking(1.0)
                        .foregroundColor(.kuroTextSecondary)
                }

                if let occupations, !occupations.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(occupations.prefix(3), id: \.self) { occ in
                            Text(occ.uppercased())
                                .font(.kuroMicro(weight: .medium))
                                .tracking(0.8)
                                .foregroundColor(.kuroTextSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.black.opacity(0.06))
                                )
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, KuroSpacing.lg)
    }

    private var heroPlaceholder: some View {
        Circle()
            .fill(Color.black.opacity(0.06))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.black.opacity(0.2))
            )
    }
}

// MARK: - Shared Entity Works Rail

struct EntityWorksRail: View {
    let title: String
    let items: [(media: Media, role: String?)]
    let isLoading: Bool
    @Binding var sortMode: EntitySortMode

    private var cardWidth: CGFloat { 110 }
    private var identifiedItems: [(id: String, media: Media, role: String?)] {
        items.enumerated().map { index, item in
            (
                id: EntityWorkIdentity.make(media: item.media, role: item.role, index: index),
                media: item.media,
                role: item.role
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text(title)
                    .font(.kuroCaption(weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)

                Spacer()

                HStack(spacing: 0) {
                    ForEach(EntitySortMode.allCases, id: \.self) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.kuroMicro(weight: sortMode == mode ? .semibold : .regular))
                                .tracking(1.0)
                                .foregroundColor(sortMode == mode ? .kuroBlack80 : .kuroTextTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(
                    Capsule().fill(Color.black.opacity(0.04))
                )
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, KuroSpacing.lg)
            } else if items.isEmpty {
                Text("No works found")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.black.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, KuroSpacing.lg)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(identifiedItems, id: \.id) { item in
                            EntityWorkCard(media: item.media, role: item.role, width: cardWidth)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Entity Work Card (wraps KuroCompactCard + optional role subtitle)

struct EntityWorkCard: View {
    let media: Media
    let role: String?
    var width: CGFloat = 110

    var body: some View {
        VStack(spacing: 4) {
            KuroCompactCard(media: media, width: width)

            if let role, !role.isEmpty {
                Text(role.uppercased())
                    .font(.system(size: 8, weight: .regular))
                    .tracking(0.8)
                    .foregroundColor(.kuroTextTertiary)
                    .lineLimit(1)
                    .frame(width: width)
            }
        }
    }
}
