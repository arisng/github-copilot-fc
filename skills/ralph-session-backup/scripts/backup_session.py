#!/usr/bin/env python3
"""
Ralph Session Backup Script

Copies a specific session folder from .ralph-sessions to GoogleDrive SwarmSessions.
"""

import os
import shutil
import sys
import platform
import subprocess

def main():
    if len(sys.argv) != 2:
        print("Usage: python backup_session.py <session_name>")
        sys.exit(1)

    session_name = sys.argv[1]

    # Paths relative to the script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    skill_dir = os.path.dirname(script_dir)
    workspace_root = os.path.dirname(os.path.dirname(skill_dir))

    source = os.path.join(workspace_root, '.ralph-sessions', session_name)
    if platform.system() == 'Linux' and 'microsoft' in platform.uname().release.lower():
        # WSL: Get Windows username and backup to Windows filesystem
        try:
            windows_user = subprocess.run(['cmd.exe', '/c', 'echo %USERNAME%'], capture_output=True, text=True, check=True).stdout.strip()
        except subprocess.CalledProcessError:
            print("Error: Could not determine Windows username in WSL")
            sys.exit(1)
        dest_base = f'/mnt/c/Users/{windows_user}/GoogleDrive/SwarmSessions'
    else:
        # Windows
        dest_base = os.path.join(os.path.expanduser('~'), 'GoogleDrive', 'SwarmSessions')
    os.makedirs(dest_base, exist_ok=True)
    dest = os.path.join(dest_base, session_name)

    print(f"Backing up session '{session_name}' from {source} to {dest}")

    if not os.path.exists(source):
        print(f"Error: Session '{session_name}' does not exist in .ralph-sessions")
        sys.exit(1)

    if not os.path.isdir(source):
        print(f"Error: '{session_name}' is not a directory")
        sys.exit(1)

    try:
        # Copy the entire directory tree, overwriting existing files
        shutil.copytree(source, dest, dirs_exist_ok=True)
        print(f"Successfully backed up session '{session_name}' to {dest}")
        print("Existing files in the destination were overwritten.")

    except Exception as e:
        print(f"Error during backup: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()