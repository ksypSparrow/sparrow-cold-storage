import Foundation
import GRDB
import SparrowDomain
import StorageContracts

/// Notebook reads and writes inside a transaction.
struct SQLiteNotebookSession: NotebookSessionAccess {
    let db: Database
    let validity: SessionValidity
    let touched: TouchedIdentifiers

    func notebook(_ id: NotebookID) throws -> Notebook? {
        try validity.check()
        return try live().filter(Column("id") == id.value.uuidString)
            .fetchOne(db)?.toDomain()
    }

    func notebook(named name: String) throws -> Notebook? {
        try validity.check()
        return try live()
            .filter(sql: "name = ? COLLATE NOCASE", arguments: [name])
            .order(Column("sort_index"))
            .fetchOne(db)?.toDomain()
    }

    func siblingCount(under parent: NotebookID?) throws -> Int {
        try validity.check()
        let query = if let parent {
            live().filter(Column("parent_id") == parent.value.uuidString)
        } else {
            live().filter(Column("parent_id") == nil)
        }
        return try query.fetchCount(db)
    }

    func insert(_ notebook: Notebook) throws {
        try validity.check()
        guard try notebookRow(notebook.id) == nil else {
            throw StorageError.constraintViolated(
                "a notebook with id \(notebook.id) already exists"
            )
        }
        try assertNoCycle(from: notebook.parentID, adding: notebook.id)
        try NotebookRow(notebook).insert(db)
        touched.notebook(notebook.id)
    }

    func update(_ notebook: Notebook) throws {
        try validity.check()
        guard let existing = try notebookRow(notebook.id),
              existing.deletedAt == nil else {
            throw StorageError.notFound
        }
        try assertNoCycle(from: notebook.parentID, adding: notebook.id)

        var row = NotebookRow(notebook)
        // Carry the sync seam forward; it is storage's, not the domain's.
        row.ownerID = existing.ownerID
        row.remoteVersion = existing.remoteVersion
        row.lastEditor = existing.lastEditor
        row.localVersion = existing.localVersion + 1
        try row.update(db)
        touched.notebook(notebook.id)
    }

    func markDeleted(_ id: NotebookID, at date: Date) throws {
        try validity.check()
        guard let existing = try notebookRow(id), existing.deletedAt == nil else {
            throw StorageError.notFound
        }
        try db.execute(
            sql: """
                UPDATE notebook
                   SET deleted_at = ?, local_version = local_version + 1
                 WHERE id = ?
                """,
            arguments: [date.timeIntervalSince1970, id.value.uuidString]
        )
        touched.notebook(id)
    }

    // MARK: Helpers

    private func live() -> QueryInterfaceRequest<NotebookRow> {
        NotebookRow.filter(Column("deleted_at") == nil)
    }

    private func notebookRow(_ id: NotebookID) throws -> NotebookRow? {
        try NotebookRow.filter(Column("id") == id.value.uuidString).fetchOne(db)
    }

    /// Walking up from `parent` must never arrive back at `id`.
    ///
    /// SQLite's foreign key cannot express this — a cycle is a perfectly valid
    /// set of references, and a notebook that is its own ancestor would hang
    /// the sidebar rather than fail a query.
    private func assertNoCycle(
        from parent: NotebookID?,
        adding id: NotebookID
    ) throws {
        var seen: Set<NotebookID> = [id]
        var cursor = parent
        while let current = cursor {
            guard seen.insert(current).inserted else {
                throw StorageError.constraintViolated(
                    "that would make a loop of notebooks"
                )
            }
            cursor = try notebookRow(current)?.parentID
                .flatMap(UUID.init(uuidString:))
                .map(NotebookID.init)
        }
    }
}
