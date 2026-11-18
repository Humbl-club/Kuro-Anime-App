import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Folio rows and shelf frames
// Picture first, title, at most one line (issue frame). Cover and title are ONE detail target; the
// advance key is a separate 44 pt sibling, never nested (rulebook §7, §12). Status is never colour.

/// What a row can do. The host owns every write (`CollectionStore` for +1/Undo, `LibraryActions` otherwise).
struct FolioRowActions {
    var open: (FolioItem) -> Void
    var advance: (FolioItem) -> Void
    var edit: (FolioItem) -> Void
    var classify: (FolioItem) -> Void
    var remove: (FolioItem) -> Void
    var toggleSelection: (FolioItem) -> Void
    /// The key a row shows (nil: none).
    var keyPhase: (FolioItem) -> FolioKeyPhase?
    /// W9: opens the tags-and-lists sheet; nil hides the menu item (switch off, or owners absent).
    var organise: ((FolioItem) -> Void)? = nil
}

extension FolioKeyPhase {
    var advanceKeyPhase: KuroAdvanceKey.Phase {
        switch self {
        case .advance: return .advance
        case .caughtUp: return .caughtUp
        case .needsChoice: return .needsChoice
        case .pending: return .pending
        }
    }
}

/// Shared VoiceOver copy of one row.
@MainActor
enum FolioAccessibility {
    static func label(_ item: FolioItem, german: Bool) -> String {
        var parts = [item.media.title]
        parts.append(item.status.title(medium: item.media.kind, german: german))
        if let position = FolioPolicy.positionLine(medium: item.media.kind, progress: item.progress, total: item.total, german: german) {
            parts.append(position)
        }
        if let next = item.next, next.isDisplayable {
            parts.append(ReleaseCopy.current().accessibilityLine(next))
        }
        if item.entry.status == .completed, let verdict = item.entry.verdict {
            parts.append(verdict.name(german: german))
        }
        if let group = item.group {
            if let label = group.label { parts.append(label) }
            parts.append(german ? "\(group.members.count) Staffeln" : "\(group.members.count) seasons")
        }
        return parts.joined(separator: ", ")
    }

    static func keyLabel(_ item: FolioItem, phase: FolioKeyPhase, german: Bool) -> String {
        switch phase {
        case .caughtUp:
            return KuroAdvanceCopy.caughtUpLabel(title: item.media.title, german: german)
        case .needsChoice:
            return german ? "Nächsten Teil von \(item.media.title) wählen" : "Choose the next unit of \(item.media.title)"
        case .advance, .pending:
            return KuroAdvanceCopy.label(medium: item.media.kind, nextUnit: item.progress + 1, title: item.media.title,
                                         current: item.progress, total: item.total, german: german)
        }
    }
}

// MARK: - Context menu

private struct FolioContextMenu: ViewModifier {
    let item: FolioItem
    let actions: FolioRowActions
    let enabled: Bool

    func body(content: Content) -> some View {
        let german = KuroLocale.isGerman
        // A group row acts on its display season only, and the menu names it ("Edit S2").
        let section = item.group?.members.first { $0.item.key == item.key }?.sectionLabel
        content.contextMenu {
            if enabled {
                Button { actions.open(item) } label: {
                    Label(german ? "Öffnen" : "Open", systemImage: "arrow.up.right")
                }
                Button { actions.edit(item) } label: {
                    Label(section.map { FolioGroupCopy.menuEdit(section: $0, german: german) }
                          ?? (german ? "Eintrag bearbeiten" : "Edit entry"), systemImage: "slider.horizontal.3")
                }
                Button { actions.classify(item) } label: {
                    Label(section.map { FolioGroupCopy.menuClassify(section: $0, german: german) }
                          ?? (german ? "Schnell einordnen" : "Quick classify"), systemImage: "tag")
                }
                if let organise = actions.organise {
                    Button { organise(item) } label: {
                        Label(OrganiseCopy.string(.tagsAndLists, german: german), systemImage: "tag.circle")
                    }
                }
                Button(role: .destructive) { actions.remove(item) } label: {
                    Label(section.map { FolioGroupCopy.menuRemove(section: $0, german: german) }
                          ?? (german ? "Aus der Liste entfernen" : "Remove from list"), systemImage: "trash")
                }
            }
        }
    }
}

private struct FolioSelectionMark: View {
    let selected: Bool

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.kuroCustom(22, relativeTo: .title3, maxSize: 30))
            .foregroundStyle(selected ? Color.kuroInk : Color.kuroWhite)
            .background(Circle().fill(selected ? Color.kuroWhite : Color.kuroInk.opacity(0.35)).padding(2))
            .accessibilityHidden(true)
    }
}

