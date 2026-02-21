---
name: publishSkills
description: Publish specified skills to personal Copilot folders.
argument-hint: Skill names to publish (comma-separated if multiple)
model: Raptor mini (Preview) (copilot)
metadata:
  version: 1.0.1
  author: arisng
---
Publish the specified skills from the workspace to personal Copilot folders (.claude, .codex, .copilot) on Windows and WSL.

Run the PowerShell script `scripts/publish/publish-skills.ps1` with the `-Force` parameter and the `-Skills` parameter set to the provided skill names.

Example: If skills are "skill1,skill2", run:
powershell -ExecutionPolicy Bypass -File "scripts/publish/publish-skills.ps1" -Force -Skills "skill1","skill2"