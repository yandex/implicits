@_spi(Unsafe)
import Implicits

func withZeroArgsImplicits<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T {
  { body(ImplicitScope()) }
}

func withOneArgImplicits<T, A1>(_ body: @escaping (A1, ImplicitScope) -> T) -> (A1) -> T {
  { a1 in body(a1, ImplicitScope()) }
}

func withTwoArgsImplicits<T, A1, A2>(_ body: @escaping (A1, A2, ImplicitScope) -> T) -> (A1, A2) -> T {
  { a1, a2 in body(a1, a2, ImplicitScope()) }
}

func withOuterImplicits<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T {
  { body(ImplicitScope()) }
}

func withInnerImplicits<T, A1>(_ body: @escaping (A1, ImplicitScope) -> T) -> (A1) -> T {
  { a1 in body(a1, ImplicitScope()) }
}

func withBranchAImplicits<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T {
  { body(ImplicitScope()) }
}

func withBranchBImplicits<T, A1>(_ body: @escaping (A1, ImplicitScope) -> T) -> (A1) -> T {
  { a1 in body(a1, ImplicitScope()) }
}

func withBagImplicits<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T {
  { body(ImplicitScope()) }
}

func namedImplicitsBag() -> Implicits {
  Implicits()
}

func withOrphanImplicits<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T {
  { body(ImplicitScope()) }
}

func withDuplicateImplicits<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T {
  { body(ImplicitScope()) }
}
