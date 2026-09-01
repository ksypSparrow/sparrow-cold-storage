# SparrowColdStorage

Persistence for Sparrow FieldNotes, and the only place SQLite is allowed to
exist.

**Two products, and that split is the whole design:**

```
   StorageContracts   the abstraction   ──►  linked by SparrowKit's services
   ColdStorage        the SQLite work   ──►  linked by the app, for one call
```

`SparrowKit` links `StorageContracts` to *use* storage. Only the composition
root links `ColdStorage`, to *construct* it — and even there it cannot name a
concrete type, because the public surface is two symbols:

```swift
public enum ColdStorage {
    public static func inMemory() throws -> StorageSet
}

public struct StorageSet: Sendable {
    public let notes: any NoteReading          // a reader
    public let transactions: any TransactionRunning
    public let observer: any StorageObserving
}
```

## Writes are unreachable outside a transaction

A note must be saved, indexed and journalled together or not at all — so the
writing protocols are obtainable only from inside a `write { }` body.

```
   Outside a transaction        Inside write { session in … }
   ──────────────────────       ─────────────────────────────
   NoteReading      ✓           NoteReading       ✓
   NoteWriting      ✗           NoteWriting       ✓
                                SearchIndexing    ✓
                                ChangeJournaling  ✓
```

**"Saved but not searchable" stops being a bug you can write.** A test asserts
it at runtime: `StorageSet.notes` is a `NoteReading` that is not a
`NoteWriting`.

## There is no delete

Only `markDeleted`. Removing a row destroys the tombstone, and without a
tombstone a deleted note reappears from another device the first time V2 syncs.

## Contents

| Since | Storage | Notes |
|---|---|---|
| 0.1.0 | `InMemoryStore` | contracts, tombstones, rollback, change events |
| 0.2.0 | SQLite + GRDB | migration v1, notebook reads, seeded default |
| 0.4.0 | SQLite | migration v2, notes — everything persists |
| 0.5.0 | SQLite + FTS5 | migration v3, full-text search |
| 0.6.0 | SQLite + FTS5 | filter compiler, Find queries |
| 0.7.0 | SQLite + FTS5 | migration v4, tags |

## Build

```bash
swift build && swift test
```

Requires a Swift 6.4 toolchain. Depends on `SparrowDomain` only.

## Documents

[`contracts.md`](../01-Sparrow-FieldNotes/contracts.md) ·
[`plans/sparrow-cold-storage.md`](../01-Sparrow-FieldNotes/plans/sparrow-cold-storage.md) ·
[`RELEASING.md`](RELEASING.md)
