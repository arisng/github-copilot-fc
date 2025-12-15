# Research: Claude Code Hooks - Comprehensive Analysis

## Context
**Requested by:** User  
**Scope:** Complete analysis of hooks in Claude Code (Anthropic's AI coding assistant tool)  
**Goal:** Provide implementation-ready research covering technical workings, types, examples, and best practices  
**Date:** December 15, 2025  

## Key Findings

### 1. What are Claude Code Hooks?

Claude Code hooks are user-defined shell commands that execute at specific lifecycle points during Claude Code's operation. They provide deterministic control over Claude Code's behavior, ensuring certain actions always happen rather than relying on the LLM to choose to run them.

**Core Purpose:**  
- Add automation and control to Claude Code workflows  
- Enable security validation and policy enforcement  
- Provide customization for development processes  
- Allow integration with external tools and systems  

**Key Characteristics:**
- Execute as shell commands with full system access
- Receive JSON input via stdin containing session/tool data
- Communicate results through exit codes and stdout/stderr
- Can block, modify, or enhance Claude Code operations
- Run in parallel when multiple hooks match an event

### 2. How do they work technically?

#### Architecture
Hooks are configured in JSON settings files (`.claude/settings.json` or `~/.claude/settings.json`) and organized by event types with optional matchers:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/hook.py"
          }
        ]
      }
    ]
  }
}
```

#### Execution Flow
1. **Event Trigger**: Claude Code reaches a lifecycle point (e.g., tool use, prompt submission)
2. **Hook Selection**: Matches hooks based on event type and optional patterns
3. **Parallel Execution**: All matching hooks run simultaneously (60-second timeout each)
4. **Input Processing**: Hooks receive JSON via stdin with session context and event data
5. **Decision Making**: Hooks can approve, block, or modify operations
6. **Result Communication**: Exit codes and JSON output control Claude Code behavior

#### Input/Output Schema
**Input (stdin):**
```json
{
  "session_id": "abc123",
  "tool_name": "Bash",
  "tool_input": {"command": "ls -la"},
  "cwd": "/project/path",
  "hook_event_name": "PreToolUse"
}
```

**Output Control:**
- Exit code 0: Success, stdout added to context
- Exit code 2: Blocking error, stderr shown to Claude
- JSON output: Structured control (decisions, modifications)

### 3. Types of Hooks Available

#### Lifecycle Hook Events

| Event | Timing | Blocking Capability | Primary Use |
|-------|--------|-------------------|-------------|
| **UserPromptSubmit** | Before prompt processing | ✅ Can block prompts | Validation, context injection, logging |
| **PreToolUse** | Before tool execution | ✅ Can block tools | Security validation, parameter modification |
| **PermissionRequest** | During permission prompts | ✅ Can auto-approve/deny | Automated permission handling |
| **PostToolUse** | After tool completion | ❌ Cannot block | Result validation, cleanup, logging |
| **Notification** | When Claude sends notifications | ❌ Cannot block | Custom alerts, logging |
| **Stop** | When Claude finishes responding | ✅ Can force continuation | Completion validation |
| **SubagentStop** | When subagents finish | ✅ Can force continuation | Subagent validation |
| **PreCompact** | Before context compaction | ❌ Cannot block | Backup, logging |
| **SessionStart** | Session initialization | ❌ Cannot block | Environment setup, context loading |
| **SessionEnd** | Session termination | ❌ Cannot block | Cleanup, logging |

#### Hook Types
- **Command Hooks**: Execute shell commands (most common)
- **Prompt-Based Hooks**: Use LLM for intelligent decisions (Stop/SubagentStop only)

### 4. Real-world Examples and Use Cases

#### Security & Validation Examples

**Bash Command Validation:**
```python
# Block dangerous commands before execution
dangerous_patterns = [
    r'rm\s+.*-[rf]',      # rm -rf variants
    r'sudo\s+rm',         # privileged deletions
    r'>\s*/etc/',         # system file modifications
]

