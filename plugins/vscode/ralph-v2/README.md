# Ralph v2 for VS Code

Use this plugin when you want Ralph's planning, execution, review, and knowledge workflows available inside VS Code Copilot Chat.

## Use It

Publish the VS Code plugin bundle from this workspace:

```powershell
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Plugins ralph-v2
```

That flow builds the runtime bundle and registers its path in `chat.plugins.paths`.

## What You Get

- Runtime-specific Ralph v2 agents for VS Code.
- Bundled Ralph skills and hook assets alongside the manifest.
- Separate stable and beta bundle roots so verification does not trample the other channel.

## Practical Note

After republishing, reload Copilot Chat if VS Code is still holding the previous plugin state.