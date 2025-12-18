// Copyright 2023 Yandex LLC. All rights reserved.

/// Namespace for syntax tree model and builder.
/// Common terms:
/// - Statement - a generic definition of a syntax expression presented in `TopLevelStatement`,
/// `MemberBlockStatement` and `CodeBlockStatement`
/// - Entity - syntax element paired with corresponding statement
/// - Type - `class`, `struct` or `enum`
public enum SyntaxTree<Syntax> {
  /// Represents an entity within the syntax tree. This generic structure
  /// is used to associate a specific syntax element with its corresponding
  /// Syntax, which can be used for error reporting.
  public struct Entity<T> {
    public var value: T
    public var syntax: Syntax
  }

  // MARK: Statements by syntax level

  /// Enum defining kinds of top-level declarations in a Swift file,
  /// such as imports, type declarations (class, struct, enum), extensions,
  /// function declarations, variable declarations and unknown member blocks.
  public enum TopLevelStatement {
    case `import`(ImportDecl)
    case declaration(Declaration)
    case `extension`(Extension)
    case ifConfig(IfConfig)
  }

  /// Enum defining kinds of declarations that can be part of a type's
  /// member definitions, including type declarations, variable declarations,
  /// function declarations, initializer declarations, and other nested member blocks.
  public enum MemberBlockStatement {
    case declaration(Declaration)
    case initializer(InitializerDecl)
  }

  /// Enum defining kinds of entities that can exist within a code block,
  /// such as type declarations, variable declarations, function declarations,
  /// expressions, and statements.
  public enum CodeBlockStatement {
    case decl(Declaration)
    case stmt(Statement)
    case expr(Expression)
  }

  /// Statements within a code block.
  public enum Statement {
    case `defer`(DeferStmt)
    case `do`(DoStmt)
    case other(CodeBlockItemList)
  }

  /// Definition of declaration statements, such as types (`class`,
  /// `struct` and `enum`), variables (`let` and `var`) and functions (`func`)
  public enum Declaration {
    case type(TypeDecl)
    case `protocol`(ProtocolDecl)
    case function(FunctionDecl)
    case variable(VariableDecl)
    case memberBlock(MemberBlock)
  }

  // MARK: Entities by statement levels

  public typealias TopLevelEntity = Entity<TopLevelStatement>
  public typealias MemberBlockEntity = Entity<MemberBlockStatement>
  public typealias CodeBlockEntity = Entity<CodeBlockStatement>

  // MARK: Definitions

  public typealias Affiliation = SyntaxTreeBuildingBlocks.Affiliation
  public typealias DeclModifier = SyntaxTreeBuildingBlocks.DeclModifier

  /// Represents import statement
  /// `import Foo`
  public struct ImportDecl {
    public var attributes: Attributes
    public var visibility: Visibility
    public var type: String?
    public var moduleName: String
    public var path: [String]
  }

  public struct IfConfig {
    public enum Condition {
      case `if`(Syntax)
      case elif(Syntax)
      case `else`
    }

    public struct Clause {
      public var condition: Condition
      public var body: [TopLevelEntity]
    }

    public var clauses: [Clause]
  }

  /// Represents class like declarations of `class`, `struct` and `enum`
  /// ```
  /// class Foo { ... }
  public struct TypeDecl {
    public typealias Kind = SyntaxTreeBuildingBlocks.TypeDeclKind
    public var name: String
    public var kind: Kind
    public var attributes: Attributes
    public var visibility: Visibility
    public var modifiers: [DeclModifier]
    public var members: MemberBlock
  }

  /// Represents extension declaration
  /// ```
  /// extension <extendedType> { ... }
  public struct Extension {
    public var extendedType: TypeModel
    public var attributes: Attributes
    public var visibility: Visibility
    public var members: MemberBlock
  }

  public struct ProtocolDecl {
    public var name: String
    public var attributes: Attributes
    public var visibility: Visibility
    public var members: MemberBlock
  }

  /// Represents body of all declarations with child scopes such as `class`, `struct`, `enum` and
  /// `extension`
  public typealias MemberBlock = [MemberBlockEntity]

