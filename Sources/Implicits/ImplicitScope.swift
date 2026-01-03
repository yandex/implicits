// Copyright 2023 Yandex LLC. All rights reserved.

/// ImplicitScope is a RAII-like scope for implicit parameters.
///
/// It saves the current implicit context on initialization and restores it on `end()` call.
/// It also used in static analysis to determine which functions
/// use implicit parameters, so the scope paramter is needed everywhere where
/// implicit parameters are used.
///
/// Example:
/// ```
/// func foo() {
///   let scope = ImplicitScope()
///   defer { scope.end() }
///   @Implicit
///   let x = 42
///   if featureIsOn {
///     // Nesting scope so that we don't
///     // override the outer scope.
///     let scope = scope.nested()
///     defer { scope.end() }
///     @Implicit()
///     let x = 43
///     printX(scope) // prints 43
///   }
///   printX(scope) // prints 42
/// }
///
/// func printX(_ scope: ImplicitScope) {
///   @Implicit()
///   var x: Int
///   print(x)
/// }
/// ```
public struct ImplicitScope: Sendable {
  @usableFromInline
  var isRoot: Bool

  /// Creates a new scope with the given implicits.
  ///
  /// Defines top level scope, used when there is no scope
  /// to inherit from or you want to override the inherited
  /// scope from scratch.
  ///
  /// - Parameter implicits: The implicits to add to the scope.
  ///  Used in closures to capture the outer scope:
  ///  ```
  ///  let closure = { [implicits = closureImplicits()] in
  ///    let scope = ImplicitScope(with: implicits)
  ///    defer { scope.end() }
  ///    ...
  ///  }
  ///  ```
  @inlinable
  public init(
    with implicits: Implicits? = nil
  ) {
    self.init(with: implicits, isRoot: true)
  }

  @inlinable
  init(
    with implicits: Implicits? = nil,
    isRoot: Bool
  ) {
    self.isRoot = isRoot
    let store = isRoot ? RawStore.onRootScopeCreation() : RawStore.current()
    if let implicits {
      store.push(replacingCurrent: implicits.args)
    } else {
      store.push()
    }
  }

  /// Creates a nested scope with the given implicits.
  ///
  /// Defines nested scope, used when you want to add or override implicits
  /// in the current scope.
  ///
  @inlinable
  public func nested() -> Self {
    Self(with: nil, isRoot: false)
  }

  /// Ends the scope and restores state of the outer scope.
  @inlinable
  public func end() {
    let store = RawStore.current()
    store.pop()
    if isRoot {
      store.onRootScopeEnd()
    }
  }

  #if DEBUG
  /// Dump the current scope for debug.
  ///
  /// Examples:
  /// - Get parameters by key name
  ///   `(lldb) p ImplicitScope.dumpCurrent()[like: "telemetry"]`
  /// - Get all the parameters' key names
  ///   `(lldb) p ImplicitScope.dumpCurrent().keys`
  public static func dumpCurrent() -> DebugCollection {
    DebugCollection(entries: RawStore.current().dumpCurrentScope())
  }
  #endif
}

#if DEBUG
extension ImplicitScope {
  /// DebugCollection represents a collection of implicit parameters available
  /// in the scope in a way suitable for debug purposes.
  public struct DebugCollection: Collection {
    public typealias Element = (key: String, value: any Any, sourceLocation: SourceLocation)
    public typealias Index = Array<Element>.Index

    internal var entries: [Element]

    internal init(entries: [Element]) {
      self.entries = entries
    }

    /// Returns parameters whose keys contain the given substring.
    public subscript(like keyName: String) -> [Element] {
      let keyName = keyName.lowercased()
      return entries.filter { key, _, _ in
        key.lowercased().contains(keyName)
      }
    }

    /// Returns all the keys of the scope.
    public var keys: [String] {
      entries.map(\.key)
    }

    /// Returns a formatted string with locations for debugging.
    public var formatted: String {
      entries.map { key, value, location in
        "\(key): \(value) (defined at \(location))"
      }.joined(separator: "\n")
    }

    public func makeIterator() -> Array<Element>.Iterator {
      entries.makeIterator()
    }

    public var count: Int {
      entries.count
    }

    public var startIndex: Array<Element>.Index {
      entries.startIndex
    }

    public var endIndex: Array<Element>.Index {
      entries.endIndex
    }

    public func index(after i: Array<Element>.Index) -> Array<Element>.Index {
      entries.index(after: i)
    }

    public subscript(position: Array<Element>.Index) -> Element {
      _read {
        yield entries[position]
      }
    }
  }
}
#endif

/// Executes the given closure with a new implicit scope and ensures it's properly ended.
///
/// This is a convenience function that creates a new scope, passes it to the closure,
/// and automatically calls `end()` when the closure completes, even if an error is thrown.
///
/// Example:
/// ```
/// withScope { scope in
///   @Implicit
///   let x = 42
///   // ...
/// }
/// ```
///
/// - Parameter body: A closure that takes an ImplicitScope and returns a value.
/// - Returns: The value returned by the closure.
/// - Throws: Rethrows any error thrown by the closure.
@inlinable
public func withScope<T>(_ body: (ImplicitScope) throws -> T) rethrows -> T {
  let scope = ImplicitScope()
  defer { scope.end() }
  return try body(scope)
}

