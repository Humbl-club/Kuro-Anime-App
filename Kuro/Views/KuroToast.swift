import SwiftUI

struct KuroToastState: Identifiable {
    enum Kind: Equatable {
        case success
        case error
        case info
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String?
    let actionTitle: String?
    let onAction: (() -> Void)?
}

struct KuroToast: View {
    let toast: KuroToastState

    private var icon: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "sparkles"
        }
    }

    private var iconColor: Color {
        switch toast.kind {
        case .success: return .green
        case .error: return .orange
        case .info: return .black.opacity(0.75)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.2)
                    .foregroundColor(.black.opacity(0.9))

                if let subtitle = toast.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.black.opacity(0.55))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if let actionTitle = toast.actionTitle, let onAction = toast.onAction {
                Button(action: onAction) {
                    Text(actionTitle.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundColor(.black.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.70),
                                    Color.white.opacity(0.22),
                                    Color.black.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.16), radius: 20, x: 0, y: 12)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(toast.title). \(toast.subtitle ?? "")")
    }
}
