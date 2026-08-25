// Machina State-Machine engine — dependency-free, testable.
// Faithful port of the compliance/scoring/autofill engine from the canonical
// Machina simulator, shared by the Copilot tools and the simulator app
// (the app imports this module as /engine.mjs). See
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

function deepClone(v) {
  return v == null ? v : JSON.parse(JSON.stringify(v));
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
