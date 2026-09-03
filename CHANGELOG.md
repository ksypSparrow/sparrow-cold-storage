# Changelog

All notable changes to `SparrowColdStorage`. Two products: `StorageContracts`
(what the service layer is allowed to ask for) and `ColdStorage` (the
implementation, almost entirely `internal`).

Pre-1.0, **the minor is the breaking bump**. Dependents pin with
`.upToNextMinor(from:)`.

## [Unreleased]

## [1.0.0] — wave 12 · stable

Requires **SparrowDomain 1.0.0**, pinned `.upToNextMajor` — after a
compatibility promise, the major is the breaking bump.

### The public surface, entire

```swift
public enum ColdStorage {
    public static func inMemory() throws -> StorageSet
    public static func make(at url: URL) throws -> StorageSet
}

public struct StorageSet: Sendable {
    public let notes: any NoteReading
    public let notebooks: any NotebookReading
    public let tags: any TagReading
    public let search: any SearchIndexing
    public let journal: any ChangeJournaling
    public let transactions: any TransactionRunning
    public let observer: any StorageObserving
}
```

Plus `StorageError` and the contracts. **Every implementation type is
`internal`** — a composition root cannot name `SQLiteNoteRepository`, and there
is no public path to a write that skips a transaction.

### Added — a migration the review found

**`v6_daily_day_from_observed`.**

⚠️ v5's backfill read `created_at`, while `NoteRow` has always written `day`
from `happenedAt` — which prefers `observed_at`. **Two definitions of "which
day", disagreeing:** a daily entry written at 00:30 about yesterday landed on
today if it was migrated and on yesterday if it was saved fresh.

v5 is not edited — a device that already ran it has the old keys, and rewriting
v5 would never reach that device. v6 corrects them and v5 stays as it shipped.

🧪 **Found by the new v1→v5 chain test**, not by the per-migration ones. Those
open a *current* database and check one step; only a database carrying data
from before a migration can show that the migration and the writer disagree.

### Added — the chain tests

Migrations are now tested against databases built at **older schemas**:
v1 → v5 for a notebook, v2 → v6 for a note, v4 → v6 for tags.

Historical rows are written with raw SQL, because a record type describes the
schema as it is *today* — inserting a `NoteRow` into a v2 database fails with
*"table note has no column named day"*.

### What this release promises

- **Two stores, one test suite.** Every behavioural test runs against
  `.inMemory()` and `.make(at:)` both. That discipline caught three real
  divergences across the waves.
- **Migrations are append-only.** v6 exists rather than v5 being corrected.
- **GRDB appears in four files**, all under `Sources/ColdStorage/SQLite/`, and
  in no other repository.

## [0.8.0] — wave 7 · daily notes

**No domain change.** `NoteKind.daily` has existed since domain 0.4.0, so
`sparrow-domain` ships nothing this wave and does not tag — the second dash in
its column.

### Added

- `NoteReading.dailyNote(on:)` — a calendar-day query.
- `Migrations.v5_daily_unique` — a `day` column and a **partial unique index**
  on it, for `kind = 'daily'` and live rows only.
- `DayKey` — the one definition of which calendar day a date belongs to.

### Notes

- **The day is computed at write time and stored.** A day is a calendar
  question, not an arithmetic one: it depends on the timezone and on daylight
  saving. Deriving it on every read would make the same note answer
  differently after a flight.
- **`happenedAt` decides the day**, so a daily entry written at 00:30 *about
  yesterday* belongs to yesterday.
- **The index excludes tombstones.** Deleting today's entry must not prevent
  writing another one.
- **The in-memory store enforces the same constraint in code.** SQLite has an
  index; memory has nothing, and the two would disagree about whether a second
  daily note is an error. Written up front this time rather than found by the
  parity suites, which have caught this shape three times.
- v5 backfills `day` before building the index, so a database that already had
  daily notes cannot fail to migrate.

## [0.7.0] — wave 6 · tags

Depends on **SparrowDomain 0.6.0**.

### Added

- `Migrations.v4_tags` — the `tag` table and the `note_tag` join.
- `TagReading` and `TagSessionAccess`; `TagRow`, `SQLiteTagRepository`,
  `SQLiteTagSession`.
- `NoteFilter.tagIDs` compiles to one `EXISTS` per tag.
- `StorageSet.tags`; `JournalEntry.Subject.tag`; `StoredChange.tags`.

### Notes

- **`note_tag` carries a `position`.** Tag order is user-visible, and a plain
  join returns rows in whatever order SQLite finds convenient — a note whose
  tags reshuffle between reads looks like a bug in the view that drew it.
