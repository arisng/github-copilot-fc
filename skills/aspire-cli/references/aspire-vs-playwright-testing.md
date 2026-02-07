# Aspire Testing vs Playwright-CLI: Comparative Analysis

## Overview

Aspire testing and playwright-cli serve **complementary** testing purposes in the .NET ecosystem. Understanding when to use each (or both together) is key to effective test strategy.

| Dimension         | Aspire Testing                                | Playwright-CLI                               |
| ----------------- | --------------------------------------------- | -------------------------------------------- |
| **Primary Focus** | Distributed backend services, APIs, databases | Browser UI, frontend interactions            |
| **Test Type**     | Closed-box integration/E2E                    | Browser automation/E2E                       |
| **Test Target**   | AppHost + resources (services, databases)     | Web pages, SPAs, forms                       |
| **Process Model** | Separate processes (AppHost + resources)      | Browser instances (Chromium/Firefox/WebKit)  |
| **Access Level**  | External only (HTTP/endpoints)                | DOM, network, console, storage               |
| **Best For**      | Service integration, data flow, API contracts | User journeys, UI validation, visual testing |

---

## When to Use Each

### Use Aspire Testing When

- Testing interactions between multiple services (API → Database)
- Validating service discovery and configuration
- Testing with real external dependencies (PostgreSQL, Redis, etc.)
- Verifying data persistence across service boundaries
- Testing Aspire-specific features (orchestration, health checks)
- Running integration tests in CI/CD pipelines

**Example scenario:**
```
Frontend → API Service → Database
              ↓
         Cache (Redis)
```
Test: Verify that data written through the API is correctly cached and retrievable.

### Use Playwright-CLI When

- Testing user interfaces and user journeys
- Filling and submitting forms
- Taking screenshots for visual regression
- Scraping data from web pages
- Testing JavaScript-heavy SPAs
- Validating responsive design
- Extracting information from web applications

**Example scenario:**
```
User logs in → navigates dashboard → submits form → sees confirmation
```
Test: Verify the complete user workflow through the browser.

### Use Both Together When

- Full-stack E2E testing from UI to database
- Testing that UI changes correctly reflect backend state
- Validating complete user journeys with real services
- Integration testing with browser-level assertions

**Example scenario:**
```
Playwright: User submits order via web UI
     ↓
Aspire: API processes order, writes to database
     ↓
Playwright: Verify order appears in user's order history
```

---

## Architecture Comparison

### Aspire Testing Architecture

```
[Test Project]
      │
      ▼
[DistributedApplicationTestingBuilder]
      │
      ▼
[AppHost Process] ──┬──► [API Service]
                    ├──► [Database]
                    └──► [Cache]
```

- Test project starts AppHost as a separate process
- Services run as real processes with actual dependencies
- Tests communicate via HTTP/endpoints only
- No access to internal DI containers

### Playwright-CLI Architecture

```
[CLI Commands]
      │
      ▼
[Playwright Browser] ──┬──► [Chromium]
                       ├──► [Firefox]
                       └──► [WebKit]
                              │
                              ▼
                        [Web Application]
```

- CLI controls browser instances
- Full access to DOM, network, console logs
- Can intercept and mock network requests
- Runs against any accessible URL (local or remote)

---

## Feature Matrix

| Feature                   | Aspire Testing         | Playwright-CLI                       |
| ------------------------- | ---------------------- | ------------------------------------ |
| **Service orchestration** | ✅ Native               | ❌ Manual (start services separately) |
| **Database integration**  | ✅ Real databases       | ⚠️ Via API only                       |
| **HTTP/API testing**      | ✅ Via HttpClient       | ✅ Via page requests                  |
| **Browser automation**    | ❌ Not applicable       | ✅ Full support                       |
| **Form interaction**      | ❌ Not applicable       | ✅ Fill, submit, validate             |
| **Screenshots**           | ❌ Not applicable       | ✅ Built-in                           |
| **Video recording**       | ❌ Not applicable       | ✅ Built-in                           |
| **Network mocking**       | ❌ Limited              | ✅ Advanced                           |
| **Parallel execution**    | ✅ Concurrent test runs | ✅ Multiple browser contexts          |
| **CI/CD integration**     | ✅ Test containers      | ✅ Headless mode                      |

---

## Configuration Patterns

### Aspire Testing Configuration

```csharp
// Default: randomized ports, no dashboard
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>();

// Stable ports for predictable URLs
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>(
        ["DcpPublisher:RandomizePorts=false"]);

// Enable dashboard for debugging
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>(
        args: [],
        configureBuilder: (appOptions, hostSettings) =>
        {
            appOptions.DisableDashboard = false;
        });
```

