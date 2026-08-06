// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tonos",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tonos", targets: ["Tonos"])
    ],
    dependencies: [
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess.git", from: "1.3.0")
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
            dependencies: ["TPCircularBuffer", .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess")],
            path: "Sources/PitchSystem",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
