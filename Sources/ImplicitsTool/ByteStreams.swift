// Copyright 2024 Yandex LLC. All rights reserved.

import Foundation

/// Error namespace for serialization errors.
///
/// Serialization ans stream implementation must throw only those errors.
public struct SerializationError: Error {
  public var description: String

  init(description: String) {
    self.description = description
  }

  public static func endOfStream(
    at: String, need: String
  ) -> Self {
    .init(description: "End of stream at \(at), need \(need)")
  }

  public static func failedToCreateStream(at: URL) -> Self {
    .failedToCreateStream(at: at.absoluteString)
  }

  public static func failedToCreateStream(at: String) -> Self {
    Self(description: "Failed to create stream at \(at)")
  }
}

/// Provides read-only access to a byte stream.
/// This is simplified version of `InputStream` from Foundation.
public protocol InputByteStreamInterface: ~Copyable {
  mutating func read(
    into: UnsafeMutableRawBufferPointer
  ) throws(SerializationError)
  var location: String { get }
}

public typealias InputByteStream = ~Copyable & InputByteStreamInterface

/// Provides write-only access to a byte stream.
/// This is simplified version of `OutputStream` from Foundation.
public protocol OutputByteStreamInterface: ~Copyable {
  mutating func write(
    _ buffer: UnsafeRawBufferPointer
  ) throws(SerializationError)
}

public typealias OutputByteStream = ~Copyable & OutputByteStreamInterface

public struct FileReader {
  public struct Stream: ~Copyable, InputByteStream {
    private var impl: InputStream

    fileprivate init(impl: InputStream) {
      self.impl = impl
      impl.open()
    }

    deinit {
      impl.close()
    }

    public mutating func read(
      into: UnsafeMutableRawBufferPointer
    ) throws(SerializationError) {
      guard let baseAddress = into.baseAddress else { return }
      let bytesRead = impl.read(
        baseAddress.assumingMemoryBound(to: UInt8.self),
        maxLength: into.count
      )
      if bytesRead != into.count {
        // TODO: Take into account stream error and status
        throw SerializationError.endOfStream(
          at: impl.fileLocation, need: "\(into.count) bytes"
        )
      }
    }

    public var location: String { impl.fileLocation }
  }

  private var impl: InputStream

  public init(url: URL) throws(SerializationError) {
    guard let impl = InputStream(url: url) else {
      throw .failedToCreateStream(at: url)
    }
    self.impl = impl
  }

  public init(fileAtPath path: String) throws(SerializationError) {
    guard let impl = InputStream(fileAtPath: path) else {
      throw .failedToCreateStream(at: path)
    }
    self.impl = impl
  }

  @_spi(Testing)
  public init(stream: InputStream) {
    self.impl = stream
  }

  public func withStream<R>(
    _ body: (inout Stream) throws -> R
  ) rethrows -> R {
    var stream = Stream(impl: impl)
    return try body(&stream)
  }
}

public struct FileWriter {
  public struct Stream: ~Copyable, OutputByteStream {
    private var impl: OutputStream

    fileprivate init(impl: OutputStream) {
      self.impl = impl
      impl.open()
    }

    deinit {
      impl.close()
    }

    public func write(
      _ buffer: UnsafeRawBufferPointer
    ) throws(SerializationError) {
      guard buffer.count > 0, let baseAddress = buffer.baseAddress else { return }
      let bytesWritten = impl.write(
        baseAddress.assumingMemoryBound(to: UInt8.self),
        maxLength: buffer.count
      )
      if bytesWritten != buffer.count {
        // TODO: Take into account stream error and status
        throw SerializationError.endOfStream(
          at: impl.fileLocation, need: "\(buffer.count) bytes"
        )
      }
    }
  }

  private var impl: OutputStream

  public init(url: URL, append: Bool) throws(SerializationError) {
    guard let impl = OutputStream(url: url, append: append) else {
      throw .failedToCreateStream(at: url)
    }
    self.impl = impl
  }

  public init(
    fileAtPath path: String, append: Bool
  ) throws(SerializationError) {
    guard let impl = OutputStream(toFileAtPath: path, append: append) else {
      throw .failedToCreateStream(at: path)
    }
    self.impl = impl
  }

  @_spi(Testing)
  public init(stream: OutputStream) {
    self.impl = stream
  }

  public func withStream<R>(
    _ body: (inout Stream) throws -> R
  ) rethrows -> R {
    var stream = Stream(impl: impl)
    return try body(&stream)
  }
}

extension Stream {
  fileprivate var fileLocation: String {
    let offset = property(forKey: .fileCurrentOffsetKey) as? NSNumber
    guard let offset else { return "<unknown>" }
    return "\(offset)"
  }
}
