---
category: reference
source_session: 260302-142754
extracted_at: 2026-03-06T00:00:00+07:00
promoted: true
---

# Harness Engineering Checklist — Ralph-v2

Baseline checklist for continuous refinement of the ralph-v2 multi-agent orchestration workflow. Use this as the review protocol whenever modifying or re-harnessing any part of the system.

---

## 1. Per-Agent Instruction File

Run for each of the 7 instruction files in `agents/ralph-v2/instructions/`.

### 1a. Required Structural Sections

| Section         | Agent files that must have it            | Check                                                      |
| --------------- | ---------------------------------------- | ---------------------------------------------------------- |
| `<persona>`     | All 6 (not appendix)                     | Role identity, invocation constraints, required parameters |
| `<rules>`       | All 6 (not appendix)                     | Numbered list; all rules present                           |
| `<artifacts>`   | All 6 (not appendix)                     | Files read / files written tables; output schemas          |
| Signal protocol | All 6 (not appendix)                     | `Poll-Signals Routine` and/or `Live Signals Protocol`      |
| `<contract>`    | All 6 (not appendix)                     | JSON/YAML contract schema with typed fields                |
| Modes section   | Planner, Questioner, Reviewer, Librarian | All mode names present; each with explicit step list       |

### 1b. Body Budget (CLI 30K limit)

| File                                             | Last measured | Target ceiling | Status           |
| ------------------------------------------------ | ------------- | -------------- | ---------------- |
| `ralph-v2-orchestrator.instructions.md`          | 20,775        | < 28,000       | ✅                |
| `ralph-v2-orchestrator-appendix.instructions.md` | 14,311        | < 28,000       | ✅ (VS Code only) |
| `ralph-v2-planner.instructions.md`               | 18,481        | < 28,000       | ✅                |
| `ralph-v2-questioner.instructions.md`            | 10,047        | < 28,000       | ✅                |
| `ralph-v2-executor.instructions.md`              | 8,943         | < 28,000       | ✅                |
| `ralph-v2-reviewer.instructions.md`              | 18,472        | < 28,000       | ✅                |
| `ralph-v2-librarian.instructions.md`             | 14,012        | < 28,000       | ✅                |

> Ceiling is 28K (not 30K) to leave margin for combined agent body overhead. Measure with `(Get-Content <file> -Raw).Length` after stripping frontmatter.

### 1c. Content Quality Rules

**Every instruction file must satisfy ALL of these:**

- [ ] All numbered rules are complete and distinct (no rule omitted, no rule duplicated)
- [ ] No rule is explained inline — "why" belongs in `.docs/`, not the instruction body
- [ ] All mode names are present and every mode has an explicit step list
- [ ] Signal poll blocks appear exactly **once** per instruction file (not once per mode) — reference `Signal Protocol` section, do not inline
- [ ] Artifact path patterns match the session structure defined in README.md
- [ ] Contract fields match those used in the agent's `<artifacts>` section
- [ ] `applyTo: ".ralph-sessions/**"` is set in YAML frontmatter
- [ ] No motivational preamble or intent paragraphs before rules/modes
- [ ] No pseudo-code blocks with inline comments that restate the rule above them
- [ ] Skills Directory Resolution reduced to: OS-specific paths + failure mode + discovery bullet (3 lines max)

---

## 2. Agent `.agent.md` File

Run for each of the 12 agent files across `agents/ralph-v2/cli/` and `agents/ralph-v2/vscode/`.

### 2a. YAML Frontmatter

| Field                            | CLI agents                                       | VS Code agents                                      |
| -------------------------------- | ------------------------------------------------ | --------------------------------------------------- |
| `name:`                          | `Ralph-v2-{Role}-CLI`                            | `Ralph-v2-{Role}-VSCode`                            |
| `target:`                        | `github-copilot`                                 | `vscode`                                            |
| `description:`                   | required                                         | required                                            |
| `disable-model-invocation: true` | orchestrator only                                | orchestrator only                                   |
| `user-invocable: false`          | sub-agents                                       | sub-agents                                          |
| `agents:`                        | orchestrator only — all 5 sub-agent `-CLI` names | orchestrator only — all 5 sub-agent `-VSCode` names |
| `infer:`                         | MUST NOT be present (deprecated)                 | MUST NOT be present (deprecated)                    |

### 2b. Body Content

- [ ] Exactly one `<!-- EMBED: <filename> -->` marker present per agent (both CLI and VS Code)
- [ ] EMBED target file exists in `agents/ralph-v2/instructions/`
- [ ] Combined body (agent body + instruction body after embed) ≤ 30,000 chars for CLI agents
- [ ] All delegation references in orchestrator body use exact `-CLI` (or `-VSCode`) suffixed names
- [ ] Orchestrator body must NOT instruct the agent to read instruction files at runtime

### 2c. Combined Body Budget (CLI)

