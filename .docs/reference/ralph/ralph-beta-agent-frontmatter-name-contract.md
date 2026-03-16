# Ralph beta agent frontmatter name contract

## Purpose

This reference defines how Ralph plugin bundles must express beta channel identity inside bundled agent YAML frontmatter, including both the agent `name` field and any VS Code-only `agents` references that point at bundled Ralph subagents.

## Contract

1. Source agent files may keep their original unsuffixed YAML frontmatter `name` values and, for VS Code orchestrators, their original unsuffixed `agents` references.
2. During bundle construction, beta channel builds must rewrite each bundled agent file so its YAML frontmatter `name` ends with `-beta` exactly once.
3. During that same beta-only bundling step, any bundled VS Code `agents` references that target Ralph subagents must also be rewritten to the matching `-beta` names exactly once.
4. The rewrite applies generically to bundled agent artifacts, not to a hard-coded agent list. The `agents`-reference rewrite is VS Code-only because CLI agents do not use that frontmatter key.
5. Stable channel builds must preserve the original unsuffixed YAML frontmatter `name` values and unsuffixed VS Code `agents` references for the equivalent bundled agent files.
6. The frontmatter rewrite happens in the beta bundle construction path and must not break instruction embedding, manifest generation, or post-bundle validation.
7. Post-bundle validation must check channel-specific agent filenames, channel-specific YAML frontmatter `name` values, and VS Code bundled `agents` references when present.

## Stable vs beta rules

### Beta bundles

- Every bundled agent file under `agents/` must keep its `-beta.agent.md` filename.
- Every bundled agent YAML frontmatter `name` must end with `-beta`.
- Every bundled VS Code `agents` reference must point to the corresponding `-beta` Ralph subagent name.
- The suffix must be applied exactly once.

### Stable bundles

- Bundled agent filenames under `agents/` must remain unsuffixed.
- Bundled agent YAML frontmatter `name` values must remain unsuffixed.
- Bundled VS Code `agents` references must remain unsuffixed.

## Implementation points

- The bundle copy flow in `Build-PluginBundle` is the channel-identity rewrite boundary for bundled agents.
- The frontmatter rewrite must run only for beta bundle construction and must operate across all copied agent artifacts.
- For VS Code bundles, the same beta rewrite boundary must update both bundled agent `name` values and bundled `agents` references so they stay aligned.
- `Test-AgentChannelContract` (plus the same post-bundle validation pass for VS Code `agents` references) is the validation gate for filename suffix rules and bundled frontmatter identity rules.

## Verified output shape

Iteration 3 verification confirmed the contract across both runtime bundles and both channels:

- Beta CLI bundle agents use `*-CLI-beta.agent.md` filenames and `name: Ralph-v2-*-CLI-beta` frontmatter values.
- Beta VS Code bundle agents use `*-VSCode-beta.agent.md` filenames, `name: Ralph-v2-*-VSCode-beta` frontmatter values, and beta-suffixed `agents:` references such as `Ralph-v2-Planner-VSCode-beta`.
- Stable CLI bundle agents use `*-CLI.agent.md` filenames and unsuffixed `name: Ralph-v2-*-CLI` frontmatter values.
- Stable VS Code bundle agents use `*-VSCode.agent.md` filenames, unsuffixed `name: Ralph-v2-*-VSCode` frontmatter values, and unsuffixed `agents:` references such as `Ralph-v2-Planner-VSCode`.

The same verification confirmed that instruction merging and bundle validation still completed successfully after the beta-only frontmatter rewrite for both `name` values and VS Code `agents` references.
