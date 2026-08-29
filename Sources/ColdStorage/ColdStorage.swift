import Foundation
import StorageContracts

/// Everything the rest of the app is given when storage is opened.
///
/// Note what is here and what is not: **readers and a transaction runner, never
/// a writer.** There is no public path to a write that skips a transaction.
public struct StorageSet: Sendable {
    public let notes: any NoteReading
    public let transactions: any TransactionRunning
    public let observer: any StorageObserving

    init(
        notes: any NoteReading,
        transactions: any TransactionRunning,
        observer: any StorageObserving
    ) {
        self.notes = notes
        self.transactions = transactions
        self.observer = observer
    }
}

/// The entire public surface of this target.
///
/// The concrete repositories are `internal`, so even the composition root
/// cannot name one. It receives protocols and passes them to `SparrowKit`,
/// which never learns that SQLite exists.
public enum ColdStorage {
    /// An ephemeral store for tests and previews.
    ///
    /// Honours the same contracts as the on-disk store: tombstones instead of
    /// deletes, rollback on a thrown error, change events published only after
    /// a commit.
    public static func inMemory() throws -> StorageSet {
        let broadcaster = ChangeBroadcaster()
        let store = InMemoryStore(broadcaster: broadcaster)
        return StorageSet(
            notes: InMemoryNoteReader(store: store),
            transactions: InMemoryTransactionRunner(store: store),
            observer: InMemoryObserver(broadcaster: broadcaster)
        )
    }
}
