@_spi(Unsafe) internal import Implicits
import Testing

struct WithScopeTests {
  @Test func scopeBasics() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var value = 42

    withScope { scope in
      @Implicit(\.id)
      var value = 200
      #expect(value == 200)

      do {
        let scope = scope.nested()
        defer { scope.end() }

        @Implicit(\.id)
        var value = 300
        #expect(value == 300)
      }

      #expect(value == 200)
    }

    #expect(value == 42)
  }

  @Test func scopeThrows() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var value = 42

    do {
      try withScope { _ in
        @Implicit(\.id)
        var value = 300
        #expect(value == 300)
        throw TestError()
      }
      Issue.record("Should have thrown")
    } catch {
      #expect(value == 42)
    }
  }

  @Test func scopeNesting() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 42

    @Implicit(\.launchID)
    var launchID = 999

    withScope(nesting: scope) { _ in
      @Implicit(\.id)
      var inheritedId: Int
      @Implicit(\.launchID)
      var inheritedLaunchID: Int
      #expect(inheritedId == 42)
      #expect(inheritedLaunchID == 999)

      @Implicit(\.id)
      var overriddenId = 100
      #expect(overriddenId == 100)

      @Implicit(\.launchID)
      var unchangedLaunchID: Int
      #expect(unchangedLaunchID == 999)
    }

    #expect(id == 42)
    #expect(launchID == 999)

    do {
      try withScope(nesting: scope) { _ in
        @Implicit(\.id)
        var value = 300
        #expect(value == 300)
        throw TestError()
      }
      Issue.record("Should have thrown")
    } catch {
      #expect(id == 42)
    }
  }

  @Test func scopeWithBag() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 42

    let closure = {
      [
        implicits = Implicits(
          unsafeKeys: Implicits.getRawKey(\.id)
        )
      ] in
      withScope(with: implicits) { _ in
        @Implicit(\.id)
        var inheritedValue: Int
        #expect(inheritedValue == 42)

        @Implicit(\.id)
        var overriddenValue = 100
        #expect(overriddenValue == 100)
      }
    }
    closure()

    #expect(id == 42)

    do {
      let closure = {
        [
          implicits = Implicits(
            unsafeKeys: Implicits.getRawKey(\.id)
          )
        ] in
        try withScope(with: implicits) { _ in
          @Implicit(\.id)
          var value = 300
          #expect(value == 300)
          throw TestError()
        }
      }
      try closure()
      Issue.record("Should have thrown")
    } catch {
      #expect(id == 42)
    }
  }

  @Test func scopeWithStoredBag() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 42

    @Implicit(\.launchID)
    var launchID = 999

    let service = TestService(
      implicits: Implicits(
        unsafeKeys: Implicits.getRawKey(\.id), Implicits.getRawKey(\.launchID)
      )
    )

    service.doWork { inheritedId, inheritedLaunchID in
      #expect(inheritedId == 42)
      #expect(inheritedLaunchID == 999)
    }

    #expect(id == 42)
    #expect(launchID == 999)
  }

  @Test func asyncScopeConcurrentIsolation() async {
    // Test that concurrent tasks have isolated scopes via TaskLocal
    await withTaskGroup(of: Void.self) { group in
      for i in 1...10 {
        group.addTask {
          await withScope { _ in
            @Implicit(\.id)
            var id = i * 100

            // Yield to allow other tasks to interleave
            await Task.yield()

            // Each task should see its own value, not values from other tasks
            @Implicit(\.id)
            var readId: Int
            #expect(readId == i * 100)

            // Nested scope should also be isolated
            await withScope { _ in
              @Implicit(\.id)
              var nestedId = i * 1000

              await Task.yield()

              @Implicit(\.id)
              var readNestedId: Int
              #expect(readNestedId == i * 1000)
            }

            // After nested scope, value should be restored
            @Implicit(\.id)
            var afterNestedId: Int
            #expect(afterNestedId == i * 100)
          }
        }
      }
    }
  }
}

private class TestService {
  var implicits: Implicits

