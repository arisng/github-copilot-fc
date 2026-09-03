// Engine replay tests (Stage 1) — run with: node test/replay.test.mjs
// Covers replayRunLedger + replayIntegrityOk for all 5 record types,
// integrity verification (tampered-red), STUCK disposition on blocked-final,
// trace==ledger sequence assertion, and the re-eval diff (A3).

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  canonicalizeMachinaText,
  sha256Hex,
  replayRunLedger,
  replayIntegrityOk,
  clone,
} from "../machine-simulator.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixturePath = path.join(__dirname, "fixtures", "ledger-synthetic.jsonl");
const machinePath = path.join(__dirname, "fixtures", "machine-releasenotes.json");
const ledger = fs
  .readFileSync(fixturePath, "utf8")
  .trim()
  .split("\n")
  .map((l) => JSON.parse(l));
const machine = JSON.parse(fs.readFileSync(machinePath, "utf8"));

// --- fixture helpers -------------------------------------------------------
// record(payload, prev) — builds a self-consistent chained record via the
// engine's own canonicalizer (used only for inline guards/stuck fixtures).
function record(payload, prev = null) {
  return { prev_hash: prev, payload, hash: sha256Hex(canonicalizeMachinaText(JSON.stringify(payload))) };
}

// --- integrity + trace -----------------------------------------------------
test("replayRunLedger on synthetic ledger: verifiable integrity + 5 trace entries", () => {
  const r = replayRunLedger(machine, ledger);
  assert.equal(r.integrity.verdict, "verifiable");
  assert.equal(r.integrity.ok, true);
  assert.equal(r.trace.length, 5);
  assert.deepEqual(r.trace.map((e) => e.type), ["init", "transition", "blocked", "transition", "redirect"]);
  assert.equal(r.integrity.indexOfFirstFailure, null);
});

test("trace == ledger sequence (events, from/to, evidence)", () => {
  const r = replayRunLedger(machine, ledger);
  for (let i = 0; i < ledger.length; i++) {
    const src = ledger[i].payload;
    const tr = r.trace[i];
    assert.equal(tr.event ?? null, src.event ?? null);
    assert.equal(tr.from ?? null, src.from ?? null);
    assert.equal(tr.to ?? null, src.to ?? null);
    if (src.evidence) assert.deepEqual(tr.evidence, src.evidence);
  }
});

test("blocked records carry reason/evidence/note and leave state unchanged", () => {
  const r = replayRunLedger(machine, ledger);
  const blocked = r.trace.find((e) => e.type === "blocked");
  assert.ok(blocked);
  assert.equal(blocked.reason, "evidence");
  assert.ok(Array.isArray(blocked.evidence) && blocked.evidence.length > 0);
  assert.equal(blocked.note, "negative gate proof");
  const before = r.trace[r.trace.indexOf(blocked) - 1];
  assert.equal(blocked.state, before.state);
    assert.deepEqual(blocked.context, before.context); // context carried unchanged, not moved
  assert.equal(r.blockedCount, 1);
});

test("terminal disposition: non-terminal machine state derives incomplete", () => {
  const r = replayRunLedger(machine, ledger);
  // Final record is a redirect to review, which is not a final state -> incomplete.
  assert.equal(r.terminal, "incomplete");
  assert.equal(r.state, "review");
});

test("replayIntegrityOk passes on the valid ledger", () => {
  const v = replayIntegrityOk(ledger);
  assert.deepEqual(v, { ok: true, verdict: "verifiable", indexOfFirstFailure: null, expectedHash: null, actualHash: null });
});

test("tampered ledger: integrityOk false + indexOfFirstFailure (RED)", () => {
  const tampered = ledger.map((r) => clone(r));
  // Flip a byte in a transition payload value (channel value) without touching the chain hashes.
  tampered[3].payload.note = "tampered note";
  const r = replayRunLedger(machine, tampered);
  assert.equal(r.integrity.ok, false);
  assert.equal(r.integrity.verdict, "tampered");
  assert.equal(r.integrity.indexOfFirstFailure, 3);
  // Even if only the payload changed, the recomputed record hash differs.
  const v = replayIntegrityOk(tampered);
  assert.equal(v.ok, false);
  assert.equal(v.verdict, "tampered");
  assert.equal(v.indexOfFirstFailure, 3);
});

