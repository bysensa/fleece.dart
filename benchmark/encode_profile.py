"""Summarize macOS sample call trees for throughput --profile-encode."""
import argparse
from collections import Counter
import csv
from pathlib import Path
import re


FRAME = re.compile(r"^([ +!:|.]*)(\d+) (.*?)  \(in ([^)]+)\)")


def read_profile(path):
    exclusive, inclusive = Counter(), Counter()
    stack = []
    total = 0
    for line in path.read_text().splitlines():
        if line.startswith("Total number in stack"):
            break
        if re.match(r"^\s*\d+ Thread_", line):
            stack.clear()
            continue
        match = FRAME.match(line)
        if not match:
            continue
        prefix, count, name, image = match.groups()
        depth, count = len(prefix), int(count)
        if name == "???":
            name = f"[{image}]"
        while stack and stack[-1][0] >= depth:
            stack.pop()
        if not stack:
            if name.lstrip("_") != "measure":
                continue
            total += count
        else:
            exclusive[stack[-1][1]] -= count
        exclusive[name] += count
        if all(parent != name for _, parent in stack):
            inclusive[name] += count
        stack.append((depth, name))
    if not total or sum(exclusive.values()) != total or min(exclusive.values()) < 0:
        raise ValueError(f"Could not account for samples in the timed operation in {path}")
    return total, exclusive, inclusive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--csv", required=True, type=Path)
    args = parser.parse_args()
    with args.csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(["build", "function", "self_samples", "inclusive_samples", "total_samples"])
        for label, path in [("before", args.before), ("after", args.after)]:
            total, exclusive, inclusive = read_profile(path)
            for name, count in exclusive.most_common():
                writer.writerow([label, name, count, inclusive[name], total])
            print(f"{label}: {total} samples inside the timed loop")
            for name, count in exclusive.most_common(10):
                print(f"  {100 * count / total:5.1f}%  {name}")


if __name__ == "__main__":
    main()