  /// Represents function declaration
  /// ```
  /// func foo(arg: Foo) { ... }
  public struct FunctionDecl {
    public var name: String
    public var attributes: Attributes
    public var visibility: Visibility
    public var affiliation: Affiliation
    public var modifiers: [DeclModifier]
    public var parameters: Parameters
    public var returnType: Entity<TypeModel>?
    public var body: CodeBlockItemList?
  }

  /// Represents the abstract expression.
  /// This enum is used to model the various forms of expressions
  /// that can appear in code.
  public enum Expression {
    case functionCall(FunctionCall)
    case closure(ClosureExpr)
    case macroExpansion(String)
    case declRef(String, parameters: [String]?)
    indirect case memberAccessor(base: Expression, String)
    case other([CodeBlockEntity])
  }

  /// Represents initializer declaration
  /// ```
  /// init(arg: Foo) { ... }
  public struct InitializerDecl {
    public var attributes: Attributes
    public var visibility: Visibility
    public var modifiers: [DeclModifier]
    public var optional: Bool
    public var parameters: Parameters
    public var body: CodeBlockItemList?
  }

  public struct ClosureParameter {
    public var name: Entity<Parameter.Name>
    public var type: TypeModel?
    public var hasDefaultValue: Bool
  }

  /// Represents closure syntax expression in the form of a variable value,
  /// argument or a free standing function call
  /// ```
  /// let v = { ... }
  public struct ClosureExpr {
    public struct CaptureDescription {
      public var name: String?
      public var expression: Entity<Expression>?
    }

    public typealias Capture = Entity<CaptureDescription>
    public typealias Parameters = [ClosureParameter]

    public var captures: [Capture]?
    public var parameters: Parameters?
    public var body: [CodeBlockEntity]
  }

  /// Represents defer statement
  /// ```
  /// defer { ... }
  public typealias DeferStmt = [CodeBlockEntity]

  /// Represents do-catch statement
  /// ```
  /// do { ... } catch { ... }
  /// ```
  public struct DoStmt {
    public var body: [CodeBlockEntity]
    public var catchBodies: [[CodeBlockEntity]]
  }

  /// Represents the content of a code block
  /// ```
  /// { ... }
  public typealias CodeBlockItemList = [CodeBlockEntity]

  /// Represents an access block for a variable declaration
  /// ```
  /// { get { ... } set { ... } }
  public typealias AccessorBlock = SyntaxTreeBuildingBlocks.AccessorBlock

  public struct VariableDecl {
    /// Represents a binding in a variable declaration that looks
    ///   like this `a: Int = 1`.
    /// It's possible to have several bindings within one declaration
    ///   like here `var a: Int = 1, b: Double = 2`
    ///   so that's why a variable declaration has an array of bindings
    public struct Binding {
      public var name: Pattern
      public var type: TypeModel?
      public var initializer: Entity<Expression>?
      public var syntax: Syntax
      public var accessorBlock: AccessorBlock?
    }

    public enum Pattern {
      case wildcard, identifier(String), tuple([Pattern]), unsupported
    }

    public var constant: Bool
    public var attributes: Attributes
    public var visibility: Visibility
    public var affiliation: Affiliation
    public var bindings: [Binding]
  }

  /// Represents function call statement
  /// ```
  /// obj.foo(arg1, arg2, ...)
  public struct FunctionCall {
    public var base: TypeModel?
    public var name: Entity<TypeModel>?
    public var arguments: [Argument]
    public var trailingClosure: Entity<ClosureExpr>?
    public var baseExprs: [CodeBlockEntity]
  }

