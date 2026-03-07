---
name: publishPlugins
description: Publish specified Copilot CLI plugins using the publish-plugins.ps1 script
metadata:
  version: 1.0.0
  author: arisng
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user input should contain the plugin names to publish, optionally with environment and force flags.

## Instructions
Let's publish the specified plugins using the publish-plugins.ps1 script.

1. Parse the user input to extract plugin names. If multiple, separate by commas or spaces.
2. Optionally, check for environment (windows/wsl/all, default all) and force flag.
3. Run the script: `pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Plugins "<plugin_names>" -Environment "<env>" -Force:$force`
4. Report the results, including any warnings or errors.

## Context

$ARGUMENTS