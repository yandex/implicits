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
        throw NSError(domain: "Test", code: 1, userInfo: nil)
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

    withScope(nesting: scope) { scope in
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
        throw NSError(domain: "Test", code: 1, userInfo: nil)
      }
      XCTFail("Should have thrown")
    } catch {
      XCTAssertEqual(id, 42)
    }
  }
}
