# Machina Simulator — Maintenance

Canonical implementation-grounded guidance for editing
[`simulator/app.html`](../app.html)
(the simulator app served by this extension at `/`). The app is a single HTML file
(no external assets, no dependencies, no embedded schema data); it imports the shared
compliance/scoring/autofill engine from `/machine-simulator.mjs`, which is the same
`machine-simulator.mjs` used by the Copilot tools — one engine implementation, two surfaces.
This extension owns the simulator implementation and its docs; for **authoring**
machine definitions see the `machina-authoring` skill.

## Non-negotiable principles

1. **No embedded schema data.** Never add sample machines, a "Machine" dropdown, or schema
   persistence in `localStorage`. Exactly one machine at a time, read from and written back to the
   host filesystem. `localStorage` (`machina.v1`) stores **UI prefs only**: `{ loop, speed, spacing }`.
2. **Declarative only.** Guards and actions stay declarative objects
   (`{type:"compare",…}`, `{type:"increment"/"assign",…}`). Never introduce code evaluation — a
   machine must remain safe to share, paste, version, and ingest.
3. **The in-app schema spec is versioned and canonical.** Compliance always scores against the
   version the machine *targets* (`spec_version`; latest assumed when absent), never blindly the latest.

## Three distinct "versions" — never conflate

| Concept | Source | Where surfaced |
|---|---|---|
| **App version** | single `APP_VERSION` constant at top of the module `<script>` + one changelog comment line | topbar tagline (`Machina · vX.Y.Z`), `data-app-version`, startup console log |
| **Schema spec version** | `SPEC_REGISTRY` + `LATEST_SPEC_VERSION` (currently v2.0.0, v1.0.0; newest first) | spec browser, compliance header, upgrade banner |
| **Machine version** | the machine's own free-form `version` field (autofill stamps `1.0.0` only when missing, never rewrites) | stage header (`· vX`) |

A release = edit `APP_VERSION` once + append one changelog line. Bump prefs key suffix
(`machina.v2`) only if the prefs shape changes.

## Editing workflows

### Making any change

1. Locate the region by its stable anchor: every UI region carries a `data-od-id`
   (`topbar`, `schema-panel`, `stage`, `inspector-panel`, …). Prefer these over line numbers.
2. Use the locked design tokens from `:root` — **never reintroduce raw hex values**. Accent budget:
   single near-black accent at most twice per screen (primary CTA + status pill).
   Success/warn/danger are semantic status only, not decoration.
3. Honor accessibility contracts: focus trap in modals, `--focus-ring` on all focusables,
   ≥44px touch targets (transport buttons), reduced-motion respected globally,
   no horizontal overflow, single primary CTA per view.
4. If you change behavior covered by an acceptance criterion (§18 of the spec), verify against it;
   the acceptance list is reproduced in [compliance-scoring.md](compliance-scoring.md)
   alongside the checks it maps to.

### Changing compliance scoring or autofill

Read [compliance-scoring.md](compliance-scoring.md) first. Key invariants:

- 17 checks, total weight = exactly 100; new checks must keep the total at 100.
- Checks carry `since` — they only apply when `since ≤ target spec version`.
- Autofill (`autoPatchItems`) writes **only** failing `auto` gaps, in fixed order
  (spec-version → version → scenarios → coverage → cycle-guards → descriptions → finals-typed),
  always through the diff-preview → apply → re-score flow, always ending with `markDirty()`.
- Review-only items (never invent): new transitions, convention renames, `name`,
  `actions-used`. Cycle guards auto-generate **only** when `context` has a genuine
  `retry`/`attempt` counter — never invent a counter key.

### Evolving the schema spec

Read [schema-spec.md](schema-spec.md) first. Rules:

- Append new revisions to the **front** of `SPEC_REGISTRY`; older machines then get flagged via
  the upgrade banner. Upgrades remain opt-in; `spec_version` stays weight-0.
- Keep v1.0.0 as a faithful subset so spec copy/export degrades correctly.
- Update `buildSpecJsonSchema()` / `buildSpecMarkdown()` together with the field table so the
  spec-browser copy actions stay faithful.