### Playwright-CLI Configuration

```bash
# Headless mode for CI
playwright-cli open --headless https://example.com

# Specific browser
playwright-cli open --browser=firefox https://example.com

# Session-based (maintain state)
playwright-cli --session=mysession open https://example.com

# Config file
playwright-cli config --headed --isolated --browser=chromium
playwright-cli open --config=my-config.json https://example.com
```

---

## Combined Testing Strategy

### Pattern 1: Aspire Backend + Playwright Frontend

```csharp
// Test.cs - Combined approach
public class FullStackTests
{
    [Fact]
    public async Task UserJourney_CreatesOrderSuccessfully()
    {
        // 1. Start Aspire app
        var builder = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.MyAppHost>(
                ["DcpPublisher:RandomizePorts=false"]);
        
        using var app = await builder.BuildAsync();
        await app.StartAsync();
        
        // 2. Get frontend URL
        var frontendUrl = app.CreateHttpClient("web").BaseAddress;
        
        // 3. Use playwright-cli to test UI
        await RunPlaywrightTest($"""
            playwright-cli open {frontendUrl}
            playwright-cli fill e1 "test@example.com"
            playwright-cli fill e2 "password"
            playwright-cli click e3
            playwright-cli fill e5 "Product A"
            playwright-cli click e6
            playwright-cli snapshot
            playwright-cli screenshot order-confirmation.png
            """);
        
        // 4. Verify backend state via API
        var apiClient = app.CreateHttpClient("api");
        var orders = await apiClient.GetFromJsonAsync<List<Order>>("/api/orders");
        Assert.Single(orders);
        Assert.Equal("Product A", orders[0].ProductName);
    }
}
```

### Pattern 2: CLI-Level Integration

```bash
# Terminal 1: Start Aspire app
aspire run
# Note the dashboard URL and frontend endpoint

# Terminal 2: Run playwright tests against running app
playwright-cli open http://localhost:5000
playwright-cli fill e1 "test@example.com"
playwright-cli click e2
playwright-cli snapshot

# Clean up
playwright-cli close
# Stop aspire run with Ctrl+C
```

### Pattern 3: CI/CD Pipeline

```yaml
# github-actions.yml example
steps:
  - name: Start Aspire App
    run: |
      aspire run &
      sleep 30  # Wait for services to be healthy
    
  - name: Run Playwright Tests
    run: |
      playwright-cli open http://localhost:5000 --headless
      playwright-cli fill e1 "ci-test@example.com"
      playwright-cli click e2
      playwright-cli screenshot test-result.png
      playwright-cli close
    
  - name: Upload Screenshots
    uses: actions/upload-artifact@v3
    with:
      name: screenshots
      path: test-result.png
```

---

## Decision Tree

```
What do you need to test?
│
├── Backend services/APIs only?
│   └── Use Aspire Testing
│
├── Browser UI only?
│   └── Use Playwright-CLI
│
├── Service-to-service communication?
│   └── Use Aspire Testing
│
├── User journey through web app?
│   └── Use Playwright-CLI
│
├── Full stack (UI → API → Database)?
│   └── Use BOTH:
│       1. Aspire for service orchestration
│       2. Playwright for UI automation
│
└── Data persistence/integrity?
    └── Use Aspire Testing (real dependencies)
```

---

## Best Practices Summary

### Aspire Testing
- Use `WebApplicationFactory<T>` for isolated unit tests
- Use Aspire testing for integration scenarios with real dependencies
- Disable port randomization when tests need stable URLs
- Enable dashboard for debugging test failures
- Keep tests in a separate test project referencing the AppHost

### Playwright-CLI
- Use snapshots to understand page structure
- Prefer element refs (e3, e5) over selectors for stability
- Use sessions for multi-step workflows
- Take screenshots at key validation points
- Use `--headless` for CI/CD, headed for debugging
- Configure tracing for difficult-to-debug scenarios

### Combined Usage
- Start Aspire app first, then target playwright at it
- Use Aspire's `CreateHttpClient()` for backend verification
- Use playwright for frontend assertions
- Capture both backend logs and browser screenshots on failure

---

## Key Takeaways

1. **Aspire testing** = Backend integration testing (services, databases, APIs)
2. **Playwright-CLI** = Frontend/browser testing (UI, user journeys)
3. **They complement each other** - use both for full-stack coverage
4. **Aspire orchestrates**, **Playwright automates** - different layers of the stack
5. In a complete testing strategy, use Aspire for service contracts and Playwright for user-facing features
