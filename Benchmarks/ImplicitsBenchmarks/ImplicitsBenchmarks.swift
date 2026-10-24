// Copyright 2026 Yandex LLC. All rights reserved.

import Benchmark
import Foundation
import Implicits

let benchmarks: @Sendable () -> Void = {
  precondition(
    ProcessInfo.processInfo.environment["SWIFT_DETERMINISTIC_HASHING"] == "1",
    """
    Run with SWIFT_DETERMINISTIC_HASHING=1: the store is a dictionary, \
    and a per-process hash seed changes instruction counts between runs by up to 30%.
    """
  )
  Benchmark.defaultConfiguration = .init(
    metrics: [.instructions, .wallClock, .mallocCountTotal],
    scalingFactor: .kilo
  )

  Benchmark("Retrieve Int") { benchmark in
    onThread { retrieve(42, benchmark) }
  }

  Benchmark("Retrieve Int inside a task") { benchmark in
    retrieve(42, benchmark)
  }

  Benchmark("Retrieve any Service") { benchmark in
    onThread { retrieve(ServiceImpl() as any Service, benchmark) }
  }

  Benchmark("Retrieve struct with a String") { benchmark in
    onThread { retrieve(Big(), benchmark) }
  }

  Benchmark("Declare Int in a nested scope") { benchmark in
    onThread {
      let scope = ImplicitScope()
      defer { scope.end() }
      declareFillers(W<Void>.self, 20)
      benchmark.startMeasurement()
      for _ in benchmark.scaledIterations {
        declareInNestedScope(42, scope)
      }
    }
  }

  // The one-time cost of a type the process has never stored, in the specialized code
  // an app runs: every iteration takes the next thousand of the generated `NewTypes`.
  // The second benchmark repeats the same calls on types it has already met, so the
  // difference between the two is that one-time cost. memoryLeakedBytes is what stays
  // allocated after the types' scope ends.
  Benchmark(
    "New types: first declare and retrieve",
    configuration: newTypesConfiguration()
  ) { benchmark in
    onThread { passOverNewTypes(benchmark, alreadySeen: false) }
  }

  Benchmark(
    "New types: second declare and retrieve",
    configuration: newTypesConfiguration()
  ) { benchmark in
    onThread { passOverNewTypes(benchmark, alreadySeen: true) }
  }
}

private let newTypeIterations = 10

private func newTypesConfiguration() -> Benchmark.Configuration {
  .init(
    metrics: [.instructions, .wallClock, .mallocCountTotal, .memoryLeakedBytes],
    warmupIterations: 0,
    scalingFactor: .kilo,
    maxIterations: newTypeIterations
  )
}

private func passOverNewTypes(_ benchmark: Benchmark, alreadySeen: Bool) {
  let first = benchmark.currentIteration * 1000
  let touches = NewTypes.touches[first..<first + 1000]
  let scope = ImplicitScope()
  defer { scope.end() }
  // Grows the store to its final size outside the measurement; with `alreadySeen`
  // it does so with the measured types themselves.
  withScope(nesting: scope) { _ in
    if alreadySeen {
      touches.forEach { $0() }
    } else {
      declareFillers(W<Void>.self, 1000)
    }
  }
  benchmark.startMeasurement()
  withScope(nesting: scope) { _ in
    touches.forEach { $0() }
  }
  benchmark.stopMeasurement()
}

private enum NewTypes {
  #newTypes(10000)
}

@freestanding(declaration, names: arbitrary)
private macro newTypes(_ count: Int) = #externalMacro(
  module: "ImplicitsBenchmarksMacros",
  type: "NewTypesMacro"
)

/// Runs `body` on a thread outside any task and waits for it. The runner calls benchmarks
/// inside a task, where the store lives in a task-local value; on a thread it lives in
/// thread-specific data, the path synchronous code takes.
private func onThread(_ body: @escaping () -> Void) {
  BenchmarkThread.shared.run(body)
}

/// One thread for the whole process that never exits: a thread that exits while the
/// runner counts mallocs crashes the process inside the counter's thread-exit cleanup.
private final class BenchmarkThread: @unchecked Sendable {
  static let shared = BenchmarkThread()

  private var body: (() -> Void)?
  private let started = DispatchSemaphore(value: 0)
  private let finished = DispatchSemaphore(value: 0)

  private init() {
    Thread { [self] in
      while true {
        started.wait()
        body?()
        body = nil
        finished.signal()
      }
    }.start()
  }

  func run(_ body: @escaping () -> Void) {
    self.body = body
    started.signal()
    finished.wait()
  }
}

@inline(never)
private func retrieve<T>(_ value: T, _ benchmark: Benchmark) {
  let scope = ImplicitScope()
  defer { scope.end() }
  declareFillers(W<Void>.self, 20)
  @Implicit var declared = value
  benchmark.startMeasurement()
  for _ in benchmark.scaledIterations {
    blackHole(retrieveOnce(T.self, scope))
  }
}

@inline(never)
private func retrieveOnce<T>(_: T.Type, _: ImplicitScope) -> T {
  @Implicit() var value: T
  return value
}

@inline(never)
private func declareInNestedScope(_ value: some Any, _ outer: ImplicitScope) {
  let scope = outer.nested()
  defer { scope.end() }
  @Implicit var declared = value
  blackHole(declared)
}

/// Fills the current scope with `count` implicits of distinct types,
/// so lookups happen in a store of realistic size.
private func declareFillers<T>(_: T.Type, _ count: Int) {
  @Implicit var filler = W<T>(reference: sharedReference)
  if count > 1 {
    declareFillers(W<T>.self, count - 1)
  }
}

@inline(never)
private func declareAndRetrieve<T>(_ value: T) {
  @Implicit var declared = value
  @Implicit() var retrieved: T
  blackHole(retrieved)
}

private protocol Service {
  func ping() -> Int
}

private final class ServiceImpl: Service {
  func ping() -> Int { 1 }
}

private struct Big {
  var a = 1, b = 2, c = 3, d = 4
  var s = "heap allocated string, longer than 15 bytes"
}

private final class Reference: Sendable {}

private let sharedReference = Reference()

private struct W<T> {
  var reference: Reference
}
