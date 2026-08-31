# Changelog

All notable changes to `SparrowColdStorage`. Two products: `StorageContracts`
(what the service layer is allowed to ask for) and `ColdStorage` (the
implementation, almost entirely `internal`).

Pre-1.0, **the minor is the breaking bump**. Dependents pin with
`.upToNextMinor(from:)`.

## [Unreleased]

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
