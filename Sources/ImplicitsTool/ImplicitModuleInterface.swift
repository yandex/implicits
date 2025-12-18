// Copyright 2024 Yandex LLC. All rights reserved.

public struct ImplicitModuleInterface: Equatable, Sendable {
  public typealias ExternalSymbol = SymbolInfo<Diagnostic.Location>

  public struct Symbol: Equatable, Sendable {
    public var info: ExternalSymbol
    public var requirements: [ImplicitKey]?

    public init(info: ExternalSymbol, requirements: [ImplicitKey]?) {
      self.info = info
      self.requirements = requirements
    }
  }

  public struct DefinedKey: Equatable, Sendable {
    public var name: String
    public var type: String

    public init(name: String, type: String) {
      self.name = name
      self.type = type
    }
  }

  /// The name of the module
  public var module: String
  /// Externally visible symbols, used for namespace and type inference, and implicits resolution.
  public var symbols: [Symbol]
  /// Symbols that are only visible when `@testable import` is used
  public var testableSymbols: [Symbol]
  /// KeyPath keys defined in the module, used for type inference and imports
  public var definedKeypathKeys: [DefinedKey]
  /// Modules reexported by this module
  public var reexportedModules: [String]

  public init(
    module: String, symbols: [Symbol],
    testableSymbols: [Symbol],
    definedKeypathKeys: [DefinedKey],
    reexportedModules: [String]
  ) {
    self.module = module
    self.symbols = symbols
    self.testableSymbols = testableSymbols
    self.definedKeypathKeys = definedKeypathKeys
    self.reexportedModules = reexportedModules
  }
}

extension ImplicitModuleInterface: Serializable {
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    try self.init(
      module: .init(from: &stream),
      symbols: .init(from: &stream),
      testableSymbols: .init(from: &stream),
      definedKeypathKeys: .init(from: &stream),
      reexportedModules: .init(from: &stream)
    )
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try module.serialize(to: &buffer)
    try symbols.serialize(to: &buffer)
    try testableSymbols.serialize(to: &buffer)
    try definedKeypathKeys.serialize(to: &buffer)
    try reexportedModules.serialize(to: &buffer)
  }
}

extension ImplicitModuleInterface.Symbol: Serializable {
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    try self.init(info: .init(from: &stream), requirements: .init(from: &stream))
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try info.serialize(to: &buffer)
    try requirements.serialize(to: &buffer)
  }
}

extension ImplicitModuleInterface.DefinedKey: Serializable {
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    try self.init(name: String(from: &stream), type: String(from: &stream))
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try name.serialize(to: &buffer)
    try type.serialize(to: &buffer)
  }
}

extension DiagnosticMessage: Serializable {
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    try self.init(value: .init(from: &stream))
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try value.serialize(to: &buffer)
  }
}

extension TypeInfo.Failable: Serializable where T: Serializable {
  private enum Plain: UInt8, Serializable { case success, failure }
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    switch try Plain(from: &stream) {
    case .success:
      self = try .success(T(from: &stream))
    case .failure:
      self = try .failure(diagnostics: [DiagnosticMessage](from: &stream))
    }
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try plain.serialize(to: &buffer)
    switch self {
    case let .success(value):
      try value.serialize(to: &buffer)
    case let .failure(diagnostics):
      try diagnostics.serialize(to: &buffer)
    }
  }

  private var plain: Plain {
    switch self {
    case .success: .success
    case .failure: .failure
    }
  }
}

extension TypeInfo: Serializable {
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    try self.init(
      namespace: .init(from: &stream),
      description: .init(from: &stream),
      strictDescription: .init(from: &stream)
    )
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try namespace.serialize(to: &buffer)
    try description.serialize(to: &buffer)
    try strictDescription.serialize(to: &buffer)
  }
}

extension ImplicitModuleInterface.ExternalSymbol: Serializable {
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    try self.init(
      kind: CallableSignature.Kind(from: &stream),
      parameters: [Parameter](from: &stream),
      namespace: Sema.Namespace(from: &stream),
      returnType: .init(from: &stream),
      syntax: Diagnostic.Location(from: &stream),
      file: String(from: &stream)
    )
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try kind.serialize(to: &buffer)
    try parameters.serialize(to: &buffer)
    try namespace.serialize(to: &buffer)
    try returnType.serialize(to: &buffer)
    try syntax.serialize(to: &buffer)
    try file.serialize(to: &buffer)
  }
}

extension CallableSignature.Kind: Serializable {
  fileprivate enum PlainKind: UInt8, Serializable {
    case callAsFunction, initializer, memberFunction, staticFunction

    init(kind: CallableSignature.Kind) {
      self =
        switch kind {
        case .callAsFunction: .callAsFunction
        case .initializer: .initializer
        case .memberFunction: .memberFunction
        case .staticFunction: .staticFunction
        }
    }
  }

  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    let kind = try PlainKind(from: &stream)
    switch kind {
    case .callAsFunction: self = .callAsFunction
    case .initializer:
      self = try .initializer(optional: .init(from: &stream))
    case .memberFunction:
      self = try .memberFunction(name: String(from: &stream))
    case .staticFunction:
      self = try .staticFunction(name: String(from: &stream))
    }
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try PlainKind(kind: self).serialize(to: &buffer)
    switch self {
    case .callAsFunction: break
    case let .initializer(optional: opt):
      try opt.serialize(to: &buffer)
    case let .memberFunction(name):
      try name.serialize(to: &buffer)
    case let .staticFunction(name):
      try name.serialize(to: &buffer)
    }
  }
}

extension ImplicitModuleInterface.ExternalSymbol.Parameter: Serializable {
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    name = try String(from: &stream)
    type = try String(from: &stream)
    hasDefaultValue = try Bool(from: &stream)
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try name.serialize(to: &buffer)
    try type.serialize(to: &buffer)
    try hasDefaultValue.serialize(to: &buffer)
  }
}

extension ImplicitModuleInterface.ExternalSymbol.Namespace: Serializable {
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    value = try [String](from: &stream)
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try value.serialize(to: &buffer)
  }
}

extension Diagnostic.Location: Serializable {
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    file = try String(from: &stream)
    line = try Int(Int32(from: &stream))
    column = try Int(Int32(from: &stream))
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try file.serialize(to: &buffer)
    try Int32(line).serialize(to: &buffer)
    try Int32(column).serialize(to: &buffer)
  }
}

extension ImplicitKey: Serializable {
  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    kind = try Kind(from: &stream)
    name = try String(from: &stream)
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try kind.serialize(to: &buffer)
    try name.serialize(to: &buffer)
  }
}

extension ImplicitKey.Kind: Serializable {
  private enum PlainKind: UInt8, Serializable {
    case type, keyPath
    init(_ other: ImplicitKey.Kind) {
      switch other {
      case .type: self = .type
      case .keyPath: self = .keyPath
      }
    }

    var value: ImplicitKey.Kind {
      switch self {
      case .type: .type
      case .keyPath: .keyPath
      }
    }
  }

  public init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    self = try PlainKind(from: &stream).value
  }

  public func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try PlainKind(self).serialize(to: &buffer)
  }
}
