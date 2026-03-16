# Test Scripts

## Ralph v2 CLI smoke / publish gate

`scripts/test/ralph-v2-cli-smoke.ps1` is the deterministic smoke harness for the Ralph-v2 CLI plugin.

What it checks:

1. Builds the Ralph CLI bundle with the existing `scripts/publish/build-plugins.ps1` helper.
2. Installs the built bundle into an isolated Copilot CLI config directory with the supported flow:
   - `copilot plugin install <local_plugin_path>`
3. Verifies plugin discovery with `copilot plugin list`.
4. Detects the installed plugin manifest under the Copilot config cache without hard-coding one cache path contract.
5. Runs a real non-interactive Ralph orchestrator smoke scenario and records whether the Ralph state machine produced reviewable session artifacts for planner, questioner, executor, reviewer, and librarian coverage.
6. Proves the expected Ralph custom subagents were actually invoked by parsing the captured Copilot CLI logs for runtime-visible custom-agent names (for example `ralph-v2-beta/ralph-v2-planner-CLI-beta`), rather than relying only on artifact shape.
7. Invokes the built bundle with `--plugin-dir <bundle>` and the runtime-visible qualified agent name (`<plugin-name>/<agent-file-stem>`) while still separately validating the supported install/discovery flow.

What it now produces for human review on every run:

1. A Markdown report with an execution checklist grouped around overall, build, install/discovery, orchestration, planner, questioner, executor, reviewer, librarian, and cleanup checkpoints.
2. Concrete evidence artifacts for the exact run (commands used, command outputs, manifests, summaries, workflow snapshots, copied workspace artifacts, subagent-provenance summaries, captured Copilot CLI logs, and cleanup record).
3. Machine-readable JSON files (`summary.json`, `inputs.json`, `test-cases.json`) that match the human report.

### Review artifacts

By default, each run writes review artifacts under:

`scripts/test/.artifacts/ralph-v2-cli-smoke/run-<timestamp>-<pid>/`

Key files:

- `report.md`: human-readable checklist with checkpoint details and links to evidence.
- `summary.json`: complete machine-readable execution summary.
- `inputs.json`: effective test inputs/config used for the run.
- `test-cases.json`: structured checkpoint status list.
- `evidence/`: concrete captured artifacts such as `commands.json`, `copilot --version`, built/installed plugin manifests, `copilot plugin install` output, `copilot plugin list` output, orchestrator stdout/stderr, copied workflow/log snapshots, `subagent-provenance.json`, and cleanup data.

Use `-ReportPath` when you want the review markdown written to a specific location. The sibling JSON/evidence artifacts will be written next to that report path.
Large text evidence is preserved verbatim unless it becomes very large; in that case the artifact is truncated with clear notes and original/stored lengths recorded in the report and JSON summary.

### How to read a Ralph smoke report

For most reviews, read the bundle in this order:

1. `report.md`
   - Start here.
   - Read these sections in order:
     - `Run overview`
     - `Execution checklist`
     - `Ralph workflow path`
     - `Ralph role coverage`
     - `Custom subagent provenance`
   - This is the fastest way to answer: did the run pass, which checkpoint failed, and what evidence should I inspect next?
2. `summary.json`
   - Use this when you need the full machine-readable state behind the report.
   - It is the best place to confirm:
     - final run status/stage
     - exact command lines
     - resolved layout detection
     - raw orchestrator stdout/stderr
     - `unexpected_builtin_agent_delegation`
     - the structured `workflow`, `role_coverage`, and `subagent_provenance` objects
3. `test-cases.json`
   - Use this for checkpoint-by-checkpoint evidence arrays without reading the full summary.
4. `inputs.json`
   - Use this when you need to know the exact prompt, model, timeout, cleanup flags, and effective paths used for the run.
5. `evidence\...`
   - Use this only for drill-down proof after the report points you at a specific checkpoint.

If you only want the minimum human review path, use:

1. `report.md` to find the important section
2. the linked file under `evidence\...`
3. `summary.json` only if you need the raw structured context behind the report

#### How to interpret the main report sections

- `Execution checklist`
  - This is the harness verdict ledger.
  - Each row is one smoke checkpoint with a status, a short explanation, and direct evidence links.
  - If a run fails, start with the first failed row before reading anything else.
