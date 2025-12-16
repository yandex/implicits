// Copyright 2023 Yandex LLC. All rights reserved.

import Testing

import ImplicitsToolMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport

private let testMacros: [String: Macro.Type] = [
  "GeneralVisitorMacro": GeneralVisitorMacro.self,
]

struct GeneralVisitorMacroTests {
  @Test func generalVisitorFailOnClass() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      class GeneralVisitor {}
      """,
      expandedSource: """
      class GeneralVisitor {}
      """,
      diagnostics: [declarationError],
      macros: testMacros
    )
  }

  @Test func generalVisitorFailOnStructWithNoGeneric() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct GeneralVisitor {}
      """,
      expandedSource: """
      struct GeneralVisitor {}
      """,
      diagnostics: [declarationError],
      macros: testMacros
    )
  }

  @Test func generalVisitorFailOnStructWithMoreThanOneGeneric() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct GeneralVisitor<One, Two> {}
      """,
      expandedSource: """
      struct GeneralVisitor<One, Two> {}
      """,
      diagnostics: [declarationError],
      macros: testMacros
    )
  }

  @Test func generalVisitorSuccessOnEmptyStructWithOneGeneric() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct GeneralVisitor<S> {}
      """,
      expandedSource: """
      struct GeneralVisitor<S> {}

      extension GeneralVisitor {
          fileprivate final class StatefulSyntaxVisitor: SyntaxVisitor {
              var state: S
              required init(state: S) {
                  self.state = state
                  super.init(viewMode: .fixedUp)
              }
          }
          fileprivate func makeVisitor(state: S) -> StatefulSyntaxVisitor {
              StatefulSyntaxVisitor(state: state)
          }
          func lense<UpState>(_ kp: WritableKeyPath<UpState, S>) -> GeneralVisitor<UpState> {
              GeneralVisitor<UpState>()
          }
      }
      """,
      macros: testMacros
    )
  }

  @Test func generalVisitorSuccessOnEmptyStructWithOneGenericAndDifferentName() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct SomeVisitor<S> {}
      """,
      expandedSource: """
      struct SomeVisitor<S> {}

      extension SomeVisitor {
          fileprivate final class StatefulSyntaxVisitor: SyntaxVisitor {
              var state: S
              required init(state: S) {
                  self.state = state
                  super.init(viewMode: .fixedUp)
              }
          }
          fileprivate func makeVisitor(state: S) -> StatefulSyntaxVisitor {
              StatefulSyntaxVisitor(state: state)
          }
          func lense<UpState>(_ kp: WritableKeyPath<UpState, S>) -> SomeVisitor<UpState> {
              SomeVisitor<UpState>()
          }
      }
      """,
      macros: testMacros
    )
  }

  @Test func generalVisitorSuccessOnStructWithOneGenericAndNoVisitors() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct GeneralVisitor<State> {
        typealias Visitor<K> = (inout State, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

        func walk(
          initial: State, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }
      """,
      expandedSource: """
      struct GeneralVisitor<State> {
        typealias Visitor<K> = (inout State, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

        func walk(
          initial: State, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }

      extension GeneralVisitor {
          fileprivate final class StatefulSyntaxVisitor: SyntaxVisitor {
              var state: State
              required init(state: State) {
                  self.state = state
                  super.init(viewMode: .fixedUp)
              }
          }
          fileprivate func makeVisitor(state: State) -> StatefulSyntaxVisitor {
              StatefulSyntaxVisitor(state: state)
          }
          func lense<UpState>(_ kp: WritableKeyPath<UpState, State>) -> GeneralVisitor<UpState> {
              GeneralVisitor<UpState>()
          }
      }
      """,
      macros: testMacros
    )
  }

  @Test func generalVisitorSuccessOnStructWithOneGenericAndOneVisitor() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct GeneralVisitor<State> {
        typealias Visitor<K> = (inout State, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

        var someVisitor: Visitor<ClassDeclSyntax> = emptyVisitor()

        func walk(
          initial: State, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }
      """,
      expandedSource: """
      struct GeneralVisitor<State> {
        typealias Visitor<K> = (inout State, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

        var someVisitor: Visitor<ClassDeclSyntax> = emptyVisitor()

        func walk(
          initial: State, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }

      extension GeneralVisitor {
          fileprivate final class StatefulSyntaxVisitor: SyntaxVisitor {
              var state: State
              var someVisitor: Visitor<ClassDeclSyntax>
              required init(state: State, someVisitor: @escaping Visitor<ClassDeclSyntax>) {
                  self.state = state
                  self.someVisitor = someVisitor
                  super.init(viewMode: .fixedUp)
              }
              override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
                  visitGeneral(someVisitor, node)
              }
          }
          fileprivate func makeVisitor(state: State) -> StatefulSyntaxVisitor {
              StatefulSyntaxVisitor(state: state, someVisitor: someVisitor)
          }
          func lense<UpState>(_ kp: WritableKeyPath<UpState, State>) -> GeneralVisitor<UpState> {
              GeneralVisitor<UpState> { upState, visitee in
                  someVisitor(&upState[keyPath: kp], visitee)
              }
          }
      }
      """,
      macros: testMacros
    )
  }

  @Test func generalVisitorSuccessOnStructWithOneGenericAndTwoSameVisitors() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct GeneralVisitor<State> {
        typealias Visitor<K> = (inout State, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

        var someVisitor: Visitor<ClassDeclSyntax> = emptyVisitor()
        var anotherVisitor: Visitor<ClassDeclSyntax> = emptyVisitor()

        func walk(
          initial: State, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }
      """,
      expandedSource: """
      struct GeneralVisitor<State> {
        typealias Visitor<K> = (inout State, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

        var someVisitor: Visitor<ClassDeclSyntax> = emptyVisitor()
        var anotherVisitor: Visitor<ClassDeclSyntax> = emptyVisitor()

        func walk(
          initial: State, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }
      """,
      diagnostics: [sameVisitorsError],
      macros: testMacros
    )
  }

  @Test func generalVisitorSuccessOnStructWithOneGenericAndOneRandomVariable() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct GeneralVisitor<State> {
        var someVariable: Int = 5

        func walk(
          initial: State, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }
      """,
      expandedSource: """
      struct GeneralVisitor<State> {
        var someVariable: Int = 5

        func walk(
          initial: State, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }

      extension GeneralVisitor {
          fileprivate final class StatefulSyntaxVisitor: SyntaxVisitor {
              var state: State
              required init(state: State) {
                  self.state = state
                  super.init(viewMode: .fixedUp)
              }
          }
          fileprivate func makeVisitor(state: State) -> StatefulSyntaxVisitor {
              StatefulSyntaxVisitor(state: state)
          }
          func lense<UpState>(_ kp: WritableKeyPath<UpState, State>) -> GeneralVisitor<UpState> {
              GeneralVisitor<UpState>()
          }
      }
      """,
      macros: testMacros
    )
  }

  @Test func generalVisitorSuccessOnStructWithDifferentlyNamedGeneric() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct GeneralVisitor<Foo> {
        typealias Visitor<K> = (inout Foo, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

        var visitClassDecl: Visitor<ClassDeclSyntax> = emptyVisitor()
        var visitClosureExpr: Visitor<ClosureExprSyntax> = emptyVisitor()
        var visitVariableDecl: Visitor<VariableDeclSyntax> = emptyVisitor()

        func walk(
          initial: Foo, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }
      """,
      expandedSource: """
      struct GeneralVisitor<Foo> {
        typealias Visitor<K> = (inout Foo, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

        var visitClassDecl: Visitor<ClassDeclSyntax> = emptyVisitor()
        var visitClosureExpr: Visitor<ClosureExprSyntax> = emptyVisitor()
        var visitVariableDecl: Visitor<VariableDeclSyntax> = emptyVisitor()

        func walk(
          initial: Foo, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }

      extension GeneralVisitor {
          fileprivate final class StatefulSyntaxVisitor: SyntaxVisitor {
              var state: Foo
              var visitClassDecl: Visitor<ClassDeclSyntax>
              var visitClosureExpr: Visitor<ClosureExprSyntax>
              var visitVariableDecl: Visitor<VariableDeclSyntax>
              required init(state: Foo, visitClassDecl: @escaping Visitor<ClassDeclSyntax>, visitClosureExpr: @escaping Visitor<ClosureExprSyntax>, visitVariableDecl: @escaping Visitor<VariableDeclSyntax>) {
                  self.state = state
                  self.visitClassDecl = visitClassDecl
                  self.visitClosureExpr = visitClosureExpr
                  self.visitVariableDecl = visitVariableDecl
                  super.init(viewMode: .fixedUp)
              }
              override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
                  visitGeneral(visitClassDecl, node)
              }
              override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
                  visitGeneral(visitClosureExpr, node)
              }
              override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
                  visitGeneral(visitVariableDecl, node)
              }
          }
          fileprivate func makeVisitor(state: Foo) -> StatefulSyntaxVisitor {
              StatefulSyntaxVisitor(state: state, visitClassDecl: visitClassDecl, visitClosureExpr: visitClosureExpr, visitVariableDecl: visitVariableDecl)
          }
          func lense<UpState>(_ kp: WritableKeyPath<UpState, Foo>) -> GeneralVisitor<UpState> {
              GeneralVisitor<UpState> { upState, visitee in
                  visitClassDecl(&upState[keyPath: kp], visitee)
              } visitClosureExpr: { upState, visitee in
                  visitClosureExpr(&upState[keyPath: kp], visitee)
              } visitVariableDecl: { upState, visitee in
                  visitVariableDecl(&upState[keyPath: kp], visitee)
              }
          }
      }
      """,
      macros: testMacros
    )
  }

  @Test func generalVisitorSuccessOnStructWithDifferentlyNamedVisitorAlias() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct GeneralVisitor<Foo> {
        typealias SomeVisitor<K> = (inout Foo, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> SomeVisitor<K> { { _, _ in .visitChildren } }

        var visitClassDecl: SomeVisitor<ClassDeclSyntax> = emptyVisitor()
        var visitClosureExpr: SomeVisitor<ClosureExprSyntax> = emptyVisitor()
        var visitVariableDecl: SomeVisitor<VariableDeclSyntax> = emptyVisitor()

        func walk(
          initial: Foo, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }
      """,
      expandedSource: """
      struct GeneralVisitor<Foo> {
        typealias SomeVisitor<K> = (inout Foo, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> SomeVisitor<K> { { _, _ in .visitChildren } }

        var visitClassDecl: SomeVisitor<ClassDeclSyntax> = emptyVisitor()
        var visitClosureExpr: SomeVisitor<ClosureExprSyntax> = emptyVisitor()
        var visitVariableDecl: SomeVisitor<VariableDeclSyntax> = emptyVisitor()

        func walk(
          initial: Foo, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }

      extension GeneralVisitor {
          fileprivate final class StatefulSyntaxVisitor: SyntaxVisitor {
              var state: Foo
              var visitClassDecl: SomeVisitor<ClassDeclSyntax>
              var visitClosureExpr: SomeVisitor<ClosureExprSyntax>
              var visitVariableDecl: SomeVisitor<VariableDeclSyntax>
              required init(state: Foo, visitClassDecl: @escaping SomeVisitor<ClassDeclSyntax>, visitClosureExpr: @escaping SomeVisitor<ClosureExprSyntax>, visitVariableDecl: @escaping SomeVisitor<VariableDeclSyntax>) {
                  self.state = state
                  self.visitClassDecl = visitClassDecl
                  self.visitClosureExpr = visitClosureExpr
                  self.visitVariableDecl = visitVariableDecl
                  super.init(viewMode: .fixedUp)
              }
              override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
                  visitGeneral(visitClassDecl, node)
              }
              override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
                  visitGeneral(visitClosureExpr, node)
              }
              override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
                  visitGeneral(visitVariableDecl, node)
              }
          }
          fileprivate func makeVisitor(state: Foo) -> StatefulSyntaxVisitor {
              StatefulSyntaxVisitor(state: state, visitClassDecl: visitClassDecl, visitClosureExpr: visitClosureExpr, visitVariableDecl: visitVariableDecl)
          }
          func lense<UpState>(_ kp: WritableKeyPath<UpState, Foo>) -> GeneralVisitor<UpState> {
              GeneralVisitor<UpState> { upState, visitee in
                  visitClassDecl(&upState[keyPath: kp], visitee)
              } visitClosureExpr: { upState, visitee in
                  visitClosureExpr(&upState[keyPath: kp], visitee)
              } visitVariableDecl: { upState, visitee in
                  visitVariableDecl(&upState[keyPath: kp], visitee)
              }
          }
      }
      """,
      macros: testMacros
    )
  }

  @Test func generalVisitorCorrectForm() throws {
    assertMacroExpansion(
      """
      @GeneralVisitorMacro
      struct GeneralVisitor<State> {
        typealias Visitor<K> = (inout State, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

        var visitClassDecl: Visitor<ClassDeclSyntax> = emptyVisitor()
        var visitClosureExpr: Visitor<ClosureExprSyntax> = emptyVisitor()
        var visitVariableDecl: Visitor<VariableDeclSyntax> = emptyVisitor()

        func walk(
          initial: State, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }
      """,
      expandedSource: """
      struct GeneralVisitor<State> {
        typealias Visitor<K> = (inout State, K) -> SyntaxVisitorContinueKind
        static func emptyVisitor<K>() -> Visitor<K> { { _, _ in .visitChildren } }

        var visitClassDecl: Visitor<ClassDeclSyntax> = emptyVisitor()
        var visitClosureExpr: Visitor<ClosureExprSyntax> = emptyVisitor()
        var visitVariableDecl: Visitor<VariableDeclSyntax> = emptyVisitor()

        func walk(
          initial: State, syntax: some SyntaxProtocol
        ) -> State {
          let visitor = makeVisitor(state: initial)
          visitor.walk(syntax)
          return visitor.state
        }
      }

      extension GeneralVisitor {
          fileprivate final class StatefulSyntaxVisitor: SyntaxVisitor {
              var state: State
              var visitClassDecl: Visitor<ClassDeclSyntax>
              var visitClosureExpr: Visitor<ClosureExprSyntax>
              var visitVariableDecl: Visitor<VariableDeclSyntax>
              required init(state: State, visitClassDecl: @escaping Visitor<ClassDeclSyntax>, visitClosureExpr: @escaping Visitor<ClosureExprSyntax>, visitVariableDecl: @escaping Visitor<VariableDeclSyntax>) {
                  self.state = state
                  self.visitClassDecl = visitClassDecl
                  self.visitClosureExpr = visitClosureExpr
                  self.visitVariableDecl = visitVariableDecl
                  super.init(viewMode: .fixedUp)
              }
              override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
                  visitGeneral(visitClassDecl, node)
              }
              override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
                  visitGeneral(visitClosureExpr, node)
              }
              override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
                  visitGeneral(visitVariableDecl, node)
              }
          }
          fileprivate func makeVisitor(state: State) -> StatefulSyntaxVisitor {
              StatefulSyntaxVisitor(state: state, visitClassDecl: visitClassDecl, visitClosureExpr: visitClosureExpr, visitVariableDecl: visitVariableDecl)
          }
          func lense<UpState>(_ kp: WritableKeyPath<UpState, State>) -> GeneralVisitor<UpState> {
              GeneralVisitor<UpState> { upState, visitee in
                  visitClassDecl(&upState[keyPath: kp], visitee)
              } visitClosureExpr: { upState, visitee in
                  visitClosureExpr(&upState[keyPath: kp], visitee)
              } visitVariableDecl: { upState, visitee in
                  visitVariableDecl(&upState[keyPath: kp], visitee)
              }
          }
      }
      """,
      macros: testMacros
    )
  }
}

private nonisolated(unsafe) let declarationError = DiagnosticSpec(
  message: "@GeneralVisitorMacro can only be applied to a structure with one generic type",
  line: 1, column: 1
)

private nonisolated(unsafe) let sameVisitorsError = DiagnosticSpec(
  message: "There should be no repeating visitor types as variables of a struct",
  line: 1, column: 1
)
