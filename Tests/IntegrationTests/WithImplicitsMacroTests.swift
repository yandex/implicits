@_spi(Unsafe) internal import Implicits
import Testing

struct WithImplicitsMacroTests {
  @Test func capturesImplicitsAtDefinitionTime() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.testID) var id = 10
    @Implicit(\.testLaunchID) var launchID = 20

    let wrapped = #withImplicits { _ in
      @Implicit(\.testID) var a: Int
      @Implicit(\.testLaunchID) var b: Int
      return a + b
    }

    #expect(wrapped() == 30)

    verifyInNestedScope(scope, wrapped: wrapped)
  }

  @Test func multipleInvocations() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.testID) var id = 10

    var n = 0
    let wrapped = #withImplicits { _ in
      @Implicit(\.testID) var v: Int
      n += 1
      return v + n
    }

    #expect(wrapped() == 11)
    #expect(wrapped() == 12)
    #expect(wrapped() == 13)
  }
}

private func verifyInNestedScope(_ scope: ImplicitScope, wrapped: () -> Int) {
  let scope = scope.nested()
  defer { scope.end() }

  @Implicit(\.testID) var nestedId = 999
  @Implicit(\.testLaunchID) var nestedLaunchID = 999

  #expect(wrapped() == 30)
}

extension ImplicitsKeys {
  static let testID = Key<Int>()
  static let testLaunchID = Key<Int>()
}
