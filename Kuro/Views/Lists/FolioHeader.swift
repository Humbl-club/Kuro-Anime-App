import KuroCore
import SwiftUI

// MARK: - Folio header: status strip, density, sort, search, select
// Typographic controls only (rulebook §7): words with an ink underline, quiet ink when unselected,
// no colored chips, every target at least 44 pt.

/// "Watching 12 · Planned 40 · Completed 85 · Paused 3 · Dropped 1" as one scrollable word strip.
struct FolioStatusStrip: View {
    @Binding var selection: FolioStatus
    let counts: [FolioStatus: Int]
    let medium: MediaKind
    var gutter: CGFloat = KuroDesignSpacing.padding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let german = KuroLocale.isGerman
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .firstTextBaseline, spacing: KuroDesignSpacing.lg) {
                    ForEach(FolioStatus.allCases) { status in
                        word(status, german: german)
                            .id(status)
                    }
                }
                .padding(.horizontal, gutter)
            }
            .kuroTrailingOverflowFade()
            .kuroSwipeExclusionZone()
            .onChange(of: selection) { _, value in
                if reduceMotion { proxy.scrollTo(value, anchor: .center) }
                else { withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) { proxy.scrollTo(value, anchor: .center) } }
            }
        }
    }

    private func word(_ status: FolioStatus, german: Bool) -> some View {
        let selected = selection == status
        let count = counts[status] ?? 0
        let title = status.title(medium: medium, german: german)
        return Button {
            guard !selected else { return }
            KuroAccessibility.impactHaptic(.light)
            selection = status
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title)
                        .font(.kuroCustom(16, weight: selected ? .semibold : .regular, relativeTo: .subheadline, maxSize: 30))
                    Text("\(count)")
                        .font(.kuroCustom(13, weight: .regular, relativeTo: .footnote, maxSize: 26))
                        .monospacedDigit()
                }
                .foregroundStyle(selected ? Color.kuroInk : Color.kuroInkQuiet)
                .lineLimit(1)
                Rectangle()
                    .fill(selected ? Color.kuroInk : Color.clear)
                    .frame(height: 2)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(german ? "\(title), \(count) Titel" : "\(title), \(count) \(count == 1 ? "title" : "titles")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Density words, the sort menu, search and select in one quiet row (two rows when it does not fit).
struct FolioControlsRow: View {
    @Binding var density: FolioDensity
    @Binding var sort: FolioSort
    let isSearching: Bool
    let isSelecting: Bool
    let canSelect: Bool
    let onToggleSearch: () -> Void
    let onToggleSelect: () -> Void
    var gutter: CGFloat = KuroDesignSpacing.padding

    var body: some View {
        let german = KuroLocale.isGerman
        ViewThatFits(in: .horizontal) {
            HStack(spacing: KuroDesignSpacing.md) {
                densityWords(german: german)
                Spacer(minLength: KuroDesignSpacing.sm)
                sortMenu(german: german)
                searchButton(german: german)
                selectButton(german: german)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: KuroDesignSpacing.md) {
                    densityWords(german: german)
                    Spacer(minLength: 0)
                }
                HStack(spacing: KuroDesignSpacing.md) {
                    sortMenu(german: german)
                    Spacer(minLength: 0)
                    searchButton(german: german)
                    selectButton(german: german)
                }
            }
        }
        .padding(.horizontal, gutter)
    }

    private func densityWords(german: Bool) -> some View {
        HStack(spacing: KuroDesignSpacing.md) {
            ForEach(FolioDensity.allCases) { option in
                let selected = density == option
                Button {
                    guard !selected else { return }
                    KuroAccessibility.impactHaptic(.light)
                    withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) { density = option }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.title(german: german))
                            .font(.kuroMeta(weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.kuroInk : Color.kuroInkQuiet)
                            .lineLimit(1)
                        Rectangle()
                            .fill(selected ? Color.kuroInk : Color.clear)
                            .frame(width: 16, height: 1.5)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle())
                .accessibilityLabel(option.title(german: german))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(german ? "Ansicht" : "View")
    }

    private func sortMenu(german: Bool) -> some View {
        Menu {
            Picker(selection: $sort) {
                ForEach(FolioSort.allCases) { option in
                    Text(option.title(german: german)).tag(option)
                }
            } label: {
                Text(german ? "Sortieren" : "Sort")
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(sort.title(german: german))
                    .font(.kuroMeta(weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.kuroCustom(10, weight: .medium, relativeTo: .caption2, maxSize: 16))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.kuroInk)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(german ? "Sortieren: \(sort.title(german: true))" : "Sort: \(sort.title(german: false))")
    }

    private func searchButton(german: Bool) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            onToggleSearch()
        } label: {
            Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                .font(.kuroCustom(15, weight: .regular, relativeTo: .body, maxSize: 24))
                .foregroundStyle(Color.kuroInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(isSearching
                            ? (german ? "Suche schließen" : "Close search")
                            : (german ? "In der Liste suchen" : "Search this list"))
    }

    @ViewBuilder
    private func selectButton(german: Bool) -> some View {
        if canSelect || isSelecting {
            Button {
                KuroAccessibility.impactHaptic(.light)
                onToggleSelect()
            } label: {
                Text(isSelecting ? (german ? "Fertig" : "Done") : (german ? "Auswählen" : "Select"))
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                    .lineLimit(1)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KuroPressStyle())
        }
    }
}

/// The in-list search field (filters every loaded row; the host loads the rest of the list).
struct FolioSearchField: View {
    @Binding var text: String
    let medium: MediaKind
    var focused: FocusState<Bool>.Binding
    var gutter: CGFloat = KuroDesignSpacing.padding

    var body: some View {
        let german = KuroLocale.isGerman
        HStack(spacing: KuroDesignSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.kuroCustom(14, relativeTo: .body, maxSize: 22))
                .foregroundStyle(Color.kuroInkQuiet)
                .accessibilityHidden(true)
            TextField(FolioCopy.searchPlaceholder(medium: medium, german: german), text: $text)
                .font(.kuroBody())
                .foregroundStyle(Color.kuroInk)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused(focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.kuroCustom(15, relativeTo: .body, maxSize: 22))
                        .foregroundStyle(Color.kuroInkQuiet)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(german ? "Suche löschen" : "Clear search")
            }
        }
        .padding(.leading, KuroDesignSpacing.md)
        .frame(minHeight: 44)
        .background(Color.kuroCanvasQuiet, in: RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous))
        .padding(.horizontal, gutter)
    }
}

