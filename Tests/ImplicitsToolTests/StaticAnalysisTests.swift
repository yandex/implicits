// Copyright 2023 Yandex LLC. All rights reserved.

import Testing

struct StaticAnalysisTests {
  @Test func syntaxStructure() {
    verify(file: "syntax_structure.swift")
  }

  @Test func basicGraph() {
    verify(file: "graph_basic.swift")
  }

  @Test func nestedScopes() {
    verify(file: "nested_scope.swift")
  }

  @Test func recursion() {
    verify(file: "graph_recursion.swift")
  }

  @Test func objectScope() {
    verify(file: "object_scope.swift")
  }

  @Test func symbolResolution() {
    verify(file: "symbol_resolution.swift")
  }

  @Test func implicitBag() {
    verify(file: "implicit_bag.swift")
  }

  @Test func storedImplicitBag() {
    verify(file: "stored_implicit_bag.swift")
  }

  @Test func implicitScopeOrder() {
    verify(file: "implicit_scope_order.swift")
  }

  @Test func keyResolving() {
    verify(file: "key_resolving.swift")
  }

  @Test func expressions() {
    verify(file: "expressions.swift")
  }

  @Test func implicitMap() {
    verify(file: "implicit_map.swift")
  }

  @Test func withScope() {
    verify(file: "with_scope.swift")
  }

  @Test func withNamedImplicits() {
    verify(file: "with_named_implicits.swift")
  }

  @Test func generatedInit() {
    verify(file: "generated_init.swift")
  }

  @Test func typeResolution() {
    verify(file: "type_resolution.swift")
  }

  @Test func multipleFileResolution() {
    verify(files: [
      "multiple_file_resolution_f1.swift",
      "multiple_file_resolution_f2.swift",
    ])
  }

  @Test func usingImplicitInterface() {
    verify(
      files: [
        "using_implicit_interface.swift",
      ],
      dependencies: [anotherModule]
    )
  }

  @Test func usingTestableImplicitInterface() {
    verify(
      files: [
        "using_testable_implicit_interface.swift",
      ],
      dependencies: [anotherModule]
    )
  }

  @Test func exporting() {
    verify(file: "exporting.swift", enableExporting: true)
  }

  @Test func supportFile() {
    verify(
      files: ["support_file.swift"],
      enableExporting: true,
      supportFile: "support_file_snapshot.swift",
      dependencies: [
        (modulename: "AnotherModule", files: ["another_module.swift"]),
      ]
    )
  }

  @Test func ifConfigFiltering() {
    verify(file: "if_config_filtering.swift", compilationConditions: ["A", "B", "C"])
  }
}

private let anotherModule = (modulename: "AnotherModule", files: ["another_module.swift"])
