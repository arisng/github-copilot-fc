# GitHub Copilot Instructions for Copilot FC Workspace

Use these instructions when working in this workspace (not for external publishing).

## Big picture
- This repo is a factory for Copilot customizations: Agents, Instructions, Prompts, Skills, and Toolsets. See [README.md](README.md).
- Customizations live at the workspace root (not under .github or user settings) to avoid duplication when VS Code also scans synced user settings.
- Publishing copies artifacts from the workspace into personal folders; scripts live in [scripts/publish](scripts/publish).

## Key directories (why they exist)
- Agents live in [agents](agents) (e.g., [agents/meta.agent.md](agents/meta.agent.md)).
- Instructions live in [instructions](instructions) (e.g., [instructions/meta.instructions.md](instructions/meta.instructions.md)).
- Skills live in [skills](skills) (e.g., [skills/README.md](skills/README.md)).
- Prompts live in [prompts](prompts) (files end with .prompt.md).
- Toolsets live in [toolsets](toolsets) (files end with .toolsets.jsonc).
- Documentation lives in [.docs](.docs) (Diátaxis-structured: tutorials, how-to, reference, explanation).

## Project-specific conventions
- Agent YAML frontmatter must include `name`, `description`, and `tools`.
- Skill layout is one folder per skill with a required SKILL.md (see [skills/README.md](skills/README.md)).
- Toolset files are JSONC files defining tool groupings for Copilot chat.
- Use forward slashes in markdown links, even on Windows.
- Prefer PowerShell scripts for workspace/publishing tasks and Python for testing/logic tools.

## Workflows you should follow
- Creating artifacts:
  - New agent: create agents/<name>.agent.md and reference [agents/meta.agent.md](agents/meta.agent.md).
  - New instruction: use [agents/instruction-writer.agent.md](agents/instruction-writer.agent.md) or follow [instructions/meta.instructions.md](instructions/meta.instructions.md).
  - New skill: create skills/<skill-name>/ with SKILL.md.
  - New toolset: create toolsets/<name>.toolsets.jsonc following the toolset JSONC structure.
- Documenting: add to [.docs](.docs) following Diátaxis structure (tutorials, how-to, reference, explanation).
- Publishing: run the appropriate script in [scripts/publish](scripts/publish) (agents, instructions, prompts, skills, toolsets).
- Testing: Python tooling runs via scripts/run_tests.py; PowerShell tests use Pester (see scripts for patterns).

## Examples worth copying
- Agent structure example: [agents/meta.agent.md](agents/meta.agent.md).
- Instruction structure example: [instructions/meta.instructions.md](instructions/meta.instructions.md).
- Skill publishing workflow: [skills/README.md](skills/README.md).
