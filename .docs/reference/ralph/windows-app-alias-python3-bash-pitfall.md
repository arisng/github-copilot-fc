# Windows App Alias python3 shim crashes Bash scripts under set -euo pipefail

## Problem

On Windows with App Execution Aliases enabled, `command -v python3` resolves to the Microsoft Store shim at `%LOCALAPPDATA%/Microsoft/WindowsApps/python3`. This shim exists as a file (so `command -v` succeeds) but fails with exit code 9009 when executed because Python is not installed via the Microsoft Store.

When a Bash script uses `set -euo pipefail` (as the Ralph Bash hook logger does), executing the shim propagates the non-zero exit and crashes the entire script — violating any non-fatal exit contract.

## Affected scenario

Git Bash on Windows where:
1. The Windows App Execution Alias for Python exists in PATH.
2. Real Python is installed under a different name or path (e.g., `python.exe` at `C:\Python313\`).
3. The script uses `set -euo pipefail`.

This does **not** affect WSL, native Linux, or macOS environments where `python3` resolves to a real binary.

## Detection

```bash
# This succeeds (shim file exists):
command -v python3

# This crashes with exit 9009:
python3 -c "import sys"
```

## Fix pattern

After `command -v python3`, add an execution validation:

```bash
if command -v python3 >/dev/null 2>&1 && python3 -c "import sys" 2>/dev/null; then
    # python3 is real and functional
    python3 -c "..."
elif command -v date >/dev/null 2>&1; then
    # GNU date fallback
    date -u -d "@$((ms / 1000))" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "null"
else
    echo "null"
fi
```

## General applicability

Any Bash script that uses `command -v python3` as a guard before executing `python3` is vulnerable to this on Windows with App Execution Aliases. The pattern affects Git Bash specifically — PowerShell is not affected because it uses a different Python resolution path.