| Agent            | Agent body | Instruction body | Combined | Status |
| ---------------- | ---------- | ---------------- | -------- | ------ |
| Orchestrator-CLI | ~1,407     | ~20,775          | ~22,182  | ✅      |
| Planner-CLI      | ~300       | ~18,481          | ~18,781  | ✅      |
| Questioner-CLI   | ~300       | ~10,047          | ~10,347  | ✅      |
| Executor-CLI     | ~300       | ~8,943           | ~9,243   | ✅      |
| Reviewer-CLI     | ~300       | ~18,472          | ~18,772  | ✅      |
| Librarian-CLI    | ~300       | ~14,012          | ~14,312  | ✅      |

> Re-measure after any instruction file change: `(Get-Content agents/ralph-v2/instructions/<file> -Raw).Length`

---

## 3. Workflow-Level Consistency

Cross-file checks that span all agents.

### 3a. Naming Consistency

- [ ] Every agent `name:` in frontmatter ends with `-CLI` or `-VSCode` (no bare names)
- [ ] The orchestrator `agents:` frontmatter field exactly matches the `name:` of each sub-agent
- [ ] All delegation references in the orchestrator body exactly match the `name:` field values

### 3b. Signal Type Consistency

Active signal types: `STEER`, `INFO`, `PAUSE`, `ABORT`. No others.

- [ ] No operational reference to `SKIP` (historical changelog entries exempt)
- [ ] No operational reference to `APPROVE` or `CURATE` (historical references exempt)
- [ ] `INFO + target: Librarian + SKIP_PROMOTION:` convention used for opt-out (not raw SKIP)
- [ ] All 6 instruction files reference the same signal schema (field names, file paths)

```powershell
# Quick scan
Select-String -Path "agents/ralph-v2/**/*.md" -Pattern "\bSKIP\b|APPROVE|CURATE" -Recurse |
  Where-Object { $_.Line -notmatch "SKIP_PROMOTION|version history|changelog" }
```

### 3c. Artifact Path Consistency

- [ ] All instruction files reference session paths in the form `.ralph-sessions/<SESSION_ID>/`
- [ ] Iteration paths follow `iterations/<N>/` (not `iteration/<N>/` or `iter/<N>/`)
- [ ] Progress file is `iterations/<N>/progress.md` (SSOT for all agents)
- [ ] Knowledge pipeline paths: `iterations/<N>/knowledge/` → `knowledge/` → `.docs/`
- [ ] No instruction file references a path pattern that contradicts README.md Session Structure

### 3d. Ownership Model Consistency

Each artifact must have exactly one write owner. Cross-check against README Ownership table:

| Artifact                     | Expected owner                             | What to check                              |
| ---------------------------- | ------------------------------------------ | ------------------------------------------ |
| `metadata.yaml`              | Planner (init), Orchestrator (transitions) | No other agent instructed to write it      |
| `iterations/<N>/plan.md`     | Planner only                               | Executor/Reviewer must not write plan.md   |
| `iterations/<N>/progress.md` | All agents (read+append)                   | No agent must overwrite the whole file     |
| `iterations/<N>/tasks/*.md`  | Planner only                               | Executor reads, does not write tasks/      |
| `iterations/<N>/reports/*`   | Executor, Reviewer                         | Planner/Questioner must not write reports/ |
| `knowledge/`                 | Librarian (STAGE, PROMOTE)                 | No other agent writes to knowledge/        |

### 3e. Version Consistency

- [ ] All agent frontmatter `version:` fields match the version declared in README.md `## Current version`
- [ ] Version bump is reflected in README.md version history entry

```powershell
Select-String -Path "agents/ralph-v2/**/*.agent.md" -Pattern "^version:" -Recurse
```

---

## 4. CLI Plugin Distribution

Checks for `plugins/cli/ralph-v2/plugin.json` and build/publish scripts.

### 4a. plugin.json Schema

- [ ] `"runtime": "github-copilot-cli"` is present
- [ ] `"agents"` path resolves to `agents/ralph-v2/cli/` relative to plugin.json
- [ ] All `"skills"` paths resolve to existing skill directories
- [ ] No forbidden fields: `strict`, `instructions`, `config`, `tools`, `system`
- [ ] Only official schema fields used: `agents`, `skills`, `commands`, `hooks`, `mcpServers`, `lspServers` (plus metadata fields: `name`, `description`, `version`, `author`, `runtime`)

```powershell
Get-Content plugins/cli/ralph-v2/plugin.json | ConvertFrom-Json | Select-Object *
```

### 4b. Build and Publish Scripts

- [ ] `scripts/publish/build-plugins.ps1` exists and contains `Merge-AgentInstructions`, `Build-PluginBundle`, `Invoke-PluginBuild`
- [ ] `scripts/publish/publish-plugins.ps1` dot-sources `build-plugins.ps1` (no duplicate function definitions)
- [ ] `$officialMetadataFields` in `build-plugins.ps1` includes `runtime`; does NOT include `strict`
- [ ] `build-plugins.ps1` has standalone guard: `if ($MyInvocation.InvocationName -ne '.') { Invoke-PluginBuild ... }`
- [ ] EMBED markers are resolved at build time (not runtime), using `[Regex]::Replace` with script block evaluator

