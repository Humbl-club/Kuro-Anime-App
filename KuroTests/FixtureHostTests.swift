import Foundation
import Testing
@testable import Kuro

/// F48: the unit-test host runs the fixture configuration, so a test run can never contact the real
/// project or read a real account's tokens.
@MainActor
@Suite("Fixture host: the test host cannot reach production", .serialized)
struct FixtureHostTests {
    private static let productionHost = "bkdifromsqxkndnllmdj.supabase.co"

    @Test("The test host is selected as a fixture host and starts no launch restore")
    func testHostIsFixtureHost() {
        #expect(FixtureHost.isTestHost())
        #expect(FixtureHost.isActive())
        let identity = AppComposition.shared.identity
        #expect(identity.configError == nil, "the fixture client counts as configured")
        #expect(!identity.isAuthBootstrapping, "the unit-test host must not restore a session at launch")
        #expect(!identity.isAuthenticated)
    }

    @Test("The app's own composed client refuses a request locally, before dispatch")
    func composedClientIsDenied() async {
        let before = FixtureHost.deniedHosts.count
        let exists = await AppComposition.shared.auth.checkEmailExists(email: "nobody@example.com")
        #expect(!exists)
        let denied = Array(FixtureHost.deniedHosts.dropFirst(before))
        #expect(denied.contains("fixture.invalid"), "the composed client targets the fixture URL: \(denied)")
        #expect(!denied.contains(Self.productionHost))
    }

    @Test("The shared URL session refuses a request to the production host locally")
    func sharedSessionIsDenied() async {
        let url = URL(string: "https://\(Self.productionHost)/rest/v1/anime?select=id&limit=1")!
        let before = FixtureHost.deniedHosts.count
        do {
            _ = try await URLSession.shared.data(from: url)
            Issue.record("a request to the production host must not be dispatched from the test host")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(Array(FixtureHost.deniedHosts.dropFirst(before)).contains(Self.productionHost))
    }

    @Test("The fixture client never reads or writes the Keychain session")
    func fixtureStorageIsInMemory() throws {
        let storage = FixtureAuthStorage()
        #expect(try storage.retrieve(key: "supabase.auth.token") == nil)
        try storage.store(key: "k", value: Data([1]))
        #expect(try storage.retrieve(key: "k") == Data([1]))
        try storage.remove(key: "k")
        #expect(try storage.retrieve(key: "k") == nil)
    }
}
