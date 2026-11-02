// Copyright 2026 Yandex LLC. All rights reserved.

import ArgumentParser
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// Writes `NewTypes`, the types of the new-type benchmarks and a closure per
/// type that calls `declareAndRetrieve` with a value of it.
@main
struct GenerateNewTypes: ParsableCommand {
  @Argument(help: "How many types to generate.")
  var count: Int

  @Argument(help: "The Swift file to write.")
  var output: String

  func run() throws {
    let file = try FileDescriptor.open(
      FilePath(output),
      .writeOnly,
      options: [.create, .truncate],
      permissions: [.ownerReadWrite, .groupRead, .otherRead]
    )
    try file.closeAfter {
      func write(_ text: String) throws {
        try file.writeAll(text.utf8)
      }
      try write("enum NewTypes {\n")
      for i in 0..<count {
        try write("  protocol P\(i) {}\n  final class C\(i): P\(i) {}\n")
      }
      try write("  static let touches: [@Sendable () -> Void] = [\n")
      for i in 0..<count {
        try write("    { declareAndRetrieve(C\(i)() as any P\(i)) },\n")
      }
      try write("  ]\n}\n")
    }
  }
}
