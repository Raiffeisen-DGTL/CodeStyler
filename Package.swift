// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodeStyler",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "CodeStyler",
            targets: ["CodeStyler"]),
        .library(
            name: "CodeStylerSwiftUI",
            targets: ["CodeStylerSwiftUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/Raiffeisen-DGTL/raifmagiccore.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/Raiffeisen-DGTL/MagicDesign.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/Raiffeisen-DGTL/CommandExecutor.git", .upToNextMajor(from: "1.0.0"))
    ],
    targets: [
        .target(
            name: "CodeStyler",
            dependencies: [
                .product(name: "RaifMagicCore", package: "RaifMagicCore"),
                .product(name: "CommandExecutor", package: "CommandExecutor")
            ],
            path: "Sources/Service"
        ),
        .target(
            name: "CodeStylerSwiftUI",
            dependencies: [
                "CodeStyler",
                .product(name: "MagicDesign", package: "MagicDesign")
            ],
            path: "Sources/SwiftUI"
        )
    ]
)
