---
category: reference
---

# Cross-Environment Python Fallback Chain

## Summary

Bash scripts that invoke Python in cross-platform environments (Windows Git Bash, WSL, macOS, Linux) should use a `python3` → `python` → `py` fallback chain with Windows App Alias shim detection. The `python3` command is not universally available — `command -v python3` succeeds on Windows even when the resolved path is a non-functional App Alias shim that opens the Microsoft Store.

## The Problem

On fresh Windows installations, `python3` resolves via `command -v` to a path under `WindowsApps/` (the App Execution Alias). This shim:
- Passes `command -v` checks (the executable exists)
- Crashes or opens the Microsoft Store when actually invoked
- Causes silent failures under `set -euo pipefail`

## The Pattern: `resolve_python()`

```bash
resolve_python() {
    local candidate path
    for candidate in python3 python py; do
        path=$(command -v "$candidate" 2>/dev/null) || continue
        # Skip Windows App Alias shim
        case "$path" in
            *WindowsApps*) continue ;;
        esac
        # Verify the candidate actually runs
        if "$candidate" --version >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    printf '\n'
}

PYTHON_CMD=$(resolve_python)
```

## Design Properties

| Property | Implementation | Why |
|----------|---------------|-----|
| Priority order | `python3` → `python` → `py` | `python3` is canonical on Linux/macOS; `python` is common on systems with Python installed; `py` is the Windows launcher |
| Shim detection | `case "$path" in *WindowsApps*)` | Pattern match on the resolved path catches the App Execution Alias without requiring a specific version or path |
| Runtime verification | `"$candidate" --version >/dev/null 2>&1` | Defense-in-depth: catches non-functional executables not caught by the path pattern |
| Cached result | `PYTHON_CMD=$(resolve_python)` at script top | Avoids repeated `command -v` probes on every timestamp call |
| Graceful degradation | Empty `PYTHON_CMD` → skip Python-dependent features | When no Python is available, Python-dependent fields (e.g., `ts_iso`) are omitted via conditional logic; core functionality continues |

## Non-Fatal Contract

`resolve_python()` always returns exit code 0. Failures are expressed as an empty return value, not a non-zero exit code. This preserves compatibility with `set -euo pipefail`.

## Usage in Callers

```bash
# Guard Python-dependent branches
if [ -n "$PYTHON_CMD" ]; then
    result=$("$PYTHON_CMD" -c "..." 2>/dev/null) || result=""
fi
```

When `PYTHON_CMD` is empty, Python-dependent fields are omitted from output rather than causing script failure.
