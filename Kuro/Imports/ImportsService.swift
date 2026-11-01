import Foundation
import AuthenticationServices
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Imports
// Owner of structured import preparation/review/application/recovery and the retained Concierge
// parse/Apply/Undo helpers. Provider references never become Kuro catalog IDs.
//
// Structured v2 preparation freezes protected source pages and stages review without Library
// writes. Explicit approval uses immutable SQL receipts. Finalization publishes authoritative
// Library/Home/Collection/Releases once; failed publication retains saved counts and recovery.
// Bounded Undo holds the Library's affected-key reservation and keeps its own action/cursor.
//
// Legacy writes: apply and Undo are SERVER-SIDE list writers (edge `concierge-apply` / `concierge-undo`);
// nothing here writes a list row locally. After a successful call of the still-current account they
// call the single Library hook (`LibraryRefreshHook.listsChangedServerSide`: tracking copies dropped,
// fresh Library re-read). A failed call (thrown error) refreshes nothing. A result or failure that
// arrives after the account ended ends in `CancellationError` and refreshes nothing (the next
// account's own session refresh already reads its lists).
//
// Account scope: a parse response carries the caller's list rows (`existing_entry`, which gates
// auto-apply), so the parse cache and its in-flight loads are keyed by user id, cleared on every
// account transition (`AccountScopedState`) and dropped whenever the tracking state changes
// (`dropTrackingCopies`). A completion of an account that is no longer current is never cached or
// handed out: it ends in `CancellationError` (success and failure alike). The export text is built
// from the current account's library and is not handed out once that account ended.
//
// Tracking revision (F06): a parse response is a snapshot of the account's tracking at the time it was
// requested. `trackingRevision` moves on with every tracking change (`dropTrackingCopies`: an applied
// Library change, a server-side list write). A parse answered under an older revision is superseded:
// it is neither cached nor handed out, and the parse is requested again once (a rebase on the current
// state; a second supersession ends in `CancellationError`). In-flight parses are keyed by revision, so
// a call after a change never joins a load from before it. Precedence: a parse snapshot handed out by
// this owner is never older than the latest tracking change it knows of, so `ImportReconciler`'s rule
// (the snapshot's `existing_entry` first, then the Library's entry) reads current data either way.
//
// Credentials (F33): every edge call (parse, apply, Undo, AniList preview/import) runs as a credential
// lease of the account that asked: never dispatched (or retried) once that account ended and never with
// another account's token (`AccountSessionCoordinator.withCredentialLease`).

@MainActor
@Observable
final class ImportsService: AccountScopedState, MemoryPressureTrimmable {
    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every call fails with `MissingSupabaseConfiguration`.
    let client: SupabaseClient?
    /// The shared account coordinator (every completion is checked against it).
    let accountSession: AccountSessionCoordinator
    /// Read-only: the export text lists the account's tracked titles.
    @ObservationIgnored let library: LibraryStore
    /// Read-only: the legacy anime pages are the export text's last-resort title fallback.
    @ObservationIgnored private let catalog: CatalogStore
    /// The single Library hook after a server-side list write, and the view-path refresh.
    @ObservationIgnored let libraryHook: LibraryRefreshHook
    @ObservationIgnored let importJournal: LibraryImportPageJournal?
    @ObservationIgnored var streamToken: UUID?
    @ObservationIgnored let malAccount: MALNativeAccountConnector
    @ObservationIgnored var workflowToken: UUID?
    @ObservationIgnored var workflowAccount: AccountContext?
    private var workflowActiveImport: ImportOutcome?
    private var workflowBusy = false
    private var workflowError: ImportFailure?
    private var workflowPending: [ImportManifest] = []
    private var workflowMALIdentity: String?
    private var workflowUndoReverted = 0
    private var workflowUndoSkipped = 0
    var activeImport: ImportOutcome? {
        get { accountSession.isCurrent(workflowAccount) ? workflowActiveImport : nil }
        set { workflowActiveImport = newValue }
    }
    var importBusy: Bool {
        get { accountSession.isCurrent(workflowAccount) && workflowBusy }
        set { workflowBusy = newValue }
    }
    var importError: ImportFailure? {
        get { accountSession.isCurrent(workflowAccount) ? workflowError : nil }
        set { workflowError = newValue }
    }
    var pendingImports: [ImportManifest] {
        get { accountSession.isCurrent(workflowAccount) ? workflowPending : [] }
        set { workflowPending = newValue }
    }
    var malAccountIdentity: String? {
        get { accountSession.isCurrent(workflowAccount) ? workflowMALIdentity : nil }
        set { workflowMALIdentity = newValue }
    }
    var importUndoReverted: Int {
        get { accountSession.isCurrent(workflowAccount) ? workflowUndoReverted : 0 }
        set { workflowUndoReverted = newValue }
    }
    var importUndoSkipped: Int {
        get { accountSession.isCurrent(workflowAccount) ? workflowUndoSkipped : 0 }
        set { workflowUndoSkipped = newValue }
    }

