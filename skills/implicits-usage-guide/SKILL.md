---
name: implicits-usage-guide
description: Swift Implicits library — use for code with `@Implicit`, `ImplicitScope`, `#withImplicits`, `#implicits`, `withScope`, or a `Package.swift` depending on the `implicits` package.
---

# Implicits Usage Guide

Implicits is a Swift library for implicit parameter passing through call stacks — eliminates "parameter drilling" (passing the same arguments through many function layers). Similar in spirit to implicit parameters in Scala or context receivers in Kotlin.

## Core Pattern

```swift
func start() {
  let scope = ImplicitScope()
  defer { scope.end() }
  @Implicit var network = NetworkService()  // declare
  process(scope)
}

func process(_ scope: ImplicitScope) { fetch(scope) }

func fetch(_ scope: ImplicitScope) {
  @Implicit var network: NetworkService  // retrieve
  network.request()
}
```

**Rules:**
- `ImplicitScope` — last argument, no parameter label
- Always `defer { scope.end() }` after creating a scope
- Declaration: `@Implicit var x = value` (with initializer)
- Retrieval: `@Implicit var x: Type` (no initializer, explicit type)
- Missing implicit = compile-time error

## Keys: Type-Based vs Named

**Type-based (default)** — the type itself is the key:
```swift
@Implicit var network: NetworkService
```

**Named keys** — use when type alone doesn't explain meaning:
```swift
extension ImplicitsKeys {
  static let guestMode = Key<Bool>()
}

@Implicit(\.guestMode) var guest = true   // declare
@Implicit(\.guestMode) var isGuest: Bool  // retrieve
```

## Nested Scopes

Child scope inherits parent values, can override or add new (retrieval picks nearest):
```swift
func inner(_ outer: ImplicitScope) async {
  let scope = outer.nested()
  defer { scope.end() }

  @Implicit var extra = ExtraService()
  await extra.doWork(scope)
}
```

Async code is supported.

## Closures

Closures don't inherit scope automatically. Use `#withImplicits` to capture implicits used in the body:

```swift
fetchData(completion: #withImplicits { result, scope in
  @Implicit var handler: ResultHandler
  handler.process(result)
})
```

Effects (`async`/`throws`) are inferred. `@MainActor` is preserved on the result; other global actors aren't — use named wrappers for those.

`#withImplicits` takes an `isolation:` parameter: `.mainActor` selects the `@MainActor` variant explicitly when the compiler or the analyzer can't choose it.

For full details on `#withImplicits`, named wrappers, capture lists, and `#implicits`, see `docs/closures.md` in the Implicits repo.

## Factory Pattern

Store context for later use:
```swift
class Component {
  let implicits = #implicits

  init(_ scope: ImplicitScope) {}

  func createChild() -> Child {
    withScope(with: implicits) { scope in
      Child(scope)
    }
  }
}
```

## Stored Properties in Types

`@Implicit` works as a stored property — the type needs a scope in its initializer:
```swift
struct View {
  @Implicit var theme: Theme

  init(_ scope: ImplicitScope) {}
}
```

## `withScope` Alternative

`withScope` handles scope lifecycle when indentation isn't a problem and the body is small:
```swift
withScope { scope in ... }                    // root scope
withScope(with: implicits) { scope in ... }   // from captured implicits
withScope(nesting: outer) { scope in ... }    // nested scope
```

## Build-Time Analysis Setup

Add the plugin to `Package.swift`:
```swift
.target(
  name: "MyApp",
  dependencies: [.product(name: "Implicits", package: "implicits")],
  plugins: [.plugin(name: "ImplicitsAnalysisPlugin", package: "implicits")]
)
```

**Plugin graph rule:** Every module on the path from your code to the Implicits library must have the plugin. Example: if `App → FeatureA → FeatureB → Implicits` and FeatureB uses implicits, then FeatureB and FeatureA both need the plugin (App too if it uses implicits).

## Static Analysis Constraints

1. **Type annotations may be needed** for type-based keys — the analyzer infers when possible.
2. **No dynamic dispatch** — the analyzer can't track through protocol-typed values or closures stored in properties. Static calls only.
