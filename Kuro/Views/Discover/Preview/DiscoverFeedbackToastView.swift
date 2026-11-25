import SwiftUI

// MARK: - The feedback toast (spec 2026-11-04 §5.3, §13.3)
// `TastePlanToastView`'s anatomy, copied: `#282f2bf5`, 12 pt white text, radius 18, padding 5/5/5/14,
// inset 13/13/12 from the page foot, then an optional text action ("Add as Completed ›"), "Undo" and a
// dismiss ×. Every control is a 44 pt target. When the line and its three controls do not fit one row
// (German at 320, large text), the controls move under the message, so nothing truncates.

struct DiscoverFeedbackToastView: View {
    let message: String
    /// The optional text action's words (nil: none).
    let actionTitle: String?
    let actionSpoken: String
    let showsUndo: Bool
    let german: Bool
    let onAction: () -> Void
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                messageText
                    .frame(maxWidth: .infinity, alignment: .leading)
                controls
            }
            VStack(alignment: .leading, spacing: 0) {
                messageText
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if let actionTitle { actionButton(actionTitle).fixedSize() }
                    Spacer(minLength: 0)
                    if showsUndo { undoButton.fixedSize() }
                    dismissButton
                }
            }
            // The narrowest: × beside the message, then the action and Undo on their own line.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    messageText
                        .frame(maxWidth: .infinity, alignment: .leading)
                    dismissButton
                }
                HStack(spacing: 4) {
                    if let actionTitle {
                        actionButton(actionTitle)
                            .layoutPriority(1)
                    }
                    Spacer(minLength: 0)
                    if showsUndo { undoButton.fixedSize() }
                }
            }
        }
        .padding(.leading, 14)
        .padding([.top, .bottom, .trailing], 5)
        .background(Color.kuroControlInk.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 15, y: 8)
        .padding(.horizontal, 13)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
    }

    private var messageText: some View {
        Text(message)
            .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 22))
            .foregroundStyle(Color.white)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var controls: some View {
        if let actionTitle { actionButton(actionTitle).fixedSize() }
        if showsUndo { undoButton.fixedSize() }
        dismissButton
    }

    private func actionButton(_ title: String) -> some View {
        Button(action: onAction) {
            Text(title)
                .font(.kuroCustom(12, weight: .semibold, relativeTo: .footnote, maxSize: 22))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.97))
        .accessibilityLabel(actionSpoken)
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            Text(DiscoverMenuCopy.undo(german: german))
                .font(.kuroCustom(12, weight: .semibold, relativeTo: .footnote, maxSize: 22))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
                        )
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.96))
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.08), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.94))
        .accessibilityLabel(DiscoverMenuCopy.dismiss(german: german))
    }
}
