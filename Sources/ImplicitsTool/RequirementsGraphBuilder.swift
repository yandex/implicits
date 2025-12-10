// Copyright 2024 Yandex LLC. All rights reserved.

func buildRequrementsGraph<Syntax, File>(
  sema: [(File, [SemaTree<Syntax>.TopLevel])],
  diagnostics: inout Diagnostics<Syntax>,
  dependencies: [(symbol: SymbolInfo<Syntax>, reqs: [ImplicitKey]?)]
) -> RequirementsGraph<Syntax, File> {
  var unresolved = UnresolvedGraph<Syntax, File>()
  for dep in dependencies {
    guard let reqs = dep.reqs else { continue }
    _ = unresolved.addNode(
      syntax: dep.symbol.syntax,
      requires: Set(reqs),
      definesSymbol: (dep.symbol, .public, external: true),
      parent: nil
    )
  }
  for topLevel in sema {
    unresolved.traverse(file: topLevel.0, sema: topLevel.1)
  }
  unresolved.resolve()
  diagnostics += unresolved.diagnostics
  return unresolved.reqGraph
}

private struct UnresolvedGraph<Syntax, File> {
  typealias Symbol = CallableSignature
  typealias ReqGraph = RequirementsGraph<Syntax, File>
  typealias Node = ReqGraph.Node
  typealias Graph = ReqGraph.Graph
  typealias Idx = Graph.Index
  typealias Diagnostics = DiagnosticsGeneric<Syntax>

  var graph = Graph()
  var entryPoints = [Idx]()

  var symbols = [Symbol: [Idx]]()
  var referencesToSymbols = [Idx: Symbol]()
  var implicitStoredProperties = [Sema.Namespace: (head: Idx, tail: Idx)]()
  var initializers = [Sema.Namespace: [Idx]]()
  var bags = [(SMT.ImplicitBag, Idx, File)]()
  var diagnostics = Diagnostics()
  var publicInterface = [(Idx, SymbolInfo<Syntax>)]()
  var testableInterface = [(Idx, SymbolInfo<Syntax>)]()
  var implicitFunctions = [(Idx, File, SMT.FuncDecl)]()

  // Bags
  var storedBags = [Sema.Namespace: Idx]()
  var storedBagsUsage = [Sema.Namespace: [Idx]]()

  var reqGraph: RequirementsGraph<Syntax, File> {
    RequirementsGraph<Syntax, File>(
      graph: graph, entryPoints: entryPoints,
      bags: bags.map { ($0.1, name: $0.0.node.fillFunctionName, $0.2) },
      publicInterface: publicInterface,
      testableInterface: testableInterface,
      implicitFunctions: implicitFunctions
    )
  }

  init() {}

  mutating func addNode(
    syntax: Syntax,
    provides: Set<ImplicitKey> = [],
    requires: Set<ImplicitKey> = [],
    definesSymbol: (SymbolInfo<Syntax>, Visibility, external: Bool)? = nil,
    referencesSymbol: Symbol? = nil,
    parent: Idx?
  ) -> Idx {
    let node = Node(payload: syntax, provides: provides, requires: requires)
    let idx = graph.addNode(node, parent: parent)
    if let symbol = definesSymbol {
      symbols[symbol.0.callableSignature, default: []].append(idx)
      if !symbol.external, symbol.1.moreOrEqualVisible(than: .package) {
        publicInterface.append((idx, symbol.0))
      }
      if !symbol.external, symbol.1.moreOrEqualVisible(than: .internal),
         symbol.1.lessOrEqualVisible(than: .internal) {
        testableInterface.append((idx, symbol.0))
      }
    }
    if let symbol = referencesSymbol {
      referencesToSymbols[idx] = symbol
    }
    return idx
  }

