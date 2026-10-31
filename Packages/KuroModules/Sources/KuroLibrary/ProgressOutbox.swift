import Foundation
import SQLite3

/// One absolute progress intent. Unsent intents for the same entry collapse to the
/// latest position and keep the first mutation id, base revision and prior value.
public struct ProgressIntent: Equatable, Sendable {
    public var mutationId: UUID
    public var accountId: String
    public var medium: String
    public var mediaId: Int
    public var lifecycleId: UUID?
    public var unitId: UUID?
    public var baseRevision: Int64?
    public var position: Int
    /// False for status-only actions: position is local projection, never a wire field.
    public var writesPosition: Bool
    public var positionLabel: String?
    public var status: String?
    public var priorPosition: Int?
    public var localSequence: Int64
    public var state: String
    public var conflictRevision: Int64? = nil
    public var conflictPosition: Int? = nil

    public init(
        mutationId: UUID = UUID(),
        accountId: String,
        medium: String,
        mediaId: Int,
        lifecycleId: UUID? = nil,
        unitId: UUID? = nil,
        baseRevision: Int64? = nil,
        position: Int,
        writesPosition: Bool = true,
        positionLabel: String? = nil,
        status: String? = nil,
        priorPosition: Int? = nil,
        localSequence: Int64 = 0,
        state: String = "pending"
    ) {
        self.mutationId = mutationId
        self.accountId = accountId
        self.medium = medium
        self.mediaId = mediaId
        self.lifecycleId = lifecycleId
        self.unitId = unitId
        self.baseRevision = baseRevision
        self.position = position
        self.writesPosition = writesPosition
        self.positionLabel = positionLabel
        self.status = status
        self.priorPosition = priorPosition
        self.localSequence = localSequence
        self.state = state
    }
}

public enum ProgressOutboxError: Error, Equatable {
    case storage(String)
    case unsupportedSchema(String)
}

/// Versioned SQLite outbox in a caller-chosen file. Disk work stays off the caller's actor.
public final class ProgressOutbox: @unchecked Sendable {
    private let queue = DispatchQueue(label: "kuro.progress.outbox")
    private var database: OpaquePointer?
    private var nextSequence: Int64 = 0

    public init(path: String) throws {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let opened else {
            if let opened { sqlite3_close(opened) }
            throw ProgressOutboxError.storage("open failed")
        }
        database = opened
        do { try queue.sync {
            try exec("pragma journal_mode=WAL")
            try exec("pragma secure_delete=ON")
            try exec("begin immediate")
            defer { if sqlite3_get_autocommit(database) == 0 { try? exec("rollback") } }
            try exec("""
                create table if not exists meta (
                  key text primary key,
                  value text not null
                )
                """)
            try exec("""
                create table if not exists intents (
                  mutation_id text primary key,
                  account_id text not null,
                  medium text not null,
                  media_id integer not null,
                  lifecycle_id text,
                  unit_id text,
                  base_revision integer,
                  position integer not null,
                  position_label text,
                  status text,
                  prior_position integer,
                  local_sequence integer not null,
                  state text not null,
                  created_at real not null
                )
                """)
            try exec("create index if not exists intents_drain on intents(account_id, state, local_sequence)")
            let version = try queryString("select value from meta where key = 'schema_version'")
            if let version, version != "1" && version != "2" && version != "3" && version != "4" {
                try exec("rollback")
                throw ProgressOutboxError.unsupportedSchema(version)
            }
            if version == nil {
                try exec("insert into meta(key, value) values ('schema_version', '1')")
            }
            if version == nil || version == "1" {
                try exec("alter table intents add column attempted integer not null default 0")
                try exec("alter table intents add column claimed_at real")
                // v1 rows that might have reached the server must never be coalesced.
                try exec("update intents set attempted = 1 where state != 'pending'")
                try exec("update meta set value = '2' where key = 'schema_version'")
            }
            if version != "3" && version != "4" {
                try exec("alter table intents add column conflict_revision integer")
                try exec("alter table intents add column conflict_position integer")
                try exec("update meta set value = '3' where key = 'schema_version'")
            }
            if version != "4" {
                try exec("alter table intents add column writes_position integer not null default 1")
                try exec("update meta set value = '4' where key = 'schema_version'")
            }
            try exec("create index if not exists intents_entry on intents(account_id, medium, media_id, lifecycle_id, local_sequence)")
            nextSequence = Int64(try queryInt("select coalesce(max(local_sequence), 0) from intents") ?? 0)
            try exec("update intents set state = 'pending' where state = 'in_flight'")
            // Older schemas did not retain conflict metadata. Replay the immutable attempted
            // body to recover the same conflict receipt; it must never become a success ACK.
            try exec("update intents set state = 'pending' where state = 'conflict' and (conflict_revision is null or conflict_position is null)")
            try exec("commit")
        } } catch {
            sqlite3_close(opened)
            database = nil
            throw error
        }
        #if os(iOS)
        do { for file in [path, path + "-wal", path + "-shm"] where FileManager.default.fileExists(atPath: file) {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file)
        } } catch {
            sqlite3_close(opened)
            database = nil
            throw error
        }
        #endif
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    public func enqueue(_ intent: ProgressIntent) async throws -> ProgressIntent {
        try await run { try self.enqueueSync(intent) }
    }

