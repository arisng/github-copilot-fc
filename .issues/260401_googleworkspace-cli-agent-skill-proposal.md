---
date: 2026-04-01
type: RFC
severity: High
status: Open for Comment
---

# RFC: Google Workspace CLI Agent Skill

## Summary

Propose a new **googleworkspace-cli-agent-skill** that integrates the Google Workspace CLI (gws) Rust tool into the Copilot ecosystem. This skill enables Copilot agents (CLI and VS Code) to orchestrate 18+ Google Workspace services (Drive, Gmail, Calendar, Sheets, Docs, Chat, Admin, etc.) through a unified, structured command interface without requiring boilerplate authentication or API knowledge. The skill provides security-hardened access, multi-format output, and pre-built helper functions for common enterprise workflows.

## Motivation

### Problem Statement

Today, agents working with Google Workspace require:
- **Manual API integration**: Each service needs separate authentication setup, error handling, and response parsing
- **Boilerplate code**: Agents must write repetitive credential management, multi-step workflows, and pagination logic
- **Security gaps**: Credentials often leak into logs; sensitive data isn't encrypted in transit
- **Scattered documentation**: No unified interface; agents must learn 18+ different API styles
- **No workflow support**: Multi-step operations (search → paginate → filter → act) are fragile and require careful state management

The **googleworkspace-cli (gws)** project already solves these problems at the CLI level: it provides self-updating command generation from Discovery Service, 100+ pre-built agent skills (including 18 service APIs, 21 helpers, 50 recipes, and 10 personas), OAuth2 with AES-256-GCM encryption, and Model Armor integration.

### Solution

Expose gws as a reusable Copilot agent skill so that Copilot agents can:
1. Call gws commands with structured parameters (no shell escaping)
2. Access 18+ services through a consistent interface
3. Leverage pre-built helper skills and recipes without reinventing workflows
4. Get encrypted credential management and Model Armor protection out of the box
5. Parse multi-format output (JSON, CSV, YAML, table) natively

### Why Now?

- gws is production-ready (100+ skills, proven security model, 18+ service APIs)
- Copilot agents are increasingly autonomous and need enterprise API access
- Enterprises demand Workspace integration; gws fills a gap that competitors don't have
- The skill leverages existing gws infrastructure, reducing implementation burden

## Detailed Design

### Architecture

The skill exposes gws as a **command-driven interface**:

```
Agent ──[Copilot skill]──> gws CLI (Rust)
                              ├── OAuth2 flow + credential cache
                              ├── 18+ Discovery Service endpoints
                              ├── Helper skills & recipes
                              ├── Model Armor enforcement
                              └── Multi-format output (JSON/CSV/YAML/table)
```

### What's Included

#### Service APIs (18+)
- **Drive**: File/folder CRUD, sharing, permissions, team drives
- **Gmail**: Email search, read, send, labels, threads
- **Calendar**: Events, recurring patterns, availability, sharing
- **Sheets**: Data manipulation, formulas, charts, sharing
- **Docs**: Document creation, content management, collaboration
- **Chat**: Messages, threads, spaces, webhooks
- **Admin**: Users, groups, organizational units, policies
- **Plus**: Forms, Tasks, Keep, Sites, Classroom, Meet, Groups, etc.

#### Helper Skills (21+)
- Batch operations (bulk user creation, email send)
- Pagination handlers (automatic page iteration)
- Event subscriptions (watch resources, push notifications)
- Dry-run modes (preview actions without execution)
- Retry logic with exponential backoff
- Error decoders (actionable hints for common failures)

#### Pre-built Recipes (50+)
- Email triage (search, label, archive workflows)
- Document collaboration (comment threads, version tracking)
- Meeting prep (calendar fetch, attendee availability)
- Task tracking (create, assign, update lifecycle)
- Content distribution (bulk Drive sharing)
- Admin workflows (user onboarding/offboarding)
- Customer support (email history + Sheets CRM)

#### Security Model
- **OAuth2 with credential caching** (token refresh automatic)
- **AES-256-GCM encryption** for sensitive data (credentials, attachment content)
- **Model Armor integration**: Prevents LLM misuse (e.g., exfiltration attempts)
- **Audit logging**: All API calls logged with timestamp, user, scope

