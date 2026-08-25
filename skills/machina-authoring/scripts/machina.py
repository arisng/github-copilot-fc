#!/usr/bin/env python3
"""Machina machine tooling — deterministic authoring engine for Machina machine JSON.

Faithful Python port of the deterministic routines in state-machine-simulator.html:
validation, the 17-check compliance scorer, gap analysis, autofill patches,
scenario generation, cycle detection, and coverage-block building.

Usage:
  python3 machina.py <command> <machine.json> [options]

Commands:
  validate   Structural validation errors (hard/blocking only)
  score      Full compliance report (JSON) — add --text for human-readable
  gaps       Ordered auto-fillable patch list (preview, no writes)
  apply      Apply all auto patches; -o OUT writes elsewhere, default overwrites input
  scenarios  Generated scenario paths (DFS to terminal, deduped)
  cycles     Cycle analysis findings
  coverage   Deterministic coverage metadata block (what "Generate missing" would embed)

Options:
  --spec V   Score against a specific spec version instead of the detected target
"""

import json
import re
import sys
from datetime import datetime, timezone

SPEC_VERSIONS = ["2.0.0", "1.0.0"]  # newest first
LATEST_SPEC_VERSION = SPEC_VERSIONS[0]
MAX_DEPTH = 24
MAX_SCEN = 500
MAX_VISITS = 2


# ── helpers (ported) ────────────────────────────────────────────

def spec_rank(v):
    try:
        return SPEC_VERSIONS.index(v)
    except ValueError:
        return 0


def detect_spec_version(m):
    sv = m.get("spec_version") if isinstance(m, dict) else None
    if sv in SPEC_VERSIONS:
        return {"version": sv, "declared": True, "assumed": False}
    return {"version": LATEST_SPEC_VERSION, "declared": bool(sv), "assumed": True}


def humanize(key):
    return re.sub(r"[_-]+", " ", str(key)).strip()


def is_upper_snake(s):
    return bool(re.fullmatch(r"[A-Z][A-Z0-9_]*", s))


def is_kebab(s):
    return bool(re.fullmatch(r"[a-z][a-z0-9]*(-[a-z0-9]+)*", s))


def get_path(obj, key):
    cur = obj
    for k in key.split("."):
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur


def set_path(obj, key, val):
    ks = key.split(".")
    for k in ks[:-1]:
        obj = obj.setdefault(k, {})
    obj[ks[-1]] = val


def transitions(m):
    """Yield (state_key, event, transition) for every transition."""
    for sk, st in (m.get("states") or {}).items():
        for evt, tr in ((st or {}).get("on") or {}).items():
            yield sk, evt, tr


def reachable_states(m):
    states = m.get("states") or {}
    entries, seen = [], set()
    for sc in m.get("scenarios") or []:
        ini = sc.get("initial")
        if ini and ini in states and ini not in seen:
            entries.append(ini)
            seen.add(ini)
    if m.get("initial") in states and m.get("initial") not in seen:
        entries.append(m["initial"])
    visited = set(entries)
    q = list(entries)
    while q:
        s = q.pop(0)
        for _sk, _evt, tr in transitions_of(m, s):
            t = (tr or {}).get("target")
            if t and t in states and t not in visited:
                visited.add(t)
                q.append(t)
    return visited


def transitions_of(m, state_key):
    st = (m.get("states") or {}).get(state_key) or {}
    return [(_sk := state_key, evt, tr) for evt, tr in ((st.get("on") or {}).items())]


def is_terminal_state(m, s):
    st = (m.get("states") or {}).get(s)
    return bool(st and (st.get("type") == "final" or not (st.get("on") or {})))


def eval_guard(g, ctx):
    """Declarative guard evaluation (compare). Unknown ops pass."""
    if not g or g.get("type") != "compare":
        return True
    a = get_path(ctx or {}, g.get("key", ""))
    b = g.get("value")
    if isinstance(b, str):
        ctxd = ctx or {}
        if b in ctxd:
            b = ctxd[b]
        elif re.fullmatch(r"-?\d+(\.\d+)?", b):
            b = float(b) if "." in b else int(b)
    op = g.get("op")
    try:
        return {
            "eq": a == b, "neq": a != b, "lt": a < b,
            "lte": a <= b, "gt": a > b, "gte": a >= b,
        }.get(op, True)
    except TypeError:
        return True


