# Usage Examples and Workflows

## Example Queries

### GitHub Copilot Questions
- "How do I set up custom instructions for GitHub Copilot?"
- "What are the best practices for prompt engineering with Copilot?"
- "How do I create a custom agent for my project?"
- "Can Copilot help with debugging this error?"

### VS Code Feature Questions
- "How do I set up remote development with SSH?"
- "What's the best way to configure debugging for a Node.js app?"
- "How do I create custom tasks and launch configurations?"
- "How do I set up a dev container for my project?"

### Configuration Questions
- "How do I configure VS Code settings for a team?"
- "What extensions should I install for React development?"
- "How do I set up workspace-specific settings?"

## Research Workflow Steps

### 1. Query Analysis
- Identify the core VS Code feature or Copilot capability being asked about
- Determine if this requires official documentation research

### 2. Freshness Check
- Open `https://code.visualstudio.com/updates` to see the current stable version
- If `assets/toc.md` is older than the latest major release, regenerate it: `python3 scripts/parse_toc.py`
- For customization topics (instructions, prompt files, skills, agents), assume fast-moving status and verify the live page

### 3. Documentation Navigation
- Read `assets/toc.md` to locate relevant sections
- Identify 2-3 most relevant documentation pages
- Fall back to `https://code.visualstudio.com/llms.txt` when the TOC doesn't cover the topic

### 4. Content Retrieval
- Fetch pages with the `.md` suffix (e.g. `https://code.visualstudio.com/docs/agent-customization/prompt-files.md`) for clean Markdown
- Focus on official Microsoft documentation URLs
- Retrieve related pages for comprehensive coverage

### 5. Answer Grounding
- Base responses on retrieved documentation content
- Cite specific URLs and version information
- Include practical examples from official docs
- Note any version-specific limitations or requirements

## Tool Usage Patterns

### When to Use Web Fetching
- Need detailed feature explanations
- Looking for step-by-step guides
- Checking for recent updates or changes
- Verifying configuration options

### When to Use TOC Navigation
- Understanding documentation structure
- Finding related topics
- Planning comprehensive research
- Identifying knowledge gaps

### When to Update TOC
- TOC seems outdated (check the microsoft/vscode-docs repo for recent changes)
- New major VS Code release
- A link in `assets/toc.md` returns 404
- User reports missing documentation sections

## Quality Assurance

### Answer Validation
- Ensure information comes from official sources
- Check version compatibility
- Include working URLs and examples
- Note any prerequisites or limitations

### Currency Checks
- Verify release notes for recent changes
- Check for breaking changes and deprecations (e.g. harness lifecycle)
- Update TOC if structure has changed significantly