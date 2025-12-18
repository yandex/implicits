@_spi(Unsafe)
import Implicits

private func entry(int: UInt8, someVar: UInt16) {
  let scope = ImplicitScope()
  defer { scope.end() }
  @Implicit
  var i1 = Outer()

  @Implicit
  var i2 = Outer.Inner()

  @Implicit
  var int = int

  @Implicit
  var int2 = someVar

  @Implicit
  var v1 = OptionalInitializer()

  @Implicit
  var v2 = MultipleInits(a: 0)

  @Implicit
  var v3 = createFunctionReturnType()

  requiresOuter(scope)
  requiresInner(scope)
  requiresUInts(scope)
  requiresOthers(scope)
  requiresFunctionReturnType(scope)
}

private func requiresOuter(_ scope: ImplicitScope) {
  @Implicit()
  var i1: Outer
}

private func requiresInner(_ scope: ImplicitScope) {
  @Implicit()
  var i1: Outer.Inner
}

private func requiresOthers(_ scope: ImplicitScope) {
  @Implicit()
  var v1: OptionalInitializer?
  @Implicit()
  var v2: MultipleInits
}

private func requiresUInts(_ scope: ImplicitScope) {
  @Implicit()
  var i1: UInt8
  @Implicit()
  var i2: UInt16
}

private struct Outer {
  struct Inner {
  }
}

private final class OptionalInitializer {
  init?() {}
}

private struct S_TypesOfFieldVars {
  @Implicit()
  var field1: Int

  @Implicit()
  var field2: UInt8?

  @Implicit()
  private var field3: UInt16

  init(_: ImplicitScope) {}

  private func entry1() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit()
    var _field1 = field1
    @Implicit()
    var _field2 = self.field2
    @Implicit()
    var field3 = self.field3

    requiresInts(scope)
  }

  private func requiresInts(_ scope: ImplicitScope) {
    @Implicit()
    var _v1: Int
    @Implicit()
    var _v2: UInt8?
    @Implicit()
    var _v3: UInt16
  }
}

// Type should be resolved even when there is ambiguity in called function,
// but all candidates have the same return type.
private struct MultipleInits {
  init(a: Int) {}
  init(a: UInt = 0) {}
}

private struct FunctionReturnType {}

private func createFunctionReturnType() -> FunctionReturnType {
  FunctionReturnType()
}

private func requiresFunctionReturnType(_ scope: ImplicitScope) {
  @Implicit()
  var v: FunctionReturnType
}
