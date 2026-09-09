"""Program grader for the machina-simulator replay eval suite.

Grades whether run history produced by the machina-driving skill is faithfully
re-playable by the machina-simulator engine. Two gates per produced run:

  Gate A (driver integrity): `machine-driver.py check --run <rid> --run-dir <root>`
      must return ok:true — the run's ledger chain + artifact hashes are intact.

  Gate B (simulator replay): `node scripts/replay-check.mjs <run-dir>` replays the
      run through the real engine (machine-simulator.mjs replayRunLedger with
      diffReeval + raw machineJson) and reports the trust verdicts the UI badge
      renders. Modes assert the replay verdicts equal ground truth.

Expectation flags (combine as needed):
  --expect-runs N                     exact number of produced run dirs (>=1)
  --expect-result SUCCESS|STUCK       at least one run's report.json has this result
  --expect-final-states s1,s2[,..]    each of these final_state ids exists in a run report
  --expect-terminal complete|stuck    the primary (result-matching) run replays to this
  --expect-min-blocked N              at least one run's replay blockedCount >= N
  --expect-nested                     at least one run's replay trace lists a child run
  --expect-hash-ok                    every run's replay machineHashOk is true
  --expect-tamper-detected            the only run's frozen machine.json was edited: driver
                                      check now REFUSES and replay reports machineHashOk=false
  --expect-no-drive                   negative: no run artifacts exist -> pass

Exit 0 only when all expectations + the integrity gates hold; non-zero with
diagnostics otherwise.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
DRIVER = REPO_ROOT / "skills" / "machina-driving" / "scripts" / "machine-driver.py"
VALIDATOR = REPO_ROOT / "skills" / "machina-authoring" / "scripts" / "machine-validator.py"
REPLAY_CHECK = SCRIPT_DIR.parent / "scripts" / "replay-check.mjs"

RUN_MARKERS = ("ledger.jsonl",)


def has_node():
    import shutil
    return shutil.which("node") is not None


def find_run_dirs(workspace):
    """Return run dirs (dirs directly containing ledger.jsonl) under the workspace."""
    out = []
    for p in workspace.rglob("ledger.jsonl"):
        out.append(p.parent)
    # deterministic order by directory name
    out.sort(key=lambda p: str(p).casefold())
    return out


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        return {"__read_error__": str(e)}


def run(popen_args, timeout=120, env_extra=None, cwd=None):
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    try:
        r = subprocess.run(popen_args, capture_output=True, text=True, env=env, timeout=timeout, cwd=cwd)
    except subprocess.TimeoutExpired:
        return None, "timed out"
    return r.stdout + r.stderr, None


def driver_check(run_dir):
    """Gate A: deterministic driver integrity check."""
    run_id = run_dir.name
    base_dir = run_dir.parent
    out, _ = run(
        [sys.executable, str(DRIVER), "check", "--run", run_id, "--run-dir", str(base_dir)],
        env_extra={"MACHINA_VALIDATOR": str(VALIDATOR)},
    )
    try:
        return json.loads(out).get("ok") is True
    except (json.JSONDecodeError, TypeError):
        return False


def sim_replay(run_dir):
    """Gate B: replay through the actual simulator engine."""
    if not REPLAY_CHECK.exists():
        return {"__error__": f"replay-check.mjs missing at {REPLAY_CHECK}"}
    out, _ = run(["node", str(REPLAY_CHECK), str(run_dir)])
    try:
        return json.loads(out)
    except (json.JSONDecodeError, TypeError):
        return {"__error__": f"replay harness produced non-JSON: {(out or '')[:300]}"}


def main(argv):
    expect_runs = None
    expect_result = "SUCCESS"
    expect_final_states = None
    expect_terminal = None
    expect_min_blocked = 0
    expect_nested = False
    expect_hash_ok = False
    expect_tamper = False
    expect_no_drive = False

    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--expect-runs" and i + 1 < len(argv):
            expect_runs = int(argv[i + 1]); i += 2
        elif a == "--expect-result" and i + 1 < len(argv):
            expect_result = argv[i + 1].upper(); i += 2
        elif a == "--expect-final-states" and i + 1 < len(argv):
            expect_final_states = [s.strip() for s in argv[i + 1].split(",") if s.strip()]; i += 2
        elif a == "--expect-terminal" and i + 1 < len(argv):
            expect_terminal = argv[i + 1]; i += 2
        elif a == "--expect-min-blocked" and i + 1 < len(argv):
            expect_min_blocked = int(argv[i + 1]); i += 2
        elif a == "--expect-nested":
            expect_nested = True; i += 1
        elif a == "--expect-hash-ok":
            expect_hash_ok = True; i += 1
        elif a == "--expect-tamper-detected":
            expect_tamper = True; i += 1
        elif a == "--expect-no-drive":
            expect_no_drive = True; i += 1
        else:
            i += 1

    for need in (DRIVER, VALIDATOR):
        if not need.exists():
            print(f"FATAL: {need} missing", file=sys.stderr); return 2
    if not has_node():
        print("FATAL: node not found on PATH - replay harness requires node", file=sys.stderr); return 2

    workspace_raw = os.environ.get("WAZA_WORKSPACE_DIR", "").strip()
    workspace = Path(workspace_raw) if workspace_raw and Path(workspace_raw).is_dir() else None

    if workspace is None:
        if expect_no_drive:
            print("OK: no workspace (and thus no run artifacts) - expected for a negative case")
            return 0
        print("FATAL: WAZA_WORKSPACE_DIR not set or not a directory - cannot artifact-grade.")
        return 2

    run_dirs = find_run_dirs(workspace)
    if expect_no_drive:
        if run_dirs:
            print("negative case violated - run artifacts exist:")
            for rd in run_dirs:
                print(f"  - {rd}")
            return 1
        print("OK: no run artifacts produced (expected for a negative case)")
        return 0

    if not run_dirs:
        print(f"no run dirs (ledger.jsonl) found under the workspace at {workspace} - "
              "the agent did not drive any machine with machine-driver.py.")
        return 1
    if expect_runs is not None and len(run_dirs) != expect_runs:
        print(f"found {len(run_dirs)} run(s), expected {expect_runs}:")
        for rd in run_dirs:
            print(f"  - {rd}")
        return 1

    rows = []
    problems = []
    report_states = []  # (run_dir_name, result, final_state)
    replay_ok_all = True

    for rd in run_dirs:
        report = read_json(rd / "report.json")
        rep = sim_replay(rd)
        chk = driver_check(rd)

        r = {
            "run_dir": str(rd),
            "run_id": rd.name,
            "report": report,
            "replay": rep,
            "driver_check_ok": chk,
        }
        rows.append(r)

        rep_err = rep.get("__error__")
        if rep_err:
            problems.append(f"{rd.name}: replay harness error - {rep_err}")
            replay_ok_all = False
            continue

        if not rep.get("ok"):
            problems.append(f"{rd.name}: replay harness returned ok=false ({rep.get('error')})")
            replay_ok_all = False
            continue

        if not expect_tamper and not rep.get("integrity", {}).get("ok"):
            problems.append(
                f"{rd.name}: simulator replay integrity = {rep['integrity'].get('verdict')} "
                f"at record {rep['integrity'].get('indexOfFirstFailure')} "
                f"(failureKind={rep['integrity'].get('failureKind')})"
            )
            replay_ok_all = False

        if expect_hash_ok and rep.get("machineHashOk") is not True:
            problems.append(f"{rd.name}: machineHashOk = {rep.get('machineHashOk')}, expected true")
            replay_ok_all = False

        # accumulate report facts for the primary-run scans
        if isinstance(report, dict) and "__read_error__" not in report:
            report_states.append((rd.name, report.get("result"), report.get("final_state")))

    if expect_tamper:
            # exactly-one run expected (the grader signature the task shows). The pre-tamper
            # report must still carry the genuine result; the tampered machine.json copy makes
            # the driver check refuse AND the simulator replay report HASH MISMATCH.
            if len(run_dirs) != 1:
                problems.append(f"tamper case expects exactly one run, found {len(run_dirs)}")
            else:
                r = rows[0]
                rep = r["replay"]
                if r["driver_check_ok"]:
                    problems.append(f"tamper case NOT proven: driver check returned ok - "
                                    "expected an integrity violation (frozen machine.json was edited)")
                if rep.get("machineHashOk") is not False:
                    problems.append(f"tamper case NOT proven: replay machineHashOk = {rep.get('machineHashOk')}, "
                                    "expected false (HASH MISMATCH badge)")
                if r["report"].get("result") != expect_result:
                    problems.append(f"tamper case: pre-tamper report result = {r['report'].get('result')!r}, "
                                    f"expected {expect_result!r}")
                if expect_final_states:
                    rs = r["report"].get("final_state")
                    if rs not in expect_final_states:
                        problems.append(f"tamper case: pre-tamper report final_state = {rs!r}, "
                                        f"expected one of {expect_final_states}")
    else:
        # genuine drives: driver check must pass on every run
        for r in rows:
            if not r["driver_check_ok"]:
                problems.append(f"{r['run_id']}: driver check FAILED - run ledger/artifacts not intact")
        if not replay_ok_all:
            problems.append("simulator replay reported integrity/machine-hash failures on genuine runs")

    # report-fact expectations (run on non-tamper cases; tamper asserts result separately)
    if not expect_tamper:
        if not report_states:
            problems.append("no valid report.json found in any run dir - the agent did not emit machina.report.v1")
        else:
            if not any(rs[1] == expect_result for rs in report_states):
                problems.append(f"no run report has result {expect_result}: "
                                f"{[(s[0], s[1], s[2]) for s in report_states]}")
            if expect_final_states:
                states = {s[2] for s in report_states}
                missing = [fs for fs in expect_final_states if fs not in states]
                if missing:
                    problems.append(f"missing final_state(s) {missing} in run reports (have {sorted(states)})")
            # primary run = first whose report result matches
            primary = next((s for s in report_states if s[1] == expect_result), None)
            rp_run = rows[[rd.name for rd in run_dirs].index(primary[0])] if primary else None
            if expect_terminal and rp_run is not None:
                rep_terminal = rp_run["replay"].get("terminal")
                if rep_terminal != expect_terminal:
                    problems.append(f"{primary[0]}: replay terminal = {rep_terminal}, expected {expect_terminal}")

    if expect_min_blocked:
        blocked_counts = [(r["run_id"], r["replay"].get("blockedCount", 0)) for r in rows
                          if "__error__" not in r["replay"]]
        if not any(bc >= expect_min_blocked for _, bc in blocked_counts):
            problems.append(f"no run has blockedCount >= {expect_min_blocked}: {blocked_counts}")

    if expect_nested:
        child_counts = [(r["run_id"], r["replay"].get("childRuns", [])) for r in rows
                        if "__error__" not in r["replay"]]
        if not any(bool(list_refs) for _, list_refs in child_counts):
            problems.append(f"no run's replay trace lists a child run (nested badge): {child_counts}")

    if problems:
        print("simulator replay eval FAILED:")
        for p in problems:
            print(f"  - {p}")
        print(f"  runs found: {[rd.name for rd in run_dirs]}")
        for r in rows:
            rep = r["replay"]
            if "__error__" not in rep:
                print(f"    {r['run_id']}: driver_check={r['driver_check_ok']} "
                      f"replay={rep.get('integrity', {}).get('verdict')} "
                      f"hash_ok={rep.get('machineHashOk')} terminal={rep.get('terminal')} "
                      f"state={rep.get('state')} blocked={rep.get('blockedCount')} "
                      f"mismatch={rep.get('guardMismatchCount')} child={rep.get('childRuns', [])}")
        return 1

    terminal_note = f" terminal={expect_terminal}" if expect_terminal else ""
    nested_note = " nested=yes" if expect_nested else ""
    print(f"OK: {len(run_dirs)} run(s) replay faithfully through the machina-simulator engine"
          f"{terminal_note}{nested_note}; driver check {len(run_dirs)}/{len(run_dirs)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))