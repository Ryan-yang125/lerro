// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lerro",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "LerroCore", targets: ["LerroCore"]),
        .library(name: "LerroIntelligence", targets: ["LerroIntelligence"]),
        .library(name: "LerroMac", targets: ["LerroMac"]),
        .executable(name: "Lerro", targets: ["Lerro"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle.git",
            exact: "2.9.4"
        ),
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm.git",
            revision: "3b3516d8fbc6451d6c444a5e03cd1e0ba8719964",
            traits: []
        ),
        .package(path: "Vendor/swift-huggingface"),
        .package(path: "Vendor/swift-transformers")
    ],
    targets: [
        .target(
            name: "LerroCore",
            path: "Sources/LerroCore"
        ),
        .target(
            name: "LerroIntelligence",
            dependencies: [
                "LerroCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            path: "Sources/LerroIntelligence"
        ),
        .target(
            name: "LerroMac",
            dependencies: ["LerroCore"],
            path: "Sources/LerroMac",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("Metal"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Speech"),
                .linkedFramework("Translation")
            ]
        ),
        .executableTarget(
            name: "Lerro",
            dependencies: [
                "LerroCore",
                "LerroIntelligence",
                "LerroMac",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Lerro",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "LerroCoreTests",
            dependencies: ["LerroCore"],
            path: "Tests/LerroCoreTests"
        ),
        .testTarget(
            name: "LerroMacTests",
            dependencies: ["LerroCore", "LerroMac"],
            path: "Tests/LerroMacTests"
        ),
        .testTarget(
            name: "LerroIntelligenceTests",
            dependencies: ["LerroCore", "LerroIntelligence"],
            path: "Tests/LerroIntelligenceTests"
        ),
        .testTarget(
            name: "LerroTests",
            dependencies: ["LerroCore", "LerroMac", "Lerro"],
            path: "Tests/LerroTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
