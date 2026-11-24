# GitHub Copilot Instructions for Copilot FC Workspace

## Big picture

This repository (`arisng/github-copilot-fc`, origin of this clone) is a **GitHub Copilot customization factory**: a workspace that authors, evaluates, and guards reusable agent artifacts. It has six purposes, listed below. This file grounds any AI agent working *inside this repository* — read it before changing anything.

Key facts:

- The gate is the lint suite in `scripts/workspace/`, run through `task check`, the git hooks, and the `ci` GitHub Actions workflow (`.github/workflows/ci.yml` — the backstop for clones that never ran `task hooks:install`). **`git push` runs that suite via `.githooks/pre-push` — expect ~90 s of quiet before output appears; slow is the gate working, not a hang or failure.**
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
| `plugins/` | **Empty by design** — rebuild per purpose 1 |
| `schemas/` | `plugin.schema.json`, `marketplace.schema.json`, `skill.schema.json` (JSON Schema draft 2020-12) |
| `scripts/workspace/` | The whole lint suite: `workspace-check.ps1`, `check-consistency.ps1`, `validate-manifests.py`, `check-supply-chain.py`, `generate-skills-catalog.py`, `known-domains.txt` |
| `evals/` | waza evaluations, one folder per evaluated skill |
| `docs/` | Diátaxis-style documentation; `docs/blazor-agui/` and `docs/ci-gates/` |
| `.issues/` | Markdown issue documents plus the generated `.issues/index.md` |
| `.github/` | Workspace-discovered artifacts: this file, `.github/skills/copilot-cli-tools-inventory-refresh/`, `git-scope-constitution.md`, `git-scope-inventory.md` |
| `tools/` | Cross-runtime tools inventory (`tools/inventory.yaml`, drift report) |
| `workshops/` | Workshop material (ignored by markdownlint) |
| `.githooks/` | `pre-commit` and `pre-push` hooks |
| `.archived/` | Retired material (repo root and per-tree `.archived/` folders); never edit |
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

`docs/` follows Diátaxis categories (tutorials, how-to guides, reference, explanation) — see the layout table above for the current topics, alongside `docs/ci-gates/reference.md` for the local-vs-cloud gate boundary. `.issues/*.md` documents (dated `YYMMDD_title.md` with YAML frontmatter: `date`, `type`, `severity`, `status`) are authored through the `skills/issue-md-writer` skill; `.issues/index.md` is generated — run `task issues:index` after adding or editing any issue, because index freshness is checked by the consistency engine.

## Authoring standards

### Skills

Layout: `skills/<name>/SKILL.md` with optional `references/`, `scripts/`, `assets/`, `tests/`. The directory name must equal the frontmatter `name` (kebab-case, ≤64 chars) — a mismatch is a FAIL. Test Python helpers with `task test` (pytest over `skills/`).

### Agents

`agents/<name>.agent.md` with `name` and `description` frontmatter (plus a `tools` list when needed). Agent `name` uniqueness is a FAIL, `-beta` identities in source are a FAIL, and any EMBED marker must resolve to an existing `instructions/` file. Retire agents by moving them to `agents/.archived/`, not by deleting conventions in place.

### Instructions

`instructions/<name>.instructions.md`, lowercase kebab-case name, required frontmatter `description` + `applyTo` glob. `instructions/meta.instructions.md` is the spec: it defines Level 2 of the Agent → Instruction → Skill architecture (instructions are the policy layer; agents reference them; skills hold procedural detail).

### Hooks

One folder per hook: `hooks/<name>/<name>.json` (the name matching the folder is what Copilot CLI discovery expects) with command scripts under `hooks/<name>/scripts/` (provide both `.ps1` and `.sh` where the hook runs shell logic). Prefer the Copilot CLI schema for shared hook files: lowerCamelCase event keys such as `preToolUse` and `subagentStop`, `bash`/`powershell` command properties, and `timeoutSec`. `hooks/README.md` documents the format; skill-description length is enforced by `schemas/skill.schema.json` (10-1,024 chars) via `scripts/workspace/validate-manifests.py`.

### Canvas

Each `canvas/<name>/` is a self-contained extension project: `extension.mjs` (SDK entry), `package.json`, README, and tests (for example `npm test` inside `canvas/machina-simulator/`, which runs its node test suite). Keep `node_modules/` out of scope — markdownlint already ignores it.

### Plugins

See purpose 1: empty by design; rebuild only via `skills/copilot-plugin-builder`, with manifests validated against `schemas/plugin.schema.json`.

## Guardrails & automation

The exact local-vs-cloud gate boundary (which mode runs which check, what blocks, what is deliberately unwired) is documented in [docs/ci-gates/reference.md](../docs/ci-gates/reference.md) — consult it before changing hooks, workflows, or the check list.

### Lint suite

Single entry point:

```powershell
pwsh -NoProfile -File scripts/workspace/workspace-check.ps1        # full suite
pwsh -NoProfile -File scripts/workspace/workspace-check.ps1 -Quick # pre-commit subset
```

Full-suite checks, in order:

1. **Markdown lint** — full-repo markdownlint-cli2 scan compared with the frozen-debt baseline `scripts/workspace/markdown-debt-baseline.txt`: legacy debt passes at its recorded per-file count, and any new file or count increase FAILs (regenerate the baseline with `workspace-check.ps1 -UpdateMarkdownBaseline` only to accept a reviewed change).
2. **Consistency** — `scripts/workspace/check-consistency.ps1`: jsonschema validation via `validate-manifests.py` (plugin/skill/marketplace schemas + instruction frontmatter), cross-file rules (skill dir ↔ name, 500-line body budget, agent name uniqueness, EMBED marker resolution, no `-beta` identity in source), skills-catalog freshness, issues index freshness, and marketplace parity via the shipped verifier when a marketplace index exists.
3. **PowerShell lint** — `scripts/workspace/check-powershell.ps1` over every `.ps1`: parse errors, the parameter-clobber pattern (a parameter assigned before its first read), and cross-platform portability (`.exe` suffixes, `$env:TEMP` in tests).
4. **waza check** — advisory skill-quality report; never blocking.
5. **Supply chain** — `scripts/workspace/check-supply-chain.py`: flags shell-install pipes, insecure plaintext links, un-SRI'd CDN script tags, and link domains outside `scripts/workspace/known-domains.txt` (warn-first; `--strict` is the future ratchet target, `--update-allowlist` regenerates the list).
6. **Eval preflight** — `waza preflight` over every `evals/*/eval.yaml` (offline only).

`-Quick` runs steps 1–3 (markdown, consistency, PowerShell lint). Exit is non-zero on any FAIL.

**Parse-check a directory before iterating.** `check-powershell.ps1` takes `-Path`, parses in well under a second, and reports the line and token:

```powershell
pwsh -NoProfile -File scripts/workspace/check-powershell.ps1 -Path skills/<name>
```

Run it after editing `.ps1` files and before re-running the suite. The full suite spends minutes on test suites that a one-line parse typo (a stray `}`, a collapsed `$x = 1if (...)`) fails 80 seconds later; the scoped parse check catches the same errors in under one second.

### Taskfile

`Taskfile.yml` (go-task v3) is the command surface — prefer tasks over raw invocations:

```text
task lint            # quick lint (pre-commit gate)
task check           # full suite (the CI gate); `task` with no args = check
task test            # python3 -m pytest skills -q
task issues:index    # regenerate .issues/index.md
task skills:catalog  # regenerate the skills catalog in skills/README.md
```

### Git hooks

`core.hooksPath` is `.githooks` — **never repoint it**. Wire each fresh clone or worktree once with `task hooks:install`. Three hooks run, cheapest first:

| Hook | Runs | Cost |
|---|---|---|
| `commit-msg` | `scripts/workspace/check-commit-message.ps1` — validates `type(scope)` against the constitution | <1 s |
| `pre-commit` | `workspace-check.ps1 -Quick` | ~8 s |
| `pre-push` | `workspace-check.ps1 -SkipAdvisoryWaza` | ~90-180 s |

`.github/workflows/ci.yml` runs the complete `task check` on every push/PR. All three hooks skip cleanly when `pwsh` is missing so a clone without PowerShell is never bricked.

**Checking before you commit:** run `task lint` (the pre-commit subset, ~8 s). Do not run the full `task check` by hand as a pre-flight — the pre-push hook runs the same suite on the tree you are about to push, so a manual full run is duplicated work. Run `task check` by hand only to debug a pre-push failure, or when you want the advisory waza check the push deliberately skips.

**Cross-platform test changes:** fixtures that read differently on Linux (paths, sqlite, git identity) get one more local lane — `task check:linux` runs the Pester suites in a Docker ubuntu container, the ubuntu-latest parity the Windows gate cannot give (needs Docker; the first run pulls the image).

### Schemas

`schemas/*.schema.json` are draft 2020-12 and validated as schemas themselves by `validate-manifests.py`. That script checks `plugins/<runtime>/<name>/plugin.json` (when plugins exist), every `skills/<name>/SKILL.md` frontmatter, `.github/plugin/marketplace.json` (when present), and instruction frontmatter (`description` 1–500 chars + `applyTo`).

### Markdown lint config

`.markdownlint-cli2.jsonc` disables MD013 (line length), MD024 with `siblings_only` (repeated section names across different parents), MD033, MD036, MD028, and MD060. It has no globs on purpose — inputs come from the caller so a bare config can never fan out to a whole-repo lint of legacy docs. To lint one file manually:

```bash
npx --yes markdownlint-cli2@0.24.2 .github/copilot-instructions.md
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
- **Kebab-case directory names** in every authored tree — FAIL-checked by the consistency engine; file names are kebab-case too except where a toolchain owns the name (pytest `test_*.py`, waza `trigger_tests.yaml`).
- **`&&` only for native commands** (e.g. `npm test && git status`); in PowerShell scripts use `;` and explicit `if` blocks instead.
- `task` (go-task v3) is installed and is the supported entry point for lint/test/index commands; `git` and `npx` are required by the lint suite.
- **`pwsh -File` passes an array parameter as one string.** `-IssueTypes task,bug,feature` arrives as a single element, not three, so any `[string[]]` parameter documented as a list must split on commas itself (`.Split(',')`, or the skill's `ConvertTo-StringList`). Accept both shapes: an array from an in-process call, and a comma-joined scalar from the CLI.
- **Tool-quirk sharp edges**: pass filesystem paths to search/listing tools as plain strings (never JSON-array-shaped strings), and hand grep-style tools a **directory** plus a glob — a file path or array fails with "Search paths do not exist". Address the shell tool by its lowercase name `powershell`. `Select-String -Context` needs the space (`-Context 1,1`, never `-Context1,1`). Wrap one-item pipelines in `@()` before splatting (`& cmd @scalar` otherwise passes one character per argument), and write `${var}:` when a variable meets a colon inside a double-quoted string.
- **Pushes that touch `.github/workflows/**` go through gh's token**: Git Credential Manager's stored OAuth token lacks the workflow scope, so GitHub rejects those pushes with "OAuth App ... without the workflow scope"; run `git -c credential.helper= -c "credential.https://github.com.helper=!gh auth git-credential" push origin main`. Ordinary pushes use the normal remote.