    init(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        library: LibraryStore,
        catalog: CatalogStore,
        libraryHook: LibraryRefreshHook,
        malRegistration: MALNativeRegistration? = nil,
        importJournal: LibraryImportPageJournal? = nil,
        malCredentials: any MALCredentialStore = KeychainMALCredentialStore()
    ) {
        self.client = client
        self.accountSession = accountSession
        self.library = library
        self.catalog = catalog
        self.libraryHook = libraryHook
        self.importJournal = importJournal ?? Self.makeImportJournal()
        self.malAccount = MALNativeAccountConnector(registration: malRegistration, accounts: accountSession,
                                                    credentials: malCredentials)
    }

    // MARK: State

    /// Per-user parse responses, keyed "concierge_parse|<user>|<scope>|<limit>|<text>|<clarification>".
    var conciergeParseCache: [String: TimedCache<ConciergeParseResponse>] = [:]
    /// In-flight parses: joined only by the same key, tracking revision and account context.
    @ObservationIgnored let conciergeParseLoads = AccountScopedLoads<String, ConciergeParseResponse>()
    /// The account's tracking revision (F06): moves on with every tracking change.
    @ObservationIgnored private(set) var trackingRevision = 0

    // MARK: AccountScopedState

    func cancelAccountWork() {
        conciergeParseLoads.cancelAll()
        workflowToken = nil; workflowAccount = nil; importBusy = false
        activeImport = nil; importError = nil; pendingImports = []; malAccountIdentity = nil
        importUndoReverted = 0; importUndoSkipped = 0
        streamToken = nil
        malAccount.cancelAccountWork()
    }

    func clearPrivateState() {
        conciergeParseCache.removeAll()
        malAccount.clearPrivateState()
    }

    /// The registered account connector remains unavailable until provider qualification is recorded.
    var malAccountAvailable: Bool { malAccount.isAvailable }

    func connectMALAccount(presentationAnchor: ASPresentationAnchor) async throws {
        try await malAccount.connect(presentationAnchor: presentationAnchor)
        _ = try await refreshMALAccountIdentity()
    }

    func disconnectMALAccount() throws { try malAccount.disconnect(); malAccountIdentity = nil }

    func removeMALCredentials(forDeletedAccount accountId: String) throws {
        try malAccount.removeCredentials(forDeletedAccount: accountId)
    }

