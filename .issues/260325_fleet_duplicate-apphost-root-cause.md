---
date: 2026-03-25
type: Bug
severity: High
status: Investigating
---

# Duplicate AGUIDojo host launches crash / environment mismatch during `/fleet` run

## Problem
During a `copilot /fleet` execution, both ad-hoc app launches crashed when multiple long-running subagents tried to start the same app host. This manifested as repeated start attempts, duped `AGUIDojo` servers, and “Waiting up to 5 seconds for command output” tight-loop noise in CLI logs.

## Root Cause
- Subagents lacked a reliable cluster-wide host ownership check before starting `AGUIDojo`.
- The orchestration path attempted to start duplicate hosts in parallel (layout agent + projections agent), resulting in process conflicts and environment mismatch failures.
- Duplication produced extra noise from the harness (durable-gap and crash output blocks) which made it harder to separate true implementation state from startup artifacts.

## Solution
- Prefer existing running app instance if one is reported by liveliness probe/service registry (for example `http://localhost:6001`), and skip any additional host startup attempts.
- Add an atomic lock or single-responsibility `app-host-manager` component in `aspire-cli`/agent runtime to commit host ownership before start.
- In the agent action flow, validate host connectivity first (HTTP ping / process check) before launching a new process.

## Lessons Learned
- Orchestrator-level deduplication is critical for long-running agents that share the same test app.
- Harness noise from crash cleanup can hide root-cause events; use separate durable-gap scan and `owner` hints to avoid repeating startup logic.
- Explicit state (e.g., `runningInstanceUrl`) is better than optional re-discovery by each agent.

## Prevention
- [ ] Implement a shared `AGUIDojo` host lease mechanism in `aspire-cli` (or equivalent orchestration wrapper), with clear ownership and TTL.
- [ ] Introduce integration tests for parallel deployment paths (`layout agent` vs `projections agent`) asserting one host launch only.
- [ ] Add a `fleet` preflight check that looks for a running app on `localhost:6001` and exports the host URL to the agent graph.
- [ ] Document `avoid duplicate host starts` guidance in the `aspire-cli` skill and Copilot orchestration playbook.
