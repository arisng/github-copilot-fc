# Glossary format (schema 1)

The canonical glossary lives at `reports/daily/<git-username>/glossary.md`.
`scripts/Merge-Glossary.ps1` owns the file: this document names the same
contract that the script parses, the tests pin, and the skill consumes.

## File shape

```markdown
---
owner: example-user
schema: 1
---

# Glossary

| Term | Meaning |
| --- | --- |
| definition of ready | Work items must satisfy the checklist before a build may start. |
| acceptance criteria | One condition the deliverable must satisfy. |
```

## Rules

| Rule | Value |
| --- | --- |
| Frontmatter | Exactly `owner` (sanitized git username — must equal the folder name) and `schema` (integer, currently `1`). No timestamps: time lives in the report's `created`/`updated`. |
| Headings | Exactly one H1, `# Glossary`, and exactly one table. |
| Columns | Exactly two: `Term`, `Meaning`. The canonical file has no `Status` column — `NEW`/`known` is report-only. |
| Cells | Single-line. A literal `\|` is written for a pipe. No HTML. |
| Keys | Trimmed, ≤ 100 characters, unique case-insensitively; first-seen casing is the display form. |
| Meanings | Non-empty, ≤ 25 words. |
| Order | Case-insensitive ordinal sort by term — stable diffs, reproducible output. |
| Byte-stability | An upsert that changes nothing must not rewrite the file. |
| Failure | A schema violation aborts with a line-numbered error; the file is never recreated destructively. |

## Operations

`Merge-Glossary.ps1 -TermsJson` takes `[{term, meaning, op}]` with:

| op | Semantics |
| --- | --- |
| `insert` | Must be absent. An existing key fails loudly. |
| `refresh` | Replace the meaning when present and different; insert when absent. |
| `keep` | Leave the stored meaning when present; insert when absent. |

The script emits a JSON receipt `{added, refreshed, kept, total, changed}`
for the report-back step, and exposes `-Validate` as the single parse
authority shared with `Test-DailyReport.ps1`.
