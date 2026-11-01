import AuthenticationServices
import CryptoKit
import SwiftUI

// MARK: - Auth (welcome, email form, password reset, set new password)
// Welcome: the approved b943e457 composition (rulebook §14.8, FROZEN: scenery band at 52% of the
// height, "Kuro" serif 18, 33 pt serif headline, two 54 pt capsules, 11 pt legal line). Only tokens,
// German copy and tappable Terms/Privacy links were added; the English headline is unchanged.
// Email form (layout acceptance open): white page, ink focus (no blue ring, no red accent), Dynamic
// Type roles, @FocusState with Return chaining, VoiceOver labels, EN/DE copy (`AuthCopy`). Duplicate
// addresses are reported on submit only (spec D13: no live "taken" check). Sign-in accepts any
// non-empty password; sign-up keeps the 8-character rule.
// Data access stays in the owners: `SessionController` (sign-in/up, Apple, reset, new password) and
// `IdentityStore` (messages, link progress). The DEBUG-only Genie welcome (`-AuthGenieHero`) is kept
// as it was, below.

struct AuthView: View {
    @Environment(IdentityStore.self) private var identity
    @Environment(SessionController.self) private var session
    @Environment(DiscoveryStore.self) private var discovery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step { case welcome, welcomeGenie, email }

