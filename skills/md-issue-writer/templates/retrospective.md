# Retrospective

Use this template to document lessons learned from incidents, projects, or sprints. Retrospectives capture what went well, what didn't, and actionable improvements to prevent or enable similar situations in the future.

## Template

```markdown
---
date: YYYY-MM-DD
type: Retrospective
severity: N/A
status: Documented | Reviewed | Implemented
---

# Lesson: [Concise Title]

## Context
[What happened? Brief background on the incident, problem, or project.]

## What Went Well
- [Positive aspects or successes]

## What Didn't Go Well
- [Challenges, mistakes, or areas for improvement]

## Key Lessons Learned
- [Actionable insights and takeaways]
- [What we learned about processes, tools, or team dynamics]

## Actions Taken
- [Immediate fixes or changes implemented]

## Future Prevention / Improvements
- [ ] [Checklist item for preventing recurrence]
- [ ] [Recommendations for similar situations]
```

## Field Descriptions

- **date**: ISO 8601 date when the retrospective was written (typically shortly after the incident/sprint)
- **type**: Always "Retrospective" for this template
- **severity**: Always "N/A" for retrospectives (learning documents, not issues)
- **status**: Documented (initial writeup), Reviewed (team consensus), Implemented (actions completed)

## Writing Tips

- **Context**: Set the scene without blame. What happened, why does it matter, who was involved?
- **What Went Well**: Celebrate the wins. This builds team morale and ensures you preserve winning practices.
- **What Didn't Go Well**: Be honest but blameless. Focus on systems and processes, not individuals.
- **Key Lessons**: Extract the principle. Don't just list symptoms — identify root causes and the patterns you discovered.
- **Actions Taken**: Show momentum. What changes have already been made or are in flight?
- **Future Prevention**: Make commitments concrete. Assign owners if possible (can be as simple as "monitoring team to watch X metric").

## Types of Retrospectives

- **Post-incident**: After a production outage or security incident
- **Project retrospective**: After shipping a feature or completing a major project
- **Sprint retrospective**: Regular check-ins on what's working in the development process
- **Post-release**: After a release cycle to capture deployment learnings

## Example

```markdown
---
date: 2026-03-08
type: Retrospective
severity: N/A
status: Reviewed
---

# Lesson: Database migration taught us about deployment safety

## Context
We performed a zero-downtime migration of 50GB of customer data from PostgreSQL 11 to 14. The process took 18 hours, longer than planned. The team learned critical lessons about testing, communication, and runbook preparation.

## What Went Well
- Dry run on staging caught index incompatibility early (saved 4+ hours in production)
- On-call rotation was smooth — team stayed focused and well-rested
- Database team prepared detailed rollback steps, which we didn't need but appreciated having
- Real-time monitoring dashboard caught performance degradation immediately

## What Didn't Go Well
- Testing didn't cover application queries with custom PostgreSQL extensions
- Runbook had assumed version during migration, didn't account for slowdown on old hardware
- Communication gaps: frontend team not aware of feature flag restrictions during migration
- Initial estimate (4 hours) was off by 4x; planning was optimistic

## Key Lessons Learned
- **Test with the actual schema and queries**, not just empty tables
- **Load test realistic scenarios** — staging hardware doesn't match production
- **Runbooks need decision trees** for unknowns (what if X takes longer than Y?)
- **Communication is as important as execution** — keep all teams in the loop even if silent
- **Better to overestimate and surprise with early completion** than scramble with overages

## Actions Taken
- [ ] Created database migration checklist template for future use
- [ ] Added monitoring alerts for query latency degradation (deploy next week)
- [ ] Scheduled quarterly chaos engineering exercises (first one: simulate slow disk)
- [ ] Set up pre-migration stakeholder alignment meeting (added to runbook)

## Future Prevention / Improvements
- [ ] Infrastructure team: Upgrade staging to match production specs
- [ ] Database team: Add PostgreSQL extension tests to CI
- [ ] DevOps team: Build automated validation script to check app ↔ DB compatibility
- [ ] All teams: Pre-migration dry run is now mandatory for any data migration
```
