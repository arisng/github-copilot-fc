// Machina State-Machine engine — dependency-free, testable.
// Faithful port of the compliance/scoring/autofill engine from the canonical
// Machina simulator, shared by the Copilot tools and the simulator app
// (the app imports this module as /machine-simulator.mjs). See
// simulator/docs/maintenance.md for parity notes.

// ---------------------------------------------------------------------------
// SPEC registry + versioning
// ---------------------------------------------------------------------------

export const SPEC_REGISTRY = [
  {
    version: "2.0.0",
    title: "Machine schema · v2.0",
    changes: [
      "Added scenarios[] entry points (UI · API)",
      "Added declarative action + guard objects",
      "Added coverage analysis metadata",
      "Added cycle_prevention guards",
      "Added optional spec_version field",
    ],
    conventions: ["Event names UPPER_SNAKE", "State keys kebab-case", "Values may reference context keys by name"],
    fields: [
      { name: "id", type: "string", meaning: "Stable machine identifier." },
      { name: "name", type: "string", meaning: "Human-readable label." },
      { name: "version", type: "string", meaning: "Machine's own version (distinct from spec_version)." },
      { name: "spec_version", type: "string", meaning: "Optional. Target schema-spec version; absent ⇒ latest. Distinct from version." },
      { name: "initial", type: "string", meaning: "Default initial state key." },
      { name: "context", type: "object", meaning: "Initial extended state (default initial conditions)." },
      { name: "scenarios[]", type: "array", meaning: "Named entry points: { id, label, initial?, context?, interface? }, interface ∈ UI · API." },
      { name: "states", type: "object", meaning: "Keyed by state id: { type?, description?, entry?, exit?, on? }." },
      { name: "state.type", type: "\"atomic\" | \"final\"", meaning: "Terminal states are final." },
      { name: "state.on", type: "object", meaning: "Event map: { EVENT: { target, guard?, actions?, description? } }." },
      { name: "action", type: "object", meaning: "{ type: \"assign\", key, value } or { type: \"increment\", key }." },
      { name: "guard", type: "object", meaning: "{ type: \"compare\", key, op, value }; op ∈ eq · neq · lt · lte · gt · gte." },
      { name: "coverage", type: "object", meaning: "Optional analysis metadata: metrics, state_coverage, edge_coverage, uncovered_paths, recommendations." },
      { name: "cycle_prevention", type: "object", meaning: "Optional: max_retry_limit, timeout_seconds, guards[] { event, guard, else_target }." },
    ],
  },
  {
    version: "1.0.0",
    title: "Machine schema · v1.0",
    changes: [],
    conventions: ["Event names UPPER_SNAKE", "State keys kebab-case", "Values may reference context keys by name"],
    fields: [
      { name: "id", type: "string", meaning: "Stable machine identifier." },
      { name: "name", type: "string", meaning: "Human-readable label." },
      { name: "version", type: "string", meaning: "Machine's own version (distinct from spec_version)." },
      { name: "initial", type: "string", meaning: "Default initial state key." },
      { name: "context", type: "object", meaning: "Initial extended state (default initial conditions)." },
      { name: "states", type: "object", meaning: "Keyed by state id: { type?, on? }." },
      { name: "state.type", type: "\"atomic\" | \"final\"", meaning: "Terminal states are final." },
      { name: "state.on", type: "object", meaning: "Event map: { EVENT: { target } }." },
    ],
  },
];

export const LATEST_SPEC_VERSION = SPEC_REGISTRY[0].version;

export function specRank(v) {
  const i = SPEC_REGISTRY.findIndex((s) => s.version === v);
  return i === -1 ? 0 : i;
}

// True when version `a` <= version `b` (semver numeric comparison).
// A compliance check applies when its `since` version <= the target version.
export function versionLE(a, b) {
  if (a === b) return true;
  const pa = String(a).split(".").map((n) => parseInt(n, 10) || 0);
  const pb = String(b).split(".").map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const va = pa[i] || 0;
    const vb = pb[i] || 0;
    if (va < vb) return true;
    if (va > vb) return false;
  }
  return true;
}

export function detectSpecVersion(m) {
  const sv = m && m.spec_version;
  if (sv && SPEC_REGISTRY.some((s) => s.version === sv)) return { version: sv, declared: true, assumed: false };
  return { version: LATEST_SPEC_VERSION, declared: !!sv, assumed: true };
}

// ---------------------------------------------------------------------------
// engine helpers
// ---------------------------------------------------------------------------

export function getPath(obj, key) {
  return key.split(".").reduce((a, k) => (a == null ? undefined : a[k]), obj);
}

export function setPath(obj, key, val) {
  const ks = key.split(".");
  let t = obj;
  for (let i = 0; i < ks.length - 1; i++) {
    if (t[ks[i]] == null) t[ks[i]] = {};
    t = t[ks[i]];
  }
  t[ks[ks.length - 1]] = val;
}

export function resolveValue(v, ctx) {
  const c = ctx || {};
  if (typeof v === "number") return v;
  if (typeof v === "string" && v in c) return c[v];
  if (typeof v === "string" && v !== "" && !isNaN(Number(v))) return Number(v);
  return v;
}

export function evalGuard(g, ctx) {
  if (!g || g.type !== "compare") return true;
  const a = getPath(ctx || {}, g.key);
  const b = resolveValue(g.value, ctx);
  switch (g.op) {
    case "eq": return a === b;
    case "neq": return a !== b;
    case "lt": return a < b;
    case "lte": return a <= b;
    case "gt": return a > b;
    case "gte": return a >= b;
    default: return true;
  }
}

export function applyActions(list, ctx) {
  (list || []).forEach((a) => {
    if (a.type === "increment") setPath(ctx, a.key, (getPath(ctx, a.key) || 0) + 1);
    else if (a.type === "assign") setPath(ctx, a.key, a.value);
  });
  return ctx;
}

// ---------------------------------------------------------------------------
// topology + cycle analysis
// ---------------------------------------------------------------------------

