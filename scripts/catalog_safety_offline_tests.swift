import Foundation

struct CatalogSafetyTestError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

final class FakeCatalogSafetyStore: CatalogSafetyStore {
    var rows: [SafetyCandidate]
    var terms: [SafetyTerm]
    var gaps: [OpenGapRow]
    var failWritesFor: Set<Int>
    var decisions: [(mediaId: Int, state: String, blocked: Bool)] = []
    var failures: [(mediaId: Int, reason: String)] = []

    init(rows: [SafetyCandidate], terms: [SafetyTerm], gaps: [OpenGapRow] = [], failWritesFor: Set<Int> = []) {
        self.rows = rows
        self.terms = terms
        self.gaps = gaps
        self.failWritesFor = failWritesFor
    }

    func backlogCount(mediaType: String) async throws -> Int { rows.count }

    func candidates(mediaType: String, limit: Int) async throws -> [SafetyCandidate] {
        Array(rows.prefix(limit))
    }

    func safetyTerms() async throws -> [SafetyTerm] { terms }

    func writeDecision(_ payload: [String: Any]) async throws {
        let mediaId = payload["p_media_id"] as? Int ?? -1
        if failWritesFor.contains(mediaId) {
            throw CatalogSafetyTestError(message: "upsert_failed")
        }
        decisions.append((
            mediaId,
            payload["p_decision_state"] as? String ?? "",
            payload["p_blocked"] as? Bool ?? false
        ))
    }

    func markFailed(mediaType: String, mediaId: Int, reason: String) async throws {
        failures.append((mediaId, reason))
    }

    func openGaps(limit: Int) async throws -> [OpenGapRow] {
        Array(gaps.prefix(limit))
    }
}

@main
struct CatalogSafetyOfflineTests {
    static func main() async {
        do {
            let checks = try await runOffline()
            fputs("catalog_safety_offline_tests passed \(checks) checks\n", stderr)
        } catch {
            fputs("catalog_safety_offline_tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func runOffline() async throws -> Int {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            if !condition { throw CatalogSafetyTestError(message: message) }
            checks += 1
        }

        let blockedTerm = SafetyTerm(term: "hentai", language: "en", match_type: "contains", weight: 300, category: "porn_core")
        let weakTerm = SafetyTerm(term: "beach", language: "en", match_type: "contains", weight: 50, category: "suggestive")
        let blocked = SafetyCandidate(
            media_type: "ANIME",
            media_id: 11,
            title: "Hentai Example",
            title_english: nil,
            title_romaji: nil,
            title_native: nil,
            source_description: "An explicit feature.",
            source_description_normalized: nil,
            genres: ["Hentai"],
            source_hash: "abc"
        )
        let uncertain = SafetyCandidate(
            media_type: "ANIME",
            media_id: 22,
            title: "Beach Days",
            title_english: nil,
            title_romaji: nil,
            title_native: nil,
            source_description: "Friends spend a summer at the beach.",
            source_description_normalized: nil,
            genres: ["Slice of Life"],
            source_hash: "def"
        )
        let successStore = FakeCatalogSafetyStore(
            rows: [blocked, uncertain],
            terms: [blockedTerm, weakTerm],
            gaps: [
                OpenGapRow(
                    media_type: "ANIME",
                    media_id: 22,
                    title: "Beach Days",
                    decision_state: "uncertain",
                    model_label: "uncertain",
                    model_confidence: 0.4,
                    rule_hits: ["suggestive:beach"],
                    reason_codes: ["model_uncertain"],
                    suggested_lexicon: [],
                    last_scanned_at: nil
                )
            ]
        )
        let reportsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-safety-offline-\(UUID().uuidString)", isDirectory: true)

        let success = try await runCatalogSafety(
            mediaTypes: ["ANIME"],
            batchSize: 50,
            openGapLimit: 20,
            minBlockedConfidence: 0.78,
            minSafeConfidence: 0.70,
            safeFallbackMaxRuleScore: 40,
            classify: { candidate in
                CatalogSafetyModelResult(
                    label: "uncertain",
                    confidence: 0.4,
                    rationale: "ambiguous",
                    suggestedTerms: [],
                    available: true
                )
            },
            store: successStore,
            reportsRoot: reportsRoot
        )

        try expect(success.processed == 2, "processed \(success.processed)")
        try expect(success.blocked == 1, "blocked \(success.blocked)")
        try expect(success.uncertain == 1, "uncertain \(success.uncertain)")
        try expect(success.safe == 0, "safe \(success.safe)")
        try expect(success.failed == 0, "failed \(success.failed)")
        try expect(success.blocked_by_rules == 1, "blocked_by_rules \(success.blocked_by_rules)")
        try expect(successStore.failures.isEmpty, "success path recorded a failure")
        try expect(successStore.decisions.count == 2, "decisions \(successStore.decisions.count)")
        try expect(successStore.decisions.contains { $0.mediaId == 11 && $0.state == "blocked" && $0.blocked }, "blocked decision")
        try expect(successStore.decisions.contains { $0.mediaId == 22 && $0.state == "uncertain" && !$0.blocked }, "uncertain decision")
        let uncertainReport = try String(contentsOf: reportsRoot.appendingPathComponent("uncertain-latest.md"), encoding: .utf8)
        try expect(uncertainReport.contains("Beach Days"), "uncertain report")
        try expect(uncertainReport.contains("uncertain"), "uncertain state in report")
        try expect(!reportsRoot.path.contains("synopsis-enrichment"), "catalog report path collided with synopsis")

        let writeFailure = SafetyCandidate(
            media_type: "MANGA",
            media_id: 33,
            title: "Quiet Library",
            title_english: nil,
            title_romaji: nil,
            title_native: nil,
            source_description: "A student catalogs old books.",
            source_description_normalized: nil,
            genres: ["Drama"],
            source_hash: nil
        )
        let failureStore = FakeCatalogSafetyStore(
            rows: [writeFailure],
            terms: [],
            failWritesFor: [33]
        )
        let failureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-safety-offline-fail-\(UUID().uuidString)", isDirectory: true)
        let failed = try await runCatalogSafety(
            mediaTypes: ["MANGA"],
            batchSize: 50,
            openGapLimit: 20,
            minBlockedConfidence: 0.78,
            minSafeConfidence: 0.70,
            safeFallbackMaxRuleScore: 40,
            classify: { _ in
                CatalogSafetyModelResult(
                    label: "uncertain",
                    confidence: 0.2,
                    rationale: "model_error",
                    suggestedTerms: [],
                    available: true
                )
            },
            store: failureStore,
            reportsRoot: failureRoot
        )
        try expect(failed.failed == 1, "failure metric \(failed.failed)")
        try expect(failureStore.decisions.isEmpty, "failed write was stored as a decision")
        try expect(failureStore.failures.count == 1, "failure checkpoints \(failureStore.failures.count)")
        try expect(failureStore.failures.first?.mediaId == 33, "failure checkpoint id")
        try expect(failureStore.failures.first?.reason.contains("upsert_failed") == true, "failure reason")
        try expect(!failureStore.decisions.contains { $0.state == "safe" || $0.state == "blocked" }, "invented a confident decision")

        return checks
    }
}
