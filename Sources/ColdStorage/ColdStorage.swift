import Foundation
import StorageContracts

/// Everything the rest of the app is given when storage is opened.
///
/// Note what is here and what is not: **readers and a transaction runner, never
/// a writer.** There is no public path to a write that skips a transaction.
public struct StorageSet: Sendable {
    public let notes: any NoteReading
    public let notebooks: any NotebookReading
    public let search: any SearchIndexing

    /// The outbound change log. Nothing reads it in V1 — it is here because
    /// the sync engine will, and because a journal nobody can inspect is a
    /// journal nobody can test.
    public let journal: any ChangeJournaling

    public let transactions: any TransactionRunning
    public let observer: any StorageObserving

    init(
        notes: any NoteReading,
        notebooks: any NotebookReading,
        search: any SearchIndexing,
        journal: any ChangeJournaling,
        transactions: any TransactionRunning,
        observer: any StorageObserving
    ) {
        self.notes = notes
        self.notebooks = notebooks
        self.search = search
        self.journal = journal
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
            search: InMemorySearchIndex(store: store),
            journal: InMemoryJournalReader(store: store),
            transactions: InMemoryTransactionRunner(store: store),
            observer: ChangeObserver(broadcaster: broadcaster)
        )
    }

    /// Opens the store at `url`, running any migrations it needs, and returns
    /// the protocols the rest of the app is allowed to hold.
    ///
    /// As of 0.4.0 everything persists: notes, notebooks, the journal.
    /// Full-text search is the last piece, and arrives in 0.5.0.
    public static func make(at url: URL) throws -> StorageSet {
        let broadcaster = ChangeBroadcaster()
        let storage = try SQLiteStorage(at: url)

        return StorageSet(
            notes: SQLiteNoteRepository(storage: storage),
            notebooks: SQLiteNotebookRepository(storage: storage),
            // Full-text search arrives in 0.5.0. Until then this refuses
            // rather than answering from an index that does not exist.
            search: UnavailableSearchIndex(),
            journal: SQLiteJournalReader(storage: storage),
            transactions: SQLiteTransactionRunner(
                storage: storage,
                broadcaster: broadcaster
            ),
            observer: ChangeObserver(broadcaster: broadcaster)
        )
    }
}
