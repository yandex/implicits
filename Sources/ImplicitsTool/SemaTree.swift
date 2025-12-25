// Copyright 2023 Yandex LLC. All rights reserved.

import SwiftSyntax

/// Namespace for semantic tree model and builder.
/// Used terms:
/// - Node - fundamental entity of this model that represents a statement
///   with intention behind it in the context of Implicits. Consists of three parts,
///   where each part represents a level of syntax tree hierarchy
/// - Error - structure that pairs up a syntax element with a corresponding error kind
enum SemaTree<Syntax> {
  struct WithSyntax<T> {
    var syntax: Syntax
    var node: T
  }

  struct TypeDecl {
    var name: Sema.Namespace
    var members: [MemberBlockItem]

    init(name: Sema.Namespace, members: [MemberBlockItem]) {
      self.name = name
      self.members = members
    }
  }

  struct FuncDecl {
    typealias Modifier = Sema.FuncModifier
    var signature: Symbol
    var visibility: Visibility
    var modifiers: [Modifier]
    var hasScopeParameter: Bool
    var enclosingTypeIsClass: Bool
    /// Function paramters without scope parameter
    var parameters: [(name: String, type: String)]
    var returnType: String?
    var body: [CodeBlockItem]
  }

  typealias Implicit = Sema.Implicit
  typealias Symbol = SymbolInfo<Syntax>

  enum TopLevelNode {
    case typeDeclaration(TypeDecl)
    case extensionDeclaration(Sema.Namespace?, [MemberBlockItem])
    case functionDeclaration(FuncDecl)
    case keysDeclaration([Sema.ImplicitKeyDecl])
  }

  enum MemberBlockNode {
    case typeDeclaration(TypeDecl)
    case functionDeclaration(FuncDecl)
    case implicit(ImplicitKey)
    case bag(ImplicitBag)
    case field(initializer: [CodeBlockItem])
  }

  typealias FuncCall = Sema.FuncCall

  typealias ImplicitBag = WithSyntax<Sema.ImplicitBagDescription>

  struct ClosureExpression {
    var bag: ImplicitBag?
    var body: [CodeBlockItem]
  }

  enum CodeBlockItemNode {
    case typeDeclaration(TypeDecl)
    case functionDeclaration(FuncDecl)
    case deferStatement([CodeBlockItem])
    case closureExpression(ClosureExpression)
    case innerScope([CodeBlockItem])
    case functionCall(FuncCall)
    case implicitScopeBegin(nested: Bool, withBag: Bool)
    case implicitScopeEnd
    case withScope(nested: Bool, withBag: Bool, body: [CodeBlockItem])
    case withNamedImplicits(wrapperName: String, closureParamCount: Int, body: [CodeBlockItem])
    case implicitMap(from: ImplicitKey, to: ImplicitKey)
    case implicit(Implicit)
    case unresolvedIfConfigBlock(condition: Syntax, body: [CodeBlockItem])
  }

  typealias TopLevel = WithSyntax<TopLevelNode>
  typealias CodeBlockItem = WithSyntax<CodeBlockItemNode>
  typealias MemberBlockItem = WithSyntax<MemberBlockNode>
}

// Namespace for things that are not dependent on `Syntax` generic
enum Sema {
  struct Implicit {
    enum Mode {
      case set, get
    }

    var mode: Mode
    var key: ImplicitKey
  }

  struct ImplicitKeyDecl: Hashable {
    var name: String
    var type: String
    var visibility: Visibility
  }

  struct FuncCall {
    var signature: CallableSignature
  }

  typealias Namespace = SymbolNamespace

  struct ImplicitBagDescription {
    var fillFunctionName: String
  }

  enum FuncModifier {
    case convenience
  }
}

extension Array {
  mutating func append<T, S>(
    _ node: T, syntax: S
  ) where Element == SemaTree<S>.WithSyntax<T> {
    append(.init(syntax: syntax, node: node))
  }
}

extension SemaTree.TopLevelNode {
  func mapSyntax<NewSyntax>(
    _ transform: (Syntax) -> NewSyntax
  ) -> SemaTree<NewSyntax>.TopLevelNode {
    switch self {
    case let .typeDeclaration(typeDecl):
      .typeDeclaration(typeDecl.mapSyntax(transform))
    case let .extensionDeclaration(type, members):
      .extensionDeclaration(type, members.map { $0.mapSyntax(transform) })
    case let .functionDeclaration(decl):
      .functionDeclaration(decl.mapSyntax(transform))
    case let .keysDeclaration(keys):
      .keysDeclaration(keys)
    }
  }
}

extension SemaTree.TypeDecl {
  func mapSyntax<NewSyntax>(
    _ transform: (Syntax) -> NewSyntax
  ) -> SemaTree<NewSyntax>.TypeDecl {
    .init(
      name: name,
      members: members.map { $0.mapSyntax(transform) }
    )
  }
}

