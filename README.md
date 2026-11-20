# GitHub Copilot FC

GitHub Copilot FC is a **customization factory for GitHub Copilot** — a single workspace where
agent plugins, individual skills, Copilot customizations, evaluations, guardrails, and
documentation are authored, validated, and maintained. Skills are distributed straight from this
repository with the Skills CLI, customizations live in dedicated source folders, and an automated
lint suite wired into git hooks keeps the whole workspace consistent.

## Purposes

This repository exists to:

1. **Author public agent plugins** — `plugins/` is intentionally empty today, reserved for a
   from-scratch rebuild grounded in the `skills/copilot-plugin-builder` skill; `schemas/` holds
   the plugin, marketplace, and skill JSON Schemas that rebuild must satisfy.
2. **Author public individual skills** — `skills/` holds ~50 standalone skills, distributed to
   any agent environment via `npx skills add arisng/github-copilot-fc`.
3. **Author GitHub Copilot customizations** — custom agents (`agents/`), instruction files
   (`instructions/`), hooks (`hooks/`), Copilot canvas/extension sources (`canvas/`), and
   workspace-discovered customizations (`.github/`).
4. **Maintain evaluations** — `evals/` holds waza evaluation suites, with conventions codified
   in `instructions/waza-eval.instructions.md`. Validation is structural only; execution gating
   in CI is deferred.
5. **Maintain local repo guardrails** — an automated lint suite under `scripts/workspace/`,
   backed by JSON Schemas in `schemas/`.
6. **Maintain local repo docs and issues** — `docs/` (currently `docs/blazor-agui/`, four
   explanation pages) and `.issues/`, indexed by `.issues/index.md`.

## Repository layout

| Path | Description |
| ---- | ----------- |
| `.github/` | Workspace-discovered customizations: shared skills, memories, and git-scope docs. |
| `.githooks/` | `pre-commit` and `pre-push` hooks (enable with `git config core.hooksPath .githooks`). |
| `.issues/` | Planning/change issue documents; `index.md` is generated from issue frontmatter. |
| `Taskfile.yml` | go-task v3 entry points: `lint`, `check`, `test`, `issues:index`, `skills:catalog`. |
| `agents/` | Custom agent definitions (`*.agent.md`). |
| `canvas/` | Copilot canvas/extension sources: `machina-simulator`, `session-md-reader`. |
| `docs/` | Repository documentation; currently `docs/blazor-agui/` with four explanation pages. |
| `evals/` | waza evaluation suites — one directory per skill, each with `eval.yaml` and task YAML. |
| `hooks/` | Agent hook configurations: one directory per hook with manifest and companion scripts. |
| `instructions/` | Reusable instruction files (`*.instructions.md`). |
| `plugins/` | Intentionally empty — reserved for the plugin rebuild (see below). |
| `schemas/` | JSON Schemas for plugins (`plugin.schema.json`), marketplaces, and skills. |
| `scripts/workspace/` | The lint suite: `workspace-check.ps1` plus consistency, manifest, supply-chain, and catalog checks. |
| `skills/` | ~50 public skills — see [`skills/README.md`](skills/README.md) for authoring conventions. |
| `tools/` | Cross-runtime tools inventory (`inventory.yaml`) with generated drift reports. |

## Workflows

The repo uses [go-task](https://taskfile.dev) (`Taskfile.yml`) as the single entry point for
automation:

| Command | What it does |
| ------- | ------------ |
| `task lint` | Quick lint — changed markdown plus schema/consistency engine (the pre-commit gate). |
| `task check` | Full lint suite — all workspace checks (the pre-push gate; also the default task). |
| `task test` | Run skill test suites — pytest over `skills/`. |
| `task issues:index` | Regenerate `.issues/index.md` from issue frontmatter. |
| `task skills:catalog` | Regenerate the skills catalog table in `skills/README.md`. |

### Git hooks

Hooks are wired once per clone with `git config core.hooksPath .githooks`, then run
automatically:

- `.githooks/pre-commit` runs the quick lint mode (equivalent to `task lint`) and blocks the
  commit on lint violations.
- `.githooks/pre-push` runs the full suite (equivalent to `task check`) and blocks the push on
  any failure.

Both hooks skip cleanly when `pwsh` is missing from `PATH`, so a clone without PowerShell is
never bricked.

### The lint suite

`scripts/workspace/workspace-check.ps1` orchestrates the checks:

- `check-consistency.ps1` — cross-file consistency checks.
- `validate-manifests.py` — JSON Schema validation (jsonschema engine against `schemas/`).
- `check-supply-chain.py` — supply-chain sanity checks.
- `generate-skills-catalog.py` — regenerates the catalog table in `skills/README.md`.
- `waza check` (advisory) and offline `waza preflight` over `evals/`.
- markdownlint over the markdown files changed in the working tree (config in
  `.markdownlint-cli2.jsonc`).

## Using the skills

Install everything this repository offers, or a single skill by name:

```bash
# Install every skill from this repository
npx skills add arisng/github-copilot-fc

# Install one specific skill
npx skills add arisng/github-copilot-fc -s <name>
```

Skills are copied into your personal skills folder (`~/.agents/skills/` by default), so agent
tools find exactly one active copy of each skill. For skill-authoring conventions, distribution
details, and the full catalog, see [`skills/README.md`](skills/README.md).

## Plugins: empty by design

`plugins/` contains no live plugins yet. It is an intentionally empty folder reserved for a
from-scratch rebuild of the plugin factory, grounded in the
[`copilot-plugin-builder`](skills/copilot-plugin-builder/SKILL.md) skill and validated against
the JSON Schemas in `schemas/`. Until that rebuild lands, treat the schemas — not folder
contents — as the contract.

## Contributing

1. Create or edit artifacts in their source folders (`skills/`, `agents/`, `instructions/`,
   `hooks/`, `canvas/`, `evals/`, `docs/`).
2. Run `task check` before pushing — the git hooks run the same gates automatically.
3. After editing issue frontmatter or the skills catalog, regenerate with `task issues:index`
   and `task skills:catalog`.
4. Follow [`skills/README.md`](skills/README.md) when authoring or modifying a skill.

## License

MIT — see [LICENSE](LICENSE).
