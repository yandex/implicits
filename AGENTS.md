## Project Overview

Implicits is a Swift library for implicit parameter passing through call stacks, similar to implicit parameters in Scala or context receivers in Kotlin.

## Usage Guide

@skills/implicits-usage-guide/SKILL.md

## Development Process

### TDD

Every bug fix, feature, or implementation must follow these steps in order:

1. Write a test that exercises the bug or feature
2. Run it and verify it fails
3. Implement the fix or feature
4. Verify the test passes

If the test passes in step 2, either the bug doesn't exist or the test is wrong. The failing test tells you exactly what's broken and where. Without it, you're guessing — you'll waste time investigating why existing tests pass, make wrong assumptions, and "fix" things that weren't the problem.

After implementing new features, keep `README.md` and `skills/implicits-usage-guide/SKILL.md` up to date.

## Common Development Commands

### Building
```bash
swift build                           # Build entire package
swift build --product Implicits      # Build specific product
swift build --product ImplicitsTool
```

### Testing
```bash
swift test                           # Run all tests
swift test --filter ImplicitsTests   # Run specific test targets
swift test --filter ImplicitsToolTests
swift test --parallel                # Run tests in parallel
```

### Benchmarks
Benchmarks of the implicit store live in the separate `Benchmarks/` package (ordo-one/benchmark), so the library doesn't depend on it. They refuse to run without deterministic hashing:
```bash
SWIFT_DETERMINISTIC_HASHING=1 swift package --package-path Benchmarks benchmark                        # Run all benchmarks
SWIFT_DETERMINISTIC_HASHING=1 swift package --package-path Benchmarks benchmark baseline update main   # Save the current results as baseline "main"
SWIFT_DETERMINISTIC_HASHING=1 swift package --package-path Benchmarks benchmark baseline compare main  # Compare a change against it
```
Even with fixed hashing, the store's layout follows metadata addresses, so instruction counts move between builds and boots (up to 20% on declare), and one run against one run can't call a regression; `Benchmarks/compare.py` compares builds over several process runs. `Benchmarks/README.md` has the results and where the time and memory go. A release build takes about five minutes, because the new-type benchmarks generate 10,000 types.

### Formatting
```bash
swiftformat .    # Run SwiftFormat (reads .swiftformat config automatically)
```

### Static Analysis
The ImplicitsAnalysisPlugin runs automatically during build for targets that use it (Showcase and ShowcaseDependency). To run the analysis tool directly:
```bash
swift run implicits-tool-spm-plugin <args-file>
```

## Key Design Patterns

1. **Scope-Based Lifetime Management**
   - Always use `defer { scope.end() }` after creating an ImplicitScope
   - Scopes must be explicitly passed as parameters due to Swift limitations

2. **Type vs Named Keys**
   - Type keys: Use the type itself as key (e.g., `@Implicit var network: NetworkService`)
   - Named keys: For multiple values of same type, define in `ImplicitsKeys` extension

3. **Closure Capture Pattern**
   ```swift
   let closure = { [implicits = #implicits] in
     let scope = ImplicitScope(with: implicits)
     defer { scope.end() }
     // ...
   }
   ```

## Analyzer Architecture

The static analyzer (`ImplicitsTool`) is a three-stage pipeline: `SyntaxTreeBuilder` → `SemaTreeBuilder` → `RequirementsGraphBuilder`. Scope dataflow — the local/inherited/none state machine, writability, nesting, scope-end and other cross-statement scope rules — lives only in the last stage (`CodeBlockState`); add scope rules there, not in the earlier stages.

Source-level name literals (keywords, identifiers, attribute names) live in `ImplicitKeyword` (`Constants.swift`) — reference them, don't hardcode strings like `"testable"`. Semantic predicates over an attribute (`isImplicit`, `isTestable`, `importAttribute`, …) all live in `SyntaxTreeAttribute.swift`; add new ones there, not inline in a builder. Structural extensions on `SyntaxTree.Attribute` (`mapSyntax`, `render`) stay beside their siblings instead.

## Testing

**Necessity and sufficiency principle**: Every test must add unique use case coverage. Don't write tests for the sake of tests - each test should verify a specific behavior that isn't already covered.

Analyzer regression tests are the `test_data/*.swift` files in `Sources/TestResources/test_data/` (run from `StaticAnalysisTests.swift`): ordinary Swift exercising the analyzer, with expected diagnostics asserted by inline comments. They look like:

```swift
private func entry() {
  // expected-error@+1 {{Using implicits without 'ImplicitScope'}}
  @Implicit() var v: Int
}
```

`@+1` points the comment at the next line; omit it to annotate the same line. Also `expected-note`/`expected-warning` and `expected-key …` for key declarations. The harness matches diagnostics as a set — an unexpected one fails just like a missing one.

Every file under `test_data/` is also a build input: the `__TestResourcesCompilation` target compiles the whole directory against `Implicits` + `AnotherModule`, so each test-data and snapshot file must be valid Swift importing only real modules (`Implicits`, `AnotherModule`, or system frameworks) — you can't `import` a made-up module to exercise import handling. Some tests also assert the generated support file against a checked-in `*_snapshot.swift`; when rendering changes, update that snapshot and keep it compilable too.

## File Organization

- **Main type first**: The primary type of a file goes at the top. If a file is named `Foo.swift`, the `Foo` type should be at the top.
- **Helper/utility types at the bottom**: Supporting structs, enums, extensions, and helper types go after the main type, not before it.
- **Extensions of the main type**: Prefer the type's own body for its members and nested types; use a same-file extension only to group a distinct concern, and place it immediately after the main type definition. Keep companion nested types together rather than leaving one free-floating.
- **Extensions of other types**: Place extensions of unrelated types (like `DiagnosticMessage`) at the bottom.

## Important Constraints

- Static analysis requires explicit type annotations (limited type inference)
- No support for dynamic dispatch (protocols, closures) in static analysis
- Scope objects must be explicitly passed as function parameters