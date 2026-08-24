---
name: copilot-context-engineering
description: "Discipline for refining agent customization files in the `.github` folder standard — `.github/agents/*.agent.md`, `.github/skills/*/SKILL.md`, `.github/instructions/*.instructions.md` — after a PR merge or commit. Codifies lessons as durable SINGLE-SOURCED / SINGLE-OWNER homes that are INHERITED BY REFERENCE, never duplicated prose across multiple files. Use when asked to codify lessons learned, add a rule to agent/skill/instruction files, refine agent customization after merge, avoid duplication/drift, or decide which file owns a piece of guidance."
metadata:
   version: 0.1.0
---

# Context Engineering

Context Engineering is the discipline of refining an **agent context file set** — custom
agent definitions (`.github/agents/*.agent.md`), skills (`.github/skills/*/SKILL.md`),
scoped instruction files (`.github/instructions/*.instructions.md`), plus the root
constitution file (`.github/copilot-instructions.md`, `AGENTS.md`, or equivalent) the host
repo uses — so that lessons learned are codified once, in exactly one authoritative owner,
and inherited everywhere else **by reference**.

## The Standard Layout

Treat the following `.github` folder structure as the repo standard:

```text
.github/
├── copilot-instructions.md   # Root constitution: universal rules + authority model
├── agents/*.agent.md         # Agent orchestration behavior
├── skills/*/SKILL.md         # Task playbooks
└── instructions/*.instructions.md  # Scoped repo policy with applyTo patterns
```

Before refining anything:

1. **Confirm the layout exists.** Check for `.github/copilot-instructions.md` (or `AGENTS.md`)
   and the three directories above. The root constitution defines universal rules and often an
   authority model mapping asset types to ownership.
2. **Adopt the host's documented authority model** if present; it supersedes the default
   decision table below.
3. **Handle deviations gracefully.** If a repo relocates customization elsewhere
   (`.claude/skills/`, `.agents/skills/`, …), apply this discipline to wherever its files live,
   but never invent new top-level conventions for a repo that already follows the `.github`
   standard.
4. **Respect protected areas** the repo declares (shared framework code, generated artifacts,
   persisted state). Refinements touch only agent customization files — never protected areas.

## Core Technique

**When distilling a lesson learned, codify it as a durable, single-sourced, single-owner home that is inherited by reference — never as repeated prose duplicated across multiple agent customization files.**

Duplicated prose makes files overlap, then silently diverge as each is edited independently — more noise than signal, stale or contradictory guidance. One owner + inherited-by-reference gives a single source of truth and a single place to update.

## When to Refine (Trigger)

Run this discipline after a PR merge or a commit when the work surfaced a lesson worth keeping:

- A debugging loop revealed a non-obvious behavior (tooling quirks, environment pitfalls).
- A cross-cutting rule was learned the hard way (auth gating, URL resolution, credential scoping).
- A QA/verification invariant became clear (e.g. "verify access constraints by authenticating the real persona").
- Any guidance was repeated verbatim in more than one file during the work — that is a drift smell to fix.

The goal is a "systematic inheritance and combination" model across the whole file set: each
file has a clear, non-overlapping responsibility, and cross-cutting lessons live in exactly
one owner that the rest reference.

## Owner-Assignment Decision Table

Choose the **single most-specific owning file** per the host repo's authority model (if documented), otherwise per this default table:

| Concern kind | Default owner | Example |
|---|---|---|
| Repo-wide policy (operations, conventions, architecture, auth) | Scoped `.github/instructions/*.instructions.md` (or a section in the root constitution if no scoped files exist) | API conventions, tenant URL resolution |
| An agent's own execution/orchestration behavior | The agent's `.github/agents/*.agent.md` file | A QA smoke rule belongs in the QA agent file |
| A task playbook driven only by one skill | That skill's `.github/skills/<name>/SKILL.md` | A workflow only that skill drives |

If a rule is both policy and an agent's execution rule, prefer the instruction file for the policy itself and let the agent reference it.

## Write Once, Inherit by Reference

1. **Write the lesson once** in its owner file (per the decision table above).
2. **Do not restate the prose** in consumer files.
3. **Add a thin pointer** to consumers that must know the rule:

   > → see `qa-agent.agent.md` ("Verify Access Constraints, Never Assume Them")

   Pointers should name the owning file and, where helpful, the section. Keep them a single line or bullet.

### Use the Existing Inheritance Mechanisms

- **Agents**: add the pointing file to the agent's always-on instructions list, or add a one-line pointer in the specific behavior block. Never paste the policy prose inline.
- **Skills**: reference the owner in a "Load With" list or a related-files line. Never paste the policy prose inline.
- If a pre-existing file already holds a divergent copy, **do not edit that copy** to sync it — leave it untouched and point consumers to the new owner.

## Drift-Detection Scan (Before You Add a Lesson)

Before writing any lesson into a file, **first scan for existing coverage / an existing owner** across all customization directories:

```powershell
# Search all customization files for the key phrase of the lesson
grep -ri "<key-phrase>" .github/agents .github/skills .github/instructions
```

- **If a lesson already exists** → reference its owner from wherever a consumer needs it. Do not create a second copy.
- **If a lesson exists in multiple files with matching prose** → that is pre-existing drift; leave the divergent copies alone, keep the most authoritative owner, and reference it.
- **If no owner exists** → create the owner (per the decision table) in a single file, then add references in consumers.

## How To Workflow

1. **Identify the lesson** — name the durable rule in one sentence.
2. **Pick the owner** — use the decision table; exactly one file.
3. **Write the lesson once** — into that owner file, in its natural section.
4. **Add references in consumers** — thin pointers ("→ see `<file>` (`<section>`)") in every file that must know the rule, using the existing inheritance mechanisms.
5. **Verify no duplicate prose remains** — grep the key phrase. It should appear **only in the owner**, plus thin pointers elsewhere:

   ```powershell
   # The full lesson prose should grep to exactly one file (the owner)
   grep -rl "<full-lesson-phrase>" .github/agents .github/skills .github/instructions
```

   Pointers are allowed everywhere; full prose is allowed in exactly one owner.

## Motivating Example

After a debugging loop against a distributed-app stack, four lessons were codified with single-owner placement each:

| Lesson | Owner (single) |
|---|---|
| Restart the orchestrator/AppHost rather than restarting individual project resources mid-run (they can hang waiting) | Operations instructions file |
| User-facing URLs must resolve via a dedicated resolver policy, not ad-hoc domain assumptions | Scoped instructions file for that concern |
| Login admits all authenticated users at the entry point while individual pages gate per-role | Instructions file for that app surface |
| QA smoke: verify access constraints by authenticating the real persona, never assume rejection behavior | The QA agent's execution block in its `*.agent.md` |

The orchestrating agent's file received **only** concise inheriting pointers referencing the four owners — not restated generic-policy items.

**Wrong approach (drift):** writing the same prose verbatim into the operations instructions **and** the orchestrator agent file **and** an unrelated skill's `SKILL.md`.

## Guardrails

- **Never duplicate.** One concern, one owner, one copy of the prose.
- **Never edit multiple owners** for a single concern.
- **Keep pointers thin.** A pointer that grows into prose is drift in disguise — if a pointer needs a full paragraph, the rule belongs in the owner, not the pointer.
- **Respect protected areas.** Only modify agent customization files; never hand-edit persisted state, generated artifacts, or memory/knowledge-graph stores the repo governs through dedicated processes.
- **Do not edit third-party/upstream skill files** you don't own. Create clearly-suffixed forks if a customization requires deviation.
