"""Run the Rust repository's Couchbase compatibility suites with the Dart CLI."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("crate", type=Path, help="checkout of crates/fleece")
    parser.add_argument("--tools", type=Path, help="directory with the built Couchbase tools")
    parser.add_argument("--dart", default="dart", help="Dart SDK executable")
    parser.add_argument("--rust-cli", type=Path, help="also require byte equality with the Rust CLI on every document")
    args = parser.parse_args()
    source = args.crate.resolve() / "tools/reference"
    package = Path(__file__).resolve().parents[2]
    with TemporaryDirectory() as temp:
        root = Path(temp)
        scripts = root / "tools/reference"
        shutil.copytree(source, scripts)
        target = root / "target"
        binary = target / "release/examples/fleece"
        binary.parent.mkdir(parents=True)
        tools = args.tools or args.crate / "target/reference"
        if (tools / "fleece/build/fleeceTool").is_file() and (tools / "delta").is_file():
            (target / "reference").symlink_to(tools.resolve(), target_is_directory=True)
        else:
            subprocess.run(["sh", str(scripts / "build.sh")], check=True)
        subprocess.run([args.dart, "compile", "exe", "bin/fleece.dart", "-o", str(binary)],
                       cwd=package, check=True)
        for name in ("documents.py", "deltas.py"):
            subprocess.run([sys.executable, str(scripts / name)], check=True,
                           env={**os.environ, "TMPDIR": temp})
        if args.rust_cli:
            # The same independent document generator accepts either CLI. Both
            # write and cross-read its 307 inputs, including far roots and i64s.
            comparison = root / "rust-comparison"
            generate = comparison / "tools/reference/documents.py"
            generate.parent.mkdir(parents=True)
            shutil.copyfile(scripts / "documents.py", generate)
            for dest, exe in [("release/examples/fleece", binary),
                              ("reference/fleece/build/fleeceTool", args.rust_cli.resolve())]:
                link = comparison / "target" / dest
                link.parent.mkdir(parents=True)
                link.symlink_to(exe)
            result = subprocess.check_output([sys.executable, str(generate)], text=True)
            print("Dart / Rust:", result.rstrip())
            if not re.fullmatch(r"(\d+) documents, 0 failures, \1 with identical bytes\s*", result):
                raise SystemExit("Dart and Rust produced different document bytes")


if __name__ == "__main__":
    main()
