import Foundation
import KuroCore
import KuroLibrary
struct NoNetworkBackend: LibraryBackend {
 var rows: [LibraryEntry] = []
 func fetchAll(for account: AccountContext) async throws -> [LibraryEntry] { rows }
 func edit(_ edit: LibraryEdit, key: MediaKey, createIfMissing: ListStatus?, mutationId: UUID, baseRevision: Int64?, account: AccountContext) async throws -> LibraryWriteResult { throw LibraryError.unavailable(message: "no network") }
 func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult { throw LibraryError.unavailable(message: "no network") }
 func remove(_ key: MediaKey, account: AccountContext) async throws { throw LibraryError.unavailable(message: "no network") }
}
@MainActor final class LossyProgressServer: HomeProgressSending {
 var revision:Int64=1, position=3, loseFirst=true, suspended=true
 var attempts:[Data]=[], receipts:[String:ProgressMutationResult.Item]=[:]
 private var continuation:CheckedContinuation<Void,Never>?
 func resume() { suspended=false; continuation?.resume(); continuation=nil }
 func apply(_ mutations:[RPCProgressMutationsParams.Mutation]) async throws -> ProgressMutationResult {
  // Compare request values deterministically. JSON object-key order is not a
  // mutation field and the default encoder can reorder it between attempts.
  let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]
  attempts.append(try encoder.encode(RPCProgressMutationsParams(p_mutations:mutations)))
  if suspended { await withCheckedContinuation { continuation=$0 } }
  var result:[ProgressMutationResult.Item]=[]
  for item in mutations {
   if let existing=receipts[item.mutation_id] {
    result.append(.init(mutationId:item.mutation_id,outcome:existing.outcome=="applied" ? "already_applied" : existing.outcome,serverRevision:existing.serverRevision,position:existing.position))
   } else {
    let outcome=item.base_revision==revision ? "applied" : "conflict"
    if outcome=="applied" { revision+=1; if let next = item.position { position=next } }
    let receipt=ProgressMutationResult.Item(mutationId:item.mutation_id,outcome:outcome,serverRevision:revision,position:position)
    receipts[item.mutation_id]=receipt; result.append(receipt)
   }
  }
  if loseFirst { loseFirst=false; throw LibraryError.retryable(message:"Response lost AFTER commit") }
  return .init(items:result)
 }
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
   for _ in 0..<100 { group.addTask { @MainActor in
    await home.advance(medium: "anime", mediaId: 7, lifecycleId: lifecycle, baseRevision: 1, serverProgress: 3)
   } }
  }
  home.cancelAccountWork()
  let actual=home.displayedProgress(medium:"anime",mediaId:7,server:3,lifecycleId:UUID(uuidString:lifecycle))
  precondition(actual == 103,"Lost concurrent Home advances")
  let replacement=UUID()
  precondition(home.displayedProgress(medium:"anime",mediaId:7,server:0,lifecycleId:replacement)==0,"Old lifecycle projected into new row")
  await home.advance(medium:"anime",mediaId:7,lifecycleId:replacement.uuidString,baseRevision:1,serverProgress:0)
  precondition(home.displayedProgress(medium:"anime",mediaId:7,server:0,lifecycleId:replacement)==1,"New lifecycle advance reused old progress")
  print("HOME_LIFECYCLE_ISOLATION: PASS old103 new1")
  let work=Task { @MainActor in await home.advance(medium:"anime",mediaId:9,lifecycleId:UUID().uuidString,baseRevision:1,serverProgress:2) }
  await Task.yield()
  _ = account.begin(userId:"b"); library.bind(account.current!); home.cancelAccountWork(); home.clearPrivateState()
  await work.value
  precondition(home.pendingPosition(medium:"anime",mediaId:9)==nil,"Old account republished after a switch")
  print("HOME_ACCOUNT_PUBLICATION: PASS")

  print("HOME_RAPID_TAPS: PASS taps100 initial3 expected103 actual\(actual)")
  print("HOME_RAPID_TAPS: persisted-row-count=\(try await box.count(accountId: "a"))")
  // Execute the real Home drain/FIFO/lease path with a deterministic lossy transport.
  let transportPath=FileManager.default.temporaryDirectory.appendingPathComponent("home-transport-\(UUID()).sqlite").path
  defer { try? FileManager.default.removeItem(atPath:transportPath) }
  let transportBox=try ProgressOutbox(path:transportPath), sender=LossyProgressServer()
  let transportAccount=AccountSessionCoordinator(); _ = transportAccount.begin(userId:"a")
  let transportLibrary=LibraryStore(backend:NoNetworkBackend()); transportLibrary.bind(transportAccount.current!)
  let tested=HomeStore(accountSession:transportAccount,library:transportLibrary,outbox:transportBox,progressSender:sender)
  let transportLife=UUID().uuidString
  await tested.advance(medium:"anime",mediaId:7,lifecycleId:transportLife,baseRevision:1,serverProgress:3)
  for _ in 0..<400 { if !sender.attempts.isEmpty { break }; try await Task.sleep(for:.milliseconds(5)) }
  precondition(!sender.attempts.isEmpty,"Actual drain never dispatched")
  await withTaskGroup(of:Void.self) { group in
   for _ in 0..<99 { group.addTask { @MainActor in await tested.advance(medium:"anime",mediaId:7,lifecycleId:transportLife,baseRevision:1,serverProgress:3) } }
  }
  precondition(tested.displayedProgress(medium:"anime",mediaId:7,server:3,lifecycleId:UUID(uuidString:transportLife))==103)
  sender.resume()
  for _ in 0..<400 { if try await transportBox.active(accountId:"a").allSatisfy({$0.state != "in_flight"}) { break }; try await Task.sleep(for:.milliseconds(5)) }
  await tested.drain()
  precondition(sender.attempts.count>=3,"Retry and successor were not drained")
  precondition(sender.attempts[0]==sender.attempts[1],"Lost-response retry changed its immutable payload")
  precondition(sender.position==103,"Server lost rapid taps across response loss")
  precondition(tested.conflict==nil,"Home conflicted with its own acknowledged write")
  let remaining = try await transportBox.active(accountId:"a")
  precondition(remaining.isEmpty,"Pending queue did not drain")
  precondition(tested.displayedProgress(medium:"anime",mediaId:7,server:3,lifecycleId:UUID(uuidString:transportLife))==103,"ACK cleared confirmed fallback")
  await tested.advance(medium:"anime",mediaId:7,lifecycleId:transportLife,baseRevision:1,serverProgress:3)
  for _ in 0..<400 { if sender.position==104 { break }; try await Task.sleep(for:.milliseconds(5)) }
  precondition(sender.position==104 && tested.conflict==nil,"Tap after ACK used stale revision")
  tested.cancelAccountWork()
  print("HOME_ACTUAL_DRAIN: PASS lost response after commit, immutable retry, 100 taps, ACK successor, unloaded Library, tap-after-ACK")

  // Actual personal cache / Library / Home restore, with no provider or hosted session claim.
  let cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("home-cache-\(UUID())")
  let cachePath = FileManager.default.temporaryDirectory.appendingPathComponent("home-cache-outbox-\(UUID()).sqlite")
  defer { try? FileManager.default.removeItem(at: cacheDirectory); try? FileManager.default.removeItem(at: cachePath) }
  let cache = HomePersonalSnapshotCache(directory: cacheDirectory)
  let cacheAccount = AccountSessionCoordinator(); _ = cacheAccount.begin(userId: UUID().uuidString.lowercased())
  let owner = cacheAccount.current!, cachedLife = UUID(), cachedUnit = UUID(), cachedKey = MediaKey(kind: .anime, id: 7)
  let baseline = LibraryEntry(key: cachedKey, rowId: 42, status: .current, progress: 3, rating: UserRating(value: 8),
    notes: "owner-only note", createdAt: .distantPast, updatedAt: Date(), revision: 1, lifecycleId: cachedLife)
  let onlineLibrary = LibraryStore(backend: NoNetworkBackend(rows: [baseline])); onlineLibrary.bind(owner)
  try await onlineLibrary.refresh()
  let fixture: HomeBundle = try JSONDecoder().decode(HomeBundle.self, from: Data(("""
  {"medium":"anime","window_days":7,"home_revision":5,"active":[{"media_id":7,"list_type":"WATCHING","progress":3,"server_revision":1,"lifecycle_id":"\(cachedLife.uuidString)","title":"Saved personal title"}],"upcoming":[],"pending":[],"schedule_state":"fresh","next_cursor":null,"club":{"state":"ready","label":"DO_NOT_STORE_CLUB_LABEL","items":[{"comment_id":"c1","media_id":7,"media_type":"anime","text":"DO_NOT_STORE_CLUB_BODY","display_name":"DO_NOT_STORE_CLUB_NAME"}]}}
  """).utf8))
  let onlineHome = HomeStore(accountSession: cacheAccount, library: onlineLibrary, personalSnapshots: cache)
  await onlineHome.persistPersonalSnapshot(fixture, for: owner)
  let saved = await cache.read(accountId: owner.userId, medium: "anime")
  precondition(saved != nil, "Accepted personal snapshot not written")
  let olderBaseline = LibraryEntry(key: cachedKey, rowId: 42, status: .current, progress: 2,
    createdAt: .distantPast, updatedAt: Date(), revision: 0, lifecycleId: cachedLife)
  precondition(HomePersonalSnapshot(accountId: owner.userId, bundle: fixture,
    baselines: [cachedKey:olderBaseline]) == nil, "Snapshot mixed newer Home with older Library fields")
  for replacement in [Optional<LibraryEntry>.none, LibraryEntry(key: cachedKey, rowId: 43, status: .current,
    progress: 1, createdAt: .distantPast, updatedAt: Date(), revision: 2, lifecycleId: UUID()),
    LibraryEntry(key: cachedKey, rowId: 42, status: .completed, progress: 3,
      createdAt: .distantPast, updatedAt: Date(), revision: 2, lifecycleId: cachedLife)] {
    let currentLibrary = LibraryStore(backend: NoNetworkBackend(rows: replacement.map { [$0] } ?? []))
    currentLibrary.bind(owner); try await currentLibrary.refresh()
    let currentHome = HomeStore(accountSession: cacheAccount, library: currentLibrary, personalSnapshots: cache)
    let staleRestored = await currentHome.restorePersonalSnapshot(for: owner)
    precondition(!staleRestored && currentHome.bundle == nil, "Removed/replaced lifecycle restored from stale Home cache")
    // Also exercise a cache restored before the full authoritative Library read.
    let delayedLibrary = LibraryStore(backend: NoNetworkBackend(rows: replacement.map { [$0] } ?? []))
    delayedLibrary.bind(owner)
    let delayedHome = HomeStore(accountSession: cacheAccount, library: delayedLibrary, personalSnapshots: cache)
    let initialRestore = await delayedHome.restorePersonalSnapshot(for: owner)
    precondition(initialRestore)
    try await delayedLibrary.refresh()
    await delayedHome.load()
    precondition(delayedHome.bundle == nil && !delayedHome.isUsingCachedSnapshot,
      "Offline fallback retained a lifecycle invalidated by a complete Library read")
  }
  let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
  let bytes = try Data(contentsOf: files[0]); let persisted = String(decoding: bytes, as: UTF8.self)
  precondition(!persisted.contains("DO_NOT_STORE"), "Club content reached disk")
  let offlineBox = try ProgressOutbox(path: cachePath.path)
  _ = try await offlineBox.enqueue(ProgressIntent(accountId: owner.userId, medium: "anime", mediaId: 7,
    lifecycleId: cachedLife, unitId: cachedUnit, baseRevision: 1, position: 7, positionLabel: "7.5", priorPosition: 3))
  let offlineLibrary = LibraryStore(backend: NoNetworkBackend()); offlineLibrary.bind(owner)
  let offlineHome = HomeStore(accountSession: cacheAccount, library: offlineLibrary, outbox: offlineBox, personalSnapshots: cache)
  let mediumPreferenceKey = "kuro.home.medium.\(owner.userId.lowercased())"
  defer { UserDefaults.standard.removeObject(forKey: mediumPreferenceKey) }
  UserDefaults.standard.set("manga", forKey: mediumPreferenceKey)
  let recovered = await offlineHome.restorePersonalSnapshot(for: owner)
  precondition(offlineHome.medium == "anime", "Launch restore lost its available Anime cache fallback")
  offlineHome.selectMedium("manga")
  await offlineHome.load()
  precondition(offlineHome.medium == "manga" && offlineHome.bundle == nil,
    "A deliberate uncached Manga selection was replaced by the cached Anime fallback")
  _ = await offlineHome.restorePersonalSnapshot(for: owner)
  precondition(offlineHome.medium == "manga", "A late launch bootstrap overrode an already selected Manga tab")
  offlineHome.selectMedium("anime")
  precondition(recovered, "Offline foundation metadata not restored")
  precondition(offlineHome.bundle?.active.first?.title == "Saved personal title")
  precondition(offlineHome.bundle?.club.items.isEmpty == true)
  precondition(offlineHome.displayedProgress(medium:"anime",mediaId:7,server:3,lifecycleId:cachedLife) == 7)
  precondition(offlineHome.displayedProgressLabel(medium:"anime",mediaId:7,serverLabel:nil,lifecycleId:cachedLife) == "7.5")
  precondition(offlineLibrary.entry(for:cachedKey)?.unitId == cachedUnit)
  precondition(offlineLibrary.entry(for:cachedKey)?.notes == "owner-only note")
  await offlineHome.load()
  precondition(offlineHome.loadState == .loaded && offlineHome.isUsingCachedSnapshot,
    "An unavailable Home transport hid the accepted personal cache")
  precondition(offlineLibrary.entry(for: LibraryKnowledgeQuery(MediaKey(kind:.anime,id:999))) == .unknown,
    "Partial cache claimed a missing title was definitively absent")
  _ = cacheAccount.begin(userId: UUID().uuidString.lowercased()); let other = cacheAccount.current!
  offlineLibrary.bind(other); offlineHome.cancelAccountWork(); offlineHome.clearPrivateState()
  let recoveredOther = await offlineHome.restorePersonalSnapshot(for: other)
  precondition(!recoveredOther, "Another account read owner's snapshot")
  precondition(offlineHome.bundle == nil && offlineLibrary.entry(for:cachedKey) == nil)
  let otherSnapshot = HomePersonalSnapshot(accountId:other.userId,bundle:fixture,baselines:[cachedKey:baseline])!
  try await cache.write(otherSnapshot)
  try await cache.remove(accountId: owner.userId)
  try await cache.write(saved!) // A late callback must not recreate a deleted account file.
  let removedOwner = await cache.read(accountId:owner.userId,medium:"anime")
  let retainedOther = await cache.read(accountId:other.userId,medium:"anime")
  precondition(removedOwner == nil)
  precondition(retainedOther != nil)
  let expired = HomePersonalSnapshot(accountId:other.userId,bundle:fixture,baselines:[cachedKey:baseline],now:Date().addingTimeInterval(-8*86_400))!
  precondition(!expired.isValid(for:other.userId,medium:"anime",now:Date()))
  offlineHome.cancelAccountWork()
  print("PERSONAL_HOME_OFFLINE_RESTORE: PASS explicit medium selection, launch fallback, title, coherent revision, active membership/lifecycle, durable fractional unit, account isolation, club exclusion, partial knowledge, expiry, deletion/late-write isolation")

  let conflictPath = FileManager.default.temporaryDirectory.appendingPathComponent("home-conflict-\(UUID()).sqlite")
  defer { try? FileManager.default.removeItem(at: conflictPath) }
  let conflictBox = try ProgressOutbox(path: conflictPath.path)
  let conflictLibrary = LibraryStore(backend: NoNetworkBackend()); conflictLibrary.bind(owner)
  conflictLibrary.configureProgress(outbox: conflictBox, acceptsWrites: { false }) { _,_ in
    throw LibraryError.unavailable(message:"no network")
  }
  let oldHead = try await conflictBox.enqueue(ProgressIntent(accountId:owner.userId,medium:"anime",mediaId:7,
    lifecycleId:cachedLife,baseRevision:1,position:4))
  _ = try await conflictBox.claim(accountId:owner.userId)
  try await conflictBox.recordConflict(oldHead.mutationId,revision:2,position:8)
  try await conflictLibrary.restoreProgress(); let oldControl = conflictLibrary.progressConflict!
  _ = try await conflictBox.resolveConflict(accountId:owner.userId,medium:"anime",mediaId:7,
    lifecycleId:cachedLife,serverRevision:2,serverPosition:8,reapply:false)
  let newHead = try await conflictBox.enqueue(ProgressIntent(accountId:owner.userId,medium:"anime",mediaId:7,
    lifecycleId:cachedLife,baseRevision:2,position:9))
  _ = try await conflictBox.claim(accountId:owner.userId)
  try await conflictBox.recordConflict(newHead.mutationId,revision:3,position:11)
  try await conflictLibrary.restoreProgress(); let newControl = conflictLibrary.progressConflict!
  try await conflictLibrary.resolveProgressConflict(reapply:false, expected:oldControl)
  let unchangedConflict = try await conflictBox.conflicts(accountId:owner.userId)
  precondition(unchangedConflict.first?.mutationId == newHead.mutationId,
    "An obsolete control resolved the newer conflict")
  let successor = try await conflictBox.enqueue(ProgressIntent(accountId:owner.userId,medium:"anime",mediaId:7,
    lifecycleId:cachedLife,baseRevision:3,position:12,status:"WATCHING"))
  do {
    try await conflictLibrary.resolveProgressConflict(reapply:false, expected:newControl)
    preconditionFailure("An obsolete decision discarded a newer disk admission")
  } catch ProgressOutboxError.storage { }
  let retainedSuccessor = try await conflictBox.latest(accountId:owner.userId,medium:"anime",mediaId:7,lifecycleId:cachedLife)
  precondition(retainedSuccessor?.mutationId == successor.mutationId && retainedSuccessor?.state == "pending")
  print("HOME_CONFLICT_CONTROL_IDENTITY: PASS newer conflict and newer disk admission survive stale controls")

 }
}