    @State private var step: Step = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-AuthShowEmail") {
            return .email
        }
        if ProcessInfo.processInfo.arguments.contains("-AuthGenieHero") {
            return .welcomeGenie
        }
        #endif
        return .welcome
    }()
    /// "Get started" opens Create account; returning users switch to Sign in with the tab.
    @State private var mode: AuthFormRules.Mode = .signUp

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var noticeText: String? = nil
    @State private var currentNonce: String? = nil
    @State private var showPassword = false
    @State private var submitAttempted = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, password }

    @State private var coverURLs: [URL] = []
    /// Soft staggered email-form entrance after the curtain lands.
    @State private var emailRevealed = false
    @State private var revealTask: Task<Void, Never>?
    @State private var showResetSheet = false
    /// The reset request's resend cooldown survives closing and reopening the sheet.
    @State private var resetCooldownUntil: Date? = nil

    private var german: Bool { KuroLocale.isGerman }

    /// Freeze hero at a second for Simulator screenshots: `-AuthHeroAt=2.8`
    private static var debugHeroAt: Double? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("-AuthHeroAt=") })?
            .split(separator: "=").last,
              let value = Double(raw) else { return nil }
        return value
        #else
        return nil
        #endif
    }

    /// Curtain-rise curve: scene exits up, form rises from below (kept; rulebook §14.8).
    private var curtainAnimation: Animation {
        if reduceMotion {
            return KuroMotion.resolve(KuroAnimation.editorial)
        }
        return .spring(response: 0.55, dampingFraction: 0.90)
    }

    var body: some View {
        ZStack {
            Color.kuroCanvasPage.ignoresSafeArea()

            switch step {
            case .welcome:
                welcomeStep
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            case .welcomeGenie:
                genieWelcomeStep
                    .transition(.opacity)
            case .email:
                emailStep
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .overlay(alignment: .top) {
            if identity.isOpeningAuthLink {
                AuthLinkProgress()
                    .padding(.top, KuroDesignSpacing.sm)
                    .transition(.opacity)
            }
        }
        .kuroAnimation(KuroMotion.settle, value: identity.isOpeningAuthLink)
        .animation(curtainAnimation, value: step)
        .task {
            #if DEBUG
            // Only the DEBUG Genie welcome shows covers; the shipping welcome makes no catalog request.
            if step == .welcomeGenie { await loadCovers() }
            #endif
        }
        .onAppear {
            if step == .email {
                revealEmailForm(animated: !reduceMotion)
            }
            takeAuthMessage(identity.authErrorMessage)
        }
        .onDisappear { revealTask?.cancel() }
        .onChange(of: identity.authErrorMessage) { _, newValue in
            takeAuthMessage(newValue)
        }
        .onChange(of: errorText) { _, newValue in
            if let newValue { AccessibilityNotification.Announcement(newValue).post() }
        }
        .onChange(of: noticeText) { _, newValue in
            if let newValue { AccessibilityNotification.Announcement(newValue).post() }
        }
        .sheet(isPresented: $showResetSheet) {
            AuthResetPasswordSheet(initialEmail: email, cooldownUntil: $resetCooldownUntil) { sentTo in
                email = sentTo
                noticeText = AuthCopy.resetSent(email: sentTo, german: german)
                errorText = nil
            }
        }
    }

    /// An auth failure published by the funnel (sign-in, rejected or expired link). The welcome never
    /// renders messages (frozen composition), so a message arriving there opens the sign-in form.
    private func takeAuthMessage(_ message: String?) {
        guard let message else { return }
        identity.authErrorMessage = nil
        noticeText = nil
        errorText = message
        if step != .email {
            mode = .signIn
            goToEmail(clearingMessages: false)
        }
    }

    private func goToEmail(clearingMessages: Bool = true) {
        if clearingMessages {
            errorText = nil
            noticeText = nil
        }
        emailRevealed = false
        withAnimation(curtainAnimation) { step = .email }
        // Stagger the form in just after the curtain starts rising (cancellable; no main-queue timer).
        revealTask?.cancel()
        let animated = !reduceMotion
        revealTask = Task { @MainActor in
            if animated { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            revealEmailForm(animated: animated)
        }
    }

    private func goToWelcome() {
        revealTask?.cancel()
        focusedField = nil
        emailRevealed = false
        withAnimation(curtainAnimation) { step = .welcome }
    }

    private func revealEmailForm(animated: Bool) {
        if animated {
            emailRevealed = true
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { emailRevealed = true }
        }
    }

    // MARK: - Welcome (approved composition + living scenery; frozen)

    private var welcomeStep: some View {
        GeometryReader { geo in
            ZStack {
                Color.kuroCanvasPage.ignoresSafeArea()
                welcomeScenery(in: geo)
                welcomeChrome(in: geo)
            }
        }
    }

    private func welcomeScenery(in geo: GeometryProxy) -> some View {
        let bannerH = geo.size.height * 0.52 + geo.safeAreaInsets.top
        return ZStack {
            VStack(spacing: 0) {
                KuroSceneryLoop()
                    .frame(maxWidth: .infinity)
                    .frame(height: bannerH)
                    .mask(
                        LinearGradient(
                            colors: [.black, .black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea(edges: .top)

                Spacer()
            }
        }
    }

    private func welcomeChrome(in geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                KuroWordmark()

                Text(german
                     ? "Dein nächster Lieblingsanime\nwartet schon auf dich"
                     : "Your next favorite anime,\nalready waiting for you")
                    .font(.kuroCustom(33, weight: .medium, design: .serif, relativeTo: .largeTitle, maxSize: 40))
                    .foregroundStyle(Color.kuroInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    mode = .signUp
                    goToEmail()
                } label: {
                    Text(german ? "Los geht’s" : "Get started")
                        .font(.kuroButtonLabel())
                        .foregroundStyle(Color.kuroWhite)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .background(Capsule().fill(Color.kuroInk))
                        .contentShape(Capsule())
                }
                .buttonStyle(KuroPressStyle())
                .disabled(isWorking)

                appleButton
                    .frame(height: 54)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.kuroKeyRim, lineWidth: 1)
                    )

                AuthLegalLine(context: .welcome)
                    .padding(.top, 6)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, max(18, geo.safeAreaInsets.bottom + 8))
        }
    }

    // MARK: - Welcome (Genie composition — DEBUG `-AuthGenieHero` only)

    private var genieWelcomeStep: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                AuthGenieHero(
                    urls: coverURLs,
                    reduceMotion: reduceMotion,
                    forcedTime: Self.debugHeroAt
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 10) {
                    appleButton
                        .frame(height: 52)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.kuroKeyRim, lineWidth: 1)
                        )

                    KuroInkButton(german ? "Weiter mit E-Mail" : "Continue with Email") {
                        goToEmail()
                    }
                    .disabled(isWorking)

                    AuthLegalLine(context: .welcome)
                        .padding(.top, 4)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, max(18, geo.safeAreaInsets.bottom + 8))
            }
        }
    }

    // MARK: - Email form

    private var emailStep: some View {
        let show = emailRevealed || reduceMotion
        return GeometryReader { geo in
            VStack(spacing: 0) {
                ZStack {
                    HStack {
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            goToWelcome()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.kuroCustom(16, weight: .semibold, relativeTo: .body, maxSize: 24))
                                .foregroundStyle(Color.kuroInk)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(KuroPressStyle())
                        .disabled(isWorking)
                        .accessibilityLabel(german ? "Zurück" : "Back")
                        Spacer()
                    }

                    KuroWordmark(size: 20, tracking: 0, opacity: 1)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .modifier(AuthStaggerEnter(revealed: show, delay: 0.00))

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mode == .signIn
                             ? (german ? "Willkommen zurück" : "Welcome back")
                             : (german ? "Werde Teil von Kuro" : "Join Kuro"))
                            .font(.kuroFeature(weight: .semibold))
                            .foregroundStyle(Color.kuroInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 28)
                            .modifier(AuthStaggerEnter(revealed: show, delay: 0.05))

                        Text(mode == .signIn
                             ? (german ? "Mach da weiter, wo du aufgehört hast." : "Pick up where you left off.")
                             : (german ? "Leg dein Regal an." : "Create your shelf."))
                            .font(.kuroBody(weight: .regular))
                            .foregroundStyle(Color.kuroInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                            .modifier(AuthStaggerEnter(revealed: show, delay: 0.10))

                        HStack(spacing: 26) {
                            modeTab(german ? "Anmelden" : "Sign in", selected: mode == .signIn) {
                                switchMode(.signIn)
                            }
                            modeTab(german ? "Konto erstellen" : "Create account", selected: mode == .signUp) {
                                switchMode(.signUp)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                        .modifier(AuthStaggerEnter(revealed: show, delay: 0.15))

                        VStack(alignment: .leading, spacing: 14) {
                            AuthField(
                                title: german ? "E-Mail" : "Email",
                                text: $email,
                                isSecure: false,
                                focus: $focusedField,
                                value: .email,
                                isDisabled: isWorking
                            ) {
                                emailStatus
                            }
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled(true)
                            .textContentType(.emailAddress)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .modifier(AuthStaggerEnter(revealed: show, delay: 0.20))

                            VStack(alignment: .leading, spacing: 8) {
                                AuthField(
                                    title: german ? "Passwort" : "Password",
                                    text: $password,
                                    isSecure: !showPassword,
                                    focus: $focusedField,
                                    value: .password,
                                    isDisabled: isWorking
                                ) {
                                    AuthPasswordVisibilityToggle(isVisible: $showPassword)
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .textContentType(mode == .signIn ? .password : .newPassword)
                                .submitLabel(.go)
                                .onSubmit { attemptSubmit() }

                                if mode == .signUp {
                                    AuthRuleLine(
                                        text: german ? "Mindestens 8 Zeichen" : "At least 8 characters",
                                        isMet: AuthFormRules.passwordMeetsSignUpRule(password)
                                    )
                                }
                            }
                            .modifier(AuthStaggerEnter(revealed: show, delay: 0.25))
                        }

                        if let errorText, !errorText.isEmpty {
                            AuthMessageLine(text: errorText, tone: .error)
                                .padding(.top, 14)
                        } else if let noticeText, !noticeText.isEmpty {
                            AuthMessageLine(text: noticeText, tone: .notice)
                                .padding(.top, 14)
                        }

                        KuroInkButton(
                            mode == .signIn ? (german ? "Weiter" : "Continue") : (german ? "Konto erstellen" : "Create account"),
                            isLoading: isWorking
                        ) {
                            attemptSubmit()
                        }
                        .disabled(isWorking)
                        .padding(.top, 24)
                        .modifier(AuthStaggerEnter(revealed: show, delay: 0.30))

                        if mode == .signIn {
                            Button {
                                errorText = nil
                                noticeText = nil
                                focusedField = nil
                                showResetSheet = true
                            } label: {
                                Text(german ? "Passwort vergessen?" : "Forgot password?")
                                    .font(.kuroMeta(weight: .medium))
                                    .underline()
                                    .foregroundStyle(Color.kuroInkSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)
                            .padding(.top, 8)
                            .modifier(AuthStaggerEnter(revealed: show, delay: 0.35))
                        } else {
                            AuthLegalLine(context: .signUp)
                                .padding(.top, 16)
                                .modifier(AuthStaggerEnter(revealed: show, delay: 0.35))
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, max(24, geo.safeAreaInsets.bottom + 8))
                    .kuroReadableWidth()
                    .background(
                        // Tapping outside the fields dismisses the keyboard.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { focusedField = nil }
                    )
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private func modeTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard !selected else { return }
            KuroAccessibility.impactHaptic(.light)
            withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) { action() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.kuroCustom(15, weight: .semibold, relativeTo: .subheadline, maxSize: 28))
                    .foregroundStyle(selected ? Color.kuroInk : Color.kuroInkQuiet)
                Rectangle()
                    .fill(selected ? Color.kuroInk : Color.clear)
                    .frame(width: 28, height: 2)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44, alignment: .bottomLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var emailStatus: some View {
        if AuthFormRules.emailLooksValid(email) {
            Image(systemName: "checkmark")
                .font(.kuroCustom(12, weight: .semibold, relativeTo: .footnote, maxSize: 20))
                .foregroundStyle(Color.kuroInkSecondary)
                .accessibilityLabel(german ? "Gültige E-Mail-Adresse" : "Valid email address")
        } else if !email.isEmpty, focusedField != .email || submitAttempted {
            Text(german ? "Adresse prüfen" : "Check the address")
                .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 20))
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize()
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            guard let nonce = Self.randomNonceString() else {
                errorText = german ? "Sicherheitsfehler. Versuche es erneut." : "Security error. Try again."
                return
            }
            currentNonce = nonce
            request.requestedScopes = [.email, .fullName]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            Task { await handleAppleSignIn(result) }
        }
        .signInWithAppleButtonStyle(.white)
        .disabled(isWorking)
    }

    // MARK: - Actions

    private func switchMode(_ next: AuthFormRules.Mode) {
        mode = next
        errorText = nil
        noticeText = nil
        submitAttempted = false
    }

    /// Validates locally first (nothing is sent for a form that can't succeed), then submits.
    private func attemptSubmit() {
        guard !isWorking else { return }
        submitAttempted = true
        if let problem = AuthFormRules.problem(mode: mode, email: email, password: password) {
            noticeText = nil
            errorText = AuthFormRules.message(for: problem, german: german)
            switch problem {
            case .emailMissing, .emailInvalid: focusedField = .email
            case .passwordMissing, .passwordTooShort: focusedField = .password
            }
            return
        }
        Task { await submit() }
    }

    private func submit() async {
        let address = AuthFormRules.trimmedEmail(email)
        errorText = nil
        noticeText = nil
        focusedField = nil
        isWorking = true
        defer { isWorking = false }
        do {
            switch mode {
            case .signIn:
                try await session.signInWithEmail(email: address, password: password)
            case .signUp:
                let outcome = try await session.signUpWithEmail(email: address, password: password)
                if outcome == .noSession {
                    // Email confirmation is on: the account waits for the link (no silent failure).
                    password = ""
                    mode = .signIn
                    noticeText = AuthCopy.signUpNeedsConfirmation(german: german)
                }
            }
        } catch is CancellationError {
            // A newer attempt (or a sign-out) superseded this one; it reports for itself.
        } catch {
            identity.authErrorMessage = nil
            errorText = AuthService.userFacingAuthErrorMessage(from: error)
            if mode == .signUp, AuthService.isAccountExistsError(error) {
                mode = .signIn
                focusedField = .password
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        // Cancelling the Apple sheet is not an error: stay where the user was, say nothing.
        if case .failure(let error) = result,
           let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            currentNonce = nil
            return
        }
        KuroAccessibility.impactHaptic(.medium)
        errorText = nil
        noticeText = nil
        isWorking = true
        defer { isWorking = false; currentNonce = nil }
        do {
            guard let credential = try result.get().credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let idToken = String(data: identityToken, encoding: .utf8),
                  let rawNonce = currentNonce else {
                showAppleFailure(AuthCopy.appleDidNotComplete(german: german))
                return
            }
            let fullName = credential.fullName.flatMap {
                [$0.givenName, $0.familyName].compactMap { $0 }.joined(separator: " ")
            }
            try await session.signInWithApple(idToken: idToken, rawNonce: rawNonce, fullName: fullName)
        } catch is CancellationError {
            // Superseded by a newer attempt.
        } catch {
            identity.authErrorMessage = nil
            showAppleFailure(error is ASAuthorizationError
                             ? AuthCopy.appleDidNotComplete(german: german)
                             : AuthService.userFacingAuthErrorMessage(from: error))
        }
    }

    /// The welcome renders no messages, so an Apple failure there opens the form to show it.
    private func showAppleFailure(_ message: String) {
        errorText = message
        if step != .email {
            mode = .signIn
            goToEmail(clearingMessages: false)
        }
    }

    #if DEBUG
    private func loadCovers() async {
        let anime = await discovery.fetchTrendingAnime(limit: 12)
        let urls = anime.compactMap { URL(string: $0.displayImage) }.filter { !$0.absoluteString.isEmpty }
        if !urls.isEmpty { coverURLs = Array(urls.prefix(6)) }
    }
    #endif

    private static func randomNonceString(length: Int = 32) -> String? {
        guard length > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let charset: [Swift.Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Brand mark

/// The welcome's "Kuro" serif mark (also the launch/bootstrap and set-password screens).
struct KuroWordmark: View {
    var size: CGFloat = 18
    var tracking: CGFloat = 4
    var opacity: Double = 0.72

    var body: some View {
        Text("Kuro")
            .font(.kuroCustom(size, weight: .semibold, design: .serif, relativeTo: .headline, maxSize: size + 8))
            .tracking(tracking)
            .foregroundStyle(Color.kuroInk.opacity(opacity))
            .accessibilityLabel("Kuro")
    }
}

// MARK: - Set new password (after a recovery link; spec D12)

/// Shown by the root instead of the app while `identity.requiresPasswordUpdate` is set: a password
/// reset link signed this account in, and it needs a new password before anything else. Sign out is
/// the escape (the requirement then ends with the session).
struct AuthSetPasswordView: View {
    @Environment(SessionController.self) private var session

    @State private var password = ""
    @State private var confirmation = ""
    @State private var showPassword = false
    @State private var isWorking = false
    @State private var errorText: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case password, confirmation }

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        ZStack {
            Color.kuroCanvasPage.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    KuroWordmark()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                    Text(german ? "Wähle ein neues Passwort" : "Choose a new password")
                        .font(.kuroFeature(weight: .semibold))
                        .foregroundStyle(Color.kuroInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 40)

                    Text(german
                         ? "Du hast einen Link zum Zurücksetzen geöffnet. Lege ein neues Passwort fest, um weiterzumachen."
                         : "You opened a reset link. Set a new password to continue.")
                        .font(.kuroBody(weight: .regular))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 14) {
                        AuthField(
                            title: german ? "Neues Passwort" : "New password",
                            text: $password,
                            isSecure: !showPassword,
                            focus: $focusedField,
                            value: .password,
                            isDisabled: isWorking
                        ) {
                            AuthPasswordVisibilityToggle(isVisible: $showPassword)
                        }
                        .textContentType(.newPassword)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirmation }

                        AuthField(
                            title: german ? "Passwort wiederholen" : "Repeat password",
                            text: $confirmation,
                            isSecure: !showPassword,
                            focus: $focusedField,
                            value: .confirmation,
                            isDisabled: isWorking
                        ) {
                            EmptyView()
                        }
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .onSubmit { attemptSave() }

                        AuthRuleLine(
                            text: german ? "Mindestens 8 Zeichen" : "At least 8 characters",
                            isMet: AuthFormRules.passwordMeetsSignUpRule(password)
                        )
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(.top, 28)

                    if let errorText {
                        AuthMessageLine(text: errorText, tone: .error)
                            .padding(.top, 14)
                    }

                    KuroInkButton(german ? "Passwort speichern" : "Save password", isLoading: isWorking) {
                        attemptSave()
                    }
                    .disabled(isWorking)
                    .padding(.top, 24)

                    Button {
                        Task { await session.signOut() }
                    } label: {
                        Text(german ? "Abmelden" : "Sign out")
                            .font(.kuroMeta(weight: .medium))
                            .underline()
                            .foregroundStyle(Color.kuroInkSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
                .kuroReadableWidth()
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { focusedField = nil }
                )
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: errorText) { _, newValue in
            if let newValue { AccessibilityNotification.Announcement(newValue).post() }
        }
    }

    private func attemptSave() {
        guard !isWorking else { return }
        if let problem = AuthFormRules.newPasswordProblem(password, confirmation: confirmation) {
            errorText = AuthFormRules.message(for: problem, german: german)
            focusedField = problem == .tooShort ? .password : .confirmation
            return
        }
        Task { await save() }
    }

    private func save() async {
        errorText = nil
        focusedField = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.updatePassword(password)
            KuroAccessibility.successHaptic()
        } catch is CancellationError {
            // The account changed meanwhile; the root re-renders for the new state.
        } catch {
            errorText = AuthService.userFacingAuthErrorMessage(from: error)
        }
    }
}

// MARK: - Reset password sheet

/// "Forgot password?": sends a reset link for this device (spec D12: the link only works on the
/// device that asked). The confirmation is neutral and enumeration-safe; a resend waits 60 s.
private struct AuthResetPasswordSheet: View {
    let initialEmail: String
    @Binding var cooldownUntil: Date?
    let onSent: (String) -> Void

    @Environment(SessionController.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var noticeText: String?
    @State private var now = Date()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email }
    private static let cooldown: TimeInterval = 60

    private var german: Bool { KuroLocale.isGerman }
    private var coolingDown: Bool { (cooldownUntil ?? .distantPast) > now }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(german ? "Schließen" : "Close") { dismiss() }
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .frame(minWidth: 44, minHeight: 44)
                }

                Text(german ? "Passwort zurücksetzen" : "Reset password")
                    .font(.kuroHeadline(weight: .regular))
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)

                Rectangle()
                    .fill(Color.kuroInk)
                    .frame(width: 46, height: 2)
                    .padding(.top, 12)
                    .accessibilityHidden(true)

                Text(german
                     ? "Wir schicken dir einen Link, mit dem du ein neues Passwort wählst. Öffne ihn auf diesem Gerät."
                     : "We’ll email you a link to choose a new password. Open it on this device.")
                    .font(.kuroBody(weight: .regular))
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                AuthField(
                    title: german ? "E-Mail" : "Email",
                    text: $email,
                    isSecure: false,
                    focus: $focusedField,
                    value: .email,
                    isDisabled: isWorking
                ) {
                    EmptyView()
                }
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled(true)
                .textContentType(.emailAddress)
                .submitLabel(.send)
                .onSubmit { attemptSend() }
                .padding(.top, 22)

                if let errorText {
                    AuthMessageLine(text: errorText, tone: .error)
                        .padding(.top, 14)
                } else if let noticeText {
                    AuthMessageLine(text: noticeText, tone: .notice)
                        .padding(.top, 14)
                }

                KuroInkButton(sendTitle, isLoading: isWorking) {
                    attemptSend()
                }
                .disabled(isWorking || coolingDown)
                .padding(.top, 22)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
            .kuroReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.kuroCanvasPage.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear {
            email = initialEmail
            if AuthFormRules.trimmedEmail(initialEmail).isEmpty { focusedField = .email }
        }
        .task(id: cooldownUntil) {
            // Re-enables the button when the resend cooldown ends (one wake-up, no ticking timer).
            now = Date()
            guard let until = cooldownUntil, until > now else { return }
            try? await Task.sleep(for: .seconds(until.timeIntervalSince(now)))
            guard !Task.isCancelled else { return }
            now = Date()
        }
        .onChange(of: errorText) { _, newValue in
            if let newValue { AccessibilityNotification.Announcement(newValue).post() }
        }
        .onChange(of: noticeText) { _, newValue in
            if let newValue { AccessibilityNotification.Announcement(newValue).post() }
        }
    }

    private var sendTitle: String {
        if coolingDown { return german ? "Gesendet" : "Sent" }
        if noticeText != nil { return german ? "Erneut senden" : "Send again" }
        return german ? "Link senden" : "Send link"
    }

    private func attemptSend() {
        guard !isWorking, !coolingDown else { return }
        let address = AuthFormRules.trimmedEmail(email)
        guard AuthFormRules.emailLooksValid(address) else {
            noticeText = nil
            errorText = AuthFormRules.message(for: address.isEmpty ? .emailMissing : .emailInvalid, german: german)
            focusedField = .email
            return
        }
        Task { await send(to: address) }
    }

    private func send(to address: String) async {
        errorText = nil
        focusedField = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.requestPasswordReset(email: address)
            cooldownUntil = Date().addingTimeInterval(Self.cooldown)
            noticeText = AuthCopy.resetSent(email: address, german: german)
            onSent(address)
        } catch {
            noticeText = nil
            errorText = AuthService.userFacingAuthErrorMessage(from: error)
        }
    }
}

