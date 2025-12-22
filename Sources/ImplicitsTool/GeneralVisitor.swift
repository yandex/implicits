// Copyright 2023 Yandex LLC. All rights reserved.

import SwiftSyntax

@attached(
  extension,
  names: named(StatefulSyntaxVisitor),
  named(makeVisitor(state:)),
  named(lense(_:))
)
macro GeneralVisitorMacro() = #externalMacro(
  module: "ImplicitsToolMacros",
  type: "GeneralVisitorMacro"
)

enum GeneralVisitorContinuation {
  case visitChildren
  case skipChildren
  case visit([Syntax])
}

@GeneralVisitorMacro
struct GeneralVisitor<State>: @unchecked Sendable {
  typealias Continuation = GeneralVisitorContinuation
  typealias Visitor<K> = (inout State, K) -> Continuation
  static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

  var visitImportDecl: Visitor<ImportDeclSyntax> = emptyVisitor()
  var visitIfConfigDecl: Visitor<IfConfigDeclSyntax> = emptyVisitor()
  var visitClassDecl: Visitor<ClassDeclSyntax> = emptyVisitor()
  var visitStructDecl: Visitor<StructDeclSyntax> = emptyVisitor()
  var visitEnumDecl: Visitor<EnumDeclSyntax> = emptyVisitor()
  var visitActorDecl: Visitor<ActorDeclSyntax> = emptyVisitor()
  var visitExtensionDecl: Visitor<ExtensionDeclSyntax> = emptyVisitor()
  var visitProtocolDecl: Visitor<ProtocolDeclSyntax> = emptyVisitor()
  var visitFunctionDecl: Visitor<FunctionDeclSyntax> = emptyVisitor()
  var visitInitializerDecl: Visitor<InitializerDeclSyntax> = emptyVisitor()
  var visitDeferStmt: Visitor<DeferStmtSyntax> = emptyVisitor()
  var visitDoStmt: Visitor<DoStmtSyntax> = emptyVisitor()
  var visitClosureExpr: Visitor<ClosureExprSyntax> = emptyVisitor()
  var visitFunctionCallExpr: Visitor<FunctionCallExprSyntax> = emptyVisitor()
  var visitTryExpr: Visitor<TryExprSyntax> = emptyVisitor()
  var visitAwaitExpr: Visitor<AwaitExprSyntax> = emptyVisitor()
  var visitVariableDecl: Visitor<VariableDeclSyntax> = emptyVisitor()
  var visitMemberBlockItemList: Visitor<MemberBlockItemListSyntax> = emptyVisitor()
  var visitCodeBlockItemList: Visitor<CodeBlockItemListSyntax> = emptyVisitor()

  func walk(
    initial: State, syntax: some SyntaxProtocol
  ) -> State {
    let visitor = makeVisitor(state: initial)
    visitor.walk(syntax)
    return visitor.state
  }
}

extension GeneralVisitor.StatefulSyntaxVisitor {
  fileprivate func visitGeneral<S>(
    _ visitor: GeneralVisitor.Visitor<S>, _ node: S
  ) -> SyntaxVisitorContinueKind where S: SyntaxProtocol {
    let continuation = visitor(&state, node)
    switch continuation {
    case .skipChildren:
      return .skipChildren
    case .visitChildren:
      return .visitChildren
    case let .visit(syntaxes):
      for syntax in syntaxes {
        walk(syntax)
      }
      return .skipChildren
    }
  }
}

extension GeneralVisitor {
  func modify<S>(
    _ visitor: WritableKeyPath<GeneralVisitor, Visitor<S>>,
    _ newVisitor: (@escaping Visitor<S>) -> Visitor<S>
  ) -> Self {
    var copy = self
    copy[keyPath: visitor] = newVisitor(copy[keyPath: visitor])
    return copy
  }
}
