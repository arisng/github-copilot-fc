// replay-check.mjs — eval-side harness: replay ONE machina run dir through the
// ACTUAL machina-simulator engine and print the trust verdicts as strict JSON.
//
// The engine at copilot-extensions/machina-simulator/machine-simulator.mjs is
// imported by absolute repo path (never modified by this suite). This is the
// same replay computation the `/machina-simulator` canvas renders as its
// ✓ verified / TAMPERED badge, terminal disposition, blocked records, nested
// badges and HASH MISMATCH — executed headlessly so the grader can assert it.
//
// Usage:
//   node replay-check.mjs <run-dir>
//
// stdout: one strict-JSON object:
//   { ok, error?, runDir, machineId, ledgerLength, integrity:{verdict,ok,indexOfFirstFailure,failureKind},
//     machineHashOk, machineMatch, terminal, state, blockedCount, guardMismatchCount,
//     childRuns[], trace:[{index,type,event,from,to,note,reason,evidence,child_run,guardMismatch}] }
//
// Exit: 0 when the replay ran (even if it reports tampered — that is a verdict,
// not a harness error); non-zero only on hard IO/harness errors.

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// scripts/ -> repo root (../../../copilot-extensions/...)
const ENGINE = path.resolve(
  __dirname,
  "..",
  "..",
  "..",
  "copilot-extensions",
  "machina-simulator",
  "machine-simulator.mjs",
);

const { replayRunLedger } = await import(pathToFileURL(ENGINE).href);

function die(msg) {
  console.log(JSON.stringify({ ok: false, error: msg }));
  process.exit(1);
}

export function replayRunDir(runDir) {
  const ledgerPath = path.join(runDir, "ledger.jsonl");
  const machinePath = path.join(runDir, "machine.json");
  if (!fs.existsSync(ledgerPath)) throw new Error(`no ledger.jsonl in ${runDir}`);
  const ledger = fs
    .readFileSync(ledgerPath, "utf8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l));
  const machineJson = fs.existsSync(machinePath) ? fs.readFileSync(machinePath, "utf8") : null;
  const machine = machineJson ? JSON.parse(machineJson) : null;
  const rep = replayRunLedger(machine, ledger, { diffReeval: true, machineJson });
  return { ledger, machineJson, rep };
}

function main(argv) {
  const runDir = argv[2];
  if (!runDir) die("usage: node replay-check.mjs <run-dir>");
  if (!fs.existsSync(path.join(runDir, "ledger.jsonl"))) die(`no ledger.jsonl in ${runDir}`);

  let ledger, machineJson, rep;
  try {
    ({ ledger, machineJson, rep } = replayRunDir(runDir));
  } catch (err) {
    die(`replay harness error: ${err.message}`);
  }

  const trace = (rep.trace || []).map((e) => {
    const o = { index: e.index, type: e.type };
    for (const k of ["event", "from", "to", "note", "reason", "evidence", "child_run", "guardMismatch", "reevalTo"]) {
      if (e[k] !== undefined) o[k] = e[k];
    }
    return o;
  });

  const childRuns = [...new Set((rep.trace || [])
    .map((e) => e.child_run)
    .filter((c) => c != null && c !== ""))];

  console.log(
    JSON.stringify({
      ok: true,
      runDir,
      machineId: rep.machineId,
      ledgerMachineId: rep.ledgerMachineId,
      ledgerLength: ledger.length,
      integrity: rep.integrity,
      machineHashOk: rep.machineHashOk,
      machineMatch: rep.machineMatch,
      terminal: rep.terminal,
      state: rep.state,
      blockedCount: rep.blockedCount,
      guardMismatchCount: rep.trace.filter((e) => e.guardMismatch).length,
      childRuns,
      trace,
    }),
  );
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv);
}