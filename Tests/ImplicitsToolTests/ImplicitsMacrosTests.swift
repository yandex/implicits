// Copyright 2023 Yandex LLC. All rights reserved.

import Testing

import ImplicitsMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport

private let testMacros: [String: Macro.Type] = [
  "implicits": ImplicitMacro.self,
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
}
