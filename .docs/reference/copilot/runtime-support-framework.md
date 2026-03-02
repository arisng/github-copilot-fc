# Runtime Support Framework

Reference document mapping workspace artifact primitives to runtime targets with automated publishing status, destination paths, delivery mechanisms, and shareability assessments.

## Support Matrix

The matrix below maps **6 artifact primitives** (rows) across **4 runtime targets** (columns). Each cell uses a three-state verdict:

| Verdict     | Meaning                                                                       |
| ----------- | ----------------------------------------------------------------------------- |
| ✅ Automated | Runtime supports the artifact AND a publish script implements the target      |
| ⚠️ Manual    | Runtime supports the artifact BUT no publish script implements the target yet |
| ❌ N/A       | Runtime does not support this artifact type                                   |

> **Note:** VS Code Stable and VS Code Insiders share identical behavior for all artifact types. They differ only in install path (`%APPDATA%/Code/` vs `%APPDATA%/Code - Insiders/`). Both are covered by the "VS Code" column. Publish scripts target both paths simultaneously.

### Primary Matrix

| Artifact Type    | VS Code (Win) | copilot-cli (Win) | copilot-cli (WSL) | Future Placeholder |
| :--------------- | :-----------: | :---------------: | :---------------: | :----------------: |
| **Agents**       |  ✅ Automated  |    ✅ Automated    |    ✅ Automated    |         —          |
| **Instructions** |  ✅ Automated  |     ⚠️ Manual      |     ⚠️ Manual      |         —          |
| **Skills**       |  ✅ Automated  |    ✅ Automated    |    ✅ Automated    |         —          |
| **Hooks**        |  ✅ Automated  |   ✅ Automated¹    |     ⚠️ Manual²     |         —          |
| **Prompts**      |  ✅ Automated  |       ❌ N/A       |       ❌ N/A       |         —          |
| **Toolsets**     |  ✅ Automated  |       ❌ N/A       |       ❌ N/A       |         —          |

¹ Hooks are published to `.github/hooks/` (repo-scoped), which copilot-cli discovers when invoked from the repo root. No separate `~/.copilot/` path needed.
² WSL copilot-cli discovers hooks from CWD. If the repo is cloned inside WSL, `.github/hooks/` works via the same repo-scoped mechanism. No dedicated WSL publish target exists yet for user-level hook paths.

## Publish Destinations and Delivery Mechanisms

### Agents

| Runtime            | Destination Path                                    | Delivery                                |
| :----------------- | :-------------------------------------------------- | :-------------------------------------- |
| VS Code (Stable)   | `%APPDATA%/Code/User/prompts/*.agent.md`            | Direct file copy                        |
| VS Code (Insiders) | `%APPDATA%/Code - Insiders/User/prompts/*.agent.md` | Direct file copy                        |
| copilot-cli (Win)  | `%USERPROFILE%/.copilot/agents/*.agent.md`          | Direct file copy                        |
| copilot-cli (WSL)  | `~/.copilot/agents/*.agent.md`                      | WSL cross-copy (`wsl bash -c "cp ..."`) |

**Script:** `scripts/publish/publish-agents.ps1` — targets all four destinations. Uses `-SkipWSL` opt-out. Flat file copy (no recursive directory structure at destination).

### Instructions

| Runtime            | Destination Path                                           | Delivery                                                                                                                                                         |
| :----------------- | :--------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| VS Code (Stable)   | `%APPDATA%/Code/User/prompts/*.instructions.md`            | Direct file copy                                                                                                                                                 |
| VS Code (Insiders) | `%APPDATA%/Code - Insiders/User/prompts/*.instructions.md` | Direct file copy                                                                                                                                                 |
| copilot-cli (Win)  | `%USERPROFILE%/.copilot/copilot-instructions.md`           | Concatenation of all `.instructions.md` files into single file (Mode Concat) **OR** directory-based via `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` env var (Mode EnvVar) |
| copilot-cli (WSL)  | `~/.copilot/copilot-instructions.md`                       | Same dual-mode as Win, delivered via WSL cross-copy                                                                                                              |

**Script:** `scripts/publish/publish-instructions.ps1` — currently targets VS Code only. CLI and WSL targets are **not yet implemented** (⚠️ Manual). Planned redesign adds `-Mode Concat` (default) and `-Mode EnvVar` parameters.

