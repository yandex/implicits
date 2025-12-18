// Copyright 2023 Yandex LLC. All rights reserved.

import ImplicitsShared

protocol SyntaxAdditionalInfo {
  associatedtype Syntax
  static func location(of syntax: Syntax) -> Diagnostic.Location
}

enum SemaTreeBuilder<
  Syntax, SyntaxInfo: SyntaxAdditionalInfo
> where SyntaxInfo.Syntax == Syntax {
  typealias SMT = SemaTree<Syntax>

  typealias TopLevelNode = SMT.TopLevelNode
  typealias TopLevel = SMT.TopLevel
  typealias MemberBlockNode = SMT.MemberBlockNode
  typealias MemberBlockItem = SMT.MemberBlockItem
  typealias CodeBlockItem = SMT.CodeBlockItem

  typealias SXT = SyntaxTree<Syntax>

  typealias File = (name: String, content: [SXT.TopLevelEntity])
  typealias TopLevelStatement = SXT.TopLevelStatement
  typealias MemberBlockStatement = SXT.MemberBlockStatement
  typealias CodeBlockStatement = SXT.CodeBlockStatement
  typealias TopLevelEntity = SXT.TopLevelEntity
  typealias MemberBlockEntity = SXT.MemberBlockEntity
  typealias CodeBlockEntity = SXT.CodeBlockEntity
  typealias Attributes = SXT.Attributes
  typealias Arguments = SXT.Arguments
  typealias Affiliation = SXT.Affiliation

  typealias Diagnostics = DiagnosticsGeneric<Syntax>

  typealias Symbol = SymbolInfo<Syntax>
  typealias Dependencies = [
    String: (
      symbols: [Symbol], testableSymbols: [Symbol], reexports: [String]
    )
  ]

  static func build(
    modulename: String,
    module: [File],
    dependencies: Dependencies,
    enableExporting: Bool,
    diagnostics: inout Diagnostics
  ) -> [[TopLevel]] {
    var context = ModuleContext(
      moduleName: modulename, dependencies: dependencies,
      enableExporting: enableExporting
    )
    let scouting = module.reduce(into: Scout.Result()) {
      $0 += Scout.lookaheadFile(
        $1.content, file: $1.name,
        scope: .module, dependencies: dependencies
      )
    }
    context.symbols.addLookaheads(scouting.symbols.map(\.0))
    context.failedInitializers = .init(scouting.failedInitializers) { $0 + $1 }
    let semas = module.map { entities in
      build(
        file: entities.name, entities: entities.content,
        context: &context[file: entities.content, name: entities.name]
      )
    }
    diagnostics += context.diagnostics

    return semas
  }

  static func build(
    file: String,
    entities: [SyntaxTree<Syntax>.TopLevelEntity],
    context: inout FileContext
  ) -> [TopLevel] {
    let scouting = Scout.lookaheadFile(
      entities, file: file, scope: .file,
      dependencies: context.dependencies
    )
    context.symbols.addLookaheads(scouting.symbols.map(\.0))
    context.failedInitializers = .init(scouting.failedInitializers) { $0 + $1 }
    let result = entities.flatMap {
      visit(
        topLevelEntity: $0,
        context: &context[topLevel: $0]
      )
    }
    return result
  }

  fileprivate static func visit(
    topLevelEntity entity: TopLevelEntity,
    context: inout Context
  ) -> [TopLevel] {
    switch entity.value {
    case .import:
      break
    case let .ifConfig(ifConfig):
      return ifConfig.clauses.flatMap {
        $0.body.flatMap {
          visit(
            topLevelEntity: $0,
            context: &context // FIXME: [context]
          )
        }
      }
    case let .declaration(decl):
      switch decl {
      case let .type(typeDecl):
        return [
          .init(syntax: entity.syntax, node: .typeDeclaration(
            visit(
              typeDecl: typeDecl,
              syntax: entity.syntax,
              context: &context
            )
          )),
        ]
      case let .protocol(protocolDecl):
        visit(protocolDecl: protocolDecl, context: &context)
      case let .function(decl):
        return [.init(syntax: entity.syntax, node: .functionDeclaration(
          visit(
            decl, isEnclosigTypeFinal: true, // top-level
            syntax: entity.syntax,
            context: &context[funcDecl: decl]
          )
        ))]
      case .variable:
        break
      case .memberBlock:
        context.diagnose(.unsupportedDeclSyntax, at: entity.syntax)
        return []
      }
    case let .extension(decl):
      let namespace = context
        .canonicalNameOfExtension(decl.extendedType, syntax: entity.syntax)
      if let namespace, namespace.isImplicitKeys {
        return .item(.keysDeclaration(
          visitImplicitsKeys(decl, diagnostics: &context.diagnostics)
        ), at: entity.syntax)
      }
      return .item(.extensionDeclaration(
        namespace,
        visit(
          memberBlockEntities: decl.members,
          isEnclosigTypeFinal: true, // extension cannot contain overridable members
          context: &context[extensionNamespace: namespace]
        )
      ), at: entity.syntax)
    }
    return []
  }

  private static func visitImplicitsKeys(
    _ decl: SXT.Extension,
    diagnostics: inout Diagnostics
  ) -> [Sema.ImplicitKeyDecl] {
    decl.members.flatMap { (entity: SXT.MemberBlockEntity) -> [Sema.ImplicitKeyDecl] in
      switch entity.value {
      case let .declaration(.variable(varDecl)):
        guard varDecl.affiliation == .static else {
          diagnostics.diagnose(
            .nonStaticInsideImplicitsKeys, at: entity.syntax
          )
          return []
        }
        let visibility = varDecl.visibility
        return varDecl.bindings.compactMap { binding in
          switch (binding.name, binding.initializer?.value) {
          case let (.identifier(name), .functionCall(fcall)):
            switch fcall.name?.value {
            case let .generic(base: .identifier("Key"), args: args):
              guard let type = args.first, args.count == 1 else {
                diagnostics.diagnose(
                  .unexpectedContentInsideImplicitsKeys, at: entity.syntax
                )
                return nil
              }
              let key = Sema.ImplicitKeyDecl(
                name: name,
                type: type.description,
                visibility: visibility
              )
              return key
            default:
              return nil
            }
          default:
            diagnostics.diagnose(
              .unexpectedContentInsideImplicitsKeys, at: entity.syntax
            )
            return nil
          }
        }
      default:
        diagnostics.diagnose(
          .unexpectedContentInsideImplicitsKeys, at: entity.syntax
        )
        return []
      }
    }
  }

  private static func visit(
    typeDecl: SXT.TypeDecl,
    syntax: Syntax,
    context: inout Context
  ) -> SMT.TypeDecl {
    SMT.TypeDecl(
      name: context.canonicalName(of: typeDecl),
      members: visit(
        memberBlockEntities: typeDecl.members,
        isEnclosigTypeFinal: typeDecl.isFinal,
        context: &context[type: typeDecl, syntax]
      )
    )
  }

  private static func visit(
    protocolDecl: SXT.ProtocolDecl,
    context: inout Context
  ) {
    func visit(members: SXT.MemberBlock) {
      for member in members {
        switch member.value {
        case let .initializer(initializer):
          let hasScope = checkFuncDeclScopeParams(
            initializer.parameters, errors: &context.diagnostics
          )
          if hasScope {
            context.diagnose(
              .noDynamicDispatch(.protocolFunction), at: member.syntax
            )
          }
        case let .declaration(decl):
          switch decl {
          case let .function(f):
            let hasScope = checkFuncDeclScopeParams(
              f.parameters, errors: &context.diagnostics
            )
            if hasScope {
              context.diagnose(
                .noDynamicDispatch(.protocolFunction), at: member.syntax
              )
            }
          case .variable:
            break
          case let .memberBlock(members):
            visit(members: members)
          case .protocol, .type:
            context.diagnose(.unsupportedSyntaxInProtocol, at: member.syntax)
          }
        }
      }
    }
    visit(members: protocolDecl.members)
  }

  private static func visit(
    memberBlockEntity entity: MemberBlockEntity,
    isEnclosigTypeFinal: Bool,
    context: inout Context
  ) -> [MemberBlockItem] {
    switch entity.value {
    case let .declaration(decl):
      switch decl {
      case let .type(typeDecl):
        .item(
          .typeDeclaration(visit(
            typeDecl: typeDecl,
            syntax: entity.syntax,
            context: &context // FIXME: [context]
          )),
          at: entity.syntax
        )
      case let .protocol(decl):
        {
          visit(protocolDecl: decl, context: &context)
          return []
        }()
      case let .function(decl):
        .item(
          .functionDeclaration(visit(
            decl, isEnclosigTypeFinal: isEnclosigTypeFinal,
            syntax: entity.syntax,
            context: &context[funcDecl: decl]
          )),
          at: entity.syntax
        )
      case let .variable(variableDecl):
        visitMemberVariableDecl(
          variableDecl, syntax: entity.syntax, context: &context
        )
      case let .memberBlock(memberBlock):
        visit(
          memberBlockEntities: memberBlock,
          isEnclosigTypeFinal: isEnclosigTypeFinal,
          context: &context // FIXME: [context]
        )
      }
    case let .initializer(initializer):
      .item(
        .functionDeclaration(
          visit(
            initializer,
            syntax: entity.syntax,
            context: &context[initDecl: initializer]
          )
        ),
        at: entity.syntax
      )
    }
  }

  private static func visit(
    codeBlockEntity entity: CodeBlockEntity,
    context: inout Context
  ) -> [CodeBlockItem] {
    switch entity.value {
    case let .decl(decl):
      // Defer is a hack, so new decl will not shadow existing decls.
      // Remove when proper member resolution and scope nesting will be
      // implemented.
      defer { context.registerDeclaration(decl) }
      switch decl {
      case let .type(typeDecl):
        return .item(
          .typeDeclaration(visit(
            typeDecl: typeDecl,
            syntax: entity.syntax,
            context: &context // FIXME: [context]
          )),
          at: entity.syntax
        )
      case let .protocol(protocolDecl):
        visit(protocolDecl: protocolDecl, context: &context)
        return []
      case let .function(functionDecl):
        return [.init(syntax: entity.syntax, node: .functionDeclaration(
          visit(
            functionDecl, isEnclosigTypeFinal: true, // inside CodeBlock
            syntax: entity.syntax,
            context: &context[funcDecl: functionDecl]
          )
        ))]
      case let .variable(variable):
        return visit(
          variable: variable,
          syntax: entity.syntax,
          context: &context
        )
      case .memberBlock:
        context.diagnose(.unsupportedDeclSyntax, at: entity.syntax)
        return []
      }
    case let .expr(expression):
      return visit(
        expression: expression,
        syntax: entity.syntax,
        context: &context
      )
    case let .stmt(statement):
      return visit(
        statement: statement,
        syntax: entity.syntax,
        context: &context
      )
    }
  }

  private static func visit(
    statement: SXT.Statement,
    syntax: Syntax,
    context: inout Context
  ) -> [CodeBlockItem] {
    switch statement {
    case let .defer(deferStmt):
      let deferNodes = visit(
        codeBlockEntities: deferStmt,
        context: &context // FIXME: [context]
      )

      deferNodes.forEach { node in
        if case .functionCall = node.node {
          context
            .diagnose(.implicitScope_CantUseInDefer, at: syntax)
        }
      }

      return [.init(syntax: syntax, node: .deferStatement(deferNodes))]
    case let .do(doStmt):
      let bodyNodes = visit(
        codeBlockEntities: doStmt.body,
        context: &context
      )
      var result: [CodeBlockItem] = .item(.innerScope(bodyNodes), at: syntax)
      for catchBody in doStmt.catchBodies {
        let catchNodes = visit(codeBlockEntities: catchBody, context: &context)
        result += .item(.innerScope(catchNodes), at: syntax)
      }
      return result
    case let .other(codeBlock):
      return .item(
        .innerScope(
          visit(
            codeBlockEntities: codeBlock,
            context: &context // FIXME: [context]
          )
        ),
        at: syntax
      )
    }
  }

  private static func visit(
    memberBlockEntities entities: [MemberBlockEntity],
    isEnclosigTypeFinal: Bool,
    context: inout Context
  ) -> [MemberBlockItem] {
    entities.flatMap { visit(
      memberBlockEntity: $0,
      isEnclosigTypeFinal: isEnclosigTypeFinal,
      context: &context // FIXME: [context]
    ) }
  }

  private static func visit(
    closure: SXT.ClosureExpr,
    context: inout Context
  ) -> SMT.ClosureExpression {
    let body = visit(
      codeBlockEntities: closure.body,
      context: &context
    )
    let bag = closure.captures.flatMap {
      analyzeClosureCaptureListForImplicitBag(
        $0, errors: &context.diagnostics
      )
    }

    return SMT.ClosureExpression(bag: bag, body: body)
  }

  private static func visit(
    codeBlockEntities entities: [CodeBlockEntity],
    context: inout Context
  ) -> [CodeBlockItem] {
    entities.flatMap { visit(
      codeBlockEntity: $0,
      context: &context
    ) }
  }

  private static func visit(
    _ funcDecl: SXT.FunctionDecl,
    isEnclosigTypeFinal: Bool,
    syntax: Syntax,
    context: inout Context
  ) -> SMT.FuncDecl {
    let hasImplicitScope =
      checkFuncDeclScopeParams(funcDecl.parameters, errors: &context.diagnostics)

    if hasImplicitScope {
      checkFuncDeclIsStaticlyDispatched(
        funcDecl, isEnclosigTypeFinal: isEnclosigTypeFinal,
        syntax: syntax, errors: &context.diagnostics
      )
    }

    checkForExportingSPI(
      hasImplicitScope: hasImplicitScope,
      visibility: funcDecl.visibility,
      attributes: funcDecl.attributes,
      syntax: syntax, context: &context
    )

    return SMT.FuncDecl(
      signature: context.canonicalSignature(funcDecl, syntax: syntax),
      visibility: funcDecl.visibility,
      modifiers: funcDecl.modifiers.compactMap(Sema.FuncModifier.init),
      hasScopeParameter: hasImplicitScope,
      enclosingTypeIsClass: context.enclosingTypeIsClass,
      parameters: funcDecl.parameters.filter { !$0.isScopeParameter }.map {
        (
          $0.firstName.value.description,
          $0.type.strictDescription(errors: &context.diagnostics)
        )
      },
      returnType: funcDecl.returnType.map {
        $0.strictDescription(errors: &context.diagnostics)
      },
      body: visit(
        codeBlockEntities: funcDecl.body ?? [], // FIXME: [emptyBody]
        context: &context // FIXME: [context]
      )
    )
  }

  private static func visit(
    _ funcDecl: SXT.InitializerDecl,
    syntax: Syntax,
    context: inout Context
  ) -> SMT.FuncDecl {
    let hasImplicitScope =
      checkFuncDeclScopeParams(funcDecl.parameters, errors: &context.diagnostics)

    checkForExportingSPI(
      hasImplicitScope: hasImplicitScope,
      visibility: funcDecl.visibility,
      attributes: funcDecl.attributes,
      syntax: syntax, context: &context
    )

    let parameters = funcDecl.parameters.filter { !$0.isScopeParameter }.map {
      (
        $0.firstName.value.description,
        $0.type.strictDescription(errors: &context.diagnostics)
      )
    }
    return SMT.FuncDecl(
      signature: context.canonicalSignature(funcDecl, syntax: syntax),
      visibility: funcDecl.visibility,
      modifiers: funcDecl.modifiers.compactMap(Sema.FuncModifier.init),
      hasScopeParameter: hasImplicitScope,
      enclosingTypeIsClass: context.enclosingTypeIsClass,
      parameters: parameters,
      returnType: nil,
      body: visit(
        codeBlockEntities: funcDecl.body ?? [], // FIXME: [emptyBody]
        context: &context // FIXME: [context]
      )
    )
  }

  private static func checkFuncDeclIsStaticlyDispatched(
    _ funcDecl: SXT.FunctionDecl,
    isEnclosigTypeFinal: Bool,
    syntax: Syntax,
    errors: inout Diagnostics
  ) {
    let reason: DiagnosticMessage.Context? =
      if funcDecl.affiliation == .class {
        .classModifier
      } else if funcDecl.modifiers.contains(.override) {
        .overrideKeyword
      } else if funcDecl.visibility == .open {
        .openKeyword
      } else if !isEnclosigTypeFinal, !funcDecl.modifiers.contains(.final) {
        .notFinal
      } else {
        nil
      }
    if let reason {
      errors.diagnose(.noDynamicDispatch(reason), at: syntax)
    }
  }

  // Returns whether the function declaration has an implicit scope parameter.
  private static func checkFuncDeclScopeParams(
    _ params: [SXT.Parameter],
    errors: inout Diagnostics
  ) -> Bool {
    let scopeParams = params.filter(\.isScopeParameter)
    if scopeParams.count > 1, let excess = scopeParams.last {
      errors.diagnose(
        .excessImplicitScopeParameter,
        at: excess.firstName.syntax
      )
    }
    for param in scopeParams {
      let firstName = param.firstName
      errors.check(
        firstName.value.isWildcard,
        or: .scopeArgIsNotWildcard,
        at: firstName.syntax
      )

      if let secondName = param.secondName,
         let literal = secondName.value.literal {
        errors.check(
          literal == ImplicitKeyword.Scope.variableName,
          or: .wrongScopeArgName(literal),
          at: secondName.syntax
        )
      }
    }
    return !scopeParams.isEmpty
  }

  private static func visit(
    typeModel: SXT.Entity<SXT.TypeModel>,
    errors: inout Diagnostics
  ) {
    visit(typeModel: typeModel.value, syntax: typeModel.syntax, errors: &errors)
  }

  private static func visit(
    variable: SXT.VariableDecl,
    syntax _: Syntax,
    context: inout Context
  ) -> [CodeBlockItem] {
    variable.bindings.reduce(into: [CodeBlockItem]()) { partialResult, binding in
      partialResult += visit(
        binding: binding, attributes: variable.attributes,
        isConstant: variable.constant,
        context: &context
      )
    }
  }

  private static func visit(
    binding: SXT.VariableDecl.Binding,
    attributes: SXT.Attributes,
    isConstant: Bool,
    context: inout Context
  ) -> [CodeBlockItem] {
    let syntax = binding.syntax
    context.check(
      binding.type?.description != ImplicitKeyword.Scope.className,
      or: .redundantTypeAnnotation, at: syntax
    )

    var nestedNodes: [CodeBlockItem] = []

    if let initializer = binding.initializer {
      nestedNodes += visit(
        varInitializer: initializer.value,
        syntax: syntax,
        isConstant: isConstant,
        context: &context
      )
    }
    let implicit = analyzeBindingForImplicit(
      binding,
      attributes: attributes,
      context: &context
    )
    if let implicit {
      nestedNodes.append(
        .init(syntax: syntax, node: .implicit(implicit))
      )
    }

    return nestedNodes
  }

  private static func visit(
    varInitializer: SXT.Expression,
    syntax: Syntax,
    isConstant: Bool,
    context: inout Context
  ) -> [CodeBlockItem] {
    var nodes: [CodeBlockItem] = []
    switch varInitializer {
    case let .functionCall(functionCall):
      let fcall = visit(
        functionCall: functionCall,
        syntax: syntax,
        context: &context
      )
      switch fcall {
      case let .implicitScopeInit(withBag: hasBag):
        context.check(isConstant, or: .scopeDeclMustBeConst, at: syntax)
        nodes.append(
          .implicitScopeBegin(nested: false, withBag: hasBag), syntax: syntax
        )
      case let .scopeNested(withBag: hasBag):
        context.check(isConstant, or: .scopeDeclMustBeConst, at: syntax)
        nodes.append(
          .implicitScopeBegin(nested: true, withBag: hasBag),
          syntax: syntax
        )
      case .scopeEnd:
        context.diagnose("Unexpected scope.end() in initializer", at: syntax)
      case .implicitMap:
        context.diagnose("Unexpected Implicit.map in initializer", at: syntax)
      case let .functionWithScope(fcall, nestedExpressions):
        nodes += nestedExpressions
        nodes.append(.functionCall(fcall), syntax: syntax)
      case let .regularFunction(argsAndCalled: items):
        nodes += items
      }
    case let .closure(closure):
      nodes += .item(
        .closureExpression(
          visit(
            closure: closure,
            context: &context
          )
        ),
        at: syntax
      )
    case .declRef, .macroExpansion:
      break
    case let .memberAccessor(base: base, _):
      nodes += visit(
        varInitializer: base,
        syntax: syntax,
        isConstant: isConstant,
        context: &context
      )
    case let .other(other):
      nodes.append(
        contentsOf: visit(
          codeBlockEntities: other,
          context: &context
        )
      )
    }
    return nodes
  }

  private static func visit(
    typeModel: SXT.TypeModel,
    syntax: Syntax,
    errors: inout Diagnostics
  ) {
    switch typeModel {
    case .identifier:
      break
    case let .generic(t, g):
      visit(typeModel: t, syntax: syntax, errors: &errors)
      g.forEach { visit(typeModel: $0, syntax: syntax, errors: &errors) }
    case let .optional(t):
      visit(typeModel: t, syntax: syntax, errors: &errors)
    case let .unwrappedOptional(t):
      visit(typeModel: t, syntax: syntax, errors: &errors)
    case let .tuple(tupleMembers):
      if tupleMembers.count != 1 {
        errors.diagnose(.functionCall_SingleArgumentTupleRequired(tupleMembers.count), at: syntax)
      }
    case let .member(members):
      members.forEach { visit(typeModel: $0, syntax: syntax, errors: &errors) }
    case .attributed, .classRestriction, .array,
         .composition, .dictionary, .function, .metatype, .missing,
         .namedOpaqueReturn, .packElement, .packExpansion, .someOrAny,
         .suppressed:
      errors.diagnose(.functionCall_KeyPathExpressionOrExplicitTypeRequired, at: syntax)
    }
  }

  private enum FCall {
    case implicitScopeInit(withBag: Bool)
    case scopeNested(withBag: Bool)
    case scopeEnd
    case implicitMap(
      from: ImplicitKey,
      to: ImplicitKey,
      closure: [CodeBlockItem]
    )
    case functionWithScope(Sema.FuncCall, [CodeBlockItem])
    case regularFunction(argsAndCalled: [CodeBlockItem])
  }

  private static func visit(
    functionCall: SXT.FunctionCall,
    syntax: Syntax,
    context: inout Context
  ) -> FCall {
    let base = functionCall.base
    let name = functionCall.name

    if let (nested, withBag, closure, scope) = functionCall.isWithScope() {
      let hasBag = withBag && analyzeImplicitScopeArgs(
        args: functionCall.arguments, errors: &context.diagnostics
      )
      let withScopeBody = visit(
        codeBlockEntities: closure.body,
        context: &context[withScope: closure, scopeParamter: scope]
      )

      return .regularFunction(argsAndCalled: [
        CodeBlockItem(
          syntax: syntax,
          node: .withScope(nested: nested, withBag: hasBag, body: withScopeBody)
        )
      ])
    }

    // withFooImplicits { scope in ... }
    if let (wrapperName, closureParamCount, closure, scopeArg) = functionCall
      .isWithNamedImplicits() {
      let body = visit(
        codeBlockEntities: closure.body,
        context: &context[withScope: closure, scopeParamter: scopeArg]
      )
      return .regularFunction(argsAndCalled: [
        CodeBlockItem(
          syntax: syntax,
          node: .withNamedImplicits(
            wrapperName: wrapperName,
            closureParamCount: closureParamCount,
            body: body
          )
        )
      ])
    }

    // ImplicitScope()
    if functionCall.isImplicitScopeInitializer {
      let hasBag = analyzeImplicitScopeArgs(
        args: functionCall.arguments, errors: &context.diagnostics
      )
      return .implicitScopeInit(withBag: hasBag)
    }
    if let scopeCall = functionCall.isImplicitScopeCall() {
      switch scopeCall {
      case .nested:
        let hasBag = analyzeImplicitScopeArgs(
          args: functionCall.arguments, errors: &context.diagnostics
        )
        return .scopeNested(withBag: hasBag)
      case .end:
        return .scopeEnd
      }
    }

    let trailingClosure: [CodeBlockItem] = functionCall.trailingClosure.map {
      let expr = visit(closure: $0.value, context: &context)
      return .item(.closureExpression(expr), at: $0.syntax)
    } ?? []

    // Implicit.map
    if let base, base.description == ImplicitKeyword.Annotation.implicit,
       name?.value.description == ImplicitKeyword.Map.functionName {
      if functionCall.arguments.count != 2 {
        context.diagnose(
          .implicitMap_UnexpectedArgumentCount(functionCall.arguments.count),
          at: syntax
        )
      }

      if let from = functionCall.arguments.first,
         let to = functionCall.arguments.dropFirst().first {
        let arguments = [from, to]

        arguments.forEach { argument in
          let valueSyntax = argument.value.syntax
          switch argument.value.value {
          case let .keyed(keyPath):
            if keyPath.count > 1 {
              context.diagnose(
                .implicitMap_TooManyKeyPathComponents(keyPath.count),
                at: valueSyntax
              )
            }
          case .explicitType:
            break
          case .reference:
            context.diagnose(
              .implicitMap_KeyPathExpressionOrExplicitTypeRequired,
              at: valueSyntax
            )
          case .other:
            context.diagnose(.implicitMap_unexpectedArgument, at: valueSyntax)
          }
        }
        let fromKey = ImplicitKey(
          arg: from.value.value, errors: &context.diagnostics, syntax: syntax
        )
        let toKey = ImplicitKey(
          arg: to.value.value, errors: &context.diagnostics, syntax: syntax
        )
        if let fromKey, let toKey {
          return .implicitMap(
            from: fromKey,
            to: toKey,
            closure: trailingClosure
          )
        }
      }
    }

    let nested = nestedExpressions(
      in: functionCall.arguments,
      context: &context
    ) + visit(
      codeBlockEntities: functionCall.baseExprs,
      context: &context
    ) + trailingClosure

    // foo(scope)
    if context.hasImplicitScopeVariableInScope,
       functionCall.arguments.contains(where: \.isReferenceToImplicitScope),
       let resolvedCall = context.resolveFunctionSignature(
         functionCall, syntax: syntax
       ) {
      return .functionWithScope(
        SMT.FuncCall(signature: resolvedCall),
        nested
      )
    }

    return .regularFunction(argsAndCalled: nested)
  }

  private static func visit(
    expression: SXT.Expression,
    syntax: Syntax,
    context: inout Context
  ) -> [CodeBlockItem] {
    switch expression {
    case let .functionCall(functionCall):
      return visit(
        expressionFunctionCall: functionCall,
        syntax: syntax,
        context: &context
      )
    case let .closure(closure):
      return .item(
        .closureExpression(
          visit(
            closure: closure,
            context: &context
          )
        ),
        at: syntax
      )
    case .macroExpansion, .declRef, .memberAccessor:
      return []
    case let .other(codeBlockEntities):
      return visit(
        codeBlockEntities: codeBlockEntities,
        context: &context
      )
    }
  }

  private static func visit(
    expressionFunctionCall functionCall: SXT.FunctionCall,
    syntax: Syntax,
    context: inout Context
  ) -> [CodeBlockItem] {
    let fcall = visit(
      functionCall: functionCall,
      syntax: syntax,
      context: &context
    )
    switch fcall {
    case .implicitScopeInit, .scopeNested:
      context
        .diagnose("[WIP] Unexpected implicit control call", at: syntax)
      return []
    case .scopeEnd:
      return [.init(syntax: syntax, node: .implicitScopeEnd)]
    case let .implicitMap(from: from, to: to, closure: closure):
      return closure + .item(.implicitMap(from: from, to: to), at: syntax)
    case let .functionWithScope(fcall, array):
      return array + [
        .init(syntax: syntax, node: .functionCall(fcall)),
      ]
    case let .regularFunction(argsAndCalled: items):
      return items
    }
  }

  private static func visitMemberVariableDecl(
    _ variableDecl: SXT.VariableDecl,
    syntax: Syntax,
    context: inout Context
  ) -> [MemberBlockItem] {
    variableDecl.bindings.compactMap { binding in
      visitMemberVariableBinding(
        binding,
        attributes: variableDecl.attributes,
        syntax: syntax,
        isConstant: variableDecl.constant,
        context: &context
      )
    }
  }

  private static func visitMemberVariableBinding(
    _ binding: SXT.VariableDecl.Binding,
    attributes: SXT.Attributes,
    syntax: Syntax,
    isConstant _: Bool,
    context: inout Context
  ) -> MemberBlockItem? {
    let implicit = analyzeBindingForImplicit(
      binding,
      attributes: attributes,
      context: &context
    )
    if let implicit {
      switch implicit.mode {
      case .get:
        return MemberBlockItem(
          syntax: syntax, node: .implicit(implicit.key)
        )
      case .set:
        context.diagnose(
          .storedPropertyInSetMode, at: binding.syntax
        )
        return nil
      }
    }

    if case let .identifier(name) = binding.name, let initializer = binding.initializer {
      let bag = analyzeExpressionForImplicitBag(
        initializer,
        bindingName: name
      )
      if let bag {
        return MemberBlockItem(
          syntax: syntax,
          node: .bag(bag)
        )
      }
    }

    func visitInitializer(
      _ initializer: SXT.Expression
    ) -> [CodeBlockEntity] {
      switch initializer {
      case let .functionCall(fcall):
        [
          .init(value: .expr(.functionCall(fcall)), syntax: syntax)
        ]
      case let .closure(closure):
        [
          .init(value: .expr(.closure(closure)), syntax: syntax)
        ]
      case .declRef:
        []
      case let .memberAccessor(base: base, _):
        visitInitializer(base)
      case let .other(cb):
        cb
      case .macroExpansion:
        []
      }
    }

    if let initializer = binding.initializer {
      let codeBlock = visitInitializer(initializer.value)
      return MemberBlockItem(
        syntax: syntax,
        node: .field(
          initializer: visit(
            codeBlockEntities: codeBlock,
            context: &context
          )
        )
      )
    }

    return nil
  }

  private static func nestedExpressions(
    in args: SXT.Arguments,
    context: inout Context
  ) -> [CodeBlockItem] {
    args.flatMap { value -> [CodeBlockItem] in
      switch value.value.value {
      case let .other(block):
        visit(
          codeBlockEntities: block,
          context: &context
        )
      case .keyed, .explicitType, .reference:
        []
      }
    }
  }

  /// Return true if args has correct 'with: implicits' argument
  private static func analyzeImplicitScopeArgs(
    args: SXT.Arguments,
    errors: inout Diagnostics
  ) -> Bool {
    args.contains { arg in
      if arg.name?.value == ImplicitKeyword.Scope.bagParameterName {
        if let value = arg.value.value.simpleIdentifier(),
           value == ImplicitKeyword.Bag.variableName {
          return true
        } else {
          errors.diagnose(
            .invalidImplicitBagVariableName,
            at: arg.value.syntax
          )
          return false
        }
      }
      return false
    }
  }

  private static func analyzeClosureCaptureListForImplicitBag(
    _ captureList: [SXT.ClosureExpr.Capture],
    errors _: inout Diagnostics
  ) -> SMT.ImplicitBag? {
    let bags: [SMT.ImplicitBag] = captureList.compactMap { captured in
      captured.value.expression.flatMap {
        analyzeExpressionForImplicitBag($0, bindingName: captured.value.name)
      }
    }
    return bags.first // compiler handles multiple captures with same name
  }

  private static func analyzeExpressionForImplicitBag(
    _ expr: SXT.Entity<SXT.Expression>,
    bindingName: String?
  ) -> SMT.ImplicitBag? {
    guard bindingName == ImplicitKeyword.Bag.variableName else {
      return nil
    }
    switch expr.value {
    case let .functionCall(function):
      guard let bag = function.isImplicitBagInitializer() else { return nil }
      return SMT.ImplicitBag(syntax: expr.syntax, node: bag)
    case let .macroExpansion(name):
      guard name == "implicits" else { return nil }
      let loc = SyntaxInfo.location(of: expr.syntax)
      let filename =
        loc.file.split(separator: "/").last.map(String.init) ?? ""
      let funcName = generateImplicitBagFuncName(
        filename: filename,
        line: loc.line.description,
        column: loc.column.description
      )
      return SMT.ImplicitBag(
        syntax: expr.syntax,
        node: Sema.ImplicitBagDescription(
          fillFunctionName: funcName
        )
      )
    case .other, .declRef, .memberAccessor, .closure:
      return nil
    }
  }

  private static func analyzeBindingForImplicit(
    _ binding: SXT.VariableDecl.Binding,
    attributes: SXT.Attributes,
    context: inout Context
  ) -> SMT.Implicit? {
    let implicit: SMT.Implicit? =
      if let firstAttr = attributes.first, firstAttr.isImplicit {
        context.inferImplicit(
          attributeArguments: firstAttr.arguments,
          binding: binding
        )
      } else {
        nil
      }

    if attributes.dropFirst().contains(where: \.isImplicit) {
      // TODO: Emit error per VariableDecl, not per Binding.
      context.diagnose(
        .wrapedImplicitValue, at: binding.syntax
      )
    }
    return implicit
  }

  private static func checkForExportingSPI(
    hasImplicitScope: Bool,
    visibility: Visibility,
    attributes: SXT.Attributes,
    syntax: Syntax,
    context: inout Context
  ) {
    if hasImplicitScope,
       visibility.moreOrEqualVisible(than: .public),
       context.enableExporting,
       !attributes.contains(where: \.isImplicitSpi) {
      context.diagnose(.publicWithoutSPI, at: syntax)
    }
  }
}

