import Foundation

/// Catalog refreshes that wait for something other than a directory change.
@MainActor final class CatalogRefreshTasks {
    /// Waits until the user is no longer holding or viewing transient state.
    var deferred: Task<Void, Never>?
    /// Waits until the reserved place of a missing application ends.
    var missingApplicationReview: Task<Void, Never>?
}
