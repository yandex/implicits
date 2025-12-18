// Copyright 2025 Yandex LLC. All rights reserved.

public struct SupportFile {
  public struct ImplicitParameter {
    public var name: String
    public var type: String
    public var key: ImplicitKey
  }

  public struct FuncSignature {
    public var signature: SymbolInfo<Void>
    public var visibility: Visibility
    public var hasScopeParameter: Bool
    /// Function paramters without scope parameter
    public var parameters: [(name: String, type: String)]
    public var isConvinience: Bool
    public var returnType: String?
  }

  public struct NamedImplicitsWrapper {
    public var wrapperName: String
    public var closureParamCount: Int
    public var requirements: [ImplicitKey]
  }

  var keys: [Sema.ImplicitKeyDecl]
  var imports: [(Visibility, String, debugBlame: String)]
  var ifFalseImports: [(Visibility, String, debugBlame: String)]
  var functions: [(FuncSignature, [ImplicitParameter])]
  var ifFalseFunctions: [(FuncSignature, [ImplicitParameter])]
  var bags: [(name: String, requirements: [ImplicitKey])]
  var namedImplicitsWrappers: [NamedImplicitsWrapper]
}

extension SupportFile {
  /// `true` if the support file contains any code that is required for the successful compilation
  /// of the module.
  ///
  /// For example, keys are required for the module to access the implicit values,
  /// but code for using functions with implicit values without implicits is not.
  public var containsRequiredCode: Bool {
    !keys.isEmpty
  }
}
