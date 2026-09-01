#!/usr/bin/env python3
"""Unit tests for machine-validator.py (the shared Machina engine).

Run:  python -m unittest discover -s skills/machina-authoring/tests -v
"""
import json
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

_VALIDATOR = Path(__file__).resolve().parents[1] / "scripts" / "machine-validator.py"
_spec = importlib.util.spec_from_file_location("machine_validator", _VALIDATOR)
mv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mv)


def sample_machine(**overrides):
    m = {
        "id": "order-fulfillment",
        "name": "Order Fulfillment",
        "version": "1.0.0",
        "spec_version": "2.0.0",
        "initial": "pending",
        "context": {"attempts": 0},
        "scenarios": [{"id": "default", "label": "Default", "initial": "pending", "interface": "API"}],
        "states": {
            "pending": {
                "description": "Awaiting payment.",
                "on": {
                    "PAY": {"target": "paid"},
                    "RETRY_PAY": {
                        "target": "pending",
                        "guard": {"type": "compare", "key": "attempts", "op": "lt", "value": 3},
                        "actions": [{"type": "increment", "key": "attempts"}],
                    },
                },
            },
            "paid": {"description": "Payment confirmed.", "on": {"SHIP": {"target": "shipped"}}},
            "shipped": {"type": "final", "description": "Delivered to carrier."},
        },
    }
    m.update(overrides)
    return m


class TestSpecVersioning(unittest.TestCase):
    def test_latest_is_v3(self):
        self.assertEqual(mv.LATEST_SPEC_VERSION, "3.0.0")
        self.assertEqual(mv.SPEC_VERSIONS, ["3.0.0", "2.0.0", "1.0.0"])

    def test_detect_declared(self):
        det = mv.detect_spec_version({"spec_version": "2.0.0"})
        self.assertTrue(det["declared"])
        self.assertFalse(det["assumed"])
        self.assertEqual(det["version"], "2.0.0")

    def test_detect_assumed_latest(self):
        det = mv.detect_spec_version({})
        self.assertFalse(det["declared"])
        self.assertTrue(det["assumed"])
        self.assertEqual(det["version"], "3.0.0")

    def test_spec_rank(self):
        self.assertEqual(mv.spec_rank("3.0.0"), 0)
        self.assertEqual(mv.spec_rank("2.0.0"), 1)
        self.assertEqual(mv.spec_rank("1.0.0"), 2)
        self.assertEqual(mv.spec_rank("9.9.9"), 0)  # unknown -> latest


class TestEngineHelpers(unittest.TestCase):
    def test_get_path_dotted(self):
        ctx = {"a": {"b": {"c": 42}}}
        self.assertEqual(mv.get_path(ctx, "a.b.c"), 42)
        self.assertIsNone(mv.get_path(ctx, "a.b.missing"))
        self.assertIsNone(mv.get_path(ctx, "missing"))

    def test_set_path_creates_nested(self):
        ctx = {}
        mv.set_path(ctx, "a.b.c", 1)
        self.assertEqual(ctx, {"a": {"b": {"c": 1}}})

    def test_resolve_value_literal(self):
        self.assertEqual(mv.resolve_value(3, {}), 3)
        self.assertEqual(mv.resolve_value("3", {}), 3)
        self.assertEqual(mv.resolve_value("3.5", {}), 3.5)

    def test_resolve_value_context_key(self):
        self.assertEqual(mv.resolve_value("attempts", {"attempts": 2}), 2)

    def test_eval_guard_compare(self):
        ctx = {"attempts": 2}
        self.assertTrue(mv.eval_guard({"type": "compare", "key": "attempts", "op": "lt", "value": 3}, ctx))
        self.assertFalse(mv.eval_guard({"type": "compare", "key": "attempts", "op": "gte", "value": 3}, ctx))
        self.assertTrue(mv.eval_guard({"type": "compare", "key": "attempts", "op": "eq", "value": "attempts"}, ctx))

    def test_eval_guard_unknown_op_passes(self):
        self.assertTrue(mv.eval_guard({"type": "compare", "key": "attempts", "op": "bogus", "value": 1}, {"attempts": 0}))

    def test_eval_guard_none_passes(self):
        self.assertTrue(mv.eval_guard(None, {}))
        self.assertTrue(mv.eval_guard({"type": "other"}, {}))

    def test_apply_actions_increment_assign(self):
        ctx = {"attempts": 0, "nested": {"x": 1}}
        mv.apply_actions([{"type": "increment", "key": "attempts"}, {"type": "assign", "key": "nested.x", "value": 9}], ctx)
        self.assertEqual(ctx["attempts"], 1)
        self.assertEqual(ctx["nested"]["x"], 9)

    def test_is_terminal_state(self):
            m = sample_machine()
            self.assertFalse(mv.is_terminal_state(m, "pending"))
            self.assertTrue(mv.is_terminal_state(m, "shipped"))  # type: final
            self.assertFalse(mv.is_terminal_state(m, "paid"))  # paid has SHIP -> not terminal