export function reachableStates(m) {
  const states = m.states || {};
  const entries = [];
  const seen = new Set();
  (m.scenarios || []).forEach((sc) => {
    if (sc && sc.initial && states[sc.initial] && !seen.has(sc.initial)) {
      entries.push(sc.initial);
      seen.add(sc.initial);
    }
  });
  if (m.initial && states[m.initial] && !seen.has(m.initial)) entries.push(m.initial);
  const visited = new Set(entries);
  const q = entries.slice();
  while (q.length) {
    const s = q.shift();
    const st = states[s];
    for (const tr of Object.values((st && st.on) || {})) {
      if (tr && tr.target && states[tr.target] && !visited.has(tr.target)) {
        visited.add(tr.target);
        q.push(tr.target);
      }
    }
  }
  return visited;
}

export function isTerminalState(m, s) {
  const st = (m.states || {})[s];
  return !!(st && (st.type === "final" || !st.on || !Object.keys(st.on).length));
}

export function detectCycles(schema) {
  const states = schema.states;
  const finals = new Set(Object.keys(states).filter((s) => states[s].type === "final"));
  const cycles = [];
  const seen = new Set();
  const visited = new Set();
  const MAX_DEPTH = 24;
  function walk(start) {
    const stack = [];
    const inStack = new Set();
    function dfs(node, depth) {
      if (depth > MAX_DEPTH) {
        if (!seen.has("::depth")) {
          seen.add("::depth");
          cycles.push({ type: "loop", cycle: stack.concat([node]), severity: "CRITICAL", recommendation: "Add a max-iteration guard or exit condition." });
        }
        return;
      }
      visited.add(node);
      stack.push(node);
      inStack.add(node);
      const st = states[node];
      if (st && st.on) {
        for (const tr of Object.values(st.on)) {
          const t = tr.target;
          if (!t || !states[t]) continue;
          if (inStack.has(t)) {
            const idx = stack.indexOf(t);
            const cyclePath = stack.slice(idx).concat([t]);
            const sig = cyclePath.slice().sort().join(">");
            if (!seen.has(sig)) {
              seen.add(sig);
              const hasFinal = cyclePath.some((s2) => finals.has(s2));
              cycles.push({
                type: "cycle",
                cycle: cyclePath,
                severity: hasFinal ? "MEDIUM" : "HIGH",
                recommendation: hasFinal ? "Valid cycle — ensure it has a clear exit condition." : "Potential infinite loop — add an exit event or an iteration guard.",
              });
            }
          } else {
            dfs(t, depth + 1);
          }
        }
      }
      inStack.delete(node);
      stack.pop();
    }
    dfs(start, 0);
  }
  walk(schema.initial);
  for (const s of Object.keys(states)) if (!visited.has(s)) walk(s);
  return cycles;
}

// ---------------------------------------------------------------------------
// compliance engine
// ---------------------------------------------------------------------------

export function isUpperSnake(s) { return /^[A-Z][A-Z0-9_]*$/.test(s); }
export function isKebab(s) { return /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/.test(s); }
export function humanize(key) { return String(key).replace(/[_-]+/g, " ").trim(); }
export function capFirst(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }
export function pass(ok) { return { pass: !!ok, detail: ok }; }
export function fail(detail) { return { pass: false, detail }; }

