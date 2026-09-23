// Live-watch test — Round-2 contract (plan §1 detect-rules + r2-live-api).
// Exercises scripts/live-watcher.mjs (createLiveWatcher via manual
// tick()/start()/stop(), classifyRun as a direct unit) and the extension's
// GET /live + GET /live-events routes on the real HTTP server.
// Run: node --experimental-loader ./test/sdk-stub-loader.mjs test/live.test.mjs
//
// Round-2 membership (supersedes Round-1's "never clock-migrated"):
//   * Every row carries an EXPLICIT `live: boolean` (15 fields total).
//   * R1 — report-less final state: live only while age < GRACE_MS (30min);
//     after that live:false + terminal from report-mapping else replay
//     verbatim (the e2ae pattern → {live:false, terminal:"complete"}).
//   * R2 — non-final, report-less, abort-less: age >= STALE_CAP_MS (24h) →
//     live:false with terminal staying null (stale marker = that exact pair).
//   * abort → live:false + aborted (immediate). Terminal report (result ≠
//     IN_PROGRESS && !reportStale) → live:false + mapped terminal (P4).
//     EVERYTHING else — no report, an IN_PROGRESS report, or a reportStale
//     (growth after a terminal report) — is a CANDIDATE that flows through
//     the same clocks as no-report runs: machine-gated final state → live
//     while age < GRACE_MS (else grace → terminal precedence, so an aged
//     IN_PROGRESS report still resolves to its replay terminal); mid-state →
//     live while age < STALE_CAP_MS (else stale: live:false + terminal:null,
//     silent). Fresh IN_PROGRESS therefore stays live (mid < 24h / final <
//     grace) while the real f87fb459bce7 pattern (IN_PROGRESS, final state,
//     8.6d old) is NOT live. reportStale re-lives through these clocks too.
//   * onFinal: at most once per run, only observed live→terminal (report /
//     abort / grace expiry); born-terminal-old and born-stale first sightings
//     are silent; live→stale (R2) NEVER fires onFinal.
//   * GET /live returns live-only rows as {ok, rows} — NO scopedTo
//     (Round-2 decoupling; /runs keeps its own scoping contract).
//
// Audit #9 mechanics (plan §4 — MANDATORY):
//   * MACHINA_SIM_PORT="0" is set BEFORE the dynamic import of extension.mjs
//     (ephemeral port — never collide with a live 7750 simulator and never
//     silently degrade to a secondary against the user's session).
//   * MACHINA_STANDALONE is NEVER set here (plan trap: primary runs a
//     keep-alive interval → suite hang; secondary process.exit(0) → death).
//   * Runs under test/sdk-stub-loader.mjs — package.json declares no deps;
//     the loader resolves @github/copilot-sdk/extension to the committed stub.
//   * Run roots isolated via MACHINA_RUN_ROOTS (saved/restored in after()).
//   * Watcher cadence: unit tests drive tick() manually and any start() is
//     paired with stop() in finally — the real ~5s interval is never awaited
//     (the one route-driven tick below is synchronous inside GET /live).
//   * The SSE response stream is aborted in finally — an open socket would
//     keep the event loop alive and hang the npm test chain.
//
// SSE approach (documented choice): extension.mjs keeps `liveWatcher`
// module-private, but GET /live calls liveWatcher.tick() synchronously and
// tick() fires onDelta → broadcastLive whenever any row changed. So the test
// opens /live-events, primes via GET /live, appends a ledger record, then
// issues a SECOND GET /live — that tick observes the growth and broadcasts a
// `machina-live` / live-update frame to the connected client deterministically
// (no waiting on the real 5s cadence), then aborts the stream.
//
// Fixture clocks: membership is clock-aware, so fixture timestamps default to
// a few minutes OLD-relative-to-now (never a fixed historic date) — a fixture
// written with Round-1's fixed 2026-09-03 stamps would already be past both
// thresholds on any later run date and never classify live.