  mutating func resolve() {
    // Symbols binding
    for (idx, symbol) in referencesToSymbols {
      guard let defs = symbols[symbol], let def = defs.first else {
        diagnostics.diagnose(.unresolvedSymbol(symbol), at: graph[idx].payload)
        continue
      }
      guard defs.count == 1 else {
        diagnostics
          .diagnose(.ambiguousUseOf(symbol), at: graph[idx].payload)
        for def in defs {
          let candidate = graph[def].payload
          diagnostics.note(.foundCandidate, at: candidate)
        }
        continue
      }
      graph.addEdge(from: idx, to: def)
    }

    // Stored Implicit properties
    for (namespace, implicitProperties) in implicitStoredProperties {
      // To every initializer in namespace add successor with all implicit
      // stored properties declared in this namespace
      let initializers = initializers[namespace, default: []]
      diagnostics.check(
        !initializers.isEmpty,
        or: .noInitInTypeWithImplicitProperties,
        at: graph[implicitProperties.head].payload
      )
      for initializer in initializers {
        graph.addEdge(from: initializer, to: implicitProperties.head)
      }
    }

    // Stored bags
    for (namespace, bagUsages) in storedBagsUsage {
      guard let bagIdx = storedBags[namespace] else {
        for bagUsage in bagUsages {
          diagnostics.diagnose(.noBag, at: graph[bagUsage].payload)
        }
        continue
      }
      for usage in bagUsages {
        graph.addEdge(from: bagIdx, to: usage)
      }
    }
    for (namespace, bagIdx) in storedBags {
      if !storedBagsUsage.keys.contains(namespace) {
        diagnostics.diagnose(.unusedBag, at: graph[bagIdx].payload)
      }
    }
  }
}

extension UnresolvedGraph {
  typealias SMT = SemaTree<Syntax>

  mutating func traverse(file: File, sema: [SMT.TopLevel]) {
    for topLevel in sema {
      traverse(sema: topLevel, file: file)
    }
  }

  mutating func traverse(sema: SMT.TopLevel, file: File) {
    switch sema.node {
    case let .typeDeclaration(type):
      traverseMemberBlock(type.members, namespace: type.name, file: file)
    case let .extensionDeclaration(name, members):
      traverseMemberBlock(members, namespace: name, file: file)
    case let .functionDeclaration(decl):
      traverseFunctionDeclaration(
        decl, syntax: sema.syntax, file: file, namespace: nil
      )
    case .keysDeclaration:
      break
    }
  }

  // MARK: MemberBlock

  mutating func traverseMemberBlock(
    _ memberItems: [SMT.MemberBlockItem],
    namespace: Sema.Namespace?,
    file: File
  ) {
    for memberItem in memberItems {
      traverse(memberItem: memberItem, namespace: namespace, file: file)
    }
  }

  mutating func traverse(
    memberItem item: SMT.MemberBlockItem,
    namespace: Sema.Namespace?,
    file: File
  ) {
    switch item.node {
    case let .typeDeclaration(decl):
      traverseMemberBlock(decl.members, namespace: decl.name, file: file)
    case let .functionDeclaration(decl):
      traverseFunctionDeclaration(
        decl, syntax: item.syntax, file: file, namespace: namespace
      )
    case let .implicit(key):
      guard let namespace else {
        diagnostics.diagnose(.noExtensionNamespace, at: item.syntax)
        return
      }
      let keys = Set([key])
      if var initializer = implicitStoredProperties[namespace] {
        initializer.tail = addNode(
          syntax: item.syntax,
          requires: keys,
          parent: initializer.tail
        )
        implicitStoredProperties[namespace] = initializer
      } else {
        let idx = addNode(
          syntax: item.syntax,
          requires: keys,
          parent: nil
        )
        implicitStoredProperties[namespace] = (head: idx, tail: idx)
      }
    case let .bag(bag):
      guard let namespace else {
        diagnostics.diagnose(.noExtensionNamespace, at: item.syntax)
        return
      }
      if let prev = storedBags[namespace] {
        diagnostics.diagnose(.multipleBags, at: item.syntax)
        diagnostics.note(.previousBag, at: graph[prev].payload)
      }
      let bagNode = addNode(syntax: item.syntax, parent: nil)
      storedBags[namespace] = bagNode
      bags.append((bag, bagNode, file))
      if var initializer = implicitStoredProperties[namespace] {
        graph.addEdge(from: bagNode, to: initializer.tail)
        initializer.tail = bagNode
        implicitStoredProperties[namespace] = initializer
      } else {
        implicitStoredProperties[namespace] = (head: bagNode, tail: bagNode)
      }
    case let .field(initializer: initializer):
      let finalState = traverseCodeBlock(
        initializer,
        state: .newScope(
          nil,
          inheritsScope: false,
          allowsStoredBagUsage: true,
          file: file
        )
      )
      addBagsUsage(finalState.bagReferences, to: namespace)
    }
  }

