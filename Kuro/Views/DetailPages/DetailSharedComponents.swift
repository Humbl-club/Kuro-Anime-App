import KuroCore
import SwiftUI

// MARK: - Detail page shared chrome
// The sections and chrome the Anime and Manga detail pages both render, in one place so an edit to
// one page file cannot break the other: the hero scroll-offset preference key, synopsis, genres,
// sub-genre chips, the section utility button, the back button and the credits/ladder skeletons.
// The page-specific sections (hero, title, units, actions, similar) stay in AnimeDetailView.swift
// and MangaDetailView.swift, so the two designs remain distinct.

// MARK: - Detail copy (EN/DE)
// The detail pages' shared vocabulary: catalogue formats and release states, list-status words,
// unit counts and the "unknown" fallback. Pure (an explicit `german` flag, testable); views pass
// `KuroLocale.isGerman`. Source text is sentence case; kicker lines upper-case it with `.textCase`.
enum DetailCopy {
    /// A catalogue format ("TV", "MOVIE", "LIGHT_NOVEL") as a reader-facing word; nil when empty.
    /// Codes Discover names use Discover's words (`DiscoverFrameCopy.formatName`), so a title reads the
    /// same on Discover and on its detail page; only the codes Discover does not name are worded here.
    static func format(_ raw: String?, german: Bool) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        switch raw.uppercased() {
        case "TV", "TV_SHORT", "MOVIE", "OVA", "ONA", "SPECIAL", "MUSIC", "MANGA", "NOVEL", "ONE_SHOT":
            return DiscoverFrameCopy.formatName(raw, german: german)
        case "LIGHT_NOVEL": return german ? "Light Novel" : "Light novel"
        default: return raw.replacingOccurrences(of: "_", with: " ").lowercased().capitalizedFirstLetter
        }
    }

    /// A catalogue release state ("FINISHED", "RELEASING") as a reader-facing word; nil when empty.
    static func releaseStatus(_ raw: String?, german: Bool) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        switch raw.uppercased() {
        case "FINISHED": return german ? "Abgeschlossen" : "Finished"
        case "RELEASING": return german ? "Laufend" : "Ongoing"
        case "NOT_YET_RELEASED": return german ? "Noch nicht erschienen" : "Not yet released"
        case "CANCELLED": return german ? "Eingestellt" : "Cancelled"
        case "HIATUS": return german ? "Pausiert" : "On hiatus"
        default: return raw.replacingOccurrences(of: "_", with: " ").lowercased().capitalizedFirstLetter
        }
    }

    /// Whose status a word describes. The Collection's German words are first person ("Schaue ich"),
    /// right for the viewer's own row and wrong next to a friend's or another member's name.
    enum Perspective {
        case own
        case other
    }

    /// A raw list status from a club or friend row ("CURRENT", "READING", "ON_HOLD") as a status word
    /// for the medium; nil for an unknown value. `.own` uses the Collection's `FolioStatus` words;
    /// `.other` uses third person in German ("Schaut" / "Liest"); English is the same for both.
    static func listStatus(_ raw: String, medium: MediaKind, german: Bool, perspective: Perspective) -> String? {
        guard let folio = folioStatus(raw) else { return nil }
        if german, perspective == .other, folio == .watching {
            return medium == .manga ? "Liest" : "Schaut"
        }
        return folio.title(medium: medium, german: german)
    }

    /// A club aggregate part ("3 Watching" / "3 schauen", "1 abgeschlossen"): a count of other members
    /// with one status. German uses the plural verb or lower-case participle after the number.
    static func statusCount(_ count: Int, status: FolioStatus, medium: MediaKind, german: Bool) -> String {
        guard german else { return "\(count) \(status.title(medium: medium, german: false))" }
        let word: String
        switch status {
        case .watching:
            if medium == .manga {
                word = count == 1 ? "liest" : "lesen"
            } else {
                word = count == 1 ? "schaut" : "schauen"
            }
        case .planned: word = "geplant"
        case .completed: word = "abgeschlossen"
        case .paused: word = "pausiert"
        case .dropped: word = "abgebrochen"
        }
        return "\(count) \(word)"
    }

    private static func folioStatus(_ raw: String) -> FolioStatus? {
        switch raw.uppercased() {
        case "CURRENT", "WATCHING", "READING", "REPEATING": return .watching
        case "PLANNING", "PLANNED": return .planned
        case "COMPLETED": return .completed
        case "PAUSED", "ON_HOLD": return .paused
        case "DROPPED": return .dropped
        default: return nil
        }
    }

    static func episodes(_ count: Int, german: Bool) -> String {
        german ? "\(count) \(count == 1 ? "Folge" : "Folgen")" : "\(count) \(count == 1 ? "ep" : "eps")"
    }

    static func chapters(_ count: Int, german: Bool) -> String {
        german ? "\(count) Kap." : "\(count) ch"
    }

    static func volumes(_ count: Int, german: Bool) -> String {
        german ? "\(count) \(count == 1 ? "Band" : "Bände")" : "\(count) vol"
    }

    /// A character role ("MAIN", "SUPPORTING") as a reader-facing word; other roles keep their text.
    static func characterRole(_ raw: String, german: Bool) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.uppercased() {
        case "": return nil
        case "MAIN": return german ? "Hauptrolle" : "Main"
        case "SUPPORTING": return german ? "Nebenrolle" : "Supporting"
        case "BACKGROUND": return german ? "Statist" : "Background"
        default: return trimmed
        }
    }

    static func unknown(german: Bool) -> String {
        german ? "Unbekannt" : "Unknown"
    }
}

