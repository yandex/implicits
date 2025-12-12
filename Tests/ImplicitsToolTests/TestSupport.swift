
// Copyright 2024 Yandex LLC. All rights reserved.

@testable import ImplicitsTool

import XCTest

import SwiftBasicFormat
import SwiftParser
import SwiftSyntax
import TestResources

extension XCTestCase {
  func verify(
    file: String, enableExporting: Bool = false, supportFile: String? = nil
  ) {
    verify(
      files: [file], enableExporting: enableExporting, supportFile: supportFile
    )
  }

  func verify(
    files: [String],
    enableExporting: Bool = false,
    supportFile: String? = nil,
    dependencies: [(modulename: String, files: [String])] = []
  ) {
    var dependenciesInterfaces = [[UInt8]]()
    for dep in dependencies {
      let interface = verify(
        files: dep.files, modulename: dep.modulename,
        enableExporting: false,
        supportFile: nil,
        dependencies: []
      )
      XCTAssertNoThrow(
        try dependenciesInterfaces.append(interface.testSerialize())
      )
    }
    if !dependenciesInterfaces.isEmpty {
      let interfacesDescr = dependenciesInterfaces.map {
        $0.map { String(format: "%02x", $0) }.joined(separator: " ")
      }.joined(separator: "\n")
      add(XCTAttachment(
        string: "Serialized Interfaces:\n\(interfacesDescr)"
      ))
    }

    var deserializedInterfaces = [ImplicitModuleInterface]()
    for interfaceBytes in dependenciesInterfaces {
      XCTAssertNoThrow(try deserializedInterfaces.append(
        ImplicitModuleInterface.testDeserialize(from: interfaceBytes)
      ))
    }
    _ = verify(
      files: files, modulename: "TestModule",
      enableExporting: enableExporting,
      supportFile: supportFile,
      dependencies: deserializedInterfaces
    )
  }

  func verify(
    files: [String],
    modulename: String,
    enableExporting: Bool,
    supportFile: String?,
    dependencies: [ImplicitModuleInterface]
  ) -> ImplicitModuleInterface {
    let sources = files.map(TestSupport.readFile)
    let asts = sources.map(Parser.parse(source:))
    let analysisRun = StaticAnalysis.run(
      files: zip(asts, files).map { .init(ast: $0, filename: $1) },
      modulename: modulename,
      dependencies: dependencies,
      compilationConditions: .unknown,
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
        .flatMap(expectedDiagnosticsInFile(source:filename:))
    )

    for diag in resultDiagnostics.subtracting(expectedDiagnostics) {
      let sourceFilePath = TestSupport.pathToSourceFile(diag.loc.file)
      report(.unexpectedDiagnostic, diag, at: sourceFilePath)
    }

    for diag in expectedDiagnostics.subtracting(resultDiagnostics) {
      let sourceFilePath = TestSupport.pathToSourceFile(diag.loc.file)
      report(.missingDiagnostic, diag, at: sourceFilePath)
    }

    // Keys
    let expextedKeys = Set(sources.flatMap(expectedKeyDeclarationsInFile))
    let resultKeys = Set(analysisRun.supportFile.keys)
    for key in expextedKeys.subtracting(resultKeys) {
      XCTFail("Missing key declaration: \(key)")
    }
    for key in resultKeys.subtracting(expextedKeys) {
      XCTFail("Unexpected key declaration: \(key)")
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
        XCTFail("Support file doesn't match:\n\(diffDescr)")
      }
    }
    return analysisRun.publicInterface
  }

  private enum ErrorKind {
    case unexpectedDiagnostic
    case missingDiagnostic
  }

  private func report(_ kind: ErrorKind, _ diag: Diagnostic, at file: String) {
    let msg: String
    let issueType: XCTIssue.IssueType
    switch kind {
    case .missingDiagnostic:
      msg = "Missing diagnostic"
      issueType = .unmatchedExpectedFailure
    case .unexpectedDiagnostic:
      msg = "Unexpected diagnostic"
      issueType = .assertionFailure
    }

    XCTFail("\(msg):\n\(diag.render())\n")
    let issue = XCTIssue(
      type: issueType,
      compactDescription: "\(msg): \(diag.severity.render()): \(diag.message)",
      sourceCodeContext: XCTSourceCodeContext(
        location: XCTSourceCodeLocation(
          filePath: file,
          lineNumber: diag.loc.line
        )
      ),
      associatedError: nil, attachments: []
    )
    record(issue)
  }
}

// Inspired by
// https://clang.llvm.org/docs/InternalsManual.html#specifying-diagnostics
private func expectedDiagnosticsInFile(source: String, filename: String) -> [Diagnostic] {
  let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
  let errors = lines.enumerated().flatMap { idx, line -> [Diagnostic] in
    line.matches(of: expectedDiagRegex).compactMap { match in
      guard let severity = Diagnostic.Severity(match.output.severity) else {
        XCTFail("Unknown diagnostic severity level: \(match.output.severity)")
        return nil
      }
      let lineN: Int
      if let at = match.output.at?.dropFirst() {
        let number = Int(at) ?? {
          XCTFail("Unable to parse line number: \(at)")
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

func expectedKeyDeclarationsInFile(source: String) -> [Sema.ImplicitKeyDecl] {
  let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
  return lines.enumerated().flatMap { _, line in
    line.matches(of: expectedKeyDeclRegex).compactMap { match in
      let visibility = Visibility(match.output.visibility)
      XCTAssertNotNil(
        visibility,
        "Unknown visibility level: '\(match.output.visibility)'"
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
    from bytes: [UInt8]
  ) throws(SerializationError) -> Self {
    var input = InMemoryInputByteStream(bytes)
    let value = try Self(from: &input)
    XCTAssertEqual(input.storage.count, 0)
    return value
  }
}

extension XCTestCase {
  func checkSerialization<T: Serializable & Equatable & Sendable>(_ value: T) {
    XCTAssertNoThrow(try MainActor.assumeIsolated {
      try XCTContext.runActivity(named: "serializing type \(T.self)") {
        $0.add(XCTAttachment(string: "serializing \(value)"))
        let bytes = try value.testSerialize()
        let bytesDescr = bytes
          .map { String(format: "%02x", $0) }.joined(separator: " ")
        $0.add(XCTAttachment(string: "serialized bytes: \(bytesDescr)"))
        let deserialized = try T.testDeserialize(from: bytes)
        $0.add(XCTAttachment(string: "deserialized \(deserialized)"))
        XCTAssertEqual(value, deserialized)
      }
    })
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
