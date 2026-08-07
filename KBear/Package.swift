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
        .target(
            name: "KBearLib",
            dependencies: ["TPCircularBuffer"],
            path: "Sources/KBearLib",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "KBear",
            dependencies: ["KBearLib"],
            path: "Sources/KBear"
        ),
        .testTarget(
            name: "KBearTests",
            dependencies: ["KBearLib"],
            path: "Tests/KBearTests"
        )
    ]
)
