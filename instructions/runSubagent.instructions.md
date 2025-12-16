---
name: runSubagent
description: 'Rules for using runSubagent tool when delegating tasks to subagents'
applyTo: '**'
---

# Tool runSubagent Usage Guidelines

## Mandatory Convention: Trigger Key Phrase
**CRITICAL**: When delegating to a custom agent via runSubagent, you MUST explicitly include the key phrase **"run as subagent"** (or equivalent trigger phrase) in the prompt. This signals to the delegated custom agent that it is operating in subagent mode and should apply its specialized behavior accordingly.

Example:
```
"Please run as subagent and analyze the following API design..."
```

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

### ✅ Good: Including Trigger Key Phrase
```javascript
runSubagent(
  agentName: "Generic-Research-Agent",
  description: "Extend API research",
  // Explicitly includes the trigger key phrase "run as subagent"
  prompt: "Please run as subagent. Based on my previous response: [PASTE FULL PREVIOUS RESPONSE]. Now analyze security best practices for REST API authentication..."
)
```

### ✅ Good: Preserving Context with Key Phrase
```javascript
runSubagent(
  agentName: "Generic-Research-Agent",
  description: "Extend API research",
  // Includes both key phrase and full context
  prompt: "Run as subagent and extend this analysis: [PASTE FULL PREVIOUS RESPONSE]. Now focus on security considerations..."
)
```

### ❌ Bad: Missing Trigger Key Phrase
```javascript
runSubagent(
  agentName: "Generic-Research-Agent",
  description: "Extend API research",
  prompt: "Based on my previous response: [PASTE FULL PREVIOUS RESPONSE]. Now analyze security best practices..." 
  // Fails: Missing "run as subagent" trigger phrase
)
```

### ❌ Bad: Losing Context
```javascript
runSubagent(
  agentName: "Generic-Research-Agent",
  description: "Continue",
  prompt: "Now implement that." // Fails: Missing both trigger phrase and context
)
```