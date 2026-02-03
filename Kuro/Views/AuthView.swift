import SwiftUI

struct AuthView: View {
    @Environment(SupabaseService.self) private var supabaseService

    private enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking = false
    @State private var errorText: String? = nil

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text("KURO")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.black.opacity(0.3))

                    Text(mode == .signIn ? "SIGN IN" : "CREATE ACCOUNT")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.black)

                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 36, height: 4)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
                .padding(.top, 18)
                .padding(.bottom, 18)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(Color.white)
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
                                .font(.system(size: 12, weight: .regular))
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
                                    .font(.system(size: 12, weight: .semibold))
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
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.black.opacity(0.55))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTE")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.4)
                                .foregroundColor(.black.opacity(0.35))

                            Text("Apple Sign-In will be added next. This build uses email/password to fully enable your personal lists and concierge.")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.black.opacity(0.55))
                        }
                        .padding(.top, 10)

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
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

    private func field(_ title: String, text: Binding<String>, isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(.black.opacity(0.35))

            Group {
                if isSecure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .font(.system(size: 14, weight: .regular))
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

