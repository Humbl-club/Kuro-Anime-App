import Foundation
import KuroCore
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Support (contact form)
// Owner of the in-app contact form (Profile > About > Contact us): the draft, its validation and the
// one transport call, `contact-submit` (supabase/functions/contact-submit). The function also serves
// the legal website's form; from the app it takes the signed-in session the SDK attaches, and derives
// the account from that JWT only (the body never carries a user id).
//
// Account scope (`AccountScopedState`): the draft can hold the account's e-mail and a private message,
// so every account transition cancels an in-flight send and clears the draft and its state. A send
// runs as a credential lease of the account that started it, and a completion for an account that is
// no longer current never writes state. The send is NOT retried automatically: a retried POST after a
// lost answer would store the message twice.

/// The topics the function accepts (raw values are the wire values).
nonisolated enum ContactTopic: String, CaseIterable, Identifiable, Sendable {
    case general
    case support
    case privacy
    case legalNotice = "legal_notice"
    case reportContent = "report_content"
    case other

    var id: String { rawValue }

    func title(german: Bool) -> String {
        switch self {
        case .general: return german ? "Allgemein" : "General"
        case .support: return german ? "Hilfe zur App" : "App support"
        case .privacy: return german ? "Datenschutz" : "Privacy"
        case .legalNotice: return german ? "Rechtlicher Hinweis" : "Legal notice"
        case .reportContent: return german ? "Inhalt melden" : "Report content"
        case .other: return german ? "Sonstiges" : "Other"
        }
    }
}

/// A field the form can flag (raw values match the function's `fields`).
nonisolated enum ContactField: String, Sendable, Hashable {
    case topic
    case email
    case name
    case message
    case consent
}

/// What the user is writing.
nonisolated struct ContactDraft: Equatable, Sendable {
    var topic: ContactTopic = .general
    var email: String = ""
    var name: String = ""
    var message: String = ""
    var consent: Bool = false

    static let emailLimit = 254
    static let nameLimit = 120
    static let messageLimit = 4000
}

/// Where the form stands.
nonisolated enum ContactSubmitState: Equatable, Sendable {
    case idle
    case sending
    /// Stored by the server.
    case sent
    /// Local or server validation flagged these fields.
    case invalid([ContactField])
    /// The server's limit (5 per hour) was reached.
    case rateLimited
    /// No connection.
    case offline
    /// Anything else (server error, expired session, missing configuration).
    case failed
}

/// The request body (wire contract of `contact-submit`). Optional values are omitted when nil.
nonisolated struct ContactSubmitRequest: Encodable, Equatable, Sendable {
    let topic: String
    let email: String
    let name: String?
    let message: String
    let locale: String?
    let appVersion: String?
    /// The honeypot the website hides; the app always sends it empty.
    let website: String
    let consent: Bool

    enum CodingKeys: String, CodingKey {
        case topic, email, name, message, locale
        case appVersion = "app_version"
        case website, consent
    }
}

@MainActor
@Observable
final class SupportStore: AccountScopedState {
    /// The app's single SDK client; nil when the configuration is missing (every send then fails).
    private let client: SupabaseClient?
    let accountSession: AccountSessionCoordinator
    /// "1.4 (220)" from the bundle (injectable for tests).
    @ObservationIgnored private let appVersion: String?
    /// The device's preferred languages (injectable for tests).
    @ObservationIgnored private let preferredLanguages: () -> [String]

    var draft = ContactDraft()
    private(set) var state: ContactSubmitState = .idle
    @ObservationIgnored private var sendTask: Task<Void, Never>?

    init(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        appVersion: String? = SupportStore.bundleAppVersion(),
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.client = client
        self.accountSession = accountSession
        self.appVersion = appVersion
        self.preferredLanguages = preferredLanguages
    }

    // MARK: AccountScopedState

    func cancelAccountWork() {
        sendTask?.cancel()
        sendTask = nil
    }

    func clearPrivateState() {
        draft = ContactDraft()
        state = .idle
    }

    // MARK: Draft