**Delivery mechanism detail:**
- **Mode Concat** (default): All workspace `.instructions.md` files are concatenated into a single `copilot-instructions.md`, stripping `applyTo` frontmatter (lost in translation — all instructions apply globally).
- **Mode EnvVar**: Individual `.instructions.md` files are copied to a structured directory, and `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` environment variable is set to point to it. This preserves `applyTo` semantics but requires one-time env var setup.

### Skills

| Runtime            | Destination Path                                            | Delivery                                   |
| :----------------- | :---------------------------------------------------------- | :----------------------------------------- |
| VS Code (Stable)   | Loaded from `%USERPROFILE%/.copilot/skills/<name>/SKILL.md` | Direct directory copy (recursive)          |
| VS Code (Insiders) | Same as Stable                                              | Same personal path                         |
| copilot-cli (Win)  | `%USERPROFILE%/.copilot/skills/<name>/SKILL.md`             | Direct directory copy (recursive)          |
| copilot-cli (WSL)  | `~/.copilot/skills/<name>/SKILL.md`                         | WSL cross-copy (`wsl bash -c "cp -r ..."`) |

**Script:** `scripts/publish/publish-skills.ps1` — targets all destinations including WSL. Also publishes to `~/.claude/skills/` and `~/.codex/skills/` for cross-assistant compatibility. Uses `-SkipWSL` opt-out.

> **Note:** VS Code loads skills from the same `~/.copilot/skills/` personal path, not from the `%APPDATA%/Code/User/prompts/` directory. Skills are runtime-agnostic in both format and discovery path.

### Hooks

| Runtime           | Destination Path                                           | Delivery                                    |
| :---------------- | :--------------------------------------------------------- | :------------------------------------------ |
| VS Code           | `.github/hooks/*.hooks.json` (repo-scoped)                 | Direct file copy within workspace           |
| copilot-cli (Win) | `.github/hooks/*.hooks.json` (repo-scoped, CWD-discovered) | Same repo-scoped mechanism                  |
| copilot-cli (WSL) | `.github/hooks/*.hooks.json` (in WSL-cloned repo)          | Repo-scoped: works if repo is cloned in WSL |

**Script:** `scripts/publish/publish-hooks.ps1` — copies from `hooks/` to `.github/hooks/` in the workspace root. Both VS Code and copilot-cli discover hooks from `.github/hooks/` when operating on the repo. No personal (`~/.copilot/`) hook path publish is needed for repo-scoped hooks.

**CWD caveat:** copilot-cli discovers hooks from the current working directory. If invoked from a subdirectory, `.github/hooks/` may not be found. Standard usage (CLI from repo root) works correctly.

### Prompts

| Runtime            | Destination Path                                     | Delivery                                 |
| :----------------- | :--------------------------------------------------- | :--------------------------------------- |
| VS Code (Stable)   | `%APPDATA%/Code/User/prompts/*.prompt.md`            | Direct file copy                         |
| VS Code (Insiders) | `%APPDATA%/Code - Insiders/User/prompts/*.prompt.md` | Direct file copy                         |
| copilot-cli        | ❌ N/A                                                | No `.prompt.md` discovery in copilot-cli |

**Script:** `scripts/publish/publish-prompts.ps1` — targets VS Code only. Prompts are a VS Code-specific artifact with no copilot-cli equivalent.

### Toolsets

| Runtime            | Destination Path                                          | Delivery                                                                          |
| :----------------- | :-------------------------------------------------------- | :-------------------------------------------------------------------------------- |
| VS Code (Stable)   | `%APPDATA%/Code/User/prompts/*.toolsets.jsonc`            | Direct file copy                                                                  |
| VS Code (Insiders) | `%APPDATA%/Code - Insiders/User/prompts/*.toolsets.jsonc` | Direct file copy                                                                  |
| copilot-cli        | ❌ N/A                                                     | No `.toolsets.jsonc` discovery; CLI uses `tools:` frontmatter and `--tools` flags |

**Script:** `scripts/publish/publish-toolsets.ps1` — targets VS Code only. Toolsets have no file-format equivalent in copilot-cli. CLI tool filtering is achieved through agent frontmatter `tools:` array and CLI flags.

## Shareability Assessment

