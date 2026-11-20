# Plugin Submission Review

Sectioned PASS/FAIL checklist to run **before shipping any plugin**. Execute every
command from the repo root, work top to bottom, then report one verdict line per
section plus a prioritized fix list (format in "Report format" below).

## Manifest validity

```bash
python3 scripts/workspace/validate-manifests.py
```

Expected: exit `0` — only `[PASS]`/`[SKIP]` lines ending in
`validate-manifests: N artifact(s) green, 3 schemas valid`. Evidence covers every live
`plugins/<runtime>/<name>/plugin.json` against `schemas/plugin.schema.json`, every
`skills/*/SKILL.md` frontmatter against `schemas/skill.schema.json`,
`.github/plugin/marketplace.json` against `schemas/marketplace.schema.json` (when
present), and instruction/eval artifacts. Any `[FAIL]` line or a `failure(s)` summary
fails the section.

Verdict: `[PASS] Manifest validity: validate-manifests.py exit 0 — N artifact(s) green, 3 schemas valid`

## Cross-file consistency

```bash
pwsh -NoProfile -File scripts/workspace/check-consistency.ps1
python3 skills/copilot-plugin-builder/scripts/verify-version-sync.py .
```

- Checker must exit `0` with `check-consistency: 0 FAIL, ...` — proves plugin dir <->
  manifest `name`, component path resolution, `<!-- EMBED: ... -->` resolution, no
  `-beta` identity in source, skill dir <-> frontmatter name, agent name uniqueness,
  and marketplace parity (wired through the verifier below). WARNs do not block.
- Verifier must exit `0` whenever `.github/plugin/marketplace.json` or
  `.claude-plugin/marketplace.json` exists; exit `1` = entry/manifest name or version
  drift, `2` = no marketplace file (acceptable only while no catalog exists).

Verdict: `[PASS] Cross-file consistency: check-consistency 0 FAIL; verify-version-sync exit 0`

## Component discoverability

Every claimed component exists at its fixed Agent Plugins 1.0 location:

| Component | Location | Rule |
|-----------|----------|------|
| Skills | `skills/<name>/SKILL.md` | Every immediate `skills/` subdirectory has a `SKILL.md`; no claimed skill missing, no orphan directory |
| Commands | `com.github.copilot/commands/*.md` | At least one command file when `plugin.json` or the README claims commands |
| Agents | `com.github.copilot/agents/*.agent.md` | At least one agent file when claimed |
| Hooks | `com.github.copilot/hooks/hooks.json` | Parses as JSON; every referenced script exists under `scripts/` |
| MCP servers | `mcp.json` | Present at plugin root; every server defines `command` or `url` |

Evidence: the checker's component-path resolution (previous section) plus a directory
listing of each claimed path. No component directory may be empty, and nothing may be
claimed only in the README.

Verdict: `[PASS] Component discoverability: all claimed skills/commands/agents/hooks/mcp paths resolve`

## Frontmatter completeness

- Skills (every `skills/*/SKILL.md`): `name` (kebab-case, equals directory name),
  `description` (10–1024 chars, router-style), `metadata.version` (semver, required).
- Agents (every `com.github.copilot/agents/*.agent.md`): `name` (unique repo-wide) and
  `description` (drives intent matching), both present.
- Evidence: `python3 scripts/workspace/validate-manifests.py` (schema) and
  `pwsh -NoProfile -File scripts/workspace/check-consistency.ps1` (dir/name match,
  uniqueness) both exit `0`.

Verdict: `[PASS] Frontmatter completeness: skill and agent frontmatter green under schema and checker`

## README quality

Root `README.md` follows [plugin-readme-template.md](plugin-readme-template.md):

- Title plus one-paragraph pitch; `## Installation`, `## Quick start`,
  `## How it works`, `## Components`, `## License` all present.
- No unfilled `<placeholder>` slots remain (search `README.md` for `<plugin-name>`,
  `<marketplace-name>`, `<runtime>` — zero hits).
- Installation commands match reality: repo `arisng/github-copilot-fc`, the actual
  marketplace name, and the `name` from `plugin.json`; Components tables list exactly
  the files that exist.
- Evidence: `npx --yes markdownlint-cli2 README.md` exits `0`, plus the manual slot scan.

Verdict: `[PASS] README quality: template sections complete, no <placeholder> slots, markdownlint clean`

## Release readiness

1. Stable-channel bundle — `pwsh -NoProfile -File scripts/publish/build-plugins.ps1 -Channel stable -OutputRoot dist/plugins`
   exits `0`; self-contained bundle lands at `dist/plugins/<runtime>/<plugin-name>`
   (EMBED markers resolved, no `../..` escapes).
2. Marketplace entry — one of `marketplace.json` | `.plugin/marketplace.json` |
   `.github/plugin/marketplace.json` | `.claude-plugin/marketplace.json` carries an
   entry with `name` + `source` and a `version` matching `plugin.json` (version is
   required in practice for update detection). `source` points at the built `dist/`
   bundle, never the raw plugin directory. Evidence: verifier exit `0` (section 2).
3. Full gate — `pwsh -NoProfile -File scripts/workspace/workspace-check.ps1` exits `0`
   (12 checks).
4. E2E install smoke in a throwaway `COPILOT_HOME`:

```bash
SMOKE_HOME="$HOME/.copilot-smoke-<plugin-name>"
rm -rf "$SMOKE_HOME" && mkdir -p "$SMOKE_HOME"
COPILOT_HOME="$SMOKE_HOME" copilot plugin install dist/plugins/<runtime>/<plugin-name>
COPILOT_HOME="$SMOKE_HOME" copilot plugin list   # <plugin-name> listed, components load
rm -rf "$SMOKE_HOME"
```

Verdict: `[PASS] Release readiness: stable bundle, marketplace parity, workspace-check exit 0, smoke install green`

## Report format

One line per section, in section order:

```text
[PASS] Manifest validity: validate-manifests.py exit 0 — 62 artifact(s) green, 3 schemas valid
[FAIL] Release readiness: marketplace entry version 1.0.0 != plugin.json 1.1.0
```

Close with a prioritized fix list: every `[FAIL]` first (top-scoring ship blocker
first), then `[WARN]`-grade improvements — one bullet each naming the file to edit and
the exact command to re-run for fresh evidence.
