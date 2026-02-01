---
description: Weekly maintenance workflow for the ag-ui-blazor-agent-framework skill
---

# Skill Maintenance Workflow

Run this workflow weekly or when dependencies update to keep the skill current and aligned with framework/protocol changes.

## 1. Check Package Versions

**Frequency**: Weekly or on patch releases

- Query latest NuGet releases: `Microsoft.Agents.AI.Hosting.AGUI.AspNetCore`, `Microsoft.Extensions.AI`, `Microsoft.AgentFramework`
- Flag major/minor version bumps; review release notes and breaking changes
- Test new versions locally if available
- Update version constraints in SKILL.md if needed
- Check for security advisories via NuGet.org or GitHub Security Advisories

**Tools**: NuGet.org, GitHub Releases, [Microsoft Agent Framework releases](https://github.com/microsoft/agent-framework)

## 2. Monitor Official Documentation

**Frequency**: Weekly

- Scan [Microsoft Learn Agent Framework docs](https://learn.microsoft.com/en-us/agent-framework/) for updates (MapAGUI patterns, IChatClient, tool definitions)
- Check [Microsoft Agent Framework GitHub](https://github.com/microsoft/agent-framework) for spec changes, issues, examples
- Review [AG-UI protocol documentation](https://docs.ag-ui.com/) for protocol feature updates
- Check [CopilotKit releases](https://github.com/CopilotKit/CopilotKit) for new frontend components or AG-UI pattern updates

## 3. Validate Code Examples

**Frequency**: Bi-weekly or after framework updates

- Run smoke tests on workflow steps: MapAGUI endpoint creation, IChatClient wiring, tool definition via AIFunctionFactory
- Verify AG-UI protocol event structures match current spec (especially SSE message format, ConversationId handling)
- Check Blazor component patterns against latest templates (`dotnet new blazor`)
- Test SSE streaming and tool result serialization with current Agent Framework version

## 4. Update References

**Frequency**: As needed

- Re-fetch updated Microsoft Learn articles and save into `references/`
- Archive deprecated references with `[DEPRECATED YYYY-MM-DD]` prefix in filename
- Add new references for emerging patterns (e.g., new GenUI components, protocol extensions)
- Verify all reference links are current and not returning 404

## 5. Protocol Compatibility Check

**Frequency**: Monthly or after protocol spec changes

- Compare current AG-UI protocol version vs skill assumptions (7 supported features, SSE/HTTP transport)
- Test MapAGUI endpoint with different IChatClient implementations (Azure OpenAI, OpenAI, Ollama)
- Verify tool metadata serialization via AIFunctionFactory (JSON schema contracts)
- Test approval workflow serialization (ApprovalRequiredAIFunction → protocol events)
- Ensure ConversationId session management works correctly across concurrent requests

## 6. Industry Standards Audit

**Frequency**: Quarterly

- Cross-reference with CopilotKit AG-UI patterns and [AG-UI Dojo](https://dojo.ag-ui.com/microsoft-agent-framework-dotnet) examples
- Review WCAG accessibility standards (WCAG 2.1 Level AA minimum for frontend)
- Check ARIA patterns for chat interfaces and tool approval dialogs
- Check security advisories for dependencies and review SSE security (CORS, auth tokens)

## 7. Update Workflow & Guardrails

**Frequency**: As needed

- Revise workflow steps in SKILL.md if MapAGUI patterns, IChatClient APIs, or tool definition syntax changes
- Update guardrails for new Agent Framework anti-patterns or SSE-specific pitfalls
- Remove obsolete steps or notes
- Test updated workflow against a sample project (MapAGUI + IChatClient + tools)

## 8. Version & Changelog

**Frequency**: Per update cycle

- Increment `version` in SKILL.md frontmatter if updates are substantial
- Document changes in git commit message or a CHANGELOG.md if maintained
- Tag releases in GitHub (e.g., v1.2.0)

---

## Quick Checklist

```
Weekly:
  [ ] Check package versions (NuGet)
  [ ] Monitor Microsoft Learn + AG-UI GitHub

Bi-weekly:
  [ ] Validate code examples

Monthly:
  [ ] Protocol compatibility check

Quarterly:
  [ ] Industry standards audit (WCAG, security)

As-needed:
  [ ] Update references
  [ ] Revise workflow steps
  [ ] Increment version
```
