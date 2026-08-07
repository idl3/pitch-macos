// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KBear",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KBear", targets: ["KBear"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TPCircularBuffer",
            path: "Sources/TPCircularBuffer",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("include")]
        ),
        .executableTarget(
            name: "KBear",
            dependencies: ["TPCircularBuffer"],
            path: "Sources/PitchSystem",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
