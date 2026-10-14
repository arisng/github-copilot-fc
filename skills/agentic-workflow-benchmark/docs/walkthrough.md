# Plain-English walkthrough of the benchmark skill upgrade

## Summary

This document explains, in plain words, what changed in the `agentic-workflow-benchmark` skill
(version 0.1.0 → 0.2.3), why it had to change, what the files and numbers in a benchmarks folder
mean, and what is still left to do. It is self-contained and written for a reader who was not there
when the work happened: every term is defined where it first appears and collected again in the
glossary at [docs/CONTEXT.md](./CONTEXT.md); the numbers come entirely from one real measurement (a
session from 13 October 2026), with the original broken run cited only as the one-line before/after;
tables sit inline next to the text that explains them; and the document ends with a dated checklist
of open actions. No picture accompanies it (none was requested).

## Terms

Each term below is the canonical wording; the _Avoid_ list names the words not to use for it.

**Episode**: One run of a single skill inside a chat — a slice of the transcript, not the whole transcript.
_Avoid_: full session, the whole chat, recording

**Session**: The complete transcript of one chat with the AI — every message, click, and command, saved as a list of events.
_Avoid_: recording, transcript window, run

**Baseline**: The saved first measurement of a skill's run that later runs compare against to say better or worse.
_Avoid_: target, goal, score to beat

**Deterministic step**: A step that ran a pre-written script or command — no fresh thinking involved.
_Avoid_: automated score, good step

**Semantic step**: A step where the AI had to think, judge, or write something new.
_Avoid_: AI step, manual step

**Boundary row**: A line in the report showing work a helper skill did, counted under the main skill.
_Avoid_: merged load, sub-window attribution

**Token**: A small unit of text the AI reads or writes; usage and cost are counted in them — roughly three-quarters of an English word.
_Avoid_: word, character

**Tool step**: One completed action the AI took with a tool — a command run, a file edited, a file read.
_Avoid_: operation, click

## Why

The skill answers four questions after **any agentic workflow an AI agent executes** — a software
delivery run, a research session, an operations procedure, a content production job, or anything
else driven through skills: how many tokens (the unit of AI usage) did it burn, how long did it
take, how many steps were plain thinking, and how many ran pre-written scripts. The answer gets
saved as a *baseline* so later runs can be compared against it. The tool is deliberately
workflow-agnostic: it measures whatever happened in the session it is pointed at.

It was nevertheless discovered in a software delivery session — and broken in a way that made it
measure a shrug instead of the job. The tool cut its measurement every time a new skill was loaded,
so for the big orchestrator skill it recorded only the moment the file was opened — **279,316
tokens and 1 tool step** — when the session had actually consumed **90,457,904 tokens**. It then
quietly saved that shrug as the baseline. Worse, commands that session's own build system uses
(`task ax:build:cold` and friends, 40 of them) were not recognized as scripted work, making the run
look about 45% less automated than it was. Everything in this document exists to explain those
fixes, the folder they live in, and the numbers a reader will now see.

## Locked decisions

None. Every change described here was easy to reverse — a file can move, a wording rule can change —
so none passes the bar for a permanent decision record.

## How this document reads

The conventions this document follows, stated once:

- **Coverage:** four things, in order — the words, the story of the fix, the folder, and the numbers.
- **Audience:** a teammate who never saw the session behind the numbers, so everything is
  self-contained and every term is defined before it is used.
- **Numbers:** full tables and ratios are kept, not summarized away.
- **Plain-English rule:** each term is defined the first time it appears *in this document*, then
  used freely. "First time" is scoped per document, not per repository — the glossary file is the
  single source the definitions are copied from, so wording stays identical everywhere.
- **Ending:** a dated "open actions" checklist closes the document (see below).
- **Worked example:** the full tables come only from the 13 October 2026 session, where the fixed
  tool was used correctly; the original broken run appears only as the one-line before/after in
  Why.
- **Table placement:** every table sits inline, right after the text that explains it, so a reader
  meets a number in the same glance as its definition.
- **Location:** this file lives at `skills/agentic-workflow-benchmark/docs/walkthrough.md` — inside
  the skill, so it travels along whenever the skill is published.

## Verified facts

Established from the files themselves:

