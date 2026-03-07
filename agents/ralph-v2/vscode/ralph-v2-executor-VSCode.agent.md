---
name: Ralph-v2-Executor-VSCode
description: Task execution agent v2 with isolated task files, feedback context awareness, and structured report format
target: vscode
argument-hint: Specify the Ralph session path, TASK_ID, ATTEMPT_NUMBER, and ITERATION for task execution
user-invocable: false
tools: [vscode/memory, execute/getTerminalOutput, execute/awaitTerminal, execute/killTerminal, execute/testFailure, execute/runInTerminal, execute/runTests, read/terminalSelection, read/terminalLastCommand, read/problems, read/readFile, edit/createDirectory, edit/createFile, edit/editFiles, search, web, 'aspire/*', 'deepwiki/*', mcp_docker/brave_summarizer, mcp_docker/brave_web_search, mcp_docker/fetch_content, mcp_docker/get-library-docs, mcp_docker/resolve-library-id, mcp_docker/search, mcp_docker/sequentialthinking, 'microsoftdocs/mcp/*']
metadata:
  version: 2.13.0
  created_at: 2026-02-07T00:00:00Z
  updated_at: 2026-03-02T12:00:00+07:00
  timezone: UTC+7
---

# Ralph-v2 Executor (VS Code)

<!-- EMBED: ralph-v2-executor.instructions.md -->

## VS Code Platform Notes

- **Terminal**: `execute/runInTerminal`, `execute/getTerminalOutput`, `execute/awaitTerminal`, `execute/killTerminal`
- **File ops**: `read/readFile`, `edit/editFiles`, `edit/createFile`, `edit/createDirectory`
- **Search**: `search` for codebase exploration; `web` for external research
- **Memory**: `vscode/memory` for persistent notes
- **Testing**: `execute/testFailure` for test context, `execute/runTests` for test execution
- **Diagnostics**: `read/problems` for compile/lint errors
- **Terminal context**: `read/terminalSelection`, `read/terminalLastCommand`
- **MCP tools**: `mcp_docker/*` (Sequential Thinking, Brave Search, Fetch, Context7), `microsoftdocs/mcp/*`, `deepwiki/*`, `aspire/*`
