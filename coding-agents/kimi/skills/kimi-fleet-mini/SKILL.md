---
name: kimi-fleet-mini
description: Multi-iteration parallel subagent orchestrator for Kimi Code CLI
type: flow
metadata: 
  author: arisng
  version: 0.1.0
---

# Fleet Flow Skill

Dispatch subagents in parallel waves to complete complex work.

## Agent Flow

```mermaid
flowchart TD
    BEGIN([BEGIN]) --> INIT[Initialize Session]
    INIT --> PLAN[Create Master Plan]
    PLAN --> WAVE{Execute Wave}
    WAVE -->|Tasks ready| DISPATCH[Dispatch Subagents]
    WAVE -->|All done| REVIEW[Review Results]
    DISPATCH --> COLLECT[Collect Results]
    COLLECT --> WAVE
    REVIEW --> VALIDATE{Validation Pass?}
    VALIDATE -->|Issues found| FIX[Create Fix Tasks]
    FIX --> WAVE
    VALIDATE -->|Clean| END([END])
```

## Core Principles

- Dispatch independent tasks simultaneously using `Agent` tool with `run_in_background=true`
- Use `coder`, `explore`, or `plan` subagent types appropriately
