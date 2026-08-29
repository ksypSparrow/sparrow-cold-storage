# Changelog

All notable changes to `SparrowColdStorage`. Two products: `StorageContracts`
(what the service layer is allowed to ask for) and `ColdStorage` (the
implementation, almost entirely `internal`).

Pre-1.0, **the minor is the breaking bump**. Dependents pin with
`.upToNextMinor(from:)`.

## [Unreleased]

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