import test, { after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";

// Engine canonicalizer + chain hasher so synthetic ledgers replay verifiably
// (same recipe as canvas.test.mjs's writePersistedRun fixture).
import { canonicalizeMachinaText, sha256Hex } from "../machine-simulator.mjs";
import { GRACE_MS, STALE_CAP_MS, classifyRun, createLiveWatcher } from "../scripts/live-watcher.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
void __dirname;

// --- audit #9: ephemeral port BEFORE any import of extension.mjs ----------
process.env.MACHINA_SIM_PORT = "0";

// --- synthetic fixture helpers --------------------------------------------

const MACHINE_ID = "pm-release-notes";
const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

// Fixed clock for exact GRACE_MS / STALE_CAP_MS boundary math in classifyRun
// (which accepts opts.now — no wall-clock drift at the edge).
const T0 = "2026-06-01T00:00:00Z";
const T0_MS = Date.parse(T0);

// Relative timestamp: `ms` before now. Default fixture freshness — well under
// GRACE_MS so a freshly written fixture classifies live when the tick runs.
const isoAgo = (ms) => new Date(Date.now() - ms).toISOString();

// Exactly the 15 row fields the Round-2 watcher contract documents (plan §1:
// Round-1's 14 fields + explicit `live` boolean).
const ROW_KEYS = [
  "root", "family", "runid", "runRef",
  "machineId", "machineName", "session", "currentState",
  "records", "lastActivity", "advisory", "childRuns",
  "machineMissing", "terminal", "live",
];

function rec(payload, prev = null) {
  return { prev_hash: prev, payload, hash: sha256Hex(canonicalizeMachinaText(JSON.stringify(payload))) };
}

function machineJsonFor(machineId = MACHINE_ID) {
  return JSON.stringify(
    { id: machineId, initial: "a", states: { a: { on: { GO: { target: "b" } } }, b: { type: "final" } } },
    null,
    2,
  );
}

function initRec(machineJson, machineId, timestamp, prev = null) {
  return rec({
    type: "init",
    machine_id: machineId,
    spec_version: "3.0.0",
    scenario: "default",
    state: "a",
    context: {},
    machine_dir: "<run-dir>",
    machine_sha256: sha256Hex(canonicalizeMachinaText(machineJson)),
    tool_hashes: {},
    timestamp,
  }, prev);
}

function goRec(prevHash, timestamp) {
  return rec({
    type: "transition",
    event: "GO",
    from: "a",
    to: "b",
    guard: null,
    evidence: [],
    exit_actions: [],
    transition_actions: [],
    entry_actions: [],
    context_after: {},
    note: "ok",
    child_run: null,
    timestamp,
  }, prevHash);
}

function writeReport(runDir, runid, result, finalHash) {
  fs.writeFileSync(
    path.join(runDir, "report.json"),
    JSON.stringify({
      schema: "machina.report.v1",
      run_id: runid,
      machine_id: MACHINE_ID,
      result,
      final_state: "b",
      path: ["a", "b"],
      events: 1,
      redirects: 0,
      blocked_events: 0,
      evidence: { passed: 0, failed: 0 },
      context_snapshot: {},
      agent_notes: [],
      nested_runs: [],
      ledger_final_hash: finalHash ?? null,
    }, null, 2),
    "utf8",
  );
}

// Create <root>/<family>/<runid>/{ledger.jsonl[,machine.json[,report.json]]}.
// Defaults: FULL chain (init + transition → final state "b") with timestamps
// 5 minutes old → live under both R1 grace and R2 cap at any sane run date.
// opts: machine:false → ledger-only run (machine-missing); initOnly:true →
// single init record (current state stays "a" = mid-state); report → born
// with report.json (result); machineJson/machineId → custom machine (advisory
// fixtures); initTimestamp/goTimestamp → age fixtures. Re-calling writeRun on
// the same run dir REWRITES the ledger (fresh hashes) — used to observe
// grace-expiry / staleness transitions between manual ticks.
function writeRun(root, family, runid, opts = {}) {
  const runDir = path.join(root, family, runid);
  fs.mkdirSync(runDir, { recursive: true });
  const machineJson = opts.machineJson ?? machineJsonFor(opts.machineId ?? MACHINE_ID);
  const machineId = opts.machineId ?? MACHINE_ID;
  const initTs = opts.initTimestamp ?? isoAgo(5 * MIN);
  const goTs = opts.goTimestamp ?? initTs;
  const r1 = initRec(machineJson, machineId, initTs);
  const records = opts.initOnly ? [r1] : [r1, goRec(r1.hash, goTs)];
  const ledgerPath = path.join(runDir, "ledger.jsonl");
  fs.writeFileSync(ledgerPath, records.map((r) => JSON.stringify(r)).join("\n") + "\n", "utf8");
  if (opts.machine !== false) fs.writeFileSync(path.join(runDir, "machine.json"), machineJson, "utf8");
  if (opts.report) writeReport(runDir, runid, opts.report, records[records.length - 1].hash);
  return runDir;
}

function ledgerRecords(runDir) {
  return fs.readFileSync(path.join(runDir, "ledger.jsonl"), "utf8")
    .split(/\r?\n/).filter((l) => l.trim()).map((l) => JSON.parse(l));
}

// Chain a new record onto an existing ledger; returns the new record count.
function appendLedgerRecord(runDir, payloadBuilder) {
  const recs = ledgerRecords(runDir);
  const prev = recs.length ? recs[recs.length - 1].hash : null;
  const r = rec(payloadBuilder(prev), prev);
  fs.appendFileSync(path.join(runDir, "ledger.jsonl"), JSON.stringify(r) + "\n", "utf8");
  return recs.length + 1;
}

// Fresh by default — a growth record with an ancient timestamp would
// retroactively age lastActivity past STALE_CAP_MS / GRACE_MS and flip the
// very liveness the surrounding assertions check.
function blockedPayload(timestamp = isoAgo(1 * MIN)) {
  return (prev) => ({
    type: "blocked",
    event: "GO",
    from: "b",
    reason: "evidence",
    detail: "synthetic gate not met",
    evidence: [{ checker: "noop.py", result: "missing", ok: false }],
    note: "negative gate proof",
    timestamp,
    prev_hash: prev, // harmless payload field; the real chain lives on the record
  });
}

// Abort is rule 1 — clock-independent (checked before any age rule), so its
// timestamp never affects the aborted verdict; fresh keeps row ages sane.
function abortPayload() {
  return {
    type: "abort",
    state: "b",
    reason: "operator cancelled",
    timestamp: isoAgo(1 * MIN),
  };
}

// --- shared run roots for the EXTENSION's watcher (fixed at import) --------
// Structured as <tmp>/session-state/<uuid>/machina-runs so deriveSession
// reports "sessA"/"sessB" the same way production roots do.
const envTmp = fs.mkdtempSync(path.join(os.tmpdir(), "machina-live-env-"));
const sessA = path.join(envTmp, "session-state", "sessA");
const sessB = path.join(envTmp, "session-state", "sessB");
const rootA = path.join(sessA, "machina-runs");
const rootB = path.join(sessB, "machina-runs");

// /live is LIVE-ONLY (Round-2): the shared fixture set carries one fresh live
// fixture per session plus deliberately NOT-live fixtures that must be
// excluded from the feed (stale mid-state, born-terminal report, and the
// e2ae report-less-final pattern).
writeRun(rootA, "i5-releasenotes", "liveRunA");                        // fresh final → LIVE (sessA)
writeRun(rootA, "i5-releasenotes", "sseRun");                          // fresh final → LIVE (SSE mutation)
writeRun(rootA, "i5-releasenotes", "staleRunA", {                      // 20d mid-state → R2 stale
  initOnly: true,
  initTimestamp: isoAgo(20 * DAY),
});
writeRun(rootA, "i5-releasenotes", "terminalRunA", { report: "SUCCESS" }); // born terminal (P4) → not live
writeRun(rootA, "i5-releasenotes", "oldFinalRunA", {                   // e2ae: final, no report, 8d old
  initTimestamp: isoAgo(8 * DAY),
  goTimestamp: isoAgo(8 * DAY),
});
writeRun(rootB, "i1-triage", "liveRunB");                              // fresh final → LIVE (sessB)

const prevRunRoots = process.env.MACHINA_RUN_ROOTS;
process.env.MACHINA_RUN_ROOTS = [rootA, rootB].join(";");

// The extension registers its HTTP server at import time; the stub loader
// resolves @github/copilot-sdk/extension to test/stubs/copilot-sdk-extension.mjs.
await import("../extension.mjs");
const canvas = globalThis.__machinaTestSession.__opts.canvases[0];
assert.ok(canvas, "extension must register the machine-simulator canvas");
const probe = await canvas.open({ instanceId: "live-port-probe" });
const base = probe.url.replace(/\?.*$/, ""); // http://127.0.0.1:<ephemeral>

// Per-unit-test temp roots (NOT in MACHINA_RUN_ROOTS — the extension's watcher
// root list is fixed at import and must not see these).
const unitTmpDirs = [];
function makeUnitRoot() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "machina-live-unit-"));
  unitTmpDirs.push(tmp);
  const root = path.join(tmp, "machina-runs");
  fs.mkdirSync(root, { recursive: true });
  return root;
}

