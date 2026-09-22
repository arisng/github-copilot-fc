// Extension: machina-simulator
// Machine state-machine validation, autofill, spec reference, and interactive
// simulator. Serves the full simulator app (simulator/app.html) over the
// extension's HTTP server, sharing the compliance/scoring/autofill engine
// (machine-simulator.mjs) with the Copilot tools.

import * as fs from "node:fs";
import * as path from "node:path";
import http from "node:http";
import net from "node:net";
import { fileURLToPath } from "node:url";
import { createCanvas, joinSession } from "@github/copilot-sdk/extension";
import {
  LATEST_SPEC_VERSION,
  SPEC_REGISTRY,
  autoFillMachine,
  buildSpecJsonSchema,
  buildSpecMarkdown,
  detectSpecVersion,
  getSpec,
  replayRunLedger,
  replayIntegrityOk,
  runCompliance,
} from "./machine-simulator.mjs";
import { discoverRunHistory, listSessionWorkspaces, resolveRunRef, sessionRoots } from "./scripts/discovery.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const APP_HTML = path.join(__dirname, "simulator", "app.html");
const ENGINE_JS = path.join(__dirname, "machine-simulator.mjs");
const appHtml = fs.readFileSync(APP_HTML, "utf8");
const engineJs = fs.readFileSync(ENGINE_JS, "utf8");

// --- Fixed port for multi-session sharing ----------------------------------
const FIXED_PORT = 7750;

function isPortInUse(port) {
  return new Promise((resolve) => {
    const sock = net.createConnection({ port, host: "127.0.0.1" });
    const done = (v) => { sock.destroy(); resolve(v); };
    sock.on("connect", () => done(true));
    sock.on("error", () => done(false));
    // Bounded probe so a pathological target can't stall module init.
    // A false negative is safe: tryListen() decides definitively.
    sock.setTimeout(1500, () => done(false));
  });
}

function postAction(action, instanceId, input) {
  const body = JSON.stringify({ instanceId, input });
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: "127.0.0.1",
      port: FIXED_PORT,
      path: `/action/${action}`,
      method: "POST",
      headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) },
    }, (res) => {
      let data = "";
      res.on("data", (chunk) => { data += chunk; });
      res.on("end", () => {
        try { resolve(JSON.parse(data)); } catch { resolve({ ok: false, error: "invalid JSON response" }); }
      });
    });
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

// --- Primary election + failover -------------------------------------------
// Attempt to bind the fixed port; resolve to an Error (or null on success).
// Handles the check-then-listen race: if another process claims the port
// between the isPortInUse probe and listen(), EADDRINUSE resolves here
// instead of crashing the extension host with an unhandled 'error' event.
function tryListen(listenPort) {
  return new Promise((resolve) => {
    const onError = (err) => { server.removeListener("listening", onListening); resolve(err); };
    const onListening = () => { server.removeListener("error", onError); resolve(null); };
    server.once("error", onError);
    server.once("listening", onListening);
    server.listen(listenPort, "127.0.0.1");
  });
}

// Re-run the election, e.g. after a postAction connection failure indicates
// the previous primary died. Only one racing pro-motor can win (listen
// arbitrates); losers stay secondary.
async function tryBecomePrimary() {
  if (isPrimary) return true;
  if (await isPortInUse(FIXED_PORT)) return false;
  const err = await tryListen(FIXED_PORT);
  if (!err && server.listening) {
    isPrimary = true;
    server.unref();
    return true;
  }
  return false;
}

// Dispatch an action to this process's local handlers (primary path, or a
// secondary that just promoted after the primary died).
function runLocalAction(action, instanceId, input) {
  switch (action) {
    case "load": return handleMachinaLoad(instanceId, input);
    case "command": return handleMachinaCommand(instanceId, input);
    case "replay": return handleMachinaReplay(instanceId, input);
    case "open": return handleCanvasOpenWithStatus(instanceId, input);
    case "close": return handleCanvasClose(instanceId);
    default: return Promise.resolve({ ok: false, error: "unknown action: " + action });
  }
}

