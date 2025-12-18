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
    static let attributeName = "_spi"
    static let annotationName = "Implicits"
  }

  static let importModuleName = "Implicits"
  static let keysEnumName = "ImplicitsKeys"
  static let annotationsConstructor = "_annotationsInit"
  static let anonClosureNamePrefix = "_anonClosure"

  enum ClosureWrapper {
    static let prefix = "with"
    static let suffix = "Implicits"
  }
}
