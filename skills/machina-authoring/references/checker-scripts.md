# Checker Scripts (author's guide to machine evidence)

What a machine's checkers are, how to derive them from the workflow you are modeling, and the
contract each script has to honour. Read this when a definition needs to verify something in the
world — a state `checks[]`, a transition `requires[]`, or a checker declared in `tools[]`.

The compliance scorer never executes a checker; it only judges the declaration (see
[../SKILL.md](../SKILL.md), "Compliance boundary"). Everything below is about the layer that
actually runs: `machina-driving`'s driver, whose runtime rules live in
[machina-driving's driving-protocol.md](../../machina-driving/references/driving-protocol.md)
("Evidence checks"). This file owns the authoring side only.

## Derive the facts before writing any script

Work from the workflow, not from the schema. For each transition ask *what must be true in the
world for taking this step to be legitimate*; for each state ask *what must hold while the machine
is here*. Each distinct fact that is **externally observable** — the filesystem, git, a CLI's exit
status or output, an HTTP endpoint — becomes exactly one script.

| Modeled workflow | Observable fact → script |
|---|---|
| Draft a document | the draft file exists → `check_file.py <path>` |
| Publish a page | its relative links resolve → `check_links.py <path>` |
| Charge a card | the gateway authorizes the amount → `check_payment.py <order_id>` |
| Merge a branch | required CI concluded successfully → `check_ci.py <sha>` |

Two failure modes are disqualifying:

- **A fact only the agent can assert** (it "knows" the work is done) is not evidence. Do not wrap it
  in a script that always exits 0 — that scores as evidence and verifies nothing.
- **A fact the script has to *cause*** is not a checker. Checkers inspect and report; the agent does
  the work. Mutating the world from a checker breaks the read-only invariant the driver relies on.

## Where scripts live and how they are registered

The driver runs a tool with `cwd` set to the machine's directory, so keep the scripts beside the
machine — `scripts/check_<fact>.py` is the house convention, as in
[machina-driving's samples](../../machina-driving/samples/) and the `machina-authoring` eval
fixtures.

```json
"tools": {
  "file-exists": { "cmd": "python3 scripts/check_file.py {ctx.draft_path}", "expect_exit": 0 }
},
"states": {
  "drafting": { "description": "…", "checks": ["file-exists"], "on": { "DRAFT_COMPLETE": { "target": "review" } } }
}
```

A checker only runs if it is referenced from a **driver-executed** slot:

| Slot | Effect |
|---|---|
| `states[].checks[]` | gates **every** exit from that state |
| `transitions[].requires[]` | gates that one transition |
| `transitions[].ensures[]` | post-fire, via the `machina-ensures-runner` hook — **which is not installed**, so a checker referenced only here never executes |
| `states[].invariants[]` | **inert** — nothing executes it |

The `checkers-used` compliance check (weight 15, since v3.0.0) requires at least one usable checker,
so a v3 definition with a registry nothing invokes, or with every reference parked in
`ensures[]`/`invariants[]`, scores below Excellent.

## Interface contract

Every rule here comes from the driver's implementation, not from convention.

| Concern | Contract |
|---|---|
| Verdict | Exit code is the result: pass iff `exit == expect_exit` (default `0`). Reserve `2` for usage errors. |
| Streams | The driver parses `stdout + stderr` **concatenated**. When the tool declares `output`, print nothing but the JSON object on either stream — prose on `stderr` breaks the mapping just as badly as a stray line on `stdout`. |
| Output mapping | `"output": { "errors": "review.errors" }` writes parsed JSON keys into context, so a checker can *feed* the machine, not merely gate it. Applied only on a passing run. |
| Arguments | `{ctx.key}` and `{ctx.key|default}` interpolate from context. Prefer the array form (`["python3", "scripts/check_x.py", "{ctx.path}"]`); the string form is split on whitespace, so a path containing spaces breaks it. |
| No shell | Commands run as an argv list, so `|`, `>`, `&&` and `$VAR` do nothing. Compose in the script instead. |
| Location | Relative script paths resolve against the machine's directory (the driver's `cwd`). |
| Tempo | Checks re-run on every exit attempt and on `status`, so they must be read-only, deterministic, idempotent and fast. |

## Writing one

Start from [../assets/checker-script-template.py](../assets/checker-script-template.py) — shebang,
usage docstring, `exit 2` on bad arguments, one JSON object on `stdout`, `0`/`1` verdict. Replace the
`check()` body with your fact and keep the surrounding shape.

```python
def check(target: Path) -> tuple[bool, dict]:
    holds = target.is_file()
    return holds, {"valid": holds, "path": str(target)}
```

Then make it **fail on purpose** before you ship it: point it at a known-bad case and confirm it
exits non-zero. A checker you have only ever seen pass is untested. The repo's own fixtures model the
shape — "exit 0 on a valid argument, 2 on usage" (see
[`evals/machina-authoring/fixtures/scripts/`](../../../evals/machina-authoring/fixtures/scripts/)).

## Anti-rubber-stamp rules

A scored check that rewards "has a checker" invites a declaration that satisfies the letter of the
rule. Three of those are closed by the check itself, so treat them as requirements:

- **Name the script by path.** `cmd: "python3 -c pass"` has no path-bearing token, so it satisfies
  neither the check nor the driver's script pinning (a pathless checker is pinned as "no script" and
  an edit to it mid-run goes undetected).
- **Keep `expect_exit: 0` for a checker offered as evidence.** A script that always exits 1 "passes"
  under `expect_exit: 1`; inverted expectations are legitimate for a negative fact, but they cannot
  be the checker that proves the machine's evidence exists.
- **Reference it from `checks[]` or `requires[]`.** A reference from `ensures[]` or `invariants[]`
  never executes, so it counts for nothing.

One hole cannot be closed without executing the script: a checker that inspects something unrelated
to the modeled fact. The answer is review, not mechanism — read each checker against the fact it
claims to decide.

## What the surrounding tooling does not do

Known behaviour, so you do not assume more than the machinery delivers:

- The **compliance scorer never runs a checker** and cannot tell a correct script from a plausible
  one. A `100 / Excellent` score attests the declaration.
- `tools-exist` is weight 0 and reports, per tool, whether a path-bearing `cmd` resolves;
  [`checkers-used`](machine-quality.md) (weight 15) is what weights the requirement that one
  checker be usable.
- The driver **ignores a tool's `timeout_seconds`** — every invocation is capped at 30 seconds.
  Keep checkers well under that.
- `invariants[]` is documented as continuously validated but **nothing executes it**, and the
  ensures-runner hook is not installed. Verification today happens in `checks[]` and `requires[]`.
