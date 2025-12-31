// Copyright 2025 Yandex LLC. All rights reserved.

import Testing

@_spi(Unsafe) internal import Implicits

struct ImplicitConcurrencyTests {
  @Test func retrievingInDifferentContext() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 1

    let actor = SomeActor(scope)
    let retrieved = await actor.testActorImplicit(scope)

    #expect(retrieved == 1)
  }

  @Test func storedImplicitInActor() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 42

    let actor = SomeActor(scope)
    let retrieved = await actor.getStoredId()

    #expect(retrieved == 42)
  }

  @Test func nonisolatedActorFunction() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 77

    let actor = SomeActor(scope)
    let result = actor.nonisolatedWithImplicits(scope)

    #expect(result.got == 77)
    #expect(result.declared == 999)
  }

  @Test func createRootScopeInActor() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 0

    let actor = SomeActor(scope)
    let retrieved = await actor.createRootScope(id: 42)

    #expect(retrieved == 42)
  }

  @Test func createRootScopeInMainActor() async {
    let retrieved = await testMainActor(id: 81)
    #expect(retrieved == 81)
  }
  
  @Test func childTasksScopesShouldBeIsolated() async {
    let cp = Checkpoint<Step>()

    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var parentId = 0

    let task1 = Task {
      let scope = ImplicitScope()
      defer { scope.end() }

      @Implicit(\.id)
      var id = 1

      await cp.open(.task1Ready)
      await cp.wait(.task2Ready)

      @Implicit(\.id)
      var readBack: Int

      await cp.open(.task1Read)
      await cp.wait(.task2Read)
      return readBack
    }

    let task2 = Task {
      await cp.wait(.task1Ready)

      let scope = ImplicitScope()
      defer { scope.end() }

      @Implicit(\.id)
      var id = 2

      await cp.open(.task2Ready)
      await cp.wait(.task1Read)

      @Implicit(\.id)
      var readBack: Int

      await cp.open(.task2Read)
      return readBack
    }

    let r1 = await task1.value
    let r2 = await task2.value

    #expect(r1 == 1)
    #expect(r2 == 2)
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
  @Implicit(\.id)
  var storedId

  init(_: ImplicitScope) {}

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

  func getStoredId() -> Int {
    storedId
  }

  nonisolated func nonisolatedWithImplicits(_ scope: ImplicitScope) -> (got: Int, declared: Int) {
    let scope = scope.nested()
    defer { scope.end() }

    @Implicit(\.id)
    var gotId: Int

    @Implicit(\.launchID)
    var declaredLaunchID = 999

    return (gotId, get(\.launchID, scope))
  }
}

enum Step {
  case task1Ready
  case task2Ready
  case task1Read
  case task2Read
}

actor Checkpoint<Step: Hashable> {
  private var opened: Set<Step> = []
  private var waiters: [Step: [CheckedContinuation<Void, Never>]] = [:]

  func open(_ step: Step) {
    guard opened.insert(step).inserted else { return }
    if let list = waiters.removeValue(forKey: step) {
      for cont in list { cont.resume() }
    }
  }

  func wait(_ step: Step) async {
    if opened.contains(step) { return }
    await withCheckedContinuation { cont in
      waiters[step, default: []].append(cont)
    }
  }
}