  mutating func traverseFunctionDeclaration(
    _ decl: SMT.FuncDecl,
    syntax: Syntax,
    file: File,
    namespace: Sema.Namespace?
  ) {
    let isReferenceable = decl.hasScopeParameter
    let symbol = isReferenceable ?
      (decl.signature, decl.visibility, external: false) : nil
    let isInitializer = decl.signature.kind.isInitializer

    let funcDeclIdx: Idx?
    if isReferenceable {
      let idx = addNode(
        syntax: syntax,
        definesSymbol: symbol,
        parent: nil
      )
      implicitFunctions.append((idx, file, decl))

      if isInitializer {
        if let namespace {
          initializers[namespace, default: []].append(idx)
        } else {
          diagnostics.diagnose(.noExtensionNamespace, at: syntax)
        }
      }
      funcDeclIdx = idx
    } else {
      funcDeclIdx = nil
    }

    let finalState = traverseCodeBlock(
      decl.body,
      state: .newScope(
        funcDeclIdx,
        inheritsScope: decl.hasScopeParameter,
        allowsStoredBagUsage: !isInitializer,
        file: file
      )
    )
    addBagsUsage(finalState.bagReferences, to: namespace)
  }

  mutating func addBagsUsage(
    _ bagReferences: [Idx],
    to namespace: Sema.Namespace?
  ) {
    if let namespace {
      storedBagsUsage[namespace, default: []] += bagReferences
    } else {
      for bag in bagReferences {
        diagnostics.diagnose(.noBag, at: graph[bag].payload)
      }
    }
  }

  // MARK: CodeBlock

  struct CodeBlockState {
    enum Scope {
      case inherited
      case local(declaredAt: Syntax, endedAt: Syntax?)
    }

    var parent: Idx?
    var scope: Scope?
    var bagReferences: [Idx]
    var allowsStoredBagUsage: Bool
    var file: File

    var hasScope: Bool {
      scope != nil
    }

    var hasWritableScope: Bool {
      if case .local = scope {
        true
      } else {
        false
      }
    }

    init(
      parent: Idx?, scope: Scope?,
      bagReferences: [Idx], allowsStoredBagUsage: Bool,
      file: File
    ) {
      self.parent = parent
      self.scope = scope
      self.bagReferences = bagReferences
      self.allowsStoredBagUsage = allowsStoredBagUsage
      self.file = file
    }

    static func newScope(
      _ parent: Idx?,
      inheritsScope: Bool,
      bagReferences: [Idx] = [],
      allowsStoredBagUsage: Bool,
      file: File
    ) -> Self {
      CodeBlockState(
        parent: parent,
        scope: inheritsScope ? .inherited : nil,
        bagReferences: bagReferences,
        allowsStoredBagUsage: allowsStoredBagUsage,
        file: file
      )
    }

    // Lenses
    var innerScopeLense: Self {
      get {
        var copy = self
        copy.scope = hasScope ? .inherited : nil
        return copy
      }
      set {
        self.bagReferences = newValue.bagReferences
      }
    }

