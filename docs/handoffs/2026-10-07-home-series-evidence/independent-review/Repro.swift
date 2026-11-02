import Foundation
import SQLite3
@main struct ReviewRepro {
 static func main() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-independent-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let path = root.appendingPathComponent("retry.sqlite").path
  let box = try ProgressOutbox(path: path)
  let lifecycle = UUID(), firstUnit = UUID(), secondUnit = UUID()
  let first = try await box.enqueue(ProgressIntent(accountId: "a", medium: "manga", mediaId: 1, lifecycleId: lifecycle, unitId: firstUnit, baseRevision: 1, position: 2, priorPosition: 1))
  let second = try await box.enqueue(ProgressIntent(accountId: "a", medium: "manga", mediaId: 1, lifecycleId: lifecycle, unitId: secondUnit, baseRevision: 1, position: 3, priorPosition: 2))
  let persisted = try await box.pending(accountId: "a", limit: 50)
  print("COALESCED_UNIT_ON_DISK: latest-position=\(persisted[0].position) unit-is-latest=\(persisted[0].unitId == secondUnit) unit-is-old=\(persisted[0].unitId == firstUnit)")
  print("COALESCED_UNIT_RETURN: latest-position=\(second.position) unit-is-latest=\(second.unitId == secondUnit) unit-is-old=\(second.unitId == firstUnit)")
  try await box.markInFlight([first.mutationId])
  print("FAILED_SEND_SAME_PROCESS: pending=\(try await box.pending(accountId: "a", limit: 50).count) stored=\(try await box.count(accountId: "a"))")
  let reopened = try ProgressOutbox(path: path)
  print("REOPEN: pending=\(try await reopened.pending(accountId: "a", limit: 50).count)")
  let failurePath = root.appendingPathComponent("failure.sqlite").path
  let failing = try ProgressOutbox(path: failurePath)
  var connection: OpaquePointer?
  guard sqlite3_open(failurePath, &connection) == SQLITE_OK else { fatalError("fixture connection") }
  defer { sqlite3_close(connection) }
  guard sqlite3_exec(connection, "create trigger injected_disk_failure before insert on intents begin select raise(abort, 'injected write failure'); end;", nil, nil, nil) == SQLITE_OK else { fatalError("fixture trigger") }
  let intent = ProgressIntent(accountId: "b", medium: "anime", mediaId: 2, position: 1)
  do { _ = try await failing.enqueue(intent); print("INJECTED_WRITE: unexpectedly succeeded") } catch { print("INJECTED_WRITE: \(error)") }
  do { _ = try await failing.enqueue(intent); print("NEXT_WRITE: unexpectedly succeeded") } catch { print("NEXT_WRITE: \(error)") }
 }
}
