// Copyright 2023 Yandex LLC. All rights reserved.

import SwiftSyntax

private typealias SXT = SyntaxTree<Syntax>

private typealias TopLevelStatement = SXT.TopLevelStatement
private typealias MemberBlockStatement = SXT.MemberBlockStatement
private typealias CodeBlockStatement = SXT.CodeBlockStatement
private typealias TopLevelEntity = SXT.TopLevelEntity
private typealias MemberBlockEntity = SXT.MemberBlockEntity
private typealias CodeBlockEntity = SXT.CodeBlockEntity
private typealias Attributes = SXT.Attributes
private typealias Arguments = SXT.Arguments
private typealias Affiliation = SXT.Affiliation

extension SyntaxTree {
  public static func build(
    _ root: SyntaxProtocol,
    ifConfig: CompilationConditionsConfig
  ) -> [TopLevelEntity] where Syntax == SwiftSyntax.Syntax {
    let context = Context(ifConfig: ifConfig)
    return context.fileVisitor().walk(
      initial: ([], context), syntax: root
    ).sxt
  }
}

fileprivate struct Context {
  var ifConfig: CompilationConditionsConfig

  func fileVisitor() -> SyntaxVisitor<[TopLevelEntity]> {
    fileVisitorFactory(ifConfig)
  }

  func memberBlockVisitor() -> SyntaxVisitor<[MemberBlockEntity]> {
    memberBlockVisitorFactory(ifConfig)
  }

  func codeBlockVisitor() -> SyntaxVisitor<[CodeBlockEntity]> {
    codeBlockVisitorFactory(ifConfig)
  }
}

private typealias SyntaxVisitor<S> = GeneralVisitor<(sxt: S, ctx: Context)>

private let fileVisitorFactory: @Sendable (CompilationConditionsConfig)
  -> SyntaxVisitor<[TopLevelEntity]> = { ifConfig in
    SyntaxVisitor<[TopLevelEntity]>(
      visitImportDecl: visitSyntax(TopLevelStatement.import),
      visitIfConfigDecl: visitSyntax(TopLevelStatement.ifConfig),
      visitClassDecl: visitSyntax(TopLevelStatement.declaration),
      visitStructDecl: visitSyntax(TopLevelStatement.declaration),
      visitEnumDecl: visitSyntax(TopLevelStatement.declaration),
      visitActorDecl: visitSyntax(TopLevelStatement.declaration),
      visitExtensionDecl: visitSyntax(TopLevelStatement.extension),
      visitProtocolDecl: visitSyntax(TopLevelStatement.declaration),
      visitFunctionDecl: visitSyntax(TopLevelStatement.declaration),
      visitVariableDecl: visitSyntax(TopLevelStatement.declaration),
      visitMemberBlockItemList: visitSyntax(TopLevelStatement.declaration),
    ).filterInactiveIfConfig(config: ifConfig)
  }

private let memberBlockVisitorFactory: @Sendable (CompilationConditionsConfig)
  -> SyntaxVisitor<[MemberBlockEntity]> = { ifConfig in
    SyntaxVisitor<[MemberBlockEntity]>(
      visitClassDecl: visitSyntax(MemberBlockStatement.declaration),
      visitStructDecl: visitSyntax(MemberBlockStatement.declaration),
      visitEnumDecl: visitSyntax(MemberBlockStatement.declaration),
      visitFunctionDecl: visitSyntax(MemberBlockStatement.declaration),
      visitInitializerDecl: visitSyntax(MemberBlockStatement.initializer),
      visitVariableDecl: visitSyntax(MemberBlockStatement.declaration),
      visitMemberBlockItemList: visitSyntax(MemberBlockStatement.declaration),
    ).filterInactiveIfConfig(config: ifConfig)
  }