  /// This enum is used to model the various forms of types
  ///   that can appear in code,  such as simple identifiers,
  ///   generics, optionals, tuples, and more.
  public indirect enum TypeModel {
    public typealias MetatypeSpecifier =
      SyntaxTreeBuildingBlocks.TypeModelMetatypeSpecifier
    public typealias SomeOrAny = SyntaxTreeBuildingBlocks.TypeModelSomeOrAny

    public struct TupleTypeElement {
      public var name: (String, second: String?)?
      public var type: TypeModel
    }

    public struct EffectSpecifiers {
      public enum Throws {
        case `throws`, `rethrows`
      }

      public var isAsync: Bool
      public var `throws`: (Throws, type: TypeModel?)?
    }

    /// Just a plain string identifier
    case identifier(String)
    /// `T<U>`
    case generic(base: TypeModel, args: [TypeModel])
    /// `T?`
    case optional(TypeModel)
    /// `T!`
    case unwrappedOptional(TypeModel)
    /// `(T, U)`
    case tuple([TupleTypeElement])
    /// `T.U`
    case member([TypeModel])
    /// `[T]`
    case array(TypeModel)
    /// `inout @Foo T`
    case attributed(specifiers: [String], [Attribute], TypeModel)
    /// `protocol P: class { ... }`
    case classRestriction
    /// `T & U`
    case composition([TypeModel])
    /// `[T: U]`
    case dictionary(key: TypeModel, value: TypeModel)
    /// `(T) -> U`
    case function(
      parameters: [TupleTypeElement],
      effects: EffectSpecifiers?,
      returnType: TypeModel
    )
    /// `T.Type`
    case metatype(base: TypeModel, specifier: MetatypeSpecifier)
    /// `let a: = 5`, `a` binding has type `MissingTypeSyntax`
    case missing
    /// No Idea what this is
    ///
    /// [Tests on github](https://github.com/swiftlang/swift-syntax/blob/main/Tests/SwiftParserTest/TypeTests.swift#L170)
    ///
    /// `func f2() -> <T: SignedInteger, U: SignedInteger> Int { ... }`
    case namedOpaqueReturn(base: TypeModel, generics: [GenericParameter])
    /// `each T`
    case packElement(TypeModel)
    /// `repeat T`
    case packExpansion(TypeModel)
    /// `some T`
    case someOrAny(TypeModel, SomeOrAny)
    /// `~T`
    case suppressed(TypeModel)
  }

  /// Represents attribute of a declaration
  /// ```
  /// @Implicit() var b: Foo
  public struct Attribute {
    public var name: TypeModel
    public var arguments: [Argument]?
  }

  public typealias Attributes = [Attribute]

  /// Parameter defines an argument in place of declaration.
  /// ```
  /// func foo(a: Int, b: String)
  public struct Parameter {
    public typealias Name = SyntaxTreeBuildingBlocks.ParameterName
    public var firstName: Entity<Name>
    public var secondName: Entity<Name>?
    public var type: Entity<TypeModel>
    public var hasDefaultValue: Bool
  }

  /// Generic parameter defines a type parameter in a generic declaration.
  /// ```
  /// // 'T: Equatable' is a generic parameter
  /// func foo<T: Equatable>(a: T)
  /// ```
  public struct GenericParameter {
    public typealias Specifier = SyntaxTreeBuildingBlocks.GenericParameterSpecifier
    public var attributes: Attributes
    public var name: String
    public var specifier: Specifier?
    public var inheritedType: TypeModel?
  }

  public typealias Parameters = [Parameter]

  /// Argument defines an argument on call site.
  /// ```
  /// foo(a: 5, b: "hello")
  public struct Argument {
    public enum Value {
      /// `KeyPath` representation (each component is a `String`)
      case keyed([String])
      /// Type expression that ends with `.self`
      case explicitType(TypeModel)
      /// Any other type expression
      case reference(TypeModel)
      case other([CodeBlockEntity])
    }

    /// Differs from `Parameter.Name` because on call site the name cannot be a wildcard token (`_`)
    public var name: Entity<String>?
    public var value: Entity<Value>
  }

  typealias Arguments = [Argument]
}

/// Contains types that don't depend on `Syntax` generic parameter.
public enum SyntaxTreeBuildingBlocks {
  /// Represents type members affiliation
  /// ```
  /// class A {
  ///   // static
  ///   static var i: Int
  ///   // class
  ///   class func f()
  ///   // instance
  ///   func g()
  /// }
  /// ```
  public enum Affiliation {
    case `static`, `class`, instance
  }

