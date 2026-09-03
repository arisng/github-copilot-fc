// replay-all.mjs — run-inventory gate over every persisted Machina ledger.
// Reads ledger.jsonl (+ machine.json) from the run roots, replays each via
// replayRunLedger, emits a per-run verdict table, and exits 0 iff the full
// green gate holds.
//
// Usage:
//   node scripts/replay-all.mjs [root1 root2 ...]
//
// Defaults scan the session-state persist roots:
//   C:\Users\<USER>\.copilot\session-state\<session>\machina-persist
//   C:\Users\<USER>\.copilot\session-state\<session>\machina-i2
// You may pass explicit roots instead (each a dir containing run dirs or a
// nested family layout).
//
// Exit code: 0 = gate green (all verifiable, 0 mismatch, 0 tampered, 0 read
// errors, and — when MACHINA_EXPECTED_STUCK is set — the expected stuck count),
//            1 = any failure.
//
// The real persisted 21-run corpus has 6 blocked-final (stuck) + 3 mid-phase
// (incomplete) runs; MACHINA_EXPECTED_STUCK=6 is how the real-corpus gate is
// pinned in CI/docs. The script itself does not hard-code a corpus-local count.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import os from "node:os";
import { replayRunLedger, replayIntegrityOk } from "../machine-simulator.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function defaultRoots() {
  // Session folder: $HOME/.copilot/session-state/<uuid> — scan all sessions for
  // machina-persist / machina-i2 run containers.
  const roots = [];
  const sessionBase = path.join(os.homedir(), ".copilot", "session-state");
  for (const sesDir of fs.existsSync(sessionBase) ? fs.readdirSync(sessionBase, { withFileTypes: true }) : []) {
    if (!sesDir.isDirectory()) continue;
    for (const container of ["machina-persist", "machina-i2"]) {
      const p = path.join(sessionBase, sesDir.name, container);
      if (fs.existsSync(p) && fs.statSync(p).isDirectory()) roots.push(p);
    }
  }
  return roots;
}

function collect(runRoots) {
  const runs = [];
  const walk = (dir, family) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p, family || e.name);
      else if (e.name === "ledger.jsonl") {
        const dirPath = path.dirname(p);
        const machinePath = path.join(dirPath, "machine.json");
        let ledger = [];
        try {
          ledger = fs
            .readFileSync(p, "utf8")
            .trim()
            .split("\n")
            .filter(Boolean)
            .map((l) => JSON.parse(l));
        } catch (err) {
          runs.push({ family, runid: path.basename(dirPath), machine: null, ledger: null, readError: String(err.message) });
          continue;
        }
        let machine = null;
        try { machine = JSON.parse(fs.readFileSync(machinePath, "utf8")); } catch {}
        runs.push({ family, runid: path.basename(dirPath), machine, ledger });
      }
    }
  };
  for (const root of runRoots) walk(root, null);
  return runs;
}

function pad(s, n) { return String(s ?? "").padEnd(n); }

export async function main(argv = process.argv.slice(2)) {
  const roots = argv.length ? argv.map((p) => path.resolve(p)) : defaultRoots();
  if (!roots.length) {
    console.error("No run roots found. Pass explicit roots or set up session-state machina-persist/machina-i2.");
    return 1;
  }
  const runs = collect(roots);
  if (!runs.length) {
    console.error("No ledgers found in roots:", roots.join(", "));
    return 1;
  }

  let verifiable = 0, tampered = 0, readErrors = 0, stuck = 0, incomplete = 0, aborted = 0, complete = 0;
  let guardMismatchTotal = 0;
  const bad = [];
  const rows = [];

  console.log(pad("family", 18), pad("runid", 14), pad("machine", 22), pad("verdict", 12), pad("terminal", 10), "blk  mismatch  state");
  for (const r of runs) {
    if (r.ledger == null) {
      readErrors++;
      bad.push(`${r.family}/${r.runid}: unreadable (${r.readError})`);
      rows.push({ family: r.family, runid: r.runid, machine: "-", verdict: "unreadable", terminal: "-", blocked: "-", mismatch: "-", state: "-" });
      continue;
    }
    const rep = replayRunLedger(r.machine, r.ledger, { diffReeval: true });
    const mismatch = rep.trace.filter((e) => e.guardMismatch).length;
    guardMismatchTotal += mismatch;
    const integ = rep.integrity.ok ? "verifiable" : `tampered@${rep.integrity.indexOfFirstFailure}`;
    if (rep.integrity.ok) verifiable++; else { tampered++; bad.push(`${r.family}/${r.runid}: ${integ}`); }
    if (rep.terminal === "stuck") stuck++;
    else if (rep.terminal === "incomplete") incomplete++;
    else if (rep.terminal === "aborted") aborted++;
    else complete++;
    rows.push({ family: r.family, runid: r.runid, machine: r.machine?.id ?? "-", verdict: integ, terminal: rep.terminal, blocked: rep.blockedCount, mismatch, state: rep.state ?? "-" });
    console.log(
      pad(r.family, 18), pad(r.runid, 14), pad(r.machine?.id ?? "?", 22), pad(integ, 12), pad(rep.terminal, 10),
      String(rep.blockedCount).padEnd(5), String(mismatch).padEnd(9), rep.state ?? "-",
    );
  }

  console.log("");
  console.log(`TOTAL=${runs.length} verifiable=${verifiable} tampered=${tampered} readErrors=${readErrors}`);
  console.log(`dispositions: complete=${complete} stuck=${stuck} incomplete=${incomplete} aborted=${aborted}`);
  console.log(`re-eval guardMismatchTotal=${guardMismatchTotal}`);

  // A-6 gate: ALL verifiable + 0 mismatch + 0 tampered + 0 readErrors.
    // expectedStuck is an optional corpus assertion. The real 21-run corpus has
    // exactly 6 blocked-final runs; tests set MACHINA_EXPECTED_STUCK to match
    // their synthetic fixtures. When unset, the gate verifies integrity only and
    // reports dispositions (it does NOT bake in a machine-local count).
    const expectedStuck =
      process.env.MACHINA_EXPECTED_STUCK !== undefined
        ? Number(process.env.MACHINA_EXPECTED_STUCK)
        : null;
    const stuckMatches = expectedStuck === null || stuck === expectedStuck;

    const gate =
      verifiable === runs.length &&
      guardMismatchTotal === 0 &&
      tampered === 0 &&
      readErrors === 0 &&
      stuckMatches;

    if (!gate) {
      console.error("GATE FAILED");
      if (expectedStuck !== null && !stuckMatches) {
        console.error(`  expected stuck=${expectedStuck} but corpus has stuck=${stuck}`);
      }
      for (const b of bad) console.error("  " + b);
      // Print the full inventory as JSON for machine-readable consumption.
      console.log(JSON.stringify({ ok: false, total: runs.length, verifiable, tampered, stuck, incomplete, aborted, readErrors, guardMismatchTotal, rows }, null, 2));
      return 1;
    }
    console.log(`GATE PASSED: ${verifiable}/${runs.length} verifiable · ${stuck} stuck · 0 mismatch`);
    console.log(JSON.stringify({ ok: true, total: runs.length, verifiable, tampered, stuck, incomplete, aborted, readErrors, guardMismatchTotal, rows }, null, 2));
    return 0;
  }

// Direct execution: node scripts/replay-all.mjs
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const code = await main();
  process.exit(code);
}