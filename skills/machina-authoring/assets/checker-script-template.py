#!/usr/bin/env python3
"""Read-only checker template for a Machina machine tool.

Copy this next to the machine as `scripts/check_<fact>.py`, register it in the machine's
`tools` map, and reference it from a state `checks[]` or a transition `requires[]`.
Never reference a checker only from `ensures[]` (the ensures-runner hook is not
installed) or from `invariants[]` (nothing executes it) — see
references/checker-scripts.md.

Usage: check_<fact>.py <target>

Contract enforced by machine-driver.py:
  exit 0   the fact holds — this is the machine's `expect_exit` (default 0)
  exit 1   the fact does not hold: the transition is blocked, this run's output is evidence
  exit 2   bad usage — never a verdict
  stdout   one JSON object, when the machine maps it through the tool's `output` field.
           The driver parses stdout + stderr concatenated, so a tool that declares
           `output` must print nothing but that object on either stream.
  stderr   human diagnostics — safe only when the tool declares no `output` mapping

Rules: read-only, deterministic, idempotent, no side effects, and finished before the run's
`init` (the driver pins this file's SHA-256 and fails the run if it changes). Invoke it by
path — `python3 scripts/check_x.py`, not `python3 check_x.py` — so the pin can resolve it.
"""
import json
import sys
from pathlib import Path


def check(target: Path) -> tuple[bool, dict]:
    """Decide one externally observable fact about `target`.

    Replace this body with the fact the modeled workflow actually depends on. Keep it
    read-only, and make sure it can return False: a checker that cannot fail is not
    evidence.
    """
    holds = target.is_file()
    return holds, {"valid": holds, "path": str(target)}


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {Path(sys.argv[0]).name} <target>", file=sys.stderr)
        return 2
    try:
        holds, payload = check(Path(sys.argv[1]))
    except OSError as exc:
        print(f"checker error: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(payload))
    return 0 if holds else 1


if __name__ == "__main__":
    sys.exit(main())