/// Completed-only verdict words, with the honest nudge when titles still need one.
struct FolioVerdictWords: View {
    @Binding var selection: FolioVerdictFilter
    let unsortedCount: Int
    var gutter: CGFloat = KuroDesignSpacing.padding

    var body: some View {
        let german = KuroLocale.isGerman
        VStack(alignment: .leading, spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KuroDesignSpacing.md) {
                    ForEach(FolioVerdictFilter.allCases) { option in
                        let selected = selection == option
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            selection = option
                        } label: {
                            Text(option.title(german: german))
                                .font(.kuroMeta(weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.kuroInk : Color.kuroInkQuiet)
                                .underline(selected, color: Color.kuroInk)
                                .lineLimit(1)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, gutter)
            }
            .kuroTrailingOverflowFade()
            .kuroSwipeExclusionZone()
            if unsortedCount > 0 {
                Text(german
                     ? "\(unsortedCount) abgeschlossene Titel haben noch kein Urteil."
                     : "\(unsortedCount) completed \(unsortedCount == 1 ? "title still needs" : "titles still need") a verdict.")
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, gutter)
            }
        }
    }
}

/// The batch bar: count, a status menu that includes Dropped, and Remove (red: destructive).
struct FolioBatchBar: View {
    let count: Int
    let medium: MediaKind
    let onChangeStatus: (FolioStatus) -> Void
    let onRemove: () -> Void

