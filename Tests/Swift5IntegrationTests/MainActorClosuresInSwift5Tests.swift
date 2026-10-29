internal import Implicits
import Testing

@MainActor
struct MainActorClosuresInSwift5Tests {
  @Test func `closure reads implicits and keeps a non-Sendable capture`() {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit var greeting = Greeting(text: "Hi")
    let log = Log()

    let greet = #withImplicits(isolation: .mainActor) { _ in
      @Implicit() var greeting: Greeting
      log.lines.append(greeting.text)
      return greeting.text
    }

    #expect(greet() == "Hi")
    #expect(log.lines == ["Hi"])
  }

  @Test func `async throwing closure`() async throws {
    let scope = ImplicitScope()
    defer { scope.end() }

    @Implicit var greeting = Greeting(text: "Hello")

    let greet = #withImplicits(isolation: .mainActor) { _ in
      @Implicit() var greeting: Greeting
      return try await shout(greeting.text)
    }

    let result = try await greet()
    #expect(result == "HELLO")
  }
}

struct Greeting {
  var text: String
}

final class Log {
  var lines: [String] = []
}

@MainActor private func shout(_ text: String) async throws -> String {
  text.uppercased()
}
