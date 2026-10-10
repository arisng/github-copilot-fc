---
name: backlog-triage
description: >
  Triage a GitHub issue backlog — classify, prioritize, dedup, and groom issues.
  Repo-agnostic: each repo supplies its own label taxonomy via a triage.json config.
  Use when: triaging new issues, clearing the needs-triage queue, grooming the backlog,
  prioritizing issues, hunting duplicates, splitting oversized issues, or deciding what
  to work on next. Triggers: triage, needs-triage, issue queue, backlog grooming,
  prioritize, reprioritize, dedup issues, label issues, what should I work on next.
metadata:
  version: 0.4.0
---

# Issue Triage

Repo-agnostic GitHub issue triage. Reads every issue in **one** `gh` call, derives all
signals locally, and leaves mutation to explicit `gh` commands you run after deciding.

Reasons about abstract concepts (untriaged / blocked / owner-decision markers, ordered
priority axis, area/type tag families). Each repo maps them onto its own label names —
see [taxonomy](references/taxonomy.md).

## Workflow

1. Resolve the repo (`-Repo` > config `repo` > origin remote > error) and taxonomy
   ([taxonomy](references/taxonomy.md)).
2. Show the queue (terminal) — needs-triage issues with form-proposed priority/area.
3. Emit signals JSON + HTML report — the full decision payload.
4. Triage each queued issue from the payload ([pass](references/workflows.md)).
5. Apply with `gh`, then handle closes/splits/re-anchors ([ops](references/operations.md)).

Run from the installed skill folder (the folder containing this `SKILL.md`).

## Queue

```powershell
.\scripts\triage-queue.ps1                        # the queue
.\scripts\triage-queue.ps1 -All                   # grooming view, grouped by priority
.\scripts\triage-queue.ps1 -Repo owner/name -Config path/to/triage.json
```

The queue is every open issue carrying the configured `needs_triage` label.

## Signals → decisions → apply

Do **not** make per-issue `gh` calls. One call produces every signal; you do the
semantic work on the payload; `gh` is used only to mutate.

```powershell
.\scripts\triage-signals.ps1 -Json -OutFile cache/triage-signals.json
.\scripts\triage-report.ps1
```

The JSON is self-describing (`taxonomy` block + `summary.priority_counts` keyed by
portable code). Per queued issue: labels, age, form-proposed priority/area,
roadmap/goal refs, issue refs, open-vs-closed dependency state, dedup candidates,
body excerpt — plus a `grooming` block. Read it once, decide the whole queue.

Report prints a path + `file://` URL. Open it for the clickable view; never spawn a
browser — this often runs headless (VPS/Docker).

## Autonomy contract

Apply-and-report with hard gates. Apply labels + post a rationale comment (the review
surface), no confirmation ping. Stop and confirm before closing, splitting, rewriting
a body, or changing a roadmap status. Ask one focused question when the priority
heuristic ties on this cycle's work or you would override the form-proposed priority.

## References

[taxonomy](references/taxonomy.md) · [pass + heuristics + grooming](references/workflows.md) · [scripts + close/split/re-anchor + cycle](references/operations.md)
