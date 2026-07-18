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

  typealias WrapperInfo<Resolution> = ImplicitsTool.WrapperInfo<Resolution, File, Syntax>

  typealias Graph = OrderedGraph<Node, Void>
  var graph: Graph
  var entryPoints: [Graph.Index]
  var bags: [(Graph.Index, name: String, File)]
  var namedImplicitsWrappers: [WrapperInfo<Graph.Index>]
  var publicInterface: [(Graph.Index, Symbol)]
  var testableInterface: [(Graph.Index, Symbol)]
  var implicitFunctions: [(Graph.Index, File, SemaTree<Syntax>.FuncDecl)]
  var traceEntryPoints: Set<Graph.Index>
}

extension RequirementsGraph {
  typealias Diagnostics = DiagnosticsGeneric<Syntax>
  struct ResolveRequirementsResult {
    var bags: [(name: String, requirements: [ImplicitKey], File)]
    var namedImplicitsWrappers: [WrapperInfo<[ImplicitKey]>]
    var publicInterface: [(Symbol, [ImplicitKey])]
    var testableInterface: [(Symbol, [ImplicitKey])]
    var implicitFunctions: [(SemaTree<Syntax>.FuncDecl, File, [ImplicitKey])]
  }

  func resolveRequirements(
    diagnostics: inout Diagnostics,
    traceUnresolved: Bool = false
  ) -> ResolveRequirementsResult {
    var cache = [Graph.Index: Set<ImplicitKey>]()
    for ep in entryPoints {
      let reqs = resolveRequirements(from: ep, cache: &cache, path: [])
      diagnostics.check(
        reqs.isEmpty, or: .unresolvedRequirements(reqs),
        at: graph[ep].payload
      )
      if traceUnresolved, !reqs.isEmpty {
        emitTraceNotes(
          from: ep, unresolvedKeys: reqs, cache: cache,
          diagnostics: &diagnostics
        )
      }
    }
    let bags = self.bags.map { (
      name: $0.name,
      requirements: resolveRequirements(from: $0.0, cache: &cache, path: [])
        .sorted { $0.lexicographicalOrder < $1.lexicographicalOrder },
      file: $0.2
    ) }
    let namedImplicitsWrappers = self.namedImplicitsWrappers
      .map { wrapper in
        let reqs = resolveRequirements(from: wrapper.resolution, cache: &cache, path: [])
          .sorted { $0.lexicographicalOrder < $1.lexicographicalOrder }
        return WrapperInfo(
          wrapperName: wrapper.wrapperName,
          closureParamCount: wrapper.closureParamCount,
          effects: wrapper.effects,
          resolution: reqs,
          file: wrapper.file
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

  func emitTraceNotes(
    from entryPoint: Graph.Index,
    unresolvedKeys: Set<ImplicitKey>,
    cache: [Graph.Index: Set<ImplicitKey>],
    diagnostics: inout Diagnostics
  ) {
    var emitted = Set<[Graph.Index: DiagnosticMessage]>()
    for key in unresolvedKeys.sorted(by: { $0.lexicographicalOrder < $1.lexicographicalOrder }) {
      let path = tracePath(from: entryPoint, forKey: key, cache: cache)
      for (i, nodeIdx) in path.enumerated() {
        let noteIdx: Graph.Index
        if graph[nodeIdx].requires.contains(key) {
          noteIdx = nodeIdx
        } else if traceEntryPoints.contains(nodeIdx), i > 0 {
          noteIdx = path[i - 1]
        } else {
          continue
        }
        let msg = DiagnosticMessage.requires(key)
        if emitted.insert([noteIdx: msg]).inserted {
          diagnostics.note(msg, at: graph[noteIdx].payload)
        }
      }
    }
  }

  func tracePath(
    from start: Graph.Index,
    forKey key: ImplicitKey,
    cache: [Graph.Index: Set<ImplicitKey>]
  ) -> [Graph.Index] {
    func sortedSuccessors(of idx: Graph.Index) -> [Graph.Index] {
      graph.valueWithEdges(at: idx).successors.keys.sorted(by: >)
    }
    var path = [Graph.Index]()
    var visited = Set<Graph.Index>()
    var stack: [IndexingIterator<[Graph.Index]>] = []
    visited.insert(start)
    path.append(start)
    if graph[start].requires.contains(key) {
      return path
    }
    stack.append(sortedSuccessors(of: start).makeIterator())
    while !stack.isEmpty {
      guard let successor = stack[stack.count - 1].next() else {
        stack.removeLast()
        path.removeLast()
        continue
      }
      guard visited.insert(successor).inserted,
            cache[successor]?.contains(key) == true else { continue }
      path.append(successor)
      if graph[successor].requires.contains(key) {
        return path
      }
      stack.append(sortedSuccessors(of: successor).makeIterator())
    }
    return []
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
    cache[from] = reqs
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

  static func requires(_ key: ImplicitKey) -> Self {
    "Requires '\(key.descriptionForDiagnostics)'"
  }
}

struct WrapperInfo<Resolution, File, Syntax> {
  var wrapperName: String
  var closureParamCount: Int
  var effects: ClosureEffects<Syntax>
  var resolution: Resolution
  var file: File
}
