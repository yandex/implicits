// Copyright 2022 Yandex LLC. All rights reserved.

/// Property wrapper that allows to pass and retrieve implicit arguments.
///
/// Generic parameters:
/// - Key: type that conforms to `ImplicitKeyType` and defines the key
/// and the type of the wrappedValue. Inferred based on usage, do not specify it explicitly.
///
/// If initial value is specified, puts this value to implicit context with inferred key.
/// If initial value is not specified, gets value from implicit context with inferred key.
/// Example of usage:
///
///       func printID() {
///         // Retrieve the value of the implicit argument
///         @Implicit(\.id)
///         var id
///         print(id)
///       }
///
///       // Declare the implicit argument
///       @Implicit(\.id)
///       var id = 123
///
///       // Pass the implicit argument to the function
///       printID()
///
@propertyWrapper
public struct Implicit<Key: ImplicitKeyType> {
  public typealias Value = Key.Value
  @usableFromInline
  internal typealias Store = StoreValue<Key>

  /// The value of the implicit argument.
  @inlinable
  public var wrappedValue: Value { _value }

  /// The value of the implicit argument.
  @inlinable
  public var value: Value { _value }

  /// The value of the implicit argument.
  @usableFromInline
  internal var _value: Value

  /// Creates an implicit argument with the specified key and value.
  /// - Parameter wrappedValue: The value of the implicit argument.
  /// - Parameter key: The key of the implicit argument.
  /// - Parameter scope: Scope to keep alive
  @inlinable
  public init(
    wrappedValue: Value, _: KeySpecifier<Key>,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) {
    Self.setValue(wrappedValue, fileID: fileID, line: line)
    self.init(value: wrappedValue)
  }

  /// Creates an implicit argument with the specified key and value.
  /// Here the key is not specified and inferred as `TypeImplicitKey<T>`
  /// - Parameter scope: Scope to keep alive
  @inlinable
  public init(
    _: KeySpecifier<Key>
  ) {
    self.init(value: Self.getValue())
  }

  /// Creates an implicit argument with the specified value.
  /// Here the key is not specified and inferred as `TypeImplicitKey<T>`
  /// - Parameter scope: Scope to keep alive
  @inlinable
  public init<T>(
    wrappedValue: T,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) where Key == TypeImplicitKey<T> {
    Self.setValue(wrappedValue, fileID: fileID, line: line)
    self.init(value: wrappedValue)
  }

  /// Retrieves the value of the implicit argument.
  /// Here the key is not specified and inferred as `TypeImplicitKey<T>`.
  /// - Parameter scope: Scope to keep alive
  @inlinable
  public init<T>() where Key == TypeImplicitKey<T> {
    self.init(value: Self.getValue())
  }

  /// Retrieves the value of the implicit argument.
  /// - Parameter key: The value type of the implicit argument.
  @inlinable
  public init<T>(
    _: T.Type
  ) where Key == TypeImplicitKey<T> {
    self.init(value: Self.getValue())
  }

  /// Retrieves the value of the implicit argument.
  /// - Parameter wrappedValue: The value of the implicit argument.
  /// - Parameter key: The value type of the implicit argument.
  @inlinable
  public init<T>(
    wrappedValue: T, _: T.Type,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) where Key == TypeImplicitKey<T> {
    Self.setValue(wrappedValue, fileID: fileID, line: line)
    self.init(value: wrappedValue)
  }

  @inlinable
  internal init(value: Value) {
    self._value = value
  }

  @inlinable
  static func getValue() -> Value {
    Store.current().value
  }

  @inlinable
  static func setValue(
    _ value: Value,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) {
    Store.current().setValue(value, fileID: fileID, line: line)
  }
}

extension Implicit {
  ///  Maps the value of the implicit argument to the value of another implicit argument
  ///  with the specified key.
  ///  - Parameter from: The `KeySpecifier` of the implicit argument to map from
  ///  - Parameter to: The `KeySpecifier` of the implicit argument to map to
  ///  - Parameter transform: The closure that maps the value of the implicit argument
  ///  to the value of another implicit argument.
  ///
  ///  Example of usage:
  ///  ```
  ///  Implicit.map(\.user, to: \.name) { $0.name }
  /// ```
  @inlinable
  public static func map<To: ImplicitKeyType>(
    _ from: KeySpecifier<Key>,
    to: KeySpecifier<To>,
    _ transform: (Key.Value) -> To.Value,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) {
    let store = TypedStore.current()
    store.setValue(transform(store[from]), for: to, fileID: fileID, line: line)
  }

  ///  Maps the value of the implicit argument to the value of another implicit argument
  ///  with the specified key.
  ///  - Parameter from: The value type of the implicit argument to map from
  ///  - Parameter to: The `KeySpecifier` of the implicit argument to map to
  ///  - Parameter transform: The closure that maps the value of the implicit argument
  ///  to the value of another implicit argument.
  ///
  ///  Example of usage:
  ///  ```
  ///  Implicit.map(User.self, to: \.name) { $0.name }
  /// ```
  @inlinable
  public static func map<From, To: ImplicitKeyType>(
    _ from: From.Type,
    to: KeySpecifier<To>,
    _ transform: (Key.Value) -> To.Value,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) where Key == TypeImplicitKey<From> {
    let store = TypedStore.current()
    store.setValue(transform(store[from]), for: to, fileID: fileID, line: line)
  }

  ///  Maps the value of the implicit argument to the value of another implicit argument
  ///  with the specified key.
  ///  - Parameter from: The `KeySpecifier` of the implicit argument to map from
  ///  - Parameter to: The value type of the implicit argument to map to
  ///  - Parameter transform: The closure that maps the value of the implicit argument
  ///  to the value of another implicit argument.
  ///
  ///  Example of usage:
  ///  ```
  ///  Implicit.map(\.user, to: String.self) { $0.name }
  /// ```
  @inlinable
  public static func map<To>(
    _ from: KeySpecifier<Key>,
    to: To.Type,
    _ transform: (Key.Value) -> To,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) {
    let store = TypedStore.current()
    store.setValue(transform(store[from]), for: to, fileID: fileID, line: line)
  }

  ///  Maps the value of the implicit argument to the value of another implicit argument
  ///  with the specified key.
  ///  - Parameter from: The value type of the implicit argument to map from
  ///  - Parameter to: The value type of the implicit argument to map to
  ///  - Parameter transform: The closure that maps the value of the implicit argument
  ///  to the value of another implicit argument.
  ///
  ///  Example of usage:
  ///  ```
  ///  Implicit.map(User.self, to: String.self) { $0.name }
  /// ```
  @inlinable
  public static func map<From, To>(
    _ from: From.Type,
    to: To.Type,
    _ transform: (Key.Value) -> To,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) where Key == TypeImplicitKey<From> {
    let store = TypedStore.current()
    store.setValue(transform(store[from]), for: to, fileID: fileID, line: line)
  }
}
