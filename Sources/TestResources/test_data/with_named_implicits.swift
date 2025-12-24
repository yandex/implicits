@_spi(Unsafe)
import Implicits

private func basicUsage() {
  // expected-error@+1 {{Unresolved requirements: UInt16, UInt32, UInt8}}
  let scope = ImplicitScope()
  defer { scope.end() }

  let _: () -> Void = withZeroArgsImplicits { scope in
    @Implicit() var v1: UInt8
  }

  let _: (Int) -> Void = withOneArgImplicits { (a: Int, scope) in
    @Implicit() var v1: UInt16
  }

  let _: (String, Bool) -> Void = withTwoArgsImplicits { (a: String, b: Bool, scope) in
    @Implicit() var v1: UInt32
  }
}

private func nestedWrappers() {
  // expected-error@+1 {{Unresolved requirements: Int16, Int8}}
  let scope = ImplicitScope()
  defer { scope.end() }

  _ = withOuterImplicits { scope in
    @Implicit() var v1: Int8

    _ = withInnerImplicits { (_: Int, scope) in
      @Implicit() var v2: Int16
    }
  }
}

private func conditionalBranches() {
  // expected-error@+1 {{Unresolved requirements: Int32, Int64}}
  let scope = ImplicitScope()
  defer { scope.end() }

  if Bool.random() {
    _ = withBranchAImplicits { scope in
      @Implicit() var v1: Int32
    }
  } else {
    _ = withBranchBImplicits { (_: Int, scope) in
      @Implicit() var v1: Int64
    }
  }
}

private func bagCapture() {
  // expected-error@+1 {{Unresolved requirement: Float}}
  let scope = ImplicitScope()
  defer { scope.end() }

  let closure = { [implicits = namedImplicitsBag()] in
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }

    _ = withBagImplicits { scope in
      @Implicit() var v1: Float
    }
  }
  closure()
}

private func missingScope() {
  // expected-error@+1 {{Using implicits without 'ImplicitScope'}}
  let _: () -> Void = withOrphanImplicits { scope in
    @Implicit() var v1: Double
  }
}

private func duplicateNames(_: ImplicitScope) {
  // expected-note@+1 {{Previous wrapper here}}
  _ = withDuplicateImplicits { scope in
    @Implicit() var v1: UInt8
  }

  // expected-error@+1 {{Implicit closure wrappers must have unique names, 'withDuplicateImplicits' is already defined}}
  _ = withDuplicateImplicits { scope in
    @Implicit() var v1: Int8
  }

  _ = withDuplicateImplicits { scope in
    @Implicit() var v1: Int16
  }
}
