// discovery.test.mjs — systematic run-history auto-discovery (single convention).
// Verifies defaultRoots/env override, family/runid inference, machine.json
// sibling loading, read-error fail-open, and resolveRunRef against a temp root.
//
// Note: defaultRoots() scans the real ~/.copilot/session-state — we can't
// control that here. These tests exercise the shared helpers against a temp
// root injected via resolveRunRoots/discoverRunHistory(explicitRoots), which is
// exactly how replay-all.mjs and extension.mjs consume them.

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";
import {
  PERSIST_ROOT_NAMES,
  explicitRootsFromEnv,
  defaultRoots,
  resolveRunRoots,
  discoverRunHistory,
  resolveRunRef,
  findRun,
} from "../scripts/discovery.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function makeRoot(tmp, sub) {
  const dir = path.join(tmp, sub);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}
function writeRun(dir, runid, opts = {}) {
  const runDir = path.join(dir, runid);
  fs.mkdirSync(runDir, { recursive: true });
  const ledger = [
    JSON.stringify({
      prev_hash: null,
      payload: { type: "init", machine_id: opts.machineId || "demo", spec_version: "3.0.0", scenario: "default", state: "a", context: {}, machine_dir: "<run-dir>", machine_sha256: "x", tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z" },
      hash: "h0",
    }),
    JSON.stringify({
      prev_hash: "h0",
      payload: { type: "transition", event: "GO", from: "a", to: "b", guard: null, evidence: [], exit_actions: [], transition_actions: [], entry_actions: [], context_after: {}, note: "ok", child_run: null, timestamp: "2026-09-03T00:00:01Z" },
      hash: "h1",
    }),
  ].join("\n") + "\n";
  fs.writeFileSync(path.join(runDir, "ledger.jsonl"), ledger, "utf8");
  if (opts.machine !== false) {
    fs.writeFileSync(
      path.join(runDir, "machine.json"),
      JSON.stringify({ id: opts.machineId || "demo", initial: "a", states: { a: {}, b: { type: "final" } } }, null, 2),
      "utf8",
    );
  }
}

test("PERSIST_ROOT_NAMES lists the two canonical persist containers", () => {
  assert.deepEqual([...PERSIST_ROOT_NAMES].sort(), ["machina-i2", "machina-persist"]);
});

test("explicitRootsFromEnv parses MACHINA_RUN_ROOTS (; and , and both)", () => {
  const before = process.env.MACHINA_RUN_ROOTS;
  delete process.env.MACHINA_RUN_ROOTS;
  try {
    assert.equal(explicitRootsFromEnv(), null);
    process.env.MACHINA_RUN_ROOTS = "C:\\a\\root1;C:\\b\\root2";
    const parsed = explicitRootsFromEnv();
    assert.equal(parsed.length, 2);
    assert.ok(parsed.every((p) => path.isAbsolute(p)));
    process.env.MACHINA_RUN_ROOTS = "C:\\a,C:\\b;C:\\c";
    assert.equal(explicitRootsFromEnv().length, 3);
  } finally {
    if (before === undefined) delete process.env.MACHINA_RUN_ROOTS;
    else process.env.MACHINA_RUN_ROOTS = before;
  }
});

test("defaultRoots scans session-state for machina-persist / machina-i2", () => {
  // No hard assertions on the real machine's corpus — assert shape: absolute paths only.
  const roots = defaultRoots();
  assert.ok(Array.isArray(roots));
  for (const r of roots) assert.ok(path.isAbsolute(r));
  // Roots must be named machina-persist or machina-i2.
  for (const r of roots) assert.ok(PERSIST_ROOT_NAMES.includes(path.basename(r)), `unexpected root ${r}`);
});

test("resolveRunRoots: explicit roots win over env over default", () => {
  const before = process.env.MACHINA_RUN_ROOTS;
  delete process.env.MACHINA_RUN_ROOTS;
  try {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "machina-disc-"));
    const explicit = path.join(tmp, "explicit");
    fs.mkdirSync(explicit, { recursive: true });
    const a = resolveRunRoots([explicit]);
    assert.equal(a.length, 1);
    assert.ok(path.isAbsolute(a[0]));
    // env override when no explicit
    process.env.MACHINA_RUN_ROOTS = explicit;
    const b = resolveRunRoots(null);
    assert.equal(b.length, 1);
    assert.equal(b[0], path.resolve(explicit));
  } finally {
    if (before === undefined) delete process.env.MACHINA_RUN_ROOTS;
    else process.env.MACHINA_RUN_ROOTS = before;
  }
});

