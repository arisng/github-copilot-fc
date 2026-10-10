# Scripts

Run from the installed skill folder (the folder containing this `SKILL.md`).
All accept `-Repo <owner/name>` and `-Config <path>`; both fall back through
the discovery order in [taxonomy](taxonomy.md) (repo-local config, then
co-located `triage.json`, then defaults).

| Script | Purpose |
|---|---|
| `triage-queue.ps1` | Human queue / grooming view in the terminal |
| `triage-signals.ps1` | Issues + labels → all signals as JSON (`-Json`, `-OutFile`); `-NoLabelCheck` skips the taxonomy gate (offline/tests only — the payload is stamped `label_check: "skipped"` and the report refuses it) |
| `triage-report.ps1` | Signals JSON → self-contained static HTML (requires a v3 payload with `label_check: "passed"`) |
| `triage-bootstrap.ps1` | Create the missing taxonomy labels (`gh label create`, idempotent: existing labels are skipped, never updated); `-DryRun` previews, `-WriteExampleConfig` writes an ownable triage.json (with `-DryRun` it prints it instead of writing) |
| `triage-helpers.ps1` | Pure parsing/derivation + taxonomy functions; dot-sourced by the above and by the tests |
| `tests/test-triage.ps1` | Offline test suite for the gate, bootstrap, report, and helpers (`gh` stubbed) |

Full parameter sets: `triage-queue.ps1` also takes `-All`/`-NoLabelCheck`;
`triage-signals.ps1` also takes `-Json`/`-OutFile`/`-Now`/`-NoLabelCheck`;
`triage-bootstrap.ps1` also takes `-DryRun`/`-WriteExampleConfig`;
`triage-report.ps1` also takes `-SignalsFile`/`-OutFile` (`-Config`/`-Repo`
are only used when the signals file must be generated — otherwise the report
renders from the payload's own `taxonomy` block and warns on a mismatch).

Tests: offline, dependency-free (the `gh` calls are stubbed, no network, no Pester):

```powershell
pwsh -NoProfile -File ./scripts/tests/test-triage.ps1
```

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
