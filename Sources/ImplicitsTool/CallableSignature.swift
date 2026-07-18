// Copyright 2024 Yandex LLC. All rights reserved.

/// Represents a namespace, where functions can be declared,
public struct SymbolNamespace: Equatable, Hashable, Sendable {
  public var value: [String]

  public init(_ value: [String]) {
    self.value = value
  }
}

public enum FunctionKind: Equatable, Hashable, Sendable {
  case memberFunction(name: String)
  case staticFunction(name: String)
  case initializer(optional: Bool)
  case callAsFunction

  public var isInitializer: Bool {
    if case .initializer = self {
      return true
    }
    return false
  }

  public var isStatic: Bool {
    if case .staticFunction = self {
      return true
    }
    return false
  }
}

/// Represents a type information.
///
/// Used when there is no access to syntax tree. Contains all necessary information for type
/// resolution, function calls resolution and other semantic checks.
/// Note, 'Failable' type is used to store diagnostic messages to be able to report them later.
public struct TypeInfo: Hashable, Sendable {
  public enum Failable<T: Hashable>: Hashable {
    case success(T)
    case failure(diagnostics: [DiagnosticMessage])

    public var value: T? {
      if case let .success(value) = self {
        return value
      }
      return nil
    }
  }

  public var namespace: Failable<SymbolNamespace>
  public var description: String
  public var strictDescription: Failable<String>

  public init(
    namespace: Failable<SymbolNamespace>,
    description: String,
    strictDescription: Failable<String>
  ) {
    self.namespace = namespace
    self.description = description
    self.strictDescription = strictDescription
  }
}

/// Represents a callable function signature, such as a function or initializer.
///
/// Note that free function is represented as member function with empty namespace.
public struct CallableSignature: Equatable, Hashable {
  public typealias Kind = FunctionKind

  public var kind: Kind
  public var namespace: SymbolNamespace
  public var params: [String]
  public var paramTypes: [String]
  public var returnType: TypeInfo?
  public var file: String

  public init(
    kind: Kind, namespace: SymbolNamespace,
    params: [String], paramTypes: [String],
    returnType: TypeInfo?,
    file: String
  ) {
    self.kind = kind
    self.namespace = namespace
    self.params = params
    self.paramTypes = paramTypes
    self.returnType = returnType
    self.file = file
  }
}

extension CallableSignature {
  public init(
    kind: Kind, namespace: [String],
    params: [String], paramTypes: [String],
    returnType: TypeInfo?,
    file: String
  ) {
    self.init(
      kind: kind, namespace: SymbolNamespace(namespace),
      params: params, paramTypes: paramTypes,
      returnType: returnType, file: file
    )
  }
}

extension CallableSignature: CustomStringConvertible {
  public var description: String {
    let (name, isStatic) =
      switch kind {
      case let .memberFunction(name):
        (name, false)
      case let .staticFunction(name):
        (name, true)
      case .initializer:
        ("init", false)
      case .callAsFunction:
        ("callAsFunction", false)
      }
    let namespacedName = (namespace.value + [name]).joined(separator: ".")
    let prefix = isStatic ? "static " : ""
    let params = params.map { "\($0):" }.joined()
    return "\(prefix)\(namespacedName)(\(params))"
  }
}

extension TypeInfo.Failable: Sendable where T: Sendable {}
