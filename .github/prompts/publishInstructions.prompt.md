---
name: publishInstructions
description: Publish specified instruction files to VS Code user prompts directories.
argument-hint: One or more instruction names, separated by commas or using wildcards (e.g., "powershell,claude-skills" or "power*")
model: Raptor mini (Preview) (copilot)
metadata:
  version: 1.0.0
  author: arisng
---
Help the user copy instruction files from the repository's `instructions/` folder into the global VS Code user prompts directories so they can be used across workspaces and devices.

- Accept a list of instruction names provided as a single argument string. The user may:
  * supply multiple names separated by commas (commas may be followed by spaces),
  * use a prefix or simple wildcard pattern (PowerShell `*` style) to match a group of instruction names.

- Interpret the argument by scanning `instructions/*.instructions.md` and expanding any wildcards or prefixes into a concrete list of base names (filename without suffix). **Only names that actually exist in that directory should be included.**

- If the resolved list is empty (no matching instructions), the prompt should not call the script at all and should inform the user that nothing matched.

- Once the list of names is resolved and non‑empty, **execute the publishing script automatically** using the `run_in_terminal` tool rather than merely describing it. For example:
  ```powershell
  powershell -ExecutionPolicy Bypass -File {workspaceFolder}/scripts/publish/publish-instructions.ps1 -Instructions name1,name2
  ```
  (pass the resolved names as a comma-separated list; PowerShell also accepts an array if you quote each name individually).

- If the intent is to publish *all* instructions, call the script with no `-Instructions` parameter:
  ```powershell
  powershell -ExecutionPolicy Bypass -File {workspaceFolder}/scripts/publish/publish-instructions.ps1
  ```

- Note that the script will prompt before overwriting existing files unless `-Force` is supplied; include `-Force` in the command if the user asked to force overwrite.

The prompt should resolve any patterns, construct the appropriate command, and invoke it only if there are matches. If input is ambiguous or missing, ask a clarifying question before running anything.