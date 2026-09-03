// discovery.mjs — systematic run-history auto-discovery (single convention).
//
// A "run history source" is any directory tree under the canonical persist
// roots that contains a ledger.jsonl (+ optional machine.json sibling). The
// convention is deliberately pragmatic:
//
//   1. Default roots = every `~/.copilot/session-state/<uuid>/{machina-persist,
//      machina-i2}` directory that exists (legacy `machina-i2` stays read-only;
//      `machina-persist` is the canonical write target).
//   2. Override = explicit roots passed to `discoverRunHistory()` OR the
//      `MACHINA_RUN_ROOTS` env var (';' or ',' separated absolute paths).
//   3. A run   = any directory containing `ledger.jsonl`.
//   4. family  = the nearest named container under the root
//                (for `machina-i2/<runid>` the family equals the runid).
//   5. runid   = the ledger's parent dir name.
//   6. machine = sibling `machine.json` if present, else `null` (replay then
//                falls back to the init record's machine_id identity).
//   7. Read errors never throw — each run carries `readError` and a `null`
//      ledger, so the caller can decide (fail-closed in the gate script).
//
// Both `scripts/replay-all.mjs` and `extension.mjs` import this module so the
// canvas and the batch CLI share ONE discovery implementation.

import fs from "node:fs";
import path from "node:path";
import os from "node:os";

// Canonical persist container names written by the machina-driving skill.
export const PERSIST_ROOT_NAMES = ["machina-persist", "machina-i2"];

// MACHINA_RUN_ROOTS="root1;root2" (or ",") — explicit escape hatch used by
// tests and scripted corpora. Returns null when unset.
export function explicitRootsFromEnv() {
  const raw = process.env.MACHINA_RUN_ROOTS;
  if (!raw || !raw.trim()) return null;
  return raw
    .split(/[;,]/)
    .map((s) => s.trim())
    .filter(Boolean)
    .map((p) => path.resolve(p));
}

// Scan $HOME/.copilot/session-state/<uuid>/ for the canonical persist roots.
export function defaultRoots() {
  const sessionBase = path.join(os.homedir(), ".copilot", "session-state");
  const roots = [];
  if (!fs.existsSync(sessionBase)) return roots;
  for (const sesDir of fs.readdirSync(sessionBase, { withFileTypes: true })) {
    if (!sesDir.isDirectory()) continue;
    for (const container of PERSIST_ROOT_NAMES) {
      const p = path.join(sessionBase, sesDir.name, container);
      if (fs.existsSync(p) && fs.statSync(p).isDirectory()) roots.push(p);
    }
  }
  return roots;
}

// Explicit roots (args) > env override > default session-state scan.
export function resolveRunRoots(explicitRoots = null) {
  const roots = explicitRoots ?? explicitRootsFromEnv() ?? defaultRoots();
  return roots.map((p) => path.resolve(p));
}

// Discover run descriptors under the given roots (default: resolveRunRoots()).
// Returns [{ root, family, runid, ledgerPath, machinePath, ledger, machine,
//            readError }] — ledger/machine are parsed, or null on read failure.
export function discoverRunHistory(explicitRoots = null) {
  const roots = resolveRunRoots(explicitRoots);
  const runs = [];
  const walk = (dir, family, root) => {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return; // unreadable dir — skip, never throw
    }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p, family || e.name, root);
      else if (e.name === "ledger.jsonl") {
        const dirPath = path.dirname(p);
        const machinePath = path.join(dirPath, "machine.json");
        const runid = path.basename(dirPath);
        const run = {
          root,
          family: family || runid,
          runid,
          ledgerPath: p,
          machinePath: fs.existsSync(machinePath) ? machinePath : null,
          ledger: null,
          machine: null,
          readError: null,
        };
        try {
          run.ledger = fs
            .readFileSync(p, "utf8")
            .trim()
            .split("\n")
            .filter(Boolean)
            .map((l) => JSON.parse(l));
        } catch (err) {
          run.readError = String(err.message);
        }
        if (run.machinePath) {
          try {
            run.machine = JSON.parse(fs.readFileSync(run.machinePath, "utf8"));
          } catch (err) {
            run.readError = (run.readError ? run.readError + "; " : "") + `machine.json unreadable: ${err.message}`;
          }
        }
        runs.push(run);
      }
    }
  };
  for (const root of roots) {
    if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) continue;
    walk(root, null, root);
  }
  return runs;
}

// Resolve a run reference against discovered runs. Accepts:
//   "<family>/<runid>" (exact family + runid) or a bare "<runid>"
//   (matches any run with that runid; may return >1 — caller decides).
export function resolveRunRef(runs, runRef) {
  const raw = String(runRef || "").trim();
  if (!raw) return [];
  const parts = raw.replace(/[\\/]+/g, "/").split("/").filter(Boolean);
  if (!parts.length) return [];
  const fam = parts.slice(0, -1).join("/");
  const rid = parts[parts.length - 1];
  return runs.filter((r) => (fam ? r.family === fam && r.runid === rid : r.runid === rid));
}

// Convenience: exactly-one match or null/throw helpers.
export function findRun(explicitRoots, runRef) {
  const matches = resolveRunRef(discoverRunHistory(explicitRoots), runRef);
  if (matches.length === 1) return matches[0];
  return null;
}