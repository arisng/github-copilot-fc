// live-watcher.mjs — stat-poll watcher over persisted Machina run roots.
//
// Public contract (consumed by extension.mjs — /live + /live-events):
//
//   createLiveWatcher({ roots, onDelta, onFinal, intervalMs = 5000 })
//     -> { start(), stop(), tick() }
//   classifyRun({ ledgerPath, machinePath, reportPath, machine, ledger, ... })
//     -> row (pure classification helper so tests can unit-call it)
//
//   roots    — persist-root paths, resolved by the caller (one entry per
//              <session-state>/<uuid>/{machina-runs,machina-persist,machina-i2}).
//              May also be a FUNCTION returning that array — re-evaluated on
//              every tick so persist roots created after start (e.g. a
//              session that begins driving after the simulator was launched)
//              are picked up without a restart.
//   start()  — idempotent; the poll interval is unref()'d (audit #3 CRITICAL:
//              a ref'd interval would leak the extension process past SDK
//              session end and hang the `npm test` chain).
//   stop()   — clearInterval; idempotent.
//   tick()   — one synchronous manual pass (tests drive cadence through this
//              instead of waiting on the real ~5s interval); returns the full
//              rows array.
//
// Callback conventions (plan §1 — the documented delta choice):
//   onDelta(rows) — `rows` is the FULL current inventory (snapshot-style
//                   delta), fired only on a tick where >= 1 row changed
//                   (new / modified / removed) versus the previous tick.
//                   The first productive tick always fires (initial render).
//   onFinal(row)  — fired at MOST ONCE per run (keyed by ledger.jsonl path),
//                   only on an observed LIVE -> terminal transition where the
//                   run was live at the PREVIOUS tick and this tick's
//                   disposition is terminal (report / abort / R1 grace
//                   expiry). Runs first seen already terminal are primed
//                   silently so startup never spams live-final over historic
//                   inventory. live -> stale (R2 cap) is NOT a terminal
//                   disposition and never fires onFinal (silent row removal
//                   downstream). onFinal fires before that tick's onDelta.
//
// Enumeration is deliberately cheap (audit #10c): per tick a fs.readdir walk
// of the roots plus stat of ledger.jsonl / machine.json / report.json.
// discoverRunHistory is NEVER imported or called (it fully parses every
// ledger); files are read + parsed only when size/mtime changed since the
// last successful parse (cache keyed by path). A transient read/stat error
// or a torn JSON line keeps the previous cached state and retries on the
// next tick (audit #6c) — an existing row is never dropped.
//
// Row shape (frozen contract — Round-1's 14 fields + `live`): root, family,
// runid, runRef, machineId, machineName, session, currentState, records,
// lastActivity, advisory, childRuns, machineMissing, terminal, live.
// `live` is an EXPLICIT boolean — consumers read it and no longer infer
// membership from `terminal == null`. Stale class (R2): a mid-state
// candidate past rules 1-2 below (no abort, no terminal report — an
// IN_PROGRESS or a grown-out report does NOT exempt it) idle >=
// STALE_CAP_MS is exactly `live:false` + `terminal === null` (there is
// deliberately no extra `stale` field — that pair IS the stale marker).
//
// Membership (Round 2 — plan §1; explicitly SUPERSEDES Round-1's "lifecycle
// membership, never clock-migrated", and amended after the real-data E2E:
// an IN_PROGRESS report is NOT terminal evidence — it falls through to the
// SAME clock candidate as a no-report run, so f87fb459bce7-style 8.6d
// IN_PROGRESS zombies cannot stay LIVE): rules evaluated in order —
//   1. abort record (payload.type === "abort", driver.py:734) -> live:false,
//      terminal by the precedence below (verbatim "aborted" when replay-less).
//   2. terminal report (result !== "IN_PROGRESS") and !reportStale ->
//      live:false, terminal = report mapping (SUCCESS -> complete, ...).
//   3. R1 candidate — machine-gated final state past rules 1-2 (no report,
//      OR an IN_PROGRESS report, OR a terminal report the ledger outgrew
//      [reportStale]): live:true ONLY while now - lastActivity < GRACE_MS
//      (30min grace for the driver's `report` command to land); at/after
//      grace — or with no parseable age — -> live:false, terminal from the
//      existing precedence (report mapping — which by rule 2's definition
//      skips a non-terminal IN_PROGRESS — else replay.terminal verbatim:
//      e2ae / f87fb459bce7-final -> {live:false, terminal:"complete"}).
//      A fresh final-state run (< GRACE_MS, with or without an IN_PROGRESS
//      report) stays live awaiting its report. Rules 1-2 get NO grace.
//   4. R2 candidate — everyone else (mid-state / machine-null / replay-less
//      past rules 1-2): now - lastActivity >= STALE_CAP_MS (24h) ->
//      live:false (abandoned P2), terminal stays null (silent — stale is
//      not a terminal disposition). A missing/unparseable age is NOT
//      stale — never age out a run before its first timestamped record.
// reportStale re-lives through the clocks as well: age is measured from the
// post-growth lastActivity, so active runs keep ticking live until idle.
// Thresholds are the exported named constants GRACE_MS (30min) and
// STALE_CAP_MS (24h) — user-set; tests/docs reference those names.
//
// Advisory `advisory: "no-exits"` is SYNTACTIC only (audit #5a): machine
// exists, current state is not type:"final", and that state has zero
// outgoing `on` entries. The label deliberately avoids the protocol's
// "STUCK" vocabulary so it can never contradict report.result (semantic
// zero-*enabled*-events is impossible here — evidence checkers are Python
// tools the simulator cannot run).

