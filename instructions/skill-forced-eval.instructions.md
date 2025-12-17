---
name: skill-forced-eval
description: 'Forces GitHub Copilot to evaluate and activate referenced Claude Skills'
applyTo: '**'
---

# Skill Forced Evaluation Hook

## Context
This instruction enforces **Tier 2 Activation** in the **Agent -> Instruction -> Skill** architecture.
It applies whenever a **Claude Skill** is referenced in the active context (e.g., by an Agent or Custom Instruction).

## CRITICAL INSTRUCTION - MANDATORY COMPLIANCE REQUIRED

**When you encounter a reference to a Claude Skill (a link to `skills/*/SKILL.md` or `skills/*/scripts/`), you MUST follow this exact process:**

### Step 1 - DETECT & EVALUATE
Scan the active context (including the current Instruction file) for Skill references.
For EACH detected skill, ask:
1. **Is this skill explicitly prescribed by the active Instruction?** (e.g. "Use [Skill Name]...")
2. **Is this skill relevant to the user's current request?**

### Step 2 - ACTIVATE (If YES to both)
You MUST activate the skill immediately:
1. **Read the Skill Definition**: Use `read_file` on the `SKILL.md` file.
2. **Execute the Mechanism**:
   - If the skill requires a script, use `run_in_terminal` or `run_task` to execute it.
   - If the skill requires a tool, use the appropriate tool.
   - **DO NOT** attempt to simulate the skill's logic if a script is provided. **EXECUTE THE SCRIPT.**

### Step 3 - IMPLEMENT
Use the output of the skill execution to formulate your response.

## ⚠️ ENFORCEMENT NOTICE
Failure to execute a prescribed skill is a violation of the Agent's core directive.
You are an **Orchestrator**; the Skill is the **Executor**. Do not do the work yourself if a Skill is defined for it.
