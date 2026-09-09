import json
import os
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
DRIVER = REPO_ROOT / "skills" / "machina-driving" / "scripts" / "machine-driver.py"
VALIDATOR = REPO_ROOT / "skills" / "machina-authoring" / "scripts" / "machine-validator.py"

REPORT = "report.json"


def find_report_json(workspace):
    candidates = sorted(workspace.rglob(REPORT), key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates[0] if candidates else None


def run_driver(args):
    env = dict(os.environ)
    env["MACHINA_VALIDATOR"] = str(VALIDATOR)
    return subprocess.run(
        [sys.executable, str(DRIVER), *args],
        capture_output=True, text=True, env=env, timeout=90,
    )


def main(argv):
    expect_result = "SUCCESS"
    expect_final_state = None
    expect_no_drive = False
    i = 0
    while i < len(argv):
        if argv[i] == "--expect-result" and i + 1 < len(argv):
            expect_result = argv[i + 1].upper()
            i += 2
        elif argv[i] == "--expect-final-state" and i + 1 < len(argv):
            expect_final_state = argv[i + 1]
            i += 2
        elif argv[i] == "--expect-no-drive":
            expect_no_drive = True
            i += 1
        else:
            i += 1

    if not DRIVER.exists():
        print(f"FATAL: machine-driver.py not found at {DRIVER}", file=sys.stderr)
        return 2
    if not VALIDATOR.exists():
        print(f"FATAL: machine-validator.py not found at {VALIDATOR}", file=sys.stderr)
        return 2

    workspace_raw = os.environ.get("WAZA_WORKSPACE_DIR", "").strip()
    workspace = Path(workspace_raw) if workspace_raw and Path(workspace_raw).is_dir() else None
    if workspace is None:
        if expect_no_drive:
            print("OK: no workspace (and thus no drive artifact) - expected for a negative case")
            return 0
        print("FATAL: WAZA_WORKSPACE_DIR is not set or not a directory - cannot artifact-grade.")
        return 2

    if sys.stdin and not sys.stdin.isatty():
        agent_output = sys.stdin.read()
    else:
        agent_output = ""

    report_path = find_report_json(workspace)
    if expect_no_drive:
        if report_path is not None:
            print(f"negative case violated: report.json found at {report_path} - "
                  "the agent drove the machine when it should not have.")
            return 1
        print("OK: no drive artifact produced (expected for a negative case)")
        return 0
    if report_path is None:
        print(
            "no report.json found under the workspace - the agent did not drive the "
            "machine to a terminal report (did they run machine-driver.py report?)."
        )
        return 1

    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"report.json at {report_path} is not valid JSON: {e}")
        return 1

    problems = []
    if report.get("schema") != "machina.report.v1":
        problems.append(f'schema is {report.get("schema")!r}, expected "machina.report.v1"')
    if report.get("result") != expect_result:
        problems.append(f"result is {report.get('result')!r}, expected {expect_result!r}")
    if expect_final_state and report.get("final_state") != expect_final_state:
        problems.append(f"final_state is {report.get('final_state')!r}, expected {expect_final_state!r}")
    if not report.get("ledger_final_hash"):
        problems.append("ledger_final_hash missing - report is not bound to the ledger")

    if problems:
        print(f"report {report_path} does not match expectations:")
        for p in problems:
            print(f"  - {p}")
        print(f"  report: {json.dumps(report)}")
        return 1

    run_id = report_path.parent.name
    base_dir = report_path.parent.parent
    chk = run_driver(["check", "--run", run_id, "--run-dir", str(base_dir)])
    try:
        chk_json = json.loads(chk.stdout)
    except json.JSONDecodeError:
        chk_json = None
    ok = bool(chk_json and chk_json.get("ok"))
    if not ok:
        print(f"driver check FAILED for run {run_id} ({report_path}):")
        print(chk.stdout.strip() or chk.stderr.strip())
        return 1

    print(f"OK: genuine drive reached {expect_result}@{expect_final_state or '?'} "
          f"and driver check verifies the ledger ({run_id})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
