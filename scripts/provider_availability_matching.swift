import Foundation

enum ProviderWorkerError: Error, CustomStringConvertible {
    case missingEnv(String)
    case invalidResponse(String)

    var description: String {
        switch self {
        case .missingEnv(let key):
            return "Missing env var: \(key)"
        case .invalidResponse(let msg):
            return msg
        }
    }
}

struct StreamingServiceRecord: Decodable {
    let slug: String
    let display_name: String
    let site_patterns: [String]
    let priority: Int
    let is_active: Bool
}

struct WatchmodeSearchHit {
    let id: String
    let title: String
    let year: Int?
}

struct ScoredHit {
    let hit: WatchmodeSearchHit
    let score: Double
}

struct AvailabilityKey: Hashable {
    let mediaType: String
    let mediaId: Int
    let providerSlug: String
    let countryCode: String
    let availabilityType: String
}

struct AvailabilityAggregate {
    var audioLangs: Set<String>
    var subtitleLangs: Set<String>
    var deepLinkURL: String?
    var webURL: String?
    var sourceOfferID: String?
}

struct AvailabilityUpsert: Encodable {
    let media_type: String
    let media_id: Int
    let provider_slug: String
    let country_code: String
    let availability_type: String
    let audio_langs: [String]
    let subtitle_langs: [String]
    let deep_link_url: String?
    let web_url: String?
    let source_name: String
    let source_offer_id: String?
    let last_seen_at: String
    let updated_at: String
}

func nowISO8601() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func isoDate(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

func normalizeTitle(_ text: String) -> String {
    text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func tokenSet(_ text: String) -> Set<String> {
    Set(normalizeTitle(text).split(separator: " ").map(String.init).filter { !$0.isEmpty })
}

func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
    if lhs.isEmpty && rhs.isEmpty { return 1 }
    let intersection = lhs.intersection(rhs).count
    let union = lhs.union(rhs).count
    guard union > 0 else { return 0 }
    return Double(intersection) / Double(union)
}

func levenshteinDistance(_ a: String, _ b: String) -> Int {
    let lhs = Array(a)
    let rhs = Array(b)
    if lhs.isEmpty { return rhs.count }
    if rhs.isEmpty { return lhs.count }

    var costs = Array(0...rhs.count)
    for i in 1...lhs.count {
        var previous = costs[0]
        costs[0] = i
        for j in 1...rhs.count {
            let tmp = costs[j]
            let substitution = previous + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
            let insertion = costs[j] + 1
            let deletion = costs[j - 1] + 1
            costs[j] = min(substitution, min(insertion, deletion))
            previous = tmp
        }
    }
    return costs[rhs.count]
}

func similarity(_ lhs: String, _ rhs: String) -> Double {
    let left = normalizeTitle(lhs)
    let right = normalizeTitle(rhs)
    guard !left.isEmpty, !right.isEmpty else { return 0 }

    let tokens = jaccard(tokenSet(left), tokenSet(right))
    let lev = levenshteinDistance(left, right)
    let maxLen = max(left.count, right.count)
    let edit = maxLen > 0 ? 1.0 - (Double(lev) / Double(maxLen)) : 0

    return max(0, min(1, 0.55 * edit + 0.45 * tokens))
}

func unresolvedRetryInterval(retryCount: Int, requestReason: String?) -> TimeInterval {
    let normalizedReason = requestReason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let isOnDemand = normalizedReason == "detail_open" || normalizedReason == "user_tap"
    if isOnDemand && retryCount == 0 {
        return 30 * 60
    }
    let backoffHours = min(24, Int(pow(2.0, Double(min(retryCount, 5)))))
    return Double(backoffHours) * 3600
}

func normalizeLanguage(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let cleaned = raw
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }

    if cleaned.count == 2 {
        return String(cleaned.prefix(2))
    }
    if cleaned.hasPrefix("en") || cleaned.contains("english") { return "en" }
    if cleaned.hasPrefix("de") || cleaned.contains("german") || cleaned.contains("deutsch") { return "de" }
    if cleaned.hasPrefix("ja") || cleaned.contains("japanese") { return "ja" }
    if cleaned.hasPrefix("fr") || cleaned.contains("french") { return "fr" }
    if cleaned.hasPrefix("es") || cleaned.contains("spanish") { return "es" }
    if cleaned.hasPrefix("it") || cleaned.contains("italian") { return "it" }
    if cleaned.hasPrefix("pt") || cleaned.contains("portuguese") { return "pt" }

    return String(cleaned.prefix(2))
}

func parseLanguageArray(_ value: Any?) -> [String] {
    if let array = value as? [String] {
        return Array(Set(array.compactMap(normalizeLanguage))).sorted()
    }
    if let string = value as? String {
        let parts = string
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" })
            .map { String($0) }
        return Array(Set(parts.compactMap(normalizeLanguage))).sorted()
    }
    return []
}

func parseCountryCode(_ value: Any?) -> String? {
    guard let raw = value as? String else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard trimmed.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil else {
        return nil
    }
    return trimmed
}

