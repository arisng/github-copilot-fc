---
category: reference
---

# Copilot Hook Discovery and Publishing Model

Reference for hook discovery locations, path-resolution semantics, and published-hook layout across VS Code and GitHub Copilot CLI.

## Terminology

| Term            | Meaning                                                                                                                                  |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Repo-scoped     | Hook manifests discovered from the active repository, typically under `.github/hooks/`. This is the primary term used in this workspace. |
| Workspace-level | Compatibility synonym for repo-scoped when the runtime context is a VS Code workspace.                                                   |
| User-level      | Hook manifests stored under `~/.copilot/hooks/` and shared across local workspaces on one machine.                                       |
| Plugin-based    | Hooks bundled in a Copilot plugin and loaded through plugin installation rather than repo scanning.                                  |

## Discovery locations by runtime

| Runtime            | Discovery scope         | Default discovery locations                                   | Alternate locations                                                               | Notes                                                                                                          |
| ------------------ | ----------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| VS Code            | Repo-scoped             | `.github/hooks/*.hooks.json`                                  | Paths or files listed in `chat.hookFilesLocations`, including `~/.copilot/hooks/` | `~/.copilot/hooks/` is not a default VS Code hook search path.                                                 |
| GitHub Copilot CLI | Repo-scoped / CWD-based | `.github/hooks/*.hooks.json` in the active repository context | Installed plugin bundles that declare `hooks` in `plugin.json`                    | CLI discovery follows the current working directory and repository context.                                    |
| GitHub Copilot CLI | Plugin-based            | Installed plugin hook bundle                                  | N/A                                                                               | Plugin hooks are loaded through the plugin system, not by scanning `.github/hooks/` in the current repository. |

## Path-resolution semantics

| Context                                           | Resolution rule                                                                                                                                       |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hook `cwd` property                               | Interpreted relative to the repository root, not relative to the hook manifest file.                                                                  |
| Relative script paths in repo-scoped hooks        | Resolve within the active repository context, optionally rebased by `cwd`.                                                                            |
| Relative script paths in user-level VS Code hooks | Still resolve from the repository context; moving a manifest to `~/.copilot/hooks/` does not make `./scripts/...` relative to that user-level folder. |
| Copilot CLI repo-scoped discovery                 | Depends on the current working directory. Running `copilot` from the repository root is the stable repo-scoped case.                                  |
| Full paths in published user-level manifests      | Decouple hook execution from the active repository layout and allow one manifest to be reused across workspaces on the same machine.                  |

## Published-hook layouts

### Repo-scoped layout

| Element                             | Location                                                                                                  |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Hook manifests                      | `.github/hooks/*.hooks.json`                                                                              |
| Hook scripts                        | Repository paths referenced by the manifest, commonly `hooks/<name>/scripts/` or `.github/hooks/scripts/` |
| Command paths in published manifest | Preserved as repo-relative paths                                                                          |

### User-level layout

| Element                             | Location                                                                                                |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Hook manifests                      | `~/.copilot/hooks/<file>.hooks.json`                                                                    |
| Hook scripts                        | `~/.copilot/hooks/<hook-name>/scripts/...` when the source script comes from a hook-owned script folder |
| Command paths in published manifest | Rewritten to full user-level paths                                                                      |

## User-level publish contract

The workspace user-level publish flow uses the following contract:

| Contract element     | Behavior                                                                                                                                                                      |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Manifest placement   | Published manifests are copied as flat files into the destination root, preserving filenames such as `~/.copilot/hooks/ralph-tool-logger.hooks.json`.                         |
| Script placement     | Referenced scripts are copied below the same destination root, preserving hook-relative structure such as `~/.copilot/hooks/ralph-tool-logger/scripts/ralph-tool-logger.ps1`. |
| Command rewrite      | Published `bash`, `powershell`, `command`, `windows`, `linux`, and `osx` command values are rewritten from repo-relative script references to full user-level paths.          |
| Settings integration | VS Code user-level publishing updates `chat.hookFilesLocations` so both `.github/hooks` and `~/.copilot/hooks/` remain discoverable.                                          |
| WSL mirror           | When WSL is available, the same user-level hook tree is mirrored into the WSL home directory.                                                                                 |

## Decision matrix

| Approach                               | Primary runtime fit     | Discovery model                          | Path model                                         | Scope                                          | Best fit                                                                          |
| -------------------------------------- | ----------------------- | ---------------------------------------- | -------------------------------------------------- | ---------------------------------------------- | --------------------------------------------------------------------------------- |
| Repo-scoped `.github/hooks/`           | VS Code and Copilot CLI | Default                                  | Repo-relative paths work as-authored               | One repository                                 | Project-specific hooks, shared team automation, and the default CLI/VS Code model |
| VS Code user-level `~/.copilot/hooks/` | VS Code                 | Opt-in through `chat.hookFilesLocations` | Published manifests must use full user-level paths | All local VS Code workspaces on one machine    | Personal cross-workspace hooks in VS Code                                         |
| CLI plugin-based hooks                 | Copilot CLI             | Plugin installation                      | Plugin-managed package paths                       | All CLI sessions where the plugin is installed | Reusable CLI hook distribution that is not tied to one repository                 |

## Compatibility notes

| Topic                              | Reference fact                                                                                                                                                |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Preferred term in this workspace   | Use **repo-scoped** as the primary term. Use **workspace-level** only when aligning with older Ralph documentation.                                           |
| Bare CLI `~/.copilot/hooks/` usage | This workspace can publish user-level hook files for VS Code discovery, but the stable CLI models remain repo-scoped `.github/hooks/` and plugin-based hooks. |
| Authoring vs deployment            | `hooks/` is the authoring source tree. `.github/hooks/` and `~/.copilot/hooks/` are deployment targets.                                                       |

## Related documents

- [Workspace-Level Hook Deployment Model](../ralph/workspace-level-hook-deployment-model.md)
- [How to Publish Hooks](../../how-to/ralph/how-to-publish-hooks.md)
- [How to Publish Copilot Customizations for Copilot CLI](../../how-to/copilot/how-to-publish-customizations-for-copilot-cli.md)
- [Runtime Support Framework](runtime-support-framework.md)
- [Copilot-CLI Customization Support Matrix](copilot-cli-customization-matrix.md)
