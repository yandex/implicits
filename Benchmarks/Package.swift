// swift-tools-version: 6.3
// Copyright 2026 Yandex LLC. All rights reserved.

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "implicits-benchmarks",
  platforms: [
    .macOS(.v13),
  ],
  dependencies: [
    .package(name: "implicits", path: ".."),
    .package(url: "https://github.com/ordo-one/benchmark", from: "1.38.0"),
    .package(url: "https://github.com/apple/swift-syntax", from: "602.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "ImplicitsBenchmarks",
      dependencies: [
        "ImplicitsBenchmarksMacros",
        .product(name: "Implicits", package: "implicits"),
        .product(name: "Benchmark", package: "benchmark"),
      ],
      path: "ImplicitsBenchmarks",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "benchmark"),
      ]
    ),
    .macro(
      name: "ImplicitsBenchmarksMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ],
      path: "Macros/ImplicitsBenchmarksMacros"
    ),
  ]
)
