import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

package struct SourceLocation {
  package var fileName: String
  package var line: String
  package var column: String

  package init(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws {
    guard let loc = context.location(of: node),
          let fileExpansion = loc.filename else {
      throw DiagnosticsError.at(node, "Unable to get source location")
    }
    let moduleAndFile = fileExpansion.split(separator: "/")
    guard let lastComponent = moduleAndFile.last else {
      throw DiagnosticsError.at(node, "Unable to get file name")
    }
    self.fileName = String(lastComponent)
    self.line = loc.line.trimmedDescription
    self.column = loc.column.trimmedDescription
  }
}

extension AbstractSourceLocation {
  var filename: String? {
    switch file.as(ExprSyntaxEnum.self) {
    case let .stringLiteralExpr(literal):
      literal.representedLiteralValue
    default:
      nil
    }
  }
}
