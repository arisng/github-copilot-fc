---
domain: signals
version: 0.1.0
status: draft
created_at: 2026-03-02T15:08:02+07:00
updated_at: 2026-03-02T15:36:23+07:00
---

# Signals Specification

This specification defines the cross-cutting signal protocol — the typed, targeted, ordered message delivery system with acknowledgment and lifecycle management. Every role specification references this protocol at its behavioral checkpoints. The signal protocol depends only on Session vocabulary (SES- prefix); all other domain specifications depend on this protocol.

## Signal Types

The system defines exactly four signal types. Each type carries mandatory behavioral semantics that the recipient MUST enforce.

| Type | Category | Behavioral Semantics |
|---|---|---|
| **STEER** | Universal | Trajectory correction — the recipient MUST adjust its current approach based on the signal payload |
| **INFO** | Universal | Context injection — the recipient SHOULD incorporate the payload into its active context; no behavioral change is required |
| **PAUSE** | Universal | Temporary halt — the recipient MUST stop execution at the next safe boundary and preserve its current state for later resumption |
| **ABORT** | Universal | Permanent halt — the recipient MUST stop immediately, execute the finalization checklist, and record the termination |

## Requirements

### Signal Type Semantics

#### SIG-001: Recognized Signal Type Set
The system MUST recognize exactly four signal types: STEER, INFO, PAUSE, and ABORT. Any signal whose type does not match one of these four values MUST be left unconsumed in the Signal Channel (Inbound) (per SES-012).

#### SIG-002: STEER — Trajectory Correction
When a role receives a STEER signal, it MUST evaluate the signal payload against its in-progress work and apply one of the following responses:

1. **Work invalidated** — the payload contradicts already-completed work. The role MUST restart its current operation with the updated context.
2. **Additive / non-conflicting** — the payload adds constraints without invalidating current work. The role MUST incorporate the new context and continue from its current position.
3. **Scope change** — the payload fundamentally redefines the task objective. The role MUST halt and escalate to the Orchestration Role for task redefinition.

The role MUST determine which response applies by evaluating: (a) whether artifacts already produced are invalidated, (b) whether success criteria have changed, and (c) whether the task objective itself has been redefined.

#### SIG-003: INFO — Context Injection
When a role receives an INFO signal, it SHOULD add the payload to its active knowledge context. An INFO signal MUST NOT trigger restarts, halts, or escalation. If the information implies the role should change behavior, the sender MUST use STEER instead.

#### SIG-004: PAUSE — Temporary Halt
When a role receives a PAUSE signal, it MUST:
1. Complete the current atomic operation (no partial artifacts).
2. Record current progress in the Progress Tracker (per SES-018) with a pause indicator.
3. Return a paused status to the Orchestration Role.

Resumption after a PAUSE MUST be initiated by the Orchestration Role, which MAY attach updated context from the PAUSE signal payload.

#### SIG-005: ABORT — Permanent Halt
When a role receives an ABORT signal, it MUST execute the following finalization checklist in order:
1. Mark all in-progress tasks as failed with reason "Aborted by signal" in the Progress Tracker (per SES-015).
2. Update the Session State Store (per SES-012) to record the abort status.
3. Record the completion timestamp in the Iteration State Store (per SES-008).
4. Preserve all artifacts produced so far — reverting work is MUST NOT.

After finalization, the role MUST return a blocked status indicating the abort.

#### SIG-006: Targeted INFO Conventions
An INFO signal MAY carry structured intent via the combination of a specific target role and a recognized payload prefix. This convention MUST NOT require protocol changes — only the targeted role's processing logic interprets the prefix. Unrecognized prefixes MUST be treated as standard INFO context injection.

### Signal Delivery and Ordering

#### SIG-007: Creation-Ordered Identity
Every signal record MUST carry a creation-ordered identity that establishes its position in the delivery sequence. Signals MUST be sortable by this identity such that earlier-created signals sort before later-created signals.

#### SIG-008: FIFO Delivery Guarantee
Signals in the Signal Channel (Inbound) MUST be processed in creation order — the oldest signal (by creation-ordered identity) MUST be consumed first. No signal MAY be processed before an older signal in the same channel has been consumed or explicitly skipped due to target mismatch.

#### SIG-009: Target-Aware Routing
Every signal MUST carry a target field with one of the following values:
- **ALL** — broadcast to all active roles.
- **A specific role name** — delivered to exactly one role.

The target namespace MUST use role names only (Orchestration Role, Execution Role, Planning Role, Discovery Role, Review Role, Knowledge Role). Version identifiers MUST NOT appear in target values.