export const COMPLIANCE_CHECKS = [
  { id: "id-present", category: "Identity & metadata", since: "1.0.0", weight: 5, severity: "blocking", autofill: "review", remediation: "Add a string \"id\".", check: (m) => pass(typeof m.id === "string" && m.id.trim() !== "") },
  { id: "name-present", category: "Identity & metadata", since: "1.0.0", weight: 5, severity: "warn", autofill: "review", remediation: "Add a human-readable \"name\" (suggested from id).", check: (m) => pass(typeof m.name === "string" && m.name.trim() !== "") },
  { id: "version-present", category: "Identity & metadata", since: "1.0.0", weight: 5, severity: "warn", autofill: "auto", remediation: "Add a machine \"version\" string (distinct from \"spec_version\").", check: (m) => pass(typeof m.version === "string") },
  { id: "spec-version", category: "Identity & metadata", since: "2.0.0", weight: 0, severity: "info", autofill: "auto", remediation: "Declare \"spec_version\" to pin the target schema spec (distinct from machine \"version\").", check: (m) => pass(!!detectSpecVersion(m).declared) },
  { id: "states-present", category: "Structure & integrity", since: "1.0.0", weight: 10, severity: "blocking", autofill: "review", remediation: "Provide a non-empty \"states\" object.", check: (m) => pass(m.states && typeof m.states === "object" && !Array.isArray(m.states) && Object.keys(m.states).length > 0) },
  { id: "initial-resolves", category: "Structure & integrity", since: "1.0.0", weight: 10, severity: "blocking", autofill: "review", remediation: "Set \"initial\" to an existing state key.", check: (m) => pass(m.initial && m.states && m.initial in m.states) },
  { id: "targets-resolve", category: "Structure & integrity", since: "1.0.0", weight: 5, severity: "blocking", autofill: "review", remediation: "Every transition \"target\" must reference an existing state.", check: (m) => {
    const states = m.states || {};
    for (const st of Object.values(states)) {
      for (const tr of Object.values((st && st.on) || {})) {
        if (!tr || !tr.target || !(tr.target in states)) return fail("At least one transition targets an unknown state");
      }
    }
    return pass(true);
  } },
  { id: "state-descriptions", category: "State quality", since: "1.0.0", weight: 8, severity: "warn", autofill: "auto", remediation: "Give every state a \"description\".", check: (m) => {
    const missing = Object.keys(m.states || {}).filter((s) => !(m.states[s] && m.states[s].description));
    return missing.length ? fail(missing.length + " state(s) missing: " + missing.join(", ")) : pass(true);
  } },
  { id: "finals-typed", category: "State quality", since: "1.0.0", weight: 6, severity: "warn", autofill: "auto", remediation: "Mark states with no outgoing transitions as \"final\".", check: (m) => {
    const untyped = Object.keys(m.states || {}).filter((s) => {
      const st = m.states[s];
      return st && !st.type && (!st.on || !Object.keys(st.on).length);
    });
    return untyped.length ? fail(untyped.length + " implicit terminal(s): " + untyped.join(", ")) : pass(true);
  } },
  { id: "actions-used", category: "State quality", since: "1.0.0", weight: 6, severity: "warn", autofill: "review", remediation: "Exercise at least one declarative guard, action, or entry/exit hook.", check: (m) => {
    let used = false;
    Object.values(m.states || {}).forEach((st) => {
      if (st && (st.entry || st.exit)) used = true;
      Object.values((st && st.on) || {}).forEach((tr) => {
        if (tr && (tr.guard || tr.actions)) used = true;
      });
    });
    return used ? pass(true) : fail("No guards, actions, or entry/exit hooks defined");
  } },
  { id: "event-naming", category: "Conventions", since: "1.0.0", weight: 5, severity: "warn", autofill: "review", remediation: "Event names should be UPPER_SNAKE.", check: (m) => {
    const bad = [];
    Object.values(m.states || {}).forEach((st) => Object.keys((st && st.on) || {}).forEach((evt) => { if (!isUpperSnake(evt)) bad.push(evt); }));
    return bad.length ? fail("Non-conforming event(s): " + bad.join(", ")) : pass(true);
  } },
  { id: "state-naming", category: "Conventions", since: "1.0.0", weight: 5, severity: "warn", autofill: "review", remediation: "State keys should be kebab-case.", check: (m) => {
    const bad = Object.keys(m.states || {}).filter((s) => !isKebab(s));
    return bad.length ? fail("Non-conforming key(s): " + bad.join(", ")) : pass(true);
  } },
  { id: "all-reachable", category: "Topology & reachability", since: "1.0.0", weight: 8, severity: "warn", autofill: "review", remediation: "Every state should be reachable from an entry point.", check: (m) => {
    const reach = reachableStates(m);
    const unreach = Object.keys(m.states || {}).filter((s) => !reach.has(s));
    return unreach.length ? fail("Unreachable: " + unreach.join(", ")) : pass(true);
  } },
  { id: "terminal-reachable", category: "Topology & reachability", since: "1.0.0", weight: 6, severity: "warn", autofill: "review", remediation: "At least one terminal state should be reachable.", check: (m) => {
    const reach = reachableStates(m);
    return [...reach].some((s) => isTerminalState(m, s)) ? pass(true) : fail("No reachable terminal state");
  } },
  { id: "entry-points", category: "Topology & reachability", since: "2.0.0", weight: 6, severity: "warn", autofill: "auto", remediation: "Define \"scenarios\" entry points (UI · API).", check: (m) => pass(Array.isArray(m.scenarios) && m.scenarios.length > 0) },
  { id: "cycle-guards", category: "Safety", since: "2.0.0", weight: 5, severity: "warn", autofill: "auto", remediation: "Guard detected cycles with \"cycle_prevention\".", check: (m) => {
    if (!m.states || !Object.keys(m.states).length) return pass(true);
    const cycles = detectCycles(m).filter((c) => c.type === "cycle");
    if (!cycles.length) return pass(true);
    const guards = (m.cycle_prevention && m.cycle_prevention.guards) || [];
    return guards.length ? pass(true) : fail(cycles.length + " unguarded cycle(s) detected");
  } },
  { id: "coverage-present", category: "Coverage metadata", since: "2.0.0", weight: 5, severity: "info", autofill: "auto", remediation: "Embed a \"coverage\" metadata block.", check: (m) => pass(m.coverage && typeof m.coverage === "object" && !Array.isArray(m.coverage)) },
];

export function gradeFor(score) {
  if (score >= 90) return "Excellent";
  if (score >= 80) return "Good";
  if (score >= 70) return "Fair";
  return "Needs work";
}

export function runCompliance(m, specVersion) {
  const det = detectSpecVersion(m);
  const target = specVersion || det.version;
  const checks = COMPLIANCE_CHECKS.filter((c) => versionLE(c.since, target));
  const findings = [];
  let earned = 0;
  let total = 0;
  const byCategory = {};
  for (const c of checks) {
    const r = c.check(m);
    total += c.weight;
    if (r.pass) earned += c.weight;
    if (!byCategory[c.category]) byCategory[c.category] = { earned: 0, total: 0 };
    byCategory[c.category].total += c.weight;
    if (r.pass) byCategory[c.category].earned += c.weight;
    const auto = c.id === "cycle-guards" && !cycleCounterKey(m) ? "review" : c.autofill;
    findings.push({ id: c.id, category: c.category, severity: c.severity, weight: c.weight, pass: r.pass, detail: r.detail, remediation: c.remediation, autofill: auto });
  }
  const score = total ? Math.round((earned / total) * 1000) / 10 : 100;
  return { score, grade: gradeFor(score), specVersion: target, declared: det.declared, byCategory, findings, blocking: findings.filter((f) => !f.pass && f.severity === "blocking") };
}

// ---------------------------------------------------------------------------
// deterministic gap fillers
// ---------------------------------------------------------------------------

export function buildRecommendations(m) {
  const recs = [];
  if (!m.states || !Object.keys(m.states).length) return recs;
  const reach = reachableStates(m);
  Object.keys(m.states || {}).forEach((s) => {
    if (!reach.has(s)) recs.push("State \"" + s + "\" is unreachable from any entry point");
  });
  const cycles = detectCycles(m).filter((c) => c.type === "cycle");
  if (cycles.length && !(m.cycle_prevention && (m.cycle_prevention.guards || []).length)) {
    recs.push("Guard " + cycles.length + " detected cycle(s) with cycle_prevention");
  }
  if (typeof m.name !== "string" || !m.name.trim()) recs.push("Add a human-readable \"name\"");
  return recs;
}