/// Artwork with stable geometry: missing or failed art keeps its frame in `kuroMissingArt`.
struct FolioArtwork: View {
    let url: String?
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 3
    var maxPixelSize: Int = 480
    /// Top-biased crop for covers shown in a non-cover ratio (rulebook §6).
    var topBiased: Bool = false

    var body: some View {
        KuroCachedAsyncImage(url: URL(string: url ?? ""), maxPixelSize: maxPixelSize) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height, alignment: topBiased ? .top : .center)
                    .clipped()
            default:
                Rectangle().fill(Color.kuroMissingArt)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.kuroHairline, lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Shelf

/// Equal manga covers or shallow anime scenes in adaptive columns.
struct FolioShelf: View {
    let items: [FolioItem]
    let medium: MediaKind
    let width: CGFloat
    let isSelecting: Bool
    let selectedKeys: Set<String>
    let actions: FolioRowActions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.kuroFoldMemory) private var folds

    var body: some View {
        let gutter = FolioPolicy.gutter(forWidth: width)
        let spacing: CGFloat = medium == .manga ? 12 : 16
        let content = max(0, width - gutter * 2)
        let columns = FolioPolicy.shelfColumns(width: content, medium: medium,
                                               accessibilitySize: dynamicTypeSize.isAccessibilitySize, spacing: spacing)
        let cellWidth = floor((content - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let gridColumns = Array(repeating: GridItem(.fixed(max(1, cellWidth)), spacing: spacing, alignment: .top), count: columns)
        let rowSpacing: CGFloat = medium == .manga ? 20 : 24
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let expanded = Set(items.compactMap { item in
            item.group.flatMap { FolioGroupFold.isOpen($0, isSelecting: isSelecting, folds: folds) ? $0.id : nil }
        })
        // Manga: an expanded group's seasons are a full-width band after its grid row. Anime scenes are one
        // column, so the band sits directly under the cell.
        let chunks = medium == .manga
            ? FolioShelfChunks.split(ids: items.map(\.id), columns: columns, expanded: expanded)
            : [.grid(items.map(\.id))]
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                switch chunk {
                case .grid(let ids):
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: rowSpacing) {
                        ForEach(ids.compactMap { byId[$0] }) { item in
                            VStack(alignment: .leading, spacing: 0) {
                                Group {
                                    if medium == .manga {
                                        FolioCoverCell(item: item, width: cellWidth, isSelecting: isSelecting,
                                                       isSelected: selectedKeys.contains(item.id), actions: actions)
                                    } else {
                                        FolioSceneCell(item: item, width: cellWidth, isSelecting: isSelecting,
                                                       isSelected: selectedKeys.contains(item.id), actions: actions)
                                    }
                                }
                                .modifier(FolioContextMenu(item: item, actions: actions, enabled: !isSelecting))
                                if let group = item.group, !isSelecting {
                                    FolioGroupToggle(group: group)
                                }
                                if medium == .anime, let group = item.group, FolioGroupFold.isOpen(group, isSelecting: isSelecting, folds: folds) {
                                    FolioGroupMembers(group: group, isSelecting: isSelecting, selectedKeys: selectedKeys,
                                                      actions: actions, inset: 0)
                                }
                            }
                        }
                    }
                case .band(let id):
                    if let group = byId[id]?.group {
                        FolioGroupMembers(group: group, isSelecting: isSelecting, selectedKeys: selectedKeys,
                                          actions: actions, inset: 0)
                    }
                }
            }
        }
        .padding(.horizontal, gutter)
    }
}

// MARK: - Group seasons (W6)

/// Whether a group's seasons are showing: open in the session fold memory, or always in select mode.
enum FolioGroupFold {
    @MainActor
    static func isOpen(_ group: FolioGroup, isSelecting: Bool, folds: KuroFoldMemory) -> Bool {
        isSelecting || folds.isExpanded(page: FolioGrouping.foldPage, section: FolioGrouping.foldSection(group))
    }
}

/// "Show 3 seasons" / "Hide seasons": a real 44 pt fold button (never nested in the row's open button).
struct FolioGroupToggle: View {
    let group: FolioGroup
    var inset: CGFloat = 0
    @Environment(\.kuroFoldMemory) private var folds

    var body: some View {
        let german = KuroLocale.isGerman
        KuroFoldButton(
            isExpanded: folds.binding(page: FolioGrouping.foldPage, section: FolioGrouping.foldSection(group)),
            expandLabel: FolioGroupCopy.showSeasons(group.members.count, german: german),
            collapseLabel: FolioGroupCopy.hideSeasons(german: german))
            .padding(.leading, inset)
    }
}

