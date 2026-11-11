# Scope Constitution Playbook

Disclosed reference for `git-commit-scope-constitution`: worked scenarios, maintenance
cadence, and script output structure. Load when the SKILL.md pointer sends you here.

## Maintenance Schedule

**Weekly:**
- Extract scopes from past week (`--since "1 week ago"`)
- Analyze any new folders/modules added to repository
- Compare with constitution
- Flag anomalies or new scopes
- Update constitution if patterns warrant

**Monthly:**
- Review scope usage patterns
- Analyze repository structure changes (refactoring, new modules)
- Identify consolidation opportunities
- Update naming conventions if needed

**Quarterly:**
- Comprehensive constitution review
- Major amendments and restructuring based on repository evolution
- Scope lifecycle management (deprecations/retirements)

## Script Output Formats

**Output Formats:**
- `markdown`: Structured inventory with summary statistics and organized scope lists
- `json`: Machine-readable structure for tooling

**Inventory Structure:**
```markdown
# Scopes Inventory

**Repository:** [name]
**Last Updated:** [date]
**Source:** Git commit history analysis

## Summary
- Total Commit Types: N
- Total Unique Scopes: N
- Analysis Period: [timeframe]

## Scopes by Commit Type
### `type`
- scope-1
- scope-2

## Notes
[Additional context]
```


## Examples

### Example 1: Creating Initial Constitution with Repository Analysis

```bash
# Step 1: Extract historical scopes
python skills/git-commit-scope-constitution/scripts/extract_scopes.py \
  --output .github/git-scope-inventory.md

# Step 2: Analyze repository structure
# List top-level directories
Repository: my-web-app/
  src/
    components/     → UI components
    services/       → Business logic services
    utils/          → Utility functions
  tests/            → Test files
  scripts/          → Build/automation scripts
  docs/             → Documentation
  .github/          → GitHub workflows

# Step 3: Map structure to scopes
From structure analysis:
- components/ → scope: "components" or specific component names
- services/auth/ → scope: "auth"
- services/billing/ → scope: "billing"
- scripts/ → scope: "script" or "build"
- docs/ → scope: "docs"

From git history (.github/git-scope-inventory.md):
- feat(components): Used 15 times
- feat(auth): Used 8 times
- feat(billing): Used 12 times
- fix(api): Used 6 times
- chore(deps): Used 20 times

# Step 4: Create constitution
# Combine structure-based and history-based scopes
# Document in .github/git-scope-constitution.md with clear definitions
```

### Example 2: Weekly Refinement

```bash
# Extract last week's scopes
python skills/git-commit-scope-constitution/scripts/extract_scopes.py \
  --since "1 week ago" --format markdown

# Check for new folders/modules
# Found: New folder src/services/notifications/

# Review against constitution
# Found new scope: feat(notifications) used 3 times
# Found folder: services/notifications/ (new module)

# Update constitution
# Add to appropriate section:
# - `notifications`: Notification service and delivery system
```

### Example 3: Scope Selection for Existing Codebase

```
Scenario: Modifying skills/git-atomic-commit/SKILL.md

Step 1: Check commit type mapping
  → File pattern: skills/* → Type: agent

Step 2: Consult constitution under Type: agent
  → Available scopes: skill, instruction

Step 3: Select appropriate scope
  → Change affects a skill → Use scope: `skill`
  → Specific skill name goes in the subject

Result: agent(skill): improve pre-commit validation checklist for git-atomic-commit
```

### Example 4: Scope Selection with Repository Structure Analysis

```
Scenario: Adding new authentication feature

Step 1: Analyze repository structure
  → services/auth/ exists (authentication module)
  → New files: services/auth/oauth.ts, services/auth/jwt.ts

Step 2: Check commit type
  → File pattern: services/* → feat (no project-specific type)

Step 3: Check constitution for feat scopes
  → .github/git-scope-constitution.md shows:
    - auth: Authentication and authorization
    - billing: Payment processing
    - dashboard: Dashboard features

Step 4: Select scope based on structure
  → Files in services/auth/ → Use scope: auth
  → Aligns with both structure and constitution

Result: feat(auth): implement OAuth 2.0 authentication flow
```

### Example 5: Constitutional Amendment

```markdown
## Amendment History

### 2026-02-04 - Amendment #12

**Changes:**
- Deprecated `ai` extended type in favor of `agent`
- Consolidated instance-level scopes (e.g., `pdf`, `diataxis`) into
  category-level scope `skill` under `agent` type
- Adopted "category-level scope" principle: scopes represent artifact
  categories, not specific instances
  
**Rationale:**
`agent(skill)` immediately tells the reader an agent skill was changed.
The subject line provides the specific skill name, enabling efficient
git log scanning without opening the diff.

**Migration Notes:**
Existing commits with old `ai(*)` scopes remain in history.
Use `agent(skill)` for all future skill-related commits.
```