    func removeDeletedAccountData(userId: String) async throws {
        var cleanupError: Error?
        do { try malAccount.removeCredentials(forDeletedAccount: userId) }
        catch { cleanupError = error }
        do {
            guard let importJournal else {
                throw NSError(domain: "KuroImport", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Import journal cleanup could not be verified on this device."])
            }
            var cleaned = false
            for _ in 0..<80 {
                try Task.checkCancellation()
                do {
                    try await importJournal.removeDeletedAccountData(accountId: userId)
                    cleaned = true; break
                } catch LibraryImportPageJournal.Failure.cleanupLimit { await Task.yield() }
            }
            if !cleaned { throw LibraryImportPageJournal.Failure.cleanupLimit }
        } catch { if cleanupError == nil { cleanupError = error } }
        if let accountId = UUID(uuidString: userId)?.uuidString.lowercased() {
            let prefixes = ["kuro.import.action.\(accountId).", "kuro.import.stream.\(accountId)."]
            for key in UserDefaults.standard.dictionaryRepresentation().keys
                where prefixes.contains(where: { key.lowercased().hasPrefix($0) }) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        if let cleanupError { throw cleanupError }
    }

    /// Sheds the parse cache under memory pressure.
    func trimCachesForMemoryPressure() {
        conciergeParseCache.removeAll()
    }

    // MARK: Tracking copies

    /// The parse cache's `existing_entry` copies tracking state and gates auto-apply: it must not
    /// outlive a tracking change (called by the Library hook and the Concierge change sink). Parses in
    /// flight become superseded (F06).
    func dropTrackingCopies() {
        trackingRevision += 1
        conciergeParseCache.removeAll()
    }

    /// Concierge change sink: any applied change of the current account drops the parse cache.
    func libraryDidChange(_ change: LibraryChange) {
        guard accountSession.isCurrent(change.account) else { return }
        dropTrackingCopies()
    }

    // MARK: - Parse

    func conciergeParse(text: String, scope: ConciergeScope = .both, limitPerItem: Int = 10, clarification: [String: String]? = nil) async throws -> ConciergeParseResponse {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lim = max(3, min(15, limitPerItem))
        let context = accountSession.current
        let user = context?.userId ?? "anon"
        let clarifyKey = clarification.map { $0.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "&") } ?? ""
        let key = "concierge_parse|\(user)|\(scope.rawValue)|\(lim)|\(normalized)|\(clarifyKey)"

        let now = Date()
        // Very short TTL: just enough to make back-to-back retries feel instant.
        if let cached = conciergeParseCache[key], now.timeIntervalSince(cached.storedAt) < 600 {
            return cached.value
        }

        // Keep the request in a shared load so callers can share in-flight work (same account and
        // tracking revision only). The edge call (and its transport retries) runs as a credential lease.
        let client = self.client
        let accountSession = self.accountSession
        var payload: [String: Any] = [
            "text": text,
            "scope": scope.rawValue,
            "limitPerItem": lim,
        ]
        if let clarification {
            payload["clarification"] = clarification
        }
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            throw ConciergeFunctionErrors.translateConciergeFunctionError(error)
        }
        let work: @MainActor () async throws -> ConciergeParseResponse = {
            guard let client else { throw MissingSupabaseConfiguration() }
            let options = FunctionInvokeOptions(method: .post, body: body)
            return try await accountSession.withCredentialLease(for: context) {
                try await withRetry { [client] in
                    try await client.functions.invoke("concierge-parse", options: options)
                }
            }
        }
        // One rebase: a snapshot superseded by a tracking change while in flight is requested again.
        for _ in 0..<2 {
            let revision = trackingRevision
            let resp: ConciergeParseResponse
            do {
                resp = try await conciergeParseLoads.run(
                    key: "\(key)|r\(revision)", context: context, priority: .userInitiated, work: work
                )
            } catch {
                // A failure of an account that is no longer current is not reported to the next one.
                guard accountSession.isCurrent(context) else { throw CancellationError() }
                throw ConciergeFunctionErrors.translateConciergeFunctionError(error)
            }
            // Holds the caller's existing list entries: never publish it into another account.
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            // F06: a snapshot from before a tracking change neither fills the cache nor drives a preview.
            guard revision == trackingRevision else { continue }
            conciergeParseCache[key] = TimedCache(value: resp, storedAt: now)
            trimTimedCache(&conciergeParseCache, maxEntries: 50)
            return resp
        }
        throw CancellationError()
    }

    // MARK: - Apply / Undo (server-side list writers)

