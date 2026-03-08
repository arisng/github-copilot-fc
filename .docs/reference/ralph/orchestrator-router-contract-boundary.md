# Orchestrator Router Contract Boundary

## Rule

The Orchestrator may route only from contract-level inputs: session state, transition guards, progress facts, declared task records, role return payloads, optional forwarded context, and signal state. It must not inspect workspace content to infer session subject matter.

## Preserved Constraints

- Keep Orchestrator purity aligned with the ORCH-034 and ORCH-035 boundary.
- Discovery and workspace-aware analysis remain owned by Planner, Questioner, Executor, Reviewer, and Librarian.
- Resume behavior may inspect declared resume artifacts only. If the required artifacts are missing, fail explicitly instead of inferring from unrelated files.

## Operational Implication

When resume or routing context is incomplete, tighten the artifact contract rather than adding fallback workspace analysis to the Orchestrator.