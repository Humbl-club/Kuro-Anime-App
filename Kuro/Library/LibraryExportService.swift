import Foundation
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)

// MARK: - Library export (W2)
// The account-scoped owner of "Export your list" (Profile, behind `library_export_v1`): it gathers what
// the pure exporter (`LibraryExport.build`, package KuroLibrary) needs, runs the build off the main
// actor, writes the files into a protected per-export folder and hands their URLs to the sheet.
//
// Rules this owner enforces (each is pinned by `LibraryExportFlowTests`):
// - The release flag is checked FIRST, before any request or provider call; off means no request and no file.
// - The export is refused until the Library holds the account's rows (`loadState == .loaded`): a half-loaded
//   projection would silently miss titles.
// - The catalogue identity read (AniList / MyAnimeList ids, titles) is public data, but its id set is the
//   account's library, so it runs inside `accountSession.withCredentialLease(for:)`: a request is never
//   dispatched with another account's credential. Only keys the per-account identity cache lacks are asked
//   for, and only while the device is online (decided before the first batch is sent). A key the lookup
//   did not return is "identity unavailable" in the summary, never "no MAL id".
// - The cache is written only after the lease returned and the account is still current, so a cancelled
//   lookup leaves nothing behind.
// - Files hold private notes: they live in `directory/<UUID>/` with complete file protection, are never
//   published for a run whose account changed, and are deleted on dismiss, on every account transition
//   and on account deletion.
// - A requested format that could not be built (`summary.failedFormats`) is a failed export: nothing is
//   published for that run.
// - The library read without the fenced columns (`series_foundation_v1` off) is reported as its own gap, so
//   the export never claims to be complete while tracking-unit identity is unknown.

/// Why an export did not produce files.
nonisolated enum LibraryExportFailure: Equatable, Sendable {
    /// `library_export_v1` is off for this person.
    case disabled
    /// The Library does not hold the account's rows yet (still loading, or its load failed).
    case notLoaded
    /// Nobody is signed in.
    case signedOut
    /// The files could not be written.
    case writeFailed
    /// A requested format could not be built (`LibraryExportSummary.failedFormats`).
    case buildFailed
}

/// Where the export stands.
nonisolated enum LibraryExportState: Equatable {
    case idle
    case preparing(LibraryExportFormat)
    case ready(LibraryExportResult)
    case failed(LibraryExportFailure)
}

/// A finished export: the files to share and what they do and do not contain. `files` can be empty (a MAL
/// export while no title has a MAL id); the summary then says why.
nonisolated struct LibraryExportResult: Equatable {
    let format: LibraryExportFormat
    let files: [URL]
    let summary: LibraryExportSummary
}

/// What composition (production wiring) and KuroTests (fixtures) can replace in the export owner without it
/// being a graph member. Every default is the production behaviour.
nonisolated struct LibraryExportSeams {
    /// Whether the device has a connection (production: the app's `NetworkMonitor`).
    var isOnline: @MainActor () -> Bool = { true }
    var directory: URL = LibraryExportService.defaultDirectory
    var now: @Sendable () -> Date = { Date() }
    var timeZone: @Sendable () -> TimeZone = { .current }
    /// The tags provider (W9 wires `LibraryTagsStore` here); `nil` = could not load.
    var tagsByKey: @MainActor () async -> [MediaKey: [String]]? = { [:] }
    /// The custom-lists provider (W9 wires `CustomListsStore.exportLists()` here); `nil` = could not load.
    var customLists: @MainActor () async -> [ExportCustomList]? = { [] }
    var write: @Sendable (Data, URL, Data.WritingOptions) throws -> Void = LibraryExportService.defaultWrite
    var build: @Sendable (LibraryExportInput, Set<LibraryExportFormat>, Date, TimeZone) -> LibraryExportBundle = LibraryExportService.defaultBuild
}

@MainActor
@Observable
final class LibraryExportService: AccountScopedState {
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private let accountSession: AccountSessionCoordinator
    @ObservationIgnored private let isEnabled: @MainActor () -> Bool
    @ObservationIgnored private let isOnline: @MainActor () -> Bool
    @ObservationIgnored private let isTrackingDetailLoaded: @MainActor () -> Bool
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let timeZone: @Sendable () -> TimeZone
    @ObservationIgnored private let tagsByKey: @MainActor () async -> [MediaKey: [String]]?
    @ObservationIgnored private let customLists: @MainActor () async -> [ExportCustomList]?
    @ObservationIgnored private let write: @Sendable (Data, URL, Data.WritingOptions) throws -> Void
    @ObservationIgnored private let build: @Sendable (LibraryExportInput, Set<LibraryExportFormat>, Date, TimeZone) -> LibraryExportBundle

    private(set) var state: LibraryExportState = .idle

    /// Identity rows of earlier lookups for the current account (offline exports); only uncached keys are
    /// requested. Cleared on every account transition.
    @ObservationIgnored private(set) var identityCache: [MediaKey: ExportCatalogueRow] = [:]