    /// Computes +1 on the disk queue from the latest durable projection. Concurrent taps
    /// cannot calculate the same value across an actor suspension.
    public func advance(_ intent: ProgressIntent, cap: Int? = nil) async throws -> ProgressIntent {
        try await run {
            var next = intent
            let latest = try self.latestSync(accountId: intent.accountId, medium: intent.medium, mediaId: intent.mediaId, lifecycleId: intent.lifecycleId)
            let useLatest = latest?.state != "acked" || (latest?.baseRevision ?? 0) >= (intent.baseRevision ?? 0)
            let current = useLatest ? (latest?.position ?? intent.position) : intent.position
            let upper = max(0, cap ?? Int.max)
            next.position = current >= upper ? current : current + 1
            next.writesPosition = true
            next.priorPosition = current
            next.baseRevision = latest?.state == "acked" && useLatest ? latest?.baseRevision : intent.baseRevision
            return try self.enqueueSync(next)
        }
    }

    public func latest(accountId: String, medium: String, mediaId: Int, lifecycleId: UUID? = nil) async throws -> ProgressIntent? {
        try await run { try self.latestSync(accountId: accountId, medium: medium, mediaId: mediaId, lifecycleId: lifecycleId) }
    }

    public func active(accountId: String) async throws -> [ProgressIntent] {
        try await run {
            try self.queryIntents("""
                select \(self.intentColumns) from intents
                where account_id = '\(self.sql(accountId))' and state in ('pending', 'in_flight')
                order by local_sequence
                """)
        }
    }

    /// Atomically claims at most one mutation per entry, in FIFO order. Retry bodies are
    /// immutable after their first claim, including when the response is lost.
    public func claim(accountId: String, limit: Int = 50, mutationIds: [UUID]? = nil) async throws -> [ProgressIntent] {
        try await run {
            try self.transaction {
                try self.exec("update intents set state = 'pending', claimed_at = null where account_id = '\(self.sql(accountId))' and state = 'in_flight' and claimed_at < \(Date().timeIntervalSince1970 - 120)")
                let rows = try self.pendingSync(accountId: accountId, limit: limit).filter { row in mutationIds?.contains(row.mutationId) ?? true }
                try self.markSync(rows.map(\.mutationId), state: "in_flight")
                return rows
            }
        }
    }

    public func release(_ ids: [UUID]) async throws {
        try await run { try self.markSync(ids, state: "pending", requiredState: "in_flight") }
    }