#### SIG-010: Target Filtering
When a role polls the Signal Channel (Inbound), it MUST skip any signal whose target does not match either ALL or the role's own identity. Skipped signals MUST remain in the channel for the correct recipient.

### Acknowledgment Protocol

#### SIG-011: Broadcast Acknowledgment Requirement
When a signal has target ALL, every active role that processes it MUST create a Signal Acknowledgment Record (per SES-012) specific to that signal and that role. The role MUST NOT remove the signal from the Signal Channel (Inbound) after acknowledgment.

#### SIG-012: Acknowledgment Quorum Set
The required acknowledgment quorum for broadcast signals MUST include: the Orchestration Role, Execution Role, Planning Role, Discovery Role, and Review Role. Episodic roles (roles that are invoked only during specific states, such as the Knowledge Role) MUST be excluded from the required quorum set to prevent quorum deadlock during states where episodic roles are not active.

#### SIG-013: Broadcast Archival Gate
A broadcast signal MUST NOT be moved from the Signal Channel (Inbound) to the Signal Archive until acknowledgment records exist from all roles in the quorum set (per SIG-012). Only the Orchestration Role MAY perform this archival.

#### SIG-014: Idempotent Acknowledgment
A role's acknowledgment for a given signal MUST be idempotent. Writing an acknowledgment record when one already exists for the same role and signal MUST be a no-op.

#### SIG-015: Single-Target Consumption
When a signal targets a specific role (not ALL), the targeted role MUST consume the signal by moving it from the Signal Channel (Inbound) to the Signal Archive with handling metadata. No acknowledgment record is required for single-target signals.

### Signal Lifecycle

#### SIG-016: Lifecycle States
Every signal MUST pass through exactly three lifecycle states in order:
1. **Created** — the signal exists in the Signal Channel (Inbound) and has not been processed by any role.
2. **Acknowledged** — at least one role has processed the signal. For broadcast signals, this state persists until quorum is reached. For single-target signals, this state is transient (immediately transitions to processed).
3. **Processed** — the signal resides in the Signal Archive with handling metadata recording which role(s) processed it, when, and what action was taken.

#### SIG-017: Handling Metadata Preservation
When a signal transitions to the processed state, the archiving role MUST attach handling metadata recording: the identity of the role that performed final archival, the timestamp of archival, and a summary of the action taken.

#### SIG-018: Session-End Finalization
When the session transitions to its terminal state, the Orchestration Role MUST evaluate all remaining broadcast signals in the Signal Channel (Inbound):
- If all required acknowledgments exist (per SIG-012), the signal MUST be archived normally.
- If some acknowledgments are missing, the signal MUST be archived with a partial delivery indicator and a list of roles that did not acknowledge. This prevents orphaned signals while preserving the delivery audit trail.

### Polling Contract

#### SIG-019: Universal Polling Routine
Every role MUST implement the following behavioral sequence when polling for signals. This routine is the normative contract that all role specifications cross-reference.

1. **Enumerate** — list all signal records in the Signal Channel (Inbound), sorted by creation-ordered identity ascending (per SIG-008).
2. **Peek** — for the oldest signal, read its type and target without consuming it.
3. **Filter** — evaluate the target (per SIG-010):
   - If target does not match ALL or the current role's identity, skip to the next signal.
4. **Route** (broadcast path) — if target is ALL:
   a. Process the signal payload locally according to its type (per SIG-002 through SIG-005).
   b. Create a Signal Acknowledgment Record for the current role (per SIG-011).
   c. Do NOT remove the signal from the channel.
   d. (Orchestration Role only) Check whether all quorum acknowledgments exist. If yes, archive the signal (per SIG-013).
5. **Route** (single-target path) — if target matches the current role:
   a. Process the signal payload according to its type.
   b. Move the signal to the Signal Archive with handling metadata (per SIG-015, SIG-017).
6. **Route** (third-party target, Orchestration Role only) — if target names a different role:
   a. Buffer the signal for delivery at the next invocation of the targeted role.
   b. Move the signal to the Signal Archive.
   c. Do NOT process the payload locally.
7. **Repeat** — continue with the next signal in creation order until the channel is exhausted or a PAUSE/ABORT is encountered.

#### SIG-020: Hybrid Polling Model
The system MUST implement a hybrid polling model where:
- The Orchestration Role polls the Signal Channel (Inbound) at state boundaries (when no other role is active).
- All other roles poll at step boundaries within their own execution (when the Orchestration Role is blocked awaiting their return).

This temporal separation ensures that signals are never unattended during long-running operations. The Orchestration Role and other roles MUST NOT poll simultaneously.