# ── validation (ported from validate()) ─────────────────────────

def validate(obj):
    errs = []
    if not isinstance(obj, dict):
        return ["Root must be a JSON object."]
    if not isinstance(obj.get("id"), str):
        errs.append('"id" must be a string.')
    cov = obj.get("coverage")
    if cov is not None and (not isinstance(cov, dict)):
        errs.append('"coverage" must be an object.')
    states = obj.get("states")
    if not isinstance(states, dict) or not states:
        errs.append('"states" must be a non-empty object.')
    else:
        ini = obj.get("initial")
        if ini is not None and ini not in states:
            errs.append(f'"initial" ("{ini}") is not a state key.')
        for key, st in states.items():
            if not isinstance(st, dict):
                errs.append(f'State "{key}" must be an object.')
                continue
            for evt, tr in (st.get("on") or {}).items():
                if not isinstance(tr, dict) or not isinstance(tr.get("target"), str):
                    errs.append(f'Transition "{key} → {evt}" needs a string "target".')
                elif tr.get("target") not in states:
                    errs.append(f'Transition "{key} → {evt}" targets unknown state "{tr.get("target")}".')
    for sc in obj.get("scenarios") or []:
        if not isinstance(sc, dict) or not isinstance(sc.get("id"), str):
            errs.append('Every scenario needs a string "id".')
        elif sc.get("initial") is not None and sc.get("initial") not in (obj.get("states") or {}):
            errs.append(f'Scenario "{sc.get("id")}" initial "{sc.get("initial")}" is not a state key.')
    return errs


# ── cycle analysis (ported from detectCycles()) ──────────────────

def detect_cycles(m):
    states = m.get("states") or {}
    finals = {s for s, st in states.items() if (st or {}).get("type") == "final"}
    cycles, seen_sig, visited = [], set(), set()

    def walk(start):
        stack, in_stack = [], set()

        def dfs(node, depth):
            if depth > MAX_DEPTH:
                sig = "::depth"
                if sig not in seen_sig:
                    seen_sig.add(sig)
                    cycles.append({
                        "type": "loop",
                        "cycle": stack + [node],
                        "severity": "CRITICAL",
                        "recommendation": "Add a max-iteration guard or exit condition.",
                    })
                return
            visited.add(node)
            stack.append(node)
            in_stack.add(node)
            st = states.get(node) or {}
            for tr in (st.get("on") or {}).values():
                t = (tr or {}).get("target")
                if not t or t not in states:
                    continue
                if t in in_stack:
                    idx = stack.index(t)
                    path = stack[idx:] + [t]
                    sig = ">".join(sorted(path))
                    if sig not in seen_sig:
                        seen_sig.add(sig)
                        has_final = any(s in finals for s in path)
                        cycles.append({
                            "type": "cycle",
                            "cycle": path,
                            "severity": "MEDIUM" if has_final else "HIGH",
                            "recommendation": (
                                "Valid cycle — ensure it has a clear exit condition."
                                if has_final else
                                "Potential infinite loop — add an exit event or an iteration guard."
                            ),
                        })
                else:
                    dfs(t, depth + 1)
            in_stack.discard(node)
            stack.pop()

        dfs(start, 0)

    walk(m.get("initial"))
    for s in states:
        if s not in visited:
            walk(s)
    return cycles


# ── compliance scoring (17 checks, total weight = 100) ───────────

def cycle_counter_key(m):
    for k in (m.get("context") or {}):
        if re.search(r"retry|attempt", k, re.I):
            return k
    return None


def _pass(detail=True):
    return {"pass": True, "detail": detail}


def _fail(detail):
    return {"pass": False, "detail": detail}


def _check_targets_resolve(m):
    states = m.get("states") or {}
    for _s, _e, tr in transitions(m):
        if not isinstance(tr, dict) or not tr.get("target") or tr.get("target") not in states:
            return _fail("At least one transition targets an unknown state")
    return _pass(True)


