// Copyright 2024 Yandex LLC. All rights reserved.

import Foundation
import Testing

@_spi(Testing) import ImplicitsTool

struct SerializationTests {
  @Test func integers() {
    check(UInt8.min)
    check(UInt8(13))
    check(UInt8.max)

    check(Int32.max)
    check(Int32.min)
    check(Int32(0))
    check(Int32(42 << 24))
    check(Int32(-1_300_000))
  }

  @Test func strings() {
    check("")
    check("Hello, world!")
    check("🚀")
  }

  @Test func arrays() {
    check([Int32]())
    check([Int32(-5), 2, 3])
    check([[[Int32]]]())
    check([[Int64(1), 2], [3, 4], [5, 6]])
    check(["a", "b", "c"])
    check([["a", "b"], ["c", "d"], ["e", "f"]])
  }

  @Test func invalidDataError() throws {
    enum Foo: UInt8, Serializable {
      case a = 1, b = 2
    }
    enum Bar: UInt8, Serializable {
      case a = 1
    }
    let value = Foo.b
    let bytes = try value.testSerialize()
    #expect(throws: SerializationError.self) {
      try Bar.testDeserialize(from: bytes)
    }
  }

  @Test func untrivialTypes() {
    check(Parent(bar: 42))
    let child = Child(bar: 0, baz: 0)
    let child2 = Child(bar: 0, baz: 1)
    #expect(child != child2)
    check([Pointer(child), Pointer(child2)])
  }

  @Test func emptyStringFollowedByDataWrite() throws {
    let stream = OutputStream.toMemory()
    try FileWriter(stream: stream).withStream { try ["", "after"].serialize(to: &$0) }
    let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
    var input = InMemoryInputByteStream(Array(data))
    #expect(try [String](from: &input) == ["", "after"])
  }

  @Test func emptyStringFollowedByDataRead() throws {
    let bytes = try ["", "after"].testSerialize()
    let result = try FileReader(stream: InputStream(data: Data(bytes)))
      .withStream { try [String](from: &$0) }
    #expect(result == ["", "after"])
  }

  private func check(_ value: some Serializable & Equatable & Sendable) {
    checkSerialization(value)
  }
}

private final class Pointer<T>: @unchecked Sendable {
  let value: T

  init(_ value: T) {
    self.value = value
  }
}

extension Pointer: Serializable where T: Serializable {
  convenience init(from stream: inout some InputByteStream) throws(SerializationError) {
    let header = try String(from: &stream)
    guard header == "Pointer" else {
      throw try SerializationError.invalidData(
        at: stream.location,
        expected: "Pointer",
        got: String(from: &stream)
      )
    }
    try self.init(T(from: &stream))
  }

  func serialize(to buffer: inout some OutputByteStream) throws(SerializationError) {
    try "Pointer".serialize(to: &buffer)
    try value.serialize(to: &buffer)
  }
}

extension Pointer: Equatable where T: Equatable {
  static func ==(lhs: Pointer, rhs: Pointer) -> Bool {
    lhs.value == rhs.value
  }
}

private class Parent: NSObject, Serializable, @unchecked Sendable {
  let bar: Int32

  init(bar: Int32) {
    self.bar = bar
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? Parent else { return false }
    return bar == other.bar
  }

  required init(from stream: inout some InputByteStream) throws(SerializationError) {
    bar = try Int32(from: &stream)
  }

  func serialize(to buffer: inout some OutputByteStream) throws(SerializationError) {
    try bar.serialize(to: &buffer)
  }
}

private class Child: Parent, @unchecked Sendable {
  var baz: Int32

  init(bar: Int32, baz: Int32) {
    self.baz = baz
    super.init(bar: bar)
  }

  required init(
    from stream: inout some InputByteStream
  ) throws(SerializationError) {
    baz = try Int32(from: &stream)
    try super.init(from: &stream)
  }

  override func serialize(
    to buffer: inout some OutputByteStream
  ) throws(SerializationError) {
    try baz.serialize(to: &buffer)
    try super.serialize(to: &buffer)
  }

  override func isEqual(_ other: Any?) -> Bool {
    guard let other = other as? Child else { return false }
    return baz == other.baz && super.isEqual(other)
  }
}
