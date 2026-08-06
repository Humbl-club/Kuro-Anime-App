import AuthenticationServices
import CryptoKit
import SwiftUI

// Genie-faithful welcome loop + Genie email form, Kuro assets.
// Welcome choreography (~15s): assemble → glowing orbs → metaball morph → typing prompts.
// CTAs fixed: Apple outline + Email solid black.

struct AuthView: View {
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step { case welcome, welcomeGenie, email }
    private enum Mode { case signIn, signUp }

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
    @State private var mode: Mode = .signIn

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var currentNonce: String? = nil
    @State private var showPassword = false
    @State private var focusedField: Field? = nil

    private enum Field { case email, password }
    private enum EmailStatus { case empty, invalidFormat, checking, taken, available }
    private enum PasswordStatus { case empty, tooShort, valid }

    @State private var emailStatus: EmailStatus = .empty
    @State private var passwordStatus: PasswordStatus = .empty
    @State private var emailCheckTask: Task<Void, Never>?

    @State private var coverURLs: [URL] = []
    /// Soft staggered email-form entrance after the curtain lands.
    @State private var emailRevealed = false

    private static let emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/
    private static let ink = Color(red: 22 / 255, green: 20 / 255, blue: 18 / 255)
    private static let accent = Color(red: 160 / 255, green: 40 / 255, blue: 35 / 255)

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

    /// Curtain-rise curve: scene exits up, form rises from below.
    private var curtainAnimation: Animation {
        if reduceMotion {
            return KuroMotion.resolve(KuroAnimation.editorial)
        }
        return .spring(response: 0.55, dampingFraction: 0.90)
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

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
        .animation(curtainAnimation, value: step)
        .task { await loadCovers() }
        .onAppear {
            if step == .email {
                revealEmailForm(animated: !reduceMotion)
            }
        }
        .onChange(of: email) { _, _ in revalidateEmail() }
        .onChange(of: password) { _, _ in revalidatePassword() }
        .onChange(of: supabaseService.authErrorMessage) { _, newValue in
            if let msg = newValue {
                errorText = msg
                supabaseService.authErrorMessage = nil
            }
        }
    }

