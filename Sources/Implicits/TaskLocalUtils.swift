// Copyright 2024 Yandex LLC. All rights reserved.

@available(iOS 13, macOS 10.15, *)
extension TaskLocal {
  private var key: BuiltinRawPointer {
    unsafeBitCast(self, to: BuiltinRawPointer.self)
  }

  func push(_ value: __owned Value) {
    _taskLocalValuePush(key: key, value: consume value)
  }

  func pop() {
    _taskLocalValuePop()
  }
}

@available(iOS 13, macOS 10.15, *)
func isAsyncContext() -> Bool {
  withUnsafeCurrentTask { $0 != nil }
}

class UnmanagedAsyncTaskWrapper {}

// Mirrors Builtin.retain(_task) in stdlib's withUnsafeCurrentTask
// to prevent "destroying a task that never completed" crashes.
// See: github.com/swiftlang/swift/blob/swift-6.0-RELEASE/stdlib/public/Concurrency/Task.swift#L686
@available(iOS 13, macOS 10.15, *)
func currentTaskID() -> ObjectIdentifier? {
  guard isAsyncContext(), let task = _getCurrentAsyncTask()
  else { return nil }
  let classTask = unsafeBitCast(task, to: UnmanagedAsyncTaskWrapper.self)
  let unmanagedTask = Unmanaged.passRetained(classTask)
  let id = unsafeBitCast(
    unmanagedTask.takeUnretainedValue(), to: ObjectIdentifier.self
  )
  return id
}

private protocol BuiltinRawPointerTypeExtractor {
  associatedtype BuiltinRawPointer
  var _rawValue: BuiltinRawPointer { get }
}

extension UnsafeRawPointer: BuiltinRawPointerTypeExtractor {}

private typealias BuiltinRawPointer = UnsafeRawPointer.BuiltinRawPointer

// @available(SwiftStdlib 5.1, *)
// https://github.com/swiftlang/swift/blob/main/utils/availability-macros.def
@available(iOS 13, macOS 10.15, *)
@_silgen_name("swift_task_localValuePush")
private func _taskLocalValuePush(
  key: BuiltinRawPointer /*: Key */,
  value: __owned some Any
) // where Key: TaskLocal

@available(iOS 13, macOS 10.15, *)
@_silgen_name("swift_task_localValuePop")
private func _taskLocalValuePop()
