---
date: 2026-03-24
type: Feature Plan
status: Draft
severity: Low
tags:
  - agentic-engineering
  - workshop
  - copilot
  - agenda
  - learning
---

# Agentic Engineering Workshop: Agenda Plan

## 1. Executive Summary

A 2-3 hour online workshop on **Agentic Engineering** (AI-assisted software development workflows) with hands-on demos using **GitHub Copilot** as the primary coding agent. The session emphasizes practical patterns, orchestration best practices, and interactive labs using curated reference URLs.

## 2. Goals

- Introduce Agentic Engineering concepts, roles, and lifecycle.
- Demonstrate Copilot-driven development workflows, including orchestration and tool integration.
- Practice building, validating, and deploying agentic features using curated reference patterns.
- Define takeaway artifacts: playbook, code samples, next-step checklist.

## 3. Audience

- Software engineers exploring AI-assisted development.
- Team leads planning agentic workflows in product cycles.
- Developer advocates preparing demos for AI-first coding.

## 4. Duration

- Total: 2-3 hours
- Format: Online meeting (video conference + shared IDE/session)

## 5. Agenda

1. **Welcome & context (15 min)**
   - Introductions
   - Workshop objectives
   - Quick definitions: agentic system, coding agent, orchestration, HITL

2. **Foundations of Agentic Engineering (20 min)**
   - Core patterns from https://simonwillison.net/guides/agentic-engineering-patterns/
   - Orchestration primitives (agents, instructions, skills, MCP servers)
   - Success criteria (safety, repeatability, observability)

3. **Copilot Demo #1: Ideation to Code (30 min)**
   - Validate use case: automation script, data pipeline, API feature
   - Run Copilot in VS Code with live prompt and refactoring iterations
   - Quick pairing exercise: attendees propose refinements

4. **Agentic Workflow & Architecture (30 min)**
   - Reference patterns from https://dometrain.com/workshop/vibe-coding-for-production/ and https://vibeworking.neuronsai.net/
   - Session: map requirements to agent/instruction/skill artifacts
   - Code walkthrough: Copilot CLI + repository orchestration for safe rollout

5. **Break (10 min)**

6. **Copilot Demo #2: End-to-end in 60 min (hands-on lab)**
   - Build feature from scratch (e.g., marketplace plugin or task automation)
   - Use GitHub Copilot as primary coding agent to scaffold, test, and document
   - Pair program mode: attendees follow with own forks/branches

7. **Risks, governance, and anti-patterns (15 min)**
   - Lessons from https://towardsdatascience.com/claude-skills-and-subagents-escaping-the-prompt-engineering-hamster-wheel/
   - Avoid lock-in, hallucination, and unreviewed changes
   - Share review checklist and enforcement guardrails

8. **Wrap-up and next steps (15 min)**
   - Workshop outputs: agenda record, shared repository, follow-up learning plan
   - Feedback form and community channels

## 6. Reference URLs

- https://dometrain.com/workshop/vibe-coding-for-production/
- https://vibeworking.neuronsai.net/
- https://simonwillison.net/guides/agentic-engineering-patterns/
- https://github.com/github/copilot-cli-for-beginners
- https://towardsdatascience.com/claude-skills-and-subagents-escaping-the-prompt-engineering-hamster-wheel/

## 7. Acceptance Criteria

- [ ] Agenda is written and reviewed
- [ ] Copilot demos are scripted and tested before workshop
- [ ] Reference resources included and validated
- [ ] Follow-up playbook is drafted after session

## 8. Notes

- Workshop artifacts should be added to `.docs/`, `scripts/`, or `agents/` as follow-up tasks.
- Keep the workshop interactive and hands-on; minimize lecture time.
