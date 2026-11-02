// Copyright 2026 Yandex LLC. All rights reserved.

import ArgumentParser
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

@main
struct CompareBuilds: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "compare-builds",
    abstract: "Compares the benchmarks across revisions of the library.",
    discussion: """
    Each revision is exported into the work directory and built with the \
    benchmarks of the repository's working tree, so every revision runs the \
    same benchmarks. Every round runs every benchmark of every revision once, \
    each in its own process, in a new random order.

    For each metric the report gives the median over the rounds of one \
    benchmark iteration as the runner counts it, before the benchmark's \
    scaling factor; times are in nanoseconds. For each revision after the \
    first it gives the change against the first (relative, or absolute when \
    the first's median is 0), its bootstrap 95% interval and the exact \
    two-sided Mann-Whitney p-value. A change is "changed" when its interval \
    excludes zero and p < 0.05; across this many benchmarks and metrics an \
    occasional "changed" is chance.
    """
  )

  @Option(help: "The git repository of the library.", transform: absolutePath)
  var repository: String

  @Option(
    help: "Where the revisions are exported and built; kept between runs.",
    transform: absolutePath
  )
  var workDirectory: String

  @Option(help: "How many times each benchmark of each revision runs.")
  var rounds = 10

  @Argument(help: "Git revisions of the library; the first is the baseline.")
  var revisions: [String]

  func validate() throws {
    if revisions.count < 2 {
      throw ValidationError("Give a baseline and at least one revision.")
    }
    if rounds < 4 {
      throw ValidationError("With fewer than 4 rounds no change reaches p < 0.05.")
    }
    let benchmarks = "\(repository)/Benchmarks/"
    if "\(workDirectory)/".hasPrefix(benchmarks),
       !workDirectory.hasPrefix("\(benchmarks).build/") {
      throw ValidationError(
        "Inside Benchmarks the work directory must be under .build, "
          + "which isn't copied into the exports."
      )
    }
  }

  func run() async throws {
    var builds = [String]()
    for revision in revisions {
      try await builds.append(build(revision))
    }
    // The runner can't list its benchmarks without running them, so one run
    // of the baseline gives their names and metrics.
    let reference = try await runBenchmarks(builds[0])

    let jobs = builds.indices.flatMap { b in
      reference.names.map { Job(build: b, name: $0) }
    }
    var runs = [Job: [Medians]]()
    for round in 1...rounds {
      for job in jobs.shuffled() {
        let results = try await runBenchmarks(
          builds[job.build],
          "--filter", NSRegularExpression.escapedPattern(for: job.name)
        )
        let expected = reference.medians[job.name]!.metrics
        guard let medians = results.medians[job.name],
              medians.metrics == expected else {
          throw MissingMetrics(revision: revisions[job.build], job: job, expected: expected)
        }
        runs[job, default: []].append(medians)
      }
      log("round \(round)/\(rounds)")
    }

    for name in reference.names {
      print("\n\(name)")
      let baseRuns = runs[Job(build: 0, name: name)]!
      for metric in reference.medians[name]!.metrics {
        let base = baseRuns.map { $0.values[metric]! }
        print("  \(metric): \(revisions[0]) \(String(format: "%.0f", median(base)))")
        for b in builds.indices.dropFirst() {
          let values = runs[Job(build: b, name: name)]!
            .map { $0.values[metric]! }
          print(
            "    \(revisions[b]) \(String(format: "%.0f", median(values)))  "
              + comparison(values, base)
          )
        }
      }
    }
  }

  /// Returns the benchmark executable built against the library at `revision`.
  private func build(_ revision: String) async throws -> String {
    let commit = try await execute(
      .name("git"), "-C", repository, "rev-parse", "--verify", "\(revision)^{commit}"
    )
    // Named after the revision, not its commit, so that a branch that moves
    // keeps its build and rebuilds only what changed.
    let export = "\(workDirectory)/\(revision.replacingOccurrences(of: "/", with: "_"))"
    log("exporting \(revision)")
    try removeContents(of: export, except: "Benchmarks")
    try removeContents(of: "\(export)/Benchmarks", except: ".build")
    try await execute(
      .name("git"), "-C", repository, "archive", "--output", "\(export).tar", commit
    )
    try await execute(.name("tar"), "-xf", "\(export).tar", "-C", export)
    try FileManager.default.removeItem(atPath: "\(export).tar")
    try replaceSources(
      of: "\(export)/Benchmarks", with: "\(repository)/Benchmarks"
    )
    log("building \(revision)")
    let package = ["-c", "release", "--package-path", "\(export)/Benchmarks"]
    try await execute(
      .name("swift"), ["build", "--product", "ImplicitsBenchmarks"] + package,
      logOutput: true
    )
    let bin = try await execute(
      .name("swift"), ["build", "--show-bin-path"] + package
    )
    return "\(bin)/ImplicitsBenchmarks"
  }
}