    private func goToEmail() {
        errorText = nil
        emailRevealed = false
        withAnimation(curtainAnimation) { step = .email }
        // Stagger form in just after the curtain starts rising.
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.18)) {
            revealEmailForm(animated: !reduceMotion)
        }
    }

    private func goToWelcome() {
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

    // MARK: - Welcome (Anything composition + living scenery)

    private var welcomeStep: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()
                welcomeScenery(in: geo)
                welcomeChrome(in: geo)
            }
        }
    }

    private func welcomeScenery(in geo: GeometryProxy) -> some View {
        let bannerH = geo.size.height * 0.52 + geo.safeAreaInsets.top
        return ZStack {
            VStack(spacing: 0) {
                AuthSceneryLoop()
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

            AuthZenTV(height: bannerH)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    private func welcomeChrome(in geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Text("Kuro")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundColor(Self.ink.opacity(0.72))

                Text("Your next favorite anime,\nalready waiting for you")
                    .font(.system(size: 33, weight: .medium, design: .serif))
                    .foregroundColor(Self.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    goToEmail()
                } label: {
                    Text("Get started")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(Self.ink))
                }
                .buttonStyle(AuthPressStyle())
                .disabled(isWorking)

                appleButton
                    .frame(height: 54)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )

                Text("By continuing, you agree to Kuro’s Terms of Service and Privacy Policy.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(white: 0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, max(18, geo.safeAreaInsets.bottom + 8))
        }
    }

    // MARK: - Welcome (Genie composition — kept behind -AuthGenieHero)

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
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )

                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        errorText = nil
                        withAnimation(KuroMotion.resolve(KuroAnimation.editorial)) {
                            step = .email
                        }
                        revealEmailForm(animated: !reduceMotion)
                    } label: {
                        Text("Continue with Email")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Capsule().fill(Color.black))
                    }
                    .buttonStyle(AuthPressStyle())
                    .disabled(isWorking)

                    Text("By tapping the button above, you agree to Kuro’s Terms of Service and Privacy Policy.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(white: 0.55))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, max(18, geo.safeAreaInsets.bottom + 8))
            }
        }
    }

    // MARK: - Email (Genie form)

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
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Self.ink)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(AuthPressStyle())
                        .disabled(isWorking)
                        Spacer()
                    }

                    Text("Kuro")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundColor(Self.ink)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .modifier(AuthStaggerEnter(revealed: show, delay: 0.00))

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mode == .signIn ? "Welcome back" : "Join Kuro")
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                            .foregroundColor(Self.ink)
                            .padding(.top, 28)
                            .modifier(AuthStaggerEnter(revealed: show, delay: 0.05))

                        Text(mode == .signIn
                              ? "Let’s get started"
                              : "Create your shelf")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Self.ink.opacity(0.42))
                            .padding(.top, 6)
                            .modifier(AuthStaggerEnter(revealed: show, delay: 0.10))

                        HStack(spacing: 26) {
                            modeTab("Sign in", selected: mode == .signIn) {
                                mode = .signIn
                                errorText = nil
                                revalidateEmail()
                            }
                            modeTab("Create account", selected: mode == .signUp) {
                                mode = .signUp
                                errorText = nil
                                revalidateEmail()
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                        .modifier(AuthStaggerEnter(revealed: show, delay: 0.15))

                        VStack(spacing: 14) {
                            authField(
                                title: "Email",
                                text: $email,
                                isSecure: false,
                                field: .email,
                                status: emailStatusView
                            )
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled(true)
                            .textContentType(.emailAddress)
                            .modifier(AuthStaggerEnter(revealed: show, delay: 0.20))

                            authField(
                                title: "Password",
                                text: $password,
                                isSecure: !showPassword,
                                field: .password,
                                status: passwordStatusView,
                                trailing: {
                                    Button { showPassword.toggle() } label: {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(Self.ink.opacity(0.38))
                                    }
                                    .buttonStyle(.plain)
                                }
                            )
                            .textContentType(mode == .signIn ? .password : .newPassword)
                            .modifier(AuthStaggerEnter(revealed: show, delay: 0.25))
                        }

                        if let errorText, !errorText.isEmpty {
                            Text(errorText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Self.accent)
                                .padding(.top, 12)
                        }

                        Button {
                            KuroAccessibility.impactHaptic(.medium)
                            if !canSubmit {
                                if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    errorText = "Enter your email to continue."
                                } else if passwordStatus != .valid {
                                    errorText = "Password needs at least 8 characters."
                                } else if mode == .signUp && emailStatus == .taken {
                                    errorText = "That email is already in use."
                                } else {
                                    errorText = "Check your email and password."
                                }
                                return
                            }
                            Task { await submit() }
                        } label: {
                            HStack(spacing: 10) {
                                if isWorking { ProgressView().tint(.white) }
                                Text(mode == .signIn ? "Continue" : "Create account")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Capsule().fill(Self.ink))
                        }
                        .buttonStyle(AuthPressStyle())
                        .disabled(isWorking)
                        .padding(.top, 26)
                        .modifier(AuthStaggerEnter(revealed: show, delay: 0.30))

                        if mode == .signIn {
                            Button { Task { await forgotPassword() } } label: {
                                Text("Forgot password?")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Self.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 16)
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)
                            .modifier(AuthStaggerEnter(revealed: show, delay: 0.35))
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, max(24, geo.safeAreaInsets.bottom + 8))
                }
            }
        }
    }

    private func modeTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            withAnimation(KuroMotion.resolve(KuroAnimation.scaleUp)) { action() }
        } label: {
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(selected ? Self.ink : Self.ink.opacity(0.35))
                Capsule()
                    .fill(selected ? Self.accent : Color.clear)
                    .frame(height: 2.5)
                    .frame(maxWidth: 48)
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            guard let nonce = Self.randomNonceString() else {
                errorText = "Security error. Please try again."
                return
            }
            currentNonce = nonce
            request.requestedScopes = [.email, .fullName]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            KuroAccessibility.impactHaptic(.medium)
            Task { await handleAppleSignIn(result) }
        }
        .signInWithAppleButtonStyle(.white)
        .disabled(isWorking)
    }

    // MARK: - Field

    private func authField<Trailing: View>(
        title: String,
        text: Binding<String>,
        isSecure: Bool,
        field: Field,
        status: some View,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        let isFocused = focusedField == field
        return VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isFocused ? Color(red: 0.25, green: 0.45, blue: 0.95) : Self.ink.opacity(0.42))

            HStack(spacing: 10) {
                Group {
                    if isSecure {
                        SecureField("", text: text, prompt: Text(title).foregroundColor(Self.ink.opacity(0.28)))
                    } else {
                        TextField("", text: text, prompt: Text(title).foregroundColor(Self.ink.opacity(0.28)))
                    }
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Self.ink)
                .onTapGesture { focusedField = field }

                status
                trailing()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused
                          ? Color(red: 0.93, green: 0.95, blue: 1.0)
                          : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isFocused
                            ? Color(red: 0.35, green: 0.55, blue: 0.98)
                            : Self.ink.opacity(0.12),
                        lineWidth: isFocused ? 1.75 : 1
                    )
            )
        }
    }

    // MARK: - Validation / actions

    private var canSubmit: Bool {
        let emailOk: Bool
        switch mode {
        case .signUp: emailOk = emailStatus == .available
        case .signIn: emailOk = emailStatus == .available || emailStatus == .checking
        }
        return emailOk && passwordStatus == .valid
    }

    private func revalidateEmail() {
        emailCheckTask?.cancel()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { emailStatus = .empty; return }
        guard trimmed.wholeMatch(of: Self.emailRegex) != nil else {
            emailStatus = .invalidFormat
            return
        }
        if mode == .signIn {
            emailStatus = .available
            return
        }
        emailStatus = .checking
        emailCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let exists = await supabaseService.checkEmailExists(email: trimmed)
            guard !Task.isCancelled else { return }
            emailStatus = exists ? .taken : .available
        }
    }

    private func revalidatePassword() {
        guard !password.isEmpty else { passwordStatus = .empty; return }
        passwordStatus = password.count >= 8 ? .valid : .tooShort
    }

    @ViewBuilder private var emailStatusView: some View {
        switch emailStatus {
        case .empty: EmptyView()
        case .invalidFormat: statusHint("Invalid")
        case .checking: ProgressView().controlSize(.mini)
        case .taken: statusHint("Taken")
        case .available:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Self.accent)
        }
    }

    @ViewBuilder private var passwordStatusView: some View {
        switch passwordStatus {
        case .empty: EmptyView()
        case .tooShort: statusHint("Min 8")
        case .valid:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Self.accent)
        }
    }

    private func statusHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Self.ink.opacity(0.4))
    }

    private func loadCovers() async {
        let anime = await supabaseService.fetchTrendingAnime(limit: 12)
        let urls = anime.compactMap { URL(string: $0.displayImage) }.filter { !$0.absoluteString.isEmpty }
        if !urls.isEmpty { coverURLs = Array(urls.prefix(6)) }
    }

    private func submit() async {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else { return }
        errorText = nil
        isWorking = true
        defer { isWorking = false }
        do {
            if mode == .signIn {
                try await supabaseService.signInWithEmail(email: e, password: password)
            } else {
                try await supabaseService.signUpWithEmail(email: e, password: password)
            }
        } catch {
            errorText = supabaseService.authErrorMessage ?? SupabaseService.userFacingAuthErrorMessage(from: error)
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        errorText = nil
        isWorking = true
        defer { isWorking = false; currentNonce = nil }
        do {
            guard let credential = try result.get().credential as? ASAuthorizationAppleIDCredential else {
                errorText = "Unexpected credential type."
                return
            }
            guard let identityToken = credential.identityToken,
                  let idToken = String(data: identityToken, encoding: .utf8) else {
                errorText = "Missing identity token."
                return
            }
            guard let rawNonce = currentNonce else {
                errorText = "Missing nonce. Please try again."
                return
            }
            let fullName = credential.fullName.flatMap {
                [$0.givenName, $0.familyName].compactMap { $0 }.joined(separator: " ")
            }
            try await supabaseService.signInWithApple(idToken: idToken, rawNonce: rawNonce, fullName: fullName)
        } catch {
            errorText = SupabaseService.userFacingAuthErrorMessage(from: error)
            if step != .email {
                withAnimation(KuroMotion.resolve(KuroAnimation.editorial)) { step = .email }
            }
        }
    }

    private func forgotPassword() async {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.contains("@") else {
            errorText = "Enter your email above, then tap Forgot password."
            return
        }
        errorText = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await supabaseService.resetPassword(email: e)
            errorText = "Password reset email sent. Check your inbox."
        } catch {
            errorText = SupabaseService.userFacingAuthErrorMessage(from: error)
        }
    }

    private static func randomNonceString(length: Int = 32) -> String? {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let charset: [Swift.Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Press

private struct AuthPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Soft staggered rise used by the email form landing.
private struct AuthStaggerEnter: ViewModifier {
    let revealed: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 12)
            .animation(
                .spring(response: 0.50, dampingFraction: 0.84).delay(delay),
                value: revealed
            )
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

// MARK: - Living scenery loop (Anything hero)

/// A truly seamless, infinitely scrolling banner. The asset is a double-width
/// mirrored tile. We lay out TWO tiles (4 tile-widths) side by side and slide the
/// strip by exactly one tile-width, then wrap — so frame N and frame N+period are
/// pixel-identical. No seam, no restart, at any size.
private struct AuthSceneryLoop: View {
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            // Wrap distance = one tile at the artwork's TRUE aspect (3072×1024 = 3:1).
            // Using anything narrower crops the mountains out of the center via scaledToFill.
            let tileW = h * 3.0
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let period: Double = 34
                let t = elapsed.truncatingRemainder(dividingBy: period) / period
                let shift = tileW * t
                HStack(spacing: 0) {
                    Image("KuroZenMountains")
                        .resizable()
                        .scaledToFill()
                        .frame(width: tileW, height: h)
                        .clipped()
                    Image("KuroZenMountains")
                        .resizable()
                        .scaledToFill()
                        .frame(width: tileW, height: h)
                        .clipped()
                }
                .frame(width: geo.size.width, height: h, alignment: .leading)
                .offset(x: -shift)
                .saturation(1.02)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Zen TV (static brand reveal at the foot of the loop)

/// A photoreal vintage TV standing on a rock outcrop at the bottom edge of
/// the scenery, the Kuro mark glowing on its screen like a broadcast ident.
/// Fully static on purpose: the only motion in the sky band is the scenery
/// loop drifting behind it.
private struct AuthZenTV: View {
    let height: CGFloat

    var body: some View {
        let tvWidth = min(height * 0.62, 240)
        VStack {
            Spacer()
            ZStack(alignment: .bottom) {
                // soft contact shadow so the rock grounds into the mist
                Ellipse()
                    .fill(Color(red: 0.16, green: 0.19, blue: 0.22).opacity(0.10))
                    .frame(width: tvWidth * 0.66, height: tvWidth * 0.07)
                    .blur(radius: 8)
                Image("KuroZenTV")
                    .resizable()
                    .scaledToFit()
                    .frame(width: tvWidth)
            }
            .padding(.bottom, height * 0.07)
        }
        .frame(height: height)
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

