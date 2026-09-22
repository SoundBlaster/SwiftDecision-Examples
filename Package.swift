// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "SwiftDecision-Examples",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
  ],
  products: [
    .library(name: "CityChainGame", targets: ["CityChainGame"])
  ],
  dependencies: [
    .package(url: "https://github.com/SoundBlaster/SwiftDecision.git", exact: "0.2.0"),
    .package(url: "https://github.com/SoundBlaster/SpecificationCore.git", exact: "1.1.0"),
    .package(url: "https://github.com/SoundBlaster/SwiftJev.git", exact: "0.1.0"),
  ],
  targets: [
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
      dependencies: ["CityChainGame", "SwiftDecision", "SpecificationCore"]
    ),
  ]
)