  init(implicits: Implicits) {
    self.implicits = implicits
  }

  func doWork(_ callback: (Int, Int) -> Void) {
    withScope(with: implicits) { _ in
      @Implicit(\.id)
      var inheritedId: Int
      @Implicit(\.launchID)
      var inheritedLaunchID: Int
      callback(inheritedId, inheritedLaunchID)
    }
  }

  func doWorkAsync(_ callback: (Int, Int) -> Void) async {
    await withScope(with: implicits) { _ in
      await Task.yield()
      @Implicit(\.id)
      var inheritedId: Int
      @Implicit(\.launchID)
      var inheritedLaunchID: Int
      callback(inheritedId, inheritedLaunchID)
    }
  }
}

private struct TestError: Error {}

// MARK: - Async Tests

struct AsyncWithScopeTests {
  @Test func asyncScopeBasics() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var value = 42

    await withScope { scope in
      await Task.yield()
      @Implicit(\.id)
      var value = 200
      #expect(value == 200)

      do {
        let scope = scope.nested()
        defer { scope.end() }

        @Implicit(\.id)
        var value = 300
        #expect(value == 300)
      }

      #expect(value == 200)
    }

    #expect(value == 42)
  }

  @Test func asyncScopeThrows() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var value = 42

    do {
      try await withScope { _ in
        await Task.yield()
        @Implicit(\.id)
        var value = 300
        #expect(value == 300)
        throw TestError()
      }
      Issue.record("Should have thrown")
    } catch {
      #expect(value == 42)
    }
  }

  @Test func asyncScopeNesting() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 42

    @Implicit(\.launchID)
    var launchID = 999

    await withScope(nesting: scope) { _ in
      await Task.yield()
      @Implicit(\.id)
      var inheritedId: Int
      @Implicit(\.launchID)
      var inheritedLaunchID: Int
      #expect(inheritedId == 42)
      #expect(inheritedLaunchID == 999)

      @Implicit(\.id)
      var overriddenId = 100
      #expect(overriddenId == 100)

      @Implicit(\.launchID)
      var unchangedLaunchID: Int
      #expect(unchangedLaunchID == 999)
    }

    #expect(id == 42)
    #expect(launchID == 999)

    do {
      try await withScope(nesting: scope) { _ in
        await Task.yield()
        @Implicit(\.id)
        var value = 300
        #expect(value == 300)
        throw TestError()
      }
      Issue.record("Should have thrown")
    } catch {
      #expect(id == 42)
    }
  }

  @Test func asyncScopeWithBag() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 42

    let closure = {
      [
        implicits = Implicits(
          unsafeKeys: Implicits.getRawKey(\.id)
        )
      ] in
      await withScope(with: implicits) { _ in
        await Task.yield()
        @Implicit(\.id)
        var inheritedValue: Int
        #expect(inheritedValue == 42)

        @Implicit(\.id)
        var overriddenValue = 100
        #expect(overriddenValue == 100)
      }
    }
    await closure()

    #expect(id == 42)

    do {
      let closure = {
        [
          implicits = Implicits(
            unsafeKeys: Implicits.getRawKey(\.id)
          )
        ] in
        try await withScope(with: implicits) { _ in
          await Task.yield()
          @Implicit(\.id)
          var value = 300
          #expect(value == 300)
          throw TestError()
        }
      }
      try await closure()
      Issue.record("Should have thrown")
    } catch {
      #expect(id == 42)
    }
  }

  @Test func asyncScopeWithStoredBag() async {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var id = 42

    @Implicit(\.launchID)
    var launchID = 999

    let service = TestService(
      implicits: Implicits(
        unsafeKeys: Implicits.getRawKey(\.id), Implicits.getRawKey(\.launchID)
      )
    )

    await service.doWorkAsync { inheritedId, inheritedLaunchID in
      #expect(inheritedId == 42)
      #expect(inheritedLaunchID == 999)
    }

    #expect(id == 42)
    #expect(launchID == 999)
  }
}
