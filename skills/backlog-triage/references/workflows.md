# Triage pass (per issue)

Work from the signals payload, not from fresh `gh` calls.

1. **Read** — the queue entry in `cache/triage-signals.json` (title, labels,
   body excerpt, refs).
2. **Dedup** — use the payload's `dedup_candidates`; confirm with
   `gh issue list --repo <owner/name> --search "<keywords>" --state all` only
   when a candidate looks real. Match found → hard gate: propose closing as
   duplicate.
3. **Type** — verify the template's `type:*` matches the content (bug vs task
   vs feature-plan vs map).
4. **Priority** — apply the heuristics below against the repo's priority axis.
5. **Area** — from the form answer plus code knowledge; one or more.
6. **Dependencies** — the payload already resolved open vs closed. Open
   dependency and no `blocked` label → add `blocked`.
7. **Owner-decision** — the issue needs owner confirmation before work
   proceeds → add `owner_decision`.
8. **Apply + report:**

   ```powershell
   gh issue edit <N> --repo <owner/name> `
     --add-label priority:P1 --add-label area:ingest --remove-label needs-triage
   gh issue comment <N> --repo <owner/name> `
     --body "**Triage:** type:task, priority:P1 (blocks G2), area:ingest. <one-line rationale>"
   ```

## Priority heuristics

Map intent onto the target repo's axis (`code` values are what the heuristics
reason about):

| Tier | Assign when |
|---|---|
| top (`P0`) | Data loss, corruption, security — drop everything |
| high (`P1`) | Blocks a north-star goal or a roadmap item |
| mid (`P2`) | Important, but not blocking |
| low (`P3`) | Nice to have |

Tie-break: *"if this waits one more cycle, what breaks?"* A goal or integrity
issue → high; convenience → low. The top tier is reserved for true
emergencies; nothing in the normal backlog qualifies.

## Grooming (`-All`, or the `grooming` block in the signals JSON)

- **Stale top-priority** (`stale_priority`) — a top-tier item (per
  `stale_priority_codes`) older than `stale_age_days` is misprioritized or
  blocked; say which in the report. Label + age only; does not filter on open
  dependencies.
- **Blocked chains** (`blocked_chains`) — which single issue unblocks the most
  work.
- **Low-priority accumulation** (`low_priority_accumulation`) — bottom-tier
  items; candidates for `wontfix`.
- **Priority drift** — labels that no longer match reality (reprioritize with a
  comment).
- **Stale dependency references** (`stale_dependency_refs`) — body cites a
  closed issue; the `blocked` label is correctly absent but the body text is
  stale (fixing the body is a hard gate).
- **Missing `blocked` label** (`missing_blocked_label`) — body cites an open
  dependency but the label is absent.