private let codeBlockVisitorFactory: @Sendable (CompilationConditionsConfig)
  -> SyntaxVisitor<[CodeBlockEntity]> = { ifConfig in
    SyntaxVisitor<[CodeBlockEntity]>(
      visitFunctionDecl: visitSyntax(CodeBlockStatement.decl),
      visitDeferStmt: visitSyntax { CodeBlockStatement.stmt(.defer($0)) },
      visitDoStmt: visitSyntax { CodeBlockStatement.stmt(.do($0)) },
      visitClosureExpr: visitSyntax { CodeBlockStatement.expr(.closure($0)) },
      visitFunctionCallExpr: visitSyntax { CodeBlockStatement.expr(.functionCall($0)) },
      visitVariableDecl: visitSyntax(CodeBlockStatement.decl),
      visitCodeBlockItemList: visitSyntax { CodeBlockStatement.stmt(.other($0)) },
    ).filterInactiveIfConfig(config: ifConfig)
  }

// MARK: Visitor Helpers

extension GeneralVisitor {
  fileprivate func walk<T>(
    syntax: some SyntaxProtocol
  ) -> State where State == [T] {
    walk(initial: [], syntax: syntax)
  }
}

private protocol SyntaxDescriptionProvider: SyntaxProtocol {
  associatedtype Description
  func syntaxDescription(context: Context) -> Description
}

extension SyntaxDescriptionProvider {
  fileprivate func entityDescription(context: Context) -> SXT.Entity<Description> {
    .init(value: syntaxDescription(context: context), syntax: self)
  }
}

private func visitSyntax<Provider, Description, Statement>(
  _ factory: @escaping (Description) -> Statement
) -> SyntaxVisitor<[SXT.Entity<Statement>]>.Visitor<Provider>
  where Provider: SyntaxDescriptionProvider, Provider.Description == Description {
  { state, syntax in
    state.sxt.append(.init(
      value: factory(syntax.syntaxDescription(context: state.ctx)),
      syntax: syntax
    ))
    return .skipChildren
  }
}

extension SXT.Entity {
  init(value: T, syntax: some SyntaxProtocol) {
    self.init(value: value, syntax: Syntax(syntax))
  }
}

// MARK: Import Declaration

extension ImportDeclSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.ImportDecl {
    .init(
      attributes: Attributes(attributes, context: context),
      visibility: Visibility(modifiers),
      type: importKindSpecifier?.trimmedDescription,
      moduleName: path.first?.name.trimmedDescription ?? "",
      path: path.dropFirst().map(\.name.trimmedDescription)
    )
  }
}

// MARK: Concrete Type Declaration

private protocol TypeDeclSyntax: SyntaxDescriptionProvider {
  typealias Kind = SXT.TypeDecl.Kind

  var kind: Kind { get }
  var name: TokenSyntax { get }
  var attributes: AttributeListSyntax { get }
  var modifiers: DeclModifierListSyntax { get }
  var memberBlock: MemberBlockSyntax { get }
}

extension TypeDeclSyntax {
  fileprivate func syntaxDescription(context: Context) -> SXT.Declaration {
    .type(.init(
      name: name.text, kind: kind,
      attributes: Attributes(attributes, context: context),
      visibility: Visibility(modifiers),
      modifiers: modifiers.compactMap(SXT.DeclModifier.init),
      members: memberBlock.parsedMemberBlock(context: context)
    ))
  }
}

extension ClassDeclSyntax: TypeDeclSyntax {
  fileprivate var kind: Kind { .class }
}

extension StructDeclSyntax: TypeDeclSyntax {
  fileprivate var kind: Kind { .struct }
}

extension EnumDeclSyntax: TypeDeclSyntax {
  fileprivate var kind: Kind { .enum }
}

extension ActorDeclSyntax: TypeDeclSyntax {
  fileprivate var kind: Kind { .actor }
}

// MARK: Extension Declaration

extension ExtensionDeclSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.Extension {
    .init(
      extendedType: extendedType.parsedType(context: context),
      attributes: Attributes(attributes, context: context),
      visibility: Visibility(modifiers),
      members: memberBlock.parsedMemberBlock(context: context)
    )
  }
}

