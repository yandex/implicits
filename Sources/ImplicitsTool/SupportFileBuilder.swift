// Copyright 2025 Yandex LLC. All rights reserved.

enum SupportFileBuilder<Syntax> {
  typealias Diagnostics = DiagnosticsGeneric<Syntax>
  typealias SyntaxTreeFile = (name: String, content: [SyntaxTree<SyntaxInfo>.TopLevelEntity])

  private typealias ImplicitParameter = SupportFile.ImplicitParameter

  // Elements of syntaxTrees and semaTrees must correspond to each other
  // (represent the same file).
  // TODO: Enforce this in the type system
  static func build(
    syntaxTrees: [SyntaxTreeFile],
    semaTrees: [[SemaTree<Syntax>.TopLevel]],
    implicitFunctions: [(SemaTree<Syntax>.FuncDecl, SyntaxTreeFile, [ImplicitKey])],
    bags: [(name: String, requirements: [ImplicitKey], file: SyntaxTreeFile)],
    enableExporting: Bool,
    dependencies: [ImplicitModuleInterface],
    diagnostics: inout Diagnostics,
    syntaxToLocation: (Syntax) -> Diagnostic.Location
  ) -> (
    SupportFile, generatedSymbols: [ImplicitModuleInterface.Symbol]
  ) {
    var keyDecls: [Sema.ImplicitKeyDecl] = []
    var imports = ImportsIndex()
    var ifFalseImports = ImportsIndex()
    for (syntaxTree, sematree) in zip(syntaxTrees, semaTrees) {
      let keys = sematree.flatMap {
        if case let .keysDeclaration(keyDecl) = $0.node {
          return keyDecl
        }
        return []
      }
      keyDecls += keys
      let needsImports = !keys.isEmpty
      if needsImports {
        imports.registerImports(from: syntaxTree, blame: "keys")
      }
    }

    let keyIndex = {
      var index: [String: (ImplicitParameter, import: String?)] = [:]
      for dependency in dependencies {
        for key in dependency.definedKeypathKeys {
          index[key.name] = (
            ImplicitParameter(
              name: key.name, type: key.type, key: .keyPath(key.name)
            ),
            dependency.module
          )
        }
      }
      for keyDecl in keyDecls {
        index[keyDecl.name] = (
          ImplicitParameter(
            name: keyDecl.name, type: keyDecl.type, key: .keyPath(keyDecl.name)
          ),
          nil
        )
      }
      return index
    }()

    var needsAdapter = [(SupportFile.FuncSignature, [ImplicitParameter])]()
    var generatedSymbols = [ImplicitModuleInterface.ExternalSymbol]()
    var needsAdapterIfFalse = [(SupportFile.FuncSignature, [ImplicitParameter])]()
    for (funcDecl, file, keys) in implicitFunctions {
      guard funcDecl.visibility.moreOrEqualVisible(than: .internal) else {
        continue
      }
      let parameters = keys.compactMap { key -> ImplicitParameter? in
        switch key.kind {
        case .type:
          return ImplicitParameter(
            name: parameterNameFromType(key.name),
            type: key.name,
            key: key
          )
        case .keyPath:
          guard let (parameter, importModule) = keyIndex[key.name] else {
            diagnostics.diagnose(
              .missingKey(key.name),
              at: funcDecl.signature.syntax
            )
            return nil
          }
          if let importModule, enableExporting {
            imports.registerImport(
              module: importModule, visibility: .private,
              blame: "key '\(key.name)'"
            )
          }
          return parameter
        }
      }.sorted { $0.name < $1.name }
      if enableExporting {
        imports.registerImports(from: file, blame: "implicit functions")
      } else {
        ifFalseImports.registerImports(from: file, blame: "implicit functions")
      }
      let isConvenience = funcDecl.enclosingTypeIsClass ||
        funcDecl.modifiers.contains(.convenience)
      let adapterFuncDecl = SupportFile.FuncSignature(
        signature: funcDecl.signature.mapSyntax { _ in },
        visibility: funcDecl.visibility,
        hasScopeParameter: funcDecl.hasScopeParameter,
        parameters: funcDecl.parameters.map {
          ($0.name, String(describing: $0.type))
        },
        isConvinience: isConvenience,
        returnType: funcDecl.returnType
      )
      if enableExporting, adapterFuncDecl.visibility.moreOrEqualVisible(than: .public) {
        needsAdapter.append((adapterFuncDecl, parameters))
        var symbol = funcDecl.signature.mapSyntax(syntaxToLocation)
        symbol.parameters.removeLast()
        for parameter in parameters {
          symbol.parameters.append(.init(
            name: parameter.name, type: "@auto_closure () -> \(parameter.type)"
          ))
        }
        generatedSymbols.append(symbol)
      } else {
        needsAdapterIfFalse.append((adapterFuncDecl, parameters))
      }
    }

    for (_, _, file) in bags {
      imports.registerImports(from: file, blame: "bags")
    }
    let supprotFile = SupportFile(
      keys: keyDecls,
      imports: imports.sortedImports(),
      ifFalseImports: ifFalseImports.sortedImports(),
      functions: needsAdapter,
      ifFalseFunctions: needsAdapterIfFalse,
      bags: bags.map { ($0.0, $0.1) }
    )
    return (
      supprotFile, generatedSymbols.map { .init(info: $0, requrements: nil) }
    )
  }
}

