import SwiftUI

// MARK: - The pinned index (usability spec §5.10)
// Once the contents block has scrolled under the header, a 38 pt band on the canvas with a 0.5 pt
// `kuroHairline` under it: one line of short section words (New · Season · Essentials · Manga ·
// Trending · Classics), scrolling sideways if needed. The current section is ink with the 28 × 2
// `HomeInk.switchMark` under it (fading in place, no travel), passed sections ink, sections ahead
// `kuroMuted` (AA on both canvases); a 4 pt dot follows a word whose section has NEW titles. A word scrolls to
// its section. Every word is a 44 pt target (the band's hit area reaches below the drawn 38).

/// The band's words and states (pure).
struct DiscoverPinnedEntry: Identifiable, Equatable {
    /// The section's scroll anchor.
    let id: String
    let word: String
    let hasNew: Bool
}

nonisolated enum DiscoverPinnedState: Equatable, Sendable {
    case passed, current, ahead

    /// Each entry's state for the current section's index (nil: none yet, everything ahead).
    static func states(count: Int, current: Int?) -> [DiscoverPinnedState] {
        (0..<max(0, count)).map { index in
            guard let current else { return .ahead }
            if index < current { return .passed }
            return index == current ? .current : .ahead
        }
    }
}

struct DiscoverPinnedIndex: View {
    let entries: [DiscoverPinnedEntry]
    let current: String?
    let canvas: Color
    let onJump: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let bandHeight: CGFloat = 38

    var body: some View {
        let currentIndex = entries.firstIndex { $0.id == current }
        let states = DiscoverPinnedState.states(count: entries.count, current: currentIndex)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    word(entry, state: states[index])
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
        .frame(height: Self.bandHeight)
        .frame(maxWidth: .infinity)
        .background(canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.kuroHairline).frame(height: 0.5).accessibilityHidden(true)
        }
        .kuroSwipeExclusionZone()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DiscoverIssueCopy.pinnedLabel(german: KuroLocale.isGerman))
    }

    private func word(_ entry: DiscoverPinnedEntry, state: DiscoverPinnedState) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            onJump(entry.id)
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(entry.word)
                        .font(.kuroCustom(12, weight: state == .current ? .semibold : .medium,
                                          relativeTo: .footnote, maxSize: 22))
                        // `kuroMuted` (4.86 : 1 on the Manga canvas #F5F5F3; `switchUnselected` was 4.20 : 1, under AA).
                        .foregroundStyle(state == .ahead ? Color.kuroMuted : Color.kuroInk)
                        .lineLimit(1)
                        .fixedSize()
                    if entry.hasNew {
                        Circle().fill(Color.kuroInk.opacity(0.7)).frame(width: 4, height: 4)
                    }
                }
                Rectangle()
                    .fill(HomeInk.switchMark)
                    .frame(width: 28, height: 2)
                    .opacity(state == .current ? 1 : 0)
                    .animation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.settle : nil, value: state)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(entry.word)
        .accessibilityAddTraits(state == .current ? .isSelected : [])
    }
}
