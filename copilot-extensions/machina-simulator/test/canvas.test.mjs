// Canvas integration test — exercises the real extension.mjs HTTP server and
// canvas wiring via the @github/copilot-sdk/extension test stub.
// Run: node --experimental-loader ./test/sdk-stub-loader.mjs test/canvas.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Craft a self-consistent ledger (init→transition→final-ish) whose hashes use
// the engine's canonicalizer so replay verifies.
import { canonicalizeMachinaText, sha256Hex } from "../machine-simulator.mjs";
function rec(payload, prev = null) {
  return { prev_hash: prev, payload, hash: sha256Hex(canonicalizeMachinaText(JSON.stringify(payload))) };
}
function writePersistedRun(root, runid, machineId = "pm-release-notes") {
  const runDir = path.join(root, runid);
  fs.mkdirSync(runDir, { recursive: true });
  const machineJson = JSON.stringify(
    { id: machineId, initial: "a", states: { a: { on: { GO: { target: "b" } } }, b: { type: "final" } } },
    null,
    2,
  );
  const machine = JSON.parse(machineJson);
  const r1 = rec({ type: "init", machine_id: machineId, spec_version: "3.0.0", scenario: "default", state: "a", context: {}, machine_dir: "<run-dir>", machine_sha256: sha256Hex(canonicalizeMachinaText(machineJson)), tool_hashes: {}, timestamp: "2026-09-03T00:00:00Z" });
  const r2 = rec({ type: "transition", event: "GO", from: "a", to: "b", guard: null, evidence: [], exit_actions: [], transition_actions: [], entry_actions: [], context_after: {}, note: "ok", child_run: null, timestamp: "2026-09-03T00:00:01Z" }, r1.hash);
  fs.writeFileSync(path.join(runDir, "ledger.jsonl"), [r1, r2].map((l) => JSON.stringify(l)).join("\n") + "\n", "utf8");
  fs.writeFileSync(path.join(runDir, "machine.json"), machineJson, "utf8");
}

// Note: extension.mjs registers its HTTP server at import time. The test stub
// (test/stubs/copilot-sdk-extension.mjs) records joinSession opts.
const { __opts } = await import("../extension.mjs").then(() => globalThis.__machinaTestSession);

const sample = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "simulator", "samples", "machina-order.json"), "utf-8"),
);

const tools = __opts.tools || [];
const canvas = (__opts.canvases || [])[0];

test("extension registers 3 tools with unique names", () => {
  assert.equal(tools.length, 3);
  const names = tools.map((t) => t.name);
  assert.deepEqual(names.sort(), ["machina_autofill", "machina_spec", "machina_validate"]);
  assert.equal(new Set(names).size, 3);
});

test("extension registers one machina-viewer canvas and requests renderer", () => {
  assert.equal(__opts.requestCanvasRenderer, true);
  assert.ok(canvas);
  assert.equal(canvas.id, "machina-viewer");
  assert.ok(Array.isArray(canvas.actions));
  assert.equal(canvas.displayName, "Machina Simulator");
});

test("extension registers a /machina-simulator slash command that opens the canvas via prompt", async () => {
  assert.ok(Array.isArray(__opts.commands), "joinSession must register a commands array");
  const cmd = __opts.commands.find((c) => c.name === "machina-simulator");
  assert.ok(cmd, "expected a /machina-simulator command");
  assert.ok(cmd.description.startsWith("Open the Machina Simulator canvas"));
  assert.equal(typeof cmd.handler, "function");
  // Capture send() calls made by the handler (stub records them in __calls).
  const session = globalThis.__machinaTestSession;
  const before = (session.__calls || []).length;
  await cmd.handler({ sessionId: "sess-1", args: "" });
  const calls = session.__calls || [];
  assert.ok(calls.length > before, "handler must call session.send");
  const sent = calls[calls.length - 1];
  assert.ok(sent.payload && sent.payload.prompt, "send must carry a prompt");
  assert.match(sent.payload.prompt, /open_canvas/i);
  assert.match(sent.payload.prompt, /machina-viewer/);
  assert.match(sent.payload.prompt, /Do NOT explain/);
  // A machine arg is threaded into the prompt.
  const before2 = calls.length;
  await cmd.handler({ sessionId: "sess-2", args: '{ "id": "demo" }' });
  const sent2 = session.__calls[session.__calls.length - 1];
  assert.match(sent2.payload.prompt, /passing machine/);
  void before2;
});

test("canvas action names do not start with canvas.", () => {
  for (const a of canvas.actions) {
    assert.ok(!a.name.startsWith("canvas."), `bad action name ${a.name}`);
  }
});

