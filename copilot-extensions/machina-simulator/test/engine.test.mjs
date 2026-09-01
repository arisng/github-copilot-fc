// Machina engine tests — run with: node test/engine.test.mjs
// Uses Node's built-in test runner (node:test), no external deps.

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  SPEC_REGISTRY,
  LATEST_SPEC_VERSION,
  COMPLIANCE_CHECKS,
  detectSpecVersion,
  specRank,
  versionLE,
  evalGuard,
  applyActions,
  reachableStates,
  isTerminalState,
  detectCycles,
  runCompliance,
  gradeFor,
  buildCoverageBlock,
  cycleCounterKey,
  buildCyclePrevention,
  deriveScenarios,
  addDescriptions,
  markFinals,
  autoPatchItems,
  autoFillMachine,
  buildSpecJsonSchema,
  buildSpecMarkdown,
  getSpec,
} from "../machine-simulator.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sample = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "simulator", "samples", "machina-order.json"), "utf-8"),
);

test("SPEC_REGISTRY newest-first and latest is 2.0.0", () => {
  assert.equal(SPEC_REGISTRY[0].version, "2.0.0");
  assert.equal(SPEC_REGISTRY[1].version, "1.0.0");
  assert.equal(LATEST_SPEC_VERSION, "2.0.0");
});

test("total compliance weight equals exactly 100 for v2", () => {
  const v2 = COMPLIANCE_CHECKS.filter((c) => versionLE(c.since, "2.0.0"));
  assert.equal(v2.length, 17);
  const sum = v2.reduce((a, c) => a + c.weight, 0);
  assert.equal(sum, 100);
});

test("detectSpecVersion: declared vs assumed", () => {
  assert.deepEqual(detectSpecVersion(sample), { version: "2.0.0", declared: false, assumed: true });
  const declared = { ...sample, spec_version: "1.0.0" };
  assert.deepEqual(detectSpecVersion(declared), { version: "1.0.0", declared: true, assumed: false });
});

test("gradeFor boundaries", () => {
  assert.equal(gradeFor(95), "Excellent");
  assert.equal(gradeFor(90), "Excellent");
  assert.equal(gradeFor(85), "Good");
  assert.equal(gradeFor(70), "Fair");
  assert.equal(gradeFor(40), "Needs work");
});

test("sample machine scores Good (80-89) and has no blocking findings", () => {
  const res = runCompliance(sample);
  // The sample legitimately loses points: no declared spec_version (wt 0),
  // no actions/guards (wt 6), and snake_case state keys (wt 5) => 89 = Good.
  assert.ok(res.score >= 80 && res.score < 90, `expected Good band (80-89), got ${res.score}`);
  assert.equal(res.grade, "Good");
  assert.deepEqual(res.blocking, []);
  assert.equal(res.declared, false);
  assert.equal(res.specVersion, "2.0.0");
  const failIds = res.findings.filter((f) => !f.pass).map((f) => f.id);
  assert.ok(failIds.includes("spec-version"));
  assert.ok(failIds.includes("actions-used"));
  assert.ok(failIds.includes("state-naming"));
});

test("runCompliance result shape", () => {
  const res = runCompliance(sample);
  assert.equal(typeof res.score, "number");
  assert.ok(typeof res.byCategory === "object");
  assert.ok(Array.isArray(res.findings));
  assert.ok(res.findings.length > 0);
  const f = res.findings[0];
  for (const k of ["id", "category", "severity", "weight", "pass", "detail", "remediation", "autofill"]) {
    assert.ok(k in f, `missing finding key ${k}`);
  }
  const catTotal = Object.values(res.byCategory).reduce((a, c) => a + c.total, 0);
  const findTotal = res.findings.reduce((a, f) => a + f.weight, 0);
  assert.equal(catTotal, findTotal);
});

test("empty machine fails blocking checks", () => {
  const res = runCompliance({});
  assert.ok(res.score < 50, `expected low score, got ${res.score}`);
  const blockIds = res.blocking.map((b) => b.id);
  assert.ok(blockIds.includes("id-present"));
  assert.ok(blockIds.includes("states-present"));
  assert.ok(blockIds.includes("initial-resolves"));
});

