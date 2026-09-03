# Machina Driving Protocol

The agent-facing playbook for driving a Machina state machine to a deterministic
outcome. Read this when you are the agent executing a task under a machine.

## Roles

| Role | Who | Responsibilities |
|---|---|---|
| **Driver** | `scripts/machine-driver.py` | Sole mutator of run state/context/history/logs. Validates legality + evidence. Emits strict JSON. |
| **Agent (you)** | the AI agent | Performs the real work in the world. Chooses events. Attaches notes. Never touches run state. |
| **Human conductor** | the user | Initiates the run, reviews the report, resolves escalations. |

## Invariants

- **INV-1** You never hand-edit a machine's current state, context, history, or
  logs. The driver is the only writer. Run state lives in a tamper-evident,
  append-only ledger (chained SHA-256 hashes); any tamper is detected and
  reported as a ledger integrity violation.
- **INV-2** Machine JSON never contains code strings. Tools are named references
  to scripts the driver executes. You never inline code into a machine.
- **Post-init context immutability**: after `init`, only machine actions and
  tool-output mappings mutate context. Your `--note` is the only agent-authored
  datum and never touches context.

## Command surface

Every command prints **exactly one strict-JSON object** on stdout. Exit code 0
unless the driver cannot operate safely. A blocked `fire` is a first-class JSON
outcome, not an error.

