import Foundation

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Concierge edge functions: shared request scope and error mapping
// Neutral helpers of the Concierge edge-function family, shared by `ImportsService` (parse, apply,
// undo, AniList import) and `ConciergeStore` (recommend). Moved verbatim from `SupabaseService`.

/// Which catalog a Concierge request covers.
enum ConciergeScope: String, Sendable {
    case anime
    case manga
    case both
}

/// The one typed error of the Concierge edge functions: the guardrails answered HTTP 429.
enum ConciergeGuardrailsError: LocalizedError, Sendable, Equatable {
    case rateLimited(retryAfterSeconds: Int?)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let s):
            if let s, s > 0 { return "Too many requests. Try again in \(s)s." }
            return "Too many requests. Try again in a moment."
        }
    }
}

/// A Concierge write that did not commit and can be repeated with the same idempotency key,
/// or a request the server rejected before writing.
enum ConciergeRequestFailure: LocalizedError, Sendable, Equatable {
    case retryable(message: String, retryAfterSeconds: Int?)
    case invalid(message: String, code: String?, index: Int?)

    var isRetryable: Bool {
        if case .retryable = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .retryable(let message, let seconds):
            if let seconds, seconds > 0 { return "\(message) Try again in \(seconds)s." }
            return message
        case .invalid(let message, _, let index):
            if let index { return "\(message) (item \(index + 1))" }
            return message
        }
    }
}

#if canImport(Supabase)
/// Maps edge-function failures onto the Concierge error contract.
enum ConciergeFunctionErrors {
    static func decodeRetryAfterSeconds(from data: Data) -> Int? {
        // Edge functions return: { "error": "Rate limited", "retry_after_s": 30 }
        guard !data.isEmpty else { return nil }
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let n = obj["retry_after_s"] as? Int { return n }
            if let d = obj["retry_after_s"] as? Double { return Int(d.rounded()) }
            if let s = obj["retry_after_s"] as? String, let n = Int(s) { return n }
        }
        return nil
    }

    /// HTTP 429 becomes `ConciergeGuardrailsError.rateLimited`. HTTP 503, and HTTP 500 whose body says
    /// `retryable: true`, become `ConciergeRequestFailure.retryable` (same idempotency key). HTTP 400
    /// with a `code` becomes `ConciergeRequestFailure.invalid`. Cancellation passes through. Every
    /// other error passes through unchanged. The exact account-deletion 403 is a definitive rejection.
    static func translateConciergeFunctionError(_ error: Error) -> Error {
        if error is CancellationError { return error }
        guard case let FunctionsError.httpError(code, data) = error else { return error }
        let body = jsonObject(from: data)
        if code == 429 {
            return ConciergeGuardrailsError.rateLimited(retryAfterSeconds: decodeRetryAfterSeconds(from: data))
        }
        if code == 503 || (code == 500 && body?["retryable"] as? Bool == true) {
            let message = (body?["error"] as? String)?.nilIfEmpty ?? "The request could not be completed."
            return ConciergeRequestFailure.retryable(
                message: message,
                retryAfterSeconds: decodeRetryAfterSeconds(from: data)
            )
        }
        if code == 400 || (code == 403 && body?["code"] as? String == "ACCOUNT_DELETION_IN_PROGRESS") {
            let message = (body?["error"] as? String)?.nilIfEmpty ?? "The request was rejected."
            let itemCode = body?["code"] as? String
            let index = body?["index"] as? Int
            return ConciergeRequestFailure.invalid(message: message, code: itemCode, index: index)
        }
        return error
    }

    private static func jsonObject(from data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