  /// Declaration modifiers, that do not belong to obvious group, but still needed for analysis.
  public enum DeclModifier: Equatable {
    case override, open, final, convenience
  }

  public enum TypeDeclKind {
    case `class`, `struct`, `enum`, `actor`
  }

  public enum ParameterName {
    /// Wildcard is `_`
    case wildcard
    case literal(String)

    var isWildcard: Bool {
      switch self {
      case .wildcard: true
      case .literal: false
      }
    }

    var literal: String? {
      switch self {
      case .wildcard: nil
      case let .literal(name): name
      }
    }
  }

  public enum TypeModelMetatypeSpecifier {
    case type, `protocol`
  }

  public enum TypeModelSomeOrAny {
    case some, any
  }

  public enum AccessorBlock {
    public enum Kind: Equatable {
      case getter, setter, other(String)
    }

    case getter
    case multiple([Kind])
  }

  public enum GenericParameterSpecifier {
    case each, `let`
  }
}

extension SyntaxTree.MemberBlockStatement {
  var isInitializer: Bool {
    switch self {
    case .initializer: true
    case .declaration: false
    }
  }
}

extension SyntaxTreeBuildingBlocks.AccessorBlock {
  var isCalculatable: Bool {
    switch self {
    case .getter: true
    case let .multiple(accessors):
      accessors.contains { $0 == .getter }
    }
  }
}

extension SyntaxTree.Parameter {
  /// The parameter's name used for reference within the function body.
  var bodyName: String? {
    switch (firstName.value, secondName?.value) {
    case let (_, .literal(value)), let (.literal(value), nil):
      value
    case (_, .wildcard), (.wildcard, nil):
      nil
    }
  }
}

// MARK: - mapSyntax

fileprivate typealias ST<S> = SyntaxTree<S>

extension SyntaxTree.Entity {
  fileprivate func map<NewSyntax, NewValue>(
    _ syntaxTransform: (Syntax) -> NewSyntax,
    _ valueTransform: (T) -> ((Syntax) -> NewSyntax) -> NewValue
  ) -> SyntaxTree<NewSyntax>.Entity<NewValue> {
    .init(
      value: valueTransform(value)(syntaxTransform),
      syntax: syntaxTransform(syntax)
    )
  }

  fileprivate func mapSyntax<NewSyntax>(
    _ t: (Syntax) -> NewSyntax
  ) -> SyntaxTree<NewSyntax>.Entity<T> {
    .init(value: value, syntax: t(syntax))
  }

  func mapSyntax<NewSyntax>(
    _ t: (Syntax) -> NewSyntax
  ) -> SyntaxTree<NewSyntax>.TopLevelEntity
    where T == SyntaxTree.TopLevelStatement {
    map(t, ST.TopLevelStatement.mapSyntax)
  }

  func mapSyntax<NewSyntax>(
    _ t: (Syntax) -> NewSyntax
  ) -> SyntaxTree<NewSyntax>.Entity<SyntaxTree<NewSyntax>.TypeModel>
    where T == SyntaxTree.TypeModel {
    map(t, ST.TypeModel.mapSyntax)
  }

  func mapSyntax<NewSyntax>(
    _ t: (Syntax) -> NewSyntax
  ) -> SyntaxTree<NewSyntax>.Entity<
    SyntaxTree<NewSyntax>.Expression
  > where T == SyntaxTree.Expression {
    map(t, ST.Expression.mapSyntax)
  }
}

extension SyntaxTree.TopLevelStatement {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.TopLevelStatement {
    switch self {
    case let .import(v):
      .import(v.mapSyntax(t))
    case let .declaration(v):
      .declaration(v.mapSyntax(t))
    case let .extension(v):
      .extension(v.mapSyntax(t))
    case let .ifConfig(v):
      .ifConfig(v.mapSyntax(t))
    }
  }
}

