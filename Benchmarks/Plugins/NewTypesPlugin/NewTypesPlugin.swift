// Copyright 2026 Yandex LLC. All rights reserved.

import PackagePlugin

/// Generates the types of the new-type benchmarks.
@main
struct NewTypesPlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext, target _: any Target
  ) throws -> [Command] {
    let output = context.pluginWorkDirectoryURL.appending(path: "NewTypes.swift")
    return try [
      .buildCommand(
        displayName: "Generating NewTypes.swift",
        executable: context.tool(named: "generate-new-types").url,
        arguments: ["2000", output.path],
        outputFiles: [output]
      ),
    ]
  }
}