def _check_descriptions(m):
    missing = [s for s, st in (m.get("states") or {}).items()
               if not ((st or {}).get("description"))]
    return _fail(f"{len(missing)} state(s) missing: " + ", ".join(missing)) if missing else _pass(True)


def _check_finals_typed(m):
    untyped = [s for s, st in (m.get("states") or {}).items()
               if isinstance(st, dict) and not st.get("type") and not (st.get("on") or {})]
    return _fail(f"{len(untyped)} implicit terminal(s): " + ", ".join(untyped)) if untyped else _pass(True)


def _check_actions_used(m):
    used = False
    for st in (m.get("states") or {}).values():
        if not isinstance(st, dict):
            continue
        if st.get("entry") or st.get("exit"):
            used = True
        for tr in (st.get("on") or {}).values():
            if isinstance(tr, dict) and (tr.get("guard") or tr.get("actions")):
                used = True
    return _pass(True) if used else _fail("No guards, actions, or entry/exit hooks defined")


def _check_event_naming(m):
    bad = [evt for _s, evt, _tr in transitions(m) if not is_upper_snake(evt)]
    return _fail("Non-conforming event(s): " + ", ".join(bad)) if bad else _pass(True)


def _check_state_naming(m):
    bad = [s for s in (m.get("states") or {}) if not is_kebab(s)]
    return _fail("Non-conforming key(s): " + ", ".join(bad)) if bad else _pass(True)


def _check_all_reachable(m):
    reach = reachable_states(m)
    unreach = [s for s in (m.get("states") or {}) if s not in reach]
    return _fail("Unreachable: " + ", ".join(unreach)) if unreach else _pass(True)


def _check_terminal_reachable(m):
    reach = reachable_states(m)
    if any(is_terminal_state(m, s) for s in reach):
        return _pass(True)
    return _fail("No reachable terminal state")


def _check_cycle_guards(m):
    if not m.get("states"):
        return _pass(True)
    cycles = [c for c in detect_cycles(m) if c["type"] == "cycle"]
    if not cycles:
        return _pass(True)
    guards = ((m.get("cycle_prevention") or {}).get("guards")) or []
    if guards:
        return _pass(True)
    return _fail(f"{len(cycles)} unguarded cycle(s) detected")


