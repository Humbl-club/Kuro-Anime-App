import KuroCore
import SwiftUI

// MARK: - First-run onboarding (spec D7, rulebook §14.8; acceptance open)
// At most three frames in the welcome's language: the mountain scenery as a still frame (ambient
// drift belongs to the welcome and the empty-Home invitation only), a serif cover line with a short
// ink rule, one sentence, and an ink-rule action with an arrow. No icon circles.
//   1. Anime or manga: persists the Home medium preference exactly as `HomeStore` stores it.
//   2. Bring your list: opens the existing import chooser (`ImportSourceChooser`), or skip. The
//      sentence names only the sources that import in the current world (MyAnimeList files need the
//      series foundation) and promises no review step (the legacy AniList path may auto-apply).
//   3. Clubs are private.
// Steps 2 and 3 show a Back chevron (top-left, "Back"/"Zurück") to the previous step (navigation
// contract N1); Skip stays top-right on steps 1 and 2.
// The copy works in both worlds (flags off: no Home page; flags on: Home). Completion is stored per
// account (`OnboardingCompletion`, Kuro/Identity), so a second account on the device sees it once too.

/// The onboarding steps in order (pure; tested in NavshellTests).
nonisolated enum OnboardingStep: Int, CaseIterable {
    case medium, list, clubs

    /// The step Back returns to (navigation contract N1); nil on the first step (no Back control).
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

enum OnboardingDestination {
    /// Land where the pager starts.
    case home
    /// The Taste page (TastePicksView in both pager orders).
    case tasteDeck
}

struct OnboardingView: View {
    let onComplete: (OnboardingDestination) -> Void

    @Environment(IdentityStore.self) private var identity
    @Environment(HomeStore.self) private var home
    @Environment(FeatureFlags.self) private var flags
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Frame = OnboardingStep

    @State private var frame: Frame = .medium
    @State private var medium: MediaKind = .anime
    @State private var showImport = false
    @AccessibilityFocusState private var headlineFocused: Bool

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        GeometryReader { geo in
            let bandHeight = min(max(geo.size.height * 0.34, 170), 320)
            ZStack(alignment: .top) {
                Color.kuroCanvasPage.ignoresSafeArea()

                KuroSceneryLoop(isActive: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: bandHeight + geo.safeAreaInsets.top)
                    .mask(
                        LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
                    )
                    .ignoresSafeArea(edges: .top)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: bandHeight * 0.82)
                            .accessibilityHidden(true)

                        KuroFormWordmark()

                        frameContent
                            .id(frame)
                            .transition(.opacity)
                            .padding(.top, KuroDesignSpacing.lg)

                        Spacer(minLength: KuroDesignSpacing.xl)

                        stepIndicator
                            .frame(maxWidth: .infinity)
                            .padding(.top, KuroDesignSpacing.lg)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, max(KuroDesignSpacing.lg, geo.safeAreaInsets.bottom + 8))
                    .frame(minHeight: geo.size.height, alignment: .top)
                    .kuroReadableWidth()
                }

                HStack {
                    // Back to the previous step (N1); the first step has none.
                    if let previous = frame.previous {
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            advance(to: previous)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 20))
                                .foregroundStyle(Color.kuroInk)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.kuroCanvasPage.opacity(0.92)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(KuroPressStyle())
                        .accessibilityLabel(german ? "Zurück" : "Back")
                    }
                    Spacer()
                    if frame != .clubs {
                        Button {
                            complete(.home)
                        } label: {
                            Text(german ? "Überspringen" : "Skip")
                                .font(.kuroMeta(weight: .medium))
                                .foregroundStyle(Color.kuroInk)
                                .padding(.horizontal, KuroDesignSpacing.md)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(Capsule().fill(Color.kuroCanvasPage.opacity(0.92)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(KuroPressStyle())
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.md)
                .padding(.top, KuroDesignSpacing.xs)
            }
        }
        .onAppear {
            medium = home.medium == "manga" ? .manga : .anime
        }
        .sheet(isPresented: $showImport) {
            // Onboarding ends where the pager starts, so no Collection filter is set here (it would be
            // invisible); the imported titles are in Collection like any other.
            // "Continue", not "See your lists": the lists are not on screen until onboarding ends.
            ImportSourceChooser(resultAction: .continueFlow) { _ in
                showImport = false
                advance(to: .clubs)
            }
        }
    }

    // MARK: Frames

    @ViewBuilder
    private var frameContent: some View {
        switch frame {
        case .medium:
            frameText(
                line: german ? "Anime oder Manga?" : "Anime or manga?",
                sentence: german
                    ? "Wähle, was du am meisten verfolgst. Du kannst jederzeit wechseln."
                    : "Choose what you follow most. You can switch any time."
            ) {
                KuroMediumSwitch(selection: $medium, size: .large)
                    .padding(.top, KuroDesignSpacing.lg)

                KuroInkButton(german ? "Weiter" : "Continue", role: .secondary) {
                    persistMedium()
                    advance(to: .list)
                }
                .padding(.top, KuroDesignSpacing.xl)
            }
        case .list:
            frameText(
                line: german ? "Bring deine Liste mit." : "Bring your list.",
                sentence: listSentence
            ) {
                KuroInkButton(german ? "Liste importieren" : "Import a list", role: .secondary) {
                    showImport = true
                }
                .padding(.top, KuroDesignSpacing.xl)

                Button {
                    advance(to: .clubs)
                } label: {
                    Text(german ? "Später" : "Not now")
                        .font(.kuroMeta(weight: .medium))
                        .underline()
                        .foregroundStyle(Color.kuroInkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, KuroDesignSpacing.sm)
            }
        case .clubs:
            frameText(
                line: german ? "Clubs sind privat." : "Clubs are private.",
                sentence: german
                    ? "Bis zu 20 Personen, per Einladungscode. Nur Mitglieder sehen, was dort geteilt wird."
                    : "Up to 20 people, by invite code. Only members see what’s shared there."
            ) {
                KuroInkButton(german ? "Los geht’s" : "Start", role: .secondary) {
                    complete(.home)
                }
                .padding(.top, KuroDesignSpacing.xl)
            }
        }
    }

    /// True in both worlds: MyAnimeList files import only with the series foundation on (flags off,
    /// the chooser's MAL file path is refused), and no review step is promised.
    private var listSentence: String {
        if flags.seriesFoundationV1Enabled {
            return german
                ? "Importiere von AniList oder aus einer MyAnimeList-Datei. Oder füge Titel nach und nach hinzu."
                : "Import from AniList or a MyAnimeList file. Or add titles as you go."
        }
        return german
            ? "Importiere deine Liste von AniList. Oder füge Titel nach und nach hinzu."
            : "Import your list from AniList. Or add titles as you go."
    }

    private func frameText<Actions: View>(
        line: String,
        sentence: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(line)
                .kuroRoleText(.feature)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headlineFocused)

            Rectangle()
                .fill(Color.kuroInk)
                .frame(width: 46, height: 2)
                .padding(.top, 14)
                .accessibilityHidden(true)

            Text(sentence)
                .font(.kuroBody(weight: .regular))
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            actions()
        }
    }

    /// Three short ink marks; the step is spoken, never printed as a number.
    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Frame.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == frame ? Color.kuroInk : Color.kuroHairline)
                    .frame(width: 22, height: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(german ? "Schritt \(frame.rawValue + 1) von 3" : "Step \(frame.rawValue + 1) of 3")
    }

    // MARK: Actions

    private func advance(to next: Frame) {
        withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) { frame = next }
        headlineFocused = true
    }

    /// The Home medium preference, under the same key `HomeStore` reads (`kuro.home.medium.<lowercased
    /// user id>`, per account; `HomeStore` reads it at bootstrap). With the series Home live, the store's
    /// own selection follows (it is already mounted). The choice also lands in Collection's own medium key
    /// (`kuro.folio.medium`, a per-device convenience Collection reads on its first load), so it takes
    /// effect this session in both worlds instead of after a relaunch.
    private func persistMedium() {
        let value = medium.rawValue
        if let userId = identity.currentUserId?.lowercased(), !userId.isEmpty {
            UserDefaults.standard.set(value, forKey: "kuro.home.medium.\(userId)")
        }
        UserDefaults.standard.set(value, forKey: "kuro.folio.medium")
        if flags.seriesHomeNativeV1Enabled, home.medium != value {
            home.selectMedium(value)
        }
    }

    private func complete(_ destination: OnboardingDestination) {
        KuroAccessibility.impactHaptic(.light)
        OnboardingCompletion.markCompleted(userId: identity.currentUserId)
        onComplete(destination)
    }
}

extension OnboardingView {
    /// Whether `userId`'s account has completed onboarding (read by the main view on appear; the
    /// signed-in tree is keyed by the account, so it is re-read on every account switch).
    static func hasCompletedOnboarding(for userId: String?) -> Bool {
        OnboardingCompletion.isCompleted(userId: userId)
    }
}