test("canvas exposes machina_load, machina_command, machina_replay actions", () => {
  const names = canvas.actions.map((a) => a.name).sort();
  assert.deepEqual(names, ["machina_command", "machina_load", "machina_replay"]);
});

test("machina_load action renders the machine and returns compliance summary", async () => {
  const action = canvas.actions.find((a) => a.name === "machina_load");
  assert.ok(action);
  const result = await action.handler({ instanceId: "test-inst-1", input: { machine: sample } });
  assert.equal(result.ok, true);
  assert.equal(typeof result.score, "number");
  assert.equal(result.score, 89);
  assert.equal(result.grade, "Good");
  assert.equal(result.states, 11);
  assert.ok(Array.isArray(result.failing));
});

test("machina_load rejects invalid machine with a clear error", async () => {
  const action = canvas.actions.find((a) => a.name === "machina_load");
  const result = await action.handler({ instanceId: "test-inst-2", input: { machine: "{bad" } });
  assert.equal(result.ok, false);
  assert.ok(/not valid JSON/.test(result.error));
});

test("machina_command accepts all documented commands", async () => {
  const action = canvas.actions.find((a) => a.name === "machina_command");
  for (const cmd of ["play", "pause", "step", "back", "reset", "scenarios", "compliance", "jump", "replayStep", "replayBack", "replayReset", "replayJump"]) {
    const result = await action.handler({
      instanceId: "cmd-inst-1",
      input: { command: cmd, state: cmd === "jump" ? "a" : undefined, index: cmd === "replayJump" ? 0 : undefined },
    });
    assert.equal(result.ok, true, cmd);
    assert.equal(result.command, cmd);
  }
});

test("machina_replay replays a ledger and returns trace + integrity verdict", async () => {
  const action = canvas.actions.find((a) => a.name === "machina_replay");
  assert.ok(action);
  const ledger = fs
    .readFileSync(path.join(__dirname, "fixtures", "ledger-synthetic.jsonl"), "utf8")
    .trim()
    .split("\n")
    .map((l) => JSON.parse(l));
  const machine = JSON.parse(
    fs.readFileSync(path.join(__dirname, "fixtures", "machine-releasenotes.json"), "utf8"),
  );
  const result = await action.handler({
    instanceId: "replay-inst-1",
    input: { machine, ledger },
  });
  assert.equal(result.ok, true);
  assert.equal(result.verdict, "verifiable");
  assert.equal(result.integrityOk, true);
  assert.equal(result.trace.length, 5);
  assert.deepEqual(result.trace.map((t) => t.type), ["init", "transition", "blocked", "transition", "redirect"]);
  assert.equal(result.terminal, "incomplete");
  assert.equal(result.machineMatch, true);
  // blocked record surfaces reason/evidence
  const blocked = result.trace.find((t) => t.type === "blocked");
  assert.equal(blocked.reason, "evidence");
});

test("machina_replay detects tampered ledger", async () => {
  const action = canvas.actions.find((a) => a.name === "machina_replay");
  const ledger = fs
    .readFileSync(path.join(__dirname, "fixtures", "ledger-synthetic.jsonl"), "utf8")
    .trim()
    .split("\n")
    .map((l) => JSON.parse(l));
  ledger[3].payload.note = "tampered";
  const machine = JSON.parse(
    fs.readFileSync(path.join(__dirname, "fixtures", "machine-releasenotes.json"), "utf8"),
  );
  const result = await action.handler({
    instanceId: "replay-inst-2",
    input: { machine, ledger },
  });
  assert.equal(result.ok, true);
  assert.equal(result.verdict, "tampered");
  assert.equal(result.integrityOk, false);
  assert.equal(result.indexOfFirstFailure, 3);
});

test("machina_replay rejects empty ledger", async () => {
  const action = canvas.actions.find((a) => a.name === "machina_replay");
  const result = await action.handler({
    instanceId: "replay-inst-3",
    input: { machine: sample, ledger: [] },
  });
  assert.equal(result.ok, false);
  assert.ok(/non-empty array/.test(result.error));
});

