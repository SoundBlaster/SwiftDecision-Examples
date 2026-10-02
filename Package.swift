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
    .library(name: "OracleHistory", targets: ["OracleHistory"])
  ],
  dependencies: [
    .package(url: "https://github.com/SoundBlaster/SwiftDecision.git", revision: "77171f9151eee022b268ce761d115298aa97860f"),
    .package(
      url: "https://github.com/SoundBlaster/SpecificationCore.git",
      exact: "2.1.0"
    ),
    .package(url: "https://github.com/SoundBlaster/SwiftJev.git", revision: "7fde26e158390d861c5fb521fc518103581acb3c"),
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
