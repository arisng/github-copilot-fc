# Blazor Interactive Server readiness guide

## Purpose
Use this guide to define reliable readiness signals for Blazor Interactive Server apps before running Playwright E2E assertions.

## Readiness signals checklist
- App shell is rendered and visible.
- Interactive components are hydrated (event handlers wired).
- The SignalR circuit is connected and stable.
- A dedicated app readiness marker is present (preferred).

## Recommended app-side markers
Provide explicit, test-only markers that indicate interactivity is fully enabled.

### Example readiness marker (Razor)
```razor
<div data-testid="app-shell">
    <span data-testid="app-ready" hidden="@(!_ready)"></span>
    @* App content *@
</div>

@code {
    private bool _ready;

    protected override async Task OnAfterRenderAsync(bool firstRender)
    {
        if (firstRender)
        {
            _ready = true;
            StateHasChanged();
        }
    }
}
```

### Notes
- Keep markers stable and unique (prefer `data-testid`).
- Avoid timing-only gates like fixed delays.
- If the app has authentication, place readiness markers after login completes.

## Playwright waits (conceptual)
- Wait for the app shell to be visible.
- Wait for the readiness marker to be present/visible.
- Proceed with interactions only after readiness is confirmed.

## Troubleshooting hydration delays
- Inspect the browser console for Blazor error UI or JS interop failures.
- Verify the circuit connection is not being dropped by proxies or timeouts.
- Ensure the readiness marker is only set after interactive rendering completes.
