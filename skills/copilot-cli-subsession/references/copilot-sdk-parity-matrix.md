# Copilot CLI ↔ SDK Capability Parity Matrix

Single source of truth for **which surface exposes which sub-session capability** and how the surfaces correlate. Used to keep `copilot-cli-subsession`, `copilot-sdk-dotnet`, and `copilot-byok` in sync with each other and with the upstream Copilot CLI.

**How to use this matrix:**

1. When a new capability appears in **any** surface (CLI flag, `COPILOT_*` env var, SDK API, VS Code `chatLanguageModels.json`), add/update its row here once.
2. Skills link to this file instead of re-documenting cross-surface equivalence.
3. Run `scripts/Test-CopilotCliParity.ps1` to detect drift between the documented CLI surface and the **installed** CLI, and re-verify this matrix's "Verified" column.
4. Bump `lastVerified` / `verifiedCliVersion` in the three skill frontmatters when the matrix is re-grounded.

**Verified against:** GitHub Copilot CLI **1.0.77** (`copilot --version` + `copilot --help` + `copilot help environment`) on **2026-08-03**.

---

## Feature ↔ surface map

| Feature | copilot-cli-subsession (CLI flag / env) | copilot-sdk-dotnet (SDK API) | VS Code chatLanguageModels | Notes / verified (v1.0.77) |
| --- | --- | --- | --- | --- |
| Session identity / chaining | `--session-id <uuid>`; `--name <slug>` (`-n`) | `SessionConfig.SessionId`, `ResumeSessionAsync`, `GetLastSessionIdAsync` | — | `--session-id` and `-n, --name` present in v1.0.77 help. |
| Non-interactive prompt | `-p, --prompt` | `SendAsync`, `SendAndWaitAsync` | — | `-p, --prompt` present. |
| Custom agent | `--agent <name>` | `SessionConfig.CustomAgents` | — | `--agent` present. Plugin-qualified `plugin:agent` in CLI. |
| Model | `--model`; `COPILOT_MODEL` | `SessionConfig.Model`; `ProviderConfig` | model `id` | `--model` present; `COPILOT_MODEL` documented in `copilot help environment`. `-Model` takes precedence over profile model in the sub-session script. |
| Reasoning effort | `--reasoning-effort` / alias `--effort`; levels `none, minimal, low, medium, high, xhigh, max` | **Not documented in SDK skill** ⚠ gap | `supportsReasoningEffort`, `reasoningEffortFormat` | v1.0.77 choices: `"none", "minimal", "low", "medium", "high", "xhigh", "max"` — note `minimal` is newer than the skill's original list. Per-model subset is grounded in `copilot-byok/references/shared/reasoning-effort-lookup.md`. No `COPILOT_*` env var exists for it. |
| Permissions | `--allow-all`, `--no-ask-user`, `--allow-tool`, `--deny-tool`, `--allow-url`, `--deny-url`; `COPILOT_ALLOW_ALL` | `SessionConfig.OnPermissionRequest` | — | All present in v1.0.77; `--allow-all` = tools+paths+urls. `COPILOT_ALLOW_ALL=true` documented. |
| MCP servers | `--disable-builtin-mcps`, `--additional-mcp-config`, `--disable-mcp-server` | `SessionConfig.McpServers` | — | `--additional-mcp-config` and `--disable-mcp-server` are newer (v1.0.77). Sub-session script currently only forwards `--disable-builtin-mcps`. |
| Custom instructions | `--no-custom-instructions`; `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` | — | — | `--no-custom-instructions` present; `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` documented. |
| Streaming | `--stream on\|off` | `SessionConfig.Streaming`; `AssistantMessageDeltaEvent` | `streaming` | `--stream` choices `on`/`off` present. Sub-session script forces `--stream off` for programmatic capture. |
| Structured output | `--output-format text\|json` (JSONL) | `session.Events` (UserMessageEvent, AssistantMessageEvent, ToolExecution*, SessionIdleEvent, SessionErrorEvent) | — | `--output-format` choices `text`/`json` present. |
| BYOK provider | `COPILOT_PROVIDER_BASE_URL`, `_TYPE`, `_API_KEY`, `_WIRE_API`, `_MAX_PROMPT_TOKENS`, `_MAX_OUTPUT_TOKENS`, `_OFFLINE` | `SessionConfig.Provider` → `ProviderConfig` | Custom endpoint vendor (`chat-completions` / `responses` / `messages` apiType) | All documented in `copilot help environment`. Newer: `COPILOT_PROVIDER_BEARER_TOKEN`, `_TRANSPORT` (http\|websockets), `_MODEL_ID`, `_WIRE_MODEL`, `_HEADERS`, `_AZURE_API_VERSION`. `copilot-byok` is the grounding owner. |
| Token limits | `COPILOT_PROVIDER_MAX_PROMPT_TOKENS`, `_MAX_OUTPUT_TOKENS` | — | `maxInputTokens`, `maxOutputTokens` | Grounded sizing in `copilot-byok` (`shared/reasoning-effort-lookup.md`, `shared/environment-variables.md`). |
| Working directory | `-C <dir>`; sub-session script `-WorkingDir` | `CopilotClientOptions.Cwd` | — | `-C` present in v1.0.77. |
| Attachments | `--attachment <path>` | `MessageOptions.Attachments` (file/directory) | — | `--attachment` present (non-interactive only). |
| Config isolation | `COPILOT_HOME` env var (`--config-dir` removed in v1.0.77) | `CopilotClientOptions.CliPath` | — | Sub-session `-CopilotHome` maps to `COPILOT_HOME` (F-1 resolved; deprecated alias `-ConfigDir`) and seeds a minimal staging tree (`byok-profiles.json` + `mcp-config.json` when present) on first use. Staging doubles as the skill's testing sandbox (dojo): durable, independent of production, process-scoped so the root session stays in production. |
| Logging / diagnostics | `--log-dir`, `--log-level` | `CopilotClientOptions.LogLevel` | — | `--log-level` choices in v1.0.77 include `default`. |
| Tool allow/deny lists | `--available-tools`, `--excluded-tools` | `SessionConfig.AvailableTools`, `ExcludedTools` | — | Both present. |
| Newer CLI capabilities (not yet in skills) | `--share`, `--share-gist`, `--connect`, `--context`, `--mode`, `--autopilot`, `--enable-memory`, `--remote`, `--remote-export`, `--secret-env-vars`, `--max-ai-credits`, `--extension-sdk-path` | n/a (assess per feature) | — | Present in v1.0.77 help; candidates for the sub-session skill's `-Passthrough` examples or future params. |