/// Executes the given closure with a new implicit scope initialized with an implicit bag.
///
/// It creates a new scope with the provided implicits, passes it to the closure,
/// and automatically calls `end()` when the closure completes, even if an error is thrown.
///
/// Example:
/// ```
/// class MyService {
///   let implicits = #implicits
///
///   init(_: ImplicitScope) {}
///
///   func doWork() {
///     withScope(with: implicits) { scope in
///       @Implicit
///       var x: Int
///       print(x)
///     }
///   }
/// }
/// ```
///
/// - Parameters:
///   - implicits: The implicit bag to initialize the scope with.
///   - body: A closure that takes an ImplicitScope and returns a value.
/// - Returns: The value returned by the closure.
/// - Throws: Rethrows any error thrown by the closure.
@inlinable
public func withScope<T>(
  with implicits: Implicits,
  _ body: (ImplicitScope) throws -> T
) rethrows -> T {
  let scope = ImplicitScope(with: implicits)
  defer { scope.end() }
  return try body(scope)
}

/// Executes the given closure with a nested implicit scope and ensures it's properly ended.
///
/// This is a convenience function that creates a nested scope from an existing scope,
/// passes it to the closure, and automatically calls `end()` when the closure completes,
/// even if an error is thrown. The nested scope inherits all implicits from the outer scope.
///
/// Example:
/// ```
/// let scope = ImplicitScope()
/// defer { scope.end() }
///
/// @Implicit
/// let x = 42
///
/// withScope(nesting: scope) { scope in
///   @Implicit
///   var x: Int // x == 42, inherited from outer scope
///   @Implicit
///   let y = 100 // y is only visible in nested scope
/// }
/// ```
///
/// - Parameters:
///   - outer: The outer scope to nest within.
///   - body: A closure that takes an ImplicitScope and returns a value.
/// - Returns: The value returned by the closure.
/// - Throws: Rethrows any error thrown by the closure.
@inlinable
public func withScope<T>(
  nesting outer: ImplicitScope,
  _ body: (ImplicitScope) throws -> T
) rethrows -> T {
  let scope = outer.nested()
  defer { scope.end() }
  return try body(scope)
}

// MARK: - Async Variants

/// Executes the given async closure with a new implicit scope and ensures it's properly ended.
///
/// This is a convenience function that creates a new scope, passes it to the async closure,
/// and automatically calls `end()` when the closure completes, even if an error is thrown.
///
/// Example:
/// ```
/// await withScope { scope in
///   @Implicit
///   let x = 42
///   await someAsyncWork(scope)
/// }
/// ```
///
/// - Parameter body: An async closure that takes an ImplicitScope and returns a value.
/// - Returns: The value returned by the closure.
/// - Throws: Rethrows any error thrown by the closure.
@available(iOS 13, macOS 10.15, watchOS 6, tvOS 13, *)
@inlinable
public func withScope<T>(_ body: (ImplicitScope) async throws -> T) async rethrows -> T {
  let scope = ImplicitScope()
  defer { scope.end() }
  return try await body(scope)
}

/// Executes the given async closure with a new implicit scope initialized with an implicit bag.
///
/// It creates a new scope with the provided implicits, passes it to the async closure,
/// and automatically calls `end()` when the closure completes, even if an error is thrown.
///
/// Example:
/// ```
/// class MyService {
///   let implicits = #implicits
///
///   init(_: ImplicitScope) {}
///
///   func doWork() async {
///     await withScope(with: implicits) { scope in
///       @Implicit
///       var x: Int
///       await someAsyncWork(scope)
///     }
///   }
/// }
/// ```
///
/// - Parameters:
///   - implicits: The implicit bag to initialize the scope with.
///   - body: An async closure that takes an ImplicitScope and returns a value.
/// - Returns: The value returned by the closure.
/// - Throws: Rethrows any error thrown by the closure.
@available(iOS 13, macOS 10.15, watchOS 6, tvOS 13, *)
@inlinable
public func withScope<T>(
  with implicits: Implicits,
  _ body: (ImplicitScope) async throws -> T
) async rethrows -> T {
  let scope = ImplicitScope(with: implicits)
  defer { scope.end() }
  return try await body(scope)
}

/// Executes the given async closure with a nested implicit scope and ensures it's properly ended.
///
/// This is a convenience function that creates a nested scope from an existing scope,
/// passes it to the async closure, and automatically calls `end()` when the closure completes,
/// even if an error is thrown. The nested scope inherits all implicits from the outer scope.
///
/// Example:
/// ```
/// let scope = ImplicitScope()
/// defer { scope.end() }
///
/// @Implicit
/// let x = 42
///
/// await withScope(nesting: scope) { scope in
///   @Implicit
///   var x: Int // x == 42, inherited from outer scope
///   await someAsyncWork(scope)
/// }
/// ```
///
/// - Parameters:
///   - outer: The outer scope to nest within.
///   - body: An async closure that takes an ImplicitScope and returns a value.
/// - Returns: The value returned by the closure.
/// - Throws: Rethrows any error thrown by the closure.
@available(iOS 13, macOS 10.15, watchOS 6, tvOS 13, *)
@inlinable
public func withScope<T>(
  nesting outer: ImplicitScope,
  _ body: (ImplicitScope) async throws -> T
) async rethrows -> T {
  let scope = outer.nested()
  defer { scope.end() }
  return try await body(scope)
}
