# Copilot FC Reference

This reference documents the JSON schema and expected fields in `copilot-fc.json` (default manifest filename). Files matching `copilot-*.json` are supported and you can set the `COPILOT_WORKSPACE_FILE` environment variable to point to an alternate filename.

## Top-level fields
- `name` (string) — Human-readable workspace name.
- `version` (string) — Semantic version of the workspace manifest (informational).
- `description` (string) — Short description of the workspace purpose.

## `workspace`
- `type` (string) — Should be `copilot-workspace` to identify this manifest format.
- `components` (array of strings) — Which top-level components the repo provides (common values: `prompts`, `agents`, `instructions`, `skills`). Scripts may rely on these values.

## `directories`
Maps logical components to folder paths relative to the repo root:
- `prompts`, `agents`, `instructions`, `skills`, `scripts`, `issues`

Scripts use these directory mappings to find content to publish or index.

## `commands`
A map of convenience commands (key → shell command). Use these to centralize task invocations. Example keys: `agents:publish`, `skills:update-apply`, `issues:reindex`.

## `vscode`
- `recommendedExtensions` (array) — Extensions VS Code will recommend to contributors.
- `settings` (object) — Workspace settings that editors may apply when the workspace is opened.

## `metadata`
- `created` (date string) — Manifest creation date.
- `author` (string) — Owner or author alias.
- `repository` (string) — Source repo URL.
- `documentation` (string) — Path to docs (e.g., `.docs/issues/`).

## Best practices
- Keep `commands` idempotent and safe to run locally.
- Use `directories` to avoid hard-coding paths in scripts.
- Document added commands in `.docs/how-to/` and update the index.

## Schema validation
No strict JSON schema is enforced by default in the repo; if you need strict validation, add a JSON Schema and a CI check that validates `copilot-*.json`.