extension SyntaxTree.Argument.Value {
  /// If value represents simple identifier returns it, returns nil otherwise
  func simpleIdentifier() -> String? {
    switch self {
    case let .reference(ref):
      switch ref {
      case let .identifier(identifier):
        identifier
      default:
        nil
      }
    case .other, .explicitType, .keyed:
      nil
    }
  }
}

extension SyntaxTree.Affiliation {
  var isStaticLike: Bool {
    switch self {
    case .static, .class: true
    case .instance: false
    }
  }
}

extension SyntaxTree.Argument {
  fileprivate var isReferenceToImplicitScope: Bool {
    if case let .reference(ref) = value.value {
      ref.description == ImplicitKeyword.Scope.variableName
    } else {
      false
    }
  }
}

extension SyntaxTree.Parameter {
  fileprivate var isScopeParameter: Bool {
    type.value.description == ImplicitKeyword.Scope.className
  }

  var signatureName: String { // FIXME: Dedup
    switch firstName.value {
    case let .literal(literal): literal
    case .wildcard: "_"
    }
  }
}

extension SyntaxTree.Attribute {
  var simpleIdentifier: String? {
    switch self.name {
    case let .identifier(id): id
    default: nil
    }
  }

  var isImplicit: Bool {
    simpleIdentifier == ImplicitKeyword.Annotation.implicit
  }

