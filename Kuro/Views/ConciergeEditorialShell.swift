import SwiftUI

struct ConciergeEditorialShell<IntentDeck: View, ResponseStage: View, Composer: View, Footer: View>: View {
    let title: String
    let subtitle: String
    let errorText: String?
    let showsIntentDeck: Bool
    @ViewBuilder let intentDeck: () -> IntentDeck
    @ViewBuilder let responseStage: () -> ResponseStage
    @ViewBuilder let composer: () -> Composer
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            responseStage()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay {
                    if showsIntentDeck {
                        WhisperEmptyState(text: subtitle)
                    }
                }

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.kuroCaption())
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            composer()
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(height: 0.5)
                        Color.white
                    }
                )

            footer()
                .frame(height: 0)
                .opacity(0)
        }
    }
}

private struct WhisperEmptyState: View {
    let text: String

    var body: some View {
        VStack(spacing: 18) {
            WhisperMoonMark(size: 56)
            Text(text)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundColor(.black.opacity(0.55))
                .tracking(0.3)
                .lineSpacing(2)
                .padding(.horizontal, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .offset(y: 10)))
        .animation(.easeInOut(duration: 0.5), value: text)
    }
}

private struct WhisperMoonMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Image(systemName: "moon.fill")
                .font(.system(size: size * 0.72, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.55))

            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: size * 0.14, height: size * 0.14)
                .offset(x: size * 0.17, y: -size * 0.15)
        }
        .frame(width: size, height: size)
    }
}
