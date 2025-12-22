private func effectDetectionTests() {
  check { await asyncFunc() } // expect-syntax: async
  check { plainFunc() }

  check { try throwingFunc() } // expect-syntax: throws
  check { try? throwingFunc() }
  check { try! throwingFunc() }

  check { try! throwingFunc(try throwingFunc()) }
  check { try? throwingFunc(try throwingFunc()) }

  check { try await asyncThrowingFunc() } // expect-syntax: async, throws
  check { try? await asyncThrowingFunc() } // expect-syntax: async
  check { try! await asyncThrowingFunc() } // expect-syntax: async

  check { let _ = await asyncFunc() } // expect-syntax: async
  check { let _ = try throwingFunc() } // expect-syntax: throws

  check {
    do {
      try throwingFunc()
    } catch {}
  }

  check { // expect-syntax: throws
    do {
      try throwingFunc()
    } catch {
      try throwingFunc()
    }
  }

  check { // expect-syntax: throws
    do {
      try throwingFunc()
    }
  }

  check { if true { await asyncFunc() } } // expect-syntax: async
  check { if true { try throwingFunc() } } // expect-syntax: throws

  check { for _ in [] as [Int] { await asyncFunc() } } // expect-syntax: async
  check { for _ in [] as [Int] { try throwingFunc() } } // expect-syntax: throws

  check { takes(await asyncFunc()) } // expect-syntax: async
  check { takes(try throwingFunc()) } // expect-syntax: throws

  check {
    Task {
      await asyncFunc()
    }
  }

  check {
    check { // expect-syntax: throws
      try throwingFunc()
    }
  }

  check {
    check { // expect-syntax: async
      await asyncFunc()
    }
  }
}

private func check(_ closure: () async throws -> Void) {}
private func asyncFunc() async {}
private func throwingFunc(_: Void? = nil) throws {}
private func asyncThrowingFunc() async throws {}
private func plainFunc() {}
private func takes(_: Void) {}
