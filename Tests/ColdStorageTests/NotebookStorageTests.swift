import Foundation
import SparrowDomain
import StorageContracts
import Testing
@testable import ColdStorage

@Suite("Notebook storage")
struct NotebookStorageTests {
    @Test("Every store starts with a default notebook", arguments: StoreKind.allCases)
    func storesSeedADefaultNotebook(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        let all = try await fixture.storage.notebooks.allNotebooks()
        #expect(all.count == 1)
        #expect(all.first?.name == DefaultNotebook.name)
    }

    @Test("defaultNotebook() never returns nil", arguments: StoreKind.allCases)
    func defaultNotebookAlwaysExists(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        let notebook = try await fixture.storage.notebooks.defaultNotebook()
        #expect(notebook.id == DefaultNotebook.identifier)
        #expect(notebook.isTopLevel)
    }

    @Test("The seeded notebook is fetchable by identifier", arguments: StoreKind.allCases)
    func seededNotebookIsFetchable(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        let found = try await fixture.storage.notebooks
            .notebook(DefaultNotebook.identifier)
        #expect(found?.name == DefaultNotebook.name)
    }

    @Test("An unknown identifier reads as nil", arguments: StoreKind.allCases)
    func unknownIdentifierIsNil(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        #expect(try await fixture.storage.notebooks.notebook(NotebookID()) == nil)
    }

    @Test(
        "Lookup by name is case-insensitive",
        arguments: StoreKind.allCases,
        ["Field Notes", "field notes", "FIELD NOTES", "fIeLd NoTeS"]
    )
    func lookupByNameIgnoresCase(kind: StoreKind, name: String) async throws {
        let fixture = try StoreFixture(kind)

        let found = try await fixture.storage.notebooks.notebook(named: name)
        #expect(found?.id == DefaultNotebook.identifier)
    }

    @Test("A name that matches nothing reads as nil", arguments: StoreKind.allCases)
    func unknownNameIsNil(kind: StoreKind) async throws {
        let fixture = try StoreFixture(kind)

        #expect(try await fixture.storage.notebooks.notebook(named: "Wetlands") == nil)
    }

    /// The identifier is fixed rather than generated. Two devices that have
    /// never met still agree on which notebook is the default — without that,
    /// V2's first merge would leave every user with two.
    @Test("Both stores seed the same identifier")
    func bothStoresAgreeOnTheDefault() async throws {
        let memory = try StoreFixture(.inMemory)
        let disk = try StoreFixture(.onDisk)

        let fromMemory = try await memory.storage.notebooks.defaultNotebook()
        let fromDisk = try await disk.storage.notebooks.defaultNotebook()

        #expect(fromMemory.id == fromDisk.id)
        #expect(fromMemory.name == fromDisk.name)
    }
}
