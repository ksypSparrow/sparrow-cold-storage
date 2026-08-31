import Foundation
import SparrowDomain
import StorageContracts

/// The whole of wave 0's persistence: dictionaries behind an actor.
///
/// It exists to prove the shape of the contracts against a real caller before
/// SQLite arrives in 0.2.0. Every behaviour the protocols promise is
/// implemented here — tombstones, an index, a journal, rollback and
/// post-commit change events — so that `.inMemory()` and `.make(at:)` can be
/// held to the same tests later.
actor InMemoryStore {
    private var notes: [NoteID: Note] = [:]
    private var notebooks: [NotebookID: Notebook]
    private var tombstones: [NoteID: Date] = [:]
    private var indexed: [NoteID: String] = [:]
    private var journal: [JournalEntry] = []
    private var sequence: Int64 = 0

    private let writeLock = AsyncLock()
    private let broadcaster: ChangeBroadcaster
    private var snapshot: Snapshot?
    private var touched: Set<NoteID> = []

    init(broadcaster: ChangeBroadcaster, seededAt date: Date = Date()) {
        self.broadcaster = broadcaster
        // Seeded exactly as migration v1 seeds the SQLite store, so
        // `.inMemory()` and `.make(at:)` answer `defaultNotebook()` alike.
        let seed = DefaultNotebook.make(at: date)
        self.notebooks = [seed.id: seed]
    }

    // MARK: Notebooks

    func notebook(_ id: NotebookID) -> Notebook? {
        notebooks[id]
    }

    func allNotebooks() -> [Notebook] {
        notebooks.values.sorted(by: Notebook.orderedBySiblingPosition)
    }

    func notebook(named name: String) -> Notebook? {
        notebooks.values
            .filter { $0.name.lowercased() == name.lowercased() }
            .min(by: Notebook.orderedBySiblingPosition)
    }

    func defaultNotebook() throws -> Notebook {
        if let seeded = notebooks[DefaultNotebook.identifier] {
            return seeded
        }
        guard let candidate = notebooks.values
            .filter(\.isTopLevel)
            .min(by: Notebook.orderedBySiblingPosition)
        else {
            throw StorageError.corrupted("the store has no notebooks")
        }
        return candidate
    }

    private struct Snapshot {
        let notes: [NoteID: Note]
        let notebooks: [NotebookID: Notebook]
        let tombstones: [NoteID: Date]
        let indexed: [NoteID: String]
        let journal: [JournalEntry]
        let sequence: Int64
    }

    // MARK: Reading

    func note(_ id: NoteID) -> Note? {
        tombstones[id] == nil ? notes[id] : nil
    }

    func notes(_ ids: [NoteID]) -> [Note] {
        ids.compactMap { note($0) }
    }

    func recentNotes(limit: Int) -> [Note] {
        guard limit > 0 else { return [] }
        return notes.values
            .filter { tombstones[$0.id] == nil }
            .sorted { ($0.updatedAt, $0.id.value.uuidString) > ($1.updatedAt, $1.id.value.uuidString) }
            .prefix(limit)
            .map { $0 }
    }

    func count() -> Int {
        notes.keys.count { tombstones[$0] == nil }
    }

    // MARK: Writing

    func insert(_ note: Note) throws {
        guard notes[note.id] == nil else {
            throw StorageError.constraintViolated(
                "a note with id \(note.id) already exists"
            )
        }
        notes[note.id] = note
        touched.insert(note.id)
    }

    func update(_ note: Note) throws {
        guard notes[note.id] != nil, tombstones[note.id] == nil else {
            throw StorageError.notFound
        }
        notes[note.id] = note
        touched.insert(note.id)
    }

    func markDeleted(_ id: NoteID, at date: Date) throws {
        guard notes[id] != nil, tombstones[id] == nil else {
            throw StorageError.notFound
        }
        tombstones[id] = date
        indexed[id] = nil
        touched.insert(id)
    }

    // MARK: Index

    func index(_ note: Note) {
        indexed[note.id] = "\(note.title)\n\(note.body)".lowercased()
    }

    func removeFromIndex(_ id: NoteID) {
        indexed[id] = nil
    }

    func matches(_ text: String, limit: Int) -> [NoteID] {
        let needle = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty, limit > 0 else { return [] }
        return indexed
            .filter { $0.value.contains(needle) && tombstones[$0.key] == nil }
            .compactMap { notes[$0.key] }
            .sorted { ($0.updatedAt, $0.id.value.uuidString) > ($1.updatedAt, $1.id.value.uuidString) }
            .prefix(limit)
            .map(\.id)
    }

    func rebuildIndex() {
        indexed = [:]
        for note in notes.values where tombstones[note.id] == nil {
            index(note)
        }
    }

    // MARK: Journal

    func nextSequence() -> Int64 {
        sequence += 1
        return sequence
    }

    func record(_ entry: JournalEntry) {
        journal.append(entry)
    }

    func pending(limit: Int) -> [JournalEntry] {
        guard limit > 0 else { return [] }
        return journal.sorted { $0.sequence < $1.sequence }.prefix(limit).map { $0 }
    }

    func clear(_ ids: [JournalEntry.ID]) {
        let removed = Set(ids)
        journal.removeAll { removed.contains($0.id) }
    }

    // MARK: Transactions

    func begin() async {
        await writeLock.acquire()
        snapshot = Snapshot(
            notes: notes,
            notebooks: notebooks,
            tombstones: tombstones,
            indexed: indexed,
            journal: journal,
            sequence: sequence
        )
        touched = []
    }

    func commit() async {
        let changed = touched
        snapshot = nil
        touched = []
        await writeLock.release()
        guard !changed.isEmpty else { return }
        broadcaster.publish(.notes(Array(changed)))
    }

    func rollback() async {
        if let snapshot {
            notes = snapshot.notes
            notebooks = snapshot.notebooks
            tombstones = snapshot.tombstones
            indexed = snapshot.indexed
            journal = snapshot.journal
            sequence = snapshot.sequence
        }
        snapshot = nil
        touched = []
        await writeLock.release()
    }

}
