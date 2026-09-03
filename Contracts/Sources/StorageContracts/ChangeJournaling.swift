import Foundation
import SparrowDomain

/// One change, as the caller describes it.
///
/// There is no `sequence` and no `id` here: both are assigned by storage. A
/// caller that could choose its own sequence could restart at 1 and silently
/// reorder the sync stream.
public struct JournalDraft: Hashable, Sendable {
    public let subject: JournalEntry.Subject
    public let operation: JournalEntry.Operation
    /// The wire shape V2 will send.
    public let payload: Data
    public let recordedAt: Date

    public init(
        subject: JournalEntry.Subject,
        operation: JournalEntry.Operation,
        payload: Data,
        recordedAt: Date
    ) {
        self.subject = subject
        self.operation = operation
        self.payload = payload
        self.recordedAt = recordedAt
    }
}

/// One change, as storage recorded it.
public struct JournalEntry: Identifiable, Hashable, Sendable {
    public enum Subject: Hashable, Sendable {
        case note(NoteID)
        case notebook(NotebookID)
        case tag(TagID)
    }

    public enum Operation: String, Hashable, Sendable {
        case upsert
        case delete
    }

    public let id: UUID
    /// Local and monotonic, assigned by storage. The only ordering the sync
    /// protocol trusts — never the timestamp, which can go backwards when a
    /// clock is corrected.
    public let sequence: Int64
    public let subject: Subject
    public let operation: Operation
    public let payload: Data
    public let recordedAt: Date

    public init(
        id: UUID,
        sequence: Int64,
        subject: Subject,
        operation: Operation,
        payload: Data,
        recordedAt: Date
    ) {
        self.id = id
        self.sequence = sequence
        self.subject = subject
        self.operation = operation
        self.payload = payload
        self.recordedAt = recordedAt
    }
}

/// Reading the outbound change log, from outside a transaction.
///
/// Written in V1 and read by nobody until V2. `payload` holds the message
/// format the server will accept, so the wire contract is fixed and tested long
/// before a server exists.
public protocol ChangeJournaling: Sendable {
    func pending(limit: Int) async throws -> [JournalEntry]
    func clear(_ ids: [JournalEntry.ID]) async throws
}

/// Appending to the journal inside a transaction.
public protocol ChangeJournalWriting {
    @discardableResult
    func record(_ draft: JournalDraft) throws -> JournalEntry
}