Each artifact type is assessed against three levels of cross-runtime compatibility, from weakest to strongest:

1. **File Format Compatibility** — Both runtimes can parse the file without errors
2. **Semantic Compatibility** — Both runtimes interpret the same fields with the same meaning
3. **Behavioral Compatibility** — An identical file produces identical functional behavior on both runtimes

**Shareability = Behavioral Compatibility.** An artifact is "shareable" only if the same file, without modification, produces the same functional result on both platforms.

### Assessment Table

| Artifact         | File Format | Semantic | Behavioral | Verdict                              |
| :--------------- | :---------: | :------: | :--------: | :----------------------------------- |
| **Skills**       |      ✅      |    ✅     |     ✅      | **Shareable**                        |
| **Hooks**        |      ✅      |    ✅     |     ⚠️      | **Mostly Shareable**                 |
| **Instructions** |      ✅      |    ⚠️     |     ❌      | **Content Shareable / Delivery Not** |
| **Agents**       |      ✅      |    ⚠️     |     ❌      | **Not Shareable**                    |
| **Prompts**      |      ❌      |    ❌     |     ❌      | **VS Code Only**                     |
| **Toolsets**     |      ❌      |    ❌     |     ❌      | **VS Code Only**                     |

### Per-Artifact Analysis

#### Skills — Shareable ✅

- **File Format:** Both runtimes read `SKILL.md` with YAML frontmatter + Markdown body. ✅
- **Semantic:** `name:` and `description:` frontmatter fields interpreted identically. Skill invocation triggered by task-description matching on both platforms. ✅
- **Behavioral:** Same `~/.copilot/skills/<name>/SKILL.md` discovery path. Skill content injected into agent context via the same mechanism. No platform-specific fields. ✅
- **Verdict:** A single `SKILL.md` file works identically on both runtimes. No variants needed. Publish once, use everywhere.

#### Hooks — Mostly Shareable ⚠️

- **File Format:** Both runtimes parse `*.hooks.json` with identical JSON schema (`version`, `hooks`, lifecycle events, command entries with `bash`/`powershell` keys). ✅
- **Semantic:** All 6 lifecycle events (`sessionStart`, `sessionEnd`, `userPromptSubmitted`, `preToolUse`, `postToolUse`, `errorOccurred`) supported on both platforms. `preToolUse` `deny`/`allow`/`ask` responses work the same. ✅
- **Behavioral:** Same behavior **when hooks are in `.github/hooks/`** and CLI is invoked from repo root. Discovery difference: VS Code always uses workspace root; CLI uses CWD. If CLI runs from a subdirectory, hooks may not be found. ⚠️
- **Verdict:** Shareable for standard repo-scoped usage. The CWD discovery caveat is minor and aligns with typical developer workflow (CLI from repo root).

#### Instructions — Content Shareable / Delivery Not ⚠️❌

- **File Format:** Both runtimes parse `.instructions.md` with YAML frontmatter. ✅
- **Semantic:** `description:` field works on both. `applyTo:` glob patterns work in VS Code but are **lost** in CLI's concatenation mode. `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` preserves path semantics but requires env var setup. ⚠️
- **Behavioral:** VS Code loads individual files from user prompts directory preserving per-file scope. CLI loads a single concatenated file (`~/.copilot/copilot-instructions.md`) with global scope. Identical instruction content produces different scoping behavior. ❌
- **Verdict:** The **content** (markdown body with guidelines) is fully portable. The **delivery mechanism** is fundamentally different. Publish scripts must handle the translation. Same source files, different publish pipelines.

#### Agents — Not Shareable ❌

- **File Format:** Both runtimes read `*.agent.md` with YAML frontmatter + Markdown body. ✅
- **Semantic:** Shared fields (`name`, `description`, `tools`) work on both. But critical fields differ: `agents:` (subagent declarations) is VS Code-only; `infer:` and `mcpServers:` are CLI-only. `tools:` array uses different namespaces (`execute/runInTerminal` vs `bash`). ⚠️
- **Behavioral:** An agent file authored for VS Code will load on CLI without errors (unknown fields silently ignored), but VS Code-specific tool references won't function. Subagent orchestration has no shared syntax. Body-level tool name references (`use execute/runInTerminal`) don't match CLI tool names. ❌
- **Verdict:** Agents require **per-runtime variants**. Recommended approach: extract shared logic (persona, rules, workflows) into `.instructions.md` files; agent variants become thin platform-specific wrappers (~50 lines each) with platform-specific frontmatter and `tools:` arrays.