- ⚠️ **One `EXISTS` per tag, not `tag_id IN (…)`.** `IN` matches a note
  carrying *any* of them; `NoteFilter.tagIDs` requires *all* of them. The
  difference is silent: the query runs and returns too much.
- **`upsert`, not `insert`.** Tags arrive by being used — someone types
  `#wetlands` on a note — so there is no separate create step to fail on a
  duplicate. Re-using a tombstoned tag revives it, because typing it again
  means *the* tag.
- **Deleting a tag leaves the `note_tag` rows.** A tombstoned tag disappears
  from reads because they join through `tag`, but the link survives — so
  reviving the tag restores it, and V2 merging a delete-here/keep-there does
  not have to invent the association again.
- Tags are fetched for a page of notes in **one** extra query, not one per
  note.

### The parity gate, a third time

`Deleting a tag leaves its notes intact` and `A tombstoned tag matches nothing`
passed on `.make(at:)` and failed on `.inMemory()`. SQLite hides a deleted tag
for free — reads join through `tag`, which filters tombstones. In memory the
identifiers live on the note value, so nothing filtered them. The in-memory
store now projects a note's tags through the live set.

## [0.6.0] — wave 5 · filter compiler

Depends on **SparrowDomain 0.5.0**.

### Added

- `FilterCompiler` — `NoteFilter` → bound SQL, plus the ORDER BY.
- `NoteReading.notes(matching:sort:limit:)` and `count(matching:)`.
- `NoteReading.count()` is now a protocol extension over `count(matching: .all)`.

### Notes

- **Never string-interpolate a value.** Every value becomes a `?` with an
  argument beside it — a filter is built from whatever a Shortcut passed in,
  and one interpolated quote is the whole class of bug. Tests run `'; DROP
  TABLE note; --` against a real database and check the table survives.
- **An empty `kinds` set compiles to no clause at all.** The natural
  translation, `IN ()`, is both invalid SQLite and the opposite of what the
  filter means.
- **One statement, not two.** The plan describes running FTS first and
  intersecting; a join does the same thing and is strictly better — the LIMIT
  applies after *both* filters, so a text search matching ten thousand notes
  does not materialise ten thousand identifiers to return twenty.
- **A filter with no text never touches the index.** Proved by dropping the FTS
  table and running the query anyway.
- The ORDER BY reproduces `NoteSort.orders(_:before:)` exactly, tiebreak
  included. The sorting test compares SQL output against the domain's own
  ordering rather than a hand-written expectation, which is what stops the two
  definitions drifting.
- The in-memory store evaluates the same filter through
  `NoteFilter.matchesFields(of:)`, so both stores share one definition of the
  structural fields.

## [0.5.0] — wave 4 · full-text search

**No domain change.** `search` takes a `String` and returns `[Note]`, both of
which already existed — so `sparrow-domain` ships nothing this wave, and does
not tag.

### Added

- `Migrations.v3_fts` — a **standalone** FTS5 table with
  `tokenize = 'unicode61 remove_diacritics 2'`, which is what makes `"heron"`
  match `"Herón"` (**FR-1.3**).
- `SQLiteIndexSession` (inside a transaction) and `SQLiteSearchIndex`
  (outside one).
- `FTSQuery` — turns typed input into something `MATCH` will accept.

### Changed

- `search.matches` no longer throws `.unavailable`. `DiscardingIndexSession` is
  gone; index writes now land in FTS5.
- **The in-memory matcher was rewritten to match FTS5's semantics.**

### Notes

- **Standalone, not external-content.** External content needs an INTEGER
  rowid join, the awkward `INSERT INTO fts(fts, rowid, …) VALUES('delete', …)`
  form, and triggers to stay in step. Duplicating tens of kilobytes per
  thousand notes buys an index that cannot drift.
- **v3 builds the index from notes already on disk.** 0.4.0 accepted index
  writes and discarded them; this is the other half of that promise, so
  nothing had to be remembered in between.
- **Raw input never reaches `MATCH`.** FTS5 has its own query syntax, so every
  term is quoted — an apostrophe or a bare `AND` would change the meaning of a
  search or make it throw. Every term also gets a `*`, so search-as-you-type
  finds a note before the word is finished.
- Results are **newest first**, in both stores. For field notes the most recent
  sighting is usually the wanted one; bm25 relevance is a later choice.

### The parity gate earned its place

Four search tests failed on `.inMemory()` and passed on `.make(at:)`. The
naive substring matcher had no diacritic folding, no term ANDing and no prefix
matching — it had passed every test that only ever ran against it. A test
double weaker than the real thing is worse than none, because it makes the
layer above look correct. `SearchText` now mirrors FTS5 deliberately.

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
