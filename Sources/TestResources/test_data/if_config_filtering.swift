@_spi(Unsafe)
import Implicits

// compilationConditions: ["A", "B", "C"]

private func tests() {
  withScope { scope in // expected-error {{Unresolved requirement: UInt8}}
    #if A
    @Implicit() var v1: UInt8
    #else
    @Implicit() var v2: UInt16
    #endif
  }

  withScope { scope in // expected-error {{Unresolved requirement: UInt64}}
    #if D
    @Implicit() var v1: UInt32
    #else
    @Implicit() var v1: UInt64
    #endif
  }

  withScope { scope in // expected-error {{Unresolved requirements: Int16, Int8}}
    #if os(iOS)
    @Implicit() var v1: Int8
    #elseif A
    @Implicit() var v1: Int16
    #else
    @Implicit() var v1: Int32
    #endif
  }

  withScope { scope in // expected-error {{Unresolved requirement: Int}}
    #if A
      #if D
      @Implicit() var v1: Float
      #else
      @Implicit() var v1: Int
      #endif
    #else
    @Implicit() var v1: Double
    #endif
  }

  withScope { scope in // expected-error {{Unresolved requirement: String}}
    #if A && B
    @Implicit() var v1: String
    #else
    @Implicit() var v1: Character
    #endif
  }

  withScope { scope in // expected-error {{Unresolved requirement: Bool}}
    #if !D
    @Implicit() var v1: Bool
    #else
    @Implicit() var v1: Never
    #endif
  }
}
