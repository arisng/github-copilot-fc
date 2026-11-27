---
name: diataxis-categorizer
description: Classify documentation files into domain-based sub-categories within Diátaxis top-level categories (tutorials, how-to, reference, explanation). Use when organizing wiki files into sub-folders like blazor-agui/, copilot/, sdk/ within a Diátaxis category, determining where a file belongs using the three-rule heuristic (keyword extraction → reuse check → create check → fallback), reclassifying research/ staging files into standard categories, or performing batch wiki reorganization. Supplements the `diataxis` skill which handles top-level classification — this skill adds sub-category depth.
metadata: 
  version: 1.0.0
  author: arisng
---

# Diátaxis Categorizer — Domain-Based Sub-Category Classification

This skill adds **sub-category classification** to the Diátaxis framework. While the `diataxis` skill determines *which top-level category* a file belongs in (tutorials, how-to, reference, explanation), this skill determines *which domain sub-folder* within that category.

## Relationship to `diataxis` Skill

| Concern | `diataxis` skill | `diataxis-categorizer` skill |
|---------|------------------|------------------------------|
| Top-level classification | ✅ Owns | ❌ Defers |
| Sub-category placement | ❌ Not covered | ✅ Owns |
| Templates & language patterns | ✅ Owns | ❌ Defers |
| Domain taxonomy | ❌ Not covered | ✅ Owns |
| Batch reorganization | ❌ Not covered | ✅ Owns |

## Domain Taxonomy Convention

Sub-categories are **domain-based folders** inside each Diátaxis top-level category:

```text
docs/
├── tutorials/
│   └── blazor-agui/          # ≥3 blazor-agui-related tutorials
├── how-to/
│   ├── blazor-agui/          # ≥3 blazor-agui-related how-to guides
│   └── copilot/              # ≥3 copilot-related how-to guides
├── reference/
│   ├── blazor-agui/          # ≥3 blazor-agui-related reference docs
│   └── copilot/              # ≥3 copilot-related reference docs
├── explanation/
│   ├── blazor-agui/          # ≥3 blazor-agui-related explanations
│   └── copilot/              # ≥3 copilot-related explanations
└── index.md
```

**Naming convention**: `<category>/<domain>/filename.md`

- Domain folder names: lowercase kebab-case (e.g., `blazor-agui`, `copilot`, `sdk`)
- Each domain sub-folder is independent per category — `reference/blazor-agui/` can exist without `tutorials/blazor-agui/`
- Cross-domain files (spanning multiple domains) remain at the category root

### Known Domains

Primary domains for this workspace:

| Domain | Keyword patterns | Description |
|--------|-----------------|-------------|
| `blazor-agui` | blazor, ag-ui, blueprint, razor, agentic | Blazor AG-UI / agentic UI framework |
| `copilot` | copilot, copilot-fc, extension, agent, custom instruction | GitHub Copilot customization |
| `sdk` | sdk, copilot-sdk, acp, client | Copilot SDK / Agent Communication Protocol |

Domains are extensible — new domains emerge when files naturally cluster around a keyword.

## Three-Rule Heuristic

Given a file path and its content, determine the target sub-category:

### Rule 1 — Keyword Extraction

Extract the primary domain keyword from the file using this priority chain:

1. **Filename prefix**: `copilot-cli-help.md` → `copilot`
2. **Frontmatter `category` field**: `category: copilot` → `copilot`
3. **H1 title scan**: `# Copilot CLI Session Topology` → `copilot`
4. **Content body scan**: Count domain keyword occurrences; dominant domain wins (must be >2× runner-up)

If no single domain dominates, the file is **cross-domain** → stays at category root.

### Rule 2 — Reuse Check

If an existing sub-category folder matches the extracted domain keyword:

- **Recommend placing the file there**
- Example: `reference/blazor-agui/` exists and file domain is `blazor-agui` → target is `reference/blazor-agui/filename.md`

### Rule 3 — Create Check (≥3 Threshold)

If no matching sub-category folder exists:

- Count files at the category root (and in the current batch) that share the same domain keyword
- If **≥3 files** share the domain → **recommend creating the sub-category** and moving all matching files
- If **<3 files** → **fallback**: leave at category root (flat)

The ≥3 threshold prevents premature sub-folder creation for one-off files.

### Fallback

File stays at the category root when:

- No single domain keyword dominates (cross-domain)
- Fewer than 3 peers share the domain and no existing sub-folder matches
- Domain extraction yields no confident result

### Decision Flowchart

```text
Input: file path + metadata
         │
    ┌────▼────┐
    │ Rule 1: │
    │ Extract  │
    │ keyword  │
    └────┬────┘
         │
    keyword found?
    ├── NO ──────────────────────────────► FALLBACK: category root
    │
    YES
    │
    ┌────▼────┐
    │ Rule 2: │
    │ Reuse   │
    │ check   │
    └────┬────┘
         │
    sub-folder exists?
    ├── YES ─────────────────────────────► TARGET: <category>/<domain>/file.md
    │
    NO
    │
    ┌────▼────┐
    │ Rule 3: │
    │ Create  │
    │ check   │
    └────┬────┘
         │
    ≥3 peers share domain?
    ├── YES ─────────────────────────────► CREATE sub-folder + move all peers
    │
    NO ──────────────────────────────────► FALLBACK: category root
```

## Research Staging Convention

The `research/` folder is a **staging area**, not a permanent 5th Diátaxis category.

### Rules

- New research files land in `research/` during active investigation
- The categorizer treats `research/` files as **candidates for reclassification**
- Mature research files must be reclassified into a standard category within 1-2 iterations
- When reclassifying: apply the same three-rule heuristic to determine both the category (using `diataxis` skill) and the sub-category (using this skill)

### Maturity Signals

A research file is ready for reclassification when:

- It has a clear single-purpose alignment (tutorial, how-to, reference, or explanation)
- It no longer references in-progress investigation or speculative content
- It can stand alone without session-specific context

## Batch Reorganization Workflow

For retroactive reorganization of an existing `docs/` wiki:

### Steps

1. **Scan**: Enumerate all `.md` files in a target category (e.g., `reference/`)
2. **Classify**: Apply the three-rule heuristic to each file
3. **Manifest**: Output a JSON manifest of proposed moves:

```json
{
  "category": "reference",
  "scan_date": "2026-03-01",
  "proposed_moves": [
    {
      "source": "reference/agentic-ux-spec-research.md",
      "target": "reference/blazor-agui/agentic-ux-spec-research.md",
      "domain": "blazor-agui",
      "action": "create_and_place",
      "reason": "5 files share domain 'blazor-agui' — creating sub-folder"
    },
    {
      "source": "reference/copilot-cli-help.md",
      "target": "reference/copilot/copilot-cli-help.md",
      "domain": "copilot",
      "action": "create_and_place",
      "reason": "4 files share domain 'copilot' — creating sub-folder"
    }
  ],
  "staying": [
    {
      "file": "reference/urls.md",
      "domain": null,
      "reason": "Cross-domain — no single domain dominates"
    }
  ]
}
```

1. **Review**: Human reviews the manifest and approves/rejects individual moves
2. **Execute**: Script executes approved moves (create folders, `mv` files)
3. **Regenerate**: Run `python3 skills/diataxis/scripts/generate_index.py` to update `index.md`

### Batch Scan Command (Pseudocode)

```text
For each category in [tutorials, how-to, reference, explanation]:
  files = list .md files at category root (not in sub-folders)
  domain_counts = {}
  For each file in files:
    domain = extract_domain(file)  # Rule 1
    domain_counts[domain] += 1
  For each file in files:
    domain = extract_domain(file)
    if sub-folder exists for domain:      # Rule 2
      propose move → <category>/<domain>/file
    elif domain_counts[domain] >= 3:      # Rule 3
      propose create + move → <category>/<domain>/file
    else:
      mark as staying                     # Fallback
  Output manifest JSON
```
