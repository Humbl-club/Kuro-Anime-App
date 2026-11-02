import SwiftUI

// MARK: - Folding sections (navigation contract F1–F3)
//
// A foldable section (story "Read more", episodes/chapters "More", songs "Show all", coverage guides,
// Profile "Advanced", …) keeps its open/closed state for the session per page and section, animates
// with the prototype easing and is a real button:
//
//     @Environment(\.kuroFoldMemory) private var folds
//     let story = folds.binding(page: KuroFold.page(anime.libraryKey), section: "story")
//     Text(synopsis).lineLimit(story.wrappedValue ? nil : 5)
//     KuroFoldButton(isExpanded: story,
//                    expandLabel: KuroLocale.text("Read more", "Mehr lesen"),
//                    collapseLabel: KuroLocale.text("Show less", "Weniger anzeigen"),
//                    onCollapse: { proxy.scrollTo("story", anchor: .top) })        // F2: stay in view
//
// - F1: the toggle animates with `KuroMotion.settle`; Reduce Motion (or Low Power): no animation.
// - F2: the label states what it does, VoiceOver reads "Expanded"/"Collapsed" ("Aufgeklappt"/
//   "Zugeklappt"); `onCollapse` lets the page scroll the section header back into view.
// - F3: `KuroFoldMemory` is plain UI state (account-agnostic, never persisted): one per app run, held
//   by KuroRootView and injected as `\.kuroFoldMemory`; a new launch starts folded.

/// Session memory of opened sections, keyed by page identity and section id (F3).
@Observable
final class KuroFoldMemory {
    private var expanded: Set<String> = []

    init() {}

    /// Whether `section` on `page` is open (`defaultExpanded` until the user toggles it).
    func isExpanded(page: String, section: String, defaultExpanded: Bool = false) -> Bool {
        let key = KuroFold.key(page: page, section: section)
        if expanded.contains(key) { return true }
        if expanded.contains(KuroFold.collapsedKey(key)) { return false }
        return defaultExpanded
    }

    func setExpanded(_ value: Bool, page: String, section: String) {
        let key = KuroFold.key(page: page, section: section)
        if value {
            expanded.insert(key)
            expanded.remove(KuroFold.collapsedKey(key))
        } else {
            expanded.remove(key)
            expanded.insert(KuroFold.collapsedKey(key))
        }
    }

    /// A binding to one section's state (what `KuroFoldButton` takes).
    func binding(page: String, section: String, defaultExpanded: Bool = false) -> Binding<Bool> {
        Binding(
            get: { self.isExpanded(page: page, section: section, defaultExpanded: defaultExpanded) },
            set: { self.setExpanded($0, page: page, section: section) }
        )
    }
}

/// The fold rules (pure).
enum KuroFold {
    /// The memory key of a section on a page.
    nonisolated static func key(page: String, section: String) -> String { "\(page)#\(section)" }
    nonisolated static func collapsedKey(_ key: String) -> String { "\(key)#closed" }

    /// A page identity for a title (`anime:7`, `manga:7`).
    nonisolated static func page(kind: String, id: Int) -> String { "\(kind):\(id)" }

    /// The animation a fold toggle uses (F1): the prototype easing, none with Reduce Motion / Low Power.
    static func animation(reduceMotion: Bool) -> Animation? {
        KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.settle : nil
    }

    /// VoiceOver's value for the control (F2).
    nonisolated static func accessibilityValue(expanded: Bool, german: Bool) -> String {
        if german { return expanded ? "Aufgeklappt" : "Zugeklappt" }
        return expanded ? "Expanded" : "Collapsed"
    }
}

private struct KuroFoldMemoryKey: EnvironmentKey {
    static let defaultValue = KuroFoldMemory()
}

extension EnvironmentValues {
    /// The session's fold memory (KuroRootView injects the app's; previews/tests get a private one).
    var kuroFoldMemory: KuroFoldMemory {
        get { self[KuroFoldMemoryKey.self] }
        set { self[KuroFoldMemoryKey.self] = newValue }
    }
}

/// The fold control: a real button that toggles with the prototype easing and says what it does.
struct KuroFoldButton<Label: View>: View {
    @Binding var isExpanded: Bool
    let expandLabel: String
    let collapseLabel: String
    var onCollapse: (() -> Void)? = nil
    @ViewBuilder let label: (_ title: String, _ isExpanded: Bool) -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            let collapsing = isExpanded
            withAnimation(KuroFold.animation(reduceMotion: reduceMotion)) { isExpanded.toggle() }
            if collapsing { onCollapse?() }
        } label: {
            label(isExpanded ? collapseLabel : expandLabel, isExpanded)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? collapseLabel : expandLabel)
        .accessibilityValue(KuroFold.accessibilityValue(expanded: isExpanded, german: KuroLocale.isGerman))
    }
}

extension KuroFoldButton where Label == KuroFoldDefaultLabel {
    /// The default label: the words and a `+` / `−` mark, 44 pt tall.
    init(isExpanded: Binding<Bool>, expandLabel: String, collapseLabel: String, onCollapse: (() -> Void)? = nil) {
        self.init(isExpanded: isExpanded, expandLabel: expandLabel, collapseLabel: collapseLabel,
                  onCollapse: onCollapse) { title, expanded in
            KuroFoldDefaultLabel(title: title, isExpanded: expanded)
        }
    }
}

/// The default fold label.
struct KuroFoldDefaultLabel: View {
    let title: String
    let isExpanded: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInk)
            Spacer(minLength: 8)
            Text(isExpanded ? "\u{2212}" : "+")
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInk)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }
}