test("discoverRunHistory walks family/runid layout and reads machine.json", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "machina-disc-"));
  const root = makeRoot(tmp, "machina-persist");
  writeRun(path.join(root, "i1-triage"), "runA", { machineId: "pm-issue-triage" });
  writeRun(path.join(root, "i1-triage"), "runB", { machineId: "pm-issue-triage" });
  writeRun(path.join(root, "i2-milestone"), "runC", { machineId: "pm-milestone-triage" });
  const runs = discoverRunHistory([root]);
  assert.equal(runs.length, 3);
  const byId = Object.fromEntries(runs.map((r) => [r.runid, r]));
  assert.equal(byId.runA.family, "i1-triage");
  assert.equal(byId.runA.machine.id, "pm-issue-triage");
  assert.ok(byId.runA.ledger.length === 2);
  assert.ok(byId.runA.readError === null);
  assert.equal(byId.runC.family, "i2-milestone");
});

test("discoverRunHistory handles flat layout (runid as family) and missing machine.json", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "machina-disc-"));
  const root = makeRoot(tmp, "machina-i2");
  writeRun(root, "runX", { machine: false });
  const runs = discoverRunHistory([root]);
  assert.equal(runs.length, 1);
  assert.equal(runs[0].family, "runX");
  assert.equal(runs[0].runid, "runX");
  assert.equal(runs[0].machine, null);
  assert.equal(runs[0].machinePath, null);
});

test("discoverRunHistory reports readError (fail-open) for corrupt ledger", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "machina-disc-"));
  const root = makeRoot(tmp, "machina-persist");
  const runDir = path.join(root, "i1-triage");
  fs.mkdirSync(runDir, { recursive: true });
  fs.writeFileSync(path.join(runDir, "ledger.jsonl"), "{ not valid json\n", "utf8");
  const runs = discoverRunHistory([root]);
  assert.equal(runs.length, 1);
  assert.equal(runs[0].ledger, null);
  assert.ok(runs[0].readError);
});

test("resolveRunRef matches family/runid and bare runid", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "machina-disc-"));
  const root = makeRoot(tmp, "machina-persist");
  writeRun(path.join(root, "i1-triage"), "runA");
  writeRun(path.join(root, "i1-triage"), "runB");
  writeRun(path.join(root, "i2-milestone"), "runA", { machineId: "other" });
  const runs = discoverRunHistory([root]);
  const fam = resolveRunRef(runs, "i1-triage/runA");
  assert.equal(fam.length, 1);
  assert.equal(fam[0].family, "i1-triage");
  const bare = resolveRunRef(runs, "runB");
  assert.equal(bare.length, 1);
  assert.equal(bare[0].runid, "runB");
  const ambiguous = resolveRunRef(runs, "runA");
  assert.equal(ambiguous.length, 2, "bare runA is ambiguous, both families should match");
  const none = resolveRunRef(runs, "does-not-exist");
  assert.equal(none.length, 0);
});

test("findRun returns the exact run or null (ambiguity → null)", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "machina-disc-"));
  const root = makeRoot(tmp, "machina-persist");
  writeRun(path.join(root, "i1-triage"), "runA");
  writeRun(path.join(root, "i2-milestone"), "runA", { machineId: "other" });
  const exact = findRun([root], "i1-triage/runA");
  assert.equal(exact.runid, "runA");
  assert.equal(exact.family, "i1-triage");
  const ambiguous = findRun([root], "runA");
  assert.equal(ambiguous, null);
});

console.log("All discovery tests passed.");