#### SIG-021: Checkpoint Placement
Every role MUST poll for signals at:
1. **Initialization** — before beginning any work.
2. **Step boundaries** — between major workflow steps.
3. **Loop boundaries** — between iterations of repeated operations.

The Orchestration Role MUST additionally poll at every state transition boundary.

#### SIG-022: Unrecognized Signal Handling
If a signal's type does not match the recognized type set (per SIG-001), the polling role MUST leave the signal in the Signal Channel (Inbound) without modification.

### Orchestration Role Archive Moments

#### SIG-023: Deterministic Archive Points
The Orchestration Role MUST archive signals at exactly the following moments:
1. **Self-targeted consumption** — immediately after processing a signal targeted to the Orchestration Role (per SIG-015).
2. **Third-party routing** — immediately after buffering a signal for a different role (per SIG-019 step 6).
3. **Broadcast quorum** — when all quorum acknowledgments exist for a broadcast signal (per SIG-013).
4. **Session-end finalization** — during terminal state transition, for all remaining broadcast signals (per SIG-018).

No other archive moment is permitted for the Orchestration Role.

## Scenarios

### SC-SIG-001: STEER Signal — Work Invalidated
**Validates**: SIG-002 (branch 1), SIG-008
```
GIVEN a role is executing a task and has produced partial artifacts
AND a STEER signal exists in the Signal Channel (Inbound) with a payload that contradicts the produced artifacts
WHEN the role polls at a step boundary
THEN the role processes the oldest signal first (FIFO)
AND determines that existing work is invalidated
AND restarts the current operation with the updated context from the STEER payload
```

### SC-SIG-002: STEER Signal — Additive Context
**Validates**: SIG-002 (branch 2)
```
GIVEN a role is executing a task
AND a STEER signal exists with a payload that adds constraints without contradicting current work
WHEN the role polls at a step boundary
THEN the role incorporates the new constraints into its active context
AND continues from its current position without restarting
```

### SC-SIG-003: STEER Signal — Scope Change Escalation
**Validates**: SIG-002 (branch 3)
```
GIVEN a role is executing a task
AND a STEER signal exists with a payload that redefines the task objective
WHEN the role polls at a step boundary
THEN the role halts its current work
AND returns a blocked status to the Orchestration Role indicating a scope change
AND does not silently redefine or discard the original task scope
```

### SC-SIG-004: INFO Signal — Context Injection
**Validates**: SIG-003
```
GIVEN a role is executing a task
AND an INFO signal exists in the Signal Channel (Inbound) with contextual information
WHEN the role polls at a step boundary
THEN the role adds the payload to its active knowledge context
AND continues its current workflow without restart, halt, or escalation
```

### SC-SIG-005: PAUSE Signal — Graceful Suspension
**Validates**: SIG-004
```
GIVEN a role is executing a task with an in-progress atomic operation
AND a PAUSE signal exists in the Signal Channel (Inbound)
WHEN the role polls at a step boundary
THEN the role completes the current atomic operation
AND records its progress in the Progress Tracker with a pause indicator
AND returns a paused status to the Orchestration Role
```

### SC-SIG-006: ABORT Signal — Finalization Checklist
**Validates**: SIG-005
```
GIVEN a role is executing a task
AND an ABORT signal exists in the Signal Channel (Inbound)
WHEN the role polls at a step boundary
THEN the role marks all in-progress tasks as failed with reason "Aborted by signal"
AND the Session State Store records the abort status
AND the Iteration State Store records the completion timestamp
AND all produced artifacts are preserved (no revert)
AND the role returns a blocked status
```

### SC-SIG-007: FIFO Ordering Enforcement
**Validates**: SIG-007, SIG-008
```
GIVEN the Signal Channel (Inbound) contains three signals with creation-ordered identities T1, T2, T3 where T1 < T2 < T3
WHEN a role polls the channel
THEN the role processes T1 before T2 and T2 before T3
AND no signal is processed out of creation order
```

### SC-SIG-008: Broadcast Acknowledgment and Archival
**Validates**: SIG-011, SIG-012, SIG-013, SIG-014
```
GIVEN a broadcast signal (target ALL) exists in the Signal Channel (Inbound)
AND the quorum set contains 5 roles (excluding the episodic Knowledge Role)
WHEN the first role processes the signal and creates its Signal Acknowledgment Record
THEN the signal remains in the Signal Channel (Inbound)
AND WHEN the same role creates a duplicate acknowledgment record
THEN the duplicate is a no-op
AND WHEN all 5 quorum roles have created their acknowledgment records
THEN the Orchestration Role moves the signal to the Signal Archive
```

