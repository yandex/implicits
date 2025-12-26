// Copyright 2025 Yandex LLC. All rights reserved.

import Testing

@_spi(Testing)
import ImplicitsTool
import SwiftParser
import SwiftSyntax

struct IfConfigTests {
  @Test func `evaluateCondition evaluates #if conditions`() throws {
    func check(_ e: String, _ expected: Bool?) {
      var parser = Parser(e)
      let e = ExprSyntax.parse(from: &parser)
      let res = evaluateCondition(
        e, config: .enabled(["A", "B", "C"])
      )
      #expect(
        res == expected,
        "Expected \(e) to be \(expected.descr), but got \(res.descr)"
      )
    }

    check("true", true)
    check("false", false)
    check("A", true)
    check("D", false)
    check("A(0)", nil)
    check("D(0)", nil)

    check("A && B", true)
    check("A && D", false)
    check("A && D(1)", nil)
    check("D(2) && D(1)", nil)
    check("D && A(1)", false)

    check("A || B", true)
    check("A || D", true)
    check("A || D(1)", true)
    check("D(2) || D(1)", nil)
    check("D || A(1)", nil)
    check("D || E", false)

    check("!A", false)
    check("!D", true)

    check("(A || B) && D", false)
    check("A || (B && D)", true)
    check("A || B && D", true)
    check("(A && B) || (!A && !B)", true)

    check("A == B", nil)
    check("A != B", nil)
    check("A ** B", nil)
    check("A = B", nil)
  }

  @Test func `Trivia(preservingPositionFrom) converts syntax to spaces`() {
    func check(_ source: String, _ expected: String) {
      let trivia = Trivia(preservingPositionFrom: Parser.parse(source: source))
      #expect(trivia.description == expected)
    }

    check("foo()", "     ")
    check("// comment", "// comment")
    check("/* block */", "/* block */")
    check("let 💩 = 1", "         ")
    check(
      """
      let x = 1
      let y = 2
      """,
      "         \n         "
    )
  }
}

extension Bool? {
  fileprivate var descr: String {
    map { "\($0)" } ?? "nil"
  }
}
