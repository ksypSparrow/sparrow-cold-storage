// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SparrowColdStorage",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "StorageContracts", targets: ["StorageContracts"]),
        .library(name: "ColdStorage", targets: ["ColdStorage"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ksypSparrow/sparrow-domain",
            // ⚠️ `.upToNextMajor` now that domain is 1.0.0 — after a
            // compatibility promise, the major is the breaking bump.
            .upToNextMajor(from: "1.0.0")
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift",
            .upToNextMinor(from: "7.11.0")
        ),
    ],
    targets: [
        .target(name: "StorageContracts", dependencies: [
            .product(name: "SparrowDomain", package: "sparrow-domain"),
        ]),
        .target(name: "ColdStorage", dependencies: [
            "StorageContracts",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .testTarget(name: "ColdStorageTests", dependencies: [
            "ColdStorage",
            "StorageContracts",
        ]),
    ]
)
