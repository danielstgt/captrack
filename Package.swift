// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "CapTrack",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CapTrack",
            path: "Sources/CapTrack",
            swiftSettings: [
                // UI app: everything is main-actor by default unless marked nonisolated.
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "CapTrackTests",
            dependencies: ["CapTrack"],
            path: "Tests/CapTrackTests",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