extension ProtocolDeclSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.Declaration {
    SXT.Declaration.protocol(.init(
      name: name.text,
      attributes: Attributes(attributes, context: context),
      visibility: Visibility(modifiers),
      members: memberBlock.parsedMemberBlock(context: context)
    ))
  }
}

extension IfConfigDeclSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.IfConfig {
    .init(clauses: clauses.map { $0.syntaxDescription(context: context) })
  }
}

extension IfConfigClauseSyntax {
  fileprivate func syntaxDescription(context: Context) -> SXT.IfConfig.Clause {
    let parsedCondition = condition.map(Syntax.init(_:)).map {
      poundKeyword.tokenKind == .poundIf ?
        SXT.IfConfig.Condition.if($0) : .elif($0)
    } ?? .else

    return SXT.IfConfig.Clause(
      condition: parsedCondition,
      body: elements.map {
        context.fileVisitor().walk(initial: ([], context), syntax: $0).sxt
      } ?? []
    )
  }
}

// MARK: Member Block Declaration

extension MemberBlockItemListSyntax: SyntaxDescriptionProvider {
  fileprivate func parsedMemberBlock(context: Context) -> SXT.MemberBlock {
    flatMap { context.memberBlockVisitor().walk(initial: ([], context), syntax: $0).sxt }
  }

  fileprivate func syntaxDescription(context: Context) -> SXT.Declaration {
    .memberBlock(parsedMemberBlock(context: context))
  }
}

extension MemberBlockSyntax {
  fileprivate func parsedMemberBlock(context: Context) -> SXT.MemberBlock {
    members.parsedMemberBlock(context: context)
  }
}

// MARK: Function Declaration Parameter

extension FunctionSignatureSyntax {
  fileprivate func parsedParameters(context: Context) -> [SXT.Parameter] {
    parameterClause.parameters.map {
      SXT.Parameter(
        firstName: SXT.Entity(value: $0.firstName.asParameterName, syntax: self),
        secondName: $0.secondName.map {
          SXT.Entity(value: $0.asParameterName, syntax: self)
        },
        type: SXT.Entity(
          value: $0.type.parsedType(context: context),
          syntax: $0
        ),
        hasDefaultValue: $0.defaultValue != nil
      )
    }
  }
}

extension ClosureSignatureSyntax {
  fileprivate func parsedParameters(
    context: Context
  ) -> [SXT.ClosureParameter]? {
    switch parameterClause {
    case let .parameterClause(clause):
      clause.parameters.map {
        SXT.ClosureParameter(
          name: SXT.Entity(
            value: ($0.secondName ?? $0.firstName).asParameterName,
            syntax: self
          ),
          type: $0.type?.parsedType(context: context),
          hasDefaultValue: false
        )
      }
    case let .simpleInput(clause):
      clause.map {
        SXT.ClosureParameter(
          name: SXT.Entity(
            value: $0.name.asParameterName,
            syntax: self
          ),
          type: nil,
          hasDefaultValue: false
        )
      }
    case nil:
      nil
    }
  }
}

extension TokenSyntax {
  fileprivate var asParameterName: SXT.Parameter.Name {
    switch tokenKind {
    case .wildcard: .wildcard
    default: .literal(text)
    }
  }
}

// MARK: Function Declaration

extension FunctionDeclSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.Declaration {
    .function(.init(
      name: name.description,
      attributes: Attributes(attributes, context: context),
      visibility: Visibility(modifiers),
      affiliation: Affiliation(modifiers),
      modifiers: modifiers.compactMap(SXT.DeclModifier.init),
      parameters: signature.parsedParameters(context: context),
      returnType: signature.returnClause.map {
        SXT.Entity(
          value: $0.type.parsedType(context: context),
          syntax: $0.type
        )
      },
      body: body?.syntaxDescription(context: context)
    ))
  }
}

// MARK: Initializer Declaration

