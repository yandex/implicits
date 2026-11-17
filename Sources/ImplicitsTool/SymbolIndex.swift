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
    typealias ParameterAutomaton = Automaton<String, Symbol>

    var impl = [[String]: ParameterAutomaton]()
    private var signatures = Set<CallableSignature>()

    func findFunction(
      args: [String],
      namespace: [String]
    ) -> [Symbol] {
      impl[namespace]?.match(args) ?? []
    }

    mutating func addLookaheads(_ lookaheads: [Symbol]) {
      for lookahead in lookaheads {
        let namespace = lookahead.namespace.value
        if signatures.insert(lookahead.callableSignature).inserted {
          let pattern: ParameterAutomaton.Pattern = .sequence(
            lookahead.parameters.map {
              $0.hasDefaultValue ? .optional($0.name) : .exact($0.name)
            }
          )
          impl[namespace, default: Automaton()]
            .addPattern(pattern, value: lookahead)
        }
      }
    }

    func match(_ image: SymbolImage) -> [Symbol] {
      var matches: [Symbol] = []
      matches += findFunction(
        args: image.arguments, namespace: image.namespace
      ).filter {
        switch (image.kind, $0.kind) {
        case (.callAsFunction, .callAsFunction),
             (.explicitInit, .initializer), (.static, .initializer):
          true
        case let (.member(name: lName), .memberFunction(name: rName)):
          lName == rName
        default:
          false
        }
      }
      if !image.namespace.isEmpty {
        matches += findFunction(
          args: image.arguments, namespace: image.namespace.dropLast()
        ).filter {
          switch (image.kind, $0.kind) {
          case let (.static, .staticFunction(name: name)):
            name == image.namespace.last
          default:
            false
          }
        }
      }
      return matches
    }

    func findInitializer(
      namespace: [String],
      args: [String]
    ) -> [Symbol] {
      match(.explicitInit(namespace: namespace, args: args))
    }
  }
}

extension FunctionKind {
  fileprivate func matches(with other: Self) -> Bool {
    switch (self, other) {
    // initializer optionality is ignored
    case (.initializer, .initializer):
      true
    default:
      self == other
    }
  }
}
