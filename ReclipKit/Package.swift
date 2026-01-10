// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ReclipKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ReclipCore",
            targets: ["ReclipCore"]
        ),
        .library(
            name: "ReclipASR",
            targets: ["ReclipASR"]
        ),
        .library(
            name: "ReclipLLM",
            targets: ["ReclipLLM"]
        ),
    ],
    dependencies: [
        // ASR - WhisperKit
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),

        // LLM - Ollama (macOS only)
        .package(url: "https://github.com/mattt/ollama-swift.git", from: "0.4.0"),

        // LLM - Claude API
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic.git", from: "1.9.0"),
    ],
    targets: [
        // Core library - shared logic
        .target(
            name: "ReclipCore",
            dependencies: []
        ),

        // ASR providers
        .target(
            name: "ReclipASR",
            dependencies: [
                "ReclipCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),

        // LLM providers
        .target(
            name: "ReclipLLM",
            dependencies: [
                "ReclipCore",
                .product(name: "Ollama", package: "ollama-swift"),
                .product(name: "SwiftAnthropic", package: "SwiftAnthropic"),
            ]
        ),

        // Tests
        .testTarget(
            name: "ReclipCoreTests",
            dependencies: ["ReclipCore"]
        ),
    ]
)
