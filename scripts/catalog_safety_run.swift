import Foundation

struct BacklogCountRow: Decodable {
    let backlog_count: Int
}

struct OpenGapRow: Decodable {
    let media_type: String
    let media_id: Int
    let title: String
    let decision_state: String
    let model_label: String?
    let model_confidence: Double?
    let rule_hits: [String]?
    let reason_codes: [String]?
    let suggested_lexicon: [String]?
    let last_scanned_at: String?
}

struct RunMetrics: Codable {
    var started_at: String
    var finished_at: String
    var processed: Int
    var blocked: Int
    var safe: Int
    var uncertain: Int
    var failed: Int
    var blocked_by_rules: Int
    var blocked_by_model: Int
    var safe_fallback_no_signal: Int
    var model_used: Int
    var model_unavailable: Int
    var avg_latency_ms: Int
    var backlog_due_before: Int
    var backlog_due_after: Int
    var open_gaps_count: Int
    var open_gaps_fetch_failed: Int
}

protocol CatalogSafetyStore {
    func backlogCount(mediaType: String) async throws -> Int
    func candidates(mediaType: String, limit: Int) async throws -> [SafetyCandidate]
    func safetyTerms() async throws -> [SafetyTerm]
    func writeDecision(_ payload: [String: Any]) async throws
    func markFailed(mediaType: String, mediaId: Int, reason: String) async throws
    func openGaps(limit: Int) async throws -> [OpenGapRow]
}

