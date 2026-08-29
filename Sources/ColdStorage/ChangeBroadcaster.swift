import Foundation
import Synchronization
import StorageContracts

/// Fans committed changes out to every observer.
///
/// Deliberately **not** part of `InMemoryStore`. Subscribing to an actor would
/// mean an `await`, so a caller that subscribed and then immediately wrote
/// could miss its own change — a race that would show up as a flaky test and be
/// blamed on the store. A mutex makes subscription synchronous.
final class ChangeBroadcaster: Sendable {
    private let observers =
        Mutex<[UUID: AsyncStream<StoredChange>.Continuation]>([:])

    func stream() -> AsyncStream<StoredChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<StoredChange>.makeStream()
        observers.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        return stream
    }

    func publish(_ change: StoredChange) {
        for continuation in observers.withLock({ Array($0.values) }) {
            continuation.yield(change)
        }
    }

    private func remove(_ id: UUID) {
        observers.withLock { $0[id] = nil }
    }
}