    /// The in-flight export. A newer export, a dismiss and every account transition cancel it.
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    /// Bumped whenever the current run stops owning `state`; a run whose token is stale publishes nothing.
    @ObservationIgnored private var generation = 0
    /// The folder of the run that owns `state` (deleted on discard).
    @ObservationIgnored private var currentFolder: URL?

    /// - Parameters:
    ///   - isEnabled: the release flag (production: `{ [weak flags] in flags?.libraryExportV1Enabled ?? false }`).
    ///   - isOnline: whether the device has a connection; offline, no lookup batch is sent and the cached
    ///     identities are used.
    ///   - isTrackingDetailLoaded: whether the Library was read with the fenced columns
    ///     (`series_foundation_v1`); `false` reports `trackingDetailUnavailable`.
    ///   - directory: where per-export folders are made (default: the temporary directory).
    ///   - tagsByKey / customLists: the organisation providers (W9). `nil` = could not load, which the
    ///     summary reports as `organisationUnavailable`; they are called after the flag check only.
    ///   - write: writes one file (default `Data.write(to:options:)`); a test observes the options.
    ///   - build: the pure exporter (default `LibraryExport.build`); a test makes a format fail.
    init(
        library: LibraryStore,
        catalog: CatalogStore,
        accountSession: AccountSessionCoordinator,
        isEnabled: @escaping @MainActor () -> Bool,
        isOnline: @escaping @MainActor () -> Bool = { true },
        isTrackingDetailLoaded: @escaping @MainActor () -> Bool = { true },
        directory: URL = LibraryExportService.defaultDirectory,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        tagsByKey: @escaping @MainActor () async -> [MediaKey: [String]]? = { [:] },
        customLists: @escaping @MainActor () async -> [ExportCustomList]? = { [] },
        write: @escaping @Sendable (Data, URL, Data.WritingOptions) throws -> Void = LibraryExportService.defaultWrite,
        build: @escaping @Sendable (LibraryExportInput, Set<LibraryExportFormat>, Date, TimeZone) -> LibraryExportBundle = LibraryExportService.defaultBuild
    ) {
        self.library = library
        self.catalog = catalog
        self.accountSession = accountSession
        self.isEnabled = isEnabled
        self.isOnline = isOnline
        self.isTrackingDetailLoaded = isTrackingDetailLoaded
        self.directory = directory
        self.now = now
        self.timeZone = timeZone
        self.tagsByKey = tagsByKey
        self.customLists = customLists
        self.write = write
        self.build = build
    }

    // MARK: Defaults

