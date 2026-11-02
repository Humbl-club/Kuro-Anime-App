import SwiftUI

// MARK: - Discard guard (navigation contract N7, docs/superpowers/specs/2026-11-02-navigation-contract-design.md)
//
// A tool sheet with unsaved input never loses it silently:
//   - swipe-down is blocked while the form has changes (or while it is saving),
//   - Cancel / ✕ asks "Discard changes?" first; a clean form closes at once.
//
//     .kuroDiscardGuard(isDirty: form.isDirty, isBusy: isSaving, isConfirming: $confirmDiscard) {
//         dismiss()                                    // what Discard does (after any reset)
//     }
//     Button(KuroDiscardGuard.cancelTitle) {
//         switch KuroDiscardGuard.cancelStep(isDirty: form.isDirty) {
//         case .close: dismiss()
//         case .confirm: confirmDiscard = true
//         }
//     }
//
// The rules are pure (`KuroDiscardGuard`, tested in NavclubsTests); the modifier only wires them.

/// The discard rules (pure).
nonisolated enum KuroDiscardGuard {
    /// What Cancel / ✕ does.
    enum CancelStep: Equatable {
        /// Nothing to lose: the sheet closes.
        case close
        /// Unsaved input: ask "Discard changes?" first.
        case confirm
    }

    static func cancelStep(isDirty: Bool) -> CancelStep {
        isDirty ? .confirm : .close
    }

    /// Whether swipe-down is blocked: unsaved input, or a save in flight.
    static func blocksInteractiveDismiss(isDirty: Bool, isBusy: Bool) -> Bool {
        isDirty || isBusy
    }

    static func title(german: Bool) -> String { german ? "Änderungen verwerfen?" : "Discard changes?" }
    static func message(german: Bool) -> String {
        german ? "Was du eingegeben hast, geht verloren." : "What you entered will be lost."
    }
    static func discardTitle(german: Bool) -> String { german ? "Verwerfen" : "Discard" }
    static func keepTitle(german: Bool) -> String { german ? "Weiter bearbeiten" : "Keep editing" }
    static func cancelTitle(german: Bool) -> String { german ? "Abbrechen" : "Cancel" }
}

extension View {
    /// Blocks swipe-down while `isDirty || isBusy` and shows the "Discard changes?" confirmation while
    /// `isConfirming` is true; Discard runs `onDiscard` (reset what must be reset, then dismiss).
    func kuroDiscardGuard(isDirty: Bool, isBusy: Bool = false, isConfirming: Binding<Bool>,
                          onDiscard: @escaping () -> Void) -> some View {
        let german = KuroLocale.isGerman
        return self
            .interactiveDismissDisabled(KuroDiscardGuard.blocksInteractiveDismiss(isDirty: isDirty, isBusy: isBusy))
            .confirmationDialog(KuroDiscardGuard.title(german: german),
                                isPresented: isConfirming,
                                titleVisibility: .visible) {
                Button(KuroDiscardGuard.discardTitle(german: german), role: .destructive) { onDiscard() }
                Button(KuroDiscardGuard.keepTitle(german: german), role: .cancel) {}
            } message: {
                Text(KuroDiscardGuard.message(german: german))
            }
    }
}
