// Extension: machina-simulator
// Machine state-machine validation, autofill, spec reference, and interactive
// simulator. Serves the full simulator app (simulator/app.html) over the
// extension's HTTP server, sharing the compliance/scoring/autofill engine
// (engine.mjs) with the Copilot tools.

import fs from "node:fs";
import path from "node:path";
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
  runCompliance,
} from "./engine.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const APP_HTML = path.join(__dirname, "simulator", "app.html");
const ENGINE_JS = path.join(__dirname, "engine.mjs");
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
//   /            → simulator/app.html (the full interactive app)
//   /engine.mjs  → engine.mjs (shared single source of truth for the engine)
//   /events      → SSE stream; 'machina' events carry {type:'load'|'command'}
//   /state       → JSON snapshot of the machine + compliance for the instance
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
  if (url.pathname === "/engine.mjs") {
    res.writeHead(200, { "Content-Type": "text/javascript; charset=utf-8" });
    res.end(engineJs);
    return;
  }
  if (url.pathname === "/state") {
    const entry = getInstance(instanceId);
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    const { machine, compliance, error } = entry.state;
    if (error) {
      res.end(JSON.stringify({ ok: false, error }));
      return;
    }
    if (!machine) {
      res.end(JSON.stringify({ ok: true, machine: null, compliance: null }));
      return;
    }
    res.end(
      JSON.stringify({
        ok: true,
        machine,
        compliance: compliance
          ? {
              score: compliance.score,
              grade: compliance.grade,
              specVersion: compliance.specVersion,
              declared: compliance.declared,
              failing: compliance.findings.filter((f) => !f.pass).map((f) => f.id),
            }
          : null,
      }),
    );
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
  id: "machina-viewer",
  displayName: "Machina Simulator",
  description: "Render and drive a Machina state machine in the full simulator (graph, scenario playback, coverage, cycle guards, compliance, schema editor). Live-load machines and send playback commands from the agent.",
  inputSchema: {
    type: "object",
    properties: {
      machine: {
        type: ["object", "string"],
        description: "The Machina machine definition (object or JSON string) to load into the simulator.",
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
      description: "Drive simulator playback: play, pause, step, back, reset, or jump to a state; or run scenario generation / open the compliance panel.",
      inputSchema: {
        type: "object",
        properties: {
          command: {
            type: "string",
            enum: ["play", "pause", "step", "back", "reset", "scenarios", "compliance", "jump"],
            description: "Simulator command to execute.",
          },
          state: {
            type: "string",
            description: "State key to jump to (required for 'jump').",
          },
        },
        required: ["command"],
      },
      handler: async ({ instanceId, input }) => {
        const entry = getInstance(instanceId);
        const cmd = input && input.command;
        broadcast(entry, "machina", { type: "command", command: cmd, state: input && input.state });
        return { ok: true, command: cmd, state: input && input.state };
      },
    },
  ],
  open: async (ctx) => {
    const entry = getInstance(ctx.instanceId);
    if (ctx.input && ctx.input.machine) {
      try {
        const m = parseMachine(ctx.input.machine);
        entry.state.machine = m;
        entry.state.error = null;
        entry.state.compliance = runCompliance(m);
      } catch (err) {
        entry.state.error = String(err.message || err);
      }
    }
    return {
      url: `http://127.0.0.1:${port}?instance=${ctx.instanceId}`,
      title: "Machina Simulator",
      status: entry.state.machine ? "Ready" : "Empty — load a machine to begin",
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
  requestCanvasRenderer: true,
  extensionInfo: {
    source: "project",
    name: "machina-simulator",
  },
});