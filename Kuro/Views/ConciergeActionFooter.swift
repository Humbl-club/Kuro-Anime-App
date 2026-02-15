import SwiftUI

struct ConciergeActionFooter: View {
    let helperText: String
    let showUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(helperText)
                .font(.kuroCaption(weight: .light))
                .foregroundColor(.black.opacity(0.50))
                .lineLimit(1)

            Spacer(minLength: 0)

            if showUndo {
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    onUndo()
                }) {
                    Text("UNDO")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.4)
                        .foregroundColor(.black.opacity(0.78))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .stroke(Color.black.opacity(0.16), lineWidth: 0.7)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }
}

