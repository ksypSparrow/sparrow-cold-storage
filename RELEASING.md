# Releasing SparrowColdStorage

The middle of the diamond: waits on `sparrow-domain`, blocks `sparrow-kit`.

## The ritual

```
   1  bump domain in Package.swift, if the wave requires it
   2  swift package resolve
   3  implement · swift test
   4  CHANGELOG.md entry naming the wave
   5  git tag vX.Y.Z && git push --tags
   6  notify: sparrow-kit
```

## Gate for every release

```
   ✓  swift build && swift test
   ✓  swift build -Xswiftc -strict-concurrency=complete
   ✓  xcodebuild -scheme SparrowColdStorage-Package \
        -destination 'generic/platform=iOS'
   ✓  no implementation type is public:
        grep -rn "^public" Sources/ColdStorage/
        → only ColdStorage and StorageSet
   ✓  .inMemory() and .make(at:) pass the same tests
```

The third check is the one that decays quietly. A `public` slipped onto a
repository is invisible in review and permanently reachable afterwards.

## Standing rules

| | |
|---|---|
| Public surface | `ColdStorage.make(at:)`, `.inMemory()`, `StorageSet`, `StorageError` |
| Migrations | Append-only. A shipped migration is never edited |
| Writes | Reachable only inside `write { }` |
| Change events | Published **after** COMMIT, never inside |
| GRDB | Confined to this package. It appears nowhere else in the project |

**Never re-tag.** SwiftPM caches by tag.

## Waves that wait on nothing

0.5.0 (full-text search) and 0.8.0 (daily notes) need no upstream release —
they are pure storage work and can start as soon as the previous wave's app
milestone is done.
