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
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.2"
        )
    ],
    targets: [
        .executableTarget(
            name: "SitRight",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "SitRightTests",
            dependencies: ["SitRight"],
            path: "Tests"
        )
    ]
)
