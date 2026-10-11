# Worked Example and Lesson Criteria

Companion to [SKILL.md](../SKILL.md).

## What counts as a lesson

Run the discipline after a PR merge or commit when the work surfaced a lesson worth keeping:

- A debugging loop revealed a non-obvious behavior (tooling quirks, environment pitfalls).
- A cross-cutting rule was learned the hard way (auth gating, URL resolution, credential scoping).
- A QA/verification invariant became clear (e.g. "verify access constraints by authenticating the real persona").
- Any guidance that appeared verbatim in more than one file during the work — that repetition is a drift smell to fix.

The goal is a "systematic inheritance and combination" model across the whole file set: each file has a clear, non-overlapping responsibility, and cross-cutting lessons live in exactly one owner that the rest reference.

## Single-owner placement

After a debugging loop against a distributed-app stack, four lessons were codified with single-owner placement each:

| Lesson | Owner (single) |
|---|---|
| Restart the orchestrator/AppHost rather than restarting individual project resources mid-run (they can hang waiting) | Operations instructions file |
| User-facing URLs must resolve via a dedicated resolver policy, not ad-hoc domain assumptions | Scoped instructions file for that concern |
| Login admits all authenticated users at the entry point while individual pages gate per-role | Instructions file for that app surface |
| QA smoke: verify access constraints by authenticating the real persona, never assume rejection behavior | The QA agent's execution block in its `*.agent.md` |

The orchestrating agent's file received **only** concise inheriting pointers referencing the four owners — not restated generic-policy items. For example:

> → see `qa-agent.agent.md` ("Verify Access Constraints, Never Assume Them")

**Wrong approach (drift):** writing the same prose verbatim into the operations instructions **and** the orchestrator agent file **and** an unrelated skill's `SKILL.md`.
