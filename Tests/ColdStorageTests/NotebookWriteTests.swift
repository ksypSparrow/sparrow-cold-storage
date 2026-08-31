import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Notebook writes")
struct NotebookWriteTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func draft(_ name: String, parent: NotebookID? = nil) -> Notebook {
        Notebook(
            name: name,
            parentID: parent,
            sortIndex: 0,
            createdAt: Self.now,
            updatedAt: Self.now
        )
    }

    @Test("An inserted notebook is readable outside the transaction",
          arguments: StoreKind.allCases)
    func insertIsVisibleAfterCommit(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let notebook = draft("Wetlands")

        try await fixture.storage.transactions.write { session in
            try session.notebooks.insert(notebook)
        }

        let found = try await fixture.storage.notebooks.notebook(notebook.id)
        #expect(found?.name == "Wetlands")
    }

    @Test("A rename survives, and identity does not change",
          arguments: StoreKind.allCases)
    func updateRenames(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let original = draft("Untitled")
        try await fixture.storage.transactions.write { session in
            try session.notebooks.insert(original)
        }

        try await fixture.storage.transactions.write { session in
            let edit = NotebookEdit(name: "Saltmarsh")
            guard let current = try session.notebooks.notebook(original.id) else {
                throw StorageError.notFound
            }
            try session.notebooks.update(current.applying(edit, at: Self.now))
        }

        let found = try await fixture.storage.notebooks.notebook(original.id)
        #expect(found?.name == "Saltmarsh")
        #expect(found?.id == original.id)
    }

    @Test("A tombstoned notebook disappears from reads",
          arguments: StoreKind.allCases)
    func markDeletedHidesIt(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let notebook = draft("Transient")
        try await fixture.storage.transactions.write { session in
            try session.notebooks.insert(notebook)
        }

        try await fixture.storage.transactions.write { session in
            try session.notebooks.markDeleted(notebook.id, at: Self.now)
        }

        #expect(try await fixture.storage.notebooks.notebook(notebook.id) == nil)
        #expect(try await fixture.storage.notebooks.allNotebooks().count == 1)
    }

    @Test("Inserting the same identifier twice is a constraint violation",
          arguments: StoreKind.allCases)
    func duplicateInsertIsRejected(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let notebook = draft("Once")
        try await fixture.storage.transactions.write { session in
            try session.notebooks.insert(notebook)
        }

        await #expect(throws: StorageError.self) {
            try await fixture.storage.transactions.write { session in
                try session.notebooks.insert(notebook)
            }
        }
    }

    @Test("Updating a notebook that was never inserted is notFound",
          arguments: StoreKind.allCases)
    func updateRequiresAnExistingRow(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        await #expect(throws: StorageError.notFound) {
            try await fixture.storage.transactions.write { session in
                try session.notebooks.update(self.draft("Ghost"))
            }
        }
    }

    /// `NotebookDraft` carries no `sortIndex`, so storage has to answer this
    /// for a caller who cannot know how many siblings a new notebook will have.
    @Test("siblingCount answers where a new notebook should land",
          arguments: StoreKind.allCases)
    func siblingCountCountsTheRightScope(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let parent = draft("Surveys")

        try await fixture.storage.transactions.write { session in
            try session.notebooks.insert(parent)
            try session.notebooks.insert(self.draft("Wetlands", parent: parent.id))
            try session.notebooks.insert(self.draft("Saltmarsh", parent: parent.id))
        }

        let (children, topLevel) = try await fixture.storage.transactions
            .write { session in
                (
                    try session.notebooks.siblingCount(under: parent.id),
                    try session.notebooks.siblingCount(under: nil)
                )
            }
        #expect(children == 2)
        #expect(topLevel == 2)   // the seeded default, plus Surveys
    }

    /// SQLite's foreign key cannot express this: a cycle is a perfectly valid
    /// set of references. A notebook that is its own ancestor would hang the
    /// sidebar rather than fail a query, so both stores check it.
    @Test("A notebook cannot become its own ancestor",
          arguments: StoreKind.allCases)
    func cyclesAreRejected(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)
        let grandparent = draft("Grandparent")
        let parent = draft("Parent", parent: grandparent.id)

        try await fixture.storage.transactions.write { session in
            try session.notebooks.insert(grandparent)
            try session.notebooks.insert(parent)
        }

        await #expect(throws: StorageError.self) {
            try await fixture.storage.transactions.write { session in
                var looped = grandparent
                looped.parentID = parent.id
                try session.notebooks.update(looped)
            }
        }
    }
}