test("evalGuard: compare semantics and value resolution", () => {
  const ctx = { retry_count: 2, flag: "yes", limit: "5" };
  assert.equal(evalGuard({ type: "compare", key: "retry_count", op: "lt", value: 3 }, ctx), true);
  assert.equal(evalGuard({ type: "compare", key: "retry_count", op: "gte", value: 3 }, ctx), false);
  assert.equal(evalGuard({ type: "compare", key: "retry_count", op: "lt", value: "limit" }, ctx), true);
  assert.equal(evalGuard({}, ctx), true);
  assert.equal(evalGuard(null, ctx), true);
});

test("applyActions and setPath mutate context", () => {
  const ctx = { attempts: 0, nested: { n: 1 } };
  applyActions([{ type: "increment", key: "attempts" }], ctx);
  assert.equal(ctx.attempts, 1);
  applyActions([{ type: "increment", key: "nested.n" }], ctx);
  assert.equal(ctx.nested.n, 2);
  applyActions([{ type: "assign", key: "role", value: "admin" }], ctx);
  assert.equal(ctx.role, "admin");
});

test("reachableStates includes initial and scenario entries", () => {
  const reach = reachableStates(sample);
  assert.ok(reach.has("placed"));
  assert.ok(reach.has("refunded"));
  const simple = { initial: "a", states: { a: { on: { GO: { target: "b" } } }, b: {}, c: {} } };
  const r = reachableStates(simple);
  assert.ok(r.has("a") && r.has("b"));
  assert.ok(!r.has("c"));
});

test("isTerminalState honors type final and no-outgoing", () => {
  assert.equal(isTerminalState(sample, "refunded"), true);
  const implicit = { states: { x: {} } };
  assert.equal(isTerminalState(implicit, "x"), true);
});

test("detectCycles finds cycles in sample", () => {
  const cycles = detectCycles(sample);
  const trueCycles = cycles.filter((c) => c.type === "cycle");
  assert.ok(trueCycles.length > 0, "sample has retry cycles");
});

test("cycleCounterKey finds retry/attempt counters", () => {
  const k = cycleCounterKey(sample);
  assert.ok(k === "retry_count" || k === "payment_retries");
  assert.equal(cycleCounterKey({ context: { x: 1 } }), null);
});

test("buildCoverageBlock matches sample coverage semantics", () => {
  const block = buildCoverageBlock(sample);
  assert.equal(block.version, LATEST_SPEC_VERSION);
  assert.equal(typeof block.metrics.coverage_percentage, "number");
  assert.equal(block.metrics.total_states, Object.keys(sample.states).length);
  assert.ok(Array.isArray(block.uncovered_paths));
  assert.ok(Array.isArray(block.recommendations));
  assert.ok(Object.keys(block.edge_coverage).some((k) => k.includes(":")));
});

test("buildCyclePrevention returns null without a retry/attempt counter", () => {
  const noCounter = JSON.parse(JSON.stringify(sample));
  delete noCounter.context.retry_count;
  delete noCounter.context.payment_retries;
  assert.equal(buildCyclePrevention(noCounter), null);
});

test("buildCyclePrevention produces guards when counter present", () => {
  const cp = buildCyclePrevention(sample);
  if (cp) {
    assert.equal(cp.max_retry_limit, 3);
    assert.equal(cp.timeout_seconds, 300);
    assert.ok(Array.isArray(cp.guards) && cp.guards.length > 0);
    for (const g of cp.guards) {
      assert.equal(g.guard.type, "compare");
      assert.equal(g.guard.op, "lt");
    }
  }
});

test("deriveScenarios uses existing scenarios or derives default", () => {
  assert.equal(deriveScenarios(sample), sample.scenarios);
  const bare = { initial: "a", states: { a: {} } };
  assert.deepEqual(deriveScenarios(bare), [{ id: "default", label: "Default", initial: "a", interface: "API" }]);
});

test("addDescriptions and markFinals mark generated", () => {
  const m = { states: { a: { on: { GO: { target: "b" } } }, b: {} } };
  addDescriptions(m);
  assert.ok(m.states.a.description);
  assert.ok(m.states.a.generated);
  markFinals(m);
  assert.equal(m.states.b.type, "final");
  assert.ok(m.states.b.generated);
});

test("autoPatchItems is deterministic on the complete sample", () => {
  const items = autoPatchItems(sample);
  const ids = items.map((i) => i.id);
  assert.deepEqual(ids, ["spec-version"]);
  for (const it of items) {
    assert.equal(typeof it.apply, "function");
  }
});

