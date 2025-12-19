@_spi(Unsafe)
import Implicits

// compilationConditions: ["A", "B", "C"]

private func tests() {
  withScope { scope in // expected-error {{Unresolved requirement: UInt8}}
    #if A
    @Implicit var _: UInt8
    #else
    @Implicit var _: UInt16
    #endif
  }

  withScope { scope in // expected-error {{Unresolved requirement: UInt64}}
    #if D
    @Implicit var _: UInt32
    #else
    @Implicit var _: UInt64
    #endif
  }

  withScope { scope in // expected-error {{Unresolved requirements: Int16, Int8}}
    #if os(iOS)
    @Implicit var _: Int8
    #elseif A
    @Implicit var _: Int16
    #else
    @Implicit var _: Int32
    #endif
  }

  withScope { scope in // expected-error {{Unresolved requirement: Int}}
    #if A
      #if D
      @Implicit var _: Float
      #else
      @Implicit var _: Int
      #endif
    #else
    @Implicit var _: Double
    #endif
  }

  withScope { scope in // expected-error {{Unresolved requirement: String}}
    #if A && B
    @Implicit var _: String
    #else
    @Implicit var _: Character
    #endif
  }

  withScope { scope in // expected-error {{Unresolved requirement: Bool}}
    #if !D
    @Implicit var _: Bool
    #else
    @Implicit var _: Never
    #endif
  }
}