after(() => {
  if (prevRunRoots === undefined) delete process.env.MACHINA_RUN_ROOTS;
  else process.env.MACHINA_RUN_ROOTS = prevRunRoots;
  fs.rmSync(envTmp, { recursive: true, force: true });
  for (const d of unitTmpDirs) fs.rmSync(d, { recursive: true, force: true });
});

// ===========================================================================
// Watcher / classifyRun detection — the core Round-2 regression suite
// ===========================================================================

test("watcher: e2ae pattern (final state, no report, 8 days old) → live:false/terminal:complete, onFinal silent", () => {
  const root = makeUnitRoot();
  const t8d = isoAgo(8 * DAY);
  writeRun(root, "i5", "runE2ae", { initTimestamp: t8d, goTimestamp: t8d });
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    let rows = w.tick();
    let row = rows.find((r) => r.runid === "runE2ae");
    assert.equal(rows.length, 1);
    assert.equal(row.currentState, "b", "replay reaches the machine-gated final state");
    assert.equal(row.records, 2);
    assert.equal(row.lastActivity, t8d, "age basis is the newest ledger timestamp");
    assert.equal(row.live, false, "R1 grace (30min) expired on an 8-day-old final state");
    assert.equal(row.terminal, "complete", "report-less final → replay terminal verbatim (P1 fix)");
    assert.equal(finals.length, 0, "born-terminal-old first sighting is primed SILENTLY (never live in this watcher's view)");
    rows = w.tick();
    row = rows.find((r) => r.runid === "runE2ae");
    assert.equal(finals.length, 0, "it can never fire later either — it was never live here");
    assert.equal(row.live, false);
    assert.equal(row.terminal, "complete");
  } finally {
    w.stop();
  }
});

test("watcher: born-stale mid-state run (20 days old) → live:false/terminal:null, onFinal silent", () => {
  const root = makeUnitRoot();
  writeRun(root, "i5", "runBornStale", { initOnly: true, initTimestamp: isoAgo(20 * DAY) });
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    let rows = w.tick();
    let row = rows.find((r) => r.runid === "runBornStale");
    assert.ok(row, "stale runs stay in the inventory (RUNS tab still probes them)");
    assert.equal(row.currentState, "a", "mid-state — never reached the final state");
    assert.equal(row.live, false, "R2 staleness cap: 20 days >= 24h → abandoned");
    assert.equal(row.terminal, null, "stale marker is exactly live:false + terminal:null");
    assert.equal(finals.length, 0, "born-stale first sighting never fires onFinal");
    rows = w.tick();
    row = rows.find((r) => r.runid === "runBornStale");
    assert.equal(row.live, false);
    assert.equal(row.terminal, null);
    assert.equal(finals.length, 0);
  } finally {
    w.stop();
  }
});

test("watcher: fresh final-state run (10 min old) → live 15-field row + initial onDelta (start/stop idempotent)", () => {
  const root = makeUnitRoot();
  const t10 = isoAgo(10 * MIN);
  writeRun(root, "i5", "runFresh", { initTimestamp: t10 });
  const deltas = [];
  const finals = [];
  const w = createLiveWatcher({
    roots: [root],
    intervalMs: 600000, // never fires in-process; cadence is driven by tick()
    onDelta: (rows) => { deltas.push(rows); },
    onFinal: (row) => { finals.push(row); },
  });
  try {
    w.start(); // idempotent-guard exercised below; interval is unref'd
    w.start();
    const rows = w.tick();
    assert.equal(rows.length, 1);
    const row = rows[0];
    assert.deepEqual(Object.keys(row).sort(), [...ROW_KEYS].sort(), "row must carry exactly the 15-field Round-2 shape");
    assert.equal(typeof row.live, "boolean", "`live` is an EXPLICIT boolean — consumers never infer it from terminal");
    assert.equal(row.runRef, "i5/runFresh");
    assert.equal(row.family, "i5");
    assert.equal(row.runid, "runFresh");
    assert.equal(row.machineId, MACHINE_ID);
    assert.equal(row.machineName, null);
    assert.equal(row.machineMissing, false);
    assert.equal(row.records, 2);
    assert.equal(row.currentState, "b");
    assert.equal(row.lastActivity, t10);
    assert.equal(row.live, true, "final state within GRACE_MS → live, awaiting the driver's report");
    assert.equal(row.terminal, null, "within grace the terminal stays null (report may still land)");
    assert.equal(row.advisory, null, "final current state never carries the no-exits advisory");
    assert.deepEqual(row.childRuns, []);
    // First productive tick always fires onDelta with the FULL snapshot.
    assert.equal(deltas.length, 1);
    assert.deepEqual(deltas[0], rows);
    assert.equal(finals.length, 0, "a live run must never emit onFinal");
    // A no-change tick must not fire another delta (snapshot-diff contract).
    w.tick();
    assert.equal(deltas.length, 1);
    assert.equal(finals.length, 0);
  } finally {
    w.stop();
    w.stop(); // idempotent
  }
});

