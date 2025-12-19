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

## Development Process

This project follows **strict TDD (Test-Driven Development)**:
1. Write a test first
2. Verify the test fails
3. Implement the fix
4. Verify the test passes

Almost all code changes in this project happen this way.

## Important Constraints

- Static analysis requires explicit type annotations (limited type inference)
- No support for dynamic dispatch (protocols, closures) in static analysis
- Scope objects must be explicitly passed as function parameters
- Always check `TestResources/test_data` for examples when implementing new features