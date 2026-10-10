# Event Schema Reference

Ground truth for parsing a Copilot session's `events.jsonl` (the primary data source).
Verified empirically against CLI 1.0.95 session dirs; cross-check against
`.docs/reference/copilot/cli/copilot-cli-session-state-schema.md` (note: its
`tool.execution_complete` field list is outdated — the live shape is documented below).

Each line is one JSON object with at least: `type`, `id`, `timestamp` (ISO-8601 UTC, `Z`
suffix), `parentId`, and `data`. Only `data`-level fields listed here matter.

## Event types used by the metrics engine

| Type | Key data fields | Use |
|------|-----------------|-----|
| `session.start` | `copilotVersion` (may be absent in older sessions) | Record CLI version in the report |
| `skill.invoked` | `name`, `path`, `trigger` (may be absent), `invokedAtTurn` (**undefined in older sessions**) | Episode boundaries: start = target skill invocation; end = next `skill.invoked` of any skill, else last event |
| `session.usage_record` | `usage.model`, `usage.inputTokens`, `usage.outputTokens`, `usage.cacheReadTokens`, `usage.cacheWriteTokens`, `usage.reasoningTokens`, `usage.cost` (0 for BYOK), `usage.duration` (ms), `usage.initiator` (`user` / `sub-agent`), `usage.agentId` (sub-agent only), `usage.apiCallId` | Token and LLM-time metrics; sub-agent breakout |
| `tool.execution_start` | `toolCallId`, `toolName`, `arguments` (object), `turnId`, `model` | Step classification + timing start |
| `tool.execution_complete` | `toolCallId`, `success`, `error`, `toolTelemetry` (**no `toolName`, no duration field**) | Timing end: duration = timestamp delta from matching start |
| `assistant.message` | `messageId`, `model`, `toolRequests[]` (`toolCallId`, `name`, `arguments`, `intentionSummary`) | Optional enrichment; step counting uses `tool.execution_start` instead |

## Other event types (ignored by the engine)

- `hook.start` / `hook.end` — hook executions are separate from tool steps; they are NOT counted (avoids double-counting)
- `session.resume` / `session.shutdown` — one events file may span resumes; the engine handles this naturally because the episode is a timestamp window, not a turn range
- `user.message`, `assistant.thought`, `skill.proposed`, etc. — not needed for the four goal families

## Parsing rules

1. Skip blank and unparseable lines; count them and surface in the report (`bad_event_lines`).
2. Compare timestamps as timezone-aware datetimes (`datetime.fromisoformat` handles the `Z` suffix on Python ≥3.11).
3. Pair tool start/complete by `toolCallId`; unpaired starts get duration 0 (reported as such, not dropped).
4. `invokedAtTurn` is unreliable — never use turn indices for episode boundaries; use timestamp windows.
5. Usage attribution is per LLM call, not per skill — the episode window is the only reliable slicing mechanism.
