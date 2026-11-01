import AuthenticationServices
import Foundation
import KuroCore
import KuroLibrary
import Security

/// Values must come from the registered public/native client and reviewed provider documentation.
/// No default client, secret, callback or unverified PKCE-method assumption is shipped.
struct MALNativeRegistration: Sendable {
    let clientId: String
    let authorizationURL: URL
    let tokenURL: URL
    let redirectURL: URL
    let challengeMethod: LibraryOAuthAttempt.ChallengeMethod
    let qualified: Bool

    var isUsable: Bool {
        qualified && !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && authorizationURL.absoluteString == "https://myanimelist.net/v1/oauth2/authorize"
            && tokenURL.absoluteString == "https://myanimelist.net/v1/oauth2/token"
            && challengeMethod == .plain
            && authorizationURL.user == nil && tokenURL.user == nil
            && authorizationURL.query == nil && tokenURL.query == nil
            && authorizationURL.fragment == nil && tokenURL.fragment == nil
            && redirectURL.scheme == "kuro" && redirectURL.host == "mal"
            && redirectURL.path == "/callback" && redirectURL.query == nil && redirectURL.fragment == nil
    }
}

enum MALConnectionError: Error {
    case registrationUnavailable, invalidCallback, providerRejected, invalidToken, secureStorage(OSStatus)
    case http(status: Int), malformedAccount
}

private final class MALRedirectRefusal: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // A 307/308 must never resend authorization codes, refresh tokens or verifiers elsewhere.
        completionHandler(nil)
    }
}

/// Where each Kuro account's MAL tokens are kept (the encoded token record per account id). The app
/// uses the device Keychain; an object graph built for tests uses its own in-memory store, so a test
/// never reads, writes or deletes the device's Keychain record (an unsigned test host has no Keychain
/// entitlement at all: `errSecMissingEntitlement`, -34018) and graphs never share credentials.
nonisolated protocol MALCredentialStore: Sendable {
    /// The account's record, nil when there is none.
    func read(account: String) throws -> Data?
    func save(_ data: Data, account: String) throws
    /// Removes the account's record; no record is not an error.
    func delete(account: String) throws
}

/// The device Keychain: one generic password per Kuro account (service `com.Kuro.app.myanimelist`,
/// account id lower-cased), readable only while unlocked on this device.
nonisolated struct KeychainMALCredentialStore: MALCredentialStore {
    private func key(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.Kuro.app.myanimelist",
         kSecAttrAccount as String: account.lowercased()]
    }

    func read(account: String) throws -> Data? {
        var query = key(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw MALConnectionError.secureStorage(status)
        }
        return data
    }

    func save(_ data: Data, account: String) throws {
        let query = key(account: account)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw MALConnectionError.secureStorage(status) }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(key(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MALConnectionError.secureStorage(status)
        }
    }
}

/// An in-memory credential store, private to one object graph (`AppComposition.testingGraph`).
nonisolated final class InMemoryMALCredentialStore: MALCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: Data] = [:]

    init() {}

    func read(account: String) throws -> Data? {
        lock.withLock { records[account.lowercased()] }
    }

    func save(_ data: Data, account: String) throws {
        lock.withLock { records[account.lowercased()] = data }
    }

    func delete(account: String) throws {
        _ = lock.withLock { records.removeValue(forKey: account.lowercased()) }
    }
}