---

## Cross-surface equivalence rules

- **CLI flag ↔ env var**: flags shown with `(env: X)` in help map to that env var. `--model` beats `COPILOT_MODEL` beats settings. For BYOK, env vars are the contract; there is no CLI flag per provider field.
- **CLI ↔ SDK**: both speak JSON-RPC over stdio/TCP to the same Copilot CLI engine. SDK `SessionConfig` fields generally mirror CLI flags (session-id, model, streaming, tools, permissions, MCP). Where a capability exists in one surface but not the other (e.g., reasoning effort in CLI/VS Code but un-documented in the SDK skill), record it as a **gap** row rather than assuming parity.
- **VS Code BYOK**: uses `chatLanguageModels.json` and **ignores** `COPILOT_PROVIDER_*` env vars. `reasoningEffortFormat` differs per apiType (chat-completions → top-level `reasoning_effort`, responses → nested `reasoning.effort`, messages → `output_config.effort`).

## Related references

- [Copilot CLI feature verification audit](copilot-cli-feature-verification-audit.md) — empirical verification of every CLI feature claimed by the copilot skills (CLI 1.0.77, 2026-08-03) + findings.
- [copilot-cli-subsession cheatsheet](copilot-cli-programmatic-cheatsheet.md) — flag-level invocation reference.
- [copilot-byok reasoning-effort lookup](../../copilot-byok/references/shared/reasoning-effort-lookup.md) — per-model reasoning-effort support (authoritative).
- [copilot-byok CLI env vars](../../copilot-byok/references/shared/environment-variables.md) — BYOK env vars and provider examples.
- [copilot-sdk-dotnet API reference](../../copilot-sdk-dotnet/references/api-reference.md) — SDK API surface.
- [.docs customization matrix](../../../.docs/reference/copilot/cli/copilot-cli-customization-matrix.md) — cross-runtime compatibility of agent/hook/prompt artifacts (different concern: artifact formats, not capability parity).

## Grounding

- **Evidence-backed**: every row's "Verified" claim comes from `copilot --version`, `copilot --help`, and `copilot help environment` output of the installed CLI 1.0.77 (captured 2026-08-03), and from the referenced skill reference files.
- **Gap/inference**: the SDK-skill reasoning-effort gap is flagged as a finding, not an asserted fact. (The `--config-dir` question was resolved in F-1 — see the audit.)

`Grounding status: evidence-backed (v1.0.77, 2026-08-03), with explicitly flagged gaps.`
