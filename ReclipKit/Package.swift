// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ReclipKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
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
        .library(
            name: "ReclipUI",
            targets: ["ReclipUI"]
        ),
    ],
    dependencies: [
        // ASR - WhisperKit (v0.15.0 - Nov 2025)
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0"),

        // LLM - Ollama (v1.8.0 - Jun 2025, macOS only)
        .package(url: "https://github.com/mattt/ollama-swift.git", from: "1.8.0"),

        // LLM - Claude API (v2.2.0 - Oct 2025, Skills API support)
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic.git", from: "2.2.0"),
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

        // UI components (SwiftUI + Liquid Glass)
        .target(
            name: "ReclipUI",
            dependencies: ["ReclipCore"]
        ),

        // Tests
        .testTarget(
            name: "ReclipCoreTests",
            dependencies: ["ReclipCore"]
        ),
    ]
)
