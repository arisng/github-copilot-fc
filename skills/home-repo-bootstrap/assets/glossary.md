# Standing Glossary

Cross-repo vocabulary. Seeded on bootstrap; add terms here instead of re-explaining them in
each repo. Report-specific terms stay in each report's own glossary.

| Term | Meaning |
| --- | --- |
| tower | Multi-repo mode of the daily-report skill: a home repo watches every repo path the manifest lists and writes one report covering all of them. |
| coverage receipt | `sessions/<yymmdd>/coverage.json` — the completeness proof a daily report must commit with; local CI fails a report without it. |
| Home Repo | One repository holding shared docs, steering and pointers to every other repo; agent sessions start there. |
| pointer | One line in `AGENTS.md` naming a repo, its local path and its clone URL, with "clone if missing" semantics. |
| one-owner rule | Every skill has exactly one source of truth — an updater or a git repo — and never a second copy in another location. |
| canonical store | `~/.agents/skills/` — the only real user-level skill directory on a machine; the harness personal dirs are junctions to it. |