// MARK: - Form parts

/// A labelled text field: quiet fill, hairline stroke, ink stroke while focused (no blue, no red).
private struct AuthField<FocusValue: Hashable, Trailing: View>: View {
    let title: String
    @Binding var text: String
    let isSecure: Bool
    let focus: FocusState<FocusValue?>.Binding
    let value: FocusValue
    let isDisabled: Bool
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        let isFocused = focus.wrappedValue == value
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.kuroMeta(weight: .semibold))
                .foregroundStyle(isFocused ? Color.kuroInk : Color.kuroInkSecondary)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                Group {
                    if isSecure {
                        SecureField(title, text: $text, prompt: Text(title).foregroundStyle(Color.kuroInkQuiet))
                    } else {
                        TextField(title, text: $text, prompt: Text(title).foregroundStyle(Color.kuroInkQuiet))
                    }
                }
                .font(.kuroCustom(17, weight: .regular, relativeTo: .body, maxSize: 30))
                .foregroundStyle(Color.kuroInk)
                .tint(Color.kuroInk)
                .focused(focus, equals: value)
                .disabled(isDisabled)

                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                    .fill(Color.kuroCanvasQuiet)
            )
            .overlay(
                RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                    .strokeBorder(isFocused ? Color.kuroInk : Color.kuroHairline, lineWidth: isFocused ? 1.5 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { if !isDisabled { focus.wrappedValue = value } }
            .kuroAnimation(KuroMotion.contact, value: isFocused)
        }
    }
}

