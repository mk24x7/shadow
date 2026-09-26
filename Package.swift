// swift-tools-version: 5.9
import PackageDescription

// The CLI target is `shadow` and the app target is `ShadowApp`: macOS volumes
// are case-insensitive by default, so `shadow` and `Shadow` would collide in
// .build and in Sources. build.sh renames the app binary to Shadow inside
// Shadow.app.
let package = Package(
    name: "Shadow",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ShadowCore", targets: ["ShadowCore"]),
        .executable(name: "shadow", targets: ["shadow"]),
        .executable(name: "ShadowApp", targets: ["ShadowApp"]),
    ],
    targets: [
        .target(
            name: "ShadowCore",
            path: "Sources/ShadowCore"
        ),
        .executableTarget(
            name: "shadow",
            dependencies: ["ShadowCore"],
            path: "Sources/ShadowCLI"
        ),
        .executableTarget(
            name: "ShadowApp",
            dependencies: ["ShadowCore"],
            path: "Sources/ShadowApp"
        ),
        .testTarget(
            name: "ShadowCoreTests",
            dependencies: ["ShadowCore"],
            path: "Tests/ShadowCoreTests"
        ),
    ]
)