test("watcher: mid-state run 3 hours old stays live (under the 24h cap)", () => {
  const root = makeUnitRoot();
  writeRun(root, "i5", "run3h", { initOnly: true, initTimestamp: isoAgo(3 * HOUR) });
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    const rows = w.tick();
    const row = rows.find((r) => r.runid === "run3h");
    assert.equal(row.currentState, "a");
    assert.equal(row.live, true, "mid-state under STALE_CAP_MS (24h) stays live");
    assert.equal(row.terminal, null);
    assert.equal(finals.length, 0);
  } finally {
    w.stop();
  }
});

test("watcher: mid-state run 25 hours old → live:false/terminal:null (R2 stale)", () => {
  const root = makeUnitRoot();
  writeRun(root, "i5", "run25h", { initOnly: true, initTimestamp: isoAgo(25 * HOUR) });
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    const rows = w.tick();
    const row = rows.find((r) => r.runid === "run25h");
    assert.equal(row.currentState, "a", "still mid-state — abandoned, not terminal");
    assert.equal(row.live, false, "age 25h >= STALE_CAP_MS → not live");
    assert.equal(row.terminal, null, "live→stale keeps terminal null (that pair IS the stale marker)");
    assert.equal(finals.length, 0, "live→stale is not a terminal disposition — never onFinal");
    assert.ok(rows.length >= 1, "the row remains in the inventory");
  } finally {
    w.stop();
  }
});

test("classifyRun: exact GRACE_MS / STALE_CAP_MS boundary edges + threshold sanity", () => {
  const root = makeUnitRoot();
  const midDir = writeRun(root, "i5", "runMidEdge", { initOnly: true, initTimestamp: T0 });
  const finDir = writeRun(root, "i5", "runFinEdge", { initTimestamp: T0, goTimestamp: T0 });
  const classify = (runDir, now) => classifyRun({
    ledgerPath: path.join(runDir, "ledger.jsonl"),
    machinePath: path.join(runDir, "machine.json"),
    reportPath: path.join(runDir, "report.json"),
    now, // deterministic clock — exact-edge assertions without sleeping
  });

  // Threshold sanity — user-set Round-2 values, referenced by name.
  assert.equal(GRACE_MS, 30 * 60 * 1000, "R1 grace is 30 minutes");
  assert.equal(STALE_CAP_MS, 24 * 60 * 60 * 1000, "R2 staleness cap is 24 hours");

  // R2 cap edge (mid-state): just under → live; exactly at → stale.
  const midUnder = classify(midDir, T0_MS + STALE_CAP_MS - 1);
  assert.equal(midUnder.live, true, "age = cap - 1ms is still live");
  assert.equal(midUnder.terminal, null);
  const midAt = classify(midDir, T0_MS + STALE_CAP_MS);
  assert.equal(midAt.live, false, "age >= STALE_CAP_MS → stale (the -1ms/+0ms boundary)");
  assert.equal(midAt.terminal, null, "stale class keeps terminal null by contract");

  // R1 grace edge (report-less final state): just under → live; exactly at →
  // grace-expired with the replay terminal verbatim (the e2ae verdict).
  const finUnder = classify(finDir, T0_MS + GRACE_MS - 1);
  assert.equal(finUnder.live, true, "final state just under the grace window awaits its report");
  assert.equal(finUnder.terminal, null);
  const finAt = classify(finDir, T0_MS + GRACE_MS);
  assert.equal(finAt.live, false, "age >= GRACE_MS → grace expired");
  assert.equal(finAt.terminal, "complete", "replay terminal verbatim once grace expires");
});

test("classifyRun: report SUCCESS maps terminal complete with precedence over a stuck replay", () => {
  const root = makeUnitRoot();
  const runDir = writeRun(root, "i5", "runMapped");
  // Make the replay say "stuck" (last record blocked), then land SUCCESS:
  // report.result is AUTHORITATIVE — the row must never render replay's stuck.
  appendLedgerRecord(runDir, blockedPayload());
  writeReport(runDir, "runMapped", "SUCCESS", ledgerRecords(runDir).at(-1).hash);
  const row = classifyRun({
    ledgerPath: path.join(runDir, "ledger.jsonl"),
    machinePath: path.join(runDir, "machine.json"),
    reportPath: path.join(runDir, "report.json"),
    // no `root` — exercises the pure deriveRoot/deriveFamily fallback
  });
  assert.deepEqual(Object.keys(row).sort(), [...ROW_KEYS].sort());
  assert.equal(row.live, false, "P4: a terminal report ends liveness immediately (no grace)");
  assert.equal(row.terminal, "complete", "report mapping (SUCCESS→complete) wins over replay's stuck");
});