- `Ralph workflow path`
  - This shows state-machine coverage rather than a full transcript.
  - Use it to verify the workflow progressed through planning, execution/review, knowledge, and completion.
- `Ralph role coverage`
  - This shows whether each Ralph role produced the expected artifact family.
  - Think of it as "artifact ownership + durable evidence," not just "did a file exist."
- `Custom subagent provenance`
  - This is the strongest proof that the workflow used Ralph custom agents rather than only leaving similarly shaped artifacts.
  - It is driven from captured Copilot CLI logs and should be the first stop when reviewing delegation concerns.

#### Best evidence files for common review questions

- Did the orchestrator finish?
  - `evidence\agent-invocation.json`
  - `evidence\agent.stdout.txt`
  - `evidence\workflow\working-directory\metadata.yaml`
- Did the harness actually use Ralph custom subagents?
  - `evidence\subagent-provenance.json`
  - `evidence\workflow\logs\process-*.log`
- Did the run avoid built-in Copilot bootstrap/task delegation?
  - `summary.json` or `evidence\workflow-summary.json` under `unexpected_builtin_agent_delegation`
  - `evidence\workflow\logs\process-*.log` for corroboration
- Where are the preserved workflow artifacts after cleanup?
  - `evidence\workflow\working-directory\...`

#### Easy-to-miss details

- The authoritative artifact layout may be **root-level** (`metadata.yaml` + `iterations\1\...`) instead of session-local under `.ralph-sessions\<session-id>\iterations\...`.
- The temp working directory is usually deleted at the end of the run; the durable copy for review is the snapshot under `evidence\workflow\working-directory\...`.
- Librarian coverage may be satisfied either by promoted knowledge artifacts or by an explicit, durable skip/cancel outcome recorded in iteration artifacts, depending on the scenario.
- A successful reviewer phase does not guarantee a git commit happened; review evidence is authoritative even when commit status is intentionally skipped.

### How the smoke harness works

At a high level, `scripts/test/ralph-v2-cli-smoke.ps1` does five things:

1. creates an isolated smoke workspace
2. builds and installs the Ralph CLI bundle
3. runs one real non-interactive Ralph orchestrator session
4. validates workflow artifacts, role coverage, and custom-subagent provenance
5. writes a durable review bundle and cleans up temporary directories

#### End-to-end flow

1. **Resolve tools and inputs**
   - Resolves the `copilot` and `git` commands.
   - Accepts overrides for channel, model, reasoning effort, config/log/work directories, report path, session id, prompt, timeouts, and cleanup retention flags.
2. **Create the isolated fixture**
   - If explicit paths are not provided, the harness creates temporary config/log/work directories.
   - It seeds a disposable repo/worktree with:
     - `README.md` containing the seed bullet
     - `.docs\README.md`
     - `.gitignore`
     - `.ralph-sessions\<session-id>\signals\{inputs,acks,processed}`
     - root-level `iterations\1\{tasks,questions,reports,tests,feedbacks,knowledge}`
   - The fixture is prepared so Ralph can route through its normal workflow without needing a built-in bootstrap task agent.
3. **Build, install, and discover the plugin**
   - Imports build helpers from `scripts/publish/build-plugins.ps1`.
   - Builds the local CLI bundle.
   - Verifies bundle contract details such as name, version, runtime, README presence, and bundled Ralph agents.
   - Installs the bundle with the supported flow:
     - `copilot plugin install --config-dir <isolated-dir> <buildDir>`
   - Confirms discovery with `copilot plugin list`.
   - Detects installed manifests dynamically instead of assuming one fixed Copilot cache layout.
4. **Run the real orchestrator turn**
   - Invokes the built bundle directly with `--plugin-dir <buildDir>`.
   - Resolves the runtime-visible qualified orchestrator agent name from the built bundle.
   - Runs a narrow prompt that asks Ralph to:
     - perform exactly one tiny README documentation change
     - route through planner/questioner/executor/reviewer/librarian
     - keep normal Ralph artifacts
     - finish by printing only:
       - `SESSION_PATH: <path>`
       - `FINAL_STATE: <state>`
