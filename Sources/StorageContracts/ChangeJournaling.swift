import Foundation
import SparrowDomain

/// The outbound change log.
///
/// Written in V1 and read by nobody until V2. `payload` holds the message
/// format the server will accept, so the wire contract is fixed and tested long
/// before a server exists.
public protocol ChangeJournaling: Sendable {
    func record(_ entry: JournalEntry) async throws
    func pending(limit: Int) async throws -> [JournalEntry]
    func clear(_ ids: [JournalEntry.ID]) async throws
}

public struct JournalEntry: Identifiable, Hashable, Sendable {
    public enum Subject: Hashable, Sendable {
        case note(NoteID)
        // notebook and tag subjects arrive with their domain types, in 0.2.0
        // and 0.7.0 respectively.
    }

    public enum Operation: String, Hashable, Sendable {
        case upsert
        case delete
    }

    public let id: UUID
    /// Local and monotonic. The only ordering the sync protocol trusts.
    public let sequence: Int64
    public let subject: Subject
    public let operation: Operation
    /// The wire shape V2 will send.
    public let payload: Data
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
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