    var deferLense: Self {
      get { self }
      set { self = newValue }
    }

    mutating func beginLocalScope(
      nested: Bool, at: Syntax,
      diagnostics: inout Diagnostics
    ) {
      switch scope {
      case .inherited:
        diagnostics.check(
          nested, or: .newScopeWhileInheriting, at: at, severity: .warning
        )
        scope = .local(declaredAt: at, endedAt: nil)
      case .none:
        diagnostics.check(!nested, or: .nestingNoScope, at: at)
        scope = .local(declaredAt: at, endedAt: nil)
      case let .local(declared, _):
        diagnostics.diagnose(.moreThanOneLocalScope, at: at)
        diagnostics.note(.scopeDeclaredHere, at: declared)
      }
    }

    mutating func endLocalScope(at: Syntax, diagnostics: inout Diagnostics) {
      switch scope {
      case .inherited, .none:
        diagnostics.diagnose(.endingNonLocalScope, at: at)
      case let .local(declared, ended):
        if let alreadyEnded = ended {
          diagnostics.diagnose(.endingScopeMultipleTimes, at: at)
          diagnostics.diagnose(.scopeEndedHere, at: alreadyEnded, severity: .note)
        }
        scope = .local(declaredAt: declared, endedAt: at)
      }
    }

    func checkOnScopeExit(into diagnostics: inout Diagnostics) {
      switch scope {
      case .inherited:
        break
      case let .local(declared, ended):
        diagnostics.check(
          ended != nil,
          or: .scopeIsNotEnded,
          at: declared
        )
      case .none:
        break
      }
    }
  }

  mutating func traverseCodeBlock(
    _ blockItems: [SMT.CodeBlockItem],
    state: CodeBlockState
  ) -> CodeBlockState {
    var state = state
    traverseCodeBlock(blockItems, state: &state)
    return state
  }

  mutating func traverseCodeBlock(
    _ blockItems: [SMT.CodeBlockItem],
    state: inout CodeBlockState
  ) {
    for blockItem in blockItems {
      traverse(
        sema: blockItem, state: &state,
        onlyCalledFromTraverseBlock: ()
      )
    }
    state.checkOnScopeExit(into: &diagnostics)
  }

