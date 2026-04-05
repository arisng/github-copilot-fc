# End-to-End Workflow Simulation

A real-life simulation of the full OpenSpec SDD cycle for a software engineering task. Annotated so each step explains *why* not just *what*.

## Contents

- [Scenario overview](#scenario-add-rate-limiting-to-a-saas-rest-api)
- [Phase 1 — Explore](#phase-1--explore)
- [Phase 2 — Propose](#phase-2--propose)
- [Phase 3 — Apply](#phase-3--apply)
- [Phase 4 — Mid-Flight Adjustment](#phase-4--mid-flight-adjustment)
- [Phase 5 — Verify](#phase-5--verify)
- [Phase 6 — Archive](#phase-6--archive)
- [Simulation Summary](#simulation-summary)

---

## Scenario: Add Rate Limiting to a SaaS REST API

**Starting point**: A Node.js/Express API powers a multi-tenant SaaS platform. Users authenticate with JWT tokens. Engineering receives a support escalation: heavy API consumers are degrading performance for other tenants. The task: *"Limit authenticated users to 100 requests per minute. Return HTTP 429 when the limit is exceeded."*

**Tech stack** (from `openspec/config.yaml`):
```yaml
schema: spec-driven
context: |
  Node.js 22 + Express 5 REST API.
  Multi-tenant SaaS — users identified by JWT sub claim.
  Redis for session storage (already available).
  Tests: Vitest + supertest.
  CI: GitHub Actions, no deploys on failing tests.
```

---

## Phase 1 — Explore

**Trigger**: The problem statement is silent on: per-user vs per-IP, sliding vs fixed window, response format, which endpoints are affected. These gaps mean a straight `/opsx:propose` would produce a design with hidden assumptions. Use `/opsx:explore` first.

**Agent runs:**
```bash
openspec list --json              # understand existing change landscape
openspec list --specs --json      # which domains are already specified
```

**Agent reads:**
- `src/middleware/` — no rate-limiting middleware exists
- `src/auth/jwt.ts` — `req.user.sub` is always present after auth
- `openspec/specs/requests/spec.md` — exists, covers request validation; no rate-limit requirements

**Agent surfaces to user:**

> **Gaps I need resolved before proposing:**
> 1. Scope: all authenticated endpoints, or a specific subset?
> 2. Window type: sliding window (Redis sorted sets) or fixed window (Redis INCR + TTL)?
> 3. 429 response body: include `Retry-After` header and remaining quota?
> 4. Unauthenticated requests: rate-limit by IP or skip entirely?
>
> **Architecture risk**: Redis is available but not dependency-injected into middleware yet.

**User responds:** All authenticated endpoints. Fixed window. Yes to `Retry-After` and `X-RateLimit-Remaining`. Skip unauthenticated (blocked elsewhere).

**Outcome**: Ambiguity resolved → move to `/opsx:propose`.

---

## Phase 2 — Propose

**Agent runs:**
```bash
openspec new change rate-limiting
openspec instructions proposal --change rate-limiting --json
```

**`openspec/changes/rate-limiting/proposal.md`:**
```markdown
# Change Proposal: Rate Limiting

## Why
Heavy consumers degrade API performance for all tenants. No enforcement mechanism exists.
Escalation ticket: #1847.

## What Changes
- New rate-limiting middleware applied to all authenticated routes
- Redis fixed-window counter keyed by JWT `sub` claim
- HTTP 429 response with `Retry-After` and `X-RateLimit-Remaining` headers
- Configurable limit via `RATE_LIMIT_RPM` env var (default: 100)

## New Capabilities
- **Per-user request throttling**: Each authenticated user is independently throttled
- **Transparent quota headers**: Clients can observe remaining quota without hitting 429

## Modified Capabilities
- **Request pipeline**: Rate-limit check inserted after JWT validation, before route handlers

## Impact
- Low risk: additive middleware, no schema changes, no data migrations
- Redis dependency already present; new key pattern: `rl:<sub>:<window>`

## Rollback
Remove middleware registration in `src/app.ts`. Redis keys expire automatically.
```

**`openspec/changes/rate-limiting/specs/requests/spec.md`:**
```markdown
# Requests Specification — Delta

## MODIFIED

### Requirement: Rate Limit Enforcement
The system SHALL enforce a per-user request rate limit of `RATE_LIMIT_RPM` requests
per 60-second fixed window for all authenticated endpoints.

#### Scenario: Request within limit
- **GIVEN** an authenticated user has made fewer than `RATE_LIMIT_RPM` requests in the current window
- **WHEN** the user sends a new API request
- **THEN** the request is processed normally
- **AND** the response includes an `X-RateLimit-Remaining` header with the remaining count

#### Scenario: Request exceeds limit
- **GIVEN** an authenticated user has reached `RATE_LIMIT_RPM` requests in the current window
- **WHEN** the user sends another request
- **THEN** the system returns HTTP 429
- **AND** the response body contains `{ "error": "rate_limit_exceeded", "retryAfter": <seconds> }`
- **AND** the response includes a `Retry-After` header with seconds until window reset

#### Scenario: Unauthenticated request
- **GIVEN** a request carries no valid JWT
- **WHEN** the request reaches the rate-limiting middleware
- **THEN** the middleware passes the request through without incrementing any counter
```

**`openspec/changes/rate-limiting/design.md`:**
```markdown
# Design: Rate Limiting

## Approach
Fixed-window counter in Redis. Key: `rl:<sub>:<windowStart>` where `windowStart` is the
Unix timestamp floored to the nearest 60 seconds. TTL: 61 seconds (handles clock skew).

## Architecture Decisions
- **Middleware placement**: After `authenticateJwt`, before route handlers (`src/middleware/rateLimiter.ts`)
- **Counter strategy**: `INCR` + `EXPIRE` on first hit (atomic, no race conditions)
- **Config**: `RATE_LIMIT_RPM` env var, default 100
- **Error format**: `{ error, retryAfter }` — consistent with existing API error envelope

## File Changes
| File | Action |
|---|---|
| `src/middleware/rateLimiter.ts` | CREATE |
| `src/app.ts` | MODIFY — register middleware after `authenticateJwt` |
| `src/config.ts` | MODIFY — add `RATE_LIMIT_RPM` |
| `tests/middleware/rateLimiter.test.ts` | CREATE |
| `.env.example` | MODIFY — document `RATE_LIMIT_RPM` |
```

**`openspec/changes/rate-limiting/tasks.md`:**
```markdown
# Tasks: Rate Limiting

## Phase 1 — Config
- [ ] Add `RATE_LIMIT_RPM` to `src/config.ts` with default 100
- [ ] Document `RATE_LIMIT_RPM` in `.env.example`

## Phase 2 — Middleware
- [ ] Create `src/middleware/rateLimiter.ts`
  - Accept `redis` client + `limitPerMinute` as constructor args (testable)
  - Compute `windowStart`: `Math.floor(Date.now() / 60000) * 60`
  - Key: `rl:<req.user.sub>:<windowStart>`
  - `INCR` key; `EXPIRE 61` only when count === 1
  - If count > limit → 429 with headers and body
  - Otherwise attach `X-RateLimit-Remaining` and call `next()`
  - Skip when `req.user` is absent

## Phase 3 — Wire Up
- [ ] Register `rateLimiter` in `src/app.ts` after `authenticateJwt`

## Phase 4 — Tests
- [ ] Write `tests/middleware/rateLimiter.test.ts`
  - Case: first request → 200 + correct `X-RateLimit-Remaining`
  - Case: at limit → 429 + `Retry-After` header + correct body
  - Case: unauthenticated → passes through, no counter incremented
  - Case: counter resets after window boundary

## Phase 5 — Validation
- [ ] Run `openspec validate --change rate-limiting --all`
- [ ] Run `npm test`
```

**Validation before implementation:**
```bash
openspec validate --change rate-limiting --all
# ✔ proposal.md — valid
# ✔ specs/requests/spec.md — valid (3 scenarios)
# ✔ design.md — valid
# ✔ tasks.md — 9 tasks, 0 complete
```

---

## Phase 3 — Apply

```bash
openspec status --change "rate-limiting" --json
# → 0/9 tasks complete, all artifacts present
```

Agent works through tasks in order, referencing delta specs for *what* to implement and `design.md` for *how*:

**`src/config.ts`** (excerpt):
```typescript
export const config = {
  rateLimitRpm: parseInt(process.env.RATE_LIMIT_RPM ?? '100', 10),
};
```

**`src/middleware/rateLimiter.ts`**:
```typescript
import type { Request, Response, NextFunction } from 'express';
import type { Redis } from 'ioredis';

export function createRateLimiter(redis: Redis, limitPerMinute = 100) {
  return async function rateLimiter(req: Request, res: Response, next: NextFunction) {
    if (!req.user?.sub) return next();

    const windowStart = Math.floor(Date.now() / 60_000) * 60;
    const key = `rl:${req.user.sub}:${windowStart}`;

    const count = await redis.incr(key);
    if (count === 1) await redis.expire(key, 61);

    if (count > limitPerMinute) {
      const retryAfter = 60 - (Math.floor(Date.now() / 1000) % 60);
      res.set('Retry-After', String(retryAfter));
      return res.status(429).json({ error: 'rate_limit_exceeded', retryAfter });
    }

    res.set('X-RateLimit-Remaining', String(limitPerMinute - count));
    next();
  };
}
```

**`src/app.ts`** (registration):
```typescript
app.use(authenticateJwt);
app.use(createRateLimiter(redisClient, config.rateLimitRpm));
```

Each completed task is marked `- [x]` in `tasks.md` immediately after implementation.

---

## Phase 4 — Mid-Flight Adjustment

**Situation**: While writing tests, the agent spots a gap: if `redis.incr()` throws, the unhandled exception propagates as HTTP 500. The spec is silent on Redis failure behavior.

**Agent surfaces the gap:**

> The spec and design don't address Redis unavailability. "Fail open" (pass request through, log warning) is safer for a rate-limiting middleware than crashing the request. Should I add a scenario and update the delta spec before implementing?

**User responds:** "Yes, fail open."

**Agent adds to the delta spec** (mid-flight direct edit — acceptable for in-progress changes):
```markdown
#### Scenario: Redis unavailable
- **GIVEN** the Redis connection is unavailable or returns an error
- **WHEN** the rate-limiting middleware attempts to increment the counter
- **THEN** the middleware logs a warning and passes the request through
- **AND** the response does not include rate-limit headers
```

**Agent adds to `rateLimiter.ts`**:
```typescript
try {
  const count = await redis.incr(key);
  // ... rest of logic
} catch (err) {
  console.warn('[rateLimiter] Redis error — failing open', err);
  return next();
}
```

> **Why this matters**: The delta spec is updated *before* implementing — not after. Silent behavior gaps become documented requirements. The `/opsx:sync` command is not needed here because this edit is to the *change's* delta spec, not the main specs.

---

## Phase 5 — Verify

```bash
openspec validate --change rate-limiting --all
# ✔ proposal.md — valid
# ✔ specs/requests/spec.md — valid (4 scenarios)
# ✔ tasks.md — 10/10 tasks complete

npm test
# ✔ rateLimiter — first request passes
# ✔ rateLimiter — limit exceeded returns 429
# ✔ rateLimiter — unauthenticated skipped
# ✔ rateLimiter — window reset resets counter
# ✔ rateLimiter — Redis error fails open
# All tests pass (47 total, 5 new)
```

| Dimension | Result |
|---|---|
| **Completeness** | All 10 tasks done. All 4 scenarios covered by tests. |
| **Correctness** | 429 body and headers match spec exactly. Fail-open on Redis error. |
| **Coherence** | Redis key pattern matches design. Middleware registered in correct order. |

Result: **No CRITICALs, no WARNINGs.**

---

## Phase 6 — Archive

```bash
openspec archive rate-limiting -y
```

What happens internally:
1. Validates task completion (10/10 ✔)
2. Validates delta spec markers (MODIFIED, 4 scenarios ✔)
3. Merges delta into `openspec/specs/requests/spec.md` — rate-limit requirements become permanent
4. Moves change folder → `openspec/changes/archive/2026-04-05-rate-limiting/`

The `Current-Spec Mutation Rule` is now in effect for this domain: any future change to rate-limiting behavior requires a new delta proposal.

---

## Simulation Summary

| Phase | Command/Action | Outcome |
|---|---|---|
| Explore | `/opsx:explore` | 4 ambiguities resolved before any artifact |
| Propose | `/opsx:propose` | `proposal.md`, delta spec (3 scenarios), `design.md`, `tasks.md` (9 tasks) |
| Validate | `openspec validate --all` | All green before first line of code |
| Apply | `/opsx:apply` × 9 tasks | Working middleware + tests |
| Mid-flight fix | Direct delta spec edit + implement | Fail-open Redis behavior spec'd then coded |
| Verify | Tests + validate pass | 10/10 tasks, 0 CRITICALs |
| Archive | `openspec archive rate-limiting -y` | Delta merged into main specs, folder archived |

**The spec is the living record** — no separate documentation pass needed.
