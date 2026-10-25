// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "SwiftDecision-Examples",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v15),
    .macOS(.v10_15),
  ],
  products: [
    .library(name: "CityChainPresentation", targets: ["CityChainPresentation"]),
    .library(name: "CityChainGame", targets: ["CityChainGame"]),
    .library(name: "OraclePresentation", targets: ["OraclePresentation"]),
    .library(name: "OracleGame", targets: ["OracleGame"]),
    .library(name: "OracleHistory", targets: ["OracleHistory"]),
    .library(name: "OracleGLiNER", targets: ["OracleGLiNER"]),
  ],
  traits: [.trait(name: "GLiNER", description: "Enable the experimental local GLiNER provider.")],
  dependencies: [
    // Pilot dependency: SwiftDecision PR #23, pinned until its first release.
    .package(
      url: "https://github.com/SoundBlaster/SwiftDecision.git",
      revision: "d655ab6d750bac2d69c3af1e27b0a7bb8b5c136c",
      traits: [.trait(name: "GLiNER", condition: .when(traits: ["GLiNER"]))]
    ),
    .package(
      url: "https://github.com/SoundBlaster/SpecificationCore.git",
      exact: "2.1.0"
    ),
    .package(url: "https://github.com/SoundBlaster/SwiftJev.git", exact: "0.5.0"),
  ],
  targets: [
    .target(
      name: "CityChainPresentation",
      dependencies: [.product(name: "SpecificationCore", package: "SpecificationCore")]
    ),
    .testTarget(name: "CityChainPresentationTests", dependencies: ["CityChainPresentation"]),
    .target(name: "OraclePresentation"),
    .testTarget(name: "OraclePresentationTests", dependencies: ["OraclePresentation"]),
    .target(
      name: "OracleGame",
      dependencies: [
        .product(name: "SwiftDecision", package: "SwiftDecision"),
        .product(name: "SpecificationCore", package: "SpecificationCore"),
        .product(name: "SwiftJev", package: "SwiftJev"),
      ],
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "OracleGameTests",
      dependencies: ["OracleGame", .product(name: "SwiftJev", package: "SwiftJev")]
    ),
    .target(
      name: "OracleHistory",
      dependencies: ["OracleGame"],
      resources: [.process("PrivacyInfo.xcprivacy")]
    ),
    .testTarget(name: "OracleHistoryTests", dependencies: ["OracleHistory"]),
    .target(
      name: "OracleGLiNER",
      dependencies: [
        "OracleGame",
        .product(name: "SwiftDecision", package: "SwiftDecision"),
        .product(name: "SwiftDecisionGLiNER", package: "SwiftDecision", condition: .when(platforms: [.iOS, .macOS], traits: ["GLiNER"])),
      ],
      swiftSettings: [.define("ORACLE_GLINER", .when(platforms: [.iOS, .macOS], traits: ["GLiNER"]))]
    ),
    .testTarget(name: "OracleGLiNERTests", dependencies: [
      "OracleGLiNER", "OracleGame", .product(name: "SwiftDecision", package: "SwiftDecision")]),
    .target(
      name: "CityChainGame",
      dependencies: [
        .product(name: "SwiftDecision", package: "SwiftDecision"),
        .product(name: "SpecificationCore", package: "SpecificationCore"),
        .product(name: "SwiftJev", package: "SwiftJev"),
      ]
    ),
    .testTarget(
      name: "CityChainGameTests",
      dependencies: ["CityChainGame", "SwiftDecision", "SpecificationCore", .product(name: "SwiftJev", package: "SwiftJev")]
    ),
  ]
)
