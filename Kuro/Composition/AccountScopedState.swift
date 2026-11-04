import Foundation

/// An owner that holds personalised (account-scoped) results outside the Library store.
///
/// `AppComposition` hands the session funnel (`SessionController`) ONE list of these owners
/// (`AppComposition.makeAccountScopedStates`); the funnel calls both
/// methods on every account transition (a different user signs in, or the session ends), before
/// its first suspension point:
/// - `cancelAccountWork()`: cancels the owner's in-flight account-scoped loads.
/// - `clearPrivateState()`: drops every personalised cache and projection the owner holds.
/// Public data (catalog models, entity and ladder caches, the detail disk cache, the provider
/// registry and availability caches) is not account-scoped and is never cleared here.
@MainActor
protocol AccountScopedState: AnyObject {
    func cancelAccountWork()
    func clearPrivateState()
    /// Confirmed deletion cleanup uses the deleted identity even after a switch.
    func removeDeletedAccountData(userId: String) async throws
    /// A failed launch restore after which the SDK holds no session: no account owns this device's
    /// data any more (the funnel removes the airing reminders in the same case). Default: nothing.
    func removeDataWithoutOwner()
}

extension AccountScopedState {
    func removeDeletedAccountData(userId: String) async throws {}
    func removeDataWithoutOwner() {}
}
