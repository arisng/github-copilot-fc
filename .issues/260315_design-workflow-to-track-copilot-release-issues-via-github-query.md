---
date: 2026-03-15
type: Task
severity: Medium
status: Draft
---

# Task: Design workflow to track Copilot release issues via GitHub query

## Objective
Implement an automated workflow that regularly scans GitHub issues and release sources to detect new Copilot releases and update this workspace accordingly.

Start with the current query URL:
https://github.com/Microsoft/vscode/issues?q=is%3Aissue%20is%3Aclosed%20milestone%3A1.112.0%20-label%3Atestplan-item&page=2

As part of this effort, curate a list of authoritative Copilot release/update sources across runtimes (VS Code, CLI, GitHub.com, GitHub Actions, GitHub Mobile) and ensure the workflow can also scan the Copilot CLI releases feed:
https://github.com/github/copilot-cli/releases

## Authoritative release/update source URLs (draft)
Below is a working draft of the initial set of URLs that should be tracked. This list is expected to grow as we discover more authoritative runtime-specific release feeds.

| Runtime / Scope | Description | URL | Notes |
|---|---|---|---|
| VS Code extension release issues | Copilot release issues in the VS Code repo (milestone-based release tracking). | https://github.com/Microsoft/vscode/issues?q=is%3Aissue+is%3Aclosed+milestone%3A1.112.0+-label%3Atestplan-item | Supports milestone + label filtering; page-based pagination |
| CLI releases | Copilot CLI GitHub Releases feed (tags & assets). | https://github.com/github/copilot-cli/releases | Use GitHub Releases API for structured data |
| SDK releases | Copilot SDK repository releases (packages, tags). | https://github.com/github/copilot-sdk/releases | Track SDK updates / compatibility notes |

## Tasks
- [ ] Research GitHub issue query parameters and pagination to reliably locate Copilot release PRs/issues (milestone, label, repo filter, closed state).
- [ ] Identify authoritative Copilot release/update sources across runtimes (VS Code, CLI, GitHub.com, GitHub Actions, GitHub Mobile) and maintain a curated list of URLs that can be used by the workflow.
- [ ] Prototype a script (Python/PowerShell) that fetches results from the GitHub Issues Search API or by scraping the provided `https://github.com/microsoft/vscode/issues?...` URL and extracts release identifiers (milestone/label + release date).
- [ ] Extend the prototype to also scan the Copilot CLI releases page (https://github.com/github/copilot-cli/releases) via the GitHub Releases API and incorporate those findings into the output.
- [ ] Define a canonical output format (e.g., JSON or markdown) that can be consumed by other repo automation (e.g., docs update scripts, release notes, or workflow gating).
- [ ] Add a scheduled GitHub Actions workflow (or local cron helper) that runs the script regularly and commits/outputs results for review.
- [ ] Document the query URL, query parameters, and how to adjust them for future Copilot release branches.

## Acceptance Criteria
- [ ] The workflow can be triggered manually or on a schedule and successfully retrieves matching issues from GitHub using the stored query parameters.
- [ ] The workflow also retrieves Copilot CLI release metadata from the GitHub Releases API (https://github.com/github/copilot-cli/releases) and integrates it with the issue-based release findings.
- [ ] A curated list of authoritative Copilot release/update URLs (across runtimes: VS Code, CLI, GitHub.com, GitHub Actions, GitHub Mobile) is maintained in the repo and referenced by the workflow.
- [ ] Results clearly identify the Copilot release milestone and associated PR/issue numbers (and/or release tag/asset links for CLI), and are saved in a predictable location (e.g., `.github/release-notes/` or `.docs/`).
- [ ] The repo contains documentation describing how to update the query/URLs, how to run the workflow locally, and what the output means.
- [ ] The workflow is resilient to pagination and can handle at least the first 2 pages of results for the query.

## References
- GitHub issues query (example): https://github.com/microsoft/vscode/issues?q=is%3Aissue+is%3Aclosed+milestone%3A1.112.0+-label%3Atestplan-item
