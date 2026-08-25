// Canvas integration test — exercises the real extension.mjs HTTP server and
// canvas wiring via the @github/copilot-sdk/extension test stub.
// Run: node --experimental-loader ./test/sdk-stub-loader.mjs test/canvas.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

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

test("canvas action names do not start with canvas.", () => {
  for (const a of canvas.actions) {
    assert.ok(!a.name.startsWith("canvas."), `bad action name ${a.name}`);
  }
});

test("canvas exposes machina_load and machina_command actions", () => {
  const names = canvas.actions.map((a) => a.name).sort();
  assert.deepEqual(names, ["machina_command", "machina_load"]);
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
  for (const cmd of ["play", "pause", "step", "back", "reset", "scenarios", "compliance", "jump"]) {
    const result = await action.handler({
      instanceId: "cmd-inst-1",
      input: { command: cmd, state: cmd === "jump" ? "a" : undefined },
    });
    assert.equal(result.ok, true, cmd);
    assert.equal(result.command, cmd);
  }
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
  assert.ok(html.includes("/engine.mjs"), "app imports the shared engine");
});

test("HTTP server serves engine.mjs as JS", async () => {
  const opened = await canvas.open({ instanceId: "http-inst-engine" });
  const port = new URL(opened.url).port;
  const res = await fetch(`http://127.0.0.1:${port}/engine.mjs`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-type") || "", /javascript/);
  const js = await res.text();
  assert.ok(js.includes("export function runCompliance"), "engine.mjs exposes runCompliance");
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