test("tampered hash breaks the chain at the exact index", () => {
  const tampered = ledger.map((r) => clone(r));
  // Corrupt record 2's hash wholesale (append garbage) -> both chain and hash fail there.
  tampered[2].hash = "deadbeef" + tampered[2].hash.slice(8);
  const r = replayRunLedger(machine, tampered);
  assert.equal(r.integrity.ok, false);
  assert.equal(r.integrity.indexOfFirstFailure, 2);
});

test("missing machine id: machineMatch null, replay still works", () => {
  const r = replayRunLedger(machine, ledger);
  assert.equal(r.machineMatch, true);
  const other = replayRunLedger({ ...machine, id: "other-id" }, ledger);
  assert.equal(other.machineMatch, false);
});

// --- STUCK disposition (non-terminal blocked-final) -----------------------
test("blocked-final ledger renders terminal=stuck, state unchanged (R8)", () => {
  const init = record({
    type: "init", machine_id: "demo", spec_version: "3.0.0", scenario: "default",
    state: "waiting", context: { n: 0 }, machine_dir: "<run-dir>",
    machine_sha256: "x", tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z",
  });
  const blocked = record({
    type: "blocked", event: "PROCEED", from: "waiting", reason: "guard",
    detail: "n must be >= 1 but is 0", note: "final blocked", timestamp: "2026-09-03T00:00:01Z",
  }, init.hash);
  const mk = {
    id: "demo", initial: "waiting", states: {
      waiting: { on: { PROCEED: { target: "done", guard: { type: "compare", key: "n", op: "gte", value: 1 } } } },
      done: { type: "final" },
    },
  };
  const r = replayRunLedger(mk, [init, blocked]);
  assert.equal(r.terminal, "stuck");
  assert.equal(r.state, "waiting");
  assert.equal(r.blockedCount, 1);
  assert.equal(r.integrity.verdict, "verifiable");
});

test("aborted run renders terminal=aborted with state preserved", () => {
  const init = record({
    type: "init", machine_id: "demo", spec_version: "3.0.0", scenario: "default",
    state: "running", context: {}, machine_dir: "<run-dir>",
    machine_sha256: "x", tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z",
  });
  const abort = record({
    type: "abort", state: "running", reason: "operator cancelled", timestamp: "2026-09-03T00:00:02Z",
  }, init.hash);
  const mk = { id: "demo", initial: "running", states: { running: {}, done: { type: "final" } } };
  const r = replayRunLedger(mk, [init, abort]);
  assert.equal(r.terminal, "aborted");
  assert.equal(r.state, "running");
  // abort keeps the context fold from init
  assert.deepEqual(r.context, {});
});

// --- re-eval diff (A3) -------------------------------------------------------
test("diffReeval: guard mismatch detected when recorded transition disagrees with re-eval", () => {
  // Machine: gate to 'go' guarded by ready==true.
  const mk = {
    id: "demo", initial: "idle", states: {
      idle: {
        on: {
          GO: { target: "go", guard: { type: "compare", key: "ready", op: "eq", value: true }, else_target: "idle" },
        },
      },
      go: { type: "final" },
    },
  };
  const init = record({
    type: "init", machine_id: "demo", spec_version: "3.0.0", scenario: "default",
    state: "idle", context: { ready: false }, machine_dir: "<run-dir>",
    machine_sha256: "x", tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z",
  });
  // Recorded claim: GO fired to 'go' from a context where ready==false.
  // Re-eval: guard fails -> else_target 'idle' -> guardMismatch true.
  const trans = record({
    type: "transition", event: "GO", from: "idle", to: "go",
    guard: { type: "compare", key: "ready", op: "eq", value: true },
    evidence: [], exit_actions: [], transition_actions: [], entry_actions: [],
    context_after: { ready: false }, note: "recorded", child_run: null, timestamp: "2026-09-03T00:00:01Z",
  }, init.hash);
  const r = replayRunLedger(mk, [init, trans], { diffReeval: true });
  const e = r.trace[1];
  assert.equal(e.recordedTo, "go");
  assert.equal(e.reevalTo, "idle");
  assert.equal(e.guardMismatch, true);
});

