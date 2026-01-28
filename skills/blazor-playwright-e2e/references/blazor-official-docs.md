# Blazor Interactive Server render mode — official docs

## Sources
- ASP.NET Core Blazor render modes (Microsoft Learn): https://learn.microsoft.com/aspnet/core/blazor/components/render-modes?view=aspnetcore-10.0
- Build a Blazor movie database app (Part 8 - Add interactivity) (Microsoft Learn): https://learn.microsoft.com/aspnet/core/blazor/tutorials/movie-database-app/part-8?view=aspnetcore-10.0
- Tooling for ASP.NET Core Blazor (templates/options) (Microsoft Learn): https://learn.microsoft.com/aspnet/core/blazor/tooling?view=aspnetcore-10.0

## Concise, actionable takeaways
- **Interactive Server = interactive SSR over SignalR.** Add interactivity by configuring services/endpoints and then applying `@rendermode InteractiveServer` on pages/components.
- **Required hosting configuration in `Program.cs`:**
  - `builder.Services.AddRazorComponents().AddInteractiveServerComponents();`
  - `app.MapRazorComponents<App>().AddInteractiveServerRenderMode();`
- **Per-component or global render mode:**
  - Per component: `@rendermode InteractiveServer` on the component definition or instance.
  - Global: set render mode on the `Routes` (and `HeadOutlet`) in `App.razor`.
- **Render mode propagation rules:**
  - Default is Static SSR; render modes propagate down the component tree.
  - You cannot switch to a different interactive render mode in a child component.
  - Parameters from Static parents to interactive children must be JSON-serializable (no `RenderFragment`/child content).
- **Prerendering is on by default** for interactive modes. You can disable per component using `new InteractiveServerRenderMode(prerender: false)`.
- **Detect interactive state at runtime** using `RendererInfo.IsInteractive` or `AssignedRenderMode` to gate UI actions during prerendering.

## Practical checklist
- ✅ In `Program.cs`, enable interactive server components and render mode endpoints.
- ✅ Apply `@rendermode InteractiveServer` on the specific pages you want to be interactive, or configure global interactivity in `App.razor`.
- ✅ If using global interactivity, set the same render mode on both `Routes` and `HeadOutlet`.
- ✅ Avoid passing non-serializable parameters from static parents to interactive children.
- ✅ Consider disabling prerendering only when necessary (e.g., heavy JS interop on first render).
- ✅ Use `RendererInfo.IsInteractive` to avoid actions that require an established circuit during prerendering.

## Gotchas to watch
- If you try to place an Interactive WebAssembly child inside Interactive Server (or vice versa), Blazor throws a runtime error.
- Components using WebAssembly/Auto render modes must be built from the `.Client` project in a Blazor Web App solution.
