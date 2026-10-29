// Copyright 2023 Yandex LLC. All rights reserved.

enum ImplicitKeyword {
  enum Scope {
    static let className = "ImplicitScope"
    static let variableName = "scope"
    static let nestedFuncName = "nested"
    static let endFuncName = "end"
    static let bagParameterName = "with"
  }

  enum Bag {
    static let className = "Implicits"
    static let variableName = "implicits"
  }

  enum Annotation {
    static let implicit = "Implicit"
    static let implicitable = "Implicitable"
  }

  enum Map {
    static let functionName = "map"
    static let argName = "to"
  }

  enum SPI {
    static let annotationName = "Implicits"
  }

  /// Built-in Swift attributes the analyzer recognizes but Implicits doesn't declare.
  enum SwiftAttribute {
    static let testable = "testable"
    static let exported = "_exported"
    static let spi = "_spi"
    static let mainActor = "MainActor"
    static let sendable = "Sendable"
  }

  static let importModuleName = "Implicits"
  static let keysEnumName = "ImplicitsKeys"
  static let annotationsConstructor = "_annotationsInit"
  static let anonClosureNamePrefix = "_anonClosure"

  enum ClosureWrapper {
    static let prefix = "with"
    static let suffix = "Implicits"
  }

  enum Macro {
    static let withImplicits = "withImplicits"
    static let implicits = "implicits"
    static let isolationArgName = "isolation"
    static let mainActorIsolation = "mainActor"
  }
}
