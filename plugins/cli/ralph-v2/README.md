# Ralph v2 for Copilot CLI

Install the bundle, then invoke Ralph from the Copilot CLI when you want structured multi-agent delivery instead of one-off prompting.

## Use It

Build or publish from this workspace:

```powershell
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Plugins ralph-v2
```

Or install the source plugin directly with the official CLI flow:

```bash
copilot plugin install ./plugins/cli/ralph-v2
```

## What You Get

- Ralph v2 orchestration agents for planning, execution, review, and knowledge capture.
- Bundled Ralph workflow skills and hook support assets.
- A beta-safe workspace publish flow that keeps stable and beta bundles separate.

## Practical Note

If you edit plugin contents, reinstall or republish. The CLI caches plugin files.