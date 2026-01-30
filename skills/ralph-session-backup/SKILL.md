---
name: ralph-session-backup
description: Backup a specific Ralph session directory from .ralph-sessions to the Google Drive SwarmSessions folder with versioning support. Use when archiving or copying Ralph session data with all nested files and folders.
version: 1.2.0
---

# Ralph Session Backup

This skill provides a script to backup Ralph sessions with versioning support. Each session maintains multiple timestamped backups, organized under repository-specific folders to avoid naming conflicts between different repositories.

## Usage

To backup a specific session:

1. First, resolve the skill directory location (this skill's folder containing SKILL.md)
2. Navigate to the repository root directory where .ralph-sessions exists
3. Run the backup script with a path resolved relative to the skill directory: `python3 <skill_directory>/scripts/backup_session.py <session_name>`

**Important**: The script path must be resolved relative to the current skill directory location. This requires first determining where this skill is installed (e.g., in personal Copilot folders like .claude, .copilot, etc.) before executing the script.

### Versioning Structure

The script creates a versioned backup structure:

```txt
SwarmSessions/
└── <repo_name>/
    └── <session_name>/           # Session folder (YYMMDD-HHMMSS)
        ├── backup_YYMMDD-HHMMSS/    # Individual backup versions
        ├── backup_YYMMDD-HHMMSS/    # Another backup version
        └── latest/                  # Latest backup (symlink on Unix, copy on Windows)
```

### Command Options

- `python3 backup_session.py <session_name>` - Create a new versioned backup
- `python3 backup_session.py <session_name> --list` - List all existing versions
- `python3 backup_session.py <session_name> --cleanup=N` - Keep only the last N versions (default: 5)

### Recovery

To restore from a specific version:
1. Navigate to `SwarmSessions/<repo_name>/<session_name>/`
2. Copy the desired `backup_YYMMDD-HHMMSS` folder back to `.ralph-sessions/<session_name>`
3. Or use the `latest` folder for the most recent backup

## Requirements

- Python 3.8 or higher
- The session folder must exist in `.ralph-sessions`
- Write access to the Google Drive folder
- Cross-platform: Works on Windows and WSL (backs up to Windows filesystem)
