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

struct InMemoryObserver: StorageObserving {
    let broadcaster: ChangeBroadcaster

    var changes: AsyncStream<StoredChange> {
        broadcaster.stream()
    }
}
