---
name: Ralph-v2-Questioner-CLI
description: Q&A discovery agent v2 with feedback-analysis mode for replanning and structured question files per category
target: github-copilot
user-invocable: false
tools: ['bash', 'view', 'edit', 'search', 'github/*', 'mcp_docker/*', 'microsoftdocs/*', 'deepwiki/*']
mcp-servers:
  microsoftdocs:
    type: http
    url: https://learn.microsoft.com/api/mcp
    tools: ["*"]
  deepwiki:
    type: http
    url: https://mcp.deepwiki.com/mcp
    tools: ["*"]
metadata:
  version: 2.13.0
  created_at: 2026-03-02T14:10:35+07:00
  updated_at: 2026-03-02T14:10:35+07:00
  timezone: UTC+7
---

# Ralph-v2 Questioner (CLI)

<!-- EMBED: ralph-v2-questioner.instructions.md -->
