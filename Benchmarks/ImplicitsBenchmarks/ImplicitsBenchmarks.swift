// Copyright 2026 Yandex LLC. All rights reserved.

import Benchmark
import Foundation
import Implicits
import Synchronization

let benchmarks: @Sendable () -> Void = {
  precondition(
    ProcessInfo.processInfo.environment["SWIFT_DETERMINISTIC_HASHING"] == "1",
    "SWIFT_DETERMINISTIC_HASHING is not 1"
  )
  Benchmark.defaultConfiguration = .init(
    metrics: [.instructions, .wallClock, .mallocCountTotal],
    scalingFactor: .mega
  )
  let thread = BenchmarkThread()

  Benchmark("Retrieve Int") { benchmark in
    let iterations = benchmark.scaledIterations
    thread.run(benchmark) { retrieve(42, iterations, $0) }
  }

  Benchmark("Retrieve Int inside a task") { benchmark in
    retrieve(42, benchmark.scaledIterations) { body in
      benchmark.startMeasurement()
      body()
      benchmark.stopMeasurement()
    }
  }

  Benchmark("Retrieve any Service") { benchmark in
    let iterations = benchmark.scaledIterations
    thread.run(benchmark) {
      retrieve(ServiceImpl() as any Service, iterations, $0)
    }
  }

  Benchmark("Retrieve struct with a String") { benchmark in
    let iterations = benchmark.scaledIterations
    thread.run(benchmark) { retrieve(Big(), iterations, $0) }
  }

  Benchmark("Declare Int in a nested scope") { benchmark in
    let iterations = benchmark.scaledIterations
    thread.run(benchmark) { measure in
      let scope = ImplicitScope()
      defer { scope.end() }
      declareFillers(W<Void>.self, 20)
      measure {
        for _ in iterations {
          declareInNestedScope(42, scope)
        }
      }
    }
  }

  Benchmark(
    "New types: first declare and retrieve",
    configuration: newTypesConfiguration()
  ) { benchmark in
    passOverNewTypes(benchmark, alreadySeen: false)
  }

  Benchmark(
    "New types: second declare and retrieve",
    configuration: newTypesConfiguration()
  ) { benchmark in
    passOverNewTypes(benchmark, alreadySeen: true)
  }
}

private let newTypeIterations = 10
private let newTypesPerIteration = NewTypes.touches.count / newTypeIterations

private func newTypesConfiguration() -> Benchmark.Configuration {
  .init(
    metrics: [.instructions, .wallClock, .mallocCountTotal, .memoryLeakedBytes],
    warmupIterations: 0,
    scalingFactor: .one,
    maxIterations: newTypeIterations
  )
}

private func passOverNewTypes(_ benchmark: Benchmark, alreadySeen: Bool) {
  let first = benchmark.currentIteration * newTypesPerIteration
  let touches = NewTypes.touches[first..<first + newTypesPerIteration]
  let scope = ImplicitScope()
  defer { scope.end() }
  // Before the measurement the second pass declares its types once and the
  // first pass declares as many fillers, so in both the store has already
  // grown to the same capacity.
  withScope(nesting: scope) { _ in
    if alreadySeen {
      touches.forEach { $0() }
    } else {
      declareFillers(W<Void>.self, newTypesPerIteration)
    }
  }
  benchmark.startMeasurement()
  withScope(nesting: scope) { _ in
    touches.forEach { $0() }
  }
  benchmark.stopMeasurement()
}

/// Runs work outside any task, where synchronous code keeps the store in
/// thread-specific data. The thread never exits: malloc-interposer 1.6 crashes
/// when a thread exits while it counts mallocs.
private final class BenchmarkThread: Sendable {
  private let job = Mutex<(@Sendable () -> Void)?>(nil)
  private let jobPosted = DispatchSemaphore(value: 0)

  init() {
    Thread { [self] in
      while true {
        jobPosted.wait()
        job.withLock { $0.take() }?()
      }
    }.start()
  }

  /// Runs `work` on the thread and waits for it; `work` passes the measured
  /// part to its argument. The runner counts instructions and mallocs per
  /// process, so the counts include the thread.
  func run(
    _ benchmark: Benchmark,
    _ work: @escaping @Sendable (_ measure: (() -> Void) -> Void) -> Void
  ) {
    let measure = Measure()
    let finished = DispatchSemaphore(value: 0)
    job.withLock {
      $0 = {
        work(measure.run)
        finished.signal()
      }
    }
    jobPosted.signal()
    measure.ready.wait()
    benchmark.startMeasurement()
    measure.go.signal()
    measure.done.wait()
    benchmark.stopMeasurement()
    finished.wait()
  }
}

/// The thread's side of the measurement in `BenchmarkThread.run`.
private struct Measure: Sendable {
  var ready = DispatchSemaphore(value: 0)
  var go = DispatchSemaphore(value: 0)
  var done = DispatchSemaphore(value: 0)

  func run(_ body: () -> Void) {
    ready.signal()
    go.wait()
    body()
    done.signal()
  }
}

@inline(never)
private func retrieve<T>(
  _ value: T,
  _ iterations: Range<Int>,
  _ measure: (() -> Void) -> Void
) {
  let scope = ImplicitScope()
  defer { scope.end() }
  declareFillers(W<Void>.self, 20)
  @Implicit var declared = value
  measure {
    for _ in iterations {
      blackHole(retrieveOnce(T.self, scope))
    }
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
  @Implicit var filler = W<T>(reference: Reference())
  if count > 1 {
    declareFillers(W<T>.self, count - 1)
  }
}

/// What every closure in the generated `NewTypes.touches` calls.
@inline(never)
func declareAndRetrieve<T>(_ value: T) {
  @Implicit var declared = value
  @Implicit() var retrieved: T
  blackHole(retrieved)
}

private protocol Service: Sendable {}

private final class ServiceImpl: Service {}

private struct Big {
  var a = 1, b = 2, c = 3, d = 4
  var s = String(repeating: "s", count: 32)
}

private final class Reference: Sendable {}

private struct W<T> {
  var reference: Reference
}
