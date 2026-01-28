# Authoritative Blogs: Blazor Interactive Server & Playwright E2E

## Blazor Interactive Server & Render Modes

### Announcing ASP.NET Core in .NET 8 — .NET Blog (Microsoft)
- Link: https://devblogs.microsoft.com/dotnet/announcing-asp-net-core-in-dotnet-8/
- Summary: Official release post that explains Blazor’s full-stack model in .NET 8 and the new per-component `@rendermode` directive, including Interactive Server, Interactive WebAssembly, and Auto. Highlights interactive rendering per component/page and the new Blazor Web App template options.
- Actionable takeaways:
  - Use `@rendermode` on pages/components to enable interactivity only where needed.
  - Prefer Auto mode for fast first paint (Interactive Server) with later WASM handoff.
  - Configure render modes via the Blazor Web App template or in `Program.cs`.

### ASP.NET Core updates in .NET 8 Preview 6 — .NET Blog (Microsoft)
- Link: https://devblogs.microsoft.com/dotnet/asp-net-core-updates-in-dotnet-8-preview-6/
- Summary: Preview guidance with concrete API calls for enabling interactive rendering and call-site render modes. Covers `@rendermode` at component call sites and notes about WebAssembly interactivity setup and prerendering control.
- Actionable takeaways:
  - Enable interactivity with `AddInteractiveServerComponents()` and `AddInteractiveWebAssemblyComponents()` plus corresponding render modes.
  - Use `@rendermode` on component instances to scope interactivity to a small subtree.
  - Disable prerendering explicitly when a component cannot render on the server.

### Getting Started with Blazor’s New Render Modes in .NET 8 — Telerik Blog (Jon Hilton)
- Link: https://www.telerik.com/blogs/getting-started-blazor-new-render-modes-net-8
- Summary: Practical walkthrough of Static, Interactive Server, Interactive WebAssembly, and Auto modes, with trade-offs, diagrams, and setup snippets.
- Actionable takeaways:
  - Use Static SSR for read-only content; switch to Interactive Server for local interactivity without an API.
  - Plan a separate client project for Interactive WASM components.
  - Use Auto mode when you want server-first UX with eventual client-side interactivity.

### .NET 8: Blazor Render Modes Explained — SitePoint (Peter De Tender)
- Link: https://www.sitepoint.com/net-8-blazor-render-modes-explained/
- Summary: Render-mode overview with an end-to-end sample that shows configuring interactive render modes and applying `@rendermode` per page or per component.
- Actionable takeaways:
  - Configure render-mode services and endpoints before applying `@rendermode` in components.
  - Use per-component render modes to keep most pages static while enabling targeted interactivity.
  - Validate in the browser that interactivity is active (WebSocket for Interactive Server).

## Playwright + Blazor E2E Testing

### Tutorial Unit and E2E Testing in Blazor – Part 2: Playwright Introduction — Steven Giesel
- Link: https://steven-giesel.com/blogPost/fa2b1601-c724-4d37-915c-a6033e194e7e
- Summary: A Blazor-focused Playwright introduction with a first test, installation steps, and notes on requiring a real running server for E2E tests.
- Actionable takeaways:
  - Install Playwright CLI and browsers, then run against a live app URL (not in-memory).
  - Use headful mode and screenshots when debugging flakiness.
  - Organize tests by page objects for maintainability.

### End-to-End Tests With ASP.NET Core, XUnit, and Playwright — Khalid Abuhakmeh
- Link: https://khalidabuhakmeh.com/end-to-end-test-with-aspnet-core-xunit-and-playwright
- Summary: Shows how to run Playwright tests with ASP.NET Core by self-hosting the app and sharing a browser fixture to reduce startup cost.
- Actionable takeaways:
  - Create a fixture that boots the app on a random open port and shares `IBrowser`.
  - Use stable, test-only attributes (e.g., `pw-name`) for selectors.
  - Keep the test host and browser lifetime aligned to reduce test overhead.

### End-to-End testing with Playwright, part I — BartekR
- Link: https://blog.bartekr.net/2021/11/13/end-to-end-testing-with-playwright-part-i/
- Summary: Step-by-step Playwright + Blazor setup with NUnit, covering project creation, Playwright installation, and first test structure.
- Actionable takeaways:
  - Use `Microsoft.Playwright.NUnit` and inherit from `PageTest` to get a ready `Page`.
  - Start the Blazor app separately (e.g., `dotnet watch` or `dotnet run`).
  - Prefer `await` on all Playwright calls and keep selectors simple (`Page.TextContentAsync("p")`).

### End to End Testing using Playwright in Blazor WASM — I ❤️ .NET (Abdul Rahman)
- Link: https://ilovedotnet.org/blogs/e2e-testing-blazor-wasm-using-playwright/
- Summary: Blazor WASM-focused E2E flow including Playwright installation, codegen, runsettings for base URLs, screenshots, and trace viewer usage.
- Actionable takeaways:
  - Use Playwright codegen to bootstrap tests quickly, then refine selectors.
  - Externalize base URLs via .runsettings or environment variables for multi-env testing.
  - Use screenshots and trace viewer artifacts to troubleshoot failures in CI.
