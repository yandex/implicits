# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Implicits is a Swift library for implicit parameter passing through call stacks, similar to implicit parameters in Scala or context receivers in Kotlin.

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

## Testing

This project follows **strict TDD**:
1. Write a test that exercises the bug or feature
2. Run it and verify it fails — if it passes, either the bug doesn't exist or the test is wrong; this step catches false assumptions and prevents shipping unnecessary code
3. Implement the fix or feature
4. Verify the test passes

- Integration tests are in `Sources/TestResources/test_data/` - check these for examples when implementing new features
- Tests use inline annotations (e.g., `// expected-error`, `// expect-syntax:`) to specify expected behavior

## Important Constraints

- Static analysis requires explicit type annotations (limited type inference)
- No support for dynamic dispatch (protocols, closures) in static analysis
- Scope objects must be explicitly passed as function parameters