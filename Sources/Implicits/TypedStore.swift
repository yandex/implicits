// Copyright 2022 Yandex LLC. All rights reserved.

/// `TypedStore` is a typed wrapper over `RawStore`. It provides a typed
/// API for accessing values in the raw store.
///
///     let store = TypedStore.fromTSD()
///     let value = store[MyKey.self]
///
@usableFromInline
internal struct TypedStore {
  @usableFromInline
  internal var raw: RawStore

  @inlinable
  internal init(raw: RawStore) {
    self.raw = raw
  }

  /// Returns a typed store for current thread.
  @inlinable
  internal static func current() -> Self {
    .init(raw: .current())
  }

  @inlinable
  internal func value<Key: ImplicitKeyType>(
    for _: Key.Type
  ) -> StoreValue<Key> {
    .init(store: self)
  }

  /// Returns a value for the given key.
  /// - Parameter key: The key to look up.
  /// - Returns: The value for the given key.
  /// - Precondition: The store must contain a value for the given key
  ///   and it must be of the correct type.
  @inlinable
  internal subscript<Key: ImplicitKeyType>(_: Key.Type) -> Key.Value {
    get {
      measure(.typedStoreSubscriptGet) {
        guard let entry = raw[Key.id] else {
          Key.noValueFatalError()
        }
        return entry.value(as: Key.Value.self)
      }
    }

    nonmutating set {
      measure(.typedStoreSubscriptSet) {
        raw[Key.id] = Entry.make(newValue)
      }
    }
  }

  /// Returns a value for the given key.
  /// - Parameter key: Key specifier for the key to look up.
  /// - Returns: The value for the given key.
  /// - Precondition: The store must contain a value for the given key
  @inlinable
  internal subscript<Key: ImplicitKeyType>(_: KeySpecifier<Key>) -> Key.Value {
    get { self[Key.self] }
    nonmutating set { self[Key.self] = newValue }
  }

  /// Returns a value for the given key.
  /// - Parameter key: Type of the value to look up.
  /// - Returns: The value for the given key.
  /// - Precondition: The store must contain a value for the given key type
  @inlinable
  internal subscript<Key>(_: Key.Type) -> Key {
    get { self[TypeImplicitKey<Key>.self] }
    nonmutating set { self[TypeImplicitKey<Key>.self] = newValue }
  }
}

/// `StoreValue` is a wrapper over `TypedStore` with a defined key.
@usableFromInline
internal struct StoreValue<Key: ImplicitKeyType> {
  @usableFromInline
  internal typealias Value = Key.Value

  @usableFromInline
  internal var store: TypedStore

  @inlinable
  internal var value: Value {
    get {
      store[Key.self]
    }
    nonmutating set {
      store[Key.self] = newValue
    }
  }

  @inlinable
  internal init(store: TypedStore) {
    self.store = store
  }

  @inlinable
  internal static func current() -> Self {
    .init(store: .current())
  }
}

extension ImplicitKeyType {
  @usableFromInline
  internal static func noValueFatalError() -> Never {
    fatalError("No value for \(Self.self)")
  }
}
