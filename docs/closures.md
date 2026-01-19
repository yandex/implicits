# Working with Closures

Closures in Swift capture values from their surrounding context, but they can't automatically capture the implicit scope from the call stack. This guide covers different approaches for passing implicits through closures.

## The Problem

When you create a closure, the implicit context from the call stack isn't automatically available:

```swift
class FeedComponent {
  var postFactory: () -> Post

  init(_ scope: ImplicitScope) {
    // Problem: when postFactory is called later,
    // the original implicit scope may no longer exist
    self.postFactory = {
      return Post(???) // What scope to use?
    }
  }
}
```

The solution is to capture the implicit context at definition time and restore it when the closure executes.

## `#withImplicits` Macro (Recommended)

The recommended way to create closures that capture implicit context.

### Basic Usage

```swift
class FeedComponent {
  var postFactory: () -> Post

  init(_ scope: ImplicitScope) {
    self.postFactory = #withImplicits { scope in
      return Post(scope)
    }
  }
}
```

The macro captures implicits at definition time and restores them when called. The `scope` parameter is automatically provided.

### With Parameters

When your closure needs additional parameters, list them before `scope`:

```swift
// One parameter
downloadImage(url: avatarURL, completion: #withImplicits { image, scope in
  @Implicit var filters: FilterApplier
  imageView.image = filters.applyBlur(image)
})

// Multiple parameters
fetchData(completion: #withImplicits { data, response, scope in
  @Implicit var parser: DataParser
  processResult(parser.parse(data), scope)
})
```

The `scope` parameter is always last.

> **Note:** Since the closure must be wrapped in the macro, you can't use trailing closure syntax for the outer function. Instead of `fetch { ... }`, you write `fetch(completion: #withImplicits { ... })`.

### Async and Throws

The macro automatically infers `async` and `throws` from the closure body:

```swift
#withImplicits { scope async in ... }
#withImplicits { scope throws in ... }
#withImplicits { scope async throws in ... }
```

## Named Wrappers: `with${Name}Implicits`

If your project prefers not to use macros, you can use wrapper functions that follow a naming convention. The analyzer recognizes functions matching `with${Name}Implicits`:

```swift
class FeedComponent {
  var postFactory: () -> Post

  init(_ scope: ImplicitScope) {
    self.postFactory = withPostFactoryImplicits { scope in
      return Post(scope)
    }
  }
}

// With parameters
let onImageLoaded = withImageImplicits { (image: UIImage, scope) in
  @Implicit var filters: FilterApplier
  imageView.image = filters.applyBlur(image)
}
```

### Naming Requirements

Names must be **unique within the module**. The name serves to distinguish wrappers from each other:

```swift
// Each wrapper needs a unique name
let closure1 = withFirstImplicits { scope in ... }
let closure2 = withSecondImplicits { scope in ... }

// Error: duplicate name
let closure3 = withFirstImplicits { scope in ... } // Conflict!
```

## `#implicits` Macro

The `#implicits` macro captures implicit context as a stored value. While primarily used for factory patterns (see the [Factory Pattern](../README.md#factory-pattern) section in the README), it can also be used with closures:

```swift
class FeedComponent {
  init(_ scope: ImplicitScope) {
    self.postFactory = {
      [implicits = #implicits] in
      let scope = ImplicitScope(with: implicits)
      defer { scope.end() }
      return Post(scope)
    }
  }
}
```

This is more verbose than `#withImplicits`.

## Named Bag Functions

For capturing implicits in closures without macros, define a named bag function:

```swift
// Define (analyzer generates implementation)
func myImplicitsBag() -> Implicits {
  fatalError("Analyzer generates implementation")
}

// Use in closure capture
self.postFactory = {
  [implicits = myImplicitsBag()] in
  let scope = ImplicitScope(with: implicits)
  defer { scope.end() }
  return Post(scope)
}
```

## When to Use What

Use `#withImplicits` for closures. If your project prefers to avoid macros, use `with${Name}Implicits` instead.

The `#implicits` capture pattern and named bag functions are more verbose alternatives that are rarely needed for closures.
