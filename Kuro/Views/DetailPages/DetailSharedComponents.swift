import SwiftUI

// MARK: - Detail page shared chrome
// The sections and chrome the Anime and Manga detail pages both render, in one place so an edit to
// one page file cannot break the other: the hero scroll-offset preference key, synopsis, genres,
// sub-genre chips, the section utility button, the back button and the credits/ladder skeletons.
// The page-specific sections (hero, title, units, actions, similar) stay in AnimeDetailView.swift
// and MangaDetailView.swift, so the two designs remain distinct.

// MARK: - Scroll offset (hero parallax)
struct KuroDetailScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Description Section
struct DescriptionSection: View {
    let description: String
    @Binding var showFull: Bool
    var condensedSynopsis: String? = nil

    private var expandedParagraphs: [String] {
        description
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// When collapsed, prefer the FM-condensed hook over raw truncation.
    private var collapsedText: String {
        condensedSynopsis ?? description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            Text("SYNOPSIS")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)

            if showFull && expandedParagraphs.count > 1 {
                VStack(alignment: .leading, spacing: KuroSpacing.md) {
                    ForEach(Array(expandedParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.kuroBody(weight: .regular))
                            .tracking(0.2)
                            .foregroundColor(.kuroBlack80)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(showFull ? description : collapsedText)
                    .font(.kuroBody(weight: .regular))
                    .tracking(0.2)
                    .foregroundColor(.kuroBlack80)
                    .lineSpacing(5)
                    .lineLimit(showFull ? nil : (condensedSynopsis != nil ? nil : 4))
                    .fixedSize(horizontal: false, vertical: true)
            }

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

// MARK: - Minimal tag chips
struct TagChipsSection: View {
    let title: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            Text(title)
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags.prefix(18), id: \.self) { t in
                        Text(t.uppercased())
                            .font(.kuroMicro(weight: .light))
                            .tracking(0.8)
                            .foregroundColor(.kuroBlack60)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().stroke(Color.black.opacity(0.10), lineWidth: 0.7)
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Secondary Action Button
struct DetailSectionUtilityButton: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: KuroSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack80)
                Text(subtitle)
                    .font(.kuroMicro(weight: .light))
                    .foregroundColor(.kuroBlack60)
            }

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

// MARK: - Detail Page Skeleton Placeholders

struct DetailCreditsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            // "CAST" caption placeholder
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(width: 40, height: 10)
                .kuroShimmer()

            // Circle avatars row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 64, height: 64)
                            .kuroShimmer()
                    }
                }
            }

            // "PRODUCTION" caption placeholder
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(width: 80, height: 10)
                .kuroShimmer()

            // Text line placeholders
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(width: 180, height: 12)
                .kuroShimmer()

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(width: 140, height: 12)
                .kuroShimmer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DetailLadderSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            // Caption placeholder
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(width: 100, height: 10)
                .kuroShimmer()

            // Body text placeholder
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(width: 220, height: 14)
                .kuroShimmer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