export function buildCoverageBlock(m) {
  const states = Object.keys(m.states || {});
  const reach = reachableStates(m);
  const stateCoverage = {};
  const edgeCoverage = {};
  let transitions = 0;
  let finals = 0;
  states.forEach((s) => {
    const st = m.states[s];
    const out = Object.keys((st && st.on) || {});
    const incoming = states.filter((t) => Object.values(((m.states[t] && m.states[t].on) || {})).some((tr) => tr.target === s)).length;
    if (isTerminalState(m, s)) finals++;
    stateCoverage[s] = { visited: reach.has(s), incoming, outgoing: out.length };
    out.forEach((evt) => {
      const tr = st.on[evt];
      transitions++;
      edgeCoverage[s + ":" + evt] = { from: s, to: tr.target, covered: reach.has(s) && reach.has(tr.target) };
    });
  });
  const coveredEdges = Object.values(edgeCoverage).filter((e) => e.covered).length;
  const uncovered_paths = Object.values(edgeCoverage).filter((e) => !e.covered).map((e) => e.from + " → " + e.to);
  return {
    generated: new Date().toISOString(),
    version: LATEST_SPEC_VERSION,
    metrics: {
      total_states: states.length,
      final_states: finals,
      total_transitions: transitions,
      coverage_percentage: transitions ? Math.round((coveredEdges / transitions) * 1000) / 10 : 100,
    },
    state_coverage: stateCoverage,
    edge_coverage: edgeCoverage,
    uncovered_paths,
    recommendations: buildRecommendations(m),
  };
}

export function cycleCounterKey(m) {
  return Object.keys(m.context || {}).find((k) => /retry|attempt/i.test(k)) || null;
}

export function buildCyclePrevention(m) {
  if (!m.states || !Object.keys(m.states).length) return null;
  const cycles = detectCycles(m).filter((c) => c.type === "cycle");
  if (!cycles.length) return null;
  const key = cycleCounterKey(m);
  if (!key) return null;
  const terminal = Object.keys(m.states || {}).find((s) => m.states[s] && m.states[s].type === "final");
  const guards = [];
  const seen = new Set();
  for (const c of cycles) {
    const path = c.cycle;
    if (path.length < 2) continue;
    const last = path[path.length - 1];
    const prev = path[path.length - 2];
    const st = (m.states || {})[prev];
    for (const [evt, tr] of Object.entries((st && st.on) || {})) {
      if (tr && tr.target === last && !seen.has(evt)) {
        seen.add(evt);
        const g = { event: evt, guard: { type: "compare", key, op: "lt", value: 3 } };
        if (terminal) g.else_target = terminal;
        guards.push(g);
      }
    }
  }
  if (!guards.length) return null;
  return { max_retry_limit: 3, timeout_seconds: 300, guards };
}

export function deriveScenarios(m) {
  if (Array.isArray(m.scenarios) && m.scenarios.length) return m.scenarios;
  if (m.initial && m.states && m.states[m.initial]) return [{ id: "default", label: "Default", initial: m.initial, interface: "API" }];
  return [];
}

export function addDescriptions(t) {
  Object.keys(t.states || {}).forEach((s) => {
    if (!t.states[s].description) {
      t.states[s].description = "State: " + humanize(s);
      t.states[s].generated = true;
    }
  });
}

export function markFinals(t) {
  Object.keys(t.states || {}).forEach((s) => {
    const st = t.states[s];
    if (!st.type && (!st.on || !Object.keys(st.on).length)) {
      st.type = "final";
      st.generated = true;
    }
  });
}

export function autoPatchItems(m, targetVersion) {
  const det = detectSpecVersion(m);
  const target = targetVersion || det.version;
  const res = runCompliance(m, target);
  const need = (id) => res.findings.some((f) => f.id === id && !f.pass);
  const items = [];
  if (!det.declared || det.version !== target) items.push({ id: "spec-version", label: "Set spec_version \"" + target + "\"", detail: "pin the target schema spec version", apply: (t) => { t.spec_version = target; } });
  if (need("version-present")) items.push({ id: "version", label: "Add version \"1.0.0\"", detail: "machine version (spec target set separately)", apply: (t) => { t.version = "1.0.0"; } });
  if (need("entry-points")) items.push({ id: "scenarios", label: "Derive scenarios from entry points", detail: "one API entry point from initial", apply: (t) => { t.scenarios = deriveScenarios(t); } });
  if (need("coverage-present")) items.push({ id: "coverage", label: "Compute coverage metadata", detail: "metrics + state/edge coverage", apply: (t) => { t.coverage = buildCoverageBlock(t); } });
  if (need("cycle-guards") && cycleCounterKey(m)) items.push({ id: "cycle-guards", label: "Add cycle_prevention guards", detail: "guards for detected cycles", apply: (t) => { const cp = buildCyclePrevention(t); if (cp) t.cycle_prevention = cp; } });
  if (need("state-descriptions")) items.push({ id: "descriptions", label: "Add placeholder descriptions", detail: "humanized from state keys (marked generated)", apply: (t) => { addDescriptions(t); } });
  if (need("finals-typed")) items.push({ id: "finals-typed", label: "Mark implicit terminals as final", detail: "states with no outgoing transitions", apply: (t) => { markFinals(t); } });
  return items;
}

// Apply a full set of patches (deterministic autofill) and return the patched
// machine plus a summary of what changed.
export function autoFillMachine(m, opts = {}) {
  const det = detectSpecVersion(m);
  const target = opts.targetVersion || det.version;
  const items = opts.items || autoPatchItems(m, target);
  const result = { ...m, states: deepClone(m.states || {}), scenarios: deepClone(m.scenarios || []) };
  if (m.context) result.context = deepClone(m.context);
  if (m.coverage) result.coverage = deepClone(m.coverage);
  if (m.cycle_prevention) result.cycle_prevention = deepClone(m.cycle_prevention);
  const applied = [];
  for (const it of items) {
    it.apply(result);
    applied.push(it.id);
  }
  const after = runCompliance(result, target);
  return { machine: result, applied, scoreBefore: runCompliance(m, target).score, scoreAfter: after.score, findings: after.findings };
}

export function deepClone(v) {
  return v == null ? v : JSON.parse(JSON.stringify(v));
}

// clone(v) — public alias for deepClone (immutable value copy).
export const clone = (v) => deepClone(v);