    /// `idempotencyKey` is one identity per user action (reused when that action is retried). A missing
    /// or invalid key is replaced so the request still has one; callers that retry must pass the same key.
    func conciergeApply(items: [[String: Any]], idempotencyKey: String? = nil) async throws -> ConciergeApplyResponse {
        let context = accountSession.current
        let key = idempotencyKey.flatMap { ImportApplyIdentity.isValid($0) ? $0 : nil }
            ?? UUID().uuidString.lowercased()
        do {
            let data = try JSONSerialization.data(withJSONObject: ["items": items, "idempotencyKey": key], options: [])
            let client = self.client
            let response: ConciergeApplyResponse = try await accountSession.withCredentialLease(for: context) {
                guard let client else { throw MissingSupabaseConfiguration() }
                return try await client.functions.invoke("concierge-apply", options: FunctionInvokeOptions(method: .post, body: data))
            }
            // A result of an account that is no longer current is neither handed out nor refreshed for.
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            // The edge function wrote the lists server-side: fresh Library read, stale copies dropped.
            if let context { libraryHook.listsChangedServerSide(for: context) }
            return response
        } catch {
            // A failure of an account that is no longer current is not reported to the next one.
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            throw ConciergeFunctionErrors.translateConciergeFunctionError(error)
        }
    }

    /// Durable Home import. Counts are added, updated, conflict, and unmatched. No percentage.
    /// A later source that omits a title does not delete it: the job only merges.
    func applyStructuredLibraryImport(
        provider: String,
        sourceKind: String,
        mediumFilter: String,
        drafts: [LibraryImportDraft],
        exhausted: Bool,
        streamIdentity: String? = nil
    ) async throws -> LibraryImportCounts {
        let context = accountSession.current
        let prepared = LibraryImportBatch.prepare(drafts)
        let hash = streamIdentity ?? LibraryImportBatch.payloadHash(prepared, provider: provider, sourceKind: sourceKind, mediumFilter: mediumFilter)
        // An action identity survives retry; a later deliberate import of the same file is new.
        guard let context else { throw CancellationError() }
        let resumeKey = "kuro.import.action.\(context.userId.lowercased()).\(hash)"
        guard let importJournal else {
            throw NSError(domain: "KuroImport", code: 3, userInfo: [NSLocalizedDescriptionKey: "Import cannot be safely saved on this device."])
        }
        // UserDefaults is a legacy migration source, not the durable identity authority.
        // Persist before dispatch so a process death cannot strand a committed active job.
        let idempotency = try await importJournal.beginAction(key: resumeKey,
            legacyActionId: UserDefaults.standard.string(forKey: resumeKey))
        guard accountSession.isCurrent(context) else { throw CancellationError() }
        do {
            let client = self.client
            let final: LibraryImportFinal = try await accountSession.withCredentialLease(for: context) {
                guard let client else { throw MissingSupabaseConfiguration() }
                let started: LibraryImportStart = try await client
                    .rpc("start_library_import_v1", params: LibraryImportStartParams(
                        p_provider: provider,
                        p_source_kind: sourceKind,
                        p_medium_filter: mediumFilter,
                        p_idempotency_key: idempotency,
                        p_payload_hash: hash
                    ))
                    .execute()
                    .value
                if started.state == "ready" || started.state == "ready_with_issues" {
                    let final: LibraryImportFinal = try await client.rpc("import_job_status_v1", params: LibraryImportStatusParams(p_job_id: started.jobId)).execute().value
                    return final
                }
                for chunk in LibraryImportBatch.chunks(prepared) {
                    let _: LibraryImportChunkResult = try await client
                        .rpc("apply_import_chunk_v1", params: LibraryImportChunkParams(
                            p_job_id: started.jobId,
                            p_items: chunk.map(LibraryImportItemPayload.init)
                        ))
                        .execute()
                        .value
                    guard self.accountSession.isCurrent(context) else { throw CancellationError() }
                    await self.libraryHook.listsChangedServerSide(for: context)?.value
                }
                let final: LibraryImportFinal = try await client
                    .rpc("finish_library_import_v1", params: LibraryImportFinishParams(
                        p_job_id: started.jobId,
                        p_exhausted: exhausted
                    ))
                    .execute().value
                return final
            }
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            await libraryHook.listsChangedServerSide(for: context)?.value
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            if exhausted { try await libraryHook.prepareImportHome(revisions:final.homeRevisions,for:context) }
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            if exhausted && streamIdentity == nil {
                try await importJournal.completeAction(key: resumeKey, actionId: idempotency)
                UserDefaults.standard.removeObject(forKey: resumeKey)
            }
            return final.counters
        } catch {
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            throw error
        }
    }