func scoreHits(hits: [WatchmodeSearchHit], localTitles: [String], localYear: Int?) -> [ScoredHit] {
    let scored = hits.map { hit -> ScoredHit in
        var best = 0.0
        for local in localTitles {
            best = max(best, similarity(local, hit.title))
        }
        if let localYear, let hitYear = hit.year, abs(localYear - hitYear) > 2 {
            best -= 0.08
        }
        return ScoredHit(hit: hit, score: max(0, min(1, best)))
    }
    return scored.sorted { lhs, rhs in
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.hit.id < rhs.hit.id
    }
}

func mapProvider(providerName: String, services: [StreamingServiceRecord]) -> StreamingServiceRecord? {
    let normalized = providerName
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()

    var best: (service: StreamingServiceRecord, patternLength: Int)? = nil
    for service in services where service.is_active {
        for pattern in service.site_patterns {
            let p = pattern.lowercased()
            guard !p.isEmpty, normalized.contains(p) else { continue }
            if let current = best {
                if service.priority < current.service.priority {
                    best = (service, p.count)
                } else if service.priority == current.service.priority, p.count > current.patternLength {
                    best = (service, p.count)
                }
            } else {
                best = (service, p.count)
            }
        }
    }
    return best?.service
}

func normalizeAvailabilityType(_ raw: String?) -> String {
    guard let raw else { return "subscription" }
    let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if lower.contains("free") { return "free" }
    if lower.contains("buy") || lower.contains("purchase") { return "purchase" }
    if lower.contains("rent") { return "rent" }
    if lower.contains("add") || lower.contains("channel") { return "addon" }
    return "subscription"
}

func sanitizeURL(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lower = trimmed.lowercased()
    guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
    return trimmed
}

func transformOffers(
    offers: [[String: Any]],
    mediaType: String,
    mediaId: Int,
    services: [StreamingServiceRecord]
) -> (rows: [AvailabilityUpsert], countryCount: Int) {
    var aggregate: [AvailabilityKey: AvailabilityAggregate] = [:]

    for offer in offers {
        let providerName = (offer["name"] as? String)
            ?? (offer["source_name"] as? String)
            ?? (offer["source"] as? String)
            ?? ""
        guard !providerName.isEmpty else { continue }

        guard let mappedService = mapProvider(providerName: providerName, services: services) else {
            continue
        }

        let countryCode = parseCountryCode(offer["region"])
            ?? parseCountryCode(offer["country"])
            ?? parseCountryCode(offer["country_code"])
        guard let countryCode else { continue }

        let availabilityType = normalizeAvailabilityType(offer["type"] as? String)

        let audio = Set(
            parseLanguageArray(offer["audio_languages"]) +
            parseLanguageArray(offer["audio_language"]) +
            parseLanguageArray(offer["language"])
        )
        let subtitles = Set(
            parseLanguageArray(offer["subtitle_languages"]) +
            parseLanguageArray(offer["subtitles"]) +
            parseLanguageArray(offer["subtitle_language"])
        )

        let deepLink = (offer["ios_url"] as? String)
            ?? (offer["android_url"] as? String)
            ?? (offer["deep_link_url"] as? String)
        let webURL = (offer["web_url"] as? String)
            ?? (offer["url"] as? String)

        let sourceOfferID: String?
        if let sourceID = offer["source_id"] as? Int {
            sourceOfferID = String(sourceID)
        } else if let sourceID = offer["source_id"] as? String {
            sourceOfferID = sourceID
        } else if let id = offer["id"] as? Int {
            sourceOfferID = String(id)
        } else if let id = offer["id"] as? String {
            sourceOfferID = id
        } else {
            sourceOfferID = nil
        }

        let key = AvailabilityKey(
            mediaType: mediaType,
            mediaId: mediaId,
            providerSlug: mappedService.slug,
            countryCode: countryCode,
            availabilityType: availabilityType
        )

        var current = aggregate[key] ?? AvailabilityAggregate(
            audioLangs: [],
            subtitleLangs: [],
            deepLinkURL: nil,
            webURL: nil,
            sourceOfferID: nil
        )
        current.audioLangs.formUnion(audio)
        current.subtitleLangs.formUnion(subtitles)
        if current.deepLinkURL == nil { current.deepLinkURL = sanitizeURL(deepLink) }
        if current.webURL == nil { current.webURL = sanitizeURL(webURL) }
        if current.sourceOfferID == nil { current.sourceOfferID = sourceOfferID }
        aggregate[key] = current
    }

    let now = nowISO8601()
    let rows = aggregate.map { key, value in
        AvailabilityUpsert(
            media_type: key.mediaType,
            media_id: key.mediaId,
            provider_slug: key.providerSlug,
            country_code: key.countryCode,
            availability_type: key.availabilityType,
            audio_langs: value.audioLangs.sorted(),
            subtitle_langs: value.subtitleLangs.sorted(),
            deep_link_url: sanitizeURL(value.deepLinkURL),
            web_url: sanitizeURL(value.webURL),
            source_name: "watchmode",
            source_offer_id: value.sourceOfferID,
            last_seen_at: now,
            updated_at: now
        )
    }

    return (rows.sorted { lhs, rhs in
        if lhs.provider_slug != rhs.provider_slug { return lhs.provider_slug < rhs.provider_slug }
        if lhs.country_code != rhs.country_code { return lhs.country_code < rhs.country_code }
        return lhs.availability_type < rhs.availability_type
    }, aggregate.count)
}
