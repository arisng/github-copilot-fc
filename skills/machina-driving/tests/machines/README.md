# Test Machine

A small Machina state machine used to validate hook-based tooling and the driving skill's lifecycle.

## States

| State | Description |
|---|---|
| **drafting** | Initial state. A draft file must exist at `draft_path` before leaving. |
| **reviewing** | Output is reviewed. The output file must exist. |
| **published** | Final state — work published successfully. |

## Transitions

- `DRAFT_COMPLETE` — drafting → reviewing (requires draft file to exist, output validated)
- `REVIEW_FAILED` — reviewing → drafting (increments `review_errors`; cycle guard skips to published after 3 consecutive failures)
- `APPROVED` — reviewing → published

## Tools

| Tool | What it does |
|---|---|
| `file-exists` | Asserts that a file exists at a given path. Exit 0 if present, 1 otherwise. |
| `output-ready` | Checks the output file exists and captures error count into context. |
| `validate-output` | Reads the output file and counts occurrences of "error" (case-insensitive). Reports via JSON. |

## Checker Scripts

Both scripts live in `scripts/` and are invoked by the machine's tools.

### `check_file.py <path>`
Read-only: exits 0 if the file exists, 1 if missing.

### `validate_output.py <path>`
Read-only: exits 0 if the file contains zero "error" strings, 1 otherwise. Outputs `{"errors": <count>}` as JSON.

## Usage

```jsonc
// Required context inputs (via scenario "default"):
{
  "draft_path": "path/to/draft.txt",
  "output_path": "path/to/output.txt"
}
```

The machine expects both files to already exist on disk. Hook scripts or test harnesses create them before driving the machine.