private struct ImportsIndex {
  var store: [String: [(Visibility, debugBlame: String)]] = [:]

  private mutating func register(
    key: String, visibility: Visibility, blame: String
  ) {
    store[key, default: []].append((visibility, blame))
  }

  mutating func registerImport(
    module: String, visibility: Visibility, blame: String
  ) {
    register(key: module, visibility: visibility, blame: blame)
  }

  mutating func registerImport(
    _ decl: SyntaxTree<some Any>.ImportDecl, blame: String
  ) {
    register(
      key: decl.importedSymbolDescr,
      visibility: decl.visibility, blame: blame
    )
  }

  mutating func registerImports(
    from: SupportFileBuilder.SyntaxTreeFile, blame: String
  ) {
    for importDecl in from.content.compactMap(\.value.import) {
      registerImport(importDecl, blame: "\(blame) from \(from.name)")
    }
  }

  func sortedImports() -> [(Visibility, String, debugBlame: String)] {
    store.map {
      (
        $0.value.max {
          $0.0.visibilityRelation < $1.0.visibilityRelation
        }?.0 ?? .default,
        $0.key,
        debugBlame: $0.value.map(\.debugBlame).joined(separator: ", ")
      )
    }.sorted { $0.1 < $1.1 }
  }
}

/// Returns a camel-cased name for the parameter based on the type name.
///
/// It removes any non-alphanumeric characters
/// and capitalizes the first letter of each word.
/// For example:
/// `Bool` -> `bool`, `Foo.Bar` -> `fooBar`,
/// `(Int32) -> Void` -> `int32Void`
fileprivate func parameterNameFromType(_ type: String) -> String {
  type.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).enumerated()
    .map { index, s in
      s.mapFirstLetter { index > 0 ? $0.uppercased() : $0.lowercased() }
    }
    .joined()
}

extension StringProtocol {
  fileprivate func mapFirstLetter(_ t: (Character) -> String) -> String {
    guard let first else { return String(self) }
    return String(t(first)) + dropFirst()
  }
}

extension DiagnosticMessage {
  static func missingKey(_ key: String) -> Self {
    "[BUG IN IMPLICITS] Key '\(key)' is not found in keys index"
  }
}

extension SyntaxTree.ImportDecl {
  var importedSymbolDescr: String {
    guard let type else { return moduleName }
    let components = [moduleName] + path
    return "\(type) \(components.joined(separator: "."))"
  }
}