### 4c. Plugin-Managed Marker

- [ ] `agents/ralph-v2/cli/.plugin-managed` file exists (prevents `publish-agents.ps1` from overwriting)
- [ ] `publish-agents.ps1` skips CLI agent directories containing `.plugin-managed`
- [ ] `publish-skills.ps1` skips skill directories containing `.plugin-managed`

---

## 5. Compression Patterns Reference

Use this table when deciding what to keep vs. remove/compress during a harness pass.

### 5a. Always Remove

| Pattern                                                                  | Substitute                                                                             |
| ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| Motivational preamble ("This agent is responsible for...") before rules  | Nothing — start directly with `<persona>` or `<rules>`                                 |
| "Why this rule exists" inline explanation in rule body                   | Reference `.docs/` if essential                                                        |
| Repeated signal poll blocks (one per mode)                               | Single Poll-Signals Routine section; each mode says "Poll signals per Signal Protocol" |
| Skills Directory Resolution 4-step reasoning procedure                   | 2 lines: Windows path, Linux/WSL path + one discovery + degraded-mode fallback         |
| Pseudo-code blocks with comments that restate surrounding prose          | Bullet list of steps                                                                   |
| Explicit per-case merge algorithm sub-cases inline within modes          | Reference `Merge Algorithm` table in `<artifacts>`                                     |
| Example output blocks that reproduce the schema already in `<artifacts>` | Nothing                                                                                |
| "Note:" callout blocks restating a rule just stated above                | Fold into rule wording                                                                 |
| Frontmatter template field descriptions (comments after each YAML field) | Nothing — fields are self-explanatory                                                  |

### 5b. Replace with Compact Form

| Verbose form                                              | Compact form                              |
| --------------------------------------------------------- | ----------------------------------------- |
| 4+ prose paragraphs describing mode intent                | One-line scope + compact Mode Index table |
| Named sub-steps with headers (e.g., "Step 2a: Detect...") | Flat numbered bullet list                 |
| `> blockquote note` after every schema field              | Inline parenthetical or nothing           |
| Full template examples with placeholder sentences         | Minimal `[descriptor]` placeholders       |
| Separate Disambiguation section for two similar modes     | One-row each in Mode Index table          |
| ASCII/pseudo-code decision trees                          | Bullet list with `if/else` language       |

### 5c. Always Preserve

| Element                                                   | Why                                               |
| --------------------------------------------------------- | ------------------------------------------------- |
| ALL numbered rules in `<rules>` (not one may be dropped)  | Rules are the enforcement contract                |
| ALL mode names and their complete step lists              | Missing a mode makes the agent non-functional     |
| Artifact path patterns (exact directory names)            | Agents navigate by these paths                    |
| Contract field names, types, and required/optional status | Cross-agent communication depends on exact schema |
| Signal type names and their payload fields                | Signal processing is schema-dependent             |
| Preflight gates (Librarian)                               | Silent missing-dir errors break the pipeline      |
| Rework vs. fresh-task branching logic                     | Iterations ≥ 2 follow different code paths        |

---

## 6. Continuous Refinement Triggers

Re-run the checklist (or applicable sections) when:

| Trigger                                     | Sections to re-run                                             |
| ------------------------------------------- | -------------------------------------------------------------- |
| Any instruction file modified               | §1 + §2b (combined budget) + §3 consistency checks             |
| Agent .agent.md frontmatter modified        | §2a + §3a naming + §4 if CLI agent                             |
| New agent added to the workflow             | §1 + §2 (new file) + §3 (all cross-checks) + §4a (plugin.json) |
| Signal type changed or added                | §3b signal consistency (all files)                             |
| Session structure paths changed (README.md) | §1c artifact paths + §3c workflow paths                        |
| plugin.json modified                        | §4a + §4c                                                      |
| build/publish scripts modified              | §4b                                                            |
| Version bump                                | §3e                                                            |

### Measurement Command (body chars)

```powershell
# Measure instruction file body (strip frontmatter, count remaining chars)
$file = "agents/ralph-v2/instructions/ralph-v2-planner.instructions.md"
$content = Get-Content $file -Raw
$body = $content -replace '(?s)^---.*?---\r?\n', ''
"Body chars: $($body.Length)"
```

```powershell
# Measure all 7 instruction files at once
Get-ChildItem agents/ralph-v2/instructions/*.md | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $body = $content -replace '(?s)^---.*?---\r?\n', ''
    [PSCustomObject]@{ File = $_.Name; BodyChars = $body.Length }
} | Format-Table -AutoSize
```

---

## 7. Harness History

| Session       | Pass             | Files changed           | Total chars before | Total chars after | Reduction |
| ------------- | ---------------- | ----------------------- | ------------------ | ----------------- | --------- |
| 260302-001737 | 1st pass         | orchestrator, appendix  | 46,528             | 35,086            | −25%      |
| 260302-142754 | 2nd pass (all 7) | all 7 instruction files | 156,371            | 105,041           | −33%      |

> Update this table after each harness pass. Track which session and which files were touched.
