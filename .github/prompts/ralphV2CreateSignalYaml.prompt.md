---
name: ralphV2CreateSignalYaml
description: Generate a timestamped Ralph v2 `signals/inputs/` YAML file for live steering.
argument-hint: sessionId, message (hot-steering text), optional: type (STEER|PAUSE|STOP|INFO), optional: target (ALL | Ralph-v2 | Ralph-v2-Executor | Ralph-v2-Planner | Ralph-v2-Questioner | Ralph-v2-Reviewer | Ralph-v2-Librarian)
---
Given the following inputs:
- `sessionId`: the Ralph session identifier
- `message`: the hot-steering or informational text to inject
- optional `type`: one of `STEER`, `PAUSE`, `STOP`, or `INFO` (default: `STEER`)
- optional `target`: `ALL` or a specific subagent name (default: `ALL`). Accept and normalize these canonical targets (case-insensitive): `Ralph-v2` (orchestrator), `Ralph-v2-Executor`, `Ralph-v2-Planner`, `Ralph-v2-Questioner`, `Ralph-v2-Reviewer`, `Ralph-v2-Librarian`.

Create a ready-to-write, timestamped signal file for the session mailbox.

Requirements:
1. Produce a filename in this exact format: `signal.<YYMMDD-HHMMSSZ>.yaml` (use UTC time).
2. Show the full relative path where the file should be created: `.ralph-sessions/<SESSION_ID>/signals/inputs/<FILENAME>`.
3. The YAML file written to disk MUST match the following schema (do NOT output the YAML to the user):
   type: <TYPE>
   target: <TARGET>
   message: "<MESSAGE>"
   created_at: <ISO-8601-local-timestamp-with-offset>

Timestamps and SESSION_ID (local-time rules):
- Use local system time for `SESSION_ID` and metadata timestamps (the environment's local timezone — your system is UTC+7). Do **not** convert these fields to UTC.
- `SESSION_ID` format: `<YYMMDD>-<hhmmss>`.
  - Windows (PowerShell): `Get-Date -Format "yyMMdd-HHmmss"`
  - Linux/WSL (bash): `TZ=Asia/Ho_Chi_Minh date +"%y%m%d-%H%M%S"`
- `created_at` must be an ISO8601 local timestamp that includes the timezone offset (for example `2026-02-14T15:04:05+07:00`).
  - Windows (PowerShell): `Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"`
  - Linux/WSL (bash): `TZ=Asia/Ho_Chi_Minh date +"%Y-%m-%dT%H:%M:%S%z"`

Compatibility notes:
- Ensure the prompt is compatible with both Windows PowerShell and WSL/Linux bash. When the agent generates or validates `sessionId` or `created_at`, prefer the platform-specific commands above. If the runtime environment is unknown, assume local system time and format values accordingly.
- Note: Requirement 1 (signal filename `signal.<YYMMDD-HHMMSSZ>.yaml`) remains UTC (`Z`) unless the user explicitly requests otherwise.

Defaults and validation:
- If `type` is omitted or invalid, use `STEER`.
- If `target` is omitted, use `ALL`.
- If `target` is ambiguous, normalize common aliases (case-insensitive): `orchestrator` -> `Ralph-v2`, `executor` -> `Ralph-v2-Executor`, `planner` -> `Ralph-v2-Planner`, `questioner` -> `Ralph-v2-Questioner`, `reviewer` -> `Ralph-v2-Reviewer`, `librarian` -> `Ralph-v2-Librarian`; if still ambiguous, default to `ALL`.
- Ensure `message` is present and trimmed; if empty, respond with an error line indicating the missing argument.

When the assistant or agent has file-system write access, it MUST create the signal file at the computed relative path (`.ralph-sessions/{sessionId}/signals/inputs/{filename}`) and write the YAML exactly as shown. The file write MUST:
- create parent directories if they do not exist
- write using UTF8 encoding (no BOM)
- preserve the YAML content exactly (no added/removed leading or trailing blank lines)
- perform an atomic write by writing to a temporary file in the same directory then renaming to the final filename (e.g., Move-Item -Force)

After creating the file, the assistant's response MUST be a single line containing only the relative path to the created file (for example: `.ralph-sessions/<SESSION_ID>/signals/inputs/<FILENAME>`). Do not output the YAML contents, PowerShell commands, explanations, or any other text.

If the assistant does NOT have permission to write to the workspace, the assistant MUST NOT output the YAML or a PowerShell command; instead it MUST return only the single line with the relative path where the file would be created. Do not output any other content.

Placeholders to replace in your output: `{sessionId}`, `{filename}`, `{path}` — the model must substitute these with actual values; do not output literal placeholders. Do not include any other commentary.

Example fallback command pattern (DON'T output this pattern when acting; this is only for authoring the prompt):

$path = '.ralph-sessions/{sessionId}/signals/inputs/{filename}'; $dir = Split-Path $path; New-Item -ItemType Directory -Force -Path $dir | Out-Null; $tmp = "$path.tmp"; @'
<YAML CONTENT>
'@ | Set-Content -Path $tmp -Encoding UTF8; Move-Item -Force -Path $tmp -Destination $path

Placeholders to replace in your output: `{sessionId}`, `{filename}`, `{path}` — the model must substitute these with actual values; do not output literal placeholders. Do not include any other commentary.