test("watcher: IN_PROGRESS is not a liveness short-circuit — fresh final (< grace) and fresh mid (< cap) stay live", () => {
  const root = makeUnitRoot();
  const tFresh = isoAgo(5 * MIN);
  // Born WITH IN_PROGRESS reports on both state shapes — under the amended
  // flow the report grants nothing; the clocks alone decide liveness.
  writeRun(root, "i5", "runWipFinal", { initTimestamp: tFresh, report: "IN_PROGRESS" });
  writeRun(root, "i5", "runWipMid", { initOnly: true, initTimestamp: tFresh, report: "IN_PROGRESS" });
  // Late-report fixture: no report at prime time, written afterwards.
  const lateDir = writeRun(root, "i5", "runWipLate", { initTimestamp: tFresh });
  const deltas = [];
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: (r) => deltas.push(r), onFinal: (r) => finals.push(r) });
  try {
    const rows = w.tick();
    assert.equal(deltas.length, 1, "initial snapshot fires exactly one onDelta");

    const fin = rows.find((r) => r.runid === "runWipFinal");
    assert.equal(fin.currentState, "b", "final state");
    assert.equal(fin.live, true, "IN_PROGRESS + fresh final-state → within GRACE_MS → live");
    assert.equal(fin.terminal, null, "protocol-sanctioned mid-run report must not terminate the run");
    assert.ok(Date.now() - Date.parse(fin.lastActivity) < GRACE_MS, "the fixture's age really is inside the grace window (age matters)");

    const mid = rows.find((r) => r.runid === "runWipMid");
    assert.equal(mid.currentState, "a", "mid-state");
    assert.equal(mid.live, true, "IN_PROGRESS + fresh mid-state → under STALE_CAP_MS → live");
    assert.equal(mid.terminal, null);
    assert.ok(Date.now() - Date.parse(mid.lastActivity) < STALE_CAP_MS, "the fixture's age really is under the 24h cap");

    assert.equal(finals.length, 0, "IN_PROGRESS must never fire onFinal");

    // A mid-run report written AFTER the prime must not change the row →
    // no new delta, no final (Round-1 row-stability check, still valid).
    writeReport(lateDir, "runWipLate", "IN_PROGRESS", ledgerRecords(lateDir).at(-1).hash);
    const after = w.tick();
    const late = after.find((r) => r.runid === "runWipLate");
    assert.equal(late.live, true, "late IN_PROGRESS on a fresh final run stays live via the grace clock");
    assert.equal(late.terminal, null, "IN_PROGRESS never maps a terminal");
    assert.equal(finals.length, 0, "IN_PROGRESS report must not fire onFinal");
    assert.equal(deltas.length, 1, "the report alone leaves the row JSON unchanged → no new delta");
  } finally {
    w.stop();
  }
});

test("watcher: IN_PROGRESS report, final state, 8.6 days old → live:false/terminal:complete (f87fb459bce7 pattern)", () => {
  const root = makeUnitRoot();
  const tOld = isoAgo(Math.round(8.6 * DAY));
  writeRun(root, "i5", "runWipOldFinal", { initTimestamp: tOld, goTimestamp: tOld, report: "IN_PROGRESS" });
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    let rows = w.tick();
    let row = rows.find((r) => r.runid === "runWipOldFinal");
    assert.equal(row.currentState, "b", "machine-gated final state reached");
    assert.equal(row.live, false, "IN_PROGRESS does NOT short-circuit to live — the grace clock decides");
    assert.equal(row.terminal, "complete", "grace → terminal precedence: IN_PROGRESS has no terminal mapping → replay terminal verbatim");
    assert.equal(finals.length, 0, "born-past-grace first sighting is primed silently");
    rows = w.tick();
    row = rows.find((r) => r.runid === "runWipOldFinal");
    assert.equal(row.live, false, "still not live on every subsequent tick");
    assert.equal(row.terminal, "complete");
    assert.equal(finals.length, 0, "it can never fire later — it was never live in this watcher's view");
  } finally {
    w.stop();
  }
});

test("watcher: IN_PROGRESS report, mid-state, 25h+ old → live:false/terminal:null (stale, silent)", () => {
  const root = makeUnitRoot();
  writeRun(root, "i5", "runWipOldMid", { initOnly: true, initTimestamp: isoAgo(25 * HOUR), report: "IN_PROGRESS" });
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    const rows = w.tick();
    const row = rows.find((r) => r.runid === "runWipOldMid");
    assert.equal(row.currentState, "a", "still mid-state");
    assert.equal(row.live, false, "IN_PROGRESS + mid-state 25h+ old → STALE_CAP_MS decides, not the report");
    assert.equal(row.terminal, null, "stale marker is exactly live:false + terminal:null");
    assert.equal(finals.length, 0, "stale is never a terminal disposition — never onFinal");
    assert.ok(rows.length >= 1, "the stale row stays in the inventory");
  } finally {
    w.stop();
  }
});

test("watcher: abort record ends a previously-live run as aborted (onFinal once, before onDelta)", () => {
  const root = makeUnitRoot();
  const runDir = writeRun(root, "i5", "runAbort");
  const log = []; // callback order matters: onFinal fires BEFORE that tick's onDelta
  const finals = [];
  const w = createLiveWatcher({
    roots: [root],
    onDelta: () => log.push("delta"),
    onFinal: (row) => { log.push("final"); finals.push(row); },
  });
  try {
    w.tick(); // prime LIVE
    assert.deepEqual(log, ["delta"]);

    const count = appendLedgerRecord(runDir, () => abortPayload());
    assert.equal(count, 3);

    const rows = w.tick();
    const row = rows.find((r) => r.runid === "runAbort");
    assert.equal(row.live, false, "P3: abort record ends liveness immediately");
    assert.equal(row.terminal, "aborted", "payload.type abort → terminal aborted");
    assert.equal(finals.length, 1, "abort must fire onFinal exactly once");
    assert.equal(finals[0].terminal, "aborted");
    assert.deepEqual(log, ["delta", "final", "delta"], "onFinal must precede the same tick's onDelta");

    w.tick(); // no further transitions
    assert.equal(finals.length, 1, "onFinal fires at most once per run");
  } finally {
    w.stop();
  }
});

test("watcher: terminal report on a previously-live run fires onFinal exactly once (report mapping)", () => {
  const root = makeUnitRoot();
  const runDir = writeRun(root, "i5", "runDone");
  const log = []; // callback order matters: onFinal fires BEFORE that tick's onDelta
  const finals = [];
  const w = createLiveWatcher({
    roots: [root],
    onDelta: () => log.push("delta"),
    onFinal: (row) => { log.push("final"); finals.push(row); },
  });
  try {
    w.tick(); // prime LIVE
    assert.equal(log.length, 1);
    assert.deepEqual(log, ["delta"]);

    writeReport(runDir, "runDone", "SUCCESS", ledgerRecords(runDir).at(-1).hash);
    const rows = w.tick();
    const row = rows.find((r) => r.runid === "runDone");
    assert.equal(row.live, false);
    assert.equal(finals.length, 1, "LIVE → terminal must fire onFinal exactly once");
    assert.equal(finals[0].runRef, "i5/runDone");
    assert.equal(finals[0].terminal, "complete", "terminal comes from the report mapping");
    assert.equal(row.terminal, "complete");
    assert.deepEqual(log, ["delta", "final", "delta"], "onFinal must fire before that tick's onDelta");

    w.tick(); // no further transitions
    assert.equal(finals.length, 1, "onFinal fires at most once per run");
  } finally {
    w.stop();
  }
});

