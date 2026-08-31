import Foundation
import SparrowDomain
import StorageContracts

struct InMemoryNotebookReader: NotebookReading {
    let store: InMemoryStore

    func notebook(_ id: NotebookID) async throws -> Notebook? {
        await store.notebook(id)
    }

    func allNotebooks() async throws -> [Notebook] {
        await store.allNotebooks()
    }

    func notebook(named name: String) async throws -> Notebook? {
        await store.notebook(named: name)
    }

    func defaultNotebook() async throws -> Notebook {
        try await store.defaultNotebook()
    }
}
