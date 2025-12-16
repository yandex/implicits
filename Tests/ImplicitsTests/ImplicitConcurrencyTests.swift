// Copyright 2024 Yandex LLC. All rights reserved.

import Testing

@_spi(Unsafe) internal import Implicits

struct ImplicitConcurrencyTests {
  @Test func retrievingInDifferentContext() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 1

    let actor = SomeActor()
    let retrieved = await actor.testActorImplicit(scope)

    #expect(retrieved == 1)
  }

  @Test func createRootScopeInActor() async {
    let actor = SomeActor()
    let retrieved = await actor.createRootScope(id: 42)

    #expect(retrieved == 42)
  }

  @Test func createRootScopeInMainActor() async {
    let retrieved = await testMainActor(id: 81)
    #expect(retrieved == 81)
  }
}

@MainActor
func testMainActor(id given: Int) async -> Int {
  let scope = ImplicitScope()
  defer { scope.end() }

  @Implicit(\.id)
  var id = given

  syncContext(scope)

  @Implicit(\.id)
  var got

  return got
}

private func syncContext(_ scope: ImplicitScope) {
  let scope = scope.nested()
  defer { scope.end() }

  @Implicit(\.id)
  var overridenID = -1

  @Implicit(\.id)
  var got

  #expect(got == -1)
}

private func asyncGetId(_ scope: ImplicitScope) async -> Int {
  get(\.id, scope)
}

actor SomeActor {
  func testActorImplicit(_ scope: ImplicitScope) async -> Int {
    let retrieved = await asyncGetId(scope)

    return retrieved
  }

  func createRootScope(id given: Int) async -> Int {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = given

    let retrieved = await testActorImplicit(scope)

    return retrieved
  }
}
