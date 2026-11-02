# Benchmarks

Benchmarks of the implicit store, on [ordo-one/benchmark](https://github.com/ordo-one/benchmark).

| benchmark | what one operation is |
|---|---|
| Retrieve Int | `@Implicit() var v: Int` from a store with 20 other values, on a thread outside any task |
| Retrieve Int inside a task | the same inside a task, where the store is a task-local value |
| Retrieve any Service | the same for an `any Service` |
| Retrieve struct with a String | the same for a struct with a heap-allocated string |
| Declare Int in a nested scope | `outer.nested()`, one `@Implicit var v = 42`, `scope.end()` |
| New types: first / second declare and retrieve | declare and retrieve a value of a type the process has never stored, then the same again; the difference is the one-time cost of a new type |

The new-type benchmarks run over types generated at build time (`protocol P<i>`, `final class C<i>: P<i>`, values `C<i>() as any P<i>`), so the code under test is specialized for each type, as in an app.

## Running

```bash
SWIFT_DETERMINISTIC_HASHING=1 swift package --package-path Benchmarks benchmark
```

The store is a dictionary keyed by type metadata addresses. With a per-process hash seed its layout, and so the instruction counts, would change on every run. Even with a fixed seed the addresses change between builds and, on macOS, between boots, so a single run against a single run can't show a regression.

## Comparing revisions

```bash
swift run -c release --package-path Benchmarks compare-builds \
  --repository . --work-directory Benchmarks/.build/compare-builds main HEAD
```

`--help` describes how it runs and what it reports. A small difference can still be layout alone: confirm it in a profile before crediting the change.
