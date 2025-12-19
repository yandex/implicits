
// Copyright 2024 Yandex LLC. All rights reserved.

@testable import ImplicitsTool

import Testing

import SwiftBasicFormat
import SwiftParser
import SwiftSyntax
import TestResources

func verify(
  file: String,
  enableExporting: Bool = false,
  supportFile: String? = nil,
  compilationConditions: Set<String>? = nil,
  sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
  verify(
    files: [file],
    enableExporting: enableExporting,
    supportFile: supportFile,
    compilationConditions: compilationConditions,
    sourceLocation: sourceLocation
  )
}

func verify(
  files: [String],
  enableExporting: Bool = false,
  supportFile: String? = nil,
  compilationConditions: Set<String>? = nil,
  dependencies: [(modulename: String, files: [String])] = [],
  sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
  var dependenciesInterfaces = [[UInt8]]()
  for dep in dependencies {
    let interface = verify(
      files: dep.files,
      modulename: dep.modulename,
      enableExporting: false,
      supportFile: nil,
      compilationConditions: compilationConditions,
      dependencies: [],
      sourceLocation: sourceLocation
    )
    do {
      try dependenciesInterfaces.append(interface.testSerialize())
    } catch {
      Issue.record("Serialization failed: \(error)", sourceLocation: sourceLocation)
    }
  }

  var deserializedInterfaces = [ImplicitModuleInterface]()
  for interfaceBytes in dependenciesInterfaces {
    do {
      try deserializedInterfaces.append(
        ImplicitModuleInterface.testDeserialize(from: interfaceBytes)
      )
    } catch {
      Issue.record("Deserialization failed: \(error)", sourceLocation: sourceLocation)
    }
  }
  _ = verify(
    files: files,
    modulename: "TestModule",
    enableExporting: enableExporting,
    supportFile: supportFile,
    compilationConditions: compilationConditions,
    dependencies: deserializedInterfaces,
    sourceLocation: sourceLocation
  )
}

func verify(
  files: [String],
  modulename: String,
  enableExporting: Bool,
  supportFile: String?,
  compilationConditions: Set<String>?,
  dependencies: [ImplicitModuleInterface],
  sourceLocation: Testing.SourceLocation
) -> ImplicitModuleInterface {
  let sources = files.map(TestSupport.readFile)
  let asts = sources.map(Parser.parse(source:))
  let compilationConditionsConfig: CompilationConditionsConfig =
    if let compilationConditions {
      .enabled(compilationConditions)
    } else {
      .unknown
    }
  let analysisRun = StaticAnalysis.run(
    files: zip(asts, files).map { .init(ast: $0, filename: $1) },
    modulename: modulename,
    dependencies: dependencies,
    compilationConditions: compilationConditionsConfig,
    enableExporting: enableExporting
  )

  // Diagnostics
  let resultDiagnostics = Set(analysisRun.diagnostics.map {
    var diag = $0
    diag.loc.column = 0
    diag.loc.columnEnd = nil
    return diag
  })
  let expectedDiagnostics = Set(
    zip(sources, files)
      .flatMap { expectedDiagnosticsInFile(source: $0, filename: $1) }
  )

  for diag in resultDiagnostics.subtracting(expectedDiagnostics) {
    let sourceFilePath = TestSupport.pathToSourceFile(diag.loc.file)
    reportDiagnostic(.unexpectedDiagnostic, diag, at: sourceFilePath)
  }

  for diag in expectedDiagnostics.subtracting(resultDiagnostics) {
    let sourceFilePath = TestSupport.pathToSourceFile(diag.loc.file)
    reportDiagnostic(.missingDiagnostic, diag, at: sourceFilePath)
  }

  // Keys
  let expextedKeys = Set(sources.flatMap { expectedKeyDeclarationsInFile(source: $0) })
  let resultKeys = Set(analysisRun.supportFile.keys)
  for key in expextedKeys.subtracting(resultKeys) {
    Issue.record("Missing key declaration: \(key)", sourceLocation: sourceLocation)
  }
  for key in resultKeys.subtracting(expextedKeys) {
    Issue.record("Unexpected key declaration: \(key)", sourceLocation: sourceLocation)
  }

  // Support file
  if let supportFile {
    let expectedSupportFile = TestSupport.readFile(supportFile)
    // Disable all formatters
    let resultSupportFile = "// swiftformat:disable all\n#if false\n#endif\n" +
      analysisRun.supportFile
      .render(accessLevelOnImports: true)
      .formatted(using: BasicFormat(indentationWidth: .spaces(2)))
      .description
    let (isEqual, diff) = diff(expectedSupportFile, resultSupportFile)

    if !isEqual {
      let diffDescr = diff.map { "\($0.change.rawValue)\($0.line)" }
        .joined(separator: "\n")
      Issue.record("Support file doesn't match:\n\(diffDescr)", sourceLocation: sourceLocation)
    }
  }
  return analysisRun.publicInterface
}

