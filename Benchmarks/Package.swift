// swift-tools-version: 6.3
// Copyright 2026 Yandex LLC. All rights reserved.

import PackageDescription

let package = Package(
  name: "implicits-benchmarks",
  platforms: [
    .macOS(.v15),
  ],
  dependencies: [
    .package(name: "implicits", path: ".."),
    .package(url: "https://github.com/ordo-one/benchmark", from: "1.38.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
    .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.2"),
    .package(url: "https://github.com/apple/swift-system", from: "1.8.1"),
  ],
  targets: [
    .executableTarget(
      name: "ImplicitsBenchmarks",
      dependencies: [
        .product(name: "Implicits", package: "implicits"),
        .product(name: "Benchmark", package: "benchmark"),
      ],
      path: "ImplicitsBenchmarks",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "benchmark"),
        "NewTypesPlugin",
      ]
    ),
    .executableTarget(
      name: "compare-builds",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(
          name: "SystemPackage",
          package: "swift-system",
          condition: .when(platforms: [.linux])
        ),
      ]
    ),
    .executableTarget(
      name: "generate-new-types",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(
          name: "SystemPackage",
          package: "swift-system",
          condition: .when(platforms: [.linux])
        ),
      ]
    ),
    .plugin(
      name: "NewTypesPlugin",
      capability: .buildTool(),
      dependencies: ["generate-new-types"]
    ),
  ]
)
