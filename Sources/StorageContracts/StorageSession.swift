import Foundation

/// Handed to the body of a write. Everything mutable lives here, and nowhere
/// else.
///
/// ```
///    Outside a transaction        Inside write { session in … }
///    ──────────────────────       ─────────────────────────────
///    NoteReading      ✓           NoteReading       ✓
///    NoteWriting      ✗           NoteWriting       ✓
///                                 SearchIndexing    ✓
///                                 ChangeJournaling  ✓
/// ```
///
/// A service that wants to save a note has no choice but to open a transaction,
/// and once inside it has the index and the journal at hand.
public protocol StorageSession: Sendable {
    var notes: any NoteReading & NoteWriting { get }
    var index: any SearchIndexing { get }
    var journal: any ChangeJournaling { get }
}

/// The only way to reach a writer.
public protocol TransactionRunning: Sendable {
    /// Runs `body` as one unit. Everything it wrote is committed together, or
    /// nothing is.
    ///
    /// Change events are published **after** the commit, never inside it.
    func write<T: Sendable>(
        _ body: @Sendable (any StorageSession) async throws -> T
    ) async throws -> T
}
