---
name: machina-driving
description: >-
  Drive a Machina state machine to a deterministic outcome on behalf of an AI
  agent. USE WHEN: a task is governed by a state machine (a machine definition
  JSON with states, transitions, guards, actions, tools, checks, scenarios);
  executing a workflow that must be deterministic and auditable; running a
  skill whose SKILL.md declares a `machina:` machine; firing events, checking
  status, satisfying evidence checks, or producing a terminal report for a
  machine-driven run; escalating a STUCK run to a human conductor. DO NOT USE
  FOR: authoring or scoring machine definitions (use machina-authoring);
  modifying the Machina simulator app or its engine (use machina-simulator);
    implementing or modifying the driver/runtime tooling such as
    scripts/machine-driver.py (that is engine development, not driving);
    general diagramming or XState/SCXML authoring.
metadata:
  version: 0.2.0
---

# Machina Driving

Execute a task under a Machina state machine: the driver (`scripts/machine-driver.py`)
is the sole mutator of run state; you perform the real work, choose events, and
satisfy evidence checks. The outcome is a deterministic, auditable report.

## Quick start

```powershell
# From the skill directory (or any workspace with this skill installed):
python3 scripts/machine-driver.py init --machine <machine.json> --scenario <id> --input k=v --run-dir <session-workspace>/.machina/runs
python3 scripts/machine-driver.py status --run <run_id> --run-dir <session-workspace>/.machina/runs
python3 scripts/machine-driver.py fire <EVENT> --run <run_id> --note "what you did" --run-dir <session-workspace>/.machina/runs
python3 scripts/machine-driver.py report --run <run_id> --run-dir <session-workspace>/.machina/runs
```

Every command prints exactly one strict-JSON object. A blocked `fire` is a
first-class outcome, not an error.

## Workflow

1. **Discover** the governing machine — read the relevant skill's `SKILL.md`
   frontmatter (`machina: { machine, scenario }`), or use the machine file the
   human conductor names.
2. **Init** the run with all required scenario inputs.
3. **Work the current state** — the state's `description` tells you what the
   state demands. Do real work before firing events.
4. **Check status** — `status` shows enabled vs blocked events and why.
5. **Fire** events with a `--note`; iterate on `blocked` outcomes by fixing the
   underlying condition (guard or evidence), never by forcing the machine.
6. **Report** at terminal — ground your final summary to the report facts.

## Hard rules

- **INV-1**: never hand-edit a machine's state, context, history, or logs. The
  driver is the only writer; the ledger is tamper-evident.
- **INV-2**: never inline code into machine JSON. Tools are named references to
  scripts the driver executes.
- **Post-init context immutability**: after `init`, only machine actions and
  tool-output mappings mutate context. Your `--note` never touches context.
- **STUCK is not a crash**: a non-final state with zero enabled events is a
  modeling gap. Report it to the human conductor; never improvise a transition
  or fabricate completion.
- **Ground your summary to the report**: render only report facts
  (`result`, `final_state`, `path`, `events`, `evidence`, `context_snapshot`).

## References (load on demand)

| File | Load when |
|---|---|
| [references/driving-protocol.md](references/driving-protocol.md) | Any driving task — the full protocol: command surface, driving loop, evidence, phase states, STUCK/escalation, report grounding, discovery |
| [references/schema-v3.md](references/schema-v3.md) | Reading or writing machine JSON — v3 field reference, tools registry, checks/requires/ensures, inputs, limits, phase states |

## Dependency

This skill **depends on** [`machina-authoring`](../machina-authoring/SKILL.md):
`scripts/machine-driver.py` imports the shared engine (guard/action evaluation,
terminal detection, compliance scoring) from `machina-authoring/scripts/machine-validator.py`.
Distributing this skill to a workspace **implicitly distributes `machina-authoring`**.
The `machina-simulator` Copilot extension is **optional** (human UI only).

## Samples

- [samples/docs-authoring.machine.json](samples/docs-authoring.machine.json) — a
  v3 machine with tools, checks, requires, inputs, and a phase state.
- [samples/scripts/check_file.py](samples/scripts/check_file.py) — a read-only
  checker script referenced by the sample machine.

## Trust boundary

The driver executes referenced checker scripts with the user's privileges.
Machines are trusted artifacts (authored by the user or by `machina-authoring`).
No sandboxing in v1.

## Report output contract

Your final user-facing summary is a **grounded report** that renders only facts
from the terminal `report` output. It is not prose — each field must trace to a
`machina.report.v1` field.

| Report field | Required content | Source (`report`) field |
|---|---|---|
| `result` | `SUCCESS` · `ESCALATED` · `ABORTED` · `STUCK` · `IN_PROGRESS` | `result` |
| `final_state` | the final state id | `final_state` |
| `path` | the visited state sequence | `path` |
| `events` | count + comma-separated event names | `events`, `agent_notes[].event` |
| `evidence` | `passed N / failed M` | `evidence.passed`, `evidence.failed` |
| `blocked_events` | only when present | `blocked_events` |
| `context_snapshot` | only when it affects the outcome | `context_snapshot` |

Rules:

- Keep it under ~80 words; one paragraph per report.
- **Never invent claims beyond the report.** If `result` is `STUCK`, say
  `STUCK` — do not claim success.
- On `STUCK` or `ESCALATED`, head the summary as a **grounded escalation**:
  state the blocked events, the evidence failures, and the decision the human
  conductor must make. Never improvise a transition or fabricate completion.
- On `ABORTED`, render the abort reason from the report.
- If the driver emitted a strict-JSON `machina.report.v1` object, that object is
  the report — do not paraphrase it into different fields.

## Resources

- `scripts/` — `machine-driver.py` implements the `init` / `status` / `fire` /
  `abort` / `report` command surface. Execute it directly; do not load into
  context.
- `references/` — `driving-protocol.md` (the driving loop, evidence, STUCK,
  report grounding) and `schema-v3.md` (machine JSON v3 reference). Load on
  demand per the table above.
- `samples/` — `docs-authoring.machine.json` and its `scripts/` checkers for a
  worked example of a driven run.
