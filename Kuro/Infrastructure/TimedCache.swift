import Foundation

// MARK: - Timed response caches (neutral infrastructure)
// Moved verbatim from `SupabaseService` (E6c2): the owners keep lightweight response caches (avoid
// refetching the same rails/recs when a view reappears). Each owner checks its own TTL against
// `storedAt`; `trimTimedCache` bounds a cache by evicting the oldest entries.

/// A cached value and the moment it was stored.
struct TimedCache<T>: Sendable {
    let value: T
    let storedAt: Date
}

/// Evicts the oldest entries beyond `maxEntries` (shared by the owners' string-keyed caches).
func trimTimedCache<T>(_ cache: inout [String: TimedCache<T>], maxEntries: Int) {
    guard cache.count > maxEntries else { return }
    let sorted = cache.sorted { $0.value.storedAt < $1.value.storedAt }
    let removeCount = max(0, sorted.count - maxEntries)
    for (k, _) in sorted.prefix(removeCount) { cache.removeValue(forKey: k) }
}