    /// Where per-export folders are made unless a test says otherwise.
    nonisolated static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kuro-export", isDirectory: true)
    }

    nonisolated static func defaultWrite(_ data: Data, _ url: URL, _ options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    nonisolated static func defaultBuild(
        _ input: LibraryExportInput, _ formats: Set<LibraryExportFormat>, _ exportedAt: Date, _ timeZone: TimeZone
    ) -> LibraryExportBundle {
        LibraryExport.build(input, formats: formats, exportedAt: exportedAt, timeZone: timeZone)
    }

    // MARK: Export

    /// Prepares `format`: checks the release flag first (off: `.failed(.disabled)`, nothing else happens),
    /// captures the account, refuses unless the Library is loaded, reads the organisation, looks up the
    /// uncached identities inside the account's credential lease, builds the files off the main actor and
    /// writes them with complete file protection into a fresh folder. Publishes `.ready` only if the account
    /// is still current; an account change (or a newer export, or a dismiss) publishes nothing and deletes
    /// what this run wrote.
    func export(_ format: LibraryExportFormat) async {
        supersedeCurrentRun()
        guard isEnabled() else {
            state = .failed(.disabled)
            return
        }
        guard let context = accountSession.current else {
            state = .failed(.signedOut)
            return
        }
        guard library.loadState == .loaded else {
            state = .failed(.notLoaded)
            return
        }
        let token = generation
        state = .preparing(format)
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.run(format, context: context, token: token)
        }
        exportTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Deletes the current export folder, stops a run in flight and returns to `.idle` (sheet dismiss).
    func discardFiles() {
        supersedeCurrentRun()
        state = .idle
    }

    // MARK: AccountScopedState

    func cancelAccountWork() {
        exportTask?.cancel()
        exportTask = nil
    }

    func clearPrivateState() {
        discardFiles()
        identityCache = [:]
        removeItem(directory)
    }

    func removeDeletedAccountData(userId: String) async throws {
        clearPrivateState()
    }

    func removeDataWithoutOwner() {
        clearPrivateState()
    }

    // MARK: Run

    private func run(_ format: LibraryExportFormat, context: AccountContext, token: Int) async {
        // The organisation first: the list items it names are part of the identity lookup.
        let tags = await tagsByKey()
        guard isLive(context, token) else { return abandon(token: token, folder: nil) }
        let lists = await customLists()
        guard isLive(context, token) else { return abandon(token: token, folder: nil) }
        let organisationUnavailable = tags == nil || lists == nil

        // The point-in-time snapshot this export describes.
        let entries = library.allEntries
        var keys = Set(entries.map(\.key))
        if !organisationUnavailable {
            for list in lists ?? [] { keys.formUnion(list.items) }
        }

        var catalogue = identityCache.filter { keys.contains($0.key) }
        let uncached = keys.subtracting(identityCache.keys)
        if !uncached.isEmpty, isOnline() {
            let found: [MediaKey: ExportCatalogueRow]
            do {
                found = try await accountSession.withCredentialLease(for: context) { [catalog] in
                    await catalog.exportIdentities(for: uncached)
                }
            } catch {
                // A cancelled lease (account transition, newer export, dismiss): publish nothing.
                return abandon(token: token, folder: nil)
            }
            // Cache only what a lookup that was neither cancelled nor overtaken by an account change read.
            guard isLive(context, token) else { return abandon(token: token, folder: nil) }
            identityCache.merge(found) { _, new in new }
            catalogue.merge(found) { _, new in new }
        }

        let input = LibraryExportInput(
            entries: entries,
            catalogue: catalogue,
            tagsByKey: tags ?? [:],
            customLists: lists ?? [],
            organisationUnavailable: organisationUnavailable,
            trackingDetailUnavailable: !isTrackingDetailLoaded()
        )
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        currentFolder = folder
        let outcome = await Self.buildAndWrite(
            input, format: format, exportedAt: now(), timeZone: timeZone(),
            folder: folder, directory: directory, build: build, write: write
        )

        guard isLive(context, token) else { return abandon(token: token, folder: folder) }
        switch outcome {
        case .written(let urls, let summary):
            if urls.isEmpty {
                removeItem(folder)
                currentFolder = nil
            }
            state = .ready(LibraryExportResult(format: format, files: urls, summary: summary))
            exportTask = nil
        case .buildFailed:
            removeItem(folder)
            currentFolder = nil
            state = .failed(.buildFailed)
            exportTask = nil
        case .writeFailed:
            removeItem(folder)
            currentFolder = nil
            state = .failed(.writeFailed)
            exportTask = nil
        }
    }

    private nonisolated enum Outcome: Sendable {
        case written([URL], LibraryExportSummary)
        case buildFailed
        case writeFailed
    }

    /// Builds and writes off the main actor. Replaces whatever an earlier export left in `directory`.
    private nonisolated static func buildAndWrite(
        _ input: LibraryExportInput,
        format: LibraryExportFormat,
        exportedAt: Date,
        timeZone: TimeZone,
        folder: URL,
        directory: URL,
        build: @escaping @Sendable (LibraryExportInput, Set<LibraryExportFormat>, Date, TimeZone) -> LibraryExportBundle,
        write: @escaping @Sendable (Data, URL, Data.WritingOptions) throws -> Void
    ) async -> Outcome {
        await Task.detached(priority: .userInitiated) {
            let bundle = build(input, [format], exportedAt, timeZone)
            // A format that could not be built is a failed export, not a partial one.
            guard bundle.summary.failedFormats.isEmpty else { return Outcome.buildFailed }
            do {
                let manager = FileManager.default
                if manager.fileExists(atPath: directory.path) {
                    try manager.removeItem(at: directory)
                }
                try manager.createDirectory(
                    at: folder, withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete]
                )
                var urls: [URL] = []
                for file in bundle.files {
                    let url = folder.appendingPathComponent(file.name, isDirectory: false)
                    try write(file.data, url, [.atomic, .completeFileProtection])
                    urls.append(url)
                }
                return Outcome.written(urls, bundle.summary)
            } catch {
                #if DEBUG
                print("[LibraryExportService] Writing the export failed: \(error)")
                #endif
                return Outcome.writeFailed
            }
        }.value
    }

    // MARK: Lifecycle helpers

    /// The run still describes the world: not cancelled, not overtaken, same account.
    private func isLive(_ context: AccountContext, _ token: Int) -> Bool {
        !Task.isCancelled && token == generation && accountSession.isCurrent(context)
    }

    /// Ends a run that publishes nothing: deletes the files it wrote and, if it still owns `state`, returns
    /// to `.idle`.
    private func abandon(token: Int, folder: URL?) {
        if let folder { removeItem(folder) }
        guard token == generation else { return }
        currentFolder = nil
        exportTask = nil
        state = .idle
    }

    /// Stops the current run (a newer export, a dismiss, a transition) and deletes its folder. After this
    /// the stopped run never touches `state` again.
    private func supersedeCurrentRun() {
        exportTask?.cancel()
        exportTask = nil
        generation += 1
        if let folder = currentFolder {
            removeItem(folder)
            currentFolder = nil
        }
    }

    private func removeItem(_ url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            #if DEBUG
            print("[LibraryExportService] Removing \(url.lastPathComponent) failed: \(error)")
            #endif
        }
    }
}

#endif
