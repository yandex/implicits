// Copyright 2023 Yandex LLC. All rights reserved.

import Testing

import ImplicitsMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport

private let testMacros: [String: Macro.Type] = [
  "implicits": ImplicitMacro.self,
  "withImplicits": WithImplicitsMacro.self,
]

struct ImplicitMacroTests {
  @Test func implicitMacro() throws {
    assertMacroExpansion(
      """
      let c = { [implictis = #implicits] in 42 }
      """,
      expandedSource: """
      let c = { [implictis = __implicit_bag_test_swift_1_24()] in 42 }
      """,
      diagnostics: [],
      macros: testMacros
    )
  }

  @Test func withImplicitsMacro() throws {
    assertMacroExpansion(
      """
      let c = #withImplicits { _ in 42 }
      """,
      expandedSource: """
      let c = __implicit_wrap_test_swift_1_9({ _ in 42 })
      """,
      diagnostics: [],
      macros: testMacros
    )
  }
}
