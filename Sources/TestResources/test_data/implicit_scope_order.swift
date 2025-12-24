import Implicits

private func entry1() {
  @Implicit()
  var v1: UInt8 // expected-error {{Using implicits without 'ImplicitScope'}}

  let scope = ImplicitScope() // expected-error {{Unresolved requirement: UInt8}}
  defer { scope.end() }

  if Bool.random() {
    // Reading is allowed in inherited scope
    @Implicit()
    var v1: UInt8
  } else {
    // But writung is not
    // expected-error@+2 {{Writing to implicit scope without local 'ImplicitScope'}}
    @Implicit()
    var v2: UInt16 = 0
  }

  // scope.end()
  if Bool.random() {
    // expected-error@+1 {{'scope.end()' must be called before leaving the scope in defer block}}
    let scope = scope.nested()

    @Implicit()
    var v2: UInt8 = 0

    scope.end() // expected-error {{'scope.end()' must be called in 'defer' block}}
  } else if Bool.random() {
    // expected-error@+1 {{Ending inherited implicit scope is forbidden}}
    defer { scope.end() }
    code()
  } else {
    let scope = scope.nested()
    defer { scope.end() } // expected-note {{Foremost scope end}}
    defer { scope.end() } // expected-error {{'scope.end()' is called once per instance}}
    code()
  }

  // nesting is forbidden in closures
  let closure = {
    let scope = scope.nested() // expected-error {{Nesting scope is forbidden here}}
    defer { scope.end() }
    code()
  }
  closure()

  // expected-error@+1 {{Using implicits without 'ImplicitScope'}}
  _ = { funcRequiringScope(scope) }

  // expected-error@+1 {{Using implicits without 'ImplicitScope'}}
  func nestedFunc() { funcRequiringScope(scope) }

  func nestedFunc2() {
    // expected-error@+2 {{Using implicits without 'ImplicitScope'}}
    @Implicit()
    var v1: UInt32
  }

  // expected-error@+1 {{Nested functions with scope parameter are not supported}}
  func nestedFuncWithScope(_ scope: ImplicitScope) {
    @Implicit()
    var v1: UInt32
  }

  func nestedFuncWithNestedScope() {
    // expected-error@+1 {{Nesting scope is forbidden here}}
    let scope = scope.nested()
    defer { scope.end() }
    _ = scope
  }

  func nestedFuncWithOwnScope() {
    // expected-error@+1 {{Unresolved requirement: UInt64}}
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit()
    var v1: UInt64
  }

  if Bool.random() {
    let scope = ImplicitScope() // expected-warning {{Implicitly overriding existing scope}}
    defer { scope.end() }
    code()
  } else {
    let scope = scope.nested()
    defer {
      // expected-error@+2 {{Unexpected statement in 'defer' block, only 'scope.end()' allowed}}
      @Implicit()
      var v3: UInt8

      scope.end()
    }
    code()
  }

  if Bool.random() {
    let scope = scope.nested() // expected-note {{Foremost declaration}}
    defer { scope.end() }

    let scope2 = scope.nested() // expected-error {{Multiple local implicit scopes}}

    code(scope2)
  }
}

private func code() {}
private func code(_: ImplicitScope) {}

private func funcRequiringScope(_: ImplicitScope) {
  @Implicit()
  var v: Int64
}
