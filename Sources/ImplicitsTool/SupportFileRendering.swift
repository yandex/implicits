// Copyright 2025 Yandex LLC. All rights reserved.

import SwiftSyntax
import SwiftSyntaxBuilder

extension SupportFile {
  /// Renders the support file as a Swift code block.
  ///
  /// - Parameters:
  ///  - accessLevelOnImports: Whether to add access level modifiers to the imports.
  ///  - legacyMode: Whether to render imports for the `if false` block outside of the `if false`
  /// block.
  public func render(
    accessLevelOnImports: Bool = true,
    legacyMode: Bool = true,
    debugInfo: Bool = false
  ) -> CodeBlockItemListSyntax {
    let imports = importSyntax(
      imports: imports,
      needsImplicitsUnsafeSPI: !bags.isEmpty || !namedImplicitsWrappers.isEmpty,
      accessLevelOnImports: accessLevelOnImports,
      renderBlame: debugInfo
    ).map { DeclSyntax($0) }
    let ifFalseImports = importSyntax(
      imports: ifFalseImports,
      needsImplicitsUnsafeSPI: false,
      accessLevelOnImports: accessLevelOnImports,
      renderBlame: debugInfo
    ).map { DeclSyntax($0) }
    let keys = keysSyntax()
    let publicFunctions = adapterFunctions(for: functions)
      .map { DeclSyntax($0) }
    let ifFalseFunctions = adapterFunctions(for: ifFalseFunctions)
      .map { DeclSyntax($0) }
    return CodeBlockItemListSyntax(itemsBuilder: {
      imports
      if legacyMode {
        ifFalseImports
      }
      if !keys.isEmpty {
        DeclSyntax.extension(TypeSyntax("ImplicitsKeys"), keys)
      }
      bagsSyntax().map { DeclSyntax($0) }
      namedImplicitsWrappersSyntax().map { DeclSyntax($0) }
      publicFunctions
      if !ifFalseFunctions.isEmpty {
        IfConfigDeclSyntax(clauses: IfConfigClauseListSyntax {
          IfConfigClauseSyntax(
            poundKeyword: .poundIfToken(),
            condition: "false" as ExprSyntax,
            elements: .statements(CodeBlockItemListSyntax(itemsBuilder: {
              if !legacyMode {
                ifFalseImports
              }
              ifFalseFunctions
            }))
          )
        })
      }
    })
  }

  private func keysSyntax() -> [MemberBlockItemSyntax] {
    keys.flatMap { key in
      let visibility = key.visibility.render()
      let tagName = "_" + key.name.withFirstLetterUppercased() + "Tag"
      let modifiers = DeclModifierListSyntax {
        if let visibility {
          visibility
        }
      }
      let keyType = TypeSyntax("ImplicitKey<\(raw: key.type), \(raw: tagName)>")
      let binding = PatternBindingSyntax(
        pattern: IdentifierPatternSyntax(identifier: "\(raw: key.name)"),
        typeAnnotation: TypeAnnotationSyntax(
          type: "\(keyType).Type" as TypeSyntax
        ),
        accessorBlock: AccessorBlockSyntax(
          accessors: .getter(["\(keyType).self"])
        )
      )
      let getter = VariableDeclSyntax(
        attributes: AttributeListSyntax {
          if key.visibility.moreOrEqualVisible(than: .public) {
            .inlinable
          }
        },
        modifiers: modifiers,
        bindingSpecifier: .keyword(.var),
        bindings: [binding]
      )
      let tag = EnumDeclSyntax(
        modifiers: .init(itemsBuilder: {
          if let visibility {
            visibility
          }
        }),
        name: .identifier(tagName),
        memberBlock: .init(members: [])
      )
      return [
        MemberBlockItemSyntax(decl: tag),
        MemberBlockItemSyntax(decl: getter),
      ]
    }
  }