// Single entry point for canvas actions / open: primary executes locally,
// secondary delegates to the primary over HTTP, and a connection-level
// failure triggers a failover election (the primary may have exited).
async function invokeAction(action, instanceId, input) {
  if (isPrimary) return runLocalAction(action, instanceId, input);
  try {
    return await postAction(action, instanceId, input);
  } catch (err) {
    if (await tryBecomePrimary()) return runLocalAction(action, instanceId, input);
    return { ok: false, error: String(err.message || err) };
  }
}

// --- Argument helpers ------------------------------------------------------
// Accept machine as either an already-parsed object or a JSON string.
function parseMachine(arg) {
  if (arg == null) throw new Error("Missing required argument \"machine\".");
  if (typeof arg === "object") return arg;
  if (typeof arg === "string") {
    try {
      return JSON.parse(arg);
    } catch (e) {
      throw new Error("machine is not valid JSON: " + e.message);
    }
  }
  throw new Error("machine must be an object or a JSON string.");
}

function cleanFindings(f) {
  return f.map(({ id, category, severity, weight, pass, detail, remediation, autofill }) => ({
    id, category, severity, weight, pass, detail, remediation, autofill,
  }));
}

// Probe a run's replayed outcome without transferring ledger payloads. The
// app fetches the specific run via /open-run; the inventory only carries the
// adjudication-relevant summary each run row needs at-a-glance.
function probeRun(r) {
  const base = {
    terminal: null,
    verdict: null,
    integrityOk: null,
    finalState: null,
    blockedCount: 0,
    machineMatch: null,
    childRuns: [],
    report: null,
    startedAt: null,
  };
  if (r.readError || !r.ledger || !r.ledger.length || !r.machine) {
    if (r.report) base.report = r.report;
    base.startedAt = r.ledger && r.ledger.length ? (r.ledger[0].payload?.timestamp ?? null) : null;
    return base;
  }
  try {
    const machineJson = r.machinePath ? fs.readFileSync(r.machinePath, "utf8") : null;
    const rep = replayRunLedger(r.machine, r.ledger, { diffReeval: false, machineJson });
    base.terminal = rep.terminal;
    base.verdict = rep.integrity.verdict;
    base.integrityOk = rep.integrity.ok;
    base.finalState = rep.state;
    base.blockedCount = rep.blockedCount || 0;
    base.machineMatch = rep.machineMatch;
    base.childRuns = r.ledger
      .map((rec) => (rec.payload && rec.payload.child_run) || null)
      .filter(Boolean);
    base.startedAt = r.ledger[0].payload?.timestamp ?? null;
    if (r.report) base.report = r.report;
  } catch {
    // Probe is best-effort — a failed probe stays null and the UI shows '?'
    if (r.report) base.report = r.report;
    base.startedAt = r.ledger && r.ledger.length ? (r.ledger[0].payload?.timestamp ?? null) : null;
  }
  return base;
}

// Adjudication-focused run-history inventory for the canvas surface. Carries
// no ledger payloads — the app fetches a specific run via /open-run — but
// does carry each run's terminal disposition + integrity verdict so the Runs
// tab can render outcome chips and family aggregates at-a-glance.
function runInventory(runs) {
  return (runs || []).map((r) => ({
    root: r.root,
    family: r.family,
    runid: r.runid,
    machine: r.machine?.id ?? null,
    machineName: r.machine?.name ?? null,
    records: r.ledger ? r.ledger.length : 0,
    readError: r.readError ?? null,
    ...probeRun(r),
  }));
}

// --- State for canvas ------------------------------------------------------
const instances = new Map();
function getInstance(instanceId) {
  let inst = instances.get(instanceId);
  if (!inst) {
    inst = { state: { machine: null, compliance: null, error: null }, sseClients: new Set(), cleanup: [] };
    instances.set(instanceId, inst);
  }
  return inst;
}
function broadcast(entry, event, data) {
  for (const res of entry.sseClients) {
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  }
}