test("diffReeval: no mismatch when recorded transition agrees with re-eval", () => {
  const mk = {
    id: "demo", initial: "idle", states: {
      idle: {
        on: { GO: { target: "go", guard: { type: "compare", key: "ready", op: "eq", value: true }, else_target: "idle" } },
      },
      go: { type: "final" },
    },
  };
  const init = record({
    type: "init", machine_id: "demo", spec_version: "3.0.0", scenario: "default",
    state: "idle", context: { ready: true }, machine_dir: "<run-dir>",
    machine_sha256: "x", tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z",
  });
  const trans = record({
    type: "transition", event: "GO", from: "idle", to: "go",
    guard: { type: "compare", key: "ready", op: "eq", value: true },
    evidence: [], exit_actions: [], transition_actions: [], entry_actions: [],
    context_after: { ready: true }, note: "ok", child_run: null, timestamp: "2026-09-03T00:00:01Z",
  }, init.hash);
  const r = replayRunLedger(mk, [init, trans], { diffReeval: true });
  const e = r.trace[1];
  assert.equal(e.reevalTo, "go");
  assert.equal(e.guardMismatch, false);
  assert.deepEqual(e.foldedCtxAfter, trans.payload.context_after);
});

test("diffReeval foldedCtxAfter folds recorded actions over context_after (no mutation)", () => {
  const mk = {
    id: "demo", initial: "s", states: {
      s: { on: { STEP: { target: "t", actions: [{ type: "increment", key: "n" }] } } },
      t: {},
    },
  };
  const init = record({
    type: "init", machine_id: "demo", spec_version: "3.0.0", scenario: "default",
    state: "s", context: { n: 0 }, machine_dir: "<run-dir>",
    machine_sha256: "x", tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z",
  });
  const trans = record({
    type: "transition", event: "STEP", from: "s", to: "t",
    evidence: [], exit_actions: [], transition_actions: [{ type: "increment", key: "n" }], entry_actions: [],
    context_after: { n: 1 }, note: "", child_run: null, timestamp: "2026-09-03T00:00:01Z",
  }, init.hash);
  const r = replayRunLedger(mk, [init, trans], { diffReeval: true });
  assert.equal(r.trace[1].guardMismatch, false);
  assert.equal(r.trace[1].foldedCtxAfter.n, 1);
  // follower: no mutation of the recorded payload
  assert.equal(trans.payload.context_after.n, 1);
});

// --- machine_sha256 binding (HIGH-finding regression) -----------------------

test("machine_sha256 verified when raw machineJson matches the pinned hash", () => {
  const raw = fs.readFileSync(machinePath, "utf8");
  const pinned = sha256Hex(canonicalizeMachinaText(raw));
  const init = record({
    type: "init", machine_id: "pm-release-notes", spec_version: "3.0.0", scenario: "default",
    state: "collect", context: {}, machine_dir: "<run-dir>",
    machine_sha256: pinned, tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z",
  });
  const r = replayRunLedger(machine, [init], { machineJson: raw });
  assert.equal(r.machineHashOk, true);
  assert.equal(r.integrity.verdict, "verifiable");
});

test("machine_sha256 mismatched raw text flips integrity to tampered (RED)", () => {
  const raw = fs.readFileSync(machinePath, "utf8");
  const pinned = sha256Hex(canonicalizeMachinaText(raw));
  const init = record({
    type: "init", machine_id: "pm-release-notes", spec_version: "3.0.0", scenario: "default",
    state: "collect", context: {}, machine_dir: "<run-dir>",
    machine_sha256: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef", tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z",
  });
  // Provide the CORRECT raw text but a WRONG pinned hash -> mismatch.
  const r = replayRunLedger(machine, [init], { machineJson: raw });
  assert.equal(r.machineHashOk, false);
  assert.equal(r.integrity.ok, false);
  assert.equal(r.integrity.failureKind, "machine-hash");
  assert.equal(r.integrity.verdict, "tampered");
});

test("machine_sha256 skipped (null) when no raw machineJson provided", () => {
  const init = record({
    type: "init", machine_id: "pm-release-notes", spec_version: "3.0.0", scenario: "default",
    state: "collect", context: {}, machine_dir: "<run-dir>",
    machine_sha256: "some-hash", tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z",
  });
  const r = replayRunLedger(machine, [init]);
  assert.equal(r.machineHashOk, null);
  assert.equal(r.integrity.verdict, "verifiable"); // chain/record-hash still verified
});

console.log("All replay engine tests passed.");