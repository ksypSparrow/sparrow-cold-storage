import Foundation
import GRDB
import SparrowDomain
import StorageContracts

/// A session over a live `Database` handle.
///
/// ⚠️ **This is why `StorageSession` is neither `Sendable` nor asynchronous.**
/// A GRDB `Database` belongs to one connection on one thread and must not
/// escape the closure it was handed to. Everything here is synchronous because
/// the handle cannot outlive a suspension point.
struct SQLiteSession: StorageSession {
    let db: Database
    let validity: SessionValidity
    let touched: TouchedIdentifiers

    var notes: any NoteSessionAccess {
        // The note table arrives with migration v2 in 0.4.0. Until then this
        // session honestly reports that there is nowhere to put one, rather
        // than accepting a write that goes nowhere.
        UnavailableNoteSession()
    }

    var notebooks: any NotebookSessionAccess {
        SQLiteNotebookSession(db: db, validity: validity, touched: touched)
    }

    var index: any SearchIndexWriting {
        // FTS5 arrives in 0.5.0, alongside the notes it indexes.
        UnavailableIndexSession()
    }

    var journal: any ChangeJournalWriting {
        SQLiteJournalSession(db: db, validity: validity)
    }
}

/// What a transaction touched, collected so the publisher can announce it
/// after the commit.
final class TouchedIdentifiers: @unchecked Sendable {
    private(set) var notes: Set<NoteID> = []
    private(set) var notebooks: Set<NotebookID> = []

    func note(_ id: NoteID) { notes.insert(id) }
    func notebook(_ id: NotebookID) { notebooks.insert(id) }
}

/// Stands in for storage that does not exist yet.
///
/// Returning this rather than silently doing nothing means a caller that
/// reaches for notes before 0.4.0 finds out at the call site, not by wondering
/// where its data went.
struct UnavailableNoteSession: NoteSessionAccess {
    private var error: StorageError {
        .unavailable("note storage arrives with migration v2, in 0.4.0")
    }

    func note(_ id: NoteID) throws -> Note? { throw error }
    func insert(_ note: Note) throws { throw error }
    func update(_ note: Note) throws { throw error }
    func markDeleted(_ id: NoteID, at date: Date) throws { throw error }
}

struct UnavailableIndexSession: SearchIndexWriting {
    private var error: StorageError {
        .unavailable("the search index arrives with FTS5, in 0.5.0")
    }

    func index(_ note: Note) throws { throw error }
    func remove(_ id: NoteID) throws { throw error }
}
