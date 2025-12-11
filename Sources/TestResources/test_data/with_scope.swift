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

private func requireUInt8(_ scope: ImplicitScope) {
  @Implicit()
  var foo: UInt8
}

private func requireUInt16(_ scope: ImplicitScope) {
  @Implicit()
  var _: UInt16
}

private struct Err: Error {}
