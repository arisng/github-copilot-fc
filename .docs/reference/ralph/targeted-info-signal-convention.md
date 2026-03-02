---
category: reference
source_session: "260227-144634"
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-2 spec and report — SKIP signal removal and INFO+target convention"
extracted_at: "2026-03-01T12:35:28+07:00"
promoted: true
promoted_at: "2026-03-01T12:43:56+07:00"
---

# Targeted INFO Signal Convention

## Overview

The Ralph v2 Live Signal Protocol supports four universal signal types: **STEER**, **INFO**, **PAUSE**, and **ABORT**. Rather than creating additional signal types for agent-specific behaviors, the protocol uses a **targeted INFO convention** — an INFO signal with a `target` field and a structured message prefix that encodes the intent.

## Convention Pattern

A targeted INFO signal uses three fields to route intent to a specific agent:

| Field | Value | Purpose |
|-------|-------|---------|
| `type` | `INFO` | Standard universal signal type |
| `target` | `<agent-name>` (e.g., `Librarian`) | Routes to the specific agent |
| `message` | `<PREFIX>: <details>` | Structured prefix encodes the intent |

### Example: Skip-Promotion Convention

To opt out of automatic knowledge promotion, the human sends:

```yaml
type: INFO
target: Librarian
message: "SKIP_PROMOTION: Do not promote staged knowledge to the workspace wiki this iteration."
created_at: 2026-03-01T12:00:00+07:00
```

The Librarian agent checks for this convention during its pre-promotion step:
1. Poll for signals with `type: INFO` AND `target: Librarian`
2. Check if the message starts with `SKIP_PROMOTION:`
3. If matched: cancel promotion, preserve staged knowledge for future manual promotion
4. If not matched: proceed with auto-promotion (default behavior)

## Design Rationale

This convention replaced a dedicated `SKIP` signal type. The simplification reduces the protocol from five signal types to four while preserving the same capability:

| Before | After |
|--------|-------|
| 5 types: STEER, INFO, PAUSE, ABORT, SKIP | 4 types: STEER, INFO, PAUSE, ABORT |
| SKIP was state-specific (only meaningful during promotion) | INFO is universal; targeting makes it agent-specific |
| Required special routing logic in the orchestrator | Uses existing INFO routing with `target` filtering |

Benefits:
- **Simpler protocol**: Fewer signal types to document, validate, and route
- **Extensible**: Future agent-specific intents use the same `INFO + target + prefix` pattern without adding new types
- **Consistent routing**: All signals use the universal polling mechanism; agents filter by `target` field

## Signal Type Summary (Current Protocol)

| Type | Category | Purpose |
|------|----------|---------|
| **STEER** | Universal | Redirect scope, approach, or priorities |
| **INFO** | Universal | Inject context; with `target` field, enables agent-specific conventions |
| **PAUSE** | Universal | Halt execution until resumed |
| **ABORT** | Universal | Terminate the session immediately |

Historical types (removed):
- `APPROVE` — Removed when promotion became automatic (replaced by auto-promote default)
- `SKIP` — Removed and replaced by the `INFO + target: Librarian + SKIP_PROMOTION:` convention