private enum DiagnosticErrorKind {
  case unexpectedDiagnostic
  case missingDiagnostic
}

private func reportDiagnostic(_ kind: DiagnosticErrorKind, _ diag: Diagnostic, at file: String) {
  let msg =
    switch kind {
    case .missingDiagnostic:
      "Missing diagnostic"
    case .unexpectedDiagnostic:
      "Unexpected diagnostic"
    }

  Issue.record(
    Comment(rawValue: "\(msg):\n\(diag.render())\n"),
    sourceLocation: SourceLocation(
      fileID: file,
      filePath: file,
      line: diag.loc.line,
      column: 1
    )
  )
}

// Inspired by
// https://clang.llvm.org/docs/InternalsManual.html#specifying-diagnostics
private func expectedDiagnosticsInFile(
  source: String,
  filename: String,
  sourceLocation: Testing.SourceLocation = #_sourceLocation
) -> [Diagnostic] {
  let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
  let errors = lines.enumerated().flatMap { idx, line -> [Diagnostic] in
    line.matches(of: expectedDiagRegex).compactMap { match in
      guard let severity = Diagnostic.Severity(match.output.severity) else {
        Issue.record(
          "Unknown diagnostic severity level: \(match.output.severity)",
          sourceLocation: sourceLocation
        )
        return nil
      }
      let lineN: Int
      if let at = match.output.at?.dropFirst() {
        let number = Int(at) ?? {
          Issue.record("Unable to parse line number: \(at)", sourceLocation: sourceLocation)
          return 0
        }()
        switch at.first {
        case "+", "-":
          lineN = idx + 1 + number
        default:
          lineN = number
        }
      } else {
        lineN = idx + 1 // Lines are counted from 1
      }
      let message = match.output.message
      return Diagnostic(
        severity: severity,
        message: String(message),
        codeLine: String(lines[lineN - 1]),
        loc: Diagnostic.Location(file: filename, line: lineN, column: 0)
      )
    }
  }
  return errors
}

func expectedKeyDeclarationsInFile(
  source: String,
  sourceLocation: Testing.SourceLocation = #_sourceLocation
) -> [Sema.ImplicitKeyDecl] {
  let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
  return lines.enumerated().flatMap { _, line in
    line.matches(of: expectedKeyDeclRegex).compactMap { match in
      let visibility = Visibility(match.output.visibility)
      #expect(
        visibility != nil,
        "Unknown visibility level: '\(match.output.visibility)'",
        sourceLocation: sourceLocation
      )
      let key = match.output.key
      let type = match.output.type
      return Sema.ImplicitKeyDecl(
        name: String(key),
        type: String(type),
        visibility: visibility ?? .default
      )
    }
  }
}

private nonisolated(unsafe) let expectedDiagRegex = #/
expected-(?'severity'[a-z]+)(?'at'@[+\-]?[0-9]+)?\s*\{\{(?'message'[^}]+)\}\}
/#

private nonisolated(unsafe) let expectedKeyDeclRegex = #/
expected-key\s+(?'visibility'\w+)\s+(?'key'\S+)\:\s*(?'type'.+)
/#

extension Diagnostic.Severity {
  fileprivate init?(_ severity: some StringProtocol) {
    switch severity {
    case "error": self = .error
    case "warning": self = .warning
    case "note": self = .note
    default: return nil
    }
  }

