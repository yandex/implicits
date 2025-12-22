// Copyright 2024 Yandex LLC. All rights reserved.

extension SemaTreeBuilder {
  typealias FailedInitializers = [SymbolNamespace: [PreDiagnostic<Syntax>]]
  struct ModuleContext: DiagnosticWrapper {
    var modulename: String
    var enableExporting: Bool
    var diagnostics = Diagnostics()
    var symbols = SymbolIndex()
    var failedInitializers = FailedInitializers()
    var dependencies: Dependencies

    init(
      moduleName: String,
      dependencies: Dependencies,
      enableExporting: Bool
    ) {
      self.modulename = moduleName
      self.dependencies = dependencies
      self.enableExporting = enableExporting
    }

    subscript(
      file file: [SyntaxTree<Syntax>.TopLevelEntity],
      name name: String
    ) -> FileContext {
      get {
        var extensions = [SymbolNamespace: [SXT.Extension]]()
        for (ns, ext) in file.compactMap(\.value.extension) {
          extensions[ns, default: []].append(ext)
        }

        var symbols = symbols
        let scouting = Scout.lookaheadFile(
          file, file: name, scope: .file,
          dependencies: dependencies
        )
        symbols.addLookaheads(scouting.symbols.map(\.0))

        return FileContext(
          modulename: modulename,
          enableExporting: enableExporting,
          file: name,
          diagnostics: Diagnostics(),
          symbols: symbols,
          failedInitializers: .init(scouting.failedInitializers) { $0 + $1 },
          dependencies: dependencies,
          extensions: extensions
        )
      }
      set {
        diagnostics += newValue.diagnostics
      }
    }
  }

  struct FileContext: DiagnosticWrapper {
    var modulename: String
    var enableExporting: Bool
    var file: String
    var diagnostics: Diagnostics
    var symbols: SymbolIndex
    var failedInitializers: FailedInitializers
    var dependencies: Dependencies
    var extensions: [SymbolNamespace: [SXT.Extension]]

    subscript(
      topLevel topLevel: SyntaxTree<Syntax>.TopLevelEntity
    ) -> Context {
      get {
        let enclosingType: SXT.TypeDecl? =
          if case let .declaration(.type(t)) = topLevel.value {
            t
          } else { nil }
        return Context(
          modulename: modulename, enableExporting: enableExporting, file: file,
          symbols: symbols,
          failedInitializers: failedInitializers,
          diagnostics: diagnostics,
          hasImplicitScope: false, dependencies: dependencies,
          enclosingType: enclosingType,
          extensions: extensions
        )
      }
      set {
        diagnostics = newValue.diagnostics
      }
    }
  }

  struct Context: DiagnosticWrapper {
    typealias SMT = SemaTree<Syntax>
    typealias Diagnostics = SemaTreeBuilder.Diagnostics
    enum InferredNamespace {
      case unknown
      case known(String)
    }

    struct VariableInfoForTypeInference {
      var writtenType: SXT.TypeModel?
      var initializer: SXT.Expression?
      var cachedType: TypeInfo?
      var isKnownImplicitScope: Bool
      var syntax: Syntax

      init(
        writtenType: SXT.TypeModel?,
        initializer: SXT.Expression?,
        cachedType: TypeInfo? = nil,
        isKnownImplicitScope: Bool = false,
        syntax: Syntax
      ) {
        self.writtenType = writtenType
        self.initializer = initializer
        self.cachedType = cachedType
        self.isKnownImplicitScope = isKnownImplicitScope
        self.syntax = syntax
      }
    }

    var diagnostics: Diagnostics
    // TODO: Implement scopes stack mechanics, so subscopes cannot affect
    // its parent scopes
    var visibleVariables = [String: VariableInfoForTypeInference]()
    var symbols: SymbolIndex
    var failedInitializers: FailedInitializers
    var currentNamespaceStack = [String]()
    var moduleName: String
    var enableExporting: Bool
    var file: String
    var dependencies: Dependencies
    var enclosingType: SXT.TypeDecl?
    var extensions: [SymbolNamespace: [SXT.Extension]]

