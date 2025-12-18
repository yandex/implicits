// swiftformat:disable all
#if false
#endif
import AnotherModule
private import CoreGraphics
internal import CoreImage
import Foundation

@_spi(Unsafe) import Implicits
extension ImplicitsKeys {
  internal enum _SupportFileKey1Tag {
  }
  internal var supportFileKey1: ImplicitKey<Bool, _SupportFileKey1Tag>.Type {
    ImplicitKey<Bool, _SupportFileKey1Tag>.self
  }
  public enum _SupportFileKey2Tag {
  }
  @inlinable public var supportFileKey2: ImplicitKey<[Int], _SupportFileKey2Tag>.Type {
    ImplicitKey<[Int], _SupportFileKey2Tag>.self
  }
}

internal func closureImplicits() -> Implicits {
  Implicits(unsafeKeys: Implicits.getRawKey((UInt16).self), Implicits.getRawKey((UInt8).self))
}

internal func __implicit_bag_support_file_swift_28_22() -> Implicits {
  Implicits(unsafeKeys: Implicits.getRawKey((UInt16).self), Implicits.getRawKey((UInt8).self))
}

internal func __implicit_bag_support_file_swift_62_19() -> Implicits {
  Implicits()
}

internal func withSupportZeroImplicits<T>(_ body: @escaping (ImplicitScope) -> T) -> () -> T {
  let implicits = Implicits(unsafeKeys: Implicits.getRawKey((UInt16).self), Implicits.getRawKey((UInt8).self))
  return {
    let scope = ImplicitScope(with: implicits)
    defer {
      scope.end()
    }
    return body(scope)
  }
}

internal func withSupportOneImplicits<T, A1>(_ body: @escaping (A1, ImplicitScope) -> T) -> (A1) -> T {
  let implicits = Implicits(unsafeKeys: Implicits.getRawKey((UInt16).self), Implicits.getRawKey((UInt8).self))
  return { arg1 in
    let scope = ImplicitScope(with: implicits)
    defer {
      scope.end()
    }
    return body(arg1, scope)
  }
}

internal func withSupportTwoImplicits<T, A1, A2>(_ body: @escaping (A1, A2, ImplicitScope) -> T) -> (A1, A2) -> T {
  let implicits = Implicits(unsafeKeys: Implicits.getRawKey((UInt16).self), Implicits.getRawKey((UInt8).self))
  return { arg1, arg2 in
    let scope = ImplicitScope(with: implicits)
    defer {
      scope.end()
    }
    return body(arg1, arg2, scope)
  }
}

public func supportFileFunc(arg: Int, bool: @autoclosure () -> Bool, keyFromAnotherModule: @autoclosure () -> [String: [Int]], supportFileKey2: @autoclosure () -> [Int]) {
  let scope = ImplicitScope()
  defer {
    scope.end()
  }
  @Implicit var bool_: Bool = bool()
  @Implicit(\.keyFromAnotherModule) var keyFromAnotherModule_: [String: [Int]] = keyFromAnotherModule()
  @Implicit(\.supportFileKey2) var supportFileKey2_: [Int] = supportFileKey2()
  supportFileFunc(arg: arg, scope)
}

extension SupportFileClass {
  public convenience init(arg: @escaping () -> Void, int: @autoclosure () -> [Int]) {
    let scope = ImplicitScope()
    defer {
      scope.end()
    }
    @Implicit var int_: [Int] = int()
    self.init(arg: arg, scope)
  }

  public convenience init(anotherArg: Bool, setInt: @autoclosure () -> Set<Int>) {
    let scope = ImplicitScope()
    defer {
      scope.end()
    }
    @Implicit var setInt_: Set<Int> = setInt()
    self.init(anotherArg: anotherArg, scope)
  }
}

extension SupportFileStruct {
  public init(supportFileKey2: @autoclosure () -> [Int]) {
    let scope = ImplicitScope()
    defer {
      scope.end()
    }
    @Implicit(\.supportFileKey2) var supportFileKey2_: [Int] = supportFileKey2()
    self.init(scope)
  }
  public static func staticFunction(supportFileKey1: @autoclosure () -> Bool) -> [Bool] {
    let scope = ImplicitScope()
    defer {
      scope.end()
    }
    @Implicit(\.supportFileKey1) var supportFileKey1_: Bool = supportFileKey1()
    return SupportFileStruct.staticFunction(scope)
  }
  public func memberFunction(supportFileKey2: @autoclosure () -> [Int]) -> [Int] {
    let scope = ImplicitScope()
    defer {
      scope.end()
    }
    @Implicit(\.supportFileKey2) var supportFileKey2_: [Int] = supportFileKey2()
    return memberFunction(scope)
  }
  public func callAsFunction(int: @autoclosure () -> [Int]) -> [Int] {
    let scope = ImplicitScope()
    defer {
      scope.end()
    }
    @Implicit var int_: [Int] = int()
    return callAsFunction(scope)
  }
}
extension SupportFileStruct.Subtype {
  public init(int: @autoclosure () -> [Int]) {
    let scope = ImplicitScope()
    defer {
      scope.end()
    }
    @Implicit var int_: [Int] = int()
    self.init(scope)
  }
}

#if false
internal func supportFileFunc2(arg: Int, bool: @autoclosure () -> Bool) {
  let scope = ImplicitScope()
  defer {
    scope.end()
  }
  @Implicit var bool_: Bool = bool()
  supportFileFunc2(arg: arg, scope)
}
#endif
