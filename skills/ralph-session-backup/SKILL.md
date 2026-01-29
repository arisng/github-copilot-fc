---
name: ralph-session-backup
description: Backup a specific Ralph session directory from .ralph-sessions to the Google Drive SwarmSessions folder. Use when archiving or copying Ralph session data with all nested files and folders.
version: 1.1.0
---

# Ralph Session Backup

This skill provides a script to backup Ralph sessions using an overwrite strategy for existing destination folders. Sessions are organized under a repository-specific folder to avoid naming conflicts between different repositories.

## Usage

To backup a specific session:

1. Navigate to the repository root directory
2. Run the backup script: `python3 skills/ralph-session-backup/scripts/backup_session.py <session_name>`

The script will copy the entire session folder from `.ralph-sessions/<session_name>` to the user's Google Drive SwarmSessions folder under a repository-specific subfolder (e.g., `C:\Users\<username>\GoogleDrive\SwarmSessions\<repo_name>\<session_name>`), including all nested folders and files.

If the destination already exists, existing files will be overwritten with the new backup.

## Requirements

- Python 3.8 or higher
- The session folder must exist in `.ralph-sessions`
- Write access to the Google Drive folder
- Cross-platform: Works on Windows and WSL (backs up to Windows filesystem)