extension SemaTree.FuncDecl {
  func mapSyntax<NewSyntax>(
    _ transform: (Syntax) -> NewSyntax
  ) -> SemaTree<NewSyntax>.FuncDecl {
    .init(
      signature: signature.mapSyntax(transform),
      visibility: visibility,
      modifiers: modifiers,
      hasScopeParameter: hasScopeParameter,
      enclosingTypeIsClass: enclosingTypeIsClass,
      parameters: parameters,
      returnType: returnType,
      body: body.map { $0.mapSyntax(transform) }
    )
  }
}

extension SemaTree.MemberBlockNode {
  func mapSyntax<NewSyntax>(
    _ transform: (Syntax) -> NewSyntax
  ) -> SemaTree<NewSyntax>.MemberBlockNode {
    switch self {
    case let .typeDeclaration(type):
      .typeDeclaration(type.mapSyntax(transform))
    case let .functionDeclaration(decl):
      .functionDeclaration(decl.mapSyntax(transform))
    case let .implicit(key):
      .implicit(key)
    case let .bag(bag):
      .bag(bag.mapSyntax(transform))
    case let .field(initializer: initializer):
      .field(initializer: initializer.map { $0.mapSyntax(transform) })
    }
  }
}

extension SemaTree.WithSyntax {
  init(
    syntax: Syntax,
    fillFunctionName: String
  ) where T == Sema.ImplicitBagDescription {
    self.init(
      syntax: syntax,
      node: Sema.ImplicitBagDescription(fillFunctionName: fillFunctionName)
    )
  }

  func mapSyntax<NewSyntax>(
    _ transform: (Syntax) -> NewSyntax
  ) -> SemaTree<NewSyntax>.CodeBlockItem where T == SemaTree.CodeBlockItemNode {
    .init(syntax: transform(syntax), node: node.mapSyntax(transform))
  }

  func mapSyntax<NewSyntax>(
    _ transform: (Syntax) -> NewSyntax
  ) -> SemaTree<NewSyntax>.TopLevel where T == SemaTree.TopLevelNode {
    .init(syntax: transform(syntax), node: node.mapSyntax(transform))
  }

  func mapSyntax<NewSyntax>(
    _ transform: (Syntax) -> NewSyntax
  ) -> SemaTree<NewSyntax>.MemberBlockItem where T == SemaTree.MemberBlockNode {
    .init(syntax: transform(syntax), node: node.mapSyntax(transform))
  }

  func mapSyntax<NewSyntax>(
    _ transform: (Syntax) -> NewSyntax
  ) -> SemaTree<NewSyntax>.ImplicitBag where T == Sema.ImplicitBagDescription {
    .init(syntax: transform(syntax), node: node)
  }
}

extension SemaTree.CodeBlockItemNode {
  func mapSyntax<NewSyntax>(
    _ transform: (Syntax) -> NewSyntax
  ) -> SemaTree<NewSyntax>.CodeBlockItemNode {
    switch self {
    case let .typeDeclaration(type):
      .typeDeclaration(type.mapSyntax(transform))
    case let .functionDeclaration(decl):
      .functionDeclaration(decl.mapSyntax(transform))
    case let .deferStatement(nodes):
      .deferStatement(nodes.map { $0.mapSyntax(transform) })
    case let .closureExpression(nodes):
      .closureExpression(nodes.mapSyntax(transform))
    case let .innerScope(nodes):
      .innerScope(nodes.map { $0.mapSyntax(transform) })
    case let .functionCall(fcall):
      .functionCall(fcall)
    case let .implicitScopeBegin(nested: nested, withBag: hasBag):
      .implicitScopeBegin(nested: nested, withBag: hasBag)
    case .implicitScopeEnd:
      .implicitScopeEnd
    case let .implicit(implicit):
      .implicit(implicit)
    case let .withScope(nested: nested, withBag: withBag, body: body):
      .withScope(nested: nested, withBag: withBag, body: body.map { $0.mapSyntax(transform) })
    case let .withNamedImplicits(wrapperName: name, closureParamCount: count, body: body):
      .withNamedImplicits(
        wrapperName: name,
        closureParamCount: count,
        body: body.map { $0.mapSyntax(transform) }
      )
    case let .implicitMap(from: from, to: to):
      .implicitMap(from: from, to: to)
    case let .unresolvedIfConfigBlock(condition: condition, body: body):
      .unresolvedIfConfigBlock(
        condition: transform(condition),
        body: body.map { $0.mapSyntax(transform) }
      )
    }
  }
}

extension SemaTree.ClosureExpression {
  func mapSyntax<NewSyntax>(
    _ transform: (Syntax) -> NewSyntax
  ) -> SemaTree<NewSyntax>.ClosureExpression {
    .init(
      bag: bag.map { $0.mapSyntax(transform) },
      body: body.map { $0.mapSyntax(transform) }
    )
  }
}