  var isImplicitSpi: Bool {
    guard
      simpleIdentifier == ImplicitKeyword.SPI.attributeName,
      let args = arguments,
      let arg = args.first, args.count == 1
    else {
      return false
    }
    return arg.value.value.simpleIdentifier() == ImplicitKeyword.SPI.annotationName
  }
}

extension Sema.FuncModifier {
  init?(_ m: SyntaxTreeBuildingBlocks.DeclModifier) {
    switch m {
    case .convenience: self = .convenience
    case .final, .open, .override: return nil
    }
  }
}

extension SemaTreeBuilder.Context {
  mutating func inferImplicit(
    attributeArguments: SXT.Arguments?,
    binding: SXT.VariableDecl.Binding
  ) -> SMT.Implicit? {
    // 1. Check argument
    // 1a. Check if its type or casepath
    // 2. Check variable's declaration type
    // 3. Try to infer type
    let key: ImplicitKey?
    if let keyArg = attributeArguments?.first {
      if let name = keyArg.name {
        diagnose(
          .unexpectedArgumentName(name.value),
          at: name.syntax
        )
      }
      let argValue = keyArg.value
      key = nonNil(
        ImplicitKey(
          arg: argValue.value, errors: &diagnostics, syntax: argValue.syntax
        ),
        or: .unableToInferImplicitKey, at: argValue.syntax
      )
    } else if let varType = binding.type {
      key = ImplicitKey(type: varType, errors: &diagnostics, syntax: binding.syntax)
    } else if let initializer = binding.initializer {
      let resolvedType =
        resolveVariableType(initializer.value, syntax: binding.syntax)
      guard let resolvedType else {
        return nil
      }
      key = .type(resolvedType.description)
    } else {
      // Shouldn't happen without a compiler error
      diagnose(.missingType, at: binding.syntax)
      key = nil
    }
    return key.map {
      SMT.Implicit(
        mode: binding.initializer == nil ? .get : .set,
        key: $0
      )
    }
  }
}

