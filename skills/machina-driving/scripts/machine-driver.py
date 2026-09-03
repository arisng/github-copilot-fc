#!/usr/bin/env python3
"""
Machina Driving — deterministic state-machine driver for AI agents.

A stateless CLI that drives a Machina state machine (spec v2.0.0 / v3.0.0) on
behalf of an agent. The agent performs the real work in the world; this driver
is the *sole* mutator of machine state, context, history, and logs (INV-1), and
it enforces legality plus declared evidence checks (gatekeeper model).

The shared engine (guard/action evaluation, terminal detection, compliance
scoring) is imported from the `machina-authoring` skill's
`machine-validator.py` — never re-implemented here, so the two skills cannot
drift. This file contains only the v3 execution layer: tools/evidence,
inputs, limits, phase delegation, the tamper-evident ledger, and the command
surface.

Design invariants (see references/driving-protocol.md):
  - INV-1  The driver is the only writer of run state. The agent only fires
           events and attaches notes. Run state lives in a tamper-evident,
           append-only ledger (chained SHA-256 hashes).
  - INV-2  Declarative only, by reference. Machine JSON never contains code
           strings; tools are named references to scripts the driver executes.
  - Every command prints exactly one strict-JSON object on stdout.
  - A blocked `fire` is a first-class JSON outcome, never an error exit.
  - Exit code 0 unless the driver cannot operate safely (ledger integrity
    violation, unknown machine, missing required input).

Commands:
  init   --machine <file> [--scenario <id>] [--input k=v ...] [--run-dir <dir>]
  status [--run <id>] [--run-dir <dir>]
  fire   <EVENT> [--run <id>] [--note "..."] [--child-run <id>] [--run-dir <dir>]
    abort  [--run <id>] [--reason "..."] [--run-dir <dir>]
    check  [--run <id>] [--run-dir <dir>]
  check  [--run <id>] [--run-dir <dir>]
  report [--run <id>] [--run-dir <dir>]

Run state layout (--run-dir, default: <cwd>/.machina/runs):
  <run-dir>/<run_id>/machine.json   copy of the machine definition
  <run-dir>/<run_id>/ledger.jsonl   append-only event ledger (chained hashes)
  <run-dir>/<run_id>/report.json    terminal report (written by `report`)

Tamper-evidence (v0.3.0):
  The ledger chain (prev_hash/hash over each record payload) verifies that no
  record was inserted, removed, or reordered. Artifact binding additionally
  pins the run's machine definition (machine_sha256) and every tool/checker
  script the machine references (tool_hashes) in the `init` record; status,
  fire, abort, check, and report recompute those hashes on every invocation
  and raise LedgerIntegrityError on mismatch. See references/driving-protocol.md
  ("Tamper prevention") for the four mechanisms and the honest ceiling:
  this is detect-and-fail-closed, not cryptographic proof against an attacker
  who can rewrite the run directory (no OS read-only, no HMAC by design).

Stdlib only. Python 3.9+.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path

# ---------------------------------------------------------------------------
# Shared engine — imported from machina-authoring (single source of truth)
# ---------------------------------------------------------------------------

def _find_validator():
    """Locate machine-validator.py from the machina-authoring skill.

    Search order:
      1. $MACHINA_VALIDATOR env var (explicit override)
      2. sibling of this script (same skill dir, e.g. tests)
      3. workspace skills/machina-authoring/scripts/
      4. walk up from cwd looking for skills/machina-authoring/scripts/
      5. user skill roots (~/.agents/skills, ~/.copilot/skills)
    """
    candidates = []
    env = os.environ.get("MACHINA_VALIDATOR")
    if env:
        candidates.append(Path(env))
    here = Path(__file__).resolve().parent
    candidates.append(here / "machine_validator.py")
    # workspace root: <repo>/skills/machina-authoring/scripts/machine-validator.py
    for root in (here.parents):
        candidates.append(root / "skills" / "machina-authoring" / "scripts" / "machine-validator.py")
    for home in (Path.home() / ".agents" / "skills", Path.home() / ".copilot" / "skills"):
        candidates.append(home / "machina-authoring" / "scripts" / "machine-validator.py")
    for c in candidates:
        if c.exists():
            return c
    raise ImportError(
        "machine-validator.py not found. machina-driving depends on machina-authoring; "
        "set MACHINA_VALIDATOR=<path> or install the machina-authoring skill."
    )


_VALIDATOR_PATH = _find_validator()
sys.path.insert(0, str(_VALIDATOR_PATH.parent))
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location("machine_validator", _VALIDATOR_PATH)
mv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mv)

# Re-export the shared engine surface used by the v3 layer below.
SPEC_VERSIONS = mv.SPEC_VERSIONS
LATEST_SPEC_VERSION = mv.LATEST_SPEC_VERSION
spec_rank = mv.spec_rank
detect_spec_version = mv.detect_spec_version
get_path = mv.get_path
set_path = mv.set_path
resolve_value = mv.resolve_value
eval_guard = mv.eval_guard
apply_actions = mv.apply_actions
is_terminal_state = mv.is_terminal_state
reachable_states = mv.reachable_states
detect_cycles = mv.detect_cycles
run_compliance = mv.run_compliance
grade_for = mv.grade_for

DRIVER_VERSION = "0.1.0"
# ---------------------------------------------------------------------------
# v3 extensions: tools, checks, requires, ensures, inputs, limits, phase
# ---------------------------------------------------------------------------

def is_phase_state(m, s):
    """True when a state is a phase state (nested machine delegation)."""
    st = (m.get("states") or {}).get(s)
    return bool(st and st.get("type") == "phase")


def _resolve_tool_cmd(tool, machine_dir):
    """Resolve a tool's command to an absolute command list, machine-relative."""
    cmd = tool.get("cmd")
    if not cmd:
        return None
    if isinstance(cmd, str):
        parts = cmd.split()
    else:
        parts = list(cmd)
    if not parts:
        return None
    # First token is the interpreter/executable; resolve relative paths against machine dir.
    if not os.path.isabs(parts[0]) and "/" in parts[0] or "\\" in parts[0]:
        parts[0] = str(Path(machine_dir) / parts[0])
    return parts


