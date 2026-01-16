@_spi(Unsafe)
import Implicits

private func basicUsage() {
  // expected-error@+1 {{Unresolved requirements: Int8, UInt8}}
  let scope = ImplicitScope()
  defer { scope.end() }

  _ = #withImplicits { scope in
    @Implicit() var v1: UInt8
  }

  _ = #withImplicits { (a: Int, b: String, scope) in
    @Implicit() var v1: Int8
    return "\(a): \(b)"
  }
}

private func missingScope() {
  // expected-error@+1 {{Using implicits without 'ImplicitScope'}}
  _ = #withImplicits { scope in
    @Implicit() var v1: Double
  }
}

private func underscoreScope() {
  // expected-error@+1 {{Unresolved requirement: Float}}
  let scope = ImplicitScope()
  defer { scope.end() }

  _ = #withImplicits { _ in
    @Implicit() var v1: Float
  }
}

private func __implicit_wrap_with_implicits_macro_swift_9_7<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T { fatalError() }
private func __implicit_wrap_with_implicits_macro_swift_13_7<A1, A2, T>(_ body: @escaping (A1, A2, ImplicitScope) -> T) -> (A1, A2) -> T { fatalError() }
private func __implicit_wrap_with_implicits_macro_swift_21_7<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T { fatalError() }
private func __implicit_wrap_with_implicits_macro_swift_31_7<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T { fatalError() }
