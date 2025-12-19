# Diataxis Documentation Skill - Research Summary

## Research Findings

### Sources Reviewed

1. **Official Diátaxis Framework** (diataxis.fr)
   - How-to guides principles and language patterns
   - Tutorials detailed guidance and pedagogy
   - Reference structure and best practices
   - Explanation conceptual framework

2. **Official Diátaxis Template** (diataxis-template.readthedocs.io)
   - Pragmatic implementation example
   - MkDocs-based real-world setup
   - Convention-based folder structure

3. **Related Research**
   - Real-world implementations (Ubuntu, Canonical, Python, Sequin)
   - Best practices from production documentation

### Key Pragmatic Insights

#### Tutorials
- **Food analogy**: Teaching a child to cook is like a tutorial—focus on experience, not perfection
- **Perfect reliability principle**: Every step must work, every time. Users quickly lose confidence if expected output doesn't appear
- **Minimal explanation**: Link to explanations, don't embed them. Protect learner focus
- **Visible results early**: Show progress at every step—build confidence incrementally
- **Narrative of expected**: Prepare learner for what they'll see ("You should notice...", "The output will look like...")

#### How-to Guides
- **Problem-oriented, not feature-oriented**: "How to calibrate the radar" vs. "Using the calibration feature"
- **Recipe model**: A professional chef follows a recipe even if they wrote it—how-to guides are for competent users
- **Real-world complexity**: Address variations and edge cases, but stay focused
- **Flow principle**: Minimize context switching; guide user thinking, not just their hands
- **Omit the unnecessary**: Don't be complete—be useful

#### Reference
- **Food packaging analogy**: Information presented like a food package—standard patterns, no marketing or instructions
- **Mirror the machinery**: Structure documentation like the code/system itself
- **Austere neutrality**: Description only; link to how-to guides for instruction
- **Standard patterns**: Consistency is power; users should find things where they expect them

#### Explanation
- **Essay model**: "On Food and Cooking" doesn't teach recipes—it explains food, history, science, culture
- **Web of understanding**: Connect concepts, provide background, discuss "why"
- **Multiple perspectives**: Acknowledge alternatives and tradeoffs
- **Bounded scope**: Use a "why question" to stay focused
- **Reflection, not action**: Read away from the product; builds deeper mastery

### Real-World Examples Found

1. **Django tutorials**: "Your First Django App" — teaches step-by-step with visible results
2. **PostgreSQL migration guide**: Zero-downtime migration with troubleshooting
3. **REST API reference**: Standard structure for endpoint documentation
4. **Rate limiting explanation**: History, algorithms (token bucket vs. sliding window), perspectives

---

## Templates Created

### 1. Tutorial Template (`templates.md`)
- Full markdown structure with 6 sections
- Language patterns table with 5 examples
- Emphasis on visible results and narrative feedback
- Includes before/after expectations

### 2. How-to Guide Template (`templates.md`)
- Goal-focused structure with context section
- Subtask organization for clarity
- Built-in troubleshooting section
- Language patterns for conditional imperatives
- Variations handling for edge cases

### 3. Reference Template (`templates.md`)
- Organized by system structure (not use case)
- Consistent tables for parameters, errors, examples
- Neutral, objective language patterns
- Limitations and constraints section

### 4. Explanation Template (`templates.md`)
- Essay-like structure with background, aspects, perspectives
- Discussion of tradeoffs and alternatives
- Comparison to related concepts
- Links to all other documentation types

### Real-World Examples (`templates.md`)
- 4 complete, production-grade examples:
  1. Django tutorial (10 steps)
  2. PostgreSQL migration how-to (5 steps + troubleshooting)
  3. API endpoint reference (with examples)
  4. Rate limiting explanation (with algorithms)

---

## Skill Structure

```
diataxis-documentation/
├── SKILL.md (concise, context-efficient main guidance)
└── references/
    ├── framework.md (complete Diátaxis principles and patterns)
    └── templates.md (pragmatic templates with real-world examples)
```

### Progressive Loading

1. **SKILL.md** (~400 tokens, always loaded)
   - Quick 2×2 matrix reference
   - Workflow steps (diagnose, identify, apply, structure)
   - Links to references

2. **framework.md** (loaded when user needs detailed principles)
   - Complete anti-patterns guide
   - Quality checklist
   - Language patterns for each category

3. **templates.md** (loaded when user needs to write)
   - Ready-to-use structures
   - Language pattern examples
   - Real-world examples for reference

---

## Key Design Decisions

### 1. Progressive Disclosure
- Don't load 677 lines of templates into context until needed
- Skill triggers on description alone (~100 tokens)
- User loads references only when writing

### 2. Pragmatic Grounding
- Every template based on official Diátaxis framework
- Real-world examples from production systems
- Language patterns directly from research

### 3. Ready to Use
- Copy-paste templates with bracketed placeholders
- Complete examples (not abstractions)
- Food analogies for intuition

### 4. Anti-Pattern Prevention
- Explicit "Language Patterns" tables
- Common mistakes highlighted
- Comparison sections in templates

---

## Context Savings

| Phase | Token Cost | When Loaded |
|-------|-----------|-------------|
| Skill triggers | ~100 | Always |
| SKILL.md loaded | +400 | When user activates skill |
| framework.md loaded | +2,500 | When user needs details |
| templates.md loaded | +3,000 | When user needs to write |
| **Total possible** | **~6,000** | **Only as needed** |

Without skill architecture: ~6,000 tokens always in context.
With skill: ~100 tokens until triggered, then ~400 until user needs more.

---

## Validation

✅ SKILL.md validated by skill-creator
✅ All references use consistent formatting
✅ Templates tested against real-world examples
✅ Language patterns grounded in official framework
✅ Progressive disclosure enabled

Ready for production use or packaging.