extension JSONEncoder {
    static var workerEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func compactReason(_ error: Error) -> String {
    let text = String(describing: error)
    return String(text.prefix(180))
}

func runCatalogSafety<Store: CatalogSafetyStore>(
    mediaTypes: [String],
    batchSize: Int,
    openGapLimit: Int,
    minBlockedConfidence: Double,
    minSafeConfidence: Double,
    safeFallbackMaxRuleScore: Int,
    classify: (SafetyCandidate) async -> CatalogSafetyModelResult,
    store: Store,
    reportsRoot: URL
) async throws -> RunMetrics {
    try FileManager.default.createDirectory(at: reportsRoot, withIntermediateDirectories: true)

    let startedDate = Date()
    let terms = try await store.safetyTerms()

    var metrics = RunMetrics(
        started_at: isoNow(),
        finished_at: isoNow(),
        processed: 0,
        blocked: 0,
        safe: 0,
        uncertain: 0,
        failed: 0,
        blocked_by_rules: 0,
        blocked_by_model: 0,
        safe_fallback_no_signal: 0,
        model_used: 0,
        model_unavailable: 0,
        avg_latency_ms: 0,
        backlog_due_before: 0,
        backlog_due_after: 0,
        open_gaps_count: 0,
        open_gaps_fetch_failed: 0
    )

    var latencySamples: [Int] = []

    for mediaType in mediaTypes {
        metrics.backlog_due_before += try await store.backlogCount(mediaType: mediaType)
    }

    for mediaType in mediaTypes {
        let candidates = try await store.candidates(mediaType: mediaType, limit: batchSize)

        for candidate in candidates {
            metrics.processed += 1
            let started = Date()
            do {
                let evaluatedRules = evaluateRules(candidate: candidate, terms: terms)
                let resolved = await decideSafety(
                    candidate: candidate,
                    terms: terms,
                    minBlockedConfidence: minBlockedConfidence,
                    minSafeConfidence: minSafeConfidence,
                    safeFallbackMaxRuleScore: safeFallbackMaxRuleScore,
                    classify: classify
                )

                let decision = resolved.decision
                if resolved.modelUsed { metrics.model_used += 1 }
                if !resolved.modelAvailable { metrics.model_unavailable += 1 }

                if decision.state == "blocked" {
                    metrics.blocked += 1
                    if decision.reasonCodes.contains("rules_high_confidence") {
                        metrics.blocked_by_rules += 1
                    } else if decision.reasonCodes.contains("model_blocked") {
                        metrics.blocked_by_model += 1
                    } else if evaluatedRules.score >= 250 {
                        metrics.blocked_by_rules += 1
                    }
                } else if decision.state == "safe" {
                    metrics.safe += 1
                    if decision.reasonCodes.contains("fallback_safe_no_signal") {
                        metrics.safe_fallback_no_signal += 1
                    }
                } else {
                    metrics.uncertain += 1
                }

                var payload: [String: Any] = [
                    "p_media_type": candidate.media_type,
                    "p_media_id": candidate.media_id,
                    "p_decision_state": decision.state,
                    "p_blocked": decision.blocked,
                    "p_rule_hits": decision.ruleHits,
                    "p_reason_codes": decision.reasonCodes,
                    "p_suggested_lexicon": decision.suggestedLexicon
                ]
                if let modelLabel = decision.modelLabel, !modelLabel.isEmpty {
                    payload["p_model_label"] = modelLabel
                }
                if let modelConfidence = decision.modelConfidence {
                    payload["p_model_confidence"] = modelConfidence
                }
                if let modelRationale = decision.modelRationale, !modelRationale.isEmpty {
                    payload["p_model_rationale"] = modelRationale
                }
                if let sourceHash = candidate.source_hash, !sourceHash.isEmpty {
                    payload["p_source_hash"] = sourceHash
                }

                try await store.writeDecision(payload)
            } catch {
                metrics.failed += 1
                try? await store.markFailed(
                    mediaType: candidate.media_type,
                    mediaId: candidate.media_id,
                    reason: compactReason(error)
                )
            }
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            latencySamples.append(elapsedMs)
        }
    }

    for mediaType in mediaTypes {
        metrics.backlog_due_after += try await store.backlogCount(mediaType: mediaType)
    }

    var openGaps: [OpenGapRow] = []
    do {
        openGaps = try await store.openGaps(limit: openGapLimit)
    } catch {
        metrics.open_gaps_fetch_failed += 1
        appendWorkerLog(
            reportsRoot: reportsRoot,
            message: "open gaps fetch failed: \(compactReason(error))"
        )
    }

    metrics.open_gaps_count = openGaps.count
    metrics.finished_at = isoNow()
    if !latencySamples.isEmpty {
        metrics.avg_latency_ms = latencySamples.reduce(0, +) / latencySamples.count
    }

    let statusData = try JSONEncoder.workerEncoder.encode(metrics)
    try statusData.write(to: reportsRoot.appendingPathComponent("latest-status.json"), options: .atomic)

    let runName = ISO8601DateFormatter().string(from: startedDate).replacingOccurrences(of: ":", with: "-")
    let runLogURL = reportsRoot.appendingPathComponent("run-\(runName).log")
    let summary = "processed=\(metrics.processed) blocked=\(metrics.blocked) safe=\(metrics.safe) uncertain=\(metrics.uncertain) failed=\(metrics.failed) blocked_by_rules=\(metrics.blocked_by_rules) blocked_by_model=\(metrics.blocked_by_model) safe_fallback_no_signal=\(metrics.safe_fallback_no_signal) model_used=\(metrics.model_used) model_unavailable=\(metrics.model_unavailable) avg_latency_ms=\(metrics.avg_latency_ms) backlog_due_before=\(metrics.backlog_due_before) backlog_due_after=\(metrics.backlog_due_after) open_gaps_count=\(metrics.open_gaps_count) open_gaps_fetch_failed=\(metrics.open_gaps_fetch_failed)"
    try summary.appending("\n").write(to: runLogURL, atomically: true, encoding: .utf8)

    let latestUncertainURL = reportsRoot.appendingPathComponent("uncertain-latest.md")
    let runUncertainURL = reportsRoot.appendingPathComponent("uncertain-\(runName).md")
    if metrics.open_gaps_fetch_failed == 0 {
        let uncertainMarkdown = buildUncertainMarkdown(generatedAt: metrics.finished_at, rows: openGaps)
        try uncertainMarkdown.write(
            to: latestUncertainURL,
            atomically: true,
            encoding: .utf8
        )
        try uncertainMarkdown.write(
            to: runUncertainURL,
            atomically: true,
            encoding: .utf8
        )
    } else if let previousReport = try? String(contentsOf: latestUncertainURL, encoding: .utf8), !previousReport.isEmpty {
        try previousReport.write(
            to: runUncertainURL,
            atomically: true,
            encoding: .utf8
        )
    } else {
        let fallbackReport = """
        # Catalog Safety Open Gaps

        - Generated at: \(metrics.finished_at)
        - Decision state: uncertain
        - Count: unavailable
        - Note: get_catalog_safety_open_gaps failed in this run; no prior report available.
        """
        try fallbackReport.write(
            to: runUncertainURL,
            atomically: true,
            encoding: .utf8
        )
    }

    if let statusText = String(data: statusData, encoding: .utf8) {
        print(statusText)
    }

    return metrics
}

func buildUncertainMarkdown(generatedAt: String, rows: [OpenGapRow]) -> String {
    var lines: [String] = []
    lines.append("# Catalog Safety Open Gaps")
    lines.append("")
    lines.append("- Generated at: \(generatedAt)")
    lines.append("- Decision state: uncertain")
    lines.append("- Count: \(rows.count)")
    lines.append("")
    lines.append("| Media | ID | Title | Model | Confidence | Rule hits | Reason | Suggested lexicon | Last scanned |")
    lines.append("| --- | ---: | --- | --- | ---: | --- | --- | --- | --- |")

    for row in rows {
        let title = row.title.replacingOccurrences(of: "|", with: "\\|")
        let model = (row.model_label ?? "-").replacingOccurrences(of: "|", with: "\\|")
        let confidence = row.model_confidence.map { String(format: "%.3f", $0) } ?? "-"
        let hits = (row.rule_hits ?? []).joined(separator: ", ").replacingOccurrences(of: "|", with: "\\|")
        let reason = (row.reason_codes ?? []).joined(separator: ", ").replacingOccurrences(of: "|", with: "\\|")
        let suggested = (row.suggested_lexicon ?? []).joined(separator: ", ").replacingOccurrences(of: "|", with: "\\|")
        let scanned = row.last_scanned_at ?? "-"
        lines.append("| \(row.media_type) | \(row.media_id) | \(title) | \(model) | \(confidence) | \(hits.isEmpty ? "-" : hits) | \(reason.isEmpty ? "-" : reason) | \(suggested.isEmpty ? "-" : suggested) | \(scanned) |")
    }

    lines.append("")
    lines.append("## Suggested Lexicon Additions")
    let suggestionCounts = rows
        .flatMap { $0.suggested_lexicon ?? [] }
        .map { $0.lowercased() }
        .reduce(into: [String: Int]()) { result, value in
            result[value, default: 0] += 1
        }
    let topSuggestions = suggestionCounts.sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key < rhs.key
    }

    if topSuggestions.isEmpty {
        lines.append("- None from current open gaps.")
    } else {
        for (term, count) in topSuggestions.prefix(20) {
            lines.append("- \(term) (\(count))")
        }
    }
    lines.append("")
    return lines.joined(separator: "\n")
}

func appendWorkerLog(reportsRoot: URL, message: String) {
    let logURL = reportsRoot.appendingPathComponent("worker.log")
    let line = "[\(isoNow())] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }

    if FileManager.default.fileExists(atPath: logURL.path),
       let handle = try? FileHandle(forWritingTo: logURL) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
        return
    }

    try? data.write(to: logURL, options: .atomic)
}