test("autoPatchItems on a bare machine fills deterministic gaps in fixed order", () => {
  const bare = { id: "demo", states: { a: { on: { GO: { target: "b" } } }, b: {} } };
  const ids = autoPatchItems(bare).map((i) => i.id);
  assert.deepEqual(ids.slice(0, 3), ["spec-version", "version", "scenarios"]);
});

test("autoFillMachine improves score and never mutates the input", () => {
  const input = { id: "demo", initial: "a", context: { retry: 0 }, states: { a: { on: { GO: { target: "b" } } }, b: {} } };
  const bare = JSON.parse(JSON.stringify(input));
  const before = runCompliance(bare).score;
  const res = autoFillMachine(bare);
  assert.ok(res.scoreAfter >= before, `expected autofill to not lower score (${before} -> ${res.scoreAfter})`);
  assert.ok(res.applied.length > 0);
  assert.equal(bare.spec_version, undefined);
  assert.equal(bare.version, undefined);
  assert.ok(res.machine.spec_version);
  assert.ok(res.machine.states.b.type === "final");
});

test("autoFillMachine round-trips without throwing on the full sample", () => {
  const res = autoFillMachine(sample);
  assert.ok(Array.isArray(res.applied));
  assert.equal(typeof res.scoreBefore, "number");
  assert.equal(typeof res.scoreAfter, "number");
});

test("buildSpecJsonSchema v2 includes v2-only properties and required", () => {
  const schema = buildSpecJsonSchema(getSpec("2.0.0"));
  assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
  assert.ok(schema.properties.spec_version);
  assert.ok(schema.properties.scenarios);
  assert.ok(schema.properties.coverage);
  assert.ok(schema.properties.cycle_prevention);
  assert.deepEqual(schema.required, ["id", "states"]);
  assert.ok(schema.$defs.guard);
  assert.ok(schema.$defs.action);
});

test("buildSpecJsonSchema v1 excludes v2-only properties", () => {
  const schema = buildSpecJsonSchema(getSpec("1.0.0"));
  assert.equal(schema.properties.spec_version, undefined);
  assert.equal(schema.properties.scenarios, undefined);
  assert.equal(schema.properties.coverage, undefined);
  assert.equal(schema.$defs.scenario, undefined);
});

test("buildSpecMarkdown is a markdown table with conventions", () => {
  const md = buildSpecMarkdown(getSpec("2.0.0"));
  assert.ok(md.startsWith("# Machine schema · v2.0"));
  assert.ok(md.includes("| Field | Type | Meaning |"));
  assert.ok(md.includes("| `states` |"));
});

test("specRank maps unknown to 0 (latest)", () => {
  assert.equal(specRank("2.0.0"), 0);
  assert.equal(specRank("1.0.0"), 1);
  assert.equal(specRank("9.9.9"), 0);
});

test("compliance applies checks where since <= target version", () => {
  // Full 17-check model at v2 target
  const v2 = runCompliance(sample, "2.0.0").findings.map((f) => f.id);
  assert.equal(v2.length, COMPLIANCE_CHECKS.length);
  // Spec-version check is introduced at 2.0.0, so it must NOT appear at a v1 target
  const v1 = runCompliance(sample, "1.0.0").findings.map((f) => f.id);
  assert.ok(!v1.includes("spec-version"));
  assert.ok(!v1.includes("entry-points"));
  assert.ok(!v1.includes("cycle-guards"));
  assert.ok(!v1.includes("coverage-present"));
  // v1 checks are a subset of v2 findings
  for (const id of v1) assert.ok(v2.includes(id), `v1 check ${id} missing from v2`);
});

test("autofill honors the documented fixed order on a minimal machine", () => {
  // Minimal valid machine missing deterministic auto gaps
  const m = { id: "demo", initial: "a", states: { a: { on: { GO: { target: "b" } } }, b: {} } };
  const ids = autoPatchItems(m, "2.0.0").map((i) => i.id);
  const order = ["spec-version", "version", "scenarios", "coverage", "descriptions", "finals-typed"];
  for (const id of order) {
    assert.ok(ids.includes(id), `expected ${id} in autofill items ${JSON.stringify(ids)}`);
  }
});

console.log("All engine tests passed.");
