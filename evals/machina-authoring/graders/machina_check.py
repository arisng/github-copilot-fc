#!/usr/bin/env python3
"""Program grader for the machina-authoring eval suite.

Extracts a Machina machine definition from the agent's output (a fenced
```json block, or the whole output when it is already pure JSON), writes it to
the waza workspace, and runs the skill's bundled machine-validator.py against
it deterministically.

Usage (invoked by waza's `program` grader):
    machina_check.py [--min-score N] [--require-golden]

Protocol:
    stdin                agent output
    WAZA_WORKSPACE_DIR   task workspace dir (env, provided by waza)
    exit 0               the emitted machine is structurally valid
    non-zero             invalid or score below threshold

The validator path is resolved relative to this script (repo-root skills dir),
so the grader works regardless of the invoking working directory.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
# evals/machina-authoring/graders -> repo root is 3 levels up
REPO_ROOT = SCRIPT_DIR.parents[2]
VALIDATOR = REPO_ROOT / "skills" / "machina-authoring" / "scripts" / "machine-validator.py"

FENCE_RE = re.compile(r"```(?:json)?\s*\n(.*?)```", re.DOTALL)


def extract_machine(output: str) -> dict | None:
    """Return the machine JSON from fenced block(s), else from bare JSON."""
    for match in FENCE_RE.finditer(output):
        try:
            return json.loads(match.group(1).strip())
        except json.JSONDecodeError:
            continue
    try:
        return json.loads(output.strip())
    except json.JSONDecodeError:
        return None


def run_validator(args, machine_path):
    # validator CLI parses (cmd, path, *flags) positionally; flags must trail the path
    return subprocess.run(
        [sys.executable, str(VALIDATOR), *args, str(machine_path)],
        capture_output=True, text=True,
    )


def grade_path(machine_path, min_score, require_golden):
    """Run validate (blocking) + score on the machine file; exit 0 = valid."""
    # 1. Structural validation (blocking).
    v = run_validator(["validate"], machine_path)
    if v.returncode != 0:
        print("machine FAILS structural validation:")
        print(v.stdout.strip() or v.stderr.strip())
        return 1

    # 2. Compliance score.
    s = subprocess.run(
        [sys.executable, str(VALIDATOR), "score", str(machine_path), "--text"],
        capture_output=True, text=True,
    )
    score_m = re.search(r"Score:\s*([\d.]+)", s.stdout)
    score = float(score_m.group(1)) if score_m else 0.0
    if require_golden and score < 90.0:
        print(f"score {score:.1f} < 90 (not Excellent); gaps:")
        for line in s.stdout.splitlines():
            if "Gaps:" in line or line.strip().startswith("[") or line.strip().startswith("  ["):
                print(line)
        return 1
    if score < min_score:
        print(f"score {score:.1f} < min_score {min_score:.1f}")
        return 1

    print(f"machine valid (score {score:.1f})")
    return 0


def main(argv):
    min_score = 0.0
    require_golden = False
    i = 0
    while i < len(argv):
        if argv[i] == "--min-score" and i + 1 < len(argv):
            min_score = float(argv[i + 1])
            i += 2
        elif argv[i] == "--require-golden":
            require_golden = True
            i += 1
        else:
            i += 1

    if not VALIDATOR.exists():
        print(f"FATAL: machine-validator.py not found at {VALIDATOR}", file=sys.stderr)
        return 2

    output = sys.stdin.read()
    machine = extract_machine(output)
    if machine is None:
        print("no machine JSON found in output (need a fenced ```json block or bare JSON)")
        return 1

    # Write the machine to a file the validator can read. Prefer the waza
    # workspace when provided; otherwise use an OS temp dir so we never write
    # into the invoking CWD (which can be the repo root in standalone runs).
    workspace = os.environ.get("WAZA_WORKSPACE_DIR", "").strip()
    if workspace and Path(workspace).is_dir():
        machine_path = Path(workspace) / "graded-machine.json"
        cleanup_path = None
    else:
        fd, tmp_name = tempfile.mkstemp(prefix="machina-graded-", suffix=".json")
        os.close(fd)
        machine_path = Path(tmp_name)
        # temp-file fallback only used standalone; remove it before exiting.
        cleanup_path = machine_path

    try:
        machine_path.write_text(json.dumps(machine, indent=2), encoding="utf-8")
        return grade_path(machine_path, min_score, require_golden)
    finally:
        if cleanup_path is not None:
            try:
                cleanup_path.unlink()
            except OSError:
                pass


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))