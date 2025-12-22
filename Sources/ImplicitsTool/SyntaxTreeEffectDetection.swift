// Copyright 2025 Yandex LLC. All rights reserved.

extension SyntaxTree.ClosureExpr {
  @_spi(Testing)
  public var isAsync: Bool { body.contains(where: \.isAsync) }
  @_spi(Testing)
  public var isThrowing: Bool { body.contains(where: \.isThrowing) }
}

extension SyntaxTree.Expression {
  var isAsync: Bool {
    switch self {
    case .await: true
    case let .memberAccessor(base, _): base.isAsync
    case let .other(entities): entities.contains(where: \.isAsync)
    case let .try(expr, _): expr.isAsync
    case let .functionCall(call): call.arguments.contains { $0.value.value.isAsync }
    case .macroExpansion, .declRef, .closure: false
    }
  }

  var isThrowing: Bool {
    switch self {
    case let .try(_, questionOrExclamation: q): !q
    case let .memberAccessor(base, _): base.isThrowing
    case let .other(entities): entities.contains(where: \.isThrowing)
    case let .await(expr): expr.isThrowing
    case let .functionCall(call): call.arguments.contains { $0.value.value.isThrowing }
    case .macroExpansion, .declRef, .closure: false
    }
  }
}

extension SyntaxTree.CodeBlockStatement {
  var isAsync: Bool {
    switch self {
    case let .decl(decl):
      decl.isAsync
    case let .stmt(stmt):
      switch stmt {
      case let .defer(stmts): stmts.contains(where: \.isAsync)
      case let .do(doStmt): doStmt.body.contains(where: \.isAsync) || doStmt.catchBodies
        .contains { $0.contains(where: \.isAsync) }
      case let .other(items): items.contains(where: \.isAsync)
      }
    case let .expr(expr):
      expr.isAsync
    }
  }

  var isThrowing: Bool {
    switch self {
    case let .decl(decl):
      decl.isThrowing
    case let .stmt(stmt):
      switch stmt {
      case let .defer(stmts): stmts.contains(where: \.isThrowing)
      case let .do(doStmt):
        if doStmt.catchBodies.isEmpty {
          doStmt.body.contains(where: \.isThrowing)
        } else {
          doStmt.catchBodies.contains { $0.contains(where: \.isThrowing) }
        }
      case let .other(items): items.contains(where: \.isThrowing)
      }
    case let .expr(expr):
      expr.isThrowing
    }
  }
}

extension SyntaxTree.Declaration {
  private func checkVarInitializers(_ predicate: (SyntaxTree.Expression) -> Bool) -> Bool {
    switch self {
    case let .variable(varDecl):
      varDecl.bindings.contains {
        guard let initializer = $0.initializer else { return false }
        return predicate(initializer.value)
      }
    case .type, .protocol, .function, .memberBlock:
      false
    }
  }

  var isAsync: Bool { checkVarInitializers(\.isAsync) }
  var isThrowing: Bool { checkVarInitializers(\.isThrowing) }
}

extension SyntaxTree.Argument.Value {
  private func checkOther(_ predicate: (SyntaxTree.CodeBlockEntity) -> Bool) -> Bool {
    switch self {
    case let .other(entities): entities.contains(where: predicate)
    case .keyed, .explicitType, .reference: false
    }
  }

  var isAsync: Bool { checkOther(\.isAsync) }
  var isThrowing: Bool { checkOther(\.isThrowing) }
}

extension SyntaxTree.Entity where T == SyntaxTree.CodeBlockStatement {
  var isAsync: Bool { value.isAsync }
  var isThrowing: Bool { value.isThrowing }
}
