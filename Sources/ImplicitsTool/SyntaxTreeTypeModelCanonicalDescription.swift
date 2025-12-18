// Copyright 2024 Yandex LLC. All rights reserved.

extension SyntaxTree.TypeModel {
  func strictDescription(
    errors: inout Diagnostics<Syntax>,
    syntax: Syntax
  ) -> String {
    var policy = StrictDescriptionPolicy<Syntax>()
    defer {
      policy.diagnostics.forEach {
        errors.diagnose($0, at: syntax)
      }
    }
    return render(&policy)
  }

  func strictDescription(
  ) -> (description: String, diagMessages: [DiagnosticMessage]) {
    var policy = StrictDescriptionPolicy<Syntax>()
    let result = render(&policy)
    return (result, policy.diagnostics)
  }

  public var description: String {
    var policy = DiagnosticDescriptionPolicy<Syntax>()
    return render(&policy)
  }
}

extension SyntaxTree.Entity {
  func strictDescription(
    errors: inout Diagnostics<Syntax>
  ) -> String where T == SyntaxTree.TypeModel {
    value.strictDescription(errors: &errors, syntax: syntax)
  }
}

// MARK: - Private

extension SyntaxTree.TypeModel {
  fileprivate func render(_ policy: inout some DescriptionPolicy<Syntax>) -> String {
    switch self {
    case let .identifier(identifier):
      identifier
    case let .generic(base, arguments):
      base.render(&policy) + "<" +
        arguments.map { $0.render(&policy) }.joined(separator: ", ")
        + ">"
    case let .optional(optional):
      optional.render(&policy) + "?"
    case let .unwrappedOptional(unwrappedOptional):
      unwrappedOptional.render(&policy) + "!"
    case let .tuple(tuple):
      "(" + tuple.map { $0.render(&policy) }.joined(separator: ", ") + ")"
    case let .member(member):
      member.map { $0.render(&policy) }.joined(separator: ".")
    case let .array(array):
      "[" + array.render(&policy) + "]"
    case let .inlineArray(count, element):
      "[" + count.render(&policy) + " of " + element.render(&policy) + "]"
    case let .dictionary(key, value):
      "[" + key.render(&policy) + ": " + value.render(&policy) + "]"
    case let .function(params, effects, returnType):
      "(" + params.map { $0.render(&policy) }.joined(separator: ", ") +
        ")\(effects.map { " \($0.render(&policy))" } ?? "") -> " + returnType.render(&policy)
    case let .composition(types):
      types.map { $0.render(&policy) }.joined(separator: " & ")
    case let .attributed(specifiers, attrs, type):
      (specifiers + attrs.map { $0.render(&policy) })
        .joined(separator: " ") + " " + type.render(&policy)
    case let .metatype(base: type, specifier: spec):
      "\(type.render(&policy)).\(spec.description)"
    case let .namedOpaqueReturn(base: base, generics: generic):
      "<" + generic.map { $0.render(&policy) }.joined(separator: ", ") + "> " + base.render(&policy)
    case .classRestriction:
      "class"
    case .missing:
      ""
    case let .suppressed(base):
      "~\(base.render(&policy))"
    case let .packElement(element):
      "each \(element.render(&policy))"
    case let .packExpansion(base):
      "repeat \(base.render(&policy))"
    case let .someOrAny(base, specifier):
      "\(specifier.description) \(base.render(&policy))"
    }
  }
}

extension SyntaxTree.Attribute {
  fileprivate func render(_ policy: inout some DescriptionPolicy<Syntax>) -> String {
    let args = arguments
      .map { "(\($0.map { $0.render(&policy) }.joined(separator: ", ")))" }
    let name = name.render(&policy)
    return "@" + name + (args ?? "")
  }
}

extension SyntaxTree.Argument {
  fileprivate func render(_ policy: inout some DescriptionPolicy<Syntax>) -> String {
    var descr = ""
    if let name {
      descr += name.value + ": "
    }
    descr += value.value.render(&policy)
    return descr
  }
}

extension SyntaxTree.Argument.Value {
  fileprivate func render(_ policy: inout some DescriptionPolicy<Syntax>) -> String {
    switch self {
    case let .explicitType(type):
      type.render(&policy)
    case let .reference(reference):
      reference.render(&policy)
    case let .keyed(keys):
      "\\\(keys.joined(separator: "."))"
    case .other:
      policy.handleUnknownAttributeArgument(self)
    }
  }
}

extension SyntaxTree.TypeModel.MetatypeSpecifier {
  fileprivate var description: String {
    switch self {
    case .type: "Type"
    case .protocol: "Protocol"
    }
  }
}

extension SyntaxTree.TypeModel.SomeOrAny {
  fileprivate var description: String {
    switch self {
    case .some: "some"
    case .any: "any"
    }
  }
}

extension SyntaxTree.TypeModel.TupleTypeElement {
  fileprivate func render(_ policy: inout some DescriptionPolicy<Syntax>) -> String {
    let name = self.name.map {
      $0.0 + ($0.second.map { " \($0)" } ?? "") + ": "
    } ?? ""
    return name + type.render(&policy)
  }
}

extension SyntaxTree.TypeModel.EffectSpecifiers {
  fileprivate func render(_ policy: inout some DescriptionPolicy<Syntax>) -> String {
    let asyncSpec = isAsync ? "async" : nil
    let throwsSpec = `throws`.map {
      let word =
        switch $0.0 {
        case .throws: "throws"
        case .rethrows: "rethrows"
        }
      let type = $0.type.map { "(\($0.render(&policy)))" } ?? ""
      return word + type
    }
    return [asyncSpec, throwsSpec].compactMap(\.self).joined(separator: " ")
  }
}

private protocol DescriptionPolicy<Syntax> {
  associatedtype Syntax
  typealias Arg = SyntaxTree<Syntax>.Argument
  mutating func handleUnknownAttributeArgument(_ attribute: Arg.Value) -> String
}

private let argValuePlaceholder = "UNPARSED_ARGUMENT"

private struct DiagnosticDescriptionPolicy<Syntax>: DescriptionPolicy {
  mutating func handleUnknownAttributeArgument(_: Arg.Value) -> String {
    argValuePlaceholder
  }
}

private struct StrictDescriptionPolicy<Syntax>: DescriptionPolicy {
  var diagnostics: [DiagnosticMessage] = []

  mutating func handleUnknownAttributeArgument(_: Arg.Value) -> String {
    diagnostics.append("Unsupported argument inside type")
    return argValuePlaceholder
  }
}

extension SyntaxTree.GenericParameter {
  fileprivate func render(_ policy: inout some DescriptionPolicy<Syntax>) -> String {
    let attr = attributes.map { $0.render(&policy) }.joined(separator: " ")
    let each = specifier.map { $0.description + " " } ?? ""
    let inherited = inheritedType.map { ": " + $0.render(&policy) } ?? ""
    return attr + each + name + inherited
  }
}

extension SyntaxTree.GenericParameter.Specifier {
  fileprivate var description: String {
    switch self {
    case .each: "each"
    case .let: "repeat"
    }
  }
}
