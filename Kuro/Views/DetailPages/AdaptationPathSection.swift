import KuroCore
import SwiftUI

struct AdaptationPathSection: View {
    let ladder: MediaLadderResponse
    let mediaType: MediaKind

    @State private var selectedItem: MediaLadderItem?
    @State private var showFullPath = false

    private var source: MediaLadderItem? {
        ladder.primarySource ?? ladder.sourceMaterial.first
    }

    private var adaptation: MediaLadderItem? {
        ladder.primaryAdaptation ?? ladder.adaptations.first
    }

    private var shouldShow: Bool {
        switch mediaType {
        case .anime: return source != nil
        case .manga: return adaptation != nil
        }
    }

    var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                Text(KuroLocale.text("Adaptation path", "Adaptionsweg"))
                    .font(.kuroCaption(weight: .semibold))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundColor(.kuroBlack80)
                    .accessibilityAddTraits(.isHeader)

                FootnoteStatement(
                    ladder: ladder,
                    mediaType: mediaType,
                    source: source,
                    adaptation: adaptation,
                    selectedItem: $selectedItem
                )

                FootnoteMetadataLine(
                    mediaType: mediaType,
                    source: source,
                    adaptation: adaptation
                )

                EditorialLayout.divider()

                FootnoteProse(
                    ladder: ladder,
                    mediaType: mediaType,
                    selectedItem: $selectedItem,
                    showFullPath: $showFullPath
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(item: $selectedItem) { item in
                let kind: MediaKind = item.mediaType.uppercased() == "MANGA" ? .manga : .anime
                MediaDetailSheet(kind: kind, id: item.mediaId)
            }
            .sheet(isPresented: $showFullPath) {
                FranchisePathSheet(ladder: ladder)
            }
        }
    }
}

// MARK: - Statement (26pt serif headline)

private struct FootnoteStatement: View {
    let ladder: MediaLadderResponse
    let mediaType: MediaKind
    let source: MediaLadderItem?
    let adaptation: MediaLadderItem?
    @Binding var selectedItem: MediaLadderItem?

    private var statementText: String {
        switch mediaType {
        case .anime:
            guard let src = source else { return "" }
            if let author = src.sourceAuthorName, !author.isEmpty {
                let format = src.format?.uppercased() ?? ""
                if format == "MANGA" || format == "ONE_SHOT" {
                    return KuroLocale.text("Based on the manga by \(author)", "Nach dem Manga von \(author)")
                } else if format == "NOVEL" || format == "LIGHT_NOVEL" {
                    return KuroLocale.text("Based on the light novel by \(author)", "Nach der Light Novel von \(author)")
                }
            }
            return KuroLocale.text("Based on \(src.title)", "Nach der Vorlage \(src.title)")
        case .manga:
            guard let adpt = adaptation else { return "" }
            let yearStr = adpt.year.map { " (\($0))" } ?? ""
            return KuroLocale.text("Adapted as \(adpt.title)\(yearStr)", "Adaptiert als \(adpt.title)\(yearStr)")
        }
    }

    private var tappableItem: MediaLadderItem? {
        switch mediaType {
        case .anime: return source
        case .manga: return adaptation
        }
    }

    var body: some View {
        if !statementText.isEmpty {
            Button {
                selectedItem = tappableItem
            } label: {
                Text(statementText)
                    .font(.kuroHeadline())
                    .foregroundColor(.kuroBlack80)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(statementText)
        }
    }
}

// MARK: - Micro metadata line

private struct FootnoteMetadataLine: View {
    let mediaType: MediaKind
    let source: MediaLadderItem?
    let adaptation: MediaLadderItem?

    private var metadataParts: [String] {
        let item: MediaLadderItem? = mediaType == .anime ? source : adaptation
        guard let item else { return [] }
        var parts: [String] = [item.title]
        if let year = item.year { parts.append(String(year)) }
        if let formatted = DetailCopy.format(item.format, german: KuroLocale.isGerman) {
            parts.append(formatted)
        }
        if let rating = item.rating {
            let display = rating > 10 ? rating / 10.0 : rating
            parts.append(String(format: "%.1f", display))
        }
        return parts
    }

    var body: some View {
        let parts = metadataParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " \u{00B7} "))
                .font(.kuroMicro(weight: .regular))
                .foregroundColor(.kuroTextTertiary)
                .lineLimit(1)
        }
    }
}

// MARK: - Editorial footnote prose