// --- Standalone handler functions (shared by tools + HTTP action endpoints) -
async function handleMachinaLoad(instanceId, input) {
  const entry = getInstance(instanceId);
  try {
    const m = parseMachine(input && input.machine);
    entry.state.machine = m;
    entry.state.error = null;
    const compliance = runCompliance(m);
    entry.state.compliance = compliance;
    broadcast(entry, "machina", { type: "load", machine: m });
    return {
      ok: true,
      score: compliance.score,
      grade: compliance.grade,
      specVersion: compliance.specVersion,
      declared: compliance.declared,
      states: Object.keys(m.states || {}).length,
      failing: compliance.findings.filter((f) => !f.pass).map((f) => f.id),
    };
  } catch (err) {
    entry.state.error = String(err.message || err);
    broadcast(entry, "machina", { type: "load", machine: null, error: entry.state.error });
    return { ok: false, error: entry.state.error };
  }
}

async function handleMachinaCommand(instanceId, input) {
  const entry = getInstance(instanceId);
  const cmd = input && input.command;
  broadcast(entry, "machina", { type: "command", command: cmd, state: input && input.state, index: input && input.index });
  return { ok: true, command: cmd, state: input && input.state, index: input && input.index };
}

async function handleMachinaReplay(instanceId, input) {
  const entry = getInstance(instanceId);
  try {
    const m = parseMachine(input && input.machine);
    const ledger = Array.isArray(input && input.ledger) ? input.ledger : [];
    if (!ledger.length) throw new Error("ledger must be a non-empty array of records");
    const machineJson = typeof (input && input.machineJson) === "string" && (input.machineJson).length ? input.machineJson : null;
    entry.state.machine = m;
    entry.state.error = null;
    entry.state.compliance = runCompliance(m);
    const rep = replayRunLedger(m, ledger, { diffReeval: true, machineJson });
    entry.state.replay = {
      ledger,
      trace: rep.trace,
      integrity: rep.integrity,
      terminal: rep.terminal,
      state: rep.state,
      context: rep.context,
      blockedCount: rep.blockedCount,
      machineMatch: rep.machineMatch,
      machineHashOk: rep.machineHashOk,
    };
    broadcast(entry, "machina", { type: "load", machine: m, replay: { ledger, diffReeval: true, machineJson, runRef: entry.state.replaySource?.runRef ?? null } });
    return {
      ok: true,
      verdict: rep.integrity.verdict,
      integrityOk: rep.integrity.ok,
      indexOfFirstFailure: rep.integrity.indexOfFirstFailure,
      machineHashOk: rep.machineHashOk,
      terminal: rep.terminal,
      blockedCount: rep.blockedCount,
      trace: rep.trace.map((t, i) => ({
        index: i,
        type: t.type,
        event: t.event ?? null,
        from: t.from ?? null,
        to: t.to ?? null,
        reason: t.reason ?? null,
        note: t.note ?? null,
        child_run: t.child_run ?? null,
        integrityOk: t.integrityOk,
      })),
      machineMatch: rep.machineMatch,
      ledgerMachineId: rep.ledgerMachineId,
    };
  } catch (err) {
    entry.state.error = String(err.message || err);
    broadcast(entry, "machina", { type: "load", machine: null, error: entry.state.error });
    return { ok: false, error: entry.state.error };
  }
}

