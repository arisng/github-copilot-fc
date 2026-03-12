---
date: 2026-03-12
type: RFC
severity: N/A
status: Proposed
---

# RFC: Harnessing vs. Hardening in Agentic Engineering

## Summary
This RFC formalizes the distinction between **Harnessing** (directing capability) and **Hardening** (securing and stabilizing) within the context of Software and Agentic Engineering. It provides a conceptual framework for AI Engineers to differentiate between enabling an agent's power and ensuring its safe, reliable operation.

## Motivation
In the emerging field of Agentic Engineering, terminology often overlaps with traditional software engineering, creating ambiguity. Developers frequently conflate "making an agent work" with "making an agent safe." Establishing clear definitions helps teams prioritize work across the development lifecycle, moving from functional "harnessed" prototypes to robust "hardened" production systems.

## Detailed Design

### 1. Harnessing (Directing Capability)
Harnessing is the process of capturing and directing raw technology through interfaces, tooling, and infrastructure.

*   **Software Engineering:** Focused on **Test Harnesses**. Sets of data and software configurations used to execute program units under controlled conditions.
*   **Agentic Engineering:** Focused on **Steering the LLM**. Creating the operational environment for an agent, including:
    *   **Tools:** Providing APIs and function definitions.
    *   **Persona:** Crafting specific system prompts.
    *   **Sandbox:** A controlled space where reasoning translates to system actions (e.g., a RAG pipeline).

| Feature | Software Engineering (General) | Agentic Engineering |
| --- | --- | --- |
| **Focus** | Observability and Testing | Capability and Tool-use |
| **Goal** | Verify functional correctness. | Enable real-world interaction. |
| **Example** | Mock APIs for unit tests. | RAG pipelines for context. |

### 2. Hardening (Securing and Stabilizing)
Hardening is the process of reducing vulnerability surfaces and ensuring stability against edge cases or malicious intent.

*   **Software Engineering:** Disabling unneeded services, closing ports, encrypting data, and patching vulnerabilities.
*   **Agentic Engineering:** Managing the "critical frontier" of AI safety, including:
    *   **Prompt Injection:** Preventing unauthorized overrides.
    *   **Guardrails:** Stopping hallucinations or illegal actions.
    *   **Determinism:** Ensuring reliability from non-deterministic models.

## Alternatives Considered
*   **Merging concepts**: Treating both as "Quality Assurance." **Rejected** because it misses the distinction between "reins" (harnessing capability) and "armor" (hardening security).
*   **Using traditional terms only**: Sticking to "Capability" and "Security." **Rejected** because "Harnessing" captures the interactive/environmental nature of agent development better than "Capability" alone.

## Unresolved Questions
- [ ] How do we measure the "hardness" of a non-deterministic agent?
- [ ] At what specific point in the Ralph-v2 workflow should a change move from Harnessing to Hardening?
- [ ] Should specific "Hardening Tools" be first-class citizens in the Agent Framework?

## Potential Future Work

- To refine the current skill `harness-engineering-copilot` to explicitly address harnessing checklist for each agent customization primitive.
- To create new skills about `hardening-copilot-<agent-customization-primitive>` that focus on best practices for securing and stabilizing agents in production.