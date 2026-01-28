# Reverse Engineering the Sample System Message

## Purpose

Define how the sample system message shapes LLM behavior and how its structure maps into a reusable data model for custom system messages. This document is scoped to request-time system messages in the standard request topology:

Request Messages
- System Message
- User Message(s)
- Tool Message(s)
- Assistant Message(s)

Response
- Assistant Message

## High-Level Observations

- The sample system message is a **compound policy bundle** that mixes identity, safety, workflow, tooling, formatting, and workspace rules.
- It is **hierarchical**: global rules appear first; specialized rule blocks follow; scoped/conditional rules are nested with tags or prefixes.
- It is **typed**: each block is conceptually different (e.g., tool usage vs. output formatting vs. apply patch rules).
- It is **priority-ordered**: earlier rules constrain later rules; conflicts are resolved by priority and scope.

## Structural Decomposition (Conceptual Blocks)

1. **Identity & Safety Preamble**
   - Declares assistant identity and model disclosure.
   - Sets safety constraints and response limitations.

2. **General Agent Behavior**
   - Emphasizes autonomy, thoroughness, and tool use strategy.
   - Requires ongoing action until task resolution.

3. **Tooling Rules**
   - Defines when and how to use tools.
   - Enforces specific JSON schema usage and restrictions.

4. **Editing Rules**
   - Specifies file editing workflow and patch format.
   - Includes code-style preservation rules.

5. **Output Formatting Rules**
   - Defines formatting and hyperlinking rules for file references.
   - Sets math rendering conventions.

6. **Workspace/Project Instructions**
   - Project-specific conventions and folder structure guidance.
   - Required processes for workspace tasks.

7. **Skill & Agent Catalogs**
   - Enumerates skills/agents and when to use them.

8. **Mode-Specific Instructions**
   - Overrides general behavior in specific modes (e.g., orchestrator/subagent).

## Priority Model (Suggested)

1. **Safety / Policy**
2. **Identity & Disclosure**
3. **Mode Overrides**
4. **Tooling & Editing Rules**
5. **Output Formatting**
6. **Project/Workspace Rules**
7. **Advisory Preferences**

When multiple blocks apply, the higher-priority block wins. Within equal priority, the most specific scope wins.

## Data Model Implications

A robust data model should:
- Represent **typed instruction blocks** with priorities and scopes.
- Support **nested blocks** (e.g., output formatting contains file linkification rules).
- Provide **conditions** (e.g., applyTo globs, mode-specific overrides).
- Include **metadata** (source file, version, created timestamp).

## Building Block Rules & Constraints

These rules define how the instruction blocks are assembled and validated:

- **Block identity**: each block must have a stable, unique `id` within the system message.
- **Ordering**: blocks are evaluated in order; explicit `priority` resolves conflicts across blocks of different types.
- **Type discipline**: `type` must be one of the canonical block types; unknown types are rejected.
- **Non-empty content**: every block must provide `content` (text or structured) and it must be non-empty.
- **Scoped applicability**: if a block includes a `scope`, it must narrow applicability (e.g., `applyTo`, `modes`, or `tools`).
- **Conditional activation**: `conditions` should be declarative and side-effect free; if any condition fails, the block is skipped.
- **Hierarchical inheritance**: child blocks inherit parent `scope` and `conditions` unless explicitly overridden or narrowed.
- **Conflict resolution**: higher priority wins; if priorities are equal, the narrower scope wins.
- **Metadata integrity**: `version`, `createdAt`, and `updatedAt` must be set and consistent with the content being shipped.

## Mapping to Request Topology

- **System Message** holds the full instruction bundle described above.
- **User Messages** provide task-specific intent and context.
- **Tool Messages** return outputs used by the assistant.
- **Assistant Messages** must respect the system message constraints.

This implies the data model should separate **system policy** from **per-request user intent**, and allow programmatic assembly of the system message before a request is made.

## Recommended Artifacts

- JSON Schema for the system message model.
- Human-readable data model documentation.
- Example request payload using the topology.