extension InitializerDeclSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.InitializerDecl {
    .init(
      attributes: Attributes(attributes, context: context),
      visibility: Visibility(modifiers),
      modifiers: modifiers.compactMap(SXT.DeclModifier.init),
      optional: optionalMark?.tokenKind == .postfixQuestionMark,
      parameters: signature.parsedParameters(context: context),
      body: body?.syntaxDescription(context: context)
    )
  }
}

// MARK: Closure Block Declaration

extension ClosureExprSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.ClosureExpr {
    .init(
      captures: signature?.capture?.syntaxDescription(context: context),
      parameters: signature?.parsedParameters(context: context),
      body: statements.syntaxDescription(context: context)
    )
  }
}

extension ClosureCaptureClauseSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> [SXT.ClosureExpr.Capture] {
    items.map { $0.entityDescription(context: context) }
  }
}

extension ClosureCaptureSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.ClosureExpr.CaptureDescription {
    SXT.ClosureExpr.CaptureDescription(
      name: name.text,
      expression: initializer?.value.entityDescription(context: context)
    )
  }
}

extension ExprSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.Expression {
    switch self.as(ExprSyntaxEnum.self) {
    case let .functionCallExpr(e):
      .functionCall(e.syntaxDescription(context: context))
    case let .closureExpr(e):
      .closure(e.syntaxDescription(context: context))
    case let .macroExpansionExpr(e):
      .macroExpansion(e.macroName.text)
    case let .declReferenceExpr(e):
      .declRef(
        e.baseName.text,
        parameters: e.argumentNames.map {
          $0.arguments.map(\.name.text)
        }
      )
    case let .memberAccessExpr(e):
      .memberAccessor(
        base: e.base?.syntaxDescription(context: context) ?? .other([]),
        e.declName.baseName.text
      )
    default:
      .other(context.codeBlockVisitor().walk(
        initial: ([], context), syntax: self
      ).sxt)
    }
  }
}

// MARK: Defer Block Declaration

extension DeferStmtSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.DeferStmt {
    body.syntaxDescription(context: context)
  }
}

// MARK: Do-Catch Statement

extension DoStmtSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.DoStmt {
    SXT.DoStmt(
      body: body.syntaxDescription(context: context),
      catchBodies: catchClauses.map { $0.body.syntaxDescription(context: context) }
    )
  }
}

// MARK: Code Block Declaration

extension CodeBlockItemListSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.CodeBlockItemList {
    flatMap { context.codeBlockVisitor().walk(initial: ([], context), syntax: $0).sxt }
  }
}

extension CodeBlockSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.CodeBlockItemList {
    statements.syntaxDescription(context: context)
  }
}

// MARK: Variable Declaration

extension VariableDeclSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.Declaration {
    .variable(.init(
      constant: bindingSpecifier.tokenKind == .keyword(.let),
      attributes: Attributes(attributes, context: context),
      visibility: Visibility(modifiers),
      affiliation: Affiliation(modifiers),
      bindings: bindings.map { binding in
        let initializer = binding.initializer.map { $0.value.entityDescription(context: context) }
        return .init(
          name: binding.pattern.syntaxDescription,
          type: binding.typeAnnotation?.type.parsedType(context: context),
          initializer: initializer,
          syntax: Syntax(binding),
          accessorBlock: binding.accessorBlock?.syntaxDescription
        )
      }
    ))
  }
}

extension AccessorBlockSyntax {
  fileprivate var syntaxDescription: SXT.AccessorBlock {
    switch self.accessors {
    case .getter: .getter
    case let .accessors(list):
      .multiple(list.map {
        switch $0.accessorSpecifier.tokenKind {
        case .keyword(.get): .getter
        case .keyword(.set): .setter
        default: .other($0.accessorSpecifier.trimmedDescription)
        }
      })
    }
  }
}

extension InitializerClauseSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.Expression {
    value.syntaxDescription(context: context)
  }
}

extension PatternSyntax {
  fileprivate var syntaxDescription: SXT.VariableDecl.Pattern {
    if self.is(WildcardPatternSyntax.self) {
      .wildcard
    } else if let identifier = self.as(IdentifierPatternSyntax.self) {
      .identifier(identifier.identifier.text)
    } else if let tuple = self.as(TuplePatternSyntax.self) {
      .tuple(tuple.elements.map(\.pattern.syntaxDescription))
    } else {
      .unsupported
    }
  }
}

