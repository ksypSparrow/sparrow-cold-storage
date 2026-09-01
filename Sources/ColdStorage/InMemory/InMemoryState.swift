import Foundation
import SparrowDomain
import StorageContracts

/// The whole of the in-memory store's data, and every operation on it.
///
/// Deliberately **unguarded**. `InMemoryStore` owns the lock; holding it for a
/// whole transaction is what makes a write atomic, and a second lock in here
/// would deadlock against the first.
///
/// `@unchecked Sendable` because the mutex is the guarantee the compiler cannot
/// see. The reference is only ever reachable from inside `withLock`, and the
/// session that borrows it is invalidated the moment the lock is released.
final class InMemoryState: @unchecked Sendable {
    var notes: [NoteID: Note] = [:]
    var noteTombstones: [NoteID: Date] = [:]
    var notebooks: [NotebookID: Notebook] = [:]
    var notebookTombstones: [NotebookID: Date] = [:]
    var tags: [TagID: Tag] = [:]
    var tagTombstones: [TagID: Date] = [:]
    var indexed: [NoteID: String] = [:]
    var journal: [JournalEntry] = []
    var sequence: Int64 = 0

    var touchedNotes: Set<NoteID> = []
    var touchedNotebooks: Set<NotebookID> = []
    var touchedTags: Set<TagID> = []

    init(seededAt date: Date) {
        let seed = DefaultNotebook.make(at: date)
        notebooks[seed.id] = seed
    }

    private init(copying other: InMemoryState) {
        notes = other.notes
        noteTombstones = other.noteTombstones
        notebooks = other.notebooks
        notebookTombstones = other.notebookTombstones
        tags = other.tags
        tagTombstones = other.tagTombstones
        indexed = other.indexed
        journal = other.journal
        sequence = other.sequence
    }

    func snapshot() -> InMemoryState { InMemoryState(copying: self) }

    func restore(from snapshot: InMemoryState) {
        notes = snapshot.notes
        noteTombstones = snapshot.noteTombstones
        notebooks = snapshot.notebooks
        notebookTombstones = snapshot.notebookTombstones
        tags = snapshot.tags
        tagTombstones = snapshot.tagTombstones
        indexed = snapshot.indexed
        journal = snapshot.journal
        sequence = snapshot.sequence
    }

    // MARK: Notes

    func note(_ id: NoteID) -> Note? {
        guard noteTombstones[id] == nil, let note = notes[id] else { return nil }
        return withLiveTags(note)
    }

    func liveNotes() -> [Note] {
        notes.values
            .filter { noteTombstones[$0.id] == nil }
            .map(withLiveTags)
            .sorted { ($0.updatedAt, $0.id.value.uuidString)
                    > ($1.updatedAt, $1.id.value.uuidString) }
    }

    /// Drops tags that have been tombstoned.
    ///
    /// ⚠️ SQLite gets this for free: a note's tags are read through a join to
    /// `tag`, which filters `deleted_at IS NULL`. In memory the identifiers
    /// live on the note value itself, so nothing filters them unless this
    /// does — and the two stores would disagree about a deleted tag. The
    /// parity suites caught exactly that.
    private func withLiveTags(_ note: Note) -> Note {
        guard !note.tagIDs.isEmpty else { return note }
        var projected = note
        projected.tagIDs = note.tagIDs.filter { tagTombstones[$0] == nil }
        return projected
    }

    func insert(_ note: Note) throws {
        guard notes[note.id] == nil else {
            throw StorageError.constraintViolated(
                "a note with id \(note.id) already exists"
            )
        }
        notes[note.id] = note
        touchedNotes.insert(note.id)
    }

    func update(_ note: Note) throws {
        guard notes[note.id] != nil, noteTombstones[note.id] == nil else {
            throw StorageError.notFound
        }
        notes[note.id] = note
        touchedNotes.insert(note.id)
    }

    func markNoteDeleted(_ id: NoteID, at date: Date) throws {
        guard notes[id] != nil, noteTombstones[id] == nil else {
            throw StorageError.notFound
        }
        noteTombstones[id] = date
        indexed[id] = nil
        touchedNotes.insert(id)
    }

    // MARK: Notebooks

    func notebook(_ id: NotebookID) -> Notebook? {
        notebookTombstones[id] == nil ? notebooks[id] : nil
    }

    func liveNotebooks() -> [Notebook] {
        notebooks.values
            .filter { notebookTombstones[$0.id] == nil }
            .sorted(by: Notebook.orderedBySiblingPosition)
    }

    func notebook(named name: String) -> Notebook? {
        liveNotebooks().first { $0.name.lowercased() == name.lowercased() }
    }

