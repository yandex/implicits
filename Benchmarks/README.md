# Benchmarks

Benchmarks of the implicit store, on [ordo-one/benchmark](https://github.com/ordo-one/benchmark). The commands to run them are in `AGENTS.md`; they need `SWIFT_DETERMINISTIC_HASHING=1`.

| benchmark | what one operation is |
|---|---|
| Retrieve Int | `@Implicit() var v: Int` from a store of 21 values, on a plain thread |
| Retrieve Int inside a task | the same inside a Swift task, where the store is a task-local value |
| Retrieve any Service | the same for an `any Service`, five words: an inline buffer, the type and a witness table |
| Retrieve struct with a String | the same for a six-word struct |
| Declare Int in a nested scope | `outer.nested()`, one `@Implicit var v = 42`, `scope.end()` |
| New types: first / second declare and retrieve | declare and retrieve a value of a type the process has never stored, then the same again |

The new-type benchmarks use 10,000 generated types (`protocol P<i>`, `final class C<i>: P<i>`, values `C<i>() as any P<i>`), so the code under test is specialized for each type, as in an app. The first pass minus the second is the one-time cost of a new type.

## Results

Apple M4 Pro, macOS 26.6.2, Swift 6.3.3, release build. Medians of 10 process runs.

| | time | instructions | mallocs |
|---|---|---|---|
| Retrieve Int | 28 ns | 538 | 0 |
| Retrieve Int inside a task | 33 ns | 751 | 0 |
| Retrieve any Service | 32 ns | 654 | 0 |
| Retrieve struct with a String | 30 ns | 571 | 0 |
| Declare Int in a nested scope | 103 ns | 2,413 | 1 |
| New type, first pass | 3.7 µs | 67.7K | 8 |
| New type, second pass | 0.26 µs | 4.1K | 2 |
| **New type, one-time cost** | **3.4 µs** | **63.6K** | 1,043 bytes kept for the life of the process |

### Retrieve

Shares of cycles in Instruments' CPU Profiler for Retrieve Int:

- 22%: exclusivity checks (`swift_beginAccess`/`swift_endAccess`). `EntryConcrete.value` is a `var` in a class, so every read is checked at run time.
- 19%: the dictionary lookup, most of it SipHash of the key's `ObjectIdentifier`.
- 15%: finding the current store in thread-specific data.
- 12%: retain and release of the store and the entry.

Inside a task the store is found only after the thread-specific lookup misses, through `TaskLocal.get()`, which copies `Optional<RawStore>` through value witnesses: 31% of the cycles instead of 15%, and 213 more instructions.

### Declare

- 40%: ending the scope. It undoes the journal: a dictionary removal, then release and free of the entry.
- 20%: the store setter. It removes the old value and inserts the new one, two hash lookups, and appends to the journal.
- 14%: allocating the entry, the benchmark's one malloc.
- 8%: finding the current store.
- About 9% is the benchmark's malloc counter itself, so malloc-heavy benchmarks read slower than they run in an app.

### A new type

94% of the first pass goes to creating type metadata: the specialized code finds `Implicit<ImplicitKey<P<i>, P<i>>>` and `EntryConcrete<any P<i>>` by mangled name, which the runtime demangles, checks the generic requirements of (a conformance lookup for `ImplicitKey: ImplicitKeyType`), allocates and initializes.

What one new type leaves behind, from breakpoints on the runtime's allocation functions:

| what | bytes |
|---|---|
| `EntryConcrete<any P<i>>`: class metadata with its Objective-C class data 320, cache entry 48, copied ivar list 40 | 408 |
| `Implicit<ImplicitKey<…>>`, the property wrapper: metadata 56, its own copy of the value witness table 88, cache entry 56 | 200 |
| `ImplicitKey<P<i>, P<i>>`: metadata 48, cache entry 56 | 104 |
| witness table for `ImplicitKey<…>: ImplicitKeyType` | 40 |
| `any P<i>` existential metadata | 32 |
| Objective-C realization of the value's class `C<i>` (two `class_rw_t`) | 64 |
| growth of the runtime's hash tables, by difference | about 190 |

Metadata comes from the runtime's own pool (a 64 KB static block, then 16 KB pages from malloc), so it shows in malloc counts only as an occasional page. The bytes kept per type are therefore a mean: per thousand types they swing by up to a quarter, depending on whether one of the runtime's hash tables doubled inside that thousand.

The wrapper's metadata is needed only because the value is address-only: the specialized code copies `Implicit<…>` through its value witness table. For a class value (`C<i>()` without `as any P<i>`) there is no wrapper metadata, no existential and no witness table, and the one-time cost halves to 1.7 µs and 589 bytes. Temporary control benchmarks that touched only part of the chain gave this split for existential values:

| touched | one-time time | instructions | bytes kept |
|---|---|---|---|
| the value only | 0.45 µs | 9.5K | 105 |
| + `ImplicitKey` | 0.9 µs | 18.9K | 224 |
| + the `Implicit` wrapper | 1.85 µs | 36.3K | 589 |
| declare and retrieve | 3.4 µs | 63.6K | 1,043 |

## Storage alternatives

The store keeps each value in an `EntryConcrete<T>`, a generic subclass of `EntryAbstract`, and each new `T` costs a class metadata. Four alternatives were measured by building the suite against patched copies of the library:

- `let value`: `EntryConcrete` with `let value` instead of `var value`.
- `Any` holding `() -> T`: set `{ newValue } as () -> T`, get `(entry as! () -> T)()`.
- `() -> Any`: a struct with a closure returning `Any`, get `entry.get() as! T`.
- writer: a struct with a closure `(UnsafeMutableRawBufferPointer) -> Void` that writes the value into a buffer the reader provides; get allocates the buffer on the stack and moves the value out. No cast and no per-type metadata.

Medians of 10 interleaved process runs; the change is shown when its bootstrap 95% interval excludes zero.

| | main | `let value` | `Any` holding `() -> T` | `() -> Any` | writer |
|---|---|---|---|---|---|
| Retrieve Int | 28 ns | 24 ns, −11% | 39 ns, +42% | 37 ns, +35% | 26 ns, −4% |
| Retrieve Int inside a task | 33 ns | 30 ns, −9% | 44 ns, +33% | 42 ns, +28% | 32 ns, −5% |
| Retrieve any Service | 32 ns | 29 ns, −10% | 42 ns, +31% | 116 ns, +257%, 1 malloc | 32 ns |
| Retrieve struct with a String | 30 ns | 27 ns, −9% | 41 ns, +37% | 76 ns, +156%, 1 malloc | 28 ns, −4% |
| Declare Int in a nested scope | 103 ns | 103 ns | 145 ns, +41% | 97 ns, −5% | 99 ns, −4% |
| New type, one-time time | 3.4 µs | 3.4 µs | 2.6 µs, −25% | 19.8 µs, +480% | 2.3 µs, −33% |
| New type, one-time instructions | 63.6K | 63.7K | 47.8K, −25% | 488K, +667% | 43.2K, −32% |
| New type, bytes kept | 1,043 | 1,043 | 650 | 546 | 597 |

Why:

- `let value` removes the run-time exclusivity check on every read. Nothing else changes.
- `Any` holding `() -> T` retrieves through a dynamic cast: it unwraps the `Any`, compares the stored function type with `() -> T`, copies the closure and retains its context, then calls it. Declare is slower because the entry is now a four-word `Any` instead of one reference: every copy and destroy of it in the dictionary and the scope journal goes through the value witnesses of whatever is inside (35% of declare's cycles). Per new type it drops `EntryConcrete` but adds the function type `() -> T` (40 bytes and about 4K instructions).
- `() -> Any` casts from `Any` on every read. `any Service` is five words and `Any` holds three inline, so each read boxes the value on the heap, and `Any as! any Service` looks up the conformance twice: once for `Any` itself, which fails, then for the unwrapped type. A six-word struct is boxed too. The first cast to a new protocol finds no cached conformance and scans every conformance record in the process: 83% of the first pass, with the suite's 10,000 generated conformances among the records. In an app this cost grows with the number of conformances in it.
- The writer keeps main's hot path and per type creates exactly what the wrapper control above does: no class metadata, no function type, no cast.
- The 4–5% that the writer and `() -> Any` gain on declare, and the writer's 4% on retrieve, are dictionary layout, not storage (next section).
- The writer and `() -> Any` allocate the same per new type, except that `() -> Any` adds two entries to the runtime's conformance cache. The 51 bytes between their means come from where the runtime's hash tables reallocate relative to the measured thousands, not from either storage: with the runner's allocation-stack recording on, the order flips, 889 bytes for the writer against 1,071 for `() -> Any`.

### Entries without a cast

A second round compared entries that read the value without any dynamic cast, each trusting the key to give the right `T`, as `unsafeDowncast` does on main:

- closure downcast: the entry is `() -> Any`, set stores `unsafeBitCast({ newValue } as () -> T, to: (() -> Any).self)`, get calls `unsafeBitCast(entry, to: (() -> T).self)()`. Both casts must be `unsafeBitCast`: a plain conversion to `() -> Any` wraps the closure in a reabstraction thunk.
- box: one non-generic `ManagedBuffer<Any.Type, SIMD2<UInt64>>` subclass. The header holds `T.self`, the value sits in the tail, and the deinit passes the stored type to a generic function that destroys the value. The `SIMD2<UInt64>` element only aligns the tail to 16 bytes. About 20 lines; a longer version with a byte tail and alignment arithmetic measured the same.
- `Any` opened: the entry is the value as `Any`, get opens it with `_openExistential` and bit-casts the opened value to `T`.

Instructions per operation, one build each, medians of 10 interleaved process runs. Retrieve and declare are given for two dictionary layouts (the second with `SWIFT_DEBUG_ENABLE_METADATA_ALLOCATION_ITERATION=1`, see the next section). The "entry alone" rows count the entry outside the dictionary, in a harness of a million reads or creates, so they don't depend on layout.

| | main | closure downcast | box | `Any` opened |
|---|---|---|---|---|
| Retrieve Int | 540 / 541 | 551 / 530 | 475 / 524 | 478 / 549 |
| Retrieve any Service | 635 / 637 | 625 / 654 | 586 / 576 | 662 / 642 |
| Declare Int in a nested scope | 2,648 / 2,507 | 2,658 / 2,468 | 3,154 / 2,636 | 2,214 / 2,554 |
| Entry alone: read Int | 77 | 53 | 2 | 150 |
| Entry alone: read any Service | 152 | 125 | 77 | 265 |
| Entry alone: create and destroy Int | 615 | 577 | 658 | 140 |
| New type, one-time instructions | 63.6K | 43.2K | 43.6K | 43.2K |
| New type, bytes kept | 1,043 | 589 | 589 | 589 |

Why:

- None of the three creates metadata for the entry: under lldb, main calls `swift_allocateGenericClassMetadata` once per new type and the others never do, and none requests function type metadata. A closure's context metadata is emitted statically, so `() -> T` costs nothing per type once the cast is gone. That is the 450 bytes and 20K instructions of `EntryConcrete`.
- The box reads with one load at a fixed offset, so an `Int` costs 2 instructions; reading `any Service` is the retain of the copied reference. Main pays 75 more for the exclusivity check on `var value`, the closure about 50 for the indirect call.
- The box's deinit must reach the header through `withUnsafeMutablePointers`: reading the `header` property is an exclusivity-checked access, about 80 instructions per destroyed entry. Passing the stored `Any.Type` to a generic function needs Swift 6 language mode; Swift 5 mode refuses to open it and needs `_openExistential`.
- `Any` opened stores small values inline, so declare allocates nothing, but get copies through the value witness table without specialization: 150 to 265 instructions per read. Each dictionary value grows from one word to four.
- The box's 3,154 on declare in the first layout comes from the dictionary, not the box: its deinit and set path compile to the same code as the longer version, which measured 2,468 there, and in the second layout the two are 2,636 and 2,630.

## How much a build moves the numbers

The store's keys are `ObjectIdentifier`s of key types, that is metadata addresses. With deterministic hashing the dictionary's layout, and so how many entries a lookup or a removal visits, follows those addresses, and they change with the binary and with each boot. Shifting every metadata allocation by 8 bytes (`SWIFT_DEBUG_ENABLE_METADATA_ALLOCATION_ITERATION=1`) moves declare from 2,370 to 2,710 instructions for the writer, and from 2,646 to anywhere between 2,413 and 2,890 for main. The same main source measured 2,413 one night and 2,650 the next day; retrieve moves by up to 20 instructions. Within one build and boot the counts are stable to a few instructions, except where a read allocates: `() -> Any` reading `any Service` moves by 5% between processes.

Two entries that compile to the same code measured up to 10% apart on retrieve and 20% on declare in one layout and equal in the other (previous section). So between two builds a difference under about 10% on retrieve or 20% on declare can be layout alone, whatever `compare.py` says about noise: confirm it in a profile before crediting the change. The effects above that are larger, `let value`, the casts, the boxing and every one-time cost, were each confirmed in a profile.

In every alternative `ImplicitKey`, the `Implicit` wrapper and the rest of the table above remain: about 590 bytes and 43K instructions per new existential type. Replacing `EntryConcrete` saves its 408 bytes plus its share of hash-table growth, about 450 bytes in all, and 20K instructions (1.1 µs).

## Comparing a change

`baseline compare` compares one run against one run, and time differs between processes by several percent, so a single pair can't tell a regression from noise. `compare.py` runs several builds in interleaved rounds, one process per benchmark, and reports each change with a bootstrap interval and an exact Mann-Whitney p-value:

```bash
python3 Benchmarks/compare.py 10 path/to/baseline/ImplicitsBenchmarks path/to/changed/ImplicitsBenchmarks
```

Values are per iteration as the runner reports them, that is per thousand operations. With fewer than four rounds no change can reach p < 0.05.
