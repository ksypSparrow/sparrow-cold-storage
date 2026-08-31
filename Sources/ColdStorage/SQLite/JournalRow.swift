import Foundation
import GRDB
import SparrowDomain
import StorageContracts

/// The database's shape of a journal entry.
struct JournalRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "journal"

    var seq: Int64?
    var id: String
    var subjectType: String
    var subjectID: String
    var operation: String
    var payload: Data
    var recordedAt: Double
    var ownerID: String?
    var lastEditor: String?

    enum CodingKeys: String, CodingKey {
        case seq
        case id
        case subjectType = "subject_type"
        case subjectID = "subject_id"
        case operation
        case payload
        case recordedAt = "recorded_at"
        case ownerID = "owner_id"
        case lastEditor = "last_editor"
    }
}

extension JournalRow {
    init(_ draft: JournalDraft, id: UUID) {
        seq = nil                       // SQLite assigns it
        self.id = id.uuidString
        switch draft.subject {
        case .note(let noteID):
            subjectType = "note"
            subjectID = noteID.value.uuidString
        case .notebook(let notebookID):
            subjectType = "notebook"
            subjectID = notebookID.value.uuidString
        }
        operation = draft.operation.rawValue
        payload = draft.payload
        recordedAt = draft.recordedAt.timeIntervalSince1970
        ownerID = nil
        lastEditor = nil
    }

    func toDomain() throws -> JournalEntry {
        guard let uuid = UUID(uuidString: id) else {
            throw StorageError.corrupted("journal.id is not a UUID: \(id)")
        }
        guard let subjectUUID = UUID(uuidString: subjectID) else {
            throw StorageError.corrupted(
                "journal.subject_id is not a UUID: \(subjectID)"
            )
        }
        guard let operation = JournalEntry.Operation(rawValue: operation) else {
            throw StorageError.corrupted(
                "journal.operation is unknown: \(operation)"
            )
        }

        let subject: JournalEntry.Subject
        switch subjectType {
        case "note": subject = .note(NoteID(subjectUUID))
        case "notebook": subject = .notebook(NotebookID(subjectUUID))
        default:
            throw StorageError.corrupted(
                "journal.subject_type is unknown: \(subjectType)"
            )
        }

        return JournalEntry(
            id: uuid,
            sequence: seq ?? 0,
            subject: subject,
            operation: operation,
            payload: payload,
            recordedAt: Date(timeIntervalSince1970: recordedAt)
        )
    }
}