extension SyntaxTree.TypeDecl.Kind {
  var isInheritable: Bool { self == .class }
}

extension SyntaxTree.TypeDecl {
  var isFinal: Bool {
    !kind.isInheritable || modifiers.contains(.final)
  }
}

enum ImplicitScopeCall {
  case nested, end
}

extension SyntaxTree.FunctionCall {
  var isImplicitScopeInitializer: Bool {
    base == nil &&
      name?.value.description == ImplicitKeyword.Scope.className
  }

  // TODO: Callers must ensure that 'scope' variable here is actually
  // an implicit scope variable
  func isImplicitScopeCall() -> ImplicitScopeCall? {
    guard base?.description == ImplicitKeyword.Scope.variableName else {
      return nil
    }
    switch name?.value.description {
    case "nested": return .nested
    case "end": return .end
    default: return nil
    }
  }

  func isImplicitBagInitializer() -> Sema.ImplicitBagDescription? {
    guard let name = name?.value.description, arguments.isEmpty, base == nil
    else { return nil }
    return Sema.ImplicitBagDescription(fillFunctionName: name)
  }

  func getWithScopeArgs() -> (nested: Bool, withBag: Bool, closure: SyntaxTree.ClosureExpr)? {
    var nested = false
    var withBag = false

    switch arguments.count {
    case 0:
      break
    case 1:
      switch arguments[0].name?.value {
      case "nesting":
        nested = true
      case ImplicitKeyword.Scope.bagParameterName:
        withBag = true
      default:
        return nil
      }
    default:
      return nil
    }

    guard let trailingClosure else { return nil }
    return (nested: nested, withBag: withBag, closure: trailingClosure.value)
  }

