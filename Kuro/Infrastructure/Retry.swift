import Foundation

// MARK: - Transient-failure retry (neutral infrastructure)
// Moved from `SupabaseService.withRetry` (E6c2), behavior unchanged: only `URLError` is retried
// (transport failures), with exponential backoff 500 ms, 1 s; anything else (HTTP 4xx, decoding,
// cancellation) is thrown at once. The backoff sleep is injectable for tests; production sleeps.

/// Production backoff sleep.
func retryBackoffSleep(_ delay: Duration) async throws {
    try await Task.sleep(for: delay)
}

/// Runs `operation`, retrying it up to `maxRetries` times after a `URLError`.
/// Non-network errors (e.g. HTTP 4xx, decoding) are thrown immediately.
func withRetry<T>(
    maxRetries: Int = 2,
    sleep: (Duration) async throws -> Void = retryBackoffSleep,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?
    for attempt in 0...maxRetries {
        do {
            return try await operation()
        } catch let error as URLError {
            lastError = error
            if attempt < maxRetries {
                #if DEBUG
                print("⟳ retry \(attempt + 1)/\(maxRetries) after URLError \(error.code.rawValue)")
                #endif
                try await sleep(.milliseconds(Int(500 * pow(2.0, Double(attempt)))))
            }
        } catch {
            throw error // Non-network errors are not retried
        }
    }
    throw lastError ?? URLError(.unknown)
}
