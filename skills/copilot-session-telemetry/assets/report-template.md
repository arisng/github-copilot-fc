# Real-Session Efficiency Audit — {{SKILL_NAME}}

- Session: `{{SESSION_DIR}}`
- Mode: {{MODE}}
- {{WINDOW_LINE}}
- Generated: {{GENERATED_AT}}
- CLI version: {{CLI_VERSION}} · Models: {{MODELS}}

> An **episode** is one execution run of the skill — a time-window *slice* of the
> session's `events.jsonl` transcript, from the skill's invocation to the next
> external skill invocation (or session end). One session can contain many
> episodes; `--mode session` measures everything in the session before this
> audit's own activation instead.

## Caveats

{{CAVEATS}}

## Goal scorecard

{{SCORECARD_HEADER}}
{{SCORECARD_ROWS}}

## Tokens

{{TOKENS_TABLE}}

## Time

{{TIME_TABLE}}

## Steps

Classification per `references/classification.md` (semantic / deterministic / query-read / workflow-control / uncertain).

{{STEPS_TABLE}}

## Efficiency ratios

{{RATIOS_TABLE}}

## Boundaries & merged skill loads

Skill loads that were merged into this episode instead of terminating it (skill-chain matches and subagent-internal loads), each with its own sub-window totals.

{{BOUNDARIES}}

## Per-episode breakdown

Mechanical per-skill windows for this session (secondary detail; primary attribution is the episode/session scorecard above).

{{EPISODE_BREAKDOWN}}

## Notes

{{NOTES}}
