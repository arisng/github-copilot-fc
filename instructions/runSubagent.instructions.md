---
name: runSubagent-guidelines
description: 'Best practices for using runSubagent to delegate tasks to subagents'
applyTo: '**'
---

# RunSubagent Usage Guidelines

Instructions for effectively using the runSubagent tool to delegate tasks to subagents.

## When to Use RunSubagent

Use runSubagent for tasks that are:

- Complex and multi-step requiring autonomous execution
- Research-intensive across multiple sources
- Involving specialized knowledge or tools
- Time-consuming if done manually
- Requiring consistent, validated outputs

Avoid using runSubagent for:

- Simple, single-step tasks
- Tasks that can be completed with existing tools in one call
- When immediate response is critical
- For tasks already within your core capabilities

## Best Practices

### Context Preservation

**CRITICAL**: Always preserve exact context from the last main agent response when delegating new tasks. This ensures continuity and prevents loss of critical information.

It is the responsibility of the main agent to paraphrase and preserve 100% correct context of its last response (visible to user) into a new message (invisible to user) to subagent.

- Include the full, unaltered output from your previous response to the user in the subagent prompt
- When user queries imply continuation (e.g., "proceed with that" or "now do X"), explicitly reference and include the prior main agent response
- Never assume subagents retain context between invocations - each call is stateless
- Document the context chain clearly in prompts to maintain accuracy

Failure to preserve context can lead to incomplete or incorrect subagent outputs, directly impacting the final result returned to the user.

### Prompt Engineering

- Provide highly detailed task descriptions
- Specify exact output format and information to return
- Include all relevant context and constraints
- Clearly state whether code generation or research is expected
- Indicate if the agent should validate or test results

### Agent Selection

- Choose the most appropriate agent from available options
- Use exact agent names as listed (case-sensitive)
- Match agent expertise to task requirements
- Consider Generic-Research-Agent for broad research tasks
- Use specialized agents for domain-specific work

### Task Delegation

- Break complex tasks into logical sub-tasks if needed
- Ensure subagent has access to necessary tools
- Provide sufficient background information
- Set clear success criteria

### Result Handling

- Expect a single, comprehensive response from the subagent
- **CRITICAL**: Preserve the full **final** subagent response in your final output to ensure complete information reaches the user
- Avoid unnecessary summarization or filtering that could omit important details from subagent work
- Present subagent findings, code samples, and recommendations directly to maintain accuracy and reduce information loss
- Integrate subagent results into your workflow
- Validate outputs before proceeding
- Document any assumptions or limitations

## Examples

### Good Example - Research Task with Context Preservation

When following up on a previous main agent response, always include the exact context:

```
runSubagent(
  agentName: "Generic-Research-Agent",
  description: "Continue API research with previous findings",
  prompt: "Based on my previous response to the user: [paste exact main agent response here]. Now extend this by analyzing current best practices for REST API integration in modern web applications. Include examples in JavaScript/TypeScript, security considerations, and testing approaches. Provide implementation-ready code samples and validation steps."
)
```

### Bad Example - Lost Context

Never delegate without preserving previous main agent context:

```
# Avoid this - subagent loses critical context
runSubagent(
  agentName: "Generic-Research-Agent",
  description: "Continue with implementation",
  prompt: "Now implement the API integration patterns we discussed."
)
```

Always include: `prompt: "Based on my previous response to the user: [exact main agent response]. Now implement..."`

## Validation

After delegating to a subagent:

- Review the returned information for completeness
- Verify any code samples work as expected
- Ensure results align with project requirements
- Test integrations if applicable

This ensures high-quality outcomes from delegated tasks.