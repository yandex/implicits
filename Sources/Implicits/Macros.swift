// Copyright 2025 Yandex LLC. All rights reserved.

/// Captures implicit requirements from the enclosing scope for later restoration.
///
/// Store as a property to restore the implicit scope later via `withScope(with:)`.
///
/// Example:
/// ```swift
/// class MyService {
///   let implicits = #implicits
///
///   init(_: ImplicitScope) {}
///
///   func doWork() {
///     withScope(with: implicits) { scope in
///       @Implicit var network: NetworkService
///       // ...
///     }
///   }
/// }
/// ```
@freestanding(expression)
public macro implicits() -> Implicits = #externalMacro(
  module: "ImplicitsMacros",
  type: "ImplicitMacro"
)

/// Wraps a closure to capture implicit requirements from the enclosing scope.
///
/// Example:
/// ```swift
/// downloadImage(url: avatarURL, completion: #withImplicits { image, scope in
///   @Implicit var filters: FilterApplier
///   imageView.image = filters.applyBlur(image)
/// })
/// ```
@freestanding(expression)
public macro withImplicits<each A, T>(
  _ body: (repeat each A, ImplicitScope) -> T
) -> (repeat each A) -> T = #externalMacro(
  module: "ImplicitsMacros",
  type: "WithImplicitsMacro"
)

/// Wraps a closure to capture implicit requirements from the enclosing scope.
///
/// Example:
/// ```swift
/// downloadImage(url: avatarURL, completion: #withImplicits { image, scope in
///   @Implicit var filters: FilterApplier
///   imageView.image = filters.applyBlur(image)
/// })
/// ```
@freestanding(expression)
public macro withImplicits<each A, T>(
  _ body: (repeat each A, ImplicitScope) async -> T
) -> (repeat each A) async -> T = #externalMacro(
  module: "ImplicitsMacros",
  type: "WithImplicitsMacro"
)

/// Wraps a closure to capture implicit requirements from the enclosing scope.
///
/// Example:
/// ```swift
/// downloadImage(url: avatarURL, completion: #withImplicits { image, scope in
///   @Implicit var filters: FilterApplier
///   imageView.image = filters.applyBlur(image)
/// })
/// ```
@freestanding(expression)
public macro withImplicits<each A, T>(
  _ body: (repeat each A, ImplicitScope) throws -> T
) -> (repeat each A) throws -> T = #externalMacro(
  module: "ImplicitsMacros",
  type: "WithImplicitsMacro"
)

/// Wraps a closure to capture implicit requirements from the enclosing scope.
///
/// Example:
/// ```swift
/// downloadImage(url: avatarURL, completion: #withImplicits { image, scope in
///   @Implicit var filters: FilterApplier
///   imageView.image = filters.applyBlur(image)
/// })
/// ```
@freestanding(expression)
public macro withImplicits<each A, T>(
  _ body: (repeat each A, ImplicitScope) async throws -> T
) -> (repeat each A) async throws -> T = #externalMacro(
  module: "ImplicitsMacros",
  type: "WithImplicitsMacro"
)