if any(re.search(pattern, command) for pattern in dangerous_patterns):
    print("BLOCKED: Dangerous command detected", file=sys.stderr)
    sys.exit(2)  # Blocks execution
```

**File Protection:**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"import json, sys; data=json.load(sys.stdin); path=data.get('tool_input',{}).get('file_path',''); sys.exit(2 if any(p in path for p in ['.env', 'package-lock.json', '.git/']) else 0)\""
          }
        ]
      }
    ]
  }
}
```

#### Automation Examples

**Code Formatting:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | xargs -I {} sh -c 'if echo {} | grep -q \"\\.ts$\"; then npx prettier --write {}; fi'"
          }
        ]
      }
    ]
  }
}
```

**Context Injection:**
```python
# Add project context to every prompt
context = f"""
Project: {os.getenv('PROJECT_NAME', 'Unknown')}
Current branch: {subprocess.getoutput('git branch --show-current')}
Recent commits: {subprocess.getoutput('git log --oneline -3')}
"""

print(context)  # Added to Claude's context
sys.exit(0)
```

#### Notification & Feedback Examples

**TTS Completion Messages:**
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/tts_completion.py"
          }
        ]
      }
    ]
  }
}
```

**Desktop Notifications:**
```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "notify-send 'Claude Code' 'Permission required'"
          }
        ]
      }
    ]
  }
}
```

### 5. How to Implement/Create Hooks

#### Basic Implementation Steps

1. **Create Hook Script:**
```python
#!/usr/bin/env python3
import json
import sys

def main():
    # Load input data
    input_data = json.load(sys.stdin)
    
    # Extract relevant information
    event = input_data.get('hook_event_name')
    tool_name = input_data.get('tool_name')
    
    # Implement hook logic
    if event == 'PreToolUse' and tool_name == 'Bash':
        command = input_data.get('tool_input', {}).get('command', '')
        if 'rm -rf' in command:
            print("BLOCKED: Dangerous deletion command", file=sys.stderr)
            sys.exit(2)
    
    sys.exit(0)

if __name__ == '__main__':
    main()
```

2. **Configure in Settings:**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/hook.py"
          }
        ]
      }
    ]
  }
}
```

3. **Make Executable:**
```bash
chmod +x /path/to/hook.py
```

#### Advanced JSON Output Control

**Structured Decisions:**
```python
output = {
    "decision": "block",  # or "approve"
    "reason": "Security policy violation",
    "hookSpecificOutput": {
        "additionalContext": "Extra information for Claude"
    }
}
print(json.dumps(output))
sys.exit(0)
```

**Tool Input Modification:**
```python
output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "updatedInput": {
            "command": "safer-command --with-validation"
        }
    }
}
```

#### UV Single-File Scripts (Recommended)

Use UV for dependency management:
```python
#!/usr/bin/env python3
# /// script
# requires-python = ">=3.8"
# dependencies = ["requests", "pyyaml"]
# ///

import json
import sys
# Hook implementation here
```

### 6. Limitations and Considerations

#### Technical Limitations
- **60-second timeout** per hook execution
- **No direct Claude communication** (only through structured output)
- **Parallel execution** can cause race conditions
- **Environment inheritance** may expose sensitive variables
- **No hook chaining** (hooks don't see other hooks' outputs)

#### Security Considerations
- **Full system access** - hooks run with user's permissions
- **Input validation required** - never trust input data blindly
- **Path traversal risks** - validate file paths carefully
- **Command injection** - quote variables properly (`"$VAR"` not `$VAR`)
- **Sensitive data exposure** - avoid logging secrets

#### Performance Impact
- **Parallel execution overhead** for multiple hooks
- **JSON parsing/serialization** for each hook
- **Shell command spawning** adds latency
- **Context window pressure** from hook outputs

#### Reliability Issues
- **Hook failures** don't stop Claude Code execution
- **Inconsistent environments** across systems
- **Dependency management** complexity
- **Debugging difficulty** in production

### 7. Integration with Other Tools/Systems

#### MCP (Model Context Protocol) Integration
Hooks work seamlessly with MCP tools:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__memory__.*",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/mcp-validator.py"
          }
        ]
      }
    ]
  }
}
```