  fileprivate func render() -> String {
    switch self {
    case .error: "error"
    case .warning: "warning"
    case .note: "note"
    }
  }
}

extension Visibility {
  fileprivate init?(_ visibility: some StringProtocol) {
    switch visibility {
    case "public": self = .public
    case "internal": self = .internal
    case "fileprivate": self = .fileprivate
    case "private": self = .private
    case "default": self = .default
    default: return nil
    }
  }
}

extension Diagnostic {
  fileprivate func render() -> String {
    """
    \(loc.file):\(loc.line): \(severity.render()): \(message)
    \(codeLine)
    """
  }
}

struct InMemoryInputByteStream: InputByteStream {
  var storage: ArraySlice<UInt8>

  init(_ buffer: [UInt8]) {
    self.storage = buffer[...]
  }

  var location: String { "\(storage.startIndex)" }

  mutating func read(
    into buffer: UnsafeMutableRawBufferPointer
  ) throws(SerializationError) {
    guard buffer.count <= storage.count else {
      throw SerializationError.endOfStream(
        at: "\(storage.startIndex) of \(storage.count)",
        need: "\(buffer.count)"
      )
    }
    storage.withUnsafeBytes { bytes in
      buffer.copyMemory(
        from: UnsafeRawBufferPointer(rebasing: bytes[..<(buffer.count)])
      )
    }
    storage.removeFirst(buffer.count)
  }
}

struct InMemoryOutputByteStream: OutputByteStream {
  var storage: [UInt8]

  init() {
    self.storage = []
  }

  mutating func write(
    _ buffer: UnsafeRawBufferPointer
  ) throws(SerializationError) {
    storage.append(contentsOf: buffer)
  }

  func data() -> [UInt8] {
    storage
  }
}

extension Serializable {
  func testSerialize() throws(SerializationError) -> [UInt8] {
    var bytes = InMemoryOutputByteStream()
    try serialize(to: &bytes)
    return bytes.storage
  }

  static func testDeserialize(
    from bytes: [UInt8],
    sourceLocation: Testing.SourceLocation = #_sourceLocation
  ) throws(SerializationError) -> Self {
    var input = InMemoryInputByteStream(bytes)
    let value = try Self(from: &input)
    #expect(input.storage.count == 0, sourceLocation: sourceLocation)
    return value
  }
}

func checkSerialization<T: Serializable & Equatable & Sendable>(
  _ value: T,
  sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
  do {
    let bytes = try value.testSerialize()
    let deserialized = try T.testDeserialize(from: bytes, sourceLocation: sourceLocation)
    #expect(value == deserialized, sourceLocation: sourceLocation)
  } catch {
    Issue.record("Serialization failed: \(error)", sourceLocation: sourceLocation)
  }
}

// LCS-based diff algorithm
enum Change: String {
  case add = "+", remove = "-", same = " "
}

func diff<S: StringProtocol>(
  _ old: S, _ new: S
) -> (isEqual: Bool, diff: [(change: Change, line: S.SubSequence)]) {
  let old = old.split(separator: "\n")
  let new = new.split(separator: "\n")
  let m = old.count
  let n = new.count

  var lcs = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
  for i in 1...m {
    for j in 1...n {
      if old[i - 1] == new[j - 1] {
        lcs[i][j] = lcs[i - 1][j - 1] + 1
      } else {
        lcs[i][j] = max(lcs[i - 1][j], lcs[i][j - 1])
      }
    }
  }

  var i = m, j = n
  var result: [(change: Change, line: S.SubSequence)] = []

  var isEqual = true
  while i > 0 || j > 0 {
    if i > 0, j > 0, old[i - 1] == new[j - 1] {
      result.append((change: .same, line: old[i - 1]))
      i -= 1
      j -= 1
    } else if j > 0, i == 0 || lcs[i][j - 1] >= lcs[i - 1][j] {
      result.append((change: .add, line: new[j - 1]))
      isEqual = false
      j -= 1
    } else if i > 0, j == 0 || lcs[i][j - 1] < lcs[i - 1][j] {
      result.append((change: .remove, line: old[i - 1]))
      isEqual = false
      i -= 1
    }
  }

  return (isEqual, result.reversed())
}
