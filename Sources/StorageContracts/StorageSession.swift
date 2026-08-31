import Foundation

/// Handed to the body of a write. Everything mutable lives here, and nowhere
/// else.
///
/// ⚠️ **Not `Sendable`, and every member is synchronous.** Both are forced by
/// how SQLite works, and both turn out to be what you want:
///
/// - A `Database` handle belongs to one connection on one thread. GRDB's own
///   `write` takes a *synchronous* closure for exactly this reason, so a
///   session whose methods were `async` could not be implemented over it
///   honestly.
/// - A synchronous body also makes it impossible to `await` a network call
///   while holding the write lock, which is the classic way a local database
///   ends up blocked behind someone's timeout.
///
/// The session must not escape `write { }`. One that does is invalidated, and
/// every method on it throws rather than touching a transaction that has
/// already committed.
///
/// ```
///    Outside a transaction        Inside write { session in … }
///    ──────────────────────       ─────────────────────────────
///    NoteReading      ✓ async     NoteSessionAccess      ✓ sync
///    NotebookReading  ✓ async     NotebookSessionAccess  ✓ sync
///    SearchIndexing   ✓ async     SearchIndexWriting     ✓ sync
///    ChangeJournaling ✓ async     ChangeJournalWriting   ✓ sync
///    …writing         ✗           …everything            ✓
/// ```
public protocol StorageSession {
    var notes: any NoteSessionAccess { get }
    var notebooks: any NotebookSessionAccess { get }
    var index: any SearchIndexWriting { get }
    var journal: any ChangeJournalWriting { get }
}

/// The only way to reach a writer.
public protocol TransactionRunning: Sendable {
    /// Runs `body` as one unit. Everything it wrote is committed together, or
    /// nothing is.
    ///
    /// Change events are published **after** the commit, never inside it — a
    /// consumer that read the database on hearing an event fired mid-commit
    /// would see rows that may still be rolled back.
    func write<T: Sendable>(
        _ body: @Sendable (any StorageSession) throws -> T
    ) async throws -> T
}
