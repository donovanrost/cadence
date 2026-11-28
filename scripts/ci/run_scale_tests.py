#!/usr/bin/env python3
"""Repeat a Mix test selection and report ExUnit's timings."""

import argparse
from collections import defaultdict
import html
import json
import os
from pathlib import Path
import platform
import re
from statistics import median
import subprocess
import time


def selection(root, raw_filter):
    value = raw_filter.strip()
    tag = re.fullmatch(r"(?:--only\s+)?(\w+(?::[\w.-]+)?)", value)
    if tag:
        return root / "apps/cadence", ["--only", tag[1]]

    base = root / "apps/cadence" if value.startswith("test/") else root
    path = (base / value).resolve()
    if path.suffix == ".exs" and path.is_file() and path.is_relative_to(root):
        for project in path.parents:
            if project == root:
                break
            if (project / "mix.exs").is_file() and path.is_relative_to(project / "test"):
                return project, [str(path.relative_to(project)), "--include", "scale"]

    raise ValueError("Choose a tag (for example --only scale) or an existing Mix test file")


def runner_info():
    cpu_model = platform.processor() or "unavailable"
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.is_file():
        for line in cpuinfo.read_text().splitlines():
            key, _, value = line.partition(":")
            if key.strip() == "model name":
                cpu_model = value.strip()
                break

    return {
        "type": os.environ.get("SCALE_RUNNER_TYPE", "local"),
        "image_version": os.environ.get("ImageVersion", "unavailable"),
        "cpu_model": cpu_model,
        "logical_cores": len(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else os.cpu_count(),
    }


def repeat_tests(project, test_args, repeats, output, runner):
    formatter = Path(__file__).resolve().with_name("scale_test_formatter.exs")
    command = [
        "elixir", "-r", str(formatter), "-S", "mix", "test",
        "--formatter", "ExUnit.CLIFormatter",
        "--formatter", "Cadence.CI.ScaleTestFormatter",
        "--seed", "0", "--max-cases", "1", "--no-color", *test_args,
    ]

    results = []
    for index in range(1, repeats + 1):
        print(f"Scale repeat {index}/{repeats} on {runner['type']}", flush=True)
        timings_path = output / f"run-{index}.jsonl"
        log_path = output / f"run-{index}.log"
        timings_path.write_text("", encoding="utf-8")
        env = dict(os.environ, SCALE_TEST_TIMINGS=str(timings_path))

        with log_path.open("w", encoding="utf-8") as log:
            log.write(
                f"Runner: {runner['type']} (image {runner['image_version']}), "
                f"{runner['cpu_model']}, {runner['logical_cores']} logical cores\n"
            )
            log.flush()
            started = time.monotonic()
            result = subprocess.run(command, cwd=project, env=env, stdout=log, stderr=subprocess.STDOUT)
            seconds = time.monotonic() - started

        timings = [json.loads(line) for line in timings_path.read_text(encoding="utf-8").splitlines()]
        results.append({
            "run": index,
            "wall_seconds": round(seconds, 3),
            "exit_code": result.returncode,
            "timings": timings,
        })
        print(f"Repeat {index}: {seconds:.2f} s, exit {result.returncode}, {len(timings)} timed tests")

    return results


def summarize(results):
    grouped = defaultdict(list)
    for run in results:
        for timing in run["timings"]:
            if timing["passed"]:
                grouped[timing["test"]].append(timing["duration_ms"])

    return {
        name: {"median_ms": median(times), "min_ms": min(times), "max_ms": max(times), "samples": len(times)}
        for name, times in grouped.items()
    }


def cell(value):
    return html.escape(str(value)).replace("|", r"\|").replace("\n", " ")


def markdown(report):
    runner = report["runner"]
    runs = report["runs"]
    lines = [
        "# CI repeatability numbers only. #217 budgets use Earendil scale scorecards.",
        "",
        f"Runner {cell(runner['type'])} (image {cell(runner['image_version'])}), "
        f"{cell(runner['cpu_model'])}, {runner['logical_cores']} logical cores.",
        "",
        f"Commit {report['commit']} · Project {cell(report['project'])} · Filter {cell(report['filter'])}",
        "",
        "| Run | Wall time (s) | Exit code | Timed tests |",
        "| ---: | ---: | ---: | ---: |",
    ]
    for run in runs:
        lines.append(
            f"| {run['run']} | {run['wall_seconds']:.2f} | {run['exit_code']} | {len(run['timings'])} |"
        )

    lines.extend([
        "",
        "## Per-test timings",
        "",
        "ExUnit durations include test setup. The spread is the minimum and maximum of passing timings.",
        "",
        "| Test | Median (ms) | Min (ms) | Max (ms) | Passing samples |",
        "| --- | ---: | ---: | ---: | ---: |",
    ])
    for name, stats in sorted(report["tests"].items()):
        lines.append(
            f"| {cell(name)} | {stats['median_ms']:.3f} | {stats['min_ms']:.3f} | "
            f"{stats['max_ms']:.3f} | {stats['samples']}/{len(runs)} |"
        )

    if not report["tests"]:
        lines.extend(["", "No passing test timings were recorded. The artifact includes the run logs."])

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--filter", default="--only scale")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    if not 1 <= args.repeats <= 10:
        parser.error("--repeats must be between 1 and 10")

    root = Path.cwd()
    try:
        project, test_args = selection(root, args.filter)
    except ValueError as error:
        parser.error(str(error))
    if args.validate:
        return 0
    if args.output is None:
        parser.error("--output is required when running tests")

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    runner = runner_info()
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    results = repeat_tests(project, test_args, args.repeats, output, runner)
    report = {
        "commit": commit,
        "filter": args.filter,
        "project": str(project.relative_to(root)),
        "runner": runner,
        "runs": results,
        "tests": summarize(results),
    }
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    summary = markdown(report)
    (output / "summary.md").write_text(summary, encoding="utf-8")
    if "GITHUB_STEP_SUMMARY" in os.environ:
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as job_summary:
            job_summary.write(summary)

    return int(any(run["exit_code"] or not run["timings"] for run in results))


if __name__ == "__main__":
    raise SystemExit(main())