// MARK: Function Call

extension FunctionCallExprSyntax: SyntaxDescriptionProvider {
  fileprivate func syntaxDescription(context: Context) -> SXT.FunctionCall {
    let calledType = calledExpression.asMemberAccess(context: context)
    return SXT.FunctionCall(
      base: calledType?.base,
      name: calledType.map { SXT.Entity(value: $0.head, syntax: self) },
      arguments: arguments.parsedArguments(context: context),
      trailingClosure: trailingClosure.map { $0.entityDescription(context: context) },
      baseExprs: context.codeBlockVisitor()
        .walk(initial: ([], context), syntax: calledExpression).sxt
    )
  }
}

// MARK: Member Components

extension TypeSyntax {
  fileprivate func parsedType(context: Context) -> SXT.TypeModel {
    switch self.as(TypeSyntaxEnum.self) {
    case let .arrayType(t):
      .array(t.element.parsedType(context: context))
    case let .attributedType(t):
      .attributed(
        specifiers: t.specifiers.map(\.trimmed.description),
        .init(t.attributes, context: context),
        t.baseType.parsedType(context: context)
      )
    case .classRestrictionType:
      .classRestriction
    case let .compositionType(t):
      .composition(t.elements.map { $0.type.parsedType(context: context) })
    case let .dictionaryType(t):
      .dictionary(
        key: t.key.parsedType(context: context),
        value: t.value.parsedType(context: context)
      )
    case let .functionType(t):
      .function(
        parameters: t.parameters.map { $0.syntaxDescription(context: context) },
        effects: t.effectSpecifiers?.syntaxDescription(context: context),
        returnType: t.returnClause.type.parsedType(context: context)
      )
    case let .identifierType(t):
      parseIdentifierSyntax(
        t.name, t.genericArgumentClause, context: context
      )
    case let .implicitlyUnwrappedOptionalType(t):
      .unwrappedOptional(t.wrappedType.parsedType(context: context))
    case let .memberType(t):
      .member(
        t.baseType.parsedType(context: context).flattenedMembers + [
          parseIdentifierSyntax(
            t.name, t.genericArgumentClause, context: context
          ),
        ]
      )
    case let .metatypeType(t):
      .metatype(
        base: t.baseType.parsedType(context: context),
        specifier: t.metatypeSpecifier.tokenKind == .keyword(.Type) ?
          .type : .protocol
      )
    case .missingType:
      .missing
    case let .namedOpaqueReturnType(t):
      .namedOpaqueReturn(
        base: t.type.parsedType(context: context),
        generics: t.genericParameterClause.parsedType(context: context)
      )
    case let .optionalType(t):
      .optional(t.wrappedType.parsedType(context: context))
    case let .packElementType(t):
      .packElement(t.pack.parsedType(context: context))
    case let .packExpansionType(t):
      .packExpansion(t.repetitionPattern.parsedType(context: context))
    case let .someOrAnyType(t):
      .someOrAny(
        t.constraint.parsedType(context: context),
        t.someOrAnySpecifier.tokenKind == .keyword(.some) ? .some : .any
      )
    case let .suppressedType(t):
      .suppressed(t.type.parsedType(context: context))
    case let .tupleType(t):
      .tuple(t.elements.map { $0.syntaxDescription(context: context) })
    }
  }

  private func parseIdentifierSyntax(
    _ name: TokenSyntax,
    _ genericArgumentClause: GenericArgumentClauseSyntax?,
    context: Context
  ) -> SXT.TypeModel {
    if let genericArgumentClause {
      .generic(
        base: .identifier(name.text),
        args: genericArgumentClause.parsedType(context: context)
      )
    } else {
      .identifier(name.text)
    }
  }
}