    /// Commits the receipt and rebases only never-attempted successors. Later edits remain
    /// durable and visible; an earlier receipt cannot clear their projection.
    public func acknowledge(_ id: UUID, revision: Int64, position: Int) async throws {
        try await run {
            try self.transaction {
                guard let item = try self.queryIntents("select \(self.intentColumns) from intents where mutation_id = '\(id.uuidString)'").first else { return }
                try self.exec("update intents set state = 'acked', base_revision = \(revision), position = \(position), claimed_at = null where mutation_id = '\(id.uuidString)'")
                try self.exec("""
                    update intents set base_revision = \(revision)
                    where account_id = '\(self.sql(item.accountId))' and medium = '\(self.sql(item.medium))'
                      and media_id = \(item.mediaId) and ifnull(lifecycle_id, '') = '\(item.lifecycleId?.uuidString ?? "")'
                      and local_sequence > \(item.localSequence) and state = 'pending' and attempted = 0
                    """)
                // Retain the latest confirmed projection per entry; prune older receipts after
                // 14 days. Unsynced/conflict intents are never evicted by this policy.
                try self.exec("""
                    delete from intents as old where state = 'acked' and created_at < \(Date().timeIntervalSince1970 - 14 * 86400)
                      and exists (select 1 from intents newer where newer.account_id = old.account_id
                        and newer.medium = old.medium and newer.media_id = old.media_id
                        and newer.lifecycle_id = old.lifecycle_id and newer.state = 'acked'
                        and newer.local_sequence > old.local_sequence)
                    """)
            }
        }
    }

    public func pending(accountId: String, limit: Int) async throws -> [ProgressIntent] {
        try await run {
            try self.transaction {
                try self.exec("update intents set state = 'pending', claimed_at = null where account_id = '\(self.sql(accountId))' and state = 'in_flight' and claimed_at < \(Date().timeIntervalSince1970 - 120)")
                return try self.pendingSync(accountId: accountId, limit: limit)
            }
        }
    }

    /// A prior Library edit may advance the row while this intent waits for admission.
    /// Only a never-sent body can adopt that revision; retries preserve their original hash.
    public func rebaseUnsent(accountId: String, medium: String, mediaId: Int, lifecycleId: UUID, revision: Int64) async throws {
        try await run {
            try self.exec("""
                update intents set base_revision = max(coalesce(base_revision,0),\(revision))
                where account_id = '\(self.sql(accountId))' and medium = '\(self.sql(medium))'
                  and media_id = \(mediaId) and lifecycle_id = '\(lifecycleId.uuidString)'
                  and state = 'pending' and attempted = 0
                """)
        }
    }

    public func markInFlight(_ ids: [UUID]) async throws {
        try await run { try self.markSync(ids, state: "in_flight") }
    }

    public func markResolved(_ id: UUID, state: String) async throws {
        try await run { try self.markSync([id], state: state) }
    }

    public func recordConflict(_ id: UUID, revision: Int64, position: Int) async throws {
        try await run {
            try self.exec("update intents set state = 'conflict', conflict_revision = \(revision), conflict_position = \(position), claimed_at = null where mutation_id = '\(id.uuidString)' and state = 'in_flight'")
        }
    }

    public func conflicts(accountId: String, afterSequence: Int64 = 0) async throws -> [ProgressIntent] {
        try await run { try self.queryIntents("select \(self.intentColumns) from intents where account_id = '\(self.sql(accountId))' and state = 'conflict' and local_sequence > \(afterSequence) order by local_sequence limit 50") }
    }

    public func confirmations(accountId: String) async throws -> [ProgressIntent] {
        try await run {
            try self.queryIntents("""
                select \(self.intentColumns) from intents as current
                where account_id = '\(self.sql(accountId))' and state = 'acked'
                  and not exists (select 1 from intents different where different.account_id=current.account_id
                    and different.medium=current.medium and different.media_id=current.media_id
                    and different.lifecycle_id != current.lifecycle_id and different.state='acked'
                    and different.local_sequence>current.local_sequence)
                  and not exists (select 1 from intents newer where newer.account_id = current.account_id
                    and newer.medium = current.medium and newer.media_id = current.media_id
                    and newer.lifecycle_id = current.lifecycle_id and newer.state = 'acked'
                    and newer.local_sequence > current.local_sequence)
                """)
        }
    }

