// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SparrowColdStorage",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "ColdStorage", type: .dynamic, targets: ["ColdStorage"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ksypSparrow/sparrow-domain",
            // ⚠️ 1.1.0 minimum: that is where the domain product became
            // `.dynamic`. Against a static one, ColdStorage.framework
            // statically swallows the domain types instead of linking them.
            .upToNextMajor(from: "1.1.0")
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift",
            .upToNextMinor(from: "7.11.0")
        ),
        // ⚠️ Its own package so `ColdStorage` links it dynamically. As a target
        // here it was statically swallowed — see Contracts/Package.swift.
        .package(path: "Contracts"),
    ],
    targets: [
        .target(name: "ColdStorage", dependencies: [
            .product(name: "StorageContracts", package: "Contracts"),
            .product(name: "SparrowDomain", package: "sparrow-domain"),
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .testTarget(name: "ColdStorageTests", dependencies: [
            "ColdStorage",
            .product(name: "StorageContracts", package: "Contracts"),
        ]),
    ]
)