  private func adapterFunctions(
    for functions: [(FuncSignature, [ImplicitParameter])]
  ) -> [DeclSyntax] {
    var namespaces = [String: [DeclSyntax]]()
    var withoutNamespace = [DeclSyntax]()
    for (f, requirements) in functions {
      let (namespace, decl) = adaptionFunctionSyntax(
        decl: f, additionalParamters: requirements
      )
      if let namespace {
        namespaces[namespace, default: []].append(decl)
      } else {
        withoutNamespace.append(decl)
      }
    }
    let extensions = namespaces
      .sorted { $0.key < $1.key }
      .map { namespace, functions in
        DeclSyntax.extension(
          "\(raw: namespace)",
          functions.map { MemberBlockItemSyntax(decl: $0) }
        )
      }
    return withoutNamespace + extensions
  }

  private func bagsSyntax() -> [FunctionDeclSyntax] {
    bags.map { name, requirements in
      FunctionDeclSyntax(
        modifiers: [.internal],
        name: "\(raw: name)",
        signature: FunctionSignatureSyntax(
          parameterClause: FunctionParameterClauseSyntax(parameters: []),
          returnClause: ReturnClauseSyntax(type: TypeSyntax("Implicits"))
        ),
        body: CodeBlockSyntax { implicitsCallSyntax(requirements: requirements) }
      )
    }
  }

  private func namedImplicitsWrappersSyntax() -> [FunctionDeclSyntax] {
    namedImplicitsWrappers.map { wrapper in
      let genericParams = GenericParameterClauseSyntax {
        GenericParameterSyntax(name: "T")
        for i in 0..<wrapper.closureParamCount {
          GenericParameterSyntax(name: "A\(raw: i + 1)")
        }
      }

      let closureParamTypes: [String] = (0..<wrapper.closureParamCount)
        .map { "A\($0 + 1)" } + ["ImplicitScope"]
      let closureType = "(\(closureParamTypes.joined(separator: ", "))) -> T"

      let returnParamTypes: [String] = (0..<wrapper.closureParamCount).map { "A\($0 + 1)" }
      let returnType = returnParamTypes.isEmpty ? "() -> T" : "(\(returnParamTypes.joined(separator: ", "))) -> T"

      let funcSignature = FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(parameters: [
          FunctionParameterSyntax(
            firstName: "_",
            secondName: "body",
            type: "@escaping \(raw: closureType)" as TypeSyntax
          ),
        ]),
        returnClause: ReturnClauseSyntax(type: "\(raw: returnType)" as TypeSyntax)
      )

      let funcName =
        ImplicitKeyword.ClosureWrapper.prefix +
        wrapper.wrapperName +
        ImplicitKeyword.ClosureWrapper.suffix
      let argNames = (0..<wrapper.closureParamCount).map { "arg\($0 + 1)" }

      let body = CodeBlockSyntax {
        VariableDeclSyntax(
          .let,
          name: "implicits",
          initializer: InitializerClauseSyntax(
            value: implicitsCallSyntax(requirements: wrapper.requirements)
          )
        )

        ReturnStmtSyntax(expression: ClosureExprSyntax(
          signature: wrapper.closureParamCount > 0 ? ClosureSignatureSyntax(
            parameterClause: .simpleInput(ClosureShorthandParameterListSyntax {
              for argName in argNames {
                ClosureShorthandParameterSyntax(name: .identifier(argName))
              }
            })
          ) : nil,
          statements: CodeBlockItemListSyntax {
            VariableDeclSyntax(
              .let,
              name: "scope",
              initializer: InitializerClauseSyntax(
                value: FunctionCallExprSyntax(callee: "ImplicitScope" as ExprSyntax) {
                  LabeledExprSyntax(label: "with", expression: "implicits" as ExprSyntax)
                }
              )
            )
            DeferStmtSyntax {
              FunctionCallExprSyntax(callee: "scope.end" as ExprSyntax)
            }
            ReturnStmtSyntax(expression: FunctionCallExprSyntax(callee: "body" as ExprSyntax) {
              for argName in argNames {
                LabeledExprSyntax(expression: "\(raw: argName)" as ExprSyntax)
              }
              LabeledExprSyntax(expression: "scope" as ExprSyntax)
            })
          }
        ))
      }

      return FunctionDeclSyntax(
        modifiers: [.internal],
        name: "\(raw: funcName)",
        genericParameterClause: genericParams,
        signature: funcSignature,
        body: body
      )
    }
  }
}

