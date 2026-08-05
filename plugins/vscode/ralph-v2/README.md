# Ralph v2 for VS Code

Use this plugin when you want Ralph's planning, execution, review, and knowledge workflows available inside VS Code Copilot Chat.

## Use It

Build the VS Code plugin bundle from this workspace:

```powershell
# Build the local bundle (preferred; publish-plugins.ps1 is deprecated)
pwsh -NoProfile -File scripts/publish/build-plugins.ps1 -Plugins ralph-v2
```

That places the VS Code bundle under `plugins/vscode/.build/ralph-v2/`. To make VS Code load it, register that bundle path in the `chat.plugins.paths` setting (the legacy `publish-plugins.ps1 -Runtime vscode` did this automatically, but it is deprecated).

## What You Get

- Runtime-specific Ralph v2 agents for VS Code.
- Bundled Ralph skills and hook assets alongside the manifest.
- Separate stable and beta bundle roots so verification does not trample the other channel.

## Practical Note

After republishing, reload Copilot Chat if VS Code is still holding the previous plugin state.