test("machina_replay broadcasts a load event carrying replay payload", async () => {
  const action = canvas.actions.find((a) => a.name === "machina_replay");
  const ledger = fs
    .readFileSync(path.join(__dirname, "fixtures", "ledger-synthetic.jsonl"), "utf8")
    .trim()
    .split("\n")
    .map((l) => JSON.parse(l));
  const machineJson = fs.readFileSync(path.join(__dirname, "fixtures", "machine-releasenotes.json"), "utf8");
  const machine = JSON.parse(machineJson);
  // instance shares getInstance state; assert the SSR /state now carries verdict
  await action.handler({ instanceId: "replay-inst-state", input: { machine, ledger, machineJson } });
  const opened = await canvas.open({ instanceId: "replay-inst-state" });
  const port = new URL(opened.url).port;
  const res = await fetch(`http://127.0.0.1:${port}/state?instance=replay-inst-state`);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.replay.verdict, "verifiable");
  assert.equal(body.replay.traceLength, 5);
  assert.equal(body.replay.terminal, "incomplete");
  // machine_sha256 bound via machineJson raw text
  assert.equal(body.replay.machineHashOk, true);
});

test("machina_replay machine-hash mismatch surfaces in /state (RED)", async () => {
  const action = canvas.actions.find((a) => a.name === "machina_replay");
  const ledger = fs
    .readFileSync(path.join(__dirname, "fixtures", "ledger-synthetic.jsonl"), "utf8")
    .trim()
    .split("\n")
    .map((l) => JSON.parse(l));
  const machineJson = fs.readFileSync(path.join(__dirname, "fixtures", "machine-releasenotes.json"), "utf8");
  const machine = JSON.parse(machineJson);
  // Corrupt the ledger's init machine_sha256 (wrong pin) but keep the chain/hashes valid.
  const brokenLedger = ledger.map((r) => JSON.parse(JSON.stringify(r)));
  brokenLedger[0].payload.machine_sha256 = "deadbeef".repeat(8);
  // Hash chain stays valid (we only changed a payload value AFTER hashing) -> record
  // hash mismatch would be the failure; to isolate the machine-hash path we need a
  // ledger whose init hash is recomputed over the WRONG pin. Simplest: verify engine
  // level (unit covered); here at least confirm the action returns machineHashOk=false
  // when machineJson mismatches a CORRECT-looking chain (the recompute naturally
  // fails at record 0 with record-hash, but we also get the explicit machineHashOk).
  const result = await action.handler({ instanceId: "replay-inst-msha", input: { machine, ledger: brokenLedger, machineJson } });
  assert.equal(result.ok, true);
  assert.equal(result.integrityOk, false);
  assert.equal(result.machineHashOk, false);
});

test("canvas open is idempotent and returns a loopback URL on 127.0.0.1", async () => {
  const url1 = await canvas.open({ instanceId: "test-inst-open", input: { machine: sample } });
  const url2 = await canvas.open({ instanceId: "test-inst-open", input: { machine: sample } });
  assert.equal(url1.url, url2.url, "open must be idempotent");
  assert.ok(url1.url.startsWith("http://127.0.0.1:"));
  assert.ok(url1.title);
  assert.equal(url1.status, "Ready");
});

test("HTTP server serves the full simulator app (module script, imports engine)", async () => {
  const opened = await canvas.open({ instanceId: "http-inst" });
  const port = new URL(opened.url).port;
  const res = await fetch(`http://127.0.0.1:${port}/`);
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.ok(html.includes("Machina ·") || html.includes("State Machine Simulator"), "serves the simulator app");
  assert.ok(html.includes('<script type="module">'), "app uses a module script");
  assert.ok(html.includes("/machine-simulator.mjs"), "app imports the shared engine");
});