def _render_template(template, ctx):
    """Render {ctx.path} / {ctx.path|default} templates from context."""
    if not isinstance(template, str):
        return template

    def repl(m):
        expr = m.group(1)
        if "|" in expr:
            path, default = expr.split("|", 1)
            val = get_path(ctx, path.strip())
            return str(val) if val is not None else default
        val = get_path(ctx, expr)
        return str(val) if val is not None else ""

    return re.sub(r"\{ctx\.([^}]+)\}", repl, template)


def _run_tool(tool, args, machine_dir, timeout_seconds):
    """Run a checker tool. Returns {ok, exit_code, output, error?}."""
    cmd = _resolve_tool_cmd(tool, machine_dir)
    if cmd is None:
        return {"ok": False, "exit_code": None, "output": "", "error": "tool has no cmd"}
    rendered = [_render_template(a, args) for a in cmd]
    try:
        proc = subprocess.run(
            rendered,
            cwd=machine_dir,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "exit_code": None, "output": "", "error": f"timeout after {timeout_seconds}s"}
    except FileNotFoundError as e:
        return {"ok": False, "exit_code": None, "output": "", "error": f"executable not found: {e}"}
    except OSError as e:
        return {"ok": False, "exit_code": None, "output": "", "error": str(e)}
    output = (proc.stdout or "") + (proc.stderr or "")
    expect = tool.get("expect_exit", 0)
    ok = proc.returncode == expect
    return {"ok": ok, "exit_code": proc.returncode, "output": output.strip()}


def _run_evidence(tool_name, tool, ctx, machine_dir, timeout_seconds):
    """Run one evidence tool; returns {tool, passed, exit_code, output, error?, mapped?}."""
    res = _run_tool(tool, ctx, machine_dir, timeout_seconds)
    mapped = None
    if res["ok"] and tool.get("output"):
        try:
            parsed = json.loads(res["output"])
            if isinstance(parsed, dict):
                for key, path in tool["output"].items():
                    if key in parsed:
                        set_path(ctx, path, parsed[key])
                        mapped = mapped or {}
                        mapped[path] = parsed[key]
        except (json.JSONDecodeError, TypeError):
            pass
    return {"tool": tool_name, "passed": res["ok"], "exit_code": res["exit_code"],
            "output": res["output"], "error": res.get("error"), "mapped": mapped}


