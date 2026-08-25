---
name: machina-authoring
description: >-
  Author valid, high-scoring state machines in the Machina machine JSON format
  (`state-machine-simulator.html` format, spec v2.0.0 / v1.0.0). USE WHEN: writing or generating a
  new machine definition JSON (states, transitions, guards, actions, context, scenarios);
  modeling a real workflow (order fulfillment, refunds, signup, retries) as a Machina state
  machine; fixing or upgrading an existing machine JSON so it validates or scores higher;
  explaining why a machine fails validation or scores below target; running the bundled machina.py
  CLI to validate, compliance-score, or generate gaps/scenarios for a machine JSON; adding retry
  guards or cycle protection to a looping workflow; or preparing machines for the compliance
  scorer ("Excellent" ≥90). DO NOT USE FOR: modifying the Machina simulator app itself, its
  engine, UI, or SPEC_REGISTRY (use machina-simulator-maintenance), debugging or bug-fixing the
  bundled machina.py scripts themselves, XState config authoring, SCXML documents, or general
  diagramming.
metadata:
  version: 0.1.0
---

# Machina Machine Authoring

Guidance for writing state-machine definitions that open cleanly in the Machina simulator and
score well against its compliance scorer.

## Glossary

Use these terms consistently — in prompts, output, and code comments:

| Term | Meaning |
|---|---|
| **Machina** | Brand name covering both the simulator app (`state-machine-simulator.html`) and its machine schema spec. Qualify which: "**Machina simulator**" (the app) vs "**Machina schema spec**" (the JSON contract). Never use bare "Machina" where the referent is ambiguous. |
| **State machine** | The modeled FSM itself. Always write "state machine", never bare "machine". |
| **Machine definition** | The JSON document that encodes a state machine (the artifact you author). A file contains one definition. |
| **Schema spec / spec version** | The versioned field contract (`v1.0.0`, `v2.0.0`) a definition targets via `spec_version`. Distinct from the definition's own `version` field. |
| **Final state** | A state typed `"type": "final"` (or with no outgoing transitions). Prefer "final state" over "terminal" — matches UML/XState. |
| **Event** | Named trigger (`UPPER_SNAKE`) that fires a transition from a state's `on` map. |
| **Transition** | `{ EVENT: { target, guard?, actions? } }` — moves between states. |
| **Guard** | Declarative predicate `{ type:"compare", key, op, value }` gating a transition. Matches SCXML/XState semantics. |
| **Action** | Declarative side effect `{ type:"increment"\|"assign" }` on context. No code strings, ever. |
| **Context** | Extended state data available to guards/actions; supports dotted paths. |
| **Scenario / entry point** | A named start into the state machine (`scenarios[]` with `initial`, `interface ∈ UI·API`). |
| **Compliance scorer** | The deterministic 17-check evaluator producing score/grade/gaps (in-app or via `machina.py`). Not "checker", "linter", or "validator" (validation is only its blocking subset). |
| **Gap** | A failing check finding: `auto` (deterministically fillable) or `review` (needs human judgment). |

## Minimal viable machine

Every state machine definition needs at minimum: `id`, non-empty `states`, `initial` resolving
to a state key, and every transition `target` pointing at an existing state key.

```json
{
  "id": "order-fulfillment",
  "name": "Order Fulfillment",
  "version": "1.0.0",
  "spec_version": "2.0.0",
  "initial": "pending",
  "context": { "attempts": 0 },
  "scenarios": [
    { "id": "default", "label": "Default", "initial": "pending", "interface": "API" }
  ],
  "states": {
    "pending": {
      "description": "Awaiting payment confirmation.",
      "on": {
        "PAY": { "target": "paid", "actions": [{ "type": "assign", "key": "attempts", "value": 0 }] },
        "RETRY_PAY": { "target": "pending", "guard": { "type": "compare", "key": "attempts", "op": "lt", "value": 3 }, "actions": [{ "type": "increment", "key": "attempts" }] }
      }
    },
    "paid": { "description": "Payment confirmed.", "on": { "SHIP": { "target": "shipped" } } },
    "shipped": { "type": "final", "description": "Order delivered to carrier." }
  }
}
```

## Authoring workflow

1. Read [references/schema-spec.md](references/schema-spec.md) — full field reference, naming
   conventions, guard/action semantics.