### Out of Scope
- **Custom API extensions**: Only pre-built Discovery Service APIs
- **Beta services**: Only GA services (Workspace doesn't officially support beta)
- **Webhook re-implementation**: Agents use pre-built subscription helpers
- **Advanced admin features**: Policies, audit log search (use gws CLI directly for these)

### Skill Structure

```
skills/googleworkspace-cli-agent-skill/
├── SKILL.md                      # Skill metadata + overview
├── scripts/
│   ├── install-gws.sh            # Download & verify gws binary
│   ├── test-integration.ps1      # Integration tests
│   └── gws-wrapper.ps1           # PowerShell wrapper for agent calls
├── references/
│   ├── service-catalog.md        # 18+ services quick reference
│   ├── helper-skills.md          # 21 helper functions
│   ├── recipes.md                # 50 recipes with examples
│   ├── auth-flow.md              # OAuth2 setup guide
│   └── security-model.md         # Encryption, Model Armor
└── assets/
    └── gws-command-schema.json   # Auto-generated command spec
```

### Command Interface

**Example 1: Search Email**
```powershell
Invoke-GwsCommand -Service gmail -Command search `
  -Parameters @{ query = "from:boss subject:urgent"; maxResults = 10 }
```

**Example 2: Create Google Meet Event**
```powershell
Invoke-GwsCommand -Service calendar -Command create `
  -Parameters @{
      summary = "Team Sync"
      start = "2026-04-15T10:00:00Z"
      conferenceData = @{ conferenceSolution = @{ key = @{ type = "hangoutsMeet" } } }
  }
```

**Example 3: Batch User Creation (Recipe)**
```powershell
Invoke-GwsRecipe -Recipe "user-onboarding" `
  -Parameters @{ csvPath = "users.csv"; ou = "/Engineering" }
```

### Multi-Format Output

All commands support output formatting:
```
gws gmail search --query "from:boss" --output json   # Structured JSON
gws gmail search --query "from:boss" --output csv    # CSV export
gws gmail search --query "from:boss" --output yaml   # YAML readable
gws gmail search --query "from:boss" --output table  # Human-readable table
```

Agents can choose format based on downstream consumption.

### Error Recovery

- **Dry-run mode**: Preview changes before committing
  ```powershell
  Invoke-GwsCommand -DryRun -Service drive -Command share `
    -Parameters @{ fileId = "123"; role = "editor"; emailAddress = "user@example.com" }
  ```

- **Actionable hints**: Errors include remediation steps
  ```
  ERROR: Permission denied on folder 'myteamdrive'
  HINT: Ensure you have editor+ access. Check sharing permissions: gws drive info --id myteamdrive
  HINT: Or request access from: owner@example.com
  ```

- **Retry with backoff**: Built-in exponential backoff for transient failures

## Design Considerations

### 1. Security & Encryption

**Challenge**: Protecting credentials and sensitive data in agent contexts

**Approach**:
- OAuth2 flow stores tokens in OS credential store (Windows Credential Manager, macOS Keychain, Linux pass)
- Agent requests never include raw credentials (skill handles auth internally)
- Sensitive payloads (email bodies, document content) encrypted with AES-256-GCM before storage
- Model Armor prevents agents from attempting credential exfiltration or policy bypass

**Risk Mitigation**:
- Audit log every API call (user, timestamp, scope, resource ID)
- Credential rotation enforced via gws configuration
- Skill validates OAuth2 scopes match requested operations

### 2. Multi-Step Workflows

**Challenge**: Agents need to paginate, filter, and transform large result sets

**Approach**:
- Pagination handlers built into skill:
  ```powershell
  Invoke-GwsCommand -Service gmail -Command search -Paginate -PageSize 100 `
    -ParameterFile results.json
  ```
- Result streaming for large datasets (avoids memory bloat)
- Helper skill for filtering:
  ```powershell
  Invoke-GwsHelper -Helper filter-emails -Parameters @{ results = $emails; predicate = "label:urgent" }
  ```

**Timeout Handling**:
- Long-running operations support checkpointing (save state, resume later)
- Agents can poll subscription status instead of blocking

### 3. Output Flexibility

**Challenge**: Agents work with different downstream systems (databases, LLMs, file systems)

**Approach**:
- Native output format support (JSON, CSV, YAML, table)
- Skill includes transformation helpers:
  ```powershell
  ConvertFrom-GwsOutput -Format json -To csv
  ConvertFrom-GwsOutput -Format table -To json
  ```

### 4. Error Recovery

**Challenge**: Agents must recover from transient failures, rate limits, and invalid requests

**Approach**:
- Automatic retry with exponential backoff (transient errors)
- Distinguish recoverable (429, 503) from unrecoverable (401, 403) errors
- Return error category + hint:
  ```json
  {
    "error": "RATE_LIMIT",
    "message": "Quota exceeded",
    "retryAfter": 60,
    "hint": "Wait 60s or upgrade to higher quota tier"
  }
  ```

## Implementation Plan

### Phase 1: Foundation (Weeks 1-2)
1. Create `SKILL.md` with frontmatter (name: `googleworkspace-cli-agent-skill`, tags: `google-workspace`, `gws`, `enterprise`)
2. Document gws binary installation and verification
3. Create skill wrapper function (`Invoke-GwsCommand`)
4. Publish skill to `~/.copilot/skills/googleworkspace-cli-agent-skill/`

### Phase 2: Service APIs (Weeks 3-4)
1. Auto-generate command schema from gws Discovery Service
2. Document all 18+ service APIs in `service-catalog.md`
3. Create CLI-specific agent (`googleworkspace-cli-agent/cli/`) and VS Code variant
4. Add 5 example workflows (email triage, calendar events, Sheets updates, Drive sharing, Chat messages)

### Phase 3: Helper Skills (Week 5)
1. Document 21 helper skills in `helper-skills.md`
2. Create wrapper functions for pagination, filtering, batch operations
3. Add integration tests for common patterns

### Phase 4: Recipes & Security (Week 6)
1. Document 50 pre-built recipes with examples
2. Add OAuth2 setup guide and security model documentation
3. Add Model Armor configuration guide
4. Publish complete skill to all personal folders

### Phase 5: Testing & Documentation (Week 7)
1. Integration tests (Service API compliance)
2. Security audit (credential handling, encryption)
3. Performance benchmarks (pagination, large result sets)
4. Publish skill to plugin registry

## Success Criteria

1. **Skill integrates cleanly**
   - Available in `~/.copilot/skills/`
   - Listed in Copilot CLI skill discovery
   - Agents can `invoke` the skill with structured parameters

2. **All 18+ service APIs accessible**
   - Command schema auto-generated and accurate
   - Each service tested with at least one operation (CRUD)
   - Error messages are actionable (include hints)

3. **Multi-step workflows work reliably**
   - Pagination tested with 1000+ item datasets
   - Long-running operations checkpoint and resume correctly
   - Rate limit recovery automatic (no manual intervention)

4. **Security model validated**
   - Credentials never logged or exposed to agents
   - Encryption in place for sensitive data
   - Model Armor prevents credential/policy bypass
   - Audit log comprehensive (100% of API calls tracked)

5. **Documentation complete**
   - Service catalog quick reference
   - 5+ example workflows with copy-paste code
   - OAuth2 setup guide (< 5 minutes)
   - Common error scenarios + hints

6. **Agents can accomplish real tasks**
   - Email triage: Search + label + archive in single workflow
   - Meeting prep: Fetch calendar + check attendee availability
   - Document collaboration: Create doc + add collaborators + share
   - Admin: Bulk user onboarding from CSV
   - Customer support: Email history + CRM lookups

## Unresolved Questions

- [ ] Should the skill auto-detect and update gws CLI on startup, or require manual installation?
- [ ] How do we handle OAuth2 token refresh in long-running agent sessions? (polling vs. lifecycle hook)
- [ ] Should recipes be bundled in the skill or fetched dynamically from gws?
- [ ] Do we support multiple Google Workspace accounts (domain switching) per agent session?
- [ ] How aggressively should we rate-limit agent API calls to stay within quotas? (configurable?)
- [ ] Should we expose gws admin audit logs (which require special permissions) or keep them out of scope?

## References

### Official Resources
- **GitHub**: https://github.com/googleworkspace/cli
- **gws Documentation**: https://github.com/googleworkspace/cli/tree/main/docs
- **Google Workspace APIs**: https://developers.google.com/workspace/apis
- **Discovery Service Spec**: https://developers.google.com/discovery/v1/reference

### Related Work in This Ecosystem
- **Ralph v2 Multi-Agent Orchestration**: Demonstrates state machine pattern for coordinating agents (applicable to multi-step workflows)
- **Existing Google Calendar Skill** (`google-calendar-cli`): Shows credential management, event operations, and pagination patterns
- **gws Pre-built Skills**: 100+ existing recipes (email triage, document collab, meeting prep, etc.) provide templates for agent workflows

### Dependencies
- **gws CLI** (Rust binary): Must be installed and available in `$PATH`
- **OAuth2 credentials**: User must authenticate gws once (one-time setup per domain)
- **Google Workspace Admin Console**: For granting API scopes at domain level
- **Copilot CLI**: v1.0+ (for skill discovery and invoke semantics)

### Future Integration Points
- **Copilot Spaces**: Share workflows with team (credential pooling, shared audit logs)
- **OpenSpec**: Define gws commands as behavioral specs (verify agents stay within scope)
- **Model Armor**: Prevent agents from exfiltrating data or escalating privileges
- **Ralph v2 Knowledge Base**: Document gws service APIs as discoverable entities

---

## Appendix: Example Workflows

### Workflow 1: Email Triage (Urgent → Label → Reply)
```powershell
# Find urgent emails from leadership
$urgent = Invoke-GwsCommand -Service gmail -Command search `
  -Parameters @{ query = "from:boss OR from:ceo subject:urgent"; maxResults = 50 }

# Apply "urgent" label to each
foreach ($email in $urgent.messages) {
    Invoke-GwsCommand -Service gmail -Command modify `
      -Parameters @{ id = $email.id; addLabelIds = @["URGENT"] }
}