### Graph, playback, and limits

Read [architecture.md](architecture.md) for engine semantics (guard evaluation,
transition firing order, BFS layered layout), interaction contract (pan/zoom/jump/edge-fire),
and the three centralized limits rendered from the `LIMITS` constant:

- **L1** `MAX_GRAPH_STATES = 40` — graph truncates with a dismissible notice.
- **L2** `MAX_MATRIX_STATES = 16` — coverage matrix replaced by metrics above the cap.
- **L3** Mode B (`!fileIOAvailable()` under `file://`) — download-only save plus persistent hint.

Never inline these literals; read them from the constants/LIMITS so the Inspector → Analysis →
Limits section and point-of-use notes cannot drift. New user-visible help topics should follow the
same pattern: stable `data-od-id`, string centralized in a constant.

### Run replay (recorded ledgers)

Replay is an engine feature powered by `replayRunLedger`/`replayIntegrityOk` in
`machine-simulator.mjs` + app `loadReplay()`. Editing invariants:

- Replay must reproduce the driver's fold: `init` sets state/context, `transition`/`redirect`
  move, `blocked` leaves state unchanged, `abort` finalizes. Anything else is a bug (Stage 1
  `test/replay.test.mjs` asserts trace == ledger sequence).
- Integrity is **recomputed** on load — never trust the ledger's own hashes blindly; the
  Python-canonical tokenizer in `canonicalizeMachinaText` is what makes JS match the driver.
  A naive `JSON.stringify` re-serialization will NOT verify (RED test guards this).
- Keep the trust badge contract: verified → `✓ verified`, failure → `TAMPERED at record N`.
  Non-terminal (blocked-final) runs must render `replaying`/blocked, never silently "complete".
- `test/canvas.test.mjs` asserts the exact action list (`machina_command`, `machina_load`,
  `machina_replay`) and command enum — any new canvas surface must update it in the same commit.

## Reference map (load on demand)

| File | Load when |
|---|---|
| [architecture.md](architecture.md) | Working on app shell, responsive tabs, engine/playback, graph layout & interaction, density control, scenario generation, inspector, file I/O |
| [schema-spec.md](schema-spec.md) | Working on machine JSON shape, guard/action semantics, SPEC_REGISTRY, detectSpecVersion, spec export formats |
| [compliance-scoring.md](compliance-scoring.md) | Working on the 17-check registry, scoring math, grades, findings shape, autofill patch builders, compliance modal |

**Writing machine JSON for Machina?** That is the `machina-authoring` skill.
This extension owns only the simulator implementation.

## Known pitfalls

- Do not store machine/schema data or file handles anywhere but the open file handle.
- Do not let `version` (machine identity) drift into `spec_version` (contract pin) — the split was
  a resolved decision; regressions here are review-blocking.
- `detectSpecVersion()` returns `{version, declared, assumed}` — preserve the assumed-latest path
  and its "(assumed latest)" label in the compliance header.
- Mutations must flow through `markDirty()`; save/open-while-dirty confirm and the `beforeunload`
  guard are the only sanctioned data-loss protections — do not remove either.
- Density ≠ zoom: `spacing` factor scales relative gaps at fixed node size; zoom is a uniform view
  transform. Self-loop/vertical bend radii are fixed and do not scale with density.

## Engine — single source of truth

`machine-simulator.mjs` (at the extension root) is the compliance/scoring/autofill engine. The Copilot
tools import it directly, and the simulator app imports it as `/machine-simulator.mjs` (served by the
extension HTTP server), so **tool results and in-app scoring can never drift**. The app's
module script may not define any engine function itself — engine definitions live only in
`machine-simulator.mjs`. When you change scoring or autofill, edit `machine-simulator.mjs` and update
`test/engine.test.mjs`; the app consumes the change automatically.

The engine matches the documented model used by the `machina-authoring` skill's bundled
`machine-validator.py`:

- `pass(false)` correctly reports a failing check.
- Checks apply when `since ≤ target spec version` (all 17 checks at v2.0.0, total weight 100).
