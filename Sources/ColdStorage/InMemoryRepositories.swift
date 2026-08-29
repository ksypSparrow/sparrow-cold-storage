import Foundation
import SparrowDomain
import StorageContracts

/// Every type in this file is `internal` on purpose.
///
/// If `InMemoryNoteRepository` were public, a composition root could construct
/// one directly and hand a writer to a view. The only way in is
/// `ColdStorage.inMemory()`, which returns protocols.

struct InMemoryNoteRepository: NoteReading, NoteWriting {
    let store: InMemoryStore

    func note(_ id: NoteID) async throws -> Note? {
        await store.note(id)
    }

    func notes(_ ids: [NoteID]) async throws -> [Note] {
        await store.notes(ids)
    }

    func recentNotes(limit: Int) async throws -> [Note] {
        await store.recentNotes(limit: limit)
    }

    func count() async throws -> Int {
        await store.count()
    }

    func insert(_ note: Note) async throws {
        try await store.insert(note)
    }

    func update(_ note: Note) async throws {
        try await store.update(note)
    }

    func markDeleted(_ id: NoteID, at date: Date) async throws {
        try await store.markDeleted(id, at: date)
    }
}

/// Reading half of the same store, handed out where a writer must not be
/// reachable.
struct InMemoryNoteReader: NoteReading {
    let store: InMemoryStore

    func note(_ id: NoteID) async throws -> Note? {
        await store.note(id)
    }

    func notes(_ ids: [NoteID]) async throws -> [Note] {
        await store.notes(ids)
    }

    func recentNotes(limit: Int) async throws -> [Note] {
        await store.recentNotes(limit: limit)
    }

    func count() async throws -> Int {
        await store.count()
    }
}

struct InMemorySearchIndex: SearchIndexing {
    let store: InMemoryStore

    func index(_ note: Note) async throws {
        await store.index(note)
    }

    func remove(_ id: NoteID) async throws {
        await store.removeFromIndex(id)
    }

    func matches(_ text: String, limit: Int) async throws -> [NoteID] {
        await store.matches(text, limit: limit)
    }

    func rebuild() async throws {
        await store.rebuildIndex()
    }
}

struct InMemoryJournal: ChangeJournaling {
    let store: InMemoryStore

    func record(_ entry: JournalEntry) async throws {
        await store.record(entry)
    }

    func pending(limit: Int) async throws -> [JournalEntry] {
        await store.pending(limit: limit)
    }

    func clear(_ ids: [JournalEntry.ID]) async throws {
        await store.clear(ids)
    }
}
