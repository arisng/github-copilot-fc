# Ralph beta agent filename contract

## Purpose

This reference defines how Ralph plugin bundles must express beta channel identity for bundled agent files.

## Contract

1. Source plugin manifests may keep their agent entries unsuffixed.
2. During bundle construction, beta channel builds must rename copied agent markdown files from `*.agent.md` to `*-beta.agent.md`.
3. The renaming happens only for non-directory items in the `agents` component field.
4. The cleaned bundle manifest must record the renamed local `agents/...-beta.agent.md` paths before `plugin.json` is written.
5. Instruction embedding runs against the already-renamed bundled agent files, not the original source filenames.
6. Post-bundle validation must check both the manifest agent entries and the copied files on disk.

## Stable vs beta rules

### Beta bundles

- Every manifest agent entry must end with `-beta.agent.md`.
- Every copied agent file under `agents/` must end with `-beta.agent.md`.

### Stable bundles

- Manifest agent entries must not end with `-beta.agent.md`.
- Copied agent files under `agents/` must not end with `-beta.agent.md`.

## Implementation points

- `Get-BundledComponentItemName` is the rename gate. It applies the suffix only when `Field = agents`, the item is a file, the channel is `beta`, and the name already ends with `.agent.md`.
- The component copy loop must call that rename helper before it appends local paths into the cleaned manifest.
- `Test-AgentChannelContract` is the validation gate. It rejects mismatches in both manifest entries and copied bundle files.

## Verified output shape

Iteration 2 verification confirmed the contract for both runtime bundles:

- Beta CLI bundle agents: `agents/ralph-v2-*-CLI-beta.agent.md`
- Beta VS Code bundle agents: `agents/ralph-v2-*-VSCode-beta.agent.md`
- Stable CLI bundle agents: `agents/ralph-v2-*-CLI.agent.md`
- Stable VS Code bundle agents: `agents/ralph-v2-*-VSCode.agent.md`

The same verification also confirmed that instruction embedding still completed with zero remaining `<!-- EMBED:` markers after the rename step.
