import SwiftUI
import UIKit

// MARK: - Journey chrome + shrinking header (navigation contract N1–N3, H1–H4)
//
// Every journey page draws its controls with ONE modifier:
//
//     @State private var collapse: CGFloat = 0
//     ScrollView { hero; sections }
//         .kuroCollapseTracking($collapse, distance: heroHeight - 44)   // H1/H3: offset -> 0...1
//         .kuroJourneyChrome(title: anime.displayTitle, collapseProgress: collapse, material: material)
//
// - Back chevron (only when pushed, `JourneyContext.isPushed`) top-left, ✕ top-right, 44 pt each,
//   "Back"/"Zurück" and "Close"/"Schließen" for VoiceOver (N1, N3).
// - Over the artwork (progress 0) they are the round material keys (`ArtworkMaterial.base`, white
//   glyph; neutral paper key without a material); in the compact bar (progress 1) plain ink glyphs.
// - The compact bar (paper `kuroPaper`, hairline `kuroLine`, one-line title) fades in with the
//   progress (H1); the controls never scroll away (H2). Reduce Motion: the bar snaps at half way with a
//   short cross-fade (H3).
// - The system bar and back button are hidden and edge swipe-back is restored (N2).
// - A page with no artwork passes `collapseProgress: 1` (the compact bar from the start).
// Outside a journey (a legacy sheet) the chrome shows ✕ only and ✕ dismisses the sheet.

/// The shrinking header's pure rules.
enum KuroCollapse {
    /// Scroll offset -> progress 0...1: 0 until `start`, 1 after `start + distance`.
    nonisolated static func progress(offset: CGFloat, start: CGFloat = 0, distance: CGFloat) -> CGFloat {
        guard distance > 0 else { return offset > start ? 1 : 0 }
        return min(1, max(0, (offset - start) / distance))
    }

    /// The progress the chrome draws: the raw progress, or (Reduce Motion) 0 or 1, switched half way.
    nonisolated static func displayProgress(_ raw: CGFloat, reduceMotion: Bool) -> CGFloat {
        guard reduceMotion else { return min(1, max(0, raw)) }
        return raw >= 0.5 ? 1 : 0
    }

    /// The round material key's opacity (fully gone by 60 % so the glyphs never double up).
    nonisolated static func keyOpacity(_ progress: CGFloat) -> CGFloat {
        max(0, 1 - progress / 0.6)
    }
}

extension View {
    /// Tracks a scroll view's vertical offset as collapse progress (`KuroCollapse.progress`).
    func kuroCollapseTracking(_ progress: Binding<CGFloat>, start: CGFloat = 0, distance: CGFloat) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            let next = KuroCollapse.progress(offset: offset, start: start, distance: distance)
            if abs(next - progress.wrappedValue) > 0.001 { progress.wrappedValue = next }
        }
    }

    /// The journey page chrome (back chevron when pushed, ✕, shrinking compact bar). See the file header.
    /// - Parameters:
    ///   - title: the page's one-line title for the compact bar.
    ///   - collapseProgress: 0 = the hero is showing (round keys over artwork), 1 = compact bar.
    ///   - material: the artwork material the round keys use (nil: the neutral paper key).
    func kuroJourneyChrome(title: String, collapseProgress: CGFloat = 1, material: ArtworkMaterial? = nil) -> some View {
        modifier(KuroJourneyChromeModifier(title: title, progress: collapseProgress, material: material))
    }
}

private struct KuroJourneyChromeModifier: ViewModifier {
    let title: String
    let progress: CGFloat
    let material: ArtworkMaterial?

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .background(KuroInteractivePopEnabler())
            .overlay(alignment: .top) {
                KuroJourneyChrome(title: title, progress: progress, material: material)
            }
    }
}

/// The chrome bar itself (also usable directly by a page that lays out its own overlay).
struct KuroJourneyChrome: View {
    let title: String
    let progress: CGFloat
    var material: ArtworkMaterial? = nil

