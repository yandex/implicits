@_spi(Unsafe)
import Implicits

private func entry() {
  // expected-error@+1 {{Unresolved requirements: UInt16, UInt32, UInt8}}
  let scope = ImplicitScope()
  defer { scope.end() }

  _ = StoresImplicitsBag(scope)
  _ = ImplicitBagMacro(scope)
}

private struct StoresImplicitsBag {
  let implicits = testBag1Implicits()

  init(_: ImplicitScope) {}

  func usesBag() {
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }

    @Implicit()
    var v1: UInt8
  }

  func nestedFuncCantUseBag() {
    func nested() {
      // expected-error@+1 {{Using unknown bag}}
      let scope = ImplicitScope(with: implicits)
      defer { scope.end() }
      _ = scope
    }
  }

  lazy var usesBagLazy: UInt16 = {
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }

    @Implicit()
    var v1: UInt16

    return v1
  }()

  #if NOCOMPILE // No support in runtime
  func usesBagAndNested(_ scope: ImplicitScope) {
    // expected-error@+1 {{Nested scopes with bags are not supported yet}}
    let scope = scope.nested(with: implicits)
    defer { scope.end() }

    @Implicit()
    var v1: UInt8

    @Implicit()
    var v2: UInt16
  }
  #endif
}

private struct StoresImplicitBagWithoutInitializer {
  // expected-error@+1 {{Type with '@Implicit' stored properties or stored implicits bag must have an initializer with 'scope' argument}}
  let implicits = testBag2Implicits()

  func f() {
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }

    @Implicit()
    var v1: UInt8
  }
}

private struct StoresMultipleBags {
  // expected-note@+1 {{Previous stored bag here}}
  let implicits = testBag2Implicits()

  #if NOCOMPILE
  // expected-error@+1 {{More that one stored implicit bag}}
  let implicits = testBag3Implicits()
  #endif

  init(_: ImplicitScope) {}
}

private struct ImplicitBagMacro {
  let implicits = #implicits

  init(_: ImplicitScope) {}

  func usesBag() {
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }

    @Implicit()
    var v1: UInt32
  }
}

private func __implicit_bag_stored_implicit_bag_swift_86_19() -> Implicits {
  return Implicits()
}

private func testBag1Implicits() -> Implicits {
  return Implicits()
}

private func testBag2Implicits() -> Implicits {
  return Implicits()
}

private func testBag3Implicits() -> Implicits {
  return Implicits()
}