    /// Provider pages and item receipts resume under one action. No 400-title terminal cap.
    /// The checkpoint advances only after the entire source page commits locally/server-side.
    func importCompleteAniList(_ selection: ConciergeAniListImportResponse) async throws -> LibraryImportCounts {
        guard let context=accountSession.current,let client,let username=selection.username else { throw CancellationError() }
        guard streamToken == nil else { throw NSError(domain:"KuroImport",code:4,userInfo:[NSLocalizedDescriptionKey:"An import is already running."]) }
        let token=UUID(); streamToken=token
        defer { if streamToken == token { streamToken=nil } }
        let types=selection.types ?? ["ANIME","MANGA"]
        let statuses=selection.statuses ?? ["CURRENT","COMPLETED","PLANNING"]
        let selectionKey="anilist.stream.v1|\(username.lowercased())|\(types.joined(separator:","))|\(statuses.joined(separator:","))"
        let fingerprint=LibraryImportBatch.payloadHash([],provider:"anilist",sourceKind:selectionKey)
        let checkpoint="kuro.import.stream.\(context.userId.lowercased()).\(fingerprint)"
        guard let importJournal else { throw NSError(domain:"KuroImport",code:3,userInfo:[NSLocalizedDescriptionKey:"Import cannot be safely saved on this device."]) }
        var saved=try await importJournal.read(key:checkpoint)
        // Migrate an older cursor-only checkpoint; page receipts remain server-side.
        if saved.cursor == nil && saved.page == nil,let cursor=UserDefaults.standard.string(forKey:checkpoint) {
            saved=LibraryImportPageJournal.Checkpoint(cursor:cursor)
            try await importJournal.write(saved,key:checkpoint)
            UserDefaults.standard.removeObject(forKey:checkpoint)
        }
        while true {
            try Task.checkCancellation()
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            let page:LibraryImportPageJournal.Page
            if let persisted=saved.page { page=persisted }
            else {
                var body:[String:Any] = ["mode":"import","stream":true,"username":username,"types":types,"statuses":statuses,"maxItems":200,"perPage":50]
                if let cursor=saved.cursor { body["cursor"]=cursor }
                let data=try JSONSerialization.data(withJSONObject:body)
                let fetched:ConciergeAniListImportResponse = try await accountSession.withCredentialLease(for:context) {
                    try await client.functions.invoke("concierge-import-anilist",options:FunctionInvokeOptions(method:.post,body:data))
                }
                guard accountSession.isCurrent(context) else { throw CancellationError() }
                guard fetched.success,let items=fetched.libraryItems,let exhausted=fetched.sourceExhausted,
                      exhausted || (fetched.nextCursor != nil && fetched.nextCursor != saved.cursor) else {
                    throw NSError(domain:"KuroImport",code:1,userInfo:[NSLocalizedDescriptionKey:fetched.error ?? "Provider paging unavailable. The import is saved for retry."])
                }
                page=LibraryImportPageJournal.Page(drafts:items.map{$0.draft()},nextCursor:fetched.nextCursor,exhausted:exhausted)
                saved=LibraryImportPageJournal.Checkpoint(cursor:saved.cursor,page:page)
                try await importJournal.write(saved,key:checkpoint)
            }
            let counts=try await applyStructuredLibraryImport(provider:"anilist",sourceKind:"account",mediumFilter:types.count==2 ? "both" : (types.first=="MANGA" ? "manga" : "anime"),
                drafts:page.drafts,exhausted:page.exhausted,streamIdentity:fingerprint)
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            if page.exhausted {
                try await importJournal.remove(key:checkpoint)
                let actionKey = "kuro.import.action.\(context.userId.lowercased()).\(fingerprint)"
                try await importJournal.remove(key: actionKey)
                UserDefaults.standard.removeObject(forKey: actionKey)
                return counts
            }
            saved=LibraryImportPageJournal.Checkpoint(cursor:page.nextCursor)
            try await importJournal.write(saved,key:checkpoint)
        }
    }

