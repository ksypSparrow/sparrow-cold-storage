import Foundation
import SparrowDomain
import StorageContracts

/// A session's validity, shared by every facade hanging off it.
///
/// The runner flips this the moment `write { }` returns. A session captured
/// past that point then throws on every call instead of quietly mutating state
/// that has already been committed — which would be a write outside any
/// transaction, the exact thing the design forbids.
final class SessionValidity {
    private(set) var isValid = true
    func invalidate() { isValid = false }

    func check() throws {
        guard isValid else {
            throw StorageError.unavailable(
                "this session escaped its write { } block"
            )
        }
    }
}

struct InMemorySession: StorageSession {
    let state: InMemoryState
    let validity: SessionValidity

    var notes: any NoteSessionAccess {
        InMemoryNoteSession(state: state, validity: validity)
    }
    var notebooks: any NotebookSessionAccess {
        InMemoryNotebookSession(state: state, validity: validity)
    }
    var tags: any TagSessionAccess {
        InMemoryTagSession(state: state, validity: validity)
    }

    var index: any SearchIndexWriting {
        InMemoryIndexSession(state: state, validity: validity)
    }
    var journal: any ChangeJournalWriting {
        InMemoryJournalSession(state: state, validity: validity)
    }
}

struct InMemoryNoteSession: NoteSessionAccess {
    let state: InMemoryState
    let validity: SessionValidity

    func note(_ id: NoteID) throws -> Note? {
        try validity.check()
        return state.note(id)
    }

    func insert(_ note: Note) throws {
        try validity.check()
        try state.insert(note)
    }

    func update(_ note: Note) throws {
        try validity.check()
        try state.update(note)
    }

    func markDeleted(_ id: NoteID, at date: Date) throws {
        try validity.check()
        try state.markNoteDeleted(id, at: date)
    }
}

struct InMemoryNotebookSession: NotebookSessionAccess {
    let state: InMemoryState
    let validity: SessionValidity

    func notebook(_ id: NotebookID) throws -> Notebook? {
        try validity.check()
        return state.notebook(id)
    }

    func notebook(named name: String) throws -> Notebook? {
        try validity.check()
        return state.notebook(named: name)
    }

    func siblingCount(under parent: NotebookID?) throws -> Int {
        try validity.check()
        return state.siblingCount(under: parent)
    }

    func insert(_ notebook: Notebook) throws {
        try validity.check()
        try state.insert(notebook)
    }

    func update(_ notebook: Notebook) throws {
        try validity.check()
        try state.update(notebook)
    }

    func markDeleted(_ id: NotebookID, at date: Date) throws {
        try validity.check()
        try state.markNotebookDeleted(id, at: date)
    }
}

struct InMemoryTagSession: TagSessionAccess {
    let state: InMemoryState
    let validity: SessionValidity

    func tag(_ id: TagID) throws -> Tag? {
        try validity.check()
        return state.tag(id)
    }

    func upsert(_ tag: Tag) throws {
        try validity.check()
        state.upsert(tag)
    }

    func markDeleted(_ id: TagID, at date: Date) throws {
        try validity.check()
        try state.markTagDeleted(id, at: date)
    }
}

struct InMemoryIndexSession: SearchIndexWriting {
    let state: InMemoryState
    let validity: SessionValidity

    func index(_ note: Note) throws {
        try validity.check()
        state.index(note)
    }

    func remove(_ id: NoteID) throws {
        try validity.check()
        state.removeFromIndex(id)
    }
}

struct InMemoryJournalSession: ChangeJournalWriting {
    let state: InMemoryState
    let validity: SessionValidity

    @discardableResult
    func record(_ draft: JournalDraft) throws -> JournalEntry {
        try validity.check()
        return state.record(draft)
    }
}
