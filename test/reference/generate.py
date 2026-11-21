"""Regenerate portable reference cases from a checkout of crates/fleece.

python3 test/reference/generate.py ../the-base/crates/fleece
Cargo uses the checkout's lockfile. Set CARGO_TARGET_DIR to reuse a build.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

here = Path(__file__).resolve().parent
crate = Path(sys.argv[1]).resolve()
required = {"fleece", "half", "rust_decimal", "num_bigint", "proptest",
            "serde_json", "surrealdb_types", "geo_types", "geo", "serde"}
with TemporaryDirectory() as directory:
    tmp = Path(directory)
    cargo = ["cargo", "test", "--manifest-path", str(crate / "Cargo.toml"),
             "--locked", "--all-features", "--no-run", "-p", "fleece",
             "--message-format=json", "--target-dir",
             os.environ.get("CARGO_TARGET_DIR", str(tmp / "target"))]
    artifacts = {}
    for line in subprocess.check_output(cargo, text=True).splitlines():
        item = json.loads(line)
        if item.get("reason") == "compiler-artifact":
            for path in item["filenames"]:
                if path.endswith(".rlib"):
                    artifacts[item["target"]["name"]] = path
    # Keep upstream's private proptest strategies and independent comparators.
    for module in ["properties", "reference", "surreal", "serde"]:
        source = (crate / "tests" / (module + ".rs")).read_text()
        for name in ["value", "compare", "finite_number", "to_surreal"]:
            source = source.replace("\nfn " + name + "(", "\npub(super) fn " + name + "(")
        if module == "serde":
            source += "\npub(super) fn dog_bytes() -> Vec<u8> { to_vec(&dog()).unwrap() }\n"
        (tmp / ("up_" + module + ".rs")).write_text(source)
    seeds = (crate / "examples/fuzz_seeds.rs").read_text()
    (tmp / "up_seeds.rs").write_text(seeds.replace("\nfn values(", "\npub(super) fn values("))
    (tmp / "cases.rs").write_text((here / "cases.rs").read_text())
    args = ["rustc", "--edition=2024", "--cfg", 'feature="serde"', "-Awarnings", str(tmp / "cases.rs"),
            "-L", "dependency=" + str(Path(artifacts["fleece"]).parent)]
    for name in sorted(required):
        args += ["--extern", name + "=" + artifacts[name]]
    subprocess.run(args + ["-o", str(tmp / "cases")], check=True)
    with (here / "cases.json").open("wb") as out:
        subprocess.run([str(tmp / "cases")], stdout=out, check=True)
