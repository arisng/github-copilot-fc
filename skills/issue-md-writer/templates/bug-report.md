# Bug Report / Technical Issue

Use this template when something broke, isn't working correctly, or has degraded functionality. Include root cause analysis, the solution applied, and actionable prevention steps.

## Template

```markdown
---
date: YYYY-MM-DD
type: Bug
severity: Critical | High | Medium | Low | N/A
status: Resolved | In Progress | Investigating
---

# [Concise Title]

## Problem
[What broke? What is the impact? Be specific.]

## Root Cause
[Why did it happen? Trace to origin.]

## Solution
[How was it fixed? Show code before/after.]

## Lessons Learned
- [Actionable takeaway]

## Prevention
- [ ] [Checklist item]
```

## Field Descriptions

- **date**: ISO 8601 date when the issue was discovered or resolved
- **type**: Always "Bug" for this template
- **severity**: Impact level — Critical (system down), High (major feature broken), Medium (minor feature affected), Low (cosmetic), or N/A if unknown
- **status**: Resolved (issue fixed and verified), In Progress (actively being fixed), or Investigating (root cause not yet found)

## Writing Tips

- **Problem**: Be specific about user impact. Include error messages, failed operations, or affected features.
- **Root Cause**: Explain the "why" — bad assumption, missing null check, race condition, etc. Link to code if possible.
- **Solution**: Show the fix clearly. If complex, explain the approach before the code.
- **Prevention**: Think about what could have caught this earlier — tests, monitoring, code review checks, etc.

## Example

```markdown
---
date: 2026-03-10
type: Bug
severity: High
status: Resolved
---

# Login token expiration causes 500 errors

## Problem
Users logged in for more than 30 minutes are experiencing 500 errors when performing actions. The issue affects ~15% of daily active users during high-traffic periods.

## Root Cause
The session middleware was not refreshing expired JWT tokens. When a token expired mid-request, the auth check failed and threw an unhandled exception instead of gracefully refreshing.

## Solution
Added token refresh logic in the auth middleware before the protected route handler:

```typescript
if (isTokenExpired(token)) {
  token = await refreshToken(token);
  req.headers.authorization = `Bearer ${token}`;
}
```

## Lessons Learned
- Token refresh should happen transparently without user knowledge
- Expired tokens should trigger refresh, not error
- Error recovery paths need explicit handling

## Prevention
- [ ] Add integration test for token refresh flow
- [ ] Add monitoring alert for high 500 error rate
- [ ] Code review checklist: "Are error paths handled for auth failures?"
```