private struct FootnoteProse: View {
    let ladder: MediaLadderResponse
    let mediaType: MediaKind
    @Binding var selectedItem: MediaLadderItem?
    @Binding var showFullPath: Bool

    private var alternateItem: MediaLadderItem? {
        let primaryId: String? = {
            switch mediaType {
            case .anime:
                return (ladder.primarySource ?? ladder.sourceMaterial.first)?.id
            case .manga:
                return (ladder.primaryAdaptation ?? ladder.adaptations.first)?.id
            }
        }()
        return ladder.adaptations.first(where: { $0.id != primaryId })
    }

    private var franchiseCount: Int {
        if let count = ladder.totalFranchiseCount, count > 0 { return count }
        var ids = Set<String>()
        let allItems = ladder.sourceMaterial + ladder.adaptations + ladder.prequels
            + ladder.sequels + ladder.sideStories + ladder.spinOffs
        for item in allItems { ids.insert(item.id) }
        return ids.count
    }

    private var hasAlternate: Bool { alternateItem != nil }
    private var hasFranchise: Bool { franchiseCount > 2 }

    var body: some View {
        if hasAlternate || hasFranchise {
            FootnoteProseContent(
                alternateItem: alternateItem,
                franchiseCount: hasFranchise ? franchiseCount : nil,
                selectedItem: $selectedItem,
                showFullPath: $showFullPath
            )
        }
    }
}

private struct FootnoteProseContent: View {
    let alternateItem: MediaLadderItem?
    let franchiseCount: Int?
    @Binding var selectedItem: MediaLadderItem?
    @Binding var showFullPath: Bool

    private let german = KuroLocale.isGerman

    /// "a 2015 television series" (EN, with its article) / "Fernsehserie (2015)" (DE, no article needed).
    private func alternateLabel(_ item: MediaLadderItem) -> String {
        let format = item.format?.uppercased() ?? ""
        if german {
            let noun: String
            switch format {
            case "TV": noun = "Fernsehserie"
            case "MOVIE": noun = "Film"
            case "MANGA": noun = "Manga"
            case "NOVEL": noun = "Roman"
            case "LIGHT_NOVEL": noun = "Light Novel"
            default: noun = DetailCopy.format(item.format, german: true) ?? "Adaption"
            }
            return item.year.map { "\(noun) (\($0))" } ?? noun
        }
        let year = item.year.map { "\($0) " } ?? ""
        let label: String
        switch format {
        case "TV": label = "television series"
        case "MOVIE": label = "film"
        case "OVA": label = "OVA"
        case "ONA": label = "ONA"
        case "SPECIAL": label = "special"
        case "MANGA": label = "manga"
        case "NOVEL", "LIGHT_NOVEL": label = "novel"
        default: label = (item.format ?? "adaptation").lowercased()
            .replacingOccurrences(of: "_", with: " ")
        }
        let phrase = "\(year)\(label)"
        let article = phrase.first.map { "aeiouAEIOU".contains($0) } == true ? "an" : "a"
        return "\(article) \(phrase)"
    }

    private var fullPathWords: String { KuroLocale.text("see the full path", "den ganzen Weg ansehen") }