    init(
      modulename: String, enableExporting: Bool, file: String,
      symbols: SymbolIndex,
      failedInitializers: FailedInitializers,
      diagnostics: Diagnostics,
      hasImplicitScope _: Bool,
      dependencies: Dependencies,
      enclosingType: SXT.TypeDecl?,
      extensions: [SymbolNamespace: [SXT.Extension]]
    ) {
      self.moduleName = modulename
      self.file = file
      self.symbols = symbols
      self.failedInitializers = failedInitializers
      self.diagnostics = diagnostics
      self.dependencies = dependencies
      self.enableExporting = enableExporting
      self.enclosingType = enclosingType
      self.extensions = extensions
    }

    subscript(type type: SXT.TypeDecl, syntax: Syntax) -> Self {
      get {
        var copy = self
        copy.currentNamespaceStack += [type.name]
        copy.enclosingType = type
        let privates = Scout.lookaheadType(
          type, scope: .type, file: file, syntax: syntax
        )
        copy.symbols.addLookaheads(privates.symbols.map(\.0))
        copy.failedInitializers.merge(privates.failedInitializers) { $0 + $1 }
        copy.registerFieldVariables(from: type)
        let ns = SymbolNamespace(copy.currentNamespaceStack)
        for exts in extensions[ns] ?? [] {
          let fromExtension = Scout.lookaheadExtension(
            exts, scope: .type, file: file
          )
          copy.symbols.addLookaheads(fromExtension.symbols.map(\.0))
          copy.failedInitializers.merge(fromExtension.failedInitializers) { $0 + $1 }
        }
        return copy
      }
      set {
        diagnostics = newValue.diagnostics
      }
    }

    private mutating func registerFieldVariables(from typeDecl: SXT.TypeDecl) {
      for member in typeDecl.members {
        switch member.value {
        case let .declaration(.variable(varDecl)):
          if varDecl.affiliation == .instance {
            registerVariable(varDecl)
          }
        case .initializer, .declaration(.function),
             .declaration(.memberBlock), .declaration(.protocol),
             .declaration(.type):
          break
        }
      }
    }

    subscript(extensionNamespace name: String) -> Self {
      get {
        self[extensionNamespace: Sema.Namespace([name])]
      }
      set {
        self[extensionNamespace: Sema.Namespace([name])] = newValue
      }
    }

    subscript(extensionNamespace name: Sema.Namespace?) -> Self {
      get {
        var copy = self
        // TODO: Support extension with unknown namespace
        if let value = name?.value {
          copy.currentNamespaceStack += value

          // Look ahead for private symbols in the extension
          if let ns = name, let exts = extensions[ns] {
            for ext in exts {
              let fromExtension = Scout.lookaheadExtension(
                ext, scope: .type, file: file
              )
              copy.symbols.addLookaheads(fromExtension.symbols.map(\.0))
              copy.failedInitializers.merge(fromExtension.failedInitializers) { $0 + $1 }
            }
          }
        }
        return copy
      }
      set {
        diagnostics = newValue.diagnostics
      }
    }

    subscript(funcDecl funcDecl: SXT.FunctionDecl) -> Self {
      get {
        var copy = self
        copy.registerFunctionParamters(funcDecl.parameters)
        return copy
      }
      set {
        diagnostics = newValue.diagnostics
      }
    }

    subscript(
      withScope _: SXT.ClosureExpr,
      scopeParamter scopeParamter: Syntax
    ) -> Self {
      get {
        var copy = self
        copy.visibleVariables[ImplicitKeyword.Scope.variableName] =
          VariableInfoForTypeInference(
            writtenType: nil,
            initializer: nil,
            isKnownImplicitScope: true,
            syntax: scopeParamter
          )
        return copy
      }
      set {
        diagnostics = newValue.diagnostics
      }
    }

    subscript(
      closure closure: SXT.ClosureExpr
    ) -> Self {
      get {
        var copy = self
        if let ps = closure.parameters {
          copy.registerFunctionParamters(ps)
        }
        return copy
      }
      set {
        diagnostics = newValue.diagnostics
      }
    }

