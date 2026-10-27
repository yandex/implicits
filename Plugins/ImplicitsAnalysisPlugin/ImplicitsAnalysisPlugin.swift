// Copyright 2025 Yandex LLC. All rights reserved.

import Foundation
import PackagePlugin

/// NOTE: Plugin and tool currently use separate schema copies.
/// They can be unified when SPM plugins supports shared code.
struct ImplicitsToolSPMPluginArgs: Codable {
  // Inputs
  var moduleName: Target.ID
  var sourceFiles: [URL]
  var dependentInterfaces: [URL]
  // Outputs
  var supportFile: URL
  var implicitInterface: URL
}

struct Paths {
  var argsFile: URL
  var supportFile: URL
  var implicitInterface: URL

  init(pluginWorkDir dir: URL, target: any SourceModuleTarget) {
    let module = target.moduleName
    self.argsFile = dir.appending(path: "\(module)_implicit_tool_args.json")
    self.supportFile = dir.appending(path: "\(module)-Implicits.swift")
    self.implicitInterface = dir.appending(path: "\(module).implicitinterface")
  }
}

@main
struct ImplicitsAnalysisPlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext, target: any Target
  ) throws -> [Command] {
    guard let target = target.sourceModule else { return [] }
    let allDeps = target.recursiveTargetDependencies.compactMap(\.sourceModule)
    let targetPackageMap = targetPackageMap(root: context.package)
    let implicitRuntimeID = findImplicitRuntimeTargetID(
      allDeps: allDeps, targetPackageMap: targetPackageMap
    )
    guard let implicitRuntimeID else {
      return []
    }

    let tool = try context.tool(named: "implicits-tool-spm-plugin")
    let genDir = context.pluginWorkDirectoryURL
    let modulename = target.moduleName

    let paths = Paths(
      pluginWorkDir: genDir, target: target
    )
    let sources = target.sourceFiles.map(\.url)

    let dependenciesWithImplicitsRuntime = getImplicitsRuntimeDependants(
      root: target, implicitRuntime: implicitRuntimeID
    )
    let dependentInterfaces = dependenciesWithImplicitsRuntime.compactMap {
      getImplicitInterface(
        for: $0, targetPackageMap: targetPackageMap, genDir: genDir,
        currentPackage: context.package, currentTarget: target
      )
    }

    let input = ImplicitsToolSPMPluginArgs(
      moduleName: modulename,
      sourceFiles: sources,
      dependentInterfaces: dependentInterfaces,
      supportFile: paths.supportFile,
      implicitInterface: paths.implicitInterface,
    )
    let data = try encoder.encode(input)
    try data.write(to: paths.argsFile)

    return [
      .buildCommand(
        displayName: "Implicit Analysis",
        executable: tool.url,
        arguments: [paths.argsFile.path],
        inputFiles: [paths.argsFile] + sources + dependentInterfaces,
        outputFiles: [paths.supportFile, paths.implicitInterface]
      )
    ]
  }
}

// Unfortunately SPM has no way of propagating info between plugin invocations
// between different targets. So we have to use a workaround:
// 1. Find the implicit runtime target in the dependency graph.
// 2. Find all targets that depend on it.
// 3. Assume that they all have plugin enabled, and would generate
//     the implicit interface file.
// 4. Calculate a path to the implicit interface file
//     based on the target package and module name.
// This is not ideal, as we assume how spm generates the output paths.
private func getImplicitInterface(
  for target: any SourceModuleTarget,
  targetPackageMap: [Target.ID: Package],
  genDir: URL,
  currentPackage: Package,
  currentTarget: any SourceModuleTarget
) -> URL? {
  guard let package = targetPackageMap[target.id] else { return nil }

  // Use find-and-replace approach: take current genDir and replace package/target names
  let targetDir = replacePackageAndTargetInPath(
    currentPath: genDir,
    currentPackage: currentPackage.displayName,
    currentTarget: currentTarget.moduleName,
    targetPackage: package.displayName,
    targetTarget: target.moduleName
  )

  return Paths(
    pluginWorkDir: targetDir, target: target
  ).implicitInterface
}

private func targetPackageMap(
  root: Package,
) -> [Target.ID: Package] {
  var map = [Target.ID: Package]()
  var packages = [root]
  var visited = Set<Package.ID>()
  while let package = packages.popLast() {
    guard !visited.contains(package.id) else { continue }
    visited.insert(package.id)
    for target in package.targets {
      map[target.id] = package
    }
    packages += package.dependencies.map(\.package)
  }
  return map
}

private func findImplicitRuntimeTargetID(
  allDeps: [any SourceModuleTarget],
  targetPackageMap: [Target.ID: Package],
) -> Target.ID? {
  allDeps.first(where: {
    $0.moduleName == "Implicits" && targetPackageMap[$0.id]?.displayName == "implicits"
  })?.id
}

private func getImplicitsRuntimeDependants(
  root: any SourceModuleTarget,
  implicitRuntime: Target.ID
) -> [SourceModuleTarget] {
  var found: Set<Target.ID> = [implicitRuntime], visited: Set<Target.ID> = []
  var result: [SourceModuleTarget] = []
  var stack: [(any Target, Bool)] = [(root, false)]

  while let (target, postVisit) = stack.last {
    let id = target.id
    guard !postVisit else {
      if target.directDependencies.contains(where: { found.contains($0.id) }) {
        found.insert(id)
        if let sourceModule = target.sourceModule, id != root.id {
          result.append(sourceModule)
        }
      }
      stack.removeLast()
      continue
    }

    if !visited.insert(id).inserted {
      stack.removeLast()
      continue
    }

    stack[stack.count - 1].1 = true
    for dep in target.directDependencies {
      stack.append((dep, false))
    }
  }

  return result.sorted { $0.moduleName < $1.moduleName }
}

extension Target {
  var directDependencies: [any Target] {
    var deps = [any Target]()
    for dependency in dependencies {
      switch dependency {
      case let .target(target):
        deps.append(target)
      case let .product(product):
        deps.append(contentsOf: product.targets)
      @unknown default:
        continue
      }
    }
    return deps
  }
}

extension String {
  func findAndReplace(
    _ target: String,
    with replacement: String
  ) -> String {
    guard !target.isEmpty else { return self }
    let replacement = replacement[...]
    var parts: [Substring] = []
    var remainder = self[...]

    while let range = remainder.range(of: target) {
      parts.append(remainder[..<range.lowerBound])
      parts.append(replacement)
      remainder = remainder[range.upperBound...]
    }
    if !remainder.isEmpty {
      parts.append(remainder)
    }
    return parts.joined()
  }
}

/// Replaces package and target names in a path using pure Swift string find-and-replace
/// Works with any path format automatically
private func replacePackageAndTargetInPath(
  currentPath: URL,
  currentPackage: String,
  currentTarget: String,
  targetPackage: String,
  targetTarget: String
) -> URL {
  let pathString = currentPath.path
  let newPath = pathString
    .findAndReplace(currentPackage, with: targetPackage)
    .findAndReplace(currentTarget, with: targetTarget)
  return URL(fileURLWithPath: newPath)
}

private let encoder = {
  var encoder = JSONEncoder()
  encoder.outputFormatting = .prettyPrinted
  return encoder
}()