extension SyntaxTree.ImportDecl {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.ImportDecl {
    .init(
      attributes: attributes.map { $0.mapSyntax(t) },
      visibility: visibility,
      type: type,
      moduleName: moduleName,
      path: path
    )
  }
}

extension SyntaxTree.IfConfig {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.IfConfig {
    .init(
      clauses: clauses.map { $0.mapSyntax(t) }
    )
  }
}

extension SyntaxTree.IfConfig.Clause {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.IfConfig.Clause {
    .init(
      condition: condition.mapSyntax(t),
      body: body.map { $0.mapSyntax(t) }
    )
  }
}

extension SyntaxTree.IfConfig.Condition {
  func mapSyntax<S>(
    _ t: (Syntax) -> S
  ) -> SyntaxTree<S>.IfConfig.Condition {
    switch self {
    case let .if(v): .if(t(v))
    case let .elif(v): .elif(t(v))
    case .else: .else
    }
  }
}

extension SyntaxTree.MemberBlockStatement {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.MemberBlockStatement {
    switch self {
    case let .declaration(v):
      .declaration(v.mapSyntax(t))
    case let .initializer(v):
      .initializer(v.mapSyntax(t))
    }
  }
}

extension SyntaxTree.CodeBlockStatement {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.CodeBlockStatement {
    switch self {
    case let .decl(v):
      .decl(v.mapSyntax(t))
    case let .stmt(v):
      .stmt(v.mapSyntax(t))
    case let .expr(e):
      .expr(e.mapSyntax(t))
    }
  }
}

extension SyntaxTree.Statement {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.Statement {
    switch self {
    case let .defer(v):
      .defer(v.map { $0.map(t, ST.CodeBlockStatement.mapSyntax) })
    case let .do(v):
      .do(v.mapSyntax(t))
    case let .other(v):
      .other(v.map { $0.map(t, ST.CodeBlockStatement.mapSyntax) })
    }
  }
}

extension SyntaxTree.DoStmt {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.DoStmt {
    .init(
      body: body.map { $0.map(t, ST.CodeBlockStatement.mapSyntax) },
      catchBodies: catchBodies.map { $0.map { $0.map(t, ST.CodeBlockStatement.mapSyntax) } }
    )
  }
}

extension SyntaxTree.Declaration {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.Declaration {
    switch self {
    case let .type(v):
      .type(v.mapSyntax(t))
    case let .protocol(v):
      .protocol(v.mapSyntax(t))
    case let .function(v):
      .function(v.mapSyntax(t))
    case let .variable(v):
      .variable(v.mapSyntax(t))
    case let .memberBlock(v):
      .memberBlock(v.map { $0.map(t, ST.MemberBlockStatement.mapSyntax) })
    }
  }
}

extension SyntaxTree.TypeDecl {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.TypeDecl {
    .init(
      name: name,
      kind: kind,
      attributes: attributes.map { $0.mapSyntax(t) },
      visibility: visibility,
      modifiers: modifiers,
      members: members.map { $0.map(t, ST.MemberBlockStatement.mapSyntax) }
    )
  }
}

extension SyntaxTree.Extension {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.Extension {
    .init(
      extendedType: extendedType.mapSyntax(t),
      attributes: attributes.map { $0.mapSyntax(t) },
      visibility: visibility,
      members: members.map { $0.map(t, ST.MemberBlockStatement.mapSyntax) }
    )
  }
}

extension SyntaxTree.ProtocolDecl {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.ProtocolDecl {
    .init(
      name: name,
      attributes: attributes.map { $0.mapSyntax(t) },
      visibility: visibility,
      members: members.map { $0.map(t, ST.MemberBlockStatement.mapSyntax) }
    )
  }
}

extension SyntaxTree.FunctionDecl {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.FunctionDecl {
    .init(
      name: name,
      attributes: attributes.map { $0.mapSyntax(t) },
      visibility: visibility,
      affiliation: affiliation,
      modifiers: modifiers,
      parameters: parameters.map { $0.mapSyntax(t) },
      returnType: returnType?.mapSyntax(t),
      body: body?.map { $0.map(t, ST.CodeBlockStatement.mapSyntax) }
    )
  }
}

