// Copyright 2025 Yandex LLC. All rights reserved.

import Foundation

import ImplicitsTool
import SwiftBasicFormat
import SwiftParser

/// NOTE: Plugin and tool currently use separate schema copies.
/// They can be unified when SPM plugins supports shared code.
struct ImplicitsToolSPMPluginArgs: Codable {
  // Inputs
  var moduleName: String
  var sourceFiles: [URL]
  var dependentInterfaces: [URL]
  // Outputs
  var supportFile: URL
  var implicitInterface: URL
}

@main
private enum ImplicitsTool {
  // FIXME: Replace `throws` with proper user-facing error messages.
  static func main() throws {
    let inputPath = URL(fileURLWithPath: CommandLine.arguments[1])
    let args = try JSONDecoder().decode(
      ImplicitsToolSPMPluginArgs.self,
      from: Data(contentsOf: inputPath)
    )

    let analysisResult = try StaticAnalysis.run(
      files: args.sourceFiles,
      modulename: args.moduleName,
      dependencies: args.dependentInterfaces,
      enableExporting: true
    )

    try analysisResult.supportFile.render()
      .formatted(using: .defaultStyle).description
      .write(to: args.supportFile, atomically: true, encoding: .utf8)

    try FileWriter(url: args.implicitInterface, append: false).withStream { s in
      try analysisResult.publicInterface.serialize(to: &s)
    }

    var hasErrors = false
    for diagnostic in analysisResult.diagnostics {
      print(diagnostic.swiftcLikeRender())
      hasErrors = hasErrors || diagnostic.severity == .error
    }
    if hasErrors {
      exit(1)
    }
  }
}

extension StaticAnalysis {
  static func run(
    files: [URL],
    modulename: String,
    dependencies: [URL],
    enableExporting: Bool
  ) throws -> StaticAnalysis.Result {
    try run(
      files: files.map {
        try StaticAnalysis.SourceFileInput(
          ast: Parser.parse(source: String(contentsOf: $0)),
          filename: $0.path
        )
      },
      modulename: modulename,
      dependencies: dependencies.map {
        try readDependencyInterface(at: $0)
      },
      compilationConditions: .unknown,
      enableExporting: enableExporting
    )
  }

  private static func readDependencyInterface(at url: URL) throws -> ImplicitModuleInterface {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw MissingInterfaceError(path: url.path)
    }
    return try FileReader(url: url).withStream {
      try ImplicitModuleInterface(from: &$0)
    }
  }
}

struct MissingInterfaceError: CustomStringConvertible, Error {
  var path: String

  var description: String {
    let moduleName = URL(fileURLWithPath: path)
      .deletingPathExtension().lastPathComponent
    return """
    Missing implicit interface file for module '\(moduleName)'.

    This usually means the module depends on Implicits but doesn't have \
    the analysis plugin enabled. Add to your Package.swift:

      .target(
        name: "\(moduleName)",
        dependencies: [...],
        plugins: [.plugin(name: "ImplicitsAnalysisPlugin", package: "implicits")]
      )

    All modules in the dependency chain that use Implicits must have the plugin enabled.
    """
  }
}

extension BasicFormat {
  nonisolated(unsafe) static let defaultStyle = BasicFormat(indentationWidth: .spaces(2))
}
