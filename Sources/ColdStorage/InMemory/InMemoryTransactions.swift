import Foundation
import StorageContracts

struct InMemoryTransactionRunner: TransactionRunning {
    let store: InMemoryStore

    func write<T: Sendable>(
        _ body: @Sendable (any StorageSession) throws -> T
    ) async throws -> T {
        try store.transaction { state in
            let validity = SessionValidity()
            defer { validity.invalidate() }
            return try body(
                InMemorySession(state: state, validity: validity)
            )
        }
    }
}

/// Not in-memory-specific: both stores publish through the same broadcaster,
/// so both observe through this.
struct ChangeObserver: StorageObserving {
    let broadcaster: ChangeBroadcaster

    var changes: AsyncStream<StoredChange> {
        broadcaster.stream()
    }
}
