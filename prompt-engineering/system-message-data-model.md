# System Message Data Model (Human-Readable)

## Overview

A system message is a structured bundle of instruction blocks. Each block has a type, priority, scope, and content. Blocks can be nested to reflect hierarchical constraints (e.g., output formatting contains file-link rules).

## Core Entities

### SystemMessage

- **id**: Unique identifier.
- **version**: Semantic or date-based version.
- **role**: Always "system".
- **createdAt**: RFC 3339 timestamp for creation.
- **updatedAt**: RFC 3339 timestamp for last update.
- **blocks**: Ordered list of `InstructionBlock` objects.
- **priorityModel**: Optional global ordering of block types.

### InstructionBlock

- **id**: Unique block identifier.
- **type**: One of: identity, safety, behavior, tooling, editing, formatting, project, skills, agents, mode, attachments, advisory.
- **priority**: Integer, higher wins during conflicts.
- **scope**: Optional scoping rules such as applyTo globs or modes.
- **conditions**: Optional rule activation conditions.
- **content**: Instruction text or structured content.
- **children**: Nested instruction blocks.

### Scope

- **applyTo**: File globs the block applies to.
- **modes**: Modes or personas the block applies to.
- **tools**: Tools or tool namespaces referenced in the block.
- **files**: Target files referenced by name.

### Condition

- **kind**: Condition type (e.g., "whenUserAsksForName").
- **value**: Condition payload.

## Priority Rules

Recommended precedence order (highest first):
1. safety
2. identity
3. mode
4. tooling
5. editing
6. formatting
7. project
8. advisory

Conflicts resolve by priority. If priorities tie, the more specific scope wins.

## Building Block Rules & Constraints

- **Stable identifiers**: `SystemMessage.id` and `InstructionBlock.id` must be non-empty and unique within their scope.
- **Required timestamps**: `createdAt` and `updatedAt` are required and must be valid date-time strings.
- **Non-empty content**: `content` must be a non-empty string or an object with `format` and `text`.
- **Content format**: `format` is one of `plain`, `markdown`, `json`, `yaml`.
- **Scope validation**: if `scope` is present, at least one of `applyTo`, `modes`, `tools`, or `files` must be provided.
- **Children semantics**: when `children` exists it must contain at least one block and inherits parent scope/conditions.
- **Array uniqueness**: top-level `blocks` should be unique entries (avoid duplicated block payloads).

## Request Topology Integration

The system message is inserted as the first message in the request sequence. It must be complete and deterministic, and should be assembled before user/tool messages.

## Example Block Types

- **identity**: Name/model disclosure rules.
- **tooling**: When to call tools and schema constraints.
- **editing**: Patch requirements and editing workflow.
- **formatting**: Link formatting and math rendering rules.
- **project**: Workspace-specific constraints.
- **mode**: Overrides (e.g., orchestrator/subagent responsibilities).

## Builder Patterns

Use builders to ensure ordering, required fields, and consistent composition of nested blocks.

### InstructionBlockBuilder

- Enforces required fields (`id`, `type`, `priority`, `content`).
- Provides fluent setters for `scope`, `conditions`, and `children`.
- Validates `children` count and inherited scope/conditions.

### ScopeBuilder

- Ensures at least one target is set (`applyTo`, `modes`, `tools`, `files`).
- Normalizes glob patterns and deduplicates arrays.

### ConditionBuilder

- Enforces `kind` and `value` presence.
- Allows composing multiple conditions for a block.

### ContentBuilder

- Enforces non-empty content.
- Supports either plain string content or structured content with `format` and `text`.

### SystemMessageBuilder

- Enforces required fields (`id`, `version`, `role`, `createdAt`, `updatedAt`).
- Accepts an ordered list of blocks and applies `priorityModel` defaults.
- Validates uniqueness of `InstructionBlock.id` across `blocks` and `children`.

### C# Example (Builder Composition)

```csharp
using System;
using System.Collections.Generic;

var content = ContentBuilder
	.Plain("Formatting rules for outputs.")
	.Build();

var linkContent = ContentBuilder
	.Markdown("Use link formatting rules for file references and KaTeX for equations.")
	.Build();

var scope = ScopeBuilder
	.Create()
	.WithModes("Ralph-Subagent")
	.WithTools("read_file", "apply_patch")
	.Build();

var condition = ConditionBuilder
	.Create("whenUserAsksForName", new { })
	.Build();

var formattingChild = InstructionBlockBuilder
	.Create("formatting-link-1", "formatting")
	.WithPriority(60)
	.WithContent(linkContent)
	.Build();

var formattingBlock = InstructionBlockBuilder
	.Create("formatting-1", "formatting")
	.WithPriority(60)
	.WithContent(content)
	.WithScope(scope)
	.WithChildren(formattingChild)
	.Build();

var systemMessage = SystemMessageBuilder
	.Create("sys-001", "2026-01-28")
	.WithRole("system")
	.WithCreatedAt(DateTimeOffset.Parse("2026-01-28T09:00:00Z"))
	.WithUpdatedAt(DateTimeOffset.Parse("2026-01-28T09:00:00Z"))
	.WithPriorityModel(new[]
	{
		"safety", "identity", "mode", "tooling", "editing", "formatting", "project", "advisory"
	})
	.AddBlock(InstructionBlockBuilder
		.Create("identity-1", "identity")
		.WithPriority(90)
		.WithContent(ContentBuilder.Plain("When asked for your name, respond with GitHub Copilot.").Build())
		.WithCondition(condition)
		.Build())
	.AddBlock(formattingBlock)
	.Build();
```
