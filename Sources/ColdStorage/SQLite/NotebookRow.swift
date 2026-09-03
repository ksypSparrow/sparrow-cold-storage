import Foundation
internal import GRDB
import SparrowDomain
import StorageContracts

/// The database's shape of a notebook, and the only place it is known.
///
/// A separate type from `Notebook` on purpose: the domain must not gain a GRDB
/// conformance, or `SparrowDomain` stops compiling on Linux for the V2 server.
/// The cost is this file; the benefit is that the schema can change without the
/// domain noticing.
struct NotebookRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "notebook"

    var id: String
    var name: String
    var parentID: String?
    var colorName: String?
    var sortIndex: Int
    var createdAt: Double
    var updatedAt: Double
    var ownerID: String?
    var localVersion: Int
    var remoteVersion: Int?
    var deletedAt: Double?
    var lastEditor: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentID = "parent_id"
        case colorName = "color_name"
        case sortIndex = "sort_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case ownerID = "owner_id"
        case localVersion = "local_version"
        case remoteVersion = "remote_version"
        case deletedAt = "deleted_at"
        case lastEditor = "last_editor"
    }
}

extension NotebookRow {
    init(_ notebook: Notebook) {
        id = notebook.id.value.uuidString
        name = notebook.name
        parentID = notebook.parentID?.value.uuidString
        colorName = notebook.colorName
        sortIndex = notebook.sortIndex
        createdAt = notebook.createdAt.timeIntervalSince1970
        updatedAt = notebook.updatedAt.timeIntervalSince1970
        ownerID = nil
        localVersion = 0
        remoteVersion = nil
        deletedAt = nil
        lastEditor = nil
    }

    /// - Throws: `StorageError.corrupted` rather than returning `nil`. A row
    ///   whose identifier will not parse is a broken database, and a silently
    ///   skipped notebook would be a far harder bug to find than a thrown one.
    func toDomain() throws -> Notebook {
        guard let uuid = UUID(uuidString: id) else {
            throw StorageError.corrupted("notebook.id is not a UUID: \(id)")
        }
        var parent: NotebookID?
        if let parentID {
            guard let parentUUID = UUID(uuidString: parentID) else {
                throw StorageError.corrupted(
                    "notebook.parent_id is not a UUID: \(parentID)"
                )
            }
            parent = NotebookID(parentUUID)
        }

        return Notebook(
            id: NotebookID(uuid),
            name: name,
            parentID: parent,
            colorName: colorName,
            sortIndex: sortIndex,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