    var body: some View {
        let proseFont = Font.kuroCustom(14, weight: .light, design: .serif, maxSize: 22)
        let linkFont = Font.kuroCustom(14, weight: .medium, design: .serif, maxSize: 22)

        if let alt = alternateItem, let count = franchiseCount {
            let altLabel = alternateLabel(alt)
            let altLink = Text(altLabel)
                .font(linkFont)
                .foregroundColor(.kuroBlack80)
                .underline()
            let fullPathLink = Text(fullPathWords)
                .font(linkFont)
                .foregroundColor(.kuroBlack80)
                .underline()

            (german
                ? Text("Auch adaptiert als \(altLink). Das Franchise umfasst \(count) Titel \u{2014} \(fullPathLink).")
                : Text("Also adapted as \(altLink). The franchise includes \(count) titles \u{2014} \(fullPathLink)."))
                .font(proseFont)
                .foregroundColor(.kuroTextSecondary)
            .onTapGesture { showFullPath = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(german
                ? "Auch adaptiert als \(altLabel). Das Franchise umfasst \(count) Titel. Tippen, um den ganzen Weg zu sehen."
                : "Also adapted as \(altLabel). The franchise includes \(count) titles. Tap to see the full path.")
            .accessibilityAddTraits(.isButton)
        } else if let alt = alternateItem {
            let altLabel = alternateLabel(alt)
            Button {
                selectedItem = alt
            } label: {
                let altLink = Text(altLabel)
                    .font(linkFont)
                    .foregroundColor(.kuroBlack80)
                    .underline()
                (german ? Text("Auch adaptiert als \(altLink).") : Text("Also adapted as \(altLink)."))
                    .font(proseFont)
                    .foregroundColor(.kuroTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(german
                ? "Auch adaptiert als \(altLabel). Tippen zum Ansehen."
                : "Also adapted as \(altLabel). Tap to view.")
        } else if let count = franchiseCount {
            Button {
                showFullPath = true
            } label: {
                let fullPathLink = Text(fullPathWords)
                    .font(linkFont)
                    .foregroundColor(.kuroBlack80)
                    .underline()
                (german
                    ? Text("Das Franchise umfasst \(count) Titel \u{2014} \(fullPathLink).")
                    : Text("The franchise includes \(count) titles \u{2014} \(fullPathLink)."))
                    .font(proseFont)
                    .foregroundColor(.kuroTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(german
                ? "Das Franchise umfasst \(count) Titel. Tippen, um den ganzen Weg zu sehen."
                : "The franchise includes \(count) titles. Tap to see the full path.")
        }
    }
}

// MARK: - Franchise Path Sheet

private struct FranchisePathSheet: View {
    let ladder: MediaLadderResponse
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: MediaLadderItem?

    private var groups: [(label: String, items: [MediaLadderItem])] {
        var result: [(label: String, items: [MediaLadderItem])] = []
        if !ladder.sourceMaterial.isEmpty {
            result.append((KuroLocale.text("Source", "Vorlage"), ladder.sourceMaterial))
        }
        if !ladder.adaptations.isEmpty {
            result.append((KuroLocale.text("Adaptations", "Adaptionen"), ladder.adaptations))
        }
        if !ladder.prequels.isEmpty {
            result.append((KuroLocale.text("Prequels", "Vorgeschichten"), ladder.prequels))
        }
        if !ladder.sequels.isEmpty {
            result.append((KuroLocale.text("Sequels", "Fortsetzungen"), ladder.sequels))
        }
        if !ladder.sideStories.isEmpty {
            result.append((KuroLocale.text("Side stories", "Nebengeschichten"), ladder.sideStories))
        }
        if !ladder.spinOffs.isEmpty {
            result.append((KuroLocale.text("Spin-offs", "Spin-offs"), ladder.spinOffs))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KuroSpacing.lg) {
                    ForEach(groups, id: \.label) { group in
                        FranchisePathGroup(
                            label: group.label,
                            items: group.items,
                            selectedItem: $selectedItem
                        )
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.vertical, KuroSpacing.lg)
            }
            .background(Color.kuroBackground)
            .navigationTitle(KuroLocale.text("Adaptation path", "Adaptionsweg"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DetailSheetCloseButton { dismiss() }
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            let kind: MediaKind = item.mediaType.uppercased() == "MANGA" ? .manga : .anime
            MediaDetailSheet(kind: kind, id: item.mediaId)
        }
    }
}

private struct FranchisePathGroup: View {
    let label: String
    let items: [MediaLadderItem]
    @Binding var selectedItem: MediaLadderItem?

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            Text(label.uppercased())
                .font(.kuroMicro(weight: .medium))
                .tracking(1.4)
                .foregroundColor(.kuroTextSecondary)

            ForEach(items) { item in
                FranchisePathRow(item: item) {
                    selectedItem = item
                }
            }
        }
    }
}

private struct FranchisePathRow: View {
    let item: MediaLadderItem
    let onTap: () -> Void

    private var metadataParts: [String] {
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        if let formatted = DetailCopy.format(item.format, german: KuroLocale.isGerman) {
            parts.append(formatted)
        }
        if let rating = item.rating {
            let display = rating > 10 ? rating / 10.0 : rating
            parts.append(String(format: "%.1f", display))
        }
        return parts
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.kuroBody())
                    .foregroundColor(.kuroBlack80)
                    .multilineTextAlignment(.leading)

                if !metadataParts.isEmpty {
                    Text(metadataParts.joined(separator: " \u{00B7} "))
                        .font(.kuroMicro(weight: .regular))
                        .foregroundColor(.kuroTextTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, KuroSpacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title), \(metadataParts.joined(separator: ", "))")
    }
}

// MARK: - MediaLadderItem conformances for sheet(item:) presentation

extension MediaLadderItem: Hashable {
    static func == (lhs: MediaLadderItem, rhs: MediaLadderItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
