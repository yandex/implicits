@_spi(Unsafe)
import Implicits

private func entry1() {
  var scope: ImplicitScope = ImplicitScope()
  // expected-error@-1 {{'scope' must be a 'let' constant}}
  // expected-error@-2 {{Redundant type annotation}}}
  defer { scope.end() }

  scope = devil()

  @Implicit(wrappedValue: 5)
  // expected-error@-1 {{Unexpected argument name, got 'wrappedValue', expected empty}}
  // expected-error@-2 {{Unable to infer implicit key, expected literal type or keypath}}
  var i: Int

  @Implicit
  var j = Int("42", radix: 16)
  // expected-error@-1 {{Unresolved symbol 'Int(_:radix:)'}}

  #if NO_COMPILE
  @Implicit()
  var tux
  // expected-error@-1 {{Missing type; see compiler message. if it there is none, file a bug!}}
  #endif

  // expected-error@+3 {{'@Implicit' property wrapper must be outermost}}
  @Wrapper
  @Implicit
  var wrapped: Int = 5

  if Bool.random() {
    // expected-error@+2 {{Redundant type annotation}}}
    // expected-error@+1 {{'scope' must be a 'let' constant}}
    var scope: ImplicitScope = scope.nested()
    defer { scope.end() }

    scope = devil()
  }
}

// Different control statemenets
private func entry2() {
  // expected-error@+1 {{Unresolved requirements: Int16, Int32, Int64, Int8, UInt16, UInt32, UInt64, UInt8}}
  let scope = ImplicitScope()
  defer { scope.end() }

  if Bool.random() {
    @Implicit()
    var i: UInt8
  }

  if Bool.random() {
    @Implicit()
    var i: UInt16
  } else {
    @Implicit()
    var i: UInt32
  }

  if Bool.random() {
    @Implicit()
    var i: UInt64
  } else if Bool.random() {
    @Implicit()
    var i: Int8
  } else {
    @Implicit()
    var i: Int16
  }

  for _ in 0..<1 {
    @Implicit()
    var i: Int32
  }

  while Bool.random() {
    @Implicit()
    var i: Int64
  }
}

// MARK: Compile config

#if NO_COMPILE
private func entry3() {
  // expected-error@+1 {{Unresolved requirement: Int8}}
  let scope = ImplicitScope()
  defer { scope.end() }

  @Implicit()
  var i: Int8
}

private func entry3() {
  // expected-error@+1 {{Unresolved requirement: Int16}}
  let scope = ImplicitScope()
  defer { scope.end() }

  @Implicit()
  var i: Int16
}
#else
private func entry3() {
  // expected-error@+1 {{Unresolved requirement: Int32}}
  let scope = ImplicitScope()
  defer { scope.end() }

  @Implicit()
  var i: Int32
}
#endif

func `underscore variable name`() {
  let scope = ImplicitScope() // expected-error {{Unresolved requirement: Int}}
  defer { scope.end() }
  
  @Implicit()
  var _: Int = 42 // expected-error {{Anonymous implicit will not be saved to context}}
  
  @Implicit()
  var v1: Int
}

// expected-error@+2 {{'ImplicitScope' argument in function declaration must be wildcard. Possible variants are: '_: ImplicitScope' or '_ scope: ImplicitScope'}}
// expected-error@+1 {{Excess 'ImplicitScope' parameter in function declaration}}
private func f1(scope: ImplicitScope, _: ImplicitScope) {
  let scope = scope.nested()
  defer { scope.end() }

  @Implicit
  var i: Int = 4
}

private struct S1 {
  // expected-error@+2 {{Stored Implicit property cannot have initial value}}
  @Implicit()
  var foo: UInt8 = 5
  // expected-error@+1 {{'ImplicitScope' argument in function declaration must be wildcard. Possible variants are: '_: ImplicitScope' or '_ scope: ImplicitScope'}}
  init(scope: ImplicitScope) {
    let scope = scope.nested()
    defer { scope.end() }

    @Implicit
    var i: Int = 4
  }

