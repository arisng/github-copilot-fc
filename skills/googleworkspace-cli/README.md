# Google Workspace CLI Agent Skill

**Production-ready Copilot skill for unified Google Workspace automation across 18+ services.**

## Quick Overview

This skill provides Copilot agents with a unified CLI interface to:
- **Gmail**: Search, send, label, archive emails
- **Drive**: Create, upload, share, audit file permissions
- **Calendar**: Query events, check availability, create meetings
- **Sheets**: Read, write, append data
- **Docs**: Create, edit, share documents
- **Chat**: Post messages, create spaces
- **Admin**: Manage users, groups, organizational units

**No boilerplate.** No credential management headaches. Just `gws command args`.

---

## File Structure

```
googleworkspace-cli/
├── SKILL.md                           # Primary documentation (808 lines, 2500+ words)
│   ├── Overview
│   ├── What It Does
│   ├── Installation & Setup
│   ├── Quick Start Examples (3 real-world scenarios)
│   ├── Key Capabilities (by service)
│   ├── Common Patterns (4 reusable workflows)
│   ├── Security & Best Practices
│   ├── Troubleshooting (6+ issues with solutions)
│   └── References
│
├── references/
│   ├── recipes.md                     # 10+ copy-paste workflows
│   │   ├── Daily email triage
│   │   ├── Weekly meeting prep
│   │   ├── Bulk user onboarding
│   │   ├── Find meeting availability
│   │   ├── Export emails to Sheets
│   │   ├── Archive old emails
│   │   ├── Audit Drive permissions
│   │   └── More...
│   │
│   └── schema-reference.md            # Quick command reference by service
│       ├── Gmail API (11 operations)
│       ├── Drive API (14 operations)
│       ├── Calendar API (8 operations)
│       ├── Sheets API (10 operations)
│       ├── Docs API (9 operations)
│       ├── Chat API (11 operations)
│       ├── Admin SDK (15 operations)
│       ├── Output formats
│       ├── Common flags
│       ├── Error messages
│       └── Tips & tricks
│
└── scripts/
    └── examples.sh                    # 100+ copy-paste ready commands
        ├── Setup & verification
        ├── Gmail examples
        ├── Drive examples
        ├── Calendar examples
        ├── Sheets examples
        ├── Docs examples
        ├── Chat examples
        ├── Admin examples
        ├── Common patterns
        └── Help & debugging

Total: 31K+ SKILL.md, 13K references, 12K+ examples
```

---

## What's Included

### 1. **SKILL.md** (Primary Documentation)
- ✅ Comprehensive guide (808 lines, 2500+ words)
- ✅ YAML frontmatter with name, description, tags
- ✅ Installation instructions (step-by-step)
- ✅ 3 quick-start examples (search emails, create doc, find meeting slots)
- ✅ Key capabilities organized by service (60+ commands)
- ✅ 4 common patterns with full code
- ✅ Security section (credential storage, OAuth, dry-run mode, input sanitization, audit logging)
- ✅ 6+ troubleshooting scenarios
- ✅ Links to official resources

### 2. **recipes.md** (Reusable Workflows)
10+ production-ready recipes:
1. Daily email triage (search → label → reply)
2. Weekly meeting prep (calendar → doc → share)
3. Bulk user onboarding (CSV → create users → add groups)
4. Find meeting availability (freebusy → suggest slots → book)
5. Export emails to Sheets (search → extract → append)
6. Archive old emails (batch label/archive)
7. Audit Drive permissions (find violations → remediate)
8. Create team document (create → add content → share)
9. Send daily summary (stats → email)
10. Bulk share folder (multi-user sharing)

### 3. **schema-reference.md** (Quick Reference)
Command reference organized by service:
- Gmail: 11 operations (search, send, label, modify, etc.)
- Drive: 14 operations (list, create, upload, share, permissions, etc.)
- Calendar: 8 operations (list, create, update, freebusy, etc.)
- Sheets: 10 operations (create, read, write, append, export, etc.)
- Docs: 9 operations (create, append, insert, update, comment, etc.)
- Chat: 11 operations (spaces, messages, members, etc.)
- Admin: 15 operations (users, groups, org units, reports, etc.)

Plus:
- Output format table (JSON, CSV, YAML, table)
- Common flags reference
- Error messages & solutions
- Pagination examples
- Tips & tricks

### 4. **examples.sh** (Copy-Paste Ready)
100+ annotated commands:
- Setup & verification (auth, status, services)
- Gmail operations (search, send, labels, threads)
- Drive operations (list, create, upload, share, permissions)
- Calendar operations (list, create, recurring, freebusy)
- Sheets operations (create, read, write, append, export)
- Docs operations (create, append, insert, update, comment)
- Chat operations (spaces, messages, members)
- Admin operations (users, groups, org units, reports)
- Common patterns (chaining operations, filtering, exporting)
- Help & debugging (version, help, logs)

