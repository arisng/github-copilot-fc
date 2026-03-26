---
name: publishSkills
description: Publish specified skills (or all skills if none specified) to personal Copilot folders.
argument-hint: Skill names to publish (comma-separated if multiple), or leave blank for all skills
agent: agent
metadata:
  version: 1.0.1
  author: arisng
---
Publish the specified skills from the workspace to personal Copilot folders (.claude, .codex, .copilot) on Windows and WSL. If no skills are specified, publish all skills.

Run the PowerShell script `scripts/publish/publish-skills.ps1` with the `-Force` parameter (default) and the `-Skills` parameter set to the provided skill names (or nothing to publish all skills).

Example: If skills are "skill1,skill2", run:
powershell -ExecutionPolicy Bypass -File "scripts/publish/publish-skills.ps1" -Force -Skills "skill1","skill2"