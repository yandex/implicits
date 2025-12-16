# Implicits

[![CI](https://github.com/yandex/implicits/actions/workflows/ci.yml/badge.svg)](https://github.com/yandex/implicits/actions/workflows/ci.yml)
![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-F05138.svg)
![macOS 11+](https://img.shields.io/badge/macOS-11+-007AFF.svg)
![iOS 14+](https://img.shields.io/badge/iOS-14+-007AFF.svg)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A Swift library for implicit parameter passing through call stacks. Eliminate parameter drilling and simplify dependency injection with compile-time safety.

## Table of Contents

- [Installation](#installation)
- [The Problem](#the-problem)
- [The Solution](#the-solution)
- [Usage Guide](#usage-guide)
- [Build-Time Analysis](#build-time-analysis)
- [Runtime Debugging](#runtime-debugging)
- [Alternatives](#alternatives)
- [Related Concepts](#related-concepts)
- [Contributing](#contributing)

## Installation

Add Implicits to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yandex/implicits", from: "1.0.0"),
]
```

Then add the library to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [.product(name: "Implicits", package: "implicits")],
    plugins: [.plugin(name: "ImplicitsAnalysisPlugin", package: "implicits")]
)
```

The `ImplicitsAnalysisPlugin` performs static analysis at build time to verify that all implicit parameters are properly provided through the call chain.

## The Problem

Consider a simple shopping scenario where we need to pass payment details through multiple function layers:

```swift
func goShopping(wallet: Wallet, card: DiscountCard) {
  buyGroceries(wallet: wallet, card: card)
  buyClothes(wallet: wallet, card: card)
  buyCoffee(wallet: wallet, card: card)
}

func buyGroceries(wallet: Wallet, card: DiscountCard) {
  pay(50, wallet: wallet, card: card)
}

func buyClothes(wallet: Wallet, card: DiscountCard) {
  pay(200, wallet: wallet, card: card)
}

func buyCoffee(wallet: Wallet, card: DiscountCard) {
  pay(5, wallet: wallet, card: card)
}

func pay(_ price: Int, wallet: Wallet, card: DiscountCard) {
  wallet.charge(price * (1 - card.discount))
}
```

This pattern, known as parameter drilling, requires passing the same arguments through every layer of the call stack, even when intermediate functions don't use them directly. In this simple example the savings may seem modest, but imagine dozens of parameters flowing through many layers — the boilerplate adds up quickly.

## The Solution

With Implicits, you declare values once and access them anywhere in the call stack:

```swift
func goShopping(_ scope: ImplicitScope) {
  buyGroceries(scope)
  buyClothes(scope)
  buyCoffee(scope)
}

func buyGroceries(_ scope: ImplicitScope) { pay(50, scope) }
func buyClothes(_ scope: ImplicitScope) { pay(200, scope) }
func buyCoffee(_ scope: ImplicitScope) { pay(5, scope) }

func pay(_ price: Int, _: ImplicitScope) {
  @Implicit var wallet: Wallet
  @Implicit var card: DiscountCard
  wallet.charge(price * (1 - card.discount))
}

// Usage
let scope = ImplicitScope()
defer { scope.end() }

@Implicit var wallet = Wallet(balance: 500)
@Implicit var card = DiscountCard(discount: 0.1)
goShopping(scope)
```

> **Note:** Due to Swift's current limitations, a lightweight `ImplicitScope` object must be passed through the call stack. However, the actual data (`wallet`, `card`) doesn't need to be passed — it's accessed implicitly via `@Implicit`.

## Usage Guide

Implicit arguments behave like local variables that are accessible throughout the call stack. They follow standard Swift scoping rules and lifetime management.

#### Understanding Scopes

Just like regular Swift variables have their lifetime controlled by lexical scope:

```swift
do {
  let a = 1
  do {
    let a = "foo" // shadows outer 'a'
    let b = 2
  }
  // 'a' is back to being an integer
  // 'b' is out of scope
}
```

Implicit variables follow the same pattern, but their scope is managed by `ImplicitScope` objects. Always use `defer` to guarantee proper cleanup:

```swift
func appDidFinishLaunching() {
  let scope = ImplicitScope()
  defer { scope.end() }

  // Declare dependencies as implicit
  @Implicit
  var network = NetworkService()

  @Implicit
  var database = DatabaseService()

  // Components can now access these dependencies
  @Implicit
  let search = SearchComponent(scope)

  @Implicit
  let feed = FeedComponent(scope)

  @Implicit
  let profile = ProfileComponent(scope)

  let app = App(scope)
  app.start()
}
```

In this example, we establish a dependency injection container where services are available to all components without explicit passing.

#### Nested Scopes

Sometimes you need to add local implicit arguments without polluting the parent scope:

```swift
class SearchComponent {
  // Access implicit from parent scope
  @Implicit()
  var databaseService: DatabaseService

  init(_ scope: ImplicitScope) {
    // Create a nested scope for local implicits
    let scope = scope.nested()
    defer { scope.end() }

    // This implicit is only available in this scope
    @Implicit
    var imageService = ImageService(scope)

    self.suggestionsService = SuggestionsService(scope)
  }
}
```

**Key points:**
- Use `nested()` when adding new implicit arguments
- Parent scope implicits remain accessible
- Nested implicits don't leak to parent scope

#### Working with Closures

Closures require special handling to capture implicit context:

```swift
class FeedComponent {
  init(_ scope: ImplicitScope) {
    // Using the #implicits macro (recommended)
    self.postFactory = {
      [implicits = #implicits] in
      let scope = ImplicitScope(with: implicits)
      defer { scope.end() }
      return Post(scope)
    }
  }
}
```

The `#implicits` macro captures the necessary implicit arguments. The analyzer detects which implicits are needed and generates the appropriate capture list.

#### Factory Pattern

When creating factory methods that need access to implicit dependencies:

```swift
class ProfileComponent {
  // Store implicit context at instance level
  let implicits = #implicits

  @Implicit()
  var networkService: NetworkService

  @Implicit()
  var searchComponent: SearchComponent

  init(_ scope: ImplicitScope) {}

  func makeScreen() -> Screen {
    // Create new scope with stored context
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }

    return Screen(scope)
  }
}
```

This pattern allows factory methods to access dependencies available during initialization.

#### Custom Keys for Multiple Values

By default, Implicits uses the **type itself as the key**. But what if you need multiple values of the same type?

```swift
extension ImplicitsKeys {
  // Define a unique key for a specific Bool variable
  static let guestModeEnabled =
    Key<ObservableVariable<Bool>>()
}

class ProfileComponent {
  let implicits = #implicits

  init(_ scope: ImplicitScope) {}

  func makeProfileUI() -> ProfileUI {
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }

    // Type-based key (default)
    @Implicit()
    var db: DatabaseService

    // Named key for specific semantic meaning
    @Implicit(\.guestModeEnabled)
    var guestModeEnabled = db.settings.guestModeEnabled

    return ProfileUI(scope)
  }
}
```

#### Key Selection Guidelines

Choose your key strategy based on semantics:

```swift
// Type key: Only one instance makes sense
@Implicit()
var networkService: NetworkService

// Type key: Singleton service
@Implicit()
var screenManager: ScreenManager

// Named key provides clarity when type would be ambiguous
@Implicit(\.guestModeEnabled)
var guestModeEnabled: ObservableVariable<Bool>

@Implicit(\.darkModeEnabled)
var darkModeEnabled: ObservableVariable<Bool>
```

#### Transforming Implicits with `map`

Need to derive one implicit from another? Use the `map` function:

```swift
class App {
  @Implicit()
  var databaseService: DatabaseService

  init(_ scope: ImplicitScope) {
    let scope = scope.nested()
    defer { scope.end() }

    // Transform DatabaseService → GuestStorage
    Implicit.map(DatabaseService.self, to: \.guestStorage) {
      GuestStorage($0)
    }

    // Now GuestStorage is available as an implicit
    self.guestMode = GuestMode(scope)
  }
}
```

This is equivalent to manually creating the derived implicit.

## Build-Time Analysis

The analyzer tracks implicit dependencies at compile time, generating interface files that propagate through your module dependency graph. This provides type safety and IDE integration.

### SPM Plugin Integration

Enable `ImplicitsAnalysisPlugin` for each target that uses Implicits:

```swift
.target(
    name: "MyModule",
    dependencies: [.product(name: "Implicits", package: "implicits")],
    plugins: [.plugin(name: "ImplicitsAnalysisPlugin", package: "implicits")]
)
```

The plugin generates `<Module>.implicitinterface` describing which functions require which implicits. This enables cross-module analysis:

```
ModuleA                        ModuleB (depends on A)
┌─────────────────────┐        ┌──────────────────────┐
│ func fetch(_ scope) │        │ func load(_ scope) { │
│   @Implicit network │        │   fetch(scope)       │
└─────────┬───────────┘        └──────────────────────┘
          │                               ▲
          ▼                               │ reads
   A.implicitinterface ───────────────────┘
   "fetch requires NetworkService"
```

When ModuleB calls `fetch(scope)`, the analyzer reads `A.implicitinterface` to discover that `fetch` requires `NetworkService`.

**Important:** All intermediate modules that depend on `Implicits` must have the plugin enabled:

```
App → FeatureModule → CoreModule → Implicits
       (plugin ✓)      (plugin ✓)
```

If any module in the chain is missing the plugin, downstream builds will fail trying to read its non-existent interface file.

### Limitations

Since the analyzer works at the syntax level, there are some constraints to be aware of:

**1. No Dynamic Dispatch**
- Protocols, closures, and overridable methods can't propagate implicits
- Use concrete types and final classes where possible

**2. Unique Function Names Required**
- Can't have multiple functions with the same name using implicits
- The analyzer can't resolve overloads

**3. Explicit Type Annotations**
- Type inference is limited for type-based keys
- Named keys include type information

```swift
// Type can't be inferred
@Implicit
var networkService = services.network

// Explicit type annotation
@Implicit
var networkService: NetworkService = services.network

// Type inference works with initializers
@Implicit
var networkService = NetworkService()

// Named keys don't need type annotation
@Implicit(\.networkService)
var networkService = services.network
```

## Runtime Debugging

In DEBUG builds, Implicits provides powerful debugging tools to inspect your implicit context at runtime.

#### Viewing All Implicits

At any breakpoint, add this expression to Xcode's variables view:
```swift
ImplicitScope.dumpCurrent()
```
💡 **Tip:** Enable "Show in all stack frames" for complete visibility

#### LLDB Commands

**List all available keys:**
```shell
p ImplicitScope.dumpCurrent().keys
```

Example output:
```
([String]) 4 values {
  [0] = "(extension in MyApp):Implicits.ImplicitsKeys._DarkModeEnabledTag"
  [1] = "(extension in MyApp):Implicits.ImplicitsKeys._AnalyticsEnabledTag"
  [2] = "MyApp.NetworkService"
  [3] = "MyApp.DatabaseService"
}
```

**Search for specific implicits (case-insensitive):**
```shell
p ImplicitScope.dumpCurrent()[like: "network"]
```

Example output:
```
([Implicits.ImplicitScope.DebugCollection.Element]) 1 value {
  [0] = {
    key = "MyApp.NetworkService"
    value = <NetworkService instance>
  }
}
```

## Alternatives

Other dependency injection solutions for Swift:

- [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) — A dependency management library inspired by SwiftUI's environment
- [needle](https://github.com/uber/needle) — Compile-time safe dependency injection for iOS and macOS

## Related Concepts

Similar patterns in other languages:

- **Scala** — `given`/`using` (formerly implicit parameters)
- **Kotlin** — Context receivers

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## License

Apache 2.0. See [LICENSE](LICENSE) for details.