/// Private credentials belong to a Kuro account, never to whichever account happens to be visible
/// when a browser callback or token refresh completes. Provider field/paging qualification remains
/// a separate prerequisite before composition exposes the account import workflow.
@MainActor
final class MALNativeAccountConnector: NSObject, AccountScopedState, ASWebAuthenticationPresentationContextProviding {
    private struct Tokens: Codable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let token_type: String
        let expires_in: Int
    }
    private struct BrowserFlow {
        let id: UUID
        let session: ASWebAuthenticationSession
        let continuation: CheckedContinuation<URL, Error>
    }
    private let registration: MALNativeRegistration?
    private let accounts: AccountSessionCoordinator
    private let transport: URLSession
    private let credentials: any MALCredentialStore
    private var connecting: UUID?
    private var connectionGeneration: UInt64 = 0
    private var browser: BrowserFlow?
    private var anchor: ASPresentationAnchor?
    private var refreshing: (context: AccountContext, generation: UInt64, id: UUID, task: Task<String, Error>)?

    init(registration: MALNativeRegistration?, accounts: AccountSessionCoordinator,
         transport: URLSession? = nil, credentials: any MALCredentialStore = KeychainMALCredentialStore()) {
        self.registration = registration; self.accounts = accounts
        self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        self.transport = transport ?? URLSession(configuration: configuration,
            delegate: MALRedirectRefusal(), delegateQueue: nil)
    }

    var isAvailable: Bool { registration?.isUsable == true }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // A valid foreground-window anchor is required before connect begins.
        anchor ?? ASPresentationAnchor()
    }

    func cancelAccountWork() {
        connectionGeneration &+= 1
        connecting = nil
        if let flow = browser {
            browser = nil
            flow.session.cancel()
            flow.continuation.resume(throwing: CancellationError())
        }
        refreshing?.task.cancel()
        refreshing = nil
        anchor = nil
    }

    func clearPrivateState() { cancelAccountWork() }

    func connect(presentationAnchor: ASPresentationAnchor) async throws {
        guard let registration, registration.isUsable else { throw MALConnectionError.registrationUnavailable }
        guard let context = accounts.current, connecting == nil, browser == nil, !Task.isCancelled else { throw CancellationError() }
        cancelAccountWork()
        let generation = connectionGeneration
        let connectionId = UUID()
        connecting = connectionId
        defer { if connecting == connectionId { connecting = nil; anchor = nil } }
        let attempt = LibraryOAuthAttempt(accountId: context.userId, generation: context.generation,
            state: try Self.randomValue(), verifier: try Self.randomValue(), method: registration.challengeMethod)
        guard var components = URLComponents(url: registration.authorizationURL, resolvingAgainstBaseURL: false) else {
            throw MALConnectionError.registrationUnavailable
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: registration.clientId),
            URLQueryItem(name: "redirect_uri", value: registration.redirectURL.absoluteString),
            URLQueryItem(name: "state", value: attempt.state),
            URLQueryItem(name: "code_challenge", value: attempt.challenge),
            URLQueryItem(name: "code_challenge_method", value: attempt.method.rawValue),
        ]
        guard let url = components.url else { throw MALConnectionError.registrationUnavailable }
        anchor = presentationAnchor
        let callback = try await browserCallback(url: url)
        guard accounts.isCurrent(context), generation == connectionGeneration, !Task.isCancelled,
              callback.scheme == registration.redirectURL.scheme,
              callback.host == registration.redirectURL.host,
              callback.path == registration.redirectURL.path,
              callback.fragment == nil,
              let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
            throw MALConnectionError.invalidCallback
        }
        // Duplicate parameters are ambiguous; do not choose the first value silently.
        guard Set(query.map(\.name)).count == query.count,
              attempt.accepts(state: query.first(where: { $0.name == "state" })?.value,
                              accountId: context.userId, generation: context.generation) else {
            throw MALConnectionError.invalidCallback
        }
        if query.contains(where: { $0.name == "error" }) { throw MALConnectionError.providerRejected }
        guard let code = query.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw MALConnectionError.invalidCallback
        }
        let tokens = try await accounts.withCredentialLease(for: context) {
            guard generation == self.connectionGeneration, !Task.isCancelled else { throw CancellationError() }
            return try await self.exchange([
                "grant_type": "authorization_code", "code": code,
                "redirect_uri": registration.redirectURL.absoluteString,
                "code_verifier": attempt.verifier,
            ])
        }
        guard accounts.isCurrent(context), generation == connectionGeneration, !Task.isCancelled else { throw CancellationError() }
        try save(tokens, account: context.userId)
    }

    /// Called by the provider reader immediately before dispatch; refresh joins only this account.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard isAvailable else { throw MALConnectionError.registrationUnavailable }
        guard let context = accounts.current, let tokens = try read(account: context.userId) else {
            throw MALConnectionError.invalidToken
        }
        if !forceRefresh && tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.accessToken }
        let generation = connectionGeneration
        if let refreshing, refreshing.context == context, refreshing.generation == generation { return try await refreshing.task.value }
        guard let refresh = tokens.refreshToken else { throw MALConnectionError.invalidToken }
        let id = UUID()
        let task = Task<String, Error> { @MainActor in
            let next = try await self.accounts.withCredentialLease(for: context) {
                guard generation == self.connectionGeneration, !Task.isCancelled else { throw CancellationError() }
                return try await self.exchange(["grant_type": "refresh_token", "refresh_token": refresh], retaining: refresh)
            }
            guard !Task.isCancelled, self.accounts.isCurrent(context), generation == self.connectionGeneration else { throw CancellationError() }
            try self.save(next, account: context.userId)
            return next.accessToken
        }
        refreshing = (context, generation, id, task)
        defer { if refreshing?.id == id { refreshing = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    struct ReaderSession: Sendable {
        let account: AccountContext
        let generation: UInt64
        let providerUserId: Int
        let providerName: String
    }

    /// MAL identity binds the journal to the connected provider account, including reconnects.
    func beginReader() async throws -> ReaderSession {
        guard let context = accounts.current else { throw CancellationError() }
        let generation = connectionGeneration
        let data = try await authenticatedRead(URL(string: "https://api.myanimelist.net/v2/users/@me")!,
            context: context, generation: generation)
        struct User: Decodable { let id: Int; let name: String }
        guard let user = try? JSONDecoder().decode(User.self, from: data), user.id > 0, !user.name.isEmpty, user.name.utf8.count <= 256 else {
            throw MALConnectionError.malformedAccount
        }
        return ReaderSession(account: context, generation: generation, providerUserId: user.id, providerName: user.name)
    }

    func readPage(medium: LibraryProviderReference.Medium, offset: Int,
                  session: ReaderSession) async throws -> MALAccountList.Page {
        let url = try MALAccountList.url(medium: medium, offset: offset)
        let data = try await authenticatedRead(url, context: session.account, generation: session.generation)
        return try MALAccountList.decode(data, medium: medium, offset: offset)
    }

    func isCurrent(_ session: ReaderSession) -> Bool {
        accounts.isCurrent(session.account) && session.generation == connectionGeneration && !Task.isCancelled
    }

    private func authenticatedRead(_ url: URL, context: AccountContext, generation: UInt64) async throws -> Data {
        for attempt in 0...1 {
            guard accounts.isCurrent(context), generation == connectionGeneration, !Task.isCancelled else { throw CancellationError() }
            let token = try await accessToken(forceRefresh: attempt == 1)
            guard accounts.isCurrent(context), generation == connectionGeneration, !Task.isCancelled else { throw CancellationError() }
            do {
            let data: Data = try await accounts.withCredentialLease(for: context) {
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await self.transport.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { throw MALConnectionError.providerRejected }
                guard http.expectedContentLength <= MALAccountList.maximumBodyBytes else { throw MALAccountList.Failure.bodyTooLarge }
                var body = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard body.count < MALAccountList.maximumBodyBytes else { throw MALAccountList.Failure.bodyTooLarge }
                    body.append(byte)
                }
                guard (200...299).contains(http.statusCode) else { throw MALConnectionError.http(status: http.statusCode) }
                return body
            }
            guard accounts.isCurrent(context), generation == connectionGeneration, !Task.isCancelled else { throw CancellationError() }
            return data
            } catch MALConnectionError.http(status: 401) where attempt == 0 {
                continue
            }
        }
        throw MALConnectionError.invalidToken
    }

    func disconnect() throws {
        guard let context = accounts.current else { throw CancellationError() }
        cancelAccountWork()
        try removeCredentials(forDeletedAccount: context.userId)
    }

    /// A confirmed Kuro deletion may complete after its session has ended. Its explicit identity
    /// chooses the credential record; the currently visible account must never be used as a fallback.
    func removeCredentials(forDeletedAccount accountId: String) throws {
        if let current = accounts.current, AccountSessionCoordinator.sameUser(current.userId, accountId) {
            cancelAccountWork()
        }
        try credentials.delete(account: accountId)
    }

    private func browserCallback(url: URL) async throws -> URL {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "kuro") { callback, error in
                    Task { @MainActor in
                        guard let flow = self.browser, flow.id == id else { return }
                        self.browser = nil
                        if let callback { flow.continuation.resume(returning: callback) }
                        else { flow.continuation.resume(throwing: error ?? CancellationError()) }
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                browser = BrowserFlow(id: id, session: session, continuation: continuation)
                if !session.start() {
                    browser = nil
                    continuation.resume(throwing: MALConnectionError.providerRejected)
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard let flow = self.browser, flow.id == id else { return }
                self.browser = nil
                flow.session.cancel()
                flow.continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func exchange(_ fields: [String: String], retaining refreshToken: String? = nil) async throws -> Tokens {
        guard let registration, registration.isUsable else { throw MALConnectionError.registrationUnavailable }
        var values = fields
        values["client_id"] = registration.clientId
        var request = URLRequest(url: registration.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = Data(try values.sorted(by: { $0.key < $1.key }).map { field -> String in
            guard let name = field.key.addingPercentEncoding(withAllowedCharacters: allowed),
                  let value = field.value.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw MALConnectionError.invalidCallback
            }
            return "\(name)=\(value)"
        }.joined(separator: "&").utf8)
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MALConnectionError.providerRejected
        }
        let value = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard !value.access_token.isEmpty, value.token_type.lowercased() == "bearer",
              value.expires_in > 0 else { throw MALConnectionError.invalidToken }
        return Tokens(accessToken: value.access_token, refreshToken: value.refresh_token ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(value.expires_in)))
    }

    private func read(account: String) throws -> Tokens? {
        guard let data = try credentials.read(account: account) else { return nil }
        return try JSONDecoder().decode(Tokens.self, from: data)
    }

    private func save(_ tokens: Tokens, account: String) throws {
        try credentials.save(try JSONEncoder().encode(tokens), account: account)
    }

    private static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw MALConnectionError.secureStorage(status) }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