2. Model states first: identify every distinct status, mark true final states `"type": "final"`
   explicitly (never rely on implicit finals).
3. Wire events with declarative objects only — guards `{type:"compare",…}`, actions
   `{type:"increment"/"assign",…}`. Never embed code strings; the format must stay shareable and
   safe to ingest.
4. Add `scenarios[]` entry points (`{id, label, initial, interface ∈ "UI"|"API"}`) — one per
   meaningful way the workflow starts.
5. If any path can loop (retry, rework), add a genuine counter in `context`
   (`retry`/`attempt` naming) and gate the looping transition with a `compare lt` guard against
   it — this is the only pattern the compliance scorer recognizes as cycle protection.
6. Give every state a real, human `description` — placeholder text is auto-detectable
   (`generated: true`) and reads as a gap.
7. Validate & score — use the bundled deterministic engine (see below) or open in Machina:
   `validate` → iterate → target **≥90 ("Excellent")** via `score --text`.
   - Gaps flagged `auto` can be applied deterministically with the script's `apply`
     (or "Generate missing" in-app).
   - Gaps flagged `review` need your judgment: missing transitions, convention renames, event/state
     naming, unreachable states. Fix these by hand — see [references/machine-quality.md](machine-quality.md)
     for what each check demands.

## Hard rules

- Declare `"spec_version": "2.0.0"` explicitly so scoring never assumes latest silently.
- Event names `UPPER_SNAKE`; state keys `kebab-case`.
- Guard `value` may be a literal number/string or a context-key name (resolved then numeric-coerced).
- Context paths support dotted notation (`"payment.attempts"`).
- Terminal = `type:"final"` or no outgoing transitions — prefer an explicit **final state**.

## Deterministic tooling — use the bundled script

All deterministic authoring logic from the Machina simulator (validation, the 17-check
compliance scorer, gap analysis, autofill patching, scenario generation, cycle detection,
coverage building) is bundled as a standalone CLI. Run it instead of re-deriving logic or
loading simulator source:

```powershell
# From workspace root; python3 on Linux/WSL
python3 skills/machina-authoring/scripts/machina.py <command> <machine.json> [options]
```

| Command | Purpose |
|---|---|
| `validate <file>` | Hard structural errors (blocking) — run first, always |
| `score <file> [--text] [--spec V]` | Full compliance report; JSON by default, `--text` for summary |
| `gaps <file>` | Ordered list of deterministic auto-fillable patches |
| `apply <file> id… [-o out.json]` | Apply selected patches (fixed order); default overwrites input |
| `scenarios <file>` | DFS-generated terminal paths + transition coverage % |
| `cycles <file>` | Cycle findings (CRITICAL depth / HIGH unguarded / MEDIUM valid) |
| `coverage <file>` | Exact coverage block "Generate missing" would embed |

Typical authoring loop: `validate` → iterate → `score --text` until ≥90 → `gaps` for remaining
auto-fillable items → `apply` (or hand-fix review items) → final `score`.

**Known divergence (deliberate):** the simulator source's check-inclusion filter
(`specRank(since) <= specRank(target)` over newest-first ranks) inverts v1/v2 inclusion versus
§14's documented model. The ported script implements the documented semantics (all 17 checks at
v2.0.0, weight = 100). When editing the simulator itself, follow
[the machina-simulator extension's canonical maintenance docs](../../copilot-extensions/machina-simulator/simulator/docs/maintenance.md)
and keep this divergence in mind.

## Reference map (load on demand)

| File | Load when |
|---|---|
| [references/schema-spec.md](references/schema-spec.md) | Any authoring work — field tables, versioning, guard/action semantics |
| [references/machine-quality.md](references/machine-quality.md) | Scoring below target, or proactively before finishing a definition — per-check author guidance, grade bands, review-vs-auto gaps |

## Naming discipline in generated output

When authoring definitions or writing about them: say "state machine" or "machine definition"
(never bare "machine"), qualify "Machina simulator" vs "Machina schema spec", and use "final
state", "compliance scorer", and "gap (`auto`/`review`)" per the glossary. Field-level vocabulary
(`guard`, `action`, `event`, `transition`, `context`, `scenario`) is already industry-standard —
keep it verbatim.