    func siblingCount(under parent: NotebookID?) -> Int {
        liveNotebooks().count { $0.parentID == parent }
    }

    func defaultNotebook() throws -> Notebook {
        if let seeded = notebook(DefaultNotebook.identifier) { return seeded }
        guard let candidate = liveNotebooks().first(where: \.isTopLevel) else {
            throw StorageError.corrupted("the store has no notebooks")
        }
        return candidate
    }

    func insert(_ notebook: Notebook) throws {
        guard notebooks[notebook.id] == nil else {
            throw StorageError.constraintViolated(
                "a notebook with id \(notebook.id) already exists"
            )
        }
        try assertNoCycle(from: notebook.parentID, adding: notebook.id)
        notebooks[notebook.id] = notebook
        touchedNotebooks.insert(notebook.id)
    }

    func update(_ notebook: Notebook) throws {
        guard notebooks[notebook.id] != nil,
              notebookTombstones[notebook.id] == nil else {
            throw StorageError.notFound
        }
        try assertNoCycle(from: notebook.parentID, adding: notebook.id)
        notebooks[notebook.id] = notebook
        touchedNotebooks.insert(notebook.id)
    }

    func markNotebookDeleted(_ id: NotebookID, at date: Date) throws {
        guard notebooks[id] != nil, notebookTombstones[id] == nil else {
            throw StorageError.notFound
        }
        notebookTombstones[id] = date
        touchedNotebooks.insert(id)
    }

    /// Walking up from `parent` must never arrive back at `id`.
    ///
    /// SQLite's foreign key cannot express this — a cycle is a perfectly valid
    /// set of references — so both stores check it the same way.
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
            cursor = notebooks[current]?.parentID
        }
    }

    /// Applies a filter.
    ///
    /// The structural fields come from `NoteFilter.matchesFields(of:)` — the
    /// domain's own definition, so this cannot drift from what the SQL
    /// compiler is checked against. Text goes through `SearchText`, which
    /// mirrors FTS5.
    func notes(matching filter: NoteFilter) -> [Note] {
        let terms = filter.requiresTextSearch
            ? SearchText.terms(in: filter.text ?? "")
            : []

        return liveNotes().filter { note in
            guard filter.matchesFields(of: note) else { return false }
            guard !terms.isEmpty else { return true }
            guard let haystack = indexed[note.id] else { return false }
            return SearchText.matches(terms, in: haystack)
        }
    }

    // MARK: Tags

    func tag(_ id: TagID) -> Tag? {
        tagTombstones[id] == nil ? tags[id] : nil
    }

    func liveTags() -> [Tag] {
        tags.values
            .filter { tagTombstones[$0.id] == nil }
            .sorted { $0.label < $1.label }
    }

    func upsert(_ tag: Tag) {
        // Re-using a tombstoned tag revives it, as in SQLite.
        tagTombstones[tag.id] = nil
        tags[tag.id] = tag
        touchedTags.insert(tag.id)
    }

    func markTagDeleted(_ id: TagID, at date: Date) throws {
        guard tags[id] != nil, tagTombstones[id] == nil else {
            throw StorageError.notFound
        }
        tagTombstones[id] = date
        touchedTags.insert(id)
    }

    // MARK: Index

    func index(_ note: Note) {
        indexed[note.id] = SearchText.fold(
            "\(note.plainTitle)\n\(note.plainBody)"
        )
    }

    func removeFromIndex(_ id: NoteID) {
        indexed[id] = nil
    }

    func matches(_ text: String, limit: Int) -> [NoteID] {
        let terms = SearchText.terms(in: text)
        guard !terms.isEmpty, limit > 0 else { return [] }
        return liveNotes()
            .filter { note in
                guard let haystack = indexed[note.id] else { return false }
                return SearchText.matches(terms, in: haystack)
            }
            .prefix(limit)
            .map(\.id)
    }

    func rebuildIndex() {
        indexed = [:]
        for note in liveNotes() { index(note) }
    }

    // MARK: Journal

    func record(_ draft: JournalDraft) -> JournalEntry {
        sequence += 1
        let entry = JournalEntry(
            id: UUID(),
            sequence: sequence,
            subject: draft.subject,
            operation: draft.operation,
            payload: draft.payload,
            recordedAt: draft.recordedAt
        )
        journal.append(entry)
        return entry
    }

    func pending(limit: Int) -> [JournalEntry] {
        guard limit > 0 else { return [] }
        return journal.sorted { $0.sequence < $1.sequence }
            .prefix(limit)
            .map { $0 }
    }

    func clear(_ ids: [JournalEntry.ID]) {
        let removed = Set(ids)
        journal.removeAll { removed.contains($0.id) }
    }
}
