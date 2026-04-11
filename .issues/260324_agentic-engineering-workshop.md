---
date: 2026-03-24
type: Feature Plan
status: In Progress
severity: Medium
tags:
  - agentic-engineering
  - workshop
  - slidev
  - openspec
  - github-pages
---

# Agentic Engineering Workshop Baseline

## Executive Summary

This issue is the **git-versioned baseline** for the Agentic Engineering workshop. The workshop has already moved well beyond an agenda-only draft: multi-pass planning produced the workshop structure, engineering and non-engineering use cases, and a full Slidev deck, while the media pipeline evolved into a repeatable catalog-and-injection workflow.

The next iteration should sharpen the workshop into a **practical, delivery-oriented showcase**. The anchor scenario is no longer a generic SDD demo; it is an **OpenSpec-first** end-to-end build for a pragmatic quick win that works for non-pro coding roles in a tech team: use agentic workflows to create, test, and ship a stunning dark-theme landing page that sells the course **"agentic engineering"**, publish it to GitHub Pages, and back the registration/contact flow with GitHub Issues.

This issue should be treated as the human-readable source of truth for the workshop baseline and the next phase of work.

## Goals

- Keep the workshop practical, concrete, and oriented around shipped outcomes rather than abstract agent theory.
- Show how agentic workflows can help both engineers and adjacent delivery roles move from idea to production.
- Use one compelling showcase to demonstrate the full flow: ideation -> specification -> implementation -> testing -> shipping.
- Preserve the workshop-building process as a reusable asset, not a one-off effort.

## Audience

- Software engineers and tech leads exploring agentic delivery workflows.
- Business analysts, product managers, product owners, and marketers inside tech teams who need pragmatic AI-assisted execution without being professional coders.
- Internal facilitators or future presenters who need a reusable workshop kit and repeatable authoring workflow.

## Intended Outputs

- A modular Slidev workshop deck that can be iterated quickly and presented as a single web app.
- A practical showcase that demonstrates OpenSpec-first delivery from concept to deployment.
- A media workflow that supports rich visuals, demos, placeholder briefing, and deterministic media injection.
- A reusable workshop-building skill created through the `skill-creator` workflow so future workshops can follow the same process.

## Current Baseline

The following baseline is already established in a Copilot session workspace and is now captured here so the issue becomes the durable git-tracked reference:

- These completed items describe the **current workshop workspace layout and behavior**, not files that are already committed under this repository root.
- The git-tracked issue is the durable baseline; the concrete Slidev deck, media inventory, placeholders, and generated output still need a later pass if we want to materialize them inside this repo.

These checked items record the settled workflow conventions and recovery target for the effort. They should not be read as a claim that every authored slide, section, placeholder, or inventory file is already committed in the current repository snapshot.

- [x] **Multi-pass workshop planning is complete.**
  - The workshop now has a concrete agenda, overall structure, engineering and non-engineering use cases, and a full draft Slidev deck.
- [x] **The deck architecture has converged on a single Slidev app.**
  - The authored structure is a single Slidev web app centered on `slides/main.md`, modular content under `slides/sections/*.md`, and imported `slides/modules/*.md` / partials rather than disconnected slide files.
- [x] **A media catalog workflow exists.**
  - Visual and demo assets are indexed.
  - Detailed asset briefs exist for placeholders.
  - Concrete placeholder files are seeded so the deck can be built and rehearsed before final media arrives.
  - The workflow generates `slides/generated/` from slide sources plus stable media paths under `public/media/<segment-id>/<slide-slug>/<track>-<slot>.*` and `media-catalog/inventory/media-index.json`.
- [x] **Media injection is index-driven and repeatable.**
  - The deck can be regenerated deterministically from the catalog rather than manually editing slides every time media changes.
- [x] **Both authored-deck and media-ready build/dev flows exist as part of the baseline.**
  - The workshop supports the normal deck workflow for authoring and a media-ready workflow for rehearsal/build outputs.
- [x] **A reusable workshop-building skill now exists.**
  - `skills/online-workshop-builder/` captures the multi-pass planning loop, OpenSpec-first showcase spine, single-app Slidev structure, stable media-path strategy, catalog-driven injection, and feedback reconciliation flow.

### Baseline workflow conventions

These conventions should be treated as authoritative until explicitly superseded:

