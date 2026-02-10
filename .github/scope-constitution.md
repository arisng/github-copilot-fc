# Commit Scope Constitution

Last Updated: 2026-02-10

## Purpose

This constitution defines the approved scopes for atomic commits in the GitHub Copilot FC repository, ensuring consistency and clarity in commit history. Scopes are derived from the repository's artifact-based structure, where changes are organized around customization types (agents, instructions, prompts, skills, toolsets) and supporting infrastructure (scripts, documentation).

## Repository Structure

The repository follows an artifact-based organization:
- `agents/` - Custom agent definitions
- `instructions/` - Copilot instruction files
- `prompts/` - Prompt templates
- `skills/` - Skill definitions and implementations
- `toolsets/` - Toolset configurations
- `scripts/` - Automation and utility scripts
- `.docs/` - Documentation following Diátaxis framework
- `src/` - Source code and prototypes

## Scope Naming Conventions

- Use kebab-case (lowercase with hyphens)
- Prefer singular nouns (e.g., `agent` not `agents`)
- Base scopes on repository structure and artifact types
- Keep scope names concise but descriptive
- Avoid generic scopes like `misc` or `other`

## Approved Scopes by Commit Type

### `feat`

New features or functionality additions.

- `agent`: Changes to agent definitions and configurations
- `instruction`: Changes to instruction files
- `prompt`: Changes to prompt templates
- `skill`: Changes to skill definitions and implementations
- `toolset`: Changes to toolset configurations
- `script`: Changes to automation scripts

### `fix`

Bug fixes and corrections.

- `agent`: Bug fixes in agent definitions
- `instruction`: Corrections in instruction files
- `prompt`: Fixes in prompt templates
- `skill`: Bug fixes in skill implementations
- `toolset`: Fixes in toolset configurations
- `script`: Corrections in automation scripts

### `docs`

Documentation changes.

- `readme`: Changes to README and main documentation
- `agent`: Documentation for agents
- `instruction`: Documentation for instructions
- `prompt`: Documentation for prompts
- `skill`: Documentation for skills
- `toolset`: Documentation for toolsets
- `script`: Documentation for scripts

### `style`

Code style and formatting changes (non-functional).

- `agent`: Style changes in agent files
- `instruction`: Formatting in instruction files
- `prompt`: Style updates in prompts
- `skill`: Code style in skills
- `toolset`: Formatting in toolsets
- `script`: Style changes in scripts

### `refactor`

Code refactoring without changing functionality.

- `agent`: Refactoring agent code
- `instruction`: Restructuring instruction files
- `prompt`: Refactoring prompt templates
- `skill`: Code refactoring in skills
- `toolset`: Restructuring toolsets
- `script`: Refactoring automation scripts

### `test`

Adding or modifying tests.

- `agent`: Tests for agents
- `instruction`: Tests for instructions
- `prompt`: Tests for prompts
- `skill`: Tests for skills
- `toolset`: Tests for toolsets
- `script`: Tests for scripts

### `chore`

Maintenance tasks, build changes, etc.

- `build`: Build system changes
- `ci`: Continuous integration updates
- `deps`: Dependency updates
- `config`: Configuration file changes
- `script`: Maintenance scripts

## Scope Selection Guidelines

1. **Match Repository Structure**: Choose scopes that correspond to the affected directories/artifacts
2. **Be Specific**: Use the most specific scope that applies to the change
3. **Consistency**: Follow established patterns from existing commits
4. **Atomic Commits**: Ensure the scope reflects the primary focus of the atomic change

## Amendment Process

1. **Proposal**: Create an issue describing the proposed new scope or change
2. **Analysis**: Review against repository structure and historical usage
3. **Approval**: Merge approved changes to this constitution
4. **Documentation**: Update amendment history below

## Amendment History

### 2026-02-10 - Initial Constitution

**Changes:**
- Established initial scopes based on repository structure
- Defined naming conventions and selection guidelines

**Rationale:**
First constitution for the GitHub Copilot FC repository to establish consistent commit scoping practices.</content>
<parameter name="filePath">c:\Users\DuyAnh\Workplace\CodeF\github-copilot-fc\.github\scope-constitution.md