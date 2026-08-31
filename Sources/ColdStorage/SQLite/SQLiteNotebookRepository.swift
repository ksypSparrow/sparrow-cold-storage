import Foundation
import GRDB
import SparrowDomain
import StorageContracts

/// Notebook reads, straight from SQLite.
///
/// Read-only in 0.2.0. `NotebookWriting` arrives in 0.3.0 with transactions,
/// and lands on a separate type reachable only from inside a `write { }`.
struct SQLiteNotebookRepository: NotebookReading {
    let storage: SQLiteStorage

    func notebook(_ id: NotebookID) async throws -> Notebook? {
        try await read { db in
            try NotebookRow
                .filter(Column("id") == id.value.uuidString)
                .filter(Column("deleted_at") == nil)
                .fetchOne(db)
        }?.toDomain()
    }

    func allNotebooks() async throws -> [Notebook] {
        try await read { db in
            try NotebookRow
                .filter(Column("deleted_at") == nil)
                .order(Column("sort_index"), Column("name"))
                .fetchAll(db)
        }.map { try $0.toDomain() }
    }

    func notebook(named name: String) async throws -> Notebook? {
        // SQLite's LIKE is already case-insensitive for ASCII; `COLLATE
        // NOCASE` says so explicitly and keeps the intent visible to whoever
        // reads the query next.
        try await read { db in
            try NotebookRow
                .filter(sql: "name = ? COLLATE NOCASE", arguments: [name])
                .filter(Column("deleted_at") == nil)
                .order(Column("sort_index"))
                .fetchOne(db)
        }?.toDomain()
    }

    func defaultNotebook() async throws -> Notebook {
        if let seeded = try await notebook(DefaultNotebook.identifier) {
            return seeded
        }
        // The seeded notebook was renamed away or tombstoned. Fall back to the
        // first top-level one rather than failing a note creation.
        let candidate = try await read { db in
            try NotebookRow
                .filter(Column("deleted_at") == nil)
                .filter(Column("parent_id") == nil)
                .order(Column("sort_index"), Column("name"))
                .fetchOne(db)
        }
        guard let candidate else {
            throw StorageError.corrupted("the database has no notebooks")
        }
        return try candidate.toDomain()
    }

    private func read<T: Sendable>(
        _ body: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        try await storage.read(body)
    }
}
