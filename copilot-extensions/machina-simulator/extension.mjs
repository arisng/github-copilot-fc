// Extension: machina-simulator
// Machine state-machine validation, autofill, spec reference, and interactive
// simulator. Serves the full simulator app (simulator/app.html) over the
// extension's HTTP server, sharing the compliance/scoring/autofill engine
// (machine-simulator.mjs) with the Copilot tools.

import * as fs from "node:fs";
import * as path from "node:path";
import http from "node:http";
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
import { discoverRunHistory, resolveRunRef } from "./scripts/discovery.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const APP_HTML = path.join(__dirname, "simulator", "app.html");
const ENGINE_JS = path.join(__dirname, "machine-simulator.mjs");
const appHtml = fs.readFileSync(APP_HTML, "utf8");
const engineJs = fs.readFileSync(ENGINE_JS, "utf8");

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

// Lean, serializable run-history inventory for the canvas surface. Carries no
// ledger payloads — the app fetches a specific run via /open-run.
function runInventory(runs) {
  return (runs || []).map((r) => ({
    root: r.root,
    family: r.family,
    runid: r.runid,
    machine: r.machine?.id ?? null,
    records: r.ledger ? r.ledger.length : 0,
    readError: r.readError ?? null,
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
  if (url.pathname === "/runs") {
    // Disjoint run-history inventory (root/family/runid/machine/records).
    const runs = discoverRunHistory();
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: true, runs: runInventory(runs) }));
    return;
  }
  if (url.pathname === "/open-run") {
    // Server-side resolve + replay a persisted run; broadcasts a load event so
    // the app live-loads the picked run (same path as canvas open with runRef).
    const entry = getInstance(instanceId);
    const runRef = (url.searchParams.get("runRef") || "").trim();
    try {
      const runs = discoverRunHistory();
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
      broadcast(entry, "machina", { type: "load", machine: m, replay: { ledger, diffReeval: true, machineJson } });
      res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({
        ok: true,
        verdict: rep.integrity.verdict,
        integrityOk: rep.integrity.ok,
        terminal: rep.terminal,
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
  if (url.pathname === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(appHtml);
    return;
  }
  res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("Not found");
});
server.listen(0, "127.0.0.1");
await new Promise((resolve) => server.once("listening", resolve));
server.unref(); // do not keep the host process alive solely for this loopback server
const port = server.address().port;

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
            description: "Optional persisted-run reference (\"<family>/<runid>\" or bare \"<runid>\") resolved via the shared discovery convention (~/.copilot/session-state/<uuid>/{machina-persist,machina-i2}). When provided, loads machine.json + ledger and enters replay mode.",
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
      handler: async ({ instanceId, input }) => {
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
      },
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
      handler: async ({ instanceId, input }) => {
        const entry = getInstance(instanceId);
        const cmd = input && input.command;
              broadcast(entry, "machina", { type: "command", command: cmd, state: input && input.state, index: input && input.index });
              return { ok: true, command: cmd, state: input && input.state, index: input && input.index };
      },
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
                      handler: async ({ instanceId, input }) => {
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
                          broadcast(entry, "machina", { type: "load", machine: m, replay: { ledger, diffReeval: true, machineJson } });
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
            },
          },
        ],
        open: async (ctx) => {
          const entry = getInstance(ctx.instanceId);
                  const input = ctx.input || {};
                  try {
                            // Auto-discovery: always scan run history so the canvas surfaces
                            // the persisted-run inventory (visible via /state + /runs) even
                            // when no runRef or machine is passed.
                            entry.state.runHistory = discoverRunHistory();
                            if (input.runRef) {
                              // runRef → systematic discovery: load the persisted machine.json +
                              // ledger for the referenced run and enter replay mode. Uses the same
                              // discovery convention as scripts/replay-all.mjs (single source of truth).
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
                    // else: no runRef and no machine — idempotent focus of an existing
                    // instance; preserve whatever replay/state is already loaded.
                  } catch (err) {
                                      entry.state.error = String(err.message || err);
                                    }
                                    return {
                                              url: `http://127.0.0.1:${port}?instance=${ctx.instanceId}`,
                                              title: "Machina Simulator",
                                              status: entry.state.machine
                                                ? "Ready"
                                                : entry.state.runHistory && entry.state.runHistory.length
                                                  ? `Empty — load a machine or pick a run (${entry.state.runHistory.length} discovered)`
                                                  : "Empty — load a machine to begin",
                                            };
                                          },
        onClose: async (ctx) => {
    const entry = instances.get(ctx.instanceId);
    if (entry) {
      entry.cleanup.forEach((fn) => fn());
      instances.delete(ctx.instanceId);
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