---
date: 2026-03-15
type: Feature Plan
severity: Medium
status: Proposed
---

# Simplify `tools/` folder structure and improve `tools/inventory.md` scannability

## Goal
Make the `tools/` directory easier to navigate and maintain by removing legacy/unused subfolders and converting the primary tools inventory (`tools/inventory.md`) from a dense table into a more scannable, hierarchy-friendly format. The inventory must remain the single source of truth (SSOT) for which runtime tools and namespaces should be included when building custom agents.

## Requirements
- [ ] Remove or archive the following folders from `tools/` unless they are actively used by any build/publish tooling or documentation workflows:
  - `tools/cli`
  - `tools/github-copilot`
  - `tools/templates`
- [ ] Update `tools/inventory.md` so it is easy for humans to scan and understand quickly (flat list / sectioned format) while preserving the full set of information currently encoded in the table.
- [ ] Ensure the inventory remains a complete SSOT for all tool namespaces used by the workspace (core built-in tools, MCP namespaces, runtime-specialized tools, and any custom helper tools).
- [ ] Add ephemeral guidance for maintaining the inventory, e.g., how to add a new tool entry, where to correlate with runtime toolset JSON/YAML, and how to verify correctness.

## Proposed Implementation
- Move or delete the unused `tools/cli`, `tools/github-copilot`, and `tools/templates` directories after confirming they are not referenced in scripts, docs, or build processes.
- Replace the markdown table in `tools/inventory.md` with a sectioned list format (e.g., headings by category/type), including: tool id, category, description, runtime aliases (CLI / VS Code / GitHub Copilot), default behavior, and any important notes.
- Keep the existing `## Purpose` section and add a short “How to use this inventory” section with recommendations for agent authors.
- Add a “Source of truth” note that points to this file and any runtime toolset JSON/YAML definitions that should be kept in sync.

## Risks & Considerations
- Deleting unused directories may break tooling if any scripts implicitly depend on them; perform a workspace-wide search for references before removing.
- Changing the inventory format may require updating any automation or docs that parse or link to the table format (if any exist). Verify there are no consumers expecting the markdown table layout.
- The inventory must remain authoritative for both built-in tools and custom MCP namespaces; avoid losing detail that helps configure tool allowlists for custom agents.

## Acceptance Criteria
- [ ] `tools/inventory.md` is updated to a scannable flattened format, with all tools previously listed still represented.
- [ ] The `tools/cli`, `tools/github-copilot`, and `tools/templates` directories are removed or clearly archived with a note explaining why.
- [ ] No active build scripts or documentation reference the removed folders (or they are updated to point to the new inventory structure).
- [ ] This issue is properly indexed in `.issues/index.md` by running the metadata extraction script if needed.
