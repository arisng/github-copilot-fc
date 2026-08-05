---
name: publishPlugins
description: Build and install specified Copilot CLI plugins (build-plugins.ps1 + copilot plugins)
metadata:
  version: 2.0.0
  author: arisng
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user input should contain the plugin names to build/install, optionally with a channel flag.

## Instructions
Let's build and install the specified plugins. `publish-plugins.ps1` is deprecated — use `build-plugins.ps1` to build the local bundle and `copilot plugins` for management.

1. Parse the user input to extract plugin names. If multiple, separate by commas or spaces.
2. Optionally, check for a channel (beta/stable, default beta).
3. Build the bundle: `pwsh -NoProfile -File scripts/publish/build-plugins.ps1 -Plugins "<plugin_names>" -Channel "<channel>"`
4. Install the built bundle with the native CLI: `copilot plugins install <plugin_path>` (CLI bundles land under `plugins/cli/.build/<name>/`; VS Code bundles under `plugins/vscode/.build/<name>/` — register the latter in `chat.plugins.paths`).
5. Verify with `copilot plugins list` and report the results, including any warnings or errors.

## Context

$ARGUMENTS