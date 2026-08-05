---
name: publishSkills
description: Publish specified skills (or all skills if none specified) to personal Copilot folders.
argument-hint: Skill names to publish (comma-separated if multiple), or leave blank for all skills
agent: agent
metadata:
  version: 2.0.0
  author: arisng
---
Publish the specified skills from the workspace to personal Copilot folders. `publish-skills.ps1` is deprecated — use the **Skills CLI** (`npx skills <options>`) instead.

If the skills come from a published repository, install them with the Skills CLI:

```bash
npx skills add <owner>/<repo> -s "skill1,skill2" -g -y
```

If the skills are local workspace folders (under `skills/`), either copy them into `~/.copilot/skills/` with `Copy-Item` or use `copilot skill add <directory>` for CLI discovery:

```powershell
Copy-Item -Recurse "$PWD\skills\skill1" "$HOME\.copilot\skills\skill1"
```

Legacy fallback (deprecated, workspace-to-personal copy only):

```powershell
pwsh -NoProfile -File scripts/publish/publish-skills.ps1 -Force -Skills "skill1","skill2"
```