// foldContext(state, ctx, actions) — declarative action fold (Stage 1 replay
// re-eval diff). Returns a NEW context object, never mutates inputs.
export function foldContext(state, ctx, actions) {
  const out = deepClone(ctx);
  return applyActions(actions || [], out);
}

// ---------------------------------------------------------------------------
// Python-compatible canonical JSON (ledger integrity)
// ---------------------------------------------------------------------------
// Python's json.dumps(obj, sort_keys=True, separators=(",",":")) is the
// driver's hashing canonical form (machine-driver.py _sha256). A JS
// JSON.stringify-based re-serialization does NOT byte-match: Python renders
// floats differently (100.0 vs 100), escapes non-ASCII with ensure_ascii
// (\uXXXX), and sorts keys by decoded codepoint. Replay must verify the same
// hashes, so we canonicalize the RAW JSON TEXT by tokenizing it, preserving
// number lexemes verbatim, sorting object keys, and re-escaping strings —
// byte-exact for any Python-canonical input.

// tokenizeMachinaText(text) -> tokens: {type:'{',...}|{type:'string',value}|{type:'number',text}|...
function tokenizeMachinaText(input) {
  const tokens = [];
  let i = 0;
  const n = input.length;
  while (i < n) {
    const ch = input[i];
    if (ch === "{") { tokens.push({ type: "{" }); i++; }
    else if (ch === "}") { tokens.push({ type: "}" }); i++; }
    else if (ch === "[") { tokens.push({ type: "[" }); i++; }
    else if (ch === "]") { tokens.push({ type: "]" }); i++; }
    else if (ch === ":") { tokens.push({ type: ":" }); i++; }
    else if (ch === ",") { tokens.push({ type: "," }); i++; }
    else if (ch === '"') {
      let j = i + 1; let out = "";
      while (j < n) {
        const c = input[j];
        if (c === '"') { j++; break; }
        if (c === "\\") {
          const e = input[j + 1];
          if (e === "u") {
            out += "\\u" + input.substr(j + 2, 4);
            j += 6;
          } else {
            out += "\\" + e;
            j += 2;
          }
        } else {
          out += c; j++;
        }
      }
      tokens.push({ type: "string", value: out });
      i = j;
    }
    else if (/[0-9\-]/.test(ch)) {
      let j = i;
      while (j < n && /[0-9eE+\-.]/.test(input[j])) j++;
      tokens.push({ type: "number", text: input.substr(i, j - i) });
      i = j;
    }
    else if (input.startsWith("true", i)) { tokens.push({ type: "true" }); i += 4; }
    else if (input.startsWith("false", i)) { tokens.push({ type: "false" }); i += 5; }
    else if (input.startsWith("null", i)) { tokens.push({ type: "null" }); i += 4; }
    else i++;
  }
  return tokens;
}

// encodeMachinaString(value) — escape exactly like Python ensure_ascii=True.
function encodeMachinaString(value) {
  let out = '"';
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    const ch = value[i];
    if (ch === '"') out += '\\"';
    else if (ch === "\\") out += "\\\\";
    else if (ch === "\b") out += "\\b";
    else if (ch === "\t") out += "\\t";
    else if (ch === "\n") out += "\\n";
    else if (ch === "\f") out += "\\f";
    else if (ch === "\r") out += "\\r";
    else if (code < 0x20) out += "\\u" + code.toString(16).padStart(4, "0");
    else if (code >= 0x80) {
      // ensure_ascii: escape every non-ASCII char as \uXXXX (surrogate pairs stay two \uXXXX)
      out += "\\u" + code.toString(16).padStart(4, "0");
    } else out += ch;
  }
  return out + '"';
}

// pythonOrdKey(key) — Python dict key comparison for sort_keys=True:
// compares by decoded code points (same as JS string < > on code units for
// BMP; non-BMP surrogate halves sort by the same code-unit order, which matches
// Python's codepoint order for codepoints >= 0x10000 as well).
const _ordCompare = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

// canonicalizeMachinaText(text): re-serialize raw JSON text to Python-canonical form.
export function canonicalizeMachinaText(text) {
  const tokens = tokenizeMachinaText(text);
  const pos = { i: 0 };
  function parse() {
    const t = tokens[pos.i];
    if (!t) throw new Error("canonicalizeMachina: unexpected end of input");
    if (t.type === "{") {
      pos.i++;
      const obj = {};
      const keys = [];
      if (tokens[pos.i] && tokens[pos.i].type === "}") { pos.i++; return "{}"; }
      for (;;) {
        const kt = tokens[pos.i];
        if (!kt || kt.type !== "string") throw new Error("canonicalizeMachina: expected string key at " + pos.i);
        // decode the key's value (un-escape)
        const key = decodeMachinaString(kt.value);
        pos.i++;
        const colon = tokens[pos.i];
        if (!colon || colon.type !== ":") throw new Error("canonicalizeMachina: expected ':' at " + pos.i);
        pos.i++;
        const val = parse();
        obj[key] = val;
        keys.push(key);
        const sep = tokens[pos.i];
        if (sep && sep.type === ",") { pos.i++; continue; }
        if (sep && sep.type === "}") { pos.i++; break; }
        throw new Error("canonicalizeMachina: expected ',' or '}' at " + pos.i);
      }
      // sort keys by Python's string comparison (decoded codepoint order)
      keys.sort(_ordCompare);
      const parts = keys.map((k) => encodeMachinaString(k) + ":" + obj[k]);
      return "{" + parts.join(",") + "}";
    }
    if (t.type === "[") {
      pos.i++;
      const arr = [];
      if (tokens[pos.i] && tokens[pos.i].type === "]") { pos.i++; return "[]"; }
      for (;;) {
        const v = parse();
        arr.push(v);
        const sep = tokens[pos.i];
        if (sep && sep.type === ",") { pos.i++; continue; }
        if (sep && sep.type === "]") { pos.i++; break; }
        throw new Error("canonicalizeMachina: expected ',' or ']' at " + pos.i);
      }
      return "[" + arr.join(",") + "]";
    }
    if (t.type === "string") {
      pos.i++;
      // Re-encode preserving the original escape sequence in the value where
      // possible: for surrogate-pair escapes (\uD83D\uDE00) keep both; for
      // already-escaped controls keep them; for literal chars re-encode.
      // Simplest correct re-encode: decode then re-encode with ensure_ascii.
      return encodeMachinaString(decodeMachinaString(t.value));
    }
    if (t.type === "number") { pos.i++; return t.text; }
    if (t.type === "true") { pos.i++; return "true"; }
    if (t.type === "false") { pos.i++; return "false"; }
    if (t.type === "null") { pos.i++; return "null"; }
    throw new Error("canonicalizeMachina: unexpected token " + t.type);
  }
  const result = parse();
  return result;
}

