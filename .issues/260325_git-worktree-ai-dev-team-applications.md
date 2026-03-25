---
date: 2026-03-25
type: Research
severity: Medium
status: Proposed
---

# Research: Apply "Scaling Your AI Development Team with Git Worktrees" to this Copilot plugin workspace

## Objective

Distill the key ideas from Tamir Dresher’s blog post (2025-10-20) and map concrete opportunities for our repository's AI agent/plugin development workflow.

## Article synopsis

1. Parallel developer workspaces via `git worktree` avoids constant branch switching in consumer repo clones.
2. Each worktree can host a focused branch (feature, experiment, spike, hotfix) while preserving local environment, dependency causality, and path-based tools.
3. Worktree strategy removes friction for contextual tasks like review, QA, pair programming, and release readiness.
4. Recommended patterns include strict naming, automating worktree creation/removal, and git hooks to prevent cross-worktree contamination.
5. For large teams, worktrees support concurrent CI/release pipelines while reducing merge conflicts at workspace-level dependencies and buildup of unmanaged `node_modules` etc.

## Potential applications in this repository context

1. `agents/`, `skills/`, `plugins/`, `scripts/` development:
   - Run parallel feature branches in separate worktrees (e.g., `ralph-v2-improve-plugincache` vs `toolset-worktree-support`) without interrupting existing open VS Code workspace.
   - Keep crash/hotfix staging environments isolated from long-running investigations.

2. Harvesting from this repo’s existing plugin workflows:
   - Add an entry in `scripts/workspace/` (or docs) for an official `git-worktree` wrapper (create/list/clean) specialized for Copilot plugin branches.
   - Establish convention: `.worktrees/<branch>` or `.w` builder second-level folder for reproducible build artifacts per worktree.

3. CI + smoke tests adaptation:
   - `scripts/test/ralph-v2-cli-smoke.ps1` and other smoke drivers could accept an optionally provided worktree path to avoid temporarily checking out or copying large workspace for each run.
   - In GitHub workflows, multilayered checks can use `git worktree add` for parallel pipeline agents (especially for `plugins/cli` and `plugins/vscode`) executing in same runner VM.

4. Knowledge documentation and onboarding:
   - Add a short guide under `.docs/how-to/copilot/` or `.issues/` describing “AI workflow using git worktrees” with commands and 'do not do' guard rails.
   - Reflect this in `.github/workflows/` or `CONTRIBUTING.md` if available.

5. Risk controls and team coordination:
   - Recommend pre-commit hook or script in `scripts/publish/` to validate that hard-coded paths are not using a stale worktree root (e.g., `.copilot` absolute path assumption) and to preserve plugin artifact licensing.

## Proposed next steps

- [ ] Create an official `docs` page in `.docs/how-to/copilot/` or `.issues/` with sample commands and repository-specific patterns.
- [ ] Add an optional local helper script `scripts/workspace/git-worktree.ps1` to create/checkout/clean worktrees in this repo with branch templates.
- [ ] Run hands-on test for a dual-worktree patch scenario: create two branches with new skill and updated agent metadata; validate local `publish-skills` and `publish-plugins` side-by-side.
- [ ] Sync with the team on expectations for `git worktree` lifecycle (especially cleanup of locked worktrees that can prevent branch deletion).

## Self-critique

- Clarity: The issue explains the article, applies it to repository-specific components, and includes direct tangible tasks.
- Completeness: It covers conception, tooling, CI, docs, and coordination.
 - Relevance: Focused on this workspace’s existing plugin/agent development patterns and avoids generic advice.

## References

- Tamir Dresher, "Scaling Your AI Development Team with Git Worktrees", 2025-10-20: https://www.tamirdresher.com/blog/2025/10/20/scaling-your-ai-development-team-with-git-worktrees.html
- Existing workspace scripts and docs: `scripts/workspace/`, `scripts/publish/`, `.docs/`, `agents/`, `skills/`, `plugins/`.
