"""Compare the Dart AOT executable with the original Rust throughput benchmark."""

import argparse
import csv
import json
import os
from pathlib import Path
import re
from statistics import median
import subprocess
from tempfile import TemporaryDirectory


HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent


def build_rust(crate, work):
    command = [
        "cargo", "bench", "--manifest-path", str(crate / "Cargo.toml"),
        "--locked", "-p", "fleece", "--all-features", "--bench", "throughput",
        "--no-run", "--message-format=json-render-diagnostics",
        "--target-dir", os.environ.get("CARGO_TARGET_DIR", str(work / "target")),
    ]
    output = subprocess.check_output(command, text=True, cwd=PACKAGE)
    libraries = {}
    bench = None
    for line in output.splitlines():
        item = json.loads(line)
        if item.get("reason") != "compiler-artifact":
            continue
        name = item["target"]["name"]
        if name == "throughput" and item.get("executable"):
            bench = item["executable"]
        for path in item["filenames"]:
            if path.endswith(".rlib") and name in ("fleece", "serde_json"):
                libraries[name] = path
    if bench is None:
        raise RuntimeError("Cargo did not build the throughput executable")
    return bench, libraries


def verify_inputs(crate, work, dart_benches, libraries, dict_strings=False):
    # Compile the fixture check in the same module as upstream's private record().
    source = work / "check.rs"
    source.write_text((crate / "benches/throughput.rs").read_text() + "\n" +
                      (HERE / "verify_inputs.rs").read_text())
    check = work / "check"
    command = ["rustc", "--edition=2024", "-O", "--test", str(source), "-o", str(check),
               "-L", "dependency=" + str(Path(libraries["fleece"]).parent)]
    for name, path in libraries.items():
        command.extend(["--extern", f"{name}={path}"])
    subprocess.run(command, check=True, cwd=PACKAGE)
    for index, bench in enumerate(dart_benches):
        inputs = work / f"inputs-{index}"
        subprocess.run([bench, "--write-inputs", inputs], check=True)
        subprocess.run([check, "--exact", "dart_inputs_match"], check=True,
                       env={**os.environ, "FLEECE_BENCH_INPUTS": str(inputs),
                            "FLEECE_BENCH_DICT_STRINGS": str(int(dict_strings))})
        if index == 0:
            for path in sorted(inputs.iterdir()):
                print(f"{path.name}: {path.stat().st_size:,} bytes", flush=True)
    return check


def measure(exe, args=()):
    output = subprocess.check_output([exe, *args], text=True)
    times = {}
    for line in output.splitlines():
        match = re.match(r"^(.+?)\s+(\d+(?:\.\d+)?) µs\b", line)
        if match:
            name, us = match.groups()
            name = name.replace("serde_json:", "json:").replace("dart:convert:", "json:")
            name = name.replace("geo-types", "geo").replace("geobase", "geo")
            if name in times:
                raise ValueError(f"Repeated measurement: {name}")
            times[name] = float(us)
    if not times:
        raise ValueError(f"No timings in output of {exe}:\n{output}")
    return times


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, default=os.environ.get(
        "FLEECE_REFERENCE", PACKAGE.parent / "the-base/crates/fleece"))
    parser.add_argument("--runs", type=int, default=5, help="measured runs per implementation")
    parser.add_argument("--csv", type=Path, help="write every timing sample in microseconds")
    parser.add_argument("--baseline-dart", type=Path,
                        help="include a previously compiled Dart throughput executable")
    parser.add_argument("--wide-root", action="store_true",
                        help="also time closing the prepared 1,000-record array in both languages")
    parser.add_argument("--dict-strings", action="store_true",
                        help="also check and time address dictionaries and short string values")
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    if args.csv:
        args.csv.parent.mkdir(parents=True, exist_ok=True)
    crate = args.reference.resolve()
    with TemporaryDirectory() as directory:
        work = Path(directory)
        dart = os.environ.get("DART", "dart")
        dart_bench = work / "dart-bench"
        subprocess.run([dart, "compile", "exe", str(HERE / "throughput.dart"),
                        "-o", str(dart_bench)], cwd=PACKAGE, check=True)
        rust_bench, libraries = build_rust(crate, work)
        executables = {"Dart": dart_bench, "Rust": rust_bench}
        dart_benches = [dart_bench]
        if args.baseline_dart:
            baseline = args.baseline_dart.resolve()
            executables["Dart before"] = baseline
            dart_benches.append(baseline)
        checker = verify_inputs(crate, work, dart_benches, libraries, args.dict_strings)

        def measure_build(name):
            exe = executables[name]
            times = measure(exe)
            if args.wide_root:
                root = (measure(checker, ["--exact", "close_wide_root", "--nocapture"])
                        if name == "Rust" else measure(exe, ["--wide-root"]))
                times.update(root)
            if args.dict_strings:
                parts = (measure(checker, ["--exact", "encode_dict_strings", "--nocapture"])
                         if name == "Rust" else measure(exe, ["--dict-strings"]))
                times.update(parts)
            return times

        print("Warming up the executables...", flush=True)
        operations = list(measure_build("Dart"))
        for name in executables:
            if name != "Dart" and list(measure_build(name)) != operations:
                raise ValueError(f"{name} and Dart report different operations or fixture sizes")
        samples = {name: {op: [] for op in operations} for name in executables}
        for run in range(args.runs):
            order = ["Rust", "Dart"] if run % 2 == 0 else ["Dart", "Rust"]
            if args.baseline_dart:
                order.insert(run % 3, "Dart before")
            for name in order:
                times = measure_build(name)
                if list(times) != operations:
                    raise ValueError(f"Unexpected list of operations in {name} run {run + 1}")
                for op, us in times.items():
                    samples[name][op].append(us)
            print(f"Finished run {run + 1}/{args.runs} ({', '.join(order)})", flush=True)

    if args.csv:
        with args.csv.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream, lineterminator="\n")
            writer.writerow(["operation", "implementation",
                             *(f"run_{i + 1}_us" for i in range(args.runs))])
            for op in operations:
                for name in executables:
                    writer.writerow([op, name, *samples[name][op]])
    baseline_header = "    Before µs   Speedup" if args.baseline_dart else ""
    print(f"{'Operation':54} {'Dart µs':>12} {'Rust µs':>12} {'Dart/Rust':>10}{baseline_header}")
    for op in operations:
        dart_us = median(samples["Dart"][op])
        rust_us = median(samples["Rust"][op])
        baseline_result = ""
        if args.baseline_dart:
            before_us = median(samples["Dart before"][op])
            baseline_result = f" {before_us:12.3f} {before_us / dart_us:8.2f}×"
        print(f"{op:54} {dart_us:12.3f} {rust_us:12.2f} {dart_us / rust_us:9.2f}×{baseline_result}")


if __name__ == "__main__":
    main()
