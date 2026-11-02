import Foundation

// MARK: - Memory pressure (neutral infrastructure)
// Replaces the service's `trimCachesForMemoryPressure()` fan-out (E6c2): every owner that holds
// non-essential public caches conforms to `MemoryPressureTrimmable`; `AppComposition` registers them
// in ONE list (`AppComposition.memoryPressureOwners`). User-facing state (lists, collection, auth)
// is never touched.

/// An owner that can shed non-essential caches when the system reports memory pressure.
@MainActor
protocol MemoryPressureTrimmable: AnyObject {
    func trimCachesForMemoryPressure()
}

/// The registered owners plus the shared image memory cache, trimmed together on a memory warning.
@MainActor
final class MemoryPressureRelief {
    let owners: [any MemoryPressureTrimmable]

    init(owners: [any MemoryPressureTrimmable]) {
        self.owners = owners
    }

    /// Shed non-essential entity caches under memory pressure without
    /// touching user-facing state (lists, collection, auth).
    func trimCachesForMemoryPressure() {
        for owner in owners { owner.trimCachesForMemoryPressure() }
        Task { await ImagePipeline.shared.clearMemoryCache() }
        #if DEBUG
        print("[MemoryPressure] Trimmed entity + image caches")
        #endif
    }
}
