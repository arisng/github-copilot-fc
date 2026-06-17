# RFC (Request for Comments)

Use this template when proposing a design or change that needs team discussion and consensus. RFCs are for technical proposals, API changes, protocol specifications, or significant architectural shifts that require community input before implementation.

## Template

```markdown
---
date: YYYY-MM-DD
type: RFC
severity: Critical | High | Medium | Low | N/A
status: Open for Comment | Proposed | Accepted | In Progress
---

# RFC: [Topic]

## Summary
[One paragraph explanation.]

## Motivation
[Why do we need this? What problem does it solve?]

## Detailed Design
[How will it work? API changes, data models, etc.]

## Alternatives Considered
- [Option A]: [Why rejected?]

## Unresolved Questions
- [ ] Question 1?
```

## Field Descriptions

- **date**: ISO 8601 date when the RFC was opened
- **type**: Always "RFC" for this template
- **severity**: Impact scope — Critical (affects entire system), High (affects major component), Medium (affects specific feature), Low (minor change)
- **status**: Open for Comment (soliciting feedback), Proposed (proposal ready), Accepted (consensus reached), In Progress (implementation underway)

## Writing Tips

- **Summary**: Make it scannable. Someone should understand the proposal in 30 seconds.
- **Motivation**: Clearly articulate the problem or need. Why now? What's the cost of not doing it?
- **Detailed Design**: Show your thinking. Include examples, API signatures, or flow diagrams. This is where you make the concrete.
- **Alternatives**: Show you've thought broadly. Explain trade-offs — why this approach over others?
- **Unresolved Questions**: Be transparent about unknowns. Invite team input on specific open questions.

## RFC Lifecycle

1. **Open for Comment**: Author posts RFC and gathers feedback (typically 1-2 weeks)
2. **Proposed**: Author addresses feedback, RFC enters decision phase
3. **Accepted**: Team consensus reached; plan implementation
4. **In Progress**: Implementation underway; RFC documents the realized design

## Example

```markdown
---
date: 2026-03-05
type: RFC
severity: High
status: Open for Comment
---

# RFC: Pluggable authentication providers

## Summary
Introduce a pluggable authentication system that allows projects to implement custom auth providers (OAuth, SAML, API key, etc.) without forking the codebase.

## Motivation
Today, authentication is hard-coded to JWT-based OAuth. Some enterprises need SAML or API-key auth. We're losing deals because of this inflexibility. A pluggable system unblocks multiple auth patterns without maintaining separate forks.

## Detailed Design
- Define `AuthProvider` interface with methods: `authenticate()`, `validate()`, `refresh()`, `logout()`
- Load providers via `auth.config.js`: `{ providers: [new OAuth2Provider(), new SAMLProvider()] }`
- Route incoming auth requests to the appropriate provider based on metadata or header
- Providers return a standardized `AuthResult { user, token, expiresAt }`
- Example: SAML provider could delegate to a library like `@node-saml/node-saml`

## Alternatives Considered
- **Strategy pattern in business logic**: Requires code changes every time a new provider is added. Rejected — too rigid.
- **Middleware chain**: Each middleware checks if it can handle the auth. Rejected — ordering complexity and unclear error semantics.

## Unresolved Questions
- [ ] Should providers be loaded dynamically (runtime) or statically (build-time)?
- [ ] How do we handle multi-provider scenarios (e.g., SAML + API key)?
- [ ] What's the test plan for custom providers?
```
