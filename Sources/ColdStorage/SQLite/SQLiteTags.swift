import Foundation
internal import GRDB
import SparrowDomain
import StorageContracts

struct TagRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tag"

    var id: String
    var label: String
    var createdAt: Double
    var updatedAt: Double
    var ownerID: String?
    var localVersion: Int
    var remoteVersion: Int?
    var deletedAt: Double?
    var lastEditor: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case ownerID = "owner_id"
        case localVersion = "local_version"
        case remoteVersion = "remote_version"
        case deletedAt = "deleted_at"
        case lastEditor = "last_editor"
    }

    static func live() -> QueryInterfaceRequest<TagRow> {
        TagRow.filter(Column("deleted_at") == nil)
    }
}

extension TagRow {
    init(_ tag: Tag, at date: Date) {
        id = tag.id.slug
        label = tag.label
        createdAt = date.timeIntervalSince1970
        updatedAt = date.timeIntervalSince1970
        ownerID = nil
        localVersion = 0
        remoteVersion = nil
        deletedAt = nil
        lastEditor = nil
    }

    func toDomain() throws -> Tag {
        guard let id = TagID(slug: id) else {
            // Not merely unparseable — a slug that would not survive
            // normalisation cannot have been written by this app.
            throw StorageError.corrupted("tag.id is not a valid slug: \(id)")
        }
        return Tag(id: id, label: label)
    }
}

/// Tag reads from outside a transaction.
struct SQLiteTagRepository: TagReading {
    let storage: SQLiteStorage

    func allTags() async throws -> [Tag] {
        try await storage.read { db in
            try TagRow.live().order(Column("label")).fetchAll(db)
        }.map { try $0.toDomain() }
    }

    func tags(_ ids: [TagID]) async throws -> [Tag] {
        let slugs = ids.map(\.slug)
        guard !slugs.isEmpty else { return [] }

        let found = try await storage.read { db in
            try TagRow.live().filter(slugs.contains(Column("id"))).fetchAll(db)
        }
        let byID = Dictionary(
            uniqueKeysWithValues: try found.map { ($0.id, try $0.toDomain()) }
        )
        // In the order asked for, like `notes(_:)`.
        return slugs.compactMap { byID[$0] }
    }

    func tag(_ id: TagID) async throws -> Tag? {
        try await storage.read { db in
            try TagRow.live().filter(Column("id") == id.slug).fetchOne(db)
        }?.toDomain()
    }
}

/// Tag reads and writes inside a transaction.
struct SQLiteTagSession: TagSessionAccess {
    let db: Database
    let validity: SessionValidity
    let touched: TouchedIdentifiers
    let now: Date

    func tag(_ id: TagID) throws -> Tag? {
        try validity.check()
        return try TagRow.live()
            .filter(Column("id") == id.slug)
            .fetchOne(db)?
            .toDomain()
    }

    func upsert(_ tag: Tag) throws {
        try validity.check()

        if var existing = try TagRow.filter(Column("id") == tag.id.slug)
            .fetchOne(db)
        {
            // Re-using a tombstoned tag revives it. Someone typing `#wetlands`
            // again means the tag, not a new one that happens to match.
            existing.label = tag.label
            existing.deletedAt = nil
            existing.updatedAt = now.timeIntervalSince1970
            existing.localVersion += 1
            try existing.update(db)
        } else {
            try TagRow(tag, at: now).insert(db)
        }
        touched.tag(tag.id)
    }

    func markDeleted(_ id: TagID, at date: Date) throws {
        try validity.check()
        guard let existing = try TagRow.filter(Column("id") == id.slug)
            .fetchOne(db), existing.deletedAt == nil
        else {
            throw StorageError.notFound
        }
        try db.execute(
            sql: """
                UPDATE tag
                   SET deleted_at = ?, local_version = local_version + 1
                 WHERE id = ?
                """,
            arguments: [date.timeIntervalSince1970, id.slug]
        )
        // ⚠️ The `note_tag` rows stay. A tombstoned tag disappears from reads
        // because they join through `tag`, but the notes that carried it keep
        // their link — so reviving the tag restores them, and V2 can merge a
        // delete-here/keep-there without inventing the association again.
        touched.tag(id)
    }
}
