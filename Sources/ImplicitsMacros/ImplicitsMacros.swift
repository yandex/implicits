// Copyright 2023 Yandex LLC. All rights reserved.

import Foundation

import ImplicitsShared
import MacroUtils
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct ImplicitMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    let loc = try SourceLocation(of: node, in: context)
    let funcName = generateImplicitBagFuncName(
      filename: loc.fileName,
      line: loc.line,
      column: loc.column
    )
    return "\(raw: funcName)()"
  }
}

public struct WithImplicitsMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    let loc = try SourceLocation(of: node, in: context)

    // Get the closure argument (either as argument or trailing closure)
    let closure: ClosureExprSyntax
    if let trailingClosure = node.trailingClosure {
      closure = trailingClosure
    } else if let firstArg = node.arguments.first,
              let closureExpr = firstArg.expression.as(ClosureExprSyntax.self) {
      closure = closureExpr
    } else {
      throw DiagnosticsError.at(node, "#withImplicits requires a closure argument")
    }

    let funcName = generateImplicitWrapFuncName(
      filename: loc.fileName,
      line: loc.line,
      column: loc.column
    )
    return "\(raw: funcName)(\(closure))"
  }
}

@main
struct ImplicitsToolMacros: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    ImplicitMacro.self,
    WithImplicitsMacro.self,
  ]
}
