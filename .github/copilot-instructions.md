# GitHub Copilot Instructions for Copilot FC Workspace

## Big picture

This repository (`arisng/github-copilot-fc`, origin of this clone) is a **GitHub Copilot customization factory**: a workspace that authors, evaluates, and guards reusable agent artifacts. It has six purposes, listed below. This file grounds any AI agent working *inside this repository* — read it before changing anything.

Key facts:

- There is **no cloud CI**. The gate is local: the lint suite in `scripts/workspace/`, run through `task check` and the git hooks.
- Severity policy everywhere: **WARN = ratchet-pending** (legacy backlog, does not block) and **FAIL = structural rule that is green today**. Never introduce a new FAIL, and do not add new WARNs either — the ratchet is shrink-only.
- Skills are distributed with the Skills CLI: `npx skills add arisng/github-copilot-fc`.
- Artifacts are authored in their source folders (`agents/`, `instructions/`, `hooks/`, `skills/`, `canvas/`) and discovered from `.github/` or copied deliberately.
- The workspace is runtime-agnostic: author for the GitHub Copilot CLI surface first; no editor-specific task, settings, or prompt-file configuration lives in this repo.

## Repo layout

| Path | Contents |
|---|---|
| `skills/` | ~50 public skills, one folder each (`skills/<name>/SKILL.md`); `skills/.archived/` holds retired skills |
| `agents/` | Agent definitions (`agents/nexus.agent.md`); `.archived/` holds retired agents |
| `instructions/` | Custom instruction files (`meta.instructions.md`, `waza-eval.instructions.md`, `powershell.instructions.md`, `csharp-14.instructions.md`, `aspnetcore-10.instructions.md`); `.archived/` holds retired ones |
| `hooks/` | Authored hook folders (`hooks/<name>/<name>.json` + `scripts/`) plus `hooks/README.md` |
| `canvas/` | Canvas/extension sources: `machina-simulator/` and `session-md-reader/` (each has `extension.mjs`, `package.json`, README) |
| `plugins/` | **Intentionally empty** (zero live plugins); reserved for a from-scratch rebuild |
| `schemas/` | `plugin.schema.json`, `marketplace.schema.json`, `skill.schema.json` (JSON Schema draft 2020-12) |
| `scripts/workspace/` | The whole lint suite: `workspace-check.ps1`, `check-consistency.ps1`, `validate-manifests.py`, `check-supply-chain.py`, `generate-skills-catalog.py`, `known-domains.txt` |
| `evals/` | waza evaluations, one folder per evaluated skill |
| `docs/` | Diátaxis-style documentation; currently only `docs/blazor-agui/` |
| `.issues/` | Markdown issue documents plus the generated `.issues/index.md` |
| `.github/` | Workspace-discovered artifacts: this file, `skills/copilot-cli-tools-inventory-refresh/`, `git-scope-constitution.md`, `git-scope-inventory.md`, `copilot-memories.jsonl` |
| `tools/` | Cross-runtime tools inventory (`tools/inventory.yaml`, drift report) |
| `workshops/` | Workshop material (ignored by markdownlint) |
| `.githooks/` | `pre-commit` and `pre-push` hooks |
| `.archived/` | Retired material at repo root; leave it alone |
| root | `Taskfile.yml`, `.markdownlint-cli2.jsonc`, `.waza.yaml` |

## The six purposes

### 1. Authoring public agent plugins

`plugins/` is deliberately **empty** — zero live plugins. It is reserved for a from-scratch rebuild grounded in the `skills/copilot-plugin-builder` skill (Agent Plugins 1.0 packages: skills + MCP servers, plus agents, commands, and hooks). Specs live in `schemas/plugin.schema.json` and `schemas/marketplace.schema.json`; a future marketplace manifest would be `.github/plugin/marketplace.json`, validated and kept in version parity by `skills/copilot-plugin-builder/scripts/verify-version-sync.py` once it exists. Distribution infra for a marketplace is designed but dormant. Do not scaffold plugin stubs unless the task explicitly asks for a rebuild.

### 2. Authoring public individual skills

`skills/` holds ~50 skills. Conventions are documented in `skills/README.md`:

- The `description` is a **router**: partition on the real discriminator with explicit `USE FOR:` and `DO NOT USE FOR:` clauses. Sibling skills must claim each other's exclusions (for example `diataxis` vs `diataxis-categorizer`).
- `metadata.version` (semver) is **required** by `schemas/skill.schema.json`; descriptions are 10–1024 chars and the frontmatter rejects unknown top-level keys.
- Keep the SKILL.md body at **500 lines or fewer**; push rare detail into `references/` and point to it with an explicit relative path — never say "search the skill directory".
- Declare `metadata.status` as `candidate` or `stable` (`stable` is assumed when omitted).
- The catalog table between `<!-- SKILLS-CATALOG:BEGIN -->` and `<!-- SKILLS-CATALOG:END -->` markers in `skills/README.md` is generated; regenerate with `task skills:catalog` after any skill add or frontmatter change.
- Distribution: `npx skills add arisng/github-copilot-fc` (all), `-s <skill>` (one), `-l` (list), and `npx skills update` to refresh installed copies.

