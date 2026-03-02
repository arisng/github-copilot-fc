---
category: how-to
source_session: "260227-144634"
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-4 spec and report — wiring categorizer into Librarian PROMOTE"
extracted_at: "2026-03-01T12:35:28+07:00"
promoted: true
promoted_at: "2026-03-01T12:43:56+07:00"
---

# How to Integrate Sub-Category Resolution into Knowledge Promotion

## Goal

Add intelligent sub-category placement to the knowledge promotion workflow so that promoted files are automatically placed in domain-based sub-folders (e.g., `reference/ralph/`) rather than always landing at the category root.

## Prerequisites

- A categorizer skill or heuristic that classifies files into domain-based sub-categories (see the `diataxis-categorizer` skill)
- A promotion workflow with a merge step that determines where files land in the target wiki

## Procedure

### Step 1: Identify the Insertion Point

The sub-category resolution step is inserted **after** the content transformation step (which ensures self-containment) and **before** files are marked as promoted. This positioning is critical:

- **After content transformation**: The file is already cleaned of ephemeral references, so the categorizer sees the final body text
- **Before marking promoted**: The target path can still be adjusted before the file is written to its final location

### Step 2: Implement the Resolution Logic

For each file being promoted, apply the categorizer's three-rule heuristic:

1. **Extract domain keyword** from the file using a priority chain: filename prefix → frontmatter → H1 title → body content scan (with >2× frequency threshold for body-based classification)

2. **Reuse check**: If an existing sub-category folder in the target wiki matches the extracted domain → adjust the target path to `<category>/<domain>/filename.md`

3. **Create check** (≥3 threshold): If no matching sub-folder exists, count how many peers in the promotion batch or at the category root share the same domain. If ≥3 → create the sub-folder, place the file, and retroactively move the peers

4. **Fallback**: If the domain is ambiguous, below threshold, or cross-domain → keep the file at the category root

### Step 3: Adjust Target Paths

After classification:
- Promotion targets shift from `<category>/filename.md` to `<category>/<domain>/filename.md` where sub-categorization is recommended
- Files that triggered folder creation (Rule 3) may require moving existing files already at the category root into the new sub-folder

### Step 4: Add Audit Logging

For each file, log the sub-category decision in the promotion report:
- File path
- Extracted domain keyword
- Action taken (place in existing folder, create new folder, or keep at root)
- Reason for the decision

This log provides an audit trail for understanding why files ended up where they did.

### Step 5: Update Index Generation

Ensure the wiki index generator supports recursive scanning of sub-category directories:
- Use recursive file discovery (e.g., `pathlib.Path.rglob('*.md')` or `os.walk()`) instead of flat directory listing
- Generate nested index sections with sub-category headings under each Diátaxis category
- Maintain backward compatibility for files that remain at the category root

## Skill Reference

The classification logic is encapsulated in the `diataxis-categorizer` skill — a pure classification function that takes a file path and metadata, and returns a recommended target path. The promotion workflow invokes it inline; the skill has no side effects.
