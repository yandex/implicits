// Copyright 2024 Yandex LLC. All rights reserved.

extension DiagnosticMessage {
  typealias Symbol = CallableSignature
  // Symbol resolution
  static func unresolvedSymbol(_ symbol: Symbol) -> Self {
    "Unresolved symbol '\(symbol)'"
  }

  static func ambiguousUseOf(_ symbol: Symbol) -> Self {
    "Ambiguous use of '\(symbol)'"
  }

  static let foundCandidate: Self = "Found this candidate"

  // Objective-C generic types
  static func objcGenericTypeKey(_ typeName: String) -> Self {
    "'\(typeName)' is an Objective-C type with type-erased generics; use a named key (keypath) instead of type-as-key"
  }
}