    @Environment(\.kuroJourney) private var journey
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let barHeight: CGFloat = 52

    var body: some View {
        let shown = KuroCollapse.displayProgress(progress, reduceMotion: reduceMotion)
        HStack(spacing: 8) {
            if journey?.isPushed == true {
                KuroJourneyChromeKey(kind: .back, progress: shown, material: material) { journey?.pop() }
            }
            Text(title)
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: journey?.isPushed == true ? .leading : .center)
                .padding(.leading, journey?.isPushed == true ? 0 : 52)
                .opacity(shown)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHidden(shown < 0.5)
            KuroJourneyChromeKey(kind: .close, progress: shown, material: material) {
                if let journey { journey.close() } else { dismiss() }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.barHeight)
        .background(alignment: .bottom) {
            Color.kuroPaper
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.kuroLine).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .top)
                .opacity(shown)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : nil, value: shown)
    }
}

/// One chrome control: the round material key over artwork cross-fading to a plain ink glyph.
struct KuroJourneyChromeKey: View {
    enum Kind {
        case back, close

        var symbol: String { self == .back ? "chevron.left" : "xmark" }
        var label: String {
            self == .back ? KuroLocale.text("Back", "Zurück") : KuroLocale.text("Close", "Schließen")
        }
    }

    let kind: Kind
    let progress: CGFloat
    var material: ArtworkMaterial? = nil
    let action: () -> Void

    var body: some View {
        let keyOpacity = KuroCollapse.keyOpacity(progress)
        let onArtGlyph: Color = material == nil ? .kuroInk : .white
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(material?.base.color ?? Color(hex: "EDEEEC"))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0x45 / 255.0), lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .opacity(keyOpacity)
                Image(systemName: kind.symbol)
                    .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 20))
                    .foregroundStyle(onArtGlyph)
                    .opacity(keyOpacity)
                Image(systemName: kind.symbol)
                    .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 20))
                    .foregroundStyle(Color.kuroInk)
                    .opacity(1 - keyOpacity)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(kind.label)
    }
}

// MARK: - Edge swipe-back (N2)

/// Keeps the interactive pop gesture working on pages that hide the system navigation bar or its back
/// button (UIKit disables it then). Installed by `JourneyHost` and `.kuroJourneyChrome`; public UIKit
/// only: the stack's `interactivePopGestureRecognizer` gets a delegate that allows the gesture whenever
/// there is a page to pop to and no transition is running.
struct KuroInteractivePopEnabler: UIViewControllerRepresentable {
    var onResolve: ((UINavigationController) -> Void)? = nil

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onResolve = onResolve
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onResolve = onResolve
        controller.install()
    }

    final class Controller: UIViewController {
        var onResolve: ((UINavigationController) -> Void)?

        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            self.view = view
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        func install() {
            guard let navigationController else { return }
            KuroPopGestureDelegate.install(on: navigationController)
            onResolve?(navigationController)
        }
    }
}

/// The pop gesture's delegate (one per navigation controller, held by it).
final class KuroPopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var navigationController: UINavigationController?
    private static var key: UInt8 = 0

    private init(_ navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    static func install(on navigationController: UINavigationController) {
        guard let gesture = navigationController.interactivePopGestureRecognizer else { return }
        let delegate: KuroPopGestureDelegate
        if let existing = objc_getAssociatedObject(navigationController, &key) as? KuroPopGestureDelegate {
            delegate = existing
        } else {
            delegate = KuroPopGestureDelegate(navigationController)
            objc_setAssociatedObject(navigationController, &key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        if gesture.delegate !== delegate { gesture.delegate = delegate }
        gesture.isEnabled = true
    }

    /// The pure rule: a page to pop to and no transition running.
    nonisolated static func allowsPop(stackCount: Int, isTransitioning: Bool) -> Bool {
        stackCount > 1 && !isTransitioning
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        return Self.allowsPop(stackCount: navigationController.viewControllers.count,
                              isTransitioning: navigationController.transitionCoordinator != nil)
    }
}
