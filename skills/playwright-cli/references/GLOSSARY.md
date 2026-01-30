# Glossary: Browser Automation & Testing Terms

Fundamental terminology in browser automation and UI testing, with focus on Playwright CLI and E2E scripts.

## Table of Contents
- [A](#a)
- [B](#b)
- [C](#c)
- [E](#e)
- [F](#f)
- [H](#h)
- [M](#m)
- [P](#p)
- [R](#r)
- [S](#s)
- [T](#t)

## A

**Ad-hoc Testing**

Unplanned, informal checks performed on-demand to verify specific behaviors or bugs. With Playwright CLI, this involves manual, one-off commands (e.g., quick navigation or element inspection) for immediate feedback. Differs from exploratory testing by lacking structure or documentation. Use for POC quick wins; avoid for production due to lack of repeatability.

**Assertions**

Checks in automated tests to verify expected outcomes (e.g., element visibility or text content). Not natively supported in Playwright CLI (which is command-driven); instead, use in E2E scripts (e.g., `expect(page.locator('text=Welcome')).toBeVisible()`). Essential for automation testing but absent in manual CLI sessions.

**Automation Testing**

Using tools to execute tests programmatically without human intervention, ensuring repeatability and scalability. With Playwright CLI, this means scripting sequences of commands for repeatable tasks (e.g., data extraction or form filling). Differs from manual testing by being code/script-based. Ideal for long-term production investments; use CLI for lightweight automation, scripts for full suites with assertions.

## B

**Browser Automation Testing**

Broad term for automating browser interactions to simulate user actions, validate UI, or extract data. Playwright CLI excels here for interactive or scripted tasks; E2E scripts provide structured automation. Encompasses both manual (CLI-driven) and automated (script-driven) approaches.

**Browser UI Testing**

Focused on validating user interface elements, layouts, and interactions in browsers. Includes visual checks, responsiveness, and cross-browser compatibility. Playwright CLI supports manual UI exploration (e.g., snapshots, hovers); scripts automate UI assertions. Use CLI for POC UI prototyping, scripts for regression UI testing.

## C

**CI/CD Integration**

Incorporating tests into continuous integration/delivery pipelines for automated builds and deployments. Playwright scripts integrate natively (e.g., via `npx playwright test`); CLI can be embedded for pre-checks (e.g., smoke tests). Long-term investment for production releases; CLI for quick pipeline validations.

**Cross-Browser Testing**

Verifying app behavior across different browsers (e.g., Chromium, Firefox, WebKit). Playwright CLI uses profiles for this (e.g., `profiles/firefox.json`); scripts run parallel tests. Use CLI for manual cross-browser checks in POC; scripts for automated, scalable cross-browser suites.

## E

**End-to-End (E2E) Testing**

Testing complete user workflows from start to finish (e.g., login to checkout). Playwright scripts are primary for E2E due to assertions and suites; CLI supports E2E exploration or scripting. Long-term automation investment; CLI for POC E2E prototyping.

**Exploratory Testing**

Structured, investigative testing to learn app behavior, identify edge cases, and inform test design. With Playwright CLI, this involves guided manual exploration (e.g., navigating flows, inspecting elements) with documentation. Differs from ad-hoc by being planned and goal-oriented. Use CLI for POC exploration to design scripts; transition to automated scripts for production.

## F

**Flaky Tests**

Tests that pass/fail inconsistently due to timing, environment, or race conditions. Common in browser testing; Playwright CLI helps debug via interactive commands (e.g., retries, traces); scripts mitigate with waits and retries. Address in long-term automation; CLI for quick triage.

## H

**Headless Mode**

Running browsers without a visible UI, speeding up tests. Supported in both CLI (via profiles) and scripts. Use for CI/CD automation; CLI for headless POC runs.

## M

**Manual Testing**

Human-driven testing where testers interact directly with the app. With Playwright CLI, this means issuing commands interactively (e.g., `click e5`, `type "text"`). Differs from automation by requiring human oversight. Ideal for POC quick wins and exploration; not scalable for production releases.

## P

**Playwright CLI**

Command-line tool for interactive browser automation (e.g., navigation, interactions, snapshots). Best for manual, exploratory, or ad-hoc tasks. Use for POC quick wins; complement with scripts for automation.

**Playwright Test Framework/Scripts**

Code-based testing framework (TypeScript/JavaScript) for writing structured E2E tests with assertions and suites. Primary for automation testing and production releases. Use for long-term investments; integrate with CLI for exploration.

**POC (Proof of Concept)**

Short-term experiments to validate ideas or feasibility. Use Playwright CLI for quick, manual wins (e.g., UI exploration, ad-hoc checks). Boundary: POC is exploratory and disposable; avoid for production.

**Production-Ready Releases**

Stable, automated testing for live deployments. Rely on E2E scripts for regression, CI/CD, and assertions. Use CLI sparingly for debugging; long-term investment focuses on scripts.

**Profiles**

Pre-configured JSON files defining browser settings (e.g., viewport, user agent). Shared between CLI and scripts for consistency. Essential for cross-browser/device testing in both POC and production.

## R

**Regression Testing**

Verifying that new changes don't break existing functionality. Automated via E2E scripts; CLI for manual regression checks. Long-term investment; CLI for POC regression validation.

## S

**Selectors**

Methods to identify UI elements (e.g., CSS, XPath, data attributes). Used in both CLI (e.g., `click e5`) and scripts (e.g., `page.locator('button')`). Robust selectors are key for reliable testing; prioritize `data-testid` for production.

**Sessions**

Isolated browser contexts in Playwright CLI for multi-tab or stateful interactions. Useful for complex manual flows; scripts manage contexts programmatically.

**Smoke Testing**

Basic, quick checks to ensure core functionality works. Use CLI for manual smoke runs (e.g., open page, check load); scripts for automated smoke suites. POC quick win; integrate into production pipelines.

## T

**Test Suites**

Collections of organized tests. Native to E2E scripts; CLI can simulate via command sequences. Long-term automation requires scripts.

**Tracing/Screenshots**

Debugging artifacts capturing browser state, network, and visuals. CLI generates via `tracing-start` or `screenshot`; scripts via `page.screenshot()`. Use in both POC debugging and production failure analysis.