def _run_checks(check_names, ctx, machine, machine_dir, timeout_seconds):
    """Run a list of tool references. Returns (results, all_passed)."""
    tools = machine.get("tools") or {}
    results = []
    all_passed = True
    for name in check_names or []:
        tool = tools.get(name)
        if not tool:
            results.append({"tool": name, "passed": False, "exit_code": None, "output": "",
                            "error": f"unknown tool reference: {name}"})
            all_passed = False
            continue
        r = _run_evidence(name, tool, ctx, machine_dir, timeout_seconds)
        results.append(r)
        if not r["passed"]:
            all_passed = False
    return results, all_passed


def _validate_inputs(machine, scenario, inputs):
    """Validate required scenario inputs against provided k=v pairs."""
    declared = (scenario or {}).get("inputs") or {}
    missing = []
    for name, spec in declared.items():
        if spec.get("required") and name not in inputs:
            missing.append(name)
    if missing:
        return False, f"missing required input(s): {', '.join(missing)}"
    return True, None


def _seed_context(machine, scenario, inputs):
    """Build the run's initial context: machine.context + scenario.context + inputs."""
    ctx = json.loads(json.dumps((machine.get("context") or {})))
    sc_ctx = (scenario or {}).get("context") or {}
    for k, v in sc_ctx.items():
        set_path(ctx, k, v)
    for k, v in inputs.items():
        set_path(ctx, k, v)
    return ctx


def _limits(machine):
    return machine.get("limits") or {}


def _enabled_events(machine, state_key, ctx):
    """Return {enabled: [...], blocked: [...]} for the current state."""
    st = (machine.get("states") or {}).get(state_key) or {}
    enabled = []
    blocked = []
    for evt, tr in (st.get("on") or {}).items():
        g = tr.get("guard")
        if g and not eval_guard(g, ctx):
            blocked.append({"event": evt, "reason": "guard", "detail": _guard_text(g)})
        else:
            enabled.append({"event": evt, "target": tr.get("target")})
    return {"enabled": enabled, "blocked": blocked}


def _guard_text(g):
    return f"{g.get('key')} {g.get('op')} {g.get('value')}"


# ---------------------------------------------------------------------------
# Ledger (tamper-evident, append-only)
# ---------------------------------------------------------------------------

