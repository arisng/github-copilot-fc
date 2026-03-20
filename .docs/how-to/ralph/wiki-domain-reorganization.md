---
category: how-to
source_session: "260227-144634"
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-5 spec and report — workspace wiki reorganization"
extracted_at: "2026-03-01T12:35:28+07:00"
promoted: true
promoted_at: "2026-03-01T12:43:56+07:00"
---

# How to Reorganize a Diátaxis Wiki into Domain-Based Sub-Categories

## Goal

Retroactively reorganize a flat Diátaxis wiki into domain-based sub-category folders (e.g., `reference/ralph/`, `reference/copilot/shared/`, `reference/copilot/cli/`) using a measured, script-assisted workflow that minimizes broken links and ensures human oversight.

## When to Use

- The wiki has accumulated enough files that navigating flat category directories is cumbersome
- Multiple distinct domains are intermixed within the same category (e.g., 11 reference files covering both Ralph agent docs and Copilot ecosystem docs)
- A `research/` or staging folder contains mature files that should be reclassified into standard Diátaxis categories

## Procedure

### Phase 1: Generate a Reorganization Manifest

Apply the domain categorizer heuristic to all files in the wiki:

1. For each file, extract the primary domain keyword (filename prefix, frontmatter, H1 title, or body content scan)
2. Group files by domain within each Diátaxis category
3. Apply the ≥3-file threshold — only propose a sub-category when 3 or more files share a domain, except for the explicit Copilot runtime buckets (`sdk`, `cli`, `vscode`, `github-web`, `github-mobile`, `shared`)
4. Generate a JSON manifest of proposed moves:

```json
[
  {"source": "reference/copilot-cli-help.md", "target": "reference/copilot/cli/copilot-cli-help.md", "reason": "runtime: cli"},
  {"source": "reference/self-critique-checklist.md", "target": "reference/ralph/self-critique-checklist.md", "reason": "domain: ralph"}
]
```

5. Cross-domain files (matching no single domain) stay at the category root
6. Categories with too few files for sub-categorization remain flat (e.g., a tutorials directory with only one file)

### Phase 2: Reclassify Staging Content

If a `research/` or staging folder exists:

1. Evaluate each file against Diátaxis categories — is it a tutorial, how-to, reference, or explanation?
2. Identify the domain keyword for each file
3. Add reclassification moves to the manifest
4. After reclassification, the staging folder should contain only a README documenting its purpose
5. Rename files with spaces to kebab-case during the move

### Phase 3: Human Review

Present the manifest for human review before execution. This checkpoint:
- Prevents incorrect domain classification
- Allows override of threshold decisions
- Catches edge cases (e.g., a file that appears to be one domain but serves another)

### Phase 4: Execute the Reorganization

1. Create sub-category directories as needed
2. Move files to their new locations
3. Fix cross-references — update all internal markdown links to reflect new paths:
   - Relative link depth changes (e.g., `../../agents/` → `../../../agents/`)
   - Same-wiki cross-references (e.g., `../reference/foo.md` → `../reference/ralph/foo.md`)
4. Validate that no broken links remain

### Phase 5: Update the Index Generator

If the wiki uses an automated index generator:

1. Switch from flat directory listing (`os.listdir`) to recursive scanning (`pathlib.Path.iterdir()` with sub-directory handling, or `os.walk()`)
2. Generate nested index output with sub-category headings:

```markdown
## Reference

### Copilot
- [Copilot CLI Help](reference/copilot/cli/copilot-cli-help.md)

### Ralph
- [Self-Critique Checklist](reference/ralph/self-critique-checklist.md)
```

3. Files at the category root (no sub-folder) appear before sub-category sections
4. Exclude staging folders from the standard index

### Phase 6: Regenerate the Index

Run the updated generator to produce a fresh `index.md` reflecting the new structure. Validate that all links in the index resolve to existing files.

## Expected Outcome

| Category | Sub-categories | Root files |
|----------|---------------|------------|
