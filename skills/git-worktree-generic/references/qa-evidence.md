# QA Evidence & Binary Artifact Preservation

> Guidance for preserving gitignored binary artifacts from worktree sessions before cleanup.
> Load this file when a worktree contains QA evidence that must survive removal.

---

## Overview

Worktree sessions often produce gitignored artifacts (screenshots, videos, compiled binaries, test reports, log files) that are not tracked by git. These artifacts are lost when the worktree is removed unless explicitly copied elsewhere.

---

## Preservation Strategy

### Tracked files

Files committed in the worktree survive through the merge — no extra step needed.

### Gitignored binary artifacts

Before removing a worktree, copy gitignored media to a persistent location:

```bash
# From the primary repo, copy evidence from worktree
cp -r ../<repo>.worktrees/<branch-as-folder>/evidence/* ./evidence/
```

### Suggested evidence directory

Adopt a consistent relative path for QA evidence (e.g., `evidence/` or `qa/`) at the repo root. If everyone uses the same convention, the copy command becomes predictable:

```bash
# Standard convention: evidence/ at repo root
cp -r ../<repo>.worktrees/feature-250715-login-redesign/evidence/* ./evidence/
```

### CI/CD integration

Binary files are typically gitignored. Use your project's artifact management or CI system to upload them permanently:

- **GitHub Actions**: Use `actions/upload-artifact` to store screenshots/build outputs
- **Azure DevOps**: Use `PublishBuildArtifacts` task
- **Local archive**: Copy to a shared network drive or cloud storage

> Git worktrees cannot automate binary artifact preservation — it requires human or CI intervention.