async function handleCanvasOpen(instanceId, input) {
  const entry = getInstance(instanceId);
  input = input || {};
  entry.state.sessionWorkspace = input.sessionWorkspace || null;
  try {
    const scopedRoots = sessionRoots(input.sessionWorkspace);
    entry.state.runHistory = discoverRunHistory(scopedRoots);
    if (input.runRef) {
      const runs = entry.state.runHistory;
      const matches = resolveRunRef(runs, input.runRef);
      if (!matches.length) throw new Error(`runRef "${input.runRef}" not found in any persisted run root`);
      if (matches.length > 1) throw new Error(`runRef "${input.runRef}" is ambiguous (${matches.length} matches: ${matches.map((m) => `${m.family}/${m.runid}`).join(", ")})`);
      const run = matches[0];
      if (run.readError) throw new Error(`run "${input.runRef}" is unreadable: ${run.readError}`);
      if (!run.machine) throw new Error(`run "${input.runRef}" has no machine.json sibling; load a machine explicitly`);
      const m = run.machine;
      const ledger = run.ledger;
      entry.state.machine = m;
      entry.state.error = null;
      entry.state.compliance = runCompliance(m);
      entry.state.replaySource = { root: run.root, family: run.family, runid: run.runid, runRef: input.runRef };
      entry.state.report = run.report ?? null;
      const machineJson = run.machinePath ? fs.readFileSync(run.machinePath, "utf8") : null;
      const rep = replayRunLedger(m, ledger, { diffReeval: true, machineJson });
      entry.state.replay = {
        ledger,
        trace: rep.trace,
        integrity: rep.integrity,
        terminal: rep.terminal,
        state: rep.state,
        context: rep.context,
        blockedCount: rep.blockedCount,
        machineMatch: rep.machineMatch,
        machineHashOk: rep.machineHashOk,
      };
      broadcast(entry, "machina", { type: "load", machine: m, replay: { ledger, diffReeval: true, machineJson, runRef: entry.state.replaySource?.runRef ?? null }, report: run.report ?? null });
    } else if (input.machine) {
      const m = parseMachine(input.machine);
      entry.state.machine = m;
      entry.state.error = null;
      entry.state.compliance = runCompliance(m);
      if (Array.isArray(input.ledger) && input.ledger.length) {
        const machineJson = typeof (input.machineJson) === "string" && (input.machineJson).length ? input.machineJson : null;
        const rep = replayRunLedger(m, input.ledger, { diffReeval: true, machineJson });
        entry.state.replay = {
          ledger: input.ledger,
          trace: rep.trace,
          integrity: rep.integrity,
          terminal: rep.terminal,
          state: rep.state,
          context: rep.context,
          blockedCount: rep.blockedCount,
          machineMatch: rep.machineMatch,
          machineHashOk: rep.machineHashOk,
        };
        entry.state.replaySource = undefined;
      } else {
        entry.state.replay = undefined;
        entry.state.replaySource = undefined;
      }
    }
  } catch (err) {
    entry.state.error = String(err.message || err);
    // Surface open failures to the browser (mirrors handleMachinaLoad/Replay):
    // the /state endpoint alone is never polled by the app.
    broadcast(entry, "machina", { type: "load", machine: null, error: entry.state.error });
  }
}

// Error-aware canvas status: a failed open must never masquerade as
// "Ready" (stale machine) or "Empty" (error omitted).
function computeOpenStatus(state) {
  if (state.error) return "Error — " + state.error;
  if (state.machine) return "Ready";
  const n = (state.runHistory || []).length;
  return n ? `Empty — load a machine or pick a run (${n} discovered)` : "Empty — load a machine to begin";
}

async function handleCanvasOpenWithStatus(instanceId, input) {
  await handleCanvasOpen(instanceId, input);
  const state = getInstance(instanceId).state;
  return {
    ok: !state.error,
    status: computeOpenStatus(state),
    ...(state.error ? { error: state.error } : {}),
  };
}

function cleanupLocalInstance(instanceId) {
  const entry = instances.get(instanceId);
  if (entry) {
    entry.cleanup.forEach((fn) => fn());
    instances.delete(instanceId);
  }
}

async function handleCanvasClose(instanceId) {
  cleanupLocalInstance(instanceId);
  return { ok: true };
}

