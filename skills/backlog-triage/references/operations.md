# Scripts

Run from the installed skill folder (the folder containing this `SKILL.md`).
All accept `-Repo <owner/name>` and `-Config <path>`; both fall back through
the discovery order in [taxonomy](taxonomy.md) (repo-local config, then
co-located `triage.json`, then defaults).

| Script | Purpose |
|---|---|
| `triage-queue.ps1` | Human queue / grooming view in the terminal |
| `triage-signals.ps1` | Issues + labels → all signals as JSON (`-Json`, `-OutFile`); `-NoLabelCheck` skips the taxonomy gate (offline/tests only) |
| `triage-report.ps1` | Signals JSON → self-contained static HTML |
| `triage-bootstrap.ps1` | Create missing taxonomy labels (`gh label create`, idempotent); `-DryRun` previews, `-WriteExampleConfig` writes an ownable triage.json |
| `triage-helpers.ps1` | Pure parsing/derivation + taxonomy functions; dot-sourced by the above and by the tests |

Full parameter sets: `triage-queue.ps1` also takes `-All`;
`triage-signals.ps1` also takes `-Json`/`-OutFile`/`-Now`/`-NoLabelCheck`;
`triage-report.ps1` also takes `-SignalsFile`/`-OutFile` (`-Config`/`-Repo`
are only used when the signals file must be generated — otherwise the report
renders from the payload's own `taxonomy` block and warns on a mismatch).

Tests: `task test:ps1` (Pester). The helpers are covered without network
access; the end-to-end cases are skipped when `SKIP_NETWORK_TESTS=1`.

## Full-lifecycle operations

- **Dedup-close** (hard gate): comment linking the canonical issue, then

  ```powershell
  gh issue close <N> --repo <owner/name> --reason "duplicate" --duplicate-of <canonical>
  ```

  `--reason duplicate` records GitHub's native duplicate linkage;
  `--duplicate-of` takes the canonical issue number or URL. Use
  `--reason "not planned"` only when there is no canonical issue to point at.
- **Split** (hard gate): create children with `gh issue create`, always passing
  the `needs_triage` label plus the type/priority/area labels — an unlabeled
  child never enters the queue and is permanently invisible to triage.
  Reference the parent in each child body, then narrow or close the parent.

  ```powershell
  gh issue create --repo <owner/name> --title "[task] <child>" --body-file body.md `
    --label needs-triage --label type:task --label priority:P2 --label area:ingest
  ```
- **Roadmap re-anchor**: match roadmap items to issues; status changes are a
  hard gate.

## Cycle hook

If the repo runs a periodic planning cycle, triage the queue before generating
the plan — plan against a clean backlog. Triage ad hoc any time new issues
land.
