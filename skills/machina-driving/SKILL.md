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
  general diagramming or XState/SCXML authoring.
metadata:
  version: 0.1.0
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

## Structuring This Skill

[TODO: Choose the structure that best fits this skill's purpose. Common patterns:

**1. Workflow-Based** (best for sequential processes)
- Works well when there are clear step-by-step procedures
- Example: DOCX skill with "Workflow Decision Tree" -> "Reading" -> "Creating" -> "Editing"
- Structure: ## Overview -> ## Workflow Decision Tree -> ## Step 1 -> ## Step 2...

**2. Task-Based** (best for tool collections)
- Works well when the skill offers different operations/capabilities
- Example: PDF skill with "Quick Start" -> "Merge PDFs" -> "Split PDFs" -> "Extract Text"
- Structure: ## Overview -> ## Quick Start -> ## Task Category 1 -> ## Task Category 2...

**3. Reference/Guidelines** (best for standards or specifications)
- Works well for brand guidelines, coding standards, or requirements
- Example: Brand styling with "Brand Guidelines" -> "Colors" -> "Typography" -> "Features"
- Structure: ## Overview -> ## Guidelines -> ## Specifications -> ## Usage...

**4. Capabilities-Based** (best for integrated systems)
- Works well when the skill provides multiple interrelated features
- Example: Product Management with "Core Capabilities" -> numbered capability list
- Structure: ## Overview -> ## Core Capabilities -> ### 1. Feature -> ### 2. Feature...

Patterns can be mixed and matched as needed. Most skills combine patterns (e.g., start with task-based, add workflow for complex operations).

Delete this entire "Structuring This Skill" section when done - it's just guidance.]

## [TODO: Replace with the first main section based on chosen structure]

[TODO: Add content here. See examples in existing skills:
- Code samples for technical skills
- Decision trees for complex workflows
- Concrete examples with realistic user requests
- References to scripts/templates/references as needed]

## Resources

This skill includes example resource directories that demonstrate how to organize different types of bundled resources:

### scripts/
Executable code (Python/Bash/etc.) that can be run directly to perform specific operations.

**Examples from other skills:**
- PDF skill: `fill_fillable_fields.py`, `extract_form_field_info.py` - utilities for PDF manipulation
- DOCX skill: `document.py`, `utilities.py` - Python modules for document processing

**Appropriate for:** Python scripts, shell scripts, or any executable code that performs automation, data processing, or specific operations.

**Note:** Scripts may be executed without loading into context, but can still be read by Claude for patching or environment adjustments.

### references/
Documentation and reference material intended to be loaded into context to inform Claude's process and thinking.

**Examples from other skills:**
- Product management: `communication.md`, `context_building.md` - detailed workflow guides
- BigQuery: API reference documentation and query examples
- Finance: Schema documentation, company policies

**Appropriate for:** In-depth documentation, API references, database schemas, comprehensive guides, or any detailed information that Claude should reference while working.

### assets/
Files not intended to be loaded into context, but rather used within the output Claude produces.

**Examples from other skills:**
- Brand styling: PowerPoint template files (.pptx), logo files
- Frontend builder: HTML/React boilerplate project directories
- Typography: Font files (.ttf, .woff2)

**Appropriate for:** Templates, boilerplate code, document templates, images, icons, fonts, or any files meant to be copied or used in the final output.

---

**Any unneeded directories can be deleted.** Not every skill requires all three types of resources.
