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
            header

            if showsIntentDeck {
                intentDeck()
                    .padding(.horizontal, KuroDesignSpacing.md)
                    .padding(.top, KuroDesignSpacing.sm)
                    .padding(.bottom, KuroDesignSpacing.sm)
            }

            responseStage()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            composer()
                .padding(.horizontal, KuroDesignSpacing.md)
                .padding(.top, KuroDesignSpacing.sm)
                .padding(.bottom, 8)

            footer()
                .padding(.horizontal, KuroDesignSpacing.md)
                .padding(.bottom, 10)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KURO")
                .font(.kuroMicro(weight: .medium))
                .tracking(2.2)
                .foregroundColor(.black.opacity(0.58))

            Text(title)
                .font(.system(size: 34, weight: .ultraLight, design: .serif))
                .foregroundColor(.black.opacity(0.84))
                .lineLimit(1)

            Text(subtitle)
                .font(.kuroBody(weight: .light))
                .foregroundColor(.black.opacity(0.72))
                .lineLimit(2)

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.kuroCaption())
                    .foregroundColor(.red.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KuroDesignSpacing.md)
        .padding(.top, KuroDesignSpacing.md)
        .padding(.bottom, KuroDesignSpacing.sm)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.98), Color.kuroBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.black.opacity(0.46))
                    .frame(width: 1.5, height: 11)
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
            }
            .padding(.horizontal, KuroDesignSpacing.md)
        }
    }
}
