---
date: 2026-03-15
type: Feature Plan
severity: High
status: Draft
---

# Ralph-v2 CLI Plugin Test Plan (Publish Gate)

## Goal
Ensure the `ralph-v2` Copilot CLI plugin is reliably testable and guarded by a fast, automatable test suite that validates **core runtime behaviors**, **agent orchestration flows**, **session persistence**, and **release gating** prior to publishing a new bundle.

## Scope
- **Runtime target**: GitHub Copilot CLI only (CLI plugin runtime).
- **Primary focus**: `ralph-v2` orchestrator + its delegated agents (planner, questioner, executor, reviewer, librarian) in an end-to-end session.
- **Excluded (for now)**: VS Code runtime, UI/extension expectations, editor-specific tool behavior.

## Requirements
- [ ] A deterministic, repeatable test harness that can run on CI (no interactive prompts).
- [ ] Tests cover the major agent workflows (session init, planning, execution, review, commit, cleanup) at a high level.
- [ ] Test harness must be fast: prefer small, targeted assertions over full open-ended runs; avoid waiting for slow LLM generations where possible.
- [ ] Support explicit configuration of the LLM model (e.g., `gpt-5.2`, `claude-sonnet-4.5`, `gpt-5.1-codex`) so we can pin to a stable model during CI.
- [ ] Clearly define what counts as a pass/fail (exit code, output markers, expected session state files).
- [ ] Ensure the test harness can validate that the correct plugin bundle is installed and that agent module versions match the published version.

## Test Plan (Test Cases)

### 1) Basic CLI Invocation Sanity
- [ ] Verify `copilot --version` works and returns exit code 0.
- [ ] Verify the plugin is discoverable: `copilot --agent "Ralph-v2-Orchestrator-CLI" --prompt "ping" --silent --allow-all --model gpt-5.2` returns without errors (a minimal smoke test).

### 2) Orchestrator Session Lifecycle
- [ ] Create a new session directory (e.g., `.ralph-sessions/test-<timestamp>/`).
- [ ] Invoke orchestrator in `INITIALIZE` mode and assert it writes an expected `session.yaml` and `plan.md`/`progress.md` scaffolding.
- [ ] Verify the orchestrator correctly delegates to `Planner` via the task tool (look for the `task(...)` invocation in logs or output markers).
- [ ] Confirm the session state advances to the next phase (e.g., `MODE: EXECUTE` or a specific `next_step` marker).

### 3) Planner/Questioner/Executor Basic Flows
- [ ] Run a short planner flow: start a planning iteration and assert it writes a valid task list with at least one task.
- [ ] Run a questioner prompt flow (e.g., ask a simple question) and assert the result is stored in the session folder as a file.
- [ ] Run an executor iteration with a minimal task (e.g., create a file, run a trivial shell command) and assert the effect happened.

### 4) Review & Commit
- [ ] Run the reviewer in `TASK_REVIEW` mode for a sample task and ensure it produces a review file (e.g., `task-*/review.md`).
- [ ] Run a simulated commit path (or the equivalent “approve” action) and verify the session reaches a terminal state.

### 5) Tool Compatibility & Permissions
- [ ] Validate that the agent can use its expected tools without interactive permission prompts (use `--allow-all-tools` + `--allow-all-paths` or explicit allow flags).
- [ ] Validate that `bash` commands execute and their output can be captured by the agent (e.g., `echo test` through a small task).

### 6) Versioning & Bundle Integrity
- [ ] Confirm that `ralph-v2` plugin bundle version matches the agent metadata version (metadata.version) and the plugin JSON version.
- [ ] Validate that the on-disk installed plugin manifest (in `~/.copilot/installed-plugins/_direct/ralph-v2` or similar) matches the expected bundle.

## Proposed Implementation Approach (Fast, Programmatic, CI-Friendly)

### 1) Harness Strategy
- Build a lightweight test harness script (`scripts/test/ralph-v2-cli-smoke.ps1` or `scripts/test/ralph-v2-cli-smoke.py`) that:
  - Installs or ensures the `ralph-v2` plugin bundle is available (via `copilot plugin install <bundle>` if needed).
  - Runs `copilot` in headless mode with predictable environment variables.
  - Drives the orchestrator via `copilot --agent "Ralph-v2-Orchestrator-CLI" -p "<directive>" --allow-all --silent --model <MODEL>`.
  - Parses output and/or checks session files in `.ralph-sessions/` to assert correct behavior.
  - Returns a non-zero exit code on any assertion failure.

### 2) Recommended CLI Flags for Determinism
- `--allow-all` or explicit `--allow-tool`/`--allow-url` to avoid interactive prompts.
- `--silent` to simplify output parsing.
- `--model <model>` to pin the LLM.
- `--no-auto-update` to prevent unexpected CLI upgrades during CI.
- `--config-dir <tmpdir>` to isolate from user configuration.

### 3) Test Isolation and Speed
- Use a dedicated temporary session directory (e.g., `./.ralph-sessions/test-<uuid>/`) and delete it after tests.
- Use small prompts that exercise deterministic logic (e.g., “Initialize a session with a single trivial task: create a file called test.txt with contents `hello`”).
- Prefer checks that observe file artifacts (created files, session metadata) rather than full LLM output validation.
- Limit the number of full LLM turns; e.g., treat each CLI invocation as one “turn” where the agent completes a single mode operation.

### 4) CI Integration
- Add a CI job (GitHub Actions, etc.) that:
  1. Checks out the repo.
  2. Installs prerequisites (Copilot CLI, required model credentials / API keys, if applicable).
  3. Builds or installs the local `ralph-v2` plugin bundle (using existing publish/build scripts).
  4. Runs the smoke test harness script.
  5. Reports pass/fail based on exit code.

## Risks & Considerations
- **LLM nondeterminism**: Even with a fixed model, output can vary; tests should avoid brittle text matching and instead validate side effects (files, metadata flags, exit codes).
- **Dependency on external services**: If the test requires network access (LLM calls, MCP servers), CI may be flaky. Consider caching or using a locally hosted LLM endpoint if available.
- **Plugin install path changes**: Different Copilot CLI versions or OS environments may locate installed plugins differently. Tests must detect the correct install path.
- **Tool permission prompts**: If `--allow-all` isn't set, tests can hang waiting for user approval. CI must run with non-interactive mode and proper allow flags.
- **Performance**: Running full multi-agent sessions can be slow; ensure each test is scoped to a minimal “happy path” scenario and exits quickly.

---

## Next Steps
1. Review and refine the test case list with stakeholders to ensure coverage of all critical ralph-v2 features.
2. Decide on a concrete harness implementation language (PowerShell vs Python) based on existing repo tooling and CI platform.
3. Implement the harness script and add it to CI gating for the plugin publish workflow.
