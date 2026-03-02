---
category: how-to
source_session: 260302-142754
source_iteration: 1
source_artifacts:
  - "Iteration 1 task-13 report (validation script creation)"
  - "Iteration 1 task-14 report (validation run)"
extracted_at: 2026-03-02T20:11:56+07:00
promoted: true
promoted_at: 2026-03-02T20:22:26+07:00
---

# How to Validate OpenSpec Specs

Step-by-step procedure for running the full validation suite against OpenSpec domain specifications. Covers both the built-in OpenSpec CLI validator and 3 custom scripts that cover gaps the CLI does not address.

## When to Use

Run this validation suite:
- After authoring or modifying any spec under `openspec/specs/`
- After a batch of spec changes (e.g., scenario gap-fills, terminology fixes)
- Before committing spec changes to ensure no regressions

## Prerequisites

- Node.js installed (for `npx openspec`)
- PowerShell 7+ (`pwsh`) available
- Working directory is the workspace root

## Procedure

### Step 1 — Run OpenSpec Structural Validation

```powershell
npx openspec validate --all
```

**Expected output**: 0 CRITICAL issues. ERROR-level issues about SHOULD/MAY keywords are a known CLI limitation — ignore them if specs intentionally use RFC 2119 tiered keywords.

**If CRITICAL issues appear**: Fix missing `## Purpose` sections or malformed frontmatter before proceeding.

### Step 2 — Scan for Runtime-Specific Terminology

```powershell
pwsh -NoProfile -File scripts/openspec/validate-runtime-leaks.ps1
```

**What it checks**: Scans all spec files against a 5-category blocklist (Editor/Runtime, OS/Shell, Tool Names, File Formats, Path/Filesystem) plus semantic patterns like "writes to" or "directory structure".

**Expected output**: 0 blocklist violations, 0 semantic warnings. Exit code 0 = PASS.

**If violations appear**: Replace flagged terms with runtime-agnostic equivalents. Common substitutions:
- "Terminal" → "Final" (when referring to state, not a console)
- "search" → "information retrieval"
- "directory structure" → "organizational structure"
- "writes to" → "updates" or "persists to"
- "write authority" → "mutation authority"

### Step 3 — Validate Cross-Domain References

```powershell
pwsh -NoProfile -File scripts/openspec/validate-cross-refs.ps1
```

**What it checks**: Extracts all domain-prefixed requirement IDs (e.g., SES-001, SIG-012) from their defining specs, then scans all specs for references to those IDs. Reports any reference to an ID that doesn't exist.

**Expected output**: 0 dangling references. Exit code 0 = PASS.

**If dangling references appear**: Either the referenced requirement was renamed/removed, or there's a typo in the reference. Fix the reference or add the missing requirement.

### Step 4 — Audit RFC 2119 Keywords and Scenario Coverage

```powershell
pwsh -NoProfile -File scripts/openspec/validate-rfc2119.ps1
```

**What it checks**: Parses requirement blocks by heading structure and verifies each requirement contains at least one RFC 2119 keyword (MUST, SHALL, SHOULD, MAY) and has at least one scenario referencing it via a `**Validates**:` line.
