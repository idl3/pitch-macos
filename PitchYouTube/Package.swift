// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PitchYouTube",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PitchYouTube", targets: ["PitchYouTube"])
    ],
    targets: [
        .executableTarget(
            name: "PitchYouTube",
            path: "Sources/PitchYouTube",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