extension TupleTypeElementSyntax {
  fileprivate func syntaxDescription(context: Context) -> SXT.TypeModel.TupleTypeElement {
    let name = firstName.map { ($0.text, secondName?.text) }
    let type = type.parsedType(context: context)
    return .init(name: name, type: type)
  }
}

extension TypeEffectSpecifiersSyntax {
  fileprivate func syntaxDescription(context: Context) -> SXT.TypeModel.EffectSpecifiers {
    SXT.TypeModel.EffectSpecifiers(
      isAsync: asyncSpecifier != nil,
      throws: throwsClause.map {
        (
          $0.throwsSpecifier.tokenKind == .keyword(.throws) ? .throws : .rethrows,
          $0.type?.parsedType(context: context)
        )
      }
    )
  }
}

extension ExprSyntax {
  fileprivate func parsedExpr(context: Context) -> SXT.TypeModel? {
    switch self.as(ExprSyntaxEnum.self) {
    case let .declReferenceExpr(e):
      return .identifier(e.baseName.text)
    case let .forceUnwrapExpr(e):
      let e: SXT.TypeModel? = e.expression.parsedExpr(context: context)
      return e.map { .unwrappedOptional($0) }
    case let .genericSpecializationExpr(e):
      return e.expression.parsedExpr(context: context).map {
        .generic(
          base: $0,
          args: e.genericArgumentClause.parsedType(context: context)
        )
      }
    case let .memberAccessExpr(e):
      return .member(
        (e.base?.parsedExpr(context: context)?.flattenedMembers ?? []) + [
          .identifier(e.declName.baseName.text),
        ]
      )
    case let .optionalChainingExpr(e):
      return e.expression.parsedExpr(context: context).map { .optional($0) }
    case let .tupleExpr(e):
      return .tuple(e.elements.compactMap {
        guard let expr = $0.expression.parsedExpr(context: context) else { return nil }
        return SXT.TypeModel.TupleTypeElement(
          name: $0.label.map { ($0.text, nil) },
          type: expr
        )
      })
    default:
      return nil
    }
  }
}

extension GenericArgumentClauseSyntax {
  fileprivate func parsedType(context: Context) -> [SXT.TypeModel] {
    arguments.map { $0.argument.parsedType(context: context) }
  }
}

extension GenericArgumentSyntax.Argument {
  fileprivate func parsedType(context: Context) -> SXT.TypeModel {
    switch self {
    case let .type(type):
      type.parsedType(context: context)
    // TODO: handle value generic parameters when implemented
    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0452-integer-generic-parameters.md
    default: // @_spi(ExperimentalLanguageFeatures) case expr(ExprSyntax)
      .identifier("__EXPRESSION__")
    }
  }
}

extension GenericParameterClauseSyntax {
  fileprivate func parsedType(context: Context) -> [SXT.GenericParameter] {
    // TODO: handle `where` clause if ever needed
    parameters.map { parameter in
      SXT.GenericParameter(
        attributes: Attributes(parameter.attributes, context: context),
        name: parameter.name.text,
        specifier: parameter.specifier?.genericParameterSpecifier,
        inheritedType: parameter.inheritedType?.parsedType(context: context)
      )
    }
  }
}

extension TokenSyntax {
  fileprivate var genericParameterSpecifier: SXT.GenericParameter.Specifier? {
    switch tokenKind {
    case .keyword(.each): .each
    case .keyword(.let): .let
    default: nil
    }
  }
}

extension SXT.TypeModel {
  fileprivate var flattenedMembers: [SXT.TypeModel] {
    switch self {
    case let .member(m): m
    default: [self]
    }
  }
}

// MARK: Visibility

extension Visibility {
  fileprivate init(_ declModifiers: DeclModifierListSyntax) {
    var result = Visibility.default

    for modifier in declModifiers {
      switch modifier.name.tokenKind {
      case .keyword(.private):
        result = .private
      case .keyword(.fileprivate):
        result = .fileprivate
      case .keyword(.internal):
        result = .internal
      case .keyword(.package):
        result = .package
      case .keyword(.public):
        result = .public
      case .keyword(.open):
        result = .open
      default:
        break
      }
    }

    self = result
  }
}

