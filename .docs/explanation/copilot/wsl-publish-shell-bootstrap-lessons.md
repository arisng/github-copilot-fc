---
category: explanation
---

# Why WSL Publishing Broke from PowerShell and What Fixed It

The WSL publish failure looked, at first, like a stale Node.js installation inside Ubuntu. It was not. The same Ubuntu distro reported Node.js v22.22.0 and a working GitHub Copilot CLI when tested from an interactive Bash terminal, yet `publish-plugins.ps1` failed from PowerShell with a Node.js v18.19.1 error. The discrepancy came from how the scripts entered WSL.

## The Real Failure Mode

The original publish path used `wsl bash -c ...` for both utility operations and Copilot CLI invocations. That shell mode is non-interactive, so it does not reliably load the same shell initialization that an Ubuntu terminal session loads. In this workspace, Node.js v22 was provided by `nvm`, which was activated in the interactive shell environment. Without that initialization, WSL fell back to `/usr/bin/node`, which was still Node.js v18.19.1.

This is why the failure only appeared when the command originated in PowerShell. The Ubuntu terminal and the PowerShell-driven WSL entry path were not entering the same Bash environment.

## Why the First Fix Attempt Was Insufficient

The obvious next step was to source `nvm.sh` explicitly before running `copilot`. That is directionally correct, but it still failed when passed as an inline command string from PowerShell to WSL. The problem shifted from shell startup to command transport: variable-heavy Bash fragments such as `$HOME` and `$NVM_DIR` are easy to mangle when they cross multiple command interpreters.

The issue was not `nvm` itself. The issue was trying to bootstrap `nvm` through an inline PowerShell-to-WSL command string.

## The Robust Fix

The durable solution was to centralize WSL command execution in `scripts/publish/wsl-helpers.ps1` and have it write a temporary Bash script file instead of sending the command inline. That change introduced three important properties:

1. The command text arrives in WSL exactly as Bash should read it, with no extra quoting layer to reinterpret variable references.
2. The temporary script is written with LF line endings, so Bash does not trip over stray carriage returns from Windows.
3. Node.js bootstrap is explicit and opt-in through `Invoke-WSLCommand -InitializeNode`, which sources `~/.nvm/nvm.sh` and activates the default alias before invoking `copilot`.

This keeps file-copy operations lightweight while making Node-dependent commands deterministic.

## Lessons Learned

- Interactive success in WSL does not prove non-interactive automation will see the same toolchain.
- `wsl bash -c ...` is acceptable for trivial commands, but it is brittle for environment-sensitive tools such as `nvm`-managed CLIs.
- If a command crosses PowerShell and Bash, inline strings are part of the risk surface.
- A shared transport helper is more valuable than patching individual scripts one by one.
- LF-only temp scripts matter; otherwise a correct bootstrap can still fail with carriage-return artifacts.
- Verification must exercise the real entry points. In this case, validating the helper alone was not enough; `publish-plugins.ps1`, `publish-skills.ps1`, and `publish-agents.ps1` all had to be run from PowerShell.

## Resulting Pattern for This Workspace

The workspace now uses a single WSL helper for publish scripts:

- `Invoke-WSLCommand` for deterministic WSL execution
- `Test-WSLAvailable` for capability detection
- `Copy-ToWSL` and `Remove-FromWSL` for filesystem operations

`publish-plugins.ps1` uses Node bootstrap for WSL `copilot plugin install` and `copilot plugin uninstall`. `publish-skills.ps1` and `publish-agents.ps1` now reuse the same helper layer for WSL detection and copy operations. The practical benefit is not just fixing one plugin install; it is removing a class of PowerShell-to-WSL drift across the whole publish surface.