// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Logilights",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Protocol encoding + HID access, shared by the menu bar app and
        // the CLI test tool.
        .target(
            name: "LogilightsCore",
            path: "Sources/LogilightsCore"
        ),
        // The menu bar app.
        .executableTarget(
            name: "Logilights",
            dependencies: ["LogilightsCore"],
            path: "Sources/Logilights"
        ),
        // Hardware test/diagnostics tool: lists devices and sets colors
        // directly, printing the IOReturn of every report.
        .executableTarget(
            name: "LogilightsCLI",
            dependencies: ["LogilightsCore"],
            path: "Sources/LogilightsCLI"
        ),
        .testTarget(
            name: "LogilightsTests",
            dependencies: ["LogilightsCore"],
            path: "Tests/LogilightsTests"
        )
    ]
)