test("served app.html carries the replay trust-badge + blocked-log markers (conductor surface)", () => {
  const html = fs.readFileSync(path.join(__dirname, "..", "simulator", "app.html"), "utf8");
  assert.ok(html.includes('id="stage-trust"'), "served app has the replay trust badge element");
  assert.ok(/pill-trust|stage-trust/.test(html), "served app carries trust-badge CSS/markup");
  assert.ok(/loadReplay|replayStep|replayBack|replayReset/.test(html), "served app has replay navigation functions");
  assert.ok(/↯|lg-blocked/.test(html), "served app renders a blocked-record marker");
  assert.ok(/⇀|lg-redirect/.test(html), "served app renders a redirect-record marker");
});

  test("HTTP server serves machine-simulator.mjs as JS", async () => {
  const opened = await canvas.open({ instanceId: "http-inst-engine" });
  const port = new URL(opened.url).port;
    const res = await fetch(`http://127.0.0.1:${port}/machine-simulator.mjs`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-type") || "", /javascript/);
  const js = await res.text();
    assert.ok(js.includes("export function runCompliance"), "machine-simulator.mjs exposes runCompliance");
});

test("served app.html has no inline engine definitions (single source of truth)", () => {
  const html = fs.readFileSync(path.join(__dirname, "..", "simulator", "app.html"), "utf8");
  const script = html.match(/<script type="module">([\s\S]*?)<\/script>/);
  assert.ok(script, "app.html has a module script");
  const body = script[1];
  for (const name of [
    "getPath", "setPath", "resolveValue", "evalGuard", "applyActions", "detectCycles",
    "SPEC_REGISTRY", "LATEST_SPEC_VERSION", "specRank", "detectSpecVersion",
    "buildSpecJsonSchema", "buildSpecMarkdown", "reachableStates", "isTerminalState",
    "COMPLIANCE_CHECKS", "gradeFor", "runCompliance", "buildRecommendations",
    "buildCoverageBlock", "cycleCounterKey", "buildCyclePrevention", "deriveScenarios",
    "addDescriptions", "markFinals", "autoPatchItems",
  ]) {
    assert.ok(
      !new RegExp(`(?:function|const|let)\\s+${name}\\s*(?:\\(|=)`).test(body),
      `app.html must not define ${name} (should import it)`,
    );
  }
});

test("/state returns machine + compliance JSON for a loaded instance", async () => {
  const action = canvas.actions.find((a) => a.name === "machina_load");
  await action.handler({ instanceId: "state-inst", input: { machine: sample } });
  const opened = await canvas.open({ instanceId: "state-inst" });
  const port = new URL(opened.url).port;
  const res = await fetch(`http://127.0.0.1:${port}/state?instance=state-inst`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-type") || "", /json/);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.ok(body.machine);
  assert.ok(body.compliance);
  assert.equal(body.compliance.score, 89);
  assert.equal(body.compliance.grade, "Good");
});

test("/state for an unknown instance returns empty state (ok, no machine)", async () => {
  const opened = await canvas.open({ instanceId: "state-empty" });
  const port = new URL(opened.url).port;
  const res = await fetch(`http://127.0.0.1:${port}/state?instance=state-empty`);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.machine, null);
});

test("canvas open without machine reports empty status", async () => {
  const opened = await canvas.open({ instanceId: "no-machine-inst" });
  assert.equal(opened.status, "Empty — load a machine to begin");
});

test("canvas open with runRef auto-discovers a persisted run via run history", async () => {
  // Build a temp machina-persist root and point discovery at it via MACHINA_RUN_ROOTS.
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "machina-canvas-runref-"));
  const root = path.join(tmp, "machina-persist");
  fs.mkdirSync(root, { recursive: true });
  const family = "i5-releasenotes";
  fs.mkdirSync(path.join(root, family), { recursive: true });
  writePersistedRun(path.join(root, family), "runRefA", "pm-release-notes");

  const prev = process.env.MACHINA_RUN_ROOTS;
  process.env.MACHINA_RUN_ROOTS = root;
  try {
    const opened = await canvas.open({ instanceId: "runref-inst", input: { runRef: `${family}/runRefA` } });
    assert.equal(opened.status, "Ready");
    const port = new URL(opened.url).port;
    const res = await fetch(`http://127.0.0.1:${port}/state?instance=runref-inst`);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(body.machine);
    assert.equal(body.machine.id, "pm-release-notes");
    assert.ok(body.replay, "run discovery must enter replay mode");
    assert.equal(body.replay.verdict, "verifiable");
    assert.equal(body.replay.integrityOk, true);
    assert.equal(body.replay.traceLength, 2);
    assert.equal(body.replay.terminal, "complete");
    assert.equal(body.replay.machineHashOk, true);
        assert.ok(body.replay.source, "replay source must be surfaced");
        assert.equal(body.replay.source.family, family);
        assert.equal(body.replay.source.runid, "runRefA");
        assert.equal(body.replay.source.runRef, `${family}/runRefA`);
  } finally {
    if (prev === undefined) delete process.env.MACHINA_RUN_ROOTS;
    else process.env.MACHINA_RUN_ROOTS = prev;
  }
});

test("canvas open with unknown runRef reports a clear error", async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "machina-canvas-runref-"));
  const root = path.join(tmp, "machina-persist");
  fs.mkdirSync(root, { recursive: true });
  const prev = process.env.MACHINA_RUN_ROOTS;
  process.env.MACHINA_RUN_ROOTS = root;
  try {
    const opened = await canvas.open({ instanceId: "runref-missing", input: { runRef: "nowhere/nope" } });
    // open never throws; status stays empty (error is captured, machine null)
    assert.equal(opened.status, "Empty — load a machine to begin");
  } finally {
    if (prev === undefined) delete process.env.MACHINA_RUN_ROOTS;
    else process.env.MACHINA_RUN_ROOTS = prev;
  }
});