COMPLIANCE_CHECKS = [
    {"id": "id-present", "category": "Identity & metadata", "since": "1.0.0", "weight": 5,
     "severity": "blocking", "autofill": "review",
     "remediation": 'Add a string "id".',
     "check": lambda m: _pass(isinstance(m.get("id"), str) and m.get("id", "").strip() != "")},
    {"id": "name-present", "category": "Identity & metadata", "since": "1.0.0", "weight": 5,
     "severity": "warn", "autofill": "review",
     "remediation": 'Add a human-readable "name" (suggested from id).',
     "check": lambda m: _pass(isinstance(m.get("name"), str) and m.get("name", "").strip() != "")},
    {"id": "version-present", "category": "Identity & metadata", "since": "1.0.0", "weight": 5,
     "severity": "warn", "autofill": "auto",
     "remediation": 'Add a machine "version" string (distinct from "spec_version").',
     "check": lambda m: _pass(isinstance(m.get("version"), str))},
    {"id": "spec-version", "category": "Identity & metadata", "since": "2.0.0", "weight": 0,
     "severity": "info", "autofill": "auto",
     "remediation": 'Declare "spec_version" to pin the target schema spec (distinct from machine "version").',
     "check": lambda m: _pass(detect_spec_version(m)["declared"])},
    {"id": "states-present", "category": "Structure & integrity", "since": "1.0.0", "weight": 10,
     "severity": "blocking", "autofill": "review",
     "remediation": 'Provide a non-empty "states" object.',
     "check": lambda m: _pass(isinstance(m.get("states"), dict) and len(m["states"]) > 0)},
    {"id": "initial-resolves", "category": "Structure & integrity", "since": "1.0.0", "weight": 10,
     "severity": "blocking", "autofill": "review",
     "remediation": 'Set "initial" to an existing state key.',
     "check": lambda m: _pass(bool(m.get("initial")) and m.get("initial") in (m.get("states") or {}))},
    {"id": "targets-resolve", "category": "Structure & integrity", "since": "1.0.0", "weight": 5,
     "severity": "blocking", "autofill": "review",
     "remediation": 'Every transition "target" must reference an existing state.',
     "check": _check_targets_resolve},
    {"id": "state-descriptions", "category": "State quality", "since": "1.0.0", "weight": 8,
     "severity": "warn", "autofill": "auto",
     "remediation": 'Give every state a "description".',
     "check": _check_descriptions},
    {"id": "finals-typed", "category": "State quality", "since": "1.0.0", "weight": 6,
     "severity": "warn", "autofill": "auto",
     "remediation": 'Mark states with no outgoing transitions as "final".',
     "check": _check_finals_typed},
    {"id": "actions-used", "category": "State quality", "since": "1.0.0", "weight": 6,
     "severity": "warn", "autofill": "review",
     "remediation": "Exercise at least one declarative guard, action, or entry/exit hook.",
     "check": _check_actions_used},
    {"id": "event-naming", "category": "Conventions", "since": "1.0.0", "weight": 5,
     "severity": "warn", "autofill": "review",
     "remediation": "Event names should be UPPER_SNAKE.",
     "check": _check_event_naming},
    {"id": "state-naming", "category": "Conventions", "since": "1.0.0", "weight": 5,
     "severity": "warn", "autofill": "review",
     "remediation": "State keys should be kebab-case.",
     "check": _check_state_naming},
    {"id": "all-reachable", "category": "Topology & reachability", "since": "1.0.0", "weight": 8,
     "severity": "warn", "autofill": "review",
     "remediation": "Every state should be reachable from an entry point.",
     "check": _check_all_reachable},
    {"id": "terminal-reachable", "category": "Topology & reachability", "since": "1.0.0", "weight": 6,
     "severity": "warn", "autofill": "review",
     "remediation": "At least one terminal state should be reachable.",
     "check": _check_terminal_reachable},
    {"id": "entry-points", "category": "Topology & reachability", "since": "2.0.0", "weight": 6,
     "severity": "warn", "autofill": "auto",
     "remediation": 'Define "scenarios" entry points (UI · API).',
     "check": lambda m: _pass(isinstance(m.get("scenarios"), list) and len(m["scenarios"]) > 0)},
    {"id": "cycle-guards", "category": "Safety", "since": "2.0.0", "weight": 5,
     "severity": "warn", "autofill": "auto",
     "remediation": 'Guard detected cycles with "cycle_prevention".',
     "check": _check_cycle_guards},
    {"id": "coverage-present", "category": "Coverage metadata", "since": "2.0.0", "weight": 5,
     "severity": "info", "autofill": "auto",
     "remediation": 'Embed a "coverage" metadata block.',
     "check": lambda m: _pass(isinstance(m.get("coverage"), dict))},
]


def grade_for(score):
    if score >= 90:
        return "Excellent"
    if score >= 80:
        return "Good"
    if score >= 70:
        return "Fair"
    return "Needs work"


def run_compliance(m, spec_version=None):
    det = detect_spec_version(m)
    target = spec_version or det["version"]
    # NOTE: the simulator source uses `specRank(c.since) <= specRank(target)` with
    # newest-first ranks, which INVERTS inclusion (v1 checks dropped from v2 targets,
    # v2 checks applied to v1 targets). We implement the documented §14 semantics:
    # a check applies when its `since` is not NEWER than the target, i.e. the
    # check's age >= target's age. At v2.0.0 all 17 checks run (weight = 100).
    checks = [c for c in COMPLIANCE_CHECKS if spec_rank(c["since"]) >= spec_rank(target)]
    findings, by_cat = [], {}
    earned = total = 0
    for c in checks:
        r = c["check"](m)
        total += c["weight"]
        if r["pass"]:
            earned += c["weight"]
        cat = by_cat.setdefault(c["category"], {"earned": 0, "total": 0})
        cat["total"] += c["weight"]
        if r["pass"]:
            cat["earned"] += c["weight"]
        autofill = "review" if (c["id"] == "cycle-guards" and not cycle_counter_key(m)) else c["autofill"]
        findings.append({
            "id": c["id"], "category": c["category"], "severity": c["severity"],
            "weight": c["weight"], "pass": r["pass"], "detail": r["detail"],
            "remediation": c["remediation"], "autofill": autofill,
        })
    score = round((earned / total) * 1000) / 10 if total else 100
    return {
        "score": score, "grade": grade_for(score), "specVersion": target,
        "declared": det["declared"], "byCategory": by_cat, "findings": findings,
        "blocking": [f for f in findings if not f["pass"] and f["severity"] == "blocking"],
    }


