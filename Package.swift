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
            .upToNextMinor(from: "0.1.0")
        ),
    ],
    targets: [
        .target(name: "StorageContracts", dependencies: [
            .product(name: "SparrowDomain", package: "sparrow-domain"),
        ]),
        .target(name: "ColdStorage", dependencies: ["StorageContracts"]),
        .testTarget(name: "ColdStorageTests", dependencies: [
            "ColdStorage",
            "StorageContracts",
        ]),
    ]
)
