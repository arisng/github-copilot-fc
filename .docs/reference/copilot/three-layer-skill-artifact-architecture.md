---
category: reference
---

# Three-Layer Architecture for AI-Agent-Facing Skill Documentation

When a skill covers a protocol or workflow complex enough to require both portable guidance and workspace enforcement, structure the documentation into three layers with distinct responsibilities:

## Layers

| Layer | Artifact Type | Portability | Responsibility |
|-------|--------------|-------------|----------------|
| 1. Discovery + Routing | `skills/<name>/SKILL.md` | Portable across repositories | Alias-to-skill routing tables, brief summaries, pointer to Layer 2 |
| 2. Comprehensive Policy | `skills/<name>/references/<ref>.md` | Travels with the skill package | Full protocol rules, intent routing, edit surfaces, enforcement strategy |
| 3. Workspace Enforcement | `instructions/<name>.instructions.md` | Workspace-specific | `applyTo`-scoped enforcement rules, stricter directory conventions, narrow exceptions |

## Key Principles

- **Layer 1 must not replicate deep rules** from Layer 2. It provides discovery (what exists), routing (where to go), and a pointer to the reference doc for full policy.
- **Layer 2 owns the comprehensive agent policy**. It is the authoritative source for intent routing, mutation rules, edit surfaces, and enforcement strategy.
- **Layer 3 enforces workspace-specific constraints** that may be stricter than Layer 2's portable guidance. For example, Layer 2 may allow flat directory structures for single-system repos, while Layer 3 prohibits flat structures in the current workspace.
- **No contradictions across layers**. Intentional asymmetry (Layer 2 permissive, Layer 3 restrictive) is valid; outright contradictions are not.

## Validation Pattern

A cross-artifact consistency audit should verify:
1. No contradictory rules between layers (terminology, directory conventions, mutation policies)
2. Layer 1 stays within its routing-only scope
3. Layer 2 does not duplicate enforcement rules from Layer 3
4. Layer 3's `applyTo` pattern covers all mutable surfaces from Layer 2's edit surface table
5. Terminology is consistent across all three layers (e.g., same placeholder names, same phrasing for shared concepts)

## Applied Example

The OpenSpec SDD skill uses this pattern:
- Layer 1: `skills/openspec-sdd/SKILL.md` — alias table for 4 core commands, pointer to reference doc
- Layer 2: `skills/openspec-sdd/references/ai-coding-agent-workflow.md` — full agent policy
- Layer 3: `instructions/openspec-protocol.instructions.md` — workspace enforcement with stricter directory rules
