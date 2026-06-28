// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SitRight",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SitRight", targets: ["SitRight"])
    ],
    targets: [
        .executableTarget(
            name: "SitRight",
            path: "Sources"
        ),
        .testTarget(
            name: "SitRightTests",
            dependencies: ["SitRight"],
            path: "Tests"
        )
    ]
)