// --- HTTP server -----------------------------------------------------------
// Serves:
//   /                     → simulator/app.html (the full interactive app)
//   /machine-simulator.mjs → machine-simulator.mjs (shared single source of truth for the engine)
//   /events                → SSE stream; 'machina' events carry {type:'load'|'command'}
//   /state                 → JSON snapshot of the machine + compliance for the instance
const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  const instanceId = url.searchParams.get("instance") || "";
  if (url.pathname === "/events") {
    res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" });
    res.write(":ok\n\n");
    const entry = getInstance(instanceId);
    entry.sseClients.add(res);
    res.on("close", () => entry.sseClients.delete(res));
    return;
  }
  if (url.pathname === "/machine-simulator.mjs") {
    res.writeHead(200, { "Content-Type": "text/javascript; charset=utf-8" });
    res.end(engineJs);
    return;
  }
  if (url.pathname === "/state") {
    const entry = getInstance(instanceId);
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
        const { machine, compliance, error, replay, replaySource } = entry.state;
    if (error) {
      res.end(JSON.stringify({ ok: false, error }));
      return;
    }
    if (!machine) {
            res.end(JSON.stringify({ ok: true, machine: null, compliance: null, replay: null, runHistory: runInventory(entry.state.runHistory) }));
      return;
    }
    res.end(
      JSON.stringify({
        ok: true,
        machine,
          replay: replay
          ? {
                verdict: replay.integrity.verdict,
                integrityOk: replay.integrity.ok,
                indexOfFirstFailure: replay.integrity.indexOfFirstFailure,
                terminal: replay.terminal,
                blockedCount: replay.blockedCount,
                state: replay.state,
                traceLength: replay.trace.length,
                machineMatch: replay.machineMatch,
                machineHashOk: replay.machineHashOk,
                          source: replaySource ?? null,
                        }
                      : null,
          compliance: compliance
            ? {
                score: compliance.score,
                grade: compliance.grade,
                specVersion: compliance.specVersion,
                declared: compliance.declared,
                failing: compliance.findings.filter((f) => !f.pass).map((f) => f.id),
              }
            : null,
                    runHistory: runInventory(entry.state.runHistory),
                  }),
                );
                return;
              }
  if (url.pathname === "/sessions") {
    // Browseable list of session workspaces that have machina run history so
    // the conductor can pick one and scope the Runs tab to it.
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: true, sessions: listSessionWorkspaces() }));
    return;
  }
  if (url.pathname === "/runs") {
    // Disjoint run-history inventory (root/family/runid/machine/records).
    // Precedence: explicit ?sessionWorkspace= (EVEN EMPTY = clear-all) wins;
    // absent falls back to the instance's scope (set during canvas open).
    // `has()` distinguishes "clear" from "unset" — `get() ||` would treat an
    // explicit clear as unset and wrongly re-apply the instance scope.
    const entry = getInstance(instanceId);
    const sw = url.searchParams.has("sessionWorkspace")
      ? url.searchParams.get("sessionWorkspace")
      : (entry.state.sessionWorkspace || "");
    const runs = discoverRunHistory(sessionRoots(sw) || null);
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: true, scopedTo: sw || null, runs: runInventory(runs) }));
    return;
  }
  if (url.pathname === "/open-run") {
    // Server-side resolve + replay a persisted run; broadcasts a load event so
    // the app live-loads the picked run (same path as canvas open with runRef).
    // Scopes to sessionWorkspace: query param > instance state (set during canvas open).
    const entry = getInstance(instanceId);
    const runRef = (url.searchParams.get("runRef") || "").trim();
    // Same precedence as /runs: explicit param (even empty) > instance state.
    const sw = url.searchParams.has("sessionWorkspace")
      ? url.searchParams.get("sessionWorkspace")
      : (entry.state.sessionWorkspace || "");
    try {
      const runs = discoverRunHistory(sessionRoots(sw) || null);
      const matches = resolveRunRef(runs, runRef);
      if (!matches.length) throw new Error(`runRef "${runRef}" not found in any persisted run root`);
      if (matches.length > 1) throw new Error(`runRef "${runRef}" is ambiguous (${matches.length} matches: ${matches.map((m) => `${m.family}/${m.runid}`).join(", ")})`);
      const run = matches[0];
      if (run.readError) throw new Error(`run "${runRef}" is unreadable: ${run.readError}`);
      if (!run.machine) throw new Error(`run "${runRef}" has no machine.json sibling; load a machine explicitly`);
      const m = run.machine;
      const ledger = run.ledger;
      entry.state.machine = m;
      entry.state.error = null;
      entry.state.compliance = runCompliance(m);
      entry.state.replaySource = { root: run.root, family: run.family, runid: run.runid, runRef };
            entry.state.report = run.report ?? null;
            const machineJson = run.machinePath ? fs.readFileSync(run.machinePath, "utf8") : null;
            const rep = replayRunLedger(m, ledger, { diffReeval: true, machineJson });
            entry.state.replay = {
              ledger,
              trace: rep.trace,
              integrity: rep.integrity,
              terminal: rep.terminal,
              state: rep.state,
              context: rep.context,
              blockedCount: rep.blockedCount,
              machineMatch: rep.machineMatch,
              machineHashOk: rep.machineHashOk,
            };
                    broadcast(entry, "machina", { type: "load", machine: m, replay: { ledger, diffReeval: true, machineJson, runRef: entry.state.replaySource?.runRef ?? null }, report: run.report ?? null });
      res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({
        ok: true,
        verdict: rep.integrity.verdict,
        integrityOk: rep.integrity.ok,
        terminal: rep.terminal,
              report: run.report ?? null,
              source: entry.state.replaySource,
            }));
    } catch (err) {
      entry.state.error = String(err.message || err);
      broadcast(entry, "machina", { type: "load", machine: null, error: entry.state.error });
      res.writeHead(404, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ ok: false, error: entry.state.error }));
      return;
    }
    return;
  }
  // --- POST action endpoints (for secondary process delegation) ---------------
  if (url.pathname === "/action/load" && req.method === "POST") {
    let body = "";
    req.on("data", (c) => { body += c; });
    req.on("end", async () => {
      try {
        const { instanceId, input } = JSON.parse(body);
        const result = await handleMachinaLoad(instanceId, input);
        res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ ok: false, error: String(err.message || err) }));
      }
    });
    return;
  }
  if (url.pathname === "/action/command" && req.method === "POST") {
    let body = "";
    req.on("data", (c) => { body += c; });
    req.on("end", async () => {
      try {
        const { instanceId, input } = JSON.parse(body);
        const result = await handleMachinaCommand(instanceId, input);
        res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ ok: false, error: String(err.message || err) }));
      }
    });
    return;
  }
  if (url.pathname === "/action/replay" && req.method === "POST") {
    let body = "";
    req.on("data", (c) => { body += c; });
    req.on("end", async () => {
      try {
        const { instanceId, input } = JSON.parse(body);
        const result = await handleMachinaReplay(instanceId, input);
        res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ ok: false, error: String(err.message || err) }));
      }
    });
    return;
  }
  if (url.pathname === "/action/open" && req.method === "POST") {
    let body = "";
    req.on("data", (c) => { body += c; });
    req.on("end", async () => {
      try {
        const { instanceId, input } = JSON.parse(body);
        // Returns {ok, status, error?} — status is error-aware so a failed
        // open never reads "Ready"/"Empty" to the secondary.
        const result = await handleCanvasOpenWithStatus(instanceId, input);
        res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ ok: false, error: String(err.message || err) }));
      }
    });
    return;
  }
  if (url.pathname === "/action/close" && req.method === "POST") {
    // Lets a secondary's onClose drop the instance from the PRIMARY's map —
    // without this, delegated canvases leak full replay state forever.
    let body = "";
    req.on("data", (c) => { body += c; });
    req.on("end", async () => {
      try {
        const { instanceId } = JSON.parse(body);
        const result = await handleCanvasClose(instanceId || "");
        res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ ok: false, error: String(err.message || err) }));
      }
    });
    return;
  }
  if (url.pathname === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(appHtml);
    return;
  }
  res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("Not found");
});