    /// Removes one unsent intent and returns the position to restore.
    public func cancelPending(accountId: String, medium: String, mediaId: Int, lifecycleId: UUID? = nil) async throws -> Int? {
        try await run { try self.cancelSync(accountId: accountId, medium: medium, mediaId: mediaId, lifecycleId: lifecycleId) }
    }

    /// Compare the newest durable body and insert its compensation in ONE transaction.
    /// A newer attempted, conflicted or pending edit makes an older ACK ineligible for Undo.
    public func compensateAcknowledged(_ ack: ProgressIntent) async throws -> ProgressIntent {
        try await run {
            try self.transaction {
                let latest = try self.queryIntents("select \(self.intentColumns) from intents where account_id='\(self.sql(ack.accountId))' and medium='\(self.sql(ack.medium))' and media_id=\(ack.mediaId) and lifecycle_id='\(ack.lifecycleId?.uuidString ?? "")' order by local_sequence desc limit 1").first
                guard latest?.mutationId == ack.mutationId, latest?.state == "acked", let prior = ack.priorPosition else {
                    throw ProgressOutboxError.storage("latest save is already on its way")
                }
                return try self.enqueueSync(ProgressIntent(accountId: ack.accountId,medium: ack.medium,
                    mediaId: ack.mediaId,lifecycleId: ack.lifecycleId,baseRevision: ack.baseRevision,
                    position: prior,priorPosition: ack.position), ownsTransaction: false)
            }
        }
    }

    /// A conflict suspends this entry's FIFO until an explicit, durable decision. Superseded
    /// bodies remain immutable; reapply is a NEW mutation based on the reported server revision.
    public func resolveConflict(accountId: String, medium: String, mediaId: Int, lifecycleId: UUID,
                                serverRevision: Int64, serverPosition: Int, reapply: Bool,
                                expectedMutationId: UUID? = nil, expectedDecision: ProgressIntent? = nil) async throws -> ProgressIntent {
        try await run {
            try self.transaction {
                let scope = "account_id = '\(self.sql(accountId))' and medium = '\(self.sql(medium))' and media_id = \(mediaId) and lifecycle_id = '\(lifecycleId.uuidString)'"
                let latest = try self.queryIntents("select \(self.intentColumns) from intents where \(scope) and state in ('pending','conflict') order by local_sequence desc limit 1").first
                if let expectedMutationId {
                    let conflict = try self.queryIntents("select \(self.intentColumns) from intents where \(scope) and state = 'conflict' and mutation_id = '\(expectedMutationId.uuidString)'").first
                    guard conflict?.conflictRevision == serverRevision, conflict?.conflictPosition == serverPosition,
                          expectedDecision == latest else { throw ProgressOutboxError.storage("conflict decision is no longer current") }
                }
                guard try self.queryInt("select count(*) from intents where \(scope) and state = 'in_flight'") == 0 else {
                    throw ProgressOutboxError.storage("entry is still being sent")
                }
                let chosen = reapply ? (latest?.position ?? serverPosition) : serverPosition
                try self.exec("update intents set state = 'superseded', claimed_at = null where \(scope) and state in ('pending','conflict')")
                self.nextSequence += 1
                let result = ProgressIntent(accountId: accountId, medium: medium, mediaId: mediaId,
                    lifecycleId: lifecycleId, unitId: reapply ? latest?.unitId : nil,
                    baseRevision: serverRevision, position: chosen, writesPosition: reapply ? (latest?.writesPosition ?? true) : true, positionLabel: reapply ? latest?.positionLabel : nil,
                    status: reapply ? latest?.status : nil, priorPosition: serverPosition,
                    localSequence: self.nextSequence, state: reapply ? "pending" : "acked")
                try self.exec("""
                    insert into intents (mutation_id,account_id,medium,media_id,lifecycle_id,unit_id,base_revision,
                      position,position_label,status,prior_position,local_sequence,state,created_at,attempted,writes_position)
                    values ('\(result.mutationId.uuidString)','\(self.sql(accountId))','\(self.sql(medium))',\(mediaId),
                      '\(lifecycleId.uuidString)',\(self.sqlOptional(result.unitId?.uuidString)),\(serverRevision),\(chosen),
                      \(self.sqlOptional(result.positionLabel)),\(self.sqlOptional(result.status)),\(serverPosition),
                      \(self.nextSequence),'\(result.state)',\(Date().timeIntervalSince1970),0,\(result.writesPosition ? 1 : 0))
                    """)
                return result
            }
        }
    }

