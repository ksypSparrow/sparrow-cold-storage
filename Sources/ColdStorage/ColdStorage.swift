import Foundation
import StorageContracts

/// Everything the rest of the app is given when storage is opened.
///
/// Note what is here and what is not: **readers and a transaction runner, never
/// a writer.** There is no public path to a write that skips a transaction.
public struct StorageSet: Sendable {
    public let notes: any NoteReading
    public let notebooks: any NotebookReading
    public let transactions: any TransactionRunning
    public let observer: any StorageObserving

    init(
        notes: any NoteReading,
        notebooks: any NotebookReading,
        transactions: any TransactionRunning,
        observer: any StorageObserving
    ) {
        self.notes = notes
        self.notebooks = notebooks
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
            notebooks: InMemoryNotebookReader(store: store),
            transactions: InMemoryTransactionRunner(store: store),
            observer: InMemoryObserver(broadcaster: broadcaster)
        )
    }

    /// Opens the store at `url`, running any migrations it needs, and returns
    /// the protocols the rest of the app is allowed to hold.
    ///
    /// ⚠️ **In 0.2.0 this persists notebooks, and notes are still in memory.**
    /// The `note` table arrives with migration v2 in 0.4.0, so a note created
    /// today does not survive a relaunch. Notebooks do. Nothing about this
    /// signature changes when notes join them — which is the point of handing
    /// back protocols.
    public static func make(at url: URL) throws -> StorageSet {
        let broadcaster = ChangeBroadcaster()
        let storage = try SQLiteStorage(at: url)
        let store = InMemoryStore(broadcaster: broadcaster)

        return StorageSet(
            notes: InMemoryNoteReader(store: store),
            notebooks: SQLiteNotebookRepository(storage: storage),
            transactions: InMemoryTransactionRunner(store: store),
            observer: InMemoryObserver(broadcaster: broadcaster)
        )
    }
}
