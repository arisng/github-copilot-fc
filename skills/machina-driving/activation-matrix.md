# Activation Matrix

Use this file to tune the `description` field only.

| ID | Prompt | Should Trigger | Actual Trigger | Failure Type | Notes |
|---|---|---|---|---|---|
| pos-01 | Drive the docs-authoring Machina machine to its terminal state and give me the report. | yes | yes | pass | Explicit drive + report |
| pos-02 | A skill's SKILL.md declares a `machina:` machine — run it and drive to completion. | yes | yes | pass | Discovery via machina: frontmatter |
| pos-03 | Init the run, check status, fire DRAFT_REVIEWED when evidence passes, then report. | yes | yes | pass | Command-surface workflow |
| pos-04 | Execute this workflow deterministically and audibly, satisfying the state machine's evidence checks. | yes | yes | pass | Deterministic workflow + evidence |
| pos-05 | The run is STUCK with zero enabled events — escalate to the human conductor. | yes | yes | pass | STUCK escalation |
| pos-06 | Produce the machina.report.v1 summary grounded to report facts. | yes | yes | pass | Report grounding |
| neg-01 | Author a new Machina machine definition JSON for a docs review workflow. | no | no | pass | Neighbor: machina-authoring |
| neg-02 | Score the compliance and coverage of this machine definition. | no | no | pass | Neighbor: machina-authoring scoring |
| neg-03 | Update the Machina simulator app UI to show phase states. | no | no | pass | Neighbor: machina-simulator |
| neg-04 | Draw an XState diagram of the workflow states. | no | no | pass | Neighbor: XState/diagramming |
| neg-05 | Explain what a state machine is in computing. | no | no | pass | General concept, not driving |
| neg-06 | Refactor scripts/machine-driver.py to add a retry subcommand. | no | no | pass | Explicitly excluded: driver/runtime tooling development |

## Failure type guide

- `false_negative`: the skill should trigger but does not
- `false_positive`: the skill should not trigger but does
- `pass`: behavior matches expectation