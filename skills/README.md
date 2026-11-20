# Agent Skills Factory

This repository serves as a factory for creating and publishing agent skills to personal skills folders for reuse across Copilot. Agent Skilss are standardized across coding agents (Claude, Codex, Copilot) so skills published from this factory are also applicable to Codex and Claude.

**Note**: Agents, instructions, hooks, and canvas extensions are authored in their own source folders (`agents/`, `instructions/`, `hooks/`, `canvas/`) and are distributed from the repository itself — see `.github/copilot-instructions.md` for the workspace's authoring and automation conventions.

## References (Official Documentation)

Periodically check official documentation for updates on skill capabilities and best practices:

- [About agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)

## Overview

The skills factory hosts skills in the project workspace (`skills/`) and distributes them to personal skills directories with the Skills CLI (`npx skills`). The default install target is `~/.agents/skills/`.

### Why `skills/` instead of personal skill folders?

**By Design**: Skills are intentionally located in `skills/` (not `.claude/skills/`, `.codex/skills/`, `.copilot/skills/`) to prevent duplication when tools scan for skills.

Skill discovery scans both personal and workspace locations. Installing from this factory keeps the authored copy in `skills/` and the installed copy in the personal folder, so tools see exactly one active copy of each skill.

## Distribution

Skills are distributed with the **Skills CLI** (`npx skills`): installing copies a skill from this repository into your personal skills folder (`~/.agents/skills/` by default). There are no workspace publish scripts — the repository itself is the distribution source.

## Usage

### Via the Skills CLI (preferred)

```bash
# Install every skill published from this repository
npx skills add arisng/github-copilot-fc

# Install a specific skill from this repository
npx skills add arisng/github-copilot-fc -s diataxis

# List the skills a repository offers without installing them
npx skills add arisng/github-copilot-fc -l

# List installed skills
npx skills list

# Remove a skill
npx skills remove <skill>

# Update all installed skills
npx skills update

# Update a single installed skill
npx skills update <skill>
```

The package slug for this repository is `arisng/github-copilot-fc` (the `origin` remote). Run `npx skills update` to pull the latest published version of every installed skill, or `npx skills update <skill>` to refresh a single skill.

## Skill Development Workflow

1. **Create/Edit Skills**: Work on skills in `skills/` directory
2. **Test Locally**: Skills are automatically available in this project
3. **Install**: Install to personal folders for global availability — `npx skills add arisng/github-copilot-fc`
4. **Re-publish**: Run `npx skills update` (all skills) or `npx skills update <skill>` (a single skill) — or run the install command again

## Directory Structure

```text
skills/
├── git-atomic-commit/        # Individual skill
│   └── SKILL.md              # Required skill definition
├── issue-md-writer/
│   ├── SKILL.md
│   └── references/
└── ...

~/.agents/
└── skills/                    # Personal skills (installed via `npx skills`)
    ├── git-atomic-commit/     # Installed from this factory
    └── issue-md-writer/
```

## Skill Catalog