extension SyntaxTree.InitializerDecl {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.InitializerDecl {
    .init(
      attributes: attributes.map { $0.mapSyntax(t) },
      visibility: visibility,
      modifiers: modifiers,
      optional: optional,
      parameters: parameters.map { $0.mapSyntax(t) },
      body: body?.map { $0.map(t, ST.CodeBlockStatement.mapSyntax) }
    )
  }
}

extension SyntaxTree.ClosureParameter {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.ClosureParameter {
    .init(
      name: name.mapSyntax(t),
      type: type?.mapSyntax(t),
      hasDefaultValue: hasDefaultValue
    )
  }
}

extension SyntaxTree.ClosureExpr.CaptureDescription {
  func mapSyntax<S>(
    _ t: (Syntax) -> S
  ) -> SyntaxTree<S>.ClosureExpr.CaptureDescription {
    .init(
      name: name,
      expression: expression?.mapSyntax(t)
    )
  }
}

extension SyntaxTree.Expression {
  func mapSyntax<S>(
    _ t: (Syntax) -> S
  ) -> SyntaxTree<S>.Expression {
    switch self {
    case let .functionCall(v):
      .functionCall(v.mapSyntax(t))
    case let .closure(v):
      .closure(v.mapSyntax(t))
    case let .macroExpansion(v):
      .macroExpansion(v)
    case let .declRef(v, parameters: ps):
      .declRef(v, parameters: ps)
    case let .memberAccessor(base, v):
      .memberAccessor(base: base.mapSyntax(t), v)
    case let .other(v):
      .other(v.map { $0.map(t, ST.CodeBlockStatement.mapSyntax) })
    }
  }
}

extension SyntaxTree.ClosureExpr {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.ClosureExpr {
    .init(
      captures: captures?.map { $0.map(t, ST.ClosureExpr.CaptureDescription.mapSyntax) },
      parameters: parameters?.map { $0.mapSyntax(t) },
      body: body.map { $0.map(t, ST.CodeBlockStatement.mapSyntax) }
    )
  }
}

extension SyntaxTree.VariableDecl.Pattern {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.VariableDecl.Pattern {
    switch self {
    case .wildcard:
      .wildcard
    case let .identifier(v):
      .identifier(v)
    case let .tuple(v):
      .tuple(v.map { $0.mapSyntax(t) })
    case .unsupported:
      .unsupported
    }
  }
}

extension SyntaxTree.VariableDecl {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.VariableDecl {
    .init(
      constant: constant,
      attributes: attributes.map { $0.mapSyntax(t) },
      visibility: visibility,
      affiliation: affiliation,
      bindings: bindings.map { b in
        .init(
          name: {
            switch b.name {
            case .wildcard:
              .wildcard
            case let .identifier(v):
              .identifier(v)
            case let .tuple(v):
              .tuple(v.map { $0.mapSyntax(t) })
            case .unsupported:
              .unsupported
            }
          }(),
          type: b.type?.mapSyntax(t),
          initializer: b.initializer?.mapSyntax(t),
          syntax: t(b.syntax),
          accessorBlock: b.accessorBlock
        )
      }
    )
  }
}

extension SyntaxTree.FunctionCall {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.FunctionCall {
    .init(
      base: base?.mapSyntax(t),
      name: name.map { $0.map(t, ST.TypeModel.mapSyntax) },
      arguments: arguments.map { $0.mapSyntax(t) },
      trailingClosure: trailingClosure?.map(t, ST.ClosureExpr.mapSyntax),
      baseExprs: baseExprs.map { $0.map(t, ST.CodeBlockStatement.mapSyntax) }
    )
  }
}

extension SyntaxTree.TypeModel.EffectSpecifiers.Throws {
  func mapSyntax<S>(
    _: (Syntax) -> S
  ) -> SyntaxTree<S>.TypeModel.EffectSpecifiers.Throws {
    switch self {
    case .throws: .throws
    case .rethrows: .rethrows
    }
  }
}