/// Replaces everything in `destination` but its `.build` with the files of
/// `source` but its `.build`, so the next build of `destination` is incremental.
private func replaceSources(of destination: String, with source: String) throws {
  try removeContents(of: destination, except: ".build")
  let files = FileManager.default
  for item in try files.contentsOfDirectory(atPath: source) where item != ".build" {
    try files.copyItem(atPath: "\(source)/\(item)", toPath: "\(destination)/\(item)")
  }
}

/// Empties `directory` but its item `kept`, creating the directory if needed.
private func removeContents(of directory: String, except kept: String) throws {
  let files = FileManager.default
  try files.createDirectory(atPath: directory, withIntermediateDirectories: true)
  for item in try files.contentsOfDirectory(atPath: directory) where item != kept {
    try files.removeItem(atPath: "\(directory)/\(item)")
  }
}

private func runBenchmarks(
  _ executable: String, _ arguments: String...
) async throws -> Results {
  try await Results(execute(
    .path(FilePath(executable)),
    ["--quiet", "true"] + arguments,
    environment: .inherit.updating(["SWIFT_DETERMINISTIC_HASHING": "1"])
  ))
}

private struct Job: Hashable {
  var build: Int
  var name: String
}

/// The benchmarks in the runner's output, in the order it prints them.
private struct Results {
  var names: [String] = []
  var medians: [String: Medians] = [:]

  init(_ output: String) {
    let prefix = "Debug results for "
    var name: String?
    var metric: String?
    for line in output.split(separator: "\n") {
      if line.hasPrefix(prefix), line.hasSuffix(":") {
        name = String(line.dropFirst(prefix.count).dropLast())
        names.append(name!)
        metric = nil
      } else if line.hasSuffix(":"), !line.hasPrefix(" ") {
        metric = String(line.dropLast())
      } else if let name, let metric {
        let parts = line.split(separator: " ")
        guard medians[name]?.values[metric] == nil, parts.count >= 3,
              let value = Double(parts[0]), let percentile = Double(parts[1]),
              percentile >= 0.5 else { continue }
        medians[name, default: Medians()].metrics.append(metric)
        medians[name, default: Medians()].values[metric] = value
      }
    }
  }
}

/// The p50 of every metric of one benchmark, in the order the runner prints them.
private struct Medians {
  var metrics: [String] = []
  var values: [String: Double] = [:]
}

/// The change, its interval, the p-value and the verdict.
private func comparison(_ values: [Double], _ base: [Double]) -> String {
  let relative = median(base) != 0
  let change = { (values: [Double], base: [Double]) in
    relative ? median(values) / median(base) - 1 : median(values) - median(base)
  }
  let show = { (change: Double) in
    relative ? String(format: "%+.1f%%", change * 100) : String(format: "%+.0f", change)
  }
  let (low, high) = bootstrapInterval(values, base, change)
  let p = mannWhitneyP(values, base)
  let intervalExcludesZero = low > 0 || high < 0
  let verdict = intervalExcludesZero && p < 0.05 ? "changed" : "no change"
  return "\(show(change(values, base))) [\(show(low)), \(show(high))]"
    + " p=\(String(format: "%.3f", p)) \(verdict)"
}

