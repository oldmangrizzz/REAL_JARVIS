// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrizzOS",
    platforms: [
        .iOS(.v17), .macOS(.v14), .visionOS(.v1), .watchOS(.v10), .tvOS(.v17)
    ],
    products: [
        .library(name: "GrizzOS", targets: ["GrizzOS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "GrizzOS",
            dependencies: [
                .product(name: "LiveKit", package: "client-sdk-swift")
            ],
            path: "Sources/GrizzOS"
        )
    ]
)