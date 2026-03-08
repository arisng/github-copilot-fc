# Why Knowledge Extraction Runs Before Session Review

Final session review is more accurate when it evaluates the post-knowledge state of the iteration instead of a pre-knowledge snapshot.

## Coupling

Reordering `KNOWLEDGE_EXTRACTION` ahead of `SESSION_REVIEW` is a coordinated contract change across orchestration, review, and knowledge surfaces.

- Orchestration must route `BATCHING -> KNOWLEDGE_EXTRACTION -> SESSION_REVIEW`.
- Reviewer guidance must require knowledge outputs as review evidence while keeping next-state decisions advisory only.
- Knowledge extraction must not depend on a review artifact that does not exist yet.

## Design Outcome

The Reviewer gains better evidence without gaining routing authority. The Orchestrator still owns thresholds and state transitions.