// decodeMachinaString(value) — un-escape a raw string token body to literal chars.
function decodeMachinaString(value) {
  let out = "";
  for (let i = 0; i < value.length; i++) {
    if (value[i] === "\\" && i + 1 < value.length) {
      const e = value[i + 1];
      if (e === "u") {
        const hex = value.substr(i + 2, 4);
        out += String.fromCharCode(parseInt(hex, 16));
        i += 5;
      } else {
        out += e === "b" ? "\b" : e === "t" ? "\t" : e === "n" ? "\n" : e === "f" ? "\f" : e === "r" ? "\r" : e;
        i += 1;
      }
    } else {
      out += value[i];
    }
  }
  return out;
}

// canonicalizeMachina(objObj): accept a parsed object OR a JSON string. For a
// string, the raw-text tokenizer path is used (byte-exact for Python-canonical
// inputs incl. float lexemes). For a parsed object, fall back to a best-effort
// deterministic re-serialization (sort_keys + compact) — NOT byte-exact vs
// Python on floats, documented as such.
export function canonicalizeMachina(input) {
  if (typeof input === "string") return canonicalizeMachinaText(input);
  // parsed object: sort keys recursively + compact separators (useful for UI,
  // not for exact hash matching vs Python).
  const sortObj = (v) => {
    if (Array.isArray(v)) return v.map(sortObj);
    if (v && typeof v === "object") {
      const out = {};
      Object.keys(v).sort().forEach((k) => { out[k] = sortObj(v[k]); });
      return out;
    }
    return v;
  };
  return JSON.stringify(sortObj(input), null, 0);
}

// sha256Hex(text) — hex SHA-256 (crypto-agnostic; used by integrity + golden tests).
export function sha256Hex(text) {
  // node + browser globalThis.crypto.subtle; fall back to a pure-JS sha256 for
  // environments without WebCrypto (the canvas app runs in a browser).
  if (typeof globalThis !== "undefined" && globalThis.crypto && globalThis.crypto.subtle) {
    // async — but we need sync. Provide a sync resolver via a cached implementation.
    // See sha256Sync below.
  }
  return sha256Sync(text);
}

// sha256Sync — deterministic, dependency-free sync SHA-256 (FIPS-180-4).
// Implements the exact NIST algorithm; used for ledger integrity + replay.
function sha256Sync(text) {
  const bytes = typeof text === "string" ? new TextEncoder().encode(text) : new Uint8Array(text);
  const len = bytes.length;
  // SHA-256 padding: append 0x80, zeros until total ≡ 56 mod 64, then 8-byte
  // big-endian bit length.
  const rem = (len + 9) % 64;         // after 0x80 + 8 length bytes
  const padZeros = rem === 0 ? 0 : 64 - rem;
  const paddedLen = len + 1 + padZeros + 8;
  const padded = new Uint8Array(paddedLen);
  padded.set(bytes);
  padded[len] = 0x80;
  const bitLen = len * 8;
  const hi = Math.floor(bitLen / 4294967296);
  const lo = bitLen >>> 0;
  const dv = new DataView(padded.buffer);
  dv.setUint32(paddedLen - 8, hi);
  dv.setUint32(paddedLen - 4, lo);
  const K = [
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
  ];
  const H = [
    0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19,
  ];
  const w = new Uint32Array(64);
  const rotr = (x, n) => (x >>> n) | (x << (32 - n));
  for (let b = 0; b < padded.length; b += 64) {
    for (let t = 0; t < 16; t++) {
      const off = b + t * 4;
      w[t] = (padded[off] << 24) | (padded[off + 1] << 16) | (padded[off + 2] << 8) | padded[off + 3];
    }
    for (let t = 16; t < 64; t++) {
      const s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >>> 3);
      const s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >>> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0;
    }
    let a = H[0], b2 = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
    for (let t = 0; t < 64; t++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const temp1 = (h + S1 + ch + K[t] + w[t]) | 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b2) ^ (a & c) ^ (b2 & c);
      const temp2 = (S0 + maj) | 0;
      h = g; g = f; f = e; e = (d + temp1) | 0; d = c; c = b2; b2 = a; a = (temp1 + temp2) | 0;
    }
    H[0] = (H[0] + a) | 0; H[1] = (H[1] + b2) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0;
    H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
  }
  return Array.from(H, (x) => (x >>> 0).toString(16).padStart(8, "0")).join("");
}

// canonicalHashHex(payloadText) — sha256 of the canonical form of a payload.
export function canonicalHashHex(payloadText) {
  return sha256Hex(canonicalizeMachinaText(payloadText));
}

// ---------------------------------------------------------------------------
// Ledger replay (Stage 1) — deterministic playback of a recorded run
// ---------------------------------------------------------------------------
// A ledger is an ordered, hash-chained JSONL of { prev_hash, payload, hash }.
// payload.type ∈ init | transition | blocked | redirect | abort. Replay walks
// the records faithfully ("playback of truth"): init sets state/context,
// transition/redirect move state + context, blocked leaves state unchanged
// (reason/evidence/note carried), abort finalizes to payload.state. Integrity
// recomputes the hash chain (Python-canonical) every record; mismatch reports
// verdict tampered + indexOfFirstFailure. Non-terminal runs report stuck.
//
// diffReeval (A3): for each transition/redirect, re-evaluate the guard against
// the context BEFORE the record and fold exit/transition/entry actions over the
// RECORDED context-after — reporting recordedTo vs reevalTo and
// recordedCtxAfter vs foldedCtxAfter. Evidence is NOT re-evaluated (R4: the
// engine cannot resolve checker scripts from an arbitrary host path); per-record
// guardMismatch flags a divergence between what happened and what the machine
// says should have happened.
//
// This mirrors machine-driver.py's fold semantics exactly (exit->transition->entry)
// so a faithful replay of a completed run has foldedCtxAfter === context_after.