  func isWithScope()
    -> (nested: Bool, withBag: Bool, closure: SyntaxTree.ClosureExpr, scopeArg: Syntax)? {
    guard base == nil,
          name?.value.description == "withScope",
          let (nested, withBag, closure) = getWithScopeArgs(),
          let params = closure.parameters,
          let scopeArg = params.singleElement,
          scopeArg.isImplicitScope else {
      return nil
    }
    return (nested: nested, withBag: withBag, closure: closure, scopeArg: scopeArg.name.syntax)
  }

  /// Detects pattern: `withFooImplicits { scope in ... }` or `withFooImplicits { arg1, arg2, scope
  /// in ... }`
  func isWithNamedImplicits() -> (
    wrapperName: String,
    closureParamCount: Int,
    closure: SyntaxTree.ClosureExpr,
    scopeArg: Syntax
  )? {
    guard base == nil else { return nil }
    guard let funcName = name?.value.description,
          funcName.hasPrefix(ImplicitKeyword.ClosureWrapper.prefix),
          funcName.hasSuffix(ImplicitKeyword.ClosureWrapper.suffix) else {
      return nil
    }

    let prefixLen = ImplicitKeyword.ClosureWrapper.prefix.count
    let suffixLen = ImplicitKeyword.ClosureWrapper.suffix.count
    guard funcName.count > prefixLen + suffixLen else { return nil }
    let wrapperName = String(funcName.dropFirst(prefixLen).dropLast(suffixLen))

    guard arguments.isEmpty else { return nil }
    guard let trailingClosure else { return nil }
    let closure = trailingClosure.value
    guard let params = closure.parameters, !params.isEmpty else { return nil }
    guard let lastParam = params.last, lastParam.isImplicitScope else { return nil }

    return (
      wrapperName: wrapperName,
      closureParamCount: params.count - 1,
      closure: closure,
      scopeArg: lastParam.name.syntax
    )
  }
}