/// The seasons of an open group: one 56 pt row each with its own status word, position and +1.
struct FolioGroupMembers: View {
    let group: FolioGroup
    let isSelecting: Bool
    let selectedKeys: Set<String>
    let actions: FolioRowActions
    var inset: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(group.members) { member in
                FolioMemberRow(member: member, isSelecting: isSelecting, isSelected: selectedKeys.contains(member.id),
                               actions: actions)
                    .modifier(FolioContextMenu(item: member.item, actions: actions, enabled: !isSelecting))
            }
        }
        .padding(.leading, inset)
    }
}

private struct FolioMemberRow: View {
    let member: FolioMember
    let isSelecting: Bool
    let isSelected: Bool
    let actions: FolioRowActions
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        let german = KuroLocale.isGerman
        let item = member.item
        let phase = isSelecting || member.isLoading ? nil : actions.keyPhase(item)
        HStack(spacing: KuroDesignSpacing.sm) {
            Button {
                guard !suppressCardTaps else { return }
                if isSelecting { actions.toggleSelection(item) } else { actions.open(item) }
            } label: {
                HStack(spacing: 10) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.kuroCustom(20, relativeTo: .title3, maxSize: 28))
                            .foregroundStyle(isSelected ? Color.kuroInk : Color.kuroInkQuiet)
                            .accessibilityHidden(true)
                    }
                    if let label = member.sectionLabel {
                        Text(label)
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInk)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if member.isLoading {
                            KuroBusyMark(width: 44)
                        } else {
                            Text(item.media.title)
                                .font(.kuroBody(weight: .medium))
                                .foregroundStyle(Color.kuroInk)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        let position = FolioPolicy.positionLine(medium: item.media.kind, progress: item.progress,
                                                                total: item.total, german: german)
                        Text([item.status.title(medium: item.media.kind, german: german), position]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: KuroDesignSpacing.sm)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(KuroPressStyle(pressedScale: 0.99))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(FolioGroupCopy.memberAccessibility(member, german: german))
            .accessibilityHint(isSelecting ? "" : (german ? "Öffnet die Details" : "Opens details"))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            if let phase {
                KuroAdvanceKey(style: FolioPolicy.keyStyle(for: item.media.kind), phase: phase.advanceKeyPhase,
                               accessibilityText: FolioAccessibility.keyLabel(item, phase: phase, german: german)) {
                    actions.advance(item)
                }
            }
        }
    }
}

