import Foundation
import KuroLibrary
import SQLite3
import Testing

@Test func twentyTapsCollapseToTheLatestPositionAndSurviveReopen() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-outbox-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let account = "user-1"
    let first = try ProgressOutbox(path: url.path)
    var prior: Int? = 3
    var last = ProgressIntent(accountId: account, medium: "anime", mediaId: 7, lifecycleId: UUID(), baseRevision: 4, position: 3, priorPosition: prior)
    for step in 1...20 {
        last = try await first.enqueue(ProgressIntent(
            accountId: account,
            medium: "anime",
            mediaId: 7,
            lifecycleId: last.lifecycleId,
            baseRevision: 4,
            position: 3 + step,
            priorPosition: prior
        ))
        prior = last.priorPosition
    }
    let pending = try await first.pending(accountId: account, limit: 50)
    #expect(pending.count == 1)
    #expect(pending[0].position == 23)
    #expect(pending[0].priorPosition == 3)
    #expect(pending[0].mutationId == last.mutationId)
    #expect(try await first.count(accountId: account) == 1)

    let reopened = try ProgressOutbox(path: url.path)
    let again = try await reopened.pending(accountId: account, limit: 10)
    #expect(again.count == 1)
    #expect(again[0].position == 23)
    let restored = try await reopened.cancelPending(accountId: account, medium: "anime", mediaId: 7)
    #expect(restored == 3)
    #expect(try await reopened.pending(accountId: account, limit: 10).isEmpty)
}

@Test func importBatchCollapsesDuplicatesAndDropsPrivateNotesAndZeroScores() {
    let drafts = [
        LibraryImportDraft(medium: "anime", externalId: "1", status: "watching", progress: 1, scoreRaw: "0", notes: "secret", isPrivate: true),
        LibraryImportDraft(medium: "anime", externalId: "1", status: "completed", progress: 12, scoreRaw: "8", notes: "public"),
        LibraryImportDraft(medium: "manga", externalId: "2", status: "reading", progress: 3, scoreRaw: "0.0", notes: "keep"),
    ]
    let prepared = LibraryImportBatch.prepare(drafts)
    #expect(prepared.count == 2)
    #expect(prepared[0].status == "completed")
    #expect(prepared[0].scoreRaw == "8")
    #expect(prepared[0].notes == "public")
    #expect(prepared[1].scoreRaw == nil)
    #expect(prepared[1].notes == "keep")
    #expect(LibraryImportBatch.chunks([]).isEmpty)
    #expect(LibraryImportBatch.chunks([drafts[2]]).count == 1)
    let fifty = (1...50).map { LibraryImportDraft(medium: "anime", externalId: "\($0)", status: "watching", progress: $0) }
    #expect(LibraryImportBatch.chunks(fifty).count == 1)
    #expect(LibraryImportBatch.chunks(fifty)[0].count == 50)
    let many = (1...101).map { LibraryImportDraft(medium: "anime", externalId: "\($0)", status: "watching", progress: 1) }
    #expect(LibraryImportBatch.chunks(many).count == 2)
}

@Test func outboxDrainStaysInsideTheAccount() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-outbox-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let box = try ProgressOutbox(path: url.path)
    _ = try await box.enqueue(ProgressIntent(accountId: "a", medium: "anime", mediaId: 1, position: 2, priorPosition: 1))
    _ = try await box.enqueue(ProgressIntent(accountId: "b", medium: "anime", mediaId: 1, position: 4, priorPosition: 3))
    let pendingA = try await box.pending(accountId: "a", limit: 50)
    let pendingB = try await box.pending(accountId: "b", limit: 50)
    #expect(pendingA.map(\.position) == [2])
    #expect(pendingB.map(\.position) == [4])
    #expect(try await box.cancelPending(accountId: "a", medium: "anime", mediaId: 1) == 1)
    #expect(try await box.pending(accountId: "b", limit: 50).count == 1)
}