// --- Fixed port + primary/secondary detection ------------------------------
let isPrimary = false;
let port = FIXED_PORT;

if (!(await isPortInUse(FIXED_PORT))) {
  // Check-then-listen race: another process may claim the port between the
  // probe and listen(). tryListen() catches EADDRINUSE and we degrade to
  // secondary instead of crashing on an unhandled 'error' event.
  const listenErr = await tryListen(FIXED_PORT);
  isPrimary = !listenErr && server.listening;
}
// If the port is already in use (or the race was lost), don't start the
// server — delegate to the primary via /action/* (invokeAction).
server.unref(); // do not keep the host process alive solely for this loopback server

// --- Canvas ----------------------------------------------------------------
const canvas = createCanvas({
  id: "machine-simulator",
  displayName: "Machina Simulator",
  description: "Render and drive a Machina state machine in the full simulator (graph, scenario playback, coverage, cycle guards, compliance, schema editor). Live-load machines and send playback commands from the agent.",
  inputSchema: {
    type: "object",
    properties: {
      machine: {
        type: ["object", "string"],
        description: "The Machina machine definition (object or JSON string) to load into the simulator.",
      },
        ledger: {
          type: "array",
          items: { type: "object" },
          description: "Optional recorded ledger (init/transition/blocked/redirect/abort records) to replay instead of live simulation.",
        },
          runRef: {
            type: "string",
            description: "Optional persisted-run reference (\"<family>/<runid>\" or bare \"<runid>\") resolved via the shared discovery convention (~/.copilot/session-state/<uuid>/{machina-runs,machina-persist,machina-i2}). When provided, loads machine.json + ledger and enters replay mode.",
          },
          sessionWorkspace: {
            type: "string",
            description: "Absolute path to the current Copilot session workspace (e.g. ~/.copilot/session-state/<uuid>). When provided, run-history discovery is scoped to this session only instead of scanning all sessions.",
          },
        },
      },
  actions: [
    {
      name: "machina_load",
      description: "Load a Machina machine into the simulator canvas and return its compliance summary.",
      inputSchema: {
        type: "object",
        properties: {
          machine: {
            type: ["object", "string"],
            description: "The Machina machine definition (object or JSON string).",
          },
        },
        required: ["machine"],
      },
      handler: async ({ instanceId, input }) => invokeAction("load", instanceId, input),
    },
    {
      name: "machina_command",
          description: "Drive simulator playback: play, pause, step, back, reset, or jump to a state; or run scenario generation / open the compliance panel. In replay mode, step/back/reset/jump walk the recorded ledger trace.",
      inputSchema: {
        type: "object",
        properties: {
          command: {
            type: "string",
                enum: ["play", "pause", "step", "back", "reset", "scenarios", "compliance", "jump", "replayStep", "replayBack", "replayReset", "replayJump"],
            description: "Simulator command to execute.",
          },
          state: {
            type: "string",
            description: "State key to jump to (required for 'jump').",
          },
              index: {
                type: "integer",
                description: "Ledger record index to jump to (required for 'replayJump').",
              },
            },
            required: ["command"],
          },
      handler: async ({ instanceId, input }) => invokeAction("command", instanceId, input),
    },
          {
            name: "machina_replay",
            description: "Replay a recorded Machina run from a persisted ledger (init/transition/blocked/redirect/abort records) into the simulator canvas. Returns the replay trace + integrity verdict (verifiable | tampered) with the first-failure index. Loads the machine and enters replay mode; commands step/back/reset walk the recorded trace.",
            inputSchema: {
              type: "object",
              properties: {
                machine: {
                  type: ["object", "string"],
                  description: "The Machina machine definition (object or JSON string) to load for replay. Its id should match the ledger's machine_id.",
                },
                ledger: {
                  type: "array",
                  items: { type: "object" },
                  description: "The recorded ledger: an ordered array of { prev_hash, payload, hash } records (init/transition/blocked/redirect/abort).",
                },
                          machineJson: {
                            type: "string",
                            description: "Optional raw machine.json text as the driver hashed it (sha256 of the parse, Python-canonical). When provided, machine_sha256 binding is verified. If omitted, machine-hash is skipped (not verified).",
                          },
                        },
                        required: ["machine", "ledger"],
                      },
                      handler: async ({ instanceId, input }) => invokeAction("replay", instanceId, input),
          },
        ],
        open: async (ctx) => {
          // invokeAction handles primary/secondary/failover; the {ok,status}
          // shape is identical on both paths, and status is error-aware.
          const resp = await invokeAction("open", ctx.instanceId, ctx.input || {});
          const status = resp && typeof resp.status === "string"
            ? resp.status
            : "Error — " + ((resp && resp.error) || "unreachable");
          return {
            url: `http://127.0.0.1:${port}?instance=${ctx.instanceId}`,
            title: "Machina Simulator",
            status,
          };
        },
        onClose: async (ctx) => {
          cleanupLocalInstance(ctx.instanceId);
          if (!isPrimary) {
            // Best-effort: drop the instance from the PRIMARY's map too.
            // Ignore failures — if the primary is gone, its state died with it.
            postAction("close", ctx.instanceId, {}).catch(() => {});
          }
        },
});

