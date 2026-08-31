import Foundation
import SparrowDomain
import StorageContracts

/// Every type in this file is `internal` on purpose. If they were public, a
/// composition root could construct one and hand a writer to a view.

struct InMemoryNoteReader: NoteReading {
    let store: InMemoryStore

    func note(_ id: NoteID) async throws -> Note? {
        store.read { $0.note(id) }
    }

    func notes(_ ids: [NoteID]) async throws -> [Note] {
        store.read { state in ids.compactMap { state.note($0) } }
    }

    func recentNotes(limit: Int) async throws -> [Note] {
        guard limit > 0 else { return [] }
        return store.read { Array($0.liveNotes().prefix(limit)) }
    }

    func count() async throws -> Int {
        store.read { $0.liveNotes().count }
    }
}

struct InMemoryNotebookReader: NotebookReading {
    let store: InMemoryStore

    func notebook(_ id: NotebookID) async throws -> Notebook? {
        store.read { $0.notebook(id) }
    }

    func allNotebooks() async throws -> [Notebook] {
        store.read { $0.liveNotebooks() }
    }

    func notebook(named name: String) async throws -> Notebook? {
        store.read { $0.notebook(named: name) }
    }

    func defaultNotebook() async throws -> Notebook {
        try store.read { try $0.defaultNotebook() }
    }
}

struct InMemorySearchIndex: SearchIndexing {
    let store: InMemoryStore

    func matches(_ text: String, limit: Int) async throws -> [NoteID] {
        store.read { $0.matches(text, limit: limit) }
    }

    func rebuild() async throws {
        try store.transaction { $0.rebuildIndex() }
    }
}

struct InMemoryJournalReader: ChangeJournaling {
    let store: InMemoryStore

    func pending(limit: Int) async throws -> [JournalEntry] {
        store.read { $0.pending(limit: limit) }
    }

    func clear(_ ids: [JournalEntry.ID]) async throws {
        try store.transaction { $0.clear(ids) }
    }
}
