# Machina Architecture Reference

App shell, engine, graph, playback, scenarios, inspector, file I/O.

## Contents

1. [App shell & regions](#app-shell--regions)
2. [Responsive behavior](#responsive-behavior)
3. [Design tokens](#design-tokens)
4. [Engine & playback](#engine--playback)
5. [Graph rendering & interaction](#graph-rendering--interaction)
6. [Density control](#density-control-spacing)
7. [Scenario generation & coverage](#scenario-generation--coverage)
8. [Inspector & analysis](#inspector--analysis)
9. [Schema editor & validation](#schema-editor--validation)
10. [File I/O & persistence](#file-io--persistence)
11. [Keyboard & accessibility contract](#keyboard--accessibility-contract)

## App shell & regions

Three-column grid: **schema panel (340px) · stage (flexible) · inspector (372px)** under a 56px
topbar; transport bar sits inside the stage bottom.

| Region | `data-od-id` | Contents |
|---|---|---|
| Topbar | `topbar` | brand + app version badge + "Schema spec" ghost button |
| Tabbar (mobile/tablet) | `tabbar` | Simulate / Schema / Inspector tabs |
| Schema panel | `schema-panel` | file-bar, Open/Save/Save As, scenario select, editor, Apply/Copy/Compliance |
| File bar | `file-bar` | `file-name` + `dirty-indicator` |
| Stage | `stage` | graph canvas + transport |
| Empty state | `empty-state` | "Open a schema to begin" + primary CTA |
| Graph notice | `graph-notice` | truncation warning (dismissible) |
| Graph legend | `graph-legend` | main path / other / start / end |
| Zoom controls | `zoom-controls` | − / % / + / Fit |
| Transport | `transport` | back/play/next/reset · loop/shuffle · speed |
| Inspector | `inspector-panel` | state, context, transitions, history, analysis |
| Analysis group | `analysis-group` | coverage + scenarios (`gen-scenarios`) + cycle analysis + Limits |

Use `data-od-id` anchors for locating/editing regions — never rely on line numbers.

## Responsive behavior

- **≤1100px**: grid collapses; panels toggle via the bottom `tabbar` (`.tab-active`). Stage is the
  default visible tab.
- **≤767px**: tighter topbar/canvas padding; brand tagline and graph legend hidden.
- Modals: vertical scroll, `max-height: 86vh`; horizontal overflow never permitted.

## Design tokens

Locked values from `:root`. Never reintroduce raw hex in new code.

### Core colors

| Role | Token | Value |
|---|---|---|
| Background | `--bg` | `#ffffff` |
| Surface | `--surface` | `#f7f7f7` |
| Surface warm | `--surface-warm` | `#eeeeee` |
| Foreground | `--fg` / `--fg-2` / `--muted` | `#111111` / `#3a3a3a` / `#707070` |
| Border | `--border` / `--border-soft` | `#d9d9d9` / `#eeeeee` |
| Accent | `--accent` / `--accent-on` | `#111111` (monochrome) / `#ffffff` |
| Status | `--success` / `--warn` / `--danger` | `#168a46` / `#b7791f` / `#c53030` |

Derived via `color-mix`: `--accent-hover`, `--accent-active`, `--accent-soft`, `--fg-soft`,
`--danger-soft`, `--success-text`, `--warn-text`, `--danger-text`.

### Typography, spacing, motion

- Fonts: display/body `"Helvetica Neue", Arial, sans-serif`; mono
  `"SF Mono", ui-monospace, Menlo, monospace` — mono is used extensively for eyebrows,
  metric values, and graph labels.
- Spacing: `--gap-xs` 8 · `sm` 12 · `md` 20 · `lg` 32. Radii 8 / 12.
- Type scale: `--fs-body` 14px · `--fs-meta` 12px.
- Motion: `--motion-fast` 150ms · `--motion-base` 240ms · `--ease-standard`
  cubic-bezier(0.2,0,0,1). Focus ring: 2px bg + 4px fg halo (`--focus-ring`).
- **Accent budget**: near-black accent at most twice per screen (primary CTA + status/scenario
  pill). Success/warn/danger are semantic status only.

## Engine & playback

**Runtime state:** `machine`, `stateKey`, `context`, `initialSnapshot`, `history`, `log`,
`playing`, `speedMs`, `scenarioId`, `loopMode`; graph caches `edgeMap/nodeEls/nodePos`.

Transport semantics:

- `setPlaying(on)` drives `setInterval(fireNext, speedMs)`; play button inverts icon/label and
  toggles `is-playing`.
- `fireNext()` prefers the **guided** next event of the selected scenario
  (`scenarioNextEvent()` matches while history matches the scenario's prefix), else falls back to
  the first enabled event; at terminal with no events → restart (loop mode) or stop.
- `fireEvent(evt)` blocks on guard failure ("Guard blocked: <EVT>" toast); on success applies
  **exit actions → transition actions → entry actions**, pushes to `history` + `log`.
- `stepBack()` pops history and restores prior state/context.
- Speed slider 1–10 maps to `1400 − (v−1)·130` ms (880 ms at default 5).

## Run replay (recorded ledgers)

`loadReplay(machine, ledger, opts)` enters replay mode (a "playback of truth"):

- Builds the trace via the engine's `replayRunLedger` (all 5 record types:
  `init`/`transition`/`blocked`/`redirect`/`abort`), then steps exactly through it —
  `history` is seeded from the init snapshot and appended on `replayStep()`.
- Integrity is re-verified on load (Python-canonical SHA-256 chain + `machine_sha256`):
  the trust badge renders **✓ verified** (green) or **TAMPERED at record N** (red).
- Blocked/redirect records render distinctly in the log (`↯ blocked` / `⇀ redirect`);
  blocked carries reason/evidence/note; child_run appears as a nested badge.
- Non-terminal runs render `replaying`/`replay-done` via `isTerminal()` consulting
  `replayEnded` (which is `r.terminal === 'complete'`).
- Navigation: `replayStep()` / `replayBack()` / `replayReset()` / `replayJump(i)` walk
  the recorded trace (commands `replayStep`/`replayBack`/`replayReset`/`replayJump`
  over SSE).
- `diffReeval` guards are re-evaluated against context-before per record; a
  `guardMismatch` surfaces divergence between what happened and what the machine says.

## Guard/action evaluation:

- `evalGuard`: reads context by dotted path (`getPath`); string `value` resolves against context
  keys then numeric-coerces; unknown op → pass (default true). Ops: `eq·neq·lt·lte·gt·gte`.
- `applyActions`: `increment` adds 1 to dotted path (defaulting 0); `assign` sets it.
- Terminal = `type:"final"` **or** no outgoing transitions.

## Graph rendering & interaction

**Layout (`computeLayout`):** BFS from initial state assigns layer depths; unreachable states go
to a trailing layer. Column width 256px (224px when dense >4 columns); node 168×62px;
padx 96, pady 112, row gap 148 — gaps scale by density factor. ViewBox grows with the graph
(`max(1000,…)` × `max(560,…)`).

**Rendering (`renderGraph`):** SVG defs (arrow marker, comet glow), `#viewport` pan/zoom group,
edges with invisible `.edge-hit` click paths, labels, nodes. Nodes are focusable
(`tabindex=0`, `role=button`) with name + event-count/final sublabel and `<title>` tooltip from
description. Graphs over `MAX_GRAPH_STATES` render the first 40 states plus a `graph-notice`
whose copy says to use "the editor or Inspector for the full definition".

**Interaction:**

- Pan: pointer drag with pointer capture (mouse left / touch).
- Zoom: wheel exponential, clamped 0.15–4.0; −/+ buttons step 1.25×; Fit resets.
- Node click/Enter/Space → `jumpToState`, only to states reached in this run.
- Edge click fires the transition **only if it starts at the current state**.
- Node arrow keys move to nearest neighbor along the axis (perpendicular-distance weighted).

**Trail & pathway:** `markTrail()` highlights traversed edges; `renderPathway()` marks the current
scenario's path (start/end marks). Transition firing animates a comet dot along the edge
(respects reduced-motion).

## Density control (spacing)

Floating `.spacing-controls` cluster (bottom-right above zoom): Compact · Normal · Spacious →
factor `0.7 / 1.0 / 1.4` scaling `COLW`/`ROWGAP` in `computeLayout`. Normal default.

- `setSpacing(f)` updates segmented `aria-pressed` and runs `updateGraphLayout()` — a hot
  re-layout that **preserves pan/zoom** (no `resetView`, no SVG rebuild).
- Persisted as part of prefs `{ loop, speed, spacing }` in localStorage `machina.v1`.
- Density ≠ zoom: zoom is uniform view transform; spacing changes relative gaps at fixed node
  size. Self-loop/vertical bend radii are fixed and do not scale.

## Scenario generation & coverage

- `getEntryPoints()`: deduped `scenarios[].initial` split by interface (`UI` vs `API`)
  + `machine.initial` as default `API` entry.
- `generateScenarios()`: DFS, `MAX_DEPTH 24`, `MAX_SCEN 500`, per-state `MAX_VISITS 2`;
  records every path to terminal; dedupes identical state sequences; labels `start → end`
  with `(n)` disambiguator. Cached in `generatedScenarios`.
- `scenarioCoverage()`: covered transitions vs total → "N/M transitions · X%" meta.
- `runGeneration()` (Inspector "Generate" button) rebuilds scenarios and toasts count.

## Inspector & analysis

- **Current state card** — name, type (`atomic`/`final state`), optional description.
- **Context table** — every key; numbers/bools styled `num`/`bool`.
- **Transitions** — event buttons; guarded-off ones get `evt-blocked` (dashed, non-clickable)
  with guard tooltip (`guardText`).
- **History log** — newest first; `BACK`/`JUMP` entries annotated ↩/↪.
- **Coverage** — score + bar, metrics grid (states/finals/transitions/unique paths/max paths/
  cyclomatic/complexity), interactive matrix up to `MAX_MATRIX_STATES` (hover dim/highlight);
  otherwise a "Run Compliance → Generate missing" hint when no `coverage` block exists.
- **Cycle analysis** — renders `cycle_prevention` plus `detectCycles()` findings:
  CRITICAL depth-limit / HIGH unguarded loop / MEDIUM valid cycle, each with recommendations.
- **Limits section** — renders all three limits from the single `LIMITS` constant (see below).

## Schema editor & validation

- `syncEditor()` mirrors machine into textarea; `applyEditor()` parses → `validate()` → ingest
  → `markDirty()`.
- `validate()` is structural/hard only (feeds blocking findings): root object; `id` string;
  `coverage` object; `states` non-empty object; `initial` ∈ states; every transition `target`
  string ∈ states; every scenario `id` string and `initial` ∈ states.
- `copySchema()` uses `navigator.clipboard` with `legacyCopy` fallback.

## File I/O & persistence

**Source of truth:** the filesystem. One machine at a time. Startup shows empty state, loads
nothing. `localStorage` (`machina.v1`) holds UI prefs `{ loop, speed, spacing }` only — never
schema data or file handles.

**Two capability modes** via `fileIOAvailable()`:

- **Mode A** (File System Access API): `openSchema()` picker → read → parse → validate → load,
  retaining `fileHandle` + `currentFilePath`. `saveSchema()` writes
  `JSON.stringify(machine, null, 2)` via `createWritable()` and clears dirty (falls back to
  `showSaveFilePicker` without a handle). `saveAsSchema()` always pickers with
  `suggestedName: <machine.id>.json`.
- **Mode B** (`file://` fallback): hidden file input + Blob download; download-only save with
  persistent dismissible read-only hint in the Schema panel whenever `!fileIOAvailable()`.

**Dirty tracking:** any mutation (`applyEditor`, `applyPatches`, upgrade) calls `markDirty()`
("● unsaved"); save calls `markClean()`. Open-another-file-while-dirty prompts `window.confirm`.
`beforeunload` listener triggers native "Leave site?" prompt when dirty (`e.preventDefault();
e.returnValue = ''`). Both guards must be preserved.

## Keyboard & accessibility contract

Shortcuts (ignored while typing in inputs/textarea/select/button):
`Ctrl/Cmd+O` open · `Ctrl/Cmd+S` save · `Esc` close modals · `Space` play/pause · `→` next ·
`←` back.

Focus management: `openModal` focuses `.modal`; `closeModal` restores trigger focus;
`attachModalTraps()` traps Tab in both modals. Spec version pills (`role="tab"`) and the tab bar
support arrow keys.

States & contrast: `:focus-visible` uses `--focus-ring`; hover/active darken or strengthen
borders (never lighten text); touch targets ≥44px (transport buttons 44×44); disabled is the only
state allowed to reduce contrast; reduced-motion honored globally.