/// Show/hide for password fields (44 pt target, labelled).
private struct AuthPasswordVisibilityToggle: View {
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Image(systemName: isVisible ? "eye.slash" : "eye")
                .font(.kuroCustom(15, weight: .regular, relativeTo: .body, maxSize: 24))
                .foregroundStyle(Color.kuroInkSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -12)
        .accessibilityLabel(isVisible
                            ? KuroLocale.text("Hide password", "Passwort ausblenden")
                            : KuroLocale.text("Show password", "Passwort anzeigen"))
    }
}

/// A requirement shown up front (not only after a failure), with a monochrome mark when met.
private struct AuthRuleLine: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark" : "circle")
                .font(.kuroCustom(10, weight: .semibold, relativeTo: .caption1, maxSize: 18))
                .foregroundStyle(Color.kuroInkSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isMet ? KuroLocale.text("Met", "Erfüllt") : KuroLocale.text("Not met yet", "Noch nicht erfüllt"))
    }
}

/// An inline message under a form: ink with a glyph for errors, secondary ink for neutral notices.
private struct AuthMessageLine: View {
    enum Tone { case error, notice }

    let text: String
    let tone: Tone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: tone == .error ? "exclamationmark.circle" : "envelope")
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(tone == .error ? Color.kuroInk : Color.kuroInkSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(tone == .error ? Color.kuroInk : Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Terms of Service and Privacy Policy as real links (they open in the browser).
private struct AuthLegalLine: View {
    enum Context { case welcome, signUp }

    let context: Context

    static let termsURL = "https://kuro.app/terms"
    static let privacyURL = "https://kuro.app/privacy"

    private var markdown: String {
        let terms = Self.termsURL, privacy = Self.privacyURL
        switch context {
        case .welcome:
            return KuroLocale.text(
                "By continuing, you agree to Kuro’s [Terms of Service](\(terms)) and [Privacy Policy](\(privacy)).",
                "Mit dem Fortfahren stimmst du den [Nutzungsbedingungen](\(terms)) und der [Datenschutzerklärung](\(privacy)) von Kuro zu."
            )
        case .signUp:
            return KuroLocale.text(
                "By creating an account, you agree to Kuro’s [Terms of Service](\(terms)) and [Privacy Policy](\(privacy)).",
                "Mit deinem Konto stimmst du den [Nutzungsbedingungen](\(terms)) und der [Datenschutzerklärung](\(privacy)) von Kuro zu."
            )
        }
    }

    private var attributed: AttributedString {
        guard var text = try? AttributedString(markdown: markdown) else {
            return AttributedString(markdown.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""))
        }
        for run in text.runs where run.link != nil {
            text[run.range].underlineStyle = .single
            text[run.range].foregroundColor = Color.kuroInk
        }
        return text
    }

    var body: some View {
        Text(attributed)
            .font(.kuroCustom(11, weight: .regular, relativeTo: .caption1, maxSize: 18))
            .foregroundStyle(Color.kuroInkQuiet)
            .tint(Color.kuroInk)
            .multilineTextAlignment(context == .welcome ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: context == .welcome ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Quiet progress while an email link is being applied.
private struct AuthLinkProgress: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.kuroInkQuiet)
            Text(KuroLocale.text("Opening your link…", "Link wird geöffnet …"))
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.kuroCanvasPage))
        .overlay(Capsule().strokeBorder(Color.kuroHairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Soft staggered rise used by the email form landing (ease-out, no overshoot).
private struct AuthStaggerEnter: ViewModifier {
    let revealed: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 12)
            .animation(.easeOut(duration: 0.32).delay(delay), value: revealed)
    }
}

// MARK: - Genie hero loop (Kuro assets, performant)

/// Genie welcome loop, matched frame-by-frame from the Mobbin ~15s video:
/// empty white → black dots grow (staggered) → covers bloom in → glowing orbs drift →
/// orbs melt into one colorful cluster (warm flash) → cluster darkens into ONE dark blob →
/// Kuro mark blooms out of the blob → blob shrinks to the left edge → typing bands → loop.
///
/// Smoothness rules:
/// - Orb faces (AsyncImage) are never rebuilt by a clock; all motion is state + SwiftUI animation.
/// - Multi-beat choreography is sequenced by the async driver (separate scalars per beat:
///   assembleGrow / converge / darken / bloom / logoLift) so every beat eases correctly.
/// - Per-node `.animation(value:)` modifiers add slot-staggered timing for organic motion.
private struct AuthGenieHero: View {
    let urls: [URL]
    var reduceMotion: Bool = false
    var forcedTime: Double? = nil

    private static let loopDuration: Double = 15.2
    /// Band + remnant-orb row, as a fraction of hero height (≈ 0.50 of the full screen).
    private static let bandY: CGFloat = 0.63

    private enum Act: Equatable {
        case empty
        case assemble
        case orbs
        case morph
        case fuse
        case prompts
    }

    @State private var act: Act = .empty
    @State private var assembleGrow: CGFloat = 0.08
    @State private var mediaRevealed = false
    @State private var converge: CGFloat = 0
    @State private var flash = false
    @State private var darken: CGFloat = 0
    @State private var bloom: CGFloat = 0
    @State private var logoLift: CGFloat = 0
    @State private var floating = false
    @State private var glowPulse = false
    @State private var promptIndex = 0
    @State private var typedCount = 0
    @State private var cursorOn = true
    @State private var promptEnter: CGFloat = 0
    @State private var loopTask: Task<Void, Never>?

    private struct OrbSlot: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let glow: Color
        let floatDuration: Double
        let floatX: CGFloat
        let floatY: CGFloat
        let isLogo: Bool
    }

    // Genie orb pentagon (traced from genie-f1 / t3.6), remapped into hero 0…1.
    private let slots: [OrbSlot] = [
        .init(id: 0, x: 0.48, y: 0.28, size: 0.355,
              glow: Color(red: 1.00, green: 0.72, blue: 0.42),
              floatDuration: 3.0, floatX: 4, floatY: -8, isLogo: false),
        .init(id: 1, x: 0.17, y: 0.42, size: 0.365,
              glow: Color(red: 0.40, green: 0.68, blue: 1.00),
              floatDuration: 3.6, floatX: -5, floatY: 7, isLogo: false),
        .init(id: 2, x: 0.86, y: 0.41, size: 0.375,
              glow: Color(red: 0.55, green: 0.90, blue: 0.95),
              floatDuration: 3.2, floatX: 6, floatY: 6, isLogo: true),
        .init(id: 3, x: 0.30, y: 0.62, size: 0.335,
              glow: Color(red: 0.72, green: 0.90, blue: 0.42),
              floatDuration: 2.8, floatX: -4, floatY: -6, isLogo: false),
        .init(id: 4, x: 0.74, y: 0.60, size: 0.340,
              glow: Color(red: 0.78, green: 0.60, blue: 0.98),
              floatDuration: 3.8, floatX: 5, floatY: 8, isLogo: false)
    ]

    private struct PromptBeat: Identifiable {
        let id: Int
        let lead: String
        let highlight: String
        let tint: Color
    }

    // Genie bands: one neutral near-white band color, dark lead text, tinted key word.
    private static let bandColor = Color(red: 0.976, green: 0.969, blue: 0.976)
    private static let lavender = Color(red: 0.54, green: 0.52, blue: 0.82)

    private let prompts: [PromptBeat] = [
        .init(id: 0, lead: "What should I watch tonight?", highlight: "",
              tint: Color(white: 0.22)),
        .init(id: 1, lead: "something like ", highlight: "Frieren",
              tint: Self.lavender),
        .init(id: 2, lead: "best ", highlight: "shonen",
              tint: Color(red: 0.90, green: 0.42, blue: 0.36)),
        .init(id: 3, lead: "is ", highlight: "One Piece",
              tint: Color(red: 0.30, green: 0.62, blue: 0.92)),
        .init(id: 4, lead: "a good ", highlight: "comfort anime",
              tint: Self.lavender),
        .init(id: 5, lead: "finish ", highlight: "Chainsaw Man?",
              tint: Color(red: 0.94, green: 0.56, blue: 0.28))
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white

                if act == .assemble || act == .orbs || act == .morph || act == .fuse {
                    orbFieldLayer(geo: geo)
                }

                if act == .prompts {
                    promptLayer(geo: geo)
                        .transition(.opacity)
                }

                // Above the band: the remnant orb peeks in at the band's left edge (Genie t9.5+)
                if act == .fuse || act == .prompts {
                    fuseLogoNode(geo: geo)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kuro")
        .onAppear { startLoop() }
        .onDisappear { loopTask?.cancel() }
        .onChange(of: forcedTime) { _, _ in applyForcedTimeIfNeeded() }
    }

    // MARK: - Orb field

    private func orbFieldLayer(geo: GeometryProxy) -> some View {
        let field = ZStack {
            ForEach(slots) { slot in
                orbNode(slot: slot, geo: geo)
            }
        }

        return ZStack {
            // Liquid fusion: soft-threshold the blurred orb field during melt/fuse
            if act == .morph || act == .fuse {
                field
                    .blur(radius: 8)
                    .layerEffect(
                        MetaballShaders.library.kuroMetaball(
                            .boundingRect,
                            .float(0.5),
                            .float(0.10 + converge * 0.06)
                        ),
                        maxSampleOffset: .zero
                    )
            } else {
                field
            }

            // Warm ring flash as the orbs first touch (Genie ~t4.25)
            warmFlashNode(geo: geo)
        }
    }

    private func warmFlashNode(geo: GeometryProxy) -> some View {
        let w = geo.size.width
        return Circle()
            .stroke(Color(red: 1.0, green: 0.70, blue: 0.34).opacity(flash ? 0.55 : 0), lineWidth: 3)
            .frame(width: w * (flash ? 0.62 : 0.40))
            .blur(radius: 9)
            .position(x: w * 0.5, y: geo.size.height * 0.52)
            .animation(.easeInOut(duration: 0.5), value: flash)
            .allowsHitTesting(false)
    }

    private func orbNode(slot: OrbSlot, geo: GeometryProxy) -> some View {
        let w = geo.size.width
        let h = geo.size.height
        let mediaIdx = coverIndex(for: slot)

        // Position: home → fusion point as `converge` ramps
        let nx = mix(slot.x, 0.50, converge)
        let ny = mix(slot.y, 0.52, converge)

        // Size: staggered grow → slight swell while melting → sink into the blob
        let swell = 1 + 0.12 * converge - 0.48 * darken
        let sizeFrac = slot.size * assembleGrow * max(0.3, swell)
        let diameter = w * sizeFrac

        // Faces stay visible through the melt, then dissolve as the blob darkens
        let faceOpacity: CGFloat = mediaRevealed ? max(0, 1 - darken * 2.2) : 0
        let faceBlur: CGFloat = converge * 3 + darken * 9

        // Black seeds: assemble dots, hidden behind media, resurface while darkening
        let seedBase: CGFloat = mediaRevealed ? 0 : 1
        let seedOpacity = max(seedBase, min(0.95, darken * 2.4))
        let seedBlur: CGFloat = darken * 14

        // Dark rims between lobes while melting (Genie melt edges)
        let rimOpacity = Double(converge * 0.45 * max(0, 1 - darken * 2))

        // Pastel halos merge into a warm bloom, then die into the blob
        let glowBase = Double(glowPulse ? 0.46 : 0.30)
        let glowOpacity = mediaRevealed ? glowBase * Double(max(0, 1 - darken * 1.3)) : 0
        let glowScale: CGFloat = 1.45 + converge * 0.25
        let glowBlur: CGFloat = 28 + converge * 10

        // Node fades once the fused blob owns the frame
        let nodeFade = Double(max(0, 1 - max(0, darken - 0.55) / 0.30))

        let floatX: CGFloat = (floating && act == .orbs && !reduceMotion) ? slot.floatX : 0
        let floatY: CGFloat = (floating && act == .orbs && !reduceMotion) ? slot.floatY : 0
        let floatAnim: Animation = (act == .orbs && !reduceMotion)
            ? .easeInOut(duration: slot.floatDuration).repeatForever(autoreverses: true)
            : .easeInOut(duration: 0.5)

        let faceURL: URL? = slot.isLogo ? nil : (mediaIdx < urls.count ? urls[mediaIdx] : nil)
        let stagger = Double(slot.id) * 0.07

        return ZStack {
            Circle()
                .fill(slot.glow.opacity(glowOpacity))
                .frame(width: diameter * glowScale, height: diameter * glowScale)
                .blur(radius: glowBlur)

            Circle()
                .fill(Color.black)
                .frame(width: diameter, height: diameter)
                .opacity(Double(seedOpacity))
                .blur(radius: seedBlur)

            AuthGenieOrbFace(
                url: faceURL,
                isLogo: slot.isLogo,
                placeholderIndex: mediaIdx
            )
            .frame(width: diameter, height: diameter)
            .opacity(Double(faceOpacity))
            .blur(radius: faceBlur)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(rimOpacity), lineWidth: 1.5)
                    .frame(width: diameter, height: diameter)
            )
        }
        .frame(width: diameter * 1.4, height: diameter * 1.4)
        .position(x: w * nx, y: h * ny)
        .offset(x: floatX, y: floatY)
        .opacity(nodeFade)
        .animation(.spring(response: 0.6, dampingFraction: 0.78).delay(stagger), value: assembleGrow)
        .animation(.easeInOut(duration: 0.55).delay(stagger * 0.7), value: mediaRevealed)
        .animation(.easeInOut(duration: 1.25).delay(stagger * 0.5), value: converge)
        .animation(.easeInOut(duration: 1.05), value: darken)
        .animation(floatAnim, value: floating)
    }

    // MARK: - Fused blob → Kuro mark → remnant orb

    /// One node owns the whole fusion tail so every hand-off is a real animation:
    /// darken 0→1: one large dark blob (~0.64 w) resolves at center.
    /// bloom 0→1: the cream Kuro mark circle blooms out of the blob.
    /// logoLift 0→1: the orb shrinks and glides to the left edge of the prompt band (Genie t9.5+).
    private func fuseLogoNode(geo: GeometryProxy) -> some View {
        let w = geo.size.width
        let h = geo.size.height

        let x = mix(0.50, 0.045, logoLift)
        let y = mix(0.52, Self.bandY, logoLift)

        let bigWidth = w * (0.30 + 0.34 * darken)
        let width = bigWidth * (1 - 0.72 * logoLift)

        let blobOpacity = Double(min(1, darken * 2)) * Double(1 - bloom)
        let blobBlur: CGFloat = (20 - darken * 12) * (1 - logoLift * 0.8)

        let markOpacity = Double(bloom)
        let markScale: CGFloat = 0.84 + bloom * 0.16

        let glowOpacity = Double(darken) * 0.20 * Double(1 - logoLift)

        return ZStack {
            // Warm bloom behind the blob while it is centered
            Circle()
                .fill(Color(red: 1.0, green: 0.78, blue: 0.45).opacity(glowOpacity))
                .frame(width: width * 1.45, height: width * 1.45)
                .blur(radius: 26)

            // Dark blob
            Circle()
                .fill(Color(red: 0.07, green: 0.06, blue: 0.05))
                .frame(width: width, height: width)
                .blur(radius: blobBlur)
                .opacity(blobOpacity)

            // Kuro mark circle blooming out of the blob
            Image("KuroMark")
                .resizable()
                .scaledToFill()
                .frame(width: width, height: width)
                .clipShape(Circle())
                .scaleEffect(markScale)
                .opacity(markOpacity)
                .shadow(color: .black.opacity(0.16 * markOpacity), radius: 9, x: 0, y: 5)
        }
        .position(x: w * x, y: h * y)
        .animation(.easeInOut(duration: 1.05), value: darken)
        .animation(.easeInOut(duration: 0.85), value: bloom)
        .animation(.spring(response: 0.75, dampingFraction: 0.85), value: logoLift)
        .allowsHitTesting(false)
    }

    // MARK: - Prompts (Genie bands: full-bleed, ~20% of screen, 40pt type)

    private func promptLayer(geo: GeometryProxy) -> some View {
        let beat = prompts[min(promptIndex, prompts.count - 1)]
        let full = beat.lead + beat.highlight
        let typed = String(full.prefix(typedCount))
        let leadShown = typed.count <= beat.lead.count ? typed : beat.lead
        let highlightShown = typed.count <= beat.lead.count ? "" : String(typed.dropFirst(beat.lead.count))
        let side: CGFloat = promptIndex % 2 == 0 ? 1 : -1

        return Rectangle()
            .fill(Self.bandColor)
            .frame(height: 177)
            .frame(maxWidth: .infinity)
            .overlay(
                HStack(spacing: 0) {
                    Text(leadShown).foregroundColor(Color(white: 0.22))
                    Text(highlightShown).foregroundColor(beat.tint)
                    if cursorOn || typedCount < full.count {
                        Text("|").foregroundColor(Color(white: 0.28))
                    }
                }
                .font(.system(size: 40, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.leading, 78)
                .padding(.trailing, 30),
                alignment: .leading
            )
            .offset(x: (1 - promptEnter) * side * geo.size.width * 0.22)
            .opacity(Double(promptEnter))
            .position(x: geo.size.width * 0.5, y: geo.size.height * Self.bandY)
            .allowsHitTesting(false)
    }

    private func coverIndex(for slot: OrbSlot) -> Int {
        slots.filter { !$0.isLogo }.firstIndex(where: { $0.id == slot.id }) ?? 0
    }

    private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    // MARK: - Loop driver (async sequencing; node animations do the easing)

    private func startLoop() {
        loopTask?.cancel()

        if forcedTime != nil {
            applyForcedTimeIfNeeded()
            return
        }

        if reduceMotion {
            act = .orbs
            mediaRevealed = true
            assembleGrow = 1
            floating = false
            return
        }

        loopTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowPulse = true
            }

            while !Task.isCancelled {
                // EMPTY — pure white (Genie t0–0.5)
                act = .empty
                assembleGrow = 0.08
                mediaRevealed = false
                converge = 0
                darken = 0
                bloom = 0
                logoLift = 0
                flash = false
                floating = false
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }

                // ASSEMBLE — dots grow in place, slot-staggered springs (t0.5–1.85)
                act = .assemble
                assembleGrow = 1.0
                try? await Task.sleep(for: .milliseconds(1350))
                guard !Task.isCancelled else { return }

                // MEDIA — covers bloom in, slightly staggered (t1.85–2.35)
                mediaRevealed = true
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                // ORBS — pastel halos breathe, orbs drift independently (t2.35–4.1)
                act = .orbs
                floating = true
                try? await Task.sleep(for: .milliseconds(1750))
                guard !Task.isCancelled else { return }

                // MORPH — melt into one colorful cluster + warm flash (t4.1–5.35)
                act = .morph
                floating = false
                converge = 1
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                flash = true
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                flash = false
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                // FUSE 1 — cluster darkens into ONE large dark blob (t5.35–6.45)
                act = .fuse
                darken = 1
                try? await Task.sleep(for: .milliseconds(1100))
                guard !Task.isCancelled else { return }

                // FUSE 2 — Kuro mark blooms out of the blob (t6.45–7.4)
                bloom = 1
                try? await Task.sleep(for: .milliseconds(950))
                guard !Task.isCancelled else { return }

                // PROMPTS — orb glides to the band row, typing bands (t7.4+)
                act = .prompts
                logoLift = 1
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await runPrompts()
                guard !Task.isCancelled else { return }
            }
        }
    }

    @MainActor
    private func runPrompts() async {
        for idx in prompts.indices {
            guard !Task.isCancelled else { return }
            promptIndex = idx
            typedCount = 0
            promptEnter = 0
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { promptEnter = 1 }

            let full = prompts[idx].lead + prompts[idx].highlight
            let charDelay = max(30, 620 / max(full.count, 1))
            for n in 1...full.count {
                guard !Task.isCancelled else { return }
                typedCount = n
                cursorOn.toggle()
                try? await Task.sleep(for: .milliseconds(charDelay))
            }
            // Hold with a blinking cursor
            let holdMs = max(380, 1150 - full.count * charDelay)
            let end = Date().addingTimeInterval(Double(holdMs) / 1000.0)
            while Date() < end {
                guard !Task.isCancelled else { return }
                cursorOn.toggle()
                try? await Task.sleep(for: .milliseconds(400))
            }
            withAnimation(.easeIn(duration: 0.22)) { promptEnter = 0 }
            try? await Task.sleep(for: .milliseconds(200))
        }

        // Fade the remnant orb before the loop resets to white (no hard pop)
        withAnimation(.easeIn(duration: 0.4)) {
            darken = 0
            bloom = 0
        }
        try? await Task.sleep(for: .milliseconds(420))
    }

    private func applyForcedTimeIfNeeded() {
        guard let forcedTime else { return }
        applyForcedSnapshot(forcedTime)
    }

    private func applyForcedSnapshot(_ t: Double) {
        loopTask?.cancel()
        let x = t.truncatingRemainder(dividingBy: Self.loopDuration)
        floating = false
        glowPulse = true
        flash = false
        logoLift = 0
        if x < 0.4 {
            act = .empty; assembleGrow = 0.08; mediaRevealed = false
            converge = 0; darken = 0; bloom = 0
        } else if x < 1.85 {
            act = .assemble; mediaRevealed = false
            assembleGrow = CGFloat(min(1, (x - 0.4) / 1.3)); converge = 0; darken = 0; bloom = 0
        } else if x < 4.1 {
            act = .orbs; assembleGrow = 1; converge = 0; darken = 0; bloom = 0
            mediaRevealed = x >= 2.1
            floating = x >= 2.4
        } else if x < 5.35 {
            act = .morph; mediaRevealed = true; assembleGrow = 1
            converge = CGFloat((x - 4.1) / 1.25); darken = 0; bloom = 0
            flash = x >= 4.35 && x < 5.0
        } else if x < 6.45 {
            act = .fuse; mediaRevealed = true; assembleGrow = 1; converge = 1
            darken = CGFloat((x - 5.35) / 1.1); bloom = 0
        } else if x < 7.4 {
            act = .fuse; mediaRevealed = true; assembleGrow = 1; converge = 1
            darken = 1; bloom = CGFloat((x - 6.45) / 0.95)
        } else {
            act = .prompts; mediaRevealed = false; assembleGrow = 0.08
            converge = 0; darken = 1; bloom = 1; logoLift = 1
            let local = x - 7.4
            let idx = min(prompts.count - 1, Int(local / 1.25))
            promptIndex = idx
            let beat = prompts[idx]
            let full = beat.lead + beat.highlight
            typedCount = full.count
            promptEnter = 1
            cursorOn = true
        }
    }
}

