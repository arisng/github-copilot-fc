# Playwright E2E testing — official docs

## Sources
- Playwright for .NET: Installation/Getting started: https://playwright.dev/dotnet/docs/intro
- Playwright for .NET: Test runners and configuration: https://playwright.dev/dotnet/docs/test-runners
- Playwright for .NET: Trace viewer: https://playwright.dev/dotnet/docs/trace-viewer-intro
- Playwright for .NET: Assertions: https://playwright.dev/dotnet/docs/test-assertions
- Microsoft Playwright Testing (managed service overview): https://learn.microsoft.com/azure/playwright-testing/overview-what-is-microsoft-playwright-testing

## Concise, actionable takeaways
- **Playwright is built for E2E** and supports Chromium, WebKit, and Firefox across Windows/macOS/Linux.
- **.NET test runners supported:** MSTest, NUnit, xUnit, or xUnit v3 base classes. Each test gets an isolated `BrowserContext` and a ready `Page` when you use `PageTest`.
- **Install flow (MSTest example):**
  1. `dotnet new mstest -n PlaywrightTests`
  2. `dotnet add package Microsoft.Playwright.MSTest`
  3. `dotnet build`
  4. `pwsh bin/Debug/net8.0/playwright.ps1 install`
- **Run tests:** `dotnet test` (Chromium by default). Use `.runsettings` or CLI args to control browser, headless, channel, expect timeout, etc.
- **Parallelization:** MSTest runs classes in parallel by default (class-level). Adjust workers with `.runsettings` or CLI (`MSTest.Parallelize.Workers`).
- **Tracing for debugging:** Start tracing in `TestInitialize`, stop in `TestCleanup`, then open with `playwright.ps1 show-trace ...` or https://trace.playwright.dev.
- **Assertions:** Use web-first `Expect(...)` assertions (auto-waiting). Default expect timeout is 5s; set global or per-assertion timeout when needed.
- **Managed service option:** Microsoft Playwright Testing provides cloud-hosted browsers and artifacts; note the announced retirement on March 8, 2026 and migration to Azure App Testing.

## Practical checklist
- ✅ Use `PageTest` for simplest setup (each test gets a fresh context + page).
- ✅ Keep tests isolated by using a new `BrowserContext` per test.
- ✅ Configure headless/headed and browser/channel via `.runsettings` for CI vs local.
- ✅ Enable tracing for flaky tests and open traces with the CLI or web viewer.
- ✅ Prefer `Expect` assertions for built-in auto-waiting and stability.

## Minimal trace pattern (MSTest)
- `TestInitialize`: `await Context.Tracing.StartAsync(new() { Screenshots = true, Snapshots = true, Sources = true });`
- `TestCleanup`: `await Context.Tracing.StopAsync(new() { Path = ... });`
- Open: `pwsh bin/Debug/net8.0/playwright.ps1 show-trace <trace.zip>`