test("watcher: grace expiry of a previously-live final-state run fires onFinal exactly once", () => {
  const root = makeUnitRoot();
  const runDir = writeRun(root, "i5", "runGrace", { initTimestamp: isoAgo(1 * MIN) });
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    // Tick 1: final state just reached — within GRACE_MS, awaiting its report.
    let rows = w.tick();
    let row = rows.find((r) => r.runid === "runGrace");
    assert.equal(row.live, true, "fresh final state is live during the report grace window");
    assert.equal(row.terminal, null);
    assert.equal(finals.length, 0);

    // Rewrite the ledger with lastActivity past the grace window (watcher
    // re-parses on size/mtime change) — simulates the 30 minutes elapsing
    // with no report ever landing, without sleeping on a real clock.
    writeRun(root, "i5", "runGrace", { initTimestamp: isoAgo(GRACE_MS + 10 * MIN) });
    rows = w.tick();
    row = rows.find((r) => r.runid === "runGrace");
    assert.equal(row.live, false, "grace expired → no longer live");
    assert.equal(row.terminal, "complete", "replay terminal verbatim (e2ae verdict)");
    assert.equal(finals.length, 1, "observed LIVE → grace terminal must fire onFinal exactly once");
    assert.equal(finals[0].terminal, "complete");

    w.tick();
    assert.equal(finals.length, 1, "onFinal stays at-most-once");
  } finally {
    w.stop();
  }
});

test("watcher: live → stale (mid-state crossing 24h) NEVER fires onFinal", () => {
  const root = makeUnitRoot();
  const runDir = writeRun(root, "i5", "runCross", { initOnly: true, initTimestamp: isoAgo(23 * HOUR) });
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    // Tick 1: 23h idle mid-state — still live (under the 24h cap).
    let rows = w.tick();
    let row = rows.find((r) => r.runid === "runCross");
    assert.equal(row.live, true, "23h < STALE_CAP_MS → still live");
    assert.equal(row.terminal, null);

    // Rewrite past the cap — the observed transition is live → stale.
    writeRun(root, "i5", "runCross", { initOnly: true, initTimestamp: isoAgo(25 * HOUR) });
    rows = w.tick();
    row = rows.find((r) => r.runid === "runCross");
    assert.equal(row.live, false, "crossing the 24h cap must drop liveness");
    assert.equal(row.terminal, null, "stale keeps terminal null");
    assert.equal(finals.length, 0, "live → stale is NOT a terminal disposition — onFinal never fires (silent removal)");

    w.tick();
    assert.equal(finals.length, 0, "still silent on every subsequent tick");
    void runDir;
  } finally {
    w.stop();
  }
});

test("watcher: born-terminal report run is primed WITHOUT onFinal", () => {
  const root = makeUnitRoot();
  writeRun(root, "i5", "runBornDone", { report: "SUCCESS" }); // terminal before first sight
  const finals = [];
  const deltas = [];
  const w = createLiveWatcher({ roots: [root], onDelta: (r) => deltas.push(r), onFinal: (r) => finals.push(r) });
  try {
    const rows = w.tick();
    const row = rows.find((r) => r.runid === "runBornDone");
    assert.equal(finals.length, 0, "first sight of an already-terminal run primes silently (module contract)");
    assert.equal(row.live, false, "report rule is immediate — no grace");
    assert.equal(row.terminal, "complete", "the row itself is still classified terminal");
    assert.equal(deltas.length, 1, "inventory still renders via the initial onDelta");
  } finally {
    w.stop();
  }
});

test("watcher: ledger growth grows records and fires onDelta; the fresh run stays live", () => {
  const root = makeUnitRoot();
  const runDir = writeRun(root, "i5", "runGrow");
  const deltas = [];
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: (r) => deltas.push(r), onFinal: (r) => finals.push(r) });
  try {
    let rows = w.tick();
    assert.equal(rows[0].records, 2);
    assert.equal(deltas.length, 1);

    const count = appendLedgerRecord(runDir, blockedPayload());
    assert.equal(count, 3);

    rows = w.tick();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].records, 3, "records count must grow with the ledger");
    assert.equal(rows[0].live, true, "growth with a fresh timestamp keeps the run live");
    assert.equal(rows[0].terminal, null);
    assert.equal(deltas.length, 2, "row change must fire onDelta with the full inventory");
    assert.deepEqual(deltas[1], rows);
    assert.equal(finals.length, 0);
  } finally {
    w.stop();
  }
});

test("watcher: reportStale re-live flows through the clocks — fresh lastActivity stays live, aged goes grace-terminal", () => {
  const root = makeUnitRoot();
  const runDir = writeRun(root, "i5", "runStaleClock");
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    w.tick(); // prime LIVE
    writeReport(runDir, "runStaleClock", "SUCCESS", ledgerRecords(runDir).at(-1).hash);
    let rows = w.tick();
    const afterReport = rows.find((r) => r.runid === "runStaleClock");
    assert.equal(afterReport.live, false, "a terminal report ends liveness immediately (P4)");
    assert.equal(afterReport.terminal, "complete");
    assert.equal(finals.length, 1);

    // (iii) Fresh growth after the terminal report → reportStale makes the
    // run a candidate again, and the CLOCKS decide: final state within
    // grace → live:true (no report short-circuit in either direction).
    appendLedgerRecord(runDir, blockedPayload(isoAgo(1 * MIN)));
    rows = w.tick();
    const fresh = rows.find((r) => r.runid === "runStaleClock");
    assert.equal(fresh.live, true, "reportStale with fresh lastActivity re-lives (clock flow)");
    assert.equal(fresh.terminal, null, "revival clears the terminal until the driver rewrites the report");
    assert.equal(fresh.records, 3);
    assert.equal(finals.length, 1, "onFinal stays at-most-once even after revival");

    // The other edge — proof it really is a clock: growth that is STILL
    // reportStale but carries a lastActivity past GRACE_MS → grace-expired,
    // with the terminal precedence resolving to the report mapping.
    appendLedgerRecord(runDir, blockedPayload(isoAgo(GRACE_MS + 30 * MIN)));
    rows = w.tick();
    const aged = rows.find((r) => r.runid === "runStaleClock");
    assert.equal(aged.live, false, "stale report + aged lastActivity falls through the grace clock");
    assert.equal(aged.terminal, "complete", "grace → terminal precedence: report mapping (SUCCESS) wins");
    assert.equal(aged.records, 4);
    assert.equal(finals.length, 1, "at-most-once holds across the second grace expiry (already emitted)");
  } finally {
    w.stop();
  }
});