    public func count(accountId: String) async throws -> Int {
        try await run {
            try self.queryInt("select count(*) from intents where account_id = '\(self.sql(accountId))'") ?? 0
        }
    }

    /// Used only after confirmed remote account deletion. The caller supplies the captured
    /// account identity, independent of whichever account is now bound to the UI.
    public func removeAccount(accountId: String) async throws {
        try await run {
            try self.transaction {
                try self.exec("delete from intents where lower(account_id) = '\(self.sql(accountId.lowercased()))'")
            }
            // Secure-delete clears the cells; truncating WAL removes prior page versions.
            guard sqlite3_wal_checkpoint_v2(self.database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil) == SQLITE_OK else {
                throw ProgressOutboxError.storage("account data removed; WAL cleanup could not complete")
            }
        }
    }

    // MARK: Queue

    private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try body()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func enqueueSync(_ intent: ProgressIntent, ownsTransaction: Bool = true) throws -> ProgressIntent {
        if ownsTransaction { try exec("begin immediate") }
        defer { if ownsTransaction && sqlite3_get_autocommit(database) == 0 { try? exec("rollback") } }
        let lifecycle = intent.lifecycleId?.uuidString ?? ""
        let existing = try queryRow("""
            select mutation_id, prior_position, local_sequence, base_revision, status, position, unit_id, position_label, writes_position
            from intents
            where account_id = '\(sql(intent.accountId))'
              and medium = '\(sql(intent.medium))'
              and media_id = \(intent.mediaId)
              and ifnull(lifecycle_id, '') = '\(sql(lifecycle))'
              and state = 'pending' and attempted = 0
            order by local_sequence desc limit 1
            """)
        if let existing {
            let position = intent.writesPosition ? intent.position : existing.position
            let unit = intent.writesPosition ? intent.unitId : existing.unitId
            let label = intent.writesPosition ? intent.positionLabel : existing.positionLabel
            let writesPosition = intent.writesPosition || existing.writesPosition
            try exec("""
                update intents
                   set position = \(position),
                       writes_position = \(writesPosition ? 1 : 0),
                       unit_id = \(sqlOptional(unit?.uuidString)),
                       position_label = \(sqlOptional(label)),
                       status = \(sqlOptional(intent.status ?? existing.status))
                 where mutation_id = '\(sql(existing.mutationId))'
                """)
            if ownsTransaction { try exec("commit") }
            var updated = intent
            updated.mutationId = UUID(uuidString: existing.mutationId) ?? intent.mutationId
            updated.priorPosition = existing.prior
            updated.localSequence = existing.sequence
            updated.baseRevision = existing.base
            updated.status = intent.status ?? existing.status
            updated.position = position
            updated.unitId = unit
            updated.positionLabel = label
            updated.writesPosition = writesPosition
            updated.state = "pending"
            return updated
        }
        var intent = intent
        if !intent.writesPosition,
           let latest = try latestSync(accountId: intent.accountId, medium: intent.medium, mediaId: intent.mediaId, lifecycleId: intent.lifecycleId),
           latest.state != "acked" || (latest.baseRevision ?? 0) >= (intent.baseRevision ?? 0) {
            intent.position = latest.position
            intent.unitId = latest.unitId
            intent.positionLabel = latest.positionLabel
        }
        nextSequence += 1
        let id = intent.mutationId.uuidString
        try exec("""
            insert into intents (
              mutation_id, account_id, medium, media_id, lifecycle_id, unit_id, base_revision,
              position, position_label, status, prior_position, local_sequence, state, created_at, writes_position
            ) values (
              '\(sql(id))', '\(sql(intent.accountId))', '\(sql(intent.medium))', \(intent.mediaId),
              \(sqlOptional(intent.lifecycleId?.uuidString)), \(sqlOptional(intent.unitId?.uuidString)),
              \(intent.baseRevision.map(String.init) ?? "null"),
              \(intent.position), \(sqlOptional(intent.positionLabel)), \(sqlOptional(intent.status)),
              \(intent.priorPosition.map(String.init) ?? "null"),
              \(nextSequence), 'pending', \(Date().timeIntervalSince1970), \(intent.writesPosition ? 1 : 0)
            )
            """)
        if ownsTransaction { try exec("commit") }
        var stored = intent
        stored.localSequence = nextSequence
        stored.state = "pending"
        return stored
    }