### 3. Authoring GitHub Copilot customizations

- **Agents** — `agents/*.agent.md`.
- **Instructions** — `instructions/*.instructions.md`; frontmatter requires `description` (1–500 chars) and `applyTo`, enforced by `scripts/workspace/validate-manifests.py`.
- **Hooks** — authored hook folders in `hooks/`; the Copilot CLI schema is preferred.
- **Canvas/extension sources** — `canvas/<name>/extension.mjs` modules built with the Copilot extension SDK (see `skills/copilot-extension-builder`).
- **Workspace-discovered artifacts** — everything under `.github/`, including this file and the workspace skill `.github/skills/copilot-cli-tools-inventory-refresh/`.

### 4. Maintaining evaluations

Skills and evals are separated: the skill lives in `skills/<name>/`, its harness in `evals/<name>/` (`eval.yaml`, `tasks/*.yaml`, `trigger_tests.yaml`, `graders/`, `results/`). `instructions/waza-eval.instructions.md` is the single source of truth for waza conventions — do not duplicate that prose elsewhere. Policy as of now:

- `waza preflight` is wired into the **full lint suite** for offline structural validation of every `evals/*/eval.yaml` (schema errors FAIL, fixture debt WARNs).
- `waza check` is advisory (a known backlog reports as WARN, never blocks).
- Execution gating (`waza run` / `waza gate`) in CI is **deferred by policy** — do not add it.
- `.waza.yaml` at the repo root carries the token limits (SKILL.md raised to 4000).

### 5. Maintaining local repo guardrails

The lint suite in `scripts/workspace/` plus the JSON Schemas in `schemas/` form the local CI — detailed under "Guardrails & automation" below. When you change an artifact type, update its schema and the matching cross-file rules in the same change so the engine keeps matching the tree.

### 6. Maintaining local repo docs and issues

`docs/` follows Diátaxis categories (tutorials, how-to guides, reference, explanation); today only `docs/blazor-agui/` exists. `.issues/*.md` documents (dated `YYMMDD_title.md` with YAML frontmatter: `date`, `type`, `severity`, `status`) are authored through the `skills/issue-md-writer` skill; `.issues/index.md` is generated — run `task issues:index` after adding or editing any issue, because index freshness is checked by the consistency engine.

## Authoring standards

### Skills

Layout: `skills/<name>/SKILL.md` with optional `references/`, `scripts/`, `assets/`, `tests/`. The directory name must equal the frontmatter `name` (kebab-case, ≤64 chars) — a mismatch is a FAIL. Test Python helpers with `task test` (pytest over `skills/`).

### Agents

`agents/<name>.agent.md` with `name` and `description` frontmatter (plus a `tools` list when needed). Agent `name` uniqueness is a FAIL, `-beta` identities in source are a FAIL, and any EMBED marker must resolve to an existing `instructions/` file. Retire agents by moving them to `agents/.archived/`, not by deleting conventions in place.

### Instructions

`instructions/<name>.instructions.md`, lowercase kebab-case name, required frontmatter `description` + `applyTo` glob. `instructions/meta.instructions.md` is the spec: it defines Level 2 of the Agent → Instruction → Skill architecture (instructions are the policy layer; agents reference them; skills hold procedural detail).

### Hooks

One folder per hook: `hooks/<name>/<name>.json` (the name matching the folder is what Copilot CLI discovery expects) with command scripts under `hooks/<name>/scripts/` (provide both `.ps1` and `.sh` where the hook runs shell logic). Prefer the Copilot CLI schema for shared hook files: lowerCamelCase event keys such as `preToolUse` and `subagentStop`, `bash`/`powershell` command properties, and `timeoutSec`. `hooks/README.md` documents the format; `hooks/skill-description-guard` is the existing advisory guard on overlong skill descriptions.

### Canvas

Each `canvas/<name>/` is a self-contained extension project: `extension.mjs` (SDK entry), `package.json`, README, and tests (for example `npm test` inside `canvas/machina-simulator/`, which runs its node test suite). Keep `node_modules/` out of scope — markdownlint already ignores it.

### Plugins

See purpose 1: empty by design; rebuild only via `skills/copilot-plugin-builder`, with manifests validated against `schemas/plugin.schema.json`.

## Guardrails & automation

### Lint suite

Single entry point:

```powershell
pwsh -NoProfile -File scripts/workspace/workspace-check.ps1        # full suite
pwsh -NoProfile -File scripts/workspace/workspace-check.ps1 -Quick # pre-commit subset
```

Full-suite checks, in order:

1. **Markdown lint** — markdownlint-cli2 over `.md` files changed in the working tree or pending on the branch (a ratchet: touch it, fix it).
2. **Consistency** — `scripts/workspace/check-consistency.ps1`: jsonschema validation via `validate-manifests.py` (plugin/skill/marketplace schemas + instruction frontmatter), cross-file rules (skill dir ↔ name, 500-line body budget, agent name uniqueness, EMBED marker resolution, no `-beta` identity in source), skills-catalog freshness, issues index freshness, and marketplace parity via the shipped verifier when a marketplace index exists.
3. **waza check** — advisory skill-quality report; never blocking.
4. **Supply chain** — `scripts/workspace/check-supply-chain.py`: flags shell-install pipes, insecure plaintext links, un-SRI'd CDN script tags, and link domains outside `scripts/workspace/known-domains.txt` (warn-first; `--strict` is the future ratchet target, `--update-allowlist` regenerates the list).
5. **Eval preflight** — `waza preflight` over every `evals/*/eval.yaml` (offline only).

`-Quick` runs only steps 1–2. Exit is non-zero on any FAIL.

### Taskfile

`Taskfile.yml` (go-task v3) is the command surface — prefer tasks over raw invocations:

```text
task lint            # quick lint (pre-commit gate)
task check           # full suite (pre-push gate); `task` with no args = check
task test            # python3 -m pytest skills -q
task issues:index    # regenerate .issues/index.md
task skills:catalog  # regenerate the skills catalog in skills/README.md
```

### Git hooks

`core.hooksPath` is `.githooks` — **never repoint it**. `.githooks/pre-commit` runs the quick mode (`workspace-check.ps1 -Quick`); `.githooks/pre-push` runs the full suite. Both skip cleanly when `pwsh` is missing so a clone without PowerShell is never bricked.

### Schemas

`schemas/*.schema.json` are draft 2020-12 and validated as schemas themselves by `validate-manifests.py`. That script checks `plugins/<runtime>/<name>/plugin.json` (when plugins exist), every `skills/<name>/SKILL.md` frontmatter, `.github/plugin/marketplace.json` (when present), and instruction frontmatter (`description` 1–500 chars + `applyTo`).

### Markdown lint config

`.markdownlint-cli2.jsonc` disables MD013 (line length), MD024 with `siblings_only` (repeated section names across different parents), MD033, MD036, MD028, and MD060. It has no globs on purpose — inputs come from the caller so a bare config can never fan out to a whole-repo lint of legacy docs. To lint one file manually:

```bash
npx --yes markdownlint-cli2 .github/copilot-instructions.md
```

## Docs & issues conventions

- Write docs in Diátaxis categories and place them under `docs/<topic>/`; keep them lean because the markdownlint ratchet applies to any file you touch.
- Use forward slashes in markdown links: `[skills README](skills/README.md)`.
- Issues live flat in `.issues/`; keep YAML frontmatter complete so `task issues:index` can index them, and commit the regenerated index in the same change.
- Route issue authoring through `skills/issue-md-writer` (it owns the file templates and the metadata extractor the index generator calls).

## Tooling norms

- **PowerShell 7+ only**: invoke scripts as `pwsh -NoProfile -File <path>`. Never Windows PowerShell 5.1 — the suite uses `Set-StrictMode -Version Latest` and modern syntax.
- **`python3`, never `python`**: every Taskfile command and doc example uses `python3` (for example `python3 scripts/workspace/generate-skills-catalog.py`).
- **Forward slashes** in all markdown links and doc snippets, even on Windows.
- **Kebab-case file names** for every new file and folder.
- **`&&` only for native commands** (e.g. `npm test && git status`); in PowerShell scripts use `;` and explicit `if` blocks instead.
- `task` (go-task v3) is installed and is the supported entry point for lint/test/index commands; `git` and `npx` are required by the lint suite.

## Common pitfalls

1. Adding or renaming a skill without `task skills:catalog` → catalog freshness finding.
2. Editing an instruction file without `applyTo` or a 1–500 char `description` → `validate-manifests.py` FAIL.
3. Growing a SKILL.md past 500 lines → WARN ratchet; move detail into `references/`.
4. Creating `skills/<dir>` whose frontmatter `name` differs → consistency FAIL.
5. Adding an `.issues/*.md` file without `task issues:index` → stale index finding.
6. Touching `.githooks/` contents or `core.hooksPath` → forbidden; hooks are the gate.
7. Putting anything into `plugins/` outside a deliberate plugin-builder rebuild → the directory is reserved and empty by design.
8. Re-running scripts with `powershell` (5.1) or `python` → intermittent failures; use `pwsh` and `python3`.
9. Duplicating waza policy prose that `instructions/waza-eval.instructions.md` already owns (it is the single source of truth), or wiring `waza run`/`waza gate` into CI → both violate recorded policy.
10. Editing material under `.archived/`, `agents/.archived/`, `instructions/.archived/`, or `skills/.archived/` → retired content stays retired.
11. Introducing a new lint WARN "just this once" → the ratchet only shrinks; fix the violation instead.
