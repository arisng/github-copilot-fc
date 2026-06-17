# Task

Use this template for discrete work items or projects that need tracking. Include clear objectives, acceptance criteria, and references to related design docs or issues.

## Template

```markdown
---
date: YYYY-MM-DD
type: Task
severity: Critical | High | Medium | Low | N/A
status: Draft | Proposed | In Progress | Accepted
---

# Task: [Task Name]

## Objective
[What needs to be done?]

## Tasks
- [ ] Step 1
- [ ] Step 2

## Acceptance Criteria
- [ ] Criteria 1
- [ ] Criteria 2

## References
- [Link to code or docs]
```

## Field Descriptions

- **date**: ISO 8601 date when the task was created
- **type**: Always "Task" for this template
- **severity**: Priority level — Critical (blocking), High (urgent), Medium (scheduled), Low (backlog), or N/A
- **status**: Draft (not ready), Proposed (ready for scheduling), In Progress (work started), Accepted (complete)

## Writing Tips

- **Objective**: State the end goal clearly. A developer should understand what success looks like without asking questions.
- **Tasks**: Break the work into concrete steps. Each checkbox should be something a developer can complete in a reasonable time (few hours to 1 day).
- **Acceptance Criteria**: These are the gates for "done." Include testing, documentation, or deployment requirements if applicable.
- **References**: Link to the design doc (RFC/ADR), the parent feature, related issues, or code files this task touches. Context is valuable.

## Example

```markdown
---
date: 2026-03-09
type: Task
severity: High
status: In Progress
---

# Task: Implement webhook retry logic with exponential backoff

## Objective
Improve webhook reliability by implementing exponential backoff with jitter for failed deliveries. Webhooks that fail should retry up to 5 times over ~1 hour before being marked dead.

## Tasks
- [ ] Design retry strategy (backoff formula, max attempts, timing)
- [ ] Add `retry_count` and `next_retry_at` fields to webhooks table
- [ ] Implement background job to scan for due retries (run every 30s)
- [ ] Log retry attempts with outcome (success, will retry, dead)
- [ ] Write integration test covering success, retry, and dead states
- [ ] Document retry policy in API docs
- [ ] Monitor dead webhook rate in production for 1 week

## Acceptance Criteria
- [ ] Failing webhooks retry automatically (no manual intervention)
- [ ] Backoff follows: attempt 1 at T+30s, 2 at T+2m, 3 at T+8m, 4 at T+32m, 5 at T+2h ±jitter
- [ ] All retries logged with attempt number, outcome, error
- [ ] Dead webhooks marked with status=dead and logged for alerting
- [ ] Tests cover success, failure, and partial retries (network recovered mid-sequence)

## References
- Feature: ADR-2026-02-15-webhook-reliability.md
- Related issue: #1234 "Webhooks drop during high load"
- Code: `src/services/webhook-dispatcher.ts`, `src/jobs/webhook-retry-job.ts`
```
