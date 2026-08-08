// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WindowCRTLens",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WindowCRTLensCore", targets: ["WindowCRTLensCore"]),
        .executable(name: "WindowCRTLens", targets: ["WindowCRTLens"]),
    ],
    targets: [
        .target(
            name: "WindowCRTLensCore",
            path: "Sources/WindowCRTLensCore"
        ),
        .executableTarget(
            name: "WindowCRTLens",
            dependencies: ["WindowCRTLensCore"],
            path: "Sources/WindowCRTLensApp"
        ),
        .testTarget(
            name: "WindowCRTLensCoreTests",
            dependencies: ["WindowCRTLensCore"],
            path: "Tests/WindowCRTLensCoreTests"
        ),
    ]
)
