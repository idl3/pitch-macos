// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tonos",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tonos", targets: ["Tonos"])
    ],
    targets: [
        .target(
            name: "TPCircularBuffer",
            path: "Sources/TPCircularBuffer",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("include")]
        ),
        .executableTarget(
            name: "Tonos",
            dependencies: ["TPCircularBuffer"],
            path: "Sources/PitchSystem",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