// MARK: - Stable orb face (never depends on clock)

private struct AuthGenieOrbFace: View, Equatable {
    let url: URL?
    let isLogo: Bool
    let placeholderIndex: Int

    static func == (lhs: AuthGenieOrbFace, rhs: AuthGenieOrbFace) -> Bool {
        lhs.url == rhs.url && lhs.isLogo == rhs.isLogo && lhs.placeholderIndex == rhs.placeholderIndex
    }

    var body: some View {
        ZStack {
            if isLogo {
                // Clean cream circle with the Kuro mark — no glass-orb gloss
                Image("KuroMark")
                    .resizable()
                    .scaledToFill()
            } else {
                AuthGenieLiveCover(
                    url: url,
                    placeholderIndex: placeholderIndex,
                    seed: placeholderIndex
                )

                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.08), Color.black.opacity(0.32)],
                    center: .center,
                    startRadius: 20,
                    endRadius: 200
                )
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 70, height: 36)
                    .offset(x: -8, y: -28)
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.2)
            }
        }
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 5)
    }
}

private struct AuthGeniePlaceholder: View {
    let index: Int
    var body: some View {
        let hues: [Double] = [0.08, 0.58, 0.45, 0.78, 0.12]
        let hue = hues[index % hues.count]
        LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.28, brightness: 0.9),
                Color(hue: hue, saturation: 0.45, brightness: 0.42)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// A cover that is never still: slow pan + zoom breathing inside the orb,
/// with a slot-staggered start so the five orbs move independently.
private struct AuthGenieLiveCover: View, Equatable {
    let url: URL?
    let placeholderIndex: Int
    let seed: Int

