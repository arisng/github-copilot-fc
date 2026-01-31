# Ralph Subagent Contracts

This document defines the input/output contracts for all Ralph subagents. These contracts are **environment-agnostic** and work for both VS Code (`runSubagent`) and SDK (`session.SendAndWaitAsync()`) implementations.

---

## Contract Philosophy

Each subagent contract defines:
1. **Input**: What the orchestrator provides to the subagent
2. **Output**: What the subagent returns to the orchestrator
3. **Side Effects**: What artifacts the subagent creates/modifies

This abstraction enables:
- VS Code: `runSubagent` tool with structured prompts
- SDK: `session.SendAndWaitAsync()` with `customAgents` configuration
- Testing: Mock implementations for unit testing orchestrator logic

---

## Ralph-Planner Contract

**Purpose**: Session initialization, task breakdown, Q&A coordination

### Input Schema

```json
{
  "SESSION_PATH": {
    "type": "string",
    "description": "Path to session directory (e.g., '.ralph-sessions/260131-144400/')",
    "required": true
  },
  "MODE": {
    "type": "enum",
    "values": ["INITIALIZE", "UPDATE", "TASK_BREAKDOWN", "DISCOVERY"],
    "description": "Operation mode",
    "required": true
  },
  "USER_REQUEST": {
    "type": "string",
    "description": "Original user request or follow-up requirements",
    "required": true
  },
  "CONTEXT": {
    "type": "object",
    "description": "Optional additional context (e.g., workspace info, file references)",
    "required": false
  }
}
```

### Output Schema

```json
{
  "status": {
    "type": "enum",
    "values": ["completed", "blocked", "needs_clarification", "needs_qa_cycle"],
    "description": "Result of planning operation"
  },
  "artifacts_created": {
    "type": "array",
    "items": "string",
    "description": "List of artifacts created (e.g., ['plan.md', 'tasks.md', 'progress.md'])"
  },
  "artifacts_updated": {
    "type": "array",
    "items": "string",
    "description": "List of artifacts updated"
  },
  "task_count": {
    "type": "object",
    "properties": {
      "planning": "number",
      "implementation": "number",
      "total": "number"
    }
  },
  "next_actions": {
    "type": "array",
    "items": {
      "type": "enum",
      "values": ["qa_brainstorm", "qa_research", "execute", "review", "complete"]
    },
    "description": "Recommended next steps for orchestrator"
  },
  "blockers": {
    "type": "array",
    "items": "string",
    "description": "List of blocking issues requiring user clarification"
  }
}
```

### Side Effects

| Artifact                       | Action | Condition                           |
| ------------------------------ | ------ | ----------------------------------- |
| `plan.md`                      | Create | MODE = INITIALIZE                   |
| `plan.md`                      | Update | MODE = UPDATE                       |
| `tasks.md`                     | Create | MODE = INITIALIZE or TASK_BREAKDOWN |
| `tasks.md`                     | Update | MODE = UPDATE or TASK_BREAKDOWN     |
| `progress.md`                  | Create | MODE = INITIALIZE                   |
| `progress.md`                  | Update | MODE = UPDATE                       |
| `plan.questions.md`            | Create | MODE = DISCOVERY (first cycle)  |
| `<SESSION_ID>.instructions.md` | Create | MODE = INITIALIZE                   |

---

## Ralph-Executor Contract

**Purpose**: Task implementation across coding, research, documentation, analysis

### Input Schema

```json
{
  "SESSION_PATH": {
    "type": "string",
    "description": "Path to session directory",
    "required": true
  },
  "TASK_ID": {
    "type": "string",
    "description": "Identifier of task to execute (e.g., 'task-1', 'task-2.1')",
    "required": true
  },
  "ATTEMPT_NUMBER": {
    "type": "number",
    "description": "Attempt number (1 = first, 2+ = rework)",
    "required": true,
    "default": 1
  }
}
```

### Output Schema

```json
{
  "status": {
    "type": "enum",
    "values": ["completed", "failed", "blocked"],
    "description": "Implementation result"
  },
  "report_path": {
    "type": "string",
    "description": "Path to task report (e.g., 'tasks.task-1-report.md' or 'tasks.task-1-report-r2.md')"
  },
  "success_criteria_met": {
    "type": "boolean",
    "description": "Whether all success criteria were met"
  },
  "discovered_tasks": {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "id": "string",
        "description": "string",
        "rationale": "string"
      }
    },
    "description": "New tasks discovered during implementation"
  },
  "blockers": {
    "type": "array",
    "items": "string",
    "description": "Issues preventing completion"
  }
}
```

### Side Effects

| Artifact                         | Action               | Condition               |
| -------------------------------- | -------------------- | ----------------------- |
| `progress.md`                    | Update `[ ]` → `[/]` | Start of implementation |
| `progress.md`                    | Update `[/]` → `[P]` | Success criteria met    |
| `tasks.<TASK_ID>-report.md`      | Create               | ATTEMPT_NUMBER = 1      |
| `tasks.<TASK_ID>-report-r<N>.md` | Create               | ATTEMPT_NUMBER > 1      |
| Target files                     | Create/Update        | Per task specification  |

---

## Ralph-Reviewer Contract

**Purpose**: Quality validation against success criteria

