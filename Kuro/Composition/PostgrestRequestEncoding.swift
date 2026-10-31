import Foundation

#if canImport(Supabase)
import Supabase

/// PostgREST cursor parameters target `timestamptz`. The pinned SDK's timestamp format omits
/// the zone; always send fractional seconds and UTC explicitly so PostgreSQL cannot reinterpret
/// a cursor using its session timezone. Auth and response decoding keep their existing strategies.
enum PostgrestRequestEncoding {
    nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        let defaults = PostgrestClient.Configuration.jsonEncoder
        encoder.keyEncodingStrategy = defaults.keyEncodingStrategy
        encoder.dataEncodingStrategy = defaults.dataEncodingStrategy
        encoder.nonConformingFloatEncodingStrategy = defaults.nonConformingFloatEncodingStrategy
        encoder.outputFormatting = defaults.outputFormatting
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let utc = ISO8601DateFormatter()
            utc.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            utc.timeZone = TimeZone(secondsFromGMT: 0)
            var container = encoder.singleValueContainer()
            try container.encode(utc.string(from: date))
        }
        return encoder
    }
}
#endif