private func implicitsCallSyntax(requirements: [ImplicitKey]) -> FunctionCallExprSyntax {
  FunctionCallExprSyntax(callee: "Implicits" as ExprSyntax) {
    if let first = requirements.first {
      LabeledExprSyntax(label: "unsafeKeys", expression: first.getRawKeyValueSyntax())
    }
    for req in requirements.dropFirst() {
      LabeledExprSyntax(expression: req.getRawKeyValueSyntax())
    }
  }
}

private func importSyntax(
  imports: [(Visibility, String, debugBlame: String)],
  needsImplicitsUnsafeSPI: Bool,
  accessLevelOnImports: Bool,
  renderBlame: Bool
) -> [ImportDeclSyntax] {
  imports.map { visibility, moduleName, debugBlame in
    let attributes = AttributeListSyntax {
      if needsImplicitsUnsafeSPI, moduleName == ImplicitKeyword.importModuleName {
        "@_spi(Unsafe)"
      }
    }
    return ImportDeclSyntax(
      attributes: attributes,
      modifiers: .init(itemsBuilder: {
        if accessLevelOnImports, let visibility = visibility.render() {
          visibility
        }
      }),
      path: ImportPathComponentListSyntax {
        ImportPathComponentSyntax(name: .identifier(moduleName))
      },
      trailingTrivia: renderBlame ? .blockComment(" /* \(debugBlame) */") : nil
    )
  }
}

private func adaptionFunctionSyntax(
  decl: SupportFile.FuncSignature,
  additionalParamters: [SupportFile.ImplicitParameter]
) -> (namespace: String?, DeclSyntax) {
  let visibility = decl.visibility.render()
  let namespaceComponents = decl.signature.namespace.value
  let funcCallName =
    switch decl.signature.kind {
    case .callAsFunction: "self.callAsFunction"
    case .initializer: "self.init"
    case let .memberFunction(name: val): val
    case let .staticFunction(name: val):
      "\(namespaceComponents.last ?? "Self").\(val)"
    }

  let parameters: [FunctionParameterSyntax] = decl.parameters.map { name, type in
    FunctionParameterSyntax(
      firstName: "\(raw: name)",
      type: "\(raw: type)" as TypeSyntax
    )
  } + additionalParamters.compactMap { req in
    FunctionParameterSyntax(
      firstName: "\(raw: req.name)",
      type: "@autoclosure () -> \(raw: req.type)" as TypeSyntax
    )
  }

  let returnType = decl.returnType.map { "\(raw: $0)" as TypeSyntax }
  let funcSignature = FunctionSignatureSyntax(
    parameterClause: FunctionParameterClauseSyntax(parametersBuilder: {
      parameters
    }),
    returnClause: returnType.map { ReturnClauseSyntax(type: $0) }
  )
  let needsReturnKeyword = returnType != nil
  let fCall = FunctionCallExprSyntax(callee: "\(raw: funcCallName)" as ExprSyntax) {
    for param in decl.parameters {
      LabeledExprSyntax(label: param.name, expression: "\(raw: param.name)" as ExprSyntax)
    }
    LabeledExprSyntax(expression: "scope" as ExprSyntax)
  }
  let body = CodeBlockItemListSyntax(itemsBuilder: {
    VariableDeclSyntax(
      .let,
      name: "scope",
      initializer: InitializerClauseSyntax(value: "ImplicitScope()" as ExprSyntax)
    )
    DeferStmtSyntax {
      FunctionCallExprSyntax(callee: "scope.end" as ExprSyntax)
    }
    for param in additionalParamters {
      let attribute =
        switch param.key.kind {
        case .type: "@Implicit"
        case .keyPath: "@Implicit(\\.\(param.key.name))"
        }
      VariableDeclSyntax(
        attributes: [.attribute("\(raw: attribute)")],
        .var,
        name: "\(raw: param.name)_",
        type: TypeAnnotationSyntax(type: "\(raw: param.type)" as TypeSyntax),
        initializer: InitializerClauseSyntax(value: "\(raw: param.name)()" as ExprSyntax)
      )
    }
    if needsReturnKeyword {
      ReturnStmtSyntax(expression: fCall)
    } else {
      fCall
    }
  })
  let modifiers = DeclModifierListSyntax {
    if let visibility {
      visibility
    }
    if decl.isConvinience {
      .convenience
    }
    if decl.signature.kind.isStatic {
      .static
    }
  }

  let namespace = namespaceComponents.isEmpty ?
    nil : namespaceComponents.joined(separator: ".")

  switch decl.signature.kind {
  case .initializer:
    return (namespace, DeclSyntax(InitializerDeclSyntax(
      modifiers: modifiers,
      genericParameterClause: nil,
      signature: funcSignature,
      genericWhereClause: nil,
      body: CodeBlockSyntax(statements: body)
    )))
  case let .memberFunction(name):
    return (namespace, DeclSyntax(FunctionDeclSyntax(
      modifiers: modifiers,
      name: "\(raw: name)",
      genericParameterClause: nil,
      signature: funcSignature,
      genericWhereClause: nil,
      body: CodeBlockSyntax(statements: body)
    )))
  case .callAsFunction:
    return (namespace, DeclSyntax(FunctionDeclSyntax(
      modifiers: modifiers,
      name: "\(raw: "callAsFunction")",
      genericParameterClause: nil,
      signature: funcSignature,
      genericWhereClause: nil,
      body: CodeBlockSyntax(statements: body)
    )))
  case let .staticFunction(name: name):
    return (namespace, DeclSyntax(FunctionDeclSyntax(
      modifiers: modifiers,
      name: "\(raw: name)",
      genericParameterClause: nil,
      signature: funcSignature,
      genericWhereClause: nil,
      body: CodeBlockSyntax(statements: body)
    )))
  }
}

