// Copyright 2023 Yandex LLC. All rights reserved.

import Foundation

import SwiftSyntax

public enum StaticAnalysis {
  public struct SourceFileInput {
    var ast: SyntaxProtocol
    var filename: String

    public init(ast: SyntaxProtocol, filename: String) {
      self.ast = ast
      self.filename = filename
    }
  }

  public struct Result {
    public var diagnostics: [Diagnostic]
    public var supportFile: SupportFile
    public var publicInterface: ImplicitModuleInterface
  }

  public static func run(
    files: [SourceFileInput],
    modulename: String,
    dependencies: [ImplicitModuleInterface],
    compilationConditions: CompilationConditionsConfig,
    enableExporting: Bool
  ) -> Result {
    typealias FileSyntax =
      (name: String, content: [SyntaxTree<SyntaxInfo>.TopLevelEntity])
    let syntaxTrees: [FileSyntax] = files.map { file in
      let sourceLocationConverter = SourceLocationConverter(
        fileName: file.filename,
        tree: Syntax(fromProtocol: file.ast)
      )
      let syntaxTree = SyntaxTree.build(
        file.ast,
        ifConfig: compilationConditions
      ).map { topLevel in
        topLevel.mapSyntax { swiftSyntax in
          SyntaxInfo.internal(
            converter: sourceLocationConverter, syntax: swiftSyntax
          )
        }
      }
      return (name: file.filename, content: syntaxTree)
    }

    var diagnostics: Diagnostics<SyntaxInfo> = Diagnostics()

    enum SyntaxInfoAdditional: SyntaxAdditionalInfo {
      static func location(of syntax: SyntaxInfo) -> Diagnostic.Location {
        syntax.codeLocation
      }
    }

    typealias SMTBuilder = SemaTreeBuilder<SyntaxInfo, SyntaxInfoAdditional>

    var dependenciesForSema = SMTBuilder.Dependencies()
    for dep in dependencies {
      let symbols = dep.symbols.map { symbol in
        symbol.info.mapSyntax { SyntaxInfo.external($0) }
      }
      let testableSymbols = dep.testableSymbols.map { symbol in
        symbol.info.mapSyntax { SyntaxInfo.external($0) }
      }
      let reexportedModules = dep.reexportedModules
      dependenciesForSema[dep.module] = (symbols, testableSymbols, reexportedModules)
    }

    let semaTrees = SMTBuilder.build(
      modulename: modulename, module: syntaxTrees,
      dependencies: dependenciesForSema,
      enableExporting: enableExporting,
      diagnostics: &diagnostics
    )

    let reqGraph = buildRequrementsGraph(
      sema: Array(zip(syntaxTrees, semaTrees)),
      diagnostics: &diagnostics,
      dependencies: dependencies.flatMap { $0.symbols.map { symbol in
        (symbol.info.mapSyntax { .external($0) }, symbol.requirements)
      }} + dependencies.flatMap { $0.testableSymbols.map { symbol in
        (symbol.info.mapSyntax { .external($0) }, symbol.requirements)
      }}
    )
    let checked = reqGraph.resolveRequirements(
      diagnostics: &diagnostics
    )

    var externalFuncsWithImplicits = [SymbolInfo<Diagnostic.Location>: [ImplicitKey]]()
    for funcWithImplcits in checked.publicInterface {
      externalFuncsWithImplicits[funcWithImplcits.0.mapSyntax(\.codeLocation)] = funcWithImplcits.1
    }

    var testableFuncsWithImplicits = [SymbolInfo<Diagnostic.Location>: [ImplicitKey]]()
    for funcWithImplcits in checked.testableInterface {
      testableFuncsWithImplicits[funcWithImplcits.0.mapSyntax(\.codeLocation)] = funcWithImplcits.1
    }

    let publicFunctions = SMTBuilder.Scout.lookaheadModule(
      syntaxTrees, scope: .module, dependencies: dependenciesForSema
    ).symbols.map { ($0.0.mapSyntax(\.codeLocation), $0.1) }

    let externalSymbols = publicFunctions.compactMap {
      $0.1.moreOrEqualVisible(than: .package) ? ImplicitModuleInterface.Symbol(
        info: $0.0, requirements: externalFuncsWithImplicits[$0.0]
      ) : nil
    }
    let testableSymbols = publicFunctions.compactMap {
      $0.1.moreOrEqualVisible(than: .internal) &&
        $0.1.lessOrEqualVisible(than: .package) ? ImplicitModuleInterface.Symbol(
          info: $0.0, requirements: testableFuncsWithImplicits[$0.0]
        ) : nil
    }

    let (supportFile, generatedSymbols) = SupportFileBuilder.build(
      syntaxTrees: syntaxTrees, semaTrees: semaTrees,
      implicitFunctions: checked.implicitFunctions,
      bags: checked.bags,
      namedImplicitsWrappers: checked.namedImplicitsWrappers,
      enableExporting: enableExporting,
      dependencies: dependencies,
      diagnostics: &diagnostics,
      syntaxToLocation: \.codeLocation
    )

    let reexportedModules = syntaxTrees.flatMap {
      $0.content.compactMap(\.value.import).filter {
        $0.attributes.contains(where: \.isExported)
      }
    }

    let publicInterface = ImplicitModuleInterface(
      module: modulename,
      symbols: externalSymbols + generatedSymbols,
      testableSymbols: testableSymbols,
      definedKeypathKeys: supportFile.keys
        .filter { $0.visibility.moreOrEqualVisible(than: .package) }
        .map { .init(name: $0.name, type: $0.type) },
      reexportedModules: reexportedModules.map(\.moduleName)
    )

    return Result(
      diagnostics: diagnostics.map { Diagnostic($0) },
      supportFile: supportFile,
      publicInterface: publicInterface
    )
  }
}

enum SyntaxInfo {
  case `internal`(converter: SourceLocationConverter, syntax: Syntax)
  case external(Diagnostic.Location)

  var codeLocation: Diagnostic.Location {
    switch self {
    case let .internal(converter, syntax):
      .init(syntax.startLocation(converter: converter))
    case let .external(loc):
      loc
    }
  }

  // For debug purposes
  var syntax: Syntax? {
    switch self {
    case let .internal(_, syntax): syntax
    case .external: nil
    }
  }
}

extension Diagnostic {
  init(_ pre: PreDiagnostic<SyntaxInfo>) {
    let loc: Location
    let lineString: String
    switch pre.syntax {
    case let .internal(converter, syntax):
      loc = Location(syntax.startLocation(converter: converter))
      lineString = converter.sourceLines[loc.line - 1]
        .trimmingCharacters(in: .newlines)
    case let .external(external):
      loc = external
      lineString = ""
    }
    self.severity = pre.severity
    self.message = pre.message.value
    self.codeLine = String(lineString)
    self.loc = loc
  }
}

extension Diagnostic.Location {
  init(_ location: SourceLocation) {
    self.init(file: location.file, line: location.line, column: location.column)
  }
}

extension SyntaxTree.TopLevelStatement {
  var `import`: SyntaxTree.ImportDecl? {
    guard case let .import(value) = self else { return nil }
    return value
  }
}

extension SyntaxTree.Attribute {
  var isExported: Bool {
    self.simpleIdentifier == "_exported" && self.arguments == nil
  }
}
