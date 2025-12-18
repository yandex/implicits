// Copyright 2023 Yandex LLC. All rights reserved.

import SwiftSyntax
import SwiftSyntaxBuilder

extension InitializerDeclSyntax {
  init(
    modifiers: DeclModifierSyntax...,
    @FunctionParameterListBuilder parameters: () throws -> FunctionParameterListSyntax,
    @CodeBlockItemListBuilder body: () throws -> CodeBlockItemListSyntax?
  ) throws {
    try self.init(
      modifiers: DeclModifierListSyntax(modifiers),
      signature: FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(
          parametersBuilder: parameters
        )
      ),
      bodyBuilder: body
    )
  }
}

extension DeclModifierSyntax {
  static let required: Self = .keyword(.required)

  static func keyword(_ k: Keyword) -> Self {
    Self(name: .keyword(k))
  }
}

extension ClosureSignatureSyntax.ParameterClause {
  static func simpleInput(
    parameters: String...
  ) -> Self {
    .simpleInput(
      ClosureShorthandParameterListSyntax(
        itemsBuilder: {
          for name in parameters {
            ClosureShorthandParameterSyntax(name: .identifier(name))
          }
        }
      )
    )
  }
}

extension FunctionCallExprSyntax {
  init(
    callee: some ExprSyntaxProtocol,
    trailingClosure: ClosureExprSyntax? = nil,
    @MultipleTrailingClosureElementListBuilder additionalTrailingClosures: () throws
      -> MultipleTrailingClosureElementListSyntax
  ) throws {
    try self.init(
      callee: callee,
      trailingClosure: trailingClosure,
      additionalTrailingClosures: MultipleTrailingClosureElementListSyntax(
        itemsBuilder: additionalTrailingClosures
      )
    )
  }
}