# ── deterministic builders / autofill (ported) ───────────────────

def build_recommendations(m):
    recs = []
    if not m.get("states"):
        return recs
    reach = reachable_states(m)
    for s in m.get("states") or {}:
        if s not in reach:
            recs.append(f'State "{s}" is unreachable from any entry point')
    cycles = [c for c in detect_cycles(m) if c["type"] == "cycle"]
    if cycles and not (((m.get("cycle_prevention") or {}).get("guards")) or []):
        recs.append(f"Guard {len(cycles)} detected cycle(s) with cycle_prevention")
    if not (isinstance(m.get("name"), str) and m.get("name", "").strip()):
        recs.append('Add a human-readable "name"')
    return recs


def build_coverage_block(m):
    states = list((m.get("states") or {}).keys())
    reach = reachable_states(m)
    state_cov, edge_cov = {}, {}
    n_trans = n_finals = 0
    incoming = {s: 0 for s in states}
    for sk, _evt, tr in transitions(m):
        t = (tr or {}).get("target")
        if t in incoming:
            incoming[t] += 1
    for s in states:
        st = m["states"][s] or {}
        outs = list((st.get("on") or {}).keys())
        if is_terminal_state(m, s):
            n_finals += 1
        state_cov[s] = {
            "visited": s in reach,
            "incoming": incoming[s],
            "outgoing": len(outs),
        }
        for evt in outs:
            tr = st["on"][evt]
            n_trans += 1
            edge_cov[f"{s}:{evt}"] = {
                "from": s, "to": tr.get("target"),
                "covered": s in reach and tr.get("target") in reach,
            }
    covered = sum(1 for e in edge_cov.values() if e["covered"])
    uncovered_paths = [f"{e['from']} → {e['to']}" for e in edge_cov.values() if not e["covered"]]
    return {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "version": LATEST_SPEC_VERSION,
        "metrics": {
            "total_states": len(states),
            "final_states": n_finals,
            "total_transitions": n_trans,
            "coverage_percentage": round((covered / n_trans) * 1000) / 10 if n_trans else 100,
        },
        "state_coverage": state_cov,
        "edge_coverage": edge_cov,
        "uncovered_paths": uncovered_paths,
        "recommendations": build_recommendations(m),
    }


def build_cycle_prevention(m):
    if not m.get("states"):
        return None
    cycles = [c for c in detect_cycles(m) if c["type"] == "cycle"]
    if not cycles:
        return None
    key = cycle_counter_key(m)
    if not key:
        return None
    terminal = next((s for s, st in (m.get("states") or {}).items()
                     if isinstance(st, dict) and st.get("type") == "final"), None)
    guards, seen_evt = [], set()
    for c in cycles:
        path = c["cycle"]
        if len(path) < 2:
            continue
        last, prev = path[-1], path[-2]
        st = (m.get("states") or {}).get(prev) or {}
        for evt, tr in (st.get("on") or {}).items():
            if isinstance(tr, dict) and tr.get("target") == last and evt not in seen_evt:
                seen_evt.add(evt)
                g = {"event": evt, "guard": {"type": "compare", "key": key, "op": "lt", "value": 3}}
                if terminal:
                    g["else_target"] = terminal
                guards.append(g)
    if not guards:
        return None
    return {"max_retry_limit": 3, "timeout_seconds": 300, "guards": guards}


def derive_scenarios(m):
    if isinstance(m.get("scenarios"), list) and m["scenarios"]:
        return m["scenarios"]
    if m.get("initial") in (m.get("states") or {}):
        return [{"id": "default", "label": "Default", "initial": m["initial"], "interface": "API"}]
    return []


