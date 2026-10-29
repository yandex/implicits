// Copyright 2023 Yandex LLC. All rights reserved.

extension SyntaxTree.Attribute {
  var simpleIdentifier: String? {
    name.simpleIdentifier
  }

  var isImplicit: Bool {
    simpleIdentifier == ImplicitKeyword.Annotation.implicit
  }

  var isImplicitSpi: Bool {
    guard
      simpleIdentifier == ImplicitKeyword.SwiftAttribute.spi,
      let args = arguments,
      let arg = args.first, args.count == 1
    else {
      return false
    }
    return arg.value.value.simpleIdentifier() == ImplicitKeyword.SPI.annotationName
  }

  var isTestable: Bool {
    self.simpleIdentifier == ImplicitKeyword.SwiftAttribute.testable && self.arguments == nil
  }

  var isExported: Bool {
    self.simpleIdentifier == ImplicitKeyword.SwiftAttribute.exported && self.arguments == nil
  }

  var importAttribute: SupportFile.ImportAttribute? {
    switch (name, arguments) {
    case (.identifier(ImplicitKeyword.SwiftAttribute.testable), nil): .testable
    case (.identifier(ImplicitKeyword.SwiftAttribute.exported), nil): .exported
    case let (.identifier(ImplicitKeyword.SwiftAttribute.spi), args?) where args.count == 1:
      args.first?.value.value.simpleIdentifier().map(SupportFile.ImportAttribute.spi)
    default: nil
    }
  }
}
