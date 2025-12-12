// Copyright 2024 Yandex LLC. All rights reserved.

// Represents a diagnostic message produced by different steps of the analyzer.
// Since most of the analyzer is independent from SwiftSyntax, except for the
// initial syntax traverser and top-level processing, this structure is generic
// over `Syntax`. Its purpose is to collect all the necessary information from the
// analyzer, with `Syntax`, which is then processed by the root to produce proper
// diagnostics.
struct PreDiagnostic<Syntax>: Swift.Error, @unchecked Sendable {
  typealias Message = DiagnosticMessage

  var severity: Diagnostic.Severity
  var syntax: Syntax
  var message: Message

  init(severity: Diagnostic.Severity, syntax: Syntax, message: Message) {
    self.severity = severity
    self.syntax = syntax
    self.message = message
  }

  static func error(_ message: Message, at syntax: Syntax) -> Self {
    .init(severity: .error, syntax: syntax, message: message)
  }
}

/// A struct representing a diagnostic message.
///
/// This is to create a nice namespace for diagnostic messages.
/// Example:
/// ```
/// extension DiagnosticMessage {
/// static let missingScopeParameter: Self = "Missing scope parameter, expected `_ scope: Scope`"
/// static func unexpectedArgumentType(_ type: String) -> Self {
///   "Unexpected argument type '\(type)'"
/// }
/// }
/// ```
public struct DiagnosticMessage: Hashable, ExpressibleByStringLiteral,
  ExpressibleByStringInterpolation, Sendable {
  public var value: String

  public init(value: String) {
    self.value = value
  }

  public init(stringLiteral value: String) {
    self.init(value: String(value))
  }
}

extension DiagnosticMessage {
  var expectedCompilerError: Self {
    "\(value); see compiler message. if it there is none, file a bug!"
  }
}

protocol DiagnosticInterface {
  associatedtype Syntax

  mutating func append(_ diagnostic: PreDiagnostic<Syntax>)
}

struct Diagnostics<Syntax>: DiagnosticInterface {
  var values_: [PreDiagnostic<Syntax>] = []

  mutating func append(_ diagnostic: PreDiagnostic<Syntax>) {
    values_.append(diagnostic)
  }

  static func +=(lhs: inout Self, rhs: Self) {
    lhs.values_ += rhs.values_
  }
}

extension Diagnostics: Collection {
  typealias Index = [PreDiagnostic<Syntax>].Index

  func makeIterator() -> IndexingIterator<[PreDiagnostic<Syntax>]> {
    values_.makeIterator()
  }

  var startIndex: Index { values_.startIndex }
  var endIndex: Index { values_.endIndex }

  subscript(position: Index) -> PreDiagnostic<Syntax> {
    _read { yield values_[position] }
  }

  func index(after i: Index) -> Index {
    values_.index(after: i)
  }
}

extension DiagnosticInterface {
  mutating func diagnose(
    _ message: DiagnosticMessage,
    at syntax: Syntax,
    severity: Diagnostic.Severity = .error
  ) {
    append(
      PreDiagnostic(
        severity: severity, syntax: syntax, message: message
      )
    )
  }

  mutating func check(
    _ condition: Bool,
    or message: @autoclosure () -> DiagnosticMessage,
    at syntax: Syntax,
    severity: Diagnostic.Severity = .error
  ) {
    if !condition {
      diagnose(message(), at: syntax, severity: severity)
    }
  }

  mutating func nonNil<T>(
    _ v: T?,
    or message: DiagnosticMessage,
    at syntax: Syntax,
    severity: Diagnostic.Severity = .error
  ) -> T? {
    if v == nil {
      diagnose(message, at: syntax, severity: severity)
    }
    return v
  }

  mutating func note(_ message: DiagnosticMessage, at syntax: Syntax) {
    diagnose(message, at: syntax, severity: .note)
  }
}

/// This is to avoid error 'Type alias 'Diagnostics' references itself'
/// when typealiasing inside namespaces:
/// `typealias Diagnostic = DiagnosticsGeneric<Syntax>`
typealias DiagnosticsGeneric<Syntax> = Diagnostics<Syntax>

protocol DiagnosticWrapper: DiagnosticInterface {
  associatedtype Wrapped: DiagnosticInterface
  var diagnostics: Wrapped { get set }
}

extension DiagnosticWrapper {
  mutating func append(_ diagnostic: PreDiagnostic<Wrapped.Syntax>) {
    diagnostics.append(diagnostic)
  }
}
