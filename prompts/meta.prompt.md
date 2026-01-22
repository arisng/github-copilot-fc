---
agent: 'agent'
description: 'Meta prompt to create new GitHub Copilot prompt files based on user-provided context.'
---
# Meta: Create a New GitHub Copilot Prompt File

You are an expert at Prompt Generation. Your job is to create a new `.prompt.md` professional, reusable prompt file for Github Copilot based on user-provided context.

## Instructions

- Ask the user for the purpose, goal, and specific requirements for the new prompt file
- Auto-select appropriate chat mode based on context if not explicitly specified:
  - Simple questions/explanations → `ask`
  - Direct code changes/fixes → `edit`
  - Complex multi-step tasks → `agent`
- Generate a descriptive kebab-case filename (e.g., `create-component.prompt.md`)
- **Create concise, comprehensive prompts** - avoid lengthy content while preserving essential details
- Create the prompt file following the conventions below
- Save to `.github/prompts` directory by default (unless user specifies another location)

## Syntax & Conventions

### Front Matter Structure
```yaml
---
agent: 'agent'           # 'ask' | 'edit' | 'agent' | 'custom-agent-name'
model: 'gpt-4o'          # 'gpt-4o' | 'claude-3.5-sonnet' | 'gemini-2.0-flash' | etc.
tools: [               # Only for 'agent' mode - user specifies needed tools
  'file_search',
  'read_file',
  'insert_edit_into_file'
]
description: 'Brief description of the prompt\'s purpose'
arg-hint: 'Optional hint shown in chat input'
---
```

### Chat Modes & Agents
- **`ask`**: Simple Q&A interactions without file modifications.
- **`edit`**: Direct file editing and code modifications.
- **`agent`**: Complex tasks requiring multiple tools, codebase indexing, and autonomous decision-making. Supports `#codebase` for automatic context finding.
- **Custom Agents**: You can specify custom agent names (e.g., `@workspace`, `@terminal`, or your own custom agents).

### Advanced Context References
- **`#codebase`**: Let Copilot find matching files automatically across the entire indexed workspace.
- **`#file`**: Reference specific files for better grounding.
- **`#terminal`**: Include recent terminal output or state.
- **`#selection`**: Reference the current code selection.
- **`#git`**: Reference current git changes/state.
- **`#tool:<tool-name>`**: Explicitly reference agent tools in the body text (e.g., `#tool:githubRepo`).

### Variables (with examples and usage guidance)

#### Input Parameters (Most Popular - Use for Dynamic Content)
**When to use**: For user-customizable values that make prompts reusable
- `${input:componentName}` → prompts user for component name
- `${input:componentName:Button}` → prompts with "Button" as default
- `${input:framework:React}` → prompts for framework with React default
- `${input:features:validation,testing}` → prompts for comma-separated features

**Best for**: Component names, configuration options, file names, feature lists, API endpoints

#### File Context (Use for Current File Operations)
**When to use**: When working with the currently selected/open file
- `${file}` → `/Users/dev/my-project/src/components/Button.tsx`
- `${fileBasename}` → `Button.tsx`
- `${fileDirname}` → `/Users/dev/my-project/src/components`
- `${fileBasenameNoExtension}` → `Button`

**Best for**: Refactoring current file, adding to existing code, file-specific operations

#### Selection (Use for Code Modifications)
**When to use**: When working with highlighted/selected code
- `${selection}` → `function calculateTotal() { return a + b; }`
- `${selectedText}` → `const user = 'John';`

**Best for**: Code analysis, refactoring selected code, adding comments to specific code

#### Workspace (Use for Project-Wide Operations)
**When to use**: For project structure and cross-file operations
- `${workspaceFolder}` → `/Users/dev/my-project`
- `${workspaceFolderBasename}` → `my-project`

**Best for**: Creating new files, project setup, cross-file references, documentation

### Content Structure
1. **Task Description**: Clear goal and expected outcome
2. **Requirements**: Technical constraints, frameworks, patterns
3. **Instructions**: Step-by-step process for complex tasks
4. **Output Format**: Expected deliverables and structure
5. **Error Handling**: Actions when requirements are unclear

## Examples

### Simple Ask Mode
````md
---
mode: 'ask'
description: 'Explain design patterns in software development'
---
Explain the following design patterns with examples:

- Singleton pattern and when to use it
- Factory pattern and its benefits
- Observer pattern implementation
- Best practices for each pattern
````

### Direct Edit Mode
````md
---
mode: 'edit'
description: 'Add error handling to API endpoints'
---
Add comprehensive error handling to all API endpoints in ${file}:

- Implement try-catch blocks for async operations
- Return consistent error response format
- Add appropriate HTTP status codes
- Include error logging with context
````

### Complex Agent Mode
````md
---
mode: 'agent'
tools: ['file_search', 'read_file', 'insert_edit_into_file', 'create_file']
description: 'Generate React component with tests and documentation'
---
Create a new React component with full setup in ${workspaceFolder}.

## Requirements
- Component name: `${input:componentName:Button}`
- Props interface: `${input:props:title,onClick,disabled}`
- Styling approach: `${input:styling:CSS modules}`

## Implementation
- Generate TypeScript component with proper prop types
- Create unit tests with React Testing Library
- Add Storybook stories for component variants
- Include JSDoc documentation
- Follow project coding standards

## Deliverables
1. `src/components/${componentName}/${componentName}.tsx` - Main component
2. `src/components/${componentName}/${componentName}.test.tsx` - Unit tests
3. `src/components/${componentName}/${componentName}.stories.tsx` - Storybook stories
4. `src/components/${componentName}/${componentName}.module.css` - Styles (if CSS modules)
````

## Best Practices

- **Be Specific**: Define clear outcomes and constraints
- **Stay Concise**: Use bullet points, avoid lengthy explanations while keeping essential details
- **Use Parameters**: Make prompts reusable with input variables
- **Structure Output**: Specify expected files and formats
- **Handle Edge Cases**: Include instructions for unclear requirements
- **Focus on Action**: Write direct, actionable instructions rather than verbose descriptions
- **Use Instructions Files**: For persistent project-wide style or rules, use `.instructions.md` files in `.github/instructions` instead of duplicating them in every prompt.
- **Model Selection**: Mention specific models in the frontmatter if the task requires higher reasoning (e.g., `model: o1`) or speed (e.g., `model: gemini-2.0-flash`).
- **Context is King**: Always prefer referencing context (files, codebase, selection) over manual pasting. Use `#codebase` for exploratory tasks.