### SC-SIG-009: Episodic Role Quorum Exclusion
**Validates**: SIG-012
```
GIVEN a broadcast signal (target ALL) exists in the Signal Channel (Inbound)
AND the Knowledge Role is not active (session is not in a knowledge-related state)
WHEN all non-episodic roles create their acknowledgment records
THEN the broadcast quorum is satisfied
AND the signal is archived without waiting for the Knowledge Role
```

### SC-SIG-010: Session-End Finalization — Partial Delivery
**Validates**: SIG-018
```
GIVEN the session is transitioning to its terminal state
AND a broadcast signal remains in the Signal Channel (Inbound)
AND only 3 of 5 required acknowledgment records exist
WHEN the Orchestration Role evaluates remaining signals
THEN the signal is archived with a partial delivery indicator
AND the archive record lists the 2 roles that did not acknowledge
```

### SC-SIG-011: Session-End Finalization — Complete Delivery
**Validates**: SIG-018
```
GIVEN the session is transitioning to its terminal state
AND a broadcast signal remains in the Signal Channel (Inbound)
AND all 5 required acknowledgment records exist
WHEN the Orchestration Role evaluates remaining signals
THEN the signal is archived normally with full delivery status
```

### SC-SIG-012: Target Filtering — Mismatch
**Validates**: SIG-009, SIG-010
```
GIVEN a signal with target set to a specific role name exists in the Signal Channel (Inbound)
WHEN a different role polls the channel
THEN the polling role skips the signal without modifying it
AND the signal remains in the channel for the intended recipient
```

### SC-SIG-013: Single-Target Consumption
**Validates**: SIG-015, SIG-017
```
GIVEN a signal targeting a specific role exists in the Signal Channel (Inbound)
WHEN the targeted role polls and finds the signal
THEN the role processes the payload according to the signal type
AND moves the signal to the Signal Archive with handling metadata
AND no Signal Acknowledgment Record is created
```

### SC-SIG-014: Hybrid Polling — Temporal Separation
**Validates**: SIG-020
```
GIVEN the Orchestration Role has invoked a long-running role
WHEN the Orchestration Role is blocked awaiting the invoked role's return
THEN only the invoked role polls the Signal Channel (Inbound) at step boundaries
AND the Orchestration Role does not poll until the invoked role returns
```

### SC-SIG-015: Unrecognized Signal Type
**Validates**: SIG-001, SIG-022
```
GIVEN a signal with an unrecognized type exists in the Signal Channel (Inbound)
WHEN any role polls the channel
THEN the signal is left in the channel without modification
AND the role continues processing subsequent signals
```

### SC-SIG-016: Orchestration Role Third-Party Routing
**Validates**: SIG-019 (step 6), SIG-023 (point 2)
```
GIVEN a signal targeting the Execution Role exists in the Signal Channel (Inbound)
WHEN the Orchestration Role polls the channel
THEN the Orchestration Role buffers the signal for delivery at the next Execution Role invocation
AND moves the signal to the Signal Archive
AND does not process the signal payload locally
```

### SC-SIG-017: Signal Lifecycle Progression
**Validates**: SIG-016
```
GIVEN a new signal is deposited into the Signal Channel (Inbound)
THEN the signal is in the "created" state
AND WHEN a role processes the signal and creates an acknowledgment (broadcast) or consumes it (single-target)
THEN the signal transitions to the "acknowledged" state
AND WHEN the signal is moved to the Signal Archive with handling metadata
THEN the signal is in the "processed" state
```

### SC-SIG-018: Targeted INFO Convention — Recognized Prefix
**Validates**: SIG-006
```
GIVEN an INFO signal targets a specific role with a recognized payload prefix
WHEN the targeted role polls and finds the signal
THEN the role interprets the prefix according to its role-specific convention
AND no protocol-level changes are required
AND other roles treat the same signal as standard context injection
```

### SC-SIG-019: Checkpoint Placement — Initialization
**Validates**: SIG-021
```
GIVEN a role is about to begin work
WHEN the role reaches its initialization step
THEN the role polls the Signal Channel (Inbound) before performing any other action
AND if an ABORT signal is found, the role returns blocked status without starting work
```

### SC-SIG-020: Deterministic Archive — No Unauthorized Points
**Validates**: SIG-023
```
GIVEN the Orchestration Role encounters a broadcast signal during a polling cycle
AND the quorum is not yet satisfied
WHEN the Orchestration Role creates its own acknowledgment record
THEN the signal is NOT archived
AND the signal remains in the Signal Channel (Inbound) until quorum is reached or session ends
```