5. **Validate the Ralph workflow**
   - Requires a successful exit code and a final `FINAL_STATE: COMPLETE`.
   - Detects whether the authoritative Ralph layout ended up session-local or root-level.
   - Validates durable artifacts for:
     - orchestrator
     - planner
     - questioner
     - executor
     - reviewer
     - librarian
   - Parses captured Copilot CLI logs to prove the expected Ralph custom agents actually ran.
   - Fails if the workflow delegated to the built-in Copilot `task` agent.
6. **Write the review bundle and clean up**
   - Writes:
     - `report.md`
     - `summary.json`
     - `inputs.json`
     - `test-cases.json`
     - `evidence\...`
   - Snapshots the workflow workspace and Copilot logs into `evidence\...` before cleanup.
   - Removes temp directories unless `-KeepConfigDir`, `-KeepLogDir`, or `-KeepWorkingDirectory` is set.
   - Even on failure, it still writes the review bundle before exiting non-zero.

### Common usage

```powershell
# Default beta publish-gate smoke
pwsh -NoProfile -File scripts/test/ralph-v2-cli-smoke.ps1

# Stable bundle smoke with an explicit model
pwsh -NoProfile -File scripts/test/ralph-v2-cli-smoke.ps1 -Channel stable -Model gpt-5.2

# Build/install/discovery validation only (skip the live Ralph workflow turn)
pwsh -NoProfile -File scripts/test/ralph-v2-cli-smoke.ps1 -SkipAgentInvocation

# Write the human-review markdown report to an explicit path
pwsh -NoProfile -File scripts/test/ralph-v2-cli-smoke.ps1 -Channel stable -ReportPath scripts/test/.artifacts/ralph-v2-cli-smoke/latest/report.md
```

### Smoke scenario contract

The default prompt is intentionally narrow:

- one disposable workspace
- one tiny documentation task that appends a single bullet to `README.md`
- no product-file changes beyond that `README.md` update; required Ralph artifacts (`progress.md`, task files, questions, reports, metadata, knowledge skip markers) are allowed
- bounded planning/research/execution/review/knowledge flow
- explicit permission for the knowledge step to record a skip instead of expanding scope when there is nothing reusable
- the fixture precreates the target session directory/signals so the orchestrator can route directly into Ralph custom agents instead of falling back to a built-in bootstrap task agent

The report should show:

- the exact prompt and effective paths used
- the qualified orchestrator agent name that was invoked
- explicit Copilot CLI log evidence that the expected Ralph custom subagents were invoked for planner, questioner, executor, reviewer, and librarian
- copied evidence for the generated workflow artifacts
- a checklist row for each Ralph role/state bucket

### CI notes

- The harness is non-interactive by design.
- The orchestrator invocation step pins `--model`, `--reasoning-effort`, `--config-dir`, `--log-dir`, `--plugin-dir`, `--no-auto-update`, `--no-custom-instructions`, `--disable-builtin-mcps`, and `--allow-all`.
- Current Copilot CLI builds may still materialize locally installed plugins under `~/.copilot/installed-plugins/_direct/...` even when `--config-dir` is set. The harness checks both the requested config root and the default Copilot cache root.
- Current Copilot CLI builds expose plugin agents via qualified names such as `ralph-v2/ralph-v2-orchestrator-CLI`; the harness resolves that runtime name from the built bundle instead of assuming the frontmatter `name` is directly invokable.
- The harness now treats custom-subagent provenance as a first-class gate: role coverage only passes when the expected Ralph custom agent appears in the captured Copilot CLI logs and the corresponding role-owned artifacts are present.
- The harness also fails if the isolated workflow logs show a built-in Copilot `task` agent was delegated during the Ralph workflow; the smoke fixture is prepared so planner/questioner/executor/reviewer/librarian coverage should come from Ralph custom agents only.
- If the environment is not already authenticated, provide `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, or `GITHUB_TOKEN`, or run `copilot login` before invoking the full smoke test.
- Use `-KeepConfigDir`, `-KeepLogDir`, or `-KeepWorkingDirectory` when you want to inspect isolated state after a failure.
- The review artifacts are always written before exit, so a human can inspect the markdown checklist, commands used, and evidence bundle even when the harness fails.

### Workspace command

```powershell
pwsh -NoProfile -File scripts/workspace/run-command.ps1 tests:ralph-cli-smoke
```
