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
                            field("Email", text: $email, isSecure: false)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled(true)

                            field("Password", text: $password, isSecure: true)
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
                            let nonce = Self.randomNonceString()
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
    }

    private var canSubmit: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.contains("@") && password.count >= 8
    }

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
                if !supabaseService.isAuthenticated {
                    errorText = "Check your email to confirm your account, then sign in."
                }
            }
        } catch {
            errorText = supabaseService.authErrorMessage ?? error.localizedDescription
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
            errorText = error.localizedDescription
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(result == errSecSuccess, "Failed to generate random bytes")
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
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
            errorText = error.localizedDescription
        }
    }

    private func field(_ title: String, text: Binding<String>, isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.kuroMicro(weight: .semibold))
                .tracking(1.4)
                .foregroundColor(.kuroTextTertiary)

            Group {
                if isSecure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .font(.kuroBody(weight: .regular))
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.04))
            )
        }
    }
}