  mutating func traverse(
    sema: SMT.CodeBlockItem,
    state: inout CodeBlockState,
    onlyCalledFromTraverseBlock _: Void
  ) {
    switch sema.node {
    case let .typeDeclaration(type):
      traverseMemberBlock(type.members, namespace: type.name, file: state.file)
    case let .functionDeclaration(decl):
      guard !decl.hasScopeParameter else {
        diagnostics.diagnose(.nestedFunctionWithScope, at: sema.syntax)
        return
      }

      let finalState = traverseCodeBlock(
        decl.body,
        state: .newScope(
          nil,
          inheritsScope: false,
          allowsStoredBagUsage: false,
          file: state.file
        )
      )
      state.bagReferences += finalState.bagReferences
    case let .deferStatement(nodes):
      traverseInDeferBlock(nodes, state: &state.deferLense)
    case let .closureExpression(closure):
      let bagIdx: Idx?
      if let bag = closure.bag {
        let closureNode = addNode(
          syntax: sema.syntax, parent: state.parent
        )
        let bagNode = addNode(
          syntax: bag.syntax,
          parent: closureNode
        )
        bags.append((bag, bagNode, state.file))
        bagIdx = bagNode
        diagnostics.check(state.hasScope, or: .noScope, at: sema.syntax)
      } else {
        bagIdx = nil
      }

      let finalState = traverseCodeBlock(
        closure.body,
        state: .newScope(
          nil,
          inheritsScope: false,
          allowsStoredBagUsage: state.allowsStoredBagUsage,
          file: state.file
        )
      )
      switch (usesBag: !finalState.bagReferences.isEmpty, bag: bagIdx) {
      case (usesBag: true, bag: let idx?):
        for bag in finalState.bagReferences {
          graph.addEdge(from: idx, to: bag)
        }
      case (usesBag: true, bag: nil):
        state.bagReferences += finalState.bagReferences
      case (usesBag: false, bag: let idx?):
        diagnostics.diagnose(.unusedBag, at: graph[idx].payload)
      case (usesBag: false, bag: nil):
        break
      }
    case let .innerScope(nodes):
      traverseCodeBlock(nodes, state: &state.innerScopeLense)
    case let .functionCall(fcall):
      let new = addNode(
        syntax: sema.syntax,
        referencesSymbol: fcall.signature,
        parent: state.parent
      )
      state.parent = new
      diagnostics.check(state.hasScope, or: .noScope, at: sema.syntax)
    case let .implicitScopeBegin(nested: nested, withBag: usesBag):
      let new = addNode(syntax: sema.syntax, parent: nil)
      switch (nested: nested, usesBag: usesBag, parent: state.parent) {
      case (nested: false, usesBag: false, parent: _):
        // `let scope = ImplicitScope()`
        entryPoints.append(new)
      case (nested: true, usesBag: false, parent: nil):
        // Nesting scope without known parent scope. Will be diagnosed later
        // in `beginLocalScope`
        break
      case (nested: true, usesBag: false, parent: let parent?):
        // `let scope = scope.nested()`
        graph.addEdge(from: parent, to: new)
      case (nested: false, usesBag: true, parent: _):
        // `let scope = ImplicitScope(with: implicits)`
        state.bagReferences.append(new)
      case (nested: true, usesBag: true, parent: _):
        // Nesting scope with bag, `let scope = scope.nested(with: implicits)`
        diagnostics.diagnose(.nestedScopeUsesBags, at: sema.syntax)
      }

      state.beginLocalScope(
        nested: nested, at: sema.syntax, diagnostics: &diagnostics
      )
      state.parent = new
    case .implicitScopeEnd:
      diagnostics.diagnose(.scopeEndOutsideDefer, at: sema.syntax)
    case let .implicit(implicit):
      switch implicit.mode {
      case .get:
        state.parent = addNode(
          syntax: sema.syntax,
          requires: [implicit.key],
          parent: state.parent
        )
        diagnostics.check(state.hasScope, or: .noScope, at: sema.syntax)
      case .set:
        state.parent = addNode(
          syntax: sema.syntax,
          provides: [implicit.key],
          parent: state.parent
        )
        diagnostics.check(state.hasWritableScope, or: .noWritableScope, at: sema.syntax)
      }
    case let .implicitMap(from: from, to: to):
      state.parent = addNode(
        syntax: sema.syntax,
        provides: [to],
        requires: [from],
        parent: state.parent
      )
      diagnostics.check(state.hasWritableScope, or: .noWritableScope, at: sema.syntax)
    case let .withScope(body: body):
      var innerState = state.innerScopeLense
      defer { state.innerScopeLense = innerState }
      let scopeNode = addNode(syntax: sema.syntax, parent: nil)
      entryPoints.append(scopeNode)
      innerState.parent = scopeNode
      innerState.beginLocalScope(
        nested: false, at: sema.syntax, diagnostics: &diagnostics
      )
      innerState.endLocalScope(at: sema.syntax, diagnostics: &diagnostics)
      traverseCodeBlock(body, state: &innerState)
    }
  }