def add_descriptions(m):
    for s, st in (m.get("states") or {}).items():
        if isinstance(st, dict) and not st.get("description"):
            st["description"] = "State: " + humanize(s)
            st["generated"] = True


def mark_finals(m):
    for st in (m.get("states") or {}).values():
        if isinstance(st, dict) and not st.get("type") and not (st.get("on") or {}):
            st["type"] = "final"
            st["generated"] = True


def auto_patch_items(m, target_version=None):
    det = detect_spec_version(m)
    target = target_version or det["version"]
    res = run_compliance(m, target)

    def need(cid):
        return any(f["id"] == cid and not f["pass"] for f in res["findings"])

    items = []
    if not det["declared"] or det["version"] != target:
        items.append({"id": "spec-version", "label": f'Set spec_version "{target}"',
                      "detail": "pin the target schema spec version"})
    if need("version-present"):
        items.append({"id": "version", "label": 'Add version "1.0.0"',
                      "detail": "machine version (spec target set separately)"})
    if need("entry-points"):
        items.append({"id": "scenarios", "label": "Derive scenarios from entry points",
                      "detail": "one API entry point from initial"})
    if need("coverage-present"):
        items.append({"id": "coverage", "label": "Compute coverage metadata",
                      "detail": "metrics + state/edge coverage"})
    if need("cycle-guards") and cycle_counter_key(m):
        items.append({"id": "cycle-guards", "label": "Add cycle_prevention guards",
                      "detail": "guards for detected cycles"})
    if need("state-descriptions"):
        items.append({"id": "descriptions", "label": "Add placeholder descriptions",
                      "detail": "humanized from state keys (marked generated)"})
    if need("finals-typed"):
        items.append({"id": "finals-typed", "label": "Mark implicit terminals as final",
                      "detail": "states with no outgoing transitions"})
    return items


APPLY_FNS = {}


def apply_patches(m, item_ids, target_version=None):
    """Apply selected auto patches deterministically (order matters — do not reorder)."""
    changed = []
    for item in auto_patch_items(m, target_version):
        if item["id"] not in item_ids:
            continue
        iid = item["id"]
        if iid == "spec-version":
            det = detect_spec_version(m)
            m["spec_version"] = target_version or det["version"]
        elif iid == "version":
            m["version"] = "1.0.0"
        elif iid == "scenarios":
            m["scenarios"] = derive_scenarios(m)
        elif iid == "coverage":
            m["coverage"] = build_coverage_block(m)
        elif iid == "cycle-guards":
            cp = build_cycle_prevention(m)
            if cp:
                m["cycle_prevention"] = cp
            else:
                continue
        elif iid == "descriptions":
            add_descriptions(m)
        elif iid == "finals-typed":
            mark_finals(m)
        changed.append(iid)
    return changed


# ── scenario generation (ported from generateScenarios()) ────────

def get_entry_points(m):
    states = m.get("states") or {}
    entries, seen = [], set()
    for sc in m.get("scenarios") or []:
        ini = sc.get("initial")
        if ini and ini in states and ini not in seen:
            entries.append({
                "state": ini,
                "interface": "UI" if sc.get("interface") == "UI" else "API",
                "label": sc.get("label") or sc.get("id"),
                "context": sc.get("context"),
            })
            seen.add(ini)
    if m.get("initial") in states and m.get("initial") not in seen:
        entries.append({"state": m["initial"], "interface": "API", "label": "default", "context": None})
    return entries


