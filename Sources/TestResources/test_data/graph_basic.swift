import Implicits

struct Dep1 {}
struct Dep2 {}
struct Dep3 {}

func topLevel1() {
  let scope = ImplicitScope()
  defer { scope.end() }

  @Implicit()
  var d1: Dep1 = Dep1()

  @Implicit
  var d2: Dep2 = Dep2()

  @Implicit
  var d3: Dep3 = Dep3()

  if Bool.random() {
    let scope = scope.nested()
    defer { scope.end() }

    @Implicit
    var d4: Dep3 = Dep3()

    lowest(scope)
  }

  intermediate1(scope)
}

func topLevel2() {
  let scope = ImplicitScope()
  defer { scope.end() }

  @Implicit()
  var d1: Dep1 = Dep1()

  @Implicit
  var d2: Dep2 = Dep2()
}

func topLevel3() {
  let scope = ImplicitScope() // expected-error {{Unresolved requirement: Dep3}}
  defer { scope.end() }

  @Implicit()
  var d1: Dep1 = Dep1()

  @Implicit
  var d2: Dep2 = Dep2()

  intermediate1(scope)
}

func intermediate1(_ scope: ImplicitScope) {
  lowest(scope)
}

func intermediate2(_ scope: ImplicitScope) {
  let scope = scope.nested()
  defer { scope.end() }

  @Implicit
  var d1: Dep3 = Dep3()

  lowest(scope)
}

func lowest(_: ImplicitScope) {
  @Implicit()
  var dep1: Dep1

  @Implicit()
  var dep2: Dep2

  @Implicit()
  var dep3: Dep3
}