---

## How to Use This Skill

### For Agents (in instructions)

```markdown
# Your Agent Instructions

You have access to the **googleworkspace-cli** skill for Google Workspace automation.

## Available Commands

Use `gws` to automate workflows:
- **Gmail**: `gws gmail search`, `gws gmail send`, `gws gmail modify`
- **Drive**: `gws drive list`, `gws drive upload`, `gws drive share`
- **Calendar**: `gws calendar list`, `gws calendar create`
- **Sheets**: `gws sheets get`, `gws sheets append`
- **Docs**: `gws docs create`, `gws docs append`
- **Chat**: `gws chat send-message`
- **Admin**: `gws admin create-user`, `gws admin list-users`

## Before You Start

1. Verify gws is installed: `gws --version`
2. Check authentication: `gws auth status`
3. Review the skill docs in `~/.copilot/skills/googleworkspace-cli/` for:
   - Detailed setup instructions
   - Copy-paste examples by service
   - Security best practices
   - Common troubleshooting tips

## Example: Send Urgent Email Notification

```powershell
# Find urgent emails
$emails = gws gmail search --query 'subject:urgent is:unread' --limit 50 --output json | ConvertFrom-Json

# Process each
foreach ($email in $emails.messages) {
    gws gmail modify --id $email.id --add-label-ids "URGENT" --output json
}
```

See SKILL.md for 60+ more examples.
```

### For Users (consulting the skill)

1. **Start with SKILL.md** → Overview + Quick Start Examples
2. **Need a specific pattern?** → recipes.md has 10+ tested workflows
3. **Need command details?** → schema-reference.md for quick lookup
4. **Want copy-paste code?** → examples.sh for 100+ commands by service

### For Developers (extending the skill)

The skill is self-contained and uses only the `gws` CLI tool. To add new recipes:

1. Add to `references/recipes.md` with full script + usage
2. Update `schema-reference.md` if new operations are exposed
3. Add examples to `scripts/examples.sh`
4. Update SKILL.md's "Common Patterns" section if pattern is widely useful

---

## Security Checklist

✅ Credentials stored in OS credential manager (Windows Credential Manager, macOS Keychain, Linux pass)
✅ OAuth2 tokens auto-refreshed, never logged
✅ Input validation prevents path traversal and injection
✅ All API calls audit-logged (timestamp, user, operation, result)
✅ Sensitive data encrypted with AES-256-GCM
✅ Dry-run mode (`--dry-run`) available for all destructive operations
✅ Model Armor integration prevents data exfiltration

---

## Prerequisites

- **gws CLI** (Rust binary): https://github.com/googleworkspace/cli/releases
- **Google Workspace Account** with appropriate permissions
- **OAuth2 Setup**: One-time auth with `gws auth setup`
- **Copilot CLI** v1.0+ (for skill discovery)

---

## Quick Start

```powershell
# 1. Install gws
scoop install gws

# 2. Authenticate
gws auth setup

# 3. Test it
gws gmail search --query "is:unread" --limit 5 --output json

# 4. Use in Copilot agents
# Example: Agent instructions can now use gws commands!
```

---

## Documentation Map

| Need | File | Section |
|------|------|---------|
| Overview | SKILL.md | Overview + What It Does |
| Getting started | SKILL.md | Installation & Setup, Quick Start Examples |
| Real-world workflows | recipes.md | 10+ recipes with full code |
| Command reference | schema-reference.md | By-service operation tables |
| Copy-paste examples | examples.sh | 100+ commands organized by service |
| Troubleshooting | SKILL.md | Troubleshooting section |
| Security | SKILL.md | Security & Best Practices |
| API links | SKILL.md | References section |

---

## Version

**v1.0** (2026-04-01)

Initial release:
- 18+ service APIs (Gmail, Drive, Calendar, Sheets, Docs, Chat, Admin, etc.)
- Security hardening (encryption, OAuth, audit logging)
- Multi-format output (JSON, CSV, YAML, table)
- 10+ tested recipes
- 100+ example commands
- Comprehensive troubleshooting guide

---

## Support

For help:
1. Check SKILL.md's Troubleshooting section
2. Review examples.sh for your use case
3. Check gws GitHub: https://github.com/googleworkspace/cli
4. Review official docs: https://developers.google.com/workspace
5. File an issue with: `gws --version && gws auth status`

---

## License

This skill documents the open-source `gws` CLI tool. See https://github.com/googleworkspace/cli for license.

---

**Happy automating!** 🚀
