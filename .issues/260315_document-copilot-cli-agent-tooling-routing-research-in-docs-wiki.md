---
date: 2026-03-15
type: Task
severity: Medium
status: Draft
---

# Task: Document Copilot CLI agent tooling & routing research in .docs wiki

## Objective
There are two detailed research notes in the Copilot session-state folder that capture important findings about:

- Copilot CLI custom agent tool inventories (built-in tools, alias mapping, MCP namespaces)
- Agent routing / subagent invocation patterns (disable-model-invocation vs user-invocable, runtime alias resolution, model pinning)

These findings should be formalized into the workspace wiki under `.docs` (for example, as reference docs under `.docs/reference/copilot/` or a similar logical location).

## Tasks
- [ ] Review the research notes in the session-state folder and extract the key findings.
- [ ] Create one or more `.docs` pages that capture: tool inventory conventions, tool default behavior, alias mapping, and routing/agent invocation patterns.
- [ ] Ensure the new docs are discoverable (update `.docs` index/TOC files as needed).
- [ ] Link back to or archive the original session-state research files so the source research is not lost.

## Acceptance Criteria
- [ ] New `.docs` reference pages exist and contain the key findings with actionable guidance.
- [ ] New pages are listed in the workspace `.docs` index or TOC.
- [ ] There is a clear trace from the issue to the original research files (links or notes).

## References
- `C:\Users\ADMIN\.copilot\session-state\0cc9efac-387a-4524-8743-f9e801f79553\research\what-are-built-in-tools-of-copilot-cli-agents-i-wa.md`
- `C:\Users\ADMIN\.copilot\session-state\0cc9efac-387a-4524-8743-f9e801f79553\research\follow-up-the-research-what-are-built-in-tools-of-.md`