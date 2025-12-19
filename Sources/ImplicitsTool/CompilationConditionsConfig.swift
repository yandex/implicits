// Copyright 2025 Yandex LLC. All rights reserved.

import SwiftOperators
import SwiftSyntax

public enum CompilationConditionsConfig: Sendable {
  /// Evaluates specified conditions as true, and all others as false.
  case enabled(Set<String>)
  /// Evaluates conditions as specified, skips those that aren't in the dictionary.
  case strict([String: Bool])

  /// A config that evaluates all conditions as undetermined.
  public static let unknown: Self = .strict([:])
}

extension GeneralVisitor {
  func filterInactiveIfConfig(
    config: CompilationConditionsConfig
  ) -> Self {
    modify(\.visitIfConfigDecl) { oldVisitor in
      { state, node in
        func eval(_ condition: ExprSyntax) -> Bool? {
          evaluateCondition(condition, config: config)
        }

        var toVisit = [IfConfigClauseSyntax]()
        var evaluatedAtLeastOnce = false

        for clause in node.clauses {
          switch clause.condition.flatMap(eval) {
          case nil:
            toVisit.append(clause)
          case true?:
            toVisit.append(clause)
            return .visit(toVisit.map(Syntax.init))
          case false?:
            evaluatedAtLeastOnce = true
          }
        }

        return if evaluatedAtLeastOnce {
          .visit(toVisit.map(Syntax.init))
        } else {
          oldVisitor(&state, node)
        }
      }
    }
  }
}

@_spi(Testing)
public func evaluateCondition(
  _ condition: ExprSyntax,
  config: CompilationConditionsConfig
) -> Bool? {
  guard let condition = foldOperators(condition) else {
    return nil
  }
  func eval(_ lhs: Bool?, _ op: ExprSyntax, _ rhs: Bool?) -> Bool? {
    guard case let .binaryOperatorExpr(opExpr) = op.as(ExprSyntaxEnum.self),
          case let .binaryOperator(opDescr) = opExpr.operator.tokenKind
    else { return nil }

    switch opDescr {
    case "&&":
      if lhs == false || rhs == false { return false }
      if lhs == true, rhs == true { return true }
      return nil
    case "||":
      if lhs == true || rhs == true { return true }
      if lhs == false, rhs == false { return false }
      return nil
    default:
      return nil
    }
  }
  func eval(_ c: ExprSyntax) -> Bool? {
    switch c.as(ExprSyntaxEnum.self) {
    case let .declReferenceExpr(expr) where expr.argumentNames == nil:
      return config.value(for: expr.baseName.text)
    case let .booleanLiteralExpr(expr):
      return expr.literal.tokenKind == .keyword(.true)
    case let .infixOperatorExpr(expr):
      let lhs = eval(expr.leftOperand), rhs = eval(expr.rightOperand)
      return eval(lhs, expr.operator, rhs)
    case let .tupleExpr(expr) where expr.elements.count == 1:
      return expr.elements.first.flatMap { eval($0.expression) }
    case let .prefixOperatorExpr(expr):
      switch (eval(expr.expression), expr.operator.text) {
      case let (v?, "!"):
        return !v
      default:
        return nil
      }
    default:
      return nil
    }
  }
  return eval(condition)
}

fileprivate func foldOperators(
  _ condition: some ExprSyntaxProtocol
) -> ExprSyntax? {
  var errors: [OperatorError] = []
  let foldedCondition = OperatorTable.logicalOperators
    .foldAll(condition) { errors.append($0) }
    .cast(ExprSyntax.self)
  return errors.isEmpty ? foldedCondition : nil
}

extension CompilationConditionsConfig {
  fileprivate func value(for key: String) -> Bool? {
    switch self {
    case let .enabled(set):
      set.contains(key)
    case let .strict(dict):
      dict[key]
    }
  }
}
