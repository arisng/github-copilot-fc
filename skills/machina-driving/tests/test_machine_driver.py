#!/usr/bin/env python3
"""Unit tests for machine-driver.py (the v3 Machina execution driver).

Run:  python -m unittest discover -s skills/machina-driving/tests -v
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

_DRIVER = Path(__file__).resolve().parents[1] / "scripts" / "machine-driver.py"
_spec = importlib.util.spec_from_file_location("machine_driver", _DRIVER)
md = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(md)


def write_machine(dirpath, name, machine):
    p = Path(dirpath) / name
    p.write_text(json.dumps(machine, indent=2), encoding="utf-8")
    return p


def docs_machine():
    return {
        "id": "docs-authoring",
        "name": "Docs Authoring",
        "version": "1.0.0",
        "spec_version": "3.0.0",
        "initial": "reviewing-draft",
        "context": {"draft_path": "", "review": {"broken_links": 0}},
        "tools": {
            "draft-file-exists": {
                "cmd": "python3 scripts/check_file.py {ctx.draft_path}",
                "expect_exit": 0,
                "timeout_seconds": 30,
            },
            "link-check": {
                "cmd": ["python3", "scripts/check_links.py", "{ctx.draft_path}"],
                "expect_exit": 0,
                "timeout_seconds": 30,
                "output": {"broken": "review.broken_links"},
            },
        },
        "limits": {"max_events": 20},
        "scenarios": [
            {
                "id": "default",
                "label": "Default",
                "initial": "reviewing-draft",
                "interface": "API",
                "inputs": {"draft_path": {"required": True, "type": "string"}},
            }
        ],
        "states": {
            "reviewing-draft": {
                "description": "Produce the draft file.",
                "checks": ["draft-file-exists"],
                "on": {"DRAFT_REVIEWED": {"target": "publishing", "requires": ["link-check"]}},
            },
            "publishing": {
                "description": "Publish.",
                "on": {"PUBLISHED": {"target": "published"}},
            },
            "published": {"type": "final", "description": "Done."},
        },
    }


def guard_machine():
    return {
        "id": "guard-test",
        "name": "Guard Test",
        "version": "1.0.0",
        "spec_version": "3.0.0",
        "initial": "working",
        "context": {"attempts": 0},
        "scenarios": [{"id": "default", "label": "Default", "initial": "working", "interface": "API"}],
        "states": {
            "working": {
                "description": "Working.",
                "on": {
                    "RETRY": {
                        "target": "working",
                        "guard": {"type": "compare", "key": "attempts", "op": "lt", "value": 2},
                        "actions": [{"type": "increment", "key": "attempts"}],
                        "else_target": "gave-up",
                    },
                    "DONE": {"target": "done"},
                },
            },
            "gave-up": {"type": "final", "description": "Gave up."},
            "done": {"type": "final", "description": "Done."},
        },
    }


def phase_parent_machine():
    return {
        "id": "parent-task",
        "name": "Parent Task",
        "version": "1.0.0",
        "spec_version": "3.0.0",
        "initial": "starting",
        "context": {"child_result": ""},
        "scenarios": [{"id": "default", "label": "Default", "initial": "starting", "interface": "API"}],
        "states": {
            "starting": {"description": "Start.", "on": {"BEGIN_PHASE": {"target": "child-phase"}}},
            "child-phase": {
                "type": "phase",
                "description": "Delegate to child.",
                "on": {"PHASE_DONE": {"target": "parent-done"}},
            },
            "parent-done": {"type": "final", "description": "Done."},
        },
    }


def phase_child_machine():
    return {
        "id": "child-task",
        "name": "Child Task",
        "version": "1.0.0",
        "spec_version": "3.0.0",
        "initial": "todo",
        "context": {"result": ""},
        "scenarios": [{"id": "default", "label": "Default", "initial": "todo", "interface": "API"}],
        "states": {
            "todo": {"description": "Do work.", "on": {"CHILD_DONE": {"target": "child-done"}}},
            "child-done": {"type": "final", "description": "Done."},
        },
    }


class DriverTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="machina-driver-test-")
        self.run_dir = Path(self.tmp) / "runs"
        self.run_dir.mkdir()
        # checker scripts
        scripts = Path(self.tmp) / "scripts"
        scripts.mkdir()
        (scripts / "check_file.py").write_text(
            "import sys\nfrom pathlib import Path\n"
            "p = Path(sys.argv[1])\n"
            "print('ok' if p.exists() else 'missing', file=sys.stderr)\n"
            "sys.exit(0 if p.exists() else 1)\n",
            encoding="utf-8",
        )
        (scripts / "check_links.py").write_text(
            "import json, sys\n"
            "from pathlib import Path\n"
            "p = Path(sys.argv[1])\n"
            "print(json.dumps({'valid': p.exists(), 'broken': 0 if p.exists() else 1}))\n"
            "sys.exit(0 if p.exists() else 1)\n",
            encoding="utf-8",
        )

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _init(self, machine_path, **kwargs):
        args = ["init", "--machine", str(machine_path), "--run-dir", str(self.run_dir)]
        for k, v in kwargs.items():
            args.append(f"--{k}")
            args.append(str(v))
        return md.main(args)

    def _fire(self, run_id, event, **kwargs):
        args = ["fire", event, "--run", run_id, "--run-dir", str(self.run_dir)]
        for k, v in kwargs.items():
            flag = k.replace("_", "-")
            args.append(f"--{flag}")
            args.append(str(v))
        return md.main(args)

    def _status(self, run_id):
        return md.main(["status", "--run", run_id, "--run-dir", str(self.run_dir)])

    def _report(self, run_id):
        return md.main(["report", "--run", run_id, "--run-dir", str(self.run_dir)])

    def _abort(self, run_id, reason=None):
        args = ["abort", "--run", run_id, "--run-dir", str(self.run_dir)]
        if reason:
            args += ["--reason", reason]
        return md.main(args)

    def _capture(self, fn):
        """Run a command function, capturing stdout JSON."""
        import io
        from contextlib import redirect_stdout
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = fn()
        return rc, json.loads(buf.getvalue())


class TestInit(DriverTestBase):
    def test_init_requires_input(self):
        mp = write_machine(self.tmp, "docs.machine.json", docs_machine())
        rc, out = self._capture(lambda: self._init(mp))
        self.assertEqual(rc, 1)
        self.assertFalse(out["ok"])
        self.assertIn("draft_path", out["error"])

    def test_init_valid(self):
        mp = write_machine(self.tmp, "docs.machine.json", docs_machine())
        rc, out = self._capture(lambda: self._init(mp, input="draft_path=foo.md"))
        self.assertEqual(rc, 0)
        self.assertTrue(out["ok"])
        d = out["data"]
        self.assertEqual(d["state"], "reviewing-draft")
        self.assertEqual(d["context"]["draft_path"], "foo.md")
        self.assertTrue(d["run_id"])

    def test_init_rejects_unknown_scenario(self):
        mp = write_machine(self.tmp, "docs.machine.json", docs_machine())
        rc, out = self._capture(lambda: self._init(mp, scenario="nope", input="draft_path=foo.md"))
        self.assertEqual(rc, 1)
        self.assertIn("unknown scenario", out["error"])


class TestFireEvidence(DriverTestBase):
    def test_fire_blocked_when_evidence_fails(self):
        mp = write_machine(self.tmp, "docs.machine.json", docs_machine())
        rc, out = self._capture(lambda: self._init(mp, input="draft_path=missing.md"))
        run_id = out["data"]["run_id"]
        rc, out = self._capture(lambda: self._fire(run_id, "DRAFT_REVIEWED"))
        self.assertEqual(rc, 0)
        self.assertEqual(out["data"]["status"], "blocked")
        self.assertEqual(out["data"]["reason"], "evidence")
        self.assertFalse(out["data"]["evidence"][0]["passed"])

    def test_fire_succeeds_when_evidence_passes(self):
        mp = write_machine(self.tmp, "docs.machine.json", docs_machine())
        draft = Path(self.tmp) / "draft.md"
        draft.write_text("# Draft", encoding="utf-8")
        rc, out = self._capture(lambda: self._init(mp, input=f"draft_path={draft}"))
        run_id = out["data"]["run_id"]
        rc, out = self._capture(lambda: self._fire(run_id, "DRAFT_REVIEWED"))
        self.assertEqual(rc, 0)
        self.assertEqual(out["data"]["status"], "transitioned")
        self.assertEqual(out["data"]["to"], "publishing")
        # link-check output mapped into context
        self.assertEqual(out["data"]["context"]["review"]["broken_links"], 0)

    def test_fire_unknown_event(self):
        mp = write_machine(self.tmp, "docs.machine.json", docs_machine())
        rc, out = self._capture(lambda: self._init(mp, input="draft_path=foo.md"))
        run_id = out["data"]["run_id"]
        rc, out = self._capture(lambda: self._fire(run_id, "BOGUS"))
        self.assertEqual(rc, 1)
        self.assertIn("not available", out["error"])


class TestGuardAndElseTarget(DriverTestBase):
    def test_guard_blocks_then_else_target_redirects(self):
        mp = write_machine(self.tmp, "guard.machine.json", guard_machine())
        rc, out = self._capture(lambda: self._init(mp))
        run_id = out["data"]["run_id"]
        # attempts 0 -> 1
        rc, out = self._capture(lambda: self._fire(run_id, "RETRY"))
        self.assertEqual(out["data"]["status"], "transitioned")
        self.assertEqual(out["data"]["context"]["attempts"], 1)
        # attempts 1 -> 2
        rc, out = self._capture(lambda: self._fire(run_id, "RETRY"))
        self.assertEqual(out["data"]["context"]["attempts"], 2)
        # attempts 2 -> guard fails -> else_target gave-up
        rc, out = self._capture(lambda: self._fire(run_id, "RETRY"))
        self.assertEqual(out["data"]["status"], "redirected")
        self.assertEqual(out["data"]["to"], "gave-up")
        self.assertTrue(out["data"]["terminal"])


class TestReport(DriverTestBase):
    def test_report_success(self):
        mp = write_machine(self.tmp, "docs.machine.json", docs_machine())
        draft = Path(self.tmp) / "draft.md"
        draft.write_text("# Draft", encoding="utf-8")
        rc, out = self._capture(lambda: self._init(mp, input=f"draft_path={draft}"))
        run_id = out["data"]["run_id"]
        self._fire(run_id, "DRAFT_REVIEWED")
        self._fire(run_id, "PUBLISHED")
        rc, out = self._capture(lambda: self._report(run_id))
        self.assertEqual(rc, 0)
        r = out["data"]
        self.assertEqual(r["result"], "SUCCESS")
        self.assertEqual(r["final_state"], "published")
        self.assertEqual(r["events"], 2)
        self.assertEqual(r["schema"], "machina.report.v1")

    def test_report_aborted(self):
        mp = write_machine(self.tmp, "docs.machine.json", docs_machine())
        rc, out = self._capture(lambda: self._init(mp, input="draft_path=foo.md"))
        run_id = out["data"]["run_id"]
        self._abort(run_id, "conductor changed mind")
        rc, out = self._capture(lambda: self._report(run_id))
        self.assertEqual(out["data"]["result"], "ABORTED")

    def test_report_stuck(self):
        m = {
            "id": "stuck-test",
            "name": "Stuck",
            "version": "1.0.0",
            "spec_version": "3.0.0",
            "initial": "blocked-state",
            "context": {"flag": False},
            "scenarios": [{"id": "default", "label": "Default", "initial": "blocked-state", "interface": "API"}],
            "states": {
                "blocked-state": {
                    "description": "All transitions blocked.",
                    "on": {"PROCEED": {"target": "done", "guard": {"type": "compare", "key": "flag", "op": "eq", "value": True}}},
                },
                "done": {"type": "final", "description": "Done."},
            },
        }
        mp = write_machine(self.tmp, "stuck.machine.json", m)
        rc, out = self._capture(lambda: self._init(mp))
        run_id = out["data"]["run_id"]
        rc, out = self._capture(lambda: self._report(run_id))
        self.assertEqual(out["data"]["result"], "STUCK")


class TestPhaseBoundary(DriverTestBase):
    def test_phase_done_requires_child_run(self):
        parent = write_machine(self.tmp, "parent.machine.json", phase_parent_machine())
        rc, out = self._capture(lambda: self._init(parent))
        parent_run = out["data"]["run_id"]
        self._fire(parent_run, "BEGIN_PHASE")
        rc, out = self._capture(lambda: self._fire(parent_run, "PHASE_DONE"))
        self.assertEqual(rc, 1)
        self.assertIn("--child-run", out["error"])

    def test_phase_done_rejects_non_terminal_child(self):
        parent = write_machine(self.tmp, "parent.machine.json", phase_parent_machine())
        child = write_machine(self.tmp, "child.machine.json", phase_child_machine())
        rc, out = self._capture(lambda: self._init(parent))
        parent_run = out["data"]["run_id"]
        self._fire(parent_run, "BEGIN_PHASE")
        rc, out = self._capture(lambda: self._init(child))
        child_run = out["data"]["run_id"]
        # child not driven to terminal
        rc, out = self._capture(lambda: self._fire(parent_run, "PHASE_DONE", child_run=child_run))
        self.assertEqual(rc, 1)
        self.assertIn("not reached a terminal state", out["error"])

    def test_phase_done_permits_successful_child(self):
        parent = write_machine(self.tmp, "parent.machine.json", phase_parent_machine())
        child = write_machine(self.tmp, "child.machine.json", phase_child_machine())
        rc, out = self._capture(lambda: self._init(parent))
        parent_run = out["data"]["run_id"]
        self._fire(parent_run, "BEGIN_PHASE")
        rc, out = self._capture(lambda: self._init(child))
        child_run = out["data"]["run_id"]
        self._fire(child_run, "CHILD_DONE")
        rc, out = self._capture(lambda: self._fire(parent_run, "PHASE_DONE", child_run=child_run))
        self.assertEqual(rc, 0)
        self.assertEqual(out["data"]["status"], "transitioned")
        self.assertEqual(out["data"]["to"], "parent-done")
        # report lists nested run
        rc, out = self._capture(lambda: self._report(parent_run))
        self.assertIn(child_run, out["data"]["nested_runs"])


class TestLedgerIntegrity(DriverTestBase):
    def test_tamper_detected(self):
        mp = write_machine(self.tmp, "docs.machine.json", docs_machine())
        draft = Path(self.tmp) / "draft.md"
        draft.write_text("# Draft", encoding="utf-8")
        rc, out = self._capture(lambda: self._init(mp, input=f"draft_path={draft}"))
        run_id = out["data"]["run_id"]
        self._fire(run_id, "DRAFT_REVIEWED")
        ledger = self.run_dir / run_id / "ledger.jsonl"
        lines = ledger.read_text(encoding="utf-8").splitlines()
        # ledger: [0]=init, [1]=transition. Tamper with the transition record.
        self.assertGreaterEqual(len(lines), 2)
        lines[1] = lines[1].replace('"to":"publishing"', '"to":"published"')
        ledger.write_text("\n".join(lines), encoding="utf-8")
        rc, out = self._capture(lambda: self._status(run_id))
        self.assertEqual(rc, 1)
        self.assertIn("integrity violation", out["error"])


class TestStatus(DriverTestBase):
    def test_status_shows_enabled_blocked(self):
        mp = write_machine(self.tmp, "docs.machine.json", docs_machine())
        rc, out = self._capture(lambda: self._init(mp, input="draft_path=foo.md"))
        run_id = out["data"]["run_id"]
        rc, out = self._capture(lambda: self._status(run_id))
        self.assertEqual(rc, 0)
        d = out["data"]
        self.assertEqual(d["state"], "reviewing-draft")
        self.assertEqual(d["enabled_events"][0]["event"], "DRAFT_REVIEWED")
        self.assertFalse(d["terminal"])


if __name__ == "__main__":
    unittest.main()