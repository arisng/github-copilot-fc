# Activation Matrix — copilot-cli-subsession

Use this file to tune the `description` field only. Model classifier is harness-external — actual trigger values are manual inspection proxy. Marked `KNOWN-GAP` per handoff Step 1.

| ID | Prompt | Should Trigger | Actual Trigger | Failure Type | Notes |
|---|---|---|---|---|---|
| pos-01 | spawn a copilot sub-session to analyze the auth module | yes | yes | pass | Triggers: "spawn copilot", "copilot sub-session" |
| pos-02 | invoke copilot in a separate session with the deepseek model | yes | yes | pass | Triggers: "invoke copilot" |
| pos-03 | chain two copilot prompts on the same session | yes | yes | pass | Triggers: "chain copilot sessions" |
| pos-04 | run a slash command in an isolated copilot process | yes | yes | pass | Triggers: "isolated copilot" — maps to isolation flag guidance |
| pos-05 | resume a copilot cli session by id | yes | yes | pass | Triggers: "resume copilot session", "copilot cli session id" |
| pos-06 | run copilot with a custom agent in a subprocess | yes | yes | pass | Triggers: "subagent copilot cli" |
| pos-07 | hand off context to a sub-session by listing file paths | yes | yes | pass | Trigger: context handoff convention (absolute paths + working dir) |
| pos-08 | test a skill change without polluting my production copilot home | yes | yes | pass | Trigger: staging isolation via -CopilotHome ($HOME/.copilot-staging dojo) |
| pos-09 | programmatic copilot subprocess with JSON output | yes | yes | pass | Triggers: "programmatic copilot cli" + "programmatic copilot subprocess" (Step 3 add) |
| pos-10 | task copilot cli for security audit | yes | yes | pass | Triggers: "task copilot cli" |
| neg-01 | configure my BYOK provider profile | no | no | pass | Routes to: copilot-byok — BYOK config, not spawning |
| neg-02 | create a custom copilot agent file | no | no | pass | Routes to: copilot-cli-agent-customization — agent authoring |
| neg-03 | build a copilot CLI extension | no | no | pass | Routes to: copilot-cli-extension-builder |
| neg-04 | run dotnet test in a copilot session | no | no | pass | Routes to: default agent — generic task, not sub-session orchestration |
| neg-05 | publish my copilot skills to ~/.copilot | no | no | pass | Routes to: publishing workflow (publish-skills) |
| neg-06 | set up MCP servers for copilot | no | no | pass | Routes to: MCP configuration |
| neg-07 | run the byok profile script with flash model | no | no | pass | Routes to: copilot-byok — **overlap test** for removed trigger "copilot byok profile script" (pre-step fix verified) |
| neg-08 | create an agent.md for copilot cli | no | no | pass | Routes to: copilot-cli-agent-customization — agent file authoring boundary |
| neg-09 | deploy my app to vercel | no | no | pass | Routes to: deploy-to-vercel — unrelated |

## Failure type guide

- `false_negative`: the skill should trigger but does not
- `false_positive`: the skill should not trigger but does
- `pass`: behavior matches expectation

## KNOWN-GAP

Activation coverage is **harness-external**: `description` is matched by the model classifier, not regex. Manual inspection of trigger overlap is the best available proxy. Model-in-the-loop activation testing is out of scope. Scores from `Measure-ActivationAccuracy.ps1` reflect the `Actual Trigger` column filled manually above. Re-validate after each `description` change (Step 3).

## Validation (Step 3)

Current description removed `"copilot byok profile script"` (pre-step). Proposed adds: `"programmatic copilot subprocess"`, `"isolated copilot session"` — keep `"resume copilot session"`. Measure false positive on neg-07 before/after to confirm improvement.