  // expected-error@+1 {{'ImplicitScope' argument in function declaration must be wildcard or 'scope'; found: 'scoop'. Possible variants are: '_: ImplicitScope' or '_ scope: ImplicitScope'}}
  init(i: Int, _ scoop: ImplicitScope) {}
}

private class C1 {
  // expected-error@+1 {{Dynamic dispatch for functions with implicit scope is forbidden; class member functions must be final, or class must be final}}
  func f1(_: ImplicitScope) {}
  // expected-error@+1 {{Dynamic dispatch for functions with implicit scope is forbidden; replace 'class' with 'static'}}
  class func f2(_: ImplicitScope) {}
  // expected-error@+1 {{Dynamic dispatch for functions with implicit scope is forbidden; replace 'open' with 'public'}}
  open func f3(_: ImplicitScope) {}
}

private final class C2: C1 {
  // expected-error@+1 {{Dynamic dispatch for functions with implicit scope is forbidden; remove override keyword}}
  override func f1(_: ImplicitScope) {}
}

private protocol P1 {
  // expected-error@+1 {{Dynamic dispatch for functions with implicit scope is forbidden; remove 'scope' parameter}}
  func f1(_: ImplicitScope)
  func f2(a: Int)

  var v1: Int { get }

  #if NO_COMPILE
  // expected-error@+1 {{Dynamic dispatch for functions with implicit scope is forbidden; remove 'scope' parameter}}
  func f3(_: ImplicitScope)
  #endif
}

func devil<T>() -> T {
  fatalError()
}

@propertyWrapper
fileprivate struct Wrapper<T> {
  var wrappedValue: T

  init(wrappedValue: T) {
    self.wrappedValue = wrappedValue
  }
}

extension [Int] {
  // expected-error@+1 {{Using Implicits in extension of complex type, consider using free function or moving to extension with simple type}}
  fileprivate init(_: ImplicitScope) {
    @Implicit()
    var i: Int
    self.init()
  }
}

private func defers() throws {
  // defers with complex control flow are allowed
  if Bool.random() {
    defer { [].forEach { _ in } }
    try throwing()
  }

  // nested
  if Bool.random() {
    // expected-error@+1 {{'scope.end()' must be called before leaving the scope in defer block}}
    let scope = ImplicitScope()
    defer {
      defer {
        // expected-error@+1 {{'scope.end()' must be called in topmost scope in 'defer' block}}
        scope.end()
      }
      if Bool.random() {
        // expected-error@+1 {{'scope.end()' must be called in topmost scope in 'defer' block}}
        scope.end()
      }
    }
    try throwing(scope)
  }

  if Bool.random() {
    let scope = ImplicitScope()
    defer {
      // expected-error@+2 {{Unexpected statement in 'defer' block, only 'scope.end()' allowed}}
      @Implicit()
      var i: Int
      // expected-error@+1 {{Function declaration with scope parameter in defer block is forbidden}}
      func foo(_: ImplicitScope) {}
      // expected-error@+1 {{Closure with bag in defer block is not allowed}}
      let closure = { [implicits = testBagImplicits()] in
        // expected-error@+1 {{Unexpected statement in 'defer' block, only 'scope.end()' allowed}}
        let scope = ImplicitScope(with: implicits)
        // expected-error@+1 {{'scope.end()' must be called in topmost scope in 'defer' block}}
        defer { scope.end() }
        _ = 0
      }
      _ = closure
      scope.end()
    }
    try throwing(scope)
  }
  print(0)
}

func ignoresScopeIdentifiersInNonImplicitContexts() {
  let scope = ImplicitScope()
  defer { scope.end() }

  let notAnImplicitScope = 1
  notAnImplicitFunc(scope: notAnImplicitScope)
  if Bool.random() {
    let scope = 2
    notAnImplicitFunc(scope: scope)
  }
}

func notAnImplicitFunc(scope: Int) { _ = scope }

func throwing() throws {}
func throwing(_ scope: ImplicitScope) throws {}

private func testBagImplicits() -> Implicits {
  Implicits()
}
