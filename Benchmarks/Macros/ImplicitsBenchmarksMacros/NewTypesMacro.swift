// Copyright 2026 Yandex LLC. All rights reserved.

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

/// `#newTypes(n)` expands to `n` protocols `P<i>` with classes `C<i>` conforming to
/// them, and `static let touches`, whose closure `i` declares and retrieves
/// `C<i>() as any P<i>` through `declareAndRetrieve`, each in specialized code.
public struct NewTypesMacro: DeclarationMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in _: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard
      let literal = node.arguments.first?.expression.as(IntegerLiteralExprSyntax.self),
      let count = Int(literal.literal.text)
    else {
      throw MacroError("#newTypes takes an integer literal")
    }
    let types = (0..<count).flatMap { i -> [DeclSyntax] in
      ["protocol P\(raw: i) {}", "final class C\(raw: i): P\(raw: i) {}"]
    }
    let touches = (0..<count)
      .map { "{ declareAndRetrieve(C\($0)() as any P\($0)) }," }
      .joined(separator: "\n")
    return types + ["static let touches: [@Sendable () -> Void] = [\n\(raw: touches)\n]"]
  }
}

struct MacroError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}

@main
struct ImplicitsBenchmarksMacros: CompilerPlugin {
  let providingMacros: [Macro.Type] = [NewTypesMacro.self]
}
