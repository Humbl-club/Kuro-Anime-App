import Foundation

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
// MARK: - Provider Availability Models

enum ProviderAvailabilityNoteKind: String, Sendable, Equatable {
    case dub
    case audio
    case subtitles
    case availability
}

struct ProviderAvailabilityNote: Sendable, Equatable {
    let kind: ProviderAvailabilityNoteKind
    let languageCode: String?
    let countries: [String]

    var displayText: String {
        let normalizedCountries = countries.sorted()
        switch kind {
        case .availability:
            return "Availability: \(normalizedCountries.joined(separator: ", "))"
        case .dub:
            return "\(displayLanguageCode) dub: \(normalizedCountries.joined(separator: ", "))"
        case .audio:
            return "\(displayLanguageCode) audio: \(normalizedCountries.joined(separator: ", "))"
        case .subtitles:
            return "\(displayLanguageCode) subtitles: \(normalizedCountries.joined(separator: ", "))"
        }
    }

    private var displayLanguageCode: String {
        guard let languageCode, !languageCode.isEmpty else { return "Unknown" }
        return languageCode.uppercased()
    }
}

enum ProviderAvailabilityNoteBuilder {
    static func normalizedLanguage(_ raw: String?) -> String {
        let source = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source.isEmpty { return "unknown" }
        if source.hasPrefix("de") || source.contains("german") || source.contains("deutsch") { return "de" }
        if source.hasPrefix("en") || source.contains("english") { return "en" }
        if source.hasPrefix("ja") || source.contains("japanese") { return "ja" }
        if source.hasPrefix("ko") || source.contains("korean") { return "ko" }
        if source.hasPrefix("zh") || source.contains("chinese") || source.contains("mandarin") { return "zh" }
        return "other"
    }

    static func bestNote(
        from providers: [ProviderAvailabilityProvider],
        preferredAudioLang: String?,
        preferredSubtitleLang: String? = nil,
        originalLanguage: String? = nil
    ) -> ProviderAvailabilityNote? {
        let preferredAudio = normalizedLanguage(preferredAudioLang)
        let preferredSubtitle = normalizedLanguage(preferredSubtitleLang ?? preferredAudioLang)
        let normalizedOriginal = normalizedLanguage(originalLanguage)

        func normalizedCountries(for language: String, in map: [String: [String]]) -> [String] {
            guard let countries = map[language], !countries.isEmpty else { return [] }
            return Array(Set(countries)).sorted()
        }

        func audioKind(for language: String) -> ProviderAvailabilityNoteKind {
            if normalizedOriginal == "en" || normalizedOriginal == "de" {
                return normalizedOriginal != language ? .dub : .audio
            }
            if normalizedOriginal == "ja" || normalizedOriginal == "ko" || normalizedOriginal == "zh" || normalizedOriginal == "other" {
                return .dub
            }
            return .audio
        }

        func bestNote(for provider: ProviderAvailabilityProvider) -> ProviderAvailabilityNote? {
            func audioNote(for language: String) -> ProviderAvailabilityNote? {
                guard language == "en" || language == "de" else { return nil }
                let countries = normalizedCountries(for: language, in: provider.countriesByAudioLang)
                guard !countries.isEmpty else { return nil }
                return ProviderAvailabilityNote(
                    kind: audioKind(for: language),
                    languageCode: language,
                    countries: countries
                )
            }

            func subtitleNote(for language: String) -> ProviderAvailabilityNote? {
                guard language == "en" || language == "de" else { return nil }
                let countries = normalizedCountries(for: language, in: provider.countriesBySubtitleLang)
                guard !countries.isEmpty else { return nil }
                return ProviderAvailabilityNote(kind: .subtitles, languageCode: language, countries: countries)
            }

            func availabilityNote() -> ProviderAvailabilityNote? {
                let audioCountries = provider.countriesByAudioLang.values.flatMap { $0 }
                let subtitleCountries = provider.countriesBySubtitleLang.values.flatMap { $0 }
                let countries = Array(Set(audioCountries + subtitleCountries)).sorted()
                guard !countries.isEmpty else { return nil }
                return ProviderAvailabilityNote(kind: .availability, languageCode: nil, countries: countries)
            }

            let noteCandidates: [ProviderAvailabilityNote?] = [
                audioNote(for: preferredAudio),
                subtitleNote(for: preferredSubtitle),
                audioNote(for: "en"),
                audioNote(for: "de"),
                subtitleNote(for: "en"),
                subtitleNote(for: "de"),
                availabilityNote()
            ]

            return noteCandidates.compactMap { $0 }.first
        }

        for provider in providers {
            if let note = bestNote(for: provider) {
                return note
            }
        }
        return nil
    }
}

struct ProviderAvailabilityProvider: Decodable, Sendable {
    let slug: String
    let displayName: String
    let url: String?
    let languages: [String]
    let audioLanguages: [String]
    let subtitleLanguages: [String]
    let countriesByAudioLang: [String: [String]]
    let countriesBySubtitleLang: [String: [String]]
    let isStale: Bool

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case url
        case languages
        case audioLanguages = "audio_languages"
        case subtitleLanguages = "subtitle_languages"
        case countriesByAudioLang = "countries_by_audio_lang"
        case countriesBySubtitleLang = "countries_by_sub_lang"
        case isStale = "is_stale"
    }
}

struct ProviderAvailabilityBatchItem: Decodable, Sendable {
    let mediaType: String
    let mediaId: Int
    let providers: [ProviderAvailabilityProvider]

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case mediaId = "media_id"
        case providers
    }
}

struct MediaAvailabilityStatus: Decodable, Sendable {
    let hasRows: Bool
    let status: String
    let lastRefreshedAt: Date?
    let nextRefreshAt: Date?
    let staleDays: Int?

    enum CodingKeys: String, CodingKey {
        case hasRows = "has_rows"
        case status
        case lastRefreshedAt = "last_refreshed_at"
        case nextRefreshAt = "next_refresh_at"
        case staleDays = "stale_days"
    }
}
