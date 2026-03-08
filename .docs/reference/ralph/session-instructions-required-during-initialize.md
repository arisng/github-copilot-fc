# Session Instructions Required During Initialize

## Rule

`.ralph-sessions/<SESSION_ID>.instructions.md` is a required INITIALIZE artifact for every Ralph session.

## Required Surfaces

- The planning specification must list the session instructions file as part of the INITIALIZE artifact set.
- Planner INITIALIZE workflow steps must create the file by default.
- Session-specific constraints may refine the file contents, but they do not control whether the file exists.

## Operational Implication

Treat session-instructions creation as contract enforcement, not as an optional convenience step or an explicitly requested add-on.