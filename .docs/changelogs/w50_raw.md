# Raw Changelog: December 08-14, Week 50, 2025

## Commits

Aris Nguyen | 2025-12-14 | copilot(instruction): emphasize workspace-specific nature of instructions file

Aris Nguyen | 2025-12-14 | copilot(instruction): update publishing instructions to specify exact customizations

Aris Nguyen | 2025-12-14 | copilot(skill): update file path to commit type mapping

Aris Nguyen | 2025-12-14 | copilot(custom-agent): update file path to commit type mapping

Aris Nguyen | 2025-12-14 | copilot(skill): update git-committer skill definition to align with enhanced rules

Enhance the Git Committer skill workflow with stricter rules for atomic commits:
- Mandate individual file type assignment before grouping
- Add pre-commit verification checklist
- Enforce separation of commits by type to prevent mixing
- Expand mapping table with additional VS Code config patterns
- Add validation step to ensure type consistency in commit plans

Aris Nguyen | 2025-12-14 | copilot(custom-agent): enhance commit type mapping and atomicity rules

- Add mandatory step for assigning commit types to individual files before grouping
- Expand mapping table with additional patterns for .vscode/*.json files
- Introduce critical rules enforcing separate commits for different types
- Add validation step to ensure no type mixing in commit plans
- Update constraints to emphasize atomicity requirements

These changes strengthen the agent's ability to maintain clean, type-separated commits
and improve adherence to project-specific conventional commit guidelines.

Aris Nguyen | 2025-12-14 | devtool(vscode): add workspace settings for Copilot commit generation

Aris Nguyen | 2025-12-14 | copilot(skill): update git-committer skill for MCP integration

Aris Nguyen | 2025-12-14 | copilot(mcp): add MCP server configuration

Aris Nguyen | 2025-12-14 | copilot(instruction): standardize instruction files frontmatter

Aris Nguyen | 2025-12-14 | copilot(instruction): add runSubagent usage guidelines

Aris Nguyen | 2025-12-14 | refactor: rebrand project name to "Copilot FC" and update README with architecture decisions, project structure, and usage instructions

Aris Nguyen | 2025-12-14 | refactor(skills): remove old .claude/skills directory in favor of workspace skills/

Aris Nguyen | 2025-12-14 | devtool(script): update publishing scripts and workspace configuration

Aris Nguyen | 2025-12-14 | copilot(prompt): add and update prompt templates

Aris Nguyen | 2025-12-14 | copilot(custom-agent): refactor and update agent definitions: remove conductor, context7, implementation, microsoft-docs, research, verifier, and web-search agents

Aris Nguyen | 2025-12-14 | copilot(instruction): update repository and claude skills instructions

Aris Nguyen | 2025-12-14 | docs(issue): update claude skills documentation and workspace automation

Aris Nguyen | 2025-12-14 | copilot(skill): move all skills from .claude/skills to skills folder

Aris Nguyen | 2025-12-11 | chore(workspace): update workspace metadata

Aris Nguyen | 2025-12-11 | docs: add project README

Aris Nguyen | 2025-12-11 | copilot(instruction): add repository-level instructions

Aris Nguyen | 2025-12-11 | docs(issue): update issue index with new documentation

- Update generated timestamp and statistics
- Add entries for Claude Skills documentation and workspace automation
- Refresh issue metadata index

copilot(skill): enhance vscode-docs skill description

- Add requirement to use skill before conducting web searches
- Improve guidance for VS Code feature research and documentation

Aris Nguyen | 2025-12-11 | docs(issue): add documentation for Claude Skills and workspace automation

- Document VS Code 1.107 Claude Skills integration findings
- Detail personal vs project skills locations and usage patterns
- Document workspace automation solutions and PowerShell scripts
- Include VS Code tasks integration and unified command interface

Aris Nguyen | 2025-12-11 | build: add VS Code tasks for skill management automation

- Add 'Publish Skills to Personal (Copy)' task
- Add 'Publish Skills to Personal (Link)' task
- Add 'Check for Skill Updates' task
- Add 'Update Personal Skills' task
- Add 'Workspace Commands' task for command listing

Aris Nguyen | 2025-12-11 | devtool(script): add comprehensive skill management scripts

- Add publish-skills.ps1 for Copy/Link/Sync publishing methods
- Add run-command.ps1 for unified workspace command interface
- Add update-personal-skills.ps1 for skill update management
- Support selective skill publishing and force overwrite options

Aris Nguyen | 2025-12-11 | copilot(skill): add workspace configuration system

- Add copilot-workspace.json with unified command interface
- Define workspace components: skills, agents, instructions, prompts
- Include predefined commands for skills publishing and management
- Configure VS Code settings for Claude Skills integration

Aris Nguyen | 2025-12-11 | copilot(skill): add comprehensive skills factory documentation

- Add README.md with publishing methods and usage instructions
- Document copy/link/sync methods for skill distribution
- Include VS Code tasks integration and PowerShell script usage
- Provide complete workflow for skill development and publishing

Aris Nguyen | 2025-12-11 | copilot(skill): add project-specific types and verification checklist to git-committer skill

Added mandatory project-specific commit type mappings based on file paths and pre-commit verification checklist to ensure quality standards. Updated workflow to enforce correct type usage and atomic grouping.

Aris Nguyen | 2025-12-11 | copilot(skill): update git-committer skill documentation

Aris Nguyen | 2025-12-11 | chore(vscode): add tasks for automated issue metadata reindexing

Aris Nguyen | 2025-12-11 | docs(issues): remove deprecated copilot-skills design decision issue

Aris Nguyen | 2025-12-11 | copilot(skill): add vscode-docs skill for researching VS Code docs with TOC navigation

Aris Nguyen | 2025-12-11 | copilot(instruction): update orchestration guidelines for domain-specific skills

Aris Nguyen | 2025-12-11 | chore: remove old skills directory after move to .claude/skills

Aris Nguyen | 2025-12-11 | feat(copilot/skill): add vscode-docs skill

Aris Nguyen | 2025-12-11 | feat(copilot/skill): add vn-payroll skill

Aris Nguyen | 2025-12-11 | feat(copilot/skill): add skill-creator skill

Aris Nguyen | 2025-12-11 | feat(copilot/skill): add issue-writer skill

Aris Nguyen | 2025-12-11 | feat(copilot/skill): add git-committer skill

Aris Nguyen | 2025-12-11 | style: format issue index table with borders

Aris Nguyen | 2025-12-11 | chore: remove MCP configuration

Aris Nguyen | 2025-12-10 | copilot(instruction): update tool references in discovery and learning steps

- Change #tool:skills/list_available_skills to #tool:search/listDirectory
- Change #tool:skills/inspect_skill to #tool:search/readFile

This aligns the instructions with the actual tool usage in the system.

Aris Nguyen | 2025-12-10 | copilot(skill): add conventional commit type for skill changes

Add new 'copilot(skill)' type to the project-specific conventional commit types list, defining how to commit changes to skill definitions, implementations, and packaging under the skills/ directory.

Aris Nguyen | 2025-12-10 | chore(build): add gitignore for python cache directories

Add .gitignore file with pattern to ignore __pycache__ directories generated by Python bytecode compilation, keeping the repository clean from build artifacts.

Aris Nguyen | 2025-12-10 | feat(copilot/skill): add issue-writer skill directory and files

Aris Nguyen | 2025-12-10 | refactor: rename .docs/issue/ to .docs/issues/

Aris Nguyen | 2025-12-10 | refactor(copilot/skill): rename skills/vn_payroll/ to skills/vn-payroll/

Aris Nguyen | 2025-12-10 | refactor(copilot/prompt): move prompts from .github/prompts/ to prompts/

Aris Nguyen | 2025-12-10 | refactor(copilot/instruction): move instructions from .github/instructions/ to instructions/

Aris Nguyen | 2025-12-10 | refactor(copilot/custom-agent): move agents from .github/agents/ to agents/

Aris Nguyen | 2025-12-10 | feat(copilot/skill): add vn-payroll skill for calculating Vietnam personal income tax and social insurance

Aris Nguyen | 2025-12-10 | feat(copilot/skill): add skill-creator skill with references and scripts for creating new skills

Aris Nguyen | 2025-12-10 | feat(copilot/skill): add git-committer skill for analyzing changes and generating conventional commit messages

Aris Nguyen | 2025-12-10 | feat(copilot/skill): add packaged issue-writer skill for creating and drafting issue documents

Aris Nguyen | 2025-12-10 | feat(devtool/script): add PowerShell scripts for skills instructions copying, metadata extraction, and index updating


Aris Nguyen | 2025-12-10 | feat(copilot/instruction): add custom instructions for meta guidelines, PowerShell scripts, and skills orchestration

Aris Nguyen | 2025-12-10 | feat(copilot/custom-agent): add web-search agent for .NET 10 documentation and security best practices

Aris Nguyen | 2025-12-10 | feat: add vn_payroll skill for tax calculations

Aris Nguyen | 2025-12-10 | feat: add MCP server and configuration for skills orchestration

Aris Nguyen | 2025-12-10 | copilot(instruction): add instruction files for thought logging, meta, powershell, and skills

Aris Nguyen | 2025-12-10 | docs: add design decision document for Copilot Skills implementation

Aris Nguyen | 2025-12-10 | copilot(custom-agent): update metadata and types in issue-writer agent

Aris Nguyen | 2025-12-10 | init