    subscript(initDecl initDecl: SXT.InitializerDecl) -> Self {
      get {
        var copy = self
        copy.registerFunctionParamters(initDecl.parameters)

        return copy
      }
      set {
        diagnostics = newValue.diagnostics
      }
    }

    private mutating func registerFunctionParamters(_ ps: [SXT.Parameter]) {
      for p in ps {
        guard let id = p.bodyName else { continue }
        visibleVariables[id] = VariableInfoForTypeInference(
          writtenType: p.type.value,
          initializer: nil,
          syntax: p.firstName.syntax
        )
      }
    }

    private mutating func registerFunctionParamters(
      _ ps: [SXT.ClosureParameter]
    ) {
      for p in ps {
        switch p.name.value {
        case let .literal(name):
          visibleVariables[name] = VariableInfoForTypeInference(
            writtenType: p.type,
            initializer: nil,
            syntax: p.name.syntax
          )
        case .wildcard:
          continue
        }
      }
    }

    var enclosingTypeIsClass: Bool {
      enclosingType?.kind == .class
    }
  }
}

extension SemaTreeBuilder.Context {
  typealias SXT = SyntaxTree<Syntax>
  typealias SymbolInfo = SymbolInfoGeneric<Syntax>

  var hasImplicitScopeVariableInScope: Bool {
    visibleVariables[ImplicitKeyword.Scope.variableName]?
      .isImplicitScope ?? false
  }

  // MARK: - parsing time registration

  mutating func registerDeclaration(_ item: SXT.Declaration) {
    switch item {
    case let .function(f):
      _ = f // not implemented
    case let .memberBlock(memberBlock):
      _ = memberBlock // not implemented
    case let .type(type):
      _ = type // not implemented
    case let .variable(variable):
      registerVariable(variable)
    case .protocol:
      break
    }
  }

  private mutating func registerVariable(_ variable: SXT.VariableDecl) {
    func registerPattern(
      _ pattern: SXT.VariableDecl.Pattern,
      type: SXT.TypeModel?,
      initializer: SXT.Expression?,
      syntax: Syntax
    ) {
      switch pattern {
      case let .identifier(id):
        if let shadowed = visibleVariables[id], let declRef = initializer?.declRefNoParamters,
           declRef == id {
          // Shadowing itself, `let foo = foo`
          // Happens when there is already a variable with some name, and one
          // needs to put it inder @Implicit, for example:
          // ```
          // func f(foo: Int) {
          //   @Implicit
          //   var foo = foo
          // }
          // ```
          visibleVariables[id] = VariableInfoForTypeInference(
            writtenType: shadowed.writtenType ?? type,
            initializer: shadowed.initializer,
            syntax: syntax
          )
        } else {
          visibleVariables[id] = VariableInfoForTypeInference(
            writtenType: type,
            initializer: initializer,
            syntax: syntax
          )
        }
      case let .tuple(patterns):
        for pattern in patterns {
          // this is to register all encounterd identifiers in pattern,
          // but bail out inferring complex tuple types
          registerPattern(pattern, type: nil, initializer: nil, syntax: syntax)
        }
      case .wildcard, .unsupported:
        break
      }
    }
    for binding in variable.bindings {
      registerPattern(
        binding.name,
        type: binding.type,
        initializer: binding.initializer?.value,
        syntax: binding.syntax
      )
    }
  }