# Auto-reply with acknowledgment
$reply = Invoke-GwsCommand -Service gmail -Command send `
  -Parameters @{ 
      to = $urgent.messages[0].headers.from
      subject = "Re: $(($urgent.messages[0].headers.subject))"
      body = "Thank you for your message. I've prioritized this and will respond within 2 hours."
  }
```

### Workflow 2: Meeting Prep (Calendar + Attendee Availability)
```powershell
# Get today's meetings
$meetings = Invoke-GwsCommand -Service calendar -Command list `
  -Parameters @{ timeMin = (Get-Date).ToUniversalTime().ToString('o'); maxResults = 10 }

# For each meeting, fetch attendee availability
foreach ($meeting in $meetings.items) {
    $attendees = $meeting.attendees | Select-Object -ExpandProperty email
    $freebusy = Invoke-GwsCommand -Service calendar -Command freebusy `
      -Parameters @{ items = @(@{ id = $attendees }) }
    Write-Host "Meeting: $($meeting.summary)"
    Write-Host "Attendee Availability: $(ConvertTo-Json $freebusy)"
}
```

### Workflow 3: Document Collaboration (Create + Share + Invite Comments)
```powershell
# Create a new Google Doc
$doc = Invoke-GwsCommand -Service docs -Command create `
  -Parameters @{ title = "Q2 OKRs" }

# Share with team
Invoke-GwsCommand -Service drive -Command share `
  -Parameters @{
      fileId = $doc.documentId
      role = "editor"
      emailAddress = "team@example.com"
  }

# Insert a comment request
Invoke-GwsCommand -Service docs -Command insertComment `
  -Parameters @{
      documentId = $doc.documentId
      content = "Please review and add your goals by Friday"
      resolved = $false
  }
```

### Workflow 4: Admin Onboarding (Batch CSV → Accounts)
```powershell
# Use pre-built recipe
Invoke-GwsRecipe -Recipe "user-onboarding" `
  -Parameters @{
      csvPath = "new-hires.csv"  # Columns: firstName, lastName, email, department
      ou = "/Engineering"
      groupsToAdd = @["all-hands", "engineers"]
      dryRun = $true              # Preview first
  }

# After review, execute (dryRun = $false)
Invoke-GwsRecipe -Recipe "user-onboarding" `
  -Parameters @{
      csvPath = "new-hires.csv"
      ou = "/Engineering"
      groupsToAdd = @["all-hands", "engineers"]
  }
```

### Workflow 5: Customer Support Lookup (Gmail + Sheets)
```powershell
# Search customer emails
$emails = Invoke-GwsCommand -Service gmail -Command search `
  -Parameters @{ query = "from:customer@example.com"; maxResults = 20 }

# Look up customer record in Sheets
$sheet = Invoke-GwsCommand -Service sheets -Command get `
  -Parameters @{ spreadsheetId = "ABC123"; range = "'Customer DB'!A:F" }

# Match email sender to sheet row
$customerRecord = $sheet.values | Where-Object { $_[1] -eq $emails.messages[0].headers.from }
Write-Host "Customer: $($customerRecord[0])"
Write-Host "Email History: $(ConvertTo-Json $emails)"
Write-Host "Record: $(ConvertTo-Json $customerRecord)"
```