test("watcher: ledger growth AFTER a terminal report makes the run live again (reportStale)", () => {
  const root = makeUnitRoot();
  const runDir = writeRun(root, "i5", "runRevive");
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    w.tick(); // prime LIVE
    writeReport(runDir, "runRevive", "SUCCESS", ledgerRecords(runDir).at(-1).hash);
    let rows = w.tick();
    assert.equal(finals.length, 1);
    const done = rows.find((r) => r.runid === "runRevive");
    assert.equal(done.live, false);
    assert.equal(done.terminal, "complete");

    // Report is now stale: the driver kept writing after it.
    appendLedgerRecord(runDir, blockedPayload());
    rows = w.tick();
    const row = rows.find((r) => r.runid === "runRevive");
    assert.equal(row.live, true, "post-report ledger growth must revive the run (report evidence outranks both clocks)");
    assert.equal(row.terminal, null, "revival clears the terminal until the driver rewrites the report");
    assert.equal(row.records, 3);
    assert.equal(finals.length, 1, "onFinal stays at-most-once even after revival");
  } finally {
    w.stop();
  }
});

test("watcher: machine-null run yields a machineMissing live row without crashing", () => {
  const root = makeUnitRoot();
  writeRun(root, "i5", "runNoMachine", { machine: false });
  const finals = [];
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: (r) => finals.push(r) });
  try {
    const rows = w.tick();
    assert.equal(rows.length, 1, "runs without machine.json still get a row");
    const row = rows[0];
    assert.deepEqual(Object.keys(row).sort(), [...ROW_KEYS].sort(), "machine-missing rows keep the 15-field shape");
    assert.equal(row.machineMissing, true);
    assert.equal(row.machineId, null);
    assert.equal(row.machineName, null);
    assert.equal(row.currentState, null, "no machine → no replay → null current state");
    assert.equal(row.live, true, "fresh age under the cap → live (probeRun mirror: terminal null when replay-less)");
    assert.equal(row.terminal, null);
    assert.equal(row.advisory, null, "advisory is machine-gated");
    assert.equal(row.records, 2);
    assert.equal(finals.length, 0);
  } finally {
    w.stop();
  }
});

test("watcher: advisory no-exits when the current state has zero outgoing on entries", () => {
  const root = makeUnitRoot();
  const gateJson = JSON.stringify(
    { id: "pm-gate", initial: "a", states: { a: {}, done: { type: "final" } } },
    null,
    2,
  );
  writeRun(root, "i5", "runGate", { machineJson: gateJson, machineId: "pm-gate", initOnly: true });
  const w = createLiveWatcher({ roots: [root], onDelta: () => {}, onFinal: () => {} });
  try {
    const rows = w.tick();
    assert.equal(rows.length, 1);
    const row = rows[0];
    assert.equal(row.currentState, "a");
    assert.equal(row.advisory, "no-exits", "non-final state with zero outgoing events → syntactic chip");
    assert.equal(row.live, true, "advisory never affects liveness (display-only)");
    assert.equal(row.terminal, null, "advisory never terminates the run (display-only)");
    assert.equal(row.machineMissing, false);
  } finally {
    w.stop();
  }
});

test("classifyRun derives the Live row (15 fields) directly from disk paths", () => {
  const root = makeUnitRoot();
  const runDir = writeRun(root, "i5", "directRun", { report: "SUCCESS" });
  const row = classifyRun({
    ledgerPath: path.join(runDir, "ledger.jsonl"),
    machinePath: path.join(runDir, "machine.json"),
    reportPath: path.join(runDir, "report.json"),
    // no `root` — exercises the pure deriveRoot/deriveFamily fallback
  });
  assert.deepEqual(Object.keys(row).sort(), [...ROW_KEYS].sort(), "exactly the 15 Round-2 fields incl. `live`");
  assert.equal(row.runRef, "i5/directRun");
  assert.equal(row.root, path.resolve(root));
  assert.equal(row.records, 2);
  assert.equal(row.machineMissing, false);
  assert.equal(row.live, false, "born with a terminal report → not live");
  assert.equal(row.terminal, "complete");

  const noMach = writeRun(root, "i5", "directNoMachine", { machine: false });
  const row2 = classifyRun({
    ledgerPath: path.join(noMach, "ledger.jsonl"),
    machinePath: path.join(noMach, "machine.json"),
    reportPath: path.join(noMach, "report.json"),
  });
  assert.equal(row2.machineMissing, true);
  assert.equal(row2.live, true, "fresh, no report/abort, no final state → live under the cap");
  assert.equal(row2.terminal, null);
  assert.equal(row2.currentState, null);
  assert.equal(row2.runRef, "i5/directNoMachine");
});

// ===========================================================================
// HTTP: GET /live — Round-2 live-only envelope {ok, rows}, NO scopedTo
// (Round-1's has() sessionWorkspace precedence tests are gone: the feature
// was removed from /live; /runs keeps its own scoping contract in
// canvas.test.mjs — untouched here.)
// ===========================================================================

