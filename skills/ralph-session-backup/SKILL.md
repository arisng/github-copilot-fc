---
name: ralph-session-backup
description: Backup a specific Ralph session directory from .ralph-sessions to the OneDrive SwarmSessions folder. Use when archiving or copying Ralph session data with all nested files and folders.
version: 1.0.0
---

# Ralph Session Backup

This skill provides a script to backup Ralph sessions.

## Usage

To backup a specific session:

1. Identify the session name (the folder name in `.ralph-sessions`).

2. Run the backup script: `python scripts/backup_session.py <session_name>`

The script will copy the entire session folder from `.ralph-sessions/<session_name>` to the user's OneDrive SwarmSessions folder (e.g., `C:\Users\<username>\OneDrive\SwarmSessions\<session_name>`), including all nested folders and files.

If the destination already exists, it will be overwritten.

## Requirements

- Python 3.8 or higher
- The session folder must exist in `.ralph-sessions`
- Write access to the OneDrive folder
