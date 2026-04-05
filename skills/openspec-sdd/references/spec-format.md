# Spec Format Reference

Templates and rules for writing OpenSpec spec files and delta specs.

## Contents

- [Spec Format Reference](#spec-format-reference)
  - [Contents](#contents)
  - [Spec File Template](#spec-file-template)
  - [Delta Spec Markers](#delta-spec-markers)
    - [REMOVED format](#removed-format)
    - [RENAMED format](#renamed-format)
    - [MODIFIED format](#modified-format)
    - [ADDED format](#added-format)
  - [Delta Spec Examples](#delta-spec-examples)
    - [Adding a new requirement](#adding-a-new-requirement)
    - [Renaming then modifying a requirement](#renaming-then-modifying-a-requirement)
  - [RFC 2119 Keyword Guide](#rfc-2119-keyword-guide)

---

## Spec File Template

For `openspec/specs/<workflow>/<domain>/spec.md` (or `openspec/specs/<domain>/spec.md` for single-system repos):

```markdown
# <Domain> Specification

## Purpose
High-level description of this capability.

## Requirements

### Requirement: <Name>
The system SHALL/MUST/SHOULD/MAY <behavior statement>.

#### Scenario: <Scenario Name>
- **GIVEN** <precondition>
- **WHEN** <action>
- **THEN** <expected outcome>
- **AND** <additional outcome>
```

**Rules:**
- Externally observable behavior only — no implementation details (those go in `design.md`)
- Every requirement needs at least one scenario
- Use RFC 2119 keywords for obligation level (see below)

---

## Delta Spec Markers

Delta specs live in `openspec/changes/<name>/specs/` and describe *only the changes*, not the full spec.

| Marker | Use when |
|---|---|
| `## ADDED` | New requirement being introduced |
| `## MODIFIED` | Existing requirement changing its behavior |
| `## REMOVED` | Existing requirement being deprecated/deleted |
| `## RENAMED` | Requirement changing its identifier/name |

**Delta merge order during archive**: RENAMED → REMOVED → MODIFIED → ADDED

### REMOVED format
```markdown
## REMOVED

### Requirement: <Original Name>
**Reason**: <Why this requirement is removed>
```

### RENAMED format
```markdown
## RENAMED

### Requirement: <Original Name>
**FROM**: `<Original Name>`
**TO**: `<New Name>`
```

### MODIFIED format
```markdown
## MODIFIED

### Requirement: <Name>
The system SHALL <updated behavior statement>.

#### Scenario: <Updated Scenario Name>
- **GIVEN** <updated precondition>
- **WHEN** <updated action>
- **THEN** <updated expected outcome>
```

### ADDED format
```markdown
## ADDED

### Requirement: <New Name>
The system SHALL <new behavior statement>.

#### Scenario: <Scenario Name>
- **GIVEN** <precondition>
- **WHEN** <action>
- **THEN** <expected outcome>
```

---

## Delta Spec Examples

### Adding a new requirement
```markdown
## ADDED

### Requirement: Rate Limit Enforcement
The system SHALL enforce a per-user request rate limit of 100 requests per 60-second window.

#### Scenario: Request exceeds limit
- **GIVEN** an authenticated user has reached the request limit
- **WHEN** the user sends another request within the same window
- **THEN** the system returns HTTP 429
- **AND** the response includes a `Retry-After` header
```

### Renaming then modifying a requirement
```markdown
## RENAMED

### Requirement: User Authentication
**FROM**: `Login Flow`
**TO**: `User Authentication`

## MODIFIED

### Requirement: User Authentication
The system SHALL support both password and OAuth2 authentication methods.

#### Scenario: OAuth2 login
- **GIVEN** a user initiates login via OAuth2
- **WHEN** the OAuth2 provider redirects with a valid code
- **THEN** the system creates a session and redirects to the dashboard
```

---

## RFC 2119 Keyword Guide

| Keyword | Meaning | Use when |
|---|---|---|
| **SHALL** / **MUST** | Absolute requirement | Core functional behavior that must always hold |
| **SHALL NOT** / **MUST NOT** | Absolute prohibition | Behavior that is never acceptable |
| **SHOULD** | Recommended | Best practice; valid reasons may exist to deviate |
| **SHOULD NOT** | Not recommended | Discouraged but not prohibited |
| **MAY** | Optional | Permitted behavior that isn't required |

**Common mistakes:**
- Using "will" or "can" instead of RFC 2119 keywords — these are ambiguous
- Using SHALL for optional features — use MAY instead
- Mixing implementation details into requirements — keep specs behavioral