def generate_scenarios(m):
    states = m.get("states") or {}

    def is_end(s):
        st = states.get(s) or {}
        return bool(st) and (st.get("type") == "final" or not (st.get("on") or {}))

    raw = []

    def dfs(state, spath, epath, depth, visits):
        if len(raw) >= MAX_SCEN or depth > MAX_DEPTH:
            return
        st = states.get(state) or {}
        if is_end(state):
            raw.append({"states": list(spath), "events": list(epath)})
        for evt, tr in (st.get("on") or {}).items():
            target = (tr or {}).get("target")
            if not target or target not in states:
                continue
            v = visits.get(target, 0)
            if v >= MAX_VISITS:
                continue
            visits[target] = v + 1
            spath.append(target)
            epath.append(evt)
            dfs(target, spath, epath, depth + 1, visits)
            spath.pop()
            epath.pop()
            visits[target] = v

    entries = get_entry_points(m)
    for e in entries:
        visits = {e["state"]: 1}
        dfs(e["state"], [e["state"]], [], 0, visits)

    seen, scenarios = set(), []
    for p in raw:
        key = "\x00".join(p["states"])
        if key in seen:
            continue
        seen.add(key)
        entry = next((e for e in entries if e["state"] == p["states"][0]), None)
        scenarios.append({
            "id": f"gen-{len(scenarios)}",
            "initial": p["states"][0],
            "context": entry["context"] if entry else None,
            "startLabel": entry["label"] if entry else p["states"][0],
            "start": p["states"][0],
            "startInterface": entry["interface"] if entry else "API",
            "end": p["states"][-1],
            "states": p["states"],
            "events": p["events"],
            "steps": len(p["states"]),
        })

    base_count, base_seen = {}, {}
    for sc in scenarios:
        b = f"{sc['startLabel']} → {sc['end']}"
        base_count[b] = base_count.get(b, 0) + 1
    for sc in scenarios:
        b = f"{sc['startLabel']} → {sc['end']}"
        if base_count[b] > 1:
            base_seen[b] = base_seen.get(b, 0) + 1
            sc["label"] = f"{b} ({base_seen[b]})"
        else:
            sc["label"] = b
    return scenarios


def scenario_coverage(m, scenarios):
    total = sum(len(((st or {}).get("on") or {}))
                for st in (m.get("states") or {}).values())
    covered = set()
    for sc in scenarios:
        ss = sc["states"]
        for i in range(len(ss) - 1):
            covered.add(f"{ss[i]}\x00{ss[i+1]}")
    pct = round((len(covered) / total) * 1000) / 10 if total else 0
    return {"total": total, "covered": len(covered), "pct": pct}


# ── CLI ──────────────────────────────────────────────────────────

def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd, path = argv[1], argv[2]
    m = load(path)

    if cmd == "validate":
        errs = validate(m)
        if errs:
            print("\n".join(errs))
            return 1
        print("OK — structurally valid.")
        return 0

    if cmd == "score":
        spec = None
        if "--spec" in argv:
            spec = argv[argv.index("--spec") + 1]
        res = run_compliance(m, spec)
        if "--text" in argv:
            print(f"Score: {res['score']}  Grade: {res['grade']}  "
                  f"(spec v{res['specVersion']}, {'declared' if res['declared'] else 'assumed latest'})")
            for cat, v in res["byCategory"].items():
                print(f"  {cat}: {v['earned']}/{v['total']}")
            fails = [f for f in res["findings"] if not f["pass"]]
            if fails:
                print("Gaps:")
                for f_ in sorted(fails, key=lambda x: ["blocking", "warn", "info"].index(x["severity"])):
                    print(f"  [{f_['severity']:8}] {f_['id']} ({f_['weight']}wt, {f_['autofill']}): {f_['remediation']}")
            else:
                print("No gaps.")
        else:
            print(json.dumps(res, indent=2))
        return 0

    if cmd == "gaps":
        print(json.dumps(auto_patch_items(m), indent=2))
        return 0

    if cmd == "apply":
        ids = [i for i in argv[3:] if not i.startswith("-")]
        out_idx = argv.index("-o") if "-o" in argv else None
        out_path = argv[out_idx + 1] if out_idx is not None else path
        ids = [i for i in ids if i != (argv[out_idx + 1] if out_idx is not None else None)]
        changed = apply_patches(m, ids)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(m, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print("Applied: " + (", ".join(changed) if changed else "(nothing)") + f" → {out_path}")
        return 0

    if cmd == "scenarios":
        scen = generate_scenarios(m)
        cov = scenario_coverage(m, scen)
        print(json.dumps({"coverage": cov, "count": len(scen), "scenarios": scen}, indent=2))
        return 0

    if cmd == "cycles":
        print(json.dumps(detect_cycles(m), indent=2))
        return 0

    if cmd == "coverage":
        print(json.dumps(build_coverage_block(m), indent=2))
        return 0

    print(f"Unknown command: {cmd}")
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