extension ImplicitKey {
  func getRawKeyValueSyntax() -> ExprSyntax {
    let type =
      switch kind {
      case .type: ExprSyntax("(\(raw: name)).self")
      case .keyPath: ExprSyntax("\\.\(raw: name)")
      }
    return "Implicits.getRawKey(\(type))"
  }
}

extension AttributeListSyntax.Element {
  static let inlinable = attribute(AttributeSyntax(TypeSyntax("inlinable")))
}

extension Visibility {
  func render() -> DeclModifierSyntax? {
    switch self {
    case .public: .public
    case .internal: .internal
    case .default: nil
    case .private: .private
    case .fileprivate: .fileprivate
    case .package: .package
    case .open: .open
    }
  }
}

extension DeclModifierSyntax {
  private static func keyword(_ keyword: Keyword) -> DeclModifierSyntax {
    DeclModifierSyntax(name: .keyword(keyword))
  }

  static let `public` = keyword(.public)
  static let `internal` = keyword(.internal)
  static let `private` = keyword(.private)
  static let `fileprivate` = keyword(.fileprivate)
  static let package = keyword(.package)
  static let open = keyword(.open)
  static let `static` = keyword(.static)
  static let convenience = keyword(.convenience)
}

extension MemberBlockSyntax {
  init(_ members: [MemberBlockItemSyntax]) {
    self.init(members: MemberBlockItemListSyntax(members))
  }
}

extension DeclSyntax {
  static func `extension`(
    _ extendedType: TypeSyntax, _ members: [MemberBlockItemSyntax]
  ) -> DeclSyntax {
    DeclSyntax(
      ExtensionDeclSyntax(
        extendedType: extendedType,
        memberBlock: MemberBlockSyntax(members)
      )
    )
  }
}

extension String {
  /// Returns this string with the first letter uppercased.
  ///
  /// If the string does not start with a letter, no change is made to it.
  fileprivate func withFirstLetterUppercased() -> String {
    if let firstLetter = self.first {
      firstLetter.uppercased() + self.dropFirst()
    } else {
      self
    }
  }
}
