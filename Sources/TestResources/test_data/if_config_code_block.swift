import Implicits

private func ifConfigCodeBlock() {
  withScope { scope in
    @Implicit var v0: Bool = false

    #if canImport(M1)
    // expected-note@-1 {{Unable to resolve condition}}
    // expected-error@+1 {{Cannot mutate implicit context inside '#if' block with unresolved condition}}
    @Implicit var v1: UInt8 = 0
    #endif
  }
  
  if Bool.random() {
    #if canImport(M2)
    // expected-note@-1 {{Unable to resolve condition}}
    // expected-error@+1 {{Cannot create implicit scope inside '#if' block with unresolved condition}}
    let scope = ImplicitScope()
    defer { scope.end() }
    // expected-error@+1 {{Cannot mutate implicit context inside '#if' block with unresolved condition}}
    @Implicit var v1: UInt16 = 0
    #endif
  }

  withScope { scope in
    #if canImport(M1)
    // expected-note@-1 {{Unable to resolve condition}}
    otherCode()
    #else
    // expected-error@+1 {{Cannot mutate implicit context inside '#if' block with unresolved condition}}
    @Implicit var v1: UInt32 = 0
    #endif
  }

  withScope { scope in
    #if canImport(M1)
    otherCode()
    #elseif canImport(M2)
    // expected-note@-1 {{Unable to resolve condition}}
    otherCode()
    #else
    // expected-error@+1 {{Cannot mutate implicit context inside '#if' block with unresolved condition}}
    @Implicit var v1: UInt64 = 0
    #endif
  }

  // expected-error@+1 {{Unresolved requirement: UInt32}}
  withScope { scope in
    @Implicit var v1: UInt8 = 0
    #if canImport(M1)
    // expected-warning@+2 {{Implicitly overriding existing scope}}
    // expected-error@+1 {{Unresolved requirement: UInt16}}
    withScope { scope in
      @Implicit var v2: UInt8 = 0
      requiresUInt8(scope)
      requiresUInt16(scope)
    }
    #elseif canImport(M2)
    withScope(nesting: scope) { scope in 
      @Implicit var v2: UInt16 = 0
      requiresUInt8(scope)
      requiresUInt16(scope)
      requiresUInt32(scope)
    }
    #endif
  }

  // expected-error@+1 {{Unresolved requirements: UInt16, UInt32, UInt8}}
  withScope{ scope in
    #if canImport(M1)
    requiresUInt8(scope)
    #elseif canImport(M2)
    requiresUInt16(scope)
    #else
    requiresUInt32(scope)
    #endif
  }

  // expected-error@+1 {{Unresolved requirement: UInt16}}
  withScope { scope in
    #if canImport(M1)
    if Bool.random() {
      let scope = scope.nested()
      defer { scope.end() }
      @Implicit var v2: UInt8 = 0
      requiresUInt8(scope)
      requiresUInt16(scope)
    }
    #endif
  }
}

private func otherCode() {}

private func requiresUInt8(_: ImplicitScope) {
  @Implicit() var v: UInt8
}

private func requiresUInt16(_: ImplicitScope) {
  @Implicit() var v: UInt16
}
private func requiresUInt32(_: ImplicitScope) {
  @Implicit() var v: UInt32
}
