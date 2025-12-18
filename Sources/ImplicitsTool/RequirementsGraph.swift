// Copyright 2024 Yandex LLC. All rights reserved.

public struct RequirementsGraph<Syntax, File> {
  typealias Symbol = SymbolInfo<Syntax>
  struct Node: CustomStringConvertible {
    var payload: Syntax
    var provides: Set<ImplicitKey>
    var requires: Set<ImplicitKey>

    var description: String {
      "\(payload): provides \(provides), requires \(requires)"
    }
  }

  typealias Graph = OrderedGraph<Node, Void>
  var graph: Graph
  var entryPoints: [Graph.Index]
  var bags: [(Graph.Index, name: String, File)]
  var namedImplicitsWrappers: [(Graph.Index, wrapperName: String, closureParamCount: Int, File)]
  var publicInterface: [(Graph.Index, Symbol)]
  var testableInterface: [(Graph.Index, Symbol)]
  var implicitFunctions: [(Graph.Index, File, SemaTree<Syntax>.FuncDecl)]
}

extension RequirementsGraph {
  typealias Diagnostics = DiagnosticsGeneric<Syntax>
  struct ResolveRequirementsResult {
    var bags: [(name: String, requirements: [ImplicitKey], File)]
    var namedImplicitsWrappers: [(
      wrapperName: String,
      closureParamCount: Int,
      requirements: [ImplicitKey],
      File
    )]
    var publicInterface: [(Symbol, [ImplicitKey])]
    var testableInterface: [(Symbol, [ImplicitKey])]
    var implicitFunctions: [(SemaTree<Syntax>.FuncDecl, File, [ImplicitKey])]
  }

  func resolveRequirements(
    diagnostics: inout Diagnostics
  ) -> ResolveRequirementsResult {
    var cache = [Graph.Index: Set<ImplicitKey>]()
    for ep in entryPoints {
      let reqs = resolveRequirements(from: ep, cache: &cache, path: [])
      diagnostics.check(
        reqs.isEmpty, or: .unresolvedRequirements(reqs),
        at: graph[ep].payload
      )
    }
    let bags = self.bags.map { (
      name: $0.name,
      requirements: resolveRequirements(from: $0.0, cache: &cache, path: [])
        .sorted { $0.lexicographicalOrder < $1.lexicographicalOrder },
      file: $0.2
    ) }
    let namedImplicitsWrappers = self.namedImplicitsWrappers
      .map { idx, wrapperName, paramCount, file in
        let reqs = resolveRequirements(from: idx, cache: &cache, path: [])
          .sorted { $0.lexicographicalOrder < $1.lexicographicalOrder }
        return (
          wrapperName: wrapperName,
          closureParamCount: paramCount,
          requirements: reqs,
          file: file
        )
      }
    let publicInterface = self.publicInterface.map { index, signature in
      let reqs = resolveRequirements(from: index, cache: &cache, path: [])
        .sorted { $0.lexicographicalOrder < $1.lexicographicalOrder }
      return (signature, reqs)
    }
    let testableInterface = self.testableInterface.map { index, signature in
      let reqs = resolveRequirements(from: index, cache: &cache, path: [])
        .sorted { $0.lexicographicalOrder < $1.lexicographicalOrder }
      return (signature, reqs)
    }
    let implicitFunctions = self.implicitFunctions.map { idx, file, funcDecl in
      let reqs = resolveRequirements(from: idx, cache: &cache, path: [])
        .sorted { $0.lexicographicalOrder < $1.lexicographicalOrder }
      return (funcDecl, file, reqs)
    }
    return ResolveRequirementsResult(
      bags: bags,
      namedImplicitsWrappers: namedImplicitsWrappers,
      publicInterface: publicInterface,
      testableInterface: testableInterface,
      implicitFunctions: implicitFunctions
    )
  }

  func resolveRequirements(
    from: Graph.Index,
    cache: inout [Graph.Index: Set<ImplicitKey>],
    path: Set<Graph.Index>
  ) -> Set<ImplicitKey> {
    if let cached = cache[from] {
      return cached
    }
    if path.contains(from) {
      // Cycle in graph because of recursion.
      // It's ok to return empty here, as all the requirements are already
      // taken into account in the cycle.
      return []
    }
    let node = graph.valueWithEdges(at: from)
    let path = path.union([from])
    var reqs = node.successors.reduce(into: Set()) {
      $0.formUnion(resolveRequirements(from: $1.key, cache: &cache, path: path))
    }
    requirements(of: &reqs, considering: node.value)
    return reqs
  }
}

// Modifies set of requirements, according to the requirements and provides of
// the given node
func requirements(
  of reqs: inout Set<ImplicitKey>,
  considering node: RequirementsGraph<some Any, some Any>.Node
) {
  reqs.formUnion(node.requires)
  reqs.subtract(node.provides)
}

extension DiagnosticMessage {
  static func unresolvedRequirements(_ reqs: Set<ImplicitKey>) -> Self {
    let reqString = reqs.map(\.descriptionForDiagnostics)
      .sorted().joined(separator: ", ")
    return "Unresolved requirement\(reqs.count > 1 ? "s" : ""): \(reqString)"
  }
}
