# Planner Questioner Grounding Handshake

## Canonical Fields

- `grounding_request_source`
- `question_artifact_path`
- `progress_entry_updated`
- `grounding_ready`
- `planner_resume_mode`

## Rule

Ordinary PLANNING delegation from Planner to Questioner must use one shared completion-marker vocabulary across the planning spec, discovery spec, Planner instructions, and Questioner instructions.

## Compatibility Note

If legacy payloads still send `resume_mode`, Questioner may normalize that input to `planner_resume_mode`, but new Planner outputs should emit `planner_resume_mode` only.

## Operational Implication

If the Planner or Questioner handshake drifts, fix the shared contract across both roles and the owning specs instead of patching a single instruction file in isolation.