// Copyright 2022 Yandex LLC. All rights reserved.

import Darwin

@usableFromInline
internal typealias Entry = EntryAbstract
@usableFromInline
internal typealias Arguments = [ImplicitKeyIdentifier: Entry]

/// A context-specific store for implicit arguments.
///
/// This is low level foundation for implicit arguments system,
/// every other mechanism uses this store to manage implicit arguments.
///
/// The store contains a "call stack" of implicit arguments for current context.
/// This call stack can be pushed and poped.
/// Detailed mechanics are described in corresponding methods.
///
/// Store can be obtained for current context using `current` method.
///
/// This class should not contain any generic signatures,
/// as its members must not be specialized or inlined.
///
/// RawStore stores data in TSD, if it operates outside of swift concurrency,
/// and in TaskLocal otherwise.
/// See `'man pthread_getspecific'` and https://developer.apple.com/documentation/swift/tasklocal
@usableFromInline
internal final class RawStore: @unchecked Sendable {
  private var args: ArgsStack
  private var rootScopeStackCount: Int = 0
  private let owningTaskID: ObjectIdentifier?

  private static let key: pthread_key_t = {
    var key = pthread_key_t()
    let code = pthread_key_create(&key) {
      Unmanaged<RawStore>.fromOpaque($0).release()
    }

    switch code {
    case 0:
      return key
    case EAGAIN:
      keyCreateFailedWith(reason: "EAGAIN")
    case ENOMEM:
      keyCreateFailedWith(reason: "ENOMEM")
    default:
      keyCreateFailedWith(reason: "code \(code)")
    }
  }()

  @available(iOS 13, macOS 10.15, *)
  private nonisolated(unsafe) static var taskLocalStore = TaskLocal<RawStore?>(wrappedValue: nil)

  private init(taskID: ObjectIdentifier?) {
    self.args = ArgsStack()
    self.owningTaskID = taskID
  }