extension SyntaxTree.TypeModel.EffectSpecifiers {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.TypeModel.EffectSpecifiers {
    .init(
      isAsync: isAsync,
      throws: `throws`.map { ($0.0.mapSyntax(t), $0.1?.mapSyntax(t)) }
    )
  }
}

extension SyntaxTree.TypeModel {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.TypeModel {
    switch self {
    case let .identifier(v):
      .identifier(v)
    case let .generic(base, args):
      .generic(base: base.mapSyntax(t), args: args.map { $0.mapSyntax(t) })
    case let .optional(v):
      .optional(v.mapSyntax(t))
    case let .unwrappedOptional(v):
      .unwrappedOptional(v.mapSyntax(t))
    case let .tuple(v):
      .tuple(v.map { .init(name: $0.name, type: $0.type.mapSyntax(t)) })
    case let .member(v):
      .member(v.map { $0.mapSyntax(t) })
    case let .array(v):
      .array(v.mapSyntax(t))
    case let .attributed(specifiers, attributes, type):
      .attributed(
        specifiers: specifiers,
        attributes.map { $0.mapSyntax(t) },
        type.mapSyntax(t)
      )
    case .classRestriction:
      .classRestriction
    case let .composition(v):
      .composition(v.map { $0.mapSyntax(t) })
    case let .dictionary(key, value):
      .dictionary(
        key: key.mapSyntax(t),
        value: value.mapSyntax(t)
      )
    case let .function(parameters, effects, returnType):
      .function(
        parameters: parameters.map { .init(name: $0.name, type: $0.type.mapSyntax(t)) },
        effects: effects.map { $0.mapSyntax(t) },
        returnType: returnType.mapSyntax(t)
      )
    case let .metatype(base, specifier):
      .metatype(base: base.mapSyntax(t), specifier: specifier)
    case .missing:
      .missing
    case let .namedOpaqueReturn(base, generics):
      .namedOpaqueReturn(
        base: base.mapSyntax(t),
        generics: generics.map { $0.mapSyntax(t) }
      )
    case let .packElement(v):
      .packElement(v.mapSyntax(t))
    case let .packExpansion(v):
      .packExpansion(v.mapSyntax(t))
    case let .someOrAny(v, s):
      .someOrAny(v.mapSyntax(t), s)
    case let .suppressed(v):
      .suppressed(v.mapSyntax(t))
    }
  }
}

extension SyntaxTree.Attribute {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.Attribute {
    .init(
      name: name.mapSyntax(t),
      arguments: arguments.map { $0.map { $0.mapSyntax(t) } }
    )
  }
}

extension SyntaxTree.Parameter {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.Parameter {
    .init(
      firstName: firstName.mapSyntax(t),
      secondName: secondName?.mapSyntax(t),
      type: type.mapSyntax(t),
      hasDefaultValue: hasDefaultValue
    )
  }
}

extension SyntaxTree.GenericParameter {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.GenericParameter {
    .init(
      attributes: attributes.map { $0.mapSyntax(t) },
      name: name,
      specifier: specifier,
      inheritedType: inheritedType.map { $0.mapSyntax(t) }
    )
  }
}

extension SyntaxTree.Argument.Value {
  func mapSyntax<S>(
    _ t: (Syntax) -> S
  ) -> SyntaxTree<S>.Argument.Value {
    switch self {
    case let .keyed(v):
      .keyed(v)
    case let .explicitType(v):
      .explicitType(v.mapSyntax(t))
    case let .reference(v):
      .reference(v.mapSyntax(t))
    case let .other(v):
      .other(v.map { $0.map(t, ST.CodeBlockStatement.mapSyntax) })
    }
  }
}

extension SyntaxTree.Argument {
  func mapSyntax<S>(_ t: (Syntax) -> S) -> SyntaxTree<S>.Argument {
    .init(
      name: name?.mapSyntax(t),
      value: value.map(t, SyntaxTree.Argument.Value.mapSyntax)
    )
  }
}
