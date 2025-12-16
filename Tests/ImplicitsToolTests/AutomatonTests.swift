// Copyright 2024 Yandex LLC. All rights reserved.

import Testing

import ImplicitsTool

private typealias TestAutomaton = Automaton<Character, Int>

struct AutomatonTests {
  @Test func exact() {
    var me = TestAutomaton()
    me.addPattern(.exact("a"), value: 1)
    me.addPattern(.exact("b"), value: 2)
    me.addPattern(.exact("c"), value: 3)

    me.check("a", expected: [1])
    me.check("b", expected: [2])
    me.check("c", expected: [3])
    me.check("d", expected: [])
  }

  @Test func sequence() {
    var me = TestAutomaton()
    me.addPattern(["a", "b", "c"], value: 1)
    me.addPattern(["a", "b"], value: 2)

    me.check("abc", expected: [1])
    me.check("ab", expected: [2])
    me.check("abcd", expected: [])
    me.check("a1b", expected: [])
  }

  @Test func optional() {
    var me = TestAutomaton()
    me.addPattern(["a", .optional("b"), "c"], value: 1)
    me.addPattern(["a", "c"], value: 2)

    me.check("abc", expected: [1])
    me.check("ac", expected: [1, 2])
    me.check("a1c", expected: [])
    me.check("abcd", expected: [])
  }

  @Test func nested() {
    var me = TestAutomaton()
    // 1: a(bc)?d
    me.addPattern(["a", .optional(["b", "c"]), "d"], value: 1)
    // 2: a(bc)?de
    me.addPattern(["a", .optional(["b", "c"]), "d", "e"], value: 2)
    // 3: a(bc)?de?
    me.addPattern(["a", .optional(["b", "c"]), "d", .optional("e")], value: 3)

    me.check("abcd", expected: [1, 3])
    me.check("ad", expected: [1, 3])
    me.check("abcde", expected: [2, 3])
    me.check("ade", expected: [2, 3])
    me.check("abcdef", expected: [])
  }

  @Test func manyOptionalsDoesntCauseExponentialGrowth() {
    let alphabet = "abcdefghijklmnopqrstuvwxyz"
    var me = TestAutomaton()
    me.addPattern(
      .sequence(alphabet.map { .optional($0) }),
      value: 1
    )
    me.addPattern(
      .sequence(Array(alphabet.reversed()).map { .optional($0) }),
      value: 2
    )

    me.check("", expected: [1, 2])
    me.check("a", expected: [1, 2])
    me.check("z", expected: [1, 2])
    me.check("ab", expected: [1])
    me.check("az", expected: [1])
    me.check(alphabet, expected: [1])
    me.check("ba", expected: [2])
    me.check("bad", expected: [])
    me.check("a" + alphabet, expected: [])
  }

  @Test func zeroOrMore() {
    var me = TestAutomaton()
    me.addPattern([.zeroOrMore("a")], value: 1)
    me.addPattern(["b", .zeroOrMore("c"), "d"], value: 2)

    me.check("", expected: [1])
    me.check("a", expected: [1])
    me.check("aaaa", expected: [1])

    me.check("b", expected: [])
    me.check("bd", expected: [2])
    me.check("bcd", expected: [2])
    me.check("bccccd", expected: [2])
  }

  @Test func mixed() {
    var me = TestAutomaton()
    me.addPattern(["a", .zeroOrMore("b"), "c"], value: 1)
    me.addPattern(["a", .zeroOrMore("b"), "c", "d"], value: 2)
    me.addPattern(["a", .zeroOrMore("b"), "c", .optional("d")], value: 3)

    me.check("ac", expected: [1, 3])
    me.check("abbbbbbbc", expected: [1, 3])
    me.check("accccd", expected: [])
    me.check("abbbbbbbc", expected: [1, 3])
    me.check("abbbbbbbcd", expected: [2, 3])
    me.check("abbbd", expected: [])
  }
}

extension TestAutomaton {
  func check(_ input: String, expected: [Int]) {
    #expect(Set(match(input)) == Set(expected))
  }
}

extension TestAutomaton.Pattern:
  ExpressibleByUnicodeScalarLiteral,
  ExpressibleByExtendedGraphemeClusterLiteral {
  public init(extendedGraphemeClusterLiteral value: Character) {
    self = .exact(value)
  }
}