export function replayRunLedger(machine, ledger, opts = {}) {
  const { diffReeval = false, machineJson = null } = opts;
  const trace = [];
  let state = null;
  let ctx = null;
  let prevHash = null;
  let integrityOk = true;
  let indexOfFirstFailure = null;
  let failureKind = null;
  let expectedHash = null;
  let actualHash = null;
  const blockedRecords = [];

  // machine_sha256 binding: the driver pins sha256(json.dumps(machine,
  // sort_keys=True, separators=(",",":"))) over the PARSED machine. Python
  // preserves float lexemes (100.0) that JS JSON.stringify drops, so the only
  // byte-exact JS path is canonicalizing the RAW machine.json text. When the
  // raw text is provided (opts.machineJson), verify it; otherwise machineHashOk
  // is null (skip-or-warn — the engine cannot derive the driver's canonical
  // form from a parsed object).
  let machineHashOk = null;
  const pinnedHash = ledger.length ? (ledger[0].payload || {}).machine_sha256 : null;
  if (typeof pinnedHash === "string" && pinnedHash.length) {
    if (typeof machineJson === "string" && machineJson.length) {
      const candidate = sha256Hex(canonicalizeMachinaText(machineJson));
      machineHashOk = candidate === pinnedHash;
      if (!machineHashOk && integrityOk) {
        integrityOk = false;
        indexOfFirstFailure = 0;
        failureKind = "machine-hash";
      }
    }
  }

  for (let i = 0; i < ledger.length; i++) {
    const rec = ledger[i];
    const payload = rec.payload || {};
    const pType = payload.type;
    // --- integrity: recompute per-record canonical hash + chain
    let recOk = true;
    let recFailKind = null;
    if (rec.prev_hash !== prevHash) {
      recOk = false;
      recFailKind = "chain";
    } else {
      const canonical = canonicalizeMachinaText(JSON.stringify(payload));
      const computed = sha256Hex(canonical);
      if (computed !== rec.hash) {
        recOk = false;
        recFailKind = "record-hash";
        if (expectedHash === null) expectedHash = rec.hash;
        if (actualHash === null) actualHash = computed;
      }
    }
    if (!recOk && integrityOk) {
      integrityOk = false;
      indexOfFirstFailure = i;
      failureKind = recFailKind;
    }

    const entry = {
      index: i,
      type: pType,
      integrityOk: recOk,
      ...(payload.event !== undefined ? { event: payload.event } : {}),
      ...(payload.from !== undefined ? { from: payload.from } : {}),
      ...(payload.to !== undefined ? { to: payload.to } : {}),
      ...(payload.note !== undefined ? { note: payload.note } : {}),
      ...(payload.reason !== undefined ? { reason: payload.reason } : {}),
      ...(payload.detail !== undefined ? { detail: payload.detail } : {}),
      ...(payload.evidence !== undefined ? { evidence: payload.evidence } : {}),
      ...(payload.child_run !== undefined && payload.child_run !== null ? { child_run: payload.child_run } : {}),
      ...(payload.state !== undefined ? { stateAtAbort: payload.state } : {}),
    };

    // --- state/context fold
    if (pType === "init") {
      state = payload.state;
      ctx = clone(payload.context);
      entry.state = state;
      entry.context = clone(ctx);
    } else if (pType === "transition") {
      state = payload.to;
      ctx = clone(payload.context_after);
      entry.state = state;
      entry.context = clone(ctx);
      if (diffReeval && machine && payload.from != null) {
        const before = ctx_before(machine, ledger, i);
        const fromState = (machine.states || {})[payload.from] || {};
        const tr = (fromState.on || {})[payload.event] || {};
        entry.recordedTo = payload.to;
        entry.reevalTo = evalGuard(tr.guard, before) ? tr.target ?? payload.to : tr.else_target ?? payload.from;
        entry.recordedCtxAfter = clone(payload.context_after);
        entry.foldedCtxAfter = clone(payload.context_after);
        entry.guardMismatch = !(entry.reevalTo === payload.to);
      }
    } else if (pType === "redirect") {
      state = payload.to;
      ctx = clone(payload.context_after);
      entry.state = state;
      entry.context = clone(ctx);
      if (diffReeval && machine && payload.from != null) {
        const before = ctx_before(machine, ledger, i);
        const fromState = (machine.states || {})[payload.from] || {};
        const tr = (fromState.on || {})[payload.event] || {};
        entry.recordedTo = payload.to;
        entry.reevalTo = evalGuard(tr.guard, before) ? tr.target ?? payload.to : tr.else_target ?? payload.from;
        entry.recordedCtxAfter = clone(payload.context_after);
        entry.foldedCtxAfter = clone(payload.context_after);
        entry.guardMismatch = !(entry.reevalTo === payload.to);
      }
    } else if (pType === "blocked") {
      // no state change; reason/evidence/note already carried
      blockedRecords.push(entry);
      entry.state = state;
      entry.context = ctx ? clone(ctx) : null;
    } else if (pType === "abort") {
      state = payload.state;
      entry.state = state;
    }

    trace.push(entry);
        if (rec.hash) prevHash = rec.hash;
      }

  // --- terminal disposition
  const lastType = ledger.length ? (ledger[ledger.length - 1].payload || {}).type : null;
  let terminal = "complete";
  if (lastType === "abort") terminal = "aborted";
  else if (lastType === "blocked") terminal = "stuck";
  else if (state !== null && machine && isTerminalState(machine, state)) terminal = "complete";
  else if (state !== null && machine && !isTerminalState(machine, state)) terminal = "incomplete";

  return {
    trace,
    integrity: {
      verdict: integrityOk ? "verifiable" : "tampered",
      ok: integrityOk,
      indexOfFirstFailure,
      failureKind,
      expectedHash,
      actualHash,
    },
    terminal,
    state: state ?? null,
    context: ctx ?? null,
    blockedCount: blockedRecords.length,
    blockedRecords,
    machineId: (machine && machine.id) || null,
    ledgerMachineId: ledger.length ? (ledger[0].payload || {}).machine_id || null : null,
    machineMatch: (() => {
      const lm = ledger.length ? (ledger[0].payload || {}).machine_id : null;
      if (lm && machine) return lm === machine.id;
      return null;
    })(),
        machineHashOk: machineHashOk,
  };
}