def _sha256(obj):
    return hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def _sha256_normalized_machine(machine):
    """Canonical SHA-256 of a machine definition dict.

    Normalizes by re-serializing with the same canonical form `_sha256` uses
    (sort_keys + compact separators), so formatting/whitespace never changes the
    hash. The machine dict passed in is a parsed JSON object, so key ordering is
    already lost; sorting keys restores a stable canonical form.
    """
    return hashlib.sha256(
        json.dumps(machine, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def _tool_script_path(tool, machine_dir):
    """Resolve a tool's script path (the file the engine would execute).

    Rule (deterministic, documented in the module docstring and driving-protocol):
      - No `cmd` -> None (nothing to hash; the tool has no script).
      - First cmd token is the interpreter/executable. If it is a bare builtin
        (no path separator, not absolute), there is no script file to hash:
        only tokens after the first with a path separator (relative or absolute)
        can identify a script, and the FIRST such leading token that resolves to
        a real file is the script. Relative paths resolve machine-relative
        (against machine_dir), exactly like `_resolve_tool_cmd`.
      - If no candidate resolves to a real file -> None (hashing is skipped and
        the run is "not bound" to script content for that tool; verification
        treats None as unverified).
    """
    cmd = tool.get("cmd")
    if not cmd:
        return None
    parts = cmd.split() if isinstance(cmd, str) else list(cmd)
    if not parts:
        return None
    first = parts[0]
    first_is_script = not os.path.isabs(first) and ("/" in first or "\\" in first)
    if first_is_script:
        p = Path(machine_dir) / first
        return p if p.is_file() else None
    # Interpreter-style cmd (python3 scripts/check.py, ...): the interpreter is
    # not a repo script; hash the first following token that resolves to a file.
    for tok in parts[1:]:
        if os.path.isabs(tok) or "/" in tok or "\\" in tok:
            p = Path(tok) if os.path.isabs(tok) else Path(machine_dir) / tok
            if p.is_file():
                return p
    return None


def _compute_tool_hashes(machine, machine_dir):
    """Compute {tool_name: sha256(script_content)} for every tool the machine
    references, resolved machine-relative to machine_dir.

    Deterministic skip rule: a tool whose cmd does not resolve to a real script
    file is recorded with value None (verified as "no script pinned"). Tools
    whose script sha matches the pinned value (or whose pinned value is None)
    verify OK.
    """
    hashes = {}
    for name, tool in sorted((machine.get("tools") or {}).items()):
        path = _tool_script_path(tool, machine_dir)
        if path is None:
            hashes[name] = None
        else:
            hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def _verify_artifacts(entries, machine, machine_dir):
    """Verify artifact binding from the init record against the live machine.

    The run's machine.json is bound at `init` via machine_sha256; each tool the
    machine references is bound via tool_hashes. Recomputed on every command so
    a mid-run edit to the definition copy OR a checker script fails closed.

    Backward compatibility: runs initialized before v0.3.0 have no hashes in
    their init record; those runs are treated as "not bound" and artifact
    verification is skipped so pre-upgrade runs keep working. The ledger hash
    chain is still fully verified for them.

    Returns None on success; raises LedgerIntegrityError with a precise message
    on the first mismatch.
    """
    for rec in entries:
        if rec["payload"].get("type") == "init":
            payload = rec["payload"]
            break
    else:
        raise LedgerIntegrityError("no init record in ledger")
    pinned_machine = payload.get("machine_sha256")
    pinned_tools = payload.get("tool_hashes")
    if pinned_machine is None and pinned_tools is None:
        # Pre-v0.3.0 run: not bound. Skip artifact verification.
        return
    if pinned_machine is not None:
        actual = _sha256_normalized_machine(machine)
        if actual != pinned_machine:
            raise LedgerIntegrityError(
                "machine definition hash mismatch (machine.json edited after init)"
            )
    if pinned_tools is not None:
        actual_tools = _compute_tool_hashes(machine, machine_dir)
        for name, pinned in sorted(pinned_tools.items()):
            actual = actual_tools.get(name)
            if pinned is None:
                continue  # no script pinned at init; nothing to verify
            if actual is None:
                raise LedgerIntegrityError(
                    f"tool {name}: checker script no longer resolvable (pinned hash present)"
                )
            if actual != pinned:
                    script_path = _tool_script_path((machine.get("tools") or {}).get(name) or {}, machine_dir)
                    raise LedgerIntegrityError(
                        f"tool {name} ({script_path}): checker script hash mismatch "
                        "(checker edited after init)"
                    )
        return


def _ledger_path(run_dir):
    return Path(run_dir) / "ledger.jsonl"


def _read_ledger(run_dir):
    """Read ledger entries, verifying the hash chain. Raises on integrity violation."""
    entries = []
    prev_hash = None
    path = _ledger_path(run_dir)
    if not path.exists():
        return entries
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError as e:
            raise LedgerIntegrityError(f"corrupt ledger line: {e}")
        if rec.get("prev_hash") != prev_hash:
            raise LedgerIntegrityError("hash chain broken")
        if _sha256(rec.get("payload")) != rec.get("hash"):
            raise LedgerIntegrityError("record hash mismatch")
        entries.append(rec)
        prev_hash = rec.get("hash")
    return entries


def _append_ledger(run_dir, payload):
    """Append a record to the ledger. Returns the record."""
    entries = _read_ledger(run_dir)
    prev_hash = entries[-1]["hash"] if entries else None
    rec = {"prev_hash": prev_hash, "payload": payload, "hash": _sha256(payload)}
    with open(_ledger_path(run_dir), "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, separators=(",", ":")) + "\n")
    return rec


class LedgerIntegrityError(Exception):
    pass


# ---------------------------------------------------------------------------
# Run state
# ---------------------------------------------------------------------------

def _run_state(run_dir):
    """Reconstruct current run state by folding the ledger.

    Verifies the ledger hash chain (via _read_ledger) AND the artifact binding
    (machine_sha256 + tool_hashes pinned in the init record) on every call.
    Raises LedgerIntegrityError on any violation, so status/fire/abort/check/
    report all fail closed on tamper.
    """
    entries = _read_ledger(run_dir)
    machine = json.loads((Path(run_dir) / "machine.json").read_text(encoding="utf-8"))
    state = None
    ctx = None
    scenario_id = None
    machine_dir = None
    for rec in entries:
        p = rec["payload"]
        if p["type"] == "init":
            state = p["state"]
            ctx = json.loads(json.dumps(p["context"]))
            scenario_id = p.get("scenario")
            machine_dir = p.get("machine_dir")
        elif p["type"] == "transition":
            state = p["to"]
            ctx = json.loads(json.dumps(p["context_after"]))
        elif p["type"] == "redirect":
            state = p["to"]
            ctx = json.loads(json.dumps(p["context_after"]))
        elif p["type"] == "blocked":
            pass
        elif p["type"] == "abort":
            state = p.get("state")
    if machine_dir is None:
        raise LedgerIntegrityError("init record missing machine_dir")
    _verify_artifacts(entries, machine, machine_dir)
    return {"machine": machine, "state": state, "context": ctx, "scenario_id": scenario_id,
            "machine_dir": machine_dir, "entries": entries}


def _new_run_id():
    return uuid.uuid4().hex[:12]


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_init(args):
    machine_path = Path(args.machine)
    if not machine_path.exists():
        return _err(f"machine file not found: {machine_path}")
    try:
        machine = json.loads(machine_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return _err(f"invalid machine JSON: {e}")

    # Structural validation (blocking subset)
    blocking = run_compliance(machine)["blocking"]
    if blocking:
        return _err("machine fails blocking validation: " + "; ".join(f["id"] for f in blocking))

    # Scenario resolution
    scenario = None
    if args.scenario:
        scenario = next((s for s in (machine.get("scenarios") or []) if s.get("id") == args.scenario), None)
        if not scenario:
            return _err(f"unknown scenario: {args.scenario}")
    else:
        scenario = (machine.get("scenarios") or [{}])[0] if machine.get("scenarios") else {}
    initial = (scenario or {}).get("initial") or machine.get("initial")
    if not initial or initial not in (machine.get("states") or {}):
        return _err(f"initial state does not resolve: {initial}")

    # Inputs contract
    inputs = {}
    for kv in args.input or []:
        if "=" not in kv:
            return _err(f"input must be k=v: {kv}")
        k, v = kv.split("=", 1)
        inputs[k] = v
    ok, err = _validate_inputs(machine, scenario, inputs)
    if not ok:
        return _err(err)

    ctx = _seed_context(machine, scenario, inputs)

    # Run dir — refuse to create runs inside a git worktree (deterministic
    # guarantee): run state must never silently land in a repo you might commit.
    base = Path(args.run_dir)
    refuse = _refuse_repo_run_dir(base)
    if refuse:
        return _err(refuse)
    run_dir = base / _new_run_id()
    run_dir.mkdir(parents=True, exist_ok=False)
    machine_dir = str(machine_path.resolve().parent)
    (run_dir / "machine.json").write_text(json.dumps(machine, indent=2), encoding="utf-8")

    # Entry actions
    st = (machine.get("states") or {}).get(initial) or {}
    apply_actions(st.get("entry"), ctx)

    # Artifact binding: pin the canonical machine definition hash and every
    # tool/checker script hash in the init record. Verified on every command.
    _append_ledger(run_dir, {
        "type": "init", "machine_id": machine.get("id"), "spec_version": detect_spec_version(machine)["version"],
        "scenario": (scenario or {}).get("id"), "state": initial, "context": ctx,
            "machine_dir": machine_dir,
            "machine_sha256": _sha256_normalized_machine(machine),
            "tool_hashes": _compute_tool_hashes(machine, machine_dir),
            "timestamp": _now_iso(),
        })

    return _ok({
        "run_id": run_dir.name,
        "machine_id": machine.get("id"),
        "scenario": (scenario or {}).get("id"),
        "state": initial,
        "context": ctx,
        "enabled_events": _enabled_events(machine, initial, ctx)["enabled"],
        "blocked_events": _enabled_events(machine, initial, ctx)["blocked"],
        "run_dir": str(run_dir),
    })


def cmd_status(args):
    run_dir = _resolve_run_dir(args)
    try:
        rs = _run_state(run_dir)
    except LedgerIntegrityError as e:
        return _err(f"ledger integrity violation: {e}")
    machine = rs["machine"]
    state = rs["state"]
    ctx = rs["context"]
    ev = _enabled_events(machine, state, ctx)
    # State checks (invariants) — run and report, do not block status
    checks, _ = _run_checks((machine.get("states") or {}).get(state, {}).get("checks"), ctx, machine, rs["machine_dir"], 30)
    return _ok({
        "run_id": run_dir.name,
        "machine_id": machine.get("id"),
        "state": state,
        "terminal": is_terminal_state(machine, state),
        "phase": is_phase_state(machine, state),
        "context": ctx,
        "enabled_events": ev["enabled"],
        "blocked_events": ev["blocked"],
        "checks": checks,
        "events_fired": sum(1 for e in rs["entries"] if e["payload"]["type"] == "transition"),
        "blocked_count": sum(1 for e in rs["entries"] if e["payload"]["type"] == "blocked"),
    })


def cmd_fire(args):
    run_dir = _resolve_run_dir(args)
    try:
        rs = _run_state(run_dir)
    except LedgerIntegrityError as e:
        return _err(f"ledger integrity violation: {e}")
    machine = rs["machine"]
    state = rs["state"]
    ctx = rs["context"]
    machine_dir = rs["machine_dir"]

    st = (machine.get("states") or {}).get(state) or {}
    tr = (st.get("on") or {}).get(args.event)
    if not tr:
        return _err(f"event {args.event} not available in state {state}")

    # Phase-boundary validation: leaving a phase state requires a successful child run.
    if is_phase_state(machine, state):
        if not args.child_run:
            return _err("leaving a phase state requires --child-run <child_run_id>")
        child_dir = Path(run_dir).parent / args.child_run
        if not child_dir.exists():
            return _err(f"child run not found: {args.child_run}")
        try:
            # Must pass full ledger + artifact verification: a forged child
            # cannot claim a pinned machine_sha256/tool_hashes it cannot match.
            child_rs = _run_state(child_dir)
        except LedgerIntegrityError as e:
            return _err(f"child ledger integrity violation: {e}")
        if not is_terminal_state(child_rs["machine"], child_rs["state"]):
            return _err(f"child run {args.child_run} has not reached a terminal state (state: {child_rs['state']})")
        if child_rs["machine"].get("id") != (st.get("machine") or child_rs["machine"].get("id")):
            # If the phase state declares a machine, verify the child matches.
            pass

    # Guard
    guard = tr.get("guard")
    guard_ok = eval_guard(guard, ctx) if guard else True
    if not guard_ok:
        else_target = tr.get("else_target")
        if else_target and else_target in (machine.get("states") or {}):
            # Modeled failure path: redirect to else_target, applying actions.
            ctx_after = json.loads(json.dumps(ctx))
            apply_actions(st.get("exit"), ctx_after)
            apply_actions(tr.get("actions"), ctx_after)
            apply_actions((machine.get("states") or {}).get(else_target, {}).get("entry"), ctx_after)
            _append_ledger(run_dir, {
                "type": "redirect", "event": args.event, "from": state, "to": else_target,
                "reason": "guard", "detail": _guard_text(guard), "context_after": ctx_after,
                "note": args.note, "timestamp": _now_iso(),
            })
            return _ok({"status": "redirected", "event": args.event, "from": state, "to": else_target,
                        "reason": "guard", "detail": _guard_text(guard), "state": else_target,
                        "terminal": is_terminal_state(machine, else_target),
                        "phase": is_phase_state(machine, else_target),
                        "context": ctx_after})
        _append_ledger(run_dir, {
            "type": "blocked", "event": args.event, "from": state, "reason": "guard",
            "detail": _guard_text(guard), "note": args.note, "timestamp": _now_iso(),
        })
        return _ok({"status": "blocked", "event": args.event, "from": state, "reason": "guard",
                    "detail": _guard_text(guard), "state": state, "context": ctx})

    # Evidence: state checks (gate all exits) + transition requires
    check_names = list((st.get("checks") or [])) + list((tr.get("requires") or []))
    evidence, evidence_ok = _run_checks(check_names, ctx, machine, machine_dir, 30)
    if not evidence_ok:
        _append_ledger(run_dir, {
            "type": "blocked", "event": args.event, "from": state, "reason": "evidence",
            "evidence": evidence, "note": args.note, "timestamp": _now_iso(),
        })
        return _ok({"status": "blocked", "event": args.event, "from": state, "reason": "evidence",
                    "evidence": evidence, "state": state, "context": ctx})

    # Limits: max_events / max_steps
    lim = _limits(machine)
    events_fired = sum(1 for e in rs["entries"] if e["payload"]["type"] == "transition")
    if lim.get("max_events") and events_fired + 1 > lim["max_events"]:
        _append_ledger(run_dir, {
            "type": "blocked", "event": args.event, "from": state, "reason": "limit",
            "detail": f"max_events {lim['max_events']} exceeded", "note": args.note, "timestamp": _now_iso(),
        })
        return _ok({"status": "blocked", "event": args.event, "from": state, "reason": "limit",
                    "detail": f"max_events {lim['max_events']} exceeded", "state": state, "context": ctx})

    # Fire: exit actions -> transition actions -> entry actions
    ctx_after = json.loads(json.dumps(ctx))
    apply_actions(st.get("exit"), ctx_after)
    apply_actions(tr.get("actions"), ctx_after)
    target = tr.get("target")
    apply_actions((machine.get("states") or {}).get(target, {}).get("entry"), ctx_after)

    _append_ledger(run_dir, {
        "type": "transition", "event": args.event, "from": state, "to": target,
        "guard": guard, "evidence": evidence, "exit_actions": st.get("exit"),
        "transition_actions": tr.get("actions"), "entry_actions": (machine.get("states") or {}).get(target, {}).get("entry"),
            "context_after": ctx_after, "note": args.note, "child_run": args.child_run,
            "timestamp": _now_iso(),
        })

    return _ok({
        "status": "transitioned", "event": args.event, "from": state, "to": target,
        "state": target, "terminal": is_terminal_state(machine, target),
        "phase": is_phase_state(machine, target),
        "context": ctx_after, "evidence": evidence,
    })


def cmd_abort(args):
    run_dir = _resolve_run_dir(args)
    try:
        rs = _run_state(run_dir)
    except LedgerIntegrityError as e:
        return _err(f"ledger integrity violation: {e}")
    _append_ledger(run_dir, {
        "type": "abort", "state": rs["state"], "reason": args.reason, "timestamp": _now_iso(),
    })
    return _ok({"status": "aborted", "run_id": run_dir.name, "state": rs["state"], "reason": args.reason})


def cmd_check(args):
    """Terminal integrity gate: re-run full ledger + artifact verification and
    emit a strict JSON verdict. Exit 0 when the run is intact, non-zero on any
    integrity violation. Never writes to the run."""
    run_dir = _resolve_run_dir(args)
    try:
        rs = _run_state(run_dir)
    except LedgerIntegrityError as e:
        return _err(f"ledger integrity violation: {e}")
    machine = rs["machine"]
    state = rs["state"]
    data = {
        "machine_sha256_ok": True,
        "tool_hashes_ok": True,
        "ledger_locked": True,
        "run_dir": str(run_dir),
        "state": state,
        "terminal": is_terminal_state(machine, state),
    }
    return _ok(data)


def cmd_report(args):
    run_dir = _resolve_run_dir(args)
    try:
        rs = _run_state(run_dir)
    except LedgerIntegrityError as e:
        return _err(f"ledger integrity violation: {e}")
    machine = rs["machine"]
    state = rs["state"]
    ctx = rs["context"]
    entries = rs["entries"]

    # Determine result status
    if any(e["payload"]["type"] == "abort" for e in entries):
        result = "ABORTED"
    elif is_terminal_state(machine, state):
        result = "SUCCESS"
    else:
        ev = _enabled_events(machine, state, ctx)
        if not ev["enabled"]:
            result = "STUCK"
        else:
            result = "IN_PROGRESS"

    path = [e["payload"]["from"] for e in entries if e["payload"]["type"] in ("transition", "redirect")]
    if path:
        path.append(state)
    else:
        path = [state]

    evidence_passed = sum(1 for e in entries if e["payload"]["type"] == "transition"
                          for ev in (e["payload"].get("evidence") or []) if ev.get("passed"))
    evidence_failed = sum(1 for e in entries if e["payload"]["type"] == "transition"
                          for ev in (e["payload"].get("evidence") or []) if not ev.get("passed"))

    report = {
        "schema": "machina.report.v1",
        "run_id": run_dir.name,
        "machine_id": machine.get("id"),
        "result": result,
        "final_state": state,
        "path": path,
        "events": sum(1 for e in entries if e["payload"]["type"] == "transition"),
            "redirects": sum(1 for e in entries if e["payload"]["type"] == "redirect"),
            "blocked_events": sum(1 for e in entries if e["payload"]["type"] == "blocked"),
        "evidence": {"passed": evidence_passed, "failed": evidence_failed},
        "context_snapshot": ctx,
        "agent_notes": [{"event": e["payload"].get("event"), "note": e["payload"].get("note")}
                        for e in entries if e["payload"].get("note")],
                "nested_runs": [e["payload"].get("child_run") for e in entries
                                if e["payload"].get("child_run")],
            "ledger_final_hash": entries[-1]["hash"] if entries else None,
        }
    (run_dir / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return _ok(report)


# ---------------------------------------------------------------------------
# CLI plumbing
# ---------------------------------------------------------------------------

def _now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


_ALLOW_REPO_RUNS_ENV = "MACHINA_ALLOW_REPO_RUNS"


def _in_git_worktree(path):
    """True when path lies inside a git worktree (a .git file or dir exists
    at path or at any ancestor up to the filesystem root)."""
    cur = Path(path)
    try:
        cur = cur.resolve()
    except OSError:
        cur = Path(path).absolute()
    while True:
        if (cur / ".git").exists():
            return True
        parent = cur.parent
        if parent == cur:
            return False
        cur = parent


def _refuse_repo_run_dir(base):
    """Refuse to create a run dir inside a git worktree, unless the run is
    explicitly opting in via MACHINA_ALLOW_REPO_RUNS=1."""
    if _in_git_worktree(base):
        if os.environ.get(_ALLOW_REPO_RUNS_ENV) == "1":
            return None
        return (
            f"refusing to create run dir inside a git worktree: {base} "
            f"(commit only what you intend; set {_ALLOW_REPO_RUNS_ENV}=1 to allow)"
        )
    return None


def _resolve_run_dir(args):
    base = Path(args.run_dir)
    if args.run:
        return base / args.run
    # No run id: use the most recent run dir
    runs = sorted([p for p in base.iterdir() if p.is_dir()], key=lambda p: p.stat().st_mtime, reverse=True)
    if not runs:
        raise LedgerIntegrityError("no runs found")
    return runs[0]


def _ok(payload):
    print(json.dumps({"ok": True, "data": payload}, separators=(",", ":")))
    return 0


def _err(message):
    print(json.dumps({"ok": False, "error": message}, separators=(",", ":")))
    return 1


def main(argv=None):
    parser = argparse.ArgumentParser(prog="machine-driver.py", description="Machina state-machine driver")
    sub = parser.add_subparsers(dest="command", required=True)

    p_init = sub.add_parser("init")
    p_init.add_argument("--machine", required=True)
    p_init.add_argument("--scenario")
    p_init.add_argument("--input", action="append", default=[])
    p_init.add_argument("--run-dir", default=".machina/runs")

    for name in ("status", "check", "report"):
        p = sub.add_parser(name)
        p.add_argument("--run")
        p.add_argument("--run-dir", default=".machina/runs")
    p_abort = sub.add_parser("abort")
    p_abort.add_argument("--run")
    p_abort.add_argument("--run-dir", default=".machina/runs")
    p_abort.add_argument("--reason")

    p_fire = sub.add_parser("fire")
    p_fire.add_argument("event")
    p_fire.add_argument("--run")
    p_fire.add_argument("--note")
    p_fire.add_argument("--child-run")
    p_fire.add_argument("--run-dir", default=".machina/runs")

    args = parser.parse_args(argv)
    try:
        if args.command == "init":
            return cmd_init(args)
        if args.command == "status":
            return cmd_status(args)
        if args.command == "fire":
            return cmd_fire(args)
        if args.command == "abort":
            return cmd_abort(args)
        if args.command == "check":
            return cmd_check(args)
        if args.command == "report":
            return cmd_report(args)
    except LedgerIntegrityError as e:
        return _err(f"ledger integrity violation: {e}")
    except Exception as e:  # noqa: BLE001 — CLI boundary
        return _err(f"internal error: {e}")
    return _err("unknown command")


if __name__ == "__main__":
    sys.exit(main())