### Input Schema

```json
{
  "SESSION_PATH": {
    "type": "string",
    "description": "Path to session directory",
    "required": true
  },
  "TASK_ID": {
    "type": "string",
    "description": "Identifier of task to review",
    "required": true
  },
  "REPORT_PATH": {
    "type": "string",
    "description": "Path to implementation report to review",
    "required": true
  }
}
```

### Output Schema

```json
{
  "status": {
    "type": "enum",
    "values": ["completed", "error"],
    "description": "Review operation result"
  },
  "verdict": {
    "type": "enum",
    "values": ["Qualified", "Failed"],
    "description": "Review verdict"
  },
  "criteria_results": {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "criterion": "string",
        "met": "boolean",
        "evidence": "string",
        "finding": "string"
      }
    },
    "description": "Validation results for each success criterion"
  },
  "quality_assessment": {
    "type": "string",
    "description": "Overall quality assessment"
  },
  "issues": {
    "type": "array",
    "items": "string",
    "description": "Specific problems identified"
  },
  "feedback": {
    "type": "string",
    "description": "Guidance for next iteration (if Failed)"
  }
}
```

### Side Effects

| Artifact                           | Action        | Condition |
| ---------------------------------- | ------------- | --------- |
| `tasks.<TASK_ID>-report[-r<N>].md` | Append PART 2 | Always    |

---

## Ralph-Questioner Contract

**Purpose**: Q&A discovery - question generation and evidence-based research

### Input Schema

```json
{
  "SESSION_PATH": {
    "type": "string",
    "description": "Path to session directory",
    "required": true
  },
  "MODE": {
    "type": "enum",
    "values": ["BRAINSTORM", "RESEARCH"],
    "description": "Operation mode",
    "required": true
  },
  "CYCLE_NUMBER": {
    "type": "number",
    "description": "Q&A cycle number (1, 2, 3...)",
    "required": true,
    "default": 1
  }
}
```

### Output Schema

```json
{
  "status": {
    "type": "enum",
    "values": ["completed", "blocked"],
    "description": "Operation result"
  },
  "questions_generated": {
    "type": "number",
    "description": "Number of questions generated (BRAINSTORM mode)"
  },
  "questions_answered": {
    "type": "number",
    "description": "Number of questions answered (RESEARCH mode)"
  },
  "priority_breakdown": {
    "type": "object",
    "properties": {
      "high": "number",
      "medium": "number",
      "low": "number"
    }
  },
  "confidence_distribution": {
    "type": "object",
    "properties": {
      "high": "number",
      "medium": "number",
      "low": "number",
      "unknown": "number"
    },
    "description": "Confidence levels of answers (RESEARCH mode)"
  },
  "new_questions_emerged": {
    "type": "number",
    "description": "Questions discovered while answering (RESEARCH mode)"
  },
  "invalidated_assumptions": {
    "type": "number",
    "description": "Assumptions disproven by research"
  },
  "critical_findings": {
    "type": "array",
    "items": "string",
    "description": "Most important discoveries"
  },
  "recommendations": {
    "type": "array",
    "items": "string",
    "description": "Suggested updates for plan.md"
  }
}
```

### Side Effects

| Artifact            | Action | Condition |
| ------------------- | ------ | --------- |
| `plan.questions.md` | Update | Always    |

---

## VS Code vs SDK Implementation Mapping

| Concept          | VS Code                          | SDK (C#)                                                      |
| ---------------- | -------------------------------- | ------------------------------------------------------------- |
| Invoke subagent  | `runSubagent(agentName, prompt)` | `session.SendAndWaitAsync(prompt)` with `customAgents` config |
| Agent definition | `.agent.md` file                 | `CustomAgent` object in session config                        |
| Session state    | File-based (`.ralph-sessions/`)  | File-based OR abstracted interface                            |
| Input passing    | Structured prompt text           | Prompt text OR typed parameters                               |
| Output parsing   | Parse response text              | Parse response OR typed response object                       |

### Example: VS Code Invocation

```txt
#tool:agent/runSubagent
agentName: "Ralph-Executor"
description: "Implementation of task: task-1 [Attempt #1]"
prompt: |
  SESSION_PATH: .ralph-sessions/260131-144400/
  TASK_ID: task-1
  ATTEMPT_NUMBER: 1
  
  [Additional context...]
```

### Example: SDK Invocation (C#)

```csharp
var session = await client.CreateSessionAsync(new SessionConfig
{
    CustomAgents = new[] { executorAgentConfig }
});

var result = await session.SendAndWaitAsync(new ExecutorInput
{
    SessionPath = ".ralph-sessions/260131-144400/",
    TaskId = "task-1",
    AttemptNumber = 1
});

// Parse typed response
var output = JsonSerializer.Deserialize<ExecutorOutput>(result.Content);
```

---

## Contract Versioning

| Contract         | Version | Last Updated |
| ---------------- | ------- | ------------ |
| Ralph-Planner    | 1.0.0   | 2026-01-31   |
| Ralph-Executor   | 1.0.0   | 2026-01-31   |
| Ralph-Reviewer   | 1.0.0   | 2026-01-31   |
| Ralph-Questioner | 1.0.0   | 2026-01-31   |
