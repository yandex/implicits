@_spi(Unsafe) internal import Implicits
import Testing

struct WithImplicitsMacroTests {
  @Test func `captures implicits at definition time`() {
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

    verifyInNestedScope(wrapped: wrapped, scope)
  }

  @Test func `multiple invocations`() {
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

  @MainActor
  @Test func `sync @MainActor closure preserves MainActor on result`() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.testID) var id = 42

    let wrapped: @MainActor () -> Int = #withImplicits { @MainActor _ in
      @Implicit(\.testID) var v: Int
      return v + mainActorOnly()
    }

    #expect(wrapped() == 43)
  }

  @MainActor
  @Test func `throwing @MainActor closure preserves MainActor on result`() throws {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.testID) var id = 7

    let wrapped: @MainActor () throws -> Int = #withImplicits { @MainActor _ in
      @Implicit(\.testID) var v: Int
      return try v + mainActorOnlyThrowing()
    }

    #expect(try wrapped() == 8)
  }

  @MainActor
  @Test func `async @MainActor closure preserves MainActor on result`() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.testID) var id = 11

    let wrapped: @MainActor () async -> Int = #withImplicits { @MainActor _ in
      @Implicit(\.testID) var v: Int
      return await v + mainActorOnlyAsync()
    }

    let result = await wrapped()
    #expect(result == 12)
  }

  @MainActor
  @Test func `async throwing @MainActor closure preserves MainActor on result`() async throws {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.testID) var id = 13

    let wrapped: @MainActor () async throws -> Int = #withImplicits { @MainActor _ in
      @Implicit(\.testID) var v: Int
      return try await v + mainActorOnlyAsyncThrowing()
    }

    let result = try await wrapped()
    #expect(result == 14)
  }
}

@MainActor private func mainActorOnly() -> Int { 1 }
@MainActor private func mainActorOnlyThrowing() throws -> Int { 1 }
@MainActor private func mainActorOnlyAsync() async -> Int { 1 }
@MainActor private func mainActorOnlyAsyncThrowing() async throws -> Int { 1 }

private func verifyInNestedScope(wrapped: () -> Int, _ scope: ImplicitScope) {
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