    private func pendingSync(accountId: String, limit: Int) throws -> [ProgressIntent] {
        let capped = min(50, max(1, limit))
        return try queryIntents("""
            select \(intentColumns)
            from intents
            where account_id = '\(sql(accountId))' and state = 'pending'
              and not exists (select 1 from intents older
                where older.account_id = intents.account_id and older.medium = intents.medium
                  and older.media_id = intents.media_id and ifnull(older.lifecycle_id, '') = ifnull(intents.lifecycle_id, '')
                  and older.local_sequence < intents.local_sequence and older.state in ('pending', 'in_flight', 'conflict'))
            order by local_sequence
            limit \(capped)
            """)
    }

    private func markSync(_ ids: [UUID], state: String, requiredState: String? = nil) throws {
        guard !ids.isEmpty else { return }
        let list = ids.map { "'\(sql($0.uuidString))'" }.joined(separator: ",")
        let claim = state == "in_flight" ? ", attempted = 1, claimed_at = \(Date().timeIntervalSince1970)" : ", claimed_at = null"
        try exec("update intents set state = '\(sql(state))'\(claim) where mutation_id in (\(list))\(requiredState.map { " and state = '\(self.sql($0))'" } ?? "")")
    }

    private func cancelSync(accountId: String, medium: String, mediaId: Int, lifecycleId: UUID?) throws -> Int? {
        try exec("begin immediate")
        defer { if sqlite3_get_autocommit(database) == 0 { try? exec("rollback") } }
        let lifecycle = lifecycleId.map { " and lifecycle_id = '\($0.uuidString)'" } ?? ""
        let prior = try queryInt("""
            select prior_position from intents
            where account_id = '\(sql(accountId))' and medium = '\(sql(medium))'
              and media_id = \(mediaId)\(lifecycle) and state = 'pending' and attempted = 0
            order by local_sequence limit 1
            """)
        try exec("""
            delete from intents
            where account_id = '\(sql(accountId))' and medium = '\(sql(medium))'
              and media_id = \(mediaId)\(lifecycle) and state = 'pending' and attempted = 0
            """)
        try exec("commit")
        return prior
    }

    private var intentColumns: String {
        "mutation_id, account_id, medium, media_id, lifecycle_id, unit_id, base_revision, position, position_label, status, prior_position, local_sequence, state, conflict_revision, conflict_position, writes_position"
    }

    private func latestSync(accountId: String, medium: String, mediaId: Int, lifecycleId: UUID?) throws -> ProgressIntent? {
        let lifecycle = lifecycleId.map { " and lifecycle_id = '\($0.uuidString)'" } ?? ""
        return try queryIntents("""
            select \(intentColumns) from intents
            where account_id = '\(sql(accountId))' and medium = '\(sql(medium))' and media_id = \(mediaId)\(lifecycle)
              and state in ('pending', 'in_flight', 'acked')
            order by local_sequence desc limit 1
            """).first
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("begin immediate")
        defer { if sqlite3_get_autocommit(database) == 0 { try? exec("rollback") } }
        let result = try body()
        try exec("commit")
        return result
    }

