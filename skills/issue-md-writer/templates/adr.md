# ADR (Architecture Decision Record)

Use this template to document a major technical decision after it has been made and agreed upon. ADRs are lightweight decision logs that capture context, the decision itself, and consequences. Reference ADRs in code comments and design docs.

## Template

```markdown
---
date: YYYY-MM-DD
type: ADR
severity: N/A
status: Proposed
author: Name <email>
tags:
  - architecture
  - decision
related:
  - 251201_arch-decision.md
---

# ADR: [Decision Title]

## Context
[The situation and constraints leading to this decision.]

## Decision
[The change that we are proposing or have agreed to.]

## Consequences
**Positive:**
- [Benefit 1]

**Negative:**
- [Trade-off 1]
```

## Field Descriptions

- **date**: ISO 8601 date when the decision was finalized
- **type**: Always "ADR" for this template
- **severity**: Always "N/A" for ADRs (decisions, not bugs)
- **status**: Proposed (decision pending), Accepted (decision made), Superseded (later decision replaced this one)
- **author**: Name and email of the decision maker or primary owner
- **tags**: Semantic labels (e.g., architecture, database, security, performance) for filtering and discovery
- **related**: List of related ADRs, RFCs, or design docs

## Writing Tips

- **Context**: Lay out the problem, constraints, and trade-offs being weighed. Why this decision now?
- **Decision**: Be declarative — "We will use PostgreSQL for the primary database" not "We might consider PostgreSQL."
- **Consequences**: Balanced — acknowledge benefits and trade-offs. Not all consequences are negative; some are enabling. List both.

## Example

```markdown
---
date: 2026-03-01
type: ADR
severity: N/A
status: Accepted
author: Alex <alex@example.com>
tags:
  - architecture
  - caching
  - performance
related:
  - 260228_cache-performance-analysis.md
---

# ADR: Use Redis for session caching instead of in-memory cache

## Context
Our in-memory cache works fine for single-server deployments, but with multi-region deployment coming online, we need cross-region session replication. Moving to Redis enables shared session state across instances without code changes. Alternatives: Memcached, DynamoDB, distributed memory (Hazelcast). Redis chosen for ecosystem maturity, operational familiarity, and cost.

## Decision
Deploy Redis (managed service via cloud provider) as the session cache layer. Migrate session management code to use ioredis client. Keep TTL and eviction policies in application code for flexibility.

## Consequences
**Positive:**
- Multi-region session sharing without application complexity
- Familiar ecosystem — ops team knows Redis
- Built-in persistence options for durability
- Performance: ~1ms p50 latency

**Negative:**
- Additional operational dependency (Redis uptime SLA)
- Cost: ~$300/month for managed Redis instance
- Network latency added vs in-memory (~1ms vs <1µs)
- Learning curve for debugging Redis-specific issues
```