  private mutating func candidatesForFCall(
    _ fcall: SXT.FunctionCall,
    syntax: Syntax
  ) -> [SymbolInfo] {
    guard let fname = fcall.name else { return [] }
    let type = SXT.TypeModel
      .member((fcall.base.map { [$0] } ?? []) + [fname.value])
    let components = type.componentsWithoutGenerics() ?? []
    guard let firstComponent = components.first else {
      return []
    }
    let args = fcall.arguments.map(\.signatureName)
    var matching = [SymbolInfo]()
    if firstComponent == "self" {
      if components.last == "init" {
        matching += symbols.findInitializer(
          namespace: currentNamespaceStack,
          args: fcall.arguments.map(\.signatureName)
        )
      } else {
        guard let memberFunctionName = components.last else {
          diagnostics.diagnose(
            "[WIP] Only direct member functions are supported", at: syntax
          )
          return []
        }
        matching += symbols.match(.member(
          name: memberFunctionName, namespace: currentNamespaceStack, args: args
        ))
      }
    } else if components.count == 1, !currentNamespaceStack.isEmpty,
              let memberFunctionName = components.last {
      matching += symbols.match(.member(
        name: memberFunctionName, namespace: currentNamespaceStack, args: args
      ))
    }
    // Member function
    if let variableInfo = visibleVariables[firstComponent] {
      let typeInfo = resolveTypeForVariable(name: firstComponent, info: variableInfo)
      guard let typeInfo, let namespace = typeInfo.namespace.value else {
        diagnostics
          .diagnose("[WIP] Unable to resolve type for variable", at: syntax)
        return []
      }
      guard let memberFunctionName = components.last else {
        diagnostics
          .diagnose("[WIP] Only direct member functions are supported", at: syntax)
        return []
      }
      guard components.count <= 2 else {
        // handle callAsFunction call
        diagnostics
          .diagnose("[WIP] Call as function is not supported yet", at: syntax)
        return []
      }
      let resolvedMembers = symbols.match(.member(
        name: memberFunctionName, namespace: namespace.value, args: args
      ))
      return resolvedMembers
    }

    var notes = [PreDiagnostic<Syntax>]()
    if let synthesizeErrors = failedInitializers[.init(components)] {
      notes += synthesizeErrors
    }

    // static/free
    guard let name = components.last else {
      return []
    }
    if components.count == 1 {
      matching += symbols.match(
        .member(name: name, namespace: [], args: args)
      )
    }

    matching += symbols.match(
      .static(namespace: components, args: args)
    )

    if !currentNamespaceStack.isEmpty, components.count > 1 {
      matching += symbols.match(.static(
        namespace: currentNamespaceStack + components,
        args: args
      ))
    }

    // Handle static functions in the current namespace when called without full namespace
    if components.count == 1, !currentNamespaceStack.isEmpty {
      matching += symbols.match(.static(
        namespace: currentNamespaceStack + components,
        args: args
      ))
    }

    if !matching.isEmpty {
      return matching
    }

    // FIXME: Use `SymbolImage` here
    let possibleStaticFunction = CallableSignature(
      kind: components.count == 1 ? .memberFunction(name: name) : .staticFunction(name: name),
      namespace: components.dropLast(),
      params: fcall.arguments.map(\.signatureName),
      paramTypes: [],
      returnType: nil,
      file: file
    )

    for note in notes {
      var note = note
      note.severity = .note
      note.message =
        "While resolving \(possibleStaticFunction). \(note.message.value)"
      diagnostics.append(note)
    }
    diagnostics
      .diagnose(.unresolvedSymbol(possibleStaticFunction), at: syntax)
    return []
  }

  mutating func resolveFunctionSignature(
    _ fcall: SXT.FunctionCall,
    syntax: Syntax
  ) -> CallableSignature? {
    let candidates = candidatesForFCall(fcall, syntax: syntax)
    guard let matched = candidates.first else {
      return nil
    }
    if candidates.count > 1 {
      diagnostics
        .diagnose(.ambiguousUseOf(matched.callableSignature), at: syntax)
      for candidate in candidates {
        diagnostics
          .diagnose(
            .foundCandidate, at: candidate.syntax, severity: .note
          )
      }
      return nil
    }
    return matched.callableSignature
  }

  mutating func resolveReturnType(
    _ fcall: SXT.FunctionCall,
    syntax: Syntax
  ) -> TypeInfo? {
    let candidates = candidatesForFCall(fcall, syntax: syntax)
    var types: [(TypeInfo, CallableSignature, Syntax)] = []
    for candidate in candidates {
      let signature = candidate.callableSignature
      switch signature.kind {
      case let .initializer(optional: optional):
        var type = SXT.TypeModel(namespace: signature.namespace)
        if optional {
          type = .optional(type)
        }
        types.append((type.typeInfo(), signature, syntax))
        return type.typeInfo()
      case .memberFunction, .callAsFunction, .staticFunction:
        if let returnType = signature.returnType {
          types.append((returnType, signature, syntax))
        } else {
          diagnostics.diagnose(.unableToInferType, at: syntax)
          return nil
        }
      }
    }

    if let type = types.first {
      let rest = types.dropFirst()
      if rest.allSatisfy({ $0.0 == type.0 }) {
        return type.0
      } else {
        diagnostics.diagnose(.ambiguousUseOf(type.1), at: syntax)
        for t in types {
          diagnostics.diagnose(.foundCandidate, at: t.2, severity: .note)
        }
        return nil
      }
    } else {
      return nil
    }
  }

