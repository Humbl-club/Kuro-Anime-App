import SwiftUI

// MARK: - First-Launch Onboarding (5-card horizontal pager)
// Shown once between auth and ContentView. Uses UserDefaults flag.

enum OnboardingDestination {
    case home
    case tasteDeck
}

struct OnboardingView: View {
    let onComplete: (OnboardingDestination) -> Void

    @State private var currentPage = 0
    @State private var appeared = false

    private let pages = OnboardingPage.allPages

    private var isGermanLocale: Bool {
        let language = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        return language.hasPrefix("de")
    }

    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingCard(
                            page: page,
                            isGerman: isGermanLocale
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: 420)

                // Dot indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(Color.black.opacity(currentPage == index ? 0.55 : 0.15))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 24)

                Spacer()

                // Bottom button
                VStack(spacing: 12) {
                    if currentPage < pages.count - 1 {
                        Button(action: {
                            withAnimation(KuroAnimation.editorial) {
                                currentPage += 1
                            }
                        }) {
                            Text(isGermanLocale ? "WEITER" : "CONTINUE")
                                .font(Font.kuroCaption(weight: .medium))
                                .tracking(2.0)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.88))
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: { completeOnboarding(.home) }) {
                            Text(isGermanLocale ? "Überspringen" : "Skip")
                                .font(Font.kuroCaption(weight: .medium))
                                .foregroundColor(.kuroTextTertiary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        if FeatureFlags.shared.tasteDeckV1Enabled {
                            // Deck owns index 0: the last card's primary CTA lands on it.
                            Button(action: { completeOnboarding(.tasteDeck) }) {
                                Text(isGermanLocale ? "ZEIG KURO DEINEN GESCHMACK" : "TEACH KURO YOUR TASTE")
                                    .font(Font.kuroCaption(weight: .medium))
                                    .tracking(2.0)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.black.opacity(0.88))
                                    )
                            }
                            .buttonStyle(.plain)

                            Button(action: { completeOnboarding(.home) }) {
                                Text(isGermanLocale ? "Überspringen" : "Skip")
                                    .font(Font.kuroCaption(weight: .medium))
                                    .foregroundColor(.kuroTextTertiary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: { completeOnboarding(.home) }) {
                                Text(isGermanLocale ? "LOS GEHT'S" : "GET STARTED")
                                    .font(Font.kuroCaption(weight: .medium))
                                    .tracking(2.0)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.black.opacity(0.88))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .onAppear {
            withAnimation(KuroAnimation.fadeIn) {
                appeared = true
            }
        }
    }

    private func completeOnboarding(_ destination: OnboardingDestination) {
        KuroAccessibility.impactHaptic(.light)
        UserDefaults.standard.set(true, forKey: "kuro_onboarding_completed")
        onComplete(destination)
    }
}

// MARK: - Onboarding Page Model

private struct OnboardingPage {
    let systemImage: String
    let titleEN: String
    let titleDE: String
    let subtitleEN: String
    let subtitleDE: String
    let bodyEN: String
    let bodyDE: String

    static let allPages: [OnboardingPage] = [
        OnboardingPage(
            systemImage: "rectangle.stack",
            titleEN: "Teach Kuro your taste",
            titleDE: "Zeig Kuro deinen Geschmack",
            subtitleEN: "TASTE",
            subtitleDE: "GESCHMACK",
            bodyEN: "A quiet ritual of yes and no — pass, know, or love, and Kuro learns what you love.",
            bodyDE: "Ein stilles Ritual aus Ja und Nein — und Kuro lernt, was du liebst."
        ),
        OnboardingPage(
            systemImage: "sparkles",
            titleEN: "Discover the feed",
            titleDE: "Entdecke den Feed",
            subtitleEN: "DISCOVER",
            subtitleDE: "ENTDECKEN",
            bodyEN: "Discover brings fresh picks, recommendations, and editorial flow into one quiet stream.",
            bodyDE: "Discover bringt frische Empfehlungen, Vorschläge und redaktionellen Fluss in einen ruhigen Stream."
        ),
        OnboardingPage(
            systemImage: "rectangle.grid.2x2",
            titleEN: "Browse by genre",
            titleDE: "Nach Genre stöbern",
            subtitleEN: "BROWSE",
            subtitleDE: "STÖBERN",
            bodyEN: "Browse opens the wider catalog, letting you move through genres and tags when you know the lane.",
            bodyDE: "Browse öffnet den größeren Katalog, damit du dich durch Genres und Tags bewegst, wenn du die Richtung schon kennst."
        ),
        OnboardingPage(
            systemImage: "square.stack.3d.up",
            titleEN: "Track your collection",
            titleDE: "Verfolge deine Sammlung",
            subtitleEN: "COLLECTION",
            subtitleDE: "SAMMLUNG",
            bodyEN: "Keep every title in sync with progress, ratings, and status filters that stay out of your way.",
            bodyDE: "Halte jeden Titel mit Fortschritt, Bewertungen und Statusfiltern synchron, ohne dass sie im Weg sind."
        ),
        OnboardingPage(
            systemImage: "person.3",
            titleEN: "Join the clubs",
            titleDE: "Tritt den Clubs bei",
            subtitleEN: "CLUBS",
            subtitleDE: "CLUBS",
            bodyEN: "Create or join clubs to watch together, share rails, and keep the conversation in one place.",
            bodyDE: "Erstelle oder tritt Clubs bei, um gemeinsam zu schauen, Rails zu teilen und die Unterhaltung an einem Ort zu halten."
        ),
    ]
}

// MARK: - Onboarding Card

private struct OnboardingCard: View {
    let page: OnboardingPage
    let isGerman: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Circle()
                .fill(Color.black.opacity(0.04))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: page.systemImage)
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.black.opacity(0.55))
                )

            // Eyebrow
            Text(isGerman ? page.subtitleDE : page.subtitleEN)
                .font(Font.kuroMicro(weight: .medium))
                .tracking(2.2)
                .foregroundColor(.kuroTextTertiary)

            // Title
            Text(isGerman ? page.titleDE : page.titleEN)
                .font(.kuroHeadline(weight: .ultraLight))
                .foregroundColor(.black.opacity(0.88))
                .multilineTextAlignment(.center)

            // Body
            Text(isGerman ? page.bodyDE : page.bodyEN)
                .font(Font.kuroBody(weight: .light))
                .foregroundColor(.black.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Helper

extension OnboardingView {
    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: "kuro_onboarding_completed")
    }
}
