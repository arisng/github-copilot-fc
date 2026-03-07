# Agent Variant Directory Structure Proposal

> **Status**: Design Proposal — partially implemented. CLI variant files and validation script deferred to iteration 5+.

This document proposes the workspace directory structure for per-runtime agent variants, enabling the ralph-v2 agent suite to operate on both VS Code and copilot-cli. It covers the subdirectory naming convention, shared instructions extraction strategy, publish flow adjustments, authoring model, and extensibility for future runtimes.

## Background

The runtime-support framework ([runtime-support-framework.md](runtime-support-framework.md)) establishes that **agents are not shareable** across runtimes. A single `.agent.md` file cannot produce identical functional behavior on VS Code and copilot-cli due to three categories of incompatibility (see [Per-Agent Incompatibility Analysis](#per-agent-incompatibility-analysis)). Per-runtime agent variants are therefore required (ISS-003).

Only the `agents/` directory needs restructuring — all other artifact directories (`skills/`, `instructions/`, `hooks/`, `prompts/`, `toolsets/`) are either runtime-agnostic or inherently VS Code-only and require no structural changes (Q-FDB-012).

## Proposed Directory Structure

### Convention: Subdirectories Over Suffixes

**Recommendation**: Use nested subdirectories under each agent group (`agents/ralph-v2/vscode/`, `agents/ralph-v2/cli/`) to separate runtime variants.

Three naming conventions were evaluated:

| Convention                                                           | Pros                                                                                                                                           | Cons                                                                                                                                                      |    Verdict    |
| :------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------- | :-----------: |
| **Suffix** (`ralph-v2.vscode.agent.md` / `ralph-v2.cli.agent.md`)    | All agents visible in one listing                                                                                                              | Both platforms use `*.agent.md` glob for discovery — **duplicate agent registration risk**. copilot-cli may interpret `ralph-v2.vscode` as the agent name |    ❌ Risky    |
| **Subdirectory** (`agents/ralph-v2/vscode/`, `agents/ralph-v2/cli/`) | Clean separation; encapsulation under agent group; symmetric structure; publish scripts copy from correct subdirectory; no cross-contamination | Requires publish script to select source directory; file moves required for existing VS Code agents                                                       | ✅ Recommended |
| **Conditional sections** (single file with runtime markers)          | Single source of truth                                                                                                                         | Neither runtime supports conditional logic in `.agent.md` — no `#ifdef` equivalent in Markdown                                                            | ❌ Not viable  |

The nested subdirectory convention is the safest approach because:
- `publish-agents.ps1` already uses `Get-ChildItem -Recurse` for agent discovery, so subdirectory agents are found.
- For CLI publishing to `~/.copilot/agents/`, the script copies files to a flat destination — subdirectory source → flat destination is a standard pattern.
- No risk of the wrong runtime picking up the other runtime's variants.
- Both variants and shared content are encapsulated under one agent group directory.

### Proposed Layout

```
agents/
├── ralph-v2/                          # Agent group: shared content + per-runtime variants
│   ├── README.md                      # Shared documentation
│   ├── docs/                          # Shared design docs
│   ├── specs/                         # Shared specifications
│   ├── vscode/                        # VS Code variants (moved from parent via git mv)
│   │   ├── ralph-v2.agent.md          # Orchestrator (VS Code)
│   │   ├── ralph-v2-executor.agent.md # Executor (VS Code)
│   │   ├── ralph-v2-planner.agent.md  # Planner (VS Code)
│   │   ├── ralph-v2-questioner.agent.md # Questioner (VS Code)
│   │   ├── ralph-v2-reviewer.agent.md # Reviewer (VS Code)
│   │   └── ralph-v2-librarian.agent.md # Librarian (VS Code)
│   └── cli/                           # CLI variants (new)
│       ├── ralph-v2.agent.md          # Orchestrator (CLI)
│       ├── ralph-v2-executor.agent.md # Executor (CLI)
│       ├── ralph-v2-planner.agent.md  # Planner (CLI)
│       ├── ralph-v2-questioner.agent.md # Questioner (CLI)
│       ├── ralph-v2-reviewer.agent.md # Reviewer (CLI)
│       └── ralph-v2-librarian.agent.md # Librarian (CLI)
├── generic-research.agent.md          # Non-ralph agents (unchanged)
├── planner.agent.md
└── ...
```

**Key decisions**:
- VS Code agents are **moved** from `agents/ralph-v2/` into `agents/ralph-v2/vscode/` via `git mv` — this creates a symmetric structure where both variants are nested under the agent group.
- CLI variants are created as new files in `agents/ralph-v2/cli/`.
- Shared content (`README.md`, `docs/`, `specs/`) remains at the `agents/ralph-v2/` parent level, accessible to both variants.
- Non-ralph agents (`generic-research`, `planner`, `mermaid`, etc.) remain at `agents/` root — they will refined to a runtime-specific nested structure in future iterations as needed.

**Three advantages of the nested convention** (Q-FDB-004):
1. **Encapsulation**: All content for an agent group lives under one parent directory — variants, shared docs, and specs are co-located.
2. **Symmetry**: Both `vscode/` and `cli/` are peer subdirectories under the same parent, making the structure self-documenting.
3. **Discovery simplicity**: Listing `agents/ralph-v2/` reveals both variants and shared content in one view, rather than requiring knowledge of a separate `agents/cli/` root directory.

## Three Categories of Incompatibility

Per Q-FDB-008, three categories prevent a single `.agent.md` file from serving both runtimes:

### 1. Frontmatter Schema Differences

Fields that are silently ignored on the non-target runtime:

| Field             |   VS Code   | copilot-cli | Effect When Ignored                                                                                                                       |
| :---------------- | :---------: | :---------: | :---------------------------------------------------------------------------------------------------------------------------------------- |
| `agents:`         | ✅ Required  |  ❌ Ignored  | Subagent orchestration lost — CLI cannot delegate to child agents via this mechanism                                                      |
| `argument-hint:`  | ✅ Supported |  ❌ Ignored  | User guidance in agent picker lost (cosmetic)                                                                                             |
| `user-invocable:` | ✅ Supported | ✅ Supported | Supported on both platforms — controls agent picker visibility. Default: `true`.                                                          |
| `model:`          |  ❌ Ignored  |  ⚠️ Ignored  | Silently ignored by CLI coding-agent — model selection is via `/model` command or `--model` flag; no functional effect on either platform |
| `infer:`          |  ❌ Ignored  | ⚠️ Retired  | Retired as of March 2026 official docs. Use `disable-model-invocation` instead. Ignored by VS Code.                                       |
| `mcp-servers:`    |  ❌ Ignored  | ✅ Supported | Bundled MCP server configuration not available in VS Code                                                                                 |
| `name:`           |  ✅ Shared   |  ✅ Shared   | —                                                                                                                                         |
| `description:`    |  ✅ Shared   |  ✅ Shared   | —                                                                                                                                         |
| `tools:`          |  ✅ Shared   |  ✅ Shared   | Works on both, but tool names differ (see category 2)                                                                                     |

### 2. Tools Namespace Differences

The `tools:` array uses different namespace references per runtime. Unknown tools are **silently ignored** — no errors, but **no functionality** either.

| VS Code Tool                                        | CLI Equivalent                    | Notes                              |
| :-------------------------------------------------- | :-------------------------------- | :--------------------------------- |
| `execute/runInTerminal`                             | `bash`                            | Primary command execution          |
| `read/readFile`                                     | `view`                            | File reading                       |
| `edit/editFiles`                                    | `edit`                            | File editing                       |
| `edit/createFile`                                   | `create`                          | File creation                      |
| `edit/createDirectory`                              | `bash` (via `mkdir`)              | No dedicated tool in CLI           |
| `search`                                            | Built-in (grep/glob)              | Namespace differs                  |
| `web`                                               | No direct equivalent              | CLI has no built-in web tool       |
| `agent`                                             | `task`                            | Subagent invocation mechanism      |
| `vscode/memory`                                     | No equivalent                     | Memory tool is VS Code-only        |
| `execute/testFailure`                               | No equivalent                     | —                                  |
| `execute/runTests`                                  | No equivalent                     | —                                  |
| `read/problems`                                     | No equivalent                     | —                                  |
| `read/terminalSelection`                            | No equivalent                     | —                                  |
| `read/terminalLastCommand`                          | No equivalent                     | —                                  |
| MCP tools (`mcp_docker/*`, `microsoftdocs/*`, etc.) | MCP tools (via `mcp-config.json`) | Same tools, discovered differently |

### 3. Body-Level Instruction Differences

Subtle references in the Markdown body that create behavioral drift:

- **Tool name mentions**: Instructions like "use `execute/runInTerminal` to run commands" reference VS Code-specific tool names that don't exist in CLI.
- **Subagent invocation patterns**: VS Code uses `@AgentName` syntax; CLI uses `/agent` or `--agent` flags.
- **Memory tool usage**: References to `vscode/memory` have no CLI equivalent.
- **MCP tool paths**: Body text may reference `mcp_docker/` prefixed tools; CLI discovers the same tools but with potentially different naming.

## Per-Agent Incompatibility Analysis

The 6 ralph-v2 agents and their specific incompatibility categories:

| Agent                                           | Lines | Frontmatter Issues                                           | Tools Issues                                                                                           | Body Issues                                              |                   Variant Complexity                    |
| :---------------------------------------------- | :---: | :----------------------------------------------------------- | :----------------------------------------------------------------------------------------------------- | :------------------------------------------------------- | :-----------------------------------------------------: |
| **Orchestrator** (`ralph-v2.agent.md`)          |  774  | `agents:` (5 subagents), `argument-hint:`, `user-invocable:` | `agent`, `execute/*`, `read/*`, `edit/*`, `search`, `vscode/memory`                                    | `@SubAgent` references, memory tool instructions         | **High** — subagent orchestration is the breaking point |
| **Executor** (`ralph-v2-executor.agent.md`)     |  294  | `argument-hint:`, `user-invocable:`                          | `execute/*`, `read/*`, `edit/*`, `search`, `web`, `vscode/memory`, `deepwiki/*`, `aspire/*`, MCP tools | Tool name references in workflow instructions            |                         Medium                          |
| **Planner** (`ralph-v2-planner.agent.md`)       |  571  | `argument-hint:`, `user-invocable:`                          | `execute/*`, `read/*`, `edit/*`, `search`, `web`, `vscode/memory`, MCP tools                           | Tool name references                                     |                         Medium                          |
| **Questioner** (`ralph-v2-questioner.agent.md`) |  372  | `argument-hint:`, `user-invocable:`                          | `execute/*`, `read/*`, `edit/*`, `search`, `web`, `microsoftdocs/*`, `github/*`, MCP tools             | Tool name references, GitHub MCP tool references         |                         Medium                          |
| **Reviewer** (`ralph-v2-reviewer.agent.md`)     |  690  | `argument-hint:`, `user-invocable:`                          | `execute/*`, `read/*`, `edit/*`, `search`, `web`, `vscode/memory`, `aspire/*`, MCP tools               | Tool name references                                     |                         Medium                          |
| **Librarian** (`ralph-v2-librarian.agent.md`)   |  578  | `argument-hint:`, `user-invocable:`                          | `execute/*`, `read/*`, `edit/*`, `search`, `web`, `vscode/memory`, MCP tools                           | Tool name references, git-atomic-commit skill references |                         Medium                          |

**Key finding**: The Orchestrator has the **highest variant complexity** because it is the only agent using the `agents:` frontmatter key and `@SubAgent` delegation pattern — both of which have no shared syntax across platforms. All other agents have medium complexity (frontmatter cosmetic + tool namespace remapping + body text tool references).

## Shared Instructions Extraction Strategy

### What Moves to `.instructions.md`

Each ralph-v2 agent's **runtime-agnostic content** is extracted into a shared instruction file:

| Content Type                                                   | Moves to Shared Instruction |  Stays in Agent Variant   |
| :------------------------------------------------------------- | :-------------------------: | :-----------------------: |
| Persona definition (role, responsibilities)                    |              ✅              |             —             |
| Rules and constraints                                          |              ✅              |             —             |
| Workflow steps (abstract logic)                                |              ✅              |             —             |
| Artifact tables (file structures, report templates)            |              ✅              |             —             |
| Signal protocol definitions                                    |              ✅              |             —             |
| Contract (input/output schema)                                 |              ✅              |             —             |
| Frontmatter (`name:`, `description:`, `tools:`)                |              —              |             ✅             |
| Runtime-specific fields (`agents:`, `disable-model-invocation:`, `mcp-servers:`) |              —              |             ✅             |
| Tool-specific instructions ("use `execute/runInTerminal`")     |              —              | ✅ (remapped per runtime) |

### Proposed Shared Instruction Files

| Shared Instruction                                   | Source Agent | Estimated Lines |
| :--------------------------------------------------- | :----------- | :-------------: |
| `instructions/ralph-v2-orchestrator.instructions.md` | Orchestrator |      ~700       |
| `instructions/ralph-v2-executor.instructions.md`     | Executor     |      ~250       |
| `instructions/ralph-v2-planner.instructions.md`      | Planner      |      ~520       |
| `instructions/ralph-v2-questioner.instructions.md`   | Questioner   |      ~330       |
| `instructions/ralph-v2-reviewer.instructions.md`     | Reviewer     |      ~640       |
| `instructions/ralph-v2-librarian.instructions.md`    | Librarian    |      ~530       |

### Estimated Size Reduction

| Agent        |  Current Size   |    Shared Instruction     | VS Code Variant |  CLI Variant   |
| :----------- | :-------------: | :-----------------------: | :-------------: | :------------: |
| Orchestrator |    774 lines    |        ~700 lines         |    ~50 lines    |   ~60 lines    |
| Executor     |    294 lines    |        ~250 lines         |    ~30 lines    |   ~40 lines    |
| Planner      |    571 lines    |        ~520 lines         |    ~40 lines    |   ~45 lines    |
| Questioner   |    372 lines    |        ~330 lines         |    ~35 lines    |   ~40 lines    |
| Reviewer     |    690 lines    |        ~640 lines         |    ~40 lines    |   ~45 lines    |
| Librarian    |    578 lines    |        ~530 lines         |    ~40 lines    |   ~45 lines    |
| **Totals**   | **3,279 lines** | **~2,970 lines** (shared) | **~235 lines**  | **~275 lines** |

**Net effect**: 3,279 lines (6 files) → 2,970 + 235 + 275 = 3,480 lines (18 files). The ~6% increase in total line count is offset by:
- **Single source of truth** for agent behavior — update once, both variants get it
- **~50-line variant files** that contain only runtime-specific wiring
- **Dramatically reduced risk of behavioral drift** between platforms

### Caveat: Runtime-Neutral Language

The shared instruction body **must avoid runtime-specific tool name references**. Instead of:
- ~~"use `execute/runInTerminal` to run commands"~~ → "run commands in the terminal"
- ~~"use `read/readFile` to read files"~~ → "read the file"
- ~~"use `@Ralph-v2-Executor` to delegate"~~ → "delegate to the Executor subagent"

This abstraction makes instructions work regardless of the runtime's tool naming convention.

## Publish Flow Adjustments

### Current Behavior

`publish-agents.ps1` discovers all `*.agent.md` files recursively from `agents/` and copies them flat to destinations. It does not distinguish between VS Code and CLI variants.

### Proposed Changes

Add a `-Platform` parameter to `publish-agents.ps1`:

```
publish-agents.ps1 -Platform vscode    # Copies from agents/*/vscode/ to VS Code paths
publish-agents.ps1 -Platform cli        # Copies from agents/*/cli/ to CLI paths
publish-agents.ps1                      # Default: publishes both
```

| Parameter          | Source Directory                                  | Destinations                                                              |
| :----------------- | :------------------------------------------------ | :------------------------------------------------------------------------ |
| `-Platform vscode` | `agents/*/vscode/`, `agents/` (root-level agents) | `%APPDATA%/Code/User/prompts/`, `%APPDATA%/Code - Insiders/User/prompts/` |
| `-Platform cli`    | `agents/*/cli/`                                   | `%USERPROFILE%/.copilot/agents/`, WSL `~/.copilot/agents/`                |
| (default)          | All of the above                                  | All of the above                                                          |

**Non-ralph agents** at the `agents/` root (e.g., `generic-research.agent.md`, `planner.agent.md`) are published to **VS Code only** by default, since they do not have CLI variants. Future work may add CLI variants for individual non-ralph agents as needed.

### Destination Flattening

Both VS Code and CLI discovery expect flat file placement at the destination (no subdirectories). The publish script must strip the source subdirectory structure when copying:

- `agents/ralph-v2/vscode/ralph-v2.agent.md` → `%APPDATA%/Code/User/prompts/ralph-v2.agent.md`
- `agents/ralph-v2/cli/ralph-v2.agent.md` → `%USERPROFILE%/.copilot/agents/ralph-v2.agent.md`

Both variants share the same filename (`ralph-v2.agent.md`) — they go to different destinations, so no collision occurs.

## Authoring Model

### Manual Authoring (Recommended)

Agent variants are **authored manually**, not auto-generated from a single source. Rationale:

1. **Variant differences are non-trivial**: Beyond frontmatter, CLI variants may have different MCP server bundles, model overrides, and tool-specific instructions that don't map mechanically from VS Code equivalents.
2. **Low maintenance burden**: With shared instructions extracted, each variant is ~50 lines. For 6 agents, that's ~300 lines of variant-specific content — manageable for manual maintenance.
3. **No build-step complexity**: Auto-generation adds a generator tool to maintain, potential merge conflicts when the generator schema changes, and a build step that must run before publishing.
4. **Flexibility preserved**: Manual authoring allows each variant to evolve independently (e.g., a CLI Orchestrator can remain auto-delegatable while a VS Code variant uses `agents:` for explicit subagent invocation — these are fundamentally different patterns).

### Optional Validation Script

A `scripts/publish/validate-agent-variants.ps1` script can detect variant drift without enforcing auto-generation:

| Check                        | Description                                                                                                      |
| :--------------------------- | :--------------------------------------------------------------------------------------------------------------- |
| Shared instruction reference | Both VS Code and CLI variants for the same agent reference the same shared `.instructions.md` file               |
| Cross-runtime field usage    | VS Code variant doesn't depend on CLI-only fields (`disable-model-invocation:`, `mcpServers:`) for functionality |
| Tool namespace compliance    | CLI variant doesn't include VS Code-only tool namespaces (`execute/*`, `read/*`, `edit/*`) in its `tools:` array |
| Completeness                 | Every agent in `agents/ralph-v2/vscode/` has a corresponding variant in `agents/ralph-v2/cli/` (and vice versa)  |

This validation is **advisory** — it warns about drift but does not block publishing. Implementation of this script is deferred along with the variant files themselves.

## Extensibility

### Design for Two, Extensible for Three

This proposal targets exactly two runtimes: **VS Code** and **copilot-cli**. The subdirectory convention is inherently extensible:

- Adding a future runtime (e.g., "Copilot Cloud") means creating `agents/ralph-v2/cloud/` — no restructuring of existing `agents/ralph-v2/vscode/` or `agents/ralph-v2/cli/` directories required.
- The `-Platform` parameter in `publish-agents.ps1` accepts new values without breaking existing behavior.
- Shared instructions remain the single source of truth regardless of how many runtime variants exist.
- New runtimes are **nested under the agent group**, not at the `agents/` root — keeping the encapsulation pattern consistent.

No empty `agents/ralph-v2/cloud/` directory is created preemptively. The YAGNI principle applies: solve today's known problems, not tomorrow's hypothetical ones.

### Extensibility Checklist for New Runtimes

When adding a third runtime variant:

1. Create `agents/<agent-group>/<runtime>/` directory with variant agent files
2. Extract any new runtime-specific fields into the variant frontmatter
3. Add the runtime to the `-Platform` parameter in `publish-agents.ps1`
4. Add a column to the runtime-support framework matrix
5. Update the validation script to include the new variant

## Scope and Deferral

| Item                                         |    Status    | Notes                                                                                                                                   |
| :------------------------------------------- | :----------: | :-------------------------------------------------------------------------------------------------------------------------------------- |
| Directory structure convention               |  ✅ Decided   | Nested subdirectory (`agents/ralph-v2/vscode/`, `agents/ralph-v2/cli/`). VS Code agents **moved** via `git mv` for symmetric structure. |
| Shared instructions extraction strategy      |  ✅ Decided   | Runtime-agnostic content → `instructions/ralph-v2-*.instructions.md`                                                                    |

> **Note**: `infer` is retained here only for historical analysis. For current authoring, use `disable-model-invocation`; `disable-model-invocation: true` is equivalent to the old `infer: false`.
| Per-agent incompatibility analysis           | ✅ Documented | 6 agents analyzed across 3 categories                                                                                                   |
| Publish flow adjustments design              |  ✅ Designed  | `-Platform vscode\|cli` parameter; source dirs: `agents/*/vscode/`, `agents/*/cli/`                                                     |
| Authoring model                              |  ✅ Decided   | Manual with optional validation                                                                                                         |
| **Creation of 6 CLI agent variant files**    |  ⏳ Deferred  | **Iteration 5+** — `agents/ralph-v2/cli/`                                                                                               |
| **Extraction of 6 shared instruction files** |    ✅ Done    | Completed (iteration 4) — `instructions/ralph-v2-*.instructions.md`                                                                     |
| **Move VS Code agents to `vscode/` subdir**  |    ✅ Done    | Completed (iteration 4) — `git mv` into `agents/ralph-v2/vscode/`                                                                       |
| **Implementation of `-Platform` parameter**  |    ✅ Done    | Completed (iteration 4)                                                                                                                 |
| **Validation script implementation**         |  ⏳ Deferred  | **Iteration 5+**                                                                                                                        |

## Grounding

| Decision                                           | Source                                                        |
| :------------------------------------------------- | :------------------------------------------------------------ |
| Three categories of incompatibility                | Q-FDB-008                                                     |
| Subdirectory convention over suffix                | Q-FDB-009                                                     |
| Shared instructions extraction (~50-line variants) | Q-FDB-010                                                     |
| Manual authoring with optional validation          | Q-FDB-011                                                     |
| Only `agents/` needs restructuring                 | Q-FDB-012                                                     |
| Design for 2 runtimes, extensible for 3rd          | Q-FDB-014                                                     |
| Agents require per-runtime variants                | ISS-003, runtime-support-framework.md Shareability Assessment |
