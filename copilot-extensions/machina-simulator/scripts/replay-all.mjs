// replay-all.mjs — run-inventory gate over every persisted Machina ledger.
// Reads ledger.jsonl (+ machine.json) from the run roots, replays each via
// replayRunLedger, emits a per-run verdict table, and exits 0 iff the full
// green gate holds.
//
// Usage:
//   node scripts/replay-all.mjs [root1 root2 ...]
//
// Discovery uses the shared convention (scripts/discovery.mjs): explicit argv
// roots first, then MACHINA_RUN_ROOTS env (';'- or ','-separated), then the
// default session-state scan
//   C:\Users\<USER>\.copilot\session-state\<session>\machina-persist
//   C:\Users\<USER>\.copilot\session-state\<session>\machina-i2
//
// Exit code: 0 = gate green (all verifiable, 0 mismatch, 0 tampered, 0 read
// errors, and — when MACHINA_EXPECTED_STUCK is set — the expected stuck count),
//            1 = any failure.
//
// The real persisted 21-run corpus has 6 blocked-final (stuck) + 3 mid-phase
// (incomplete) runs; MACHINA_EXPECTED_STUCK=6 is how the real-corpus gate is
// pinned in CI/docs. The script itself does not hard-code a corpus-local count.

import path from "node:path";
import { fileURLToPath } from "node:url";
import { replayRunLedger, replayIntegrityOk } from "../machine-simulator.mjs";
import { discoverRunHistory, resolveRunRoots } from "./discovery.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function pad(s, n) { return String(s ?? "").padEnd(n); }

export async function main(argv = process.argv.slice(2)) {
  const roots = resolveRunRoots(argv.length ? argv : null);
  if (!roots.length) {
    console.error("No run roots found. Pass explicit roots, set MACHINA_RUN_ROOTS, or set up session-state machina-persist/machina-i2.");
    return 1;
  }
  const runs = discoverRunHistory(roots);
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