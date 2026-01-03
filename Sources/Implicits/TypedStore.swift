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
    measure(.typedStoreSubscriptGet) {
      guard let entry = raw[Key.id] else {
        Key.noValueFatalError()
      }
      return unsafeDowncast(entry, to: EntryConcrete<Key.Value>.self).value
    }
  }

  /// Returns a value for the given key.
  /// - Parameter key: Key specifier for the key to look up.
  /// - Returns: The value for the given key.
  /// - Precondition: The store must contain a value for the given key
  @inlinable
  internal subscript<Key: ImplicitKeyType>(_: KeySpecifier<Key>) -> Key.Value {
    self[Key.self]
  }

  /// Returns a value for the given key.
  /// - Parameter key: Type of the value to look up.
  /// - Returns: The value for the given key.
  /// - Precondition: The store must contain a value for the given key type
  @inlinable
  internal subscript<Key>(_: Key.Type) -> Key {
    self[TypeImplicitKey<Key>.self]
  }

  @inlinable
  internal func setValue<Key: ImplicitKeyType>(
    _ value: Key.Value,
    for _: Key.Type,
    fileID: StaticString,
    line: UInt
  ) {
    measure(.typedStoreSetValue) {
      #if DEBUG
      let location = SourceLocation(fileID: fileID, line: line)
      raw[Key.id] = EntryConcrete(value: value, sourceLocation: location) as EntryAbstract
      #else
      raw[Key.id] = EntryConcrete(value: value) as EntryAbstract
      #endif
    }
  }

  @inlinable
  internal func setValue<Key: ImplicitKeyType>(
    _ value: Key.Value,
    for _: KeySpecifier<Key>,
    fileID: StaticString,
    line: UInt
  ) {
    setValue(value, for: Key.self, fileID: fileID, line: line)
  }

  @inlinable
  internal func setValue<T>(
    _ value: T,
    for _: T.Type,
    fileID: StaticString,
    line: UInt
  ) {
    setValue(value, for: TypeImplicitKey<T>.self, fileID: fileID, line: line)
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
    store[Key.self]
  }

  @inlinable
  internal init(store: TypedStore) {
    self.store = store
  }

  @inlinable
  internal static func current() -> Self {
    .init(store: .current())
  }

  @inlinable
  internal func setValue(
    _ newValue: Value,
    fileID: StaticString,
    line: UInt
  ) {
    store.setValue(newValue, for: Key.self, fileID: fileID, line: line)
  }
}

/// A type-erased wrapper over an implicit value.
///
/// Allows storing the value in `RawStore` and efficiently downcasting back to its original type.
@usableFromInline
final class EntryConcrete<T>: EntryAbstract {
  @usableFromInline
  var value: T

  #if DEBUG
  @inlinable
  init(value: T, sourceLocation: SourceLocation) {
    self.value = value
    super.init(sourceLocation: sourceLocation)
  }
  #else
  @inlinable
  init(value: T) {
    self.value = value
  }
  #endif

  @inlinable
  deinit {}

  #if DEBUG
  @inlinable
  override var anyValue: any Any { value }
  #endif
}

extension ImplicitKeyType {
  @usableFromInline
  internal static func noValueFatalError() -> Never {
    fatalError("No value for \(Self.self)")
  }
}
