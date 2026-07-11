// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Stayput",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StayputCore", targets: ["StayputCore"]),
        .executable(name: "Stayput", targets: ["Stayput"]),
    ],
    targets: [
        .target(name: "StayputCore"),
        .executableTarget(
            name: "Stayput",
            dependencies: ["StayputCore"]
        ),
        .testTarget(
            name: "StayputCoreTests",
            dependencies: ["StayputCore"]
        ),
    ]
)
