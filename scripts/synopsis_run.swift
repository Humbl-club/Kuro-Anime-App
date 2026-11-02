import Foundation

struct RunMetrics: Codable {
    var started_at: String
    var finished_at: String
    var processed: Int
    var generated: Int
    var tone_polish_used: Int
    var fallback_used: Int
    var autodeduped_sentences: Int
    var rejected_quality: Int
    var insufficient_source: Int
    var failed: Int
    var avg_latency_ms: Int
    var backlog_due_before: Int
    var backlog_due_after: Int
    var backlog_remaining_estimate: Int
}

struct WeakSourceEntry {
    let mediaType: String
    let mediaId: Int
    let title: String
    let sourceChars: Int
    let reason: String
}

struct GeneratedSynopsisEntry {
    let mediaType: String
    let mediaId: Int
    let title: String
    let synopsis: String
}

protocol SynopsisProvider {
    func generate(title: String, source: String, config: SynopsisQualityConfig) async throws -> String
    func polish(title: String, source: String, draft: String, config: SynopsisQualityConfig) async throws -> String
}

protocol SynopsisStore {
    func backlogCount(mediaType: String) async throws -> Int
    func candidates(mediaType: String, limit: Int) async throws -> [Candidate]
    func markFailed(mediaType: String, mediaId: Int, reason: String) async throws
    func writeEnhanced(mediaType: String, mediaId: Int, text: String) async throws
}

