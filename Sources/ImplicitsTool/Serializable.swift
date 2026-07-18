// Copyright 2024 Yandex LLC. All rights reserved.

/// A type that can be serialized and deserialized from byte streams.
///
/// Use this as fast alternative to `Codable`.
public protocol Serializable {
  init(from stream: inout some InputByteStream) throws(SerializationError)
  func serialize(
    to stream: inout some OutputByteStream
  ) throws(SerializationError)
}

extension Array: Serializable where Element: Serializable {
  public init(from stream: inout some InputByteStream) throws(SerializationError) {
    let countU = try UInt64(from: &stream)
    guard let count = Int(exactly: countU), countU < Int32.max else {
      throw SerializationError.invalidData(
        at: stream.location,
        expected: "0..<\(Int32.max)",
        got: "\(countU)"
      )
    }
    var err: SerializationError?
    self.init(unsafeUninitializedCapacity: count) { buffer, initialized in
      for i in 0..<count {
        do throws(SerializationError) {
          try buffer.initializeElement(at: i, to: Element(from: &stream))
        } catch {
          err = error
          initialized = i
          return
        }
      }
      initialized = count
    }
    if let err {
      throw err
    }
  }

  public func serialize(to s: inout some OutputByteStream) throws(SerializationError) {
    try UInt64(self.count).serialize(to: &s)
    for element in self {
      try element.serialize(to: &s)
    }
  }
}

extension String: Serializable {
  public init(from stream: inout some InputByteStream) throws(SerializationError) {
    let countU = try UInt64(from: &stream)
    guard let count = Int(exactly: countU), countU < Int32.max else {
      throw SerializationError.invalidData(
        at: stream.location,
        expected: "0..<\(Int32.max)",
        got: "\(countU)"
      )
    }

    var err: SerializationError?
    self.init(unsafeUninitializedCapacity: count) {
      do throws(SerializationError) {
        try stream.read(
          into: UnsafeMutableRawBufferPointer($0.extracting(0..<count))
        )
      } catch {
        err = error
        return 0
      }
      return count
    }
    if let err {
      throw err
    }
  }

  public func serialize(to s: inout some OutputByteStream) throws(SerializationError) {
    var copy = self
    var err: SerializationError?
    copy.withUTF8 {
      do throws(SerializationError) {
        try UInt64($0.count).serialize(to: &s)
        try s.write(UnsafeRawBufferPointer($0))
      } catch {
        err = error
      }
    }
    if let err {
      throw err
    }
  }
}

// MARK: Errors

extension SerializationError {
  public static func invalidData(
    at: String, expected: String, got: String
  ) -> Self {
    .init(
      description: "Invalid data at \(at), expected \(expected), got \(got)"
    )
  }
}

// MARK: Integers

public protocol ExplicitWidthInteger: FixedWidthInteger, Serializable {}

extension ExplicitWidthInteger {
  public init(from s: inout some InputByteStream) throws(SerializationError) {
    var err: SerializationError?
    var le = Self()
    withUnsafeMutableBytes(of: &le) {
      do throws(SerializationError) {
        try s.read(
          into: UnsafeMutableRawBufferPointer($0)
        )
      } catch {
        err = error
      }
    }
    self.init(littleEndian: le)
    if let err {
      throw err
    }
  }

  public func serialize(
    to s: inout some OutputByteStream
  ) throws(SerializationError) {
    var err: SerializationError?
    withUnsafeBytes(of: self.littleEndian) {
      do throws(SerializationError) {
        try s.write(UnsafeRawBufferPointer($0))
      } catch {
        err = error
      }
    }
    if let err {
      throw err
    }
  }
}

extension UInt64: ExplicitWidthInteger {}
extension UInt32: ExplicitWidthInteger {}
extension UInt16: ExplicitWidthInteger {}
extension UInt8: ExplicitWidthInteger {}
extension Int64: ExplicitWidthInteger {}
extension Int32: ExplicitWidthInteger {}
extension Int16: ExplicitWidthInteger {}
extension Int8: ExplicitWidthInteger {}

extension RawRepresentable where RawValue: Serializable {
  public init(
    from s: inout some InputByteStream
  ) throws(SerializationError) {
    let rawValue = try RawValue(from: &s)
    guard let value = Self(rawValue: rawValue) else {
      throw SerializationError.invalidData(
        at: s.location,
        expected: "\(Self.self) raw value",
        got: "\(rawValue)"
      )
    }
    self = value
  }

  public func serialize(to s: inout some OutputByteStream) throws(SerializationError) {
    try self.rawValue.serialize(to: &s)
  }
}

extension Bool: Serializable {
  public init(from s: inout some InputByteStream) throws(SerializationError) {
    self = try UInt8(from: &s) != 0
  }

  public func serialize(to s: inout some OutputByteStream) throws(SerializationError) {
    try UInt8(self ? 1 : 0).serialize(to: &s)
  }
}

extension Optional where Wrapped: Serializable {
  public init(from s: inout some InputByteStream) throws(SerializationError) {
    self = try Bool(from: &s) ? .some(Wrapped(from: &s)) : .none
  }

  public func serialize(to s: inout some OutputByteStream) throws(SerializationError) {
    try Bool(self != nil).serialize(to: &s)
    if let wrapped = self {
      try wrapped.serialize(to: &s)
    }
  }
}
