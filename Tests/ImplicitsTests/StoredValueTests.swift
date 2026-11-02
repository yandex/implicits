// Copyright 2026 Yandex LLC. All rights reserved.

internal import Implicits
import Testing

struct StoredValueTests {
  @Test func `values of any size and alignment come back intact`() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit var empty = Empty()
    @Implicit var vector = SIMD4<Float>(1, 2, 3, 4)
    @Implicit var wide = Wide()
    @Implicit var shape: any Shape = Square(side: 3)
    let base = String(repeating: "c", count: 20)
    @Implicit var closure: () -> String = { base + "!" }
    @Implicit var tree = Tree.node(.leaf(1), .node(.leaf(2), .leaf(3)))
    @Implicit var pair = (String(repeating: "p", count: 20), [4, 5])

    @Implicit() var storedEmpty: Empty
    @Implicit() var storedVector: SIMD4<Float>
    @Implicit() var storedWide: Wide
    @Implicit() var storedShape: any Shape
    @Implicit() var storedClosure: () -> String
    @Implicit() var storedTree: Tree
    @Implicit() var storedPair: (String, [Int])

    #expect(storedEmpty == empty)
    #expect(storedVector == vector)
    #expect(storedWide == wide)
    #expect(storedShape.area == 9)
    #expect(storedClosure() == base + "!")
    #expect(storedTree == tree)
    #expect(storedPair == pair)
  }

  @Test func `a value is released when the scope that declared it ends`() {
    weak var outerValue: Tracked?
    weak var innerValue: Tracked?

    func declareInNested(_ scope: ImplicitScope) {
      let scope = scope.nested()
      defer { scope.end() }

      @Implicit var tracked = Tracked()
      innerValue = tracked
    }

    func declare() {
      let scope = ImplicitScope()
      defer { scope.end() }

      @Implicit var tracked = Tracked()
      outerValue = tracked

      declareInNested(scope)
      #expect(innerValue == nil)

      @Implicit() var stored: Tracked
      #expect(stored === outerValue)
    }

    declare()
    #expect(outerValue == nil)
  }

  #if DEBUG
  @Test func `the debug dump shows stored values`() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit var wide = Wide()

    let dumped = ImplicitScope.dumpCurrent().map(\.value)
    #expect(dumped.count == 1)
    #expect(dumped.first as? Wide == wide)
  }
  #endif
}

private struct Empty: Equatable {}

/// Holds references and ends partway into its last 16-byte slot.
private struct Wide: Equatable {
  var name = String(repeating: "w", count: 40)
  var numbers = [1, 2, 3]
  var a = 1, b = 2, c = 3
  var flag = true
}

private protocol Shape {
  var area: Int { get }
}

private struct Square: Shape {
  var side: Int
  var area: Int { side * side }
}

private indirect enum Tree: Equatable {
  case leaf(Int)
  case node(Tree, Tree)
}

private final class Tracked {}
