import Foundation
internal import GRDB
import SparrowDomain
import StorageContracts

/// The database's shape of a note.
///
/// ⚠️ **The sync columns live here and never on `Note`.** `ownerID`,
/// `localVersion`, `remoteVersion` and `deletedAt` are storage bookkeeping;
/// putting them on the domain type would invite a service to reason about
/// them, and then V2's merge rules would be spread across three layers.
struct NoteRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "note"

    var id: String
    var notebookID: String
    var kind: String
    var titleData: Data?
    var titlePlain: String
    var bodyData: Data?
    var bodyPlain: String
    var isPinned: Bool
    var observedAt: Double?
    /// Set only for `.daily` notes — the calendar day they belong to.
    var day: String?
    var createdAt: Double
    var updatedAt: Double
    var ownerID: String?
    var localVersion: Int
    var remoteVersion: Int?
    var deletedAt: Double?
    var lastEditor: String?

    enum CodingKeys: String, CodingKey {
        case id
        case notebookID = "notebook_id"
        case kind
        case titleData = "title_data"
        case titlePlain = "title_plain"
        case bodyData = "body_data"
        case bodyPlain = "body_plain"
        case isPinned = "is_pinned"
        case observedAt = "observed_at"
        case day
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case ownerID = "owner_id"
        case localVersion = "local_version"
        case remoteVersion = "remote_version"
        case deletedAt = "deleted_at"
        case lastEditor = "last_editor"
    }
}

extension NoteRow {
    init(_ note: Note) {
        id = note.id.value.uuidString
        notebookID = note.notebookID.value.uuidString
        kind = note.kind.rawValue
        titleData = note.title.attributes
        titlePlain = note.title.plain
        bodyData = note.body.attributes
        bodyPlain = note.body.plain
        isPinned = note.isPinned
        observedAt = note.observedAt?.timeIntervalSince1970
        // The key is derived from the moment the note is *about* where there
        // is one, so a daily entry written after midnight about yesterday
        // still lands on yesterday.
        day = note.kind == .daily
            ? DayKey.string(for: note.happenedAt)
            : nil
        createdAt = note.createdAt.timeIntervalSince1970
        updatedAt = note.updatedAt.timeIntervalSince1970
        ownerID = nil
        localVersion = 0
        remoteVersion = nil
        deletedAt = nil
        lastEditor = nil
    }

    /// - Throws: `StorageError.corrupted` for anything that will not parse.
    ///   A row that yielded a silently empty note would be a far harder bug to
    ///   find than a thrown one.
    /// - Parameter tagIDs: from `note_tag`. A row alone cannot produce a
    ///   complete note, which is why every read fetches the join alongside.
    func toDomain(tagIDs: [TagID] = []) throws -> Note {
        guard let uuid = UUID(uuidString: id) else {
            throw StorageError.corrupted("note.id is not a UUID: \(id)")
        }
        guard let notebookUUID = UUID(uuidString: notebookID) else {
            throw StorageError.corrupted(
                "note.notebook_id is not a UUID: \(notebookID)"
            )
        }
        guard let kind = NoteKind(rawValue: kind) else {
            throw StorageError.corrupted("note.kind is unknown: \(kind)")
        }

        return Note(
            id: NoteID(uuid),
            title: RichText(plain: titlePlain, attributes: titleData),
            body: RichText(plain: bodyPlain, attributes: bodyData),
            notebookID: NotebookID(notebookUUID),
            tagIDs: tagIDs,
            kind: kind,
            isPinned: isPinned,
            observedAt: observedAt.map(Date.init(timeIntervalSince1970:)),
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
