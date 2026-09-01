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
    /// One timestamp for the whole transaction, so everything it writes agrees
    /// about when it happened.
    let now: Date

    var notes: any NoteSessionAccess {
        SQLiteNoteSession(db: db, validity: validity, touched: touched)
    }

    var notebooks: any NotebookSessionAccess {
        SQLiteNotebookSession(db: db, validity: validity, touched: touched)
    }

    var tags: any TagSessionAccess {
        SQLiteTagSession(db: db, validity: validity, touched: touched, now: now)
    }

    var index: any SearchIndexWriting {
        SQLiteIndexSession(db: db, validity: validity)
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
    private(set) var tags: Set<TagID> = []

    func note(_ id: NoteID) { notes.insert(id) }
    func notebook(_ id: NotebookID) { notebooks.insert(id) }
    func tag(_ id: TagID) { tags.insert(id) }
}