  /// RawStore for current thread.
  ///
  /// RawStore must be present in current context, otherwise this method will crash.
  /// This is achieved by calling `onRootScopeCreation` and `onRootScopeEnd`
  /// in the beginning and end of the root scope.
  @usableFromInline
  internal static func current() -> RawStore {
    measure(.rawStoreCurrent) {
      let store: RawStore? =
        if #available(iOS 13, macOS 10.15, *) {
          fromTSD() ?? fromTaskLocal()
        } else {
          fromTSD()
        }
      guard let store else {
        noStoreAssociatedWithCurrentContext()
      }
      return store
    }
  }

  /// This method is called in the beginning of the root scope,
  /// and must be balanced with `onRootScopeEnd` when exiting the scope.
  ///
  /// Failing to do so will result in incorrect internal state and most likely crash.
  ///
  /// It checks if there is already store in current context, and if not, creates new one
  /// and associates it with current context.
  @usableFromInline
  internal static func onRootScopeCreation() -> RawStore {
    measure(.rawStoreOnRootScopeCreation) {
      let inferredStore: RawStore
      if let tsdStore = fromTSD() {
        // There is already store in TSD, that means current context is sync
        inferredStore = tsdStore
      } else {
        // If there is no store in TSD, that means current context is either async
        // or store is not created yet
        if #available(iOS 13, macOS 10.15, *), isAsyncContext() {
          // Context is async, checking if there is store in task local
          let taskID = currentTaskID()
          if let taskLocalStore = fromTaskLocal() {
            if let taskID, taskLocalStore.owningTaskID != taskID {
              let newStore = Self(taskID: taskID)
              inferredStore = newStore
              Self.taskLocalStore.push(newStore)
            } else {
              // If there is, using it
              inferredStore = taskLocalStore
            }
          } else {
            // or creating new
            let newStore = Self(taskID: taskID)
            inferredStore = newStore
            Self.taskLocalStore.push(newStore)
          }
        } else {
          // Context is sync, no store in TSD, creating new
          let newStore = Self(taskID: nil)
          inferredStore = newStore
          setToTSD(newStore)
        }
      }
      inferredStore.rootScopeStackCount += 1
      return inferredStore
    }
  }

  @usableFromInline
  internal func onRootScopeEnd() {
    rootScopeStackCount -= 1
    if rootScopeStackCount == 0 {
      if #available(iOS 13, macOS 10.15, *), isAsyncContext() {
        Self.taskLocalStore.pop()
      } else {
        Self.clearTSD()
      }
    }
  }

  /// Pushes a new context to the stack.
  @usableFromInline
  internal func push() {
    args.push()
  }

  /// Pushes a new context to the stack, replacing the current context.
  /// Usefull when there is no need to inherit previous context.
  /// - Parameters:
  ///   - ctx: The new context.
  @usableFromInline
  internal func push(replacingCurrent ctx: Arguments) {
    args.pushReplacing(with: ctx)
  }

  /// Returns the current context.
  /// - Returns: The current context.
  internal func getContext() -> Arguments {
    args.args
  }

  /// Pops the current context from the stack.
  @usableFromInline
  internal func pop() {
    args.pop()
  }

  /// Returns the value for the given key.
  @usableFromInline
  internal subscript(key: ImplicitKeyIdentifier) -> Entry? {
    get { measure(.rawStoreSubscriptGet) { args[key] } }
    set { measure(.rawStoreSubscriptSet) { args[key] = newValue } }
  }

  // MARK: - Private helper methods for TSD and TaskLocal

  private static func fromTSD() -> Self? {
    measure(.control) { /* noop */ }
    return measure(.rawStoreFromTSD) {
      guard let ptr = pthread_getspecific(key) else {
        return nil
      }
      let store = Unmanaged<Self>.fromOpaque(ptr).takeUnretainedValue()
      return store
    }
  }

  private static func setToTSD(_ store: RawStore) {
    pthread_setspecific(key, Unmanaged.passRetained(store).toOpaque())
  }

  private static func clearTSD() {
    pthread_setspecific(key, nil)
  }

  @available(iOS 13, macOS 10.15, *)
  private static func fromTaskLocal() -> RawStore? {
    taskLocalStore.get()
  }

  #if DEBUG
  internal func dumpCurrentScope() -> [(key: String, value: any Any)] {
    args.args
      .map { key, value in
        (key.debugDescription, value.anyValue)
      }
      .sorted { lhs, rhs in
        lhs.0 < rhs.0
      }
  }
  #endif
}

extension RawStore {
  fileprivate struct ArgsStack {
    // Using journaled approach here. Recording all modifications in "journal"
    // and restoring them on pop()
    enum Modification {
      case push
      case pushReplacing(oldArgs: Arguments)
      case set(old: ImplicitKeyIdentifier, Entry?)
    }

    var journal: [Modification] = []
    var args: Arguments = [:]

    @inline(__always)
    init() {
      self.journal = []
      self.args = [:]
    }

    @inline(__always)
    subscript(key: ImplicitKeyIdentifier) -> Entry? {
      get {
        args[key]
      }
      set {
        let oldValue = args.removeValue(forKey: key)
        journal.append(.set(old: key, oldValue))
        args[key] = newValue
      }
    }

    @inline(__always)
    mutating func push() {
      journal.append(.push)
    }

    @inline(__always)
    mutating func pushReplacing(with newArgs: Arguments) {
      journal.append(.pushReplacing(oldArgs: args))
      args = newArgs
    }

    @inline(__always)
    mutating func pop() {
      loop:
        while let last = journal.popLast() {
        switch last {
        case let .set(oldKey, oldValue):
          args[oldKey] = oldValue
        case let .pushReplacing(oldArgs):
          args = oldArgs
          break loop
        case .push:
          break loop
        }
      }
    }
  }
}

private func keyCreateFailedWith(reason: String) -> Never {
  fatalError("pthread_key_create failed with \(reason)")
}

private func noStoreAssociatedWithCurrentContext() -> Never {
  fatalError("No implicit store associated with current context")
}

/// A base class for stored values.
///
/// Actual values are stored in subclasses of this class.
@usableFromInline
class EntryAbstract {
  @inlinable
  init() {}

  @inlinable
  deinit {}

  #if DEBUG
  @inlinable
  var anyValue: any Any { fatalError() }
  #endif
}