/// Manga: an equal cover (≈ 2:3), a title in a reserved two-line slot (key rows align across a grid
/// row), then "Ch. 141" beside the dark advance key, or above it when the text needs the width.
private struct FolioCoverCell: View {
    let item: FolioItem
    let width: CGFloat
    let isSelecting: Bool
    let isSelected: Bool
    let actions: FolioRowActions
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        let german = KuroLocale.isGerman
        let phase = isSelecting ? nil : actions.keyPhase(item)
        let coverHeight = floor(width / KuroCardMetrics.imageAspectRatio)
        Button {
            guard !suppressCardTaps else { return }
            if isSelecting { actions.toggleSelection(item) } else { actions.open(item) }
        } label: {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                FolioArtwork(url: item.media.imageURL, width: width, height: coverHeight, cornerRadius: 3, topBiased: true)
                    .overlay(alignment: .topTrailing) {
                        if isSelecting { FolioSelectionMark(selected: isSelected).padding(6) }
                    }
                ZStack(alignment: .topLeading) {
                    // Two lines' height, always: a one-line title never lifts its key row.
                    Text("A\nA")
                        .font(Self.titleFont)
                        .lineLimit(2)
                        .hidden()
                        .accessibilityHidden(true)
                    Text(item.media.title)
                        .font(Self.titleFont)
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                let position = item.group?.label
                    ?? FolioPolicy.shelfPositionLine(medium: .manga, progress: item.progress, german: german)
                if phase == nil {
                    positionText(position)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 0) {
                            positionText(position).fixedSize()
                            Spacer(minLength: 48)
                        }
                        .frame(minHeight: 44)
                        VStack(alignment: .leading, spacing: 0) {
                            positionText(position)
                            Color.clear.frame(height: 44)
                        }
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.985))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FolioAccessibility.label(item, german: german))
        .accessibilityHint(isSelecting ? "" : (german ? "Öffnet die Details" : "Opens details"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .overlay(alignment: .bottomTrailing) {
            if let phase {
                KuroAdvanceKey(style: FolioPolicy.keyStyle(for: item.media.kind), phase: phase.advanceKeyPhase,
                               accessibilityText: FolioAccessibility.keyLabel(item, phase: phase, german: german)) {
                    actions.advance(item)
                }
            }
        }
    }

    private static var titleFont: Font { .kuroCustom(14, weight: .medium, relativeTo: .subheadline, maxSize: 26) }

    private func positionText(_ position: String?) -> some View {
        Text(position ?? " ")
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroInkSecondary)
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// Anime: a shallow full-width scene (banner art, ≈ 3.2:1) on a white foot with the title, the
/// position and the next episode, and the light advance key on the right.
private struct FolioSceneCell: View {
    let item: FolioItem
    let width: CGFloat
    let isSelecting: Bool
    let isSelected: Bool
    let actions: FolioRowActions
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        let german = KuroLocale.isGerman
        let phase = isSelecting ? nil : actions.keyPhase(item)
        let sceneHeight = floor(width / 3.2)
        Button {
            guard !suppressCardTaps else { return }
            if isSelecting { actions.toggleSelection(item) } else { actions.open(item) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                FolioArtwork(url: item.banner ?? item.media.imageURL, width: width, height: sceneHeight,
                             cornerRadius: 5, maxPixelSize: 900, topBiased: item.banner == nil)
                    .overlay(alignment: .topTrailing) {
                        if isSelecting { FolioSelectionMark(selected: isSelected).padding(8) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.media.title)
                        .font(.kuroTitleName())
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let position = item.group?.label
                        ?? FolioPolicy.positionLine(medium: .anime, progress: item.progress, total: item.total, german: german) {
                        Text(position)
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .monospacedDigit()
                    }
                    if let next = item.next {
                        KuroReleaseLine(next)
                    }
                }
                .padding(.trailing, phase == nil ? 0 : 56)
                .frame(maxWidth: .infinity, minHeight: phase == nil ? 0 : 44, alignment: .leading)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.985))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FolioAccessibility.label(item, german: german))
        .accessibilityHint(isSelecting ? "" : (german ? "Öffnet die Details" : "Opens details"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .overlay(alignment: .bottomTrailing) {
            if let phase {
                KuroAdvanceKey(style: FolioPolicy.keyStyle(for: item.media.kind), phase: phase.advanceKeyPhase,
                               accessibilityText: FolioAccessibility.keyLabel(item, phase: phase, german: german)) {
                    actions.advance(item)
                }
            }
        }
    }
}

// MARK: - Index

/// 64 pt rows: thumb, title, next release, progress numeral, advance key; hairline separators.
struct FolioIndex: View {
    let items: [FolioItem]
    let width: CGFloat
    let isSelecting: Bool
    let selectedKeys: Set<String>
    let actions: FolioRowActions

    var body: some View {
        let gutter = FolioPolicy.gutter(forWidth: width)
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                FolioIndexRow(item: item, isSelecting: isSelecting, isSelected: selectedKeys.contains(item.id), actions: actions)
                    .padding(.horizontal, gutter)
                    .modifier(FolioContextMenu(item: item, actions: actions, enabled: !isSelecting))
                if let group = item.group {
                    FolioIndexSeasons(group: group, isSelecting: isSelecting, selectedKeys: selectedKeys,
                                      actions: actions, gutter: gutter)
                }
                Rectangle()
                    .fill(Color.kuroHairline)
                    .frame(height: 0.5)
                    .padding(.leading, gutter + 52)
            }
        }
    }
}

/// Under a group row: the fold button and, when open (always in select mode), each season.
private struct FolioIndexSeasons: View {
    let group: FolioGroup
    let isSelecting: Bool
    let selectedKeys: Set<String>
    let actions: FolioRowActions
    let gutter: CGFloat
    @Environment(\.kuroFoldMemory) private var folds

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isSelecting { FolioGroupToggle(group: group, inset: 52) }
            if FolioGroupFold.isOpen(group, isSelecting: isSelecting, folds: folds) {
                FolioGroupMembers(group: group, isSelecting: isSelecting, selectedKeys: selectedKeys, actions: actions)
            }
        }
        .padding(.leading, gutter)
        .padding(.trailing, gutter)
    }
}

