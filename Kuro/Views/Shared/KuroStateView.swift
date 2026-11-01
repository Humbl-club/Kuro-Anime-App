import SwiftUI

// MARK: - State view (spec §3.5, rulebook §9)
// Since the prototype-fidelity pass (Task 3) a thin wrapper over the branded family in
// `KuroBrandedStates.swift` (loading → `KuroLoadingView`, whose caption shows `title`; empty →
// `KuroEmptyView`, with Try again when the caller passes `retry`; offline / failed / denied → the ridge
// layout); its API and its pinned copy (`KuroStateCopy`) are unchanged.
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
        switch (kind, layout) {
        case (.loading, .page):
            KuroLoadingView(scope: .page, label: title)
        case (.loading, .inline):
            KuroLoadingView(scope: .inline, label: title)
        case (.empty, .page):
            // The invitation keeps the caller's refresh (Discover's "Nothing to show yet." has no other
            // on-screen way to reload; pull-to-refresh has no VoiceOver equivalent).
            KuroEmptyView(headline: shownTitle, message: shownMessage) {
                if let retry, Self.showsRetry(kind: kind, hasRetry: true) {
                    KuroOutlineButton(KuroStateCopy.retryTitle(german: KuroLocale.isGerman), action: retry)
                }
            }
        case (_, .page):
            // Offline and denied hold the ridge still; a failure draws it once.
            KuroStateLayout(stroke: KuroRidgeStroke(draws: isFailure), headline: shownTitle, message: shownMessage) {
                retryButton.frame(maxWidth: 280)
            }
        case (_, .inline):
            inlineBlock(title: shownTitle, message: shownMessage)
        }
    }

    private var isFailure: Bool {
        if case .failed = kind { return true }
        return false
    }

    /// Try again is offered for every state but loading whenever the caller can retry (pure).
    nonisolated static func showsRetry(kind: Kind, hasRetry: Bool) -> Bool {
        hasRetry && kind != .loading
    }

    @ViewBuilder
    private var retryButton: some View {
        if let retry, Self.showsRetry(kind: kind, hasRetry: true) {
            KuroInkButton(KuroStateCopy.retryTitle(german: KuroLocale.isGerman), role: .secondary, haptic: false, action: retry)
        }
    }

    /// The section-scoped form: a still ridge mark for offline / failed, the copy, Try again.
    private func inlineBlock(title shownTitle: String, message shownMessage: String?) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            if kind != .empty && kind != .denied {
                KuroRidgeStroke(draws: false, lineWidth: 1)
                    .frame(width: 36, height: 10)
            }
            Text(shownTitle)
                .font(.kuroBody(weight: .regular))
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
            if let shownMessage {
                Text(shownMessage)
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            retryButton.padding(.top, KuroDesignSpacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, KuroDesignSpacing.md)
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
