"""Compares builds of the benchmark executable over several interleaved process runs.

usage: python3 Benchmarks/compare.py <rounds> <baseline executable> <executable>...

Build each side with `swift build -c release --package-path Benchmarks` and copy
`.build/release/ImplicitsBenchmarks` aside, together with `libMallocInterposerSwift.dylib`
next to it. Every round runs every benchmark of every executable once, each in its own
process, in a new random order, so drift from heat or background load hits all sides alike.
One process run gives one observation: its median. For each executable after the first,
the report gives the change of the median against the baseline, its bootstrap 95% interval,
and the exact two-sided Mann-Whitney p-value. A change counts only when the interval
excludes zero and p < 0.05.
"""

import itertools
import os
import pathlib
import random
import re
import statistics
import subprocess
import sys

ENV = dict(os.environ, SWIFT_DETERMINISTIC_HASHING="1")


def run(executable, *args):
    return subprocess.run([executable, *args], env=ENV, capture_output=True, text=True, check=True).stdout


def medians(output):
    """The p50 of every metric in the runner's histogram output, per benchmark iteration."""
    result, metric = {}, None
    for line in output.splitlines():
        if line.endswith(":") and not line.startswith((" ", "Debug")):
            metric = line[:-1]
        parts = line.split()
        if metric and metric not in result and len(parts) >= 3 and parts[0][0].isdigit() and float(parts[1]) >= 0.5:
            result[metric] = float(parts[0])
    return result


def mann_whitney_p(a, b):
    """Exact two-sided p-value: the share of all splits of the pooled runs whose
    rank-sum statistic is at least as far from its mean as the observed one."""
    pooled = sorted(a + b)
    rank = {v: statistics.mean(i + 1 for i, w in enumerate(pooled) if w == v) for v in pooled}
    ranks = [rank[v] for v in a + b]
    mean = len(a) * (len(pooled) + 1) / 2
    observed = abs(sum(ranks[: len(a)]) - mean)
    splits = [abs(sum(c) - mean) >= observed - 1e-9 for c in itertools.combinations(ranks, len(a))]
    return sum(splits) / len(splits)


def bootstrap_interval(values, base, iterations=4000):
    rng = random.Random(1)
    changes = sorted(
        statistics.median(rng.choices(values, k=len(values))) / statistics.median(rng.choices(base, k=len(base))) - 1
        for _ in range(iterations)
    )
    return changes[int(0.025 * iterations)], changes[int(0.975 * iterations)]


def main(rounds, executables):
    names = re.findall(r"^Debug results for (.+):$", run(executables[0], "--quiet", "true"), re.M)
    runs = {(e, n): [] for e in executables for n in names}
    for r in range(rounds):
        jobs = list(runs)
        random.shuffle(jobs)
        for executable, name in jobs:
            runs[executable, name].append(medians(run(executable, "--filter", f"^{re.escape(name)}$", "--quiet", "true")))
        print(f"round {r + 1}/{rounds}", file=sys.stderr)

    baseline = executables[0]
    for name in names:
        print(f"\n{name}")
        for metric in runs[baseline, name][0]:
            base = [m[metric] for m in runs[baseline, name]]
            print(f"  {metric}: {pathlib.Path(baseline).name} {statistics.median(base):.0f}")
            for executable in executables[1:]:
                values = [m[metric] for m in runs[executable, name]]
                line = f"    {pathlib.Path(executable).name} {statistics.median(values):.0f}"
                if statistics.median(base) > 0:
                    low, high = bootstrap_interval(values, base)
                    p = mann_whitney_p(values, base)
                    change = statistics.median(values) / statistics.median(base) - 1
                    verdict = "no change" if low <= 0 <= high or p >= 0.05 else "changed"
                    line += f"  {change:+.1%} [{low:+.1%}, {high:+.1%}] p={p:.3f} {verdict}"
                print(line)


if __name__ == "__main__":
    main(int(sys.argv[1]), sys.argv[2:])