- When the workshop is materialized in a working deck workspace, author it as one Slidev app rooted at `slides/main.md`; if tooling ever synthesizes `slides/generated/index.md`, treat that as derived output rather than the authored source of truth.
- Keep authored slide content modular under `slides/sections/*.md`, with reusable fragments under `slides/modules/*.md`, so new material can be inserted without flattening the deck.
- Treat `media-catalog/inventory/media-index.json` as the source of truth for media injection in that workshop workspace.
- Seed placeholder assets at stable paths under `public/media/<segment-id>/<slide-slug>/<track>-<slot>.<ext>` and replace those files in place as final visuals or demos arrive.
- Reconcile accepted feedback in this order: issue baseline -> agenda -> deck map and authored slides -> media briefs/placeholders/catalog -> `slides/generated/`.

## Next Iteration / New Direction

### 1. Reuse and evolve the workshop-building skill

The workshop now includes a reusable skill created through the `skill-creator` workflow. Keep it aligned as the workshop evolves. The skill should continue to capture:

- multi-pass workshop planning and refinement
- single-app Slidev authoring with `slides/main.md` plus section modules
- media cataloging, placeholder briefing, and stable asset stems under `public/media/<segment-id>/<slide-slug>/<track>-<slot>`
- seeding concrete placeholder files so work can continue before final assets exist
- index-driven media injection from `media-catalog/inventory/media-index.json` into `slides/generated/`
- a repeatable process for reconciling accepted feedback back into the issue baseline, agenda, authored deck, media catalog, and generated deck

### 2. Make the SDD showcase OpenSpec-first

Shift the showcase away from a SpecKit-first framing.

- **Primary path:** OpenSpec-first specification and delivery workflow
- **Plan B only:** SpecKit if OpenSpec proves unsuitable for a specific step

The workshop should explicitly present OpenSpec as the default SDD story for this showcase.

### 3. Redesign the showcase around a pragmatic quick win

Refocus the main scenario so it works for non-pro coding roles embedded in a tech team, especially:

- business analyst
- product manager
- product owner
- marketer

The showcase should walk through a complete end-to-end flow:

1. ideation
2. specification
3. implementation
4. testing
5. shipping

The concrete deliverable is:

- a **stunning dark-theme landing page** for the course **"agentic engineering"**
- shipped as a **static site on GitHub Pages**
- with a **registration/contact form backed by GitHub Issues**

### 4. Keep the workshop delivery-oriented

The tone and structure should stay hands-on and outcome-focused:

- minimize abstract theory unless it directly supports execution
- use artifacts, commands, specs, screens, and deployable outputs as teaching anchors
- make the value visible to people who are coordinating delivery, not only writing code

## Work Items

### Baseline already completed

- [x] Produce the initial workshop structure through multi-pass planning.
- [x] Expand the workshop to cover both engineering and non-engineering use cases.
- [x] Create the full Slidev deck concept and converge on a single-app authoring structure.
- [x] Establish the media catalog, placeholder briefing, seeded placeholder files, and generated deck workflow.
- [x] Define both normal deck and media-ready build/dev paths.

### Next phase

- [ ] Rewrite the showcase narrative around the OpenSpec-first landing-page scenario.
- [ ] Define the non-pro coding persona journey so BA/PM/PO/marketer attendees can follow the flow without needing deep coding expertise.
- [ ] Specify the course landing page in OpenSpec, keeping SpecKit as plan B only.
- [ ] Implement and test the dark-theme static landing page flow end to end.
- [ ] Ship the showcase site to GitHub Pages.
- [ ] Design and validate the GitHub Issues-backed registration/contact form flow.
- [x] Create the reusable workshop-building skill with the `skill-creator` workflow.
- [ ] Capture the repeatable "new idea arrives -> update baseline -> agenda -> deck -> media catalog -> generated deck -> rehearse/build" process inside the skill and workshop notes.

## Acceptance Criteria

- [x] This issue reflects the real current workshop baseline rather than the original early-draft agenda.
- [x] The current baseline explicitly documents the Slidev single-app structure rooted at `slides/main.md`, the section-module layout, the stable media-path strategy, the media catalog workflow, generated deck output, and dual deck/media paths.
- [ ] The primary showcase is OpenSpec-first, with SpecKit documented only as fallback guidance.
- [ ] The workshop centers on a practical quick win for BA/PM/PO/marketer-style roles in a tech team.
- [ ] The showcase demonstrates the full flow from ideation to GitHub Pages shipping.
- [ ] The landing page outcome is a compelling dark-theme course site for **"agentic engineering"**.
- [ ] Registration/contact capture is implemented through GitHub Issues.
- [x] A reusable workshop-building skill exists and codifies planning, Slidev authoring rooted at `slides/main.md`, stable-stem media preparation, catalog-driven injection, and feedback reconciliation across the baseline issue, agenda, deck, media catalog, and generated deck workflow.
- [ ] The workshop remains practical and delivery-oriented, with each major section tied to a concrete artifact or shipped result.