#### External Tool Integration Examples

**GitHub Integration:**
```python
# Post-commit hook for PR creation
if tool_name == 'Bash' and 'git commit' in command:
    subprocess.run(['gh', 'pr', 'create', '--fill'])
```

**CI/CD Integration:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "curl -X POST $WEBHOOK_URL -d '{\"event\":\"file_changed\"}'"
          }
        ]
      }
    ]
  }
}
```

**Database Integration:**
```python
# Validate SQL before execution
if tool_name == 'Bash' and 'psql' in command:
    # Pre-validate SQL syntax
    validation_result = validate_sql(command)
    if not validation_result['valid']:
        print(f"SQL Error: {validation_result['error']}", file=sys.stderr)
        sys.exit(2)
```

#### IDE Integration
- **VS Code Extensions**: Custom Claude Code interfaces
- **Status Lines**: Real-time terminal status display
- **Output Styles**: Custom response formatting

### 8. Best Practices for Using Hooks

#### Development Best Practices

1. **Start Simple**: Begin with logging-only hooks to understand data flow
2. **Test Thoroughly**: Use safe test environments before production
3. **Handle Errors Gracefully**: Always provide clear error messages
4. **Validate Inputs**: Never trust hook input data blindly
5. **Use Absolute Paths**: Avoid relative path issues
6. **Quote Variables**: Prevent command injection with `"$VAR"`

#### Security Best Practices

1. **Input Sanitization**: Validate and escape all inputs
2. **Path Validation**: Check for `..` and absolute path requirements
3. **Permission Scoping**: Use minimal required permissions
4. **Audit Logging**: Log hook actions for security review
5. **Fail-Safe Design**: Default to allowing rather than blocking

#### Performance Best Practices

1. **Efficient Processing**: Minimize computation in hot paths
2. **Caching**: Cache expensive operations when possible
3. **Selective Matching**: Use specific matchers to reduce execution
4. **Async Operations**: Avoid blocking operations in hooks
5. **Resource Limits**: Monitor memory and CPU usage

#### Organizational Best Practices

1. **Version Control**: Store hooks in project repositories
2. **Documentation**: Document hook purposes and behaviors
3. **Code Reviews**: Review hook changes like production code
4. **Testing**: Include hook testing in CI/CD pipelines
5. **Monitoring**: Log hook performance and failure rates

#### Configuration Management

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "uv run .claude/hooks/bash_validator.py",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

## Recommendations

### Implementation Priority
1. **Security Hooks**: PreToolUse for dangerous command blocking
2. **Automation Hooks**: PostToolUse for formatting and cleanup
3. **Feedback Hooks**: Stop hooks for completion notifications
4. **Integration Hooks**: SessionStart for environment setup

### Getting Started
1. Install Claude Code and explore the `/hooks` command
2. Start with the official quickstart (bash command logging)
3. Implement security validation hooks
4. Add automation for common workflows
5. Integrate with your development toolchain

### Advanced Usage
- Combine hooks with sub-agents for complex workflows
- Use prompt-based hooks for intelligent decision making
- Implement custom status lines for better visibility
- Create plugin marketplaces for team sharing

## References
- [Official Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- [Hooks Reference Documentation](https://code.claude.com/docs/en/hooks)
- [Claude Code Plugins](https://claude.com/blog/claude-code-plugins)
- [GitHub Examples Repository](https://github.com/disler/claude-code-hooks-mastery)
- [Anthropic Official Examples](https://github.com/anthropics/claude-code/blob/main/examples/hooks/bash_command_validator_example.py)