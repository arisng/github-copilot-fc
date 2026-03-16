---
date: 2026-03-15
type: Task
severity: Medium
status: Draft
---

# Task: Design workflow to track Copilot release issues via GitHub query

## Objective
Implement an automated workflow that regularly scans GitHub issues matching specific query parameters (e.g., milestone, label) to detect new Copilot releases and update this workspace accordingly. Start with the current query URL: https://github.com/Microsoft/vscode/issues?q=is%3Aissue%20is%3Aclosed%20milestone%3A1.112.0%20-label%3Atestplan-item&page=2

## Tasks
- [ ] Research GitHub issue query parameters and pagination to reliably locate Copilot release PRs/issues (milestone, label, repo filter, closed state).
- [ ] Prototype a script (Python/PowerShell) that fetches results from the GitHub Issues Search API or by scraping the provided `https://github.com/microsoft/vscode/issues?...` URL and extracts release identifiers (milestone/label + release date).
- [ ] Define a canonical output format (e.g., JSON or markdown) that can be consumed by other repo automation (e.g., docs update scripts, release notes, or workflow gating).
- [ ] Add a scheduled GitHub Actions workflow (or local cron helper) that runs the script regularly and commits/outputs results for review.
- [ ] Document the query URL, query parameters, and how to adjust them for future Copilot release branches.

## Acceptance Criteria
- [ ] The workflow can be triggered manually or on a schedule and successfully retrieves matching issues from GitHub using the stored query parameters.
- [ ] Results clearly identify the Copilot release milestone and associated PR/issue numbers, and are saved in a predictable location (e.g., `.github/release-notes/` or `.docs/`).
- [ ] The repo contains documentation describing how to update the query, how to run the workflow locally, and what the output means.
- [ ] The workflow is resilient to pagination and can handle at least the first 2 pages of results for the query.

## References
- GitHub issues query (example): https://github.com/microsoft/vscode/issues?q=is%3Aissue+is%3Aclosed+milestone%3A1.112.0+-label%3Atestplan-item
- Existing automation examples in this workspace (search for `GitHub Actions` or `scripts/` workflows).