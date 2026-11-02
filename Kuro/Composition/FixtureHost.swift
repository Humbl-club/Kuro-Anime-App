import Foundation

#if DEBUG && canImport(Supabase)
import Supabase
import Synchronization

/// The fixture-only host configuration: the app (or the unit-test host) runs with a client that can
/// never reach a real project.
///
/// Selected BEFORE `AppComposition.shared` builds its client, and compiled for DEBUG only, so a release
/// build cannot enter it:
/// - the Supabase URL/key are fixture values (`.invalid` never resolves), never the Info.plist/env values;
/// - the SDK session lives in memory, so a real account's Keychain tokens are never read or written;
/// - every request that is not answered by an in-process stub fails locally with `DenyAllURLProtocol`
///   (the client's own session, and `URLSession.shared` through `installDenyAll`).
///
/// Active when running under XCTest (the unit-test host) or when launched with `--kuro-fixture-host`.
/// The unit-test host additionally skips the launch session restore. Per-test clients (`StubSupabase`)
/// are separate sessions that answer in-process and are unaffected.
enum FixtureHost {
    static let launchArgument = "--kuro-fixture-host"
    static let supabaseURL = URL(string: "https://fixture.invalid")!
    static let anonKey = "fixture-anon-key"

    /// True in the XCTest host process.
    static func isTestHost(_ info: ProcessInfo = .processInfo) -> Bool {
        info.environment["XCTestConfigurationFilePath"] != nil || info.environment["XCTestBundlePath"] != nil
    }

    /// True when the app must run with the fixture configuration instead of the real one.
    static func isActive(_ info: ProcessInfo = .processInfo) -> Bool {
        isTestHost(info) || info.arguments.contains(launchArgument)
    }

    /// Hosts of the requests `DenyAllURLProtocol` refused, in order.
    static var deniedHosts: [String] { DenyAllURLProtocol.denied.withLock { $0 } }

    /// Makes the shared URL session refuse every request too (image loads and any other direct use).
    static func installDenyAll() {
        URLProtocol.registerClass(DenyAllURLProtocol.self)
    }

    /// The fixture SDK client: fixture URL/key, in-memory auth storage, deny-all session.
    static func makeClient() -> SupabaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DenyAllURLProtocol.self]
        return SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: FixtureAuthStorage(),
                    autoRefreshToken: false,
                    emitLocalSessionAsInitialSession: true
                ),
                global: .init(session: URLSession(configuration: configuration))
            )
        )
    }
}

/// Session storage that never touches the Keychain.
final class FixtureAuthStorage: AuthLocalStorage {
    private let values = Mutex<[String: Data]>([:])

    func store(key: String, value: Data) throws { values.withLock { $0[key] = value } }
    func retrieve(key: String) throws -> Data? { values.withLock { $0[key] } }
    func remove(key: String) throws { _ = values.withLock { $0.removeValue(forKey: key) } }
}

/// Fails every request locally, before any dispatch.
final class DenyAllURLProtocol: URLProtocol, @unchecked Sendable {
    static let denied = Mutex<[String]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? request.url?.absoluteString ?? "unknown"
        Self.denied.withLock { $0.append(host) }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
#endif