    /// Prefills the e-mail (the account's address) when the user has not typed one.
    func prepare(prefillEmail: String?) {
        guard draft.email.isEmpty, let prefillEmail else { return }
        draft.email = prefillEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Back to an empty form after a sent message (keeps the e-mail for a follow-up).
    func startNewMessage() {
        draft = ContactDraft(email: draft.email)
        state = .idle
    }

    /// Clears a flag on a field the user is editing (and the invalid state once nothing is flagged).
    func clearFlag(_ field: ContactField) {
        guard case .invalid(let fields) = state else { return }
        let rest = fields.filter { $0 != field }
        state = rest.isEmpty ? .idle : .invalid(rest)
    }

    var isSending: Bool { state == .sending }

    // MARK: Rules (pure)

    /// The fields the server would reject, in the server's order. Pure.
    nonisolated static func validate(_ draft: ContactDraft) -> [ContactField] {
        var fields: [ContactField] = []
        let email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty || email.count > ContactDraft.emailLimit || !isPlausibleEmail(email) {
            fields.append(.email)
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count > ContactDraft.nameLimit || name.contains(where: { $0.isNewline }) {
            fields.append(.name)
        }
        let message = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty || message.count > ContactDraft.messageLimit {
            fields.append(.message)
        }
        if !draft.consent { fields.append(.consent) }
        return fields
    }

    /// Same shape as the server: one "@", no whitespace, a dot in the domain.
    nonisolated static func isPlausibleEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !email.contains(where: { $0.isWhitespace }) else { return false }
        let domain = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return domain.count >= 2 && domain.allSatisfy { !$0.isEmpty }
    }

    /// The primary language subtag only ("de", "en"); nil when it is not a plain 2–3 letter code.
    nonisolated static func localeTag(preferredLanguages: [String]) -> String? {
        guard let first = preferredLanguages.first,
              let language = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        else { return nil }
        let code = language.lowercased()
        guard (2...3).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return code
    }

    /// The wire body for `draft` (trimmed; empty name omitted). Pure.
    nonisolated static func request(for draft: ContactDraft, locale: String?, appVersion: String?) -> ContactSubmitRequest {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ContactSubmitRequest(
            topic: draft.topic.rawValue,
            email: draft.email.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.isEmpty ? nil : name,
            message: draft.message.trimmingCharacters(in: .whitespacesAndNewlines),
            locale: locale,
            appVersion: appVersion,
            website: "",
            consent: draft.consent
        )
    }

    /// Maps a send failure to the form's state. Pure.
    nonisolated static func state(for error: Error) -> ContactSubmitState {
        if let functions = error as? FunctionsError, case .httpError(let code, let data) = functions {
            switch code {
            case 429:
                return .rateLimited
            case 400:
                let body = try? JSONDecoder().decode(InvalidBody.self, from: data)
                let fields = (body?.fields ?? []).compactMap(ContactField.init(rawValue:))
                return fields.isEmpty ? .failed : .invalid(fields)
            default:
                return .failed
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .offline
            default:
                return .failed
            }
        }
        return .failed
    }

    private nonisolated struct InvalidBody: Decodable {
        let fields: [String]?
    }

    nonisolated static func bundleAppVersion(_ bundle: Bundle = .main) -> String? {
        guard let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String else { return nil }
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String
        let value = build.map { "\(version) (\($0))" } ?? version
        return value.count <= 40 ? value : String(value.prefix(40))
    }

    // MARK: Send

    /// Validates and sends the draft once. Returns when the send settled (or was dropped because its
    /// account ended). Never retried automatically.
    func submit() async {
        guard state != .sending else { return }
        let invalid = Self.validate(draft)
        guard invalid.isEmpty else {
            state = .invalid(invalid)
            return
        }
        let context = accountSession.current
        let body = Self.request(
            for: draft,
            locale: Self.localeTag(preferredLanguages: preferredLanguages()),
            appVersion: appVersion
        )
        state = .sending
        let client = self.client
        let accountSession = self.accountSession
        let task = Task { @MainActor [weak self] in
            do {
                guard let client else { throw MissingSupabaseConfiguration() }
                let _: ContactSubmitReply = try await accountSession.withCredentialLease(for: context) {
                    try await client.functions.invoke(
                        "contact-submit",
                        options: FunctionInvokeOptions(method: .post, body: body)
                    )
                }
                guard let self, accountSession.isCurrent(context), !Task.isCancelled else { return }
                self.state = .sent
                self.draft = ContactDraft(email: self.draft.email)
            } catch {
                // A send of an account that ended (or was cancelled with it) reports nothing.
                guard let self, accountSession.isCurrent(context), !Task.isCancelled,
                      !(error is CancellationError) else { return }
                self.state = Self.state(for: error)
            }
        }
        sendTask = task
        await task.value
        if sendTask == task { sendTask = nil }
    }

    private nonisolated struct ContactSubmitReply: Decodable, Sendable {
        let ok: Bool?
    }
}
#endif
