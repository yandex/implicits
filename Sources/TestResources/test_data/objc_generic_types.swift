import Foundation
import Implicits

func testObjcGenericTypes() {
  let scope = ImplicitScope()
  defer { scope.end() }

  // Objective-C generic types should produce errors
  @Implicit
  var arr1: NSArray<NSString> = NSArray() // expected-error {{'NSArray' is an Objective-C type with type-erased generics; use a named key (keypath) instead of type-as-key}}

  @Implicit
  var dict1: NSDictionary<NSString, NSNumber> = NSDictionary() // expected-error {{'NSDictionary' is an Objective-C type with type-erased generics; use a named key (keypath) instead of type-as-key}}

  @Implicit
  var set1: NSSet<NSString> = NSSet() // expected-error {{'NSSet' is an Objective-C type with type-erased generics; use a named key (keypath) instead of type-as-key}}

  @Implicit
  var orderedSet1: NSOrderedSet<NSString> = NSOrderedSet() // expected-error {{'NSOrderedSet' is an Objective-C type with type-erased generics; use a named key (keypath) instead of type-as-key}}

  // Non-generic ObjC types should be fine
  @Implicit
  var str: NSString = ""

  @Implicit
  var number: NSNumber = 0

  // Swift generic types should be fine
  @Implicit
  var swiftArr: Array<String> = []

  @Implicit
  var swiftDict: Dictionary<String, Int> = [:]
}
