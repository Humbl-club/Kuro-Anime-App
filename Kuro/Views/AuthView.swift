import AuthenticationServices
import CryptoKit
import SwiftUI

struct AuthView: View {
    @Environment(SupabaseService.self) private var supabaseService

    private enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking = false
    @State private var errorText: String? = nil
    @State private var currentNonce: String? = nil

    // Inline validation state
    private enum EmailStatus { case empty, invalidFormat, checking, taken, available }
    private enum PasswordStatus { case empty, tooShort, valid }
    @State private var emailStatus: EmailStatus = .empty
    @State private var passwordStatus: PasswordStatus = .empty
    @State private var emailCheckTask: Task<Void, Never>?

    private static let emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/

    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text("KURO")
                        .font(.kuroCaption(weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.kuroTextTertiary)

                    Text(mode == .signIn ? "SIGN IN" : "CREATE ACCOUNT")
                        .font(.kuroCaption(weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.black)

                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.kuroBlack08)
                        .frame(width: 36, height: 4)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
                .padding(.top, 18)
                .padding(.bottom, 18)
                .padding(.horizontal, KuroDesignSpacing.padding)
                .frame(maxWidth: .infinity)
                .background(Color.kuroBackground)
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(spacing: 10) {
                            validatedField("Email", text: $email, isSecure: false, status: emailStatusView)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled(true)

                            validatedField("Password", text: $password, isSecure: true, status: passwordStatusView)
                        }
                        .padding(.top, 18)

                        if let errorText, !errorText.isEmpty {
                            Text(errorText)
                                .font(.kuroCaption(weight: .regular))
                                .foregroundColor(.red.opacity(0.85))
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack(spacing: 10) {
                                if isWorking {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(mode == .signIn ? "SIGN IN" : "CREATE")
                                    .font(.kuroCaption(weight: .semibold))
                                    .tracking(1.6)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(canSubmit ? Color.black : Color.black.opacity(0.2))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit || isWorking)
                        .padding(.top, 8)

                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            mode = (mode == .signIn ? .signUp : .signIn)
                            errorText = nil
                            revalidateEmail()
                        } label: {
                            Text(mode == .signIn ? "Create an account" : "Already have an account?")
                                .font(.kuroCaption(weight: .regular))
                                .foregroundColor(.kuroTextSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)

                        if mode == .signIn {
                            Button {
                                Task { await forgotPassword() }
                            } label: {
                                Text("Forgot password?")
                                    .font(.kuroCaption(weight: .regular))
                                    .foregroundColor(.kuroTextSecondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)
                        }

                        // Divider
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.kuroBlack08)
                                .frame(height: 0.5)
                            Text("OR")
                                .font(.kuroMicro(weight: .regular))
                                .tracking(1.4)
                                .foregroundColor(.kuroTextTertiary)
                            Rectangle()
                                .fill(Color.kuroBlack08)
                                .frame(height: 0.5)
                        }
                        .padding(.top, 6)

                        SignInWithAppleButton(.signIn) { request in
                            guard let nonce = Self.randomNonceString() else {
                                errorText = "Security error. Please try again."
                                return
                            }
                            currentNonce = nonce
                            request.requestedScopes = [.email, .fullName]
                            request.nonce = Self.sha256(nonce)
                        } onCompletion: { result in
                            Task { await handleAppleSignIn(result) }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .cornerRadius(14)
                        .disabled(isWorking)

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, KuroDesignSpacing.padding)
                }
            }
        }
        .onChange(of: email) { _, _ in
            revalidateEmail()
        }
        .onChange(of: password) { _, _ in
            revalidatePassword()
        }
        .onChange(of: supabaseService.authErrorMessage) { _, newValue in
            if let msg = newValue {
                errorText = msg
                supabaseService.authErrorMessage = nil
            }
        }
    }

    // MARK: - Validation logic

    private var canSubmit: Bool {
        let emailOk: Bool
        switch mode {
        case .signUp:
            emailOk = emailStatus == .available
        case .signIn:
            emailOk = emailStatus == .available || emailStatus == .checking
        }
        return emailOk && passwordStatus == .valid
    }

    private func revalidateEmail() {
        emailCheckTask?.cancel()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emailStatus = .empty
            return
        }
        guard trimmed.wholeMatch(of: Self.emailRegex) != nil else {
            emailStatus = .invalidFormat
            return
        }
        // Format is valid — in sign-in mode, that's enough
        if mode == .signIn {
            emailStatus = .available
            return
        }
        // Sign-up mode: debounced uniqueness check
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
        guard !password.isEmpty else {
            passwordStatus = .empty
            return
        }
        passwordStatus = password.count >= 8 ? .valid : .tooShort
    }

    // MARK: - Status indicator views

    @ViewBuilder
    private var emailStatusView: some View {
        switch emailStatus {
        case .empty:
            EmptyView()
        case .invalidFormat:
            statusHint("Enter a valid email")
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .taken:
            statusHint("Email already in use")
        case .available:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.kuroTextTertiary)
        }
    }

    @ViewBuilder
    private var passwordStatusView: some View {
        switch passwordStatus {
        case .empty:
            EmptyView()
        case .tooShort:
            statusHint("8 characters minimum")
        case .valid:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.kuroTextTertiary)
        }
    }

    private func statusHint(_ text: String) -> some View {
        Text(text)
            .font(.kuroMicro(weight: .regular))
            .foregroundColor(.kuroTextTertiary)
    }

    // MARK: - Error mapping

    private func friendlyAuthError(_ error: Error) -> String {
        let raw = error.localizedDescription
        #if DEBUG
        print("[AuthView] raw auth error: \(raw)")
        #endif
        let lower = raw.lowercased()
        if lower.contains("invalid login credentials") {
            return "Incorrect email or password. Please try again."
        } else if lower.contains("user already registered") {
            return "An account with this email already exists. Try signing in instead."
        } else if lower.contains("email not confirmed") {
            return "Please check your email to verify your account."
        } else if lower.contains("password should be at least") {
            return "Password must be at least 6 characters."
        }
        return "Something went wrong. Please try again."
    }

    // MARK: - Actions

    private func submit() async {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password
        guard canSubmit else { return }

        errorText = nil
        isWorking = true
        defer { isWorking = false }

        do {
            if mode == .signIn {
                try await supabaseService.signInWithEmail(email: e, password: p)
            } else {
                try await supabaseService.signUpWithEmail(email: e, password: p)
            }
        } catch {
            errorText = supabaseService.authErrorMessage ?? friendlyAuthError(error)
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        errorText = nil
        isWorking = true
        defer {
            isWorking = false
            currentNonce = nil
        }

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
            errorText = friendlyAuthError(error)
        }
    }

    private static func randomNonceString(length: Int = 32) -> String? {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else { return nil }
        let charset: [Swift.Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
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
            errorText = friendlyAuthError(error)
        }
    }

    // MARK: - Field builder

    private func validatedField<S: View>(_ title: String, text: Binding<String>, isSecure: Bool, status: S) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.kuroMicro(weight: .semibold))
                .tracking(1.4)
                .foregroundColor(.kuroTextTertiary)

            HStack(spacing: 8) {
                Group {
                    if isSecure {
                        SecureField("", text: text)
                    } else {
                        TextField("", text: text)
                    }
                }
                .font(.kuroBody(weight: .regular))
                .foregroundColor(.black)

                status
                    .frame(height: 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.04))
            )
        }
    }
}