@Test func groupingRequiresReviewedContinuityAndIgnoresCalendarSeasons() {
    #expect(SeriesGrouping.ordinal(fromCalendarSeason: "WINTER") == nil)
    #expect(SeriesGrouping.decide(ContinuityEvidence(link: .adaptation, sameReviewedContinuity: false, format: "TV")) == .distinct(reason: "no approved continuity membership"))
    #expect(SeriesGrouping.decide(ContinuityEvidence(link: .sequel, sameReviewedContinuity: false, format: "TV")) == .distinct(reason: "no approved continuity membership"))
    #expect(SeriesGrouping.decide(ContinuityEvidence(link: .sequel, sameReviewedContinuity: true, format: "MOVIE")) == .join(label: "Film"))
    #expect(SeriesGrouping.decide(ContinuityEvidence(link: .sideStory, sameReviewedContinuity: true, format: "TV")) == .join(label: nil))
}

@Test func malExportKeepsRawScoreNotesAndRejectsEntities() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <myanimelist>
      <anime>
        <series_animedb_id>5114</series_animedb_id>
        <my_watched_episodes>12</my_watched_episodes>
        <my_status>Watching</my_status>
        <my_score>0</my_score>
        <my_comments>private note</my_comments>
        <my_times_watched>2</my_times_watched>
        <my_start_date>0000-00-00</my_start_date>
        <my_finish_date>2020-01-02</my_finish_date>
      </anime>
      <manga>
        <series_mangadb_id>42</series_mangadb_id>
        <my_read_chapters>3</my_read_chapters>
        <my_read_volumes>1</my_read_volumes>
        <my_status>Reading</my_status>
        <my_score>8</my_score>
      </manga>
    </myanimelist>
    """
    let items = try MALExportParser.parse(Data(xml.utf8))
    #expect(items.count == 2)
    #expect(items[0].externalId == "5114")
    #expect(items[0].status == "watching")
    #expect(items[0].scoreRaw == nil)
    #expect(items[0].notes == "private note")
    #expect(items[0].startedRaw == nil)
    #expect(items[0].finishedRaw == "2020-01-02")
    #expect(items[0].repeatCount == 2)
    #expect(items[1].medium == "manga")
    #expect(items[1].scoreRaw == "8")
    #expect(items[1].volumesProgress == 1)

    let attack = Data("<?xml version=\"1.0\"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM \"file:///etc/passwd\">]><myanimelist></myanimelist>".utf8)
    #expect(throws: MALExportError.externalEntity) {
        try MALExportParser.parse(attack)
    }
}

@Test func concurrentAdvancesUseDurableProjectionAndCap() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-atomic-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let box = try ProgressOutbox(path: url.path)
    let lifecycle = UUID()
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<100 {
            group.addTask {
                _ = try await box.advance(ProgressIntent(accountId: "a", medium: "anime", mediaId: 7,
                    lifecycleId: lifecycle, baseRevision: 1, position: 3), cap: 80)
            }
        }
        try await group.waitForAll()
    }
    let rows = try await box.pending(accountId: "a", limit: 50)
    #expect(rows.count == 1)
    #expect(rows.first?.position == 80)
    #expect(rows.first?.priorPosition == 3)
}

@Test func attemptedPayloadIsImmutableAndFailedSendRetriesInProcess() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-retry-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let box = try ProgressOutbox(path: url.path)
    let lifecycle = UUID()
    let first = try await box.enqueue(ProgressIntent(accountId: "a", medium: "anime", mediaId: 7,
        lifecycleId: lifecycle, unitId: UUID(), baseRevision: 1, position: 4))
    let claimed = try await box.claim(accountId: "a")
    #expect(claimed.map(\.mutationId) == [first.mutationId])
    let newer = try await box.enqueue(ProgressIntent(accountId: "a", medium: "anime", mediaId: 7,
        lifecycleId: lifecycle, unitId: UUID(), baseRevision: 1, position: 5))
    #expect(newer.mutationId != first.mutationId)
    #expect(try await box.claim(accountId: "a").isEmpty)
    try await box.release([first.mutationId])
    let retried = try await box.claim(accountId: "a")
    #expect(retried.first?.mutationId == first.mutationId)
    #expect(retried.first?.position == 4)
    #expect(retried.first?.unitId == first.unitId)
    try await box.acknowledge(first.mutationId, revision: 2, position: 4)
    let successor = try await box.claim(accountId: "a")
    #expect(successor.first?.position == 5)
    #expect(successor.first?.baseRevision == 2)
    #expect(successor.first?.unitId == newer.unitId)
}

@Test func coalescedUnitExactlyMatchesDiskAndReturn() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-unit-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let box = try ProgressOutbox(path: url.path)
    let lifecycle = UUID()
    _ = try await box.enqueue(ProgressIntent(accountId: "a", medium: "manga", mediaId: 1,
        lifecycleId: lifecycle, unitId: UUID(), baseRevision: 1, position: 2, positionLabel: "2.5"))
    let latest = try await box.enqueue(ProgressIntent(accountId: "a", medium: "manga", mediaId: 1,
        lifecycleId: lifecycle, unitId: UUID(), baseRevision: 1, position: 3, positionLabel: "3.5", status: "READING"))
    let stored = try await box.pending(accountId: "a", limit: 50)
    #expect(stored.first == latest)
}

@Test func importFingerprintIncludesEveryRetainedFieldAndIdentity() {
    let base = LibraryImportDraft(medium: "manga", externalId: "7", status: "reading", progress: 2,
        notes: "owner-only", isPrivate: true, customLists: ["Weekend"])
    #expect(LibraryImportBatch.prepare([base]).first?.notes == "owner-only")
    var variants: [LibraryImportDraft] = []
    var copy = base; copy.volumesProgress = 1; variants.append(copy)
    copy = base; copy.startedRaw = "2026-10"; variants.append(copy)
    copy = base; copy.finishedRaw = "2026"; variants.append(copy)
    copy = base; copy.scoreScale = "POINT_100"; variants.append(copy)
    copy = base; copy.isPrivate = false; variants.append(copy)
    copy = base; copy.customLists = ["Classics"]; variants.append(copy)
    copy = base; copy.hiddenFromStatusLists = true; variants.append(copy)
    let hash = LibraryImportBatch.payloadHash([base], provider: "anilist", sourceKind: "account")
    for variant in variants {
        #expect(LibraryImportBatch.payloadHash([variant], provider: "anilist", sourceKind: "account") != hash)
    }
    #expect(LibraryImportBatch.payloadHash([base], provider: "myanimelist", sourceKind: "export") != hash)
    var duplicate = base; duplicate.customLists = ["Classics"]
    #expect(LibraryImportBatch.prepare([base, duplicate]).first?.customLists == ["Classics", "Weekend"])
}

@Test func abortedDiskWriteRollsBackAndConnectionRemainsUsable() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-abort-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let box = try ProgressOutbox(path: url.path)
    var connection: OpaquePointer?
    #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
    defer { sqlite3_close(connection) }
    #expect(sqlite3_exec(connection, "create trigger fail_insert before insert on intents begin select raise(abort, 'injected'); end;", nil, nil, nil) == SQLITE_OK)
    for _ in 0..<2 {
        do {
            _ = try await box.enqueue(ProgressIntent(accountId: "a", medium: "anime", mediaId: 1, position: 1))
            Issue.record("Injected write should fail")
        } catch { #expect(error as? ProgressOutboxError == .storage("injected")) }
    }
    #expect(sqlite3_exec(connection, "drop trigger fail_insert", nil, nil, nil) == SQLITE_OK)
    _ = try await box.enqueue(ProgressIntent(accountId: "a", medium: "anime", mediaId: 1, position: 1))
    #expect(try await box.pending(accountId: "a", limit: 50).first?.position == 1)
}

@Test func releasingPartialBatchNeverReopensAcknowledgedRequests() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-partial-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let box = try ProgressOutbox(path: url.path)
    let first = try await box.enqueue(ProgressIntent(accountId: "a", medium: "anime", mediaId: 1, lifecycleId: UUID(), baseRevision: 1, position: 3))
    let second = try await box.enqueue(ProgressIntent(accountId: "a", medium: "anime", mediaId: 2, lifecycleId: UUID(), baseRevision: 1, position: 7))
    _ = try await box.claim(accountId: "a")
    try await box.acknowledge(first.mutationId, revision: 2, position: 3)
    try await box.release([first.mutationId, second.mutationId])
    #expect(try await box.latest(accountId: "a", medium: "anime", mediaId: 1)?.state == "acked")
    let retry = try await box.claim(accountId: "a")
    #expect(retry.map(\.mutationId) == [second.mutationId])
    #expect(retry.first?.baseRevision == 1)
}

@Test func emptyImportCountersDecodeAsZero() throws {
    #expect(try JSONDecoder().decode(LibraryImportCounts.self, from: Data("{}".utf8)) == LibraryImportCounts())
}

@Test func conflictSurvivesReopenAndKeepCancelsEverySuccessor() async throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("kuro-conflict-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at:url) }
    let life=UUID(),box=try ProgressOutbox(path:url.path)
    let head=try await box.enqueue(ProgressIntent(accountId:"a",medium:"manga",mediaId:1,lifecycleId:life,baseRevision:1,position:4))
    _ = try await box.claim(accountId:"a")
    _ = try await box.enqueue(ProgressIntent(accountId:"a",medium:"manga",mediaId:1,lifecycleId:life,baseRevision:1,position:6))
    try await box.recordConflict(head.mutationId,revision:5,position:10)
    #expect(try await box.pending(accountId:"a",limit:50).isEmpty)
    let reopened=try ProgressOutbox(path:url.path)
    #expect(try await reopened.conflicts(accountId:"a").first?.conflictPosition == 10)
    _ = try await reopened.resolveConflict(accountId:"a",medium:"manga",mediaId:1,lifecycleId:life,serverRevision:5,serverPosition:10,reapply:false)
    #expect(try await reopened.active(accountId:"a").isEmpty)
    #expect(try await reopened.conflicts(accountId:"a").isEmpty)
    #expect(try await reopened.confirmations(accountId:"a").first?.position == 10)
    let next=try await reopened.advance(ProgressIntent(accountId:"a",medium:"manga",mediaId:1,lifecycleId:life,baseRevision:1,position:3))
    #expect(next.position == 11)
    #expect(next.baseRevision == 5)
}

@Test func conflictReapplyRetainsFractionalUnitAndNewestIntent() async throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("kuro-fraction-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at:url) }
    let life=UUID(),unit=UUID(),box=try ProgressOutbox(path:url.path)
    let head=try await box.enqueue(ProgressIntent(accountId:"a",medium:"manga",mediaId:1,lifecycleId:life,baseRevision:1,position:4))
    _ = try await box.claim(accountId:"a")
    _ = try await box.enqueue(ProgressIntent(accountId:"a",medium:"manga",mediaId:1,lifecycleId:life,unitId:unit,baseRevision:1,position:6,positionLabel:"6.5",status:"READING"))
    try await box.recordConflict(head.mutationId,revision:5,position:10)
    let decision=try await box.resolveConflict(accountId:"a",medium:"manga",mediaId:1,lifecycleId:life,serverRevision:5,serverPosition:10,reapply:true)
    let pending=try await box.pending(accountId:"a",limit:50)
    #expect(pending.count == 1)
    #expect(pending.first?.mutationId == decision.mutationId)
    #expect(decision.mutationId != head.mutationId)
    #expect(decision.unitId == unit && decision.positionLabel == "6.5" && decision.position == 6)
    #expect(decision.status == "READING" && decision.baseRevision == 5)
}

@Test func expiredClaimRecoversWithoutAnotherPendingTitle() async throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("kuro-expired-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at:url) }
    let box=try ProgressOutbox(path:url.path)
    let head=try await box.enqueue(ProgressIntent(accountId:"a",medium:"anime",mediaId:1,lifecycleId:UUID(),baseRevision:1,position:4))
    _ = try await box.claim(accountId:"a")
    var connection:OpaquePointer?; #expect(sqlite3_open(url.path,&connection)==SQLITE_OK)
    defer { sqlite3_close(connection) }
    #expect(sqlite3_exec(connection,"update intents set claimed_at=0",nil,nil,nil)==SQLITE_OK)
    #expect(try await box.pending(accountId:"a",limit:50).first?.mutationId == head.mutationId)
    try await box.rebaseUnsent(accountId:"a",medium:"anime",mediaId:1,lifecycleId:head.lifecycleId!,revision:9)
    #expect(try await box.pending(accountId:"a",limit:50).first?.baseRevision == 1)
}

@Test func providerPageJournalReplaysExactPrivatePayloadAndAtomicCursor() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("kuro-import-journal-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at:directory) }
    let journal=try LibraryImportPageJournal(directory:directory)
    let draft=LibraryImportDraft(medium:"manga",externalId:"7",status:"reading",progress:6,notes:"private",isPrivate:true,customLists:["Weekend"])
    let saved=LibraryImportPageJournal.Checkpoint(cursor:"page1",page:.init(drafts:[draft],nextCursor:"page2",exhausted:false))
    try await journal.write(saved,key:"account-a/selection")
    let reopened=try LibraryImportPageJournal(directory:directory)
    #expect(try await reopened.read(key:"account-a/selection")==saved)
    #expect(try await reopened.read(key:"account-b/selection").page == nil)
    try await reopened.write(.init(cursor:"page2"),key:"account-a/selection")
    #expect(try await journal.read(key:"account-a/selection")==LibraryImportPageJournal.Checkpoint(cursor:"page2"))
    try await reopened.remove(key:"account-a/selection")
    #expect(try await journal.read(key:"account-a/selection").cursor == nil)
}

@Test func confirmationsPreferLatestLifecycleEvenWhenItsRevisionIsLower() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-lifecycles-\(UUID()).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let box = try ProgressOutbox(path: url.path), oldLife = UUID(), newLife = UUID()
    let old = try await box.enqueue(ProgressIntent(accountId: "a", medium: "anime", mediaId: 1, lifecycleId: oldLife,baseRevision: 49,position: 30))
    _ = try await box.claim(accountId: "a", limit: 50)
    try await box.acknowledge(old.mutationId,revision: 50,position: 30)
    let new = try await box.enqueue(ProgressIntent(accountId: "a", medium: "anime", mediaId: 1,lifecycleId: newLife,baseRevision: 1,position: 2))
    _ = try await box.claim(accountId: "a", limit: 50)
    try await box.acknowledge(new.mutationId,revision: 2,position: 2)
    let reopened = try ProgressOutbox(path: url.path)
    let confirmations = try await reopened.confirmations(accountId: "a")
    #expect(confirmations.count == 1)
    #expect(confirmations.first?.lifecycleId == newLife)
    #expect(confirmations.first?.position == 2)
}

@Test func importRetainsShelfOrderAndSourceOptionsAcrossJournal() throws {
    let options = "{\"sectionOrder\":[\"Favorites\",\"Later\"]}"
    let draft = LibraryImportDraft(medium: "anime",externalId: "7",status: "watching",progress: 3,
        scoreRaw: "3",scoreScale: "POINT_3",customLists: ["Favorites","Later"],sourceListOptions: options,normalizedRating: 10)
    let merged = LibraryImportBatch.prepare([draft,draft])
    #expect(merged[0].customLists == ["Favorites","Later"])
    #expect(merged[0].normalizedRating == 10)
    #expect(try JSONDecoder().decode(LibraryImportDraft.self,from: JSONEncoder().encode(merged[0])).sourceListOptions == options)
}

@Test func malExportPreservesCDATAAndRejectsSilentRowOrNoteLoss() throws {
    let xml = """
    <myanimelist><manga><series_mangadb_id>7</series_mangadb_id><my_status>Reading</my_status>
    <my_read_chapters>12</my_read_chapters><my_comments><![CDATA[  Private <note> & details  ]]></my_comments>
    </manga></myanimelist>
    """
    let row = try #require(MALExportParser.parse(Data(xml.utf8)).first)
    #expect(row.notes == "  Private <note> & details  ")
    #expect(row.draft().notes == row.notes)
    #expect(row.draft().sourceListOptions?.contains("unavailable_fields") == true)
    #expect(throws: MALExportError.malformed) {
        try MALExportParser.parse(Data(xml.replacingOccurrences(of: "<series_mangadb_id>7", with: "<series_mangadb_id>oops").utf8))
    }
    let oversized = xml.replacingOccurrences(of: "Private <note> & details", with: String(repeating: "x", count: 16_385))
    #expect(throws: MALExportError.tooLarge) { try MALExportParser.parse(Data(oversized.utf8)) }
    let attack = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><!DOCTYPE myanimelist [<!ENTITY x \"secret\">]><myanimelist/>"
    #expect(throws: MALExportError.externalEntity) {
        try MALExportParser.parse(#require(attack.data(using: .utf16)))
    }
}

@Test func importActionIdentityIsAtomicDurableAndAccountBound() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-action-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try LibraryImportPageJournal(directory: directory)
    let ids = try await withThrowingTaskGroup(of: String.self, returning: [String].self) { group in
        for _ in 0..<10 { group.addTask { try await journal.beginAction(key: "account-a/import") } }
        var values: [String] = []
        for try await id in group { values.append(id) }
        return values
    }
    #expect(Set(ids).count == 1)
    let reopened = try LibraryImportPageJournal(directory: directory)
    #expect(try await reopened.beginAction(key: "account-a/import") == ids.first)
    #expect(try await reopened.beginAction(key: "account-b/import") != ids.first)
    try await reopened.remove(key: "account-a/import")
    let newAction = try await reopened.beginAction(key: "account-a/import")
    #expect(newAction != ids.first)
    try await reopened.completeAction(key: "account-a/import", actionId: ids[0])
    #expect(try await reopened.beginAction(key: "account-a/import") == newAction)
    let legacy = try JSONDecoder().decode(LibraryImportPageJournal.Checkpoint.self, from: Data("{}".utf8))
    #expect(legacy.actionId == nil)
}

@Test func oauthAttemptCorrelatesAccountGenerationExpiryAndRFCChallenge() {
    let now = Date(timeIntervalSince1970: 1_000)
    let attempt = LibraryOAuthAttempt(accountId: "ACCOUNT-A", generation: 4, state: "state",
        verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", method: .s256, createdAt: now)
    #expect(attempt.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    #expect(attempt.accepts(state: "state", accountId: "account-a", generation: 4, now: now))
    #expect(!attempt.accepts(state: "wrong", accountId: "account-a", generation: 4, now: now))
    #expect(!attempt.accepts(state: "state", accountId: "account-b", generation: 4, now: now))
    #expect(!attempt.accepts(state: "state", accountId: "account-a", generation: 5, now: now))
    #expect(!attempt.accepts(state: "state", accountId: "account-a", generation: 4, now: now.addingTimeInterval(601)))
    let anime = LibraryProviderReference(provider: .anilist, medium: .anime, externalId: "7")
    #expect(anime != LibraryProviderReference(provider: .anilist, medium: .manga, externalId: "7"))
    #expect(anime != LibraryProviderReference(provider: .myanimelist, medium: .anime, externalId: "7"))
}

@Test func confirmedDeletionPurgesOnlyAttributedImportFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-import-delete-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try LibraryImportPageJournal(directory: directory)
    let a = UUID().uuidString.lowercased(), b = UUID().uuidString.lowercased()
    let keyA = "kuro.import.stream.\(a).selection", keyB = "kuro.import.stream.\(b).selection"
    let draft = LibraryImportDraft(medium: "manga", externalId: "7", status: "reading", progress: 2, notes: "owner-only")
    let page = LibraryImportPageJournal.Page(drafts: [draft], nextCursor: "next", exhausted: false)
    try await journal.write(.init(page: page), key: keyA)
    try await journal.write(.init(page: page), key: keyB)
    _ = try await journal.beginAction(key: "kuro.import.action.\(a).selection")
    try await journal.removeDeletedAccountData(accountId: a.uppercased())
    #expect(try await journal.read(key: keyA) == .init())
    #expect(try await journal.read(key: keyB).page == page)
    #expect(try await journal.read(key: keyB).accountId == b)
    #expect(try await journal.read(key: "kuro.import.action.\(a).selection") == .init())
    await #expect(throws: LibraryImportPageJournal.Failure.accountDeleted) {
        try await journal.write(.init(page: page), key: keyA)
    }
    try await journal.write(.init(page: page), key: keyB)

    // Without a known account/key, guessing deletion would risk destroying another account's retry.
    try await journal.write(.init(page: page), key: "unattributed-legacy-key")
    try await journal.removeDeletedAccountData(accountId: b)
    #expect(try await journal.read(key: keyB) == .init())
    #expect(try await journal.read(key: "unattributed-legacy-key").page == page)
    try await journal.remove(key: "unattributed-legacy-key")
    let corrupt = directory.appendingPathComponent("corrupt.json")
    try Data("not-json".utf8).write(to: corrupt)
    try await journal.removeDeletedAccountData(accountId: b)
    #expect(FileManager.default.fileExists(atPath: corrupt.path))
    #expect(try await journal.read(key: keyB) == .init())
    await #expect(throws: LibraryImportPageJournal.Failure.accountDeleted) {
        try await journal.write(.init(page: page), key: keyB)
    }
}

@Test func malAccountListPreservesMediumFieldsAndUnavailableNotes() throws {
    let anime = Data(#"{"data":[{"node":{"id":7},"list_status":{"status":"watching","score":0,"num_episodes_watched":12,"is_rewatching":true,"num_times_rewatched":2,"start_date":"2025-04","finish_date":null,"priority":2,"rewatch_value":4,"tags":["Favorites"],"updated_at":"2026-10-07T10:00:00+00:00"}}],"paging":{}}"#.utf8)
    let manga = Data(#"{"data":[{"node":{"id":7},"list_status":{"status":"reading","score":8,"num_chapters_read":32,"num_volumes_read":5,"is_rereading":false,"num_times_reread":1,"start_date":"2024","finish_date":"2025-02-12","tags":[]}}],"paging":{"next":null}}"#.utf8)
    let a = try MALAccountList.decode(anime, medium: .anime, offset: 0)
    let m = try MALAccountList.decode(manga, medium: .manga, offset: 0)
    #expect(a.exhausted && m.exhausted)
    #expect(a.drafts[0].medium == "anime" && m.drafts[0].medium == "manga")
    #expect(a.drafts[0].externalId == m.drafts[0].externalId)
    #expect(a.drafts[0].normalizedRating == nil && m.drafts[0].normalizedRating == 8)
    #expect(a.drafts[0].repeatCount == 2 && m.drafts[0].volumesProgress == 5)
    #expect(a.drafts[0].startedRaw == "2025-04" && m.drafts[0].startedRaw == "2024")
    #expect(a.drafts[0].notes == nil && a.drafts[0].unavailableFields.contains("notes"))
    #expect(a.drafts[0].customLists.isEmpty && a.drafts[0].unavailableFields.contains("custom_lists"))
    #expect(a.drafts[0].sourceListOptions?.contains("Favorites") == true)
    let missing = try MALAccountList.decode(Data(#"{"data":[{"node":{"id":9},"list_status":{"status":"completed"}}],"paging":{}}"#.utf8), medium: .manga, offset: 0)
    #expect(missing.drafts[0].unavailableFields.contains("progress"))
    #expect(missing.drafts[0].unavailableFields.contains("repeat_count"))
}

@Test func malAccountPagingRejectsCredentialDiversionAndMissingTerminalProof() throws {
    let good = try MALAccountList.url(medium: .anime, offset: 100).absoluteString
    #expect(try MALAccountList.nextOffset(good, medium: .anime, currentOffset: 0) == 100)
    for invalid in [good.replacingOccurrences(of: "api.myanimelist.net", with: "mal.invalid"),
        good.replacingOccurrences(of: "animelist", with: "mangalist"),
        good.replacingOccurrences(of: "offset=100", with: "offset=200"),
        good + "&offset=100", good + "&status=completed"] {
        #expect(throws: MALAccountList.Failure.self) { try MALAccountList.nextOffset(invalid, medium: .anime, currentOffset: 0) }
    }
    for malformed in [#"{"data":[]}"#, #"{"data":[],"paging":null}"#,
        #"{"data":[{"node":{"id":7},"list_status":{"status":"reading","num_chapters_read":-1}}],"paging":{}}"#] {
        #expect(throws: MALAccountList.Failure.self) { try MALAccountList.decode(Data(malformed.utf8), medium: .manga, offset: 0) }
    }
    #expect(throws: MALAccountList.Failure.self) {
        try MALAccountList.decode(Data(repeating: 32, count: MALAccountList.maximumBodyBytes + 1), medium: .anime, offset: 0)
    }
}


@Test func malAnimeCompletionCannotHideAnIncompleteMangaStream() throws {
    var cursor = MALAccountImportCursor()
    cursor.advance(.anime, to: nil)
    let restart = try MALAccountImportCursor.decode(cursor.encode())
    #expect(restart.nextMedium == .manga && restart.offset(for: .manga) == 0)
    cursor.advance(.manga, to: 100)
    let replay = try MALAccountImportCursor.decode(cursor.encode())
    #expect(replay.anime == nil && replay.manga == 100)
    cursor.advance(.manga, to: nil)
    #expect(cursor.nextMedium == nil)
}
