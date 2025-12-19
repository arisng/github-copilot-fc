# Diataxis Documentation Skill - Refactored Structure

## Overview

The skill has been reorganized to use **focused, individual template files** instead of a monolithic templates file. This enables better progressive disclosure and faster access to the specific template you need.

## New File Structure

```
diataxis-documentation/
├── SKILL.md (main skill definition, ~400 tokens)
├── RESEARCH-SUMMARY.md (research methodology and insights)
└── references/
    ├── framework.md (detailed principles, ~2.5k tokens)
    ├── tutorial-template.md (tutorial-specific guidance)
    ├── how-to-guide-template.md (how-to-specific guidance)
    ├── reference-template.md (reference-specific guidance)
    ├── explanation-template.md (explanation-specific guidance)
    └── examples.md (4 real-world complete examples)
```

## Key Improvements

### 1. Focused Template Files

Each template is now standalone and focused:

- **[tutorial-template.md](references/tutorial-template.md)** — Structure, language patterns, and principles for tutorials only
- **[how-to-guide-template.md](references/how-to-guide-template.md)** — Structure, language patterns, and principles for how-to guides only
- **[reference-template.md](references/reference-template.md)** — Structure, language patterns, and principles for reference only
- **[explanation-template.md](references/explanation-template.md)** — Structure, language patterns, and principles for explanations only

### 2. Direct References in SKILL.md

The main SKILL.md now directly references the right template:

```markdown
### 3. Choose the Right Template

When writing documentation, use the appropriate template:

- **Writing a tutorial?** See [tutorial-template.md](references/tutorial-template.md)
- **Writing a how-to guide?** See [how-to-guide-template.md](references/how-to-guide-template.md)
- **Writing reference?** See [reference-template.md](references/reference-template.md)
- **Writing explanation?** See [explanation-template.md](references/explanation-template.md)
- **Want real-world examples?** See [examples.md](references/examples.md)
```

### 3. Unified Examples File

All 4 real-world examples now live in one place ([examples.md](references/examples.md)):
1. Django tutorial
2. PostgreSQL zero-downtime migration
3. REST API endpoint reference
4. API rate limiting explanation

Each template links to its corresponding example for clarity.

## Context Efficiency

| File | Size | When Loaded |
|------|------|------------|
| SKILL.md | ~400 tokens | When skill triggers |
| tutorial-template.md | ~600 tokens | When user clicks link |
| how-to-guide-template.md | ~550 tokens | When user clicks link |
| reference-template.md | ~550 tokens | When user clicks link |
| explanation-template.md | ~500 tokens | When user clicks link |
| framework.md | ~2,500 tokens | When user needs detailed principles |
| examples.md | ~2,000 tokens | When user needs concrete examples |

**Total context overhead**: Only load what you need. Maximum is ~7,500 tokens for all references, but users typically load only the specific template they need (~500-600 tokens).

## User Workflows

### Writing a Tutorial
1. Open SKILL.md
2. Identify that you're writing a tutorial
3. Click [tutorial-template.md](references/tutorial-template.md)
4. Copy the structure, adapt placeholders
5. Refer to Django example in [examples.md](references/examples.md) for reference

### Writing a How-to Guide
1. Open SKILL.md
2. Identify that you're writing a how-to guide
3. Click [how-to-guide-template.md](references/how-to-guide-template.md)
4. Copy the structure, adapt placeholders
5. Refer to PostgreSQL migration example in [examples.md](references/examples.md)

### Auditing Documentation
1. Open SKILL.md
2. Use the "Diagnose" and "Identify Problems" sections
3. Check [framework.md](references/framework.md) for anti-patterns
4. Review [examples.md](references/examples.md) for what good looks like

### Learning the Framework
1. Start with SKILL.md (quick overview)
2. Read [framework.md](references/framework.md) (principles and patterns)
3. Review [examples.md](references/examples.md) (real-world reference)
4. Write documentation using the appropriate template

## Validation

✅ Skill validated by skill-creator  
✅ All template links verified  
✅ Examples link back to their templates  
✅ Progressive disclosure architecture maintained  
✅ Context-efficient (load only what you need)

## Next Steps

The skill is ready for:
- Publishing to VS Code's synced user settings
- Packaging as a .skill file for distribution
- Integration into documentation workflows
- Teaching Diátaxis framework adoption