extension JSONEncoder {
    static var enrichmentEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func runSynopsisEnrichment<Provider: SynopsisProvider, Store: SynopsisStore>(
    mediaTypes: [String],
    batchSize: Int,
    quality: SynopsisQualityConfig,
    provider: Provider,
    store: Store,
    reportsRoot: URL
) async throws -> RunMetrics {
    try FileManager.default.createDirectory(at: reportsRoot, withIntermediateDirectories: true)

    let started = Date()
    var metrics = RunMetrics(
        started_at: isoNow(),
        finished_at: isoNow(),
        processed: 0,
        generated: 0,
        tone_polish_used: 0,
        fallback_used: 0,
        autodeduped_sentences: 0,
        rejected_quality: 0,
        insufficient_source: 0,
        failed: 0,
        avg_latency_ms: 0,
        backlog_due_before: 0,
        backlog_due_after: 0,
        backlog_remaining_estimate: 0
    )

    var latencySamples: [Int] = []
    var weakSourceEntries: [WeakSourceEntry] = []
    var generatedEntries: [GeneratedSynopsisEntry] = []

    for mediaType in mediaTypes {
        metrics.backlog_due_before += try await store.backlogCount(mediaType: mediaType)
    }

    for mediaType in mediaTypes {
        let candidates = try await store.candidates(mediaType: mediaType, limit: batchSize)

        for candidate in candidates {
            metrics.processed += 1
            let sourceText = bestSourceText(for: candidate)
            if sourceText.count < quality.minSourceChars {
                metrics.insufficient_source += 1
                weakSourceEntries.append(
                    WeakSourceEntry(
                        mediaType: candidate.media_type,
                        mediaId: candidate.media_id,
                        title: candidate.title,
                        sourceChars: sourceText.count,
                        reason: "insufficient_source_text"
                    )
                )
                try? await store.markFailed(
                    mediaType: candidate.media_type,
                    mediaId: candidate.media_id,
                    reason: "insufficient_source_text"
                )
                continue
            }
            let startMs = Date()
            do {
                let generatedRaw = try await provider.generate(title: candidate.title, source: sourceText, config: quality)
                var post = postProcessSynopsis(generatedRaw, config: quality)
                var generated = post.text
                let latency = Int(Date().timeIntervalSince(startMs) * 1000)
                latencySamples.append(latency)

                if !passesQualityGates(candidate: candidate, generated: generated, sourceText: sourceText, config: quality) {
                    let polishedRaw = try await provider.polish(
                        title: candidate.title,
                        source: sourceText,
                        draft: generated,
                        config: quality
                    )
                    if normalizeText(polishedRaw).lowercased() != normalizeText(generated).lowercased() {
                        metrics.tone_polish_used += 1
                    }
                    post = postProcessSynopsis(polishedRaw, config: quality)
                    generated = post.text
                }

                if !passesQualityGates(candidate: candidate, generated: generated, sourceText: sourceText, config: quality) {
                    metrics.fallback_used += 1
                    let fallbackRaw = heuristicSynopsis(title: candidate.title, source: sourceText, config: quality)
                    post = postProcessSynopsis(fallbackRaw, config: quality)
                    generated = post.text
                }

                if !passesQualityGates(candidate: candidate, generated: generated, sourceText: sourceText, config: quality) {
                    metrics.rejected_quality += 1
                    try await store.markFailed(
                        mediaType: candidate.media_type,
                        mediaId: candidate.media_id,
                        reason: "quality_gate_style_or_structure"
                    )
                    continue
                }
                metrics.autodeduped_sentences += post.dedupedCount

                try await store.writeEnhanced(
                    mediaType: candidate.media_type,
                    mediaId: candidate.media_id,
                    text: generated
                )
                metrics.generated += 1
                if generatedEntries.count < 20 {
                    generatedEntries.append(
                        GeneratedSynopsisEntry(
                            mediaType: candidate.media_type,
                            mediaId: candidate.media_id,
                            title: candidate.title,
                            synopsis: generated
                        )
                    )
                }
            } catch {
                metrics.failed += 1
                let reason = String(String(describing: error).prefix(180))
                try? await store.markFailed(
                    mediaType: candidate.media_type,
                    mediaId: candidate.media_id,
                    reason: reason
                )
            }
        }
    }

    for mediaType in mediaTypes {
        metrics.backlog_due_after += try await store.backlogCount(mediaType: mediaType)
    }
    metrics.backlog_remaining_estimate = metrics.backlog_due_after

    metrics.finished_at = isoNow()
    if !latencySamples.isEmpty {
        metrics.avg_latency_ms = latencySamples.reduce(0, +) / latencySamples.count
    }

    let statusData = try JSONEncoder.enrichmentEncoder.encode(metrics)
    let latestStatusURL = reportsRoot.appendingPathComponent("latest-status.json")
    try statusData.write(to: latestStatusURL, options: .atomic)

    let runName = ISO8601DateFormatter().string(from: started).replacingOccurrences(of: ":", with: "-")
    let runLogURL = reportsRoot.appendingPathComponent("run-\(runName).log")
    let summary = "processed=\(metrics.processed) generated=\(metrics.generated) tone_polish_used=\(metrics.tone_polish_used) fallback_used=\(metrics.fallback_used) autodeduped_sentences=\(metrics.autodeduped_sentences) rejected_quality=\(metrics.rejected_quality) insufficient_source=\(metrics.insufficient_source) failed=\(metrics.failed) avg_latency_ms=\(metrics.avg_latency_ms) backlog_due_before=\(metrics.backlog_due_before) backlog_due_after=\(metrics.backlog_due_after)"
    try summary.appending("\n").write(to: runLogURL, atomically: true, encoding: .utf8)

    if !weakSourceEntries.isEmpty {
        let md = buildWeakSourceMarkdown(
            generatedAt: metrics.finished_at,
            minSourceChars: quality.minSourceChars,
            entries: weakSourceEntries
        )
        let latestWeakURL = reportsRoot.appendingPathComponent("weak-sources-latest.md")
        try md.write(to: latestWeakURL, atomically: true, encoding: .utf8)
        let runWeakURL = reportsRoot.appendingPathComponent("weak-sources-\(runName).md")
        try md.write(to: runWeakURL, atomically: true, encoding: .utf8)
    }

    let generatedMd = buildGeneratedSynopsisMarkdown(
        generatedAt: metrics.finished_at,
        entries: generatedEntries
    )
    let latestGeneratedURL = reportsRoot.appendingPathComponent("generated-samples-latest.md")
    try generatedMd.write(to: latestGeneratedURL, atomically: true, encoding: .utf8)
    let runGeneratedURL = reportsRoot.appendingPathComponent("generated-samples-\(runName).md")
    try generatedMd.write(to: runGeneratedURL, atomically: true, encoding: .utf8)

    if let statusText = String(data: statusData, encoding: .utf8) {
        print(statusText)
    }

    return metrics
}

func buildWeakSourceMarkdown(
    generatedAt: String,
    minSourceChars: Int,
    entries: [WeakSourceEntry]
) -> String {
    var lines: [String] = []
    lines.append("# Weak Synopsis Sources")
    lines.append("")
    lines.append("- Generated at: \(generatedAt)")
    lines.append("- Rule: source text must be at least \(minSourceChars) characters")
    lines.append("- Count: \(entries.count)")
    lines.append("")
    lines.append("| Media | ID | Title | Source chars | Reason |")
    lines.append("| --- | ---: | --- | ---: | --- |")
    for entry in entries.sorted(by: {
        if $0.mediaType != $1.mediaType { return $0.mediaType < $1.mediaType }
        return $0.mediaId < $1.mediaId
    }) {
        let safeTitle = entry.title.replacingOccurrences(of: "|", with: "\\|")
        lines.append("| \(entry.mediaType) | \(entry.mediaId) | \(safeTitle) | \(entry.sourceChars) | \(entry.reason) |")
    }
    lines.append("")
    lines.append("## Manual Research Notes")
    lines.append("- Fill this section with trusted source links and rewritten synopsis notes.")
    lines.append("- Re-run the worker after source records are improved.")
    lines.append("")
    return lines.joined(separator: "\n")
}

func buildGeneratedSynopsisMarkdown(
    generatedAt: String,
    entries: [GeneratedSynopsisEntry]
) -> String {
    var lines: [String] = []
    lines.append("# Generated Synopsis Samples")
    lines.append("")
    lines.append("- Generated at: \(generatedAt)")
    lines.append("- Count: \(entries.count)")
    lines.append("")

    if entries.isEmpty {
        lines.append("No generated synopsis samples in this run.")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    for entry in entries {
        let safeTitle = entry.title.replacingOccurrences(of: "|", with: "\\|")
        let synopsis = normalizeText(entry.synopsis).replacingOccurrences(of: "|", with: "\\|")
        lines.append("## \(entry.mediaType) \(entry.mediaId) - \(safeTitle)")
        lines.append("")
        lines.append(synopsis)
        lines.append("")
    }

    return lines.joined(separator: "\n")
}
