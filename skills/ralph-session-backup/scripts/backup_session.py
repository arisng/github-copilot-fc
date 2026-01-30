#!/usr/bin/env python3
"""
Ralph Session Backup Script with Versioning

Copies a specific session folder from .ralph-sessions to GoogleDrive SwarmSessions
with versioning support. Each session gets its own folder containing timestamped backups.
"""

import os
import shutil
import sys
import platform
import subprocess
from datetime import datetime

def get_current_timestamp():
    """Generate timestamp in YYMMDD-HHMMSS format"""
    return datetime.now().strftime("%y%m%d-%H%M%S")

def create_versioned_backup(source, dest_base, session_name, repo_name):
    """
    Create a versioned backup structure:
    dest_base/repo_name/session_name/backup_YYMMDD-HHMMSS
    Also maintains a 'latest' symlink/copy
    """
    # Create session-specific folder
    session_folder = os.path.join(dest_base, repo_name, session_name)
    os.makedirs(session_folder, exist_ok=True)

    # Generate backup timestamp
    backup_timestamp = get_current_timestamp()
    backup_name = f"backup_{backup_timestamp}"
    backup_dest = os.path.join(session_folder, backup_name)

    print(f"Creating versioned backup: {backup_dest}")

    # Copy the session to the versioned backup
    shutil.copytree(source, backup_dest, dirs_exist_ok=True)

    # Create/update latest symlink (platform-aware)
    latest_path = os.path.join(session_folder, "latest")
    try:
        if os.path.exists(latest_path) or os.path.islink(latest_path):
            if platform.system() == 'Windows':
                os.remove(latest_path)  # Windows doesn't have symlinks in older versions
            else:
                os.unlink(latest_path)
    except OSError:
        pass  # Ignore if removal fails

    try:
        if platform.system() == 'Windows':
            # On Windows, create a copy instead of symlink
            if os.path.exists(latest_path):
                shutil.rmtree(latest_path)
            shutil.copytree(backup_dest, latest_path, dirs_exist_ok=True)
            print(f"Created latest copy: {latest_path}")
        else:
            # Create symlink on Unix-like systems
            os.symlink(backup_name, latest_path)
            print(f"Created latest symlink: {latest_path} -> {backup_name}")
    except OSError as e:
        print(f"Warning: Could not create latest link/copy: {e}")

    return backup_dest

def list_session_versions(dest_base, repo_name, session_name):
    """List all versions of a session"""
    session_folder = os.path.join(dest_base, repo_name, session_name)
    if not os.path.exists(session_folder):
        return []

    versions = []
    for item in os.listdir(session_folder):
        item_path = os.path.join(session_folder, item)
        if os.path.isdir(item_path) and item.startswith("backup_"):
            versions.append(item)

    return sorted(versions, reverse=True)  # Most recent first

def cleanup_old_versions(dest_base, repo_name, session_name, keep_count=5):
    """Keep only the most recent N versions"""
    session_folder = os.path.join(dest_base, repo_name, session_name)
    versions = list_session_versions(dest_base, repo_name, session_name)

    if len(versions) <= keep_count:
        return 0

    versions_to_delete = versions[keep_count:]
    deleted_count = 0

    for version in versions_to_delete:
        version_path = os.path.join(session_folder, version)
        try:
            shutil.rmtree(version_path)
            deleted_count += 1
            print(f"Cleaned up old version: {version}")
        except OSError as e:
            print(f"Warning: Could not delete {version}: {e}")

    return deleted_count

def main():
    if len(sys.argv) < 2:
        print("Usage: python backup_session.py <session_name> [--cleanup N] [--list]")
        print("  --cleanup N: Keep only the last N versions (default: 5)")
        print("  --list: List existing versions for the session")
        sys.exit(1)

    session_name = sys.argv[1]
    cleanup_count = 5  # Default to keep 5 versions
    list_only = False

    # Parse additional arguments
    for arg in sys.argv[2:]:
        if arg == "--list":
            list_only = True
        elif arg.startswith("--cleanup="):
            try:
                cleanup_count = int(arg.split("=")[1])
            except (ValueError, IndexError):
                print("Error: --cleanup requires a number")
                sys.exit(1)

    # Get repository name from current working directory
    repo_name = os.path.basename(os.getcwd())

    # Paths relative to the current working directory (repository root)
    workspace_root = os.getcwd()
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

    print(f"Repository: {repo_name}")
    print(f"Session: {session_name}")
    print(f"Source: {source}")
    print(f"Destination base: {dest_base}")

    if list_only:
        versions = list_session_versions(dest_base, repo_name, session_name)
        if versions:
            print(f"\nExisting versions for {session_name}:")
            for version in versions:
                print(f"  {version}")
        else:
            print(f"\nNo versions found for {session_name}")
        return

    if not os.path.exists(source):
        print(f"Error: Session '{session_name}' does not exist in .ralph-sessions")
        sys.exit(1)

    if not os.path.isdir(source):
        print(f"Error: '{session_name}' is not a directory")
        sys.exit(1)

    try:
        # Create versioned backup
        backup_path = create_versioned_backup(source, dest_base, session_name, repo_name)
        print(f"Successfully created versioned backup: {backup_path}")

        # Cleanup old versions (default: keep 5)
        deleted = cleanup_old_versions(dest_base, repo_name, session_name, cleanup_count)
        if deleted > 0:
            print(f"Cleaned up {deleted} old version(s)")

        # List current versions
        versions = list_session_versions(dest_base, repo_name, session_name)
        print(f"\nCurrent versions ({len(versions)} total):")
        for version in versions[:5]:  # Show latest 5
            print(f"  {version}")
        if len(versions) > 5:
            print(f"  ... and {len(versions) - 5} more")

    except Exception as e:
        print(f"Error during backup: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()