class TestCompliance(unittest.TestCase):
    def test_good_machine_scores_high(self):
        res = mv.run_compliance(sample_machine())
        self.assertGreaterEqual(res["score"], 90)
        self.assertEqual(res["grade"], "Excellent")
        self.assertEqual(res["specVersion"], "2.0.0")

    def test_blocking_findings(self):
            bad = sample_machine()
            bad["id"] = ""
            bad["states"] = {}
            bad["initial"] = "nope"
            res = mv.run_compliance(bad)
            self.assertTrue(any(f["id"] == "id-present" and not f["pass"] for f in res["findings"]))
            self.assertTrue(any(f["id"] == "states-present" and not f["pass"] for f in res["findings"]))
            self.assertTrue(any(f["id"] == "initial-resolves" and not f["pass"] for f in res["findings"]))
            self.assertTrue(res["blocking"])

    def test_17_checks_weight_100(self):
        res = mv.run_compliance(sample_machine())
        total = sum(f["weight"] for f in res["findings"])
        self.assertEqual(total, 100)
        self.assertEqual(len(res["findings"]), 17)

    def test_v3_machine_scores(self):
        m = sample_machine(spec_version="3.0.0")
        res = mv.run_compliance(m)
        self.assertEqual(res["specVersion"], "3.0.0")
        self.assertGreaterEqual(res["score"], 90)

    def test_cycle_guards_autofill_review_without_counter(self):
        m = sample_machine(context={})
        res = mv.run_compliance(m)
        cg = next(f for f in res["findings"] if f["id"] == "cycle-guards")
        self.assertEqual(cg["autofill"], "review")


class TestValidate(unittest.TestCase):
    def test_validate_ok(self):
        self.assertEqual(mv.validate(sample_machine()), [])

    def test_validate_errors(self):
        errs = mv.validate({"id": 1, "states": {}})
        self.assertTrue(any('"id" must be a string' in e for e in errs))
        self.assertTrue(any('"states" must be a non-empty object' in e for e in errs))

    def test_validate_bad_target(self):
        m = sample_machine()
        m["states"]["pending"]["on"]["PAY"]["target"] = "missing"
        errs = mv.validate(m)
        self.assertTrue(any("target" in e for e in errs))


class TestAutofill(unittest.TestCase):
    def test_auto_patch_items_fills_gaps(self):
            m = sample_machine()
            del m["version"]
            del m["scenarios"]
            items = mv.auto_patch_items(m)
            ids = [i["id"] for i in items]
            self.assertIn("version", ids)
            self.assertIn("scenarios", ids)
            self.assertIn("coverage", ids)  # coverage-present fails -> auto patch offered

    def test_apply_patches(self):
        m = sample_machine()
        del m["version"]
        items = mv.auto_patch_items(m)
        changed = mv.apply_patches(m, [i["id"] for i in items])
        self.assertIn("version", changed)
        self.assertEqual(m["version"], "1.0.0")

    def test_derive_scenarios(self):
        m = sample_machine()
        del m["scenarios"]
        sc = mv.derive_scenarios(m)
        self.assertEqual(sc[0]["initial"], "pending")
        self.assertEqual(sc[0]["interface"], "API")


class TestTopology(unittest.TestCase):
    def test_reachable_states(self):
        m = sample_machine()
        reach = mv.reachable_states(m)
        self.assertIn("pending", reach)
        self.assertIn("paid", reach)
        self.assertIn("shipped", reach)

    def test_detect_cycles(self):
        m = sample_machine()
        cycles = mv.detect_cycles(m)
        self.assertTrue(any(c["type"] == "cycle" for c in cycles))  # RETRY_PAY self-loop

    def test_build_coverage_block(self):
        m = sample_machine()
        cov = mv.build_coverage_block(m)
        self.assertIn("metrics", cov)
        self.assertIn("state_coverage", cov)
        self.assertIn("edge_coverage", cov)
        self.assertEqual(cov["metrics"]["total_states"], 3)

    def test_build_cycle_prevention(self):
        m = sample_machine()
        cp = mv.build_cycle_prevention(m)
        self.assertIsNotNone(cp)
        self.assertIn("guards", cp)
        self.assertEqual(cp["max_retry_limit"], 3)


class TestCLI(unittest.TestCase):
    def _run(self, args):
            return mv.main(["machine-validator.py"] + args)

    def test_score_command(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(sample_machine(), f)
            path = f.name
        try:
            rc = self._run(["score", path])
            self.assertEqual(rc, 0)
        finally:
            os.unlink(path)

    def test_validate_command(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(sample_machine(), f)
            path = f.name
        try:
            rc = self._run(["validate", path])
            self.assertEqual(rc, 0)
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()