// --- Extension entry point -------------------------------------------------
const session = await joinSession({
  tools: [
    {
      name: "machina_validate",
      description: "Validate a Machina state-machine definition against the versioned schema spec and return its compliance score (0–100), grade, per-category breakdown, and per-check findings with remediation. Use for editing/authoring Machina machine JSON.",
      skipPermission: true,
      defer: "auto",
      parameters: {
        type: "object",
        properties: {
          machine: {
            description: "The Machina machine definition as an object or a JSON string.",
            oneOf: [{ type: "object" }, { type: "string" }],
          },
          targetVersion: {
            description: "Optional schema-spec version to score against (defaults to the machine's declared version or latest).",
            type: "string",
            enum: SPEC_REGISTRY.map((s) => s.version),
          },
        },
        required: ["machine"],
      },
      handler: async (args) => {
        const m = parseMachine(args && args.machine);
        const det = detectSpecVersion(m);
        const compliance = runCompliance(m, args && args.targetVersion);
        return JSON.stringify(
          {
            score: compliance.score,
            grade: compliance.grade,
            specVersion: compliance.specVersion,
            declared: compliance.declared,
            assumedLatest: det.assumed,
            byCategory: compliance.byCategory,
            blocking: compliance.blocking.map((b) => b.id),
            findings: cleanFindings(compliance.findings),
          },
          null,
          2,
        );
      },
    },
    {
      name: "machina_autofill",
      description: "Compute the deterministic 'Generate missing' patches for a Machina machine definition (spec_version, version, scenarios, coverage, cycle guards, descriptions, finals) and return the patched machine plus what changed and the before/after compliance score. Use to automatically fill only safe, deterministic gaps.",
      skipPermission: true,
      defer: "auto",
      parameters: {
        type: "object",
        properties: {
          machine: {
            description: "The Machina machine definition as an object or a JSON string.",
            oneOf: [{ type: "object" }, { type: "string" }],
          },
          targetVersion: {
            description: "Optional schema-spec version to target for patches (defaults to the machine's declared version or latest).",
            type: "string",
            enum: SPEC_REGISTRY.map((s) => s.version),
          },
        },
        required: ["machine"],
      },
      handler: async (args) => {
        const m = parseMachine(args && args.machine);
        const result = autoFillMachine(m, { targetVersion: args && args.targetVersion });
        return JSON.stringify(
          {
            applied: result.applied,
            scoreBefore: result.scoreBefore,
            scoreAfter: result.scoreAfter,
            machine: result.machine,
          },
          null,
          2,
        );
      },
    },
    {
      name: "machina_spec",
      description: "Return the Machina schema spec reference for a given version as a JSON Schema draft 2020-12 object or as Markdown. Use to look up field definitions, types, and conventions when authoring or validating Machina machine JSON.",
      skipPermission: true,
      defer: "never",
      parameters: {
        type: "object",
        properties: {
          version: {
            description: "Schema-spec version. Defaults to the latest.",
            type: "string",
            enum: SPEC_REGISTRY.map((s) => s.version),
          },
          format: {
            description: "Output format: 'json-schema' (default) or 'markdown'.",
            type: "string",
            enum: ["json-schema", "markdown"],
          },
        },
      },
      handler: async (args) => {
        const spec = getSpec(args && args.version);
        const format = (args && args.format) || "json-schema";
        if (format === "markdown") return buildSpecMarkdown(spec);
        return JSON.stringify(buildSpecJsonSchema(spec), null, 2);
      },
    },
  ],
  canvases: [canvas],
    commands: [
      {
        name: "machina-simulator",
              description: "Open the Machina Simulator canvas (machine-simulator). Usage: /machina-simulator [<machine JSON or path>]. Pass a machine JSON string to preload it.",
        handler: async (ctx) => {
          const arg = (ctx.args || "").trim();
          await session.send({
                  prompt: `Open the "machine-simulator" canvas using the open_canvas tool${
              arg ? `, passing machine "${arg}"` : ""
            }. Do NOT explain in chat — just open the canvas.`,
            displayPrompt: arg ? `Opening Machina Simulator — ${arg.slice(0, 40)}…` : "Opening Machina Simulator…",
          });
        },
      },
    ],
    requestCanvasRenderer: true,
  extensionInfo: {
    source: "project",
    name: "machina-simulator",
  },
});