    private static func makeImportJournal() -> LibraryImportPageJournal? {
        do {
            // The unit-test host gets one throwaway journal per service, so a deletion marker or
            // checkpoint written by one test graph can never leak into another (or into the app's
            // real Application Support on the same simulator).
            #if DEBUG
            if FixtureHost.isTestHost() {
                let scratch = FileManager.default.temporaryDirectory
                    .appendingPathComponent("kuro-test-import-pages-\(UUID().uuidString)", isDirectory: true)
                return try LibraryImportPageJournal(directory: scratch)
            }
            #endif
            let base=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
            return try LibraryImportPageJournal(directory:base.appendingPathComponent("Kuro/import-pages",isDirectory:true))
        } catch { return nil }
    }

    func conciergeUndo(sessionId: String) async throws -> ConciergeUndoResponse {
        let context = accountSession.current
        do {
            let data = try JSONSerialization.data(withJSONObject: ["sessionId": sessionId], options: [])
            let client = self.client
            let response: ConciergeUndoResponse = try await accountSession.withCredentialLease(for: context) {
                guard let client else { throw MissingSupabaseConfiguration() }
                return try await client.functions.invoke("concierge-undo", options: FunctionInvokeOptions(method: .post, body: data))
            }
            // A result of an account that is no longer current is neither handed out nor refreshed for.
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            // The edge function restored the lists server-side: fresh Library read, stale copies dropped.
            if let context { libraryHook.listsChangedServerSide(for: context) }
            return response
        } catch {
            // A failure of an account that is no longer current is not reported to the next one.
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            throw ConciergeFunctionErrors.translateConciergeFunctionError(error)
        }
    }

    // MARK: - AniList import

    func conciergePreviewAniListImport(
        username: String,
        types: [String] = ["ANIME", "MANGA"],
        statuses: [String] = ["CURRENT", "COMPLETED", "PLANNING"],
        maxItems: Int = 200
    ) async throws -> ConciergeAniListPreviewResponse {
        try await invokeAniListImport(
            mode: "preview",
            username: username,
            types: types,
            statuses: statuses,
            maxItems: maxItems,
            cachedText: nil
        ) { client, options in
            try await client.functions.invoke("concierge-import-anilist", options: options)
        }
    }

    func conciergeImportAniList(
        username: String,
        types: [String] = ["ANIME", "MANGA"],
        statuses: [String] = ["CURRENT", "COMPLETED", "PLANNING"],
        maxItems: Int = 200,
        cachedText: String? = nil
    ) async throws -> ConciergeAniListImportResponse {
        try await invokeAniListImport(
            mode: "import",
            username: username,
            types: types,
            statuses: statuses,
            maxItems: maxItems,
            cachedText: cachedText
        ) { client, options in
            try await client.functions.invoke("concierge-import-anilist", options: options)
        }
    }

    /// `invoke` decodes the concrete response type at its call site (the app's default actor isolation
    /// makes the models' `Decodable` conformances main-actor-isolated, so it cannot be generic here).
    private func invokeAniListImport<T: Sendable>(
        mode: String,
        username: String,
        types: [String],
        statuses: [String],
        maxItems: Int,
        cachedText: String?,
        invoke: @escaping @MainActor (SupabaseClient, FunctionInvokeOptions) async throws -> T
    ) async throws -> T {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else {
            throw NSError(
                domain: "Concierge",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Missing AniList username"]
            )
        }
        let cap = max(25, min(400, maxItems))
        let context = accountSession.current

        do {
            var payload: [String: Any] = [
                "mode": mode,
                "username": u,
                "types": types,
                "statuses": statuses,
                "maxItems": cap,
            ]
            if let cachedText, !cachedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["text"] = cachedText
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let client = self.client
            let response: T = try await accountSession.withCredentialLease(for: context) {
                guard let client else { throw MissingSupabaseConfiguration() }
                return try await invoke(client, FunctionInvokeOptions(method: .post, body: data))
            }
            // The import writes the account's lists server-side: its outcome is not handed to another
            // account (F04).
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            return response
        } catch {
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            throw ConciergeFunctionErrors.translateConciergeFunctionError(error)
        }
    }

    // MARK: - Library export

