import SwiftUI

// MARK: - State view (spec §3.5, rulebook §9)
// One honest voice for the states a surface can be in. A failure, offline state or denial never
// renders as a successful empty state. Copy is short, plain and true, names the action that fixes the
// state, and ships in EN and DE. Pass `title`/`message` to say what is empty ("No clubs yet.").
// Offline and failed states say whether earlier content is still on screen: the caller states it
// (`hasCachedContent`), because "Showing what you saw last." is false when nothing was loaded.

struct KuroStateView: View {
    nonisolated enum Kind: Equatable, Sendable {
        case loading
        case empty
        /// No connection. `hasCachedContent`: earlier content is still shown.
        case offline(hasCachedContent: Bool)
        /// The read failed. `hasCachedContent`: earlier content is still shown.
        case failed(hasCachedContent: Bool)
        case denied
    }

    /// `.page`: centred in the available space. `.inline`: a section-scoped line block.
    enum Layout {
        case page
        case inline
    }

    let kind: Kind
    var title: String? = nil
    var message: String? = nil
    var layout: Layout = .page
    var retry: (() -> Void)? = nil

    init(_ kind: Kind, title: String? = nil, message: String? = nil, layout: Layout = .page,
         retry: (() -> Void)? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.layout = layout
        self.retry = retry
    }

    var body: some View {
        let copy = KuroStateCopy.copy(for: kind, german: KuroLocale.isGerman)
        let shownTitle = title ?? copy.title
        let shownMessage = message ?? copy.message
        VStack(alignment: layout == .page ? .center : .leading, spacing: KuroDesignSpacing.sm) {
            if kind == .loading {
                ProgressView()
                    .tint(Color.kuroInkQuiet)
                    .accessibilityHidden(true)
            }
            Text(shownTitle)
                .font(layout == .page ? .kuroTitle(weight: .regular) : .kuroBody(weight: .regular))
                .foregroundStyle(Color.kuroInk)
                .multilineTextAlignment(layout == .page ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let shownMessage {
                Text(shownMessage)
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .multilineTextAlignment(layout == .page ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let retry, kind != .loading {
                KuroInkButton(KuroStateCopy.retryTitle(german: KuroLocale.isGerman), role: .secondary, haptic: false, action: retry)
                    .frame(maxWidth: layout == .page ? 280 : .infinity)
                    .padding(.top, KuroDesignSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: layout == .page ? .infinity : nil,
               alignment: layout == .page ? .center : .leading)
        .padding(.horizontal, layout == .page ? KuroDesignSpacing.padding : 0)
        .padding(.vertical, layout == .page ? KuroDesignSpacing.xl : KuroDesignSpacing.md)
        .accessibilityElement(children: .contain)
    }
}

/// Default EN/DE copy per state (rulebook §9). Pure, so tests can pin it.
nonisolated enum KuroStateCopy {
    struct Copy: Equatable, Sendable {
        let title: String
        let message: String?
    }

    static func copy(for kind: KuroStateView.Kind, german: Bool) -> Copy {
        switch kind {
        case .loading:
            return Copy(title: german ? "Wird geladen." : "Loading.", message: nil)
        case .empty:
            return Copy(title: german ? "Hier ist noch nichts." : "Nothing here yet.", message: nil)
        case .offline(hasCachedContent: true):
            return Copy(title: "Offline.",
                        message: german ? "Du siehst den letzten Stand." : "Showing what you saw last.")
        case .offline(hasCachedContent: false):
            return Copy(title: "Offline.",
                        message: german ? "Verbinde dich, um das zu laden." : "Connect to load this.")
        case .failed(hasCachedContent: true):
            return Copy(title: german ? "Konnte nicht aktualisiert werden." : "Couldn't refresh.",
                        message: german ? "Deine bisherigen Daten bleiben erhalten." : "What you had is still here.")
        case .failed(hasCachedContent: false):
            return Copy(title: german ? "Konnte nicht geladen werden." : "Couldn't load this.",
                        message: german ? "Versuch es gleich noch einmal." : "Try again in a moment.")
        case .denied:
            return Copy(title: german ? "Nur für Mitglieder sichtbar." : "Private to members.",
                        message: nil)
        }
    }

    static func retryTitle(german: Bool) -> String {
        german ? "Erneut versuchen" : "Try again"
    }
}
