# Machina Compliance Scoring & Autofill Reference

The 17-check scoring model, findings shape, and deterministic "Generate missing" pipeline.

## Contents

1. [Scoring model](#scoring-model)
2. [Check registry](#check-registry)
3. [Result shape](#result-shape)
4. [Autofill pipeline](#autofill-pipeline--generate-missing)
5. [Deterministic builders (exact output)](#deterministic-builders-exact-output)
6. [Review-only items — never invented](#review-only-items--never-invented)
7. [Compliance modal UI](#compliance-modal-ui)
8. [In-app limits](#in-app-limits)
9. [Acceptance criteria](#acceptance-criteria)

## Scoring model

`runCompliance(m, targetVersion)` filters `COMPLIANCE_CHECKS` to those with `since ≤ target`,
then sums passing weights. **Score = round(earned/total × 1000)/10**, capped at 100.
Grade bands (`gradeFor`): **90+ Excellent · 80–89 Good · 70–79 Fair · <70 Needs work**.

Score is always labelled with its target spec version, e.g. "Compliance · spec v2.0.0
(assumed latest)".

## Check registry

17 checks; total weight must equal exactly **100** — any added/removed check must rebalance to 100.

| # | id | Category | Since | Wt | Severity | Autofill |
|---|---|---|---|---|---|---|
| 1 | `id-present` | Identity & metadata | 1.0.0 | 5 | blocking | review |
| 2 | `name-present` | Identity & metadata | 1.0.0 | 5 | warn | review |
| 3 | `version-present` | Identity & metadata | 1.0.0 | 5 | warn | auto |
| 4 | `spec-version` | Identity & metadata | 2.0.0 | 0 | info | auto |
| 5 | `states-present` | Structure & integrity | 1.0.0 | 10 | blocking | review |
| 6 | `initial-resolves` | Structure & integrity | 1.0.0 | 10 | blocking | review |
| 7 | `targets-resolve` | Structure & integrity | 1.0.0 | 5 | blocking | review |
| 8 | `state-descriptions` | State quality | 1.0.0 | 8 | warn | auto |
| 9 | `finals-typed` | State quality | 1.0.0 | 6 | warn | auto |
| 10 | `actions-used` | State quality | 1.0.0 | 6 | warn | review |
| 11 | `event-naming` | Conventions | 1.0.0 | 5 | warn | review |
| 12 | `state-naming` | Conventions | 1.0.0 | 5 | warn | review |
| 13 | `all-reachable` | Topology & reachability | 1.0.0 | 8 | warn | review |
| 14 | `terminal-reachable` | Topology & reachability | 1.0.0 | 6 | warn | review |
| 15 | `entry-points` | Topology & reachability | 2.0.0 | 6 | warn | auto |
| 16 | `cycle-guards` | Safety | 2.0.0 | 5 | warn | auto* |
| 17 | `coverage-present` | Coverage metadata | 2.0.0 | 5 | info | auto |

Category totals: Identity 15 · Structure 25 · State quality 20 · Conventions 10 ·
Topology 20 · Safety 5 · Coverage 5 = **100**.

Special cases:

- `spec-version` carries weight **0** (informational) until the field becomes a hard requirement.
- \* `cycle-guards` is `auto` only when `context` has a `retry`/`attempt` counter key
  (`cycleCounterKey`); otherwise its autofill downgrades to **review** and no counter is invented.

## Result shape

```js
{ score, grade, specVersion, declared, byCategory, findings, blocking }
```

`findings[]` = `{ id, category, severity, weight, pass, detail, remediation, autofill }`.
`blocking` = failing blocking-severity findings — surfaced as a red banner but does **not**
zero the score.

## Autofill pipeline ("Generate missing")

An auto-fill, **not** a code generator. `autoPatchItems(m, targetVersion)` collects failing `auto`
gaps into an ordered patch list `{ id, label, detail, apply }`. Fixed order:

| Order | id | Label | Writes |
|---|---|---|---|
| 1 | `spec-version` | Set `spec_version` | `t.spec_version = target` (when undeclared or mismatched) |
| 2 | `version` | Add `version` | `t.version = "1.0.0"` only when missing |
| 3 | `scenarios` | Derive scenarios | `deriveScenarios()` → `[{id:"default", label:"Default", initial, interface:"API"}]` |
| 4 | `coverage` | Compute coverage | `buildCoverageBlock()` |
| 5 | `cycle-guards` | Add cycle guards | `buildCyclePrevention()` (only with a genuine retry/attempt counter) |
| 6 | `descriptions` | Placeholder descriptions | `"State: " + humanize(key)`; marks state `generated:true` |
| 7 | `finals-typed` | Mark implicit finals | `type:"final"`; marks state `generated:true` |

Flow: "Generate missing" (primary button; disabled when only `review` gaps remain) →
`renderDiffPreview` checkbox list → Apply → `applyPatches`:
clone → apply selected → `loadMachine` → `markDirty()` → re-score → toast
"Applied N change(s) — unsaved".

## Deterministic builders (exact output)

- `buildCoverageBlock()` →
  `{ generated: ISO, version: LATEST,
     metrics:{ total_states, final_states, total_transitions, coverage_percentage },
     state_coverage:{ key:{visited,incoming,outgoing} },
     edge_coverage:{ "s:evt":{from,to,covered} },
     uncovered_paths:[], recommendations:[] }`
- `buildCyclePrevention()` →
  `{ max_retry_limit:3, timeout_seconds:300,
     guards:[{ event, guard:{type:"compare",key,op:"lt",value:3}, else_target? }] }`
  Only runs when `context` has a `/retry|attempt/` counter key (`cycleCounterKey`); returns
  `null` otherwise so the gap stays review-only. `else_target` points at a `final` state.

## Review-only items — never invented

New transitions; convention renames (destructive); `name` without a signal;
the `actions-used` check. The agent must never fabricate these via autofill.

## Compliance modal UI

`#compliance-modal`, reusing `.modal` / `.modal-head` / `.modal-body` / `.modal-foot`:

1. Score header — `cmp-score` / `cmp-num` colored success ≥80, warn 70–79, danger <70; grade;
   target spec version + assumed note; `cmp-bar`.
2. Banners — red `cmp-banner.danger` for blocking errors; amber `cmp-banner.upgrade` with
   "Apply upgrade" secondary button when `specVersion < LATEST`.
3. Breakdown — `cmp-cats` per-category earned/available with accent bars.
4. Gaps — `cmp-gap` rows sorted blocking → warn → info; severity chip (`sev`), humanized name,
   `auto-fill`/`review` badge, remediation text.
5. Actions — single primary "Generate missing" + secondary Close.

## In-app limits

Centralized in a single `LIMITS` constant; each note renders with a stable `data-od-id`.
Never inline these literals at point-of-use.

| Limit | Constant | Value | Trigger | Effect |
|---|---|---|---|---|
| L1 Graph truncation | `MAX_GRAPH_STATES` | 40 | > 40 states | First 40 states rendered + dismissible `graph-notice`; full definition stays editable in Schema editor |
| L2 Coverage matrix cap | `MAX_MATRIX_STATES` | 16 | > 16 states | Matrix replaced by metrics + dynamic `limit-note` |
| L3 Mode B download-only | capability (`fileIOAvailable()`) | — | not localhost/HTTPS | Blob-download save + persistent read-only hint |

Anchor IDs: L1 `limit-graph-truncation` · L2 `limit-matrix-coverage` (+ section entry
`limit-coverage-matrix`) · L3 `limit-modeb`. New user-visible limits/help topics should follow the
same pattern: stable `data-od-id` + centralized string constant.

Deferred (accepted): future spec revisions append to `SPEC_REGISTRY` newest-first;
`spec_version` stays weight-0; upgrades opt-in via banner.

## Acceptance criteria

Verify changes against this list (all currently implemented):

- No embedded schema data — no `SAMPLES`, no machine dropdown, no sample handlers, no spec-modal example.
- localStorage stores only `{ loop, speed, spacing }` — never schema data.
- Startup shows empty state; nothing loads until a file is opened.
- Open (native picker) loads a single `.json`; Save writes in place (Mode A); Save As writes new; Ctrl/Cmd+O/S work.
- Dirty indicator on mutation, cleared on save; open-while-dirty prompts.
- `beforeunload` guard prompts before discarding unsaved changes.
- Implementation version defined once (`APP_VERSION`) and surfaced in topbar + `data-app-version`.
- Spec browser can copy any selected spec version as JSON Schema (and markdown) with toast.
- `detectSpecVersion` resolves declared → default latest; older machines get upgrade banner;
  apply fills only deterministic items and re-scores.
- Every gap shows severity + remediation; "Generate missing" fills only `auto` items; apply marks dirty.
- Score renders 0–100 with grade, target spec version, category breakdown.
- Spec browser lists every registry version with fields + changelog.
- Single primary CTA per view; hover/focus preserve contrast; focus ring visible; no horizontal overflow.