    /// Build plain-text concierge payload from the user's current library list.
    /// Useful for one-tap import from within the app. Titles are resolved per typed `MediaKey`, so an
    /// anime and a manga with the same numeric id each export their own title.
    func conciergeLibraryExportText(
        includeStatus: Set<ListStatus>? = nil,
        includeMediaTypes: Set<String> = ["anime", "manga"],
        maxItems: Int = 400
    ) async -> ConciergeLibraryExportResult? {
        let context = accountSession.current
        if userLists.isEmpty {
            await libraryHook.refreshLists()
        }

        let userLists = self.userLists
        guard !userLists.isEmpty else { return nil }

        let allowedStatuses = includeStatus.map(Set.init) ?? Set(ListStatus.allCases)
        let allowedTypes = Set(includeMediaTypes.map { $0.lowercased() })

        let filtered = userLists.filter {
            allowedTypes.contains($0.mediaType.lowercased()) && allowedStatuses.contains($0.status)
        }

        guard !filtered.isEmpty else { return nil }

        let capped = Array(filtered.prefix(max(0, maxItems)))
        guard !capped.isEmpty else { return nil }

        // 1) Resolve titles for this snapshot.
        let lookup = await resolveLibraryTitles(for: capped)
        // The text lists the account's library: never hand it out once that account ended.
        guard accountSession.isCurrent(context) else { return nil }

        // 2) Keep list in server order (updatedAt desc from the Library projection).
        let lines: [String] = capped.compactMap { entry in
            guard let key = Self.mediaKey(of: entry), let title = lookup[key] else { return nil }
            let suffix = conciergeLibrarySuffix(for: entry)
            return suffix.isEmpty ? title : "\(title) \(suffix)"
        }

        guard !lines.isEmpty else { return nil }
        return ConciergeLibraryExportResult(
            text: lines.joined(separator: "\n"),
            exportedItemCount: lines.count,
            truncated: filtered.count > capped.count
        )
    }

    /// Legacy display projection of the current account's library (built from the store on every read).
    private var userLists: [UserList] {
        let userId = accountSession.current?.userId ?? ""
        return library.allEntries.map { UserList(legacy: $0, userId: userId) }
    }

    /// Typed identity of a list row ("anime" / "manga", any case); nil for anything else.
    private static func mediaKey(of entry: UserList) -> MediaKey? {
        switch entry.mediaType.lowercased() {
        case "anime": return MediaKey(kind: .anime, id: entry.mediaId)
        case "manga": return MediaKey(kind: .manga, id: entry.mediaId)
        default: return nil
        }
    }

    private func conciergeLibrarySuffix(for entry: UserList) -> String {
        let isAnime = entry.mediaType.lowercased() == "anime"
        let progress = max(0, entry.progress)
        let exactLabel = entry.progressLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = exactLabel.flatMap { $0.isEmpty ? nil : $0 } ?? String(progress)
        switch entry.status {
        case .completed:
            return "(completed)"
        case .dropped:
            return "(dropped)"
        case .paused:
            return "(paused)"
        case .planning:
            return "(planning)"
        case .repeating:
            return isAnime ? "(rewatching)" : "(re-reading)"
        case .current:
            if progress > 0 || exactLabel?.isEmpty == false {
                return isAnime ? "(watching ep \(label))" : "(reading ch \(label))"
            }
            return isAnime ? "(watching)" : "(reading)"
        }
    }

