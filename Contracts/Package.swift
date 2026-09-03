// swift-tools-version: 6.4
import PackageDescription

// ⚠️ A separate package, not a target of the root one, and that is the whole
// point of it existing.
//
// Within a single package SwiftPM links target dependencies **statically**, so
// while `StorageContracts` was a target here, `ColdStorage.framework` compiled
// a private copy of it — 268 symbols, measured. Ship that alongside a separate
// `StorageContracts.xcframework` and there are two copies of the module at
// runtime, with two distinct type identities. `catch let error as StorageError`
// in SparrowKit then silently fails to match an error thrown inside
// ColdStorage, which broke the layering test and the daily-note concurrency
// recovery.
//
// Being its own package makes ColdStorage link it dynamically. One copy, one
// type identity.
let package = Package(
    name: "StorageContracts",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "StorageContracts", type: .dynamic, targets: ["StorageContracts"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ksypSparrow/sparrow-domain",
            .upToNextMajor(from: "2.0.0")
        ),
    ],
    targets: [
        .target(name: "StorageContracts", dependencies: [
            .product(name: "SparrowDomain", package: "sparrow-domain"),
        ]),
    ]
)