test("GET /live returns live-only {ok,rows} (no scopedTo); stale/terminal/e2ae fixtures are excluded", async () => {
  const res = await fetch(`${base}/live`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get("content-type") || "", /json/);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.deepEqual(
    Object.keys(body).sort(),
    ["ok", "rows"],
    "Round-2 contract: exactly {ok, rows} — no scopedTo, no sessionWorkspace field",
  );
  assert.ok(Array.isArray(body.rows));

  // Live-only feed: the three fresh fixtures (sessA ×2, sessB ×1) and
  // NOTHING else — staleRunA (R2 stale), terminalRunA (report) and
  // oldFinalRunA (e2ae grace-expired) all belong to /runs, not this feed.
  const refs = body.rows.map((r) => r.runRef).sort();
  assert.deepEqual(refs, [
    "i1-triage/liveRunB",
    "i5-releasenotes/liveRunA",
    "i5-releasenotes/sseRun",
  ]);
  for (const row of body.rows) {
    assert.deepEqual(Object.keys(row).sort(), [...ROW_KEYS].sort(), "HTTP rows keep the 15-field Round-2 shape");
    assert.equal(row.live, true, "every row in /live must be explicitly live");
    assert.equal(row.terminal, null, "terminal rows never appear in the live-only feed");
    assert.equal(row.machineMissing, false);
  }
  const runA = body.rows.find((r) => r.runid === "liveRunA");
  assert.equal(runA.session, "sessA", "root under session-state/<uuid> still derives the session (display metadata only)");
});

// ===========================================================================
// HTTP: GET /live-events — SSE envelope machina-live {type:"live-update",rows}
// ===========================================================================

test("GET /live-events primes with :ok and streams a machina-live frame after ledger growth", { timeout: 20000 }, async () => {
  const controller = new AbortController();
  let reader = null;
  try {
    const res = await fetch(`${base}/live-events`, { signal: controller.signal });
    assert.equal(res.status, 200);
    assert.match(res.headers.get("content-type") || "", /text\/event-stream/);
    reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = "";

    const readWithTimeout = async (ms) => {
      let timer;
      try {
        return await Promise.race([
          reader.read(),
          new Promise((_, reject) => {
            timer = setTimeout(() => reject(new Error(`SSE read timed out after ${ms}ms`)), ms);
          }),
        ]);
      } finally {
        clearTimeout(timer);
      }
    };
    const readUntil = async (pred, ms, what) => {
      const deadline = Date.now() + ms;
      for (;;) {
        if (pred(buf)) return buf;
        const remaining = deadline - Date.now();
        if (remaining <= 0) throw new Error(`timed out waiting for ${what}; buffer so far:\n${buf}`);
        const { done, value } = await readWithTimeout(remaining);
        if (done) throw new Error(`SSE stream ended early while waiting for ${what}`);
        buf += decoder.decode(value, { stream: true });
      }
    };
    const frames = (text) => {
      const out = [];
      for (const m of text.matchAll(/event: machina-live\ndata: ([^\n]+)\n/g)) {
        try { out.push(JSON.parse(m[1])); } catch { /* partial frame — rescanned next pass */ }
      }
      return out;
    };

    // 1) :ok prime, exactly as /events does.
    await readUntil((b) => b.includes(":ok"), 5000, "the :ok SSE prime");

    // 2) Prime the extension watcher's cache (GET /live ticks it
    //    synchronously). Round-2: live-only rows, no scopedTo.
    const first = await fetch(`${base}/live`);
    assert.equal(first.status, 200);
    const firstBody = await first.json();
    assert.equal(firstBody.ok, true);
    assert.deepEqual(Object.keys(firstBody).sort(), ["ok", "rows"]);
    assert.ok(firstBody.rows.every((r) => r && r.live === true), "/live serves live rows only");

    // 3) Grow the shared fixture's ledger → the next tick MUST observe it.
    const sseRunDir = path.join(rootA, "i5-releasenotes", "sseRun");
    const count = appendLedgerRecord(sseRunDir, blockedPayload());
    assert.equal(count, 3);

    // 4) Second GET /live → tick() sees the growth → onDelta → broadcastLive
    //    → the frame is written to our socket BEFORE this response completes
    //    (deterministic; never waits on the real 5s interval cadence).
    const second = await fetch(`${base}/live`);
    const secondBody = await second.json();
    assert.equal(secondBody.ok, true);
    const sseRow = secondBody.rows.find((r) => r.runRef === "i5-releasenotes/sseRun");
    assert.ok(sseRow, "sseRun is fresh → must be present in the live-only /live feed (Round-2 row shape)");
    assert.equal(sseRow.records, 3, "the /live tick observed the appended record");
    assert.equal(sseRow.live, true);

    // 5) Consume the canonical envelope: event `machina-live`,
    //    data {type:"live-update", rows} — rows carry the Round-2 shape
    //    (15 fields incl. explicit `live`; assertion against the frame's own
    //    row objects, NOT any Round-1 inference from `terminal == null`).
    const got = await readUntil((b) =>
      frames(b).some((p) =>
        p.type === "live-update"
        && Array.isArray(p.rows)
        && p.rows.some((r) => r && r.runRef === "i5-releasenotes/sseRun" && r.records >= 3),
      ), 5000, "a machina-live live-update frame carrying the appended record");
    const update = frames(got).find((p) =>
      p.type === "live-update"
      && (p.rows || []).some((r) => r && r.runRef === "i5-releasenotes/sseRun" && r.records >= 3));
    assert.ok(update && update.rows.length >= 3, "live-update carries the full inventory snapshot");
    const framed = update.rows.find((r) => r.runRef === "i5-releasenotes/sseRun");
    assert.deepEqual(Object.keys(framed).sort(), [...ROW_KEYS].sort(), "SSE rows use the Round-2 15-field shape");
    assert.equal(framed.live, true, "the grown run is still live after fresh growth");
    assert.doesNotMatch(got, /"type":"live-final"/, "a growing live run must never emit live-final");
  } finally {
    // MANDATORY (plan §4 / audit #9): tear the stream down — an open socket
    // keeps the event loop alive and would hang the npm test chain.
    if (reader) {
      try { await reader.cancel(); } catch { /* already closed */ }
    }
    controller.abort();
  }
});
