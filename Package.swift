// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "SwiftDecision-Examples",
  platforms: [
    .iOS(.v15),
    .macOS(.v10_15),
  ],
  products: [
    .library(name: "CityChainGame", targets: ["CityChainGame"]),
    .library(name: "OraclePresentation", targets: ["OraclePresentation"]),
    .library(name: "OracleGame", targets: ["OracleGame"]),
    .library(name: "OracleHistory", targets: ["OracleHistory"])
  ],
  dependencies: [
    .package(url: "https://github.com/SoundBlaster/SwiftDecision.git", exact: "0.4.0"),
    .package(
      url: "https://github.com/SoundBlaster/SpecificationCore.git",
      exact: "2.0.0"
    ),
    .package(url: "https://github.com/SoundBlaster/SwiftJev.git", exact: "0.2.0"),
  ],
  targets: [
    .target(name: "OraclePresentation"),
    .testTarget(name: "OraclePresentationTests", dependencies: ["OraclePresentation"]),
    .target(
      name: "OracleGame",
      dependencies: [
        .product(name: "SwiftDecision", package: "SwiftDecision"),
        .product(name: "SpecificationCore", package: "SpecificationCore"),
        .product(name: "SwiftJev", package: "SwiftJev"),
      ]
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
