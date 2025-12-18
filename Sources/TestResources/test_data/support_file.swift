/// See `n_support_file_snapshot.swift` , that includes all generated code for support file
/// based on API usage in this file.

import Foundation

import AnotherModule
import Implicits

internal import CoreImage

private import CoreGraphics

extension ImplicitsKeys {
  // expected-key internal supportFileKey1: Bool
  internal static let supportFileKey1 = Key<Bool>()
  // expected-key public supportFileKey2: [Int]
  public static let supportFileKey2 = Key<[Int]>()
}


private func withBag(_: ImplicitScope) {
  _ = { [implicits = closureImplicits()] in
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }
    requires(scope)
  }

  _ = { [implicits = #implicits] in
    let scope = ImplicitScope(with: implicits)
    defer { scope.end() }
    requires(scope)
  }
}

private func withImplicits(_: ImplicitScope) {
  _ = withSupportZeroImplicits { scope in
    requires(scope)
  }
  _ = withSupportOneImplicits { (a: Int, scope) in
    _ = a
    requires(scope)
  }
  _ = withSupportTwoImplicits { (a: String, b: Bool, scope) in
    _ = a; _ = b
    requires(scope)
  }
}

@_spi(Implicits)
public func supportFileFunc(arg: Int, _: ImplicitScope) {
  @Implicit()
  var i: Bool

  @Implicit(\.supportFileKey2)
  var j: [Int]

  @Implicit(\.keyFromAnotherModule)
  var k: [String: [Int]]
}

public struct SupportFileStruct {
  let implicits = #implicits

  struct Subtype {
    @_spi(Implicits)
    public init(_: ImplicitScope) {
      @Implicit()
      var j: [Int]
    }
  }
  @_spi(Implicits)
  public init(_: ImplicitScope) {
    @Implicit(\.supportFileKey2)
    var j: [Int]
  }

  @_spi(Implicits)
  public static func staticFunction(_: ImplicitScope) -> [Bool] {
    @Implicit(\.supportFileKey1)
    var j: Bool
    return []
  }

  @_spi(Implicits)
  public func memberFunction(_: ImplicitScope) -> [Int] {
    @Implicit(\.supportFileKey2)
    var j: [Int]
    return []
  }

  @_spi(Implicits)
  public func callAsFunction(_: ImplicitScope) -> [Int] {
    @Implicit()
    var j: [Int]
    return []
  }
}

public class SupportFileClass {
  @_spi(Implicits)
  public init(arg: @escaping () -> Void, _: ImplicitScope) {
    @Implicit()
    var j: [Int]
  }

  init() {}
}

extension SupportFileClass {
  @_spi(Implicits)
  public convenience init(anotherArg: Bool, _ scope: ImplicitScope) {
    @Implicit()
    var j: Set<Int>
    self.init()
  }
}

internal func supportFileFunc2(arg: Int, _: ImplicitScope) {
  @Implicit()
  var i: Bool
}

// Those should not appear in the support file
public func supportFileFunc3(arg: Int) {}

private func requires(_: ImplicitScope) {
  @Implicit()
  var a1: UInt8
  @Implicit()
  var a2: UInt16
}