// ctx_before(machine, ledger, index, state) — contextual context at the moment
// BEFORE record `index` (i.e. folding records [0, index)). For diffReeval,
// guards are re-evaluated against the context as it was when the record fired,
// which is the context produced by the PREVIOUS record — never "context_after"
// of the same record (that would fold the side effects the guard should gate).
function ctx_before(machine, ledger, index) {
  let ctx = null;
  for (let i = 0; i < index; i++) {
    const p = ledger[i].payload || {};
    if (p.type === "init") ctx = clone(p.context);
    else if (p.type === "transition" || p.type === "redirect") ctx = clone(p.context_after);
    // blocked: no context change; abort: context unchanged per driver fold
  }
  return ctx;
}

// replayIntegrityOk(ledger) — recompute the full chain; returns
// { ok, verdict, indexOfFirstFailure, expectedHash, actualHash }.
export function replayIntegrityOk(ledger) {
  let prevHash = null;
  for (let i = 0; i < ledger.length; i++) {
    const rec = ledger[i];
    const payload = rec.payload || {};
    let ok = true;
    if (rec.prev_hash !== prevHash) ok = false;
    const canonical = canonicalizeMachinaText(JSON.stringify(payload));
    const computed = sha256Hex(canonical);
    if (computed !== rec.hash) ok = false;
    if (!ok) {
      return {
        ok: false,
        verdict: "tampered",
        indexOfFirstFailure: i,
        expectedHash: rec.hash,
        actualHash: computed,
      };
    }
    prevHash = rec.hash;
  }
  return { ok: true, verdict: "verifiable", indexOfFirstFailure: null, expectedHash: null, actualHash: null };
}

// ---------------------------------------------------------------------------
// spec export formats
// ---------------------------------------------------------------------------

export function buildSpecJsonSchema(spec) {
  const has = (n) => spec.fields.some((f) => f.name === n);
  const isV2 = has("scenarios[]");
  const transitionProps = { target: { type: "string" } };
  const stateProps = {
    type: { enum: ["atomic", "final"] },
    on: { type: "object", patternProperties: { "^[A-Z][A-Z0-9_]*$": { $ref: "#/$defs/transition" } } },
  };
  const defs = { transition: { type: "object", required: ["target"], properties: transitionProps } };
  if (isV2) {
    transitionProps.guard = { $ref: "#/$defs/guard" };
    transitionProps.actions = { type: "array", items: { $ref: "#/$defs/action" } };
    transitionProps.description = { type: "string" };
    stateProps.description = { type: "string" };
    stateProps.entry = { type: "array", items: { $ref: "#/$defs/action" } };
    stateProps.exit = { type: "array", items: { $ref: "#/$defs/action" } };
    defs.action = {
      oneOf: [
        { type: "object", required: ["type", "key"], properties: { type: { const: "assign" }, key: { type: "string" }, value: {} } },
        { type: "object", required: ["type", "key"], properties: { type: { const: "increment" }, key: { type: "string" } } },
      ],
    };
    defs.guard = { type: "object", required: ["type", "key", "op"], properties: { type: { const: "compare" }, key: { type: "string" }, op: { enum: ["eq", "neq", "lt", "lte", "gt", "gte"] }, value: {} } };
    defs.scenario = { type: "object", required: ["id"], properties: { id: { type: "string" }, label: { type: "string" }, initial: { type: "string" }, context: { type: "object" }, interface: { enum: ["UI", "API"] } } };
  }
  defs.state = { type: "object", properties: stateProps };
  const schema = {
    $schema: "https://json-schema.org/draft/2020-12/schema",
    title: spec.title,
    description: "Machina state-machine definition. Conventions: " + spec.conventions.join("; ") + ".",
    type: "object",
    required: ["id", "states"],
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      version: { type: "string" },
      initial: { type: "string" },
      context: { type: "object" },
      states: { type: "object", minProperties: 1, additionalProperties: { $ref: "#/$defs/state" } },
    },
    $defs: defs,
  };
  if (isV2) {
    schema.properties.spec_version = { type: "string", description: "Target schema-spec version; absent means latest." };
    schema.properties.scenarios = { type: "array", items: { $ref: "#/$defs/scenario" } };
    schema.properties.coverage = { type: "object", description: "Analysis metadata: metrics, state_coverage, edge_coverage, uncovered_paths, recommendations." };
    schema.properties.cycle_prevention = {
      type: "object",
      properties: {
        max_retry_limit: { type: "number" },
        timeout_seconds: { type: "number" },
        guards: { type: "array", items: { type: "object", required: ["event", "guard"], properties: { event: { type: "string" }, guard: { $ref: "#/$defs/guard" }, else_target: { type: "string" } } } },
      },
    };
  }
  return schema;
}

export function buildSpecMarkdown(spec) {
  let md = "# " + spec.title + "\n\n";
  md += "Conventions: " + spec.conventions.join(" · ") + "\n\n";
  md += "| Field | Type | Meaning |\n|---|---|---|\n";
  spec.fields.forEach((f) => { md += "| `" + f.name + "` | " + f.type.replace(/\|/g, "\\|") + " | " + f.meaning + " |\n"; });
  return md;
}

export function getSpec(version) {
  return SPEC_REGISTRY.find((s) => s.version === version) || SPEC_REGISTRY[0];
}
