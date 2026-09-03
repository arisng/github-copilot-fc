# Machina Schema Spec Reference

Machine JSON shape, guard/action semantics, SPEC_REGISTRY, and spec export formats.

## Contents

1. [Versioning model](#versioning-model)
2. [v2.0.0 field reference](#v200-field-reference-current)
3. [v1.0.0 (historical)](#v100-historical)
4. [Runtime semantics](#runtime-semantics)
5. [SPEC_REGISTRY & detection](#spec_registry--detection)
6. [Spec browser & export formats](#spec-browser--export-formats)
7. [Conventions](#conventions)

## Versioning model

Three independent version concepts — never conflate:

| Concept | Source of truth | Format | Who sets it | Surfaced |
|---|---|---|---|---|
| App version | `APP_VERSION` constant (one place, + one changelog comment) | semver | simulator dev, each release | topbar tagline, `data-app-version`, startup log |
| Schema spec version | `SPEC_REGISTRY` + `LATEST_SPEC_VERSION` | `x.y.z` | the in-app schema spec | spec browser, compliance header, upgrade banner |
| Machine version | machine's own `version` field | free-form string | machine author | stage header (`· vX`) |

Hard rules:

- Machine `version`: fully user-managed; autofill stamps `"1.0.0"` **only when missing** and never
  rewrites an existing value.
- `spec_version` must match a registry entry; absent ⇒ latest assumed. Pins the schema *contract*,
  not machine identity.
- `APP_VERSION` never affects scoring, the machine, or the registry. The localStorage prefs key
  (`machina.v1`) is the prefs-schema version and stays stable independently; bump to `machina.v2`
  only if prefs shape changes.

## v2.0.0 field reference (current)

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Stable machine identifier |
| `name` | string | Human-readable label |
| `version` | string | Machine's own version (distinct from `spec_version`) |
| `spec_version` | string | Optional target schema-spec version; absent ⇒ latest |
| `initial` | string | Default initial state key |
| `context` | object | Initial extended state |
| `scenarios[]` | array | `{ id, label, initial?, context?, interface? }`, `interface ∈ UI · API` |
| `states` | object | Keyed by state id: `{ type?, description?, entry?, exit?, on? }` |
| `state.type` | `"atomic" \| "final"` | Terminal states are `final` |
| `state.on` | object | `{ EVENT: { target, guard?, actions?, description? } }` |
| `action` | object | `{ type:"assign", key, value }` or `{ type:"increment", key }` |
| `guard` | object | `{ type:"compare", key, op, value }`, `op ∈ eq·neq·lt·lte·gt·gte` |
| `coverage` | object | Optional analysis metadata (metrics, state/edge coverage, uncovered_paths, recommendations) |
| `cycle_prevention` | object | Optional: `max_retry_limit`, `timeout_seconds`, `guards[] { event, guard, else_target }` |

v2.0.0 changelog: added `scenarios[]` (UI·API), declarative `action`/`guard`, `coverage`,
`cycle_prevention`, optional `spec_version`.

## v1.0.0 (historical)

Subset only: `id`, `name`, `version`, `initial`, `context`, `states` with `state.type` and
`state.on` where transitions are `{ EVENT: { target } }` only. No `scenarios`, `coverage`,
`cycle_prevention`. Preserve as a faithful subset so exports degrade correctly.

## Runtime semantics

- Guard evaluation (`evalGuard`): dotted-path context read (`getPath`); string `value` resolves
  against context keys first, then numeric coercion; unknown op → pass.
- Actions (`applyActions`): `increment` (+1 on dotted path, default 0); `assign` (set path).
- Firing order: exit actions → transition actions → target entry actions.
- Terminal: `type:"final"` or no outgoing transitions.

## SPEC_REGISTRY & detection

- `SPEC_REGISTRY`: JS constant, newest first (v2.0.0 then v1.0.0). New revisions append to the
  front; older machines are then automatically flagged for upgrade.
- `detectSpecVersion(m)`:
  1. If `m.spec_version` matches an entry → `{version, declared:true, assumed:false}`.
  2. Else → `{version: LATEST_SPEC_VERSION, declared:false, assumed:true}`.
- `specRank(v)` = registry index (0 = latest, higher = older).
- Upgrades remain **opt-in** via the banner; `spec-version` check stays weight-0 until the field
  becomes a hard requirement.

## Spec browser & export formats

Modal `#spec-modal`: version pills (`role="tab"`, arrow-key navigation), per-version changelog,
field table, conventions line. Browsing changes only the displayed table; scoring always uses the
machine's detected target.

Quick-copy buttons ("Copy JSON Schema", "Copy Markdown") copy the currently selected version via
`copySpecVersion(fmt)` → `buildSpecJsonSchema(spec)` / `buildSpecMarkdown(spec)` → clipboard with
`legacyCopy` fallback → toast `Copied spec v2.0.0 (JSON Schema)` / `… (Markdown)`. They work
regardless of whether a file is open and are secondary/ghost buttons (never a second primary).

**JSON Schema output:** draft 2020-12 with `$schema`, `title`, `description` (embedding the
conventions), `properties` per field, `required` = `id`, `states`, and `$defs` for `state`,
`transition`, and (v2+) `action`/`guard`/`scenario`. `patternProperties` encode UPPER_SNAKE event
names; `spec_version`/`scenarios`/`coverage`/`cycle_prevention` appear only in v2.0.0.

**Markdown output:** field table plus conventions line.

When evolving the registry, always update these builders together with the field table.

## Conventions

Event names `UPPER_SNAKE`; state keys `kebab-case`; guard `value` may reference context keys by
name.

## Ledger replay contract (machina-driving v3 runs)

A **run ledger** records a driven Machina run as an ordered, hash-chained JSONL consumed by
`machina_replay` / `replayRunLedger`:

```
{ "prev_hash": "<sha256 of prior record>|null", "payload": { … }, "hash": "<sha256 of payload>" }
```

- `hash = sha256(json.dumps(payload, sort_keys=True, separators=(",",":")))` — Python-canonical
  (byte-exact; the JS canonicalizer in `machine-simulator.mjs` re-serializes raw JSON text to match).
- The **first record's** `prev_hash` is `null`; each subsequent `prev_hash` equals the prior hash.
- Replay re-verifies the full chain + the `machine_sha256` pinned at `init`; verdict
  `verifiable | tampered` with `indexOfFirstFailure`.

### Record types (five)

| `type` | `payload` keys | State/context effect |
|---|---|---|
| `init` | `machine_id, spec_version, scenario, state, context, machine_dir, machine_sha256, tool_hashes, timestamp` | set state + context (entry actions already applied) |
| `transition` | `event, from, to, guard, evidence[], exit_actions, transition_actions[], entry_actions, context_after, note, child_run` | set state = `to`, context = `context_after` |
| `blocked` | `event, from, reason (guard·evidence·limit), detail?, evidence[], note` | no state change; reason/evidence carried |
| `redirect` | `event, from, to, reason, detail?, context_after, note` | set state = `to`, context = `context_after` (guard-failure to `else_target`) |
| `abort` | `state, reason, timestamp` | finalize; context unchanged |

### Semantics

- `child_run` resolves as a **sibling run** under the same family container (e.g.
  `Path(run_dir).parent / child_run`). Replay surfaces it as a nested badge; child-layout is a
  **data** concern (the parent run dir container), not re-derived in-engine.
- Non-terminal runs (final record is `blocked`) are not "complete": replay reports
  `terminal: stuck`, state unchanged.
- `diffReeval` (optional) re-evaluates `guard` per transition/redirect against the context
  **before** that record, reporting `guardMismatch` when recorded `to` ≠ re-evaluated target.
  Evidence/checker scripts are NOT re-run in-engine (they resolve against host paths the
  simulator cannot access) — `tool_hashes` are skip-or-warn.