| Command | Purpose |
|---|---|
| `init --machine <file> [--scenario <id>] [--input k=v ...] [--run-dir <dir>]` | Create a run. Returns `run_id`, entry state, enabled/blocked events. Binds the machine definition + tool scripts (see [Tamper prevention](#tamper-prevention)). Refuses run dirs inside a git worktree. |
| `status [--run <id>] [--run-dir <dir>]` | Current state, enabled/blocked events with reasons, invariant check status, context. |
| `fire <EVENT> [--run <id>] [--note "..."] [--run-dir <dir>]` | Fire an event. Returns new state + applied actions, **or** a `blocked` outcome with failing tools/guards. |
| `abort [--run <id>] [--reason "..."] [--run-dir <dir>]` | Abort the run (recorded in ledger). |
| `check [--run <id>] [--run-dir <dir>]` | Terminal integrity gate: re-run full ledger + artifact-hash verification. Emits `{ok:true, data:{machine_sha256_ok, tool_hashes_ok, ledger_locked, run_dir, state, terminal}}`; non-zero exit on violation. Never writes. |
| `report [--run <id>] [--run-dir <dir>]` | Emit the terminal report (`machina.report.v1`), bound to the ledger via `ledger_final_hash`. |

**Run directory:** pass `--run-dir` explicitly. The driving skill instructs you
to use the current session's workspace (e.g. `<session>/files/.machina/runs`).
Runs are session-scoped and never pollute the repo. Default `<cwd>/.machina/runs`
is refused when it lies inside a git worktree — set `MACHINA_ALLOW_REPO_RUNS=1`
to allow only when you explicitly intend a repo-local run. The check is a walk
up from the run-dir base looking for a `.git` entry (file or dir).

## Tamper prevention

The run is tamper-evident against *accidental or silent* modification — any edit
is detected and the run refuses to continue (fail closed). Four mechanisms
(v0.3.0):

1. **Ledger hash chain** — `ledger.jsonl` records chain via `prev_hash`/`hash`;
   `_read_ledger` re-verifies the chain and each record's hash on every command.
2. **Artifact-hash binding** — the `init` record pins `machine_sha256` (the
   canonical machine-definition hash, same normalization as the ledger hash)
   and `tool_hashes` (a `{tool_name: sha256(script_content)}` map for every tool
   the machine references). On every command the driver re-reads the run's
   `machine.json`, recomputes both, and raises a `LedgerIntegrityError` on
   mismatch. Runs initialized before v0.3.0 have no hashes and are treated as
   "not bound" (artifact verification skipped; the ledger chain still verifies).
   Tool-hash skip rule: only tools whose `cmd` resolves to a real script file
   (interpreter-style `cmd` → the first following token with a path separator
   that resolves to a file; direct script `cmd` → the first token) are hashed;
   a tool with no resolvable script is recorded as `null` (nothing pinned).
   `{ctx...}` template values are **not** resolved for hashing — the script file
   identity is what is pinned.
3. **Repo-worktree run-dir refusal** — `init` refuses run dirs inside a git
   worktree unless `MACHINA_ALLOW_REPO_RUNS=1`.
4. **Report bound to the ledger** — `report.json` includes `ledger_final_hash`
   (the last ledger record's hash), so the report is traceable to the exact
   ledger state it was generated from. `check` can derive/compare it.

**Honest ceiling (detect-not-proof):** this is *not* cryptographic protection
against an attacker who can rewrite the whole run directory — there is no
OS-level read-only enforcement and no HMAC by design. A forger who rewrites
`machine.json`, the checker scripts, and the `init` record (recomputing
`machine_sha256`/`tool_hashes` and re-chaining the ledger) is undetectable by
the driver, same as any log. What the mechanisms guarantee is deterministic
**detection** of any single or partial edit — definition copy, checker script, or
ledger record — and a fail-closed refusal to continue the run.

## Driving loop

1. **Discover** the governing machine (see [Discovery](#discovery)).
2. **Init**: `init --machine <machine.json> --scenario <id> --input k=v ...`.
   All required scenario inputs must be supplied or `init` fails.
3. **Work the current state**: perform the real work the state demands (the
   state's `description` tells you what). Do not fire events until the work is
   genuinely done.
4. **Check status**: `status` shows enabled vs blocked events and why. A blocked
   event means a guard or evidence check failed — fix the underlying condition,
   then retry. Never fire an event whose evidence you have not satisfied.
5. **Fire**: `fire <EVENT> --note "what you did"`. The driver re-verifies guards
   and evidence deterministically. A `blocked` outcome is normal feedback —
   iterate.
6. **Repeat** until the run reaches a terminal state.
7. **Verify integrity (optional but recommended before reporting)**: `check`
   re-runs the full ledger + artifact-hash verification and returns `{ok:true}`
   only when the run is intact.
8. **Report**: `report` emits the terminal report. **Ground your final summary
   to the report facts** — status, final state, path, events, evidence, context
   snapshot. Never invent claims beyond the report.

## Evidence checks

- State `checks[]` gate **all** exits from that state.
- Transition `requires[]` add edge-specific evidence on top.
- Checkers are **read-only validators** (v1): they inspect and report; they do
  not mutate the world. You do the work; checkers verify.
- A checker may return structured JSON that the machine maps into context via
  its `output` mapping — evidence becomes deterministic state.

## Blocked events

- **Default**: stay in the current state; the ledger records the block; `fire`
  returns `{status:"blocked", reason, detail, evidence}`. Iterate.
- **`else_target`**: if the transition declares one, a guard failure redirects
  to the modeled failure path instead of staying.

## Phase states (nested machines)

A `type:"phase"` state delegates its work to a nested machine:

1. On entering the phase state, `status` reports `"phase": true`. The phase
   state's `description` names the child machine and scenario.
2. **Init the child**: `init --machine <child-machine.json> --scenario <id>
   --input ...` — a nested run with its own `run_id` and ledger.
3. Drive the child to its terminal exactly as any other run.
4. On child success, fire the parent's completion event (e.g. `PHASE_DONE`).
   The driver permits it **iff** the child ended in a success final. A
   non-success child → completion refused with the child's result attached;
   retry (guard on a retry counter), escalate, or abort.
5. The child's outcome folds back into the parent context via the phase state's
   declared `result_map` (child context subset → parent paths) plus the child
   run summary.

## STUCK and escalation

- **STUCK** = non-final state with zero enabled events. This is a modeling gap,
  not a crash. **Never improvise a transition or fabricate completion.**
- On STUCK (or ESCALATED), end your turn with a **grounded report** to the human
  conductor: status, final state, blocked events, evidence failures, and what
  the human should decide. The chat session is the escalation channel in v1.

## Report grounding

The terminal report (`machina.report.v1`) is the single source a human can audit
against. Your final user-facing summary must be **contractually bound** to it:

- `result`: `SUCCESS` (reached a final state) · `ESCALATED` · `ABORTED` ·
  `STUCK` · `IN_PROGRESS`
- `final_state`, `path`, `events`, `blocked_events`
- `evidence`: `{ passed, failed }`
- `context_snapshot`, `agent_notes`, `nested_runs`

Render only report facts. If the report says `STUCK`, say so — do not claim
success.

## Discovery

The governing machine is found via the relevant skill's `SKILL.md` frontmatter:

```yaml
machina:
  machine: machines/docs-authoring.machine.json
  scenario: default
```

When a task names a skill, read its `SKILL.md`; if it declares `machina:`, load
the referenced machine and drive it. When the human conductor names a machine
file directly, use that. Never guess a machine that is not declared.

## Trust boundary

The driver executes referenced checker scripts with the user's privileges.
Machines are **trusted artifacts** (authored by the user or by
`machina-authoring`), same trust level as the skill itself. No sandboxing in v1.
Tamper detection protects the *run* against silent drift; it is not a security
boundary against a determined attacker (see
[Tamper prevention](#tamper-prevention)).