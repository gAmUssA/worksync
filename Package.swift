// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "worksync",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "worksync", targets: ["worksync"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
    ],
    targets: [
        // Pure logic: config, planner, markers. No EventKit/AppKit imports allowed.
        .target(
            name: "WorkSyncCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        // EventKit adapter behind the CalendarStore protocol.
        .target(
            name: "WorkSyncKit",
            dependencies: ["WorkSyncCore"]
        ),
        // Executable: CLI entry + menu bar mode.
        .executableTarget(
            name: "worksync",
            dependencies: [
                "WorkSyncCore",
                "WorkSyncKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "WorkSyncCoreTests",
            dependencies: ["WorkSyncCore"]
        ),
        // The menu bar model, tested against the real thing. Importing an
        // executable target works on this toolchain and on CI (macos-15, Swift
        // 6.1.2) with `main` not running — see docs/testing-menubar.md.
        .testTarget(
            name: "WorkSyncAppTests",
            dependencies: ["worksync", "WorkSyncCore"]
        ),
    ]
)