    private func resolveLibraryTitles(for items: [UserList]) async -> [MediaKey: String] {
        let keys = items.compactMap { Self.mediaKey(of: $0) }
        let animeIds = Set(keys.filter { $0.kind == .anime }.map(\.id))
        let mangaIds = Set(keys.filter { $0.kind == .manga }.map(\.id))

        var titlesByKey: [MediaKey: String] = [:]

        for (kind, ids) in [(MediaKind.anime, animeIds), (MediaKind.manga, mangaIds)] {
            let table = kind.rawValue
            let idList = Array(ids).sorted()
            guard !idList.isEmpty else { continue }

            struct MediaTitleRow: Decodable {
                let id: Int
                let titleEnglish: String?
                let titleRomaji: String?
                let titleNative: String?

                enum CodingKeys: String, CodingKey {
                    case id
                    case titleEnglish = "title_english"
                    case titleRomaji = "title_romaji"
                    case titleNative = "title_native"
                }
            }

            for start in stride(from: 0, through: max(0, idList.count), by: 200) {
                let end = min(start + 200, idList.count)
                guard start < end else { continue }
                let chunk = Array(idList[start..<end])

                do {
                    guard let client else { throw MissingSupabaseConfiguration() }
                    let rows: [MediaTitleRow] = try await client
                        .from(table)
                        .select("id,title_english,title_romaji,title_native")
                        .in("id", values: chunk)
                        .execute()
                        .value

                    for row in rows {
                        let title = row.titleEnglish?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? row.titleRomaji?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? row.titleNative?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? ""
                        if !title.isEmpty {
                            titlesByKey[MediaKey(kind: kind, id: row.id)] = title
                        }
                    }
                } catch {
                    #if DEBUG
                    print("[ImportsService] Failed to resolve titles for \(table): \(error)")
                    #endif
                }

            }
        }

        // An id the bounded catalog read did not title is still exported, under an explicit label.
        // A missing row is not dropped, and a failed read is not reported as an empty library.
        for key in keys where titlesByKey[key] == nil {
            titlesByKey[key] = Self.unresolvedExportTitle(key)
        }

        return titlesByKey
    }

    private struct LibraryImportStartParams: Encodable {
        let p_provider: String
        let p_source_kind: String
        let p_medium_filter: String
        let p_idempotency_key: String
        let p_payload_hash: String
    }

    private struct LibraryImportStart: Decodable {
        let jobId: String
        let state: String
        enum CodingKeys: String, CodingKey { case jobId = "job_id", state }
    }

    private struct LibraryImportItemPayload: Encodable {
        let medium: String
        let external_id: String
        let status: String
        let progress: Int?
        let volumes_progress: Int?
        let score_raw: String?
        let score_scale: String
        let notes: String?
        let repeat_count: Int?
        let started_raw: String?
        let finished_raw: String?
        let `private`: Bool?
        let custom_lists: [String]?
        let hidden_from_status_lists: Bool?
        let source_list_options: String?
        let normalized_rating: Int?

        init(_ draft: LibraryImportDraft) {
            medium = draft.medium
            external_id = draft.externalId
            status = draft.status
            let unavailable = draft.unavailableFields
            progress = unavailable.contains("progress") ? nil : draft.progress
            volumes_progress = draft.volumesProgress
            score_raw = draft.scoreRaw
            score_scale = draft.scoreScale
            notes = draft.notes
            repeat_count = unavailable.contains("repeat_count") ? nil : draft.repeatCount
            started_raw = draft.startedRaw
            finished_raw = draft.finishedRaw
            self.private = unavailable.contains("private") ? nil : draft.isPrivate
            custom_lists = unavailable.contains("custom_lists") ? nil : draft.customLists
            hidden_from_status_lists = unavailable.contains("hidden_from_status_lists") ? nil : draft.hiddenFromStatusLists
            source_list_options = draft.sourceListOptions
            normalized_rating = draft.normalizedRating
        }
    }

    private struct LibraryImportChunkParams: Encodable {
        let p_job_id: String
        let p_items: [LibraryImportItemPayload]
    }

    private struct LibraryImportChunkResult: Decodable {
        let added: Int
        let updated: Int
        let conflict: Int
        let unmatched: Int
    }

    private struct LibraryImportStatusParams: Encodable { let p_job_id: String }
    private struct LibraryImportFinal: Decodable {
        let state: String
        let counters: LibraryImportCounts
        let homeRevisions: [String:Int64]
        enum CodingKeys:String,CodingKey { case state,counters; case homeRevisions="home_revisions" }
    }

    private struct LibraryImportFinishParams: Encodable {
        let p_job_id: String
        let p_exhausted: Bool
    }

    /// Title used when the catalog batch has no row for this id.
    private static func unresolvedExportTitle(_ key: MediaKey) -> String {
        switch key.kind {
        case .anime: return "Untitled anime #\(key.id)"
        case .manga: return "Untitled manga #\(key.id)"
        }
    }
}
#endif
