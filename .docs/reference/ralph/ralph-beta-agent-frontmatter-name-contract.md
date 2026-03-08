# Ralph beta agent frontmatter name contract

## Purpose

This reference defines how Ralph plugin bundles must express beta channel identity inside bundled agent YAML frontmatter.

## Contract

1. Source agent files may keep their original unsuffixed YAML frontmatter `name` values.
2. During bundle construction, beta channel builds must rewrite each bundled agent file so its YAML frontmatter `name` ends with `-beta` exactly once.
3. The rewrite applies generically to bundled agent artifacts in both CLI and VS Code Ralph bundles, not to a hard-coded agent list.
4. Stable channel builds must preserve the original unsuffixed YAML frontmatter `name` values for the equivalent bundled agent files.
5. The frontmatter rewrite happens in the beta bundle construction path and must not break instruction embedding, manifest generation, or post-bundle validation.
6. Post-bundle validation must check both channel-specific agent filenames and channel-specific YAML frontmatter `name` values.

## Stable vs beta rules

### Beta bundles

- Every bundled agent file under `agents/` must keep its `-beta.agent.md` filename.
- Every bundled agent YAML frontmatter `name` must end with `-beta`.
- The suffix must be applied exactly once.

### Stable bundles

- Bundled agent filenames under `agents/` must remain unsuffixed.
- Bundled agent YAML frontmatter `name` values must remain unsuffixed.

## Implementation points

- The bundle copy flow in `Build-PluginBundle` is the channel-identity rewrite boundary for bundled agents.
- The frontmatter rewrite must run only for beta bundle construction and must operate across all copied agent artifacts.
- `Test-AgentChannelContract` is the validation gate for both filename suffix rules and YAML frontmatter `name` suffix rules.

## Verified output shape

Iteration 3 verification confirmed the contract across both runtime bundles and both channels:

- Beta CLI bundle agents use `*-CLI-beta.agent.md` filenames and `name: Ralph-v2-*-CLI-beta` frontmatter values.
- Beta VS Code bundle agents use `*-VSCode-beta.agent.md` filenames and `name: Ralph-v2-*-VSCode-beta` frontmatter values.
- Stable CLI bundle agents use `*-CLI.agent.md` filenames and unsuffixed `name: Ralph-v2-*-CLI` frontmatter values.
- Stable VS Code bundle agents use `*-VSCode.agent.md` filenames and unsuffixed `name: Ralph-v2-*-VSCode` frontmatter values.

The same verification confirmed that instruction merging and bundle validation still completed successfully after the beta-only frontmatter rewrite.
