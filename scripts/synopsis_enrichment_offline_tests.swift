import Foundation

struct SynopsisProviderError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

final class ScriptedSynopsisProvider: SynopsisProvider {
    let acceptedTitle: String
    let acceptedText: String

    init(acceptedTitle: String, acceptedText: String) {
        self.acceptedTitle = acceptedTitle
        self.acceptedText = acceptedText
    }

    func generate(title: String, source: String, config: SynopsisQualityConfig) async throws -> String {
        if title == acceptedTitle {
            return acceptedText
        }
        throw SynopsisProviderError(message: "provider_unavailable")
    }

    func polish(title: String, source: String, draft: String, config: SynopsisQualityConfig) async throws -> String {
        draft
    }
}

final class FakeSynopsisStore: SynopsisStore {
    let rows: [Candidate]
    var enhanced: [(mediaId: Int, text: String)] = []
    var checkpoints: [(mediaId: Int, reason: String)] = []
    private var backlogReads = 0

    init(rows: [Candidate]) {
        self.rows = rows
    }

    func backlogCount(mediaType: String) async throws -> Int {
        backlogReads += 1
        return backlogReads == 1 ? rows.count : 0
    }

    func candidates(mediaType: String, limit: Int) async throws -> [Candidate] {
        Array(rows.prefix(limit))
    }

    func markFailed(mediaType: String, mediaId: Int, reason: String) async throws {
        checkpoints.append((mediaId, reason))
    }

    func writeEnhanced(mediaType: String, mediaId: Int, text: String) async throws {
        enhanced.append((mediaId, text))
    }
}

@main
struct SynopsisEnrichmentOfflineTests {
    static func main() async {
        do {
            let checks = try await runOffline()
            fputs("synopsis_enrichment_offline_tests passed \(checks) checks\n", stderr)
        } catch {
            fputs("synopsis_enrichment_offline_tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func runOffline() async throws -> Int {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            if !condition {
                throw SynopsisProviderError(message: message)
            }
            checks += 1
        }

        let quality = SynopsisQualityConfig(
            minChars: 80,
            maxChars: 420,
            minSentences: 3,
            maxSentences: 4,
            minSourceChars: 110
        )
        let source = "In a harbor city split by rival docks, a night courier carries sealed ledgers between warehouses. The work is paid in favors, and one missing book pulls old partners back onto the route. Rain and radio static follow every crossing, while the next tide will not wait."
        let existing = "Keep this existing synopsis. It already reads cleanly for the catalog. Do not replace it with a generated variant."
        let generated = "A night courier carries sealed ledgers across a harbor city split by rival docks. The missing book pulls old partners back onto the route. Rain and radio static follow each crossing."
        let success = Candidate(
            media_type: "ANIME",
            media_id: 101,
            title: "Harbor Ledger",
            source_description: source,
            source_description_normalized: nil,
            synopsis_enhanced: nil
        )
        let failure = Candidate(
            media_type: "ANIME",
            media_id: 202,
            title: "Broken Signal",
            source_description: source,
            source_description_normalized: nil,
            synopsis_enhanced: existing
        )
        let store = FakeSynopsisStore(rows: [success, failure])
        let provider = ScriptedSynopsisProvider(acceptedTitle: success.title, acceptedText: generated)
        let reportsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("synopsis-enrichment-offline-\(UUID().uuidString)", isDirectory: true)

        let metrics = try await runSynopsisEnrichment(
            mediaTypes: ["ANIME"],
            batchSize: 25,
            quality: quality,
            provider: provider,
            store: store,
            reportsRoot: reportsRoot
        )

        try expect(metrics.processed == 2, "processed \(metrics.processed)")
        try expect(metrics.generated == 1, "generated \(metrics.generated)")
        try expect(metrics.failed == 1, "failed \(metrics.failed)")
        try expect(store.enhanced.count == 1, "writes \(store.enhanced.count)")
        try expect(store.enhanced.first?.mediaId == 101, "success id")
        let written = store.enhanced.first?.text ?? ""
        try expect(!written.isEmpty, "empty variant")
        try expect(written != existing, "wrote the previous synopsis")
        try expect(written != source, "wrote the raw source")
        try expect(
            passesQualityGates(candidate: success, generated: written, sourceText: source, config: quality),
            "success text failed quality gates: \(written)"
        )
        try expect(store.enhanced.allSatisfy { $0.mediaId != 202 }, "destructive write for provider failure")
        try expect(store.checkpoints.count == 1, "checkpoints \(store.checkpoints.count)")
        try expect(store.checkpoints.first?.mediaId == 202, "checkpoint id")
        try expect(store.checkpoints.first?.reason.contains("provider_unavailable") == true, "checkpoint reason \(store.checkpoints.first?.reason ?? "")")

        let statusURL = reportsRoot.appendingPathComponent("latest-status.json")
        let status = try JSONDecoder().decode(RunMetrics.self, from: Data(contentsOf: statusURL))
        try expect(status.processed == 2 && status.generated == 1 && status.failed == 1, "report counts")
        let samples = try String(contentsOf: reportsRoot.appendingPathComponent("generated-samples-latest.md"), encoding: .utf8)
        try expect(samples.contains("Harbor Ledger"), "sample report missing success")
        try expect(!samples.contains("Broken Signal"), "sample report included the failed title")
        try expect(!samples.contains(existing), "sample report included the preserved synopsis")

        return checks
    }
}
