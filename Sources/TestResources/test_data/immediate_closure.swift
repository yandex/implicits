import Implicits

private func immediateClosureUsage() {
  // expected-error@+1 {{Unresolved requirements: UInt16, UInt64, UInt8}}
  let scope = ImplicitScope()
  defer { scope.end() }

  MainActor.assumeIsolated {
    @Implicit() var v1: UInt8
    @Implicit() var v2: UInt16
  }

  MainActor.assumeIsolated {
    let scope = scope.nested()
    defer { scope.end() }

    @Implicit() var v1: UInt32 = 0
    requireUInt32(scope)
    requireUInt64(scope)
  }
}

private func explicitCaptureOnImmediateClosure() {
  // expected-error@+1 {{Unresolved requirement: UInt32}}
  let scope = ImplicitScope()
  defer { scope.end() }

  MainActor.assumeIsolated(withCapturedImplicits { scope in
    @Implicit() var v1: UInt32
  })
}

private func requireUInt32(_: ImplicitScope) {
  @Implicit() var v1: UInt32
}

private func requireUInt64(_: ImplicitScope) {
  @Implicit() var v1: UInt64
}

private func withCapturedImplicits<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T { fatalError() }