extension SyntaxTree.ClosureParameter {
  var isImplicitScope: Bool {
    name.value.literal == ImplicitKeyword.Scope.variableName
  }
}

extension SymbolNamespace {
  var isImplicitKeys: Bool {
    value == [ImplicitKeyword.keysEnumName]
  }
}

extension ImplicitKey {
  init<S>(
    type: SyntaxTree<S>.TypeModel,
    errors: inout Diagnostics<S>,
    syntax: S
  ) {
    self.init(
      kind: .type,
      name: type.strictDescription(errors: &errors, syntax: syntax)
    )
  }

  init?<S>(
    arg: SyntaxTree<S>.Argument.Value,
    errors: inout Diagnostics<S>,
    syntax: S
  ) {
    switch arg {
    case let .explicitType(t):
      self.init(type: t, errors: &errors, syntax: syntax)
    case let .keyed(kp):
      self.init(kind: .keyPath, name: kp.joined(separator: "."))
    case .reference, .other:
      return nil
    }
  }
}

// TODO: To base
extension String {
  public init(_ staticString: StaticString) {
    self = staticString.withUTF8Buffer {
      String(decoding: $0, as: UTF8.self)
    }
  }
}

extension Collection {
  var singleElement: Element? {
    dropFirst().isEmpty ? first : nil
  }
}

