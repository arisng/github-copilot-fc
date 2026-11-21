# Subagent dispatch preamble

Load this file by path in every dispatch prompt (fleet, research, critique,
review): subagents do not inherit session-level instructions or personal
steering, so these constraints must travel with the prompt — as a pointer to
this file, once, instead of restating the block per dispatch.

## Tool quirks

- The shell tool is named `powershell` (lowercase).
- Pass filesystem paths to any tool as plain strings, never JSON arrays.
- `grep`/search paths take a containing directory plus a glob or pattern —
  a file path fails with "Search paths do not exist".
- ripgrep has no look-around assertions; `(?=…)` / `(?!…)` fail whole calls.
- PowerShell here-strings die past ~30 KB on the command line; use
  file-creation tools instead.
- Use `;` (not `&&`) between PowerShell statements; write `${var}:` when a
  variable meets a colon inside a double-quoted string.

## Report contract

- Write the deliverable to its file **before** composing the reply: append as
  findings land; the reply is a summary of at most 10 lines plus the file
  path.
- If a reply gets interrupted, the file is the source of truth — recover it
  before redoing any work.

## Spec-driven implementation reports

End implementation reports with a **spec-section → test mapping**: every
section of the given spec maps to the test that proves it, or is listed as an
explicit deferral. A report without the mapping is incomplete.

## Gates

- Run the repo gate verbatim and quote its output:
  `pwsh -NoProfile -File scripts/workspace/workspace-check.ps1`
  (quick mode: append `-Quick`).
- Never cite `scripts/workspace/run-command.ps1` — it does not exist; the
  dispatcher an old issue doc advertised was never retained (that citation
  class is now a FAIL in `check-consistency.ps1`).