// MARK: Affiliation

extension Affiliation {
  fileprivate init(_ declModifiers: DeclModifierListSyntax) {
    var result = Affiliation.instance
    for modifier in declModifiers {
      switch modifier.name.tokenKind {
      case .keyword(.class):
        result = .class
      case .keyword(.static):
        result = .static
      default:
        break
      }
    }
    self = result
  }
}

// MARK: DeclModifier

extension SXT.DeclModifier {
  fileprivate init?(_ modifier: DeclModifierSyntax) {
    switch modifier.name.tokenKind {
    case .keyword(.override):
      self = .override
    case .keyword(.final):
      self = .final
    case .keyword(.open):
      self = .open
    case .keyword(.convenience):
      self = .convenience
    default:
      return nil
    }
  }
}

// MARK: Attributes

private let implicitAttributeNames = [
  ImplicitKeyword.Annotation.implicit,
  ImplicitKeyword.Annotation.implicitable,
]

extension Attributes {
  fileprivate init(_ list: AttributeListSyntax, context: Context) {
    self = list.compactMap { (attribute: AttributeListSyntax.Element) -> SXT.Attribute? in
      let attribute: AttributeSyntax? =
        switch attribute {
        case let .attribute(attribute):
          attribute
        case .ifConfigDecl:
          nil
        }
      guard let attribute else { return nil }

      let parameters: Arguments? = attribute.arguments?.parsedArguments(context: context)

      return .init(
        name: attribute.attributeName.parsedType(context: context),
        arguments: parameters
      )
    }
  }

  fileprivate init?(_ list: AttributeListSyntax?, context: Context) {
    if let list {
      self = .init(list, context: context)
    } else {
      return nil
    }
  }
}

extension AttributeSyntax.Arguments {
  fileprivate func parsedArguments(context: Context) -> Arguments? {
    switch self {
    case let .argumentList(labeled):
      labeled.parsedArguments(context: context)
    case let .token(token):
      .init([.init(
        name: nil,
        value: .init(
          value: .reference(.identifier(token.trimmedDescription)),
          syntax: token
        )
      )])
    default:
      nil
    }
  }
}

// MARK: Arguments

extension LabeledExprListSyntax {
  fileprivate func parsedArguments(context: Context) -> Arguments {
    map { SXT.Argument(
      name: $0.label.map { SXT.Entity(value: $0.text, syntax: $0) },
      value: SXT.Entity(value: $0.value(context: context), syntax: $0.expression)
    ) }
  }
}

extension LabeledExprSyntax {
  fileprivate func value(context: Context) -> SXT.Argument.Value {
    if let (base, name) = expression.asMemberAccess(context: context), let base,
       case let .identifier(name) = name, name == "self" {
      .explicitType(base)
    } else if let keyPath = expression.as(KeyPathExprSyntax.self) {
      .keyed(keyPath.components.compactMap {
        $0.component
          .as(KeyPathPropertyComponentSyntax.self)?
          .declName.baseName.text
      })
    } else {
      if let parsedExpr = expression.parsedExpr(context: context) {
        .reference(parsedExpr)
      } else {
        .other(context.codeBlockVisitor().walk(initial: ([], context), syntax: expression).sxt)
      }
    }
  }
}

extension ExprSyntax {
  fileprivate func asMemberAccess(
    context: Context
  ) -> (base: SXT.TypeModel?, head: SXT.TypeModel)? {
    guard let expr = parsedExpr(context: context) else { return nil }
    switch expr {
    case let .member(members):
      guard let head = members.last else { return nil }
      let baseMembers = members.dropLast()
      let base: SXT.TypeModel =
        if baseMembers.count == 1, let member = baseMembers.first {
          member
        } else {
          .member(Array(baseMembers))
        }
      return (base, head)
    case .identifier, .generic:
      return (base: nil, head: expr)
    default: return nil
    }
  }
}
