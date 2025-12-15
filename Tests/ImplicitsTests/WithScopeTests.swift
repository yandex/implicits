import XCTest

@_spi(Unsafe) internal import Implicits

final class WithScopeTests: XCTestCase {
  func testWithScope() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var value = 42

    withScope { scope in
      @Implicit(\.id)
      var value = 200
      XCTAssertEqual(value, 200)

      do {
        let scope = scope.nested()
        defer { scope.end() }

        @Implicit(\.id)
        var value = 300
        XCTAssertEqual(value, 300)
      }

      XCTAssertEqual(value, 200)
    }

    XCTAssertEqual(value, 42)
  }

  func testWithScopeThrows() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit(\.id)
    var value = 42

    do {
      try withScope { _ in
        @Implicit(\.id)
        var value = 300
        XCTAssertEqual(value, 300)
        throw TestError()
      }
      XCTFail("Should have thrown")
    } catch {
      XCTAssertEqual(value, 42)
    }
  }

  func testWithScopeNesting() {
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
      XCTAssertEqual(inheritedId, 42)
      XCTAssertEqual(inheritedLaunchID, 999)

      @Implicit(\.id)
      var overriddenId = 100
      XCTAssertEqual(overriddenId, 100)

      @Implicit(\.launchID)
      var unchangedLaunchID: Int
      XCTAssertEqual(unchangedLaunchID, 999)
    }

    XCTAssertEqual(id, 42)
    XCTAssertEqual(launchID, 999)

    do {
      try withScope(nesting: scope) { _ in
        @Implicit(\.id)
        var value = 300
        XCTAssertEqual(value, 300)
        throw TestError()
      }
      XCTFail("Should have thrown")
    } catch {
      XCTAssertEqual(id, 42)
    }
  }

  func testWithScopeWithBag() {
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
        XCTAssertEqual(inheritedValue, 42)

        @Implicit(\.id)
        var overriddenValue = 100
        XCTAssertEqual(overriddenValue, 100)
      }
    }
    closure()

    XCTAssertEqual(id, 42)

    do {
      let closure = {
        [implicits = Implicits(
          unsafeKeys: Implicits.getRawKey(\.id)
        )] in
        try withScope(with: implicits) { _ in
          @Implicit(\.id)
          var value = 300
          XCTAssertEqual(value, 300)
          throw TestError()
        }
      }
      try closure()
      XCTFail("Should have thrown")
    } catch {
      XCTAssertEqual(id, 42)
    }
  }

  func testWithScopeWithStoredBag() {
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
      XCTAssertEqual(inheritedId, 42)
      XCTAssertEqual(inheritedLaunchID, 999)
    }

    XCTAssertEqual(id, 42)
    XCTAssertEqual(launchID, 999)
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