    var body: some View {
        let german = KuroLocale.isGerman
        HStack(spacing: KuroDesignSpacing.md) {
            Text(FolioCopy.selectedCount(count, german: german))
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInk)
                .monospacedDigit()
            Spacer(minLength: 0)
            Menu {
                ForEach(FolioStatus.allCases) { status in
                    Button(status.title(medium: medium, german: german)) { onChangeStatus(status) }
                }
            } label: {
                Text(german ? "Status ändern" : "Change status")
                    .font(.kuroMeta(weight: .semibold))
                    .foregroundStyle(Color.kuroInk)
                    .padding(.horizontal, KuroDesignSpacing.md)
                    .frame(minHeight: 44)
                    .overlay(Capsule().strokeBorder(Color.kuroKeyRim, lineWidth: 1))
                    .contentShape(Capsule())
            }
            Button {
                KuroAccessibility.impactHaptic(.medium)
                onRemove()
            } label: {
                Text(german ? "Entfernen" : "Remove")
                    .font(.kuroMeta(weight: .semibold))
                    .foregroundStyle(Color.kuroDestructiveInk)
                    .padding(.horizontal, KuroDesignSpacing.md)
                    .frame(minHeight: 44)
                    .overlay(Capsule().strokeBorder(Color.kuroDestructiveInk.opacity(0.4), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(KuroPressStyle())
        }
        .padding(.horizontal, KuroDesignSpacing.padding)
        .padding(.vertical, KuroDesignSpacing.sm)
        .background(
            Color.kuroCanvasPage
                .overlay(alignment: .top) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// One short notice at the bottom of the list with an optional action ("Ep. 8 marked." · Undo).
/// The action is a real 44 pt button, reachable with VoiceOver; the notice is announced once.
struct FolioNotice: Equatable, Identifiable {
    enum Tone: Equatable { case confirmation, problem }
    let id = UUID()
    let tone: Tone
    let message: String
    let actionTitle: String?

    static func == (lhs: FolioNotice, rhs: FolioNotice) -> Bool { lhs.id == rhs.id }
}

struct FolioNoticeBar: View {
    let notice: FolioNotice
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: KuroDesignSpacing.md) {
            if notice.tone == .problem {
                Image(systemName: "exclamationmark.circle")
                    .font(.kuroCustom(15, relativeTo: .body, maxSize: 24))
                    .foregroundStyle(Color.kuroError)
                    .accessibilityHidden(true)
            }
            Text(notice.message)
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let title = notice.actionTitle {
                Button(action: onAction) {
                    Text(title)
                        .font(.kuroMeta(weight: .semibold))
                        .foregroundStyle(Color.kuroInk)
                        .underline(true, color: Color.kuroInk)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle())
            }
        }
        .padding(.horizontal, KuroDesignSpacing.md)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                .fill(Color.kuroCanvasPage)
                .overlay(RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                    .strokeBorder(Color.kuroKeyRim, lineWidth: 1))
        )
        .padding(.horizontal, KuroDesignSpacing.padding)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Overflow cue

/// A soft trailing fade on a sideways word strip while more of it lies past the trailing edge, so a
/// clipped last word ("Paused (") reads as "scroll for more" (visual QA). No fade once the end is
/// reached or when everything fits.
private struct KuroTrailingOverflowFade: ViewModifier {
    var width: CGFloat = 28
    @State private var hasMore = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxX < geometry.contentSize.width - 1
            } action: { _, more in
                hasMore = more
            }
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [.black, hasMore ? .clear : .black],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width)
                }
            }
    }
}

extension View {
    /// Fades the trailing edge of a horizontal `ScrollView` while it has more content past that edge.
    func kuroTrailingOverflowFade() -> some View {
        modifier(KuroTrailingOverflowFade())
    }
}
