// Copyright 2025 Yandex LLC. All rights reserved.

import Testing

@_spi(Testing)
import ImplicitsTool
import SwiftParser
import SwiftSyntax

struct IfConfigTests {
  @Test func conditionEvaluator() throws {
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

  @Test func ifConfig() throws {
    func check(_ e: String, _ expected: String) {
      let syntax = Syntax(Parser.parse(source: e))
      let removed = removingInactiveIfConfig(
        syntax, config: .enabled(["A", "B", "C"])
      ).description
      #expect(
        removed.trim(\.isWhitespace) == expected.trim(\.isWhitespace),
        "Expected \n\(e) to reduce into \n\(expected), but got \n\(removed)"
      )
    }

    check(
      """
      #if A
      let a = 1
      #else
      let b = 2
      #endif
      """,
      """
      #if A
      let a = 1
      #endif
      """
    )
    check(
      """
      #if D
      let a = 1
      #else
      let b = 2
      #endif
      """,
      """
      #if true
      let b = 2
      #endif
      """
    )
    check(
      """
      #if os(iOS)
      f(1)
      #elseif A
      f(2)
      #else
      f(3)
      #endif
      """,
      """
      #if os(iOS)
      f(1)
      #elseif A
      f(2)
      #endif
      """
    )
  }
}

extension Bool? {
  fileprivate var descr: String {
    map { "\($0)" } ?? "nil"
  }
}

extension StringProtocol {
  func trim(
    _ shouldTrim: (Character) -> Bool
  ) -> Substring where SubSequence == Substring {
    guard !isEmpty else { return self[startIndex..<startIndex] }
    var start = startIndex
    var end = index(before: endIndex)

    while start <= end, shouldTrim(self[start]) {
      start = index(after: start)
    }

    while end >= start, shouldTrim(self[end]) {
      end = index(before: end)
    }

    if start > end {
      return self[startIndex..<startIndex]
    }
    return self[start...end]
  }
}
