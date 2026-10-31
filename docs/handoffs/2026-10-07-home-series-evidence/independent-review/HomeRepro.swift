import Foundation
import KuroCore
import KuroLibrary
struct NoNetworkBackend: LibraryBackend {
 func fetchAll(for account: AccountContext) async throws -> [LibraryEntry] { [] }
 func edit(_ edit: LibraryEdit, key: MediaKey, createIfMissing: ListStatus?, mutationId: UUID, baseRevision: Int64?, account: AccountContext) async throws -> LibraryWriteResult { throw LibraryError.unavailable(message: "no network") }
 func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult { throw LibraryError.unavailable(message: "no network") }
 func remove(_ key: MediaKey, account: AccountContext) async throws { throw LibraryError.unavailable(message: "no network") }
}
@main struct HomeRepro {
 @MainActor static func main() async throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent("home-rapid-\(UUID().uuidString).sqlite").path
  defer { try? FileManager.default.removeItem(atPath: path) }
  let box = try ProgressOutbox(path: path)
  let account = AccountSessionCoordinator(); _ = account.begin(userId: "a")
  let library = LibraryStore(backend: NoNetworkBackend()); library.bind(account.current!)
  let home = HomeStore(accountSession: account, library: library, outbox: box)
  let lifecycle = UUID().uuidString
  await withTaskGroup(of: Void.self) { group in
   for _ in 0..<20 { group.addTask { @MainActor in
    await home.advance(medium: "anime", mediaId: 7, lifecycleId: lifecycle, baseRevision: 1, serverProgress: 3)
   } }
  }
  home.cancelAccountWork()
  print("HOME_RAPID_TAPS: taps=20 initial=3 expected=23 actual=\(home.displayedProgress(medium: "anime", mediaId: 7, server: 3))")
  print("HOME_RAPID_TAPS: persisted-row-count=\(try await box.count(accountId: "a"))")
 }
}
