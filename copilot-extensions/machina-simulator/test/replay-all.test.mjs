// Stage 3 gate test — run: node test/replay-all.test.mjs
// Exercises scripts/replay-all.mjs against a temp run root: a valid fixture
// (green gate) and a tampered copy (red gate). Uses the engine's canonicalizer
// to build self-consistent ledgers.

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { canonicalizeMachinaText, sha256Hex } from "../machine-simulator.mjs";
import { main as replayAllMain } from "../scripts/replay-all.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const mk = {
  id: "demo", initial: "a", states: {
    a: { on: { GO: { target: "b" } } },
    b: { type: "final" },
  },
};
function record(payload, prev = null) {
  return { prev_hash: prev, payload, hash: sha256Hex(canonicalizeMachinaText(JSON.stringify(payload))) };
}
function makeRunDir(root, runid, tamperIndex = -1) {
  const dir = path.join(root, runid);
  fs.mkdirSync(dir, { recursive: true });
  const r1 = record({
    type: "init", machine_id: "demo", spec_version: "3.0.0", scenario: "default",
    state: "a", context: {}, machine_dir: "<run-dir>", machine_sha256: "x",
    tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z",
  });
  const r2 = record({
    type: "transition", event: "GO", from: "a", to: "b",
    guard: null, evidence: [], exit_actions: [], transition_actions: [], entry_actions: [],
    context_after: {}, note: "ok", child_run: null, timestamp: "2026-09-03T00:00:01Z",
  }, r1.hash);
  const ledger = [r1, r2];
  if (tamperIndex >= 0) ledger[tamperIndex].payload.note = "FORGED";
  fs.writeFileSync(path.join(dir, "ledger.jsonl"), ledger.map((l) => JSON.stringify(l)).join("\n") + "\n", "utf8");
  fs.writeFileSync(path.join(dir, "machine.json"), JSON.stringify(mk, null, 2), "utf8");
}

// Patch process cwd-independent argv.
async function runGate(trueRoot, tamperedRoot) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "replay-all-"));
  const validRoot = path.join(tmp, "valid");
  const corruptRoot = path.join(tmp, "corrupt");
  fs.mkdirSync(validRoot, { recursive: true });
  fs.mkdirSync(corruptRoot, { recursive: true });
  if (trueRoot) makeRunDir(validRoot, "run1");
  if (tamperedRoot) makeRunDir(corruptRoot, "run1", 1);
  // Both roots passed together -> total = valid + corrupt runs.
  const roots = [];
  if (trueRoot) roots.push(validRoot);
  if (tamperedRoot) roots.push(corruptRoot);
    // Synthetic fixtures have no blocked-final runs => expect 0 stuck.
    process.env.MACHINA_EXPECTED_STUCK = "0";
    return { code: await replayAllMain([...roots]), tmp };
}

test("replay-all green gate: verifiable episode exits 0", async () => {
  const { code } = await runGate(true, false);
  assert.equal(code, 0);
});

test("replay-all red gate: tampered episode exits non-zero", async () => {
  const { code } = await runGate(false, true);
  assert.notEqual(code, 0);
});

test("replay-all mixed: tampered presence forces non-zero even with valid runs", async () => {
  const { code } = await runGate(true, true);
  assert.notEqual(code, 0);
});

console.log("All replay-all gate tests passed.");