  mutating func resolveVariableType(
    _ initializer: SXT.Expression,
    syntax: Syntax
  ) -> TypeInfo? {
    switch initializer {
    case let .functionCall(fcall):
      return resolveReturnType(fcall, syntax: syntax)
    case let .declRef(decl, parameters: parameters):
      guard parameters?.isEmpty ?? true else {
        diagnostics.diagnose(.unableToInferType, at: syntax)
        return nil
      }
      guard let varInfo = visibleVariables[decl] else {
        diagnostics.diagnose(.unableToFindDeclaration(for: decl), at: syntax)
        return nil
      }
      guard let type = resolveTypeForVariable(name: decl, info: varInfo) else {
        diagnostics.diagnose(.unableToInferType, at: syntax)
        return nil
      }
      return type
    case let .memberAccessor(base: base, callee):
      // FIXME: Support proper member lookup in namespaces
      guard case let .declRef(decl, parameters: parameters) = base,
            decl == "self", parameters == nil else {
        diagnostics.diagnose(.unableToInferType, at: syntax)
        return nil
      }
      guard let varInfo = visibleVariables[callee] else {
        diagnostics.diagnose(.unableToFindDeclaration(for: callee), at: syntax)
        return nil
      }
      guard let type = resolveTypeForVariable(name: callee, info: varInfo) else {
        diagnostics.diagnose(.unableToInferType, at: syntax)
        return nil
      }
      return type
    case .other, .macroExpansion, .closure:
      diagnostics.diagnose(.unableToInferType, at: syntax)
      return nil
    case let .await(expr), let .try(expr, _):
      return resolveVariableType(expr, syntax: syntax)
    }
  }

  mutating func resolveTypeForVariable(
    name: String,
    info: VariableInfoForTypeInference
  ) -> TypeInfo? {
    if let cached = info.cachedType {
      return cached
    }
    let resolved: TypeInfo?
    if let type = info.writtenType {
      resolved = type.typeInfo()
    } else if let initializer = info.initializer {
      if let type = resolveVariableType(initializer, syntax: info.syntax) {
        resolved = type
      } else {
        diagnostics
          .diagnose(.unableToInferType, at: info.syntax)
        resolved = nil
      }
    } else {
      diagnostics
        .diagnose("[WIP] Explicit type required", at: info.syntax)
      resolved = nil
    }

    visibleVariables[name]?.cachedType = resolved
    return resolved
  }

  func canonicalSignature(
    _ initDecl: SXT.InitializerDecl,
    syntax: Syntax
  ) -> SymbolInfo {
    .initializer(
      params: initDecl.parameters.map {
        SymbolInfo.Parameter(
          name: $0.signatureName, type: $0.type.value.description,
          hasDefaultValue: $0.hasDefaultValue
        )
      },
      namespace: currentNamespaceStack,
      optional: initDecl.optional,
      syntax: syntax,
      file: file
    )
  }

  func canonicalSignature(
    _ funcDecl: SXT.FunctionDecl, syntax: Syntax
  ) -> SymbolInfo {
    let name = funcDecl.name
    let kind: SymbolInfo.Kind = funcDecl.affiliation.isStaticLike ?
      .staticFunction(name: name) : .memberFunction(name: name)
    return SymbolInfo(
      kind: kind,
      parameters: funcDecl.parameters.map {
        SymbolInfo.Parameter(
          name: $0.signatureName, type: $0.type.value.description,
          hasDefaultValue: $0.hasDefaultValue
        )
      },
      namespace: currentNamespaceStack,
      returnType: funcDecl.returnTypeNamespace(),
      syntax: syntax,
      file: file
    )
  }

