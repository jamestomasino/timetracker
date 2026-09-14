// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimeTracker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TimeTrackerCore", targets: ["TimeTrackerCore"]),
        .executable(name: "TimeTracker", targets: ["TimeTrackerApp"])
    ],
    targets: [
        // Pure, AppKit-free core: model, engine, persistence, CSV, view model.
        .target(
            name: "TimeTrackerCore",
            path: "Sources/Core"
        ),
        // The SwiftUI/AppKit shell (window + menu bar).
        .executableTarget(
            name: "TimeTrackerApp",
            dependencies: ["TimeTrackerCore"],
            path: "Sources/App"
        ),
        // The assertion-based test harness.
        .executableTarget(
            name: "TimeTrackerTests",
            dependencies: ["TimeTrackerCore"],
            path: "Tests"
        )
    ]
)
