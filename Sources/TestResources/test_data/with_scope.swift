@_spi(Unsafe)
import Implicits

private func entry() throws {
  withScope { scope in // expected-error {{Unresolved requirement: UInt8}}
    requireUInt8(scope)
  }

  try withScope { scope in // expected-error {{Unresolved requirement: UInt8}}
    requireUInt8(scope)

    throw Err()
  }

  withScope { scope in // expected-error {{Unresolved requirement: UInt8}}
    if Bool.random() {
      let scope = scope.nested()
      defer { scope.end() }

      @Implicit()
      var _: UInt16 = 0

      requireUInt8(scope)
      requireUInt16(scope)
    }
  }

  // `withScope {}` doesnt inherit outer scope
  withScope { scope in
    @Implicit
    var v1: UInt8 = 1
    @Implicit
    var v2: UInt16 = 2

    // expected-error@+2 {{Unresolved requirement: UInt16}}
    // expected-warning@+1 {{Implicitly overriding existing scope}}
    withScope { scope in
      @Implicit
      var v2: UInt8 = 22

      requireUInt8(scope)
      requireUInt16(scope)
    }
  }
}

private func withScopeNestingAnother() {
  let scope = ImplicitScope()
  defer { scope.end() }

  @Implicit
  var v1: UInt8 = 1
  @Implicit
  var v2: UInt16 = 2

  withScope(nesting: scope) { scope in
    @Implicit
    var v2: UInt8 = 22

    requireUInt8(scope)
    requireUInt16(scope)
  }
}

// MARK: - withScope(with:) tests

private func withScopeWithBag() {
  // expected-error@+1 {{Unresolved requirements: UInt16, UInt8}}
  let scope = ImplicitScope()
  defer { scope.end() }

  let closure1 = { [implicits = testBagImplicits()] in
    withScope(with: implicits) { scope in
      @Implicit()
      var i: UInt8
    }
  }
  closure1()

  let closure2 = { [implicits = testBagImplicits()] in
    withScope(with: implicits) { scope in
      requireUInt16(scope)
    }
  }
  closure2()

  let closure3 = { [foo = testBagImplicits()] in
    // expected-error@+2 {{Invalid 'with:' parameter, expected 'implicits' identifier}}
    // expected-error@+1 {{Unresolved requirement: UInt32}}
    withScope(with: foo) { scope in
      @Implicit()
      var i: UInt32
    }
  }
  closure3()

  // expected-error@+1 {{Unused bag}}
  _ = { [implicits = testBagImplicits()] in
    _ = implicits
    // expected-error@+1 {{Unresolved requirement: UInt64}}
    withScope { scope in
      @Implicit()
      var i: UInt64
    }
  }

  let implicits = testBagImplicits()
  let closure4 = {
    withScope(with: implicits) { scope in // expected-error {{Using unknown bag}}
      @Implicit()
      var i: Int8
    }
  }
  closure4()
}

// MARK: - Stored bag with withScope(with:)

private func storedBagEntry() {
  // expected-error@+1 {{Unresolved requirements: UInt16, UInt8}}
  let scope = ImplicitScope()
  defer { scope.end() }

  _ = StoredBagWithScope(scope)
}

private struct StoredBagWithScope {
  let implicits = testBagImplicits()

  init(_: ImplicitScope) {}

  func usesBag() {
    withScope(with: implicits) { scope in
      @Implicit()
      var v1: UInt8
    }
  }

  func usesBagWithRequire() {
    withScope(with: implicits) { scope in
      requireUInt16(scope)
    }
  }
}

// MARK: - Helpers

private func testBagImplicits() -> Implicits {
  Implicits()
}

private func requireUInt8(_ scope: ImplicitScope) {
  @Implicit()
  var foo: UInt8
}

private func requireUInt16(_ scope: ImplicitScope) {
  @Implicit()
  var _: UInt16
}

private struct Err: Error {}