  mutating func traverseInDeferBlock(
    _ nodes: [SMT.CodeBlockItem],
    state: inout CodeBlockState
  ) {
    func checkNoImplicitStatements(_ node: SMT.CodeBlockItem) {
      switch node.node {
      case let .closureExpression(closure):
        diagnostics.check(
          closure.bag == nil, or: .closureWithBagInDefer, at: node.syntax
        )
        closure.body.forEach(checkNoImplicitStatements)
      case let .deferStatement(block):
        block.forEach(checkNoImplicitStatements)
      case .implicit, .implicitMap, .implicitScopeBegin, .functionCall, .withScope:
        diagnostics.diagnose(
          .unexpectedStatementInDefer,
          at: node.syntax
        )
      case .implicitScopeEnd:
        diagnostics.diagnose(
          .scopeEndInInnerScopeInDefer,
          at: node.syntax
        )
      case let .typeDeclaration(type):
        traverseMemberBlock(
          type.members, namespace: type.name, file: state.file
        )
      case let .functionDeclaration(fDecl):
        diagnostics.check(
          !fDecl.hasScopeParameter,
          or: .funcWithScopeInDefer,
          at: node.syntax
        )
        fDecl.body.forEach(checkNoImplicitStatements)
      case let .innerScope(scope):
        scope.forEach(checkNoImplicitStatements)
      }
    }
    for node in nodes {
      switch node.node {
      case .implicitScopeEnd:
        state.endLocalScope(at: node.syntax, diagnostics: &diagnostics)
      default:
        checkNoImplicitStatements(node)
      }
    }
  }
}

extension DiagnosticMessage {
  // ImplciitScope
  fileprivate static let noScope: Self =
    "Using implicits without 'ImplicitScope'"
  fileprivate static let noWritableScope: Self =
    "Writing to implicit scope without local 'ImplicitScope'"
  fileprivate static let scopeEndOutsideDefer: Self =
    "'scope.end()' must be called in 'defer' block"
  fileprivate static let unexpectedStatementInDefer: Self =
    "Unexpected statement in 'defer' block, only 'scope.end()' allowed" // TODO: Too harsh?
  fileprivate static let scopeIsNotEnded: Self =
    "'scope.end()' must be called before leaving the scope in defer block"
  fileprivate static let nestingNoScope: Self =
    "Nesting scope is forbidden here" // TODO: Provide reason why
  fileprivate static let noScopeForNesting: Self =
    "Nesting unknown scope"
  fileprivate static let newScopeWhileInheriting: Self =
    "Implicitly overriding existing scope"
  fileprivate static let moreThanOneLocalScope: Self =
    "Multiple local implicit scopes"
  fileprivate static let scopeDeclaredHere: Self =
    "Foremost declaration"
  fileprivate static let endingNonLocalScope: Self =
    "Ending inherited implicit scope is forbidden"
  fileprivate static let endingScopeMultipleTimes: Self =
    "'scope.end()' is called once per instance"
  fileprivate static let scopeEndedHere: Self =
    "Foremost scope end"

  fileprivate static let noExtensionNamespace: Self =
    "Using Implicits in extension of complex type, consider using free function or moving to extension with simple type"

  fileprivate static let nestedFunctionWithScope: Self =
    "Nested functions with scope parameter are not supported"

  // Defer block
  fileprivate static let closureWithBagInDefer: Self =
    "Closure with bag in defer block is not allowed"
  fileprivate static let scopeEndInInnerScopeInDefer: Self =
    "'scope.end()' must be called in topmost scope in 'defer' block"
  fileprivate static let funcWithScopeInDefer: Self =
    "Function declaration with scope parameter in defer block is forbidden"

  // Implicit Bags
  fileprivate static let noBag: Self = "Using unknown bag"
  fileprivate static let nestedScopeUsesBags: Self = "Nested scopes with bags are not supported yet"
  fileprivate static let unusedBag: Self = "Unused bag"
  fileprivate static let multipleBags: Self = "More that one stored implicit bag"
  fileprivate static let previousBag: Self = "Previous stored bag here"

  fileprivate static let noInitInTypeWithImplicitProperties: Self =
    "Type with '@Implicit' stored properties or stored implicits bag must have an initializer with 'scope' argument"
}
