# Implicits

[![CI](https://github.com/yandex/implicits/actions/workflows/ci.yml/badge.svg)](https://github.com/yandex/implicits/actions/workflows/ci.yml)
![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-F05138.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13+-007AFF.svg)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A Swift library for implicit parameter passing through call stacks, similar to implicit parameters in Scala or context receivers in Kotlin.

## Requirements

- Swift 6.2+
- macOS 13+

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
    dependencies: ["Implicits"],
    plugins: ["ImplicitsAnalysisPlugin"]  // Compile-time validation
)
```

The `ImplicitsAnalysisPlugin` performs static analysis at build time to verify that all implicit parameters are properly provided through the call chain.

### The Problem

Consider a simple shopping simulation where we need to pass payment details through multiple function layers:

```swift
func goShopping(money: Money, discountCard: DiscountCard) {
  goToGroceryStore(money: money, discountCard: discountCard)
  goToClothesStore(money: money, discountCard: discountCard)
}

func goToGroceryStore(money: Money, discountCard: DiscountCard) {
  pay(money: money, discountCard: discountCard)
}

func goToClothesStore(money: Money, discountCard: DiscountCard) {
  pay(money: money, discountCard: discountCard)
}

func pay(money: Money, discountCard: DiscountCard) {
  money.amount -= 100 * (1 - discountCard.discount)
}

// Usage
goShopping(
  money: Money(amount: 1000),
  discountCard: DiscountCard(discount: 0.05)
)
```

This pattern, known as parameter drilling, requires passing the same arguments through every layer of the call stack, even when intermediate functions don't use them. This creates unnecessary coupling and makes refactoring more difficult.

### The Solution

With Implicits, you declare values once and access them anywhere in the call stack without explicit parameter passing:

```swift
func goShopping(_ scope: ImplicitScope) {
  goToGroceryStore(scope)
  goToClothesStore(scope)
}

func goToGroceryStore(_ scope: ImplicitScope) { pay(scope) }
func goToClothesStore(_ scope: ImplicitScope) { pay(scope) }

func pay(_: ImplicitScope) {
  // Access money and discountCard implicitly — no parameters needed!
  @Implicit var money: Money
  @Implicit var discountCard: DiscountCard
  money.amount -= 100 * (1 - discountCard.discount)
}

// Usage
let scope = ImplicitScope()
defer { scope.end() }

@Implicit var money = Money(amount: 1000)
@Implicit var discountCard = DiscountCard(discount: 0.05)
goShopping(scope)
```

> **Note:** Due to Swift's current limitations, a lightweight `ImplicitScope` object must be passed through the call stack. However, the actual data (`money`, `discountCard`) doesn't need to be passed — it's accessed implicitly via `@Implicit`.

### Usage Guide

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
  let omnibox = OmniboxComponent(scope)

  @Implicit
  let webContents = WebContentsComponent(scope)

  @Implicit
  let tabs = TabsComponent(scope)

  let browser = Browser(scope)
  browser.start()
}
```

In this example, we establish a dependency injection container where services are available to all components without explicit passing.

#### Nested Scopes

Sometimes you need to add local implicit arguments without polluting the parent scope:

```swift
class OmniboxComponent {
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

    self.thumbnailsService = ThumbnailsService(scope)
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
class WebContentsComponent {
  init(_ scope: ImplicitScope) {
    // Using the #implicits macro (recommended)
    self.webContentFactory = {
      [implicits = #implicits] in
      let scope = ImplicitScope(with: implicits)
      defer { scope.end() }
      return WebContent(scope)
    }
  }
}
```

The `#implicits` macro captures the necessary implicit arguments. The analyzer detects which implicits are needed and generates the appropriate capture list.

#### Factory Pattern

When creating factory methods that need access to implicit dependencies:

```swift
class TabsComponent {
  // Store implicit context at instance level
  let implicits = #implicits
  
  @Implicit()
  var networkService: NetworkService
  
  @Implicit()
  var omniboxComponent: OmniboxComponent

  init(_ scope: ImplicitScope) {}

  func makeTab() -> Tab {
    // Create new scope with stored context
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }
    
    return Tab(scope)
  }
}
```

This pattern allows factory methods to access dependencies available during initialization.

#### Custom Keys for Multiple Values

By default, Implicits uses the **type itself as the key**. But what if you need multiple values of the same type?

```swift
extension ImplicitsKeys {
  // Define a unique key for a specific Bool variable
  static let incognitoModeEnabled = 
    Key<ObservableVariable<Bool>>()
}

class TabsComponent {
  let implicits = #implicits
  
  init(_ scope: ImplicitScope) {}
  
  func makeTabsUI() -> TabsUI {
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }

    // Type-based key (default)
    @Implicit()
    var db: DatabaseService

    // Named key for specific semantic meaning
    @Implicit(\.incognitoModeEnabled)
    var incognitoModeEnabled = db.incognitoMode.enabled

    return TabsUI(scope)
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
var tabManager: TabManager

// Named key provides clarity when type would be ambiguous
@Implicit(\.incognitoModeEnabled)
var incognitoModeEnabled: ObservableVariable<Bool>

@Implicit(\.darkModeEnabled)
var darkModeEnabled: ObservableVariable<Bool>
```

#### Transforming Implicits with `map`

Need to derive one implicit from another? Use the `map` function:

```swift
class Browser {
  @Implicit()
  var databaseService: DatabaseService

  init(_ scope: ImplicitScope) {
    let scope = scope.nested()
    defer { scope.end() }

    // Transform DatabaseService → IncognitoStorage
    Implicit.map(DatabaseService.self, to: \.incognitoStorage) {
      IncognitoStorage($0)
    }

    // Now IncognitoStorage is available as an implicit
    self.incognitoBrowser = IncognitoBrowser(scope)
  }
}
```

This is equivalent to manually creating the derived implicit.

### Build-Time Analysis

The analyzer tracks implicit dependencies at compile time, generating interface files that propagate through your module dependency graph. This provides type safety and IDE integration.

#### ⚠️ Current Limitations

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

### Runtime Debugging

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

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

### License

Apache 2.0. See [LICENSE](LICENSE) for details.