- **The root cause of the original mis-measurement** was a rule that said "stop at the next skill
  load." The orchestrator skill loads its driver skill 50 seconds in, so its measurement stopped
  there. The fix merges loads of helper skills the main skill names, and loads that happen inside a
  sub-agent's work window, into the main skill's measurement — each merged load still shown as a
  *boundary row* with its own totals.
- **The corrected measurement adds up exactly.** For the original run: 279,316 (the skill's own
  brief work) + 8,024,001 (driver skill) + 6,185,870 (a helper loaded inside a sub-agent) +
  66,462,092 (a second helper inside another sub-agent) = 80,951,279 tokens for that one skill's
  run, out of 90,457,904 for the whole session.
- **The benchmarks folder used by the example** is
  `C:\Workplace\DProcess\dprocess-dotnet-starter-kit\.github\skills\sdlc-orchestration\benchmarks\`.
  After the fix it holds: the owner skill's reports and baselines (episode and session kept in
  separate files so they are never compared against each other), two `.bak` files preserving the
  superseded measurements, and — since the ownership rule — no separate folder for the driver
  skill. The driver's contribution exists only as a boundary row inside the owner's report.
- **The re-measurement runs on 13 October 2026 behaved correctly.** The tool flagged the episode
  run as useless (1.5 minutes long while 937 tool steps happened elsewhere in the session), printed
  a warning at the top of the report, and refused to save it as a baseline — exactly the
  protection that was missing originally. The session baseline was then replaced on purpose:
  77,907,069 tokens, 949 tool steps, ratio 0.1043, with the previous 90.46M measurement preserved
  as a backup alongside it.
- **A report-location bug caused a manual file move.** The wrapper script only looked for
  `skills/<name>/`, but the consuming repo stores skills under `.github/skills/<name>/`, so runs
  first wrote to a repo-root folder that was not the real one. The wrapper now probes both
  locations.
- **The test fixture pins the classification rules:** the wrapper scripts that consolidate repeated
  ad-hoc commands are recognized as scripted work (deterministic), the ad-hoc shapes they replaced
  still count as unscripted (so nobody can game the score), `git status` counts as a lookup, and
  one known gap is documented: commands written as `git -C <path> …` are not yet recognized and
  land in the "uncertain" pile.

## Open actions (as of 2026-10-14)

1. **Commit the walkthrough and scope correction** — this document, its glossary, and the
   description change that stops the skill being described as delivery-only. Suggested message:
   `docs(skill): standalone walkthrough + scope skill to any agentic workflow (v0.2.3)`.
2. **Decide on the `git -C …` gap** — fixing it would flip one line of the test that currently
   expects "uncertain"; change both together when it should be closed.
3. **Close out issue arisng/dprocess-dotnet-starter-kit#946** — its acceptance criterion 3 asks for
   a re-measurement of an equivalent workflow run; the 13 October runs are the candidate evidence.
4. **Commit or clean up the benchmark reports in the dprocess repo** — they currently sit in that
   repo's working tree, uncommitted.
5. **Re-anchor the episode baseline** on a healthy run when one exists — the current episode
   baseline still comes from the original (broken-tool era) session, because the 13 October episode
   run was correctly refused as useless.

## Risks

- **The checklist above goes stale** — that is why it carries its date; treat a list older than the
  last real change as suspect.
- **Two baselines, two different sessions.** The episode baseline (whole-skill view) is from the
  original session; the session baseline (whole-transcript view) is from 13 October. They are kept
  in separate files precisely so nothing compares them, but a human skimming the folder could —
  read the `session_dir` line inside a baseline file before drawing conclusions.
- **`latest.json` is currently the refused, useless run** (12 steps) — do not mistake it for a
  representative measurement; the baselines are the meaningful files right now.
- **This document travels with every skill publish** — if it ever grows content that should not
  ship with the skill, move it out of the skill folder.
- **The glossary lives inside the skill** (`docs/CONTEXT.md`), not at the repository root where
  some readers look first — a deliberate choice to keep it beside the document it serves.

## Deferred

Nothing — no question was set aside; every branch reached an answer.

## Open threads

None — every discussion reached a decision. The glossary lives beside this document at
`docs/CONTEXT.md`; rename it there if a better name comes along.