import fs from "node:fs";
import path from "node:path";
import { PERSIST_ROOT_NAMES } from "./discovery.mjs";
import { isTerminalState, replayRunLedger } from "../machine-simulator.mjs";

// Exact protocol strings (driver.py:734 / report results).
const ABORT_TYPE = "abort";
const IN_PROGRESS = "IN_PROGRESS";
// machina.report.v1 result -> chip vocabulary. report.result is AUTHORITATIVE
// at terminal (audit #5a): a SUCCESS report must never render as the replay's
// blocked-last "stuck". Replay/abort remain the fallback for runs that end
// without a report; unknown results lowercase verbatim (UI shows them raw).
const REPORT_TERMINAL = { SUCCESS: "complete", STUCK: "stuck", ABORTED: "aborted", ESCALATED: "escalated" };

// Round-2 membership thresholds (plan §1 — user-set; exported so tests and
// docs reference these names instead of magic numbers).
export const GRACE_MS = 30 * 60 * 1000;          // R1: report-less final-state grace
export const STALE_CAP_MS = 24 * 60 * 60 * 1000; // R2: non-final staleness cap

// ---------------------------------------------------------------------------
// Path derivation (pure — from ledgerPath/root only)
// ---------------------------------------------------------------------------

// Nearest ancestor that is a canonical persist-root name; falls back to the
// run dir's parent (flat custom MACHINA_RUN_ROOTS layouts). Watcher passes
// `root` explicitly — this only serves direct classifyRun unit calls.
function deriveRoot(ledgerPath) {
  const runDir = path.dirname(path.resolve(ledgerPath));
  let dir = runDir;
  for (;;) {
    if (PERSIST_ROOT_NAMES.includes(path.basename(dir))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return path.dirname(runDir);
    dir = parent;
  }
}

// Session = basename of the session-workspace dir: the root's ancestor that
// sits directly under .../session-state/<uuid>. null when not under one.
function deriveSession(root) {
  let dir = path.resolve(root);
  for (;;) {
    const parent = path.dirname(dir);
    if (path.basename(parent) === "session-state") return path.basename(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

// family = nearest named container under root (first path segment), else the
// runid itself for flat <root>/<runid> layouts — mirrors discovery.mjs.
function deriveFamily(root, runDir, runid) {
  const rel = path.relative(root, runDir);
  const segs = rel.split(path.sep).filter((s) => s && s !== ".");
  if (!segs.length || segs[0] === ".." || path.isAbsolute(rel)) return runid;
  return segs[0];
}

function statOf(p) {
  try {
    const s = fs.statSync(p);
    return { ok: true, size: s.size, mtimeMs: s.mtimeMs };
  } catch (err) {
    return { ok: false, code: (err && err.code) || null };
  }
}

function isGone(code) {
  return code === "ENOENT" || code === "ENOTDIR";
}

function parseLedgerText(text) {
  return text.split(/\r?\n/).filter((l) => l.trim().length).map((l) => JSON.parse(l));
}

// Age of a ledger timestamp (ISO string or epoch ms) against `now`, in ms.
// Future stamps clamp to 0; absent/unparseable -> null (age rules decide how
// to treat unknown age — see the header Membership contract).
function ageMsOf(ts, now) {
  if (ts == null || ts === "") return null;
  const t = typeof ts === "number" ? ts : Date.parse(ts);
  if (!Number.isFinite(t)) return null;
  return Math.max(0, now - t);
}

function newEntry() {
  return {
    ledger: [],
    parsedLedgerStat: null,      // stat at last SUCCESSFUL ledger parse
    lastLedgerSize: 0,           // last observed raw size (growth tracking)
    machine: null,
    machineRaw: null,
    machineStat: null,
    report: null,
    reportSeenKey: null,         // `${size}:${mtimeMs}` of last parsed report
    ledgerSizeAtReport: null,    // ledger size when that report was parsed
    replay: null,
    lastRowJson: null,
    lastRow: null,
    lastLive: undefined,         // live flag at previous classify; undefined = first sight
  };
}

// ---------------------------------------------------------------------------
// classifyRun — pure-ish classification of one run into its Live-tab row.
//
// The watcher pre-supplies machine/ledger/report/replay from its caches
// (no I/O); direct unit callers may omit them and they are read from the
// given paths instead. `opts.now` (epoch ms) overrides Date.now for
// deterministic age assertions. Returns { row, live, disposition } —
// `disposition` is null while live, else why the row is not live
// ("report" | "abort" | "grace" | "stale"); it is internal (drives onFinal
// semantics) and NEVER part of the row. classifyRun exposes the row.
// ---------------------------------------------------------------------------

function classifyRunFull(opts = {}) {
  const ledgerPath = path.resolve(opts.ledgerPath);
  const machinePath = opts.machinePath ?? null;
  const reportPath = opts.reportPath ?? null;
  const runDir = path.dirname(ledgerPath);
  const runid = path.basename(runDir);
  const root = opts.root ? path.resolve(opts.root) : deriveRoot(ledgerPath);
  const family = deriveFamily(root, runDir, runid);
  const session = deriveSession(root);
  const runRef = `${family}/${runid}`;

  let ledger = opts.ledger;
  if (ledger === undefined) {
    try { ledger = parseLedgerText(fs.readFileSync(ledgerPath, "utf8")); } catch { ledger = []; }
  }
  const recs = Array.isArray(ledger) ? ledger : [];

  let machine = opts.machine;
  if (machine === undefined) {
    machine = null;
    if (machinePath) {
      try { machine = JSON.parse(fs.readFileSync(machinePath, "utf8")); } catch { machine = null; }
    }
  }

  let report = opts.report;
  if (report === undefined) {
    report = null;
    if (reportPath) {
      try { report = JSON.parse(fs.readFileSync(reportPath, "utf8")); } catch { report = null; }
      if (report !== null && (typeof report !== "object" || Array.isArray(report))) report = null;
    }
  }

  // Replay only when machine exists AND ledger is non-empty — mirrors
  // probeRun (extension.mjs:174-181); the watcher passes its cached result.
  let replay = opts.replay;
  if (replay === undefined) {
    replay = null;
    if (machine && recs.length) {
      let machineJson = opts.machineJson;
      if (machineJson === undefined && machinePath) {
        try { machineJson = fs.readFileSync(machinePath, "utf8"); } catch { machineJson = null; }
      }
      try {
        replay = replayRunLedger(machine, recs, { diffReeval: false, machineJson: machineJson ?? null });
      } catch {
        replay = null;
      }
    }
  }

  const machineMissing = !machine;
  const currentState = replay ? (replay.state ?? null) : null;

  // lastActivity = newest ledger timestamp (ISO string from the driver, or
  // epoch ms); its age drives the R1 grace / R2 cap below.
  let lastActivity = null;
  if (recs.length) {
    const lastP = recs[recs.length - 1] && recs[recs.length - 1].payload;
    const firstP = recs[0] && recs[0].payload;
    lastActivity = (lastP && lastP.timestamp) || (firstP && firstP.timestamp) || null;
  }
  const ageMs = ageMsOf(lastActivity, opts.now ?? Date.now());

  const hasAbort = recs.some((r) => r && r.payload && r.payload.type === ABORT_TYPE);
  const terminalReport = !!report && report.result !== IN_PROGRESS;
  const reportStale = opts.reportStale === true;

  // R1 gate: the machine's own terminal predicate — type:"final" OR no
  // outgoing transitions (isTerminalState: the same gate replay uses to say
  // "complete"). Machine-null / replay-null / mid-state -> false.
  const finalState = machine !== null && currentState !== null &&
    isTerminalState(machine, currentState);

  // Membership (header §Row shape / §Membership). `disposition` records WHY
  // a row is not live; null <=> live. "stale" is deliberately NOT a terminal
  // disposition (live -> stale must stay onFinal-silent). Everyone past
  // rules 1-2 — IN_PROGRESS reports included (they are NOT terminal
  // evidence) — flows through the SAME clock candidates as no-report runs.
  let live;
  let disposition;
  if (hasAbort) {
    live = false; disposition = "abort";                      // rule 1 — unchanged
  } else if (terminalReport && !reportStale) {
    live = false; disposition = "report";                     // rule 2 — unchanged
  } else if (finalState) {
    // rule 3 — R1 candidate (no report | IN_PROGRESS | reportStale, final)
    live = ageMs !== null && ageMs < GRACE_MS;                // grace (P1 fix)
    disposition = live ? null : "grace";
  } else {
    // rule 4 — R2 candidate (mid-state / machine-null, no terminal report)
    live = !(ageMs !== null && ageMs >= STALE_CAP_MS);        // cap (P2 fix)
    disposition = live ? null : "stale";
  }

  let terminal = null;
  if (!live) {
    if (disposition === "stale") {
      terminal = null; // R2 abandoned mid-state — terminal stays null by contract
    } else if (terminalReport && REPORT_TERMINAL[report.result]) terminal = REPORT_TERMINAL[report.result];
    else if (terminalReport) terminal = String(report.result).toLowerCase();
    else if (replay) terminal = replay.terminal ?? null;
    else if (hasAbort) terminal = "aborted";
    // An IN_PROGRESS report is non-terminal, so the report mapping above
    // skips it and replay.terminal wins verbatim (amendment: rule 3 grace).
    // machine-missing / replay-less report-only -> terminal stays null
    // (probeRun mirror); liveness + onFinal remain authoritative.
  }

  // Advisory — syntactic only: non-final current state with zero outgoing
  // `on` entries on an existing machine. Deliberately NOT "stuck"/"STUCK".
  let advisory = null;
  if (machine && currentState !== null) {
    const st = machine.states ? machine.states[currentState] : undefined;
    const isFinal = !!(st && st.type === "final");
    const exits = st && st.on ? Object.keys(st.on).length : 0;
    if (!isFinal && exits === 0) advisory = "no-exits";
  }

  const childRuns = recs.map((r) => (r && r.payload && r.payload.child_run) || null).filter(Boolean);

  const row = {
    root,
    family,
    runid,
    runRef,
    machineId: machine?.id ?? null,
    machineName: machine?.name ?? null,
    session,
    currentState,
    records: recs.length,
    lastActivity,
    advisory,
    childRuns,
    machineMissing,
    terminal,
    live,
  };
  return { row, live, disposition };
}

// Public unit-test helper: same inputs, row shape only.
export function classifyRun(opts) {
  return classifyRunFull(opts).row;
}

// ---------------------------------------------------------------------------
// createLiveWatcher
// ---------------------------------------------------------------------------

export function createLiveWatcher({ roots = [], onDelta, onFinal, intervalMs = 5000 } = {}) {
  // roots may be a function → re-evaluated per tick (new persist roots appear
  // without restart); array form is fixed (tests inject temp roots).
  const normalize = (list) => (Array.isArray(list) ? list : [])
    .filter((p) => p != null && String(p).trim().length)
    .map((p) => path.resolve(String(p)));
  const currentRoots = () => normalize(typeof roots === "function" ? roots() : roots);
  const cache = new Map();              // ledgerPath -> entry (parse caches)
  const emittedFinals = new Set();      // ledgerPath keys — onFinal at most once
  let timer = null;
  let lastRows = [];

  // Cheap readdir walk: locate run dirs (ledger.jsonl) + sibling presence.
  // NEVER discoverRunHistory — no parsing here (audit #10c).
  function enumerate() {
    const out = [];
    const seen = new Set();
    const walk = (dir, root) => {
      let entries;
      try {
        entries = fs.readdirSync(dir, { withFileTypes: true });
      } catch {
        return; // transient/unreadable dir — skip this subtree, keep cached rows
      }
      let ledgerPath = null;
      let machinePresent = false;
      let reportPresent = false;
      for (const ent of entries) {
        if (ent.isDirectory()) walk(path.join(dir, ent.name), root);
        else if (ent.name === "ledger.jsonl") ledgerPath = path.join(dir, ent.name);
        else if (ent.name === "machine.json") machinePresent = true;
        else if (ent.name === "report.json") reportPresent = true;
      }
      if (ledgerPath && !seen.has(ledgerPath)) {
        seen.add(ledgerPath);
        out.push({
          root,
          runDir: dir,
          ledgerPath,
          machinePath: path.join(dir, "machine.json"),
          reportPath: path.join(dir, "report.json"),
          machinePresent,
          reportPresent,
        });
      }
    };
    for (const root of currentRoots()) walk(root, root);
    return out;
  }

  // Refresh one run's caches: parse ONLY on size/mtime change; any read/stat
  // error or torn JSON line keeps the previous state and retries next tick.
  // Returns { kind: "ok", entry } | { kind: "cold" } | { kind: "pruned" }.
  function refreshEntry(f) {
    const st = statOf(f.ledgerPath);
    if (!st.ok) {
      const e = cache.get(f.ledgerPath);
      if (!e) return { kind: "cold" };               // nothing known yet — retry
      if (isGone(st.code)) { cache.delete(f.ledgerPath); return { kind: "pruned" }; }
      return { kind: "ok", entry: e };               // transient — keep previous state
    }
    let e = cache.get(f.ledgerPath);
    if (!e) {
      e = newEntry();
      cache.set(f.ledgerPath, e);
    }
    e.lastLedgerSize = st.size;

    // --- ledger.jsonl: parse only when size/mtime differs from last good parse
    const parsed = e.parsedLedgerStat;
    if (!parsed || parsed.size !== st.size || parsed.mtimeMs !== st.mtimeMs) {
      try {
        const recs = parseLedgerText(fs.readFileSync(f.ledgerPath, "utf8"));
        e.ledger = recs;
        e.parsedLedgerStat = { size: st.size, mtimeMs: st.mtimeMs };
        e.replay = null;                            // growth/rewrite -> re-replay
      } catch {
        // transient read error OR torn JSON line: keep previous records;
        // parsedLedgerStat unchanged so the next tick retries. Never drop the row.
      }
    }

    // --- machine.json (presence from the readdir pass)
    if (f.machinePresent) {
      const mst = statOf(f.machinePath);
      if (mst.ok) {
        if (!e.machineStat || e.machineStat.size !== mst.size || e.machineStat.mtimeMs !== mst.mtimeMs) {
          try {
            const raw = fs.readFileSync(f.machinePath, "utf8");
            e.machine = JSON.parse(raw);
            e.machineRaw = raw;
            e.machineStat = { size: mst.size, mtimeMs: mst.mtimeMs };
            e.replay = null;
          } catch {
            // keep previous machine; machineStat unchanged -> retry next tick
          }
        }
      } else if (isGone(mst.code)) {
        e.machine = null; e.machineRaw = null; e.machineStat = null; e.replay = null;
      }
      // other stat errors: transient — keep previous machine
    } else if (e.machine !== null || e.machineRaw !== null) {
      e.machine = null; e.machineRaw = null; e.machineStat = null; e.replay = null;
    }

    // --- report.json: snapshot the ledger size whenever a NEW report parses;
    // growth beyond that snapshot later marks the report stale (live again).
    if (f.reportPresent) {
      const rst = statOf(f.reportPath);
      if (rst.ok) {
        const key = `${rst.size}:${rst.mtimeMs}`;
        if (e.reportSeenKey !== key) {
          try {
            const parsedReport = JSON.parse(fs.readFileSync(f.reportPath, "utf8"));
            e.report = parsedReport !== null && typeof parsedReport === "object" && !Array.isArray(parsedReport)
              ? parsedReport
              : null;
            e.reportSeenKey = key;
            e.ledgerSizeAtReport = st.size;
          } catch {
            // torn report — keep previous report/reportSeenKey; retry next tick
          }
        }
      } else if (isGone(rst.code)) {
        e.report = null; e.reportSeenKey = null; e.ledgerSizeAtReport = null;
      }
      // transient stat error: keep previous report
    } else if (e.report !== null) {
      e.report = null; e.reportSeenKey = null; e.ledgerSizeAtReport = null;
    }

    return { kind: "ok", entry: e };
  }

  // Replay is cached on the entry until the ledger or machine re-parses.
  function classifyEntry(e, f) {
    if (e.machine && e.ledger.length && !e.replay) {
      try {
        e.replay = replayRunLedger(e.machine, e.ledger, {
          diffReeval: false,
          machineJson: e.machineRaw ?? null,
        });
      } catch {
        e.replay = null;
      }
    }
    const reportStale =
      e.reportSeenKey !== null &&
      e.ledgerSizeAtReport !== null &&
      e.lastLedgerSize > e.ledgerSizeAtReport;
    return classifyRunFull({
      ledgerPath: f.ledgerPath,
      machinePath: f.machinePath,
      reportPath: f.reportPath,
      machine: e.machine,          // null when known-missing (no auto-read)
      ledger: e.ledger,
      root: f.root,
      report: e.report,            // null when known-absent/unreadable
      replay: e.machine && e.ledger.length ? e.replay : null,
      reportStale,
    });
  }

  function tick() {
    try {
      const found = enumerate();
      const seen = new Set();
      const rows = [];
      const finals = [];
      let anyChanged = false;

      for (const f of found) {
        seen.add(f.ledgerPath);
        try {
          const res = refreshEntry(f);
          if (res.kind === "cold") continue;        // nothing known yet — retry
          if (res.kind === "pruned") { anyChanged = true; continue; }
          const e = res.entry;
          const { row, live, disposition } = classifyEntry(e, f);

          // Final emission (header §onFinal): first sight primes silently —
          // born-terminal rows join emittedFinals so they can never fire
          // later; born-stale rows stay silent now but may still fire if they
          // wake up and genuinely reach a terminal disposition. Thereafter
          // fire only when the run was live at the PREVIOUS tick and the
          // disposition is terminal (report / abort / grace expiry);
          // live -> stale (R2 cap) is not terminal and stays silent.
          const terminalDisp =
            disposition === "report" || disposition === "abort" || disposition === "grace";
          if (e.lastLive === undefined) {
            if (!live && terminalDisp) emittedFinals.add(f.ledgerPath);
          } else if (e.lastLive && !live && terminalDisp && !emittedFinals.has(f.ledgerPath)) {
            emittedFinals.add(f.ledgerPath);
            finals.push(row);
          }
          e.lastLive = live;

          const json = JSON.stringify(row);
          if (json !== e.lastRowJson) {
            e.lastRowJson = json;
            anyChanged = true;
          }
          e.lastRow = row;
          rows.push(row);
        } catch {
          // per-run isolation: keep the previous row rather than kill the tick
          const e = cache.get(f.ledgerPath);
          if (e && e.lastRow) rows.push(e.lastRow);
        }
      }

      // Cached runs the walk missed this tick: genuinely gone (ENOENT) -> prune;
      // any other stat result keeps the previous row (never drop on transient error).
      for (const [p, e] of cache) {
        if (seen.has(p)) continue;
        const st = statOf(p);
        if (!st.ok && isGone(st.code)) {
          cache.delete(p);
          anyChanged = true;
          continue;
        }
        if (e.lastRow) rows.push(e.lastRow);
      }

      rows.sort((a, b) => {
        const ka = `${a.root}\u0000${a.runRef}`;
        const kb = `${b.root}\u0000${b.runRef}`;
        return ka < kb ? -1 : ka > kb ? 1 : 0;
      });

      for (const row of finals) {
        if (typeof onFinal === "function") onFinal(row);
      }
      if (anyChanged && typeof onDelta === "function") onDelta(rows);

      lastRows = rows;
      return rows;
    } catch {
      // tick-level safety: keep the previous inventory rather than crash host
      return lastRows;
    }
  }

  function start() {
    if (timer) return; // idempotent
    timer = setInterval(() => {
      try {
        tick();
      } catch {
        // never let a tick error escape into the host process / kill the loop
      }
    }, intervalMs);
    timer.unref(); // CRITICAL (audit #3): never keep the extension process alive
  }

  function stop() {
    if (!timer) return; // idempotent
    clearInterval(timer);
    timer = null;
  }

  return { start, stop, tick };
}
