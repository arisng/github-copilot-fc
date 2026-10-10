# Step Classification Taxonomy

Every `tool.execution_start` in the episode window is classified into exactly one bucket.
The taxonomy is deliberately three-bucket **plus an explicit `uncertain` bucket**: an
honest unknown beats a wrong score. Extend the tables here when `uncertain` counts are
high — the report surfaces sample uncertain tool names to prompt exactly this.

## Buckets

| Bucket | Scored toward goal 3/4? | Meaning |
|--------|------------------------|---------|
| `semantic` | Yes — semantic step | Model-authored judgment: content creation, code authoring at runtime, nested agent dispatch |
| `deterministic` | Yes — deterministic step | Execution of **pre-authored** tooling: repo scripts, builds, tests, publish pipelines, read-only structured queries |
| `query_read` | Reported separately (counts toward decision points) | Read-only information gathering — deterministic execution, but each call is still a model decision point |
| `workflow_control` | Reported separately, not scored | Session workflow mechanics: human interaction, plan gating, completion signals, hooks |
| `uncertain` | Reported separately; reduces both scored counts | Anything unmatched — surfaced with sample names in the report |

## Classification rules (applied in order)

1. **Normalize** the tool name: trim, lowercase, then apply the alias map:
   - `sql` → `session_store_sql` (legacy alias observed in older sessions)
   - `read` → `view`
   - Case drift (`powerShell` vs `powershell`) is absorbed by lowercasing
2. **workflow_control**: `ask_user`, `exit_plan_mode`, `task_complete`, `rename_chat`,
   `addComment`, `replyToComment`, `resolveComments`, `deleteComments`, `viewUnreviewedComments`
3. **semantic**: `edit`, `create`, `skill` (skill load is a reasoning step), `task`
   (nested subagent — its own usage is broken out separately), `open_canvas`,
   `runplaywrightcode` (model-authored code executed at runtime — semantic by authorship)
4. **query_read**: `grep`, `glob`, `view`, `read`, `web_fetch`, `lsp`, `list_sessions`,
   `get_current_session`, `get_session_context`, `session_store_sql`, `read_powershell`,
   `list_powershell`, `stop_powershell`; plus tool-name prefixes `github-mcp-server-`,
   `mcp-docker-brave_`, `mcp-docker-get_`, `mcp-docker-code-mode`
5. **deterministic (shell provenance rule)**: for shell tools (`powershell`, `bash`,
   `shell`, `terminal`), the command must match a provenance pattern showing it executes
   pre-authored code:
   - contains `*.ps1` or invokes `pwsh`
   - `npm run|test|npx`, `dotnet build|test|run|publish|pack`, `pytest`,
     `python … .py`, `py -3 … .py`, `git commit|push|merge|rebase`,
     `copilot plugin|plugins`, `npx skills`
6. **uncertain**: everything else — notably **ad-hoc inline shell**
   (e.g. `Get-ChildItem …`). This is intentional: the user's goal is to maximize steps
   executed *via scripts or codebase-related implementation*, so exploratory one-off
   shell commands must not be scored as deterministic.

## Why not a binary semantic/deterministic split?

An audit of real sessions showed a binary model is gameable: a model that runs
`grep` 50 times accrues 50 "deterministic" steps while burning 50 decision points.
Mitigations baked into the metrics:

- `query_read` is counted toward **decision points** (`semantic + query_read`) so
  read-spam is visible
- `workflow_control` (e.g. long `ask_user` waits) never pollutes wall-clock-free
  efficiency scores (wait time is subtracted from active time)
- `uncertain` is always reported, never silently folded into either scored bucket

## Maintenance

- When a new CLI version renames tools, add an alias (rule 1) or extend a bucket list —
  do not change the engine
- Record the CLI version (`session.start.data.copilotVersion`) with each report so
  taxonomy drift can be correlated with upgrades
