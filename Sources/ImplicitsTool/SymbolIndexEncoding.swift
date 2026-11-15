// Copyright 2026 Yandex LLC. All rights reserved.

extension SemaTreeBuilder.SymbolIndex {
  final class Strings {
    var ids: [String: Int] = [:]
    func id(_ text: String) -> Int {
      if let value = ids[text] {
        return value
      }
      let value = ids.count
      ids[text] = value
      return value
    }

    func encode(_ symbol: Symbol)
      -> (namespace: [Int], signature: Signature, parameters: [Parameter]) {
      let namespace = symbol.namespace.value.map { id($0) }
      var signature: [Int] = []
      signature.reserveCapacity(16 + symbol.parameters.count * 2)
      signature.append(symbol.parameters.count)
      var parameters: [Parameter] = []
      parameters.reserveCapacity(symbol.parameters.count)
      for parameter in symbol.parameters {
        let label = id(parameter.name)
        signature.append(label)
        signature.append(id(parameter.type))
        parameters.append(.init(label: label, optional: parameter.hasDefaultValue))
      }

      signature.append(id(symbol.file))
      func appendStrings(_ values: [String]) {
        signature.append(values.count)
        for value in values { signature.append(id(value)) }
      }
      if let type = symbol.returnType {
        signature.append(1)
        switch type.namespace {
        case let .success(namespace):
          signature.append(0); appendStrings(namespace.value)
        case let .failure(diagnostics):
          signature.append(1); appendStrings(diagnostics.map(\.value))
        }
        signature.append(id(type.description))
        switch type.strictDescription {
        case let .success(text):
          signature.append(0); signature.append(id(text))
        case let .failure(diagnostics):
          signature.append(1); appendStrings(diagnostics.map(\.value))
        }
      } else {
        signature.append(0)
      }
      let key = Signature(kind: symbol.kind, values: signature)
      return (namespace, key, parameters)
    }
  }

  struct Parameter {
    var label: Int
    var optional: Bool
  }

  struct Signature: Hashable {
    var kind: FunctionKind
    var values: [Int]
  }
}
