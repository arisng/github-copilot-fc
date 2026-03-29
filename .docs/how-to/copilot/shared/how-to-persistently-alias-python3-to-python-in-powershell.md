# How to Persistently Alias `python3` to `python` in PowerShell

Use this when `python --version` already works in PowerShell and you want `python3` to resolve to the same interpreter in every future session.

## Add the wrapper

Open your PowerShell profile and add a small wrapper function:

```powershell
function python3 {
    python @args
}
```

The function belongs in your current user profile so the behavior persists across new shells.

## Reload the profile

After saving the profile, reload it in the current session:

```powershell
. $PROFILE
```

## Verify

Confirm both commands resolve to the same interpreter:

```powershell
python --version
python3 --version
```

If the profile loaded correctly, both commands should report the same version.

## Notes

- This is a PowerShell-only fix. It does not change Git Bash, WSL, or other shell resolution paths.
- For Bash scripts, prefer an explicit `python3` validation or fallback chain instead of relying on a PowerShell profile.