extension SyntaxTreeBuildingBlocks.ParameterName {
  var description: String {
    switch self {
    case let .literal(id): id
    case .wildcard: "_"
    }
  }
}

extension Array {
  fileprivate static func item<T, S>(
    _ kind: T, at syntax: S
  ) -> Self where Element == SemaTree<S>.WithSyntax<T> {
    [
      SemaTree<S>.WithSyntax<T>(syntax: syntax, node: kind),
    ]
  }
}

extension DiagnosticMessage {
  // MARK: Function declaration

  private static let implicitScope = ImplicitKeyword.Scope.className

  fileprivate static let possibleScopeArgVariants =
    "Possible variants are: '_: \(implicitScope)' or '_ scope: \(implicitScope)'"

  fileprivate static let excessImplicitScopeParameter: Self =
    "Excess '\(implicitScope)' parameter in function declaration"
  fileprivate static let scopeArgIsNotWildcard: Self =
    "'\(implicitScope)' argument in function declaration must be wildcard. \(possibleScopeArgVariants)"
  fileprivate static func wrongScopeArgName(_ got: String) -> Self {
    "'\(implicitScope)' argument in function declaration must be wildcard or 'scope'; found: '\(got)'. \(possibleScopeArgVariants)"
  }

  // MARK: Static dispatch

