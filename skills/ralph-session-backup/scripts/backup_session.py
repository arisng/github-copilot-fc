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

def create_cross_platform_links(session_folder, backup_dest, backup_name):
    """
    Create platform-specific link variants for cross-platform accessibility:
    - latest-win: Windows junction point (always a link, never a copy)
    - latest-linux: Linux symlink (always a link, never a copy)
    """
    latest_win = os.path.join(session_folder, "latest-win")
    latest_linux = os.path.join(session_folder, "latest-linux")

    # Clean up existing links
    for link_path in [latest_win, latest_linux]:
        try:
            if os.path.islink(link_path):
                os.unlink(link_path)
            elif os.path.exists(link_path):
                try:
                    os.rmdir(link_path)  # Try junction removal first
                except OSError:
                    shutil.rmtree(link_path)  # Fallback for directories
        except OSError:
            pass

    # Create Windows junction (always try link first, fallback to error)
    try:
        import subprocess
        result = subprocess.run(
            ['cmd', '/c', 'mklink', '/J', latest_win, os.path.abspath(backup_dest)],
            capture_output=True, text=True, check=True
        )
        print(f"Created Windows junction: {latest_win} -> {backup_name}")
    except (subprocess.CalledProcessError, OSError, FileNotFoundError):
        print(f"Warning: Could not create Windows junction: {latest_win}")

    # Create Linux symlink (always try link first, fallback to error)
    try:
        os.symlink(os.path.abspath(backup_dest), latest_linux)
        print(f"Created Linux symlink: {latest_linux} -> {backup_name}")
    except OSError:
        print(f"Warning: Could not create Linux symlink: {latest_linux}")

def create_versioned_backup(source, dest_base, session_name, repo_name):
    """
    Create a versioned backup structure:
    dest_base/repo_name/session_name/backup_YYMMDD-HHMMSS
    Also creates cross-platform latest links
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

    # Create cross-platform latest links
    create_cross_platform_links(session_folder, backup_dest, backup_name)

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

def get_latest_session_path(dest_base, repo_name, session_name):
    """Get the path to the latest session version for current platform"""
    session_folder = os.path.join(dest_base, repo_name, session_name)

    # Determine which link to use based on platform
    if platform.system() == 'Windows':
        latest_link = os.path.join(session_folder, "latest-win")
    else:  # Linux/WSL
        latest_link = os.path.join(session_folder, "latest-linux")

    if os.path.exists(latest_link):
        return os.path.abspath(latest_link)
    else:
        # Fallback: find the most recent backup directory
        versions = list_session_versions(dest_base, repo_name, session_name)
        if versions:
            latest_backup = os.path.join(session_folder, versions[0])
            return os.path.abspath(latest_backup)
        else:
            return None

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
        print("Usage: python backup_session.py <session_name> [--cleanup N] [--list] [--get-latest-path]")
        print("  --cleanup N: Keep only the last N versions (default: 5)")
        print("  --list: List existing versions for the session")
        print("  --get-latest-path: Print the path to the latest session version")
        sys.exit(1)

    session_name = sys.argv[1]
    cleanup_count = 5  # Default to keep 5 versions
    list_only = False
    get_latest_path = False

    # Parse additional arguments
    for arg in sys.argv[2:]:
        if arg == "--list":
            list_only = True
        elif arg == "--get-latest-path":
            get_latest_path = True
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

    if get_latest_path:
        latest_path = get_latest_session_path(dest_base, repo_name, session_name)
        if latest_path:
            print(latest_path)
        else:
            print(f"Error: No versions found for session '{session_name}'", file=sys.stderr)
            sys.exit(1)
        return

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