  func canonicalName(of type: SXT.TypeDecl) -> Sema.Namespace {
    Sema.Namespace(currentNamespaceStack + [type.name])
  }

  mutating func canonicalNameOfExtension(
    _ type: SXT.TypeModel,
    syntax _: Syntax
  ) -> Sema.Namespace? {
    type.componentsWithoutGenerics().map(Sema.Namespace.init)
  }
}

extension SyntaxTree.TopLevelStatement {
  var `extension`: (SymbolNamespace, SyntaxTree.Extension)? {
    switch self {
    case let .extension(e):
      guard let ns = e.extendedType.componentsWithoutGenerics() else { return nil }
      return (SymbolNamespace(ns), e)
    case .declaration, .import, .ifConfig:
      return nil
    }
  }
}

extension SyntaxTree.TypeModel {
  func componentsWithoutGenerics() -> [String]? {
    switch self {
    case let .generic(base: base, args: _):
      return base.componentsWithoutGenerics()
    case let .identifier(identifier):
      return [identifier]
    case let .member(memberChain):
      var members = [String]()
      for member in memberChain {
        let new = member
          .componentsWithoutGenerics()
        guard let new else { return nil }
        members += new
      }
      return members
    // foo?.bar()
    case let .optional(wrapped):
      return wrapped.componentsWithoutGenerics()
    case let .unwrappedOptional(wrapped):
      return wrapped.componentsWithoutGenerics()
    case .tuple, .attributed, .classRestriction, .array, .inlineArray,
         .composition, .dictionary, .function, .metatype, .missing,
         .namedOpaqueReturn, .packElement, .packExpansion, .someOrAny,
         .suppressed:
      return nil
    }
  }

  func typeInfo() -> TypeInfo {
    let namespace: TypeInfo.Failable<SymbolNamespace> =
      componentsWithoutGenerics().map { .success(SymbolNamespace($0)) } ??
      .failure(diagnostics: [.unableToParseType])
    let strict = strictDescription()
    let strictDescription: TypeInfo.Failable<String> =
      strict.diagMessages.isEmpty ?
      .success(strict.description) :
      .failure(diagnostics: strict.diagMessages)
    return TypeInfo(
      namespace: namespace,
      description: description,
      strictDescription: strictDescription
    )
  }
}

extension TypeInfo {
  init(namespace: SymbolNamespace) {
    self.namespace = .success(namespace)
    self.description = namespace.value.joined(separator: ".")
    self.strictDescription = .success(self.description)
  }
}

extension SyntaxTree.FunctionDecl {
  func returnTypeNamespace() -> TypeInfo? {
    returnType.map { $0.value.typeInfo() }
  }
}

extension SemaTreeBuilder.Context.VariableInfoForTypeInference {
  var isImplicitScope: Bool {
    if isKnownImplicitScope { return true }
    if let writtenType {
      return writtenType.description == ImplicitKeyword.Scope.className
    }
    if let initializer {
      switch initializer {
      case let .functionCall(fcall):
        if fcall.isImplicitScopeInitializer { return true }
        switch fcall.isImplicitScopeCall() {
        case .nested:
          return true
        case .end, nil:
          return false
        }
      case .declRef, .other, .memberAccessor, .macroExpansion, .closure, .await, .try:
        return false
      }
    }
    return false
  }
}

extension SyntaxTree.Argument {
  fileprivate var signatureName: String {
    name.map(\.value) ?? "_"
  }
}

extension SyntaxTree.Expression {
  var declRefNoParamters: String? {
    switch self {
    case let .declRef(decl, parameters: []), let .declRef(decl, parameters: nil):
      decl
    default:
      nil
    }
  }
}

extension SyntaxTree.TypeModel {
  init(namespace: SymbolNamespace) {
    self = .member(namespace.value.map(Self.identifier))
  }
}

extension DiagnosticMessage {
  static let unableToParseType: Self = "Unable to parse type"
  static let unableToInferType: Self =
    "Unable to infer type, provide explicit type"
  static func unableToFindDeclaration(for ref: String) -> Self {
    "Unable to find a declaration for '\(ref)'"
  }
}
