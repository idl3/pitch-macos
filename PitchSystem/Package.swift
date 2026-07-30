// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PitchSystem",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PitchSystem", targets: ["PitchSystem"])
    ],
    targets: [
        .target(
            name: "TPCircularBuffer",
            path: "Sources/TPCircularBuffer",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("include")]
        ),
        .executableTarget(
            name: "PitchSystem",
            dependencies: ["TPCircularBuffer"],
            path: "Sources/PitchSystem",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
