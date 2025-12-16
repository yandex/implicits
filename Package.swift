// swift-tools-version:6.2
// Copyright 2023 Yandex LLC. All rights reserved.

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "implicits",
  platforms: [
    .macOS(.v11),
    .iOS(.v14),
    .watchOS(.v7),
    .tvOS(.v14),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "Implicits", targets: ["Implicits"]),
    .library(name: "ImplicitsTool", targets: ["ImplicitsTool"]),
    .library(name: "Showcase", targets: ["Showcase"]),
    .plugin(name: "ImplicitsAnalysisPlugin", targets: ["ImplicitsAnalysisPlugin"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
    .package(url: "https://github.com/apple/swift-syntax", from: "601.0.1"),
  ],
  targets: [
    .target(
      name: "Implicits",
      dependencies: ["ImplicitsCUtils", "ImplicitsMacros"],
      swiftSettings: [
        .enableExperimentalFeature("AccessLevelOnImport"),
      ]
    ),
    .target(
      name: "ImplicitsTool",
      dependencies: [
        "ImplicitsToolMacros",
        "ImplicitsShared",
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftOperators", package: "swift-syntax"),
      ]
    ),
    .executableTarget(
      name: "implicits-tool-spm-plugin",
      dependencies: ["ImplicitsTool"],
    ),
    .plugin(
      name: "ImplicitsAnalysisPlugin",
      capability: .buildTool(),
      dependencies: ["implicits-tool-spm-plugin"]
    ),
    .target(
      name: "ImplicitsCUtils"
    ),
    .macro(
      name: "ImplicitsMacros",
      dependencies: [
        "ImplicitsShared",
        "MacroUtils",
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "ImplicitsShared"
    ),
    .testTarget(
      name: "ImplicitsToolTests",
      dependencies: [
        "ImplicitsToolMacros",
        "ImplicitsMacros",
        "TestResources",
        "MacroUtils",
        "ImplicitsTool",
        "__TestResourcesCompilation",
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ],
      swiftSettings: [
        .define("PACKAGE_MANAGER"),
      ]
    ),
    .target(
      name: "MacroUtils",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "ImplicitsTests",
      dependencies: ["Implicits", "ImplicitsShared", "MacroUtils",],
      swiftSettings: [.enableExperimentalFeature("AccessLevelOnImport")]
    ),
    .macro(
      name: "ImplicitsToolMacros",
      dependencies: [
        "MacroUtils",
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "TestResources",
      exclude: ["test_data"],
      swiftSettings: [
        .define("PACKAGE_MANAGER"),
      ]
    ),
    .target(
      name: "__TestResourcesCompilation",
      dependencies: ["Implicits", "AnotherModule"],
      path: "Sources/TestResources/test_data",
      exclude: ["another_module.swift"]
    ),
    .target(
      name: "AnotherModule",
      dependencies: ["Implicits"],
      path: "Sources/TestResources/test_data",
      sources: ["another_module.swift"]
    ),
    .target(
      name: "Showcase",
      dependencies: ["Implicits", "ShowcaseDependency"],
      plugins: ["ImplicitsAnalysisPlugin"],
    ),
    .target(
      name: "ShowcaseDependency",
      dependencies: ["Implicits"],
      plugins: ["ImplicitsAnalysisPlugin"],
    ),
  ]
)
