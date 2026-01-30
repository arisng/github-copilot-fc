# E2E Scripts & Integration Patterns

Integrate Playwright CLI with E2E test scripts for maximum productivity.

## Table of Contents

- [When to Integrate](#when-to-integrate)
- [10 Solid Workflows](#10-solid-workflows)
- [Best Practices](#best-practices)

## When to Integrate

Playwright CLI complements code-based E2E test scripts (using Playwright's test framework) by providing interactive exploration, debugging, and rapid prototyping. Use these integrations to boost productivity in E2E testing—potentially by 30-50%—through faster test authoring, quicker failure triage, and more reliable suites.

**Key Principle**: Always default to scripts for automation and assertions; use CLI for manual tasks. Limit CLI embedding in scripts to <20% to maintain maintainability.

- **Exploratory Testing**: Use CLI for manual flows before scripting (e.g., uncertain selectors or complex UIs)
- **Debugging Failures**: Reproduce script issues interactively with CLI
- **Prototyping**: Quick validations or data setup before full automation
- **CI/CD**: Pre-checks or parallel sessions alongside script suites
- **Avoid Overuse**: Don't replace scripts with CLI for repeatable tests; CLI lacks assertions and reporting

## 10 Solid Workflows

### 1. Exploratory to Script Conversion (For test authoring)

Explore flows manually, then convert to code.

```bash
# Explore interactively
playwright-cli --config profiles/chromium.json open https://app.com
playwright-cli click e5
playwright-cli fill e3 "user@example.com"
playwright-cli snapshot
```

Then generate code:

```bash
npx playwright codegen https://app.com
```

**Boost**: Cuts writing time by 40-60% for complex UIs.

### 2. Profile Sharing (For consistency)

Reuse CLI profiles in scripts for matching environments.

```javascript
// Load profiles/chromium.json in test setup
import chromiumProfile from './profiles/chromium.json';

test('login', async ({ browser }) => {
  const context = await browser.newContext(chromiumProfile.browser.contextOptions);
  const page = await context.newPage();
  // ...
});
```

**Boost**: Reduces flakes by ensuring same viewport/browser across tools.

### 3. Embedded CLI in Scripts (For niche actions)

Run CLI via child_process for dynamic tasks like uploads.

```javascript
const { execSync } = require('child_process');

test('upload document', async () => {
  // Use script for setup
  await page.goto('https://app.com/upload');
  
  // Use CLI for upload (handles file picker)
  execSync('playwright-cli upload ./document.pdf');
  
  // Use script for assertions
  await expect(page.locator('text=Uploaded')).toBeVisible();
});
```

**Boost**: Leverages CLI simplicity for edge cases without rewriting logic.

### 4. Debugging Workflow (For failure triage)

On script failure, replay with CLI to inspect the DOM.

```bash
# Script failed; replay interactively
playwright-cli --config profiles/chromium.json open https://app.com
playwright-cli click e4
playwright-cli eval "el => el.textContent" e4  # Inspect element
playwright-cli console                         # Check for errors
```

**Boost**: Reduces debugging time by 50% with interactive tools.

### 5. CI/CD Integration (For pipelines)

Run CLI smoke tests before scripts for fast feedback.

```bash
# Smoke test (fast)
playwright-cli open --config profiles/chromium.json https://app.com && \
  playwright-cli eval "document.title" && \
  playwright-cli close

# Full E2E suite (slower)
npx playwright test
```

**Boost**: Fast feedback catches issues before slower suites.

### 6. Data Seeding (For test prep)

Use CLI for UI-based setup, avoiding API dependency.

```bash
# Seed data via UI
playwright-cli --config profiles/chromium.json open https://app.com/admin
playwright-cli fill e1 "test-user"
playwright-cli fill e2 "password123"
playwright-cli click e3  # Create user

# Then run tests against seeded data
npx playwright test
```

**Boost**: Automates data without APIs, simplifying scripts.

### 7. Multi-Session Testing (For concurrency)

Run CLI sessions parallel to scripts for multi-user scenarios.

```bash
# Start two sessions
playwright-cli --session=user1 open https://app.com/login
playwright-cli --session=user2 open https://app.com/login

# CLI: User 1 logs in
playwright-cli --session=user1 fill e1 "user1"
playwright-cli --session=user1 click e3

# CLI: User 2 logs in (parallel)
playwright-cli --session=user2 fill e1 "user2"
playwright-cli --session=user2 click e3

# Script: Test collaboration
npx playwright test --grep "@collaboration"
```

**Boost**: Simulates multi-user scenarios realistically.

### 8. Code Generation (For automation)

Record traces to accelerate script creation.

```bash
# Record a session
playwright-cli open https://app.com
playwright-cli tracing-start
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli tracing-stop

# Convert trace to test code
npx playwright show-trace trace.zip
```

**Boost**: Accelerates script creation from manual sessions.

### 9. Artifact Sharing (For unified debugging)

Store screenshots/traces in artifacts for team triage.

```bash
# CLI: Capture artifact
playwright-cli open https://app.com
playwright-cli click e4
playwright-cli screenshot > artifacts/step1.png

# Script: Capture artifact
await page.screenshot({ path: 'artifacts/step2.png' });

# Team: Review shared evidence
ls artifacts/
```

**Boost**: Streamlines triage with shared evidence.

### 10. Hybrid Cycles (For iterative dev)

Alternate between exploration, scripts, and debugging.

**Cycle**:
1. Explore with CLI to understand behavior
2. Write test scripts for automation
3. Debug with CLI on script failure
4. Refine both tool and script

```bash
# Step 1: Explore
playwright-cli --config profiles/chromium.json open https://app.com
playwright-cli click e4
playwright-cli snapshot

# Step 2: Script (write test_login.spec.ts)
# Step 3: Debug on failure
playwright-cli --config profiles/chromium.json open https://app.com
playwright-cli eval "document.body.innerHTML" | grep "error"

# Step 4: Refine
```

**Boost**: Balances speed and reliability in agile workflows.

## Best Practices

### Version Control

- Keep profiles under version control for consistency
- Share profiles between CLI and scripts

### Metrics & Monitoring

- Track: Test creation time, failure resolution speed
- Aim: <30 min to create test with CLI + script conversion

### Team Training

- CLI for exploration and debugging
- Scripts for automation and CI/CD
- Clearly document the boundary

### Blazor Apps

- **Understand the two-phase load**: Prerender (static HTML) + SignalR circuit (interactive)
- **Wait for interactivity**: Use element visibility instead of time delays for Blazor interactions
- **Circuit readiness**: Playwright auto-waits; ensure next command follows interaction for proper timing
- **Form handling**: Prerendered forms need FormName parameter; test form submission paths
- **Test across profiles**: Mobile profiles may experience slower circuit establishment
- See [BLAZOR_TESTING.md](BLAZOR_TESTING.md) for comprehensive Blazor-specific guidance

### Maintenance

- Limit CLI embedding to <20% of script logic
- Prefer scripts for assertions and reporting
- Use CLI only for interactive or ad-hoc tasks
