// Copyright 2025 Yandex LLC. All rights reserved.

/// The `SymbolImage` struct represents symbols as it "looks like" at the call site.
struct SymbolImage {
  enum Kind {
    // $somevar.method(...), $somevar is an expression with known namespace
    case member(name: String)
    // SomeClass.AnotherClass.method(...)
    case `static`
    // SomeClass.init(...) or self.init(...) or Self.init(...)
    case explicitInit
    // $somevar(...), $somevar is an expression with known namespace
    case callAsFunction
  }

  var kind: Kind
  var namespace: [String]
  var arguments: [String]

  init(kind: Kind, namespace: [String], arguments: [String]) {
    self.kind = kind
    self.namespace = namespace
    self.arguments = arguments
  }

  static func member(
    name: String, namespace: [String], args: [String]
  ) -> Self {
    .init(kind: .member(name: name), namespace: namespace, arguments: args)
  }

  static func `static`(namespace: [String], args: [String]) -> Self {
    .init(kind: .static, namespace: namespace, arguments: args)
  }

  static func explicitInit(namespace: [String], args: [String]) -> Self {
    .init(kind: .explicitInit, namespace: namespace, arguments: args)
  }

  static func callAsFunction(namespace: [String], args: [String]) -> Self {
    .init(kind: .callAsFunction, namespace: namespace, arguments: args)
  }
}

extension SemaTreeBuilder {
  struct SymbolIndex {
    typealias Symbol = SymbolInfoGeneric<Syntax>

    private struct Node {
      var transitions: [Int: [Int]] = [:]
      var values: [Int] = []
    }

    private struct ParameterAutomaton {
      var nodes = [Node()]

      mutating func add(_ parameters: [Parameter], value: Int) {
        var previous = [0]
        for parameter in parameters {
          let next = nodes.count
          nodes.append(Node())
          for state in previous {
            nodes[state].transitions[parameter.label, default: []].append(next)
          }
          if parameter.optional {
            previous.append(next)
          } else {
            previous = [next]
          }
        }
        for state in previous { nodes[state].values.append(value) }
      }

      func matches(_ input: [Int]) -> [Int] {
        var current: Set = [0]
        for label in input {
          var next: Set<Int> = []
          for state in current {
            if let destinations = nodes[state].transitions[label] {
              next.formUnion(destinations)
            }
          }
          current = next
          if current.isEmpty {
            return []
          }
        }
        var result: [Int] = []
        for state in current { result.append(contentsOf: nodes[state].values) }
        return result
      }
    }

    private struct Bucket {
      var signatures: Set<Signature> = []
      var automaton = ParameterAutomaton()
      var entries: [Symbol] = []

      mutating func insert(signature: Signature, parameters: [Parameter], entry: Symbol) {
        guard signatures.insert(signature).inserted else { return }
        automaton.add(parameters, value: entries.count)
        entries.append(entry)
      }
    }

    private let strings = Strings()
    private var buckets: [[Int]: Bucket] = [:]

    mutating func addLookaheads(_ lookaheads: [Symbol]) {
      for symbol in lookaheads {
        let (namespace, key, parameters) = strings.encode(symbol)
        if buckets[namespace]?.signatures.contains(key) == true {
          continue
        }
        buckets[namespace, default: Bucket()].insert(
          signature: key, parameters: parameters, entry: symbol
        )
      }
    }

    private func find(
      kind: SymbolImage.Kind?,
      namespace: [String],
      args: [String]
    ) -> [Symbol] {
      let ns = namespace.map { strings.id($0) }
      let arguments = args.map { strings.id($0) }
      var result: [Symbol] = []
      if let bucket = buckets[ns] {
        for id in bucket.automaton.matches(arguments) {
          let symbol = bucket.entries[id]
          let accepts: Bool =
            switch (kind, symbol.kind) {
            case (nil, _): true
            case (.callAsFunction?, .callAsFunction),
                 (.explicitInit?, .initializer),
                 (.static?, .initializer): true
            case let (.member(name: requested)?, .memberFunction(name: actual)):
              requested == actual
            default: false
            }
          if accepts {
            result.append(symbol)
          }
        }
      }
      if case .static? = kind, let last = namespace.last,
         let bucket = buckets[Array(ns.dropLast())] {
        for id in bucket.automaton.matches(arguments) {
          let symbol = bucket.entries[id]
          if case let .staticFunction(name) = symbol.kind, name == last {
            result.append(symbol)
          }
        }
      }
      return result
    }

    func findFunction(args: [String], namespace: [String]) -> [Symbol] {
      find(kind: nil, namespace: namespace, args: args)
    }

    func findInitializer(namespace: [String], args: [String]) -> [Symbol] {
      match(.explicitInit(namespace: namespace, args: args))
    }

    func match(_ image: SymbolImage) -> [Symbol] {
      find(kind: image.kind, namespace: image.namespace, args: image.arguments)
    }
  }
}
