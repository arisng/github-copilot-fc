---
date: 2025-12-10
type: Design Decision
severity: High
status: Proposed
author: Arisng
tags:
  - agentic
  - mcp
  - skills
  - runtime
related: []
---

# Copilot Skills Implementation Specification

## Overview

The "Copilot Skills" architecture transforms VS Code into a local Agentic Runtime. It decouples **Orchestration** (LLM/Copilot) from **Execution** (Scripts/MCP). This specification defines the standards for creating, documenting, and deploying new capabilities to the system.

### Core Philosophy

* **Brain (Copilot):** Plans, routes, and formats. Does *not* calculate or guess facts.
* **Hands (MCP):** Securely executes local code.
* **Knowledge (Skills):** Self-contained units of logic and instruction.

## Directory Structure Standard

All skills must reside in the workspace `skills/` root. Each skill is a self-contained directory.

```txt
/skills
├── {skill_id}/                  # Snake_case, unique identifier (e.g., vn_payroll)
│   ├── skill.md                 # MANDATORY: The "Driver" instruction for the LLM
│   ├── {script_name}.{ext}      # MANDATORY: The executable logic (py, ps1, sh)
│   ├── data/                    # OPTIONAL: Static data (json, csv) specific to this skill
│   └── requirements.txt         # OPTIONAL: Python dependencies (if complex)
```

## Component Specification

### The Instruction File (`skill.md`)

This file is the **Interface Contract**. It tells the LLM *when* to use the skill and *how* to construct the command.

**Required Schema:**

```markdown
# Skill: {Human Readable Name}

**Description:**
A concise (1-2 sentence) description of what this skill solves.

**Tools:**
- `{script_name}`: Brief description of the script's function.

**Usage:**
`{interpreter} {script_name} --arg1 <VALUE>`

**Arguments:**
- `--{arg_name}`: {Type} - {Description}
- `--{flag_name}`: {Boolean} - {Description}

**Example Task:**
"User query example"
-> Command: `run_skill_script(skill_name="{skill_id}", script_name="{script_name}", arguments="--arg1 value")`

**Output Handling:**
Instructions on how to present the result.
```

### The Executable Script

The script performs the actual work. It must be robust, deterministic, and parseable.

**Requirements:**
1. **CLI Interface:** Must use standard argument parsing (e.g., `argparse` in Python, `param()` in PowerShell).
2. **Standard Output (STDOUT):** The result must be printed to STDOUT.
3. **Standard Error (STDERR):** Critical failures must print to STDERR and exit with a non-zero code.
4. **No User Interaction:** Scripts must run headless. No `input()` or `Read-Host`.
5. **Self-Contained:** Avoid relying on global environment variables unless documented.

**Recommended Output Format:**
* For data-heavy results: Output **JSON**. The LLM parses JSON extremely well.
* For human-readable reports: Output formatted **Text/Markdown**.

## The Runtime Protocol (MCP Interface)

The `skills-mcp-server.py` MCP server exposes three primitive tools. Your skills must be compatible with this lifecycle.

| Phase            | Tool Name               | Function                                                                         |
| :--------------- | :---------------------- | :------------------------------------------------------------------------------- |
| **1. Discovery** | `list_available_skills` | Scans `skills/` for folders. Returns the directory names.                        |
| **2. Learning**  | `inspect_skill`         | Reads `skills/{id}/skill.md`. Injects the "User Manual" into the context window. |
| **3. Execution** | `run_skill_script`      | Guideline to run the script: `[interpreter] skills/{id}/{script} [arguments]`.   |

## Development Workflow

**Step 1: Identify the Task**
* *Example:* "I need to generate VAT invoices for Vietnam."

**Step 2: Create the Folder**
* `mkdir skills/vn_invoice_generator`

**Step 3: Write the Logic**
* Write `generate.py`.
* Hardcode the logic, API calls, or math.
* **Test manually in terminal:** `python skills/vn_invoice_generator/generate.py --total 100`

**Step 4: Write the Interface (`skill.md`)**
* Describe the tool so Copilot knows *when* to trigger it.
* Define the arguments clearly.

**Step 5: Test via Agent**
* Open Copilot Chat (Agent Mode).
* Ask: "Generate a VAT invoice for 100k."
* Verify the chain: List -> Inspect -> Run.

## Best Practices & Constraints

**Idempotency:** Scripts should be safe to run multiple times. If a script is destructive, require a `--force` flag.

**Dependencies:** Keep skills lightweight. If a skill needs heavy libraries (e.g., `pandas`, `playwright`), ensure they are installed in your global environment OR use a virtual environment activation wrapper in the script.

**Security:** The MCP server restricts execution to the `skills/` directory to prevent directory traversal attacks. Do not try to access files outside the workspace unless explicitly handled by the script.

**Versioning:** If logic changes drastically, update `skill.md` immediately. The LLM trusts the doc over its training data.