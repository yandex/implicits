// Copyright 2026 Yandex LLC. All rights reserved.

@usableFromInline
typealias Entry = BoxEntry

/// RawStore contract: an entry is made from a value of any type and gives the
/// value back as that type.
extension Entry {
  @inlinable
  static func make<T>(_ value: T) -> Entry {
    let entry = allocate(for: T.self)
    entry.withStorage { _ = $0.initializeMemory(as: T.self, to: value) }
    return entry
  }

  /// - Precondition: `T` is the type the entry was made with.
  @inlinable
  func value<T>(as _: T.Type) -> T {
    assert(header == T.self, "\(T.self) is not the stored \(header)")
    return withStorage { $0.load(as: T.self) }
  }

  #if DEBUG
  var anyValue: any Any { value(as: header) }
  #endif
}

/// One class for values of every type. The header holds the value's type,
/// which `deinit` needs to destroy the value; the elements hold the value.
///
/// The element type is `SIMD2<UInt64>` only for its 16-byte size and alignment:
/// a value is stored in as many elements as cover its size.
@usableFromInline
final class BoxEntry: ManagedBuffer<Any.Type, SIMD2<UInt64>> {
  @inlinable
  static func allocate<T>(for _: T.Type) -> BoxEntry {
    // Swift's maximum type alignment is 16:
    // https://github.com/swiftlang/swift/blob/main/include/swift/ABI/MetadataValues.h#L149-L150
    precondition(MemoryLayout<T>.alignment <= 16)
    let slots = (MemoryLayout<T>.size + 15) / 16
    let entry = create(minimumCapacity: slots) { _ in T.self }
    return unsafeDowncast(entry, to: BoxEntry.self)
  }

  @inlinable
  func withStorage<R>(_ body: (UnsafeMutableRawPointer) -> R) -> R {
    withUnsafeMutablePointerToElements { body(UnsafeMutableRawPointer($0)) }
  }

  // The type is read through `withUnsafeMutablePointers` because the `header`
  // property would add a run-time exclusivity check to every destroyed entry.
  @inlinable
  deinit {
    withUnsafeMutablePointers { type, value in
      func destroy<T>(_: T.Type) {
        UnsafeMutableRawPointer(value)
          .assumingMemoryBound(to: T.self)
          .deinitialize(count: 1)
      }
      destroy(type.pointee)
    }
  }
}