#### Prompts — VS Code Only ❌

- **File Format:** copilot-cli has no `.prompt.md` discovery mechanism. ❌
- **Semantic:** N/A. ❌
- **Behavioral:** N/A. ❌
- **Verdict:** VS Code-specific artifact. No CLI equivalent exists. CLI users use `-p` flag or inline prompts for similar functionality.

#### Toolsets — VS Code Only ❌

- **File Format:** copilot-cli has no `.toolsets.jsonc` file format. ❌
- **Semantic:** N/A. ❌
- **Behavioral:** N/A. ❌
- **Verdict:** VS Code-specific artifact. CLI achieves tool filtering through agent frontmatter `tools:` array and `--tools` CLI flags, but these are not file-based artifacts.

## Gap Analysis

Cells currently at ⚠️ Manual represent gaps where the runtime supports the artifact but the workspace has no automated publish flow. Prioritized by impact:

|     Priority     | Artifact     | Runtime           | Current State | Gap Description                                                                                                                                                     | Recommended Action                                                                                                                                      |
| :--------------: | :----------- | :---------------- | :-----------: | :------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **1 (Critical)** | Instructions | copilot-cli (Win) |       ⚠️       | CLI supports instructions via `~/.copilot/copilot-instructions.md` or `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`, but `publish-instructions.ps1` only targets VS Code paths | Redesign `publish-instructions.ps1` with `-Mode Concat` (default) and `-Mode EnvVar` options targeting `%USERPROFILE%/.copilot/copilot-instructions.md` |
|   **2 (High)**   | Instructions | copilot-cli (WSL) |       ⚠️       | Same as above, extended to WSL filesystem                                                                                                                           | Add WSL support to `publish-instructions.ps1` via shared `wsl-helpers.ps1` utility, targeting `~/.copilot/copilot-instructions.md` in WSL home          |
|   **3 (Low)**    | Hooks        | copilot-cli (WSL) |       ⚠️       | Hooks publish to `.github/hooks/` repo-scoped. If repo is Windows-only and user runs CLI in WSL with a separate repo clone, hooks must be in that clone             | Minor: document that hooks are repo-scoped and travel with the repository. No additional publish target needed for most workflows                       |

### Non-Gaps (Clarification)

- **Agents (CLI):** Agents are ✅ Automated for CLI via `publish-agents.ps1 → ~/.copilot/agents/`. The fact that agents need per-runtime variants is an **authoring concern**, not a publishing gap. The publish script correctly copies whatever is in the `agents/` directory.
- **Prompts / Toolsets (CLI):** These are ❌ N/A, not gaps. The runtime fundamentally does not support these artifact types. No publish script change can address this.

## Extensibility Notes

### Adding a Future Runtime Column

The framework is designed for extensibility. To add a new runtime (e.g., "Copilot Cloud", "Copilot Mobile"):

1. **Add a column** to the Primary Matrix table with the new runtime name
2. **Assess each row** against the three-state verdict for the new runtime
3. **Add destination/delivery sections** under each artifact type for cells that are ✅ or ⚠️
4. **Update the shareability assessment** — new runtimes may change behavioral compatibility verdicts
5. **Update gap analysis** — new ⚠️ cells become prioritized implementation work

### Design Properties That Support Extension

- **Rows are stable:** The 6 artifact primitives (Agents, Instructions, Skills, Hooks, Prompts, Toolsets) are defined by the workspace's factory model and change infrequently.
- **Columns are additive:** New runtimes add columns without restructuring existing cells. Existing verdicts remain valid.
- **Three-state model is universal:** ✅/⚠️/❌ applies to any runtime that a publish script might target.
- **Shareability criterion is runtime-agnostic:** The File Format → Semantic → Behavioral assessment framework applies to any pair of runtimes.

### Machine-Readable Format (Deferred)

A machine-readable `publish-matrix.yaml` consumed by publish scripts is a candidate for a future iteration. This would make the matrix actionable: publish scripts would read their targets from the matrix config rather than hardcoding paths. The human-readable document established here defines the data model that such a config would encode.