    // MARK: SQL

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "sqlite exec"
            sqlite3_free(error)
            throw ProgressOutboxError.storage(message)
        }
    }

    private func step(_ statement: OpaquePointer?) throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else {
            throw ProgressOutboxError.storage(String(cString: sqlite3_errmsg(database)))
        }
        return result
    }

    private func queryString(_ sql: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ProgressOutboxError.storage("prepare")
        }
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { return nil }
        guard let c = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: c)
    }

    private func queryInt(_ sql: String) throws -> Int? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ProgressOutboxError.storage("prepare")
        }
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private struct Existing {
        var mutationId: String
        var prior: Int?
        var sequence: Int64
        var base: Int64?
        var status: String?
        var position: Int
        var unitId: UUID?
        var positionLabel: String?
        var writesPosition: Bool
    }

    private func queryRow(_ sql: String) throws -> Existing? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ProgressOutboxError.storage("prepare")
        }
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { return nil }
        let id = String(cString: sqlite3_column_text(statement, 0))
        let prior: Int? = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 1))
        let sequence = sqlite3_column_int64(statement, 2)
        let base: Int64? = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 3)
        let status = sqlite3_column_text(statement, 4).map { String(cString: $0) }
        let position = Int(sqlite3_column_int64(statement, 5))
        let unit = sqlite3_column_text(statement, 6).flatMap { UUID(uuidString: String(cString: $0)) }
        let label = sqlite3_column_text(statement, 7).map { String(cString: $0) }
        let writesPosition = sqlite3_column_int(statement, 8) != 0
        return Existing(mutationId: id, prior: prior, sequence: sequence, base: base, status: status,
            position: position, unitId: unit, positionLabel: label, writesPosition: writesPosition)
    }

    private func queryIntents(_ sql: String) throws -> [ProgressIntent] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ProgressOutboxError.storage("prepare")
        }
        defer { sqlite3_finalize(statement) }
        var rows: [ProgressIntent] = []
        while try step(statement) == SQLITE_ROW {
            func text(_ index: Int32) -> String? {
                guard sqlite3_column_type(statement, index) != SQLITE_NULL, let c = sqlite3_column_text(statement, index) else { return nil }
                return String(cString: c)
            }
            func int64(_ index: Int32) -> Int64? {
                sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
            }
            guard let mutationId = text(0).flatMap(UUID.init(uuidString:)),
                  text(4) == nil || text(4).flatMap(UUID.init(uuidString:)) != nil,
                  text(5) == nil || text(5).flatMap(UUID.init(uuidString:)) != nil else {
                throw ProgressOutboxError.storage("invalid persisted mutation identity")
            }
            var intent = ProgressIntent(
                mutationId: mutationId,
                accountId: text(1) ?? "",
                medium: text(2) ?? "",
                mediaId: Int(int64(3) ?? 0),
                lifecycleId: text(4).flatMap(UUID.init(uuidString:)),
                unitId: text(5).flatMap(UUID.init(uuidString:)),
                baseRevision: int64(6),
                position: Int(int64(7) ?? 0),
                writesPosition: int64(15) != 0,
                positionLabel: text(8),
                status: text(9),
                priorPosition: int64(10).map(Int.init),
                localSequence: int64(11) ?? 0,
                state: text(12) ?? "pending"
            )
            intent.conflictRevision = int64(13)
            intent.conflictPosition = int64(14).map(Int.init)
            rows.append(intent)
        }
        return rows
    }

    private func sql(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func sqlOptional(_ value: String?) -> String {
        guard let value else { return "null" }
        return "'\(sql(value))'"
    }
}