private extension String {
    /// "light novel" -> "Light novel" (sentence case for an unmapped catalogue value).
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Sheet close control
/// The one close control of the detail pages' sheets (rulebook §7): "Close" / "Schließen", meta size,
/// ink, with a 44 pt target.
struct DetailSheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(KuroLocale.text("Close", "Schließen"))
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInk)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
    }
}

// MARK: - Action dock
/// The detail action dock's one button shape (rulebook §7): a 48 pt capsule, or a 48 pt circle for an
/// icon. `.primary` is the ink fill (one per dock), `.secondary` the hairline stroke on the page colour.
/// Buttons use `KuroPressStyle`; an action that is not available is hidden, never greyed.
struct DetailDockCapsule<Content: View>: View {
    enum Role {
        case primary
        case secondary
    }

    let role: Role
    var iconOnly: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(.kuroMeta(weight: .semibold))
            .foregroundStyle(role == .primary ? Color.kuroWhite : Color.kuroInk)
            .lineLimit(1)
            .padding(.horizontal, iconOnly ? 0 : KuroDesignSpacing.md)
            .frame(minWidth: 48, minHeight: 48)
            .background(Capsule(style: .continuous).fill(role == .primary ? Color.kuroInk : Color.kuroBackground))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(role == .primary ? Color.clear : Color.kuroBlack12, lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
    }
}

/// How much of a dock button's label fits: glyph and word, the word alone, or the glyph alone.
enum DetailDockLabelForm {
    case full
    case text
    case icon
}

struct DetailDockLabel: View {
    let form: DetailDockLabelForm
    let systemImage: String
    let title: String

    var body: some View {
        switch form {
        case .full:
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
        case .text:
            Text(title)
        case .icon:
            Image(systemName: systemImage)
        }
    }
}

/// The dock's bar: opaque page colour with a top hairline, reaching under the home indicator, so
/// scrolled content never shows through. Used inside `.safeAreaInset(edge: .bottom)`, which reserves
/// the dock's height (plus the safe area) at the end of the scroll content.
struct DetailDockBar<Content: View>: View {
    let horizontalPadding: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(
                Color.kuroBackground
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.kuroBlack08)
                            .frame(height: 0.5)
                    }
                    .ignoresSafeArea(edges: .bottom)
            )
    }
}

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
            Text(KuroLocale.text("SYNOPSIS", "INHALT"))
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
                    Text(showFull ? KuroLocale.text("SHOW LESS", "WENIGER") : KuroLocale.text("READ MORE", "MEHR LESEN"))
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
            Text(KuroLocale.text("GENRES", "GENRES"))
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
                                Capsule().stroke(Color.kuroHairline, lineWidth: 0.7)
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
                .foregroundColor(.kuroInkQuiet)
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
                        .font(.kuroCustom(14, weight: .medium, maxSize: 22))
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
                .fill(Color.kuroBlack06)
                .frame(width: 40, height: 10)
                .kuroShimmer()

            // Circle avatars row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle()
                            .fill(Color.kuroBlack06)
                            .frame(width: 64, height: 64)
                            .kuroShimmer()
                    }
                }
            }

            // "PRODUCTION" caption placeholder
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.kuroBlack06)
                .frame(width: 80, height: 10)
                .kuroShimmer()

            // Text line placeholders
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.kuroBlack05)
                .frame(width: 180, height: 12)
                .kuroShimmer()

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.kuroBlack05)
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
                .fill(Color.kuroBlack06)
                .frame(width: 100, height: 10)
                .kuroShimmer()

            // Body text placeholder
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.kuroBlack04)
                .frame(width: 220, height: 14)
                .kuroShimmer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
