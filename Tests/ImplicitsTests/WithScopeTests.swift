import Testing

@_spi(Unsafe) internal import Implicits

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
      [implicits = Implicits(
        unsafeKeys: Implicits.getRawKey(\.id)
      )] in
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
        [implicits = Implicits(
          unsafeKeys: Implicits.getRawKey(\.id)
        )] in
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
      implicits: Implicits(unsafeKeys: Implicits.getRawKey(\.id), Implicits.getRawKey(\.launchID))
    )

    service.doWork { inheritedId, inheritedLaunchID in
      #expect(inheritedId == 42)
      #expect(inheritedLaunchID == 999)
    }

    #expect(id == 42)
    #expect(launchID == 999)
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
}

private struct TestError: Error {}