<!-- SKILLS-CATALOG:BEGIN -->
| Skill | Version | Description |
|---|---|---|
| `agent-tools-browsing` | 0.2.0 | **UTILITY SKILL** — Browse the tool names a runtime accepts in a custom agent's `tools:` frontmatter and produce a validated, minimal allowlist; and how to… |
| `aspire-cli` | 0.11.0 | Guidance for using the .NET Aspire CLI and agent integration to create, adopt, run, inspect, debug, update, publish, deploy, and automate Aspire AppHosts. Use… |
| `blazor-ag-ui-agent-framework` | 2.1.0 | Build Blazor-native agent user interfaces using AG-UI protocol with Microsoft Agent Framework (MAF) and ASP.NET Core. Use when implementing the 7 AG-UI… |
| `blazor-blueprint-ui` | 0.4.0 | Build and customize .NET 10+ Blazor UIs with BlazorBlueprint. Use when choosing between BlazorBlueprint.Components and BlazorBlueprint.Primitives, wiring… |
| `blazor-wasm-aot` | 0.1.0 | Build and publish Blazor WebAssembly apps with Mono AOT compilation on .NET 7 (net7.0), including toggling AOT on or off and explaining in plain English what… |
| `cap` | 1.0.0 | Comprehensive guidance for implementing distributed transactions and event bus patterns using DotNetCore.CAP library. Use when working with CAP for… |
| `chrome-extension` | 1.0.0 | Expert knowledge in developing Chrome extensions covering all aspects from basic architecture to advanced features. Covers Manifest V3, service workers,… |
| `cli-wizard-pattern` | 0.1.0 | Add an opt-in interactive wizard mode to an existing script, CLI, or Taskfile task, or build a new script whose required arguments are supplied by the user at… |
| `context7-cli` | 1.0.0 | CLI tool for managing AI coding skills across different AI assistants like Claude, Cursor, and others. Use when you need to search, install, generate, or… |
| `copilot-byok` | 0.22.0 | Configure and switch between BYOK (Bring Your Own Key) LLM providers for GitHub Copilot CLI. Use when setting up OpenAI, Azure OpenAI, Anthropic, Ollama,… |
| `copilot-cli-agent-customization` | 0.1.0 | **WORKFLOW SKILL** — Create, update, review, fix, or debug Copilot CLI customization files (`copilot-instructions.md`, `AGENTS.md`, `*.instructions.md`,… |
| `copilot-cli-subsession` | 0.6.4 | Spawn a new isolated Copilot CLI sub-session from a main Copilot CLI or VS Code session. Use when you need to programmatically create, resume, or chain… |
| `copilot-context-engineering` | 0.3.0 | **DISCIPLINE SKILL** — refine a repo's `.github` customization files (agents, skills, instructions, prompts, constitution) after a merge: each lesson… |
| `copilot-extension-builder` | 0.2.1 | Build custom Copilot extensions — tools, slash commands, and canvas UI surfaces — as Node.js/JavaScript modules using @github/copilot-sdk/extension.… |
| `copilot-plugin-builder` | 0.3.1 | Author, scaffold, test, and distribute GitHub Copilot plugins — portable Agent Plugins 1.0 packages (skills, MCP servers) plus Copilot agents, commands,… |
| `copilot-sdk-dotnet` | 1.2.0 | Build applications with GitHub Copilot CLI SDKs for .NET. Use for direct CopilotClient integration or Microsoft Agent Framework. Covers sessions, streaming,… |
| `copilot-session-telemetry` | 0.4.0 | Audit the real-session efficiency of an agent skill's execution episode in a Copilot session against four goals - minimize LLM token usage, minimize execution… |
| `csharp-file-based-apps` | 0.2.0 | Write and run C# programs without a .csproj or solution file using .NET 10+ file-based apps, including multi-file apps with `#:include` (.NET 11+). Use when… |
| `d2` | 1.0.0 | Author, verify, and export D2 (d2lang) diagram-as-code, and package the output as self-contained HTML for web apps. Covers declarative syntax for shapes,… |
| `daily-report` | 1.1.0 | Generate a one-page daily report for one git user, grounded in a single calendar day: git proof plus repo-scoped Copilot session evidence, rendered as… |
| `diataxis` | 1.0.0 | Create and evaluate documentation using the Diátaxis framework. Use when writing, organizing, or auditing documentation to ensure it serves distinct user… |
| `diataxis-categorizer` | 1.0.0 | Classify documentation files into domain-based sub-categories within Diátaxis top-level categories (tutorials, how-to, reference, explanation). Use when… |
| `frontend-skill` | 1.0.0 | Use when the task asks for a visually strong landing page, website, app, prototype, demo, or game UI. This skill enforces restrained composition, image-led… |
| `gcloud-cli` | 1.0.0 | Execute Google Cloud Platform operations using the gcloud CLI (and gsutil/bq where applicable). Use when the user wants to: authenticate with GCP, manage GCP… |
| `git-atomic-commit` | 2.4.0 | Group changed files into atomic conventional commits: assign each file a type and scope, plan a build-safe sequence, write type(scope) messages, and execute… |
| `git-commit-scope-constitution` | 2.1.0 | Build and maintain the repository's commit scope constitution (.github/git-scope-constitution.md): approved scopes per type, naming rules, boundaries,… |
| `git-session-atomic-commits` | 0.3.0 | Session-scoped commit orchestrator: commit only files with evidence of belonging to the current agent session and leave every other dirty worktree change… |
| `git-worktree-generic` | 1.0.0 | Create, manage, and clean up git worktrees using native git commands only. Works with any language, any repo, any platform — no custom scripts, no framework… |
| `github-pages-deploy` | 0.1.0 | Deploy a static HTML file or static site directory to GitHub Pages. Use when the user wants a durable GitHub-hosted URL for a static page, diagram, report, or… |
| `github-pr-media` | 0.2.2 | Upload a local image or video file to GitHub's user-attachments API and embed the returned hosted URL in a pull request description or comment. Use when asked… |
| `googleworkspace-cli` | 0.1.0 | Unified CLI interface for Google Workspace APIs (Drive, Gmail, Calendar, Sheets, Docs, Chat, Admin, etc.) with structured output and multi-service support |
| `handoff` | 1.0.0 | Compact the current conversation into a handoff document for another agent to pick up. |
| `issue-md-writer` | 2.2.0 | Create and draft markdown-based issue documents (bug reports, feature plans, RFCs, ADRs, tasks, retrospectives) in the top-level `.issues/` folder. Use this… |
| `issue-relevance-check` | 0.1.0 | Slash command to evaluate whether an issue or pull request is still relevant, actionable, and worth keeping open |
| `issue-tracking` | 1.0.1 | Repo-agnostic issue tracking for local markdown stores - bootstraps .github/issue-tracker.json on first use (interactive Q&A or auto-inferred in autopilot;… |
| `join-copilot-fc` | 1.0.0 | Extract (promote) a repo-level agent skill from the current repository into the github-copilot-fc skills factory and publish it as a user-level skill — the… |
| `machina-authoring` | 0.4.0 | Author valid, high-scoring state machines in Machina machine JSON format (spec v3.0.0 / v2.0.0 / v1.0.0). USE WHEN: writing or generating a machine definition… |
| `machina-driving` | 0.5.2 | Drive a Machina state machine to a deterministic outcome on behalf of an AI agent. USE WHEN: a task is governed by a state machine (a machine definition JSON… |
| `mermaid-creator` | 1.0.0 | Create Mermaid diagrams (activity, deployment, sequence, architecture) from text descriptions or source code. Use when asked to "create a diagram", "generate… |
| `mssql-cli` | 1.0.0 | Query SQL Server databases from the command line using mssql-cli (or sqlcmd). Use when the user provides a SQL Server connection string and needs to execute… |
| `playwright-cli` | 1.1.0 | Automates browser interactions for web testing, form filling, screenshots, and data extraction. Use when the user needs to navigate websites, interact with… |
| `postrboard-design` | 1.0.0 | Apply the Postrboard design language — a refined, airy, code-native aesthetic used across postrboard.com and burkeholland.github.io — when designing or… |
| `skill-eval` | 0.3.0 | Optimize existing AI agent skills with a dual-loop workflow for activation tuning and execution quality. Use when improving a skill after initial creation,… |
| `speckit-task-grounding` | 1.0.0 | Task grounding validation framework for ensuring development tasks are properly specified in planning artifacts before implementation. Use when validating… |
| `standup` | 0.6.2 | Generate daily standup reports from Copilot session history and git data. Scoped to the current git user; files accumulate multi-author contributions in… |
| `taskfile-authoring` | 0.1.0 | Author and maintain Taskfile.yml files for the Task runner (taskfile.dev). Use when creating, editing, or troubleshooting Taskfiles, writing task definitions,… |
| `tldraw-creator` | 0.1.0 | Programmatically create tldraw whiteboards and visualize them with a self-hosted tldraw instance. Create boards with shapes, text, and connectors, then deploy… |
| `triage-backlog` | 0.10.0 | Triage a GitHub issue backlog — classify, prioritize, dedup, and groom issues. Repo-agnostic: each repo supplies its own label taxonomy via a triage.json… |
| `visual-explainer` | 0.2.1 | Generate beautiful, self-contained HTML pages that visually explain systems, code changes, plans, and data. Use when the user asks for a diagram, architecture… |
| `vn-payroll` | 1.0.0 | Calculates Net Income, Personal Income Tax (PIT), and Social Insurance (BHXH) based on Vietnam's progressive tax brackets. |
| `waza-cli` | 0.3.0 | Drive the waza CLI (microsoft/waza) — the default skill-evaluation tool for this workspace — to check skill readiness for free (waza check, waza tokens), run… |
<!-- SKILLS-CATALOG:END -->

Generated from every `skills/*/SKILL.md` frontmatter. Regenerate after adding or updating a skill: `python3 scripts/workspace/generate-skills-catalog.py` (the gate checks freshness with `--check`).

## Best Practices

### For Skill Authors

- Keep skills focused on single responsibilities
- Write clear, specific descriptions for better discovery
- Include examples and usage instructions in SKILL.md
- Test skills thoroughly before publishing

**Description-as-router**: every SKILL.md `description` must partition on the real discriminator using explicit `USE FOR:` (positive triggers) and `DO NOT USE FOR:` (negative space) clauses. Sibling skills must each claim the other's exclusions so routing never double-claims. Keep every `description` within the existing 1,024-character cap (enforced as a warning by `hooks/skill-description-guard`).

**Body budget**: keep the SKILL.md body at 500 lines or fewer. Push rare or expensive detail into `references/` and point to it with an explicit relative path (e.g. `references/details.md`) — never tell the agent to "search the skill directory".

**Lifecycle**: declare `metadata.status` in SKILL.md frontmatter as `candidate` or `stable` (`stable` is assumed when omitted). New or experimental skills start as `candidate` and graduate to `stable` once their eval and router description settle — mirroring the tools inventory's `Status: candidate` convention.

Worked example — a sibling pair that partitions cleanly:

```text
diataxis/SKILL.md
  USE FOR: classifying documentation into the four Diátaxis categories (tutorials, how-to, reference, explanation). DO NOT USE FOR: naming domain sub-folders within a category (use diataxis-categorizer).
diataxis-categorizer/SKILL.md
  USE FOR: naming domain sub-folders within one Diátaxis category. DO NOT USE FOR: classifying into the four top-level categories (use diataxis).
```

> **Source**: this convention comes from the **dotnet/skills authoring quality bar** (learned 2026-11-19).

### For Publishing

- Install/update with the Skills CLI: `npx skills add arisng/github-copilot-fc` / `npx skills update`
- Re-run the update command after changing an installed skill
- Backup your personal skills folder before major operations

### For Team Collaboration

- Commit skill improvements to the factory repository
- Use the update scripts to sync personal skills
- Document breaking changes in skill descriptions
- Consider semantic versioning for major skill updates

## Troubleshooting

### Common Issues

**Skill not discovered**

- Run `npx skills list` to confirm it is installed
- Start a new agent session so discovery re-scans
- Check that SKILL.md has valid YAML frontmatter

**Changes not appearing**

- Re-run `npx skills update`
- Verify the skill exists in `skills/`

### Recovery

```powershell
# Reinstall every skill from this factory
npx skills add arisng/github-copilot-fc

# Reinstall a single skill
npx skills add arisng/github-copilot-fc -s <skill-name>
```

## Future Enhancements

- **Package Registry**: NPM-style skill packages
- **Version Management**: Semantic versioning for skills
- **Dependency Resolution**: Skills that depend on other skills
- **Cross-platform Links**: Improved symbolic link support
- **Automated Publishing**: GitHub Actions for automatic publishing
