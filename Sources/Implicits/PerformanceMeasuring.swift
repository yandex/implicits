// Copyright 2024 Yandex LLC. All rights reserved.

import Foundation

private import ImplicitsCUtils

public enum MeasurementSubject: CaseIterable {
  case control
  case implicitsWithUnsafeKeys
  case rawStoreCurrent
  case rawStoreFromTSD
  case rawStoreSubscriptGet
  case rawStoreSubscriptSet
  case rawStoreOnRootScopeCreation
  case rawStoreOnRootScopeEnd
  case typedStoreSubscriptGet
  case typedStoreSetValue
}

public struct ImplicitPerformanceMeasurement {
  public typealias Nanoseconds = UInt64
  public var aggregateNanos: Nanoseconds
  public var aggregateCount: UInt64

  public static func read(
    for subject: MeasurementSubject
  ) -> Self {
    let internalSubject = InternalImplicitsMeasurementSubject(subject)
    let time = GetAccumulatedMetricFor(internalSubject)
    let count = GetCounterFor(internalSubject)
    return Self(aggregateNanos: time, aggregateCount: count)
  }
}

// This function must always be inlined to avoid passing the measured code
// in a closure, which could introduce additional overhead and potentially
// affect the measurement accuracy.
@inline(__always)
@inlinable
func measure<T>(
  _ subject: MeasurementSubject, code: () throws -> T
) rethrows -> T {
  #if ENABLE_IMPLICIT_PERFORMANCE_MEASUREMENT
  let start = startMeasurement()
  defer {
    endMeasurement(start, subject: subject)
  }
  #endif
  return try code()
}

@usableFromInline
typealias Time = DispatchTime

@inlinable
func startMeasurement() -> Time {
  DispatchTime.now()
}

// The `ImplicitsPerformanceMeasuring` module must be imported privately to
// prevent visibility from outside.
// Therefore, the code cannot refer to `InternalImplicitsMeasurementSubject`
// from inlinable functions.
//
// When `measure` is called from non-inlinable functions, it will likely be
// completely inlined, including the `recordMeasurement` C function.
// When `measure` is called from inlinable functions, only `measure` itself
// will be inlined, and `endMeasurement` will not be inlined,
// which is a fair tradeoff.
@usableFromInline
@inline(__always)
func endMeasurement(_ start: Time, subject: MeasurementSubject) {
  let finish = DispatchTime.now()
  let time = finish.uptimeNanoseconds - start.uptimeNanoseconds
  let internalSubject = InternalImplicitsMeasurementSubject(subject)
  RecordMeasurement(internalSubject, time)
}

extension InternalImplicitsMeasurementSubject {
  fileprivate init(_ other: MeasurementSubject) {
    switch other {
    case .control:
      self = .control
    case .implicitsWithUnsafeKeys:
      self = .implicitsWithUnsafeKeys
    case .rawStoreCurrent:
      self = .rawStoreCurrent
    case .rawStoreFromTSD:
      self = .rawStoreFromTSD
    case .rawStoreSubscriptGet:
      self = .rawStoreSubscriptGet
    case .rawStoreSubscriptSet:
      self = .rawStoreSubscriptSet
    case .rawStoreOnRootScopeCreation:
      self = .rawStoreOnRootScopeCreation
    case .rawStoreOnRootScopeEnd:
      self = .rawStoreOnRootScopeEnd
    case .typedStoreSubscriptGet:
      self = .typedStoreSubscriptGet
    case .typedStoreSetValue:
      self = .typedStoreSetValue
    }
  }
}

extension MeasurementSubject {
  public var logIdentifier: String {
    switch self {
    case .control:
      "control"
    case .implicitsWithUnsafeKeys:
      "implicitsWithUnsafeKeys"
    case .rawStoreCurrent:
      "rawStoreCurrent"
    case .rawStoreFromTSD:
      "rawStoreFromTSD"
    case .rawStoreSubscriptGet:
      "rawStoreSubscriptGet"
    case .rawStoreSubscriptSet:
      "rawStoreSubscriptSet"
    case .typedStoreSubscriptGet:
      "typedStoreSubscriptGet"
    case .typedStoreSetValue:
      "typedStoreSetValue"
    case .rawStoreOnRootScopeCreation:
      "rawStoreOnRootScopeCreation"
    case .rawStoreOnRootScopeEnd:
      "rawStoreOnRootScopeEnd"
    }
  }
}
