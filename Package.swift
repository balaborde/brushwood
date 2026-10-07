// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Brushwood",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Brushwood", targets: ["Brushwood"]),
        .library(name: "BrushwoodCore", targets: ["BrushwoodCore"]),
    ],
    targets: [
        .target(
            name: "BrushwoodCore",
            path: "Sources/BrushwoodCore",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .executableTarget(
            name: "Brushwood",
            dependencies: ["BrushwoodCore"],
            path: "Sources/Brushwood"
        ),
        // Run with `swift run -c release selftest` (swift-testing requires a full Xcode install).
        .executableTarget(
            name: "selftest",
            dependencies: ["BrushwoodCore"],
            path: "Tests/SelfTest"
        ),
    ]
)
