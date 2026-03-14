// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Subscription",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1),
        .macCatalyst(.v17),
    ],
    products: [
        .library(
            name: "Subscription",
            targets: ["Subscription"]),
    ],
    dependencies: [
        .package(path: "../Services"),
    ],
    targets: [
        .target(
            name: "Subscription",
            dependencies: [
                .product(name: "MemosV1Service", package: "Services"),
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]),
    ]
)