private struct FolioIndexRow: View {
    let item: FolioItem
    let isSelecting: Bool
    let isSelected: Bool
    let actions: FolioRowActions
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let german = KuroLocale.isGerman
        let phase = isSelecting ? nil : actions.keyPhase(item)
        HStack(spacing: KuroDesignSpacing.sm) {
            Button {
                guard !suppressCardTaps else { return }
                if isSelecting { actions.toggleSelection(item) } else { actions.open(item) }
            } label: {
                HStack(spacing: 12) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.kuroCustom(20, relativeTo: .title3, maxSize: 28))
                            .foregroundStyle(isSelected ? Color.kuroInk : Color.kuroInkQuiet)
                            .accessibilityHidden(true)
                    }
                    FolioArtwork(url: item.media.imageURL, width: 40, height: 56, cornerRadius: 2, maxPixelSize: 140, topBiased: true)
                    if dynamicTypeSize.isAccessibilitySize {
                        // Accessibility sizes: the numeral moves under the title instead of squeezing it.
                        VStack(alignment: .leading, spacing: 3) {
                            titleText(lineLimit: 4)
                            numeralText
                            secondaryLine(german: german)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            titleText(lineLimit: 2)
                            secondaryLine(german: german)
                        }
                        Spacer(minLength: KuroDesignSpacing.sm)
                        numeralText
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(KuroPressStyle(pressedScale: 0.99))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(FolioAccessibility.label(item, german: german))
            .accessibilityHint(isSelecting ? "" : (german ? "Öffnet die Details" : "Opens details"))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            if let phase {
                KuroAdvanceKey(style: FolioPolicy.keyStyle(for: item.media.kind), phase: phase.advanceKeyPhase,
                               accessibilityText: FolioAccessibility.keyLabel(item, phase: phase, german: german)) {
                    actions.advance(item)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func titleText(lineLimit: Int) -> some View {
        Text(item.media.title)
            .font(.kuroBody(weight: .medium))
            .foregroundStyle(Color.kuroInk)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var numeralText: some View {
        if let label = item.group?.label {
            // A group row's numeral slot shows its label ("S2 · 5/12").
            Text(label)
                .font(.kuroCustom(17, weight: .regular, relativeTo: .body, maxSize: 30))
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(Color.kuroInk)
                .lineLimit(1)
        } else if let numeral = FolioPolicy.progressNumeral(progress: item.progress, total: item.total),
           item.entry.status != .planning {
            Text(numeral)
                .font(.kuroCustom(17, weight: .regular, relativeTo: .body, maxSize: 30))
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(item.entry.status == .dropped ? Color.kuroInkQuiet : Color.kuroInk)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func secondaryLine(german: Bool) -> some View {
        if let next = item.next, next.isDisplayable {
            KuroReleaseLine(next)
        } else if item.entry.status == .completed, let verdict = item.entry.verdict {
            Text(verdict.name(german: german))
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkSecondary)
        } else if item.entry.status == .planning, let total = item.total {
            Text(item.media.kind == .manga
                 ? (german ? "\(total) Kapitel" : "\(total) chapters")
                 : (german ? "\(total) Folgen" : "\(total) episodes"))
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkSecondary)
        }
    }
}

// MARK: - Loading

/// Stable skeleton geometry for both densities (no spinner-only page after the first paint).
struct FolioSkeleton: View {
    let density: FolioDensity
    let medium: MediaKind
    let width: CGFloat

    var body: some View {
        let gutter = FolioPolicy.gutter(forWidth: width)
        let content = max(0, width - gutter * 2)
        Group {
            if density == .index {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        HStack(spacing: 12) {
                            Rectangle().fill(Color.kuroBlack05).frame(width: 40, height: 56)
                            VStack(alignment: .leading, spacing: 6) {
                                Rectangle().fill(Color.kuroBlack05).frame(height: 12)
                                Rectangle().fill(Color.kuroBlack05).frame(width: 120, height: 10)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 64)
                    }
                }
                .padding(.horizontal, gutter)
            } else if medium == .manga {
                let columns = FolioPolicy.shelfColumns(width: content, medium: .manga, accessibilitySize: false)
                let cell = floor((content - 12 * CGFloat(columns - 1)) / CGFloat(columns))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(max(1, cell)), spacing: 12), count: columns), spacing: 20) {
                    ForEach(0..<(columns * 3), id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            Rectangle().fill(Color.kuroBlack05).frame(width: cell, height: floor(cell / KuroCardMetrics.imageAspectRatio))
                            Rectangle().fill(Color.kuroBlack05).frame(width: cell * 0.8, height: 10)
                        }
                    }
                }
                .padding(.horizontal, gutter)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 10) {
                            Rectangle().fill(Color.kuroBlack05).frame(width: content, height: floor(content / 3.2))
                            Rectangle().fill(Color.kuroBlack05).frame(width: content * 0.6, height: 12)
                        }
                    }
                }
                .padding(.horizontal, gutter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading your list", "Deine Liste wird geladen"))
    }
}