    static func == (lhs: AuthGenieLiveCover, rhs: AuthGenieLiveCover) -> Bool {
        lhs.url == rhs.url && lhs.placeholderIndex == rhs.placeholderIndex && lhs.seed == rhs.seed
    }

    var body: some View {
        ZStack {
            if let url {
                KuroCachedAsyncImage(url: url, maxPixelSize: 480) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        AuthGeniePlaceholder(index: placeholderIndex)
                    }
                }
            } else {
                AuthGeniePlaceholder(index: placeholderIndex)
            }
        }
        // Overscan so panning never shows edges; keyframed drift per slot
        .scaleEffect(1.22)
        .keyframeAnimator(initialValue: CoverDrift(), repeating: true) { content, value in
            content
                .scaleEffect(1.22 + value.zoom)
                .offset(x: value.x, y: value.y)
        } keyframes: { _ in
            let d = 4.0 + Double(seed % 4) * 0.7
            let a = Double(seed) * 1.7
            KeyframeTrack(\.x) {
                CubicKeyframe(0, duration: d)
                CubicKeyframe(CGFloat(7 * cos(a)), duration: d)
                CubicKeyframe(CGFloat(-6 * cos(a * 1.3)), duration: d)
                CubicKeyframe(0, duration: d)
            }
            KeyframeTrack(\.y) {
                CubicKeyframe(0, duration: d)
                CubicKeyframe(CGFloat(6 * sin(a)), duration: d)
                CubicKeyframe(CGFloat(-7 * sin(a * 1.4)), duration: d)
                CubicKeyframe(0, duration: d)
            }
            KeyframeTrack(\.zoom) {
                CubicKeyframe(0, duration: d)
                CubicKeyframe(0.05, duration: d * 1.4)
                CubicKeyframe(0, duration: d)
            }
        }
    }

    struct CoverDrift {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var zoom: CGFloat = 0
    }
}

// MARK: - Liquid metaball fusion (SwiftUI layer-effect shader)

/// Metal shader: soft-thresholds the blurred shapes so overlapping orbs
/// fuse into one liquid blob, with a warm edge where they meet.
private enum MetaballShaders {
    static let library: ShaderLibrary = {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        #include <SwiftUI/SwiftUI_Metal.h>

        [[ stitchable ]] half4 kuroMetaball(
            float2 position,
            SwiftUI::Layer layer,
            float4 bounds,
            float threshold,
            float smoothness
        ) {
            half4 c = layer.sample(position);
            half a = c.a;
            half lo = half(threshold - smoothness);
            half hi = half(threshold + smoothness);
            half t = smoothstep(lo, hi, a);
            half edge = smoothstep(lo, half(threshold), a) * (1.0h - t);
            half3 warm = half3(1.0h, 0.72h, 0.34h);
            half3 col = mix(c.rgb, warm, clamp(edge * 1.4h, 0.0h, 0.5h));
            return half4(col, t);
        }
        """
        return ShaderLibrary(data: Data(source.utf8))
    }()
}

