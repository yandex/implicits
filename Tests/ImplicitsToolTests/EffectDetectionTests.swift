// Copyright 2025 Yandex LLC. All rights reserved.

import Testing

@_spi(Testing) import ImplicitsTool
import SwiftParser
import SwiftSyntax
import TestResources

struct EffectDetectionTests {
  @Test func closureEffects() {
    verifySyntax(file: "effect_detection.swift", using: ClosureEffectVerifier.self)
  }
}

// MARK: - Closure Effect Verifier

enum ClosureEffect: String, CaseIterable {
  case async
  case `throws`
}

struct ClosureEffectVerifier: SyntaxVerifier, Sendable {
  func extractNodes(
    from syntaxTree: [SyntaxTree<Syntax>.TopLevelEntity],
    locationConverter: SourceLocationConverter
  ) -> [SyntaxNodeResult<ClosureEffect>] {
    var results: [SyntaxNodeResult<ClosureEffect>] = []

    for entity in syntaxTree {
      if case let .declaration(.function(funcDecl)) = entity.value {
        for item in funcDecl.body ?? [] {
          results.append(contentsOf: extractFromStatement(
            item,
            locationConverter: locationConverter
          ))
        }
      }
    }

    return results
  }

  private func extractFromStatement(
    _ statement: SyntaxTree<Syntax>.CodeBlockEntity,
    locationConverter: SourceLocationConverter
  ) -> [SyntaxNodeResult<ClosureEffect>] {
    if case let .expr(expr) = statement.value {
      return extractFromExpression(expr, locationConverter: locationConverter)
    }
    return []
  }

  private func extractFromExpression(
    _ expression: SyntaxTree<Syntax>.Expression,
    locationConverter: SourceLocationConverter
  ) -> [SyntaxNodeResult<ClosureEffect>] {
    switch expression {
    case let .functionCall(call):
      guard case .identifier("check") = call.name?.value else { return [] }
      var results: [SyntaxNodeResult<ClosureEffect>] = []
      if let trailingClosure = call.trailingClosure {
        results.append(contentsOf: extractFromClosure(
          trailingClosure,
          locationConverter: locationConverter
        ))
      }
      return results
    default:
      return []
    }
  }

  private func extractFromClosure(
    _ closure: SyntaxTree<Syntax>.Entity<SyntaxTree<Syntax>.ClosureExpr>,
    locationConverter: SourceLocationConverter
  ) -> [SyntaxNodeResult<ClosureEffect>] {
    let line = closure.syntax.startLocation(converter: locationConverter).line

    var properties: Set<ClosureEffect> = []
    if closure.value.isAsync {
      properties.insert(.async)
    }
    if closure.value.isThrowing {
      properties.insert(.throws)
    }

    var results = [SyntaxNodeResult(line: line, properties: properties)]

    for item in closure.value.body {
      results.append(contentsOf: extractFromStatement(item, locationConverter: locationConverter))
    }

    return results
  }
}
