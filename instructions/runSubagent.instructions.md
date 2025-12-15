---
name: runSubagent
description: 'Rules for using runSubagent tool when delegating tasks to subagents'
applyTo: '**'
---

# Tool runSubagent Usage Guidelines

## When to Use
- **Use for**: Complex, multi-step, research-intensive, or autonomous tasks.
- **Avoid for**: Simple single-step tasks or immediate responses.

## Critical: Context Preservation
**Subagents are stateless.** You MUST explicitly pass all necessary context in the `prompt`.
1. **Include History**: If the user implies continuation ("proceed", "do it"), paste your *entire previous response* into the subagent prompt.
2. **Self-Contained**: Never assume the subagent knows the conversation history.
3. **Full Output**: Preserve the subagent's *full final response* in your output to the user. Do not over-summarize.

## Best Practices
- **Prompting**: Be highly detailed. Specify output format, constraints, and validation needs.
- **Agent Selection**: Use exact case-sensitive names (e.g., `Generic-Research-Agent`). Match expertise to the task.
- **Validation**: Verify subagent outputs (code, facts) before presenting them to the user.

## Examples

### ✅ Good: Preserving Context
```javascript
runSubagent(
  agentName: "Generic-Research-Agent",
  description: "Extend API research",
  // Explicitly includes context so the subagent knows the baseline
  prompt: "Based on my previous response: [PASTE FULL PREVIOUS RESPONSE]. Now analyze security best practices..."
)
```

### ❌ Bad: Losing Context
```javascript
runSubagent(
  agentName: "Generic-Research-Agent",
  description: "Continue",
  prompt: "Now implement that." // Fails: Subagent doesn't know what "that" refers to
)
```