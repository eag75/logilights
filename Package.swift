// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Logilights",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Logilights",
            path: "Sources/Logilights"
        ),
        .testTarget(
            name: "LogilightsTests",
            dependencies: ["Logilights"],
            path: "Tests/LogilightsTests"
        )
    ]
)
