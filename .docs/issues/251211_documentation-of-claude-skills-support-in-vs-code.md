---
date: 2025-12-11
type: Task
severity: N/A
status: Completed
---

# Task: Document Claude Skills Support in VS Code

## Objective

Document the findings from exploring Claude Skills support in the latest VS Code release (v1.107), including locations, setup, and usage patterns for both personal and project skills.

## Background

VS Code 1.107 introduced experimental support for reusing existing Claude Skills in the Copilot Chat interface. This allows users to leverage their Claude Code skills ecosystem directly within VS Code's agent system.

## Key Findings

### VS Code Integration

- **Experimental Feature**: Enabled via `chat.useClaudeSkills` setting
- **Automatic Discovery**: Skills are loaded on-demand based on description matching
- **Progressive Disclosure**: Skills load supporting files only when needed to manage context
- **Tool Limitations**: `allowed-tools` attribute from Claude Code is not supported in VS Code

### Skills Locations

#### Personal Skills: `~/.claude/skills/`

- **Path**: `~/.claude/skills/skill-name/SKILL.md` (on Windows: `%USERPROFILE%\.claude\skills\`)
- **Scope**: Global across all projects and VS Code sessions
- **Use Cases**: Individual workflows, experimental skills, personal productivity tools
- **Management**: Not version controlled, personal use only

#### Workspace (Project) Skills: `skills/`

- **Path**: `${workspaceFolder}skills/skill-name/SKILL.md`
- **Scope**: Specific to the current workspace/project
- **Use Cases**: Team workflows, project-specific expertise, shared utilities
- **Management**: Version controlled with project, automatically shared with team

**Note**: All GitHub Copilot customizations (agents, instructions, prompts) and Claude Skills are intentionally located in workspace root directories (not in VS Code's standard scan locations like `.github/`, `.claude/skills/`, etc.) to prevent duplication. VS Code scans both synced user settings (for GitHub Copilot customizations) and user home locations (for Claude Skills), so workspace versions are kept separate from published versions.

### Skill Structure Requirements

- **Required**: `SKILL.md` file with YAML frontmatter
- **Frontmatter Fields**:
  - `name`: Lowercase, numbers, hyphens only (max 64 chars)
  - `description`: Brief description with trigger words (max 1024 chars)
- **Optional**: Supporting files (scripts, templates, documentation) in same directory

### Windows-Specific Setup

- **Home Directory**: `C:\Users\<username>` (confirmed as `C:\Users\ADMIN`)
- **Personal Skills Path**: `C:\Users\ADMIN\.claude\skills\`
- **Access Methods**:
  - File Explorer: `%USERPROFILE%\.claude\skills`
  - Command Line: `cd %USERPROFILE%\.claude\skills`
  - VS Code: Open folder directly

## Implementation Details

### Discovery Process

1. Enable `chat.useClaudeSkills` setting
2. VS Code scans both personal and project skills directories
3. Skills loaded based on description matching user queries
4. Supporting files loaded progressively as needed

### Usage in Agent Mode

1. Start chat in agent mode
2. Ask "What skills do you have?" to list available skills
3. Skills activate automatically based on description matching
4. Manual skill invocation possible by improving descriptions

## Tasks Completed

- [x] Explored VS Code 1.107 release notes for Claude Skills support
- [x] Researched official Claude Code documentation for skills structure
- [x] Identified and documented the two skills locations (personal and project)
- [x] Verified Windows-specific paths and setup procedures
- [x] Created personal skills directory on Windows system
- [x] Documented skill discovery and usage patterns
- [x] Provided complete setup and usage instructions

## Acceptance Criteria

- [x] Complete documentation of Claude Skills support in VS Code
- [x] Clear identification of skills locations for different platforms
- [x] Step-by-step setup instructions for Windows users
- [x] Usage examples and best practices
- [x] Troubleshooting guidance for common issues

## References

- [VS Code 1.107 Release Notes](https://code.visualstudio.com/updates/v1_107)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [VS Code Custom Agents Documentation](https://code.visualstudio.com/docs/copilot/customization/custom-agents)
- Personal Skills Location: `C:\Users\ADMIN\.claude\skills\`
