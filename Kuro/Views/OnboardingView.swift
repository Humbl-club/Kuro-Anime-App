import SwiftUI

// MARK: - First-Launch Onboarding (3-card horizontal pager)
// Shown once between auth and ContentView. Uses UserDefaults flag.

struct OnboardingView: View {
    let onComplete: () -> Void

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

                        Button(action: { completeOnboarding() }) {
                            Text(isGermanLocale ? "Überspringen" : "Skip")
                                .font(Font.kuroCaption(weight: .medium))
                                .foregroundColor(.kuroTextTertiary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: { completeOnboarding() }) {
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

    private func completeOnboarding() {
        KuroAccessibility.impactHaptic(.light)
        UserDefaults.standard.set(true, forKey: "kuro_onboarding_completed")
        onComplete()
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
            systemImage: "hand.draw",
            titleEN: "Swipe to Navigate",
            titleDE: "Wische zum Navigieren",
            subtitleEN: "THREE SECTIONS",
            subtitleDE: "DREI BEREICHE",
            bodyEN: "Concierge, Discover, and Collection — all one swipe apart. Search and Browse are a tap away.",
            bodyDE: "Concierge, Entdecken und Sammlung — alles einen Wisch entfernt. Suche und Stobern sind einen Tipp entfernt."
        ),
        OnboardingPage(
            systemImage: "bubble.left.and.bubble.right",
            titleEN: "Your Concierge",
            titleDE: "Dein Concierge",
            subtitleEN: "IMPORT + CURATE",
            subtitleDE: "IMPORT + KURATIEREN",
            bodyEN: "Paste your anime list or describe a mood. The Concierge imports, matches, and curates — cleanly filtered.",
            bodyDE: "Fuge deine Liste ein oder beschreibe eine Stimmung. Der Concierge importiert, gleicht ab und kuratiert."
        ),
        OnboardingPage(
            systemImage: "square.stack.3d.up",
            titleEN: "Build Your Collection",
            titleDE: "Baue deine Sammlung",
            subtitleEN: "TRACK EVERYTHING",
            subtitleDE: "ALLES VERFOLGEN",
            bodyEN: "Your library stays in sync. Track progress, rate titles, and organize with status filters.",
            bodyDE: "Deine Bibliothek bleibt synchron. Verfolge Fortschritte, bewerte Titel und organisiere nach Status."
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
