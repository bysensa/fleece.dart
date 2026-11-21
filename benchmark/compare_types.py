"""Compare two AOT builds of types.dart, checking fixture bytes before timing."""
import argparse
import csv
from pathlib import Path
from statistics import median
import subprocess
from tempfile import TemporaryDirectory

from compare import HERE, build_rust, measure


def verify_rust(crate, work, inputs):
    _, libraries = build_rust(crate.resolve(), work)
    library = Path(libraries["fleece"])
    check = work / "verify-types"
    subprocess.run(["rustc", "--edition=2024", "-O", str(HERE / "verify_types.rs"),
                    "-o", check, "-L", f"dependency={library.parent}",
                    "--extern", f"fleece={library}"], check=True)
    subprocess.run([check, inputs], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--reference", type=Path,
                        help="also re-encode every fixture with this upstream Rust crate")
    parser.add_argument("--write-only", action="store_true", help="time only document encoding")
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--csv", type=Path, required=True)
    args = parser.parse_args()
    if args.runs <= 0:
        parser.error("--runs must be positive")
    builds = {"before": args.before.resolve(), "after": args.after.resolve()}
    with TemporaryDirectory() as tmp:
        fixtures = {}
        for label, exe in builds.items():
            target = Path(tmp) / label
            subprocess.run([exe, "--write-inputs", target], check=True)
            fixtures[label] = {p.name: p.read_bytes() for p in target.iterdir()}
        if not fixtures["before"] or fixtures["before"] != fixtures["after"]:
            raise ValueError("Fixture bytes differ between the two builds")
        count = sum(name.endswith(".fleece") for name in fixtures["before"])
        print(f"{count} byte-identical fixtures, including external base bytes", flush=True)
        if args.reference:
            verify_rust(args.reference, Path(tmp), Path(tmp) / "after")

    samples = {}
    for i in range(args.runs):
        for label in (builds if i % 2 == 0 else reversed(builds)):
            timings = measure(builds[label], ["--write-only"] if args.write_only else [])
            if not samples:
                samples = {op: {name: [] for name in builds} for op in timings}
            if timings.keys() != samples.keys():
                raise ValueError("The two builds reported different operations")
            for op, us in timings.items():
                samples[op][label].append(us)
        print(f"Finished pair {i+1}/{args.runs}", flush=True)
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(["operation", "implementation", *(f"run_{i+1}_us" for i in range(args.runs))])
        for op, results in samples.items():
            for label, values in results.items():
                writer.writerow([op, label, *values])
            before, after = (median(results[key]) for key in builds)
            print(f"{op:30} {before:10.3f} {after:10.3f} {before / after:6.2f}×")


if __name__ == "__main__":
    main()
