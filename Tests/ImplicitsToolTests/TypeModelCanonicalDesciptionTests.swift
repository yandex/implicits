// Copyright 2024 Yandex LLC. All rights reserved.

import Testing

import ImplicitsTool
import SwiftParser
import SwiftSyntax

struct TypeModelCanonicalDesciptionTests {
  @Test func simple() {
    check("Foo")
    check(" Foo  ", "Foo")
  }

  @Test func generic() {
    check("Foo<Bar>")
    check(" Foo< Bar , Baz > ", "Foo<Bar, Baz>")
  }

  @Test func optional() {
    check("Foo?")
  }

  @Test func unwrappedOptional() {
    check("Foo!")
  }

  @Test func tuple() {
    check("(Foo, Bar)")
    check("(Foo,Bar)", "(Foo, Bar)")
    check("(foo:Foo,  bar  :  Bar  )", "(foo: Foo, bar: Bar)")
  }

  @Test func member() {
    check("Foo.Bar")
  }

  @Test func array() {
    check("[Foo]")
  }

  @Test func attributed() {
    check("@foo Bar")
    check("@foo @bar Baz")
    check("@foo(bar: baz) Qux")
    check("@[Bar] Baz")
    check("@[Bar: Baz] Qux")
    check("@Foo(bar: baz) Qux")
    check("@Foo(bar: 1) Qux", "@Foo(bar: UNPARSED_ARGUMENT) Qux")
    check("@ [ Bar : Baz] (bar: baz) Qux", "@[Bar: Baz](bar: baz) Qux")
    check("borrowing Bar")
    check("  __shared   Bar ", "__shared Bar")
  }

  @Test func classRestriction() {
    // Only valid in protocol restrictions, which SyntaxTree doesn't support yet
  }

  @Test func composition() {
    check("Foo & Bar & Baz")
  }

  @Test func dictionary() {
    check("[Foo: Bar]")
    check("[Foo:Bar]", "[Foo: Bar]")
    check("[Foo : Bar]", "[Foo: Bar]")
    check("[  Foo  :  Bar  ]", "[Foo: Bar]")
  }

  @Test func function() {
    check("(Foo) -> Bar")
    check("(Foo)->Bar", "(Foo) -> Bar")
    check("( _ foo : Foo, _ bar:Bar) -> Baz", "(_ foo: Foo, _ bar: Bar) -> Baz")
    check("(@escaping () throws -> Foo) async -> Bar")
  }

  @Test func metatype() {
    check("Foo.Type")
    check("Foo.Protocol")
  }

  @Test func namedOpaqueReturn() {
    check("<each Foo: Bar> Foo")
  }

  @Test func packElement() {
    check("each Foo")
  }

  @Test func packExpansion() {
    check("repeat Foo")
  }

  @Test func someOrAny() {
    check("some Foo")
  }

  @Test func suppressed() {
    check("~Foo")
  }

  @Test func nested() {
    check("@escaping (Foo<[(dict: [Bar: P1 & P2], Baz.Qux!?)]>) -> Void")
  }
}

enum Policy {
  case varDeclType

  func makeSource(_ src: String) -> String {
    switch self {
    case .varDeclType:
      "let a: \(src) = b()"
    }
  }

  func extract<S>(
    _ topLevel: SyntaxTree<S>.TopLevelEntity
  ) -> SyntaxTree<S>.TypeModel? {
    switch self {
    case .varDeclType:
      guard case let .declaration(.variable(variable)) = topLevel.value else {
        return nil
      }
      return variable.bindings.first?.type
    }
  }
}

func check(
  _ input: String, _ output: String? = nil, policy: Policy = .varDeclType
) {
  let output = output ?? input
  let tree = Parser.parse(source: policy.makeSource(input))
  let sxtTree = SyntaxTree.build(
    tree,
    ifConfig: .unknown,
  )
  let tl = sxtTree.first
  guard let got = tl.flatMap({ policy.extract($0)?.description }) else {
    Issue.record("Failed to extract type model")
    return
  }
  #expect(got == output)
}