/// Exact two-sided p-value: the share of all splits of the pooled runs whose
/// rank-sum statistic is at least as far from its mean as the observed one.
/// Ranks are doubled so that tied runs, which share a half rank, stay integers.
private func mannWhitneyP(_ a: [Double], _ b: [Double]) -> Double {
  let ranks = doubledRanks(a + b)
  let k = a.count
  let width = ranks.reduce(0, +) + 1
  // ways[j * width + s]: how many sets of j runs, among those seen so far,
  // have rank sum s.
  var ways = [Double](repeating: 0, count: (k + 1) * width)
  ways[0] = 1
  for r in ranks {
    for j in stride(from: k, through: 1, by: -1) {
      for s in 0..<(width - r) {
        ways[j * width + s + r] += ways[(j - 1) * width + s]
      }
    }
  }
  let mean = k * (ranks.count + 1)
  let observed = abs(ranks[..<k].reduce(0, +) - mean)
  var extreme = 0.0
  var all = 0.0
  for s in 0..<width {
    let count = ways[k * width + s]
    all += count
    if abs(s - mean) >= observed {
      extreme += count
    }
  }
  return extreme / all
}

private func doubledRanks(_ values: [Double]) -> [Int] {
  let order = values.indices.sorted { values[$0] < values[$1] }
  var ranks = Array(repeating: 0, count: values.count)
  var first = 0
  while first < order.count {
    var last = first
    while last + 1 < order.count, values[order[last + 1]] == values[order[first]] {
      last += 1
    }
    for i in first...last {
      ranks[order[i]] = first + last + 2
    }
    first = last + 1
  }
  return ranks
}

private func bootstrapInterval(
  _ values: [Double],
  _ base: [Double],
  _ change: ([Double], [Double]) -> Double
) -> (low: Double, high: Double) {
  let iterations = 4000
  let changes = (0..<iterations)
    .map { _ in change(resample(values), resample(base)) }
    .sorted()
  return (
    changes[Int(Double(iterations) * 0.025)],
    changes[Int(Double(iterations) * 0.975)]
  )
}

private func resample(_ sample: [Double]) -> [Double] {
  sample.map { _ in sample.randomElement()! }
}

private func median(_ values: [Double]) -> Double {
  let sorted = values.sorted()
  let middle = sorted.count / 2
  return sorted.count.isMultiple(of: 2)
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle]
}

/// Runs `executable` and returns its output without the trailing newline; with
/// `logOutput` the output goes to standard error instead.
@discardableResult
private func execute(
  _ executable: Executable,
  _ arguments: [String],
  environment: Environment = .inherit,
  logOutput: Bool = false
) async throws -> String {
  let status: TerminationStatus
  var output = ""
  if logOutput {
    status = try await run(
      executable,
      arguments: Arguments(arguments),
      environment: environment,
      output: .currentStandardError,
      error: .currentStandardError
    ).terminationStatus
  } else {
    let result = try await run(
      executable,
      arguments: Arguments(arguments),
      environment: environment,
      output: .string(limit: 64 << 20),
      error: .currentStandardError
    )
    status = result.terminationStatus
    output = result.standardOutput
  }
  guard status.isSuccess else {
    throw ExecuteError(executable: executable, arguments: arguments, status: status)
  }
  return output.trimmingCharacters(in: .newlines)
}

@discardableResult
private func execute(_ executable: Executable, _ arguments: String...) async throws -> String {
  try await execute(executable, arguments)
}

private struct ExecuteError: CustomStringConvertible, Error {
  var executable: Executable
  var arguments: [String]
  var status: TerminationStatus

  var description: String {
    "\(executable) \(arguments.joined(separator: " ")) ended with \(status)"
  }
}

private struct MissingMetrics: CustomStringConvertible, Error {
  var revision: String
  var job: Job
  var expected: [String]

  var description: String {
    "\(job.name) at \(revision) didn't report all of \(expected.joined(separator: ", "))"
  }
}

/// Resolves `path` against the current directory: `git -C` would resolve a
/// relative path against the repository instead.
private func absolutePath(_ path: String) -> String {
  FilePath(FileManager.default.currentDirectoryPath)
    .pushing(FilePath(path)).lexicallyNormalized().string
}

private func log(_ message: String) {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
}
