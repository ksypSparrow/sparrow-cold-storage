# Changelog

All notable changes to `SparrowColdStorage`. Two products: `StorageContracts`
(what the service layer is allowed to ask for) and `ColdStorage` (the
implementation, almost entirely `internal`).

Pre-1.0, **the minor is the breaking bump**. Dependents pin with
`.upToNextMinor(from:)`.

## [Unreleased]

## [0.4.0] — wave 3 · note storage

Depends on **SparrowDomain 0.4.0**. Notes finally persist.

### Added

- `Migrations.v2_note` — the `note` table, a foreign key to `notebook`, and
  indexes on `(notebook_id, updated_at)` and `(kind, updated_at)`.
- `NoteRow`, `SQLiteNoteRepository`, `SQLiteNoteSession`.

### Changed

- **`make(at:)` no longer touches the in-memory store.** Notes, notebooks and
  the journal are all SQLite now. The half-persistent state introduced in 0.2.0
  is over.
- `UnavailableNoteSession` is gone.

### Notes

- **No `RichTextCoder`.** The plan called for one to archive `AttributedString`
  into a blob. Domain 0.4.0's `RichText` already carries `plain` and
  `attributes` separately, which maps directly onto the schema's `title_data` /
  `title_plain` pair — the coder had nothing left to do.
- **A corrupt attribute blob costs formatting and nothing else.** The plan
  asked that one *throw* rather than yield an empty note; it cannot yield an
  empty note any more, because the plain text is its own column. Strictly
  better than throwing, and there is a test for it.
- Index writes inside a transaction are **accepted and discarded** until FTS5
  arrives in 0.5.0 — the text is in `note`, and 0.5.0 builds the index from
  there. Refusing them would block every note write, since a save indexes in
  the same transaction. Reading is different: `search.matches` throws
  `.unavailable` rather than answering from an index that does not exist.
- Sync columns stay on `NoteRow` and never on `Note`.

## [0.3.0] — wave 2 · transactions, journal, change events

Depends on **SparrowDomain 0.3.0**. The machinery every later write depends on.

### Changed — breaking

⚠️ **`StorageSession` is now synchronous and not `Sendable`, and
`TransactionRunning.write` takes a synchronous body.**

A GRDB `Database` belongs to one connection on one thread; GRDB's own `write`
takes a *synchronous* closure for exactly that reason. A session whose members
were `async` could not be implemented over it honestly. The synchronous body is
also the better contract — it makes it impossible to `await` a network call
while holding the write lock.

Reads outside a transaction stay `async`. Inside one, everything is sync:

| Outside | Inside `write { }` |
|---|---|
| `NoteReading` async | `NoteSessionAccess` sync |
| `NotebookReading` async | `NotebookSessionAccess` sync |
| `SearchIndexing` async | `SearchIndexWriting` sync |
| `ChangeJournaling` async | `ChangeJournalWriting` sync |

- `NoteWriting` → `NoteSessionAccess`; `SearchIndexing.index`/`remove` →
  `SearchIndexWriting`; `ChangeJournaling.record` → `ChangeJournalWriting`.
- `JournalDraft` is new, and `record` takes it. A caller no longer supplies a
  `sequence` — storage assigns it, because a caller that could choose one could
  restart at 1 and silently reorder the sync stream.
- `StorageSet` gains `search` and `journal` readers.

### Added

- `SQLiteTransactionRunner` — one GRDB transaction per `write { }`.
- `SQLiteSession`, `SQLiteNotebookSession` — notebook writes.
- `SQLiteJournalSession` / `SQLiteJournalReader` — the journal's first writer,
  with `seq` from SQLite's own counter.
- Cycle detection: a notebook cannot become its own ancestor. SQLite's foreign
  key cannot express this — a cycle is a valid set of references.
- Session invalidation: a session captured past `write { }` throws.

### Notes

- Change events are published **after** the write closure returns, which is
  after COMMIT. GRDB's `TransactionObserver.databaseDidCommit` fires while
  still inside the write barrier; publishing there would let a consumer read
  from inside the writer's critical section.
- Note storage and the index are still in memory. `SQLiteSession` returns them
  as `unavailable` rather than silently accepting a write that goes nowhere.

## [0.2.0] — wave 1 · SQLite and notebook reads

Depends on **SparrowDomain 0.2.0**. Adds the first real database.

### Added — `StorageContracts`

- `NotebookReading` — `defaultNotebook()` is deliberately not optional.
- `JournalEntry.Subject.notebook`, `StoredChange.notebooks`.

### Added — `ColdStorage`

- **GRDB 7.11**, confined to this package and to four files inside it.
- `ColdStorage.make(at:)` — opens, migrates, returns a `StorageSet`.
- `Migrations.v1_initial` — the `notebook` and `journal` tables, every V2 seam
  column, and a seeded default notebook.
- `NotebookRow`, `SQLiteNotebookRepository` (reads only), `SQLiteStorage`.
- `DefaultNotebook` — a **fixed** identifier, shared by both stores.

### Notes

- ⚠️ **`make(at:)` persists notebooks; notes are still in memory.** The `note`
  table arrives with migration v2 in 0.4.0. The signature does not change when
  it does — which is the point of returning protocols.
- The `journal` table is created in v1 although nothing writes to it until
  0.3.0. Adding a table to a shipped schema is a migration; adding it now is
  three lines.
- The V2 seam columns are on `notebook`, not on `journal`. `local_version` and
  `deleted_at` on a row of the sync log itself would be noise, and the design's
  own schema does not have them there.
- Every notebook test runs against **both** stores. The gate says they must
  behave identically, so the suites are parameterised over the pair rather than
  picking one.

## [0.1.0] — wave 0 · contracts and in-memory store

Depends on **SparrowDomain 0.1.0**. No database, and no GRDB — that arrives in
0.2.0.

### Added — `StorageContracts`

- `NoteReading` · `NoteWriting` — writes describe intent; there is no `delete`,
  only `markDeleted`.
- `SearchIndexing` · `ChangeJournaling` · `JournalEntry`
- `StorageSession` · `TransactionRunning` — writers are reachable only from
  inside a `write { }` body.
- `StorageObserving` · `StoredChange` — identifiers, never values.
- `StorageError`

### Added — `ColdStorage`

- `ColdStorage.inMemory()` and `StorageSet`. The entire public surface; every
  repository type is `internal`.
- `InMemoryStore` — an actor over dictionaries that honours the full contract:
  tombstones, rollback on a thrown error, serialised writes, and change events
  published only after a commit.

### Deferred, and why

The plan called for the whole protocol set in this release. `NotebookReading`,
`NotebookWriting`, `TagReading`, `TagWriting` and the filter-based reads name
domain types that **do not exist in SparrowDomain 0.1.0** — `Notebook` lands in
domain 0.2.0, `NoteFilter` in 0.5.0, `Tag` in 0.6.0. Each protocol arrives in
the wave that brings its types.