  enum Context {
    case overrideKeyword, notFinal, classModifier, openKeyword, protocolFunction
  }

  private static let noDynamicDispatchText =
    "Dynamic dispatch for functions with implicit scope is forbidden"

  fileprivate static func noDynamicDispatch(_ reason: Context) -> Self {
    let contextStr =
      switch reason {
      case .overrideKeyword: "remove override keyword"
      case .notFinal: "class member functions must be final, or class must be final"
      case .classModifier: "replace 'class' with 'static'"
      case .openKeyword: "replace 'open' with 'public'"
      case .protocolFunction: "remove 'scope' parameter"
      }
    return "\(noDynamicDispatchText); \(contextStr)"
  }

  // MARK: Implicit property wrapper

  fileprivate static func unexpectedArgumentName(_ name: String) -> Self {
    "Unexpected argument name, got '\(name)', expected empty"
  }

  fileprivate static let unableToInferImplicitKey: Self =
    "Unable to infer implicit key, expected literal type or keypath"

  fileprivate static let missingType =
    Self("Missing type").expectedCompilerError

  fileprivate static let wrapedImplicitValue: Self =
    "'@Implicit' property wrapper must be outermost"

  fileprivate static let storedPropertyInSetMode: Self =
    "Stored Implicit property cannot have initial value"

  // MARK: Scopes

  fileprivate static let scopeDeclMustBeConst: Self =
    "'scope' must be a 'let' constant"
  fileprivate static let redundantTypeAnnotation: Self =
    "Redundant type annotation"

  // MARK: Implicit Bag

  fileprivate static let invalidImplicitBagVariableName: Self =
    "Invalid 'with:' parameter, expected '\(ImplicitKeyword.Bag.variableName)' identifier"

  // MARK: ImplicitsKeys

  fileprivate static let unexpectedContentInsideImplicitsKeys: Self =
    "Unexpected declaration inside 'ImplicitsKeys'. Only 'static let keyName = Key<Type>()' are allowed"

  fileprivate static let nonStaticInsideImplicitsKeys: Self =
    "Implicit key declaration must be static"

  // MARK: SPI

  fileprivate static let publicWithoutSPI: Self =
    "Public function must be marked with '@\(ImplicitKeyword.SPI.attributeName)(\(ImplicitKeyword.SPI.annotationName))' attribute when exporting enabled"

  // MARK: Unknown syntax

  fileprivate static let unsupportedSyntaxInProtocol: Self =
    "This declaration is not supported for protocols"
  fileprivate static let unsupportedDeclSyntax: Self =
    "This declaration is not supported"

  // MARK: To Migrate

  fileprivate static let implicitScope_CantUseInDefer: Self =
    "[TBD] Implicit scope control flow can't be used in defer statement"
  fileprivate static func functionCall_SingleArgumentTupleRequired(_ count: Int) -> Self {
    "[TBD] Implicit.map requires exactly 2 arguments, got \(count)"
  }

  fileprivate static let functionCall_KeyPathExpressionOrExplicitTypeRequired: Self =
    "[TBD] Implicit.map requires keypath expression or explicit type"
  fileprivate static func implicitMap_UnexpectedArgumentCount(_ count: Int) -> Self {
    "[TBD] Implicit.map requires exactly 2 arguments, got \(count)"
  }

  fileprivate static func implicitMap_TooManyKeyPathComponents(_ count: Int) -> Self {
    "[TBD] Implicit.map keypath expression must have exactly 1 component, got \(count)"
  }

  fileprivate static let implicitMap_KeyPathExpressionOrExplicitTypeRequired: Self =
    "[TBD] Implicit.map requires keypath expression or explicit type"
  fileprivate static let implicitMap_unexpectedArgument: Self =
    "[TBD] Unexpected argument"
}
